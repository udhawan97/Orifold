import PDFKit
import XCTest
@testable import Orifold

/// The bake stamp is written through PDFium and read back through PDFKit, which
/// spell the same annotation key differently ("OrifoldBakeStamp" vs
/// "/OrifoldBakeStamp"). It is also excluded by hand at every site that walks a
/// page's annotations, since it is engine bookkeeping rather than user markup.
/// These pin both facts so neither can drift silently.
final class BakeStampConsolidationTests: XCTestCase {
    // The two spellings must come from ONE constant. Held apart in separate files
    // they are linked only by an unwritten "PDFium key == PDFKit key minus the
    // leading slash" rule: renaming the concept in one place would leave stamps
    // written but never detected, and every reconcile would silently fall back to
    // text-presence or re-bake every page.
    func testPDFiumAndPDFKitKeySpellingsShareOneConstant() {
        XCTAssertEqual(
            BakeStamp.annotationKey, "/" + BakeStamp.pdfiumAnnotationKey,
            "the PDFKit spelling must be the PDFium spelling plus a leading slash, derived not duplicated")
    }

    // Every scan of a page's user markup must skip the stamp. Sites re-derive that
    // exclusion by hand today, so a new scan that forgets it ships unnoticed —
    // this accessor is the one that cannot be forgotten.
    func testUserAnnotationsExcludesTheBakeStampButKeepsRealMarkup() throws {
        let page = PDFPage()

        let markup = PDFAnnotation(
            bounds: CGRect(x: 10, y: 10, width: 50, height: 20), forType: .freeText, withProperties: nil)
        markup.contents = "a real user note"
        page.addAnnotation(markup)
        BakeStamp.attach("deadbeef", to: page)

        XCTAssertEqual(page.annotations.count, 2, "precondition: the page carries markup AND a stamp")

        let user = BakeStamp.userAnnotations(on: page)
        XCTAssertEqual(user.count, 1, "the bake stamp must not count as user markup")
        XCTAssertEqual(user.first?.contents, "a real user note")
    }

    // The stamp is a FreeText annotation specifically so it round-trips through
    // PDFKit, which makes it indistinguishable from user markup by type alone —
    // the reason every scan needs the exclusion in the first place.
    func testTheStampIsAFreeTextAnnotationAndSoNeedsExplicitExclusion() throws {
        let page = PDFPage()
        BakeStamp.attach("cafe", to: page)

        let stamp = try XCTUnwrap(page.annotations.first)
        XCTAssertEqual(stamp.type, "FreeText", "type alone cannot distinguish the stamp from user markup")
        XCTAssertTrue(BakeStamp.isStamp(stamp))
        XCTAssertEqual(BakeStamp.value(on: page), "cafe")
        XCTAssertTrue(BakeStamp.userAnnotations(on: page).isEmpty)
    }
}
