import SwiftUI

/// The app's native macOS Settings window (⌘,). Scoped to controls that already have a
/// real, working implementation elsewhere in the app — language and appearance already
/// propagate live to open documents via the existing `@AppStorage`/`onChange` wiring in
/// `ContentView`. Deliberately does not add toolbar density/label toggles, export-default
/// pickers, or Document Comfort defaults, since those preferences have no backing behavior
/// (or, for Document Comfort, already have their own dedicated toolbar popover) — a
/// Settings row that doesn't change anything would be worse than no row at all.
struct SettingsView: View {
    @EnvironmentObject private var languageManager: LanguageManager
    @AppStorage("orifoldAppAppearanceMode") private var persistedAppAppearanceMode = AppAppearanceMode.system.rawValue

    private var appearanceModeBinding: Binding<AppAppearanceMode> {
        Binding(
            get: { AppAppearanceMode(rawValue: persistedAppAppearanceMode) ?? .system },
            set: { persistedAppAppearanceMode = $0.rawValue }
        )
    }

    var body: some View {
        Form {
            Picker("settings.language.label", selection: $languageManager.language) {
                ForEach(SupportedLanguage.allCases) { language in
                    Text(language.nativeName).tag(language)
                }
            }

            Picker("settings.appearance.label", selection: appearanceModeBinding) {
                ForEach(AppAppearanceMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.systemImage).tag(mode)
                }
            }
        }
        .padding(.dsXL)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }
}
