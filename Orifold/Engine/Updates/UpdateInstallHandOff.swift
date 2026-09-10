import Foundation
import AppKit
import Darwin

/// The two irreversible side effects of an install, behind a protocol so the orchestration
/// in `UpdateController` can be unit-tested without opening Terminal or quitting the app.
@MainActor
protocol UpdateInstallHandOff {
    /// Writes + opens the updater `.command` (unsandboxed, via LaunchServices). Returns
    /// `false` if the OS wouldn't open it, so the caller can fall back to a manual reveal.
    func launchUpdater(_ inputs: UpdaterScriptGenerator.Inputs) -> Bool
    /// Writes + opens the restore `.command` (unsandboxed). Same failure contract as `launchUpdater`.
    func launchRestore(_ inputs: UpdaterScriptGenerator.RestoreInputs) -> Bool
    /// Requests the app's normal termination path. A successful request exits the process and
    /// never returns in production; `false` means AppKit returned without terminating (for
    /// example, the user cancelled an unsaved-document review).
    func terminateForInstall() -> Bool
    /// Revokes the one launched helper before callers expose a retryable UI state.
    func abandonLaunchedHelper()
}

/// Production hand-off: generate the script into the updater cache, open it in Terminal,
/// and terminate the app through the normal path (sentinel clean-exit + NSDocument review
/// as the final backstop).
@MainActor
final class SystemUpdateInstallHandOff: UpdateInstallHandOff {
    private let cacheDirectory: URL
    private let open: (URL) -> Bool
    private var authorizationURL: URL?

    init(
        cacheDirectory: URL = UpdateStorePaths.updaterCacheDirectory(),
        open: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) }
    ) {
        self.cacheDirectory = cacheDirectory
        self.open = open
    }

    func launchUpdater(_ inputs: UpdaterScriptGenerator.Inputs) -> Bool {
        guard let team = inputs.publisherTeamIdentifier, !team.isEmpty,
              inputs.publisherBundleIdentifier == UpdatePublisherIdentity.expectedBundleIdentifier else {
            return false
        }
        guard let authorizationURL = beginAuthorization() else { return false }
        var inputs = inputs
        inputs.authorizationPath = authorizationURL.path
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
            guard let restoreURL = try? UpdaterScriptGenerator().writeRestore(restore, to: cacheDirectory) else {
                abandonLaunchedHelper()
                return false
            }
            inputs.restoreScriptPath = restoreURL.path
        }
        guard let url = try? UpdaterScriptGenerator().write(inputs, to: cacheDirectory), open(url) else {
            abandonLaunchedHelper()
            return false
        }
        return true
    }

    func launchRestore(_ inputs: UpdaterScriptGenerator.RestoreInputs) -> Bool {
        guard let team = inputs.publisherTeamIdentifier, !team.isEmpty,
              inputs.publisherBundleIdentifier == UpdatePublisherIdentity.expectedBundleIdentifier else {
            return false
        }
        guard let authorizationURL = beginAuthorization() else { return false }
        var inputs = inputs
        inputs.authorizationPath = authorizationURL.path
        guard let url = try? UpdaterScriptGenerator().writeRestore(inputs, to: cacheDirectory), open(url) else {
            abandonLaunchedHelper()
            return false
        }
        return true
    }

    func terminateForInstall() -> Bool {
        NSApp.terminate(nil)
        // A completed termination exits the process. Reaching this line means AppKit kept the
        // app alive; fail closed so the controller can revoke the helper before allowing retry.
        return false
    }

    func abandonLaunchedHelper() {
        guard let authorizationURL else { return }
        try? FileManager.default.removeItem(at: authorizationURL)
        self.authorizationURL = nil
    }

    private func beginAuthorization() -> URL? {
        guard authorizationURL == nil else { return nil }
        let url = cacheDirectory.appendingPathComponent("handoff-\(UUID().uuidString).authorized")
        do {
            try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            let descriptor = url.withUnsafeFileSystemRepresentation { fileSystemPath -> Int32 in
                guard let fileSystemPath else { return -1 }
                return Darwin.open(
                    fileSystemPath,
                    O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW,
                    S_IRUSR | S_IWUSR
                )
            }
            guard descriptor >= 0 else { return nil }
            let token = Data("authorized\n".utf8)
            let bytesWritten = token.withUnsafeBytes { buffer -> Int in
                guard let baseAddress = buffer.baseAddress else { return 0 }
                return Darwin.write(descriptor, baseAddress, buffer.count)
            }
            let closeResult = Darwin.close(descriptor)
            guard bytesWritten == token.count, closeResult == 0 else {
                try? FileManager.default.removeItem(at: url)
                return nil
            }
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else {
                try? FileManager.default.removeItem(at: url)
                return nil
            }
            authorizationURL = url
            return url
        } catch {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
    }
}
