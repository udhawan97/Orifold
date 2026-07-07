import AppKit
import SwiftUI

/// Application-chrome appearance (light/dark/system). Separate from `DocumentComfortSettings`,
/// which controls only the PDF viewer's on-screen presentation.
enum AppAppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return L10n.string("appAppearanceMode.system.title")
        case .light: return L10n.string("appAppearanceMode.light.title")
        case .dark: return L10n.string("appAppearanceMode.dark.title")
        }
    }

    var systemImage: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon.fill"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

/// A viewer presentation preset. Purely cosmetic: it changes how the page is composited on
/// screen and never touches the underlying PDF content or exported output.
enum PageMode: String, CaseIterable, Identifiable, Codable {
    case defaultMode = "default"
    case light
    case dark
    case sepia
    case dim
    case highContrast

    var id: String { rawValue }

    var title: String {
        switch self {
        case .defaultMode: return L10n.string("pageMode.default.title")
        case .light: return L10n.string("pageMode.light.title")
        case .dark: return L10n.string("pageMode.dark.title")
        case .sepia: return L10n.string("pageMode.sepia.title")
        case .dim: return L10n.string("pageMode.dim.title")
        case .highContrast: return L10n.string("pageMode.highContrast.title")
        }
    }

    var systemImage: String {
        switch self {
        case .defaultMode: return "doc.plaintext"
        case .light: return "sun.max"
        case .dark: return "moon.fill"
        case .sepia: return "book.closed"
        case .dim: return "moon.haze"
        case .highContrast: return "circle.righthalf.filled"
        }
    }

    /// Multiply-blended tint (red, green, blue, alpha) applied above the page for this preset.
    fileprivate var toneTint: (red: Double, green: Double, blue: Double, alpha: Double) {
        switch self {
        case .defaultMode, .light: return (0, 0, 0, 0)
        case .dark: return (0.05, 0.05, 0.06, 0.82)
        case .sepia: return (0.93, 0.78, 0.55, 0.30)
        case .dim: return (0.4, 0.4, 0.44, 0.40)
        case .highContrast: return (0, 0, 0, 0)
        }
    }

    fileprivate var desaturation: Double {
        self == .highContrast ? 1 : 0
    }

    fileprivate var contrastLift: Double {
        self == .highContrast ? 35 : 0
    }

    fileprivate var canvasBackground: NSColor? {
        switch self {
        case .defaultMode, .light: return nil
        case .dark: return NSColor(srgbRed: 0.07, green: 0.07, blue: 0.08, alpha: 1)
        case .sepia: return NSColor(srgbRed: 0.93, green: 0.87, blue: 0.74, alpha: 1)
        case .dim: return NSColor(srgbRed: 0.17, green: 0.17, blue: 0.18, alpha: 1)
        case .highContrast: return NSColor(srgbRed: 0.02, green: 0.02, blue: 0.02, alpha: 1)
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .defaultMode: return nil
        case .light, .sepia: return .light
        case .dark, .dim, .highContrast: return .dark
        }
    }
}

/// A one-tap bundle of `DocumentComfortSettings` values. Purely a convenience factory —
/// applying a preset just assigns the resulting struct, so it composes with manual
/// fine-tuning afterward without any extra state to keep in sync.
enum ComfortPreset: String, CaseIterable, Identifiable {
    case defaultPreset = "default"
    case night
    case eyeCare
    case focus

    var id: String { rawValue }

    var title: String {
        switch self {
        case .defaultPreset: return L10n.string("documentComfort.preset.default.title")
        case .night: return L10n.string("documentComfort.preset.night.title")
        case .eyeCare: return L10n.string("documentComfort.preset.eyeCare.title")
        case .focus: return L10n.string("documentComfort.preset.focus.title")
        }
    }

    var systemImage: String {
        switch self {
        case .defaultPreset: return "circle.dashed"
        case .night: return "moon.stars.fill"
        case .eyeCare: return "eye.fill"
        case .focus: return "viewfinder"
        }
    }

    var settings: DocumentComfortSettings {
        switch self {
        case .defaultPreset:
            return .default
        case .night:
            var settings = DocumentComfortSettings()
            settings.pageMode = .dark
            settings.warmth = 35
            settings.brightness = 90
            settings.reduceGlare = true
            return settings
        case .eyeCare:
            var settings = DocumentComfortSettings()
            settings.pageMode = .sepia
            settings.warmth = 55
            settings.softenWhitePages = true
            settings.contrast = 110
            return settings
        case .focus:
            var settings = DocumentComfortSettings()
            settings.focusMode = true
            settings.reduceAnimations = true
            return settings
        }
    }
}

/// Viewer-only "eye care" presentation settings. These never mutate PDF data, annotations, or
/// export output — they only drive presentation layers composited above/behind the page (see
/// `DocumentComfortOverlayView` in ReadingCanvas.swift).
struct DocumentComfortSettings: Equatable, Codable {
    var pageMode: PageMode = .defaultMode
    var brightness: Double = 100
    var contrast: Double = 100
    var warmth: Double = 0
    var reduceGlare = false
    var softenWhitePages = false
    var focusMode = false
    var reduceAnimations = false

    static let `default` = DocumentComfortSettings()

    var isAtDefault: Bool { clamped == .default }

    /// The preset whose settings exactly match the current (clamped) values, if any.
    /// Used only to highlight a preset chip as selected — never a source of truth.
    var activePreset: ComfortPreset? {
        let current = clamped
        return ComfortPreset.allCases.first { $0.settings.clamped == current }
    }

    var clamped: DocumentComfortSettings {
        var copy = self
        copy.brightness = min(max(brightness, 50), 150)
        copy.contrast = min(max(contrast, 50), 150)
        copy.warmth = min(max(warmth, 0), 100)
        return copy
    }

    var colorScheme: ColorScheme? { clamped.pageMode.colorScheme }

    var canvasBackgroundColor: NSColor {
        clamped.pageMode.canvasBackground ?? .dsCanvasNS
    }

    /// Multiply-blended layer: page-mode tint, warm/blue-light shift, dimmed brightness,
    /// glare reduction, and white-page softening all combine into a single tint + alpha.
    var toneOverlayColor: NSColor {
        let settings = clamped
        let tint = settings.pageMode.toneTint
        let warmthFraction = settings.warmth / 100
        let warmRed = 1.00, warmGreen = 0.60, warmBlue = 0.28

        var red = tint.red + (warmRed - tint.red) * warmthFraction * 0.55
        var green = tint.green + (warmGreen - tint.green) * warmthFraction * 0.55
        let blue = tint.blue + (warmBlue - tint.blue) * warmthFraction * 0.55
        var alpha = max(tint.alpha, warmthFraction * 0.30)

        if settings.brightness < 100 {
            let dim = (100 - settings.brightness) / 100
            alpha = min(0.9, alpha + dim * 0.9)
        }
        if settings.reduceGlare {
            alpha = min(0.9, alpha + 0.10)
        }
        if settings.softenWhitePages {
            red = min(1, red + 0.05)
            green = min(1, green + 0.03)
            alpha = min(0.9, alpha + 0.05)
        }

        return NSColor(
            srgbRed: min(max(red, 0), 1),
            green: min(max(green, 0), 1),
            blue: min(max(blue, 0), 1),
            alpha: min(max(alpha, 0), 0.92)
        )
    }

    /// Screen-blended layer: only active above 100% brightness, lightens the page.
    var brightenOverlayColor: NSColor {
        let settings = clamped
        guard settings.brightness > 100 else { return .clear }
        let alpha = min(0.35, (settings.brightness - 100) / 100 * 0.7)
        return NSColor(white: 1, alpha: alpha)
    }

    /// Overlay-blended layer approximating a contrast nudge: a light-gray overlay softens
    /// contrast below 100%, a dark-gray overlay deepens it above 100%.
    var contrastOverlayColor: NSColor {
        let settings = clamped
        let delta = settings.contrast - 100 + settings.pageMode.contrastLift
        guard delta != 0 else { return .clear }
        let alpha = min(0.4, abs(delta) / 100 * 0.6)
        let value: CGFloat = delta < 0 ? 0.82 : 0.22
        return NSColor(white: value, alpha: alpha)
    }

    /// Saturation-blended layer: desaturates the page for High Contrast mode, with a light
    /// touch also applied by Reduce Glare (glare reads as washed-out, over-saturated highlights).
    var desaturationOverlayColor: NSColor {
        let settings = clamped
        var amount = settings.pageMode.desaturation
        if settings.reduceGlare {
            amount = max(amount, 0.18)
        }
        return NSColor(white: 0.5, alpha: min(1, amount))
    }
}
