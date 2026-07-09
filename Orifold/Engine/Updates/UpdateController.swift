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

    private let transport: UpdateTransport
    private let defaults: UserDefaults
    private let currentVersion: UpdateVersion
    private let archiver: RollbackArchiver
    private let now: () -> Date

    init(
        transport: UpdateTransport = GitHubReleaseTransport(),
        defaults: UserDefaults = .standard,
        currentVersion: UpdateVersion = .current(),
        archiver: RollbackArchiver = RollbackArchiver(),
        now: @escaping () -> Date = Date.init
    ) {
        self.transport = transport
        self.defaults = defaults
        self.currentVersion = currentVersion
        self.archiver = archiver
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
        case .idle, .checking, .downloading, .readyToInstall:
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

    private enum Keys {
        static let automaticChecks = "orifoldAutomaticUpdateChecks"
        static let lastCheckAt = "orifoldUpdateLastCheckAt"
        static let skippedVersion = "orifoldUpdateSkippedVersion"
    }
}
