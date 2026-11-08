import AppKit
import Observation
import Crypto
import X509
import PDFKit
import XCTest
@testable import Orifold

@MainActor
final class WorkspaceNavigationOwnershipTests: XCTestCase {
    private lazy var fingerprintStore: WorkspaceFingerprintStore = {
        let temporaryRoot = ProcessInfo.processInfo.environment["TMPDIR"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) } ?? FileManager.default.temporaryDirectory
        let directory = temporaryRoot.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return WorkspaceFingerprintStore(directory: directory)
    }()

    func testNoteUndoAndRedoInvalidateObservedControlsWithoutChangingFocusOrRebuilding() throws {
        let (owner, note, manager) = try makeWorkspace()
        let revision = owner.structureRevision
        let title = "Edit fictional note"
        let commandChanged = observeUndoControls(owner)
        let snapshot = PDFAnnotationEditSnapshot(annotation: note)
        manager.beginUndoGrouping()
        note.contents = "Revised"
        owner.registerAnnotationEdit(note, from: snapshot, actionName: title)
        manager.endUndoGrouping()
        wait(for: [commandChanged], timeout: 1)
        XCTAssertEqual(owner.undoManagerForControls?.undoActionName, title)
        XCTAssertTrue(owner.undoManagerForControls?.canUndo == true)
        XCTAssertFalse(owner.undoManagerForControls?.canRedo == true)

        let undoChanged = observeUndoControls(owner)
        owner.performUndoCommand()
        wait(for: [undoChanged], timeout: 1)
        XCTAssertEqual(note.contents, "Fictional note")
        XCTAssertEqual(owner.undoManagerForControls?.redoActionName, title)
        XCTAssertTrue(owner.undoManagerForControls?.canRedo == true)
        XCTAssertFalse(owner.undoManagerForControls?.canUndo == true)

        let redoChanged = observeUndoControls(owner)
        owner.performRedoCommand()
        wait(for: [redoChanged], timeout: 1)
        XCTAssertEqual(note.contents, "Revised")
        XCTAssertTrue(owner.undoManagerForControls?.canUndo == true)
        XCTAssertFalse(owner.undoManagerForControls?.canRedo == true)
        XCTAssertEqual(owner.structureRevision, revision)
    }

    func testUndoControlObservationFollowsManagerReplacementAndIgnoresThePreviousWindow() throws {
        let (owner, _, previous) = try makeWorkspace()
        let (other, _, otherManager) = try makeWorkspace()
        let replacement = UndoManager()
        replacement.groupsByEvent = false

        let rebound = observeUndoControls(owner)
        owner.undoManager = replacement
        wait(for: [rebound], timeout: 1)
        let unaffectedOwner = observeUndoControls(owner)
        unaffectedOwner.isInverted = true
        owner.undoManager = replacement
        recordUndo(on: previous, name: "Previous")
        recordUndo(on: otherManager, name: "Other window")
        wait(for: [unaffectedOwner], timeout: 0.03)
        XCTAssertFalse(owner.undoManagerForControls?.canUndo == true)
        XCTAssertEqual(other.undoManagerForControls?.undoActionName, "Other window")

        let current = observeUndoControls(owner)
        recordUndo(on: replacement, name: "Replacement")
        wait(for: [current], timeout: 1)
        XCTAssertEqual(owner.undoManagerForControls?.undoActionName, "Replacement")
        let cleared = observeUndoControls(owner)
        owner.undoManager = nil
        wait(for: [cleared], timeout: 1)
        XCTAssertNil(owner.undoManagerForControls)
    }

    private func observeUndoControls(_ owner: WorkspaceViewModel) -> XCTestExpectation {
        let changed = XCTestExpectation(description: "Update the workspace's Undo and Redo controls")
        withObservationTracking {
            _ = owner.undoManagerForControls?.canRedo
        } onChange: {
            changed.fulfill()
        }
        return changed
    }

    private func recordUndo(on manager: UndoManager, name: String) {
        manager.beginUndoGrouping()
        manager.registerUndo(withTarget: self) { _ in }
        manager.setActionName(name)
        manager.endUndoGrouping()
    }

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

    func testEmptyDraftDismissalRefreshesOnlyTheOwningWorkspace() throws {
        let (owner, draft, _) = try makeWorkspace()
        let (other, _, otherUndo) = try makeWorkspace()
        let page = try XCTUnwrap(draft.page)
        draft.contents = ""
        draft.setValue(true, forAnnotationKey: WorkspaceViewModel.draftTextAnnotationKey)
        owner.selectedAnnotation = draft
        let ownerRevision = owner.commentRevision
        let otherRevision = other.commentRevision
        other.discardDraftAnnotation(draft)
        XCTAssertTrue(owner.ownsAnnotation(draft))
        XCTAssertEqual(other.commentRevision, otherRevision)
        XCTAssertFalse(otherUndo.canUndo)

        let editor = NoteEditorViewController(
            annotation: draft, discardDraft: owner.discardDraftAnnotation,
            canMutate: { owner.ownsAnnotation(draft) }
        )
        editor.loadViewIfNeeded()
        editor.viewWillDisappear()
        XCTAssertFalse(page.annotations.contains { $0 === draft })
        XCTAssertNil(owner.selectedAnnotation)
        XCTAssertGreaterThan(owner.commentRevision, ownerRevision)
        XCTAssertEqual(other.commentRevision, otherRevision)
    }

    func testBusyWorkspaceKeepsNoteEditsAndDraftDismissalPendingUntilRetry() throws {
        let (owner, note, undo) = try makeWorkspace()
        let (other, _, otherUndo) = try makeWorkspace()
        let baseline = owner.commentRevision
        let editor = NoteEditorViewController(
            annotation: note, changeHandler: owner.registerAnnotationEdit,
            discardDraft: owner.discardDraftAnnotation, canMutate: { owner.canEditAnnotation(note) }
        )
        var closed = false
        editor.closeHandler = { closed = true }
        editor.loadViewIfNeeded()
        let text = try XCTUnwrap(descendant(NSTextView.self, in: editor.view))
        text.string = "Pending fictional change"
        let done = try XCTUnwrap(editor.view.subviews.flatMap(\.subviews)
            .compactMap { $0 as? NSButton }.first { $0.keyEquivalent == "\r" })

        owner.setProcessingStateForTesting(compressionActive: true)
        done.performClick(nil)
        editor.viewWillDisappear()
        XCTAssertFalse(closed)
        XCTAssertEqual(note.contents, "Fictional note")
        XCTAssertEqual(owner.commentRevision, baseline)
        XCTAssertFalse(undo.canUndo)
        owner.setProcessingStateForTesting()
        undo.beginUndoGrouping()
        done.performClick(nil)
        undo.endUndoGrouping()
        XCTAssertTrue(closed)
        XCTAssertEqual(note.contents, "Pending fictional change")
        undo.undo()
        XCTAssertEqual(note.contents, "Fictional note")
        XCTAssertFalse(otherUndo.canUndo)
        XCTAssertEqual(other.commentRevision, 0)

        note.contents = ""
        note.setValue(true, forAnnotationKey: WorkspaceViewModel.draftTextAnnotationKey)
        let draftEditor = NoteEditorViewController(
            annotation: note, discardDraft: owner.discardDraftAnnotation,
            canMutate: { owner.canEditAnnotation(note) }
        )
        closed = false
        draftEditor.closeHandler = { closed = true }
        draftEditor.loadViewIfNeeded()
        let cancel = try XCTUnwrap(draftEditor.view.subviews.flatMap(\.subviews)
            .compactMap { $0 as? NSButton }.first { $0.keyEquivalent == "\u{1b}" })
        owner.setProcessingStateForTesting(ocrActive: true)
        cancel.performClick(nil)
        XCTAssertFalse(closed)
        XCTAssertTrue(owner.ownsAnnotation(note))
        XCTAssertFalse(owner.discardDraftAnnotation(note))
        owner.setProcessingStateForTesting()
        cancel.performClick(nil)
        XCTAssertTrue(closed)
        XCTAssertFalse(owner.ownsAnnotation(note))
        XCTAssertFalse(otherUndo.canUndo)
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
            let reopened = try WorkspaceDocument(testingFile: saved, contentType: .pdf, fingerprintStore: fingerprintStore)
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
        let document = try WorkspaceDocument(testingFile: wrapper, contentType: .pdf, fingerprintStore: fingerprintStore)
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
