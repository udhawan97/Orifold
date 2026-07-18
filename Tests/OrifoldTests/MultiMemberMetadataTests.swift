import PDFKit
import XCTest
@testable import Orifold

/// A merged export is one PDF with one `/Info` dictionary, so assembling several
/// members must pick whose document properties survive — the export deliberately
/// adopts the first member's.
///
/// The Info inspector, however, targeted whichever member backs the currently
/// selected page. In a multi-member workspace those are different members, so a
/// user could edit page 5's document title, watch it stick in the app, and export
/// a file that still carried member 1's title. No error, no warning.
final class MultiMemberMetadataTests: XCTestCase {
    private var retainedUndoManager: UndoManager?

    private func pdfData(title: String?) throws -> Data {
        let doc = PDFDocument()
        doc.insert(PDFPage(), at: 0)
        if let title { doc.documentAttributes = [PDFDocumentAttribute.titleAttribute: title] }
        return try XCTUnwrap(doc.dataRepresentation())
    }

    /// A workspace with two members: "First" then "Second".
    private func makeTwoMemberViewModel() throws -> WorkspaceViewModel {
        let wrapper = FileWrapper(regularFileWithContents: try pdfData(title: "First Member Title"))
        wrapper.preferredFilename = "first.pdf"
        let document = try WorkspaceDocument(testingFile: wrapper, contentType: .pdf, filename: "first.pdf")
        let viewModel = WorkspaceViewModel(document: document, processingEngine: PDFiumProcessingEngine())
        let undo = UndoManager()
        retainedUndoManager = undo
        viewModel.undoManager = undo

        let secondURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Orifold-second-\(UUID().uuidString).pdf")
        try pdfData(title: "Second Member Title").write(to: secondURL)
        addTeardownBlock { try? FileManager.default.removeItem(at: secondURL) }

        viewModel.importFiles(urls: [secondURL])
        for _ in 0..<200 {
            if viewModel.document.workspace.documents.count == 2, !viewModel.isImporting { break }
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        guard viewModel.document.workspace.documents.count == 2 else {
            throw XCTSkip("async import did not complete in time")
        }
        return viewModel
    }

    // Selecting a page of the SECOND member and editing the document title must
    // still reach the exported file. The editor previously retargeted itself onto
    // the second member, whose /Info the merge then discarded.
    func testMetadataEditReachesTheExportedFileWhateverPageIsSelected() throws {
        let viewModel = try makeTwoMemberViewModel()
        let secondMemberID = viewModel.document.workspace.documents[1].id
        let secondMemberPage = try XCTUnwrap(
            viewModel.document.workspace.pageOrder.first { $0.memberDocId == secondMemberID })

        viewModel.selectedPageRefID = secondMemberPage.id
        XCTAssertTrue(viewModel.applyMetadataEdit(PDFDocumentMetadata(title: "Edited While On Page Two")))

        let snapshot = try viewModel.document.snapshot(contentType: .pdf)
        let exported = try viewModel.document.exportedPDFDataThrowing(from: snapshot)
        XCTAssertEqual(
            try PDFMetadataService.read(from: exported).title, "Edited While On Page Two",
            "the title the user edited must be the title the exported file carries")
    }

    // The editor must also SHOW the properties the export will write, or the user
    // is editing a field whose displayed value belongs to a different document.
    func testInspectorShowsTheMetadataTheExportWillWrite() throws {
        let viewModel = try makeTwoMemberViewModel()
        let secondMemberID = viewModel.document.workspace.documents[1].id
        let secondMemberPage = try XCTUnwrap(
            viewModel.document.workspace.pageOrder.first { $0.memberDocId == secondMemberID })

        viewModel.selectedPageRefID = secondMemberPage.id

        let snapshot = try viewModel.document.snapshot(contentType: .pdf)
        let exported = try viewModel.document.exportedPDFDataThrowing(from: snapshot)
        XCTAssertEqual(
            viewModel.activeDocumentMetadata()?.title,
            try PDFMetadataService.read(from: exported).title,
            "the Info tab must display the document properties the export actually writes")
    }

    // Attachments stay per-member on purpose: the export collects them from EVERY
    // member, so following the page selection is correct there. Guards against a
    // fix to the metadata targeting being over-applied to attachments.
    func testAttachmentsStillTargetTheSelectedMember() throws {
        let viewModel = try makeTwoMemberViewModel()
        let secondMemberID = viewModel.document.workspace.documents[1].id
        let secondMemberPage = try XCTUnwrap(
            viewModel.document.workspace.pageOrder.first { $0.memberDocId == secondMemberID })
        viewModel.selectedPageRefID = secondMemberPage.id

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Orifold-mm-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let payloadURL = directory.appendingPathComponent("second.txt")
        try Data("on the second member".utf8).write(to: payloadURL)

        XCTAssertTrue(viewModel.addAttachment(payloadURL))

        let secondBytes = try XCTUnwrap(viewModel.document.memberPDFData[secondMemberID])
        XCTAssertEqual(try AttachmentsService.list(in: secondBytes).map(\.name), ["second.txt"],
                       "the attachment must land on the member backing the selected page")
    }
}
