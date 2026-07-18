import CoreText
import XCTest
@testable import Orifold

/// Covers bundling + runtime registration of the substitution fonts and Core-14 AFMs
/// (Feature E3). Asserts font resolution via CoreText family names (CI-safe — never via
/// `PDFPage.string`), that registration is idempotent, and that the bundled Adobe
/// Helvetica AFM carries its known metric (A = 667).
final class FontRegistrarTests: XCTestCase {
    private static let bundledFamilies = [
        "Liberation Sans", "Liberation Serif", "Liberation Mono", "Carlito", "Caladea",
    ]

    private func resolvedFamilyName(_ family: String) -> String {
        let font = CTFontCreateWithName(family as CFString, 12, nil)
        return CTFontCopyFamilyName(font) as String
    }

    func testFontsDirectoryAndAFMResolve() {
        let dir = FontRegistrar.fontsDirectoryURL()
        XCTAssertNotNil(dir, "bundled Fonts directory must resolve")
        XCTAssertNotNil(FontRegistrar.afmURL(forResource: "Helvetica"), "bundled Helvetica.afm must resolve")
    }

    func testRegisterBundledFontsMakesFamiliesResolvable() {
        FontRegistrar.registerBundledFonts()
        for family in Self.bundledFamilies {
            XCTAssertEqual(
                resolvedFamilyName(family), family,
                "\(family) should resolve to itself once the bundled font is registered"
            )
        }
    }

    /// Registration must tolerate being called more than once (the app registers at
    /// launch; tests register too) — "already registered" is success, never a failure.
    func testRegisterBundledFontsIsIdempotent() {
        FontRegistrar.registerBundledFonts()
        FontRegistrar.registerBundledFonts()
        FontRegistrar.registerBundledFonts()
        for family in Self.bundledFamilies {
            XCTAssertEqual(resolvedFamilyName(family), family)
        }
    }

    /// The bundled Adobe Core-14 Helvetica metrics load through `FontRegistrar.afmURL`
    /// and carry the canonical width for 'A' (667) — the E2 parser reading a real asset.
    func testBundledHelveticaAFMHasCanonicalWidth() throws {
        let helvetica = try XCTUnwrap(AFMMetricsStore.core14("Helvetica"), "Helvetica.afm must be bundled")
        XCTAssertEqual(helvetica.fontName, "Helvetica")
        XCTAssertEqual(helvetica.advanceWidth(glyphName: "A"), 667)
        XCTAssertEqual(helvetica.advanceWidth(glyphName: "space"), 278)
    }

    func testBundledTimesAFMResolves() throws {
        let times = try XCTUnwrap(AFMMetricsStore.core14("Times-Roman"), "Times-Roman.afm must be bundled")
        XCTAssertEqual(times.fontName, "Times-Roman")
        XCTAssertNotNil(times.advanceWidth(glyphName: "A"))
    }
}
