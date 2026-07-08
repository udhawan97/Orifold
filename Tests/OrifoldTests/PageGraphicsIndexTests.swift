import PDFKit
import XCTest
@testable import Orifold

/// WP-0 / WP-1: `PageGraphicsIndex` classification and underline detection through the real
/// PDFium analysis engine, plus underline survival across an edit commit.
final class PageGraphicsIndexTests: XCTestCase {
    // MARK: - Classifier unit tests (no PDF)

    func testClassifyHorizontalRule() {
        let rule = PageGraphicsIndex.classify(bounds: CGRect(x: 72, y: 100, width: 200, height: 0.75))
        XCTAssertNotNil(rule)
        XCTAssertTrue(rule?.isHorizontal ?? false)
    }

    func testClassifyVerticalRule() {
        let rule = PageGraphicsIndex.classify(bounds: CGRect(x: 72, y: 100, width: 0.75, height: 200))
        XCTAssertNotNil(rule)
        XCTAssertFalse(rule?.isHorizontal ?? true)
    }

    func testClassifyRejectsThickBlockAndTinyMark() {
        XCTAssertNil(PageGraphicsIndex.classify(bounds: CGRect(x: 0, y: 0, width: 200, height: 40)), "a filled block is not a rule")
        XCTAssertNil(PageGraphicsIndex.classify(bounds: CGRect(x: 0, y: 0, width: 3, height: 0.5)), "too short to be a rule")
        XCTAssertNil(PageGraphicsIndex.classify(bounds: CGRect(x: 0, y: 0, width: 4, height: 4)), "a square is not a rule")
    }

    func testUnderlineRuleQueryMatchesBelowBaseline() {
        var index = PageGraphicsIndex()
        index.add(PageGraphicsIndex.RuleLine(bounds: CGRect(x: 72, y: 98.4, width: 60, height: 1), isHorizontal: true))
        // Run baseline at y=100, font 12 → rule at 98.4 is ~1.6pt below → within band.
        let match = index.underlineRule(forRun: CGRect(x: 72, y: 100, width: 60, height: 9), baseline: 100, fontSize: 12)
        XCTAssertNotNil(match)
        // A rule far below (a separate separator) must not match.
        var faraway = PageGraphicsIndex()
        faraway.add(PageGraphicsIndex.RuleLine(bounds: CGRect(x: 72, y: 60, width: 60, height: 1), isHorizontal: true))
        XCTAssertNil(faraway.underlineRule(forRun: CGRect(x: 72, y: 100, width: 60, height: 9), baseline: 100, fontSize: 12))
    }

    // MARK: - Engine integration

    private func analyze(_ data: Data, page: Int = 0) throws -> PDFTextPageAnalysis {
        let pdf = try XCTUnwrap(PDFDocument(data: data))
        let p = try XCTUnwrap(pdf.page(at: page))
        return PDFTextAnalysisEngine().analyze(data: data, pageIndex: page, pageRefID: UUID(), fallbackPage: p)
    }

    func testEngineDetectsUnderlineOnRealFixture() throws {
        let data = EditingFixturePDFBuilder.underlinedParagraph(text: "Jane Q Public")
        let analysis = try analyze(data)
        XCTAssertFalse(analysis.graphics.horizontalRules.isEmpty, "the underline stroke must be classified as a horizontal rule")
        let name = try XCTUnwrap(analysis.blocks.first { $0.text.contains("Jane") })
        XCTAssertTrue(name.underline, "the underlined name block must be detected as underlined")
        XCTAssertFalse(name.underlineBounds.isEmpty, "the underline stroke rect must be recorded for erase coverage")
        // The non-underlined line must NOT be flagged.
        if let plain = analysis.blocks.first(where: { $0.text.contains("Contact") }) {
            XCTAssertFalse(plain.underline, "the non-underlined line must not be flagged as underlined")
        }
    }

    func testEngineDetectsTableRules() throws {
        let data = EditingFixturePDFBuilder.tableWithRules()
        let analysis = try analyze(data)
        XCTAssertGreaterThanOrEqual(analysis.graphics.horizontalRules.count, 3, "table horizontal rules must be detected")
        XCTAssertGreaterThanOrEqual(analysis.graphics.verticalRules.count, 2, "table vertical rules must be detected")
        // The bold heading above the table must NOT merge into the header row block.
        let heading = analysis.blocks.first { $0.text.contains("Quarterly Summary") }
        XCTAssertNotNil(heading, "heading must remain its own block")
        XCTAssertFalse(heading?.text.contains("Region") ?? false, "heading must not merge across the table's top rule into the header row")
    }

    /// Underline survives a commit: after editing the underlined name, the regenerated page
    /// still renders an underline stroke, and the committed op carries underline + stroke bounds.
    func testUnderlineSurvivesEditCommit() throws {
        let data = EditingFixturePDFBuilder.underlinedParagraph(text: "Jane Q Public")
        let analysis = try analyze(data)
        let block = try XCTUnwrap(analysis.blocks.first { $0.text.contains("Jane") })
        XCTAssertTrue(block.underline)

        var op = PDFTextEditOperation(
            pageRefID: UUID(),
            sourceBlockID: block.id,
            sourceBounds: block.bounds,
            sourceLineBounds: block.lines.map(\.bounds),
            sourceUnderlineBounds: block.underlineBounds,
            sourceText: block.text,
            editedBounds: block.bounds,
            replacementText: "Jane Q Public",   // same text, underline must persist
            fontName: block.fontName,
            fontSize: block.fontSize,
            textColor: block.textColor,
            alignment: .left,
            underline: true
        )
        let pdf = try XCTUnwrap(PDFDocument(data: data))
        let page = try XCTUnwrap(pdf.page(at: 0))
        op.editedBounds = PDFEditedPageRenderer.measuredBounds(for: op, pageBounds: page.bounds(for: .mediaBox), sourcePage: page)
        let regenerated = try XCTUnwrap(PDFEditedPageRenderer.regeneratedPage(from: page, applying: [op]))

        // The erase list must include the underline stroke (so the OLD stroke is covered),
        // and the replacement is drawn underlined (op.underline == true → CoreText underline).
        let erase = PDFEditedPageRenderer.eraseBounds(for: op, on: page)
        XCTAssertTrue(erase.contains { r in block.underlineBounds.contains { $0.standardized.intersects(r.standardized) } },
                      "erase must cover the original underline stroke")

        // Render check: a dark pixel row must exist just below the text baseline (the new
        // underline). Render the regenerated page and sample the underline band.
        let host = PDFDocument(); host.insert(regenerated, at: 0)
        let hosted = try XCTUnwrap(host.page(at: 0))
        let underlineBand = CGRect(x: block.bounds.minX, y: block.bounds.minY - 3, width: block.bounds.width, height: 3)
        XCTAssertGreaterThan(try darkPixels(on: hosted, in: underlineBand), 0, "the replacement must render an underline stroke")
    }

    private func darkPixels(on page: PDFPage, in region: CGRect) throws -> Int {
        let bounds = page.bounds(for: .mediaBox)
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(bounds.width), pixelsHigh: Int(bounds.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        let ctx = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: rep)?.cgContext)
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(CGRect(origin: .zero, size: bounds.size))
        page.draw(with: .mediaBox, to: ctx)
        var count = 0
        let clamped = region.standardized.insetBy(dx: -2, dy: -2)
        for y in stride(from: max(0, Int(clamped.minY)), to: min(Int(bounds.height), Int(clamped.maxY)), by: 1) {
            for x in stride(from: max(0, Int(clamped.minX)), to: min(Int(bounds.width), Int(clamped.maxX)), by: 1) {
                guard let color = rep.colorAt(x: x, y: Int(bounds.height) - y - 1)?.usingColorSpace(.sRGB) else { continue }
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                color.getRed(&r, green: &g, blue: &b, alpha: &a)
                if a > 0.5, max(r, g, b) < 0.5 { count += 1 }
            }
        }
        return count
    }
}
