import AppKit
import CoreGraphics
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
        ctx.setFillColor(NSColor.black.cgColor); ctx.fill(deleteRect)
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

    private func makeViewModel() throws -> WorkspaceViewModel {
        let wrapper = FileWrapper(regularFileWithContents: makeFixture())
        wrapper.preferredFilename = "obj.pdf"
        let document = try WorkspaceDocument(testingFile: wrapper, contentType: .pdf, filename: "obj.pdf")
        let vm = WorkspaceViewModel(document: document, processingEngine: PDFiumProcessingEngine())
        let undo = UndoManager()
        retainedUndoManager = undo
        vm.undoManager = undo
        return vm
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

    // objectMap caches per pageRef and returns the same identities on repeat calls.
    func testObjectMapIsCachedAndStable() throws {
        let vm = try makeViewModel()
        let ref = try XCTUnwrap(vm.document.workspace.pageOrder.first)
        let a = vm.objectMap(for: ref)
        let b = vm.objectMap(for: ref)
        XCTAssertEqual(a.objects.map { $0.stableKey.structuralDigest }, b.objects.map { $0.stableKey.structuralDigest })
        XCTAssertFalse(a.objects.isEmpty)
    }
}
