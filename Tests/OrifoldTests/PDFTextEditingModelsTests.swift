import XCTest
@testable import Orifold

final class PDFTextEditingModelsTests: XCTestCase {
    func testPDFTextTransformRoundTripsThroughCodable() throws {
        let transform = PDFTextTransform(a: 1, b: 0.5, c: -0.5, d: 1, e: 10, f: 20)
        let data = try JSONEncoder().encode(transform)
        let decoded = try JSONDecoder().decode(PDFTextTransform.self, from: data)
        XCTAssertEqual(decoded, transform)
        XCTAssertEqual(decoded.cgAffineTransform, CGAffineTransform(a: 1, b: 0.5, c: -0.5, d: 1, tx: 10, ty: 20))
    }

    /// `EditableTextBlock`/`PDFTextRun` are never actually written into a saved `.orifold`
    /// workspace -- verified by checking every stored-property site across the app: they're
    /// only ever held in-memory as `PDFTextAnalysisEngine` output (re-derived fresh from the
    /// page's raw PDF bytes on every analysis pass), never nested inside `PDFTextEditOperation`
    /// or `Workspace` (which persist a much smaller `PDFTextEditFormat` snapshot instead, with
    /// its own careful `decodeIfPresent`-based migration handling). So unlike that operation
    /// type, there's no old-file migration contract to protect here -- this is a plain
    /// round-trip fidelity check for the `Codable` conformance these types happen to carry.
    func testEditableTextBlockRoundTripsNewFieldsThroughCodable() throws {
        let block = EditableTextBlock(
            pageRefID: UUID(),
            text: "Rotated line",
            bounds: CGRect(x: 10, y: 20, width: 100, height: 30),
            lines: [],
            fontName: "Helvetica",
            fontSize: 12,
            textColor: .documentText,
            rotation: 45,
            pageRotation: 90,
            baseline: 20,
            confidence: .high,
            strokeColor: CodableColor(red: 1, green: 0, blue: 0, alpha: 1),
            transform: PDFTextTransform(a: 1, b: 0.5, c: -0.5, d: 1, e: 0, f: 0),
            hasSyntheticGlyphs: true
        )
        let data = try JSONEncoder().encode(block)
        let decoded = try JSONDecoder().decode(EditableTextBlock.self, from: data)
        XCTAssertEqual(decoded, block)
    }

    func testPDFTextRunRoundTripsNewFieldsThroughCodable() throws {
        let run = PDFTextRun(
            text: "Rotated run",
            bounds: CGRect(x: 0, y: 0, width: 50, height: 10),
            fontName: "Helvetica",
            fontSize: 12,
            textColor: .documentText,
            rotation: 90,
            baseline: 0,
            confidence: .high,
            strokeColor: CodableColor(red: 0, green: 1, blue: 0, alpha: 1),
            transform: PDFTextTransform(a: 0, b: 1, c: -1, d: 0, e: 5, f: 5),
            hasSyntheticGlyphs: true
        )
        let data = try JSONEncoder().encode(run)
        let decoded = try JSONDecoder().decode(PDFTextRun.self, from: data)
        XCTAssertEqual(decoded, run)
    }

    /// New fields with non-optional defaults (`pageRotation: Int = 0`, `hasSyntheticGlyphs:
    /// Bool = false`) do NOT get Swift's synthesized-Decodable leniency the way `Optional`
    /// properties do -- a missing key throws `keyNotFound` rather than falling back to the
    /// default, confirmed directly against this decoder. That's fine here (see above: these
    /// two types have no real old-file migration contract to satisfy), but it's worth pinning
    /// down explicitly so a future reader doesn't assume `= false`/`= 0` alone is enough to
    /// make a field migration-safe -- only `Optional` properties get that for free.
    func testNonOptionalDefaultedFieldsRequireTheKeyToBePresent() {
        let jsonMissingPageRotation = """
        {
            "id": "00000000-0000-0000-0000-000000000003",
            "text": "x",
            "bounds": [[0, 0], [10, 10]],
            "lines": [],
            "fontName": "Helvetica",
            "fontSize": 12,
            "textColor": {"red": 0, "green": 0, "blue": 0, "alpha": 1},
            "underline": false,
            "rotation": 0,
            "baseline": 0,
            "confidence": "high",
            "editability": "direct",
            "textSource": "pdfiumGlyphs"
        }
        """.data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(EditableTextBlock.self, from: jsonMissingPageRotation))
    }
}
