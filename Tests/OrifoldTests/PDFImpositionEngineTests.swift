import XCTest
import PDFKit
@testable import Orifold

final class PDFImpositionEngineTests: XCTestCase {
    // MARK: - Fixtures (test-only PDF creation)

    /// A 4-page Letter fixture, each page carrying a solid black mark at a distinct x offset so the
    /// pages are visually distinguishable and content presence is detectable via pixel brightness.
    private func fourPageMarkedFixture() -> Data {
        let mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else { return Data() }
        var box = mediaBox
        guard let ctx = CGContext(consumer: consumer, mediaBox: &box, nil) else { return Data() }
        for pageIndex in 0..<4 {
            ctx.beginPDFPage(nil)
            ctx.setFillColor(CGColor(gray: 0, alpha: 1))
            ctx.fill(CGRect(x: 90 + CGFloat(pageIndex) * 40, y: 320, width: 220, height: 140))
            ctx.endPDFPage()
        }
        ctx.closePDF()
        return data as Data
    }

    private func twoBlankPageFixture() -> Data {
        let doc = PDFDocument()
        for _ in 0..<2 { doc.insert(PDFPage(), at: doc.pageCount) }
        return doc.dataRepresentation()!   // fixture only — never product code
    }

    /// CI-safe content check (gotcha (d)): render a thumbnail and confirm dark pixels survived,
    /// instead of the SDK-fragile `PDFPage.string`.
    private func hasDarkPixels(_ page: PDFPage) -> Bool {
        let thumbnail = page.thumbnail(of: NSSize(width: 240, height: 240), for: .mediaBox)
        guard let tiff = thumbnail.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return false }
        let width = rep.pixelsWide
        let height = rep.pixelsHigh
        for y in stride(from: 0, to: height, by: 6) {
            for x in stride(from: 0, to: width, by: 6) {
                guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let luminance = (color.redComponent + color.greenComponent + color.blueComponent) / 3
                if luminance < 0.5 { return true }
            }
        }
        return false
    }

    // MARK: - N-up

    func testImportNPagesToOneProducesOnePage() throws {
        let out = try PDFImpositionEngine.impose(BakedPDFData(alreadyFlattened: twoBlankPageFixture()), layout: .nUp(rows: 1, cols: 2))
        let rendered = try XCTUnwrap(PDFDocument(data: out))
        XCTAssertEqual(rendered.pageCount, 1)                 // 2 src pages -> 1 sheet
        XCTAssertTrue(QPDFService.isStructurallySound(out))   // preserving-pipeline gate (f)
    }

    func testFourUpProducesOneSheet() throws {
        let out = try PDFImpositionEngine.impose(BakedPDFData(alreadyFlattened: fourPageMarkedFixture()), layout: .nUp(rows: 2, cols: 2))
        let rendered = try XCTUnwrap(PDFDocument(data: out))
        XCTAssertEqual(rendered.pageCount, 1)                 // 4 src pages -> 1 sheet (2x2)
        XCTAssertTrue(QPDFService.isStructurallySound(out))
    }

    // MARK: - Booklet

    func testBookletFourPagesProducesTwoUpSheets() throws {
        let src = fourPageMarkedFixture()
        let out = try PDFImpositionEngine.impose(BakedPDFData(alreadyFlattened: src), layout: .booklet)
        let doc = try XCTUnwrap(PDFDocument(data: out))
        XCTAssertEqual(doc.pageCount, 2)                       // 4 pages, 2-up, 1 sheet = 2 physical sides
        XCTAssertTrue(QPDFService.isStructurallySound(out))
    }

    /// Odd page counts pad to a multiple of 4 with real blank leaves (FPDFPage_New), so a 3-page
    /// booklet still yields 4 booklet pages / 2 output sheets.
    func testBookletPadsOddPageCount() throws {
        let mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        let data = NSMutableData()
        let consumer = CGDataConsumer(data: data as CFMutableData)!
        var box = mediaBox
        let ctx = CGContext(consumer: consumer, mediaBox: &box, nil)!
        for _ in 0..<3 {
            ctx.beginPDFPage(nil)
            ctx.setFillColor(CGColor(gray: 0, alpha: 1))
            ctx.fill(CGRect(x: 120, y: 320, width: 220, height: 140))
            ctx.endPDFPage()
        }
        ctx.closePDF()
        let out = try PDFImpositionEngine.impose(BakedPDFData(alreadyFlattened: data as Data), layout: .booklet)
        let doc = try XCTUnwrap(PDFDocument(data: out))
        XCTAssertEqual(doc.pageCount, 2)                       // 3 -> padded 4 -> 2 sheets
        XCTAssertTrue(QPDFService.isStructurallySound(out))
    }

    /// Bake-before-impose proof: the source's black marks survive into the imposed sheet content
    /// (they are not annotations, so imposition's XObject flattening keeps them).
    func testBookletPreservesPageContent() throws {
        let out = try PDFImpositionEngine.impose(BakedPDFData(alreadyFlattened: fourPageMarkedFixture()), layout: .booklet)
        let doc = try XCTUnwrap(PDFDocument(data: out))
        let firstSheet = try XCTUnwrap(doc.page(at: 0))
        XCTAssertTrue(hasDarkPixels(firstSheet), "imposed booklet sheet lost its source content")
    }

    func testInvalidDataThrows() {
        XCTAssertThrowsError(try PDFImpositionEngine.impose(BakedPDFData(alreadyFlattened: Data()), layout: .booklet))
        XCTAssertThrowsError(try PDFImpositionEngine.impose(BakedPDFData(alreadyFlattened: Data("not a pdf".utf8)), layout: .nUp(rows: 1, cols: 2)))
    }
}
