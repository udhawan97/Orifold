import XCTest
@testable import Orifold

private struct MockTransport: UpdateTransport {
    var result: Result<UpdateCheckOutcome, Error>
    func checkForUpdate(currentVersion: UpdateVersion) async throws -> UpdateCheckOutcome {
        try result.get()
    }
}

@MainActor
final class UpdateControllerTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var rollbackDir: URL!

    override func setUpWithError() throws {
        suiteName = "orifold-update-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        rollbackDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("orifold-ctl-rollback-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: rollbackDir)
    }

    private func makeController(
        outcome: Result<UpdateCheckOutcome, Error>,
        current: String = "0.8.4"
    ) -> UpdateController {
        UpdateController(
            transport: MockTransport(result: outcome),
            defaults: defaults,
            currentVersion: UpdateVersion(string: current)!,
            archiver: RollbackArchiver(directory: rollbackDir),
            now: { Date(timeIntervalSince1970: 1_000_000) }
        )
    }

    private func update(_ version: String) -> AvailableUpdate {
        AvailableUpdate(version: version, currentVersion: "0.8.4", releaseNotesURL: nil, downloadPageURL: nil, publishedAt: nil, assetSizeBytes: nil)
    }

    // MARK: - Pure phase resolution

    func testResolvePhase() {
        // Up to date: only shown when the user asked.
        XCTAssertEqual(UpdateController.resolvePhase(for: .upToDate, userInitiated: true, skippedVersion: nil), .upToDate)
        XCTAssertEqual(UpdateController.resolvePhase(for: .upToDate, userInitiated: false, skippedVersion: nil), .idle)

        // Available: surfaced either way, unless it's the skipped one on a background check.
        XCTAssertEqual(
            UpdateController.resolvePhase(for: .available(update("0.9.0")), userInitiated: false, skippedVersion: nil),
            .updateAvailable(update("0.9.0"))
        )
        XCTAssertEqual(
            UpdateController.resolvePhase(for: .available(update("0.9.0")), userInitiated: false, skippedVersion: "0.9.0"),
            .idle
        )
        // A manual check surfaces even a skipped version.
        XCTAssertEqual(
            UpdateController.resolvePhase(for: .available(update("0.9.0")), userInitiated: true, skippedVersion: "0.9.0"),
            .updateAvailable(update("0.9.0"))
        )
    }

    // MARK: - Integration through the controller

    func testManualCheckWhenUpToDate() async {
        let controller = makeController(outcome: .success(.upToDate))
        await controller.checkForUpdates(userInitiated: true)
        XCTAssertEqual(controller.phase, .upToDate)
        XCTAssertEqual(controller.lastCheckAt, Date(timeIntervalSince1970: 1_000_000))
    }

    func testBackgroundCheckStaysQuietWhenUpToDate() async {
        let controller = makeController(outcome: .success(.upToDate))
        await controller.checkForUpdates(userInitiated: false)
        XCTAssertEqual(controller.phase, .idle)
    }

    func testManualCheckSurfacesUpdate() async {
        let controller = makeController(outcome: .success(.available(update("0.9.0"))))
        await controller.checkForUpdates(userInitiated: true)
        XCTAssertEqual(controller.phase.availableUpdate?.version, "0.9.0")
        XCTAssertTrue(controller.hasActionableUpdate)
    }

    func testFailedCheckOnlySurfacesForUserInitiated() async {
        let failing = makeController(outcome: .failure(UpdateTransportError.httpStatus(500)))
        await failing.checkForUpdates(userInitiated: true)
        if case .failed(let failure) = failing.phase {
            XCTAssertEqual(failure.kind, .network)
        } else {
            XCTFail("expected a failed phase, got \(failing.phase)")
        }

        let quiet = makeController(outcome: .failure(UpdateTransportError.httpStatus(500)))
        await quiet.checkForUpdates(userInitiated: false)
        XCTAssertEqual(quiet.phase, .idle, "A background failure must not nag the user")
    }

    func testSkipSuppressesFutureBackgroundOffersButNotManual() async {
        let controller = makeController(outcome: .success(.available(update("0.9.0"))))
        await controller.checkForUpdates(userInitiated: true)
        controller.skipCurrentUpdate()
        XCTAssertEqual(controller.skippedVersion, "0.9.0")
        XCTAssertEqual(controller.phase, .idle)

        // Background check now stays quiet for the skipped version…
        await controller.checkForUpdates(userInitiated: false)
        XCTAssertEqual(controller.phase, .idle)

        // …but a manual check still surfaces it.
        await controller.checkForUpdates(userInitiated: true)
        XCTAssertEqual(controller.phase.availableUpdate?.version, "0.9.0")
    }

    func testAutomaticCheckIsGatedByOptInAndInterval() async {
        let controller = makeController(outcome: .success(.available(update("0.9.0"))))

        // Opt-out: no check regardless of interval.
        controller.automaticChecksEnabled = false
        await controller.maybeRunAutomaticCheck()
        XCTAssertEqual(controller.phase, .idle)

        // Opt-in with no prior check → should run.
        controller.automaticChecksEnabled = true
        XCTAssertTrue(controller.shouldAutomaticallyCheck(at: Date(timeIntervalSince1970: 1_000_000)))
        await controller.maybeRunAutomaticCheck()
        XCTAssertEqual(controller.phase.availableUpdate?.version, "0.9.0")
    }

    func testIntervalGatingRespectsLastCheck() async {
        let controller = makeController(outcome: .success(.upToDate))
        controller.automaticChecksEnabled = true
        await controller.checkForUpdates(userInitiated: false) // sets lastCheckAt to the fixed clock

        // Same instant → interval not elapsed.
        XCTAssertFalse(controller.shouldAutomaticallyCheck(at: Date(timeIntervalSince1970: 1_000_000)))
        // A day later → elapsed.
        XCTAssertTrue(controller.shouldAutomaticallyCheck(at: Date(timeIntervalSince1970: 1_000_000 + UpdateController.automaticCheckInterval)))
    }

    func testRollbackAvailabilityReflectsManifest() throws {
        // No manifest → cannot restore.
        let none = makeController(outcome: .success(.upToDate))
        XCTAssertFalse(none.canRestorePreviousVersion)

        // Write a manifest, then a fresh controller sees it.
        let archiver = RollbackArchiver(directory: rollbackDir)
        try archiver.writeManifest(RollbackManifest(version: "0.8.4", build: "11", sha256: String(repeating: "a", count: 64), archivedAt: Date(timeIntervalSince1970: 0), archiveFileName: "Orifold-0.8.4.zip"))
        let restorable = makeController(outcome: .success(.upToDate))
        XCTAssertTrue(restorable.canRestorePreviousVersion)
        XCTAssertEqual(restorable.rollbackManifest?.version, "0.8.4")
    }
}
