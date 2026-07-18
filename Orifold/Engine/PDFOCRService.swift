import AppKit
import CoreText
import Foundation
import PDFKit
import Vision

struct PDFOCRResult: Equatable {
    var dataByMemberID: [UUID: Data]
    var recognizedPageCount: Int
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
            return String(localized: "Orifold could not read \"\(memberName)\" to make it searchable. Reopen the document and try again.", locale: L10n.currentLocale)
        case .pageRenderFailed(let pageNumber):
            return String(localized: "Orifold could not read page \(pageNumber) to make it searchable. Try exporting that page to PDF, then import it again.", locale: L10n.currentLocale)
        case .recognitionFailed(let pageNumber):
            return String(localized: "Orifold could not make page \(pageNumber) searchable. Try a clearer scan or skip this page.", locale: L10n.currentLocale)
        case .outputFailed(let memberName):
            return String(localized: "Orifold could not update \"\(memberName)\" with searchable text. The original document is unchanged.", locale: L10n.currentLocale)
        case .cancelled:
            return L10n.string("error.ocr.cancelled")
        case .noScannedPages:
            return L10n.string("error.ocr.noScannedPages")
        }
    }
}

enum PDFOCRService {
    typealias RecognitionProvider = (PDFPage, Int, @escaping () -> Bool) throws -> [PDFOCRRecognizedLine]

    private static let minimumConfidence: Float = 0.3
    private static let targetDPI: CGFloat = 300
    private static let maxLongEdgePixels: CGFloat = 4_500
    private static let scanDetectionSampleSize = CGSize(width: 96, height: 96)

    static func makeSearchable(
        documents: [(MemberDocument, Data)],
        includePagesWithText: Bool = false,
        progress: @escaping @Sendable (Double) -> Void,
        isCancelled: @escaping @Sendable () -> Bool
    ) async throws -> PDFOCRResult {
        try await searchableData(
            documents: documents,
            includePagesWithText: includePagesWithText,
            recognitionProvider: recognizeText,
            progress: progress,
            isCancelled: isCancelled
        )
    }

    static func searchableData(
        documents: [(MemberDocument, Data)],
        includePagesWithText: Bool = false,
        recognitionProvider: @escaping RecognitionProvider,
        progress: @escaping @Sendable (Double) -> Void = { _ in },
        isCancelled: @escaping @Sendable () -> Bool = { false }
    ) async throws -> PDFOCRResult {
        try await Task.detached(priority: .userInitiated) {
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

            for (member, data) in documents {
                try checkCancellation(isCancelled)
                guard let pdf = PDFDocument(data: data), pdf.pageCount > 0 else {
                    throw PDFOCRError.invalidPDF(memberName: member.displayName)
                }

                var recognizedLinesByPage: [Int: [PDFOCRRecognizedLine]] = [:]
                try await withThrowingTaskGroup(of: (Int, [PDFOCRRecognizedLine]).self) { group in
                    var nextPageIndex = 0
                    var submitted = 0

                    func submitNextPageIfNeeded() {
                        while submitted < 3, nextPageIndex < pdf.pageCount {
                            let pageIndex = nextPageIndex
                            nextPageIndex += 1
                            let pageNumber = globalPageOffset + pageIndex + 1
                            guard let page = pdf.page(at: pageIndex) else {
                                group.addTask {
                                    throw PDFOCRError.pageRenderFailed(pageNumber: pageNumber)
                                }
                                submitted += 1
                                continue
                            }
                            if !shouldProcessPage(page, includePagesWithText: includePagesWithText) {
                                completedPages += 1
                                progress(Double(completedPages) / Double(max(totalPages, 1)))
                                continue
                            }
                            guard let pageData = singlePageData(from: page) else {
                                group.addTask {
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
                                    throw PDFOCRError.pageRenderFailed(pageNumber: pageNumber)
                                }
                                let lines = try autoreleasepool {
                                    try recognitionProvider(isolatedPage, pageNumber, isCancelled)
                                }
                                try checkCancellation(isCancelled)
                                let filteredLines = filteredRecognizedLines(lines)
                                guard !filteredLines.isEmpty else {
                                    throw PDFOCRError.recognitionFailed(pageNumber: pageNumber)
                                }
                                return (pageIndex, filteredLines)
                            }
                        }
                    }

                    submitNextPageIfNeeded()
                    while let result = try await group.next() {
                        submitted -= 1
                        recognizedLinesByPage[result.0] = result.1
                        completedPages += 1
                        progress(Double(completedPages) / Double(max(totalPages, 1)))
                        submitNextPageIfNeeded()
                    }
                }

                guard let rewritten = PDFDocument(data: data) else {
                    throw PDFOCRError.invalidPDF(memberName: member.displayName)
                }
                var changedPages: [(index: Int, page: PDFPage)] = []
                for pageIndex in 0..<pdf.pageCount {
                    try checkCancellation(isCancelled)
                    guard let page = pdf.page(at: pageIndex) else {
                        throw PDFOCRError.pageRenderFailed(pageNumber: globalPageOffset + pageIndex + 1)
                    }

                    if !shouldProcessPage(page, includePagesWithText: includePagesWithText) {
                        continue
                    } else {
                        guard let lines = recognizedLinesByPage[pageIndex], !lines.isEmpty else {
                            throw PDFOCRError.recognitionFailed(pageNumber: globalPageOffset + pageIndex + 1)
                        }
                        guard let searchablePage = searchablePage(from: page, lines: lines) else {
                            throw PDFOCRError.outputFailed(memberName: member.displayName)
                        }
                        searchablePage.rotation = page.rotation
                        for annotation in page.annotations {
                            guard let copied = annotation.copy() as? PDFAnnotation else {
                                throw PDFOCRError.outputFailed(memberName: member.displayName)
                            }
                            searchablePage.addAnnotation(copied)
                        }
                        changedPages.append((pageIndex, searchablePage))
                        recognizedPages += 1
                    }
                }

                for changedPage in changedPages {
                    rewritten.removePage(at: changedPage.index)
                    rewritten.insert(changedPage.page, at: changedPage.index)
                }

                guard let memberData = changedPages.isEmpty ? data as Data? : PDFSerializer.data(from: rewritten),
                      PDFDocument(data: memberData)?.pageCount == pdf.pageCount else {
                    throw PDFOCRError.outputFailed(memberName: member.displayName)
                }
                output[member.id] = memberData
                globalPageOffset += pdf.pageCount
            }

            guard recognizedPages > 0 else { throw PDFOCRError.noScannedPages }
            progress(1)
            return PDFOCRResult(dataByMemberID: output, recognizedPageCount: recognizedPages)
        }.value
    }

    private static func recognizeText(page: PDFPage, pageNumber: Int, isCancelled: @escaping () -> Bool) throws -> [PDFOCRRecognizedLine] {
        try checkCancellation(isCancelled)
        guard let image = renderedImage(for: page) else {
            throw PDFOCRError.pageRenderFailed(pageNumber: pageNumber)
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true

        do {
            try VNImageRequestHandler(cgImage: image, orientation: .up, options: [:]).perform([request])
        } catch {
            throw PDFOCRError.recognitionFailed(pageNumber: pageNumber)
        }
        try checkCancellation(isCancelled)

        return filteredRecognizedLines((request.results ?? []).compactMap { observation in
            guard let candidate = observation.topCandidates(1).first,
                  candidate.confidence >= minimumConfidence else {
                return nil
            }
            let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return PDFOCRRecognizedLine(
                text: text,
                normalizedBounds: observation.boundingBox,
                confidence: candidate.confidence
            )
        })
    }

    static func isLikelyScannedPage(_ page: PDFPage) -> Bool {
        let hasText = !(page.string?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        guard !hasText else { return false }
        return hasVisibleContent(page)
    }

    static func hasVisibleContent(_ page: PDFPage) -> Bool {
        pageHasVisibleContent(page)
    }

    private static func shouldProcessPage(_ page: PDFPage, includePagesWithText: Bool) -> Bool {
        if includePagesWithText {
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

    private static func renderedImage(for page: PDFPage) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width.isFinite, bounds.height.isFinite, bounds.width > 0, bounds.height > 0 else {
            return nil
        }

        let dpiScale = targetDPI / 72
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

    private static func searchablePage(from page: PDFPage, lines: [PDFOCRRecognizedLine]) -> PDFPage? {
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
        drawInvisibleText(lines: lines, mediaBox: mediaBox, pageRotation: page.rotation, in: context)
        context.restoreGState()
        context.endPDFPage()
        context.closePDF()

        guard let doc = PDFDocument(data: data as Data) else { return nil }
        return doc.page(at: 0)
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
            return PDFOCRRecognizedLine(text: text, normalizedBounds: line.normalizedBounds, confidence: line.confidence)
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
        for y in stride(from: 0, to: bitmap.pixelsHigh, by: stepY) {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: stepX) {
                sampled += 1
                guard let color = bitmap.colorAt(x: x, y: y) else { continue }
                if color.alphaComponent > 0.05,
                   (color.redComponent < 0.96 || color.greenComponent < 0.96 || color.blueComponent < 0.96) {
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
