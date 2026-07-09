import Foundation
import AppKit

/// Ties the update subsystem into the app lifecycle: stamps the launch sentinel, judges the
/// outcome of any pending install, reopens the documents that were on screen before an
/// update, verifies the build healthy after a crash-free grace period, kicks the (opt-in)
/// automatic check, prunes stale artifacts, and records a clean exit on quit.
///
/// It deliberately does *not* act on a detected crash loop yet — surfacing a rollback offer
/// only makes sense once user-initiated restore is wired. Until then it detects and
/// remembers, so the offer can be added without re-plumbing launch.
@MainActor
final class UpdateLaunchCoordinator {
    static let shared = UpdateLaunchCoordinator()

    /// A build that starts cleanly and survives this long without crashing is treated as
    /// verified-healthy, resetting the crash-loop accumulator and confirming a fresh install.
    static let healthyGraceInterval: TimeInterval = 30

    /// How a pending install attempt turned out, judged by the running version.
    enum InstallOutcome: Equatable {
        case none        // no attempt was pending
        case succeeded   // running the version the attempt targeted
        case failed      // attempt was pending but we're not on the target version
    }

    private let sentinel: LaunchSentinel
    private let markers: UpdateInstallMarkerStore
    private let history: UpdateHistoryStore
    private let currentVersion: String
    private(set) var lastAssessment: LaunchSentinel.Assessment?
    private var healthyTask: Task<Void, Never>?

    private init() {
        let bundle = Bundle.main
        currentVersion = (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0"
        let build = (bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "0"
        sentinel = LaunchSentinel(version: currentVersion, build: build)
        markers = UpdateInstallMarkerStore()
        history = UpdateHistoryStore()
    }

    func applicationDidFinishLaunching() {
        lastAssessment = sentinel.beginLaunch()

        // 1. Judge any pending install by whether we're now running its target version.
        let attempt = markers.readAttempt()
        switch Self.evaluateInstallOutcome(attempt: attempt, currentVersion: currentVersion) {
        case .none:
            break
        case .succeeded:
            // The new version is running; the record is confirmed verified after the grace.
            markers.clearAttempt()
        case .failed:
            markers.clearAttempt()
            if let latest = history.latest, !latest.launchVerified, latest.rollbackReason == nil {
                history.update(id: latest.id) { $0.rollbackReason = .installFailed }
            }
            UpdateController.shared.notePendingInstallFailure()
        }

        // 2. Reopen the documents that were on screen before the update (one-shot). Runs
        //    before the delegate's 0.25 s "open untitled if empty" fallback, so restored
        //    windows suppress the empty untitled window.
        if let manifest = markers.consumeReopenManifest() {
            reopenDocuments(manifest.documents)
        }

        // 3. After a crash-free grace period, mark this build healthy and confirm a fresh
        //    install as verified (so it's no longer a rollback candidate).
        healthyTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.healthyGraceInterval * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            self.sentinel.markHealthy()
            if let latest = self.history.latest, latest.toVersion == self.currentVersion, !latest.launchVerified {
                self.history.update(id: latest.id) { $0.launchVerified = true; $0.verifiedAt = Date() }
            }
        }

        Task { await UpdateController.shared.maybeRunAutomaticCheck() }

        // 4. Housekeeping: prune stale downloaded artifacts and superseded rollback archives.
        //    Runs off the main actor and only ever touches updater-owned directories.
        Task.detached(priority: .background) {
            UpdateArtifactCleaner().clean()
        }
    }

    func applicationWillTerminate() {
        healthyTask?.cancel()
        sentinel.markCleanExit()
    }

    // MARK: - Pure decision logic (unit-tested)

    static func evaluateInstallOutcome(attempt: InstallAttempt?, currentVersion: String) -> InstallOutcome {
        guard let attempt else { return .none }
        return attempt.toVersion == currentVersion ? .succeeded : .failed
    }

    /// Resolves a document to reopen, preferring the security-scoped bookmark (survives
    /// moves) and falling back to the raw path. Returns nil for a dead bookmark whose file
    /// is also gone, so reopen silently skips it rather than erroring on first launch.
    static func resolveReopenURL(_ document: ReopenDocument) -> URL? {
        if let data = document.bookmarkData, let resolved = SecurityScopedAccess.resolve(data) {
            return resolved.url
        }
        let url = URL(fileURLWithPath: document.path)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: - Reopen

    private func reopenDocuments(_ documents: [ReopenDocument]) {
        let controller = NSDocumentController.shared
        for document in documents {
            guard let url = Self.resolveReopenURL(document) else { continue }
            // `openDocument` reads asynchronously, so the security scope must stay open until
            // its completion handler fires — mirror EmptyStateView.openRecentFile.
            let didStartScope = url.startAccessingSecurityScopedResource()
            controller.openDocument(withContentsOf: url, display: true) { _, _, _ in
                if didStartScope { url.stopAccessingSecurityScopedResource() }
            }
        }
    }
}
