import Foundation
import SwiftUI

enum SupportedLanguage: String, CaseIterable, Identifiable {
    case system
    case en
    case es
    case fr
    case hi
    case zhHans = "zh-Hans"
    case ja

    var id: String { rawValue }

    /// Always shown in its own native script, regardless of the app's current language.
    var nativeName: String {
        switch self {
        case .system: return "System"
        case .en: return "English"
        case .es: return "Español"
        case .fr: return "Français"
        case .hi: return "हिन्दी"
        case .zhHans: return "简体中文"
        case .ja: return "日本語"
        }
    }

    private static let supportedCodes: Set<String> = ["en", "es", "fr", "hi", "zh-Hans", "ja"]

    /// Resolves `.system` against the user's OS-preferred languages, clamped to a
    /// language Orifold ships translations for; falls back to English.
    static func resolvedLocale(for language: SupportedLanguage) -> Locale {
        guard language != .system else {
            for preferred in Locale.preferredLanguages {
                if supportedCodes.contains(preferred) { return Locale(identifier: preferred) }
                if preferred.hasPrefix("zh") && preferred.contains("Hans") {
                    return Locale(identifier: "zh-Hans")
                }
                let base = String(preferred.prefix(2))
                if supportedCodes.contains(base) { return Locale(identifier: base) }
            }
            return Locale(identifier: "en")
        }
        return Locale(identifier: language.rawValue)
    }
}

/// Drives the in-app language override for SwiftUI. Inject `effectiveLocale` via
/// `.environment(\.locale:)` at the root of each scene so the whole view tree
/// (Text, Button, .help, alerts) resolves strings against the chosen language,
/// with automatic fallback to English for any untranslated key.
@MainActor
final class LanguageManager: ObservableObject {
    nonisolated static let storageKey = "orifoldLanguage"

    @Published var language: SupportedLanguage {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: Self.storageKey) }
    }

    init() {
        let stored = UserDefaults.standard.string(forKey: Self.storageKey)
        language = stored.flatMap(SupportedLanguage.init(rawValue:)) ?? .system
    }

    var effectiveLocale: Locale {
        SupportedLanguage.resolvedLocale(for: language)
    }
}
