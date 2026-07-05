import Foundation

/// Localized-string lookup for non-SwiftUI contexts (error enums, PetBuddy
/// messages) that can't inherit the `.environment(\.locale:)` override applied
/// to the view tree. Reads the same `orifoldLanguage` preference SwiftUI's
/// `LanguageManager` writes, so both stay in sync without shared mutable state.
enum L10n {
    static var currentLocale: Locale {
        let stored = UserDefaults.standard.string(forKey: LanguageManager.storageKey)
        let language = stored.flatMap(SupportedLanguage.init(rawValue:)) ?? .system
        return SupportedLanguage.resolvedLocale(for: language)
    }

    static func string(_ key: String.LocalizationValue) -> String {
        String(localized: key, locale: currentLocale)
    }

    static func string(_ key: StaticString, defaultValue: String.LocalizationValue) -> String {
        String(localized: key, defaultValue: defaultValue, locale: currentLocale)
    }
}
