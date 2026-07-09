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
