import CoreGraphics
import Foundation

enum PageDecorationSwatch: String, Codable, CaseIterable {
    case accent
    case sage
    case coral
    case tertiary
    case lavender
}

struct PageDecoration: Codable, Identifiable, Equatable {
    enum Kind: String, Codable {
        case watermark
        case pageNumber
        case bates
        case stamp
    }

    var id: UUID
    var kind: Kind
    var isEnabled: Bool
    var text: String
    var prefix: String
    var startNumber: Int
    var pageRefID: UUID?
    var rect: CGRect?
    var fontSize: CGFloat
    var opacity: Double
    var swatch: PageDecorationSwatch

    enum CodingKeys: String, CodingKey {
        case id, kind, isEnabled, text, prefix, startNumber, pageRefID, rect, fontSize, opacity, swatch
    }

    init(id: UUID = UUID(),
         kind: Kind,
         isEnabled: Bool = true,
         text: String = "",
         prefix: String = "DEF",
         startNumber: Int = 100,
         pageRefID: UUID? = nil,
         rect: CGRect? = nil,
         fontSize: CGFloat = 12,
         opacity: Double = 1,
         swatch: PageDecorationSwatch = .accent) {
        self.id = id
        self.kind = kind
        self.isEnabled = isEnabled
        self.text = text
        self.prefix = prefix
        self.startNumber = startNumber
        self.pageRefID = pageRefID
        self.rect = rect
        self.fontSize = fontSize
        self.opacity = opacity
        self.swatch = swatch
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try c.decode(Kind.self, forKey: .kind)
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        prefix = try c.decodeIfPresent(String.self, forKey: .prefix) ?? "DEF"
        startNumber = try c.decodeIfPresent(Int.self, forKey: .startNumber) ?? 100
        pageRefID = try c.decodeIfPresent(UUID.self, forKey: .pageRefID)
        rect = try c.decodeIfPresent(CGRect.self, forKey: .rect)
        fontSize = try c.decodeIfPresent(CGFloat.self, forKey: .fontSize) ?? 12
        opacity = try c.decodeIfPresent(Double.self, forKey: .opacity) ?? 1
        swatch = try c.decodeIfPresent(PageDecorationSwatch.self, forKey: .swatch) ?? .accent
    }
}

extension PageDecoration {
    static func watermark() -> PageDecoration {
        PageDecoration(kind: .watermark, text: "Draft", fontSize: 64, opacity: 0.16, swatch: .tertiary)
    }

    static func pageNumber() -> PageDecoration {
        PageDecoration(kind: .pageNumber, fontSize: 10, opacity: 1, swatch: .tertiary)
    }

    static func bates() -> PageDecoration {
        PageDecoration(kind: .bates, prefix: "DEF", startNumber: 100, fontSize: 10, opacity: 1, swatch: .tertiary)
    }

    static func stamp(text: String, swatch: PageDecorationSwatch, pageRefID: UUID, rect: CGRect) -> PageDecoration {
        PageDecoration(kind: .stamp, text: text, pageRefID: pageRefID, rect: rect, fontSize: 22, opacity: 0.88, swatch: swatch)
    }
}
