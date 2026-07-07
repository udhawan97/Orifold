import Foundation

/// Localized-string lookup for non-SwiftUI contexts (error enums, PetBuddy
/// messages) that can't inherit the `.environment(\.locale:)` override applied
/// to the view tree. Reads the same `orifoldLanguage` preference SwiftUI's
/// `LanguageManager` writes, so both stay in sync without shared mutable state.
enum L10n {
    /// `String(localized:)` resolves its string catalog from `bundle` if given, else
    /// falls back to `Bundle.main` — which is the *host process's* main bundle, not
    /// necessarily where `Localizable.xcstrings` actually lives. That default is wrong
    /// for the `OrifoldTests` target: it runs as a standalone XCTest bundle injected
    /// into the app via `BUNDLE_LOADER` rather than a `TEST_HOST`-hosted process, so
    /// `Bundle.main` there is the xctest runner, and every lookup silently falls back
    /// to printing the raw key. Anchoring to the bundle that actually contains this
    /// type (compiled into Orifold.app regardless of which process loaded it) resolves
    /// correctly in both the shipping app and the Xcode-built test target. Under
    /// `swift build`/`swift test`, though, SPM compiles Localizable.xcstrings into a
    /// separate sibling resource bundle (`Orifold_Orifold.bundle`) that `Bundle(for:)`
    /// never finds — only the auto-generated `Bundle.module` accessor points to it.
    #if SWIFT_PACKAGE
    private static let bundle = Bundle.module
    #else
    private final class BundleAnchor {}
    private static let bundle = Bundle(for: BundleAnchor.self)
    #endif

    static var currentLocale: Locale {
        let stored = UserDefaults.standard.string(forKey: LanguageManager.storageKey)
        let language = stored.flatMap(SupportedLanguage.init(rawValue:)) ?? .system
        return SupportedLanguage.resolvedLocale(for: language)
    }

    /// - Parameter locale: Pass a SwiftUI view's own `@Environment(\.locale)` here
    ///   when calling from `body`. Beyond correctness, this makes the view's `body`
    ///   actually *read* that environment value — SwiftUI only re-invokes `body` on
    ///   an environment change for views that read it during the previous
    ///   evaluation, so merely declaring `@Environment(\.locale)` without using it
    ///   does not, by itself, make a view refresh when the language changes.
    ///   Omit it only for non-SwiftUI contexts (error enums, PetBuddy messages),
    ///   which fall back to reading the stored preference directly.
    static func string(_ key: String.LocalizationValue, locale: Locale? = nil) -> String {
        let resolvedLocale = locale ?? currentLocale
        let resolved = String(localized: key, bundle: bundle, locale: resolvedLocale)
        #if SWIFT_PACKAGE
        // `swift build`/`swift test` copy Localizable.xcstrings byte-for-byte instead
        // of compiling it the way Xcode's build system does, so the lookup above always
        // misses and silently returns the raw key. Only reachable in that CLI build —
        // Xcode-built targets resolve via the catalog above and never touch this table.
        if let rawKey = rawKeyText(key), resolved == rawKey, let fallback = rawCatalogFallback(for: rawKey, locale: resolvedLocale) {
            return fallback
        }
        #endif
        return resolved
    }

    #if SWIFT_PACKAGE
    /// `String.LocalizationValue` has no public accessor for its source key —
    /// string interpolation prints its `Equatable`-only synthesized description
    /// (`LocalizationValue(arguments: [], key: "...")`), not the key text itself —
    /// so reflection is the only way to recover the literal string.
    private static func rawKeyText(_ key: String.LocalizationValue) -> String? {
        Mirror(reflecting: key).children.first { $0.label == "key" }?.value as? String
    }
    #endif

    static func string(_ key: StaticString, defaultValue: String.LocalizationValue) -> String {
        String(localized: key, defaultValue: defaultValue, bundle: bundle, locale: currentLocale)
    }

    /// Builds a display string from a catalog entry that contains `%@`/`%lld`-style
    /// format placeholders. Use this for interpolated `Text`/`Button` sites instead of
    /// `Text("key \(arg)")` — the latter's runtime lookup key is a compiler-derived
    /// format string, not the literal source syntax, so a catalog entry authored with
    /// the literal `\(arg)` text never actually matches at lookup time.
    static func format(_ key: String, _ args: CVarArg..., locale: Locale? = nil) -> String {
        String(format: string(String.LocalizationValue(key), locale: locale), arguments: args)
    }

    #if SWIFT_PACKAGE
    /// Lazily parsed values straight out of the raw `Localizable.xcstrings` JSON,
    /// keyed by `"<language>|<key>"`, used only as the CLI-build fallback described
    /// in `string(_:)` above.
    private static let rawCatalogFallbackTable: [String: String] = {
        guard let url = bundle.url(forResource: "Localizable", withExtension: "xcstrings"),
              let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let strings = root["strings"] as? [String: Any] else { return [:] }
        var table: [String: String] = [:]
        for (key, entry) in strings {
            guard let entry = entry as? [String: Any],
                  let localizations = entry["localizations"] as? [String: Any] else { continue }
            for (language, localization) in localizations {
                guard let localization = localization as? [String: Any],
                      let unit = localization["stringUnit"] as? [String: Any],
                      let value = unit["value"] as? String else { continue }
                table["\(language)|\(key)"] = value
            }
        }
        return table
    }()

    private static func rawCatalogFallback(for key: String, locale: Locale) -> String? {
        rawCatalogFallbackTable["\(locale.language.languageCode?.identifier ?? "en")|\(key)"]
            ?? rawCatalogFallbackTable["en|\(key)"]
    }
    #endif
}
