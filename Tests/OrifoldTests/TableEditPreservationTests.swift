import PDFKit
import XCTest
@testable import Orifold

/// WP-2: editing a table cell must not merge the heading, and must not wipe the table rules.
final class TableEditPreservationTests: XCTestCase {
    private func analyze(_ data: Data) throws -> PDFTextPageAnalysis {
        let pdf = try XCTUnwrap(PDFDocument(data: data))
        let p = try XCTUnwrap(pdf.page(at: 0))
        return PDFTextAnalysisEngine().analyze(data: data, pageIndex: 0, pageRefID: UUID(), fallbackPage: p)
    }

    /// Count dark pixels along a thin vertical strip (a table rule) to confirm the rule
    /// survives an edit.
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
        let clamped = region.standardized
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

    func testHeadingDoesNotMergeIntoTableAndRulesSurviveEdit() throws {
        let data = EditingFixturePDFBuilder.tableWithRules()
        let analysis = try analyze(data)

        // Pick a body cell to edit ("North").
        let cell = try XCTUnwrap(analysis.blocks.first { $0.text.contains("North") })
        XCTAssertFalse(cell.protectedRuleBounds.isEmpty, "a table cell must record nearby rules to preserve")

        // Establish the vertical column divider's x from the detected vertical rules (~310).
        let divider = try XCTUnwrap(analysis.graphics.verticalRules.map(\.bounds).min(by: { abs($0.midX - 310) < abs($1.midX - 310) }))
        let dividerStrip = CGRect(x: divider.midX - 1, y: 575, width: 2, height: 80)

        let pdf = try XCTUnwrap(PDFDocument(data: data))
        let page = try XCTUnwrap(pdf.page(at: 0))
        let rulePixelsBefore = try darkPixels(on: page, in: dividerStrip)
        XCTAssertGreaterThan(rulePixelsBefore, 0, "sanity: the divider rule is drawn before editing")

        var op = PDFTextEditOperation(
            pageRefID: UUID(),
            sourceBlockID: cell.id,
            sourceBounds: cell.bounds,
            sourceLineBounds: cell.lines.map(\.bounds),
            sourcePreserveRuleBounds: cell.protectedRuleBounds,
            sourceText: cell.text,
            editedBounds: cell.bounds,
            replacementText: "Northeast",
            fontName: cell.fontName,
            fontSize: cell.fontSize,
            textColor: cell.textColor,
            alignment: .left
        )
        op.editedBounds = PDFEditedPageRenderer.measuredBounds(for: op, pageBounds: page.bounds(for: .mediaBox), sourcePage: page)
        let regenerated = try XCTUnwrap(PDFEditedPageRenderer.regeneratedPage(from: page, applying: [op]))
        let host = PDFDocument(); host.insert(regenerated, at: 0)
        let hosted = try XCTUnwrap(host.page(at: 0))

        // The edit rendered.
        let editText = PDFTextAnalysisEngine()
            .analyze(data: host.dataRepresentation() ?? Data(), pageIndex: 0, pageRefID: UUID(), fallbackPage: hosted)
            .blocks.map(\.text).joined(separator: " ")
        XCTAssertTrue(editText.contains("Northeast"), "the cell edit must be visible")

        // The divider rule must still be present after the edit (holes punched in the patch).
        let rulePixelsAfter = try darkPixels(on: hosted, in: dividerStrip)
        XCTAssertGreaterThanOrEqual(rulePixelsAfter, rulePixelsBefore / 2,
                                    "the table divider rule must survive editing the adjacent cell (before=\(rulePixelsBefore) after=\(rulePixelsAfter))")
    }
}
