import AppKit
import PDFKit
import XCTest
@testable import Orifold

/// Feature G2: a `.image` page decoration carrying a generated barcode must bake into the
/// exported PDF as real, dark-moduled image content. The assertion is pixel-based on the
/// rendered thumbnail (CI-safe — never `PDFPage.string`): the barcode region must contain a
/// solid cluster of dark (low-brightness) module pixels a blank page never would.
final class BarcodeInsertBakeTests: XCTestCase {
    func testBakedBarcodeRendersDarkModules() throws {
        let pageRef = PageRef(memberDocId: UUID(), sourcePageIndex: 0)
        let rect = CGRect(x: 120, y: 420, width: 180, height: 180)
        let decoration = try barcodeDecoration(payload: "https://orifold.app/wave2-G", pageRef: pageRef, rect: rect)

        let baked = try PDFDecorationExportBaker.bake(
            decorations: [decoration],
            pageOrder: [pageRef],
            into: blankPageData()
        )

        let reopened = try XCTUnwrap(PDFDocument(data: baked))
        XCTAssertEqual(reopened.pageCount, 1)
        let page = try XCTUnwrap(reopened.page(at: 0))
        let thumbnail = page.thumbnail(of: CGSize(width: 612, height: 792), for: .mediaBox)
        let tiff = try XCTUnwrap(thumbnail.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))

        // Sample the interior of the barcode (inset past the white quiet zone). A QR is roughly
        // half dark modules, so this cluster of samples must go well below 0.6 brightness where
        // a blank white page would stay near 1.0.
        let inner = rect.insetBy(dx: rect.width * 0.16, dy: rect.height * 0.16)
        var darkModuleSamples = 0
        for px in stride(from: Int(inner.minX), to: Int(inner.maxX), by: 5) {
            for py in stride(from: Int(inner.minY), to: Int(inner.maxY), by: 5) {
                guard let color = bitmap.colorAt(x: px, y: 792 - py)?.usingColorSpace(.deviceRGB) else { continue }
                if color.brightnessComponent < 0.6 {
                    darkModuleSamples += 1
                }
            }
        }
        XCTAssertGreaterThan(darkModuleSamples, 8,
                             "baked barcode should paint dark modules; found \(darkModuleSamples) dark samples")
    }

    /// A barcode whose `pageRefID` no longer exists is rejected, exactly like a stamp or hanko —
    /// the baker never silently drops or mis-places an orphaned image decoration.
    func testOrphanedBarcodeIsRejected() throws {
        let pageRef = PageRef(memberDocId: UUID(), sourcePageIndex: 0)
        let orphan = try barcodeDecoration(payload: "ORPHAN", pageRef: PageRef(memberDocId: UUID(), sourcePageIndex: 0),
                                           rect: CGRect(x: 10, y: 10, width: 80, height: 80))
        XCTAssertThrowsError(
            try PDFDecorationExportBaker.bake(decorations: [orphan], pageOrder: [pageRef], into: blankPageData())
        )
    }

    private func barcodeDecoration(payload: String, pageRef: PageRef, rect: CGRect) throws -> PageDecoration {
        let cgImage = try BarcodeGenerator.image(for: payload, symbology: .qr)
        let png = try XCTUnwrap(NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]))
        return PageDecoration.image(imageData: png, pageRefID: pageRef.id, rect: rect)
    }

    private func blankPageData() throws -> Data {
        let page = PDFPage()
        page.setBounds(CGRect(x: 0, y: 0, width: 612, height: 792), for: .mediaBox)
        let doc = PDFDocument()
        doc.insert(page, at: 0)
        return try XCTUnwrap(doc.dataRepresentation())
    }
}
