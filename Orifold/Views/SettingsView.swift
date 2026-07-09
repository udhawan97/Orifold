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

        // Check button and status are stacked vertically, and the status text is allowed
        // to wrap, so a long "update available" line lays out on its own row(s) within the
        // fixed-width Settings window instead of bleeding past its right edge.
        VStack(alignment: .leading, spacing: .dsSM) {
            HStack(spacing: .dsSM) {
                Button(L10n.string("settings.updates.checkNow.button", locale: locale)) {
                    Task { await updateController.checkForUpdates(userInitiated: true) }
                }
                .disabled(updateController.phase.isBusy)

                // Indeterminate spinner only for the check (downloading shows its own
                // determinate bar). Reduce Motion drops it and relies on the disabled
                // button + "Checking…" text to convey progress.
                if case .checking = updateController.phase, !reduceMotion {
                    ProgressView().controlSize(.small)
                }
            }

            updateStatusView
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: updateController.phase)
    }

    @ViewBuilder
    private var updateStatusView: some View {
        switch updateController.phase {
        case .checking:
            statusText(L10n.string("settings.updates.status.checking", locale: locale))
        case .upToDate:
            statusText(L10n.format("settings.updates.status.upToDate", updateController.currentVersionString, locale: locale))
        case let .updateAvailable(update):
            VStack(alignment: .leading, spacing: .dsXS) {
                Text(L10n.format("settings.updates.status.available", update.version, locale: locale))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: .dsMD) {
                    if update.dmgDownloadURL != nil {
                        Button(L10n.string("settings.updates.action.download", locale: locale)) {
                            updateController.beginDownload()
                        }
                    }
                    Button(L10n.string("settings.updates.action.releaseNotes", locale: locale)) {
                        updateController.openReleaseNotes()
                    }
                    .buttonStyle(.link)
                    Button(L10n.string("update.action.openDownloadPage", locale: locale)) {
                        updateController.openDownloadPage()
                    }
                    .buttonStyle(.link)
                }
            }
        case let .downloading(update, fraction):
            VStack(alignment: .leading, spacing: .dsXS) {
                statusText(L10n.format("settings.updates.status.downloading", update.version, locale: locale))
                HStack(spacing: .dsMD) {
                    ProgressView(value: fraction)
                        .frame(maxWidth: .infinity)
                    Button(L10n.string("update.action.cancel", locale: locale)) {
                        updateController.cancelDownload()
                    }
                    .buttonStyle(.link)
                }
            }
        case let .installing(update):
            statusText(L10n.format("settings.updates.status.installing", update.version, locale: locale))
        case let .readyToInstall(update):
            VStack(alignment: .leading, spacing: .dsXS) {
                Text(L10n.format("settings.updates.status.readyToInstall", update.version, locale: locale))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: .dsMD) {
                    Button(L10n.string("settings.updates.action.install", locale: locale)) {
                        attemptInstall()
                    }
                    Button(L10n.string("update.action.later", locale: locale)) {
                        updateController.installLater()
                    }
                    .buttonStyle(.link)
                }
            }
        case let .failed(failure):
            statusText(failedMessage(for: failure))
        case .idle:
            EmptyView()
        }
    }

    /// Secondary status line that wraps instead of overflowing the fixed-width window.
    private func statusText(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func failedMessage(for failure: UpdateFailure) -> String {
        switch failure.kind {
        case .download, .verification:
            return L10n.string("settings.updates.status.downloadFailed", locale: locale)
        case .network, .parsing, .install:
            return L10n.string("settings.updates.status.failed", locale: locale)
        }
    }

    /// Install hand-off: never proceed while a document has unsaved changes. When clear, the
    /// app records what's open, hands the verified DMG to the unsandboxed updater, quits, and
    /// the updater swaps the bundle and relaunches the new version — which reopens the docs.
    private func attemptInstall() {
        let blocking = updateController.documentsBlockingInstall()
        guard blocking.isEmpty else { presentUnsavedWorkAlert(blocking); return }
        let reopen = UpdateReopenGatherer.currentDocuments()
        Task { await updateController.installAndRelaunch(reopenDocuments: reopen) }
    }

    private func presentUnsavedWorkAlert(_ documents: [UpdateInstallPreflight.DocumentState]) {
        let names = documents.map(\.displayName).joined(separator: ", ")
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.string("update.install.unsavedTitle", locale: locale)
        alert.informativeText = L10n.format("update.install.unsavedMessage", names, locale: locale)
        alert.addButton(withTitle: L10n.string("common.ok", locale: locale))
        alert.runModal()
    }
}
