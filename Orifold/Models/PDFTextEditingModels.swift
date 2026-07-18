import Foundation
import AppKit

enum PDFTextEditConfidence: String, Codable {
    case high
    case medium
    case low
}

/// Classifies how a detected (or synthesized) text region can actually be edited, so the
/// click-to-edit UI and export can branch on it instead of treating every region as either
/// "fully editable" or "blank white box".
enum PDFTextEditability: String, Codable {
    /// Real glyphs with high-confidence bounds/font — edit in place, erase + redraw on export.
    case direct
    /// Text recovered (e.g. via PDFKit's line selections) but geometry/font are approximate —
    /// edit in place; export covers the matching background before redrawing.
    case replace
    /// No text layer at all, but the page looks like a scanned/flattened image — the click
    /// can't be bound to a known text region, so typed text is placed as new content rather
    /// than silently pretending a real line was detected.
    case overlayOnly
    /// The click landed on genuinely blank space; the user is adding brand-new text.
    case insertion
    /// Real embedded text drawn with an invisible PDF render mode (`Tr 3`) — the classic
    /// "OCR text layer sitting under a scanned image" pattern. Still real, hittable, editable
    /// text; the UI surfaces this so editing it doesn't look like it silently did nothing.
    case hiddenOCRLayer
    /// Real embedded text whose fill color is essentially fully transparent (e.g. white text
    /// on a white page). Distinct from `hiddenOCRLayer` — this is a genuine render-mode-fill
    /// signal (near-zero alpha), not PDF's dedicated invisible mode — but the user experience
    /// is the same: editing it won't visibly show anything without an explanation.
    case lowVisibility
}

/// Where a block's text/geometry came from, for diagnostics and future OCR wiring.
enum PDFTextSource: String, Codable {
    case pdfiumGlyphs
    case pdfKitString
    case none
}

/// A raw affine transform (matches PDFium's `FS_MATRIX` / `CGAffineTransform` layout: `a b c
/// d e f` where `e`/`f` are the translation). Captured separately from the scalar `rotation`
/// angle because rotation alone can't represent shear, mirroring, or non-uniform horizontal
/// scaling (condensed/expanded text) — cases the plan explicitly calls out as needing their
/// own preserved geometry rather than being flattened into "just an angle."
struct PDFTextTransform: Codable, Equatable {
    var a: CGFloat
    var b: CGFloat
    var c: CGFloat
    var d: CGFloat
    var e: CGFloat
    var f: CGFloat

    static let identity = PDFTextTransform(a: 1, b: 0, c: 0, d: 1, e: 0, f: 0)

    var cgAffineTransform: CGAffineTransform {
        CGAffineTransform(a: a, b: b, c: c, d: d, tx: e, ty: f)
    }

    init(a: CGFloat, b: CGFloat, c: CGFloat, d: CGFloat, e: CGFloat, f: CGFloat) {
        self.a = a; self.b = b; self.c = c; self.d = d; self.e = e; self.f = f
    }

    init(_ t: CGAffineTransform) {
        self.init(a: t.a, b: t.b, c: t.c, d: t.d, e: t.tx, f: t.ty)
    }
}

struct PDFTextRun: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var text: String
    var bounds: CGRect
    var fontName: String
    var fontSize: CGFloat
    var textColor: CodableColor
    /// This run's OWN content-stream rotation in degrees (e.g. text drawn via a rotated `cm`
    /// matrix), independent of the page's `/Rotate` entry. Always 0 when no per-glyph angle
    /// signal is available (see `EditableTextBlock.pageRotation` for the page-level value —
    /// the two must never be conflated, since a consumer that already accounts for page
    /// rotation via `PDFView`'s page/view coordinate conversion would double-rotate if this
    /// field also carried the page's rotation).
    var rotation: CGFloat
    var baseline: CGFloat
    var confidence: PDFTextEditConfidence
    /// The stroke color PDFium reports for this run's ink glyphs, when available. Only
    /// meaningful for render modes that actually stroke (stroke-only / fill+stroke) —
    /// present here as captured geometry for a future consumer to decide how to use, not
    /// yet surfaced as a distinct render mode itself.
    var strokeColor: CodableColor? = nil
    /// The full affine transform for this run's ink glyphs, when PDFium can report one.
    /// `rotation` above is derived from this same signal for callers that only need the
    /// angle; this preserves shear/scale/mirroring `rotation` alone would lose.
    var transform: PDFTextTransform? = nil
    /// True when at least one of this run's ink glyphs was PDFium-synthesized (a missing or
    /// unmappable glyph filled in rather than read from the embedded font) rather than a
    /// genuine read of the document's own content. A signal of lower extraction confidence,
    /// independent of `confidence` (which reflects which analysis path produced the block).
    var hasSyntheticGlyphs: Bool = false
    /// True when a horizontal rule was detected sitting just below this run's baseline
    /// (see `PageGraphicsIndex.underlineRule`). PDF underlines are drawn as separate vector
    /// path objects, not text attributes, so this is the only way to recover them — without
    /// it, opening the editor and committing any edit silently drops the underline.
    var underline: Bool = false
}

struct PDFTextLine: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var text: String
    var bounds: CGRect
    var runs: [PDFTextRun]
    var confidence: PDFTextEditConfidence
}

struct EditableTextBlock: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var pageRefID: UUID?
    var text: String
    var bounds: CGRect
    var lines: [PDFTextLine]
    var columnBounds: CGRect? = nil
    var fontName: String
    /// The RAW unembedded PDF `/BaseFont` name this block's dominant run referenced (e.g.
    /// "Calibri", "ABCDEF+Cambria"), captured BEFORE `PDFTextAnalysisEngine.resolveFontPostScriptName`
    /// normalized it into `fontName`'s coarse display family (Calibri→Arial, Cambria→Times New
    /// Roman). Used ONLY as the key for metric-compatible font substitution (`FontSubstitution`):
    /// the table needs the real Windows-font name to reach its Carlito/Caladea entries, whereas
    /// the normalized `fontName` would collapse them to Liberation Sans/Serif. Keep `fontName`
    /// for display/trait logic; consult `rawFontName` only for the substitution decision. `nil`
    /// when no font name could be read (callers fall back to `fontName`). Optional + defaulted so
    /// persisted pre-migration workspace state still decodes (`decodeIfPresent` → nil).
    var rawFontName: String? = nil
    var fontSize: CGFloat
    var textColor: CodableColor
    var alignment: CodableTextAlignment? = nil
    var underline: Bool = false
    /// See `PDFTextRun.rotation` — this block's own content-stream rotation, never the
    /// page's. Use `pageRotation` for the page-level `/Rotate` value.
    var rotation: CGFloat
    /// The owning page's `/Rotate` value in degrees (0/90/180/270), captured verbatim from
    /// `PDFPage.rotation`. Kept separate from `rotation` (this block's own text-level
    /// rotation) so a consumer can tell "this whole page is sideways" apart from "this
    /// specific text run is drawn at an angle within an otherwise upright page" — conflating
    /// the two into one field previously meant a rotated page's blocks reported page rotation
    /// AS IF it were per-run rotation, which either double-rotates once a real consumer
    /// applies both page-rotation-aware coordinate conversion and this field, or silently
    /// hides genuine text-level rotation on a page that isn't itself rotated.
    var pageRotation: Int = 0
    var baseline: CGFloat
    var confidence: PDFTextEditConfidence
    var editability: PDFTextEditability = .direct
    var textSource: PDFTextSource = .pdfiumGlyphs
    /// See `PDFTextRun.strokeColor`.
    var strokeColor: CodableColor? = nil
    /// See `PDFTextRun.transform`.
    var transform: PDFTextTransform? = nil
    /// See `PDFTextRun.hasSyntheticGlyphs`.
    var hasSyntheticGlyphs: Bool = false
    /// The detected underline stroke rects for this block (one per underlined line), in raw
    /// page coordinates. Carried onto the committed operation so the export renderer can
    /// erase the WHOLE original stroke (not leave half of it exposed) before redrawing the
    /// replacement — and so the replacement's own underline lines up with where the original
    /// sat. Empty when no underline was detected.
    var underlineBounds: [CGRect] = []
    /// Table/separator rule rects near this block that the erase patch must PRESERVE (punch
    /// holes for) rather than paint over — so editing a table cell never wipes the
    /// surrounding grid lines. Excludes the block's own underline (which IS erased). Empty
    /// when the block isn't near any rules.
    var protectedRuleBounds: [CGRect] = []
}

struct PDFTextEditOperation: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var pageRefID: UUID
    var sourceBlockID: UUID
    var sourceBounds: CGRect
    var sourceLineBounds: [CGRect] = []
    /// Detected underline stroke rects on the original text (see `EditableTextBlock.underlineBounds`).
    /// Erased in full on export so a commit never leaves half an underline exposed under the
    /// replacement. Empty when the source text was not underlined.
    var sourceUnderlineBounds: [CGRect] = []
    /// Table/separator rule rects near the source that the erase patch must PRESERVE — the
    /// export renderer punches holes for these so editing a table cell never wipes the grid
    /// lines (see `EditableTextBlock.protectedRuleBounds`). Empty outside tables.
    var sourcePreserveRuleBounds: [CGRect] = []
    var sourceText: String = ""
    var editedBounds: CGRect
    var columnBounds: CGRect? = nil
    var replacementText: String
    var fontName: String
    var fontSize: CGFloat
    var textColor: CodableColor
    var alignment: CodableTextAlignment
    var underline: Bool = false
    /// The true formatting of the original PDF text this operation replaced, captured
    /// once at creation and preserved verbatim across every re-edit (see
    /// `applyInlineTextEdit`'s existingOp merge). Match/Copy/Restore read this directly
    /// instead of re-deriving it from a fresh text-analysis pass — re-analysis assigns
    /// brand-new random `EditableTextBlock.id`s every time (see `PDFTextAnalysisEngine`),
    /// so any lookup keyed on `sourceBlockID` would silently fail after the very first
    /// edit and fall back to a "nearest block" guess that could resolve to the wrong
    /// paragraph in dense layouts.
    var originalFormat: PDFTextEditFormat
    /// True when this operation inserts brand-new text at an empty spot rather than
    /// replacing existing PDF text. Insertions must not paint erase patches — there is
    /// nothing to erase, and patching would stamp an opaque rectangle over whatever
    /// graphics/background sit under the new text.
    var isInsertion: Bool = false
    var didManuallyReposition: Bool = false
    var didManuallyResizeWidth: Bool = false
    var didManuallyResizeHeight: Bool = false
    var didManuallyChangeStyle: Bool = false
    /// True when Match/Copy/Apply/Restore Style adopted a different paragraph's bounds
    /// or column margins for this edit. That destination can land anywhere on the page —
    /// not just within the original text's footprint — so `PDFEditedPageRenderer` must
    /// erase the destination box too, the same as it does for a manual drag/resize,
    /// or the replacement text can bleed over whatever original content sat there.
    var didApplyMatchedGeometry: Bool = false
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()

    enum CodingKeys: String, CodingKey {
        case id, pageRefID, sourceBlockID, sourceBounds, sourceLineBounds, sourceUnderlineBounds, sourcePreserveRuleBounds, sourceText, editedBounds, columnBounds
        case replacementText, fontName, fontSize, textColor, alignment, underline, originalFormat, isInsertion
        case didManuallyReposition, didManuallyResizeWidth, didManuallyResizeHeight, didManuallyChangeStyle
        case didApplyMatchedGeometry
        case createdAt, modifiedAt
    }

    init(
        id: UUID = UUID(),
        pageRefID: UUID,
        sourceBlockID: UUID,
        sourceBounds: CGRect,
        sourceLineBounds: [CGRect] = [],
        sourceUnderlineBounds: [CGRect] = [],
        sourcePreserveRuleBounds: [CGRect] = [],
        sourceText: String = "",
        editedBounds: CGRect,
        columnBounds: CGRect? = nil,
        replacementText: String,
        fontName: String,
        fontSize: CGFloat,
        textColor: CodableColor,
        alignment: CodableTextAlignment,
        underline: Bool = false,
        originalFormat: PDFTextEditFormat? = nil,
        isInsertion: Bool = false,
        didManuallyReposition: Bool = false,
        didManuallyResizeWidth: Bool = false,
        didManuallyResizeHeight: Bool = false,
        didManuallyChangeStyle: Bool = false,
        didApplyMatchedGeometry: Bool = false,
        createdAt: Date = Date(),
        modifiedAt: Date = Date()
    ) {
        self.id = id
        self.pageRefID = pageRefID
        self.sourceBlockID = sourceBlockID
        self.sourceBounds = sourceBounds
        self.sourceLineBounds = sourceLineBounds
        self.sourceUnderlineBounds = sourceUnderlineBounds
        self.sourcePreserveRuleBounds = sourcePreserveRuleBounds
        self.sourceText = sourceText
        self.editedBounds = editedBounds
        self.columnBounds = columnBounds
        self.replacementText = replacementText
        self.fontName = fontName
        self.fontSize = fontSize
        self.textColor = textColor
        self.alignment = alignment
        self.underline = underline
        self.originalFormat = originalFormat ?? PDFTextEditFormat(
            fontName: fontName,
            fontSize: fontSize,
            textColor: textColor,
            alignment: alignment,
            underline: underline,
            bounds: sourceBounds,
            columnBounds: columnBounds
        )
        self.isInsertion = isInsertion
        self.didManuallyReposition = didManuallyReposition
        self.didManuallyResizeWidth = didManuallyResizeWidth
        self.didManuallyResizeHeight = didManuallyResizeHeight
        self.didApplyMatchedGeometry = didApplyMatchedGeometry
        self.didManuallyChangeStyle = didManuallyChangeStyle
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        pageRefID = try c.decode(UUID.self, forKey: .pageRefID)
        sourceBlockID = try c.decode(UUID.self, forKey: .sourceBlockID)
        sourceBounds = try c.decode(CGRect.self, forKey: .sourceBounds)
        sourceLineBounds = try c.decodeIfPresent([CGRect].self, forKey: .sourceLineBounds) ?? []
        sourceUnderlineBounds = try c.decodeIfPresent([CGRect].self, forKey: .sourceUnderlineBounds) ?? []
        sourcePreserveRuleBounds = try c.decodeIfPresent([CGRect].self, forKey: .sourcePreserveRuleBounds) ?? []
        sourceText = try c.decodeIfPresent(String.self, forKey: .sourceText) ?? ""
        editedBounds = try c.decode(CGRect.self, forKey: .editedBounds)
        columnBounds = try c.decodeIfPresent(CGRect.self, forKey: .columnBounds)
        replacementText = try c.decode(String.self, forKey: .replacementText)
        fontName = try c.decode(String.self, forKey: .fontName)
        fontSize = try c.decode(CGFloat.self, forKey: .fontSize)
        textColor = try c.decode(CodableColor.self, forKey: .textColor)
        alignment = try c.decode(CodableTextAlignment.self, forKey: .alignment)
        underline = try c.decodeIfPresent(Bool.self, forKey: .underline) ?? false
        // Older saved workspaces (pre-dating stored original formatting) have no
        // `originalFormat` payload — best-effort fall back to this operation's own
        // replacement styling/bounds rather than losing Match/Restore for those edits.
        originalFormat = try c.decodeIfPresent(PDFTextEditFormat.self, forKey: .originalFormat) ?? PDFTextEditFormat(
            fontName: fontName,
            fontSize: fontSize,
            textColor: textColor,
            alignment: alignment,
            underline: underline,
            bounds: sourceBounds,
            columnBounds: columnBounds
        )
        isInsertion = try c.decodeIfPresent(Bool.self, forKey: .isInsertion) ?? false
        didManuallyReposition = try c.decodeIfPresent(Bool.self, forKey: .didManuallyReposition) ?? false
        didManuallyResizeWidth = try c.decodeIfPresent(Bool.self, forKey: .didManuallyResizeWidth) ?? false
        didManuallyResizeHeight = try c.decodeIfPresent(Bool.self, forKey: .didManuallyResizeHeight) ?? false
        didManuallyChangeStyle = try c.decodeIfPresent(Bool.self, forKey: .didManuallyChangeStyle) ?? false
        didApplyMatchedGeometry = try c.decodeIfPresent(Bool.self, forKey: .didApplyMatchedGeometry) ?? false
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        modifiedAt = try c.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? createdAt
    }
}

struct PageEditState: Codable, Identifiable, Equatable {
    var id: UUID { pageRefID }
    var pageRefID: UUID
    var operations: [PDFTextEditOperation] = []
}

struct PDFTextEditSession: Equatable {
    var pageRefID: UUID
    var block: EditableTextBlock
    var draftText: String
    var draftBounds: CGRect
    var columnBounds: CGRect? = nil
    var fontName: String
    var fontSize: CGFloat
    var textColor: CodableColor
    var alignment: CodableTextAlignment
}

struct PDFTextEditFormat: Codable, Equatable {
    var fontName: String
    /// The RAW unembedded PDF `/BaseFont` name behind `fontName` (see
    /// `EditableTextBlock.rawFontName`), carried so Match/Copy/Apply-Style and nearby-style
    /// insertion key font substitution off the real font name rather than `fontName`'s
    /// normalized Arial/Times fallback. `nil` for formats built from a live edited font
    /// (there is no source `/BaseFont`) — callers fall back to `fontName`.
    var rawFontName: String? = nil
    var fontSize: CGFloat
    var textColor: CodableColor
    var alignment: CodableTextAlignment
    var underline: Bool = false
    var bounds: CGRect? = nil
    var columnBounds: CGRect? = nil

    init(
        fontName: String,
        rawFontName: String? = nil,
        fontSize: CGFloat,
        textColor: CodableColor,
        alignment: CodableTextAlignment,
        underline: Bool = false,
        bounds: CGRect? = nil,
        columnBounds: CGRect? = nil
    ) {
        self.fontName = fontName
        self.rawFontName = rawFontName
        self.fontSize = fontSize
        self.textColor = textColor
        self.alignment = alignment
        self.underline = underline
        self.bounds = bounds
        self.columnBounds = columnBounds
    }

    init(block: EditableTextBlock) {
        self.fontName = block.fontName
        self.rawFontName = block.rawFontName
        self.fontSize = block.fontSize
        self.textColor = block.textColor
        self.alignment = block.alignment ?? .left
        self.underline = block.underline
        self.bounds = block.bounds
        self.columnBounds = block.columnBounds
    }
}

struct CodableColor: Codable, Equatable {
    var red: CGFloat
    var green: CGFloat
    var blue: CGFloat
    var alpha: CGFloat

    /// Fallback color for text whose fill color can't be read from the PDF. This is ink
    /// on paper — always near-black — and deliberately NOT a UI label color: resolving a
    /// dynamic AppKit color here snapshots whatever appearance is active when this static
    /// first initializes, and under dark mode that's a near-WHITE value that then gets
    /// baked verbatim into exported pages as white-on-white invisible replacement text.
    static let documentText = CodableColor(red: 0.13, green: 0.13, blue: 0.13)

    init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init(nsColor: NSColor) {
        let converted = nsColor.usingColorSpace(.sRGB) ?? .labelColor
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 1
        converted.getRed(&r, green: &g, blue: &b, alpha: &a)
        red = r
        green = g
        blue = b
        alpha = a
    }

    var nsColor: NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }
}

enum CodableTextAlignment: String, Codable, Equatable {
    case left
    case center
    case right

    init(_ alignment: NSTextAlignment) {
        switch alignment {
        case .center: self = .center
        case .right: self = .right
        default: self = .left
        }
    }

    var nsTextAlignment: NSTextAlignment {
        switch self {
        case .left: return .left
        case .center: return .center
        case .right: return .right
        }
    }
}
