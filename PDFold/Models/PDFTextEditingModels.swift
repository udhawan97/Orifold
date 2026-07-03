import Foundation
import AppKit

enum PDFTextEditConfidence: String, Codable {
    case high
    case medium
    case low
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
    var rotation: CGFloat
    var baseline: CGFloat
    var confidence: PDFTextEditConfidence
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
    /// True when this operation inserts brand-new text at an empty spot rather than
    /// replacing existing PDF text. Insertions must not paint erase patches — there is
    /// nothing to erase, and patching would stamp an opaque rectangle over whatever
    /// graphics/background sit under the new text.
    var isInsertion: Bool = false
    var didManuallyReposition: Bool = false
    var didManuallyResizeWidth: Bool = false
    var didManuallyResizeHeight: Bool = false
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()

    enum CodingKeys: String, CodingKey {
        case id, pageRefID, sourceBlockID, sourceBounds, sourceLineBounds, sourceText, editedBounds, columnBounds
        case replacementText, fontName, fontSize, textColor, alignment, isInsertion
        case didManuallyReposition, didManuallyResizeWidth, didManuallyResizeHeight
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
        isInsertion: Bool = false,
        didManuallyReposition: Bool = false,
        didManuallyResizeWidth: Bool = false,
        didManuallyResizeHeight: Bool = false,
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
        self.isInsertion = isInsertion
        self.didManuallyReposition = didManuallyReposition
        self.didManuallyResizeWidth = didManuallyResizeWidth
        self.didManuallyResizeHeight = didManuallyResizeHeight
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
        isInsertion = try c.decodeIfPresent(Bool.self, forKey: .isInsertion) ?? false
        didManuallyReposition = try c.decodeIfPresent(Bool.self, forKey: .didManuallyReposition) ?? false
        didManuallyResizeWidth = try c.decodeIfPresent(Bool.self, forKey: .didManuallyResizeWidth) ?? false
        didManuallyResizeHeight = try c.decodeIfPresent(Bool.self, forKey: .didManuallyResizeHeight) ?? false
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
