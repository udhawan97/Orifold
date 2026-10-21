import AppKit
import CoreText
import PDFKit
import XCTest
@testable import Orifold

@MainActor
final class InteractiveCompressedExportTests: XCTestCase {
    private var directories: [URL] = []

    override func tearDown() {
        directories.forEach { try? FileManager.default.removeItem(at: $0) }
        super.tearDown()
    }

    func testActualCompressedExportUsesSelectedTwoUpLayout() async throws {
        let vm = try model()
        let output = try await exported(vm, options: WorkspaceExportOptions(
            compressionPreset: .balanced, imposition: .nUp(rows: 1, cols: 2)))
        let pdf = try XCTUnwrap(PDFDocument(data: output))
        XCTAssertEqual(pdf.pageCount, 2, "the interactive compressed route must impose four pages onto two sheets")
        try assertTokens(["PAGEONE", "PAGETWO"], in: output, pageIndex: 0)
        try assertTokens(["PAGETHREE", "PAGEFOUR"], in: output, pageIndex: 1)
        XCTAssertTrue(QPDFService.isStructurallySound(output))
        XCTAssertFalse(try XCTUnwrap(vm.exportSuccess?.detail).isEmpty, "compression summary must survive finalization")
    }

    func testActualCompressedBookletKeepsFolioOrderAndBakedFormAndStamp() async throws {
        let vm = try model()
        let page = try XCTUnwrap(vm.loadedPDFs.first?.1.page(at: 0))
        let widget = PDFAnnotation(bounds: CGRect(x: 72, y: 610, width: 250, height: 30), forType: .widget, withProperties: nil)
        widget.widgetFieldType = .text
        widget.fieldName = "FixtureAnswer"
        widget.widgetStringValue = "BAKEDANSWER"
        widget.font = NSFont(name: "Helvetica", size: 18)
        page.addAnnotation(widget)
        let ref = try XCTUnwrap(vm.document.workspace.pageOrder.first)
        vm.document.workspace.decorations = [.stamp(text: "BAKEDSTAMP", swatch: .coral, pageRefID: ref.id,
            rect: CGRect(x: 72, y: 500, width: 250, height: 50))]
        let output = try await exported(vm, options: WorkspaceExportOptions(
            lockFormAnswers: true, compressionPreset: .balanced, imposition: .booklet))
        let pdf = try XCTUnwrap(PDFDocument(data: output))
        XCTAssertEqual(pdf.pageCount, 2)
        try assertTokens(["PAGEFOUR", "PAGEONE"], in: output, pageIndex: 0)
        try assertTokens(["PAGETWO", "PAGETHREE"], in: output, pageIndex: 1)
        let firstText = PDFTextAnalysisEngine.readingOrderText(data: output, pageIndex: 0)
        XCTAssertTrue(firstText.contains("BAKEDANSWER"))
        XCTAssertTrue(firstText.contains("BAKEDSTAMP"))
        XCTAssertFalse((0..<pdf.pageCount).flatMap { pdf.page(at: $0)?.annotations ?? [] }.contains { $0.isPDFWidget })
    }

    func testActualCompressedScaleChangesPageSizeAndRetainsFaithfulBookmarks() async throws {
        let vm = try model()
        vm.beginOutlineEditing()
        vm.addBookmark(title: "Chapter Two", at: vm.document.workspace.pageOrder[1])
        let output = try await exported(vm, options: WorkspaceExportOptions(
            compressionPreset: .balanced, imposition: .scale(width: 300, height: 400)))
        let pdf = try XCTUnwrap(PDFDocument(data: output))
        XCTAssertEqual(pdf.pageCount, 4)
        for index in 0..<pdf.pageCount {
            let box = try XCTUnwrap(pdf.page(at: index)).bounds(for: .mediaBox)
            XCTAssertEqual(box.width, 300, accuracy: 0.1)
            XCTAssertEqual(box.height, 400, accuracy: 0.1)
        }
        XCTAssertEqual(PDFOutlineReader.nodes(in: pdf).map(\.title), ["Chapter Two"])
        XCTAssertEqual(PDFOutlineReader.nodes(in: pdf).map(\.localPageIndex), [1])
        try assertTokens(["PAGETWO"], in: output, pageIndex: 1)
    }

    func testActualCompressedLayoutPreservesAttachmentsUnlessSanitizedBeforeProtection() async throws {
        for protects in [false, true] {
            for sanitizes in [false, true] {
                let vm = try model()
                XCTAssertTrue(vm.applyMetadataEdit(PDFDocumentMetadata(title: "Fictional metadata")))
                let payload = Data("fictional exact attachment".utf8)
                let attachment = try directory().appendingPathComponent("proof.txt")
                try payload.write(to: attachment)
                XCTAssertTrue(vm.addAttachment(attachment))
                XCTAssertEqual(try PDFMetadataService.read(from: XCTUnwrap(vm.document.memberPDFData.values.first)).title,
                    "Fictional metadata")
                // Match the established layout contract without pinning its current Info behavior.
                let expectedTitle: String?
                if sanitizes {
                    expectedTitle = nil
                } else {
                    XCTAssertEqual(try PDFMetadataService.read(from: vm.dataForPDFExport()).title, "Fictional metadata")
                    expectedTitle = try PDFMetadataService.read(from: vm.dataForPDFExport(
                        options: WorkspaceExportOptions(imposition: .nUp(rows: 1, cols: 2)))).title
                }
                let encryption = protects ? protection() : nil
                let output = try await exported(vm, options: WorkspaceExportOptions(encryption: encryption,
                    compressionPreset: .balanced,
                    sanitization: sanitizes ? PDFSanitizationOptions(removesMetadata: true) : nil,
                    imposition: .nUp(rows: 1, cols: 2)))
                XCTAssertTrue(QPDFService.isStructurallySound(output, password: encryption?.userPassword))
                let plaintext: Data
                if let encryption {
                    try PDFEncryptionService.validateEncryptedData(output, options: encryption)
                    plaintext = try XCTUnwrap(QPDFService.decrypted(output, password: encryption.userPassword))
                } else {
                    plaintext = output
                    XCTAssertFalse(try XCTUnwrap(PDFDocument(data: output)).isEncrypted)
                }
                XCTAssertEqual(PDFDocument(data: plaintext)?.pageCount, 2)
                let attachments = try AttachmentsService.list(in: output, password: encryption?.userPassword)
                XCTAssertEqual(attachments.map(\.name), sanitizes ? [] : ["proof.txt"])
                if !sanitizes {
                    XCTAssertEqual(try AttachmentsService.extract("proof.txt", from: output, password: encryption?.userPassword), payload)
                }
                XCTAssertEqual(try PDFMetadataService.read(from: output, password: encryption?.userPassword).title, expectedTitle)
            }
        }
    }

    func testCancelledActualCompressedExportLeavesExistingDestinationUntouched() async throws {
        let vm = try model()
        let destination = try directory().appendingPathComponent("existing.pdf")
        let original = Data("original destination bytes".utf8)
        try original.write(to: destination)
        XCTAssertTrue(vm.exportCompressedPDF(options: WorkspaceExportOptions(
            compressionPreset: .balanced, imposition: .booklet), destination: destination))
        vm.cancelActiveOperation()
        try await waitForCompletion(vm)
        XCTAssertNil(vm.exportSuccess)
        XCTAssertNil(vm.exportError)
        XCTAssertEqual(vm.editingStatus?.message, PDFCompressionError.cancelled.errorDescription)
        XCTAssertEqual(try Data(contentsOf: destination), original)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: destination.deletingLastPathComponent().path), ["existing.pdf"])
    }

    func testFailedActualCompressedPublicationPreservesExistingDestinationAndCleansStaging() async throws {
        let vm = try model()
        let folder = try directory()
        let destination = folder.appendingPathComponent("existing.pdf")
        let original = Data("original destination bytes".utf8)
        try original.write(to: destination)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: folder.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path) }
        XCTAssertTrue(vm.exportCompressedPDF(options: WorkspaceExportOptions(
            compressionPreset: .balanced, imposition: .nUp(rows: 1, cols: 2)), destination: destination))
        try await waitForCompletion(vm)
        XCTAssertNil(vm.exportSuccess)
        let message = try XCTUnwrap(vm.exportError?.message)
        XCTAssertTrue(message.contains(POSIXError(.EACCES).localizedDescription), "failure must come from destination publication")
        XCTAssertEqual(try Data(contentsOf: destination), original)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), ["existing.pdf"])
    }

    func testLegacyReducedDataKeepsSanitizationProtectionStatisticsAndCancellationSemantics() async throws {
        let vm = try model()
        XCTAssertTrue(vm.applyMetadataEdit(PDFDocumentMetadata(title: "Fictional metadata")))
        let source = try vm.dataForPDFExport()
        let options = protection()
        let output = try await vm.reducedData(from: source, preset: .balanced,
            sanitization: PDFSanitizationOptions(removesMetadata: true), encryption: options,
            cancellation: OperationCancellationToken(), operationID: UUID())
        try PDFEncryptionService.validateEncryptedData(output.data, options: options)
        XCTAssertEqual(try PDFMetadataService.read(from: output.data, password: options.userPassword), PDFDocumentMetadata())
        XCTAssertEqual(output.compressionResult.originalByteCount, source.count)
        XCTAssertEqual(output.compressionResult.compressedByteCount, output.compressionResult.data.count)
        XCTAssertLessThan(output.compressionResult.compressedByteCount, source.count)
        XCTAssertEqual(PDFDocument(data: output.compressionResult.data)?.pageCount, 4)
        let cancellation = OperationCancellationToken()
        cancellation.cancel()
        do {
            _ = try await vm.reducedData(from: source, preset: .balanced, encryption: nil,
                cancellation: cancellation, operationID: UUID())
            XCTFail("a cancelled legacy request must not produce output")
        } catch {
            XCTAssertEqual(error as? PDFCompressionError, .cancelled)
        }
    }

    func testReduceFileSizeCommandAndLegacyAdapterPreserveExactAttachments() async throws {
        let vm = try model()
        let attachment = try directory().appendingPathComponent("keep.txt")
        let payload = Data("fictional exact reduction attachment\0".utf8)
        try payload.write(to: attachment)
        XCTAssertTrue(vm.addAttachment(attachment))
        let source = try vm.dataForPDFExport()
        let legacy = try await vm.reducedData(from: source, preset: .balanced, encryption: nil,
            cancellation: OperationCancellationToken(), operationID: UUID())
        XCTAssertEqual(try AttachmentsService.list(in: legacy.data).map(\.name), ["keep.txt"])
        XCTAssertEqual(try AttachmentsService.extract("keep.txt", from: legacy.data), payload)
        // A preserving compression adapter must not duplicate an already-retained attachment.
        let regrafted = try WorkspaceViewModel.reinjectingAttachments(AttachmentsService.capture(in: source), into: source)
        XCTAssertEqual(try AttachmentsService.list(in: regrafted).map(\.name), ["keep.txt"])
        let destination = try directory().appendingPathComponent("reduced.pdf")
        vm.reduceFileSize(destination: destination)
        try await waitForCompletion(vm)
        XCTAssertNil(vm.exportError?.message)
        XCTAssertEqual(vm.exportSuccess?.url, destination)
        let published = try Data(contentsOf: destination)
        XCTAssertEqual(try AttachmentsService.list(in: published).map(\.name), ["keep.txt"])
        XCTAssertEqual(try AttachmentsService.extract("keep.txt", from: published), payload)
        XCTAssertTrue(QPDFService.isStructurallySound(published))
    }

    func testReduceFileSizeCancellationAndPublicationFailurePreserveDestination() async throws {
        for cancels in [true, false] {
            let vm = try model()
            let folder = try directory()
            let destination = folder.appendingPathComponent("existing.pdf")
            let original = Data("original reduction destination".utf8)
            try original.write(to: destination)
            if !cancels { try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: folder.path) }
            defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path) }
            vm.reduceFileSize(destination: destination)
            if cancels { vm.cancelActiveOperation() }
            try await waitForCompletion(vm)
            XCTAssertNil(vm.exportSuccess)
            if cancels {
                XCTAssertNil(vm.exportError)
                XCTAssertEqual(vm.editingStatus?.message, PDFCompressionError.cancelled.errorDescription)
            } else {
                XCTAssertTrue(try XCTUnwrap(vm.exportError?.message).contains(POSIXError(.EACCES).localizedDescription))
            }
            XCTAssertEqual(try Data(contentsOf: destination), original)
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), ["existing.pdf"])
        }
    }

    func testLegacyReductionKeepsInvalidPDFError() async throws {
        let vm = try model()
        do {
            _ = try await vm.reducedData(from: Data("invalid PDF".utf8), preset: .balanced,
                encryption: nil, cancellation: OperationCancellationToken(), operationID: UUID())
            XCTFail("Invalid bytes must not produce output")
        } catch {
            XCTAssertEqual(error as? PDFCompressionError, .invalidPDF)
        }
    }

    private func protection() -> PDFEncryptionOptions {
        PDFEncryptionOptions(userPassword: "Fixture User 002", ownerPassword: "Fixture Owner 002",
            allowsPrinting: false, allowsCopying: false)
    }

    private func assertTokens(_ tokens: [String], in data: Data, pageIndex: Int) throws {
        let text = PDFTextAnalysisEngine.readingOrderText(data: data, pageIndex: pageIndex)
        let ranges = try tokens.map { try XCTUnwrap(text.range(of: $0), "missing \($0) on output sheet \(pageIndex)") }
        for index in 1..<ranges.count {
            XCTAssertLessThan(ranges[index - 1].lowerBound, ranges[index].lowerBound, "source page order must follow the selected layout")
        }
        for token in ["PAGEONE", "PAGETWO", "PAGETHREE", "PAGEFOUR"] where !tokens.contains(token) {
            XCTAssertFalse(text.contains(token), "unselected source page appeared on output sheet \(pageIndex)")
        }
    }

    private func exported(_ vm: WorkspaceViewModel, options: WorkspaceExportOptions) async throws -> Data {
        let destination = try directory().appendingPathComponent("output.pdf")
        XCTAssertTrue(vm.exportCompressedPDF(options: options, destination: destination))
        try await waitForCompletion(vm)
        XCTAssertNil(vm.exportError?.message)
        XCTAssertEqual(vm.exportSuccess?.url, destination)
        return try Data(contentsOf: destination)
    }

    private func waitForCompletion(_ vm: WorkspaceViewModel) async throws {
        let deadline = Date().addingTimeInterval(60)
        var fractions: [Double] = []
        while vm.operationProgress.isActive && Date() < deadline {
            fractions.append(vm.operationProgress.fraction)
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        if vm.operationProgress.isActive {
            vm.cancelActiveOperation()
            XCTFail("export must complete within the hang detector")
            throw CancellationError()
        }
        XCTAssertEqual(fractions, fractions.sorted(), "compression and layout progress must never move backwards")
    }

    private func model() throws -> WorkspaceViewModel {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        let context = try XCTUnwrap(CGContext(consumer: XCTUnwrap(CGDataConsumer(data: data as CFMutableData)), mediaBox: &box, nil))
        let width = 1600, height = 1600
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                pixels[offset] = UInt8((x * y) % 255)
                pixels[offset + 1] = UInt8((x + 2 * y) % 255)
                pixels[offset + 2] = UInt8((2 * x + y) % 255)
            }
        }
        let provider = try XCTUnwrap(CGDataProvider(data: Data(pixels) as CFData))
        let image = try XCTUnwrap(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider,
            decode: nil, shouldInterpolate: true, intent: .defaultIntent))
        for token in ["PAGEONE", "PAGETWO", "PAGETHREE", "PAGEFOUR"] {
            context.beginPDFPage(nil)
            context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(box)
            context.draw(image, in: CGRect(x: 72, y: 72, width: 468, height: 350))
            context.textPosition = CGPoint(x: 72, y: 700)
            CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: token,
                attributes: [.font: NSFont(name: "Helvetica", size: 18)!, .foregroundColor: NSColor.black])), context)
            context.endPDFPage()
        }
        context.closePDF()
        let document = try WorkspaceDocument(testingFile: FileWrapper(regularFileWithContents: data as Data), contentType: .pdf,
            fingerprintStore: WorkspaceFingerprintStore(directory: try directory()))
        return WorkspaceViewModel(document: document, processingEngine: PDFiumProcessingEngine())
    }

    private func directory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("interactive-compressed-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        directories.append(directory)
        return directory
    }
}
