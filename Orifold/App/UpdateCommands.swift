import SwiftUI

/// "Check for Updates…" — placed in the app menu directly under "About Orifold", the
/// canonical macOS location. Opens the Software Update window (which auto-checks on appear),
/// so a manual check always surfaces its result in a real, actionable surface rather than a
/// one-shot alert — the user can download and install from there.
struct CheckForUpdatesCommandButton: View {
    var locale: Locale
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(L10n.string("appCommands.checkForUpdates.button", locale: locale)) {
            openWindow(id: SoftwareUpdateWindow.id)
            Task { @MainActor in
                let controller = UpdateController.shared
                if !controller.phase.isBusy {
                    await controller.checkForUpdates(userInitiated: true)
                }
            }
        }
    }
}
