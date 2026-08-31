import AppKit
import CoreGraphics
import CoreText
import PDFKit
import Vision
import XCTest
@testable import Orifold

@MainActor
final class ScanCleanupTests: XCTestCase {
    private var retainedUndoManager: UndoManager?

    func testBinarizeProducesOnlyBlackAndWhitePixels() throws {
        let source = try grayscaleGradient(width: 96, height: 48)

        let output = ScanCleanup.binarize(source)
        let samples = try grayscaleSamples(in: output)

        XCTAssertFalse(samples.isEmpty)
        XCTAssertTrue(samples.allSatisfy { $0 == 0 || $0 == 255 })
        XCTAssertTrue(samples.contains(0))
        XCTAssertTrue(samples.contains(255))
    }

    func testDespeckleRemovesAnIsolatedBlackPixelWithoutErasingAStroke() throws {
        var pixels = [UInt8](repeating: 255, count: 9 * 9 * 4)
        for index in stride(from: 3, to: pixels.count, by: 4) { pixels[index] = 255 }
        setGray(0, x: 1, y: 1, width: 9, pixels: &pixels)
        for y in 2...6 { setGray(0, x: 5, y: y, width: 9, pixels: &pixels) }
        let source = try makeImage(pixels: &pixels, width: 9, height: 9)

        let output = ScanCleanup.despeckle(source)
        let samples = try grayscaleSamples(in: output)

        XCTAssertEqual(samples[1 * 9 + 1], 255)
        XCTAssertEqual(samples[4 * 9 + 5], 0)
    }

    func testDeskewStraightensAndCropsAPhotographedPage() throws {
        let source = try photographedPage(angleDegrees: 7)

        let output = ScanCleanup.clean(
            source,
            options: ScanCleanupOptions(deskew: true, binarize: false, despeckle: false)
        )

        XCTAssertLessThan(abs(darkBorderSlope(in: output)), 0.03)
        XCTAssertEqual(Double(output.width) / Double(output.height), 500.0 / 360.0, accuracy: 0.12)
        XCTAssertLessThan(output.width, source.width)
        XCTAssertLessThan(output.height, source.height)
    }

    func testCleanupQualitySpikeDoesNotReduceVisionConfidence() throws {
        let source = try photographedPage(angleDegrees: 7)
        let before = try visionRecognition(in: source)

        let cleaned = ScanCleanup.clean(source, options: ScanCleanupOptions())
        let after = try visionRecognition(in: cleaned)

        XCTAssertTrue(after.text.localizedCaseInsensitiveContains("ORIFOLD RECEIPT 7429"))
        XCTAssertGreaterThanOrEqual(after.averageConfidence + 0.001, before.averageConfidence)
    }

    func testPipelineRasterizesAndCleansAPDFPage() throws {
        let image = try photographedPage(angleDegrees: 7)
        let document = PDFDocument()
        document.insert(try XCTUnwrap(PDFPage(image: NSImage(cgImage: image, size: .zero))), at: 0)
        let page = try XCTUnwrap(document.page(at: 0))

        let cleaned = try XCTUnwrap(
            ScanCleanupPipeline.cleanedImage(for: page, options: ScanCleanupOptions())
        )

        let recognized = try visionRecognition(in: cleaned)
        XCTAssertTrue(recognized.text.localizedCaseInsensitiveContains("ORIFOLD RECEIPT 7429"))
        XCTAssertLessThan(cleaned.width, try XCTUnwrap(PDFOCRService.rasterizedImage(for: page)).width)
    }

    func testReplacingPageContentPreservesMemberStructureAndOtherPages() throws {
        let source = PDFDocument()
        source.insert(
            try XCTUnwrap(PDFPage(image: NSImage(cgImage: photographedPage(angleDegrees: 7), size: .zero))),
            at: 0
        )
        source.insert(
            try XCTUnwrap(PDFPage(image: NSImage(cgImage: grayscaleGradient(width: 320, height: 220), size: .zero))),
            at: 1
        )
        let note = PDFAnnotation(
            bounds: CGRect(x: 20, y: 20, width: 24, height: 24),
            forType: .text,
            withProperties: nil
        )
        note.contents = "Keep this review note"
        source.page(at: 0)?.addAnnotation(note)
        let sourceData = try XCTUnwrap(PDFSerializer.data(from: source))
        let attachment = Data("scan-cleanup-structure-proof".utf8)
        let withAttachment = try AttachmentsService.add(
            attachment,
            name: "proof.txt",
            mimeType: "text/plain",
            to: sourceData
        )
        let untouchedBefore = try XCTUnwrap(PDFOCRService.rasterizedImage(for: XCTUnwrap(source.page(at: 1)), dpi: 72))

        let output = try ScanCleanupPipeline.replacingPageContents(
            in: withAttachment,
            pageIndices: [0],
            options: ScanCleanupOptions()
        )

        XCTAssertTrue(QPDFService.isStructurallySound(output))
        XCTAssertEqual(try AttachmentsService.extract("proof.txt", from: output), attachment)
        let reopened = try XCTUnwrap(PDFDocument(data: output))
        XCTAssertEqual(reopened.pageCount, 2)
        let cleanedPage = try XCTUnwrap(reopened.page(at: 0))
        XCTAssertTrue(cleanedPage.annotations.contains { $0.contents == "Keep this review note" })
        XCTAssertTrue(
            try visionRecognition(in: XCTUnwrap(PDFOCRService.rasterizedImage(for: cleanedPage)))
                .text.localizedCaseInsensitiveContains("ORIFOLD RECEIPT 7429")
        )
        let untouchedAfter = try XCTUnwrap(
            PDFOCRService.rasterizedImage(for: XCTUnwrap(reopened.page(at: 1)), dpi: 72)
        )
        XCTAssertLessThan(try pixelDifference(untouchedBefore, untouchedAfter), 0.001)
    }

    func testReplacingPageContentPreservesRotationAndMediaBox() throws {
        let source = PDFDocument()
        let page = try XCTUnwrap(
            PDFPage(image: NSImage(cgImage: photographedPage(angleDegrees: 4), size: .zero))
        )
        page.rotation = 90
        source.insert(page, at: 0)
        let sourceData = try XCTUnwrap(PDFSerializer.data(from: source))
        let serializedSource = try XCTUnwrap(PDFDocument(data: sourceData))
        let serializedPage = try XCTUnwrap(serializedSource.page(at: 0))
        let serializedMediaBox = serializedPage.bounds(for: .mediaBox)
        XCTAssertTrue(
            try visionRecognition(in: XCTUnwrap(PDFOCRService.rasterizedImage(for: serializedPage)))
                .text.localizedCaseInsensitiveContains("ORIFOLD RECEIPT 7429")
        )

        let output = try ScanCleanupPipeline.replacingPageContents(
            in: sourceData,
            pageIndices: [0],
            options: ScanCleanupOptions()
        )

        let reopened = try XCTUnwrap(PDFDocument(data: output))
        let reopenedPage = try XCTUnwrap(reopened.page(at: 0))
        XCTAssertEqual(reopenedPage.rotation, 90)
        XCTAssertEqual(reopenedPage.bounds(for: .mediaBox).minX, serializedMediaBox.minX, accuracy: 0.01)
        XCTAssertEqual(reopenedPage.bounds(for: .mediaBox).minY, serializedMediaBox.minY, accuracy: 0.01)
        XCTAssertEqual(reopenedPage.bounds(for: .mediaBox).width, serializedMediaBox.width, accuracy: 0.01)
        XCTAssertEqual(reopenedPage.bounds(for: .mediaBox).height, serializedMediaBox.height, accuracy: 0.01)
        let rendered = try XCTUnwrap(PDFOCRService.rasterizedImage(for: reopenedPage))
        let recognition = try visionRecognition(in: rendered)
        XCTAssertTrue(
            recognition.text.localizedCaseInsensitiveContains("RECEIPT 7429"),
            "Recognized text: \(recognition.text)"
        )
    }

    func testViewModelCleanupIsAtomicAndByteExactAcrossUndoRedo() async throws {
        let source = PDFDocument()
        source.insert(
            try XCTUnwrap(PDFPage(image: NSImage(cgImage: photographedPage(angleDegrees: 7), size: .zero))),
            at: 0
        )
        source.insert(
            try XCTUnwrap(PDFPage(image: NSImage(cgImage: grayscaleGradient(width: 320, height: 220), size: .zero))),
            at: 1
        )
        let attachment = Data("scan-cleanup-undo-proof".utf8)
        let sourceData = try XCTUnwrap(PDFSerializer.data(from: source))
        let wrapper = FileWrapper(regularFileWithContents: sourceData)
        wrapper.preferredFilename = "scan.pdf"
        let document = try WorkspaceDocument(testingFile: wrapper, contentType: .pdf, filename: "scan.pdf")
        let viewModel = WorkspaceViewModel(document: document, processingEngine: PDFiumProcessingEngine())
        let undoManager = UndoManager()
        retainedUndoManager = undoManager
        viewModel.undoManager = undoManager
        let attachmentDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Orifold-scan-cleanup-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: attachmentDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: attachmentDirectory) }
        let attachmentURL = attachmentDirectory.appendingPathComponent("proof.txt")
        try attachment.write(to: attachmentURL)
        XCTAssertTrue(viewModel.addAttachment(attachmentURL))
        undoManager.removeAllActions()
        let memberID = try XCTUnwrap(viewModel.document.workspace.documents.first?.id)
        let firstPageRefID = try XCTUnwrap(viewModel.document.workspace.pageOrder.first?.id)
        let original = try XCTUnwrap(viewModel.document.memberPDFData[memberID])

        let applied = await viewModel.applyScanCleanup(
            pageRefIDs: [firstPageRefID],
            options: ScanCleanupOptions()
        )

        XCTAssertTrue(applied)
        let cleaned = try XCTUnwrap(viewModel.document.memberPDFData[memberID])
        XCTAssertNotEqual(cleaned, original)
        XCTAssertTrue(QPDFService.isStructurallySound(cleaned))
        XCTAssertEqual(try AttachmentsService.extract("proof.txt", from: cleaned), attachment)
        XCTAssertEqual(viewModel.document.workspace.pageOrder.map(\.id), sourcePageIDs(in: viewModel))
        XCTAssertEqual(undoManager.undoActionName, L10n.string("undo.cleanScan"))

        undoManager.undo()
        XCTAssertEqual(viewModel.document.memberPDFData[memberID], original)

        undoManager.redo()
        XCTAssertEqual(viewModel.document.memberPDFData[memberID], cleaned)
    }

    func testCleanupScopeDefaultsToCurrentPageAndCanExpandToDocument() throws {
        let source = PDFDocument()
        for index in 0..<2 {
            source.insert(
                try XCTUnwrap(PDFPage(image: NSImage(cgImage: grayscaleGradient(width: 120, height: 90), size: .zero))),
                at: index
            )
        }
        let wrapper = FileWrapper(regularFileWithContents: try XCTUnwrap(PDFSerializer.data(from: source)))
        wrapper.preferredFilename = "scope.pdf"
        let document = try WorkspaceDocument(testingFile: wrapper, contentType: .pdf, filename: "scope.pdf")
        let viewModel = WorkspaceViewModel(document: document, processingEngine: PDFiumProcessingEngine())
        let refs = viewModel.document.workspace.pageOrder
        viewModel.selectPage(refs[1])

        XCTAssertEqual(viewModel.scanCleanupTargetPageRefIDs(scope: .currentPage), [refs[1].id])
        XCTAssertEqual(viewModel.scanCleanupTargetPageRefIDs(scope: .document), refs.map(\.id))
    }
}

@MainActor
private func sourcePageIDs(in viewModel: WorkspaceViewModel) -> [UUID] {
    viewModel.document.workspace.documents.flatMap(\.pageRefs)
}

private func setGray(_ value: UInt8, x: Int, y: Int, width: Int, pixels: inout [UInt8]) {
    let offset = (y * width + x) * 4
    pixels[offset] = value
    pixels[offset + 1] = value
    pixels[offset + 2] = value
    pixels[offset + 3] = 255
}

private func photographedPage(angleDegrees: CGFloat) throws -> CGImage {
    let width = 800
    let height = 650
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
          ) else { throw ScanCleanupTestError.imageCreationFailed }
    context.setFillColor(CGColor(gray: 0.35, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.saveGState()
    context.translateBy(x: CGFloat(width) / 2, y: CGFloat(height) / 2)
    context.rotate(by: angleDegrees * .pi / 180)
    let paper = CGRect(x: -250, y: -180, width: 500, height: 360)
    context.setShadow(offset: CGSize(width: 8, height: -8), blur: 12, color: CGColor(gray: 0, alpha: 0.5))
    context.setFillColor(CGColor(gray: 0.96, alpha: 1))
    context.fill(paper)
    context.setShadow(offset: .zero, blur: 0, color: nil)
    context.setStrokeColor(CGColor(gray: 0.03, alpha: 1))
    context.setLineWidth(5)
    context.stroke(paper.insetBy(dx: 2.5, dy: 2.5))
    context.setLineWidth(3)
    for offset in stride(from: -110, through: 100, by: 42) {
        context.move(to: CGPoint(x: -180, y: offset))
        context.addLine(to: CGPoint(x: 170, y: offset))
        context.strokePath()
    }
    let attributes: [NSAttributedString.Key: Any] = [
        .font: CTFontCreateWithName("Helvetica-Bold" as CFString, 27, nil),
        .foregroundColor: CGColor(gray: 0.02, alpha: 1),
    ]
    let line = CTLineCreateWithAttributedString(
        NSAttributedString(string: "ORIFOLD RECEIPT 7429", attributes: attributes)
    )
    context.textPosition = CGPoint(x: -180, y: 125)
    CTLineDraw(line, context)
    context.restoreGState()
    return try XCTUnwrap(context.makeImage())
}

private func visionRecognition(in image: CGImage) throws -> (text: String, averageConfidence: Float) {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    try VNImageRequestHandler(cgImage: image, orientation: .up, options: [:]).perform([request])
    let candidates = (request.results ?? []).compactMap { $0.topCandidates(1).first }
    let average = candidates.isEmpty
        ? 0
        : candidates.map(\.confidence).reduce(0, +) / Float(candidates.count)
    return (candidates.map(\.string).joined(separator: "\n"), average)
}

/// Independent test oracle: estimate the slope of the upper dark border by taking the first
/// dark pixel in each interior column and fitting a least-squares line.
private func darkBorderSlope(in image: CGImage) -> Double {
    let width = image.width
    let height = image.height
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
          ) else { return .infinity }
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    var points: [(Double, Double)] = []
    let inset = max(2, width / 5)
    for x in stride(from: inset, to: width - inset, by: max(1, width / 80)) {
        for y in 0..<height {
            let offset = (y * width + x) * 4
            let red = Int(pixels[offset])
            let green = Int(pixels[offset + 1])
            let blue = Int(pixels[offset + 2])
            if red + green + blue < 180 {
                points.append((Double(x), Double(y)))
                break
            }
        }
    }
    guard points.count > 8 else { return .infinity }
    let meanX = points.map(\.0).reduce(0, +) / Double(points.count)
    let meanY = points.map(\.1).reduce(0, +) / Double(points.count)
    let numerator = points.reduce(0) { $0 + ($1.0 - meanX) * ($1.1 - meanY) }
    let denominator = points.reduce(0) { $0 + ($1.0 - meanX) * ($1.0 - meanX) }
    return numerator / max(denominator, 0.000_001)
}

private func grayscaleGradient(width: Int, height: Int) throws -> CGImage {
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    for y in 0..<height {
        for x in 0..<width {
            let value = UInt8((Double(x) / Double(max(width - 1, 1)) * 255).rounded())
            let offset = (y * width + x) * 4
            pixels[offset] = value
            pixels[offset + 1] = value
            pixels[offset + 2] = value
            pixels[offset + 3] = 255
        }
    }
    return try makeImage(pixels: &pixels, width: width, height: height)
}

private func grayscaleSamples(in image: CGImage) throws -> [UInt8] {
    let width = image.width
    let height = image.height
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
          ) else {
        throw ScanCleanupTestError.imageCreationFailed
    }
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return stride(from: 0, to: pixels.count, by: 4).map { pixels[$0] }
}

private func pixelDifference(_ lhs: CGImage, _ rhs: CGImage) throws -> Double {
    guard lhs.width == rhs.width, lhs.height == rhs.height else { return 1 }
    func bytes(_ image: CGImage) throws -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: &pixels,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: image.width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { throw ScanCleanupTestError.imageCreationFailed }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return pixels
    }
    let left = try bytes(lhs)
    let right = try bytes(rhs)
    let total = zip(left, right).reduce(0.0) { partial, pair in
        partial + Double(abs(Int(pair.0) - Int(pair.1)))
    }
    return total / Double(max(left.count, 1)) / 255
}

private func makeImage(pixels: inout [UInt8], width: Int, height: Int) throws -> CGImage {
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
          ),
          let image = context.makeImage() else {
        throw ScanCleanupTestError.imageCreationFailed
    }
    return image
}

private enum ScanCleanupTestError: Error {
    case imageCreationFailed
}
