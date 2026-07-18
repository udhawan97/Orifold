import PDFKit
import XCTest
@testable import Orifold

/// Metadata edits and attachment edits are two callers of ONE member-byte
/// mutation flow: transform every present byte lane (live + pristine replay base
/// + object-edit base), commit atomically, and register one isolated undo step
/// whose inverse re-registers itself for redo.
///
/// These pin the parts of that contract the per-feature suites don't reach —
/// redo restoring actual bytes (not just the revision counter), removal undo,
/// and the isolation between two different mutations' undo steps. They are the
/// safety net for unifying the two flows: both callers must keep behaving
/// identically through the shared module.
final class MemberByteMutationTests: XCTestCase {
    // `WorkspaceViewModel.undoManager` is WEAK (the window owns it in the app),
    // so the test must retain it or every registerUndo silently no-ops.
    private var retainedUndoManager: UndoManager?

    private func fixture(title: String?) -> Data {
        let doc = PDFDocument()
        doc.insert(PDFPage(), at: 0)
        if let title { doc.documentAttributes = [PDFDocumentAttribute.titleAttribute: title] }
        return doc.dataRepresentation()!  // fixture creation only — never product code
    }

    private func makeViewModel(title: String? = nil) throws -> WorkspaceViewModel {
        let wrapper = FileWrapper(regularFileWithContents: fixture(title: title))
        wrapper.preferredFilename = "member.pdf"
        let document = try WorkspaceDocument(testingFile: wrapper, contentType: .pdf, filename: "member.pdf")
        let viewModel = WorkspaceViewModel(document: document, processingEngine: PDFiumProcessingEngine())
        let undo = UndoManager()
        retainedUndoManager = undo
        viewModel.undoManager = undo
        return viewModel
    }

    private func writeTempFile(_ data: Data, name: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Orifold-member-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    private func liveBytes(_ viewModel: WorkspaceViewModel) throws -> Data {
        let memberID = try XCTUnwrap(viewModel.document.workspace.documents.first?.id)
        return try XCTUnwrap(viewModel.document.memberPDFData[memberID])
    }

    // The existing metadata suite asserts redo bumps `structureRevision`, but not
    // that redo restores the edited BYTES. The recursive-inverse undo is what makes
    // redo work at all: each application registers the undo that restores the other
    // state, so a refactor that registered a plain (non-recursive) undo would still
    // pass the counter assertion while leaving redo a no-op on the document.
    func testMetadataRedoRestoresEditedBytesAfterUndo() throws {
        let viewModel = try makeViewModel(title: "Old Title")
        XCTAssertTrue(viewModel.applyMetadataEdit(PDFDocumentMetadata(title: "New Title", author: "Ori")))
        XCTAssertEqual(try PDFMetadataService.read(from: try liveBytes(viewModel)).title, "New Title")

        let undo = try XCTUnwrap(viewModel.undoManager)
        undo.undo()
        XCTAssertEqual(
            try PDFMetadataService.read(from: try liveBytes(viewModel)).title, "Old Title",
            "undo should restore the pre-edit title")

        undo.redo()
        let redone = try PDFMetadataService.read(from: try liveBytes(viewModel))
        XCTAssertEqual(redone.title, "New Title", "redo should re-apply the edited title to the member bytes")
        XCTAssertEqual(redone.author, "Ori", "redo should re-apply every edited field, not just the first")
    }

    // The attachments suite covers add+undo; removal is the other direction through
    // the same flow and carries an extra subtlety — its transform deliberately
    // no-ops lanes that don't carry the key (qpdf errors on removing a missing
    // one), so removal must still register a working undo.
    func testRemoveAttachmentUndoRestoresTheAttachment() throws {
        let viewModel = try makeViewModel()
        let payloadURL = try writeTempFile(Data("attach-me".utf8), name: "note.txt")
        defer { try? FileManager.default.removeItem(at: payloadURL.deletingLastPathComponent()) }

        XCTAssertTrue(viewModel.addAttachment(payloadURL))
        XCTAssertEqual(try AttachmentsService.list(in: try liveBytes(viewModel)).map(\.name), ["note.txt"])

        XCTAssertTrue(viewModel.removeAttachment(named: "note.txt"))
        XCTAssertEqual(try AttachmentsService.list(in: try liveBytes(viewModel)), [],
                       "removal should drop the attachment from the live member bytes")

        let undo = try XCTUnwrap(viewModel.undoManager)
        undo.undo()
        XCTAssertEqual(try AttachmentsService.list(in: try liveBytes(viewModel)).map(\.name), ["note.txt"],
                       "undoing a removal should restore the attachment")
    }

    // Metadata and attachment edits are separate features sharing one mutation
    // flow. Each must remain its OWN atomic undo step: undoing the attachment must
    // not also revert the metadata edit that preceded it. This is the invariant a
    // unification is most likely to break — one shared undo registration, or a
    // snapshot capturing more state than the edit touched, collapses the two steps
    // into one and silently loses a user edit on Cmd+Z.
    func testMetadataAndAttachmentEditsAreSeparateAtomicUndoSteps() throws {
        let viewModel = try makeViewModel(title: "Old Title")
        let payloadURL = try writeTempFile(Data("attach-me".utf8), name: "note.txt")
        defer { try? FileManager.default.removeItem(at: payloadURL.deletingLastPathComponent()) }

        XCTAssertTrue(viewModel.applyMetadataEdit(PDFDocumentMetadata(title: "New Title")))
        XCTAssertTrue(viewModel.addAttachment(payloadURL))

        let undo = try XCTUnwrap(viewModel.undoManager)
        undo.undo()  // peels the attachment only

        let afterFirstUndo = try liveBytes(viewModel)
        XCTAssertEqual(try AttachmentsService.list(in: afterFirstUndo), [],
                       "the first undo should remove the attachment")
        XCTAssertEqual(try PDFMetadataService.read(from: afterFirstUndo).title, "New Title",
                       "undoing the attachment must NOT revert the earlier metadata edit")

        undo.undo()  // peels the metadata edit
        XCTAssertEqual(try PDFMetadataService.read(from: try liveBytes(viewModel)).title, "Old Title",
                       "the second undo should revert the metadata edit")
    }
}
