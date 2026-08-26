import AppKit
import CoreText
import Foundation
import PDFKit
import Vision

struct PDFOCRResult: Equatable {
    var dataByMemberID: [UUID: Data]
    var recognizedPageCount: Int
    var qualityReport: PDFOCRQualityReport
}

struct PDFOCRQualityReport: Equatable, Sendable {
    var requestedPageCount: Int
    var recognizedPageCount: Int
    var skippedPageNumbers: [Int]
    var recognizedLineCount: Int
    var lowConfidenceLineCount: Int
    var averageConfidence: Float
    var changedMemberCount: Int
    var validatedMemberCount: Int

    var needsReview: Bool {
        !skippedPageNumbers.isEmpty || lowConfidenceLineCount > 0
    }

    var reviewItemCount: Int {
        skippedPageNumbers.count + lowConfidenceLineCount
    }

    var integrityChecksPassed: Bool {
        changedMemberCount > 0 && changedMemberCount == validatedMemberCount
    }
}

struct PDFOCROptions: Equatable, Sendable {
    enum PageSelection: String, CaseIterable, Equatable, Sendable {
        case scannedPagesOnly
        case allVisiblePages
    }

    var pageSelection: PageSelection
    var recognitionLanguage: String?
    var continuesAfterPageFailure: Bool

    init(
        pageSelection: PageSelection = .scannedPagesOnly,
        recognitionLanguage: String? = nil,
        continuesAfterPageFailure: Bool = true
    ) {
        self.pageSelection = pageSelection
        self.recognitionLanguage = recognitionLanguage
        self.continuesAfterPageFailure = continuesAfterPageFailure
    }
}

struct PDFOCRRecognizedLine: Equatable, Sendable {
    var text: String
    var normalizedBounds: CGRect
    var confidence: Float
}

enum PDFOCRError: LocalizedError, Equatable {
    case invalidPDF(memberName: String)
    case pageRenderFailed(pageNumber: Int)
    case recognitionFailed(pageNumber: Int)
    case outputFailed(memberName: String)
    case cancelled
    case noScannedPages

    var errorDescription: String? {
        switch self {
        case .invalidPDF(let memberName):
            return String(
                localized: """
                Orifold could not read "\(memberName)" to make it searchable. \
                Reopen the document and try again.
                """,
                locale: L10n.currentLocale
            )
        case .pageRenderFailed(let pageNumber):
            return L10n.format("error.ocr.pageUnreadable", pageNumber)
        case .recognitionFailed(let pageNumber):
            return L10n.format("error.ocr.pageNotSearchable", pageNumber)
        case .outputFailed(let memberName):
            return String(
                localized: """
                Orifold could not update "\(memberName)" with searchable text. \
                The original document is unchanged.
                """,
                locale: L10n.currentLocale
            )
        case .cancelled:
            return L10n.string("error.ocr.cancelled")
        case .noScannedPages:
            return L10n.string("error.ocr.noScannedPages")
        }
    }
}

enum PDFOCRService {
    typealias RecognitionProvider = (PDFPage, Int, @escaping () -> Bool) throws -> [PDFOCRRecognizedLine]

    private enum PageRecognitionOutcome: Sendable {
        case recognized(
            pageIndex: Int,
            pageNumber: Int,
            lines: [PDFOCRRecognizedLine],
            lowConfidenceLineCount: Int
        )
        case skipped(pageIndex: Int, pageNumber: Int, lowConfidenceLineCount: Int)
    }

    private static let minimumConfidence: Float = 0.3
    private static let reviewConfidence: Float = 0.6
    private static let targetDPI: CGFloat = 300
    private static let maxLongEdgePixels: CGFloat = 4_500
    private static let scanDetectionSampleSize = CGSize(width: 96, height: 96)

    static func makeSearchable(
        documents: [(MemberDocument, Data)],
        displayPageNumbersByMemberID: [UUID: [Int]] = [:],
        options: PDFOCROptions = PDFOCROptions(),
        progress: @escaping @Sendable (Double) -> Void,
        isCancelled: @escaping @Sendable () -> Bool
    ) async throws -> PDFOCRResult {
        try await searchableData(
            documents: documents,
            displayPageNumbersByMemberID: displayPageNumbersByMemberID,
            options: options,
            recognitionProvider: { page, pageNumber, cancellation in
                try recognizeText(
                    page: page,
                    pageNumber: pageNumber,
                    options: options,
                    isCancelled: cancellation
                )
            },
            progress: progress,
            isCancelled: isCancelled
        )
    }

    static func searchableData(
        documents: [(MemberDocument, Data)],
        displayPageNumbersByMemberID: [UUID: [Int]] = [:],
        includePagesWithText: Bool = false,
        options: PDFOCROptions? = nil,
        recognitionProvider: @escaping RecognitionProvider,
        progress: @escaping @Sendable (Double) -> Void = { _ in },
        isCancelled: @escaping @Sendable () -> Bool = { false }
    ) async throws -> PDFOCRResult {
        var resolvedOptions = options ?? PDFOCROptions()
        if options == nil, includePagesWithText {
            resolvedOptions.pageSelection = .allVisiblePages
        }
        return try await Task.detached(priority: .userInitiated) {
            var totalPages = 0
            for (member, data) in documents {
                guard let pdf = PDFDocument(data: data), pdf.pageCount > 0 else {
                    throw PDFOCRError.invalidPDF(memberName: member.displayName)
                }
                totalPages += pdf.pageCount
            }
            guard totalPages > 0 else { throw PDFOCRError.noScannedPages }

            var completedPages = 0
            var recognizedPages = 0
            var output: [UUID: Data] = [:]
            var globalPageOffset = 0
            var requestedPages = 0
            var skippedPageNumbers: [Int] = []
            var recognizedConfidences: [Float] = []
            var lowConfidenceLineCount = 0
            var validatedMembers = 0

            for (member, data) in documents {
                try checkCancellation(isCancelled)
                guard let pdf = PDFDocument(data: data), pdf.pageCount > 0 else {
                    throw PDFOCRError.invalidPDF(memberName: member.displayName)
                }
                let mappedPageNumbers = displayPageNumbersByMemberID[member.id]
                func displayPageNumber(for pageIndex: Int) -> Int {
                    if let mappedPageNumbers, mappedPageNumbers.indices.contains(pageIndex) {
                        return mappedPageNumbers[pageIndex]
                    }
                    return globalPageOffset + pageIndex + 1
                }

                var recognizedLinesByPage: [Int: [PDFOCRRecognizedLine]] = [:]
                try await withThrowingTaskGroup(of: PageRecognitionOutcome.self) { group in
                    var nextPageIndex = 0
                    var submitted = 0

                    func submitNextPageIfNeeded() {
                        while submitted < 3, nextPageIndex < pdf.pageCount {
                            let pageIndex = nextPageIndex
                            nextPageIndex += 1
                            let pageNumber = displayPageNumber(for: pageIndex)
                            guard let page = pdf.page(at: pageIndex) else {
                                group.addTask {
                                    if resolvedOptions.continuesAfterPageFailure {
                                        return .skipped(
                                            pageIndex: pageIndex,
                                            pageNumber: pageNumber,
                                            lowConfidenceLineCount: 0
                                        )
                                    }
                                    throw PDFOCRError.pageRenderFailed(pageNumber: pageNumber)
                                }
                                submitted += 1
                                continue
                            }
                            if !shouldProcessPage(page, pageSelection: resolvedOptions.pageSelection) {
                                completedPages += 1
                                progress(Double(completedPages) / Double(max(totalPages, 1)))
                                continue
                            }
                            requestedPages += 1
                            guard let pageData = singlePageData(from: page) else {
                                group.addTask {
                                    if resolvedOptions.continuesAfterPageFailure {
                                        return .skipped(
                                            pageIndex: pageIndex,
                                            pageNumber: pageNumber,
                                            lowConfidenceLineCount: 0
                                        )
                                    }
                                    throw PDFOCRError.pageRenderFailed(pageNumber: pageNumber)
                                }
                                submitted += 1
                                continue
                            }
                            submitted += 1
                            group.addTask {
                                try checkCancellation(isCancelled)
                                guard let pageDocument = PDFDocument(data: pageData),
                                      let isolatedPage = pageDocument.page(at: 0) else {
                                    if resolvedOptions.continuesAfterPageFailure {
                                        return .skipped(
                                            pageIndex: pageIndex,
                                            pageNumber: pageNumber,
                                            lowConfidenceLineCount: 0
                                        )
                                    }
                                    throw PDFOCRError.pageRenderFailed(pageNumber: pageNumber)
                                }
                                do {
                                    let lines = try autoreleasepool {
                                        try recognitionProvider(isolatedPage, pageNumber, isCancelled)
                                    }
                                    try checkCancellation(isCancelled)
                                    let lowConfidenceLines = lines.filter {
                                        !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                            && $0.confidence < reviewConfidence
                                    }.count
                                    let filteredLines = filteredRecognizedLines(lines)
                                    guard !filteredLines.isEmpty else {
                                        if resolvedOptions.continuesAfterPageFailure {
                                            return .skipped(
                                                pageIndex: pageIndex,
                                                pageNumber: pageNumber,
                                                lowConfidenceLineCount: lowConfidenceLines
                                            )
                                        }
                                        throw PDFOCRError.recognitionFailed(pageNumber: pageNumber)
                                    }
                                    return .recognized(
                                        pageIndex: pageIndex,
                                        pageNumber: pageNumber,
                                        lines: filteredLines,
                                        lowConfidenceLineCount: lowConfidenceLines
                                    )
                                } catch PDFOCRError.cancelled {
                                    throw PDFOCRError.cancelled
                                } catch is CancellationError {
                                    throw PDFOCRError.cancelled
                                } catch {
                                    if resolvedOptions.continuesAfterPageFailure {
                                        return .skipped(
                                            pageIndex: pageIndex,
                                            pageNumber: pageNumber,
                                            lowConfidenceLineCount: 0
                                        )
                                    }
                                    throw error
                                }
                            }
                        }
                    }

                    submitNextPageIfNeeded()
                    while let outcome = try await group.next() {
                        submitted -= 1
                        switch outcome {
                        case .recognized(let pageIndex, _, let lines, let pageLowConfidenceLineCount):
                            recognizedLinesByPage[pageIndex] = lines
                            lowConfidenceLineCount += pageLowConfidenceLineCount
                        case .skipped(_, let pageNumber, let pageLowConfidenceLineCount):
                            skippedPageNumbers.append(pageNumber)
                            lowConfidenceLineCount += pageLowConfidenceLineCount
                        }
                        completedPages += 1
                        progress(Double(completedPages) / Double(max(totalPages, 1)))
                        submitNextPageIfNeeded()
                    }
                }

                var overlays: [PDFPageOverlayMergeEngine.Overlay] = []
                var memberConfidences: [Float] = []
                for pageIndex in 0..<pdf.pageCount {
                    try checkCancellation(isCancelled)
                    guard let page = pdf.page(at: pageIndex) else {
                        throw PDFOCRError.pageRenderFailed(pageNumber: displayPageNumber(for: pageIndex))
                    }

                    if !shouldProcessPage(page, pageSelection: resolvedOptions.pageSelection) {
                        continue
                    } else if skippedPageNumbers.contains(displayPageNumber(for: pageIndex)) {
                        continue
                    } else {
                        guard let lines = recognizedLinesByPage[pageIndex], !lines.isEmpty else {
                            throw PDFOCRError.recognitionFailed(pageNumber: displayPageNumber(for: pageIndex))
                        }
                        guard let overlayData = searchableTextOverlay(from: page, lines: lines) else {
                            if resolvedOptions.continuesAfterPageFailure {
                                skippedPageNumbers.append(displayPageNumber(for: pageIndex))
                                continue
                            }
                            throw PDFOCRError.outputFailed(memberName: member.displayName)
                        }
                        let mediaBox = page.bounds(for: .mediaBox)
                        overlays.append(PDFPageOverlayMergeEngine.Overlay(
                            pageIndex: pageIndex,
                            data: overlayData,
                            originX: mediaBox.minX,
                            originY: mediaBox.minY
                        ))
                        memberConfidences.append(contentsOf: lines.map(\.confidence))
                    }
                }

                if !overlays.isEmpty {
                    guard let memberData = PDFPageOverlayMergeEngine.merge(overlays: overlays, into: data),
                          pageGeometryMatches(source: data, output: memberData),
                          QPDFService.isStructurallySound(memberData) else {
                        throw PDFOCRError.outputFailed(memberName: member.displayName)
                    }
                    do {
                        _ = try PDFiumProcessingEngine().validatePDF(data: memberData)
                    } catch {
                        throw PDFOCRError.outputFailed(memberName: member.displayName)
                    }
                    output[member.id] = memberData
                    recognizedPages += overlays.count
                    recognizedConfidences.append(contentsOf: memberConfidences)
                    validatedMembers += 1
                }
                globalPageOffset += pdf.pageCount
            }

            guard recognizedPages > 0 else {
                if let firstSkippedPage = skippedPageNumbers.sorted().first {
                    throw PDFOCRError.recognitionFailed(pageNumber: firstSkippedPage)
                }
                throw PDFOCRError.noScannedPages
            }
            progress(1)
            let averageConfidence = recognizedConfidences.isEmpty
                ? 0
                : recognizedConfidences.reduce(0, +) / Float(recognizedConfidences.count)
            let report = PDFOCRQualityReport(
                requestedPageCount: requestedPages,
                recognizedPageCount: recognizedPages,
                skippedPageNumbers: Array(Set(skippedPageNumbers)).sorted(),
                recognizedLineCount: recognizedConfidences.count,
                lowConfidenceLineCount: lowConfidenceLineCount,
                averageConfidence: averageConfidence,
                changedMemberCount: output.count,
                validatedMemberCount: validatedMembers
            )
            return PDFOCRResult(
                dataByMemberID: output,
                recognizedPageCount: recognizedPages,
                qualityReport: report
            )
        }.value
    }

    private static func recognizeText(
        page: PDFPage,
        pageNumber: Int,
        options: PDFOCROptions,
        isCancelled: @escaping () -> Bool
    ) throws -> [PDFOCRRecognizedLine] {
        try checkCancellation(isCancelled)
        guard let image = renderedImage(for: page) else {
            throw PDFOCRError.pageRenderFailed(pageNumber: pageNumber)
        }

        let request = VNRecognizeTextRequest()
        configureRecognitionRequest(request, options: options)

        do {
            try VNImageRequestHandler(cgImage: image, orientation: .up, options: [:]).perform([request])
        } catch {
            throw PDFOCRError.recognitionFailed(pageNumber: pageNumber)
        }
        try checkCancellation(isCancelled)

        // Return every non-empty Vision observation. The orchestration layer applies the
        // write threshold and counts rejected observations in the review receipt; filtering
        // here would make low-confidence production detections disappear from that evidence.
        return (request.results ?? []).compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return PDFOCRRecognizedLine(
                text: text,
                normalizedBounds: observation.boundingBox,
                confidence: candidate.confidence
            )
        }
    }

    static func isLikelyScannedPage(_ page: PDFPage) -> Bool {
        let hasText = !(page.string?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        guard !hasText else { return false }
        return hasVisibleContent(page)
    }

    static func hasVisibleContent(_ page: PDFPage) -> Bool {
        pageHasVisibleContent(page)
    }

    static func supportedRecognitionLanguages() -> [String] {
        let request = VNRecognizeTextRequest()
        configureRecognitionRequest(request, options: PDFOCROptions())
        return (try? request.supportedRecognitionLanguages())?.sorted() ?? []
    }

    static func configureRecognitionRequest(_ request: VNRecognizeTextRequest, options: PDFOCROptions) {
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        if let language = options.recognitionLanguage?.trimmingCharacters(in: .whitespacesAndNewlines),
           !language.isEmpty {
            request.recognitionLanguages = [language]
            request.automaticallyDetectsLanguage = false
        } else {
            request.recognitionLanguages = []
            request.automaticallyDetectsLanguage = true
        }
    }

    private static func shouldProcessPage(_ page: PDFPage, pageSelection: PDFOCROptions.PageSelection) -> Bool {
        if pageSelection == .allVisiblePages {
            return hasVisibleContent(page)
        }
        return isLikelyScannedPage(page)
    }

    private static func singlePageData(from page: PDFPage) -> Data? {
        let mediaBox = page.bounds(for: .mediaBox)
        guard mediaBox.width.isFinite, mediaBox.height.isFinite, mediaBox.width > 0, mediaBox.height > 0 else {
            return nil
        }

        let data = NSMutableData()
        var outputBox = CGRect(origin: .zero, size: mediaBox.size)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &outputBox, nil) else {
            return nil
        }

        context.beginPDFPage([kCGPDFContextMediaBox as String: outputBox] as CFDictionary)
        context.saveGState()
        context.translateBy(x: -mediaBox.minX, y: -mediaBox.minY)
        page.draw(with: .mediaBox, to: context)
        context.restoreGState()
        context.endPDFPage()
        context.closePDF()
        return data as Data
    }

    /// Rasterizes a page to a high-DPI bitmap for downstream Vision detection — currently the
    /// barcode scanner (Feature G3). A thin exposure of the OCR renderer so barcode scan and
    /// OCR share one rasterization path (same 300-DPI target, same long-edge cap) rather than
    /// duplicating the CGContext setup.
    static func rasterizedImage(for page: PDFPage) -> CGImage? {
        renderedImage(for: page)
    }

    /// Same single rendering path at a caller-chosen density — the compare feature renders
    /// page pairs at a lighter DPI than OCR/barcode detection need.
    static func rasterizedImage(for page: PDFPage, dpi: CGFloat) -> CGImage? {
        renderedImage(for: page, dpi: dpi)
    }

    private static func renderedImage(for page: PDFPage, dpi: CGFloat = targetDPI) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width.isFinite, bounds.height.isFinite, bounds.width > 0, bounds.height > 0 else {
            return nil
        }

        let dpiScale = dpi / 72
        let cappedScale = min(dpiScale, maxLongEdgePixels / max(bounds.width, bounds.height))
        let scale = max(1, cappedScale)
        let width = max(1, Int((bounds.width * scale).rounded(.up)))
        let height = max(1, Int((bounds.height * scale).rounded(.up)))

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return nil
        }

        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -bounds.minX, y: -bounds.minY)
        page.draw(with: .mediaBox, to: context)
        return context.makeImage()
    }

    /// Creates a text-only, zero-origin overlay. `PDFPageOverlayMergeEngine` imports this as a
    /// Form XObject into the original PDFium page, so OCR never redraws or replaces the source
    /// page. Existing vector content, images, annotations, forms, page boxes, outlines, and tags
    /// remain in their original object graph; only the invisible text object is appended.
    private static func searchableTextOverlay(from page: PDFPage, lines: [PDFOCRRecognizedLine]) -> Data? {
        let mediaBox = page.bounds(for: .mediaBox)
        guard mediaBox.width.isFinite, mediaBox.height.isFinite, mediaBox.width > 0, mediaBox.height > 0 else {
            return nil
        }

        let data = NSMutableData()
        let zeroOriginMediaBox = CGRect(origin: .zero, size: mediaBox.size)
        var outputBox = zeroOriginMediaBox
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &outputBox, nil) else {
            return nil
        }

        context.beginPDFPage([kCGPDFContextMediaBox as String: outputBox] as CFDictionary)
        drawInvisibleText(
            lines: lines,
            mediaBox: zeroOriginMediaBox,
            pageRotation: page.rotation,
            in: context
        )
        context.endPDFPage()
        context.closePDF()
        return data as Data
    }

    private static func pageGeometryMatches(source: Data, output: Data) -> Bool {
        guard let sourcePDF = PDFDocument(data: source),
              let outputPDF = PDFDocument(data: output),
              sourcePDF.pageCount == outputPDF.pageCount else {
            return false
        }
        let boxes: [PDFDisplayBox] = [.mediaBox, .cropBox, .bleedBox, .trimBox, .artBox]
        for pageIndex in 0..<sourcePDF.pageCount {
            guard let sourcePage = sourcePDF.page(at: pageIndex),
                  let outputPage = outputPDF.page(at: pageIndex),
                  sourcePage.rotation == outputPage.rotation else {
                return false
            }
            for box in boxes where !approximatelyEqual(sourcePage.bounds(for: box), outputPage.bounds(for: box)) {
                return false
            }
        }
        return true
    }

    private static func approximatelyEqual(_ lhs: CGRect, _ rhs: CGRect, tolerance: CGFloat = 0.01) -> Bool {
        abs(lhs.minX - rhs.minX) <= tolerance
            && abs(lhs.minY - rhs.minY) <= tolerance
            && abs(lhs.width - rhs.width) <= tolerance
            && abs(lhs.height - rhs.height) <= tolerance
    }

    private static func drawInvisibleText(lines: [PDFOCRRecognizedLine],
                                          mediaBox: CGRect,
                                          pageRotation: Int,
                                          in context: CGContext) {
        context.saveGState()
        context.textMatrix = .identity
        context.setTextDrawingMode(.invisible)

        for line in lines where line.confidence >= minimumConfidence {
            let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let bounds = pageBounds(for: line.normalizedBounds, mediaBox: mediaBox, pageRotation: pageRotation)
            guard bounds.width > 0, bounds.height > 0 else { continue }

            let fontSize = max(4, min(72, bounds.height * 0.82))
            let attributes: [NSAttributedString.Key: Any] = [
                .font: CTFontCreateWithName("Helvetica" as CFString, fontSize, nil),
                .foregroundColor: NSColor.black.cgColor
            ]
            let attributed = NSAttributedString(string: text, attributes: attributes)
            let ctLine = CTLineCreateWithAttributedString(attributed)
            let naturalWidth = CGFloat(CTLineGetTypographicBounds(ctLine, nil, nil, nil))
            let horizontalScale = naturalWidth > 0 ? min(max(bounds.width / naturalWidth, 0.45), 2.0) : 1

            context.saveGState()
            // CTLineDraw advances the context's text position. Reset it for every OCR line so
            // later lines do not inherit the previous line's width and drift outside the page.
            context.textPosition = .zero
            context.translateBy(x: bounds.minX, y: bounds.minY + max(1, bounds.height * 0.12))
            context.scaleBy(x: horizontalScale, y: 1)
            CTLineDraw(ctLine, context)
            context.restoreGState()
        }

        context.restoreGState()
    }

    private static func filteredRecognizedLines(_ lines: [PDFOCRRecognizedLine]) -> [PDFOCRRecognizedLine] {
        lines.compactMap { line in
            let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.confidence >= minimumConfidence, !text.isEmpty else { return nil }
            return PDFOCRRecognizedLine(
                text: text,
                normalizedBounds: line.normalizedBounds,
                confidence: line.confidence
            )
        }
    }

    private static func pageHasVisibleContent(_ page: PDFPage) -> Bool {
        let thumbnail = page.thumbnail(of: scanDetectionSampleSize, for: .mediaBox)
        guard let tiffData = thumbnail.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              bitmap.pixelsWide > 0,
              bitmap.pixelsHigh > 0 else {
            return false
        }

        let stepX = max(1, bitmap.pixelsWide / 24)
        let stepY = max(1, bitmap.pixelsHigh / 24)
        var sampled = 0
        var nonWhite = 0
        for pixelY in stride(from: 0, to: bitmap.pixelsHigh, by: stepY) {
            for pixelX in stride(from: 0, to: bitmap.pixelsWide, by: stepX) {
                sampled += 1
                guard let color = bitmap.colorAt(x: pixelX, y: pixelY) else { continue }
                if color.alphaComponent > 0.05,
                   color.redComponent < 0.96 || color.greenComponent < 0.96 || color.blueComponent < 0.96 {
                    nonWhite += 1
                }
            }
        }
        return sampled > 0 && Double(nonWhite) / Double(sampled) > 0.002
    }

    private static func pageBounds(for normalized: CGRect, mediaBox: CGRect, pageRotation: Int) -> CGRect {
        let clamped = normalized.standardized.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        let width = mediaBox.width
        let height = mediaBox.height
        let rotation = ((pageRotation % 360) + 360) % 360

        switch rotation {
        case 90:
            return CGRect(
                x: mediaBox.minX + clamped.minY * width,
                y: mediaBox.minY + (1 - clamped.maxX) * height,
                width: clamped.height * width,
                height: clamped.width * height
            )
        case 180:
            return CGRect(
                x: mediaBox.minX + (1 - clamped.maxX) * width,
                y: mediaBox.minY + (1 - clamped.maxY) * height,
                width: clamped.width * width,
                height: clamped.height * height
            )
        case 270:
            return CGRect(
                x: mediaBox.minX + (1 - clamped.maxY) * width,
                y: mediaBox.minY + clamped.minX * height,
                width: clamped.height * width,
                height: clamped.width * height
            )
        default:
            return CGRect(
                x: mediaBox.minX + clamped.minX * width,
                y: mediaBox.minY + clamped.minY * height,
                width: clamped.width * width,
                height: clamped.height * height
            )
        }
    }

    private static func checkCancellation(_ isCancelled: () -> Bool) throws {
        if isCancelled() || Task.isCancelled {
            throw PDFOCRError.cancelled
        }
    }
}
