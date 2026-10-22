import AppKit
import CoreText
import CQPDF
import PDFKit
import XCTest
@testable import Orifold

@MainActor
final class UnlockedPDFImportTests: XCTestCase {
    private var directories: [URL] = []
    private let metadata = PDFDocumentMetadata(title: "折り紙", author: "うまん", subject: "विषय", keywords: "标签")

    override func tearDown() {
        directories.forEach { try? FileManager.default.removeItem(at: $0) }
        super.tearDown()
    }

    func testOwnerAndUserUnlockProduceReadableWorkspaceBytesSupportingEditSaveAndPrintPreparation() async throws {
        for password in ["fictional-user", "fictional-owner"] {
            let directory = try directory()
            let source = try restrictedFixture()
            let url = directory.appendingPathComponent("restricted.pdf")
            try source.write(to: url)
            let document = WorkspaceDocument()
            let vm = WorkspaceViewModel(document: document, processingEngine: PDFiumProcessingEngine())
            vm.importFiles(urls: [url])
            try await waitForImport(vm)
            let pending = try XCTUnwrap(vm.pendingPasswordPDF)
            XCTAssertFalse(vm.unlock(pdf: pending, password: "wrong", url: url))
            XCTAssertEqual(vm.pendingPasswordURL, url)
            XCTAssertTrue(vm.memberDocuments.isEmpty)
            XCTAssertTrue(vm.unlock(pdf: pending, password: password, url: url))
            XCTAssertNil(vm.pendingPasswordURL)
            XCTAssertEqual(vm.memberDocuments.count, 1)
            let member = try XCTUnwrap(vm.memberDocuments.first)
            let bytes = try XCTUnwrap(document.memberPDFData[member.id])
            let parsed = try XCTUnwrap(PDFDocument(data: bytes))
            XCTAssertFalse(parsed.isEncrypted)
            XCTAssertFalse(parsed.isLocked)
            XCTAssertTrue(QPDFService.isStructurallySound(bytes))
            XCTAssertEqual(try PDFMetadataService.read(from: bytes), metadata)
            XCTAssertTrue(PDFTextAnalysisEngine.readingOrderText(data: bytes, pageIndex: 0).contains("Fictional text"))
            let changed = PDFDocumentMetadata(title: "Updated 折り紙", author: "うまん", subject: "विषय", keywords: "标签")
            XCTAssertTrue(vm.applyMetadataEdit(changed))
            let ref = try XCTUnwrap(document.workspace.pageOrder.first)
            vm.rotatePages([ref], by: 90)
            XCTAssertEqual(vm.loadedPDFs.first?.1.page(at: 0)?.rotation, 90)
            let printableBytes = try vm.dataForPDFExport()
            let printable = try XCTUnwrap(PDFDocument(data: printableBytes))
            XCTAssertFalse(printable.isEncrypted)
            XCTAssertTrue(printable.allowsPrinting)
            XCTAssertTrue(printable.allowsCopying)
            XCTAssertEqual(try PDFMetadataService.read(from: printableBytes), changed)
            let saved = try document.savedFileWrapper(from: document.snapshot(contentType: .pdf))
            let reopened = try WorkspaceDocument(testingFile: saved, contentType: .pdf,
                                                 fingerprintStore: WorkspaceFingerprintStore(directory: directory))
            XCTAssertEqual(try PDFMetadataService.read(from: XCTUnwrap(reopened.memberPDFData[member.id])), changed)
            XCTAssertEqual(try Data(contentsOf: url), source)
        }
    }

    func testFailedPreparationKeepsPendingBatchAndShowsPreparationErrorRatherThanWrongPassword() async throws {
        let directory = try directory()
        let original = try restrictedFixture()
        let url = directory.appendingPathComponent("restricted.pdf")
        try original.write(to: url)
        let vm = WorkspaceViewModel(document: WorkspaceDocument(), processingEngine: PDFiumProcessingEngine())
        var completions: [Int] = []
        vm.importFiles(urls: [url]) { count, _ in completions.append(count) }
        try await waitForImport(vm)
        let pending = try XCTUnwrap(vm.pendingPasswordPDF)
        vm.importError = WorkspaceViewModel.ImportError(fileName: "earlier.pdf", message: "Fictional earlier failure")
        XCTAssertFalse(vm.unlock(pdf: pending, password: "wrong", url: url))
        let prompt = PasswordPromptView(fileName: url.lastPathComponent, pdf: pending, url: url, viewModel: vm)
        XCTAssertEqual(prompt.failureMessage, L10n.string("passwordPrompt.incorrectPassword.message"))
        XCTAssertTrue(pending.unlock(withPassword: "fictional-owner"))
        pending.removePage(at: 0)
        XCTAssertFalse(vm.unlock(pdf: pending, password: "fictional-owner", url: url))
        XCTAssertEqual(vm.importError?.message, L10n.string("error.import.preparePDFForSaving"))
        XCTAssertEqual(prompt.failureMessage, L10n.string("error.import.preparePDFForSaving"))
        XCTAssertEqual(vm.pendingPasswordURL, url)
        XCTAssertTrue(vm.pendingPasswordPDF === pending)
        XCTAssertTrue(vm.memberDocuments.isEmpty)
        XCTAssertTrue(completions.isEmpty)
        XCTAssertEqual(try Data(contentsOf: url), original)
        vm.cancelPendingPasswordImport()
        XCTAssertEqual(completions, [0])
    }

    func testDecryptionPreservesUnicodeInfoAndExactAttachmentBytesAndRejectsWrongPassword() throws {
        let encrypted = try restrictedFixture()
        let payload = Data("fictional attachment\0exact".utf8)
        let attached = try AttachmentsService.add(payload, name: "fictional.txt", mimeType: "text/plain",
                                                   to: encrypted, password: "fictional-owner")
        for password in ["fictional-user", "fictional-owner"] {
            let plain = try XCTUnwrap(QPDFService.decrypted(attached, password: password))
            XCTAssertFalse(try XCTUnwrap(PDFDocument(data: plain)).isEncrypted)
            XCTAssertTrue(QPDFService.isStructurallySound(plain))
            XCTAssertEqual(try PDFMetadataService.read(from: plain), metadata)
            XCTAssertEqual(try AttachmentsService.extract("fictional.txt", from: plain), payload)
            XCTAssertTrue(PDFTextAnalysisEngine.readingOrderText(data: plain, pageIndex: 0).contains("Fictional text"))
        }
        XCTAssertNil(QPDFService.decrypted(encrypted, password: "wrong"))
    }

    private func waitForImport(_ vm: WorkspaceViewModel) async throws {
        for _ in 0..<1000 where vm.isImporting { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertFalse(vm.isImporting)
    }

    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("unlocked-pdf-\(UUID())")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        directories.append(url)
        return url
    }

    private func restrictedFixture() throws -> Data {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        let ctx = try XCTUnwrap(CGContext(consumer: XCTUnwrap(CGDataConsumer(data: data as CFMutableData)), mediaBox: &box, nil))
        ctx.beginPDFPage(nil)
        ctx.textPosition = CGPoint(x: 72, y: 700)
        CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: "Fictional text",
            attributes: [.font: NSFont(name: "Helvetica", size: 14)!, .foregroundColor: NSColor.black])), ctx)
        ctx.endPDFPage()
        ctx.closePDF()
        let base = try PDFMetadataService.write(metadata, to: data as Data)
        let qpdf = try XCTUnwrap(qpdf_init())
        defer { var handle = Optional(qpdf); qpdf_cleanup(&handle) }
        XCTAssertEqual(base.withUnsafeBytes { bytes in
            qpdf_read_memory(qpdf, "synthetic restricted", bytes.baseAddress?.assumingMemoryBound(to: CChar.self), UInt64(base.count), nil)
        }, 0)
        XCTAssertEqual(qpdf_init_write_memory(qpdf), 0)
        qpdf_set_r6_encryption_parameters2(qpdf, "fictional-user", "fictional-owner", QPDF_TRUE,
            QPDF_FALSE, QPDF_FALSE, QPDF_FALSE, QPDF_FALSE, QPDF_FALSE, qpdf_r3p_none, QPDF_TRUE)
        XCTAssertEqual(qpdf_write(qpdf), 0)
        return Data(bytes: try XCTUnwrap(qpdf_get_buffer(qpdf)), count: Int(qpdf_get_buffer_length(qpdf)))
    }
}
