import XCTest
@testable import Orifold

final class LaunchSentinelTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("orifold-sentinel-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func sentinel(version: String = "0.9.0") -> LaunchSentinel {
        LaunchSentinel(directory: directory, version: version, build: "1", now: { Date(timeIntervalSince1970: 0) })
    }

    func testFirstLaunchIsFreshWithZeroCount() {
        let assessment = sentinel().beginLaunch()
        XCTAssertTrue(assessment.versionChangedOrFresh)
        XCTAssertEqual(assessment.consecutiveUncleanCount, 0)
        XCTAssertFalse(assessment.isCrashLooping)
    }

    func testCleanExitResetsTheStreak() {
        let first = sentinel()
        first.beginLaunch()
        first.markCleanExit()

        let second = sentinel()
        let assessment = second.beginLaunch()
        XCTAssertFalse(assessment.previousExitWasUnclean)
        XCTAssertEqual(assessment.consecutiveUncleanCount, 0)
    }

    func testConsecutiveUncleanLaunchesAccumulateToCrashLoop() {
        // Launch 1: start, never mark clean (simulated crash).
        sentinel().beginLaunch()
        // Launch 2: sees the unclean launch 1 → count 1.
        let a2 = sentinel().beginLaunch()
        XCTAssertEqual(a2.consecutiveUncleanCount, 1)
        XCTAssertFalse(a2.isCrashLooping)
        // Launch 3: sees unclean launch 2 → count 2 → crash loop.
        let a3 = sentinel().beginLaunch()
        XCTAssertEqual(a3.consecutiveUncleanCount, 2)
        XCTAssertTrue(a3.isCrashLooping)
    }

    func testVersionChangeResetsTheStreak() {
        sentinel(version: "0.9.0").beginLaunch()
        sentinel(version: "0.9.0").beginLaunch() // count 1 for 0.9.0
        // An update/rollback to a different version starts fresh.
        let assessment = sentinel(version: "1.0.0").beginLaunch()
        XCTAssertTrue(assessment.versionChangedOrFresh)
        XCTAssertEqual(assessment.consecutiveUncleanCount, 0)
    }

    func testMarkHealthyPreventsPriorCrashesFromTriggeringRollback() {
        // Two unclean launches would normally reach the crash-loop threshold on the third.
        sentinel().beginLaunch()    // launch 1: count 0
        let running = sentinel()
        running.beginLaunch()       // launch 2: count 1
        running.markHealthy()       // verified good → accumulator reset to 0

        // A subsequent crash now counts as the *first* unclean exit since verification,
        // which stays below the threshold — so a healthy build that crashes once doesn't
        // get offered a rollback.
        let next = sentinel().beginLaunch()
        XCTAssertEqual(next.consecutiveUncleanCount, 1)
        XCTAssertFalse(next.isCrashLooping, "A verified-healthy build crashing once must not trip the crash-loop rollback offer")
    }

    func testPureCounterLogic() {
        XCTAssertEqual(LaunchSentinel.nextUncleanCount(previous: nil, currentVersion: "0.9.0"), 0)
        let unclean = LaunchSentinel.State(version: "0.9.0", build: "1", launchStartedAt: Date(timeIntervalSince1970: 0), cleanExit: false, consecutiveUncleanCount: 3)
        XCTAssertEqual(LaunchSentinel.nextUncleanCount(previous: unclean, currentVersion: "0.9.0"), 4)
        XCTAssertEqual(LaunchSentinel.nextUncleanCount(previous: unclean, currentVersion: "1.0.0"), 0)
        let clean = LaunchSentinel.State(version: "0.9.0", build: "1", launchStartedAt: Date(timeIntervalSince1970: 0), cleanExit: true, consecutiveUncleanCount: 3)
        XCTAssertEqual(LaunchSentinel.nextUncleanCount(previous: clean, currentVersion: "0.9.0"), 0)
    }
}
