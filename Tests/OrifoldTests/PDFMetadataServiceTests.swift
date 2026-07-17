import XCTest
import PDFKit
import UniformTypeIdentifiers
@testable import Orifold

final class PDFMetadataServiceTests: XCTestCase {
    private func fixture(title: String?, author: String?) -> Data {
        let doc = PDFDocument()
        let page = PDFPage()
        doc.insert(page, at: 0)
        var attrs: [PDFDocumentAttribute: Any] = [:]
        if let title { attrs[.titleAttribute] = title }
        if let author { attrs[.authorAttribute] = author }
        doc.documentAttributes = attrs
        return doc.dataRepresentation()!  // fixture creation only — never product code
    }

    func testReadsTitleAndAuthor() throws {
        let data = fixture(title: "折り紙", author: "Gami")
        let meta = try PDFMetadataService.read(from: data, password: nil)
        XCTAssertEqual(meta.title, "折り紙")
        XCTAssertEqual(meta.author, "Gami")
        XCTAssertNil(meta.subject)
    }

    func testMissingInfoDictYieldsAllNil() throws {
        let meta = try PDFMetadataService.read(from: fixture(title: nil, author: nil), password: nil)
        XCTAssertEqual(meta, PDFDocumentMetadata())
    }

    func testWriteRoundTrip() throws {
        let edited = try PDFMetadataService.write(
            PDFDocumentMetadata(title: "New Title", author: "Ori", subject: "S", keywords: "a, b"),
            to: fixture(title: "Old", author: nil), password: nil)
        let meta = try PDFMetadataService.read(from: edited, password: nil)
        XCTAssertEqual(meta.title, "New Title")
        XCTAssertEqual(meta.keywords, "a, b")
        XCTAssertEqual(PDFDocument(data: edited)?.pageCount, 1)   // structure intact
    }

    func testNilClearsKey() throws {
        let edited = try PDFMetadataService.write(
            PDFDocumentMetadata(), to: fixture(title: "Old", author: "A"), password: nil)
        let meta = try PDFMetadataService.read(from: edited, password: nil)
        XCTAssertNil(meta.title)
        XCTAssertNil(meta.author)
    }

    // Round-trips a non-ASCII value: the write path must encode UTF-8 into a
    // valid PDF string (UTF-16BE + BOM) the same way the read path decodes it,
    // or CJK/RTL titles corrupt silently.
    func testWritePreservesUnicode() throws {
        let edited = try PDFMetadataService.write(
            PDFDocumentMetadata(title: "折り紙", author: "うまん", subject: "विषय", keywords: "标签"),
            to: fixture(title: "Old", author: nil), password: nil)
        let meta = try PDFMetadataService.read(from: edited, password: nil)
        XCTAssertEqual(meta.title, "折り紙")
        XCTAssertEqual(meta.author, "うまん")
        XCTAssertEqual(meta.subject, "विषय")
        XCTAssertEqual(meta.keywords, "标签")
    }

    // MARK: - Workspace integration (B3)

    // `WorkspaceViewModel.undoManager` is WEAK (the window owns it in the app),
    // so the test must retain it or every registerUndo silently no-ops.
    private var retainedUndoManager: UndoManager?

    private func makeViewModel(title: String) throws -> WorkspaceViewModel {
        let wrapper = FileWrapper(regularFileWithContents: fixture(title: title, author: nil))
        wrapper.preferredFilename = "meta.pdf"
        let document = try WorkspaceDocument(testingFile: wrapper, contentType: .pdf, filename: "meta.pdf")
        let vm = WorkspaceViewModel(document: document, processingEngine: PDFiumProcessingEngine())
        let undo = UndoManager()
        retainedUndoManager = undo
        vm.undoManager = undo
        return vm
    }

    func testApplyMetadataEditFlowsThroughPreservingPipelineWithUndo() throws {
        let vm = try makeViewModel(title: "Old Title")
        let memberID = try XCTUnwrap(vm.document.workspace.pageOrder.first).memberDocId

        // Precondition: import preserved the original Info title in member bytes.
        let before = try PDFMetadataService.read(from: try XCTUnwrap(vm.document.memberPDFData[memberID]))
        XCTAssertEqual(before.title, "Old Title")

        XCTAssertTrue(vm.applyMetadataEdit(
            PDFDocumentMetadata(title: "New Title", author: "Ori"),
            alsoRemoveXMP: false
        ))

        let after = try PDFMetadataService.read(from: try XCTUnwrap(vm.document.memberPDFData[memberID]))
        XCTAssertEqual(after.title, "New Title")
        XCTAssertEqual(after.author, "Ori")

        let undo = try XCTUnwrap(vm.undoManager)
        XCTAssertTrue(undo.canUndo, "metadata edit should register an undo on vm.undoManager")
        XCTAssertFalse(undo.undoActionName.isEmpty, "undo step must carry a named action")

        undo.undo()
        let restored = try PDFMetadataService.read(from: try XCTUnwrap(vm.document.memberPDFData[memberID]))
        XCTAssertEqual(restored.title, "Old Title", "undo should restore the previous title")
        XCTAssertNil(restored.author, "undo should restore the previous (absent) author")
    }
}
