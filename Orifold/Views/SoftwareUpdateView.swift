import SwiftUI
import AppKit

/// Identifies the single Software Update window scene, opened from the "Check for Updates…"
/// menu command.
enum SoftwareUpdateWindow {
    static let id = "software-update"
}

/// The menu-driven update surface: a calm, centered card showing the same `UpdateStatusView`
/// the Settings section uses, plus a "Check Now" affordance. Auto-checks on appear so opening
/// it always reflects the latest state without an extra click.
struct SoftwareUpdateView: View {
    @EnvironmentObject private var languageManager: LanguageManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var controller = UpdateController.shared

    private var locale: Locale { languageManager.effectiveLocale }

    var body: some View {
        @Bindable var controller = controller

        VStack(spacing: .dsMD) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
                .accessibilityHidden(true)

            Text(L10n.string("window.softwareUpdate.title", locale: locale))
                .font(.title2.weight(.semibold))

            UpdateStatusView(controller: controller, locale: locale, reduceMotion: reduceMotion)
                .multilineTextAlignment(.center)

            Button(L10n.string("settings.updates.checkNow.button", locale: locale)) {
                Task { await controller.checkForUpdates(userInitiated: true) }
            }
            .disabled(controller.phase.isBusy)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.dsXL)
        .frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            // Reflect the latest state on open; the check no-ops if one is already running.
            if case .idle = controller.phase {
                Task { await controller.checkForUpdates(userInitiated: true) }
            }
        }
    }
}
