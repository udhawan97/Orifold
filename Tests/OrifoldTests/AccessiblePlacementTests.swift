import AppKit
import PDFKit
import XCTest
@testable import Orifold

@MainActor
final class AccessiblePlacementTests: XCTestCase {
    func testCurrentPageButtonPlacesSignatureAtNonzeroCropCenterAndClearsArmedState() throws {
        let viewModel = try makeViewModel()
        try armSignature(in: viewModel)
        let page = try currentPage(in: viewModel)
        let crop = page.bounds(for: .cropBox)

        XCTAssertTrue(viewModel.placeArmedPlacementOnCurrentPage())

        let placement = try XCTUnwrap(viewModel.document.workspace.signatures.first)
        XCTAssertEqual(placement.pageRefId, viewModel.document.workspace.pageOrder[1].id)
        XCTAssertEqual(placement.rect.midX, crop.midX, accuracy: 0.01)
        XCTAssertEqual(placement.rect.midY, crop.midY, accuracy: 0.01)
        XCTAssertTrue(crop.contains(placement.rect))
        XCTAssertEqual(viewModel.selectedPlacementBounds, placement.rect)
        XCTAssertFalse(viewModel.hasArmedPlacement)
        XCTAssertFalse(viewModel.placeArmedPlacementOnCurrentPage())
        XCTAssertEqual(viewModel.document.workspace.signatures.count, 1)
    }

    func testSignatureGeometryApplyUsesOneUndoAndRedoAndRemainsExportable() throws {
        let viewModel = try makeViewModel()
        try armSignature(in: viewModel)
        XCTAssertTrue(viewModel.placeArmedPlacementOnCurrentPage())
        let original = try XCTUnwrap(viewModel.selectedPlacementBounds)
        let undo = UndoManager()
        undo.groupsByEvent = false
        viewModel.undoManager = undo
        undo.beginUndoGrouping()
        XCTAssertTrue(viewModel.applySelectedPlacementBounds(CGRect(x: 65, y: 95, width: 80, height: 30)))
        undo.endUndoGrouping()
        let changed = try XCTUnwrap(viewModel.selectedPlacementBounds)
        XCTAssertNotEqual(changed, original)
        XCTAssertEqual(changed, CGRect(x: 65, y: 95, width: 80, height: 30))
        XCTAssertEqual(viewModel.document.workspace.signatures.first?.rect, changed)

        undo.undo()
        XCTAssertEqual(viewModel.selectedPlacementBounds, original)
        XCTAssertFalse(undo.canUndo, "one Apply must undo as one operation")
        undo.redo()
        XCTAssertEqual(viewModel.selectedPlacementBounds, changed)
        XCTAssertEqual(try XCTUnwrap(PDFDocument(data: viewModel.dataForPDFExport())).pageCount, 2)

        undo.beginUndoGrouping()
        viewModel.deleteSelectedAnnotation()
        undo.endUndoGrouping()
        XCTAssertTrue(viewModel.document.workspace.signatures.isEmpty)
        undo.undo()
        XCTAssertEqual(viewModel.document.workspace.signatures.first?.rect, changed)
    }

    func testStampHankoAndBarcodeUseSharedPlacementClampAndSingleGeometryUndo() throws {
        let image = try signaturePNG()
        let arms: [(String, (WorkspaceViewModel) -> Void)] = [
            ("stamp", { $0.beginStampPlacement(text: "Reviewed", swatch: .accent) }),
            ("hanko", { $0.beginHankoPlacement(text: "TEST", shape: .circle) }),
            ("barcode", { $0.beginBarcodePlacement(imageData: image, pixelSize: CGSize(width: 64, height: 32)) })
        ]
        for (name, arm) in arms {
            let viewModel = try makeViewModel()
            arm(viewModel)
            XCTAssertTrue(viewModel.placeArmedPlacementOnCurrentPage(), name)
            XCTAssertFalse(viewModel.hasArmedPlacement, name)
            let original = try XCTUnwrap(viewModel.selectedPlacementBounds)
            let page = try currentPage(in: viewModel)
            let crop = page.bounds(for: .cropBox)
            XCTAssertTrue(crop.contains(original), name)
            let undo = UndoManager()
            undo.groupsByEvent = false
            viewModel.undoManager = undo
            undo.beginUndoGrouping()
            XCTAssertTrue(viewModel.applySelectedPlacementBounds(CGRect(x: -100, y: -100, width: 1, height: 1)), name)
            undo.endUndoGrouping()
            let clamped = try XCTUnwrap(viewModel.selectedPlacementBounds)
            XCTAssertEqual(clamped, CGRect(x: crop.minX, y: crop.minY, width: 24, height: 12), name)
            undo.undo()
            XCTAssertEqual(viewModel.selectedPlacementBounds, original, name)
            XCTAssertFalse(undo.canUndo, name)
            undo.redo()
            XCTAssertEqual(viewModel.selectedPlacementBounds, clamped, name)
            XCTAssertEqual(try XCTUnwrap(PDFDocument(data: viewModel.dataForPDFExport())).pageCount, 2, name)
        }
    }

    func testInvalidGeometryAndUnavailablePageLeavePlacementAndArmedStateUntouched() throws {
        let viewModel = try makeViewModel()
        try armSignature(in: viewModel)
        viewModel.currentPageNumber = 999
        XCTAssertFalse(viewModel.placeArmedPlacementOnCurrentPage())
        XCTAssertTrue(viewModel.hasArmedPlacement)
        viewModel.currentPageNumber = 2
        XCTAssertTrue(viewModel.placeArmedPlacementOnCurrentPage())
        let original = try XCTUnwrap(viewModel.selectedPlacementBounds)
        let invalid = [
            CGRect(x: CGFloat.nan, y: 70, width: 80, height: 30),
            CGRect(x: 40, y: CGFloat.infinity, width: 80, height: 30),
            CGRect(x: 40, y: 70, width: CGFloat.infinity, height: 30),
            CGRect(x: 40, y: 70, width: 0, height: 30),
            CGRect(x: 40, y: 70, width: 80, height: -1)
        ]
        for bounds in invalid {
            XCTAssertFalse(viewModel.applySelectedPlacementBounds(bounds))
            XCTAssertEqual(viewModel.selectedPlacementBounds, original)
        }
        XCTAssertFalse(WorkspaceViewModel(document: WorkspaceDocument()).applySelectedPlacementBounds(original))
    }

    private func makeViewModel() throws -> WorkspaceViewModel {
        let bytes = EditingFixturePDFBuilder.makePDF(runs: [])
        let pdf = try XCTUnwrap(PDFDocument(data: bytes))
        let second = try XCTUnwrap(PDFDocument(data: bytes)?.page(at: 0))
        second.setBounds(CGRect(x: 40, y: 70, width: 140, height: 90), for: .cropBox)
        pdf.insert(second, at: 1)
        let document = WorkspaceDocument()
        var member = MemberDocument(displayName: "Synthetic placement", sourcePDFRef: "synthetic.pdf")
        let refs = (0..<2).map { PageRef(memberDocId: member.id, sourcePageIndex: $0) }
        member.pageRefs = refs.map(\.id)
        document.workspace.documents = [member]
        document.workspace.pageOrder = refs
        document.memberPDFData[member.id] = try XCTUnwrap(PDFSerializer.data(from: pdf))
        let viewModel = WorkspaceViewModel(document: document, processingEngine: PDFKitProcessingEngineFallback())
        viewModel.currentPageNumber = 2
        return viewModel
    }

    private func currentPage(in viewModel: WorkspaceViewModel) throws -> PDFPage {
        try XCTUnwrap(viewModel.combinedPDF.page(at: try XCTUnwrap(viewModel.combinedPageIndex(forWorkspacePageNumber: 2))))
    }

    private func signaturePNG() throws -> Data {
        try SignatureAppearanceRenderer.pngData(
            for: .typedName("Review Signature"), size: CGSize(width: 240, height: 80), scale: 2
        )
    }

    private func armSignature(in viewModel: WorkspaceViewModel) throws {
        viewModel.beginVisualSignaturePlacement(imageData: try signaturePNG(), kind: .visualTyped, signerName: "Review Signature")
    }
}
