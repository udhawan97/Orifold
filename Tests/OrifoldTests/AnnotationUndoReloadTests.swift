import AppKit
import PDFKit
import XCTest
@testable import Orifold

final class AnnotationUndoReloadTests: XCTestCase {
    func testAnnotationEditUndoAndRedoResolveTheLiveAnnotationAfterStructuralUndo() throws {
        let (viewModel, undo) = try makeViewModel()
        let page = try XCTUnwrap(viewModel.loadedPDFs.first?.1.page(at: 0))
        let note = PDFAnnotation(bounds: CGRect(x: 20, y: 20, width: 120, height: 40),
                                 forType: .freeText, withProperties: nil)
        note.contents = "Original"
        page.addAnnotation(note)
        let before = PDFAnnotationEditSnapshot(annotation: note)
        note.contents = "Changed"
        undo.beginUndoGrouping()
        viewModel.registerAnnotationEdit(note, from: before, actionName: "Edit note")
        undo.endUndoGrouping()
        undo.beginUndoGrouping()
        viewModel.deletePage(try XCTUnwrap(viewModel.document.workspace.pageOrder.last))
        undo.endUndoGrouping()
        undo.undo()
        XCTAssertEqual(try liveAnnotation(viewModel).contents, "Changed")
        XCTAssertFalse(try liveAnnotation(viewModel) === note)
        undo.undo()
        XCTAssertEqual(try liveAnnotation(viewModel).contents, "Original")
        undo.redo()
        XCTAssertEqual(try liveAnnotation(viewModel).contents, "Changed")
        undo.redo()
        XCTAssertEqual(viewModel.document.workspace.pageOrder.count, 1)
        XCTAssertEqual(try liveAnnotation(viewModel).contents, "Changed")
        let saved = try viewModel.document.savedFileWrapper(from: viewModel.document.snapshot(contentType: .pdf))
        let reopened = try WorkspaceDocument(testingFile: saved, contentType: .pdf)
        let bytes = try XCTUnwrap(reopened.memberPDFData.values.first)
        XCTAssertTrue(try XCTUnwrap(PDFDocument(data: bytes)?.page(at: 0)).annotations.contains { $0.contents == "Changed" })
    }

    func testRemovedNoteUndoAndRedoResolveTheLivePageAfterStructuralUndo() throws {
        let (viewModel, undo) = try makeViewModel()
        let page = try XCTUnwrap(viewModel.loadedPDFs.first?.1.page(at: 0))
        let note = PDFAnnotation(bounds: CGRect(x: 20, y: 20, width: 24, height: 24),
                                 forType: .text, withProperties: nil)
        note.contents = "Restore me"
        page.addAnnotation(note)
        let item = try XCTUnwrap(viewModel.pdfNoteComments.first)
        undo.beginUndoGrouping()
        viewModel.removeNoteComment(item)
        undo.endUndoGrouping()
        undo.beginUndoGrouping()
        viewModel.deletePage(try XCTUnwrap(viewModel.document.workspace.pageOrder.last))
        undo.endUndoGrouping()
        undo.undo()
        XCTAssertTrue(viewModel.pdfNoteComments.isEmpty)
        undo.undo()
        XCTAssertEqual(viewModel.pdfNoteComments.first?.body, "Restore me")
        undo.redo()
        XCTAssertTrue(viewModel.pdfNoteComments.isEmpty)
        undo.redo()
        XCTAssertEqual(viewModel.document.workspace.pageOrder.count, 1)
    }

    private func liveAnnotation(_ viewModel: WorkspaceViewModel) throws -> PDFAnnotation {
        try XCTUnwrap(viewModel.loadedPDFs.first?.1.page(at: 0)?.annotations.first { $0.type == "FreeText" })
    }

    private func makeViewModel() throws -> (WorkspaceViewModel, UndoManager) {
        let pdf = PDFDocument()
        pdf.insert(PDFPage(), at: 0)
        pdf.insert(PDFPage(), at: 1)
        let wrapper = FileWrapper(regularFileWithContents: try XCTUnwrap(PDFSerializer.data(from: pdf)))
        let document = try WorkspaceDocument(testingFile: wrapper, contentType: .pdf)
        let viewModel = WorkspaceViewModel(document: document)
        let undo = UndoManager()
        undo.groupsByEvent = false
        viewModel.undoManager = undo
        return (viewModel, undo)
    }
}
