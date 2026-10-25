import AppKit
import PDFKit
import XCTest
@testable import Orifold

@MainActor
final class WorkspaceNavigationOwnershipTests: XCTestCase {
    func testForeignAnnotationCallbackCannotReplaceSelectionOrDeleteAnotherWorkspaceNote() throws {
        let (first, firstNote, _) = try makeWorkspace()
        let (second, secondNote, undo) = try makeWorkspace()
        let firstPage = try XCTUnwrap(firstNote.page)
        let secondPage = try XCTUnwrap(secondNote.page)
        let originalModified = first.document.workspace.modifiedAt
        let view = OrifoldPDFView()
        view.document = second.combinedPDF
        let coordinator = PDFViewRepresentable.Coordinator(viewModel: second)
        coordinator.pdfView = view
        second.selectedAnnotation = secondNote

        // The previous broadcast payload must be rejected even through a direct callback.
        coordinator.jumpToAnnotation(Notification(name: .orifoldJumpToAnnotation, object: firstNote))
        XCTAssertTrue(second.selectedAnnotation === secondNote)
        coordinator.jumpToAnnotation(Notification(
            name: .orifoldJumpToAnnotation, object: first, userInfo: ["payload": firstNote]
        ))
        coordinator.jumpToAnnotation(Notification(
            name: .orifoldJumpToAnnotation, object: second, userInfo: ["payload": firstNote]
        ))
        coordinator.editAnnotation(Notification(
            name: .orifoldEditAnnotation, object: second, userInfo: ["payload": firstNote]
        ))
        XCTAssertTrue(second.selectedAnnotation === secondNote)
        undo.beginUndoGrouping()
        second.deleteSelectedAnnotation()
        undo.endUndoGrouping()

        XCTAssertTrue(firstPage.annotations.contains { $0 === firstNote })
        XCTAssertFalse(secondPage.annotations.contains { $0 === secondNote })
        XCTAssertEqual(first.document.workspace.modifiedAt, originalModified)
        undo.undo()
        XCTAssertTrue(secondPage.annotations.contains { $0 === secondNote })
        XCTAssertTrue(firstPage.annotations.contains { $0 === firstNote })
    }

    func testForeignSelectionCannotMutateOrRegisterUndoInAnotherWorkspace() throws {
        let (first, note, _) = try makeWorkspace()
        let (second, _, undo) = try makeWorkspace()
        let page = try XCTUnwrap(note.page)
        let firstModified = first.document.workspace.modifiedAt
        let secondModified = second.document.workspace.modifiedAt
        second.selectedAnnotation = note

        undo.beginUndoGrouping()
        let originalUndoAction = undo.undoActionName
        second.deleteSelectedAnnotation()
        XCTAssertEqual(undo.undoActionName, originalUndoAction)
        undo.endUndoGrouping()

        XCTAssertTrue(page.annotations.contains { $0 === note })
        XCTAssertEqual(first.document.workspace.modifiedAt, firstModified)
        XCTAssertEqual(second.document.workspace.modifiedAt, secondModified)
        XCTAssertNil(second.selectedAnnotation)
    }

    func testOwnedAnnotationCallbackSelectsAndDeletesWithIndependentUndo() throws {
        let (first, note, undo) = try makeWorkspace()
        let (second, secondNote, _) = try makeWorkspace()
        let page = try XCTUnwrap(note.page)
        let view = OrifoldPDFView()
        view.document = first.combinedPDF
        let coordinator = PDFViewRepresentable.Coordinator(viewModel: first)
        coordinator.pdfView = view
        second.selectedAnnotation = secondNote
        coordinator.jumpToAnnotation(Notification(
            name: .orifoldJumpToAnnotation, object: first, userInfo: ["payload": note]
        ))
        XCTAssertTrue(first.selectedAnnotation === note)
        XCTAssertTrue(second.selectedAnnotation === secondNote)
        undo.beginUndoGrouping()
        first.deleteSelectedAnnotation()
        undo.endUndoGrouping()
        XCTAssertFalse(page.annotations.contains { $0 === note })
        undo.undo()
        XCTAssertTrue(page.annotations.contains { $0 === note })
    }

    private func makeWorkspace() throws -> (WorkspaceViewModel, PDFAnnotation, UndoManager) {
        let pdf = PDFDocument()
        pdf.insert(PDFPage(), at: 0)
        let wrapper = FileWrapper(regularFileWithContents: try XCTUnwrap(PDFSerializer.data(from: pdf)))
        let document = try WorkspaceDocument(testingFile: wrapper, contentType: .pdf)
        let viewModel = WorkspaceViewModel(document: document)
        let page = try XCTUnwrap(viewModel.loadedPDFs.first?.1.page(at: 0))
        let note = PDFAnnotation(bounds: CGRect(x: 20, y: 20, width: 24, height: 24),
                                 forType: .text, withProperties: nil)
        note.contents = "Fictional note"
        page.addAnnotation(note)
        let undo = UndoManager()
        undo.groupsByEvent = false
        viewModel.undoManager = undo
        return (viewModel, note, undo)
    }
}
