import Foundation

/// Detects unclean shutdowns and crash loops by writing a small "I started" marker at
/// launch and only flipping it to "I exited cleanly" on graceful termination.
///
/// If the app is killed, crashes, or is force-quit, the marker stays `cleanExit == false`.
/// The *next* launch reads that and, when it's the same version that failed, increments a
/// consecutive-unclean counter. Once that counter crosses `crashLoopThreshold` for a
/// version that was never verified healthy, the update controller offers a rollback —
/// it never rolls back on its own. The "signal-coded exit vs benign early exit"
/// distinction the release smoke-test makes lives in the OS crash reporter, not here;
/// this sentinel only knows "did we get to mark a clean exit before dying?".
final class LaunchSentinel {
    static let crashLoopThreshold = 2

    struct State: Codable, Equatable {
        var version: String
        var build: String
        var launchStartedAt: Date
        var cleanExit: Bool
        var consecutiveUncleanCount: Int
    }

    /// What `beginLaunch()` concluded about the run that just ended.
    struct Assessment: Equatable {
        /// The previous run of *this same version* ended without marking a clean exit.
        var previousExitWasUnclean: Bool
        /// Consecutive unclean launches of the current version, this launch included in
        /// the sense that it is the count of failures observed *before* now.
        var consecutiveUncleanCount: Int
        /// No prior sentinel, or the version changed since it was written (a fresh
        /// install, update, or rollback) — the counter resets in that case.
        var versionChangedOrFresh: Bool

        /// True when the current version has failed to reach a clean exit at least
        /// `crashLoopThreshold` times in a row.
        var isCrashLooping: Bool { consecutiveUncleanCount >= LaunchSentinel.crashLoopThreshold }
    }

    private let fileURL: URL
    private let version: String
    private let build: String
    private let now: () -> Date

    init(
        directory: URL = UpdateStorePaths.supportDirectory,
        version: String,
        build: String,
        now: @escaping () -> Date = Date.init
    ) {
        fileURL = directory.appendingPathComponent("launch-sentinel.json")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.version = version
        self.build = build
        self.now = now
    }

    /// Reads the previous marker, computes the crash-loop assessment, then writes a fresh
    /// marker for the current run (`cleanExit == false`). Call once, early in launch.
    @discardableResult
    func beginLaunch() -> Assessment {
        let previous = Self.load(from: fileURL)
        let count = Self.nextUncleanCount(previous: previous, currentVersion: version)
        let assessment = Assessment(
            previousExitWasUnclean: previous.map { !$0.cleanExit && $0.version == version } ?? false,
            consecutiveUncleanCount: count,
            versionChangedOrFresh: previous.map { $0.version != version } ?? true
        )
        write(State(
            version: version,
            build: build,
            launchStartedAt: now(),
            cleanExit: false,
            consecutiveUncleanCount: count
        ))
        return assessment
    }

    /// Marks the current version as verified-healthy, resetting the unclean counter so a
    /// later, unrelated crash of a known-good build doesn't accumulate toward a rollback.
    func markHealthy() {
        guard var state = Self.load(from: fileURL) else { return }
        state.consecutiveUncleanCount = 0
        write(state)
    }

    /// Records a graceful shutdown. After this, the next launch sees a clean previous exit.
    func markCleanExit() {
        guard var state = Self.load(from: fileURL) else { return }
        state.cleanExit = true
        write(state)
    }

    /// Pure counter logic, exposed for testing: how many consecutive unclean launches the
    /// current version has had, given the previously-persisted state.
    static func nextUncleanCount(previous: State?, currentVersion: String) -> Int {
        guard let previous, previous.version == currentVersion else { return 0 }
        // A clean previous exit resets the streak; an unclean one extends it.
        return previous.cleanExit ? 0 : previous.consecutiveUncleanCount + 1
    }

    // MARK: - Persistence

    private static func load(from url: URL) -> State? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(State.self, from: data)
    }

    private func write(_ state: State) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(state) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
