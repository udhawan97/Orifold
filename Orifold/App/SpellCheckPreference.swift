import Foundation

/// Backs the Settings toggle and both PDF text editors. Default ON: continuous
/// spell-check is the macOS text-editing convention; the preference exists for
/// users who edit machine-generated text where red underlines are noise.
enum SpellCheckPreference {
    static let defaultsKey = "orifoldSpellCheckEnabled"

    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: defaultsKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: defaultsKey) }
    }
}

#if canImport(AppKit)
import AppKit

extension NSTextView {
    /// Applies the user's spell-check preference to a PDF text editor. Grammar and
    /// automatic correction stay off unconditionally: silently rewriting a user's PDF
    /// text is never acceptable, so only the non-destructive red-underline check is
    /// preference-driven.
    func applySpellCheckPreference() {
        isContinuousSpellCheckingEnabled = SpellCheckPreference.isEnabled
        isGrammarCheckingEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
    }
}
#endif
