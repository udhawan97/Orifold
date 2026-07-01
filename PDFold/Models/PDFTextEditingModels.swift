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
    var editedBounds: CGRect
    var replacementText: String
    var fontName: String
    var fontSize: CGFloat
    var textColor: CodableColor
    var alignment: CodableTextAlignment
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()
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
