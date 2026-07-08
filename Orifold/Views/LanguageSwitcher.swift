import SwiftUI

/// Compact language picker shown on the onboarding/empty-state screen.
/// Selecting a language updates `LanguageManager`, which the app root
/// projects into `.environment(\.locale:)` for the whole view tree, and
/// persists to `UserDefaults` so the choice survives relaunch.
struct LanguageSwitcher: View {
    @EnvironmentObject private var languageManager: LanguageManager

    var body: some View {
        Menu {
            ForEach(SupportedLanguage.allCases) { language in
                Button {
                    languageManager.language = language
                } label: {
                    if languageManager.language == language {
                        Label(language.nativeName, systemImage: "checkmark")
                    } else {
                        Text(language.nativeName)
                    }
                }
            }
        } label: {
            Label(languageManager.language.nativeName, systemImage: "globe")
                .font(.dsCaption())
                .foregroundStyle(Color.dsTextSecondary)
                .padding(.horizontal, .dsSM)
                .padding(.vertical, 6)
                .background(Color.dsCard, in: Capsule())
                .overlay {
                    Capsule().strokeBorder(Color.dsSeparator, lineWidth: 1)
                }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(L10n.string("languageSwitcher.help"))
        .accessibilityLabel(L10n.string("languageSwitcher.accessibilityLabel"))
    }
}
