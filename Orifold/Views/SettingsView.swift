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

        HStack(spacing: .dsSM) {
            Button(L10n.string("settings.updates.checkNow.button", locale: locale)) {
                Task { await updateController.checkForUpdates(userInitiated: true) }
            }
            .disabled(updateController.phase.isBusy)

            updateStatusView
        }
    }

    @ViewBuilder
    private var updateStatusView: some View {
        switch updateController.phase {
        case .checking:
            Text(L10n.string("settings.updates.status.checking", locale: locale))
                .foregroundStyle(.secondary)
        case .upToDate:
            Text(L10n.format("settings.updates.status.upToDate", updateController.currentVersionString, locale: locale))
                .foregroundStyle(.secondary)
        case let .updateAvailable(update):
            HStack(spacing: .dsXS) {
                Text(L10n.format("settings.updates.status.available", update.version, locale: locale))
                Button(L10n.string("update.action.viewRelease", locale: locale)) {
                    updateController.openDownloadPage()
                }
                .buttonStyle(.link)
            }
        case .failed:
            Text(L10n.string("settings.updates.status.failed", locale: locale))
                .foregroundStyle(.secondary)
        case .idle, .downloading, .readyToInstall:
            EmptyView()
        }
    }
}
