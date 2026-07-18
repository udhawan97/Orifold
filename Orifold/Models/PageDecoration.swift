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
        case hanko
        case image
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
    /// Border shape of a `.hanko` seal; ignored by every other kind.
    var hankoShape: HankoShape
    /// The PNG bytes of an `.image` decoration (a placed barcode/QR); `nil` for every other
    /// kind. Baked into the page via `PDFDecorationExportBaker.drawImage`, never via a PDFium
    /// image-object insert (that lane is unbound — see WAVE_2_PLAN Feature G).
    var imageData: Data?

    enum CodingKeys: String, CodingKey {
        case id, kind, isEnabled, text, prefix, startNumber, pageRefID, rect, fontSize, opacity, swatch, hankoShape, imageData
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
         swatch: PageDecorationSwatch = .accent,
         hankoShape: HankoShape = .circle,
         imageData: Data? = nil) {
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
        self.hankoShape = hankoShape
        self.imageData = imageData
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
        // Migration-safe: documents saved before the hanko studio shipped have no
        // `hankoShape`, so default it rather than failing to decode the whole workspace.
        hankoShape = try c.decodeIfPresent(HankoShape.self, forKey: .hankoShape) ?? .circle
        // Migration-safe likewise: workspaces saved before barcode insert have no
        // `imageData`; default to nil rather than failing the whole decode.
        imageData = try c.decodeIfPresent(Data.self, forKey: .imageData)
    }
}

extension PageDecoration {
    /// Seals are the free-floating, rect-anchored decorations a user drops onto a page and
    /// can then select, drag, resize, or delete — text stamps, hanko, and placed barcode
    /// images alike. The selection/hit-test/move/remove plumbing keys off this rather than
    /// `.stamp` so a placed hanko or barcode behaves exactly like a stamp.
    var isSeal: Bool { kind == .stamp || kind == .hanko || kind == .image }

    static func watermark() -> PageDecoration {
        PageDecoration(kind: .watermark, text: L10n.string("decoration.defaultWatermark"), fontSize: 64, opacity: 0.16, swatch: .tertiary)
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

    /// A procedural hanko seal: `text` holds the 1–4 characters carved into it, `hankoShape`
    /// the border. Rendered in shu-iro vermillion by `HankoRenderer` (not `swatch`).
    static func hanko(text: String, shape: HankoShape, pageRefID: UUID, rect: CGRect) -> PageDecoration {
        PageDecoration(kind: .hanko, text: text, pageRefID: pageRefID, rect: rect, fontSize: 22, opacity: 1, swatch: .coral, hankoShape: shape)
    }

    /// A placed raster image — currently the barcode/QR insert (Feature G). `imageData` holds
    /// the PNG bytes; the exporter draws it into the page content stream (no PDFium image
    /// object, no annotation).
    static func image(imageData: Data, pageRefID: UUID, rect: CGRect) -> PageDecoration {
        PageDecoration(kind: .image, pageRefID: pageRefID, rect: rect, opacity: 1, imageData: imageData)
    }
}
