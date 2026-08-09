import AppKit
import PDFKit
import XCTest
@testable import Orifold

final class PDFOverlayDecorationTests: XCTestCase {
    private struct RGBInk {
        var red: CGFloat
        var green: CGFloat
        var blue: CGFloat
    }

    func testOverlayPDFDecorationRoundTripsAndLegacyDecorationDefaultsToNoOverlay() throws {
        let overlayData = try solidPageData(color: .systemBlue)
        let decoration = PageDecoration.overlayPDF(
            pdfData: overlayData,
            placement: .under
        )

        let encoded = try JSONEncoder().encode(decoration)
        let decoded = try JSONDecoder().decode(PageDecoration.self, from: encoded)

        XCTAssertEqual(decoded, decoration)
        XCTAssertEqual(decoded.kind, .overlayPDF)
        XCTAssertEqual(decoded.overlayPDFData, overlayData)
        XCTAssertEqual(decoded.overlayPDFPlacement, .under)

        let legacy = try JSONDecoder().decode(PageDecoration.self, from: Data("""
        {
          "kind": "watermark",
          "text": "DRAFT"
        }
        """.utf8))
        XCTAssertNil(legacy.overlayPDFData)
        XCTAssertEqual(legacy.overlayPDFPlacement, .over)
    }

    func testOverlayPDFBakesVectorInkInRequestedLayerOrder() throws {
        let sourceData = try pageData { context, mediaBox in
            context.setFillColor(NSColor.white.cgColor)
            context.fill(mediaBox)
            context.setFillColor(NSColor.black.cgColor)
            context.fill(CGRect(x: 206, y: 296, width: 200, height: 200))
        }
        let overlayData = try pageData { context, _ in
            context.setFillColor(NSColor.systemBlue.cgColor)
            context.fill(CGRect(x: 206, y: 296, width: 200, height: 200))
        }
        let pageRef = PageRef(memberDocId: UUID(), sourcePageIndex: 0)

        let underData = try PDFDecorationExportBaker.bake(
            decorations: [.overlayPDF(pdfData: overlayData, placement: .under)],
            pageOrder: [pageRef],
            into: sourceData
        )
        let overData = try PDFDecorationExportBaker.bake(
            decorations: [.overlayPDF(pdfData: overlayData, placement: .over)],
            pageOrder: [pageRef],
            into: sourceData
        )

        let underInk = try centerInk(in: underData)
        let overInk = try centerInk(in: overData)
        XCTAssertLessThan(underInk.red, 0.12)
        XCTAssertLessThan(underInk.green, 0.12)
        XCTAssertLessThan(underInk.blue, 0.12)
        XCTAssertGreaterThan(overInk.blue, 0.55)
        XCTAssertGreaterThan(overInk.blue, overInk.red + 0.25)
        XCTAssertGreaterThan(overInk.blue, overInk.green + 0.05)
    }

    func testOverlayPDFViewModelPersistsPlacementAndSupportsUndo() throws {
        let overlayData = try solidPageData(color: .systemBlue)
        let viewModel = WorkspaceViewModel(
            document: WorkspaceDocument(),
            processingEngine: PDFKitProcessingEngineFallback()
        )
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        viewModel.undoManager = undoManager

        undoManager.beginUndoGrouping()
        XCTAssertTrue(viewModel.setOverlayPDF(data: overlayData, placement: .under))
        undoManager.endUndoGrouping()
        XCTAssertEqual(viewModel.decoration(of: .overlayPDF)?.overlayPDFData, overlayData)
        XCTAssertEqual(viewModel.decoration(of: .overlayPDF)?.overlayPDFPlacement, .under)

        undoManager.beginUndoGrouping()
        viewModel.setOverlayPDFPlacement(.over)
        undoManager.endUndoGrouping()
        XCTAssertEqual(viewModel.decoration(of: .overlayPDF)?.overlayPDFPlacement, .over)

        undoManager.undo()
        XCTAssertEqual(viewModel.decoration(of: .overlayPDF)?.overlayPDFPlacement, .under)
        undoManager.undo()
        XCTAssertNil(viewModel.decoration(of: .overlayPDF))
    }

    func testOverlayPDFTargetAndEnableStateUseDecorationUndoFlow() throws {
        let document = WorkspaceDocument()
        let member = MemberDocument(displayName: "Target", sourcePDFRef: "target.pdf")
        let pageRef = PageRef(memberDocId: member.id, sourcePageIndex: 0)
        document.workspace.pageOrder = [pageRef]
        let viewModel = WorkspaceViewModel(
            document: document,
            processingEngine: PDFKitProcessingEngineFallback()
        )
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        viewModel.undoManager = undoManager

        undoManager.beginUndoGrouping()
        XCTAssertTrue(viewModel.setOverlayPDF(
            data: try solidPageData(color: .systemBlue),
            placement: .under
        ))
        undoManager.endUndoGrouping()

        undoManager.beginUndoGrouping()
        XCTAssertTrue(viewModel.setOverlayPDFTarget(pageRef.id))
        undoManager.endUndoGrouping()
        XCTAssertEqual(viewModel.overlayPDFDecoration()?.pageRefID, pageRef.id)

        undoManager.beginUndoGrouping()
        viewModel.setOverlayPDFEnabled(false)
        undoManager.endUndoGrouping()
        XCTAssertEqual(viewModel.overlayPDFDecoration()?.isEnabled, false)

        undoManager.undo()
        XCTAssertEqual(viewModel.overlayPDFDecoration()?.isEnabled, true)
        undoManager.undo()
        XCTAssertNil(viewModel.overlayPDFDecoration()?.pageRefID)
    }

    func testReplacingOverlayPreservesPageTargetAndEnabledState() throws {
        let document = WorkspaceDocument()
        var member = MemberDocument(displayName: "Target", sourcePDFRef: "target.pdf")
        let pageRef = PageRef(memberDocId: member.id, sourcePageIndex: 0)
        member.pageRefs = [pageRef.id]
        document.workspace.documents = [member]
        document.workspace.pageOrder = [pageRef]
        document.memberPDFData[member.id] = try solidPageData(color: .white)
        let viewModel = WorkspaceViewModel(
            document: document,
            processingEngine: PDFKitProcessingEngineFallback()
        )

        XCTAssertTrue(viewModel.setOverlayPDF(
            data: try solidPageData(color: .systemBlue),
            placement: .under,
            pageRefID: pageRef.id
        ))
        viewModel.setOverlayPDFEnabled(false)

        let replacement = try solidPageData(color: .systemRed)
        XCTAssertTrue(viewModel.replaceOverlayPDF(data: replacement, placement: .over))

        let overlay = try XCTUnwrap(viewModel.overlayPDFDecoration())
        XCTAssertEqual(overlay.overlayPDFData, replacement)
        XCTAssertEqual(overlay.overlayPDFPlacement, .over)
        XCTAssertEqual(overlay.pageRefID, pageRef.id)
        XCTAssertFalse(overlay.isEnabled)
    }

    func testOverlayPDFRejectsMultiPageSourceAndHonorsPageTargeting() throws {
        let whitePage = try solidPageData(color: .white)
        let sourceDocument = try XCTUnwrap(PDFDocument(data: whitePage))
        let secondPage = try XCTUnwrap(PDFDocument(data: whitePage)?.page(at: 0)?.copy() as? PDFPage)
        sourceDocument.insert(secondPage, at: 1)
        let twoPageData = try XCTUnwrap(sourceDocument.dataRepresentation())

        let viewModel = WorkspaceViewModel(
            document: WorkspaceDocument(),
            processingEngine: PDFKitProcessingEngineFallback()
        )
        XCTAssertFalse(viewModel.setOverlayPDF(data: twoPageData, placement: .over))

        let refs = [
            PageRef(memberDocId: UUID(), sourcePageIndex: 0),
            PageRef(memberDocId: UUID(), sourcePageIndex: 1)
        ]
        let baked = try PDFDecorationExportBaker.bake(
            decorations: [
                .overlayPDF(
                    pdfData: try solidPageData(color: .systemBlue),
                    placement: .over,
                    pageRefID: refs[1].id
                )
            ],
            pageOrder: refs,
            into: twoPageData
        )

        let firstInk = try centerInk(in: baked, pageIndex: 0)
        let secondInk = try centerInk(in: baked, pageIndex: 1)
        XCTAssertGreaterThan(firstInk.red, 0.9)
        XCTAssertGreaterThan(firstInk.green, 0.9)
        XCTAssertGreaterThan(secondInk.blue, secondInk.red + 0.25)
    }

    private func solidPageData(color: NSColor) throws -> Data {
        try pageData { context, mediaBox in
            context.setFillColor(color.cgColor)
            context.fill(mediaBox)
        }
    }

    private func pageData(_ drawing: (CGContext, CGRect) -> Void) throws -> Data {
        let data = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        let consumer = try XCTUnwrap(CGDataConsumer(data: data as CFMutableData))
        let context = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &mediaBox, nil))
        context.beginPDFPage(nil)
        drawing(context, mediaBox)
        context.endPDFPage()
        context.closePDF()
        return data as Data
    }

    private func centerInk(in data: Data,
                           pageIndex: Int = 0) throws -> RGBInk {
        let document = try XCTUnwrap(PDFDocument(data: data))
        let page = try XCTUnwrap(document.page(at: pageIndex))
        let image = page.thumbnail(of: CGSize(width: 612, height: 792), for: .mediaBox)
        let representation = try XCTUnwrap(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        let color = try XCTUnwrap(representation.colorAt(x: representation.pixelsWide / 2,
                                                         y: representation.pixelsHigh / 2))
        let rgb = try XCTUnwrap(color.usingColorSpace(.deviceRGB))
        return RGBInk(
            red: rgb.redComponent,
            green: rgb.greenComponent,
            blue: rgb.blueComponent
        )
    }
}
