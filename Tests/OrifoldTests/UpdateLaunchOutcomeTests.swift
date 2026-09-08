import XCTest
@testable import Orifold

@MainActor
final class UpdateLaunchOutcomeTests: XCTestCase {
    private func attempt(from: String, to: String) -> InstallAttempt {
        InstallAttempt(fromVersion: from, toVersion: to, dmgPath: "/x.dmg",
                       dmgSHA256: String(repeating: "a", count: 64), startedAt: Date(timeIntervalSince1970: 0))
    }

    // MARK: - Outcome

    func testNoAttemptIsNone() {
        XCTAssertEqual(UpdateLaunchCoordinator.evaluateInstallOutcome(attempt: nil, currentVersion: "0.8.7"), .none)
    }

    func testRunningTheTargetVersionIsSuccess() {
        let a = attempt(from: "0.8.6", to: "0.8.7")
        XCTAssertEqual(UpdateLaunchCoordinator.evaluateInstallOutcome(attempt: a, currentVersion: "0.8.7"), .succeeded)
    }

    func testStillOnOldVersionIsFailure() {
        let a = attempt(from: "0.8.6", to: "0.8.7")
        XCTAssertEqual(UpdateLaunchCoordinator.evaluateInstallOutcome(attempt: a, currentVersion: "0.8.6"), .failed)
    }

    func testRunningNeitherVersionIsFailure() {
        // Somehow on an unrelated version → we did not reach the target, so: failed.
        let a = attempt(from: "0.8.6", to: "0.8.7")
        XCTAssertEqual(UpdateLaunchCoordinator.evaluateInstallOutcome(attempt: a, currentVersion: "0.5.0"), .failed)
    }

    func testEquivalentMarketingVersionsSucceedAndMatchHealthyHistory() throws {
        let offered = UpdateVersion(string: "v0.11.0")!.description
        let marker = attempt(from: "0.10", to: offered)
        XCTAssertEqual(UpdateLaunchCoordinator.evaluateInstallOutcome(attempt: marker, currentVersion: "0.11.0"), .succeeded)
        XCTAssertTrue(UpdateLaunchCoordinator.versionsMatch(offered, "0.11.0"), "the healthy-history gate uses the same identity")
        XCTAssertTrue(UpdateLaunchCoordinator.versionsMatch("release-v1.0.0+42", "1"))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("orifold-healthy-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let history = UpdateHistoryStore(directory: directory)
        history.record(UpdateHistoryRecord(fromVersion: "0.10", fromBuild: "1", toVersion: offered, toBuild: "2", installedAt: Date()))
        let verifiedAt = Date(timeIntervalSince1970: 100)
        UpdateLaunchCoordinator.confirmHealthyInstall(in: history, currentVersion: "0.11.0", at: verifiedAt)
        let reopened = UpdateHistoryStore(directory: directory)
        XCTAssertEqual(reopened.latest?.launchVerified, true)
        XCTAssertEqual(reopened.latest?.verifiedAt, verifiedAt)
    }

    func testMalformedVersionsCannotSucceedOrMatchHealthyHistory() {
        for invalid in ["", "latest", "v", "0..11", "0.11broken", "0.11.", "0.99999999999999999999999999"] {
            let marker = attempt(from: "0.10", to: invalid)
            XCTAssertEqual(UpdateLaunchCoordinator.evaluateInstallOutcome(attempt: marker, currentVersion: invalid), .failed)
            XCTAssertFalse(UpdateLaunchCoordinator.versionsMatch(invalid, invalid))
            XCTAssertFalse(UpdateLaunchCoordinator.versionsMatch("0.11", invalid))
        }
        XCTAssertFalse(UpdateLaunchCoordinator.versionsMatch("0.11", "0.12.0"))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("orifold-unhealthy-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let history = UpdateHistoryStore(directory: directory)
        history.record(UpdateHistoryRecord(fromVersion: "0.10", fromBuild: "1", toVersion: "latest", toBuild: "2", installedAt: Date()))
        UpdateLaunchCoordinator.confirmHealthyInstall(in: history, currentVersion: "latest")
        XCTAssertEqual(UpdateHistoryStore(directory: directory).latest?.launchVerified, false)
    }

    // MARK: - Reopen URL resolution

    func testResolvesExistingPathWhenNoBookmark() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("orifold-reopen-\(UUID().uuidString).pdf")
        try Data("x".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        let doc = ReopenDocument(path: file.path, bookmarkData: nil, pageIndex: 2, displayName: "x")
        XCTAssertEqual(UpdateLaunchCoordinator.resolveReopenURL(doc)?.path, file.path)
    }

    func testDeadBookmarkAndMissingFileResolvesNil() {
        // Garbage bookmark can't resolve; missing path can't back it up → skip (nil), never throw.
        let doc = ReopenDocument(path: "/nope/gone-\(UUID().uuidString).pdf",
                                 bookmarkData: Data([0xDE, 0xAD, 0xBE, 0xEF]), pageIndex: nil, displayName: "gone")
        XCTAssertNil(UpdateLaunchCoordinator.resolveReopenURL(doc))
    }
}
