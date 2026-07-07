import Foundation
import AppKit

enum PDFTextEditConfidence: String, Codable {
    case high
    case medium
    case low
}

/// Classifies how a detected (or synthesized) text region can actually be edited, so the
/// click-to-edit UI and export can branch on it instead of treating every region as either
/// "fully editable" or "blank white box". See docs/features/SMART_TEXT_EDIT_PLAN.md.
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
}

/// Where a block's text/geometry came from, for diagnostics and future OCR wiring.
enum PDFTextSource: String, Codable {
    case pdfiumGlyphs
    case pdfKitString
    case none
}

struct PDFTextRun: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var text: String
    var bounds: CGRect
    var fontName: String
    var fontSize: CGFloat
    var textColor: CodableColor
    var rotation: CGFloat
    var baseline: CGFloat
    var confidence: PDFTextEditConfidence
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
    var fontSize: CGFloat
    var textColor: CodableColor
    var alignment: CodableTextAlignment? = nil
    var underline: Bool = false
    var rotation: CGFloat
    var baseline: CGFloat
    var confidence: PDFTextEditConfidence
    var editability: PDFTextEditability = .direct
    var textSource: PDFTextSource = .pdfiumGlyphs
}

struct PDFTextEditOperation: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var pageRefID: UUID
    var sourceBlockID: UUID
    var sourceBounds: CGRect
    var sourceLineBounds: [CGRect] = []
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
        case id, pageRefID, sourceBlockID, sourceBounds, sourceLineBounds, sourceText, editedBounds, columnBounds
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
    var fontSize: CGFloat
    var textColor: CodableColor
    var alignment: CodableTextAlignment
    var underline: Bool = false
    var bounds: CGRect? = nil
    var columnBounds: CGRect? = nil

    init(
        fontName: String,
        fontSize: CGFloat,
        textColor: CodableColor,
        alignment: CodableTextAlignment,
        underline: Bool = false,
        bounds: CGRect? = nil,
        columnBounds: CGRect? = nil
    ) {
        self.fontName = fontName
        self.fontSize = fontSize
        self.textColor = textColor
        self.alignment = alignment
        self.underline = underline
        self.bounds = bounds
        self.columnBounds = columnBounds
    }

    init(block: EditableTextBlock) {
        self.fontName = block.fontName
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

    static let documentText = CodableColor(nsColor: .dsTextPrimaryNS)

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
