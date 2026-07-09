import Foundation
import Observation
import AppKit

/// The single object the update UI observes. It owns the `UpdatePhase`, the (opt-in)
/// automatic-check preference, and the rollback availability, and delegates the actual
/// "is there something newer?" question to an injected `UpdateTransport` — so it knows
/// nothing about GitHub or Sparkle and can be driven by a mock in tests.
///
/// Consent-first by construction: automatic checks default OFF, install is never initiated
/// here (the check-only transport can't install), and a manual "Check for Updates…" is
/// always available. When the Sparkle transport lands, download/install methods attach to
/// this same object behind explicit user consent.
@MainActor
@Observable
final class UpdateController {
    static let shared = UpdateController()

    /// How long to wait between automatic checks once the user has opted in.
    static let automaticCheckInterval: TimeInterval = 60 * 60 * 24

    private(set) var phase: UpdatePhase = .idle

    /// Opt-in automatic checks. Default OFF — the user's first exposure is the manual
    /// menu item; turning this on in Settings is the consent moment.
    var automaticChecksEnabled: Bool {
        didSet { defaults.set(automaticChecksEnabled, forKey: Keys.automaticChecks) }
    }

    private(set) var lastCheckAt: Date? {
        didSet { defaults.set(lastCheckAt, forKey: Keys.lastCheckAt) }
    }

    /// A version the user chose to skip; not offered again automatically until a newer
    /// one appears. A *manual* check still surfaces it.
    private(set) var skippedVersion: String? {
        didSet { defaults.set(skippedVersion, forKey: Keys.skippedVersion) }
    }

    /// Present when a previous-version archive exists to restore. Loaded at init and after
    /// each install; drives whether "Restore Previous Version…" is enabled.
    private(set) var rollbackManifest: RollbackManifest?

    /// Set by the launch coordinator when a prior install attempt did not end up running the
    /// target version. Surfaced once so the user can retry or reveal the download.
    private(set) var pendingInstallFailure = false

    /// Reports (from the launch coordinator) that the last install attempt failed.
    func notePendingInstallFailure() { pendingInstallFailure = true }

    /// Dismisses the post-install failure notice once the user has seen it.
    func dismissInstallFailure() { pendingInstallFailure = false }

    /// The verified, downloaded DMG awaiting the install hand-off. Set when a download
    /// completes and its checksum verifies; consumed by `revealDownloadedUpdateForInstall`.
    private(set) var downloadedUpdateURL: URL?

    /// The in-flight download, retained so the user can cancel it. Cancelling this Task
    /// cancels the underlying transfer (see `UpdateDownloader.streamToFile`). Readable (not
    /// settable) outside the type so tests can await it settling.
    private(set) var downloadTask: Task<Void, Never>?

    private let transport: UpdateTransport
    private let downloader: UpdateDownloading
    private let defaults: UserDefaults
    private let currentVersion: UpdateVersion
    private let currentBuild: String
    private let archiver: RollbackArchiver
    private let history: UpdateHistoryStore
    private let markers: UpdateInstallMarkerStore
    private let handOff: UpdateInstallHandOff
    private let bundleURL: URL
    private let processID: Int32
    private let now: () -> Date

    init(
        transport: UpdateTransport = GitHubReleaseTransport(),
        downloader: UpdateDownloading = UpdateDownloader(),
        defaults: UserDefaults = .standard,
        currentVersion: UpdateVersion = .current(),
        currentBuild: String = (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "0",
        archiver: RollbackArchiver = RollbackArchiver(),
        history: UpdateHistoryStore = UpdateHistoryStore(),
        markers: UpdateInstallMarkerStore = UpdateInstallMarkerStore(),
        handOff: UpdateInstallHandOff? = nil,
        bundleURL: URL = Bundle.main.bundleURL,
        processID: Int32 = ProcessInfo.processInfo.processIdentifier,
        now: @escaping () -> Date = Date.init
    ) {
        self.transport = transport
        self.downloader = downloader
        self.defaults = defaults
        self.currentVersion = currentVersion
        self.currentBuild = currentBuild
        self.archiver = archiver
        self.history = history
        self.markers = markers
        self.handOff = handOff ?? SystemUpdateInstallHandOff()
        self.bundleURL = bundleURL
        self.processID = processID
        self.now = now
        automaticChecksEnabled = defaults.bool(forKey: Keys.automaticChecks)
        lastCheckAt = defaults.object(forKey: Keys.lastCheckAt) as? Date
        skippedVersion = defaults.string(forKey: Keys.skippedVersion)
        rollbackManifest = archiver.loadManifest()
    }

    var currentVersionString: String { currentVersion.description }

    /// True when an update is available and not the one the user skipped.
    var hasActionableUpdate: Bool {
        guard let update = phase.availableUpdate else { return false }
        return update.version != skippedVersion
    }

    var canRestorePreviousVersion: Bool { rollbackManifest != nil }

    /// Runs a check. `userInitiated` checks always surface their result (including a
    /// previously-skipped version and the "you're up to date" confirmation); background
    /// checks stay quiet unless there's a fresh, non-skipped update.
    func checkForUpdates(userInitiated: Bool) async {
        if phase.isBusy { return }
        phase = .checking
        do {
            let outcome = try await transport.checkForUpdate(currentVersion: currentVersion)
            lastCheckAt = now()
            phase = Self.resolvePhase(for: outcome, userInitiated: userInitiated, skippedVersion: skippedVersion)
        } catch {
            lastCheckAt = now()
            phase = userInitiated ? .failed(Self.failure(from: error)) : .idle
        }
    }

    /// Called at launch: fires a background check only if the user opted in and the
    /// interval has elapsed.
    func maybeRunAutomaticCheck() async {
        guard automaticChecksEnabled, shouldAutomaticallyCheck(at: now()) else { return }
        await checkForUpdates(userInitiated: false)
    }

    func shouldAutomaticallyCheck(at date: Date) -> Bool {
        guard let last = lastCheckAt else { return true }
        return date.timeIntervalSince(last) >= Self.automaticCheckInterval
    }

    /// UI entry point: starts the download as a cancellable Task the user can stop.
    func beginDownload() {
        guard case .updateAvailable = phase else { return }
        downloadTask?.cancel()
        downloadTask = Task { [weak self] in await self?.downloadUpdate() }
    }

    /// Cancels an in-flight download and returns to the update-available offer, keeping any
    /// already-verified prior download for later.
    func cancelDownload() {
        guard case .downloading = phase else { return }
        downloadTask?.cancel()
        downloadTask = nil
    }

    /// Downloads the available update's verified DMG, driving the `.downloading` progress
    /// phase and ending at `.readyToInstall` (or `.failed`, or back to `.updateAvailable` on
    /// cancel). No bundle is touched — this only produces a verified local artifact.
    /// Awaitable directly (tests) or wrapped by `beginDownload()` (UI, cancellable).
    func downloadUpdate() async {
        guard case let .updateAvailable(update) = phase else { return }

        // If this exact version was already downloaded and verified in a prior attempt
        // (e.g. the user picked "Later" then came back), skip the network entirely and go
        // straight to the install offer instead of re-fetching the same DMG.
        if let existing = downloadedUpdateURL,
           existing.lastPathComponent == "Orifold-\(update.version).dmg",
           FileManager.default.fileExists(atPath: existing.path) {
            phase = .readyToInstall(update)
            return
        }

        phase = .downloading(update, fractionCompleted: 0)
        do {
            let url = try await downloader.download(update) { [weak self] fraction in
                // The downloader reports progress off the main actor; hop back to update the
                // observable phase. Guard on the *same version* still downloading so a
                // straggler tick from a superseded download can't clobber a newer one.
                Task { @MainActor in
                    guard let self, case let .downloading(current, _) = self.phase, current == update else { return }
                    self.phase = .downloading(update, fractionCompleted: fraction)
                }
            }
            try Task.checkCancellation()   // a cancel that landed just as bytes finished
            downloadedUpdateURL = url
            phase = .readyToInstall(update)
        } catch is CancellationError {
            phase = .updateAvailable(update)
        } catch let urlError as URLError where urlError.code == .cancelled {
            phase = .updateAvailable(update)
        } catch {
            phase = .failed(Self.downloadFailure(from: error))
        }
    }

    /// Open documents with unsaved changes that must be saved or closed before an install
    /// proceeds. Empty when it's safe to install.
    func documentsBlockingInstall() -> [UpdateInstallPreflight.DocumentState] {
        UpdateInstallPreflight.blockingDocuments(UpdateInstallPreflight.openDocumentsSnapshot())
    }

    /// Hands the verified download to the OS installer UI (opens the DMG's
    /// drag-to-Applications window). The caller must have cleared unsaved work first — a
    /// sandboxed app can't swap its own bundle, so the user completes the install in Finder.
    @discardableResult
    func revealDownloadedUpdateForInstall() -> Bool {
        guard let url = downloadedUpdateURL, FileManager.default.fileExists(atPath: url.path) else {
            return false
        }
        NSWorkspace.shared.open(url)
        return true
    }

    /// Orchestrates the real install: preserve on-screen state, archive the current bundle
    /// for rollback, record the attempt, then hand the verified DMG to the unsandboxed
    /// updater script and quit so it can swap the bundle and relaunch the new version.
    ///
    /// The caller must have cleared unsaved work first (`documentsBlockingInstall`) and
    /// supplies the documents to reopen. Returns false (staying put) if there's nothing
    /// verified to install or the updater couldn't be launched.
    @discardableResult
    func installAndRelaunch(reopenDocuments: [ReopenDocument]) async -> Bool {
        guard case let .readyToInstall(update) = phase else { return false }
        guard documentsBlockingInstall().isEmpty else { return false }
        guard let dmgURL = downloadedUpdateURL, FileManager.default.fileExists(atPath: dmgURL.path) else { return false }

        phase = .installing(update)

        // Preserve what's on screen so the relaunched app can reopen it (consumed once).
        let version = currentVersion.description
        let build = currentBuild
        try? markers.writeReopenManifest(UpdateReopenManifest(
            fromVersion: version, toVersion: update.version, savedAt: now(), documents: reopenDocuments))

        // Best-effort, off the main actor: digest the DMG and archive the current bundle for
        // rollback. Neither blocks the install if it fails — the script re-verifies and keeps
        // its own renamed backup of the old bundle.
        let dmgPath = dmgURL.path
        let bundleURL = self.bundleURL
        let archiver = self.archiver

        guard let digest = await Task.detached(operation: { try? RollbackArchiver.sha256(of: URL(fileURLWithPath: dmgPath)) }).value else {
            markers.clearReopenManifest()
            phase = .failed(UpdateFailure(kind: .verification, detail: "Could not hash the downloaded update."))
            return false
        }

        let rollbackZipPath: String? = await Task.detached {
            (try? archiver.archive(bundleURL: bundleURL, version: version, build: build))
                .flatMap { archiver.archiveURL(for: $0)?.path }
        }.value
        rollbackManifest = archiver.loadManifest()

        // Record the attempt + history so the next launch can judge success vs. failure.
        try? markers.writeAttempt(InstallAttempt(
            fromVersion: version, toVersion: update.version, dmgPath: dmgPath, dmgSHA256: digest, startedAt: now()))
        history.record(UpdateHistoryRecord(
            fromVersion: version, fromBuild: build, toVersion: update.version, toBuild: "",
            installedAt: now(), launchVerified: false))

        // Hand off + quit. If Terminal won't open, fall back to a failure the UI can retry
        // or resolve by revealing the DMG manually.
        let inputs = UpdaterScriptGenerator.Inputs(
            appPID: processID, appBundlePath: bundleURL.path, dmgPath: dmgPath, dmgSHA256: digest,
            newVersion: update.version, rollbackZipPath: rollbackZipPath)
        guard handOff.launchUpdater(inputs) else {
            markers.clearAttempt()
            phase = .failed(UpdateFailure(kind: .install, detail: "Could not start the updater."))
            return false
        }

        handOff.terminateForInstall()
        return true
    }

    /// Postpones an install that's ready, keeping the verified download for later.
    func installLater() {
        if case .readyToInstall = phase { phase = .idle }
    }

    /// Dismisses the current available update until a newer version appears.
    func skipCurrentUpdate() {
        if let update = phase.availableUpdate {
            skippedVersion = update.version
        }
        phase = .idle
    }

    /// Clears a transient result surface (used by "Remind Me Later" and after the
    /// up-to-date confirmation is dismissed).
    func dismissTransientState() {
        switch phase {
        case .upToDate, .failed, .updateAvailable:
            phase = .idle
        case .idle, .checking, .downloading, .readyToInstall, .installing:
            break
        }
    }

    func openReleaseNotes() {
        guard let url = phase.availableUpdate?.releaseNotesURL else { return }
        NSWorkspace.shared.open(url)
    }

    func openDownloadPage() {
        guard let url = phase.availableUpdate?.downloadPageURL
            ?? URL(string: "https://github.com/\(GitHubReleaseTransport.repository)/releases/latest") else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Pure logic (unit-tested)

    static func resolvePhase(for outcome: UpdateCheckOutcome, userInitiated: Bool, skippedVersion: String?) -> UpdatePhase {
        switch outcome {
        case .upToDate:
            return userInitiated ? .upToDate : .idle
        case let .available(update):
            if !userInitiated, update.version == skippedVersion {
                return .idle
            }
            return .updateAvailable(update)
        }
    }

    static func failure(from error: Error) -> UpdateFailure {
        switch error {
        case UpdateTransportError.decoding, UpdateTransportError.unparseableTag:
            return UpdateFailure(kind: .parsing, detail: String(describing: error))
        case UpdateTransportError.httpStatus(let code):
            return UpdateFailure(kind: .network, detail: "HTTP \(code)")
        default:
            return UpdateFailure(kind: .network, detail: String(describing: error))
        }
    }

    static func downloadFailure(from error: Error) -> UpdateFailure {
        switch error {
        case UpdateDownloader.DownloadError.checksumMismatch, UpdateDownloader.DownloadError.checksumUnavailable:
            // A failed integrity check is a verification failure, surfaced distinctly so the
            // UI can reassure the user their current version is untouched.
            return UpdateFailure(kind: .verification, detail: String(describing: error))
        default:
            return UpdateFailure(kind: .download, detail: String(describing: error))
        }
    }

    private enum Keys {
        static let automaticChecks = "orifoldAutomaticUpdateChecks"
        static let lastCheckAt = "orifoldUpdateLastCheckAt"
        static let skippedVersion = "orifoldUpdateSkippedVersion"
    }
}
