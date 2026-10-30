import AppKit
import Crypto
import X509
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
        XCTAssertEqual(secondPage.annotations.filter { $0.contents == "Fictional note" }.count, 1)
        XCTAssertTrue(firstPage.annotations.contains { $0 === firstNote })
    }

    func testForeignSelectionCannotMutateOrRegisterUndoInAnotherWorkspace() throws {
        let (first, note, _) = try makeWorkspace()
        let (second, _, undo) = try makeWorkspace()
        let page = try XCTUnwrap(note.page)
        let firstModified = first.document.workspace.modifiedAt
        let secondModified = second.document.workspace.modifiedAt
        second.selectedAnnotation = note

        let originalUndoAction = undo.undoActionName
        second.deleteSelectedAnnotation()
        XCTAssertEqual(undo.undoActionName, originalUndoAction)

        XCTAssertTrue(page.annotations.contains { $0 === note })
        XCTAssertEqual(first.document.workspace.modifiedAt, firstModified)
        XCTAssertEqual(second.document.workspace.modifiedAt, secondModified)
        XCTAssertNil(second.selectedAnnotation)
        XCTAssertFalse(undo.canUndo)
        XCTAssertFalse(undo.canRedo)
    }

    func testAllForeignNavigationCallbacksLeaveTheReceivingCanvasUnchanged() throws {
        let (first, firstNote, _) = try makeWorkspace()
        let (second, secondNote, _) = try makeWorkspace()
        let view = OrifoldPDFView(frame: CGRect(x: 0, y: 0, width: 600, height: 800))
        view.document = second.combinedPDF
        let coordinator = PDFViewRepresentable.Coordinator(viewModel: second)
        coordinator.pdfView = view
        second.selectedAnnotation = secondNote
        let page = try XCTUnwrap(view.currentPage)
        let selection = PDFSelection(document: second.combinedPDF)
        view.setCurrentSelection(selection, animate: false)
        let currentSelection = view.currentSelection
        let form = PDFFormFieldNavigationTarget(pageIndex: 0, bounds: .zero,
                                                fieldType: PDFAnnotationWidgetSubtype.button.rawValue)
        let callbacks: [(Notification.Name, Any, (Notification) -> Void)] = [
            (.orifoldJumpToSelection, PDFSelection(document: first.combinedPDF), coordinator.jumpToSelection),
            (.orifoldJumpToPageIndex, 0, coordinator.jumpToPageIndex),
            (.orifoldJumpToFormField, form, coordinator.jumpToFormField),
            (.orifoldJumpToAnnotation, firstNote, coordinator.jumpToAnnotation),
            (.orifoldEditAnnotation, firstNote, coordinator.editAnnotation),
        ]
        for (name, payload, callback) in callbacks {
            callback(Notification(name: name, object: first, userInfo: ["payload": payload]))
            XCTAssertTrue(view.currentPage === page, name.rawValue)
            XCTAssertTrue(view.currentSelection === currentSelection, name.rawValue)
            XCTAssertTrue(second.selectedAnnotation === secondNote, name.rawValue)
        }
    }

    func testForeignEditorCannotMutateOrDirtyEitherWorkspaceOrRegisterUndo() throws {
        let (first, note, firstUndo) = try makeWorkspace()
        let (second, _, secondUndo) = try makeWorkspace()
        let firstModified = first.document.workspace.modifiedAt
        let secondModified = second.document.workspace.modifiedAt
        let before = PDFAnnotationEditSnapshot(annotation: note)
        let controller = NoteEditorViewController(
            annotation: note,
            changeHandler: { annotation, snapshot, actionName in
                second.registerAnnotationEdit(annotation, from: snapshot, actionName: actionName)
            },
            canMutate: { second.ownsAnnotation(note) }
        )
        controller.loadViewIfNeeded()
        let textView = try XCTUnwrap(descendant(NSTextView.self, in: controller.view))
        textView.string = "Foreign edit must be rejected"
        controller.viewWillDisappear()
        second.registerAnnotationEdit(note, from: before, actionName: "Foreign edit")
        XCTAssertEqual(note.contents, "Fictional note")
        XCTAssertEqual(first.document.workspace.modifiedAt, firstModified)
        XCTAssertEqual(second.document.workspace.modifiedAt, secondModified)
        XCTAssertFalse(firstUndo.canUndo)
        XCTAssertFalse(secondUndo.canUndo)
        XCTAssertFalse(secondUndo.canRedo)
    }

    func testEditorRechecksOwnershipBeforeDismissalAfterAnnotationDetaches() throws {
        let (workspace, note, undo) = try makeWorkspace()
        let page = try XCTUnwrap(note.page)
        let controller = NoteEditorViewController(
            annotation: note,
            changeHandler: { annotation, snapshot, actionName in
                workspace.registerAnnotationEdit(annotation, from: snapshot, actionName: actionName)
            },
            canMutate: { workspace.ownsAnnotation(note) }
        )
        controller.loadViewIfNeeded()
        let textView = try XCTUnwrap(descendant(NSTextView.self, in: controller.view))
        textView.string = "Stale edit must be rejected"
        page.removeAnnotation(note)
        controller.viewWillDisappear()
        XCTAssertEqual(note.contents, "Fictional note")
        XCTAssertFalse(undo.canUndo)
    }

    func testOwnedNoteEditorSupportsIndependentUndoAndRedo() throws {
        let (first, note, undo) = try makeWorkspace()
        let (second, secondNote, secondUndo) = try makeWorkspace()
        let secondModified = second.document.workspace.modifiedAt
        let controller = NoteEditorViewController(
            annotation: note,
            changeHandler: { annotation, snapshot, actionName in
                first.registerAnnotationEdit(annotation, from: snapshot, actionName: actionName)
            },
            canMutate: { first.ownsAnnotation(note) }
        )
        controller.loadViewIfNeeded()
        let textView = try XCTUnwrap(descendant(NSTextView.self, in: controller.view))
        textView.string = "Edited fictional note"
        undo.beginUndoGrouping()
        controller.viewWillDisappear()
        undo.endUndoGrouping()
        XCTAssertEqual(note.contents, "Edited fictional note")
        undo.undo()
        XCTAssertEqual(note.contents, "Fictional note")
        undo.redo()
        XCTAssertEqual(note.contents, "Edited fictional note")
        XCTAssertEqual(secondNote.contents, "Fictional note")
        XCTAssertEqual(second.document.workspace.modifiedAt, secondModified)
        XCTAssertFalse(secondUndo.canUndo)
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
        XCTAssertEqual(page.annotations.filter { $0.contents == "Fictional note" }.count, 1)
        XCTAssertTrue(first.ownsAnnotation(try XCTUnwrap(first.selectedAnnotation)))
        undo.redo()
        XCTAssertFalse(page.annotations.contains { $0.contents == "Fictional note" })
        undo.undo()
        XCTAssertEqual(page.annotations.filter { $0.contents == "Fictional note" }.count, 1)
        XCTAssertTrue(secondNote.page?.annotations.contains { $0 === secondNote } == true)
    }

    func testSelectedNoteDeletionUndoAndRedoResolveCurrentPageAfterEachStructuralRestore() throws {
        for operation in ["move", "delete", "duplicate"] {
            let (workspace, note, undo) = try makeWorkspace(type: .freeText)
            let originalPage = try XCTUnwrap(note.page)
            let ref = try XCTUnwrap(workspace.document.workspace.pageOrder.first)
            workspace.selectedAnnotation = note
            undo.beginUndoGrouping()
            workspace.deleteSelectedAnnotation()
            undo.endUndoGrouping()
            undo.beginUndoGrouping()
            switch operation {
            case "move": XCTAssertTrue(workspace.movePage(ref, toIndex: 2))
            case "delete": workspace.deletePage(try XCTUnwrap(workspace.document.workspace.pageOrder.last))
            default: workspace.duplicatePages([ref])
            }
            undo.endUndoGrouping()
            undo.undo()
            let livePage = try XCTUnwrap(workspace.loadedPDFs.first?.1.page(at: 0))
            XCTAssertFalse(livePage === originalPage, operation)
            XCTAssertFalse(livePage.annotations.contains { $0.contents == "Fictional note" }, operation)
            undo.undo()
            let restored = try XCTUnwrap(livePage.annotations.first { $0.contents == "Fictional note" }, operation)
            XCTAssertTrue(workspace.selectedAnnotation === restored, operation)
            XCTAssertTrue(workspace.ownsAnnotation(restored), operation)
            XCTAssertGreaterThan(try exportedDarkPixelCount(workspace), 0, operation)
            let saved = try workspace.document.savedFileWrapper(from: workspace.document.snapshot(contentType: .pdf))
            let reopened = try WorkspaceDocument(testingFile: saved, contentType: .pdf)
            let savedPage = try XCTUnwrap(PDFDocument(data: try XCTUnwrap(reopened.memberPDFData.values.first))?.page(at: 0))
            XCTAssertEqual(savedPage.annotations.filter { $0.contents == "Fictional note" }.count, 1, operation)
            undo.redo()
            XCTAssertFalse(livePage.annotations.contains { $0.contents == "Fictional note" }, operation)
            XCTAssertEqual(try exportedDarkPixelCount(workspace), 0, operation)
            undo.undo()
            XCTAssertEqual(livePage.annotations.filter { $0.contents == "Fictional note" }.count, 1, operation)
        }
    }

    func testSignatureDeletionRestoresPlacementAnnotationAndCachedIdentityExactlyOnceAfterStructuralUndo() throws {
        let (workspace, note, undo) = try makeWorkspace()
        let page = try XCTUnwrap(note.page)
        page.removeAnnotation(note)
        let image = try SignatureAppearanceRenderer.pngData(
            for: .typedName("Fictional Signer"), size: CGSize(width: 240, height: 80), scale: 2
        )
        workspace.beginCryptographicSignaturePlacement(
            imageData: image, signerName: "Fictional Signer", signerIdentityRef: "fictional identity",
            reason: "Review", location: "Fixture", contactInfo: "fictional@example.invalid",
            timestampRequested: false, identity: try expiredIdentity(), certificateProfileID: nil
        )
        undo.beginUndoGrouping()
        let annotation = try XCTUnwrap(workspace.placeSignature(imageData: image, at: CGPoint(x: 200, y: 200), on: page))
        undo.endUndoGrouping()
        undo.removeAllActions()
        let placement = try XCTUnwrap(workspace.document.workspace.signatures.first)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let expectedPlacement = try encoder.encode(placement)
        undo.beginUndoGrouping()
        workspace.deleteSelectedAnnotation()
        undo.endUndoGrouping()
        XCTAssertTrue(workspace.document.workspace.signatures.isEmpty)
        let annotationID = try XCTUnwrap(annotation.value(forAnnotationKey: PDFAnnotationKey(rawValue: "/OrifoldAnnotationID")) as? String)
        undo.beginUndoGrouping()
        workspace.deletePage(try XCTUnwrap(workspace.document.workspace.pageOrder.last))
        undo.endUndoGrouping()
        undo.undo()
        let livePage = try XCTUnwrap(workspace.loadedPDFs.first?.1.page(at: 0))
        XCTAssertFalse(livePage === page)
        for _ in 0..<2 {
            undo.undo()
            let restored = try XCTUnwrap(livePage.annotations.first { workspace.signaturePlacementID(for: $0) == placement.id })
            XCTAssertFalse(restored === annotation)
            XCTAssertTrue(workspace.selectedAnnotation === restored)
            XCTAssertTrue(workspace.ownsAnnotation(restored))
            XCTAssertEqual(restored.value(forAnnotationKey: PDFAnnotationKey(rawValue: "/OrifoldAnnotationID")) as? String, annotationID)
            XCTAssertEqual(livePage.annotations.filter { workspace.signaturePlacementID(for: $0) == placement.id }.count, 1)
            XCTAssertEqual(workspace.document.workspace.signatures.count, 1)
            XCTAssertEqual(try encoder.encode(try XCTUnwrap(workspace.document.workspace.signatures.first)), expectedPlacement)
            XCTAssertEqual(restored.value(forAnnotationKey: WorkspaceViewModel.signaturePlacementAnnotationKey) as? String,
                           placement.id.uuidString)
            workspace.exportError = nil
            workspace.signAndExportCryptographicPDF(timestampRequested: false)
            XCTAssertEqual(workspace.exportError?.message, L10n.string("error.export.identityExpired"),
                           "the restored in-memory identity must resolve without a Keychain/profile fallback")
            XCTAssertGreaterThan(try exportedDarkPixelCount(workspace), 0)
            undo.redo()
            XCTAssertTrue(workspace.document.workspace.signatures.isEmpty)
            XCTAssertFalse(livePage.annotations.contains { workspace.signaturePlacementID(for: $0) == placement.id })
            XCTAssertEqual(try exportedDarkPixelCount(workspace), 0)
        }
    }

    private struct ExpiredIdentity: SigningIdentity {
        let certificate: Certificate
        let chain: [Certificate] = []
        let signatureAlgorithm: SignatureAlgorithm = .ecdsaP256SHA256
        func sign(_ data: Data) throws -> Data {
            XCTFail("an expired fixture identity must never sign")
            return Data()
        }
    }

    private func expiredIdentity() throws -> ExpiredIdentity {
        let key = Certificate.PrivateKey(P256.Signing.PrivateKey())
        let name = try DistinguishedName { CommonName("Fictional expired fixture") }
        return ExpiredIdentity(certificate: try Certificate(
            version: .v3, serialNumber: .init(), publicKey: key.publicKey,
            notValidBefore: Date().addingTimeInterval(-259200),
            notValidAfter: Date().addingTimeInterval(-86400), issuer: name, subject: name,
            signatureAlgorithm: .ecdsaWithSHA256,
            extensions: Certificate.Extensions {
                Critical(BasicConstraints.notCertificateAuthority)
                Critical(KeyUsage(digitalSignature: true, nonRepudiation: true))
            }, issuerPrivateKey: key
        ))
    }

    private func exportedDarkPixelCount(_ workspace: WorkspaceViewModel) throws -> Int {
        let pdf = try XCTUnwrap(PDFDocument(data: workspace.dataForPDFExport()))
        let page = try XCTUnwrap(pdf.page(at: 0))
        let image = page.thumbnail(of: NSSize(width: 306, height: 396), for: .mediaBox)
        let pixels = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation)))
        var count = 0
        for y in 0..<pixels.pixelsHigh {
            for x in 0..<pixels.pixelsWide {
                guard let color = pixels.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                if color.alphaComponent > 0.5, min(color.redComponent, color.greenComponent, color.blueComponent) < 0.5 {
                    count += 1
                }
            }
        }
        return count
    }

    private func descendant<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
        if let match = view as? T { return match }
        return view.subviews.lazy.compactMap { self.descendant(type, in: $0) }.first
    }

    private func makeWorkspace(type: PDFAnnotationSubtype = .text) throws -> (WorkspaceViewModel, PDFAnnotation, UndoManager) {
        let pdf = PDFDocument()
        pdf.insert(PDFPage(), at: 0)
        pdf.insert(PDFPage(), at: 1)
        let wrapper = FileWrapper(regularFileWithContents: try XCTUnwrap(PDFSerializer.data(from: pdf)))
        let document = try WorkspaceDocument(testingFile: wrapper, contentType: .pdf)
        let viewModel = WorkspaceViewModel(document: document)
        let page = try XCTUnwrap(viewModel.loadedPDFs.first?.1.page(at: 0))
        let note = PDFAnnotation(bounds: CGRect(x: 20, y: 20, width: 24, height: 24),
                                 forType: type, withProperties: nil)
        note.contents = "Fictional note"
        if type == .freeText {
            note.bounds = CGRect(x: 20, y: 20, width: 200, height: 40)
            note.font = .systemFont(ofSize: 18)
            note.fontColor = .black
            note.color = .clear
        }
        page.addAnnotation(note)
        let undo = UndoManager()
        undo.groupsByEvent = false
        viewModel.undoManager = undo
        return (viewModel, note, undo)
    }
}
