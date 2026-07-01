import AppKit
import PDFKit
import XCTest
@testable import PDFold

final class SignatureAppearanceRendererTests: XCTestCase {
    func testTypedSignatureRendersRasterAndSelfContainedPDFPathStream() throws {
        let descriptor = SignatureAppearanceDescriptor.typedName("Ada Lovelace")
        let png = try SignatureAppearanceRenderer.pngData(
            for: descriptor,
            size: CGSize(width: 240, height: 80),
            scale: 2
        )
        XCTAssertNotNil(NSImage(data: png))

        let stream = try SignatureAppearanceRenderer.pdfAppearanceStream(
            for: descriptor,
            bounds: CGRect(x: 0, y: 0, width: 240, height: 80)
        )
        XCTAssertEqual(stream.bbox, CGRect(x: 0, y: 0, width: 240, height: 80))

        let body = String(decoding: stream.xobject, as: UTF8.self)
        XCTAssertTrue(body.contains(" rg"))
        XCTAssertTrue(body.contains(" m"))
        XCTAssertTrue(body.contains("f"))
        XCTAssertFalse(body.contains("/F1"), "appearance stream should not require external font resources")
    }

    func testInitialsCanBeDerivedFromSignerName() {
        let descriptor = SignatureAppearanceDescriptor.initials(fromName: "Ada Byron Lovelace")
        XCTAssertEqual(descriptor.displayText, "ABL")
    }
}

final class SignatureExportBakingSupportTests: XCTestCase {
    func testBakedVisualSignatureSurvivesReopenAndRendersInPageContent() throws {
        let pdfData = try blankPageData()
        let rect = CGRect(x: 200, y: 360, width: 200, height: 80)
        let placement = SignaturePlacement(
            pageRefId: UUID(),
            imageData: try blackPNG(width: 200, height: 80),
            rect: rect,
            signerName: "Ada"
        )

        let baked = try SignatureExportBakingSupport.bake(placements: [placement], into: pdfData) { _ in 0 }
        let reopened = try XCTUnwrap(PDFDocument(data: baked))
        let page = try XCTUnwrap(reopened.page(at: 0))

        let thumbnail = page.thumbnail(of: CGSize(width: 612, height: 792), for: .mediaBox)
        let tiff = try XCTUnwrap(thumbnail.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        let sample = try XCTUnwrap(bitmap.colorAt(x: Int(rect.midX), y: Int(792 - rect.midY))?.usingColorSpace(.deviceRGB))
        XCTAssertLessThan(sample.brightnessComponent, 0.5)
    }

    private func blankPageData() throws -> Data {
        let page = PDFPage()
        page.setBounds(CGRect(x: 0, y: 0, width: 612, height: 792), for: .mediaBox)
        let doc = PDFDocument()
        doc.insert(page, at: 0)
        return try XCTUnwrap(doc.dataRepresentation())
    }

    private func blackPNG(width: Int, height: Int) throws -> Data {
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.black.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        NSGraphicsContext.restoreGraphicsState()
        return try XCTUnwrap(rep.representation(using: .png, properties: [:]))
    }
}
