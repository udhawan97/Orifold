import Foundation
import AppKit

/// The two irreversible side effects of an install, behind a protocol so the orchestration
/// in `UpdateController` can be unit-tested without opening Terminal or quitting the app.
@MainActor
protocol UpdateInstallHandOff {
    /// Writes + opens the updater `.command` (unsandboxed, via LaunchServices). Returns
    /// `false` if the OS wouldn't open it, so the caller can fall back to a manual reveal.
    func launchUpdater(_ inputs: UpdaterScriptGenerator.Inputs) -> Bool
    /// Quits the app so the (already-launched) updater can swap the bundle and relaunch it.
    func terminateForInstall()
}

/// Production hand-off: generate the script into the updater cache, open it in Terminal,
/// and terminate the app through the normal path (sentinel clean-exit + NSDocument review
/// as the final backstop).
@MainActor
struct SystemUpdateInstallHandOff: UpdateInstallHandOff {
    func launchUpdater(_ inputs: UpdaterScriptGenerator.Inputs) -> Bool {
        guard let url = try? UpdaterScriptGenerator().write(inputs) else { return false }
        return NSWorkspace.shared.open(url)
    }

    func terminateForInstall() {
        NSApp.terminate(nil)
    }
}
