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
//
// "Ai-zome ink" palette: indigo-dye (ai-zome) neutrals warmed with a whisper of
// washi paper, a glacier-blue accent, and a shu-iro (seal vermillion) accent
// reserved for signing. Quiet, uncluttered, generous with negative space (ma).
// All tokens are static values — no materials or runtime blending.

extension Color {
    /// Cool neutral ground behind PDF pages, warmed a touch like washi paper
    static let dsCanvas = Color(
        light: NSColor(srgbRed: 0.933, green: 0.941, blue: 0.949, alpha: 1),   // #EEF0F2
        dark:  NSColor(srgbRed: 0.039, green: 0.063, blue: 0.110, alpha: 1))   // #0A101C

    /// Panels: sidebar, inspector, popovers
    static let dsSurface = Color(
        light: NSColor(srgbRed: 0.973, green: 0.973, blue: 0.973, alpha: 1),   // #F8F8F8
        dark:  NSColor(srgbRed: 0.067, green: 0.102, blue: 0.161, alpha: 1))   // #111A29

    /// Raised cards, thumbnails
    static let dsCard = Color(
        light: NSColor(srgbRed: 1.000, green: 0.996, blue: 0.988, alpha: 1),   // #FFFEFC
        dark:  NSColor(srgbRed: 0.094, green: 0.141, blue: 0.204, alpha: 1))   // #182434

    /// Primary glacier-blue accent from the app icon, used sparingly
    static let dsAccent = Color(
        light: NSColor(srgbRed: 0.047, green: 0.404, blue: 0.651, alpha: 1),   // #0C67A6
        dark:  NSColor(srgbRed: 0.310, green: 0.765, blue: 0.910, alpha: 1))   // #4FC3E8

    /// Luminous end of the accent ramp — only as the bright stop of dsAccentGradient
    static let dsAccentBright = Color(
        light: NSColor(srgbRed: 0.082, green: 0.639, blue: 0.769, alpha: 1),   // #15A3C4
        dark:  NSColor(srgbRed: 0.478, green: 0.871, blue: 0.957, alpha: 1))   // #7ADEF4

    /// Soft accent fill for selection backgrounds and hover tints
    static let dsAccentSoft = Color(
        light: NSColor(srgbRed: 0.047, green: 0.404, blue: 0.651, alpha: 0.12),
        dark:  NSColor(srgbRed: 0.310, green: 0.765, blue: 0.910, alpha: 0.20))

    /// Distinct service tints for primary toolbar actions.
    static let dsEditTextAccent = Color(
        light: NSColor(srgbRed: 0.047, green: 0.404, blue: 0.651, alpha: 1),
        dark:  NSColor(srgbRed: 0.310, green: 0.765, blue: 0.910, alpha: 1))

    static let dsEditTextSoft = Color(
        light: NSColor(srgbRed: 0.047, green: 0.404, blue: 0.651, alpha: 0.12),
        dark:  NSColor(srgbRed: 0.310, green: 0.765, blue: 0.910, alpha: 0.18))

    static let dsEditTextHover = Color(
        light: NSColor(srgbRed: 0.047, green: 0.404, blue: 0.651, alpha: 0.17),
        dark:  NSColor(srgbRed: 0.310, green: 0.765, blue: 0.910, alpha: 0.24))

    /// Amber accent for non-error cautions (toast/banner warning state) — distinct from
    /// both the error and success tints below.
    static let dsWarningAccent = Color(
        light: NSColor(srgbRed: 0.702, green: 0.494, blue: 0.039, alpha: 1),   // #B37E0A
        dark:  NSColor(srgbRed: 0.976, green: 0.769, blue: 0.322, alpha: 1))   // #F9C452

    /// Adaptive success/error accents for toast/banner states, kept distinct from
    /// `dsAnnotationSage`/`dsAnnotationCoral` — those are fixed annotation-swatch colors
    /// (meant to look the same over a page regardless of app appearance), not tuned for
    /// legibility as caption-sized text/icon tint in both light and dark UI chrome.
    static let dsSuccessAccent = Color(
        light: NSColor(srgbRed: 0.220, green: 0.500, blue: 0.365, alpha: 1),   // #38805D
        dark:  NSColor(srgbRed: 0.455, green: 0.804, blue: 0.643, alpha: 1))   // #74CDA4

    static let dsErrorAccent = Color(
        light: NSColor(srgbRed: 0.749, green: 0.196, blue: 0.153, alpha: 1),   // #BF3227
        dark:  NSColor(srgbRed: 0.976, green: 0.478, blue: 0.427, alpha: 1))   // #F97A6D

    /// Shu-iro — the vermillion of a hanko seal stamp. Reserved for signing/stamping.
    static let dsSignatureAccent = Color(
        light: NSColor(srgbRed: 0.749, green: 0.267, blue: 0.173, alpha: 1),   // #BF442C
        dark:  NSColor(srgbRed: 0.976, green: 0.549, blue: 0.408, alpha: 1))   // #F98C68

    static let dsSignatureSoft = Color(
        light: NSColor(srgbRed: 0.749, green: 0.267, blue: 0.173, alpha: 0.12),
        dark:  NSColor(srgbRed: 0.976, green: 0.549, blue: 0.408, alpha: 0.17))

    static let dsSignatureHover = Color(
        light: NSColor(srgbRed: 0.749, green: 0.267, blue: 0.173, alpha: 0.17),
        dark:  NSColor(srgbRed: 0.976, green: 0.549, blue: 0.408, alpha: 0.23))

    static let dsTextPrimary = Color(
        light: NSColor(srgbRed: 0.075, green: 0.122, blue: 0.200, alpha: 1),   // #131F33
        dark:  NSColor(srgbRed: 0.929, green: 0.953, blue: 0.980, alpha: 1))   // #EDF3FA

    static let dsTextSecondary = Color(
        light: NSColor(srgbRed: 0.267, green: 0.337, blue: 0.420, alpha: 1),   // #44566B
        dark:  NSColor(srgbRed: 0.686, green: 0.761, blue: 0.839, alpha: 1))   // #AFC2D6

    static let dsTextTertiary = Color(
        light: NSColor(srgbRed: 0.443, green: 0.502, blue: 0.561, alpha: 1),   // #71808F
        dark:  NSColor(srgbRed: 0.486, green: 0.561, blue: 0.639, alpha: 1))   // #7C8FA3

    /// Hairlines and dividers
    static let dsSeparator = Color(
        light: NSColor(srgbRed: 0.075, green: 0.122, blue: 0.200, alpha: 0.10),
        dark:  NSColor(srgbRed: 0.929, green: 0.953, blue: 0.980, alpha: 0.12))

    // MARK: Annotation palette (replaces raw .yellow / .systemBlue)
    static let dsHighlightYellow    = Color(red: 0.984, green: 0.890, blue: 0.510)  // #FBE382
    static let dsAnnotationCoral    = Color(red: 0.937, green: 0.541, blue: 0.494)  // #EF8A7E
    static let dsAnnotationSage     = Color(red: 0.553, green: 0.761, blue: 0.671)  // #8DC2AB
    static let dsAnnotationSky      = Color(red: 0.455, green: 0.690, blue: 0.867)  // #74B0DD
    static let dsAnnotationLavender = Color(red: 0.690, green: 0.651, blue: 0.867)  // #B0A6DD

    /// Neutral graphite — for icon tiles that shouldn't read as a "color", e.g. Protect.
    static let dsGraphite = Color(red: 0.325, green: 0.365, blue: 0.420)

    static let annotationSwatches: [(Color, NSColor)] = [
        (.dsHighlightYellow,    .dsAnnotationYellow),
        (.dsAnnotationCoral,    .dsAnnotationCoralNS),
        (.dsAnnotationSage,     .dsAnnotationSageNS),
        (.dsAnnotationSky,      .dsAnnotationSkyNS),
        (.dsAnnotationLavender, .dsAnnotationLavNS),
    ]
}

// MARK: - Accent gradient

extension LinearGradient {
    /// Glacier ramp for hero moments only (empty state, drop targets) —
    /// static two-stop gradient, never behind text at body sizes.
    static let dsAccent = LinearGradient(
        colors: [.dsAccentBright, .dsAccent],
        startPoint: .topLeading,
        endPoint: .bottomTrailing)
}

// MARK: - NSColor semantic tokens (for AppKit/PDFKit code)

extension NSColor {
    static let dsCanvasNS: NSColor = NSColor(name: nil) { app in
        app.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0.039, green: 0.063, blue: 0.110, alpha: 1)
            : NSColor(srgbRed: 0.925, green: 0.941, blue: 0.961, alpha: 1)
    }
    static let dsSurfaceNS: NSColor = NSColor(name: nil) { app in
        app.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0.067, green: 0.102, blue: 0.161, alpha: 1)
            : NSColor(srgbRed: 0.965, green: 0.976, blue: 0.988, alpha: 1)
    }
    static let dsTextPrimaryNS: NSColor = NSColor(name: nil) { app in
        app.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0.929, green: 0.953, blue: 0.980, alpha: 1)
            : NSColor(srgbRed: 0.075, green: 0.122, blue: 0.200, alpha: 1)
    }
    static let dsTextTertiaryNS: NSColor = NSColor(name: nil) { app in
        app.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0.486, green: 0.561, blue: 0.639, alpha: 1)
            : NSColor(srgbRed: 0.443, green: 0.502, blue: 0.561, alpha: 1)
    }
    static let dsSeparatorNS: NSColor = NSColor(name: nil) { app in
        app.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0.929, green: 0.953, blue: 0.980, alpha: 0.12)
            : NSColor(srgbRed: 0.075, green: 0.122, blue: 0.200, alpha: 0.10)
    }

    // Annotation palette as NSColor
    static let dsAnnotationYellow   = NSColor(srgbRed: 0.984, green: 0.890, blue: 0.510, alpha: 1)
    static let dsAnnotationCoralNS  = NSColor(srgbRed: 0.937, green: 0.541, blue: 0.494, alpha: 1)
    static let dsAnnotationSageNS   = NSColor(srgbRed: 0.553, green: 0.761, blue: 0.671, alpha: 1)
    static let dsAnnotationSkyNS    = NSColor(srgbRed: 0.455, green: 0.690, blue: 0.867, alpha: 1)
    static let dsAnnotationLavNS    = NSColor(srgbRed: 0.690, green: 0.651, blue: 0.867, alpha: 1)

    /// Default ink stroke color
    static let dsInk = NSColor(srgbRed: 0.055, green: 0.227, blue: 0.361, alpha: 1)   // #0E3A5C

    /// Glacier-blue accent for AppKit drawing (BoundaryPage, etc.)
    static let dsAccentNS: NSColor = NSColor(name: nil) { app in
        app.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0.310, green: 0.765, blue: 0.910, alpha: 1)
            : NSColor(srgbRed: 0.047, green: 0.404, blue: 0.651, alpha: 1)
    }

    static let dsAccentSoftNS: NSColor = NSColor(name: nil) { app in
        app.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0.310, green: 0.765, blue: 0.910, alpha: 0.20)
            : NSColor(srgbRed: 0.047, green: 0.404, blue: 0.651, alpha: 0.12)
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

// MARK: - Gami companion tokens
//
// Spacing/sizing constants for the Gami companion chip and hint bubble, kept apart
// from the general spacing scale since they encode specific clearance guarantees
// (never overlapping document content) rather than generic rhythm.

extension CGFloat {
    /// Gap between the hint bubble and the companion chip.
    static let gamiBubbleGap: CGFloat = 12
    /// Minimum clearance kept between the bubble's bounds and the visible PDF page
    /// rect / any tracked exclusion zone (selection, edit handles, toolbar, etc).
    static let gamiContentClearance: CGFloat = 24
    /// Minimum inset from the window edges.
    static let gamiEdgeInset: CGFloat = 16
    /// At-rest chip container size (icon + padding), workspace presentation.
    static let gamiChipCompact: CGFloat = 64
    /// Hover-expanded chip container size, workspace presentation.
    static let gamiChipHover: CGFloat = 96
    /// Chip container size in cramped/small-window mode.
    static let gamiChipCramped: CGFloat = 44
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
        shadow(color: .black.opacity(0.08), radius: 18, x: 0, y: 8)
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

// MARK: - Calm-typography tracking
//
// A little extra letter-spacing on the wordmark and small caps-like labels,
// in place of heavier weights — quieter emphasis.

extension CGFloat {
    static let dsWordmarkTracking: CGFloat = 0.6
    static let dsLabelTracking: CGFloat = 0.4
}

// MARK: - Ensō motif
//
// A single, quiet brush-circle stroke — never closed, never symmetric —
// used sparingly as a decorative flourish (About popover, empty states).

// MARK: - Folded-corner motif
//
// A quiet dog-ear: one corner of an otherwise-rounded rect is cut on the diagonal,
// as if that corner of the sheet were folded back. Used for the sidebar's workspace
// card, the selected document card, and the drop-zone footer — the origami motif
// applied as real geometry (no seam against the background) rather than an overlay.

struct FoldedCornerRect: Shape, InsettableShape {
    var cornerRadius: CGFloat
    var foldSize: CGFloat
    private var insetAmount: CGFloat = 0

    init(cornerRadius: CGFloat, foldSize: CGFloat) {
        self.cornerRadius = cornerRadius
        self.foldSize = foldSize
    }

    func path(in rect: CGRect) -> Path {
        let insetRect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let r = max(0, min(cornerRadius - insetAmount, insetRect.width / 2, insetRect.height / 2))
        let f = max(0, min(foldSize - insetAmount, insetRect.width - r, insetRect.height - r))
        var path = Path()
        path.move(to: CGPoint(x: insetRect.minX + r, y: insetRect.minY))
        path.addLine(to: CGPoint(x: insetRect.maxX - f, y: insetRect.minY))
        path.addLine(to: CGPoint(x: insetRect.maxX, y: insetRect.minY + f))
        path.addLine(to: CGPoint(x: insetRect.maxX, y: insetRect.maxY - r))
        path.addArc(center: CGPoint(x: insetRect.maxX - r, y: insetRect.maxY - r), radius: r,
                    startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        path.addLine(to: CGPoint(x: insetRect.minX + r, y: insetRect.maxY))
        path.addArc(center: CGPoint(x: insetRect.minX + r, y: insetRect.maxY - r), radius: r,
                    startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        path.addLine(to: CGPoint(x: insetRect.minX, y: insetRect.minY + r))
        path.addArc(center: CGPoint(x: insetRect.minX + r, y: insetRect.minY + r), radius: r,
                    startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        path.closeSubpath()
        return path
    }

    func inset(by amount: CGFloat) -> some InsettableShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}

/// The small triangular flap along the folded-corner cut, drawn as its own thin
/// accent so the notch reads as paper folded back rather than simply clipped away.
private struct FoldedCornerFlap: Shape {
    var foldSize: CGFloat

    func path(in rect: CGRect) -> Path {
        let f = min(foldSize, rect.width, rect.height)
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX - f, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + f))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

extension View {
    /// Fills with `fill`, clips to a folded-corner rounded rect, and adds the
    /// fold-back flap accent plus a matching hairline stroke.
    func foldedCard(
        fill: Color,
        stroke: Color = .dsSeparator,
        radius: CGFloat = .dsRadiusMd,
        foldSize: CGFloat = 10
    ) -> some View {
        let shape = FoldedCornerRect(cornerRadius: radius, foldSize: foldSize)
        return self
            .background(fill, in: shape)
            .overlay(FoldedCornerFlap(foldSize: foldSize).fill(stroke.opacity(0.6)))
            .overlay(shape.strokeBorder(stroke, lineWidth: 1))
    }
}

// MARK: - Crease rule
//
// A quiet fold-shadow divider — fades to nothing rather than a uniform hairline.

struct CreaseRule: View {
    var height: CGFloat = 1

    var body: some View {
        LinearGradient(colors: [.dsSeparator, .clear], startPoint: .leading, endPoint: .trailing)
            .frame(height: height)
    }
}

// MARK: - Ensō motif

struct EnsoRing: Shape {
    /// Fraction of the circle left open, like a real brushstroke's gap.
    var gap: Double = 0.16
    /// Rotates where the gap sits.
    var rotation: Angle = .degrees(-100)

    func path(in rect: CGRect) -> Path {
        let start = rotation.degrees
        let end = start + (360 * (1 - gap))
        var path = Path()
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.midY),
            radius: min(rect.width, rect.height) / 2,
            startAngle: .degrees(start),
            endAngle: .degrees(end),
            clockwise: false)
        return path
    }
}
