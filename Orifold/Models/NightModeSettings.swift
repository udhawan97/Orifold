import AppKit
import SwiftUI

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

struct NightModeSettings: Equatable {
    var warmth: Double
    var intensity: Double
    var dimming: Double

    static let `default` = NightModeSettings(warmth: 0.62, intensity: 0.42, dimming: 0.38)
    static let gentle = NightModeSettings(warmth: 0.38, intensity: 0.28, dimming: 0.24)
    static let paper = NightModeSettings(warmth: 0.58, intensity: 0.40, dimming: 0.34)
    static let amber = NightModeSettings(warmth: 0.86, intensity: 0.58, dimming: 0.50)

    var clamped: NightModeSettings {
        NightModeSettings(
            warmth: min(max(warmth, 0), 1),
            intensity: min(max(intensity, 0), 1),
            dimming: min(max(dimming, 0), 1)
        )
    }

    var overlayColor: NSColor {
        let settings = clamped
        let coolRed = 0.98
        let coolGreen = 0.82
        let coolBlue = 0.58
        let warmRed = 1.00
        let warmGreen = 0.56
        let warmBlue = 0.20
        let alpha = 0.08 + settings.intensity * 0.34

        return NSColor(
            srgbRed: coolRed + (warmRed - coolRed) * settings.warmth,
            green: coolGreen + (warmGreen - coolGreen) * settings.warmth,
            blue: coolBlue + (warmBlue - coolBlue) * settings.warmth,
            alpha: alpha
        )
    }

    var canvasBackgroundColor: NSColor {
        let settings = clamped
        let brightness = 0.074 - settings.dimming * 0.045
        let warmthLift = settings.warmth * 0.014
        return NSColor(
            srgbRed: brightness + warmthLift,
            green: brightness + warmthLift * 0.72,
            blue: brightness,
            alpha: 1
        )
    }
}

enum NightModePreset: String, CaseIterable, Identifiable {
    case gentle
    case paper
    case amber

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gentle: return L10n.string("nightModePreset.gentle.title")
        case .paper: return L10n.string("nightModePreset.paper.title")
        case .amber: return L10n.string("nightModePreset.amber.title")
        }
    }

    var systemImage: String {
        switch self {
        case .gentle: return "moon"
        case .paper: return "doc.text"
        case .amber: return "sun.min"
        }
    }

    var settings: NightModeSettings {
        switch self {
        case .gentle: return .gentle
        case .paper: return .paper
        case .amber: return .amber
        }
    }
}
