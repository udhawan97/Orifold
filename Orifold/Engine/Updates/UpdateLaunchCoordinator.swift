import Foundation
import AppKit

/// Ties the update subsystem into the app lifecycle: it stamps the launch sentinel,
/// verifies the build healthy after a crash-free grace period, kicks the (opt-in)
/// automatic check, and records a clean exit on quit.
///
/// It deliberately does *not* act on a detected crash loop yet — surfacing a rollback
/// offer only makes sense once restore is wired (a previous-version archive to restore
/// to, plus the installer `--restore` path). Until then it detects and remembers, so the
/// offer can be added without re-plumbing launch.
@MainActor
final class UpdateLaunchCoordinator {
    static let shared = UpdateLaunchCoordinator()

    /// A build that starts cleanly and survives this long without crashing is treated as
    /// verified-healthy, resetting the crash-loop accumulator.
    static let healthyGraceInterval: TimeInterval = 30

    private let sentinel: LaunchSentinel
    private(set) var lastAssessment: LaunchSentinel.Assessment?
    private var healthyTask: Task<Void, Never>?

    private init() {
        let bundle = Bundle.main
        let version = (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0"
        let build = (bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "0"
        sentinel = LaunchSentinel(version: version, build: build)
    }

    func applicationDidFinishLaunching() {
        lastAssessment = sentinel.beginLaunch()

        healthyTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.healthyGraceInterval * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.sentinel.markHealthy()
        }

        Task { await UpdateController.shared.maybeRunAutomaticCheck() }
    }

    func applicationWillTerminate() {
        healthyTask?.cancel()
        sentinel.markCleanExit()
    }
}
