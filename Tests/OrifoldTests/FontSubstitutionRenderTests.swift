import CoreText
import PDFKit
import XCTest
@testable import Orifold

/// Feature E4: verifies the editor resolves unembedded standard fonts to their bundled
/// metric-compatible substitutes (asserted via CoreText family/PostScript names -- never
/// `PDFPage.string`, which is unreliable on CI's older PDFKit), and measures the export
/// size spike from embedding a substitution font so the feature can stay display-first if
/// embedding turns out to be expensive.
final class FontSubstitutionRenderTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        FontRegistrar.registerBundledFonts()
    }

    // MARK: - Render-side resolution

    /// The headline case: text whose PDF font is unembedded ArialMT resolves to the bundled
    /// Liberation Sans (metric-compatible with Arial), not a blind Helvetica fallback.
    func testUnembeddedArialResolvesToLiberationSansNotHelvetica() {
        let arial = NSFont(name: "ArialMT", size: 12) ?? .systemFont(ofSize: 12)
        let family = InlineTextEditorOverlay.editingFamilyName(for: arial, fallback: "ArialMT")
        XCTAssertEqual(family, "Liberation Sans")
        XCTAssertNotEqual(family, "Helvetica")

        // ...and the font the editor actually builds for that family is the bundled face.
        let font = InlineTextEditorOverlay.editingFont(family: family, traits: [], size: 12)
        XCTAssertEqual(CTFontCopyFamilyName(font) as String, "Liberation Sans")
        XCTAssertEqual(CTFontCopyPostScriptName(font) as String, "LiberationSans")
    }

    func testUnembeddedStandardFontsResolveToBundledSubstitutes() {
        let cases: [(psName: String, family: String, postScript: String)] = [
            ("ArialMT", "Liberation Sans", "LiberationSans"),
            ("TimesNewRomanPSMT", "Liberation Serif", "LiberationSerif"),
            ("CourierNewPSMT", "Liberation Mono", "LiberationMono"),
            ("Calibri", "Carlito", "Carlito-Regular"),
            ("Cambria", "Caladea", "Caladea-Regular"),
            ("ABCDEF+ArialMT", "Liberation Sans", "LiberationSans"),   // subset-tagged
        ]
        for (psName, expectedFamily, expectedPostScript) in cases {
            let source = NSFont(name: psName, size: 12) ?? .systemFont(ofSize: 12)
            let family = InlineTextEditorOverlay.editingFamilyName(for: source, fallback: psName)
            XCTAssertEqual(family, expectedFamily, "\(psName) should resolve to \(expectedFamily)")

            let font = InlineTextEditorOverlay.editingFont(family: family, traits: [], size: 12)
            XCTAssertEqual(CTFontCopyFamilyName(font) as String, expectedFamily)
            XCTAssertEqual(CTFontCopyPostScriptName(font) as String, expectedPostScript)
        }
    }

    /// A genuinely-unknown (or already-embedded) font is left alone -- substitution must not
    /// hijack every edit.
    func testUnknownFontIsNotSubstituted() {
        let helvetica = NSFont(name: "Helvetica", size: 12) ?? .systemFont(ofSize: 12)
        XCTAssertEqual(InlineTextEditorOverlay.editingFamilyName(for: helvetica, fallback: "Helvetica"), "Helvetica")
    }

    // MARK: - Analysis -> substitution seam (Feature E CRITICAL)

    /// The substitution DECISION must key off the block's RAW unembedded `/BaseFont` name, not
    /// the display `fontName` that `resolveFontPostScriptName` already collapsed onto a stock
    /// family. Calibri/Cambria normalize to Arial/Times *before* substitution runs, so keying
    /// off the resolved name silently degrades them to Liberation Sans/Serif and never reaches
    /// Carlito/Caladea. This routes a synthetic block -- the raw name plus the SAME normalized
    /// `fontName` the engine would derive (computed via the real resolver, so the test rides
    /// the actual analysis->substitution seam) -- through the editor's `editingFamilyName` and
    /// asserts the editing family lands on the right metric-clone even for the Windows-only
    /// faces that never install on macOS. The family string comes from the substitution table,
    /// so the assertion holds whether or not Arial/Calibri/Cambria are installed.
    func testEditingFamilyKeysOffRawPDFFontNameNotNormalizedFallback() {
        let cases: [(raw: String, expectedFamily: String)] = [
            ("Calibri", "Carlito"),
            ("Cambria", "Caladea"),
            ("ArialMT", "Liberation Sans"),  // control: Arial ships on macOS, always worked
        ]
        for (raw, expectedFamily) in cases {
            // What the engine stores in `block.fontName`: the resolver's normalized display
            // name (Calibri->Arial*, Cambria->Times*).
            let normalized = PDFTextAnalysisEngine.testResolveFontPostScriptName(
                from: raw, weightHint: nil, italicHint: false
            )
            let block = makeBlock(fontName: normalized, rawFontName: raw)
            let font = NSFont(name: block.fontName, size: 12) ?? .systemFont(ofSize: 12)

            let family = InlineTextEditorOverlay.editingFamilyName(
                for: font, fallback: block.fontName, substitutionSource: block.rawFontName
            )
            XCTAssertEqual(
                family, expectedFamily,
                "raw \(raw) (normalized to \(normalized)) should edit as \(expectedFamily)"
            )
        }
    }

    /// The mirror of the seam test: keying substitution off the NORMALIZED display name alone
    /// (the pre-fix wiring) cannot reach Carlito/Caladea, because Calibri/Cambria have already
    /// been collapsed to Arial/Times by then. Locks in *why* `editingFamilyName` must consult
    /// `substitutionSource` rather than `fallback` for the decision -- if this ever starts
    /// passing via the fallback path, the raw-name plumbing has been silently short-circuited.
    func testNormalizedFallbackAloneCannotReachCarlitoOrCaladea() {
        for (raw, wrongIfReached) in [("Calibri", "Carlito"), ("Cambria", "Caladea")] {
            let normalized = PDFTextAnalysisEngine.testResolveFontPostScriptName(
                from: raw, weightHint: nil, italicHint: false
            )
            let font = NSFont(name: normalized, size: 12) ?? .systemFont(ofSize: 12)
            // No substitutionSource -> the decision falls back to the normalized name.
            let viaNormalized = InlineTextEditorOverlay.editingFamilyName(for: font, fallback: normalized)
            XCTAssertNotEqual(
                viaNormalized, wrongIfReached,
                "normalized \(normalized) must NOT reach the raw-\(raw) substitute via fallback alone"
            )
        }
    }

    // MARK: - Export size spike

    /// SIZE SPIKE (medium-confidence risk in docs/WAVE_2_PLAN.md): editing text with a
    /// substitution font and exporting draws that font into a CoreGraphics PDF context, which
    /// subset-embeds it. This measures the per-document byte cost of that embedding by diffing
    /// an exported replacement drawn with the bundled Liberation Sans against the same
    /// replacement drawn with base-14 Helvetica (which needs no embedding). If the delta ever
    /// exceeded ~2-3 MB/doc the feature would have to stay display-only + warn on export; the
    /// assertion locks in that it does not.
    func testSubstitutionFontEmbeddingStaysWithinBudget() throws {
        let (sourceDocument, page) = try blankLetterPage()
        _ = sourceDocument // keep the owning document alive while `page` is used

        // A glyph-rich pangram so a realistic subset (not one or two glyphs) gets embedded.
        let paragraph = "The quick brown fox jumps over the lazy dog. "
            + "Sphinx of black quartz, judge my vow! 0123456789 — em-dash, curly quotes."

        let liberationBytes = try overlayByteCount(fontName: "LiberationSans", text: paragraph, on: page)
        let helveticaBytes = try overlayByteCount(fontName: "Helvetica", text: paragraph, on: page)
        let delta = liberationBytes - helveticaBytes

        print("[E4 size spike] Liberation Sans overlay = \(liberationBytes) bytes; "
            + "Helvetica overlay = \(helveticaBytes) bytes; embedding delta = \(delta) bytes "
            + "(\(String(format: "%.1f", Double(delta) / 1024)) KB).")

        // The whole feature's viability gate: a substituted edit must not bloat a document by
        // multiple megabytes. CoreGraphics subsets, so this is expected to be a few KB.
        XCTAssertLessThan(
            delta, 2_000_000,
            "Embedding a substitution font added \(delta) bytes/doc -- over budget; substitution "
                + "should be constrained to display-only with an export warning."
        )
        // NOTE: the delta is expected to be small and can even be NEGATIVE (Liberation subsets
        // tighter than base-14 Helvetica's overlay -- observed ~ -1.2 KB), so this test only
        // gates the upper bound. That the substitution font is genuinely embedded (not silently
        // fallen back to a system face) is asserted separately by
        // `testSubstitutionFontIsActuallyEmbedded`, which inspects the embedded /BaseFont name.
    }

    /// The teeth the size-spike test lacks: prove the exported overlay actually EMBEDS the
    /// Liberation substitute rather than silently falling back to a system font. Extracts the
    /// embedded font name straight from the rendered PDF via PDFium (`PDFTextAnalysisEngine`
    /// analysis -> `rawFontName`, the same FPDFText path the editor uses -- never
    /// `PDFPage.string`, which is unreliable on CI's older PDFKit) and asserts it is a
    /// Liberation face. If substitution ever stops embedding (font unregistered, drawn with a
    /// fallback), the embedded name changes and this fails.
    func testSubstitutionFontIsActuallyEmbedded() throws {
        let (sourceDocument, page) = try blankLetterPage()
        _ = sourceDocument
        let paragraph = "The quick brown fox jumps over the lazy dog. "
            + "Sphinx of black quartz, judge my vow! 0123456789"

        let overlay = try renderOverlay(fontName: "LiberationSans", text: paragraph, on: page)
        let analysis = PDFTextAnalysisEngine().analyze(
            data: overlay, pageIndex: 0, pageRefID: UUID(), fallbackPage: nil
        )
        let embeddedNames = analysis.blocks.compactMap(\.rawFontName)
        XCTAssertFalse(analysis.blocks.isEmpty, "overlay must expose an analyzable text layer")
        XCTAssertTrue(
            embeddedNames.contains { $0.localizedCaseInsensitiveContains("Liberation") },
            "substituted overlay must embed a Liberation face; embedded /BaseFont names were \(embeddedNames)"
        )
    }

    // MARK: - Helpers

    /// A minimal detected block carrying a normalized display `fontName` alongside the raw
    /// `/BaseFont` name, matching what `PDFTextAnalysisEngine.buildBlock` now produces.
    private func makeBlock(fontName: String, rawFontName: String?) -> EditableTextBlock {
        EditableTextBlock(
            pageRefID: nil,
            text: "sample",
            bounds: CGRect(x: 0, y: 0, width: 100, height: 20),
            lines: [],
            fontName: fontName,
            rawFontName: rawFontName,
            fontSize: 12,
            textColor: .documentText,
            rotation: 0,
            baseline: 0,
            confidence: .high
        )
    }

    private func overlayByteCount(fontName: String, text: String, on page: PDFPage) throws -> Int {
        try renderOverlay(fontName: fontName, text: text, on: page).count
    }

    /// Renders `text` as a committed replacement drawn in `fontName` and returns the exported
    /// overlay PDF bytes, so callers can both size and re-analyze the embedded font.
    private func renderOverlay(fontName: String, text: String, on page: PDFPage) throws -> Data {
        let bounds = CGRect(x: 72, y: 560, width: 460, height: 160)
        var op = PDFTextEditOperation(
            pageRefID: UUID(),
            sourceBlockID: UUID(),
            sourceBounds: bounds,
            sourceLineBounds: [bounds],
            sourceText: "original",
            editedBounds: bounds,
            replacementText: text,
            fontName: fontName,
            fontSize: 18,
            textColor: .documentText,
            alignment: .left,
            // Route ReplacementTextLayout through `operation.fontName` (not the preserved
            // original style) so the drawn/embedded font is the one under test.
            didManuallyChangeStyle: true
        )
        op.editedBounds = PDFEditedPageRenderer.measuredBounds(
            for: op, pageBounds: page.bounds(for: .mediaBox), sourcePage: page
        )
        return try XCTUnwrap(
            PDFEditedPageRenderer.replacementOverlayData(from: page, applying: [op]),
            "replacement overlay should render for \(fontName)"
        )
    }

    private func blankLetterPage() throws -> (PDFDocument, PDFPage) {
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        let data = NSMutableData()
        let consumer = try XCTUnwrap(CGDataConsumer(data: data as CFMutableData))
        let context = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &mediaBox, nil))
        context.beginPDFPage(nil)
        context.setFillColor(NSColor.white.cgColor)
        context.fill(mediaBox)
        context.endPDFPage()
        context.closePDF()

        let document = try XCTUnwrap(PDFDocument(data: data as Data))
        let page = try XCTUnwrap(document.page(at: 0))
        return (document, page)
    }
}
