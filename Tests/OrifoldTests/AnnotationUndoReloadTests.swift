import AppKit
import PDFKit
import XCTest
@testable import Orifold

final class AnnotationUndoReloadTests: XCTestCase {
    private final class TextPageView: NSView {
        override func draw(_ dirtyRect: NSRect) {
            NSColor.white.setFill()
            dirtyRect.fill()
            ("Markup target" as NSString).draw(
                at: NSPoint(x: 72, y: 700),
                withAttributes: [
                    .font: NSFont.systemFont(ofSize: 18),
                    .foregroundColor: NSColor.black
                ]
            )
        }
    }

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

    func testCreatedHighlightUndoAndRedoRestoreExactlyOneEquivalentAnnotation() throws {
        let (viewModel, undo) = try makeTextViewModel()
        let page = try XCTUnwrap(viewModel.loadedPDFs.first?.1.page(at: 0))
        let selection = try XCTUnwrap(page.selectionForWord(at: CGPoint(x: 90, y: 710)))

        undo.beginUndoGrouping()
        XCTAssertTrue(viewModel.applyHighlight(to: selection))
        undo.endUndoGrouping()
        XCTAssertEqual(markupCount(in: viewModel, type: "Highlight"), 1)

        undo.undo()
        XCTAssertEqual(markupCount(in: viewModel, type: "Highlight"), 0)
        undo.redo()
        XCTAssertEqual(
            markupCount(in: viewModel, type: "Highlight"),
            1,
            "redo must restore one equivalent highlight without stacking duplicates"
        )
    }

    func testCreatedMarkupUndoResolvesCurrentPageAfterStructuralRestore() throws {
        let (viewModel, undo) = try makeTextViewModel()
        let page = try XCTUnwrap(viewModel.loadedPDFs.first?.1.page(at: 0))
        let selection = try XCTUnwrap(page.selectionForWord(at: CGPoint(x: 90, y: 710)))

        undo.beginUndoGrouping()
        XCTAssertTrue(viewModel.applyMarkup(.underline, to: selection))
        undo.endUndoGrouping()
        let originalPage = page

        let pageRef = try XCTUnwrap(viewModel.document.workspace.pageOrder.first)
        undo.beginUndoGrouping()
        viewModel.rotatePages([pageRef], by: 90)
        undo.endUndoGrouping()
        undo.undo()
        let restoredPage = try XCTUnwrap(viewModel.loadedPDFs.first?.1.page(at: 0))
        XCTAssertFalse(restoredPage === originalPage)
        XCTAssertEqual(markupCount(in: viewModel, type: "Underline"), 1)

        undo.undo()
        XCTAssertEqual(
            markupCount(in: viewModel, type: "Underline"),
            0,
            "creation undo must remove markup from the current live page after structure replaced PDFKit objects"
        )
        undo.redo()
        XCTAssertEqual(markupCount(in: viewModel, type: "Underline"), 1)
    }

    private func liveAnnotation(_ viewModel: WorkspaceViewModel) throws -> PDFAnnotation {
        try XCTUnwrap(viewModel.loadedPDFs.first?.1.page(at: 0)?.annotations.first { $0.type == "FreeText" })
    }

    private func markupCount(in viewModel: WorkspaceViewModel, type: String) -> Int {
        viewModel.loadedPDFs.first?.1.page(at: 0)?.annotations.filter { $0.type == type }.count ?? 0
    }

    private func makeTextViewModel() throws -> (WorkspaceViewModel, UndoManager) {
        let view = TextPageView(frame: CGRect(x: 0, y: 0, width: 612, height: 792))
        let pdf = try XCTUnwrap(PDFDocument(data: view.dataWithPDF(inside: view.bounds)))
        pdf.insert(PDFPage(), at: pdf.pageCount)
        let wrapper = FileWrapper(regularFileWithContents: try XCTUnwrap(PDFSerializer.data(from: pdf)))
        let document = try WorkspaceDocument(testingFile: wrapper, contentType: .pdf)
        let viewModel = WorkspaceViewModel(document: document)
        let undo = UndoManager()
        undo.groupsByEvent = false
        viewModel.undoManager = undo
        return (viewModel, undo)
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
