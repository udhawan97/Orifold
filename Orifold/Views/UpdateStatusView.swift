import SwiftUI
import AppKit

/// The single source of truth for how an update's state is shown and acted on. Used by both
/// the Settings "Updates" section and the Software Update window, so the two surfaces can't
/// drift. It renders `UpdateController.phase` (plus a post-install failure notice) and owns
/// the phase-specific actions, including the unsaved-work guard before an install.
struct UpdateStatusView: View {
    @Bindable var controller: UpdateController
    var locale: Locale
    var reduceMotion: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: .dsSM) {
            if controller.pendingInstallFailure {
                installIncompleteNotice
            }
            phaseContent
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: controller.phase)
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch controller.phase {
        case .idle:
            EmptyView()

        case .checking:
            HStack(spacing: .dsSM) {
                statusText(L10n.string("settings.updates.status.checking", locale: locale))
                if !reduceMotion { ProgressView().controlSize(.small) }
            }

        case .upToDate:
            statusText(L10n.format("settings.updates.status.upToDate", controller.currentVersionString, locale: locale))

        case let .updateAvailable(update):
            VStack(alignment: .leading, spacing: .dsXS) {
                Text(L10n.format("settings.updates.status.available", update.version, locale: locale))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: .dsMD) {
                    if update.dmgDownloadURL != nil {
                        Button(L10n.string("settings.updates.action.download", locale: locale)) {
                            controller.beginDownload()
                        }
                    }
                    Button(L10n.string("settings.updates.action.releaseNotes", locale: locale)) {
                        controller.openReleaseNotes()
                    }
                    .buttonStyle(.link)
                    Button(L10n.string("update.action.openDownloadPage", locale: locale)) {
                        controller.openDownloadPage()
                    }
                    .buttonStyle(.link)
                }
            }

        case let .downloading(update, fraction):
            VStack(alignment: .leading, spacing: .dsXS) {
                statusText(L10n.format("settings.updates.status.downloading", update.version, locale: locale))
                HStack(spacing: .dsMD) {
                    ProgressView(value: fraction).frame(maxWidth: .infinity)
                    Button(L10n.string("update.action.cancel", locale: locale)) { controller.cancelDownload() }
                        .buttonStyle(.link)
                }
            }

        case let .installing(update):
            HStack(spacing: .dsSM) {
                statusText(L10n.format("settings.updates.status.installing", update.version, locale: locale))
                if !reduceMotion { ProgressView().controlSize(.small) }
            }

        case let .readyToInstall(update):
            VStack(alignment: .leading, spacing: .dsXS) {
                Text(L10n.format("settings.updates.status.readyToInstall", update.version, locale: locale))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: .dsMD) {
                    Button(L10n.string("settings.updates.action.install", locale: locale)) { attemptInstall() }
                    Button(L10n.string("update.action.later", locale: locale)) { controller.installLater() }
                        .buttonStyle(.link)
                }
            }

        case let .failed(failure):
            VStack(alignment: .leading, spacing: .dsXS) {
                statusText(failedMessage(for: failure))
                HStack(spacing: .dsMD) {
                    Button(L10n.string("update.action.tryAgain", locale: locale)) {
                        Task { await controller.checkForUpdates(userInitiated: true) }
                    }
                    Button(L10n.string("update.action.openDownloadPage", locale: locale)) {
                        controller.openDownloadPage()
                    }
                    .buttonStyle(.link)
                }
            }
        }
    }

    private var installIncompleteNotice: some View {
        VStack(alignment: .leading, spacing: .dsXS) {
            statusText(L10n.string("settings.updates.status.installIncomplete", locale: locale))
            Button(L10n.string("update.action.tryAgain", locale: locale)) {
                controller.dismissInstallFailure()
                Task { await controller.checkForUpdates(userInitiated: true) }
            }
            .buttonStyle(.link)
        }
    }

    private func statusText(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func failedMessage(for failure: UpdateFailure) -> String {
        switch failure.kind {
        case .download, .verification:
            return L10n.string("settings.updates.status.downloadFailed", locale: locale)
        case .install:
            return L10n.string("settings.updates.status.installIncomplete", locale: locale)
        case .network, .parsing:
            return L10n.string("settings.updates.status.failed", locale: locale)
        }
    }

    /// Install hand-off: never proceed while a document has unsaved changes. When clear, the
    /// app records what's open, hands the verified DMG to the unsandboxed updater, quits, and
    /// the updater swaps the bundle and relaunches the new version — which reopens the docs.
    private func attemptInstall() {
        let blocking = controller.documentsBlockingInstall()
        guard blocking.isEmpty else { presentUnsavedWorkAlert(blocking); return }
        let reopen = UpdateReopenGatherer.currentDocuments()
        Task { await controller.installAndRelaunch(reopenDocuments: reopen) }
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
