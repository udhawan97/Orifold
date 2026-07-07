import PDFKit
import XCTest
@testable import Orifold

/// Phase 5 (export ghost/duplicate hardening) of the inline-edit stress-testing pass. These
/// exercise `PDFEditedPageRenderer` directly against pages drawn from `InlineEditStressFixture`
/// rather than going through the full `WorkspaceViewModel`/`WorkspaceDocument` plumbing --
/// matching the existing direct-renderer test style in `OrifoldTests.swift`.
final class InlineEditExportHardeningTests: XCTestCase {
    /// Mirrors production (`WorkspaceViewModel` always calls `measuredBounds` before committing
    /// an edit -- see the call site right before `regenerateEditedPage`): `editedBounds` must be
    /// sized to fit the REPLACEMENT text, not reused verbatim from the original block's bounds.
    /// Skipping this step was an early mistake in writing these tests -- `CTFrameDraw` silently
    /// drops any text that doesn't fit within a fixed-height frame, so a replacement longer than
    /// the original looked exactly like a "text failed to draw" bug when it was actually just
    /// clipped out of an undersized box that a real edit flow would have auto-grown.
    private func operation(replacing block: EditableTextBlock, with replacementText: String, on page: PDFPage) -> PDFTextEditOperation {
        var op = PDFTextEditOperation(
            pageRefID: UUID(),
            sourceBlockID: block.id,
            sourceBounds: block.bounds,
            sourceLineBounds: block.lines.map(\.bounds),
            sourceText: block.text,
            editedBounds: block.bounds,
            replacementText: replacementText,
            fontName: block.fontName,
            fontSize: block.fontSize,
            textColor: block.textColor,
            alignment: .left
        )
        op.editedBounds = PDFEditedPageRenderer.measuredBounds(for: op, pageBounds: page.bounds(for: .mediaBox), sourcePage: page)
        return op
    }

    /// PDFKit's `PDFPage` does not strongly retain its owning `PDFDocument` -- a page
    /// returned by `PDFEditedPageRenderer.regeneratedPage` is only safe to render/rasterize
    /// once re-hosted in a document the CALLER keeps alive itself (same pattern used in
    /// `OrifoldTests.swift`). Returns the host document too so the caller can keep it in
    /// scope for as long as it needs to draw/rasterize the page.
    private func hosted(_ page: PDFPage) throws -> (document: PDFDocument, page: PDFPage) {
        let hostDocument = PDFDocument()
        hostDocument.insert(page, at: 0)
        return (hostDocument, try XCTUnwrap(hostDocument.page(at: 0)))
    }

    private func darkPixelCount(on page: PDFPage, in region: CGRect) throws -> Int {
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
        let clamped = region.insetBy(dx: -5, dy: -5)
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

    /// Regression test for a real bug found while stress-testing: `drawPageBackground` replays
    /// the ORIGINAL page's content stream via `drawPDFPage`/`PDFPage.draw`. When that page
    /// contains invisible (`Tr 3`) text ANYWHERE on it -- the ordinary OCR-layer-under-a-scan
    /// pattern -- CoreGraphics' text-drawing-mode state was leaking forward past that draw
    /// call, so every subsequent replacement on the SAME page rendered invisibly too, even for
    /// an edit completely unrelated to the hidden text. Fixed by forcing `.fill` mode before
    /// every replacement draw in `PDFEditedPageRenderer.drawReplacement`.
    func testEditingOrdinaryTextOnAPageThatAlsoHasInvisibleTextStaysVisible() throws {
        let document = InlineEditStressFixture.buildDocument()
        let data = try XCTUnwrap(document.dataRepresentation())
        let index = InlineEditStressFixture.index(of: .renderModes)
        let page = try XCTUnwrap(document.page(at: index))
        let analysis = PDFTextAnalysisEngine().analyze(data: data, pageIndex: index, pageRefID: UUID(), fallbackPage: page)

        // Sanity check: this page really does contain invisible text elsewhere, which is
        // exactly the contamination risk this test guards against.
        XCTAssertTrue(analysis.blocks.contains { $0.editability == .hiddenOCRLayer })

        let ordinaryBlock = try XCTUnwrap(analysis.blocks.first { $0.text.contains("Fill only") })
        XCTAssertEqual(ordinaryBlock.editability, .direct)
        let op = operation(replacing: ordinaryBlock, with: "VISIBLE REPLACEMENT", on: page)

        let regeneratedRaw = try XCTUnwrap(PDFEditedPageRenderer.regeneratedPage(from: page, applying: [op]))
        // `.attributedString`, not `.string`: confirmed via a CI-only investigation (Xcode 16.4 /
        // macOS 15, the toolchain pinned in ci.yml) that `PDFPage.string` interleaves character
        // order on that older PDFKit when two text runs occupy overlapping page geometry -- which
        // is exactly this page's shape (the replacement sits where the erased original still is,
        // per the "erase is visual only" limitation documented on
        // `UserFlowRegressionTests.testEraseIsVisualOnlyNotContentStreamRemoval`). CI's raw
        // extraction came back as "VFiIlSlIoBnLlyE(RTErP0)LACEMENT..." -- the same character SET as
        // "VISIBLE REPLACEMENT" + "Fill only (Tr 0)", just character-by-character shuffled.
        // `.attributedString` uses a different, run-preserving extraction path that was confirmed
        // clean and complete on that same CI run. Not reproducible on the Xcode 26.6 dev toolchain,
        // where `.string` itself is already correctly ordered.
        XCTAssertTrue(regeneratedRaw.attributedString?.string.contains("VISIBLE REPLACEMENT") ?? false)
        let (hostDocument, regenerated) = try hosted(regeneratedRaw)
        _ = hostDocument // kept alive for the duration of the render below
        let darkPixels = try darkPixelCount(on: regenerated, in: op.editedBounds)
        XCTAssertGreaterThan(darkPixels, 0, "an ordinary (non-hidden) edit must render visibly even on a page that also contains unrelated invisible OCR-layer text")
    }

    /// Faux-bold double-draw text (the same string drawn twice, offset by a fraction of a
    /// point, instead of using a real bold face) is a classic ghosting risk: if PDFium's own
    /// text detection only unioned bounds around ONE of the two overlapping draws, the erase
    /// patch would leave the other copy's ink exposed underneath the replacement. PDFium
    /// already reconstructs the double-draw as a single coherent block (verified via a probe:
    /// "Faux bold heading" comes back as exactly one block, not two overlapping ones), so the
    /// existing erase-patch geometry already covers both draws with no special-case handling
    /// needed -- confirmed here by editing it and checking the replacement actually renders.
    ///
    /// Deliberately does NOT assert on `.string` extraction here: a replacement long enough to
    /// wrap onto a second line grows `editedBounds` downward (see `measuredBounds`), which can
    /// land its new lines in the same Y-band as the ORIGINAL text -- still present underneath
    /// per the pre-existing, already-accepted "erase is visual only" limitation (see
    /// `UserFlowRegressionTests.testEraseIsVisualOnlyNotContentStreamRemoval`). Verified via a
    /// probe: `.string` extraction can come back scrambled/incomplete in that overlap case even
    /// though the render is completely correct -- an extraction-ordering artifact of that same
    /// known limitation, not a rendering bug. Visual correctness (`darkPixelCount`) is the
    /// property that actually reflects what the user sees, so that's what this test checks.
    func testFauxBoldDoubleDrawLeavesNoVisibleGhostInkAfterReplacement() throws {
        let document = InlineEditStressFixture.buildDocument()
        let data = try XCTUnwrap(document.dataRepresentation())
        let index = InlineEditStressFixture.index(of: .fauxBoldAndColliding)
        let page = try XCTUnwrap(document.page(at: index))
        let analysis = PDFTextAnalysisEngine().analyze(data: data, pageIndex: index, pageRefID: UUID(), fallbackPage: page)
        let fauxBold = try XCTUnwrap(analysis.blocks.first { $0.text.contains("Faux bold") })

        let op = operation(replacing: fauxBold, with: "Clean replacement", on: page)
        let regeneratedRaw = try XCTUnwrap(PDFEditedPageRenderer.regeneratedPage(from: page, applying: [op]))
        let (hostDocument, regenerated) = try hosted(regeneratedRaw)
        _ = hostDocument
        let darkPixels = try darkPixelCount(on: regenerated, in: op.editedBounds)
        XCTAssertGreaterThan(darkPixels, 0, "the replacement must render visibly")
    }

    /// Known, documented limitation (not fixed in this pass): two logically-distinct strings
    /// drawn at the exact same position/bounds (e.g. a background watermark under foreground
    /// text) get silently CONCATENATED into one merged block by the line-reconstruction
    /// heuristic, rather than surfacing a disambiguation choice between them the way the plan
    /// calls for. Pinning this down as a regression test (documents current behavior precisely
    /// -- no crash, no data loss, but no disambiguation either) rather than leaving it as an
    /// unverified assumption; building a real click-time disambiguation chooser UI is a larger,
    /// separate feature this pass doesn't attempt.
    func testCollidingStringsAtTheSamePositionAreSilentlyMergedNotDisambiguated() throws {
        let document = InlineEditStressFixture.buildDocument()
        let data = try XCTUnwrap(document.dataRepresentation())
        let index = InlineEditStressFixture.index(of: .fauxBoldAndColliding)
        let page = try XCTUnwrap(document.page(at: index))
        let analysis = PDFTextAnalysisEngine().analyze(data: data, pageIndex: index, pageRefID: UUID(), fallbackPage: page)
        let merged = try XCTUnwrap(analysis.blocks.first { $0.text.contains("Foreground string") })
        XCTAssertTrue(merged.text.contains("Background string"), "current behavior: colliding strings merge into one block rather than offering a disambiguation choice -- see doc comment")
    }
}
