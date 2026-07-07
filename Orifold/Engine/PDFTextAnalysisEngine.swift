import AppKit
import Foundation
import PDFKit

@_silgen_name("FPDF_LoadPage")
private func FPDF_LoadPage(_ document: OpaquePointer?, _ pageIndex: Int32) -> OpaquePointer?

@_silgen_name("FPDF_ClosePage")
private func FPDF_ClosePage(_ page: OpaquePointer?)

@_silgen_name("FPDFText_LoadPage")
private func FPDFText_LoadPage(_ page: OpaquePointer?) -> OpaquePointer?

@_silgen_name("FPDFText_ClosePage")
private func FPDFText_ClosePage(_ textPage: OpaquePointer?)

@_silgen_name("FPDFText_CountChars")
private func FPDFText_CountChars(_ textPage: OpaquePointer?) -> Int32

@_silgen_name("FPDFText_GetUnicode")
private func FPDFText_GetUnicode(_ textPage: OpaquePointer?, _ index: Int32) -> UInt32

@_silgen_name("FPDFText_GetCharBox")
private func FPDFText_GetCharBox(
    _ textPage: OpaquePointer?,
    _ index: Int32,
    _ left: UnsafeMutablePointer<Double>?,
    _ right: UnsafeMutablePointer<Double>?,
    _ bottom: UnsafeMutablePointer<Double>?,
    _ top: UnsafeMutablePointer<Double>?
) -> Int32

@_silgen_name("FPDFText_GetFontSize")
private func FPDFText_GetFontSize(_ textPage: OpaquePointer?, _ index: Int32) -> Double

@_silgen_name("FPDFText_GetFillColor")
private func FPDFText_GetFillColor(
    _ textPage: OpaquePointer?,
    _ index: Int32,
    _ r: UnsafeMutablePointer<UInt32>?,
    _ g: UnsafeMutablePointer<UInt32>?,
    _ b: UnsafeMutablePointer<UInt32>?,
    _ a: UnsafeMutablePointer<UInt32>?
) -> Int32

@_silgen_name("FPDFText_GetFontInfo")
private func FPDFText_GetFontInfo(
    _ textPage: OpaquePointer?,
    _ index: Int32,
    _ buffer: UnsafeMutableRawPointer?,
    _ buflen: UInt,
    _ flags: UnsafeMutablePointer<Int32>?
) -> UInt

@_silgen_name("FPDFText_GetFontWeight")
private func FPDFText_GetFontWeight(_ textPage: OpaquePointer?, _ index: Int32) -> Int32

@_silgen_name("FPDFText_GetCharAngle")
private func FPDFText_GetCharAngle(_ textPage: OpaquePointer?, _ index: Int32) -> Float

/// Layout-compatible with PDFium's `FS_MATRIX` (six packed floats, `a b c d e f`, matching
/// `CGAffineTransform`'s `a b c d tx ty`).
private struct FSMatrix {
    var a: Float = 0
    var b: Float = 0
    var c: Float = 0
    var d: Float = 0
    var e: Float = 0
    var f: Float = 0
}

@_silgen_name("FPDFText_GetMatrix")
private func FPDFText_GetMatrix(_ textPage: OpaquePointer?, _ index: Int32, _ matrix: UnsafeMutablePointer<FSMatrix>?) -> Int32

@_silgen_name("FPDFText_GetStrokeColor")
private func FPDFText_GetStrokeColor(
    _ textPage: OpaquePointer?,
    _ index: Int32,
    _ r: UnsafeMutablePointer<UInt32>?,
    _ g: UnsafeMutablePointer<UInt32>?,
    _ b: UnsafeMutablePointer<UInt32>?,
    _ a: UnsafeMutablePointer<UInt32>?
) -> Int32

@_silgen_name("FPDFText_IsGenerated")
private func FPDFText_IsGenerated(_ textPage: OpaquePointer?, _ index: Int32) -> Int32

@_silgen_name("FPDFPage_CountObjects")
private func FPDFPage_CountObjects(_ page: OpaquePointer?) -> Int32

@_silgen_name("FPDFPage_GetObject")
private func FPDFPage_GetObject(_ page: OpaquePointer?, _ index: Int32) -> OpaquePointer?

@_silgen_name("FPDFPageObj_GetType")
private func FPDFPageObj_GetType(_ pageObject: OpaquePointer?) -> Int32

@_silgen_name("FPDFPageObj_GetBounds")
private func FPDFPageObj_GetBounds(
    _ pageObject: OpaquePointer?,
    _ left: UnsafeMutablePointer<Float>?,
    _ bottom: UnsafeMutablePointer<Float>?,
    _ right: UnsafeMutablePointer<Float>?,
    _ top: UnsafeMutablePointer<Float>?
) -> Int32

@_silgen_name("FPDFTextObj_GetTextRenderMode")
private func FPDFTextObj_GetTextRenderMode(_ textObject: OpaquePointer?) -> Int32

/// PDFium's `FPDF_PAGEOBJ_TEXT` page-object type constant.
private let kPDFPageObjectTypeText: Int32 = 1

/// PDFium's `FPDF_TEXTRENDERMODE_INVISIBLE` (PDF spec `Tr 3`) constant.
private let kPDFTextRenderModeInvisible: Int32 = 3

/// PDF font-descriptor `/Flags` bit for an italic/oblique face (bit 7, value 64). Set even
/// when the embedded font's PostScript name carries no "Italic"/"Oblique" token, so it is
/// the only reliable slant signal for many documents.
private let kPDFFontFlagItalic: Int32 = 1 << 6

struct PDFTextPageAnalysis {
    var pageRefID: UUID?
    var blocks: [EditableTextBlock]
}

final class PDFTextAnalysisEngine {
    private struct CharacterSample {
        var scalar: UnicodeScalar
        var bounds: CGRect?
        /// nil when FPDFText_GetFontSize reported an implausible value for this glyph
        /// (common for CoreText-drawn replacement text, and for some glyphs even in the
        /// original PDF's own embedded font). Resolved per-line in blocksFromSamples,
        /// preferring other glyphs' valid readings from the same line over guessing from
        /// this one glyph's own bounding box, since sizes are uniform within a run/line.
        var reportedFontSize: CGFloat?
        var color: CodableColor
        var rawFontName: String?
        /// PDFium-reported font weight (100–900), or nil when unavailable. Used so a
        /// Semibold/Bold body face whose PostScript name carries no "Bold" token still
        /// resolves to a bold substitute instead of a lighter-looking regular one.
        var fontWeight: Int?
        /// True when the embedded font descriptor's italic flag is set, even if the font
        /// name has no "Italic"/"Oblique" token.
        var isItalic: Bool
        /// This glyph's own content-stream rotation in degrees, derived from
        /// `FPDFText_GetCharAngle` (radians). nil when PDFium can't report an angle for this
        /// glyph — never assume 0 in that case, since 0 is also a legitimate reading for
        /// upright text.
        var angleDegrees: CGFloat?
        /// This glyph's full text-rendering matrix, when PDFium can report one.
        var transform: PDFTextTransform?
        var strokeColor: CodableColor?
        /// True when PDFium synthesized this glyph (e.g. a missing/unmappable glyph filled
        /// in) rather than reading it from the document's own embedded font.
        var isGenerated: Bool
        /// The PDF render mode (`Tr`) of whichever page object this glyph's bounds best
        /// match, resolved via `renderModeRegions`. nil when no page-object region could be
        /// matched (e.g. a degenerate/zero-size glyph with no usable bounds).
        var renderMode: Int32?
    }

    /// One text page-object's declared bounds and PDF render mode (`Tr`), used to look up
    /// which render mode applies to a given glyph. PDFium's char-level text API (used for
    /// everything else in this file) has no render-mode accessor of its own — only the
    /// page-object API does — so this is a separate pass matched back to glyphs by bounds.
    private struct RenderModeRegion {
        var bounds: CGRect
        var mode: Int32
    }

    private func renderModeRegions(page: OpaquePointer?) -> [RenderModeRegion] {
        let count = FPDFPage_CountObjects(page)
        guard count > 0 else { return [] }
        var regions: [RenderModeRegion] = []
        regions.reserveCapacity(Int(count))
        for index in 0..<count {
            guard let object = FPDFPage_GetObject(page, index),
                  FPDFPageObj_GetType(object) == kPDFPageObjectTypeText else { continue }
            var left: Float = 0
            var bottom: Float = 0
            var right: Float = 0
            var top: Float = 0
            guard FPDFPageObj_GetBounds(object, &left, &bottom, &right, &top) != 0,
                  right > left, top > bottom else { continue }
            let mode = FPDFTextObj_GetTextRenderMode(object)
            regions.append(RenderModeRegion(
                bounds: CGRect(x: CGFloat(left), y: CGFloat(bottom), width: CGFloat(right - left), height: CGFloat(top - bottom)),
                mode: mode
            ))
        }
        return regions
    }

    /// The render mode of whichever region's bounds most tightly contain `bounds`'s center —
    /// "most tightly" (smallest matching region) so a small glyph inside a larger overlapping
    /// text object resolves to its own object's mode rather than an unrelated bigger one.
    private func renderMode(for bounds: CGRect, in regions: [RenderModeRegion]) -> Int32? {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        return regions
            .filter { $0.bounds.insetBy(dx: -0.5, dy: -0.5).contains(center) }
            .min { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height }?
            .mode
    }

    func analyze(data: Data, pageIndex: Int, pageRefID: UUID? = nil, fallbackPage: PDFPage? = nil) -> PDFTextPageAnalysis {
        if let pdfium = analyzeWithPDFium(data: data, pageIndex: pageIndex, pageRefID: pageRefID, sourcePage: fallbackPage),
           !pdfium.blocks.isEmpty {
            return pdfium
        }
        return analyzeWithPDFKit(page: fallbackPage, pageRefID: pageRefID)
    }

    /// Tiered hit test: a click is checked against every hittable block's own bounds first
    /// (tight tolerance), and among ties the SMALLEST containing block wins — so clicking a
    /// word in a dense table grabs that cell, not the whole row/paragraph. If nothing tightly
    /// contains the point, retry with a per-block adaptive band (roughly half that block's own
    /// line height) so a click landing in inter-word/inter-line whitespace just outside the
    /// tight glyph ink still resolves instead of silently falling through to a blank insertion
    /// box. `.insertion` blocks (the synthetic "nothing was detected here" placeholder) are
    /// never candidates — callers build one of those themselves once hitTest returns nil.
    func hitTest(_ point: CGPoint, in analysis: PDFTextPageAnalysis, tolerance: CGFloat = 5) -> EditableTextBlock? {
        let candidates = analysis.blocks.filter { $0.editability != .insertion }
        guard !candidates.isEmpty else { return nil }

        let tightHits = candidates.filter { $0.bounds.insetBy(dx: -tolerance, dy: -tolerance).contains(point) }
        if let best = smallestBlock(among: tightHits) {
            return best
        }

        let bandHits = candidates.filter { block in
            // Band from the block's LINE height, not its whole (possibly multi-line
            // paragraph) height — a 15-line paragraph's bounds.height would otherwise
            // grant it a ~100pt gravity band that swallows clicks intended for small
            // neighbors above/below it.
            let lineHeights = block.lines.map(\.bounds.height).sorted()
            let lineHeight = lineHeights.isEmpty
                ? max(block.fontSize * 1.3, 10)
                : lineHeights[lineHeights.count / 2]
            let bandTolerance = max(tolerance, lineHeight * 0.5)
            return block.bounds.insetBy(dx: -bandTolerance, dy: -bandTolerance * 0.6).contains(point)
        }
        return smallestBlock(among: bandHits)
    }

    private func smallestBlock(among blocks: [EditableTextBlock]) -> EditableTextBlock? {
        blocks.min { ($0.bounds.width * $0.bounds.height) < ($1.bounds.width * $1.bounds.height) }
    }

    private func analyzeWithPDFium(data: Data, pageIndex: Int, pageRefID: UUID?, sourcePage: PDFPage?) -> PDFTextPageAnalysis? {
        guard !data.isEmpty, data.count <= Int(Int32.max) else { return nil }
        pdfiumLock.lock()
        defer { pdfiumLock.unlock() }
        FPDF_InitLibrary()
        defer { FPDF_DestroyLibrary() }

        return data.withUnsafeBytes { rawBuffer -> PDFTextPageAnalysis? in
            guard let baseAddress = rawBuffer.baseAddress else { return nil }
            guard let document = FPDF_LoadMemDocument(baseAddress, Int32(data.count), nil) else { return nil }
            defer { FPDF_CloseDocument(document) }

            guard let page = FPDF_LoadPage(document, Int32(pageIndex)) else { return nil }
            defer { FPDF_ClosePage(page) }
            guard let textPage = FPDFText_LoadPage(page) else { return nil }
            defer { FPDFText_ClosePage(textPage) }

            let count = Int(FPDFText_CountChars(textPage))
            guard count > 0 else { return PDFTextPageAnalysis(pageRefID: pageRefID, blocks: []) }

            let regions = renderModeRegions(page: page)
            var samples: [CharacterSample] = []
            samples.reserveCapacity(count)
            for index in 0..<count {
                let unicode = FPDFText_GetUnicode(textPage, Int32(index))
                guard let scalar = UnicodeScalar(unicode), scalar.value != 0 else { continue }
                var left = 0.0
                var right = 0.0
                var bottom = 0.0
                var top = 0.0
                let hasBox = FPDFText_GetCharBox(textPage, Int32(index), &left, &right, &bottom, &top) != 0
                let bounds = hasBox && right > left && top > bottom
                    ? CGRect(x: left, y: bottom, width: right - left, height: top - bottom)
                    : nil
                let size = FPDFText_GetFontSize(textPage, Int32(index))
                let color = fillColor(textPage: textPage, index: index)
                let reportedFontSize: CGFloat? = size.isFinite && size >= 4 ? CGFloat(size) : nil
                let descriptor = fontDescriptor(textPage: textPage, index: index)
                let rawWeight = FPDFText_GetFontWeight(textPage, Int32(index))
                let rawAngle = FPDFText_GetCharAngle(textPage, Int32(index))
                let angleDegrees: CGFloat? = rawAngle.isFinite ? CGFloat(rawAngle) * 180 / .pi : nil
                var fsMatrix = FSMatrix()
                let hasMatrix = FPDFText_GetMatrix(textPage, Int32(index), &fsMatrix) != 0
                let transform: PDFTextTransform? = hasMatrix
                    ? PDFTextTransform(a: CGFloat(fsMatrix.a), b: CGFloat(fsMatrix.b), c: CGFloat(fsMatrix.c), d: CGFloat(fsMatrix.d), e: CGFloat(fsMatrix.e), f: CGFloat(fsMatrix.f))
                    : nil
                let isGenerated = FPDFText_IsGenerated(textPage, Int32(index)) == 1
                samples.append(CharacterSample(
                    scalar: scalar,
                    bounds: bounds,
                    reportedFontSize: reportedFontSize,
                    color: color,
                    rawFontName: descriptor.name,
                    fontWeight: rawWeight > 0 ? Int(rawWeight) : nil,
                    isItalic: descriptor.isItalic,
                    angleDegrees: angleDegrees,
                    transform: transform,
                    strokeColor: strokeColor(textPage: textPage, index: index),
                    isGenerated: isGenerated,
                    renderMode: bounds.flatMap { renderMode(for: $0, in: regions) }
                ))
            }

            let blocks = blocksFromSamples(samples, pageRefID: pageRefID, confidence: .high, sourcePage: sourcePage)
            return PDFTextPageAnalysis(pageRefID: pageRefID, blocks: blocks)
        }
    }

    private func fontDescriptor(textPage: OpaquePointer?, index: Int) -> (name: String?, isItalic: Bool) {
        var buffer = [UInt8](repeating: 0, count: 256)
        var flags: Int32 = 0
        let needed = buffer.withUnsafeMutableBytes { rawBuffer -> UInt in
            FPDFText_GetFontInfo(textPage, Int32(index), rawBuffer.baseAddress, UInt(rawBuffer.count), &flags)
        }
        let isItalic = flags & kPDFFontFlagItalic != 0
        guard needed > 1, needed <= buffer.count else { return (nil, isItalic) }
        let byteCount = Int(needed) - 1 // FPDFText_GetFontInfo includes a trailing NUL
        return (String(bytes: buffer[0..<byteCount], encoding: .utf8), isItalic)
    }

    /// Maps a font name recovered from the PDF's embedded font descriptor to a PostScript
    /// name Orifold can actually draw with (`NSFont(name:)`), so replacement text matches
    /// the surrounding document's typography instead of always falling back to Helvetica.
    /// `weightHint` (100–900, PDFium's reported weight) and `italicHint` (descriptor italic
    /// flag) come straight from the embedded font descriptor and take precedence over
    /// name-token guessing — a Semibold/Bold face whose PostScript name lacks a "Bold"
    /// token, or an italic face with no "Italic" token, would otherwise resolve to a
    /// lighter/upright substitute that no longer matches the surrounding document.
    private static func resolveFontPostScriptName(
        from pdfFontName: String,
        weightHint: Int? = nil,
        italicHint: Bool = false
    ) -> String {
        var name = pdfFontName
        // Subsetted fonts are prefixed with a 6-letter tag + "+", e.g. "ABCDEF+Georgia-Bold".
        if let plusIndex = name.firstIndex(of: "+"),
           name.distance(from: name.startIndex, to: plusIndex) == 6,
           name[..<plusIndex].allSatisfy({ $0.isUppercase || $0.isNumber }) {
            name = String(name[name.index(after: plusIndex)...])
        }
        let lower = name.lowercased()
        let boldByName = lower.contains("bold") || lower.contains("black") || lower.contains("heavy") || lower.contains("semibold")
        let italicByName = lower.contains("italic") || lower.contains("oblique")
        let boldByWeight = (weightHint ?? 0) >= 600
        let wantsBold = boldByName || boldByWeight
        let wantsItalic = italicByName || italicHint
        if lower.hasPrefix(".") ||
            lower.contains("sfns") ||
            lower.contains("apple") && lower.contains("system") {
            return stableSansSerifPostScriptName(bold: wantsBold, italic: wantsItalic)
        }
        // Even when the named font exists on the system, honor a descriptor weight/slant the
        // name itself omits by promoting to the matching face of the same family (e.g.
        // "Helvetica" + weight 700 → "Helvetica-Bold") rather than drawing it regular.
        if NSFont(name: name, size: 12) != nil {
            if let promoted = promoteToTraits(fontNamed: name, bold: wantsBold, italic: wantsItalic) {
                return promoted
            }
            return name
        }

        let isBold = wantsBold
        let isItalic = wantsItalic
        let family: String
        if lower.contains("georgia") {
            family = "Georgia"
        } else if lower.contains("carlito") || lower.contains("calibri") {
            family = "Arial"
        } else if lower.contains("times") || lower.contains("garamond") || lower.contains("cambria") || lower.contains("minion") || lower.contains("serif") {
            family = "Times New Roman"
        } else if lower.contains("courier") || lower.contains("consolas") || lower.contains("mono") {
            family = "Courier New"
        } else if lower.contains("menlo") {
            family = "Menlo"
        } else if lower.contains("avenir") {
            family = "Avenir"
        } else {
            family = "Helvetica"
        }

        var traits: NSFontTraitMask = []
        if isBold { traits.insert(.boldFontMask) }
        if isItalic { traits.insert(.italicFontMask) }
        if let matched = NSFontManager.shared.font(withFamily: family, traits: traits, weight: isBold ? 9 : 5, size: 12) {
            return matched.fontName
        }
        return family == "Helvetica" ? "Helvetica" : (NSFont(name: family, size: 12)?.fontName ?? "Helvetica")
    }

    #if DEBUG
    /// Test hook for the private font-resolution logic (weight/italic descriptor hints).
    static func testResolveFontPostScriptName(from name: String, weightHint: Int?, italicHint: Bool) -> String {
        resolveFontPostScriptName(from: name, weightHint: weightHint, italicHint: italicHint)
    }
    #endif

    private static func stableSansSerifPostScriptName(bold: Bool = false, italic: Bool = false) -> String {
        let base = NSFont(name: "HelveticaNeue", size: 12) != nil ? "HelveticaNeue" : "Helvetica"
        if bold || italic, let promoted = promoteToTraits(fontNamed: base, bold: bold, italic: italic) {
            return promoted
        }
        return base
    }

    /// Returns the PostScript name of `fontNamed`'s same-family face carrying the requested
    /// bold/italic traits, or nil when no restyle is needed / no such face exists. Keeps the
    /// family (and thus the document's typographic character) while honoring a weight/slant
    /// the base name didn't encode.
    private static func promoteToTraits(fontNamed name: String, bold: Bool, italic: Bool) -> String? {
        guard bold || italic, let base = NSFont(name: name, size: 12) else { return nil }
        let currentTraits = NSFontManager.shared.traits(of: base)
        var traits = currentTraits
        if bold { traits.insert(.boldFontMask) }
        if italic { traits.insert(.italicFontMask) }
        guard traits != currentTraits,
              let family = base.familyName,
              let promoted = NSFontManager.shared.font(
                  withFamily: family,
                  traits: traits,
                  weight: bold ? 9 : 5,
                  size: 12
              ),
              promoted.fontName != base.fontName else { return nil }
        return promoted.fontName
    }

    /// PDFium occasionally mis-decodes a ligature glyph (e.g. the "ti"/"tf" letter pair
    /// rendered as one glyph) into an unrelated character — "Generative" reads back as
    /// "Genera+ve" — when a PDF's ToUnicode table doesn't cover ligature glyphs, even
    /// though the glyphs themselves draw correctly on screen. PDFKit's own text-selection
    /// API tends to resolve this correctly, so prefer it when it plausibly describes the
    /// same span (similar length) rather than trusting PDFium's transcription blindly.
    static func reconcileLigatures(_ pdfiumText: String, bounds: CGRect, sourcePage: PDFPage?) -> String {
        guard let sourcePage,
              let rawPDFKitText = sourcePage.selection(for: bounds)?.string else {
            return pdfiumText
        }
        let pdfKitText = rawPDFKitText
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pdfKitText.isEmpty else { return pdfiumText }
        let ratio = Double(pdfKitText.count) / Double(max(pdfiumText.count, 1))
        guard ratio >= 0.6, ratio <= 1.6 else { return pdfiumText }
        return pdfKitText
    }

    private func fillColor(textPage: OpaquePointer?, index: Int) -> CodableColor {
        var r: UInt32 = 0
        var g: UInt32 = 0
        var b: UInt32 = 0
        var a: UInt32 = 255
        guard FPDFText_GetFillColor(textPage, Int32(index), &r, &g, &b, &a) != 0 else {
            return .documentText
        }
        return CodableColor(
            red: CGFloat(r) / 255,
            green: CGFloat(g) / 255,
            blue: CGFloat(b) / 255,
            alpha: CGFloat(a) / 255
        )
    }

    private func strokeColor(textPage: OpaquePointer?, index: Int) -> CodableColor? {
        var r: UInt32 = 0
        var g: UInt32 = 0
        var b: UInt32 = 0
        var a: UInt32 = 255
        guard FPDFText_GetStrokeColor(textPage, Int32(index), &r, &g, &b, &a) != 0 else {
            return nil
        }
        return CodableColor(
            red: CGFloat(r) / 255,
            green: CGFloat(g) / 255,
            blue: CGFloat(b) / 255,
            alpha: CGFloat(a) / 255
        )
    }

    private func blocksFromSamples(_ samples: [CharacterSample], pageRefID: UUID?, confidence: PDFTextEditConfidence, sourcePage: PDFPage?) -> [EditableTextBlock] {
        var lines: [[CharacterSample]] = []
        for sample in samples {
            if CharacterSet.newlines.contains(sample.scalar) {
                continue
            }
            guard let bounds = sample.bounds else {
                if sample.scalar.value == 32, var last = lines.popLast() {
                    last.append(sample)
                    lines.append(last)
                }
                continue
            }
            let midY = bounds.midY
            if let lineIndex = lines.firstIndex(where: { existing in
                guard let existingBounds = unionBounds(existing.compactMap(\.bounds)) else { return false }
                return abs(existingBounds.midY - midY) <= max(existingBounds.height, bounds.height) * 0.6
            }) {
                lines[lineIndex].append(sample)
            } else {
                lines.append([sample])
            }
        }

        let lineBlocks = lines.flatMap { rawLine -> [EditableTextBlock] in
            let sorted = rawLine.sorted {
                ($0.bounds?.minX ?? .greatestFiniteMagnitude) < ($1.bounds?.minX ?? .greatestFiniteMagnitude)
            }
            // Glyphs are grouped into a "line" by vertical position only, so visually
            // separate columns that share a baseline (e.g. a row of metric numbers, or a
            // heading and its right-aligned date) collapse into one line. Split on large
            // horizontal gaps so each column becomes its own editable block — otherwise
            // editing one cell reflows the whole row left-aligned and destroys the spacing.
            return splitIntoColumns(sorted).compactMap { segment in
                buildBlock(from: segment, pageRefID: pageRefID, confidence: confidence, sourcePage: sourcePage)
            }
        }
        let pageBounds = sourcePage?.bounds(for: .cropBox)
            ?? unionBounds(lineBlocks.map(\.bounds))?.insetBy(dx: -24, dy: -24)
            ?? .zero
        let merged = mergeWrappedLines(assignColumnBounds(to: lineBlocks, pageBounds: pageBounds))
        return inferAlignment(tightenColumnsToParagraphMargins(merged))
            .sorted { $0.bounds.minY > $1.bounds.minY }
    }

    /// Best-effort paragraph alignment inferred purely from geometry — PDFium reports no
    /// paragraph-alignment attribute directly, and this only ever replaces a silent `nil`
    /// (which every consumer already coalesces to `.left`), so a missed detection is
    /// invisible while a wrong one would visibly move text on Format Painter apply.
    ///
    /// Deliberately does NOT compare a block's lines against its OWN `columnBounds`:
    /// `assignColumnBounds` always pins a column's left edge to that same block's own
    /// `bounds.minX` (see `assignColumnBounds`, `leftEdge = max(pageBounds.minX + 8,
    /// block.bounds.minX)`), so every block — including a visibly centered or right-aligned
    /// isolated heading with no same-row neighbor — would trivially measure as flush-left
    /// against its own column and centered/right alignment could never be detected. Instead,
    /// judge every block's lines against the PAGE's typical left/right text margins.
    ///
    /// That reference is the MEDIAN left/right extent across all detected blocks, not the
    /// min/max: a single outlier block (a page number, footer, or watermark sitting
    /// unusually far left or right) would otherwise silently drag the "typical" margin for
    /// every OTHER block on the page — a page number at the gutter could make ordinary
    /// left-aligned body text measure as far from the (wrongly narrow) left margin as it is
    /// from the right one, misreading it as centered or right-aligned. The median is
    /// resistant to exactly one such outlier. A median needs enough samples to mean
    /// anything, though — on a page with only a couple of detected blocks it degenerates back
    /// to "one block's own edge," so skip inference entirely below that threshold and leave
    /// alignment at the safe, uninferred `.left` default rather than guess from too little
    /// data.
    private func inferAlignment(_ blocks: [EditableTextBlock]) -> [EditableTextBlock] {
        guard blocks.count >= 3 else { return blocks }
        let sortedLefts = blocks.map(\.bounds.minX).sorted()
        let sortedRights = blocks.map(\.bounds.maxX).sorted()
        let typicalLeft = sortedLefts[sortedLefts.count / 2]
        let typicalRight = sortedRights[sortedRights.count / 2]
        return blocks.map { block in
            guard !block.lines.isEmpty else { return block }
            var updated = block
            updated.alignment = inferredAlignment(for: block.lines, typicalLeft: typicalLeft, typicalRight: typicalRight)
            return updated
        }
    }

    private func inferredAlignment(for lines: [PDFTextLine], typicalLeft: CGFloat, typicalRight: CGFloat) -> CodableTextAlignment {
        // Proportional to typical glyph sidebearing rather than a fixed pixel count, so it
        // scales sensibly across the wide range of detected font sizes.
        let tolerance: CGFloat = 4
        var leftFlushCount = 0
        var rightFlushCount = 0
        var centeredCount = 0
        for line in lines {
            let bounds = line.bounds.standardized
            let leftMargin = bounds.minX - typicalLeft
            let rightMargin = typicalRight - bounds.maxX
            let isLeftFlush = leftMargin <= tolerance
            let isRightFlush = rightMargin <= tolerance
            if isLeftFlush, isRightFlush {
                // Fills the typical margins edge to edge — not diagnostic either way.
                continue
            } else if isRightFlush {
                rightFlushCount += 1
            } else if isLeftFlush {
                leftFlushCount += 1
            } else if abs(leftMargin - rightMargin) <= tolerance * 2 {
                centeredCount += 1
            }
        }
        let total = leftFlushCount + rightFlushCount + centeredCount
        guard total > 0 else { return .left }
        if rightFlushCount * 2 > total, rightFlushCount >= leftFlushCount {
            return .right
        }
        if centeredCount * 2 > total {
            return .center
        }
        return .left
    }

    /// After wrapped lines are merged into paragraphs, pull each full-width body
    /// paragraph's column right edge in to the paragraph's OWN right margin (its widest
    /// line).
    ///
    /// `assignColumnBounds` runs per single line and, when a body paragraph has no
    /// detected right-neighbor, defaults the column right edge to the page edge. A normal
    /// single-column paragraph never fills the page to its edge, so that inflated column
    /// later lets edited text re-wrap out into the original right margin — the reported
    /// "text bleeds right after an edit" bug. Once lines are merged we finally know the
    /// paragraph's true right margin (`bounds.maxX`, the widest wrapped line), so clamp
    /// the column to it.
    ///
    /// Guardrails so this never over-constrains: only applies to already-wrapped
    /// paragraphs (`lines.count > 1`) whose ink actually *fills* most of the detected
    /// column (`fillRatio`). A stack of short distinct lines (heading / item / caption)
    /// that merged loosely, or a genuinely narrow snippet, keeps its wide column so a
    /// replacement longer than the original can still grow rightward instead of being
    /// force-wrapped onto extra lines.
    private func tightenColumnsToParagraphMargins(_ blocks: [EditableTextBlock]) -> [EditableTextBlock] {
        blocks.map { block in
            guard block.lines.count > 1, let column = block.columnBounds, column.width > 0 else { return block }
            // Only a paragraph that already spans most of its column has an established
            // right margin worth preserving. Loosely-merged short lines do not.
            let fillRatio = block.bounds.width / column.width
            guard fillRatio >= 0.6 else { return block }
            // One space/word of slack so a replacement word a hair longer than the
            // original longest line still fits without forcing an extra wrapped line.
            let paragraphRightMargin = block.bounds.maxX + max(6, block.fontSize)
            let tightenedMaxX = min(column.maxX, paragraphRightMargin)
            guard tightenedMaxX > column.minX, tightenedMaxX < column.maxX else { return block }
            var updated = block
            updated.columnBounds = CGRect(
                x: column.minX,
                y: column.minY,
                width: tightenedMaxX - column.minX,
                height: column.height
            )
            return updated
        }
    }

    /// Splits a single vertically-grouped line into separate column segments wherever the
    /// horizontal gap between consecutive glyphs is far wider than a normal inter-word
    /// space. Normal prose (word gaps ≈ 0.2–0.4× the text height) stays intact; real
    /// column gutters (several × the text height) break into their own segments.
    private func splitIntoColumns(_ sortedLine: [CharacterSample]) -> [[CharacterSample]] {
        let heights = sortedLine.compactMap { $0.bounds?.height }.sorted()
        guard heights.count > 1 else { return [sortedLine] }
        let medianHeight = heights[heights.count / 2]
        // The median GLYPH INK height is x-height dominated (~0.5-0.6× the point size),
        // so a 1.5× multiplier put the split point around 0.78em — squarely inside the
        // range justified/loosely-set prose stretches ordinary word gaps to (up to ~1em).
        // That shattered such paragraphs into single-word "blocks". Real column gutters
        // sit at several ems; 2.2× ink height (~1.2em) keeps stretched word gaps intact
        // while still splitting genuine gutters.
        let gapThreshold = max(medianHeight * 2.2, 8)
        var segments: [[CharacterSample]] = []
        var current: [CharacterSample] = []
        var prevMaxX: CGFloat?
        for sample in sortedLine {
            if let bounds = sample.bounds {
                if let prev = prevMaxX, bounds.minX - prev > gapThreshold, !current.isEmpty {
                    segments.append(current)
                    current = []
                }
                current.append(sample)
                prevMaxX = max(prevMaxX ?? bounds.maxX, bounds.maxX)
            } else {
                // Whitespace/no-bounds glyph: keep it with the current segment.
                current.append(sample)
            }
        }
        if !current.isEmpty { segments.append(current) }
        return segments
    }

    private func buildBlock(from segment: [CharacterSample], pageRefID: UUID?, confidence: PDFTextEditConfidence, sourcePage: PDFPage?) -> EditableTextBlock? {
        let sorted = segment.sorted {
            ($0.bounds?.minX ?? .greatestFiniteMagnitude) < ($1.bounds?.minX ?? .greatestFiniteMagnitude)
        }
        let rawText = String(String.UnicodeScalarView(sorted.map(\.scalar)))
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawText.isEmpty,
              let bounds = unionBounds(sorted.compactMap(\.bounds)),
              bounds.width > 2,
              bounds.height > 2 else { return nil }
        let text = Self.reconcileLigatures(rawText, bounds: bounds, sourcePage: sourcePage)

        let inkSamples = sorted.filter { $0.scalar.value != 32 }
        let color = dominantColor(among: inkSamples) ?? .documentText
        let rawFontName = dominantFontName(among: inkSamples)
        let weightHint = dominantFontWeight(among: inkSamples)
        let italicHint = dominantItalic(among: inkSamples)
        let fontName = rawFontName.map {
            Self.resolveFontPostScriptName(from: $0, weightHint: weightHint, italicHint: italicHint)
        } ?? Self.resolveFontPostScriptName(from: "Helvetica", weightHint: weightHint, italicHint: italicHint)
        let fontSize = resolveLineFontSize(sorted, lineBounds: bounds, resolvedFontName: fontName)
        let rotationDegrees = dominantAngle(among: inkSamples) ?? 0
        let transform = dominantTransform(among: inkSamples)
        let strokeColor = dominantStrokeColor(among: inkSamples)
        let hasSyntheticGlyphs = inkSamples.contains(where: \.isGenerated)
        let pageRotation = sourcePage?.rotation ?? 0
        let editability = editability(for: inkSamples, color: color)
        let run = PDFTextRun(
            text: text,
            bounds: bounds,
            fontName: fontName,
            fontSize: fontSize,
            textColor: color,
            rotation: rotationDegrees,
            baseline: bounds.minY,
            confidence: confidence,
            strokeColor: strokeColor,
            transform: transform,
            hasSyntheticGlyphs: hasSyntheticGlyphs
        )
        let line = PDFTextLine(text: text, bounds: bounds, runs: [run], confidence: confidence)
        return EditableTextBlock(
            pageRefID: pageRefID,
            text: text,
            bounds: bounds.insetBy(dx: -2, dy: -2),
            lines: [line],
            columnBounds: nil,
            fontName: fontName,
            fontSize: fontSize,
            textColor: color,
            rotation: rotationDegrees,
            pageRotation: pageRotation,
            baseline: bounds.minY,
            confidence: confidence,
            editability: editability,
            textSource: .pdfiumGlyphs,
            strokeColor: strokeColor,
            transform: transform,
            hasSyntheticGlyphs: hasSyntheticGlyphs
        )
    }

    /// A near-zero fill alpha below this threshold is treated as effectively invisible ink —
    /// loose enough to catch anti-aliasing/rounding noise in a genuinely-transparent fill
    /// without misclassifying merely-light (but intentionally visible) text.
    private static let lowVisibilityAlphaThreshold: CGFloat = 0.05

    /// `.hiddenOCRLayer` takes priority over `.lowVisibility` when a run somehow qualifies as
    /// both — an explicit invisible render mode is a stronger, more specific signal than an
    /// incidental near-zero fill alpha reading.
    private func editability(for inkSamples: [CharacterSample], color: CodableColor) -> PDFTextEditability {
        let invisibleCount = inkSamples.filter { $0.renderMode == kPDFTextRenderModeInvisible }.count
        if !inkSamples.isEmpty, invisibleCount * 2 > inkSamples.count {
            return .hiddenOCRLayer
        }
        if color.alpha < Self.lowVisibilityAlphaThreshold {
            return .lowVisibility
        }
        return .direct
    }

    /// A line/segment can open with a differently-styled run (a hyperlink, an inline code
    /// span, a highlighted keyword) before the ordinary body-colored text that makes up
    /// most of the line. Picking the FIRST glyph's color would recolor the whole block —
    /// including words nowhere near that leading run — to the minority color once any word
    /// in the block is edited. Count glyphs per color bucket (rounded to absorb anti-
    /// aliasing noise) and keep whichever color actually covers the most characters.
    private func dominantColor(among samples: [CharacterSample]) -> CodableColor? {
        guard !samples.isEmpty else { return nil }
        var counts: [String: (count: Int, color: CodableColor)] = [:]
        for sample in samples {
            let key = colorBucketKey(sample.color)
            counts[key, default: (0, sample.color)].count += 1
            counts[key]?.color = sample.color
        }
        return counts.values.max { $0.count < $1.count }?.color
    }

    private func colorBucketKey(_ color: CodableColor) -> String {
        func bucket(_ value: CGFloat) -> Int { Int((value * 20).rounded()) }
        return "\(bucket(color.red)),\(bucket(color.green)),\(bucket(color.blue)),\(bucket(color.alpha))"
    }

    /// Same reasoning as `dominantColor`: a leading hyperlink/keyword run may also use a
    /// distinct embedded font before the body text's own font resumes.
    private func dominantFontName(among samples: [CharacterSample]) -> String? {
        guard !samples.isEmpty else { return nil }
        var counts: [String: Int] = [:]
        for sample in samples {
            guard let name = sample.rawFontName else { continue }
            counts[name, default: 0] += 1
        }
        return counts.max { $0.value < $1.value }?.key
    }

    /// Median reported weight across the line's ink glyphs (ignoring glyphs PDFium couldn't
    /// report a weight for). Same "trust the majority, not the first glyph" reasoning as
    /// `dominantColor`/`dominantFontName`: a leading bold keyword must not mark the whole
    /// body line bold, nor a stray light glyph un-bold a genuinely bold line.
    private func dominantFontWeight(among samples: [CharacterSample]) -> Int? {
        let weights = samples.compactMap(\.fontWeight).filter { $0 > 0 }.sorted()
        guard !weights.isEmpty else { return nil }
        return weights[weights.count / 2]
    }

    /// True when MOST of the line's ink glyphs are italic — one incidental italic run
    /// shouldn't slant the whole block, and vice-versa.
    private func dominantItalic(among samples: [CharacterSample]) -> Bool {
        guard !samples.isEmpty else { return false }
        let italicCount = samples.filter(\.isItalic).count
        return italicCount * 2 > samples.count
    }

    /// Median reported rotation across the line's ink glyphs, in degrees. Uses the same
    /// "median, not first-glyph" reasoning as `dominantFontWeight`: a run's glyphs should
    /// all share one content-stream rotation, but any single glyph's angle reading can be
    /// noisy right at the seam between two runs on the same line.
    private func dominantAngle(among samples: [CharacterSample]) -> CGFloat? {
        let angles = samples.compactMap(\.angleDegrees).sorted()
        guard !angles.isEmpty else { return nil }
        return angles[angles.count / 2]
    }

    /// The transform belonging to whichever glyph's angle reading is closest to the
    /// already-chosen `dominantAngle`, so the returned matrix is consistent with the
    /// rotation this block actually reports rather than an arbitrary glyph's.
    private func dominantTransform(among samples: [CharacterSample]) -> PDFTextTransform? {
        guard let targetAngle = dominantAngle(among: samples) else {
            return samples.first(where: { $0.transform != nil })?.transform
        }
        return samples
            .filter { $0.transform != nil && $0.angleDegrees != nil }
            .min { abs($0.angleDegrees! - targetAngle) < abs($1.angleDegrees! - targetAngle) }?
            .transform
    }

    /// Same majority-vote reasoning as `dominantColor`, applied to stroke color.
    private func dominantStrokeColor(among samples: [CharacterSample]) -> CodableColor? {
        let strokeColors = samples.compactMap(\.strokeColor)
        guard !strokeColors.isEmpty else { return nil }
        var counts: [String: (count: Int, color: CodableColor)] = [:]
        for color in strokeColors {
            let key = colorBucketKey(color)
            counts[key, default: (0, color)].count += 1
            counts[key]?.color = color
        }
        return counts.values.max { $0.count < $1.count }?.color
    }

    /// Runs when PDFium extracted zero usable glyph boxes for the page (unusual encodings,
    /// CID fonts PDFium can't box, some malformed content streams) but `page.string` proves
    /// PDFKit itself can still see a text layer. Rather than returning one whole-page,
    /// `.low`-confidence block that `hitTest` used to silently exclude — the historical
    /// "blank white box" bug, since PDFium-empty pages fell straight through to an empty
    /// insertion block even though the text was right there — reconstruct LINE-LEVEL blocks
    /// from PDFKit's own selection geometry so clicking a visible line still opens the editor
    /// prefilled with that line's real text. Font/size here are necessarily approximate (no
    /// per-glyph font data is available from this path), so these are tagged `.replace`
    /// rather than `.direct`.
    private func analyzeWithPDFKit(page: PDFPage?, pageRefID: UUID?) -> PDFTextPageAnalysis {
        guard let page,
              let pageText = page.string,
              !pageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return PDFTextPageAnalysis(pageRefID: pageRefID, blocks: [])
        }
        let cropBox = page.bounds(for: .cropBox)
        guard let fullSelection = page.selection(for: cropBox) else {
            return PDFTextPageAnalysis(pageRefID: pageRefID, blocks: [wholePageFallbackBlock(page: page, pageRefID: pageRefID, cropBox: cropBox, text: pageText)])
        }

        let lineSelections = fullSelection.selectionsByLine()
        let columnBounds = cropBox.insetBy(dx: 24, dy: 8)
        let lineBlocks: [EditableTextBlock] = lineSelections.compactMap { selection in
            let text = (selection.string ?? "")
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            let rawBounds = selection.bounds(for: page)
            guard rawBounds.width > 2, rawBounds.height > 2 else { return nil }
            let fontName = "Helvetica"
            // A PDFKit line SELECTION rect spans the full line box (ascent + descent +
            // leading ≈ 1.15-1.3× the point size), not glyph ink — feeding it through the
            // ink-height model overestimated fallback sizes by ~20-35%, so fallback
            // replacements rendered visibly oversized. Divide by a line-box factor instead.
            let estimatedSize = max(4, rawBounds.height / 1.22)
            return EditableTextBlock(
                pageRefID: pageRefID,
                text: text,
                bounds: rawBounds.insetBy(dx: -2, dy: -2),
                // Each fallback block is exactly one PDFKit line selection, so its own
                // (tighter, un-inset) selection rect is the true erase geometry — using it
                // here instead of leaving `lines` empty stops `PDFEditedPageRenderer`'s
                // erase patch from falling back to the wider hit-test-tolerance `bounds`
                // above (which carries an extra -2pt allowance not needed for erasing).
                lines: [PDFTextLine(text: text, bounds: rawBounds, runs: [], confidence: .medium)],
                columnBounds: columnBounds,
                fontName: fontName,
                fontSize: estimatedSize > 0 ? estimatedSize : 12,
                textColor: .documentText,
                // No per-glyph rotation signal exists on this fallback path — `rotation`
                // stays 0, and the page's own `/Rotate` is recorded separately via
                // `pageRotation` so the two are never conflated (see `EditableTextBlock`).
                rotation: 0,
                pageRotation: page.rotation,
                baseline: rawBounds.minY,
                confidence: .medium,
                editability: .replace,
                textSource: .pdfKitString
            )
        }

        guard !lineBlocks.isEmpty else {
            return PDFTextPageAnalysis(pageRefID: pageRefID, blocks: [wholePageFallbackBlock(page: page, pageRefID: pageRefID, cropBox: cropBox, text: pageText)])
        }
        return PDFTextPageAnalysis(pageRefID: pageRefID, blocks: lineBlocks.sorted { $0.bounds.minY > $1.bounds.minY })
    }

    /// Last-resort single whole-page block for the rare case PDFKit's own line-selection API
    /// can't segment the page (e.g. a single selection spanning unusual glyph runs). Still
    /// tagged hittable (not `.low`/excluded) so a click at least opens an editor pre-filled
    /// with the page's real text instead of a blank box, but flagged `.overlayOnly` since its
    /// geometry can't be trusted at line granularity.
    private func wholePageFallbackBlock(page: PDFPage, pageRefID: UUID?, cropBox: CGRect, text: String) -> EditableTextBlock {
        EditableTextBlock(
            pageRefID: pageRefID,
            text: text,
            bounds: cropBox.insetBy(dx: 48, dy: 48),
            lines: [],
            columnBounds: cropBox.insetBy(dx: 48, dy: 48),
            fontName: "Helvetica",
            fontSize: 12,
            textColor: .documentText,
            rotation: 0,
            pageRotation: page.rotation,
            baseline: cropBox.maxY - 48,
            confidence: .medium,
            editability: .overlayOnly,
            textSource: .pdfKitString
        )
    }

    private func unionBounds(_ rects: [CGRect]) -> CGRect? {
        guard var result = rects.first else { return nil }
        rects.dropFirst().forEach { result = result.union($0) }
        return result
    }

    private func assignColumnBounds(to blocks: [EditableTextBlock], pageBounds: CGRect) -> [EditableTextBlock] {
        guard !blocks.isEmpty, pageBounds.width > 0 else { return blocks }
        return blocks.map { block in
            var updated = block
            // Only a block on the SAME visual row may clamp this block's column right edge.
            // Judging "same column" by a loose vertical distance (previously up to 3× the
            // font size) let an indented block one line below shrink the column, which
            // forced measuredBounds to wrap even unchanged text onto a second line.
            let rightNeighborMinX = blocks
                .filter { candidate in
                    candidate.id != block.id &&
                    candidate.bounds.minX > block.bounds.maxX &&
                    rowsOverlap(block.bounds, candidate.bounds)
                }
                .map(\.bounds.minX)
                .min()

            let rightEdge: CGFloat
            if let rightNeighborMinX {
                rightEdge = min(pageBounds.maxX - 8, rightNeighborMinX - max(6, block.fontSize))
            } else {
                rightEdge = pageBounds.maxX - 12
            }
            let leftEdge = max(pageBounds.minX + 8, block.bounds.minX)
            let width = max(block.bounds.width, rightEdge - leftEdge)
            updated.columnBounds = CGRect(
                x: leftEdge,
                y: pageBounds.minY,
                width: width,
                height: pageBounds.height
            )
            return updated
        }
    }

    private func mergeWrappedLines(_ blocks: [EditableTextBlock]) -> [EditableTextBlock] {
        let sorted = blocks.sorted {
            if abs($0.bounds.midY - $1.bounds.midY) > max($0.fontSize, $1.fontSize) {
                return $0.bounds.midY > $1.bounds.midY
            }
            return $0.bounds.minX < $1.bounds.minX
        }
        var merged: [EditableTextBlock] = []
        for block in sorted {
            guard let mergeIndex = merged.indices.reversed().first(where: { shouldMergeWrappedLine(previous: merged[$0], next: block) }) else {
                merged.append(block)
                continue
            }
            var last = merged[mergeIndex]
            last.text = [last.text, block.text]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            last.lines.append(contentsOf: block.lines)
            last.bounds = last.bounds.union(block.bounds)
            if let existingColumn = last.columnBounds, let nextColumn = block.columnBounds {
                let minX = min(existingColumn.minX, nextColumn.minX)
                let maxX = min(existingColumn.maxX, nextColumn.maxX)
                last.columnBounds = CGRect(
                    x: minX,
                    y: min(existingColumn.minY, nextColumn.minY),
                    width: max(last.bounds.width, maxX - minX),
                    height: max(existingColumn.maxY, nextColumn.maxY) - min(existingColumn.minY, nextColumn.minY)
                )
            } else {
                last.columnBounds = last.columnBounds ?? block.columnBounds
            }
            last.confidence = last.confidence == .high && block.confidence == .high ? .high : .medium
            merged[mergeIndex] = last
        }
        return merged
    }

    private func shouldMergeWrappedLine(previous: EditableTextBlock, next: EditableTextBlock) -> Bool {
        guard previous.confidence != .low, next.confidence != .low else { return false }
        guard fontsMatch(previous, next), colorsMatch(previous.textColor, next.textColor) else { return false }
        // `previous` is the in-progress merge accumulator: once it has already absorbed
        // several wrapped lines, its `.bounds` is the UNION of every line merged so far, so
        // `.bounds.height` is the whole paragraph's height, not one line's. Every tolerance
        // below is scaled by this "line height" — using the cumulative block height instead
        // of a single line's made every threshold (gap, baseline, indent, column, wrap
        // shortfall) grow with each successful merge, so a 4-line paragraph could span a
        // tolerance wide enough to absorb an entirely separate paragraph below it. Anchor to
        // the LAST individual line actually merged (the one physically adjacent to `next`)
        // so the tolerance stays a true single-line measurement no matter how long the
        // paragraph accumulated so far has already grown.
        let previousLastLine = previous.lines.last?.bounds ?? previous.bounds
        let verticalGap = previousLastLine.minY - next.bounds.maxY
        let lineHeight = max(previousLastLine.height, next.bounds.height, previous.fontSize, next.fontSize)
        let sameBaseline = abs(previousLastLine.midY - next.bounds.midY) <= lineHeight * 0.45
        let horizontalGap = next.bounds.minX - previous.bounds.maxX
        if sameBaseline,
           horizontalGap >= 0,
           horizontalGap <= max(30, lineHeight * 3),
           previous.text.trimmingCharacters(in: .whitespacesAndNewlines).isLikelyStandaloneListMarker {
            return true
        }
        // Rows separated by more than typical single-spaced leading (chip rows, padded
        // labels, loose layouts) are standalone elements, not a wrapped continuation.
        guard verticalGap >= -lineHeight * 0.35, verticalGap <= lineHeight * 0.9 else { return false }
        guard columnBoundsCompatible(previous.columnBounds, next.columnBounds, tolerance: max(12, lineHeight)) else { return false }
        guard lineLooksWrapped(previous: previous, next: next, lineHeight: lineHeight) else { return false }

        let indentDelta = next.bounds.minX - previous.bounds.minX
        let sameLeft = abs(indentDelta) <= max(8, lineHeight * 0.8)
        let hangingContinuation = indentDelta > 0 && indentDelta <= max(48, lineHeight * 4)
        let trimmedNext = next.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let veryShortContinuation = trimmedNext.count <= 3
        let trimmedPrevious = previous.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let previousLooksOpen = trimmedPrevious.range(of: #"[.!?;:]$"#, options: .regularExpression) == nil
        guard veryShortContinuation || !trimmedNext.isLikelyListItemStart else { return false }

        return (sameLeft || hangingContinuation || veryShortContinuation) &&
            (previousLooksOpen || veryShortContinuation)
    }

    /// True when the upper line plausibly word-wrapped into the lower one. A wrapped
    /// line is never conspicuously shorter than its continuation — if the upper line had
    /// that much free room, the continuation's leading words would have moved up into it.
    /// A short label sitting above a longer unrelated line (stacked chips, sidebar rows)
    /// fails this, so the two stay separately editable instead of fusing into one block.
    private func lineLooksWrapped(previous: EditableTextBlock, next: EditableTextBlock, lineHeight: CGFloat) -> Bool {
        let shortfall = next.bounds.maxX - previous.bounds.maxX
        return shortfall <= max(24, lineHeight * 2)
    }

    private func fontsMatch(_ lhs: EditableTextBlock, _ rhs: EditableTextBlock) -> Bool {
        lhs.fontName == rhs.fontName && abs(lhs.fontSize - rhs.fontSize) <= max(0.75, lhs.fontSize * 0.08)
    }

    private func colorsMatch(_ lhs: CodableColor, _ rhs: CodableColor) -> Bool {
        abs(lhs.red - rhs.red) <= 0.02 &&
            abs(lhs.green - rhs.green) <= 0.02 &&
            abs(lhs.blue - rhs.blue) <= 0.02 &&
            abs(lhs.alpha - rhs.alpha) <= 0.02
    }

    private func columnBoundsCompatible(_ lhs: CGRect?, _ rhs: CGRect?, tolerance: CGFloat) -> Bool {
        guard let lhs, let rhs else { return true }
        return abs(lhs.maxX - rhs.maxX) <= tolerance * 2.5
    }

    private func verticalDistance(between lhs: CGRect, and rhs: CGRect) -> CGFloat {
        if lhs.intersects(rhs) { return 0 }
        if lhs.maxY < rhs.minY { return rhs.minY - lhs.maxY }
        return lhs.minY - rhs.maxY
    }

    /// True when the two rects share enough vertical extent to sit on the same text row.
    private func rowsOverlap(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        let overlap = min(lhs.maxY, rhs.maxY) - max(lhs.minY, rhs.minY)
        return overlap >= min(lhs.height, rhs.height) * 0.4
    }

    private func median(_ values: [CGFloat]) -> CGFloat {
        let sorted = values.filter { $0.isFinite && $0 > 0 }.sorted()
        guard !sorted.isEmpty else { return 12 }
        return sorted[sorted.count / 2]
    }

    /// FPDFText_GetFontSize is unreliable for some glyphs and for pages that apply a text
    /// scale through the content stream CTM: PDFium can report the nominal `Tf` size while
    /// the glyph boxes are visibly smaller in page space. Prefer reported sizes only when
    /// they agree with the actual ink height; otherwise use an ink-derived effective size.
    ///
    /// `resolvedFontName` lets the ink estimate use THIS line's own font metrics (see
    /// `effectiveFontSize`) instead of one fixed ratio for every font — measured against
    /// several common fonts, a single global ratio was off by 5-12% depending on the font's
    /// actual cap-height/descender proportions (e.g. Georgia and Verdana ink noticeably
    /// taller relative to their point size than Helvetica does). That error was large enough
    /// to make `resolveLineFontSize` reject a genuinely-correct reported size as
    /// "implausible" and substitute the less-accurate generic estimate instead — the same
    /// wrong value then got reused as-is by "Match"/"Copy nearby format", since both read
    /// this same detected size.
    private func resolveLineFontSize(_ samples: [CharacterSample], lineBounds: CGRect, resolvedFontName: String) -> CGFloat {
        let validSizes = samples.compactMap(\.reportedFontSize).filter { $0.isFinite && $0 > 0 }
        let lineText = String(String.UnicodeScalarView(samples.map(\.scalar)))
        let inkEstimatedSize = effectiveFontSize(fromInkHeight: lineBounds.height, fontName: resolvedFontName, lineText: lineText)
        if !validSizes.isEmpty {
            let reported = median(validSizes)
            guard inkEstimatedSize > 0 else { return reported }
            // Marks/punctuation-only content ("...", "—", bullet glyphs) inks far less
            // than any letter model predicts — the band check is meaningless there, and
            // the reported size is the only trustworthy signal.
            guard lineText.unicodeScalars.contains(where: { CharacterSet.alphanumerics.contains($0) }) else {
                return reported
            }
            let upperPlausible = inkEstimatedSize * 1.08
            let lowerPlausible = inkEstimatedSize * 0.85
            if reported > upperPlausible || reported < lowerPlausible {
                return inkEstimatedSize
            }
            return reported
        }
        return inkEstimatedSize > 0 ? inkEstimatedSize : 12
    }

    /// Ratio of a line's rendered ink height to its point size, cached per PostScript
    /// name + character-class combination since this is looked up on every detected line.
    /// Fonts vary meaningfully (Courier New ≈0.87, Georgia ≈0.91, Helvetica ≈0.95 for the
    /// full cap-to-descender span) — but the CHARACTERS on the line matter even more: a
    /// line with no capitals/digits/ascenders/descenders ("nunc.") only inks its x-height
    /// (≈0.52 of the point size for Helvetica), and a lowercase line without descenders
    /// ("maximus ultricies.") tops out at the ascender with nothing below the baseline.
    /// Modeling every line as cap-to-descender made those lines' ink look like a much
    /// smaller font, which made `resolveLineFontSize` reject PDFium's CORRECT reported
    /// size as implausible and substitute a badly-undersized estimate — the same wrong
    /// value then flowed into Match/Copy format AND broke paragraph merging (blocks only
    /// merge within an 8% size tolerance), fragmenting body paragraphs into stray
    /// single-word blocks with sizes like 6.4/8.6 next to their 10.7pt neighbors.
    private struct InkExtentClass: Hashable {
        var fontName: String
        var hasCapsOrDigits: Bool
        var hasAscenders: Bool
        var hasDescenders: Bool
    }

    private static var inkRatioCache: [InkExtentClass: CGFloat] = [:]
    private static let fallbackInkRatio: CGFloat = 1 / 1.15
    private static let asciiAscenders = CharacterSet(charactersIn: "bdfhkltij")
    private static let asciiDescenders = CharacterSet(charactersIn: "gjpqy")
    private static let capsOrDigits = CharacterSet.uppercaseLetters.union(.decimalDigits)

    private static func inkRatio(forFontName fontName: String, lineText: String?) -> CGFloat {
        var extentClass = InkExtentClass(
            fontName: fontName,
            hasCapsOrDigits: true,
            hasAscenders: true,
            hasDescenders: true
        )
        // Character-aware extents only when the line is plain Latin text we can classify;
        // other scripts (CJK occupies nearly the full em, Arabic/Indic have their own
        // vertical anatomy) keep the conservative full-span model.
        if let lineText {
            let scalars = lineText.unicodeScalars.filter { CharacterSet.letters.contains($0) || CharacterSet.decimalDigits.contains($0) }
            let isClassifiableLatin = !scalars.isEmpty && scalars.allSatisfy { $0.isASCII }
            if isClassifiableLatin {
                extentClass.hasCapsOrDigits = scalars.contains { capsOrDigits.contains($0) }
                extentClass.hasAscenders = scalars.contains { asciiAscenders.contains($0) }
                extentClass.hasDescenders = scalars.contains { asciiDescenders.contains($0) }
            }
        }
        if let cached = inkRatioCache[extentClass] { return cached }
        guard let font = NSFont(name: fontName, size: 1), font.capHeight > 0, font.xHeight > 0 else {
            inkRatioCache[extentClass] = fallbackInkRatio
            return fallbackInkRatio
        }
        // `font.ascender` is deliberately NOT used for the ascender case: the metric
        // includes line-fitting headroom above any actual glyph ink (Times' ascender
        // metric is ~0.89/em while its tallest lowercase ink sits near the ~0.66 cap
        // height), so modeling ascender lines with it overestimates the expected ink and
        // undersizes the font by 15-20%. Real lowercase ascenders ('l', 'd', 'b') top out
        // at — or a hair above — the cap height in common text faces, so cap height is
        // the honest expected extent for both the caps and the ascenders classes.
        let top = (extentClass.hasCapsOrDigits || extentClass.hasAscenders) ? font.capHeight : font.xHeight
        let bottom = extentClass.hasDescenders ? -font.descender : 0
        let ratio = top + bottom
        let resolved = ratio > 0 ? ratio : fallbackInkRatio
        inkRatioCache[extentClass] = resolved
        return resolved
    }

    private func effectiveFontSize(fromInkHeight inkHeight: CGFloat, fontName: String, lineText: String? = nil) -> CGFloat {
        guard inkHeight.isFinite, inkHeight > 0 else { return 0 }
        let ratio = Self.inkRatio(forFontName: fontName, lineText: lineText)
        return max(4, inkHeight / ratio)
    }
}

private extension String {
    var isLikelyListItemStart: Bool {
        range(of: #"^\s*([•\-–—*]|\(?[0-9A-Za-z]+\)|[0-9A-Za-z]+[.)])\s+"#, options: .regularExpression) != nil
    }

    var isLikelyStandaloneListMarker: Bool {
        range(of: #"^\s*([•\-–—*]|\(?[0-9A-Za-z]+\)|[0-9A-Za-z]+[.)])\s*$"#, options: .regularExpression) != nil
    }
}
