import Foundation
import AppKit

/// The two irreversible side effects of an install, behind a protocol so the orchestration
/// in `UpdateController` can be unit-tested without opening Terminal or quitting the app.
@MainActor
protocol UpdateInstallHandOff {
    /// Writes + opens the updater `.command` (unsandboxed, via LaunchServices). Returns
    /// `false` if the OS wouldn't open it, so the caller can fall back to a manual reveal.
    func launchUpdater(_ inputs: UpdaterScriptGenerator.Inputs) -> Bool
    /// Writes + opens the restore `.command` (unsandboxed). Same failure contract as `launchUpdater`.
    func launchRestore(_ inputs: UpdaterScriptGenerator.RestoreInputs) -> Bool
    /// Quits the app so the (already-launched) updater can swap the bundle and relaunch it.
    func terminateForInstall()
}

/// Production hand-off: generate the script into the updater cache, open it in Terminal,
/// and terminate the app through the normal path (sentinel clean-exit + NSDocument review
/// as the final backstop).
@MainActor
struct SystemUpdateInstallHandOff: UpdateInstallHandOff {
    func launchUpdater(_ inputs: UpdaterScriptGenerator.Inputs) -> Bool {
        guard let team = inputs.publisherTeamIdentifier, !team.isEmpty,
              inputs.publisherBundleIdentifier == UpdatePublisherIdentity.expectedBundleIdentifier else {
            return false
        }
        var inputs = inputs
        if let archive = inputs.rollbackZipPath,
           let archiveSHA = inputs.rollbackSHA256,
           let rollbackVersion = inputs.rollbackVersion {
            let restore = UpdaterScriptGenerator.RestoreInputs(
                appPID: inputs.appPID,
                appBundlePath: inputs.appBundlePath,
                archiveZipPath: archive,
                archiveSHA256: archiveSHA,
                restoreVersion: rollbackVersion,
                publisherTeamIdentifier: inputs.publisherTeamIdentifier,
                publisherBundleIdentifier: inputs.publisherBundleIdentifier,
                // Copied beside the app for the case where the new version will not launch.
                // Nobody is quitting the app to run it, so it asks before it changes anything.
                requiresConsent: true
            )
            guard let restoreURL = try? UpdaterScriptGenerator().writeRestore(restore) else { return false }
            inputs.restoreScriptPath = restoreURL.path
        }
        guard let url = try? UpdaterScriptGenerator().write(inputs) else { return false }
        return NSWorkspace.shared.open(url)
    }

    func launchRestore(_ inputs: UpdaterScriptGenerator.RestoreInputs) -> Bool {
        guard let team = inputs.publisherTeamIdentifier, !team.isEmpty,
              inputs.publisherBundleIdentifier == UpdatePublisherIdentity.expectedBundleIdentifier else {
            return false
        }
        guard let url = try? UpdaterScriptGenerator().writeRestore(inputs) else { return false }
        return NSWorkspace.shared.open(url)
    }

    func terminateForInstall() {
        NSApp.terminate(nil)
    }
}
