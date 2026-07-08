import PDFKit
import XCTest
@testable import Orifold

/// WP-5 (bullets stay put) and WP-6 (interactive backing transparency).
final class BulletAndOverlayTests: XCTestCase {
    private func analyze(_ data: Data) throws -> PDFTextPageAnalysis {
        let pdf = try XCTUnwrap(PDFDocument(data: data))
        let p = try XCTUnwrap(pdf.page(at: 0))
        return PDFTextAnalysisEngine().analyze(data: data, pageIndex: 0, pageRefID: UUID(), fallbackPage: p)
    }

    /// The bullet marker is a separate block from the item text, so editing the text can
    /// never move the bullet.
    func testBulletMarkerIsSeparateFromItemText() throws {
        let data = EditingFixturePDFBuilder.bulletList()
        let analysis = try analyze(data)

        // There must be standalone bullet blocks whose text is just the marker.
        let markerBlocks = analysis.blocks.filter { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) == "\u{2022}" }
        XCTAssertGreaterThanOrEqual(markerBlocks.count, 1, "at least one bullet marker must be its own block")

        // The item text blocks must NOT contain the bullet glyph.
        let itemBlocks = analysis.blocks.filter { $0.text.contains("migration") || $0.text.contains("load time") || $0.text.contains("Mentored") }
        XCTAssertFalse(itemBlocks.isEmpty, "item text must be detected")
        for item in itemBlocks {
            XCTAssertFalse(item.text.contains("\u{2022}"), "item text block must not include the bullet marker: \(item.text)")
            // The item's x-origin is to the RIGHT of the bullet's — editing it starts at the text.
            if let marker = markerBlocks.first {
                XCTAssertGreaterThan(item.bounds.minX, marker.bounds.maxX - 2, "item text must begin after the bullet marker")
            }
        }
    }

    /// Editing an item's text and committing must leave the bullet marker's ink untouched.
    func testEditingBulletItemLeavesMarkerInPlace() throws {
        let data = EditingFixturePDFBuilder.bulletList()
        let analysis = try analyze(data)
        let item = try XCTUnwrap(analysis.blocks.first { $0.text.contains("migration") })
        let marker = try XCTUnwrap(analysis.blocks.first { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) == "\u{2022}" && abs($0.bounds.midY - item.bounds.midY) < 6 })

        let pdf = try XCTUnwrap(PDFDocument(data: data))
        let page = try XCTUnwrap(pdf.page(at: 0))
        let markerRegion = marker.bounds.standardized
        let before = try darkPixels(on: page, in: markerRegion)
        XCTAssertGreaterThan(before, 0, "sanity: bullet is inked")

        var op = PDFTextEditOperation(
            pageRefID: UUID(), sourceBlockID: item.id, sourceBounds: item.bounds,
            sourceLineBounds: item.lines.map(\.bounds), sourceText: item.text,
            editedBounds: item.bounds, replacementText: "Led a different initiative",
            fontName: item.fontName, fontSize: item.fontSize, textColor: item.textColor, alignment: .left
        )
        op.editedBounds = PDFEditedPageRenderer.measuredBounds(for: op, pageBounds: page.bounds(for: .mediaBox), sourcePage: page)
        let regenerated = try XCTUnwrap(PDFEditedPageRenderer.regeneratedPage(from: page, applying: [op]))
        let host = PDFDocument(); host.insert(regenerated, at: 0)
        let after = try darkPixels(on: try XCTUnwrap(host.page(at: 0)), in: markerRegion)
        XCTAssertGreaterThanOrEqual(after, before / 2, "the bullet marker must remain inked after editing the item text (before=\(before) after=\(after))")
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
}
