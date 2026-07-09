import SwiftUI
import AppKit

/// The app's native macOS Settings window (⌘,). Scoped to controls that already have a
/// real, working implementation elsewhere in the app — language and appearance already
/// propagate live to open documents via the existing `@AppStorage`/`onChange` wiring in
/// `ContentView`. Deliberately does not add toolbar density/label toggles, export-default
/// pickers, or Document Comfort defaults, since those preferences have no backing behavior
/// (or, for Document Comfort, already have their own dedicated toolbar popover) — a
/// Settings row that doesn't change anything would be worse than no row at all.
struct SettingsView: View {
    @EnvironmentObject private var languageManager: LanguageManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("orifoldAppAppearanceMode") private var persistedAppAppearanceMode = AppAppearanceMode.system.rawValue
    @State private var updateController = UpdateController.shared

    private var appearanceModeBinding: Binding<AppAppearanceMode> {
        Binding(
            get: { AppAppearanceMode(rawValue: persistedAppAppearanceMode) ?? .system },
            set: { persistedAppAppearanceMode = $0.rawValue }
        )
    }

    private var locale: Locale { languageManager.effectiveLocale }

    var body: some View {
        Form {
            Picker(L10n.string("settings.language.label", locale: locale), selection: $languageManager.language) {
                ForEach(SupportedLanguage.allCases) { language in
                    Text(language.nativeName).tag(language)
                }
            }

            Picker(L10n.string("settings.appearance.label", locale: locale), selection: appearanceModeBinding) {
                ForEach(AppAppearanceMode.allCases) { mode in
                    Label(mode.title(locale: locale), systemImage: mode.systemImage).tag(mode)
                }
            }

            updatesSection
        }
        .padding(.dsXL)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var updatesSection: some View {
        @Bindable var controller = updateController

        Toggle(isOn: $controller.automaticChecksEnabled) {
            Text(L10n.string("settings.updates.automatic.label", locale: locale))
        }
        .help(L10n.string("settings.updates.automatic.help", locale: locale))

        // Check button + the shared status view stacked vertically, so a long "update
        // available" line wraps onto its own row(s) within the fixed-width Settings window
        // instead of bleeding past its right edge. The status/actions are the same component
        // the Software Update window uses, so the two surfaces can't drift.
        VStack(alignment: .leading, spacing: .dsSM) {
            Button(L10n.string("settings.updates.checkNow.button", locale: locale)) {
                Task { await updateController.checkForUpdates(userInitiated: true) }
            }
            .disabled(updateController.phase.isBusy)

            UpdateStatusView(controller: updateController, locale: locale, reduceMotion: reduceMotion)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
