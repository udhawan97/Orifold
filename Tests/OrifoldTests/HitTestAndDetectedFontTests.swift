import PDFKit
import XCTest
@testable import Orifold

/// WP-D: hitTest prefers a block whose actual LINE contains the point over one that only
/// matches via its (taller) bounding box. WP-E: monospaced fonts are detectable so the
/// font menu can tag them.
final class HitTestAndDetectedFontTests: XCTestCase {
    private let engine = PDFTextAnalysisEngine()

    private func makeBlock(text: String, bounds: CGRect, lines: [CGRect], font: String = "Helvetica", size: CGFloat = 12) -> EditableTextBlock {
        EditableTextBlock(
            pageRefID: nil, text: text, bounds: bounds,
            lines: lines.map { PDFTextLine(text: text, bounds: $0, runs: [], confidence: .high) },
            fontName: font, fontSize: size, textColor: .documentText,
            rotation: 0, baseline: bounds.minY, confidence: .high
        )
    }

    /// A point in the inter-line gap of a tall two-line paragraph that ALSO falls inside a
    /// small single-line block's union box must resolve to the block whose line contains it.
    func testLineContainmentTieBreak() throws {
        // Tall paragraph: bounds span y 100..140 (two lines at 100..114 and 126..140), with a
        // gap 114..126. A small block sits exactly in that gap (y 116..124).
        let paragraph = makeBlock(
            text: "Paragraph line one and line two",
            bounds: CGRect(x: 50, y: 100, width: 200, height: 40),
            lines: [CGRect(x: 50, y: 126, width: 200, height: 14), CGRect(x: 50, y: 100, width: 120, height: 14)]
        )
        let smallInGap = makeBlock(
            text: "gap label",
            bounds: CGRect(x: 60, y: 116, width: 80, height: 8),
            lines: [CGRect(x: 60, y: 116, width: 80, height: 8)]
        )
        let analysis = PDFTextPageAnalysis(pageRefID: nil, blocks: [paragraph, smallInGap])
        // Point at (100,120) — inside the paragraph's union box AND inside smallInGap's line.
        let hit = engine.hitTest(CGPoint(x: 100, y: 120), in: analysis, tolerance: 2)
        XCTAssertEqual(hit?.text, "gap label", "the block whose LINE contains the point wins over the paragraph's union box")
    }

    /// Among two line-containing candidates, the smaller wins (dense-cell behavior preserved).
    func testSmallestLineContainingBlockWins() throws {
        let row = makeBlock(text: "Row spanning wide", bounds: CGRect(x: 50, y: 100, width: 300, height: 14),
                            lines: [CGRect(x: 50, y: 100, width: 300, height: 14)])
        let cell = makeBlock(text: "cell", bounds: CGRect(x: 60, y: 100, width: 40, height: 14),
                             lines: [CGRect(x: 60, y: 100, width: 40, height: 14)])
        let analysis = PDFTextPageAnalysis(pageRefID: nil, blocks: [row, cell])
        let hit = engine.hitTest(CGPoint(x: 75, y: 107), in: analysis, tolerance: 2)
        XCTAssertEqual(hit?.text, "cell", "the smallest line-containing block wins")
    }

    /// WP-E input: the monospaced header fixture's blocks report a fixed-pitch font, so the
    /// detected-font menu can tag it as Mono.
    func testMonospacedFontIsDetectableForMenuTag() throws {
        XCTAssertTrue(NSFont(name: "Monaco", size: 12)?.isFixedPitch ?? false, "Monaco must be recognized as fixed-pitch")
        XCTAssertFalse(NSFont(name: "Helvetica", size: 12)?.isFixedPitch ?? true, "Helvetica must not be fixed-pitch")

        let data = EditingFixturePDFBuilder.monospacedHeaderPage()
        let pdf = try XCTUnwrap(PDFDocument(data: data))
        let page = try XCTUnwrap(pdf.page(at: 0))
        let analysis = engine.analyze(data: data, pageIndex: 0, pageRefID: UUID(), fallbackPage: page)
        let monoBlock = try XCTUnwrap(analysis.blocks.first { $0.text.contains("Demo Client") })
        XCTAssertTrue(NSFont(name: monoBlock.fontName, size: monoBlock.fontSize)?.isFixedPitch ?? false,
                      "the detected header font (\(monoBlock.fontName)) must be fixed-pitch so the menu tags it Mono")
    }
}
