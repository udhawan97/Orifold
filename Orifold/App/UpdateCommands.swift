import SwiftUI
import AppKit

/// "Check for Updates…" — placed in the app menu directly under "About Orifold", the
/// canonical macOS location. A manual check always surfaces its result (unlike a quiet
/// background check), so this presents the outcome natively when it completes.
struct CheckForUpdatesCommandButton: View {
    var locale: Locale

    var body: some View {
        Button(L10n.string("appCommands.checkForUpdates.button", locale: locale)) {
            Task { @MainActor in
                let controller = UpdateController.shared
                await controller.checkForUpdates(userInitiated: true)
                UpdateAlertPresenter.present(controller.phase, controller: controller, locale: locale)
            }
        }
    }
}

/// Native presentation of a *manual* update check's result. Deliberately an `NSAlert` —
/// the standard, calm surface Mac apps use for exactly this — rather than a bespoke
/// window, so a menu-triggered check gives clear feedback even with no window open.
enum UpdateAlertPresenter {
    @MainActor
    static func present(_ phase: UpdatePhase, controller: UpdateController, locale: Locale) {
        switch phase {
        case let .updateAvailable(update):
            presentAvailable(update, controller: controller, locale: locale)
        case .upToDate:
            presentUpToDate(controller: controller, locale: locale)
            controller.dismissTransientState()
        case let .failed(failure):
            presentFailure(failure, controller: controller, locale: locale)
            controller.dismissTransientState()
        case .idle, .checking, .downloading, .readyToInstall:
            break
        }
    }

    @MainActor
    private static func presentUpToDate(controller: UpdateController, locale: Locale) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = L10n.string("update.upToDate.title", locale: locale)
        alert.informativeText = L10n.format("update.upToDate.message", controller.currentVersionString, locale: locale)
        alert.runModal()
    }

    @MainActor
    private static func presentAvailable(_ update: AvailableUpdate, controller: UpdateController, locale: Locale) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = L10n.format("update.available.title", update.version, locale: locale)
        alert.informativeText = availableBody(update, locale: locale)
        alert.addButton(withTitle: L10n.string("update.action.viewRelease", locale: locale))   // default
        alert.addButton(withTitle: L10n.string("update.action.skipVersion", locale: locale))
        alert.addButton(withTitle: L10n.string("update.action.later", locale: locale))

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            controller.openDownloadPage()
        case .alertSecondButtonReturn:
            controller.skipCurrentUpdate()
        default:
            controller.dismissTransientState()
        }
    }

    @MainActor
    private static func presentFailure(_ failure: UpdateFailure, controller: UpdateController, locale: Locale) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.string("update.failed.title", locale: locale)
        alert.informativeText = L10n.string("update.failed.message", locale: locale)
        alert.addButton(withTitle: L10n.string("update.action.openDownloadPage", locale: locale))  // default
        alert.addButton(withTitle: L10n.string("common.ok", locale: locale))
        if alert.runModal() == .alertFirstButtonReturn {
            controller.openDownloadPage()
        }
    }

    /// "You have 0.8.4 · Released July 8, 2026 · 42 MB" — omitting the parts we don't know.
    @MainActor
    private static func availableBody(_ update: AvailableUpdate, locale: Locale) -> String {
        var parts = [L10n.format("update.available.currentVersion", update.currentVersion, locale: locale)]
        if let published = update.publishedAt {
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.dateStyle = .medium
            parts.append(L10n.format("update.available.released", formatter.string(from: published), locale: locale))
        }
        if let bytes = update.assetSizeBytes {
            let size = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
            parts.append(size)
        }
        return parts.joined(separator: " · ")
    }
}
