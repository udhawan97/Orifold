import AppKit
import CoreGraphics
import CoreText
import PDFKit
import XCTest
@testable import Orifold

/// Phase 2 (docs/OBJECT_EDITING_PLAN.md §8.3) — the WorkspaceViewModel commit lifecycle:
/// select → applyObjectEdit → live member bytes update → undo/redo, all byte-exact.
final class ObjectEditWorkspaceTests: XCTestCase {

    private let imagePDF = CGRect(x: 380, y: 560, width: 60, height: 60)
    private let deleteRect = CGRect(x: 120, y: 120, width: 150, height: 60)

    private func makeFixture() -> Data {
        let data = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        let ctx = CGContext(consumer: CGDataConsumer(data: data as CFMutableData)!, mediaBox: &mediaBox, nil)!
        ctx.beginPDFPage(nil)
        ctx.setFillColor(NSColor.white.cgColor); ctx.fill(mediaBox)
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.setStrokeColor(NSColor.systemGray.cgColor)
        ctx.setLineWidth(2)
        ctx.addRect(deleteRect)
        ctx.drawPath(using: .fillStroke)
        let img = CGContext(data: nil, width: 24, height: 24, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        img.setFillColor(NSColor.systemRed.cgColor); img.fill(CGRect(x: 0, y: 0, width: 24, height: 24))
        ctx.draw(img.makeImage()!, in: imagePDF)
        ctx.endPDFPage(); ctx.closePDF()
        return data as Data
    }

    private func near(_ a: CGRect, _ b: CGRect, tol: CGFloat = 4) -> Bool {
        abs(a.minX - b.minX) <= tol && abs(a.minY - b.minY) <= tol && abs(a.width - b.width) <= tol && abs(a.height - b.height) <= tol
    }

    // `WorkspaceViewModel.undoManager` is WEAK (the window owns it in the app), so the test must
    // retain it or it deallocates immediately and every registerUndo silently no-ops.
    private var retainedUndoManager: UndoManager?

    private func makeViewModel(data: Data? = nil) throws -> WorkspaceViewModel {
        let wrapper = FileWrapper(regularFileWithContents: data ?? makeFixture())
        wrapper.preferredFilename = "obj.pdf"
        let document = try WorkspaceDocument(testingFile: wrapper, contentType: .pdf, filename: "obj.pdf")
        let vm = WorkspaceViewModel(document: document, processingEngine: PDFiumProcessingEngine())
        let undo = UndoManager()
        retainedUndoManager = undo
        vm.undoManager = undo
        return vm
    }

    /// A shape with a real TEXT object drawn on top. Text objects are excluded from object
    /// detection, so the page's raw object count exceeds the detected set — the exact condition
    /// under which the (fixed) no-op guard used to wrongly cancel Bring-to-Front.
    private func makeTextOverShapeFixture() -> Data {
        let data = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        let ctx = CGContext(consumer: CGDataConsumer(data: data as CFMutableData)!, mediaBox: &mediaBox, nil)!
        ctx.beginPDFPage(nil)
        ctx.setFillColor(NSColor.systemBlue.cgColor)
        ctx.fill(CGRect(x: 100, y: 100, width: 220, height: 90))
        let attributed = NSAttributedString(string: "TEXT ON TOP",
                                            attributes: [.font: NSFont.systemFont(ofSize: 24),
                                                         .foregroundColor: NSColor.black])
        let line = CTLineCreateWithAttributedString(attributed)
        ctx.textPosition = CGPoint(x: 120, y: 135)
        CTLineDraw(line, ctx)
        ctx.endPDFPage(); ctx.closePDF()
        return data as Data
    }

    private func makeMixedEditingFixture() -> Data {
        let data = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        let ctx = CGContext(consumer: CGDataConsumer(data: data as CFMutableData)!, mediaBox: &mediaBox, nil)!
        ctx.beginPDFPage(nil)
        ctx.setFillColor(NSColor.white.cgColor); ctx.fill(mediaBox)
        let img = CGContext(data: nil, width: 24, height: 24, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        img.setFillColor(NSColor.systemRed.cgColor); img.fill(CGRect(x: 0, y: 0, width: 24, height: 24))
        ctx.draw(img.makeImage()!, in: imagePDF)
        let attributed = NSAttributedString(
            string: "Original mixed editing text",
            attributes: [.font: NSFont(name: "Helvetica", size: 14) ?? .systemFont(ofSize: 14),
                         .foregroundColor: NSColor.black]
        )
        let line = CTLineCreateWithAttributedString(attributed)
        ctx.textPosition = CGPoint(x: 72, y: 700)
        CTLineDraw(line, ctx)
        ctx.endPDFPage(); ctx.closePDF()
        return data as Data
    }

    private func makeMixedEditingFormFixture() throws -> Data {
        let document = try XCTUnwrap(PDFDocument(data: makeMixedEditingFixture()))
        let page = try XCTUnwrap(document.page(at: 0))
        let field = PDFAnnotation(
            bounds: CGRect(x: 72, y: 640, width: 220, height: 28),
            forType: .widget,
            withProperties: nil
        )
        field.widgetFieldType = .text
        field.fieldName = "Replay field"
        field.widgetStringValue = "Retain this value"
        page.addAnnotation(field)
        return try XCTUnwrap(document.dataRepresentation())
    }

    private func makeTwoPageFixture() throws -> Data {
        let source = try XCTUnwrap(PDFDocument(data: makeFixture()))
        let page = try XCTUnwrap(source.page(at: 0))
        let document = PDFDocument()
        document.insert(try XCTUnwrap(page.copy() as? PDFPage), at: 0)
        document.insert(try XCTUnwrap(page.copy() as? PDFPage), at: 1)
        return try XCTUnwrap(document.dataRepresentation())
    }

    private func transformOp(_ o: DetectedObject, ref: PageRef, member: UUID, dx: CGFloat, dy: CGFloat) -> ObjectEditOperation {
        var newT = o.transform; newT.e += dx; newT.f += dy
        return ObjectEditOperation(type: .objectTransform, documentID: member, pageRefID: ref.id,
            sourceObjectKey: o.stableKey, objectType: o.objectType, editability: o.editability,
            originalBoundsPdf: o.boundsPdf, newBoundsPdf: o.boundsPdf.offsetBy(dx: dx, dy: dy),
            originalTransform: o.transform, newTransform: newT, pageRotation: Int(o.pageRotation),
            originalZIndex: o.zOrder, newZIndex: o.zOrder, replacementStrategy: .pdfiumStructural)
    }
    private func deleteOp(_ o: DetectedObject, ref: PageRef, member: UUID) -> ObjectEditOperation {
        ObjectEditOperation(type: .objectDelete, documentID: member, pageRefID: ref.id,
            sourceObjectKey: o.stableKey, objectType: o.objectType, editability: o.editability,
            originalBoundsPdf: o.boundsPdf, newBoundsPdf: o.boundsPdf,
            originalTransform: o.transform, newTransform: o.transform, pageRotation: Int(o.pageRotation),
            originalZIndex: o.zOrder, newZIndex: o.zOrder, replacementStrategy: .pdfiumStructural)
    }

    private func imageBounds(in data: Data?) -> CGRect? {
        guard let data else { return nil }
        return PDFObjectDetectionEngine.detect(pdfData: data, pageIndex: 0, pageRefID: UUID())
            .objects.first { $0.objectType == .imageXObject }?.boundsPdf
    }
    private func rectPresent(in data: Data?) -> Bool {
        guard let data else { return false }
        return PDFObjectDetectionEngine.detect(pdfData: data, pageIndex: 0, pageRefID: UUID())
            .objects.contains { near($0.boundsPdf, deleteRect, tol: 6) && ($0.objectType == .rectangle || $0.objectType == .filledShape) }
    }

    func testCommitMoveAndDeleteThenUndoRedo() throws {
        let vm = try makeViewModel()
        let ref = try XCTUnwrap(vm.document.workspace.pageOrder.first, "no page")
        let member = ref.memberDocId

        // Baseline: image at start, rect present.
        XCTAssertTrue(near(try XCTUnwrap(imageBounds(in: vm.document.memberPDFData[member])), imagePDF, tol: 3))
        XCTAssertTrue(rectPresent(in: vm.document.memberPDFData[member]))

        // Select via the VM's detection map.
        let map = vm.objectMap(for: ref)
        let image = try XCTUnwrap(map.objects.first { $0.objectType == .imageXObject }, "no image; types=\(map.objects.map(\.objectType))")
        let rect = try XCTUnwrap(map.objects.first { self.near($0.boundsPdf, deleteRect, tol: 6) && ($0.objectType == .rectangle || $0.objectType == .filledShape) }, "no rect")

        let dx: CGFloat = 70, dy: CGFloat = -25
        XCTAssertTrue(vm.applyObjectEdit([transformOp(image, ref: ref, member: member, dx: dx, dy: dy),
                                          deleteOp(rect, ref: ref, member: member)]), "commit failed")
        XCTAssertTrue(vm.hasObjectEdits)

        // Member bytes now reflect the edits (asserted by re-detecting the live bytes).
        XCTAssertTrue(near(try XCTUnwrap(imageBounds(in: vm.document.memberPDFData[member])), imagePDF.offsetBy(dx: dx, dy: dy), tol: 3), "image not moved in member bytes")
        XCTAssertFalse(rectPresent(in: vm.document.memberPDFData[member]), "rect not deleted from member bytes")

        // Undo → back to baseline, byte-level.
        vm.undoManager?.undo()
        XCTAssertFalse(vm.hasObjectEdits, "undo left object edits")
        XCTAssertTrue(near(try XCTUnwrap(imageBounds(in: vm.document.memberPDFData[member])), imagePDF, tol: 3), "undo didn't restore image position")
        XCTAssertTrue(rectPresent(in: vm.document.memberPDFData[member]), "undo didn't restore deleted rect")

        // Redo → edits reapplied.
        vm.undoManager?.redo()
        XCTAssertTrue(vm.hasObjectEdits, "redo didn't re-apply")
        XCTAssertTrue(near(try XCTUnwrap(imageBounds(in: vm.document.memberPDFData[member])), imagePDF.offsetBy(dx: dx, dy: dy), tol: 3), "redo didn't move image")
        XCTAssertFalse(rectPresent(in: vm.document.memberPDFData[member]), "redo didn't delete rect")
    }

    // Regression (v0.8.10): the Undo/Redo controls read `vm.undoManager` and re-evaluate on
    // `structureRevision`. An object commit (overlay path) must (a) register an undo on that exact
    // manager — the same one the toolbar/menu buttons check — so Undo isn't stuck disabled, with a
    // meaningful action name, and (b) bump `structureRevision` so the SwiftUI buttons re-render
    // after this AppKit-driven commit. This guards the fix for "object move worked but Undo stayed
    // greyed out and Cmd-Z did nothing."
    func testObjectCommitEnablesUndoOnViewModelManagerAndBumpsRevision() throws {
        let vm = try makeViewModel()
        let ref = try XCTUnwrap(vm.document.workspace.pageOrder.first)

        let hit = try XCTUnwrap(vm.objectHit(at: CGPoint(x: imagePDF.midX, y: imagePDF.midY), on: ref, scaleFactor: 1))
        vm.selectObject(hit, on: ref)

        let undo = try XCTUnwrap(vm.undoManager, "test must retain an undo manager")
        XCTAssertFalse(undo.canUndo, "precondition: nothing to undo before the edit")
        let revBefore = vm.structureRevision

        let old = hit.boundsPdf
        _ = vm.commitObjectBoundsChange(from: old, to: old.offsetBy(dx: 60, dy: -20))

        // (a) The manager the UI buttons read now reports an undoable, named action.
        XCTAssertTrue(undo.canUndo, "object commit did not register an undo on vm.undoManager — Undo would stay disabled")
        XCTAssertEqual(undo.undoActionName, L10n.string("undo.moveObject"), "undo action name should surface in the menu")
        // (b) The re-render trigger fired so the SwiftUI buttons re-evaluate their enabled state.
        XCTAssertGreaterThan(vm.structureRevision, revBefore, "commit must bump structureRevision so Undo/Redo buttons refresh")

        // And it actually reverts.
        undo.undo()
        XCTAssertFalse(vm.hasObjectEdits, "undo should clear the object edit")
    }

    func testRestyleSelectedObjectUpdatesBytesSelectionAndUndoState() throws {
        let vm = try makeViewModel()
        let ref = try XCTUnwrap(vm.document.workspace.pageOrder.first)
        let member = ref.memberDocId
        let shape = try XCTUnwrap(
            vm.objectMap(for: ref).objects.first {
                self.near($0.boundsPdf, deleteRect, tol: 6)
                    && ($0.objectType == .rectangle || $0.objectType == .filledShape)
            }
        )
        vm.selectObject(shape, on: ref)
        XCTAssertTrue(vm.canRestyleSelectedObject)

        let fill = CodableColor(red: 0.12, green: 0.46, blue: 0.78)
        let stroke = CodableColor(red: 0.76, green: 0.24, blue: 0.18)
        XCTAssertTrue(
            vm.restyleSelectedObject(
                fillColor: fill,
                strokeColor: stroke,
                lineWidth: 3.25
            )
        )

        let liveData = try XCTUnwrap(vm.document.memberPDFData[member])
        let liveObjects = PDFObjectDetectionEngine.detect(
            pdfData: liveData,
            pageIndex: 0,
            pageRefID: ref.id
        ).objects
        let updated = try XCTUnwrap(
            liveObjects.first { $0.stableKey.structuralDigest == shape.stableKey.structuralDigest },
            "restyled object missing; objects=\(liveObjects.map { ($0.objectType, $0.boundsPdf, $0.style) })"
        )
        XCTAssertEqual(try XCTUnwrap(updated.style.fillColor).blue, fill.blue, accuracy: 0.02)
        XCTAssertEqual(try XCTUnwrap(updated.style.strokeColor).red, stroke.red, accuracy: 0.02)
        XCTAssertEqual(updated.style.lineWidth, 3.25, accuracy: 0.05)
        XCTAssertEqual(vm.objectSelection?.object.style.fillColor, fill)
        XCTAssertEqual(vm.undoManager?.undoActionName, L10n.string("undo.styleObject"))

        vm.undoManager?.undo()
        let restoredData = try XCTUnwrap(vm.document.memberPDFData[member])
        let restored = try XCTUnwrap(
            PDFObjectDetectionEngine.detect(pdfData: restoredData, pageIndex: 0, pageRefID: ref.id)
                .objects.first { $0.stableKey.structuralDigest == shape.stableKey.structuralDigest }
        )
        XCTAssertLessThan(try XCTUnwrap(restored.style.fillColor).blue, 0.1)
    }

    // Phase 3: committed object edits survive the real export → fresh-reopen path, from bytes.
    func testObjectEditsSurviveExportAndReopen() throws {
        let vm = try makeViewModel()
        let ref = try XCTUnwrap(vm.document.workspace.pageOrder.first)
        let member = ref.memberDocId
        let map = vm.objectMap(for: ref)
        let image = try XCTUnwrap(map.objects.first { $0.objectType == .imageXObject })
        let rect = try XCTUnwrap(map.objects.first { self.near($0.boundsPdf, deleteRect, tol: 6) && ($0.objectType == .rectangle || $0.objectType == .filledShape) })

        let dx: CGFloat = 65, dy: CGFloat = -20
        XCTAssertTrue(vm.applyObjectEdit([transformOp(image, ref: ref, member: member, dx: dx, dy: dy),
                                          deleteOp(rect, ref: ref, member: member)]))

        let outURL = FileManager.default.temporaryDirectory.appendingPathComponent("obj-export-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: outURL) }
        XCTAssertTrue(vm.saveFlattenedPDF(to: outURL), "export failed")
        XCTAssertNil(vm.exportError)

        // Reopen the WRITTEN FILE from disk and detect — edits proven from bytes, not app memory.
        let reopened = try Data(contentsOf: outURL)
        let objs = PDFObjectDetectionEngine.detect(pdfData: reopened, pageIndex: 0, pageRefID: UUID()).objects
        let movedImage = try XCTUnwrap(objs.first { $0.objectType == .imageXObject }, "image gone from exported file")
        XCTAssertTrue(near(movedImage.boundsPdf, imagePDF.offsetBy(dx: dx, dy: dy), tol: 4),
                      "exported image at \(movedImage.boundsPdf), expected \(imagePDF.offsetBy(dx: dx, dy: dy))")
        XCTAssertFalse(objs.contains { self.near($0.boundsPdf, deleteRect, tol: 6) && ($0.objectType == .rectangle || $0.objectType == .filledShape) },
                       "deleted rect reappeared in exported file (ghost)")
    }

    // The canvas-facing API: hit-test → select → move → delete.
    func testHitTestSelectMoveDeleteAPI() throws {
        let vm = try makeViewModel()
        let ref = try XCTUnwrap(vm.document.workspace.pageOrder.first)
        let member = ref.memberDocId

        // Hit-test the center of the image → selects the image (frontmost, small).
        let hit = try XCTUnwrap(vm.objectHit(at: CGPoint(x: imagePDF.midX, y: imagePDF.midY), on: ref, scaleFactor: 1),
                                "hit-test found nothing at the image")
        XCTAssertEqual(hit.objectType, .imageXObject)
        vm.selectObject(hit, on: ref)
        XCTAssertEqual(vm.objectSelection?.object.stableKey, hit.stableKey)
        XCTAssertNotNil(vm.objectSelectionTooltip())

        // Move it via the overlay-style bounds change (old → new page bounds).
        let old = hit.boundsPdf
        let new = old.offsetBy(dx: 50, dy: -20)
        let applied = vm.commitObjectBoundsChange(from: old, to: new)
        XCTAssertTrue(near(applied, new, tol: 2), "commit returned \(applied)")
        XCTAssertTrue(near(try XCTUnwrap(imageBounds(in: vm.document.memberPDFData[member])), imagePDF.offsetBy(dx: 50, dy: -20), tol: 3),
                      "image not moved in member bytes")
        XCTAssertNotNil(vm.objectSelection, "selection lost after move")

        // A blank click clears selection.
        XCTAssertNil(vm.objectHit(at: CGPoint(x: 500, y: 40), on: ref, scaleFactor: 1))

        // Select the deletable rect and delete it structurally.
        let rectHit = try XCTUnwrap(vm.objectHit(at: CGPoint(x: deleteRect.midX, y: deleteRect.midY), on: ref, scaleFactor: 1))
        vm.selectObject(rectHit, on: ref)
        XCTAssertTrue(vm.deleteSelectedObject())
        XCTAssertNil(vm.objectSelection, "selection should clear after delete")
        XCTAssertFalse(rectPresent(in: vm.document.memberPDFData[member]), "rect not deleted")
    }

    // z-order: bring-to-front / send-to-back change the object's PDFium draw index without
    // dropping either object, keep the selection live, and undo restores the original order.
    func testObjectZOrderBringToFrontAndSendToBack() throws {
        let vm = try makeViewModel()
        let ref = try XCTUnwrap(vm.document.workspace.pageOrder.first)
        let member = ref.memberDocId

        func zOrder(nearBounds target: CGRect) -> Int? {
            guard let data = vm.document.memberPDFData[member] else { return nil }
            return PDFObjectDetectionEngine.detect(pdfData: data, pageIndex: 0, pageRefID: UUID())
                .objects.first { near($0.boundsPdf, target, tol: 6) }?.zOrder
        }

        // Fixture draws the rect first, then the image on top → image has the higher draw index.
        XCTAssertLessThan(try XCTUnwrap(zOrder(nearBounds: deleteRect)),
                          try XCTUnwrap(zOrder(nearBounds: imagePDF)),
                          "precondition: the rect is drawn behind the image")

        // Select the rect and bring it to the front.
        let rectHit = try XCTUnwrap(vm.objectHit(at: CGPoint(x: deleteRect.midX, y: deleteRect.midY), on: ref, scaleFactor: 1))
        vm.selectObject(rectHit, on: ref)
        XCTAssertTrue(vm.canLayerSelectedObject, "the rect should support z-order changes")
        XCTAssertTrue(vm.bringSelectedObjectToFront(), "bring to front should apply")
        XCTAssertNotNil(vm.objectSelection, "selection must survive a reorder")
        let frontMap = vm.objectMap(for: ref)
        XCTAssertEqual(frontMap.objects.map(\.zOrder), frontMap.objects.map(\.zOrder).sorted())
        XCTAssertEqual(Set(frontMap.objects.map(\.zOrder)).count, frontMap.objects.count)
        XCTAssertGreaterThan(try XCTUnwrap(zOrder(nearBounds: deleteRect)),
                             try XCTUnwrap(zOrder(nearBounds: imagePDF)),
                             "rect should now be in front of the image")

        // Send it back to the bottom.
        XCTAssertTrue(vm.sendSelectedObjectToBack(), "send to back should apply")
        let backMap = vm.objectMap(for: ref)
        XCTAssertEqual(backMap.objects.map(\.zOrder), backMap.objects.map(\.zOrder).sorted())
        XCTAssertEqual(Set(backMap.objects.map(\.zOrder)).count, backMap.objects.count)
        XCTAssertLessThan(try XCTUnwrap(zOrder(nearBounds: deleteRect)),
                          try XCTUnwrap(zOrder(nearBounds: imagePDF)),
                          "rect should be behind the image again")

        // Neither object was dropped by the reordering.
        XCTAssertTrue(rectPresent(in: vm.document.memberPDFData[member]), "rect vanished during reorder")
        XCTAssertNotNil(imageBounds(in: vm.document.memberPDFData[member]), "image vanished during reorder")

        // Undo walks the two reorders back; the rect ends up in front of the image again
        // (the state after bring-to-front), proving each reorder is its own undo step.
        vm.performUndoCommand()
        XCTAssertGreaterThan(try XCTUnwrap(zOrder(nearBounds: deleteRect)),
                             try XCTUnwrap(zOrder(nearBounds: imagePDF)),
                             "undoing send-to-back should restore the front position")

        let imageAfterReorder = try XCTUnwrap(vm.objectMap(for: ref).objects.first { $0.objectType == .imageXObject })
        vm.selectObject(imageAfterReorder, on: ref)
        let countBeforeDelete = vm.objectMap(for: ref).rawObjectCount
        XCTAssertTrue(vm.deleteSelectedObject())
        let deletedMap = vm.objectMap(for: ref)
        XCTAssertEqual(deletedMap.rawObjectCount, countBeforeDelete - 1)
        XCTAssertEqual(deletedMap.objects.map(\.zOrder), deletedMap.objects.map(\.zOrder).sorted())
        XCTAssertEqual(Set(deletedMap.objects.map(\.zOrder)).count, deletedMap.objects.count)
    }

    // Regression (audit finding #1): the no-op guard must measure the ABSOLUTE draw order, not
    // the detected subset (which excludes text). A shape under a text layer is the topmost
    // *detected* object yet not the topmost *overall* — Bring-to-Front must still move it, not
    // silently no-op as the old detected-extreme guard did.
    func testBringToFrontDoesNotNoOpWhenObjectSitsBelowExcludedText() throws {
        let vm = try makeViewModel(data: makeTextOverShapeFixture())
        let ref = try XCTUnwrap(vm.document.workspace.pageOrder.first)
        let map = vm.objectMap(for: ref)
        // Precondition for the bug: excluded text objects make the raw count exceed the detected set.
        try XCTSkipUnless(map.rawObjectCount > map.objects.count,
                          "fixture didn't yield excluded text objects on this SDK")
        let shape = try XCTUnwrap(map.objects.first { $0.objectType == .rectangle || $0.objectType == .filledShape },
                                  "no detectable shape in the fixture")
        // The shape is the topmost DETECTED object — the exact case the old guard no-op'd.
        XCTAssertEqual(shape.zOrder, map.objects.map(\.zOrder).max(), "shape should be the topmost detected object")

        vm.selectObject(shape, on: ref)
        let before = shape.zOrder
        XCTAssertTrue(vm.bringSelectedObjectToFront(), "must NOT no-op: the shape sits below the excluded text")
        let after = vm.objectMap(for: ref).objects.first { $0.stableKey == shape.stableKey }?.zOrder
        XCTAssertGreaterThan(try XCTUnwrap(after), before, "the shape should have risen above the text layer")
    }

    // Deep replay contract: text + object operations on the same member compose from one
    // canonical base. Committing either lane must regenerate both, never refuse or clobber one.
    func testCrossLaneObjectEditReplaysWithMemberTextEdits() throws {
        let vm = try makeViewModel()
        let ref = try XCTUnwrap(vm.document.workspace.pageOrder.first)
        let member = ref.memberDocId
        let map = vm.objectMap(for: ref)
        let image = try XCTUnwrap(map.objects.first { $0.objectType == .imageXObject })

        // Simulate an existing inline-text edit on this member's page.
        let textOp = PDFTextEditOperation(
            pageRefID: ref.id, sourceBlockID: UUID(), sourceBounds: CGRect(x: 72, y: 700, width: 80, height: 16),
            editedBounds: CGRect(x: 72, y: 700, width: 80, height: 16), replacementText: "hello",
            fontName: "Helvetica", fontSize: 12, textColor: CodableColor(red: 0, green: 0, blue: 0), alignment: .left)
        vm.document.workspace.pageEditStates = [PageEditState(pageRefID: ref.id, operations: [textOp])]
        XCTAssertTrue(vm.memberHasTextEdits(member))

        let baselineImage = try XCTUnwrap(imageBounds(in: vm.document.memberPDFData[member]))
        XCTAssertTrue(vm.applyObjectEdit([transformOp(image, ref: ref, member: member, dx: 40, dy: -15)]),
                      "object edit should compose with the member's committed text operations")
        XCTAssertTrue(vm.hasObjectEdits, "object operation was not retained")
        XCTAssertTrue(vm.memberHasTextEdits(member), "text operation was clobbered")

        let replayedData = try XCTUnwrap(vm.document.memberPDFData[member])
        XCTAssertTrue(near(try XCTUnwrap(imageBounds(in: replayedData)), baselineImage.offsetBy(dx: 40, dy: -15), tol: 3),
                      "object transform was not present in the replayed bytes")
        XCTAssertTrue(PDFDocument(data: replayedData)?.page(at: 0)?.string?.contains("hello") == true,
                      "text replacement was not present in the same replayed bytes")

        let liveImage = try XCTUnwrap(vm.objectMap(for: ref).objects.first { $0.objectType == .imageXObject })
        XCTAssertTrue(vm.applyObjectEdit([transformOp(liveImage, ref: ref, member: member, dx: 10, dy: -5)]),
                      "a later edit should rebind to the already-transformed object")
        XCTAssertTrue(
            near(
                try XCTUnwrap(imageBounds(in: vm.document.memberPDFData[member])),
                liveImage.boundsPdf.offsetBy(dx: 10, dy: -5),
                tol: 4
            ),
            "the later operation became an unresolved duplicate instead of extending the canonical transform"
        )
    }

    func testCrossLaneTextEditReplaysWithMemberObjectEdits() throws {
        let vm = try makeViewModel(data: makeMixedEditingFormFixture())
        let ref = try XCTUnwrap(vm.document.workspace.pageOrder.first)
        let member = ref.memberDocId
        let image = try XCTUnwrap(vm.objectMap(for: ref).objects.first { $0.objectType == .imageXObject })
        XCTAssertTrue(vm.applyObjectEdit([transformOp(image, ref: ref, member: member, dx: 35, dy: -12)]))

        let currentData = try XCTUnwrap(vm.document.memberPDFData[member])
        let page = try XCTUnwrap(vm.loadedPDFs.first?.1.page(at: 0))
        let analysis = PDFTextAnalysisEngine().analyze(
            data: currentData,
            pageIndex: 0,
            pageRefID: ref.id,
            fallbackPage: page
        )
        let block = try XCTUnwrap(analysis.blocks.first { $0.text.contains("Original mixed") })
        let target = try XCTUnwrap(vm.editableTextBlock(
            at: CGPoint(x: block.bounds.midX, y: block.bounds.midY),
            on: page,
            in: vm.combinedPDF
        ))
        XCTAssertTrue(vm.applyInlineTextEdit(
            pageRef: target.pageRef,
            sourceBlock: target.block,
            replacementText: "Replayed mixed editing text",
            editedBounds: target.block.bounds,
            fontName: target.block.fontName,
            fontSize: target.block.fontSize,
            textColor: .black,
            alignment: .left
        ))

        let replayedData = try XCTUnwrap(vm.document.memberPDFData[member])
        XCTAssertTrue(QPDFService.isStructurallySound(replayedData), "combined replay must remain structurally sound")
        XCTAssertTrue(
            QPDFService.formFieldsReferencePageAnnotations(replayedData),
            "combined replay must keep the AcroForm field and page widget as one object"
        )
        let replayedWidget = try XCTUnwrap(
            PDFDocument(data: replayedData)?.page(at: 0)?.annotations.first { $0.isPDFWidget }
        )
        XCTAssertEqual(replayedWidget.widgetStringValue, "Retain this value")
        XCTAssertEqual(replayedWidget.fieldName, "Replay field")
        XCTAssertTrue(near(try XCTUnwrap(imageBounds(in: replayedData)), imagePDF.offsetBy(dx: 35, dy: -12), tol: 4),
                      "committing text lost the earlier object transform")
        XCTAssertTrue(PDFDocument(data: replayedData)?.page(at: 0)?.string?.contains("Replayed mixed editing text") == true,
                      "committing text did not materialize the replacement")
        XCTAssertEqual(vm.reconcileCommittedEditsWithLoadedPages(), 0,
                       "a fresh combined replay should carry a current two-lane stamp")

        let stampedPage = try XCTUnwrap(vm.loadedPDFs.first?.1.page(at: 0))
        for annotation in stampedPage.annotations where BakeStamp.isStamp(annotation) {
            stampedPage.removeAnnotation(annotation)
        }
        XCTAssertGreaterThan(vm.reconcileCommittedEditsWithLoadedPages(), 0,
                             "removing a combined stamp should force member replay")
        let healedData = try XCTUnwrap(vm.document.memberPDFData[member])
        XCTAssertTrue(near(try XCTUnwrap(imageBounds(in: healedData)), imagePDF.offsetBy(dx: 35, dy: -12), tol: 4),
                      "self-healing lost the object lane")
        XCTAssertTrue(PDFDocument(data: healedData)?.page(at: 0)?.string?.contains("Replayed mixed editing text") == true,
                      "self-healing lost the text lane")
    }

    func testMemberReplayPreservesAnnotationsOnUneditedSiblingPages() throws {
        let vm = try makeViewModel(data: makeTwoPageFixture())
        let refs = vm.document.workspace.pageOrder
        XCTAssertEqual(refs.count, 2)
        let firstRef = refs[0]
        let member = firstRef.memberDocId
        let firstPage = try XCTUnwrap(vm.loadedPDFs.first?.1.page(at: 0))
        let samePageNote = try XCTUnwrap(vm.addNote(at: CGPoint(x: 100, y: 100), on: firstPage))
        samePageNote.contents = "keep edited-page note"
        let secondPage = try XCTUnwrap(vm.loadedPDFs.first?.1.page(at: 1))
        let note = try XCTUnwrap(vm.addNote(at: CGPoint(x: 80, y: 80), on: secondPage))
        note.contents = "keep sibling note"

        let image = try XCTUnwrap(vm.objectMap(for: firstRef).objects.first { $0.objectType == .imageXObject })
        XCTAssertTrue(vm.applyObjectEdit([transformOp(image, ref: firstRef, member: member, dx: 20, dy: -10)]))

        let replayedSibling = try XCTUnwrap(vm.loadedPDFs.first?.1.page(at: 1))
        let replayedEditedPage = try XCTUnwrap(vm.loadedPDFs.first?.1.page(at: 0))
        XCTAssertTrue(
            replayedEditedPage.annotations.contains { $0.contents == "keep edited-page note" },
            "member replay discarded an annotation on the edited page"
        )
        XCTAssertTrue(
            replayedSibling.annotations.contains { $0.contents == "keep sibling note" },
            "member replay discarded an annotation on an untouched sibling page"
        )
    }

    func testUnresolvedObjectReplayLeavesLiveMemberBytesUntouched() throws {
        let vm = try makeViewModel()
        let ref = try XCTUnwrap(vm.document.workspace.pageOrder.first)
        let member = ref.memberDocId
        let image = try XCTUnwrap(vm.objectMap(for: ref).objects.first { $0.objectType == .imageXObject })
        var unresolved = transformOp(image, ref: ref, member: member, dx: 25, dy: -10)
        unresolved.sourceObjectKey.structuralDigest &+= 1
        vm.document.workspace.objectEditStates = [
            PageObjectEditState(pageRefID: ref.id, operations: [unresolved])
        ]
        let liveBytes = try XCTUnwrap(vm.document.memberPDFData[member])

        XCTAssertEqual(vm.reconcileCommittedEditsWithLoadedPages(), 0)
        XCTAssertEqual(
            vm.document.memberPDFData[member],
            liveBytes,
            "a partial replay must not replace the last known-good live member bytes"
        )
    }

    // objectMap caches per pageRef and returns the same identities on repeat calls.
    func testObjectMapIsCachedAndStable() throws {
        let vm = try makeViewModel()
        let ref = try XCTUnwrap(vm.document.workspace.pageOrder.first)
        let a = vm.objectMap(for: ref)
        let b = vm.objectMap(for: ref)
        XCTAssertEqual(a.objects.map { $0.stableKey.structuralDigest }, b.objects.map { $0.stableKey.structuralDigest })
        XCTAssertFalse(a.objects.isEmpty)
    }

    // Regression (UI-bug loop): boundsPdf is a POST-matrix AABB, not the object's local rect.
    // commitObjectBoundsChange used to derive a scale from AABB deltas and compose it onto the
    // object's existing (possibly rotated) transform, which shears any object whose own transform
    // carries rotation/skew — even on an unrotated page. Resize must be suppressed for such objects
    // (fall back to move-only); a plain move must still work.
    func testResizeIsSuppressedForRotatedObjectTransform() throws {
        let vm = try makeViewModel()
        let ref = try XCTUnwrap(vm.document.workspace.pageOrder.first)
        let map = vm.objectMap(for: ref)
        var image = try XCTUnwrap(map.objects.first { $0.objectType == .imageXObject })
        image.transform = PDFTextTransform(image.transform.cgAffineTransform.concatenating(CGAffineTransform(rotationAngle: .pi / 4)))
        vm.selectObject(image, on: ref)
        let old = image.boundsPdf

        let moved = old.offsetBy(dx: 20, dy: 10)
        let appliedMove = vm.commitObjectBoundsChange(from: old, to: moved)
        XCTAssertTrue(near(appliedMove, moved, tol: 3), "a rotated object should still be movable")

        let biggerFromMoved = moved.insetBy(dx: -30, dy: -30)
        let appliedResize = vm.commitObjectBoundsChange(from: moved, to: biggerFromMoved)
        XCTAssertEqual(appliedResize.width, moved.width, accuracy: 2, "rotated object must not resize (would shear)")
        XCTAssertEqual(appliedResize.height, moved.height, accuracy: 2, "rotated object must not resize (would shear)")
    }

    // Regression: rotating a DIFFERENT page must not disturb an active object selection, and
    // rotating the selected object's OWN page must clear it (rotated-page editing is punted).
    // Both the single-page and bulk-rotate paths must agree on this.
    func testRotatingUnrelatedPagePreservesObjectSelection() throws {
        let vm = try makeViewModel()
        let ref1 = try XCTUnwrap(vm.document.workspace.pageOrder.first)
        vm.duplicatePages([ref1])
        XCTAssertEqual(vm.document.workspace.pageOrder.count, 2)
        let ref2 = try XCTUnwrap(vm.document.workspace.pageOrder.last)
        XCTAssertNotEqual(ref1.id, ref2.id)

        let map = vm.objectMap(for: ref1)
        let image = try XCTUnwrap(map.objects.first { $0.objectType == .imageXObject })
        vm.selectObject(image, on: ref1)
        XCTAssertNotNil(vm.objectSelection)

        vm.rotatePage(ref2, by: 90)
        XCTAssertNotNil(vm.objectSelection, "rotating an unrelated page cleared the selection")
        XCTAssertEqual(vm.objectSelection?.pageRefID, ref1.id)

        vm.rotatePage(ref1, by: 90)
        XCTAssertNil(vm.objectSelection, "rotating the selected object's own page should clear it")
    }

    func testReselectingAfterRotationKeepsObjectEditingRefused() throws {
        let vm = try makeViewModel()
        let ref = try XCTUnwrap(vm.document.workspace.pageOrder.first)
        _ = vm.objectMap(for: ref) // Populate the canonical inspection before live rotation.

        vm.rotatePage(ref, by: 90)
        let rotatedMap = vm.objectMap(for: ref)
        let image = try XCTUnwrap(rotatedMap.objects.first { $0.objectType == .imageXObject })
        XCTAssertEqual(image.pageRotation, 90)

        vm.selectObject(image, on: ref)
        let originalBounds = image.boundsPdf
        let attemptedBounds = originalBounds.offsetBy(dx: 20, dy: 10)
        let revisionBeforeAttempt = vm.structureRevision
        let applied = vm.commitObjectBoundsChange(from: originalBounds, to: attemptedBounds)

        XCTAssertEqual(applied, originalBounds, "rotated-page editing must stay refused after reselect")
        XCTAssertFalse(vm.hasObjectEdits)
        XCTAssertEqual(vm.structureRevision, revisionBeforeAttempt)
    }

    func testBulkRotatePagesInvalidatesSelectionOnlyForRotatedPages() throws {
        let vm = try makeViewModel()
        let ref1 = try XCTUnwrap(vm.document.workspace.pageOrder.first)
        vm.duplicatePages([ref1])
        let refs = vm.document.workspace.pageOrder
        XCTAssertEqual(refs.count, 2)
        let ref2 = refs[1]

        let map = vm.objectMap(for: ref1)
        let image = try XCTUnwrap(map.objects.first { $0.objectType == .imageXObject })
        vm.selectObject(image, on: ref1)

        vm.rotatePages([ref2], by: 90)
        XCTAssertNotNil(vm.objectSelection, "bulk-rotating an unrelated page cleared the selection")

        vm.rotatePages([ref1, ref2], by: 90)
        XCTAssertNil(vm.objectSelection, "bulk-rotating the selected object's page must clear it")
    }

    // Regression (UI-bug loop, deeper root cause): OrderSnapshot — the undo mechanism shared by
    // delete/duplicate/reorder/OCR/form-reset — didn't carry objectEditStates/objectBaseData, only
    // pageEditStates. So deleting a page that had committed object edits, then undoing, restored
    // the PDF bytes (which already had the edit baked in) but NOT the bookkeeping — leaving them
    // desynced for the next edit. Deleting must purge the bookkeeping for the removed page, and
    // undo must bring it back in lockstep with the restored bytes.
    func testDeletePageWithObjectEditsPurgesAndUndoRestoresState() throws {
        let vm = try makeViewModel()
        let ref = try XCTUnwrap(vm.document.workspace.pageOrder.first)
        let member = ref.memberDocId
        let map = vm.objectMap(for: ref)
        let image = try XCTUnwrap(map.objects.first { $0.objectType == .imageXObject })

        XCTAssertTrue(vm.applyObjectEdit([transformOp(image, ref: ref, member: member, dx: 40, dy: -10)]))
        XCTAssertTrue(vm.hasObjectEdits)
        let editedImageBounds = try XCTUnwrap(imageBounds(in: vm.document.memberPDFData[member]))

        vm.deletePage(ref)
        XCTAssertFalse(vm.hasObjectEdits, "deleting the only edited page must purge its object edit state")
        XCTAssertTrue(vm.document.workspace.pageOrder.isEmpty)

        vm.undoManager?.undo()
        XCTAssertTrue(vm.hasObjectEdits, "undoing the delete must restore object-edit bookkeeping, not just bytes")
        let restoredRef = try XCTUnwrap(vm.document.workspace.pageOrder.first)
        XCTAssertEqual(restoredRef.id, ref.id)
        XCTAssertTrue(near(try XCTUnwrap(imageBounds(in: vm.document.memberPDFData[restoredRef.memberDocId])), editedImageBounds, tol: 3),
                      "undo restored bytes but the object-edit state is now desynced from them")
    }

    // Regression (Round 3 adversarial audit): regenerateObjectEditedMember rebuilds the WHOLE
    // member from `objectBaseData` — a byte snapshot frozen once, at the member's first object
    // edit. Reordering pages within that member afterward (sidebar drag) shifts every later
    // page's live index but leaves the frozen snapshot's page order untouched; without a
    // refreeze, the NEXT unrelated object edit anywhere in the member regenerates from the
    // stale pre-reorder snapshot, silently reverting the reorder (and, in this single-page-base
    // fixture, dropping the reordered-in page outright since it never existed in that snapshot).
    func testReorderWithinMemberSurvivesALaterObjectEdit() throws {
        let vm = try makeViewModel()
        let ref1 = try XCTUnwrap(vm.document.workspace.pageOrder.first)
        let member = ref1.memberDocId

        let map1 = vm.objectMap(for: ref1)
        let image1 = try XCTUnwrap(map1.objects.first { $0.objectType == .imageXObject })
        XCTAssertTrue(vm.applyObjectEdit([transformOp(image1, ref: ref1, member: member, dx: 40, dy: -10)]))

        vm.duplicatePages([ref1])
        XCTAssertEqual(vm.document.workspace.pageOrder.count, 2)
        let ref2 = try XCTUnwrap(vm.document.workspace.pageOrder.last)
        XCTAssertTrue(vm.movePage(ref2, toIndex: 0))
        XCTAssertEqual(vm.document.workspace.pageOrder.map(\.id), [ref2.id, ref1.id])

        let map2 = vm.objectMap(for: ref2)
        let image2 = try XCTUnwrap(map2.objects.first { $0.objectType == .imageXObject })
        XCTAssertTrue(vm.applyObjectEdit([transformOp(image2, ref: ref2, member: member, dx: 5, dy: 5)]),
                     "a later object edit after a reorder must still succeed")

        let regenerated = try XCTUnwrap(vm.document.memberPDFData[member])
        XCTAssertEqual(PDFDocument(data: regenerated)?.pageCount, 2,
                       "an unrelated object edit after a reorder dropped a page — regenerated from a stale pre-reorder base")
        XCTAssertEqual(vm.document.workspace.pageOrder.map(\.id), [ref2.id, ref1.id],
                       "an unrelated object edit reverted the reorder")
    }

    // Same root cause as the reorder case above, in the other direction: duplicating a page
    // inserts one, shifting every later page's live index the same way deleting removes one.
    func testDuplicateWithinMemberSurvivesALaterObjectEdit() throws {
        let vm = try makeViewModel()
        let ref1 = try XCTUnwrap(vm.document.workspace.pageOrder.first)
        let member = ref1.memberDocId

        let map1 = vm.objectMap(for: ref1)
        let image1 = try XCTUnwrap(map1.objects.first { $0.objectType == .imageXObject })
        XCTAssertTrue(vm.applyObjectEdit([transformOp(image1, ref: ref1, member: member, dx: 40, dy: -10)]))

        vm.duplicatePages([ref1])
        XCTAssertEqual(vm.document.workspace.pageOrder.count, 2)
        let ref2 = try XCTUnwrap(vm.document.workspace.pageOrder.last)

        let map2 = vm.objectMap(for: ref2)
        let image2 = try XCTUnwrap(map2.objects.first { $0.objectType == .imageXObject })
        XCTAssertTrue(vm.applyObjectEdit([transformOp(image2, ref: ref2, member: member, dx: 5, dy: 5)]),
                     "a later object edit on the duplicate must succeed")

        let regenerated = try XCTUnwrap(vm.document.memberPDFData[member])
        XCTAssertEqual(PDFDocument(data: regenerated)?.pageCount, 2,
                       "an unrelated object edit after duplicating a page dropped a page — regenerated from a stale pre-duplicate base")
    }

    // Regression (Round 2 adversarial audit): setRotation recurses through its OWN undo/redo
    // (not OrderSnapshot/restore()), so it has to carry the selection through by hand. Rotating
    // the selected object's own page clears the selection (rotated-page editing is punted); undo
    // must bring that selection back, not just revert the rotation.
    func testUndoingRotationOfSelectedObjectsPageRestoresSelection() throws {
        let vm = try makeViewModel()
        let ref = try XCTUnwrap(vm.document.workspace.pageOrder.first)
        let map = vm.objectMap(for: ref)
        let image = try XCTUnwrap(map.objects.first { $0.objectType == .imageXObject })
        vm.selectObject(image, on: ref)
        let selectedKey = try XCTUnwrap(vm.objectSelection?.object.stableKey)

        vm.rotatePage(ref, by: 90)
        XCTAssertNil(vm.objectSelection, "rotating the selected object's own page should clear it")

        vm.undoManager?.undo()
        XCTAssertEqual(vm.objectSelection?.object.stableKey, selectedKey,
                       "undoing the rotation should bring the selection back, not just revert the rotation")

        // And redo must clear it again, symmetrically.
        vm.undoManager?.redo()
        XCTAssertNil(vm.objectSelection, "redoing the rotation should re-clear the selection")
    }

    // Regression (Round 2 adversarial audit): restore() — the undo path shared by
    // delete/duplicate/reorder/OCR — used to unconditionally clear objectSelection on every
    // timeline jump. That's wrong when the selection has nothing to do with the operation being
    // undone: selecting an object on page 1, then deleting an UNRELATED page 2 and undoing that
    // delete, must leave page 1's selection exactly as it was.
    func testUndoingUnrelatedPageDeletePreservesObjectSelection() throws {
        let vm = try makeViewModel()
        // `groupsByEvent` (the default) would coalesce the duplicate + delete below into one
        // undo group since both run synchronously with no run-loop turn between them — isolate
        // them explicitly so a single `undo()` reverts only the delete. (See OrifoldTests.swift's
        // established pattern for this exact issue.)
        let undoManager = try XCTUnwrap(vm.undoManager)
        undoManager.groupsByEvent = false

        let ref1 = try XCTUnwrap(vm.document.workspace.pageOrder.first)
        undoManager.beginUndoGrouping()
        vm.duplicatePages([ref1])
        undoManager.endUndoGrouping()
        XCTAssertEqual(vm.document.workspace.pageOrder.count, 2)
        let ref2 = try XCTUnwrap(vm.document.workspace.pageOrder.last)

        let map = vm.objectMap(for: ref1)
        let image = try XCTUnwrap(map.objects.first { $0.objectType == .imageXObject })
        vm.selectObject(image, on: ref1)
        let selectedKey = try XCTUnwrap(vm.objectSelection?.object.stableKey)

        undoManager.beginUndoGrouping()
        vm.deletePage(ref2)
        undoManager.endUndoGrouping()
        XCTAssertEqual(vm.objectSelection?.object.stableKey, selectedKey, "deleting an unrelated page disturbed the selection")

        undoManager.undo()
        XCTAssertEqual(vm.document.workspace.pageOrder.count, 2, "undo didn't bring the deleted page back")
        XCTAssertEqual(vm.objectSelection?.object.stableKey, selectedKey,
                       "undoing an unrelated page delete must not clear an untouched selection")
    }
}
