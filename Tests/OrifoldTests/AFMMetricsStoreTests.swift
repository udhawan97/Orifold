import XCTest
@testable import Orifold

/// Covers the AFM (Adobe Font Metrics) parser (Feature E2): it reads glyph advance
/// widths out of the `StartCharMetrics`/`EndCharMetrics` block and the `FontName`, and
/// rejects malformed input. Uses an inline Helvetica fixture whose widths match the real
/// Adobe Core-14 `Helvetica.afm` (A = 667, space = 278) so E3's bundled-asset test lines
/// up with the same numbers.
final class AFMMetricsStoreTests: XCTestCase {
    private static let helveticaFixture = """
    StartFontMetrics 4.1
    Comment Minimal Helvetica fixture for tests.
    FontName Helvetica
    FullName Helvetica
    FamilyName Helvetica
    Weight Medium
    StartCharMetrics 5
    C 32 ; WX 278 ; N space ; B 0 0 0 0 ;
    C 65 ; WX 667 ; N A ; B 14 0 654 718 ;
    C 87 ; WX 944 ; N W ; B 4 0 940 718 ;
    C 105 ; WX 222 ; N i ; B 67 0 154 718 ;
    C -1 ; WX 500 ; N bullet ; B 35 194 465 624 ;
    EndCharMetrics
    EndFontMetrics
    """

    // MARK: parse

    func testParsesFontNameAndGlyphWidths() throws {
        let font = try XCTUnwrap(AFMMetricsStore.parse(Self.helveticaFixture))
        XCTAssertEqual(font.fontName, "Helvetica")
        XCTAssertEqual(font.glyphWidths.count, 5)
        XCTAssertEqual(font.advanceWidth(glyphName: "A"), 667)
        XCTAssertEqual(font.advanceWidth(glyphName: "space"), 278)
        XCTAssertEqual(font.advanceWidth(glyphName: "W"), 944)
        XCTAssertEqual(font.advanceWidth(glyphName: "i"), 222)
    }

    /// An unencoded glyph (`C -1`) still carries a real width via its `N` name.
    func testParsesUnencodedGlyph() throws {
        let font = try XCTUnwrap(AFMMetricsStore.parse(Self.helveticaFixture))
        XCTAssertEqual(font.advanceWidth(glyphName: "bullet"), 500)
    }

    func testAdvanceWidthIsNilForUnknownGlyph() throws {
        let font = try XCTUnwrap(AFMMetricsStore.parse(Self.helveticaFixture))
        XCTAssertNil(font.advanceWidth(glyphName: "eng"))
    }

    // MARK: width(of:)

    func testWidthOfStringSumsGlyphAdvances() throws {
        let font = try XCTUnwrap(AFMMetricsStore.parse(Self.helveticaFixture))
        XCTAssertEqual(font.width(of: "A"), 667)
        XCTAssertEqual(font.width(of: "Ai"), 889)          // 667 + 222
        XCTAssertEqual(font.width(of: "A W"), 1889)         // 667 + 278 + 944
    }

    /// Characters with no metric in this font contribute nothing rather than crashing.
    func testWidthOfStringSkipsUnmappedCharacters() throws {
        let font = try XCTUnwrap(AFMMetricsStore.parse(Self.helveticaFixture))
        XCTAssertEqual(font.width(of: "Aж"), 667)
    }

    // MARK: malformed

    func testMalformedInputReturnsNil() {
        XCTAssertNil(AFMMetricsStore.parse(""))
        XCTAssertNil(AFMMetricsStore.parse("this is not an AFM file\njust some text"))
    }

    /// A file with the global section but no char-metrics block is not usable metrics.
    func testAFMWithoutCharMetricsReturnsNil() {
        let noMetrics = """
        StartFontMetrics 4.1
        FontName Helvetica
        EndFontMetrics
        """
        XCTAssertNil(AFMMetricsStore.parse(noMetrics))
    }
}
