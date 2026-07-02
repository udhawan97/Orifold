import SwiftUI
import AppKit

// MARK: - Adaptive color helper

extension Color {
    init(light lightColor: NSColor, dark darkColor: NSColor) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            switch appearance.bestMatch(from: [.aqua, .darkAqua]) {
            case .darkAqua: return darkColor
            default:        return lightColor
            }
        })
    }
}

// MARK: - SwiftUI semantic color tokens

extension Color {
    /// Cool neutral ground behind PDF pages
    static let dsCanvas = Color(
        light: NSColor(srgbRed: 0.918, green: 0.953, blue: 0.969, alpha: 1),   // #EAF3F7
        dark:  NSColor(srgbRed: 0.039, green: 0.067, blue: 0.094, alpha: 1))   // #0A1118

    /// Panels: sidebar, inspector, popovers
    static let dsSurface = Color(
        light: NSColor(srgbRed: 0.969, green: 0.984, blue: 0.992, alpha: 1),   // #F7FBFD
        dark:  NSColor(srgbRed: 0.063, green: 0.102, blue: 0.133, alpha: 1))   // #101A22

    /// Raised cards, thumbnails
    static let dsCard = Color(
        light: NSColor(srgbRed: 1.000, green: 1.000, blue: 1.000, alpha: 1),   // #FFFFFF
        dark:  NSColor(srgbRed: 0.086, green: 0.137, blue: 0.176, alpha: 1))   // #16232D

    /// Primary glass-blue accent from the app icon, used sparingly
    static let dsAccent = Color(
        light: NSColor(srgbRed: 0.071, green: 0.478, blue: 0.647, alpha: 1),   // #127AA5
        dark:  NSColor(srgbRed: 0.282, green: 0.757, blue: 0.859, alpha: 1))   // #48C1DB

    /// Soft accent fill for selection backgrounds and hover tints
    static let dsAccentSoft = Color(
        light: NSColor(srgbRed: 0.071, green: 0.478, blue: 0.647, alpha: 0.13),
        dark:  NSColor(srgbRed: 0.282, green: 0.757, blue: 0.859, alpha: 0.20))

    /// Distinct service tints for primary toolbar actions.
    static let dsEditTextAccent = Color(
        light: NSColor(srgbRed: 0.071, green: 0.478, blue: 0.647, alpha: 1),
        dark:  NSColor(srgbRed: 0.282, green: 0.757, blue: 0.859, alpha: 1))

    static let dsEditTextSoft = Color(
        light: NSColor(srgbRed: 0.071, green: 0.478, blue: 0.647, alpha: 0.13),
        dark:  NSColor(srgbRed: 0.282, green: 0.757, blue: 0.859, alpha: 0.18))

    static let dsEditTextHover = Color(
        light: NSColor(srgbRed: 0.071, green: 0.478, blue: 0.647, alpha: 0.18),
        dark:  NSColor(srgbRed: 0.282, green: 0.757, blue: 0.859, alpha: 0.24))

    static let dsSignatureAccent = Color(
        light: NSColor(srgbRed: 0.749, green: 0.333, blue: 0.439, alpha: 1),
        dark:  NSColor(srgbRed: 0.984, green: 0.478, blue: 0.576, alpha: 1))

    static let dsSignatureSoft = Color(
        light: NSColor(srgbRed: 0.749, green: 0.333, blue: 0.439, alpha: 0.12),
        dark:  NSColor(srgbRed: 0.984, green: 0.478, blue: 0.576, alpha: 0.17))

    static let dsSignatureHover = Color(
        light: NSColor(srgbRed: 0.749, green: 0.333, blue: 0.439, alpha: 0.17),
        dark:  NSColor(srgbRed: 0.984, green: 0.478, blue: 0.576, alpha: 0.23))

    static let dsTextPrimary = Color(
        light: NSColor(srgbRed: 0.063, green: 0.137, blue: 0.200, alpha: 1),   // #102333
        dark:  NSColor(srgbRed: 0.929, green: 0.965, blue: 0.980, alpha: 1))   // #EDF6FA

    static let dsTextSecondary = Color(
        light: NSColor(srgbRed: 0.275, green: 0.349, blue: 0.404, alpha: 1),   // #465967
        dark:  NSColor(srgbRed: 0.690, green: 0.780, blue: 0.827, alpha: 1))   // #B0C7D3

    static let dsTextTertiary = Color(
        light: NSColor(srgbRed: 0.455, green: 0.510, blue: 0.549, alpha: 1),   // #74828C
        dark:  NSColor(srgbRed: 0.478, green: 0.569, blue: 0.620, alpha: 1))   // #7A919E

    /// Hairlines and dividers
    static let dsSeparator = Color(
        light: NSColor(srgbRed: 0.063, green: 0.137, blue: 0.200, alpha: 0.10),
        dark:  NSColor(srgbRed: 0.929, green: 0.965, blue: 0.980, alpha: 0.12))

    // MARK: Annotation palette (replaces raw .yellow / .systemBlue)
    static let dsHighlightYellow    = Color(red: 0.984, green: 0.890, blue: 0.510)  // #FBE382
    static let dsAnnotationCoral    = Color(red: 0.937, green: 0.541, blue: 0.494)  // #EF8A7E
    static let dsAnnotationSage     = Color(red: 0.553, green: 0.761, blue: 0.671)  // #8DC2AB
    static let dsAnnotationSky      = Color(red: 0.455, green: 0.690, blue: 0.867)  // #74B0DD
    static let dsAnnotationLavender = Color(red: 0.690, green: 0.651, blue: 0.867)  // #B0A6DD

    static let annotationSwatches: [(Color, NSColor)] = [
        (.dsHighlightYellow,    .dsAnnotationYellow),
        (.dsAnnotationCoral,    .dsAnnotationCoralNS),
        (.dsAnnotationSage,     .dsAnnotationSageNS),
        (.dsAnnotationSky,      .dsAnnotationSkyNS),
        (.dsAnnotationLavender, .dsAnnotationLavNS),
    ]
}

// MARK: - NSColor semantic tokens (for AppKit/PDFKit code)

extension NSColor {
    static let dsCanvasNS: NSColor = NSColor(name: nil) { app in
        app.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0.039, green: 0.067, blue: 0.094, alpha: 1)
            : NSColor(srgbRed: 0.918, green: 0.953, blue: 0.969, alpha: 1)
    }
    static let dsSurfaceNS: NSColor = NSColor(name: nil) { app in
        app.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0.063, green: 0.102, blue: 0.133, alpha: 1)
            : NSColor(srgbRed: 0.969, green: 0.984, blue: 0.992, alpha: 1)
    }
    static let dsTextPrimaryNS: NSColor = NSColor(name: nil) { app in
        app.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0.929, green: 0.965, blue: 0.980, alpha: 1)
            : NSColor(srgbRed: 0.063, green: 0.137, blue: 0.200, alpha: 1)
    }
    static let dsTextTertiaryNS: NSColor = NSColor(name: nil) { app in
        app.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0.478, green: 0.569, blue: 0.620, alpha: 1)
            : NSColor(srgbRed: 0.455, green: 0.510, blue: 0.549, alpha: 1)
    }
    static let dsSeparatorNS: NSColor = NSColor(name: nil) { app in
        app.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0.929, green: 0.965, blue: 0.980, alpha: 0.12)
            : NSColor(srgbRed: 0.063, green: 0.137, blue: 0.200, alpha: 0.10)
    }

    // Annotation palette as NSColor
    static let dsAnnotationYellow   = NSColor(srgbRed: 0.984, green: 0.890, blue: 0.510, alpha: 1)
    static let dsAnnotationCoralNS  = NSColor(srgbRed: 0.937, green: 0.541, blue: 0.494, alpha: 1)
    static let dsAnnotationSageNS   = NSColor(srgbRed: 0.553, green: 0.761, blue: 0.671, alpha: 1)
    static let dsAnnotationSkyNS    = NSColor(srgbRed: 0.455, green: 0.690, blue: 0.867, alpha: 1)
    static let dsAnnotationLavNS    = NSColor(srgbRed: 0.690, green: 0.651, blue: 0.867, alpha: 1)

    /// Default ink stroke color
    static let dsInk = NSColor(srgbRed: 0.071, green: 0.286, blue: 0.443, alpha: 1)

    /// Glass-blue accent for AppKit drawing (BoundaryPage, etc.)
    static let dsAccentNS: NSColor = NSColor(name: nil) { app in
        app.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0.282, green: 0.757, blue: 0.859, alpha: 1)
            : NSColor(srgbRed: 0.071, green: 0.478, blue: 0.647, alpha: 1)
    }

    static let dsAccentSoftNS: NSColor = NSColor(name: nil) { app in
        app.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0.282, green: 0.757, blue: 0.859, alpha: 0.20)
            : NSColor(srgbRed: 0.071, green: 0.478, blue: 0.647, alpha: 0.13)
    }
}

// MARK: - Spacing (4-pt grid)

extension CGFloat {
    static let dsXS:  CGFloat = 4
    static let dsSM:  CGFloat = 8
    static let dsMD:  CGFloat = 12
    static let dsLG:  CGFloat = 16
    static let dsXL:  CGFloat = 24
    static let dsXXL: CGFloat = 32
}

// MARK: - Corner radii

extension CGFloat {
    static let dsRadiusSm: CGFloat = 6
    static let dsRadiusMd: CGFloat = 10
    static let dsRadiusLg: CGFloat = 16
}

// MARK: - Elevation

extension View {
    func dsElevation() -> some View {
        shadow(color: .black.opacity(0.07), radius: 20, x: 0, y: 10)
    }
}

// MARK: - Typography scale

extension Font {
    /// Serif display — wordmark and empty-state headline only
    static func dsDisplay(size: CGFloat = 34) -> Font {
        .system(size: size, weight: .semibold, design: .serif)
    }
    static func dsTitle()    -> Font { .system(size: 17, weight: .semibold) }
    static func dsHeadline() -> Font { .system(size: 15, weight: .semibold) }
    static func dsBody()     -> Font { .system(size: 14, weight: .regular) }
    static func dsCaption()  -> Font { .system(size: 12, weight: .regular) }
}
