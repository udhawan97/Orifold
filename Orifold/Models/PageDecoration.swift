import CoreGraphics
import Foundation

enum PageDecorationSwatch: String, Codable, CaseIterable {
    case accent
    case sage
    case coral
    case tertiary
    case lavender
}

enum PageDecorationPDFPlacement: String, Codable, CaseIterable, Hashable {
    case over
    case under
}

struct PageDecoration: Codable, Identifiable, Equatable {
    enum Kind: String, Codable {
        case watermark
        case pageNumber
        case bates
        case stamp
        case hanko
        case image
        case overlayPDF
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
    /// A one-page vector PDF used as stationery or letterhead. Kept separate from
    /// `imageData` so export can draw the source `CGPDFPage` directly without rasterizing it.
    var overlayPDFData: Data?
    /// Whether the overlay PDF is composited before or after the source page content.
    var overlayPDFPlacement: PageDecorationPDFPlacement

    enum CodingKeys: String, CodingKey {
        case id, kind, isEnabled, text, prefix, startNumber, pageRefID, rect
        case fontSize, opacity, swatch, hankoShape, imageData
        case overlayPDFData, overlayPDFPlacement
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
         imageData: Data? = nil,
         overlayPDFData: Data? = nil,
         overlayPDFPlacement: PageDecorationPDFPlacement = .over) {
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
        self.overlayPDFData = overlayPDFData
        self.overlayPDFPlacement = overlayPDFPlacement
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try container.decode(Kind.self, forKey: .kind)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        prefix = try container.decodeIfPresent(String.self, forKey: .prefix) ?? "DEF"
        startNumber = try container.decodeIfPresent(Int.self, forKey: .startNumber) ?? 100
        pageRefID = try container.decodeIfPresent(UUID.self, forKey: .pageRefID)
        rect = try container.decodeIfPresent(CGRect.self, forKey: .rect)
        fontSize = try container.decodeIfPresent(CGFloat.self, forKey: .fontSize) ?? 12
        opacity = try container.decodeIfPresent(Double.self, forKey: .opacity) ?? 1
        swatch = try container.decodeIfPresent(PageDecorationSwatch.self, forKey: .swatch) ?? .accent
        // Migration-safe: documents saved before the hanko studio shipped have no
        // `hankoShape`, so default it rather than failing to decode the whole workspace.
        hankoShape = try container.decodeIfPresent(HankoShape.self, forKey: .hankoShape) ?? .circle
        // Migration-safe likewise: workspaces saved before barcode insert have no
        // `imageData`; default to nil rather than failing the whole decode.
        imageData = try container.decodeIfPresent(Data.self, forKey: .imageData)
        // Migration-safe: workspaces saved before PDF overlays have neither key.
        overlayPDFData = try container.decodeIfPresent(Data.self, forKey: .overlayPDFData)
        overlayPDFPlacement = try container.decodeIfPresent(
            PageDecorationPDFPlacement.self,
            forKey: .overlayPDFPlacement
        ) ?? .over
    }
}

extension PageDecoration {
    /// Seals are the free-floating, rect-anchored decorations a user drops onto a page and
    /// can then select, drag, resize, or delete — text stamps, hanko, and placed barcode
    /// images alike. The selection/hit-test/move/remove plumbing keys off this rather than
    /// `.stamp` so a placed hanko or barcode behaves exactly like a stamp.
    var isSeal: Bool { kind == .stamp || kind == .hanko || kind == .image }

    static func watermark() -> PageDecoration {
        PageDecoration(
            kind: .watermark,
            text: L10n.string("decoration.defaultWatermark"),
            fontSize: 64,
            opacity: 0.16,
            swatch: .tertiary
        )
    }

    static func pageNumber() -> PageDecoration {
        PageDecoration(kind: .pageNumber, fontSize: 10, opacity: 1, swatch: .tertiary)
    }

    static func bates() -> PageDecoration {
        PageDecoration(kind: .bates, prefix: "DEF", startNumber: 100, fontSize: 10, opacity: 1, swatch: .tertiary)
    }

    static func stamp(text: String, swatch: PageDecorationSwatch, pageRefID: UUID, rect: CGRect) -> PageDecoration {
        PageDecoration(
            kind: .stamp,
            text: text,
            pageRefID: pageRefID,
            rect: rect,
            fontSize: 22,
            opacity: 0.88,
            swatch: swatch
        )
    }

    /// A procedural hanko seal: `text` holds the 1–4 characters carved into it, `hankoShape`
    /// the border. Rendered in shu-iro vermillion by `HankoRenderer` (not `swatch`).
    static func hanko(text: String, shape: HankoShape, pageRefID: UUID, rect: CGRect) -> PageDecoration {
        PageDecoration(
            kind: .hanko,
            text: text,
            pageRefID: pageRefID,
            rect: rect,
            fontSize: 22,
            opacity: 1,
            swatch: .coral,
            hankoShape: shape
        )
    }

    /// A placed raster image — currently the barcode/QR insert (Feature G). `imageData` holds
    /// the PNG bytes; the exporter draws it into the page content stream (no PDFium image
    /// object, no annotation).
    static func image(imageData: Data, pageRefID: UUID, rect: CGRect) -> PageDecoration {
        PageDecoration(kind: .image, pageRefID: pageRefID, rect: rect, opacity: 1, imageData: imageData)
    }

    /// A vector PDF decoration. A nil `pageRefID` applies it to every page; a concrete
    /// `PageRef.id` targets only that workspace page.
    static func overlayPDF(
        pdfData: Data,
        placement: PageDecorationPDFPlacement = .over,
        pageRefID: UUID? = nil
    ) -> PageDecoration {
        PageDecoration(
            kind: .overlayPDF,
            pageRefID: pageRefID,
            opacity: 1,
            overlayPDFData: pdfData,
            overlayPDFPlacement: placement
        )
    }
}
