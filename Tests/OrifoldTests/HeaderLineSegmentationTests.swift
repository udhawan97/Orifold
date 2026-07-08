import PDFKit
import XCTest
@testable import Orifold

/// WP-A: short standalone header lines and rule-less table cells must NOT merge into one
/// oversized block, while genuinely-wrapped paragraphs must still merge.
final class HeaderLineSegmentationTests: XCTestCase {
    private func analyze(_ data: Data) throws -> PDFTextPageAnalysis {
        let pdf = try XCTUnwrap(PDFDocument(data: data))
        let p = try XCTUnwrap(pdf.page(at: 0))
        return PDFTextAnalysisEngine().analyze(data: data, pageIndex: 0, pageRefID: UUID(), fallbackPage: p)
    }

    private func block(_ analysis: PDFTextPageAnalysis, containing needle: String) -> EditableTextBlock? {
        analysis.blocks.first { $0.text.contains(needle) }
    }

    func testHeaderLinesStaySeparate() throws {
        let analysis = try analyze(EditingFixturePDFBuilder.monospacedHeaderPage())

        let title = try XCTUnwrap(block(analysis, containing: "SAMPLE PROJECT"))
        XCTAssertFalse(title.text.contains("Prepared for"), "title must not merge with the prepared-for line")
        XCTAssertFalse(title.text.contains("January"), "title must not merge with the date line")
        XCTAssertEqual(title.lines.count, 1, "title is a single line")

        let prepared = try XCTUnwrap(block(analysis, containing: "Demo Client"))
        XCTAssertFalse(prepared.text.contains("SAMPLE PROJECT"), "prepared-for must not include the title")
        XCTAssertFalse(prepared.text.contains("OVERVIEW"), "prepared-for must not merge with the overview header")

        let date = try XCTUnwrap(block(analysis, containing: "January 2026"))
        XCTAssertFalse(date.text.contains("SAMPLE PROJECT"), "date must not merge with the title")
        XCTAssertFalse(date.text.contains("Demo Client"), "date must not merge with the prepared-for line")

        let overview = try XCTUnwrap(block(analysis, containing: "OVERVIEW"))
        XCTAssertFalse(overview.text.contains("SAMPLE"), "OVERVIEW must not merge with the title")
        XCTAssertFalse(overview.text.contains("Demo Client"), "OVERVIEW must not merge with prepared-for")
    }

    func testWrappedControlParagraphStillMerges() throws {
        let analysis = try analyze(EditingFixturePDFBuilder.monospacedHeaderPage())
        let para = try XCTUnwrap(block(analysis, containing: "real wrapped"))
        XCTAssertTrue(para.text.contains("second line"), "a genuinely wrapped paragraph must still merge into one block")
        XCTAssertGreaterThanOrEqual(para.lines.count, 2, "the wrapped paragraph is multi-line")
    }

    func testRuleLessTableCellsStaySeparate() throws {
        let analysis = try analyze(EditingFixturePDFBuilder.monospacedHeaderPage())
        // The Phase column cells must not concatenate into one block.
        let discovery = try XCTUnwrap(block(analysis, containing: "Discovery"))
        XCTAssertFalse(discovery.text.contains("Build"), "table column cells must not merge (Discovery+Build)")
        XCTAssertFalse(discovery.text.contains("Review"), "table column cells must not merge (Discovery+Review)")
        let header = try XCTUnwrap(block(analysis, containing: "Phase"))
        XCTAssertFalse(header.text.contains("Discovery"), "column header must not merge with its first cell")
    }

    /// Regression for a real bug: `fillsReliablyNarrowedColumn`'s word-count fallback used to
    /// let ANY 3+-word line through regardless of how little of the column it filled, so a
    /// short 3-word table cell ("Net Amt Due") in a reliably-narrowed column (bounded by real
    /// left/right neighbor columns, unlike an isolated paragraph's page-edge-default column)
    /// fused into the cell above it — the exact merge bug this function exists to prevent.
    func testThreeWordTableCellsInReliablyNarrowedColumnStaySeparate() throws {
        var runs: [EditingFixturePDFBuilder.TextRun] = [
            EditingFixturePDFBuilder.TextRun(string: "Phase", origin: CGPoint(x: 54, y: 580), fontName: "Monaco", fontSize: 12),
            EditingFixturePDFBuilder.TextRun(string: "Line Item", origin: CGPoint(x: 200, y: 580), fontName: "Monaco", fontSize: 12),
            EditingFixturePDFBuilder.TextRun(string: "Owner", origin: CGPoint(x: 340, y: 580), fontName: "Monaco", fontSize: 12)
        ]
        // Same-length, non-numeric, mixed-case 3-word cells stacked with normal single
        // spacing in the middle column, which (unlike an isolated paragraph) has both a left
        // ("Phase") and right ("Owner") neighbor column, so its columnBounds is reliably
        // narrowed rather than defaulting to the page edge.
        let middleCells = ["Net Amt Due", "Tax Amt Owe", "Sum Amt Get"]
        var y: CGFloat = 560
        for cell in middleCells {
            runs.append(EditingFixturePDFBuilder.TextRun(string: cell, origin: CGPoint(x: 200, y: y), fontName: "Monaco", fontSize: 12))
            runs.append(EditingFixturePDFBuilder.TextRun(string: "X", origin: CGPoint(x: 54, y: y), fontName: "Monaco", fontSize: 12))
            runs.append(EditingFixturePDFBuilder.TextRun(string: "Y", origin: CGPoint(x: 340, y: y), fontName: "Monaco", fontSize: 12))
            y -= 18
        }
        let data = EditingFixturePDFBuilder.makePDF(runs: runs)
        let analysis = try analyze(data)

        let netAmtDue = try XCTUnwrap(block(analysis, containing: "Net Amt Due"))
        XCTAssertFalse(netAmtDue.text.contains("Tax Amt Owe"), "3-word table cells must not merge (Net Amt Due+Tax Amt Owe)")
        XCTAssertFalse(netAmtDue.text.contains("Sum Amt Get"), "3-word table cells must not merge (Net Amt Due+Sum Amt Get)")
        XCTAssertEqual(netAmtDue.lines.count, 1, "each 3-word cell stays its own single-line block")
    }

    /// Regression for a real bug: `startsWithLabelColon`'s regex only matched letters-only
    /// label tokens, so a digit-containing header field ("Q1 2026 Revenue: 500000") was
    /// invisible to the label-colon role guard and could fuse into an "open"-looking line
    /// directly above it, even though it is a new labeled fact, not that line's continuation.
    func testDigitContainingLabelColonLineDoesNotMergeIntoLineAbove() throws {
        let data = EditingFixturePDFBuilder.makePDF(runs: [
            // Deliberately ends without trailing punctuation ("previousLooksOpen" == true),
            // same left edge/font/size/case-mix as the line below, single-spaced — every
            // OTHER merge guard (font, color, gap, column, wrap-shortfall, indent, all-caps
            // role) is satisfied, so the label-colon guard is what must isolate the two
            // lines. Both lines avoid ascender/descender letters (b/d/f/h/k/l/t/i/j and
            // g/j/p/q/y) and both carry a digit, so the resolved-font-size ink-ratio model
            // (see `InkExtentClass`) puts them in the SAME extent class and `fontsMatch`
            // doesn't reject the pair on an unrelated resolved-size mismatch before the
            // label-colon guard is ever reached.
            EditingFixturePDFBuilder.TextRun(string: "Excess 2026 case revenue occurs", origin: CGPoint(x: 72, y: 700), fontName: "Helvetica", fontSize: 11),
            EditingFixturePDFBuilder.TextRun(string: "Q1 2026 Revenue: 500000", origin: CGPoint(x: 72, y: 684), fontName: "Helvetica", fontSize: 11)
        ])
        let analysis = try analyze(data)
        let summary = try XCTUnwrap(block(analysis, containing: "Excess"))
        XCTAssertFalse(summary.text.contains("Q1 2026 Revenue"), "a digit-containing 'Label: value' line must not merge into the line above it")
    }
}


