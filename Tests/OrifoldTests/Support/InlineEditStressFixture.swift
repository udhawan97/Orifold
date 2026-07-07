import AppKit
import CoreText
import PDFKit

/// Builds an in-memory PDF ("inline-edit-stress-test") battery-testing the scenarios the
/// inline text-edit hardening plan calls out: tiny/huge text, extreme spacing/scaling,
/// text- and page-level rotation, every PDF text render mode, low-visibility text, faux-bold
/// double-draws, colliding strings, dense columns, multi-script Unicode, degenerate
/// transforms, off-page text, clipped/clip-path text, and fragmented per-glyph placement.
///
/// Regenerated on every test run rather than checked in as a binary — this repo's existing
/// PDF fixtures (see `ImportStressTests`) are all built programmatically, so a byte-diffable
/// Swift source is consistent with that convention and avoids maintaining an opaque blob.
///
/// Known limitation: true Form XObject reuse (one object referenced by multiple `Do`
/// operators) isn't reachable from AppKit's high-level `dataWithPDF` drawing path. The
/// `.duplicatedFormLikeText` scenario instead draws visually-identical text at two page
/// locations as a best-effort proxy for "reused content that must not mutate every instance
/// when one placement is edited" — it does not exercise literal XObject-identity code paths.
enum InlineEditStressFixture {
    enum Page: Int, CaseIterable {
        case tinyAndHugeText
        case spacingAndScaling
        case textRotation
        case pageLevelRotation
        case renderModes
        case lowVisibility
        case fauxBoldAndColliding
        case duplicatedFormLikeText
        case denseColumns
        case multiScriptUnicode
        case degenerateAndOffPage
        case clippedText
        case fragmentedGlyphs
    }

    static let pageBounds = CGRect(x: 0, y: 0, width: 420, height: 560)

    static func buildDocument() -> PDFDocument {
        let combined = PDFDocument()
        for scenario in Page.allCases {
            let view = StressPageView(scenario: scenario)
            view.frame = pageBounds
            guard let pageData = view.dataWithPDF(inside: view.bounds) as Data?,
                  let single = PDFDocument(data: pageData)?.page(at: 0) else { continue }
            if scenario == .pageLevelRotation {
                single.rotation = 90
            }
            combined.insert(single, at: combined.pageCount)
        }
        return combined
    }

    static func buildData() -> Data {
        buildDocument().dataRepresentation() ?? Data()
    }

    /// Local index of a scenario in the combined document — every scenario is emitted
    /// exactly once, in `Page.allCases` order, so this is just the case's raw index.
    static func index(of scenario: Page) -> Int {
        scenario.rawValue
    }
}

/// Draws one stress-test page. Most scenarios use `NSAttributedString.draw` (adequate for
/// rotation via CTM, spacing/scaling attributes, and plain Unicode shaping); render-mode and
/// clip-path scenarios need direct `CGContext` text-drawing-mode control, which
/// `NSAttributedString` doesn't reliably expose, so those go through `CTLineDraw` instead.
private final class StressPageView: NSView {
    let scenario: InlineEditStressFixture.Page

    init(scenario: InlineEditStressFixture.Page) {
        self.scenario = scenario
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: CGRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        NSColor.white.setFill()
        bounds.fill()
        switch scenario {
        case .tinyAndHugeText: drawTinyAndHugeText(in: context)
        case .spacingAndScaling: drawSpacingAndScaling(in: context)
        case .textRotation: drawTextRotation(in: context)
        case .pageLevelRotation: drawPlainParagraph(in: context)
        case .renderModes: drawRenderModes(in: context)
        case .lowVisibility: drawLowVisibility(in: context)
        case .fauxBoldAndColliding: drawFauxBoldAndColliding(in: context)
        case .duplicatedFormLikeText: drawDuplicatedFormLikeText(in: context)
        case .denseColumns: drawDenseColumns(in: context)
        case .multiScriptUnicode: drawMultiScriptUnicode(in: context)
        case .degenerateAndOffPage: drawDegenerateAndOffPage(in: context)
        case .clippedText: drawClippedText(in: context)
        case .fragmentedGlyphs: drawFragmentedGlyphs(in: context)
        }
    }

    // MARK: - Helpers

    private func attributed(_ string: String, size: CGFloat, color: NSColor = .black, extra: [NSAttributedString.Key: Any] = [:]) -> NSAttributedString {
        var attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size),
            .foregroundColor: color
        ]
        for (key, value) in extra { attrs[key] = value }
        return NSAttributedString(string: string, attributes: attrs)
    }

    private func drawLine(_ text: NSAttributedString, at point: CGPoint, mode: CGTextDrawingMode, in context: CGContext) {
        context.saveGState()
        context.translateBy(x: point.x, y: point.y)
        context.textMatrix = .identity
        context.setTextDrawingMode(mode)
        let line = CTLineCreateWithAttributedString(text)
        CTLineDraw(line, context)
        context.restoreGState()
    }

    private func drawPlainParagraph(in context: CGContext) {
        attributed("Ordinary body text on a page-rotated /Rotate 90 page.", size: 14).draw(at: CGPoint(x: 20, y: 500))
        attributed("Second line, same paragraph, same column.", size: 14).draw(at: CGPoint(x: 20, y: 480))
    }

    // MARK: - Scenarios

    private func drawTinyAndHugeText(in context: CGContext) {
        attributed("1pt: the quick brown fox", size: 1).draw(at: CGPoint(x: 20, y: 530))
        attributed("2pt: the quick brown fox", size: 2).draw(at: CGPoint(x: 20, y: 510))
        attributed("4pt: the quick brown fox", size: 4).draw(at: CGPoint(x: 20, y: 490))
        attributed("12pt normal body text", size: 12).draw(at: CGPoint(x: 20, y: 460))
        attributed("Hg", size: 96).draw(at: CGPoint(x: 20, y: 240))
    }

    private func drawSpacingAndScaling(in context: CGContext) {
        attributed("W i d e   t r a c k i n g", size: 14, extra: [.kern: 6]).draw(at: CGPoint(x: 20, y: 500))
        attributed("Negativetracking", size: 14, extra: [.kern: -1.5]).draw(at: CGPoint(x: 20, y: 470))
        attributed("Huge   word   spacing   here", size: 14, extra: [.kern: 0]).draw(at: CGPoint(x: 20, y: 440))
        // Approximate horizontal scaling (Tz) via a non-uniform CTM around the text draw.
        context.saveGState()
        context.translateBy(x: 20, y: 400)
        context.scaleBy(x: 0.6, y: 1.0)
        attributed("Condensed horizontal scale 60%", size: 14).draw(at: .zero)
        context.restoreGState()
        context.saveGState()
        context.translateBy(x: 20, y: 370)
        context.scaleBy(x: 1.6, y: 1.0)
        attributed("Wide scale 160%", size: 14).draw(at: .zero)
        context.restoreGState()
    }

    private func drawTextRotation(in context: CGContext) {
        let angles: [(CGFloat, CGPoint)] = [
            (45, CGPoint(x: 60, y: 400)),
            (90, CGPoint(x: 200, y: 300)),
            (180, CGPoint(x: 340, y: 460)),
            (270, CGPoint(x: 60, y: 150))
        ]
        for (degrees, origin) in angles {
            context.saveGState()
            context.translateBy(x: origin.x, y: origin.y)
            context.rotate(by: degrees * .pi / 180)
            attributed("Rotated \(Int(degrees))°", size: 14).draw(at: .zero)
            context.restoreGState()
        }
        // Sheared/mirrored text via a non-rotation affine transform.
        context.saveGState()
        context.translateBy(x: 200, y: 80)
        context.concatenate(CGAffineTransform(a: 1, b: 0, c: 0.5, d: 1, tx: 0, ty: 0))
        attributed("Sheared text", size: 14).draw(at: .zero)
        context.restoreGState()
        context.saveGState()
        context.translateBy(x: 200, y: 50)
        context.concatenate(CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: 0, ty: 0))
        attributed("Mirrored text", size: 14).draw(at: .zero)
        context.restoreGState()
    }

    private func drawRenderModes(in context: CGContext) {
        let fill = attributed("Fill only (Tr 0)", size: 16)
        drawLine(fill, at: CGPoint(x: 20, y: 500), mode: .fill, in: context)

        context.setLineWidth(1)
        context.setStrokeColor(NSColor.black.cgColor)
        let stroke = attributed("Stroke only (Tr 1)", size: 16, extra: [
            .strokeWidth: 2.0,
            .strokeColor: NSColor.black
        ])
        drawLine(stroke, at: CGPoint(x: 20, y: 460), mode: .stroke, in: context)

        let fillStroke = attributed("Fill + stroke (Tr 2)", size: 16, color: .systemRed, extra: [
            .strokeWidth: -2.0,
            .strokeColor: NSColor.black
        ])
        drawLine(fillStroke, at: CGPoint(x: 20, y: 420), mode: .fillStroke, in: context)

        let invisible = attributed("Invisible OCR-layer text (Tr 3)", size: 16)
        drawLine(invisible, at: CGPoint(x: 20, y: 380), mode: .invisible, in: context)
    }

    private func drawLowVisibility(in context: CGContext) {
        // White-on-white: real ink, zero perceptual contrast against the page background.
        attributed("White on white", size: 16, color: .white).draw(at: CGPoint(x: 20, y: 500))
        // Near-zero alpha.
        attributed("Near-zero alpha", size: 16, color: NSColor.black.withAlphaComponent(0.01)).draw(at: CGPoint(x: 20, y: 460))
        // Visible control line so the page isn't entirely low-visibility.
        attributed("Visible control text", size: 16).draw(at: CGPoint(x: 20, y: 420))
    }

    private func drawFauxBoldAndColliding(in context: CGContext) {
        // Faux bold: the same string drawn twice, offset by half a point, instead of using an
        // actual bold face — a classic double-draw a naive editor will only patch one copy of.
        let text = attributed("Faux bold heading", size: 18)
        text.draw(at: CGPoint(x: 20, y: 500))
        text.draw(at: CGPoint(x: 20.5, y: 500))

        // Colliding strings: two different runs occupying the same bounding box.
        attributed("Background string", size: 16, color: NSColor.black.withAlphaComponent(0.3))
            .draw(at: CGPoint(x: 20, y: 440))
        attributed("Foreground string", size: 16)
            .draw(at: CGPoint(x: 20, y: 440))
    }

    private func drawDuplicatedFormLikeText(in context: CGContext) {
        let label = attributed("Reused label", size: 14)
        label.draw(at: CGPoint(x: 20, y: 500))
        label.draw(at: CGPoint(x: 20, y: 300))
        label.draw(at: CGPoint(x: 220, y: 300))
    }

    private func drawDenseColumns(in context: CGContext) {
        let leftLines = (0..<14).map { "L\($0) value \($0 * 7)" }
        let rightLines = (0..<14).map { "R\($0) value \($0 * 11)" }
        var y: CGFloat = 530
        for line in leftLines {
            attributed(line, size: 9).draw(at: CGPoint(x: 16, y: y))
            y -= 11
        }
        y = 530
        for line in rightLines {
            attributed(line, size: 9).draw(at: CGPoint(x: 220, y: y))
            y -= 11
        }
    }

    private func drawMultiScriptUnicode(in context: CGContext) {
        let lines = [
            "Chinese: 你好，世界",
            "Japanese: こんにちは世界",
            "Korean: 안녕하세요 세계",
            "Arabic: مرحبا بالعالم",
            "Hebrew: שלום עולם",
            "Devanagari: नमस्ते दुनिया",
            "Thai: สวัสดีชาวโลก",
            "Cyrillic: Привет мир",
            "Greek: Γειά σου Κόσμε",
            "Combining marks: e\u{0301}\u{0300}\u{0302} n\u{0303}",
            "Ligature: office ﬁnally",
            "Fullwidth: Ｈｅｌｌｏ",
            "Math: ∑ ∫ √ ≠ ± π ∞",
            "Symbols: ★ ✂ ✎ ☎",
            "Mixed LTR/RTL: Hello مرحبا World שלום"
        ]
        var y: CGFloat = 530
        for line in lines {
            attributed(line, size: 12).draw(at: CGPoint(x: 16, y: y))
            y -= 24
        }
    }

    private func drawDegenerateAndOffPage(in context: CGContext) {
        // Near-zero-scale transform: must not crash the analysis/hit-test pipeline.
        context.saveGState()
        context.translateBy(x: 100, y: 300)
        context.scaleBy(x: 0.0001, y: 0.0001)
        attributed("Degenerate transform text", size: 14).draw(at: .zero)
        context.restoreGState()

        // Zero-width text (explicit zero-size font as an even more extreme degenerate case).
        attributed("Zero size", size: 0.0001).draw(at: CGPoint(x: 100, y: 260))

        // Off-page text: partially and fully outside the page bounds.
        attributed("Edge text bleeding off the right margin", size: 14).draw(at: CGPoint(x: 380, y: 200))
        attributed("Fully off-page text", size: 14).draw(at: CGPoint(x: -400, y: -200))
        attributed("Visible control text", size: 14).draw(at: CGPoint(x: 20, y: 100))
    }

    private func drawClippedText(in context: CGContext) {
        // Visible bounds narrower than the underlying glyph bounds: clip to a small window
        // before drawing a much longer string.
        context.saveGState()
        context.clip(to: CGRect(x: 20, y: 480, width: 90, height: 30))
        attributed("This text is mostly clipped away and must not leak", size: 16).draw(at: CGPoint(x: 20, y: 484))
        context.restoreGState()

        // Text-as-clip-path: glyphs become a clip mask, not visible ink on their own.
        context.saveGState()
        context.translateBy(x: 20, y: 380)
        context.setTextDrawingMode(.clip)
        let clipLine = CTLineCreateWithAttributedString(attributed("CLIP", size: 40))
        CTLineDraw(clipLine, context)
        context.setFillColor(NSColor.systemTeal.cgColor)
        context.fill(CGRect(x: -10, y: -15, width: 200, height: 60))
        context.restoreGState()
    }

    private func drawFragmentedGlyphs(in context: CGContext) {
        // Per-glyph placement with irregular advances, approximating a raw TJ array that
        // piles/kerns individual glyphs rather than drawing the string as one run.
        let word = "Fragmented"
        var x: CGFloat = 20
        let y: CGFloat = 500
        let jitter: [CGFloat] = [0, 2, -1, 3, 0, 1, -2, 4, 0, 2]
        for (index, character) in word.enumerated() {
            let glyph = attributed(String(character), size: 16)
            glyph.draw(at: CGPoint(x: x, y: y))
            let advance = glyph.size().width
            x += advance + (jitter[index % jitter.count] * 0.3)
        }
    }
}
