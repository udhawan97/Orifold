import XCTest
@testable import Orifold

private struct OrchTransport: UpdateTransport {
    var outcome: UpdateCheckOutcome
    func checkForUpdate(currentVersion: UpdateVersion) async throws -> UpdateCheckOutcome { outcome }
}

private struct OrchDownloader: UpdateDownloading {
    var result: Result<URL, Error>
    func download(_ update: AvailableUpdate, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        try result.get()
    }
}

@MainActor
private final class SpyHandOff: UpdateInstallHandOff {
    var launchedInputs: UpdaterScriptGenerator.Inputs?
    var restoreInputs: UpdaterScriptGenerator.RestoreInputs?
    var terminated = false
    var launchResult = true
    var terminationAccepted = true
    var abandonResult = true
    private(set) var helperAuthorized = false
    private(set) var updaterLaunchCount = 0
    private(set) var restoreLaunchCount = 0
    func launchUpdater(_ inputs: UpdaterScriptGenerator.Inputs) -> Bool {
        updaterLaunchCount += 1
        launchedInputs = inputs
        helperAuthorized = launchResult
        return launchResult
    }
    func launchRestore(_ inputs: UpdaterScriptGenerator.RestoreInputs) -> Bool {
        restoreLaunchCount += 1
        restoreInputs = inputs
        helperAuthorized = launchResult
        return launchResult
    }
    func terminateForInstall() -> Bool {
        terminated = true
        return terminationAccepted
    }
    func abandonLaunchedHelper() -> Bool {
        if abandonResult { helperAuthorized = false }
        return abandonResult
    }
}

@MainActor
final class UpdateInstallOrchestrationTests: XCTestCase {
    private var tmp: URL!
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUpWithError() throws {
        suite = "orifold-orch-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent(suite, isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: tmp)
    }

    private func update() -> AvailableUpdate {
        AvailableUpdate(version: "0.9.0", currentVersion: "0.8.6", releaseNotesURL: nil, downloadPageURL: nil,
                        publishedAt: nil, assetSizeBytes: nil, dmgDownloadURL: URL(string: "https://example.com/u.dmg"))
    }

    /// Builds a controller already advanced to `.readyToInstall` with a real on-disk DMG and
    /// a fake current bundle to archive.
    private func readyController(
        spy: SpyHandOff,
        history: UpdateHistoryStore,
        markers: UpdateInstallMarkerStore,
        openDocumentsSnapshot: @escaping @MainActor () -> [UpdateInstallPreflight.DocumentState] = { [] }
    ) async throws -> (UpdateController, dmg: URL, bundle: URL) {
        let dmg = tmp.appendingPathComponent("Orifold-0.9.0.dmg")
        try Data("pretend-dmg-bytes".utf8).write(to: dmg)

        let bundle = tmp.appendingPathComponent("Orifold.app")
        try FileManager.default.createDirectory(at: bundle.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        try Data("v0.8.6".utf8).write(to: bundle.appendingPathComponent("Contents/marker"))

        let c = UpdateController(
            transport: OrchTransport(outcome: .available(update())),
            downloader: OrchDownloader(result: .success(dmg)),
            defaults: defaults,
            currentVersion: UpdateVersion(string: "0.8.6")!,
            currentBuild: "12",
            archiver: RollbackArchiver(directory: tmp.appendingPathComponent("Rollback")),
            history: history,
            markers: markers,
            handOff: spy,
            bundleURL: bundle,
            publisherIdentityOverride: UpdatePublisherIdentity(
                bundleIdentifier: UpdatePublisherIdentity.expectedBundleIdentifier,
                teamIdentifier: "TEAM123456"),
            processID: 4242,
            now: { Date(timeIntervalSince1970: 100) },
            openDocumentsSnapshot: openDocumentsSnapshot
        )
        await c.checkForUpdates(userInitiated: true)
        await c.downloadUpdate()
        guard case .readyToInstall = c.phase else { throw XCTSkip("setup failed to reach readyToInstall: \(c.phase)") }
        return (c, dmg, bundle)
    }

    func testInstallAndRelaunchDrivesTheFullSequenceInOrder() async throws {
        let spy = SpyHandOff()
        let history = UpdateHistoryStore(directory: tmp)
        let markers = UpdateInstallMarkerStore(directory: tmp)
        let (c, dmg, bundle) = try await readyController(spy: spy, history: history, markers: markers)

        let ok = await c.installAndRelaunch(reopenDocuments: [
            ReopenDocument(path: "/Users/x/A.pdf", bookmarkData: nil, pageIndex: 3, displayName: "A"),
        ])

        XCTAssertTrue(ok)
        XCTAssertEqual(c.phase, .installing(update()))
        XCTAssertTrue(spy.terminated, "must quit so the updater can swap the bundle")

        // Hand-off inputs are correct and consistent with the recorded attempt.
        let inputs = try XCTUnwrap(spy.launchedInputs)
        XCTAssertEqual(inputs.appPID, 4242)
        XCTAssertEqual(inputs.newVersion, "0.9.0")
        XCTAssertEqual(inputs.appBundlePath, bundle.path)
        XCTAssertEqual(inputs.dmgPath, dmg.path)
        XCTAssertEqual(inputs.dmgSHA256.count, 64)
        XCTAssertNotNil(inputs.rollbackZipPath, "current bundle should have been archived for rollback")

        // Reopen manifest preserved the on-screen state.
        let reopen = try XCTUnwrap(markers.readReopenManifest())
        XCTAssertEqual(reopen.toVersion, "0.9.0")
        XCTAssertEqual(reopen.documents.first?.pageIndex, 3)

        // Attempt marker matches the hand-off, so the next launch can judge the outcome.
        let attempt = try XCTUnwrap(markers.readAttempt())
        XCTAssertEqual(attempt.toVersion, "0.9.0")
        XCTAssertEqual(attempt.dmgSHA256, inputs.dmgSHA256)

        // History recorded as not-yet-verified.
        XCTAssertEqual(history.latest?.toVersion, "0.9.0")
        XCTAssertEqual(history.latest?.launchVerified, false)
    }

    func testInstallFallsBackToFailedWhenUpdaterWontLaunch() async throws {
        let spy = SpyHandOff()
        spy.launchResult = false
        let history = UpdateHistoryStore(directory: tmp)
        let markers = UpdateInstallMarkerStore(directory: tmp)
        let (c, _, _) = try await readyController(spy: spy, history: history, markers: markers)

        let ok = await c.installAndRelaunch(reopenDocuments: [])
        XCTAssertFalse(ok)
        XCTAssertFalse(spy.terminated, "never quit the app if the updater didn't launch")
        guard case let .failed(failure) = c.phase else { return XCTFail("expected failed, got \(c.phase)") }
        XCTAssertEqual(failure.kind, .install)
        XCTAssertNil(markers.readAttempt(), "a non-started install must not leave an attempt marker")
    }

    func testInstallStopsBeforeHelperLaunchWhenReopenManifestCannotBeSaved() async throws {
        let spy = SpyHandOff()
        let history = UpdateHistoryStore(directory: tmp)
        let markers = UpdateInstallMarkerStore(directory: tmp)
        let (c, _, _) = try await readyController(spy: spy, history: history, markers: markers)
        try FileManager.default.createDirectory(
            at: tmp.appendingPathComponent("reopen-manifest.json"),
            withIntermediateDirectories: false
        )

        let ok = await c.installAndRelaunch(reopenDocuments: [
            ReopenDocument(path: "/Users/x/A.pdf", bookmarkData: nil, pageIndex: 3, displayName: "A"),
        ])

        XCTAssertFalse(ok)
        XCTAssertNil(spy.launchedInputs, "a missing reopen record must stop before helper launch")
        XCTAssertFalse(spy.terminated, "a missing reopen record must keep the app running")
        guard case let .failed(failure) = c.phase else { return XCTFail("expected a useful install failure") }
        XCTAssertEqual(failure.kind, .install)

        try FileManager.default.removeItem(at: tmp.appendingPathComponent("reopen-manifest.json"))
        await c.checkForUpdates(userInitiated: true)
        await c.downloadUpdate()
        XCTAssertEqual(c.phase, .readyToInstall(update()), "the verified download must remain retryable after repair")
    }

    func testInstallStopsBeforeHelperLaunchWhenAttemptMarkerCannotBeSaved() async throws {
        let spy = SpyHandOff()
        let history = UpdateHistoryStore(directory: tmp)
        let markers = UpdateInstallMarkerStore(directory: tmp)
        let (c, _, _) = try await readyController(spy: spy, history: history, markers: markers)
        try FileManager.default.createDirectory(
            at: tmp.appendingPathComponent("install-attempt.json"),
            withIntermediateDirectories: false
        )

        let ok = await c.installAndRelaunch(reopenDocuments: [])

        XCTAssertFalse(ok)
        XCTAssertNil(spy.launchedInputs, "an unrecorded attempt must stop before helper launch")
        XCTAssertFalse(spy.terminated, "an unrecorded attempt must keep the app running")
        guard case let .failed(failure) = c.phase else { return XCTFail("expected a useful install failure") }
        XCTAssertEqual(failure.kind, .install)

        try FileManager.default.removeItem(at: tmp.appendingPathComponent("install-attempt.json"))
        await c.checkForUpdates(userInitiated: true)
        await c.downloadUpdate()
        XCTAssertEqual(c.phase, .readyToInstall(update()), "the verified download must remain retryable after repair")
    }

    func testCancelledTerminationRevokesHelperBeforeReturningToRetryableState() async throws {
        let spy = SpyHandOff()
        spy.terminationAccepted = false
        let history = UpdateHistoryStore(directory: tmp)
        let markers = UpdateInstallMarkerStore(directory: tmp)
        let (c, _, _) = try await readyController(spy: spy, history: history, markers: markers)

        let ok = await c.installAndRelaunch(reopenDocuments: [])

        XCTAssertFalse(ok)
        XCTAssertTrue(spy.terminated, "the normal termination path must still review open documents")
        XCTAssertFalse(spy.helperAuthorized, "a cancelled quit must revoke the launched helper")
        XCTAssertEqual(c.phase, .readyToInstall(update()), "the user must be able to retry explicitly")
        XCTAssertNil(markers.readAttempt(), "a cancelled hand-off is not a pending install")
        XCTAssertNil(markers.readReopenManifest(), "a cancelled hand-off must not reopen stale state later")
        XCTAssertNil(history.latest, "a cancelled hand-off must not leave an unverified install row")

        spy.terminationAccepted = true
        let retryOK = await c.installAndRelaunch(reopenDocuments: [])
        XCTAssertTrue(retryOK, "the user must be able to retry explicitly")
        XCTAssertTrue(spy.helperAuthorized)
    }

    func testCancelledTerminationBlocksRetryWhenHelperRevocationFails() async throws {
        let spy = SpyHandOff()
        spy.terminationAccepted = false
        spy.abandonResult = false
        let history = UpdateHistoryStore(directory: tmp)
        let markers = UpdateInstallMarkerStore(directory: tmp)
        let (c, _, _) = try await readyController(spy: spy, history: history, markers: markers)

        let firstResult = await c.installAndRelaunch(reopenDocuments: [])
        XCTAssertFalse(firstResult)
        XCTAssertTrue(spy.helperAuthorized)
        guard case let .failed(failure) = c.phase else { return XCTFail("expected failed, got \(c.phase)") }
        XCTAssertEqual(failure.kind, .install)
        XCTAssertNotNil(markers.readAttempt(), "the live helper may still install after a later quit")
        XCTAssertNotNil(markers.readReopenManifest(), "relaunch must still recover the promised documents")
        XCTAssertNotNil(history.latest, "a later helper run must retain its unverified install record")

        await c.checkForUpdates(userInitiated: true)
        let retryResult = await c.installAndRelaunch(reopenDocuments: [])
        XCTAssertFalse(retryResult, "failed revocation must keep controller-level Retry closed")
        XCTAssertEqual(spy.updaterLaunchCount, 1)
    }

    func testInstallRechecksUnsavedDocumentsAfterPreparationBeforeLaunchingHelper() async throws {
        let spy = SpyHandOff()
        let history = UpdateHistoryStore(directory: tmp)
        let markers = UpdateInstallMarkerStore(directory: tmp)
        var snapshotCount = 0
        let (c, _, _) = try await readyController(
            spy: spy,
            history: history,
            markers: markers,
            openDocumentsSnapshot: {
                snapshotCount += 1
                return snapshotCount > 1
                    ? [.init(displayName: "Changed.pdf", hasUnsavedChanges: true)]
                    : []
            }
        )

        let ok = await c.installAndRelaunch(reopenDocuments: [])

        XCTAssertFalse(ok)
        XCTAssertGreaterThanOrEqual(snapshotCount, 2)
        XCTAssertNil(spy.launchedInputs, "a document changed during preparation must stop helper launch")
        XCTAssertFalse(spy.terminated)
        XCTAssertEqual(c.phase, .readyToInstall(update()))
        XCTAssertNil(markers.readAttempt())
        XCTAssertNil(markers.readReopenManifest())
        XCTAssertNil(history.latest)
    }

    func testSystemHandOffCreatesAndRevokesOneAuthorizationToken() throws {
        var openedURL: URL?
        let handOff = SystemUpdateInstallHandOff(cacheDirectory: tmp) { url in
            openedURL = url
            return true
        }
        let inputs = UpdaterScriptGenerator.Inputs(
            appPID: 4242,
            appBundlePath: "/Applications/Orifold.app",
            dmgPath: tmp.appendingPathComponent("Orifold-0.9.0.dmg").path,
            dmgSHA256: String(repeating: "a", count: 64),
            newVersion: "0.9.0",
            publisherTeamIdentifier: "TEAM123456",
            publisherBundleIdentifier: UpdatePublisherIdentity.expectedBundleIdentifier
        )

        XCTAssertTrue(handOff.launchUpdater(inputs))
        XCTAssertNotNil(openedURL)
        let authorizationURLs = try FileManager.default.contentsOfDirectory(
            at: tmp,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "authorized" }
        XCTAssertEqual(authorizationURLs.count, 1)

        XCTAssertTrue(handOff.abandonLaunchedHelper())
        XCTAssertFalse(FileManager.default.fileExists(atPath: authorizationURLs[0].path))
    }

    func testSystemHandOffRetainsOwnershipAndBlocksDuplicateLaunchWhenRevocationFails() throws {
        var openedURLs: [URL] = []
        let handOff = SystemUpdateInstallHandOff(
            cacheDirectory: tmp,
            open: { url in openedURLs.append(url); return true },
            removeAuthorization: { _ in throw CocoaError(.fileWriteNoPermission) }
        )
        let inputs = UpdaterScriptGenerator.Inputs(
            appPID: 4242,
            appBundlePath: "/Applications/Orifold.app",
            dmgPath: tmp.appendingPathComponent("Orifold-0.9.0.dmg").path,
            dmgSHA256: String(repeating: "a", count: 64),
            newVersion: "0.9.0",
            publisherTeamIdentifier: "TEAM123456",
            publisherBundleIdentifier: UpdatePublisherIdentity.expectedBundleIdentifier
        )

        XCTAssertTrue(handOff.launchUpdater(inputs))
        XCTAssertFalse(handOff.abandonLaunchedHelper())
        XCTAssertFalse(handOff.launchUpdater(inputs), "a live token must keep a second helper from launching")
        XCTAssertEqual(openedURLs.count, 1)
        let authorizationURLs = try FileManager.default.contentsOfDirectory(
            at: tmp,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "authorized" }
        XCTAssertEqual(authorizationURLs.count, 1)
    }

    func testInstallFailsClosedWhenRollbackArchiveCannotBePrepared() async throws {
        let spy = SpyHandOff()
        let history = UpdateHistoryStore(directory: tmp)
        let markers = UpdateInstallMarkerStore(directory: tmp)
        let (c, _, bundle) = try await readyController(spy: spy, history: history, markers: markers)
        try FileManager.default.removeItem(at: bundle)

        let ok = await c.installAndRelaunch(reopenDocuments: [])
        XCTAssertFalse(ok)
        XCTAssertNil(spy.launchedInputs, "automatic replacement must not start without a rollback archive")
        XCTAssertFalse(spy.terminated)
        guard case let .failed(failure) = c.phase else { return XCTFail("expected verification failure, got \(c.phase)") }
        XCTAssertEqual(failure.kind, .verification)
    }

    /// A locally built, ad-hoc-signed copy has no publisher to bind a candidate to. The refusal
    /// must land before anything is written: no reopen manifest, no rollback archive, no attempt
    /// marker, no history row — and it must say so, rather than reporting a broken updater.
    func testInstallRefusesAnUntrustedRunningBuildBeforeAnySideEffect() async throws {
        let spy = SpyHandOff()
        let history = UpdateHistoryStore(directory: tmp)
        let markers = UpdateInstallMarkerStore(directory: tmp)
        let dmg = tmp.appendingPathComponent("Orifold-0.9.0.dmg")
        try Data("pretend-dmg-bytes".utf8).write(to: dmg)
        let bundle = tmp.appendingPathComponent("Orifold.app")
        try FileManager.default.createDirectory(at: bundle.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        let rollbackDirectory = tmp.appendingPathComponent("Rollback")

        let c = UpdateController(
            transport: OrchTransport(outcome: .available(update())),
            downloader: OrchDownloader(result: .success(dmg)),
            defaults: defaults,
            currentVersion: UpdateVersion(string: "0.8.6")!,
            currentBuild: "12",
            archiver: RollbackArchiver(directory: rollbackDirectory),
            history: history,
            markers: markers,
            handOff: spy,
            bundleURL: bundle,
            publisherIdentityOverride: nil,          // ad-hoc / unsigned: no Developer ID identity
            processID: 4242,
            now: { Date(timeIntervalSince1970: 100) }
        )
        await c.checkForUpdates(userInitiated: true)
        await c.downloadUpdate()
        guard case .readyToInstall = c.phase else { throw XCTSkip("setup failed to reach readyToInstall: \(c.phase)") }

        let ok = await c.installAndRelaunch(reopenDocuments: [
            ReopenDocument(path: "/Users/x/A.pdf", bookmarkData: nil, pageIndex: 3, displayName: "A"),
        ])

        XCTAssertFalse(ok)
        guard case let .failed(failure) = c.phase else { return XCTFail("expected an untrusted-build failure, got \(c.phase)") }
        XCTAssertEqual(failure.kind, .untrustedBuild)
        XCTAssertNil(spy.launchedInputs, "no updater may be generated for an untrusted build")
        XCTAssertFalse(spy.terminated, "the app must keep running")
        XCTAssertNil(markers.readReopenManifest(), "nothing may be written before the trust check")
        XCTAssertNil(markers.readAttempt())
        XCTAssertNil(history.latest)
        XCTAssertNil(c.rollbackManifest)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: rollbackDirectory.path),
            "an install that never started must not archive the current bundle"
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: dmg.path), "the download stays for a manual install")
    }

    func testInstallIsNoOpWhenNotReady() async {
        let spy = SpyHandOff()
        let c = UpdateController(
            transport: OrchTransport(outcome: .upToDate),
            downloader: OrchDownloader(result: .failure(URLError(.badURL))),
            defaults: defaults,
            currentVersion: UpdateVersion(string: "0.8.6")!,
            handOff: spy,
            now: { Date(timeIntervalSince1970: 1) }
        )
        let ok = await c.installAndRelaunch(reopenDocuments: [])
        XCTAssertFalse(ok)
        XCTAssertFalse(spy.terminated)
    }

    // MARK: - Restore previous version

    /// Archives a fake previous bundle, then builds a controller whose archiver points at that
    /// same directory so init loads the resulting manifest (making restore available).
    private func controllerWithArchive(spy: SpyHandOff) throws -> (UpdateController, manifest: RollbackManifest, bundle: URL, rollbackDir: URL) {
        let rollbackDir = tmp.appendingPathComponent("Rollback")
        let archiver = RollbackArchiver(directory: rollbackDir)
        let bundle = tmp.appendingPathComponent("Orifold.app")
        try FileManager.default.createDirectory(at: bundle.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        try Data("v0.8.5".utf8).write(to: bundle.appendingPathComponent("Contents/marker"))
        var manifest = try archiver.archive(bundleURL: bundle, version: "0.8.5", build: "11")
        // The fixture is intentionally ad-hoc, so inject the trusted identity metadata that a
        // signed production bundle would carry. This keeps the orchestration test focused on
        // hand-off ordering while the identity extractor itself is tested separately.
        manifest.bundleIdentifier = UpdatePublisherIdentity.expectedBundleIdentifier
        manifest.teamIdentifier = "TEAM123456"
        try archiver.writeManifest(manifest)

        let c = UpdateController(
            transport: OrchTransport(outcome: .upToDate),
            downloader: OrchDownloader(result: .failure(URLError(.badURL))),
            defaults: defaults,
            currentVersion: UpdateVersion(string: "0.8.6")!,
            archiver: archiver,
            handOff: spy,
            bundleURL: bundle,
            publisherIdentityOverride: UpdatePublisherIdentity(
                bundleIdentifier: UpdatePublisherIdentity.expectedBundleIdentifier,
                teamIdentifier: "TEAM123456"),
            processID: 4242,
            now: { Date(timeIntervalSince1970: 1) }
        )
        return (c, manifest, bundle, rollbackDir)
    }

    func testRestoreHandsOffTheVerifiedArchiveAndQuits() async throws {
        let spy = SpyHandOff()
        let (c, manifest, bundle, rollbackDir) = try controllerWithArchive(spy: spy)
        XCTAssertTrue(c.canRestorePreviousVersion)

        let ok = await c.restorePreviousVersion()
        XCTAssertTrue(ok)
        XCTAssertTrue(spy.terminated, "must quit so the restore script can swap the bundle")

        let inputs = try XCTUnwrap(spy.restoreInputs)
        XCTAssertEqual(inputs.appPID, 4242)
        XCTAssertEqual(inputs.appBundlePath, bundle.path)
        XCTAssertEqual(inputs.restoreVersion, "0.8.5")
        XCTAssertEqual(inputs.archiveSHA256, manifest.sha256)
        XCTAssertEqual(inputs.archiveZipPath, rollbackDir.appendingPathComponent(manifest.archiveFileName).path)
    }

    func testCancelledRestoreTerminationRevokesHelperAndAllowsRetry() async throws {
        let spy = SpyHandOff()
        spy.terminationAccepted = false
        let (c, _, _, _) = try controllerWithArchive(spy: spy)

        let firstOK = await c.restorePreviousVersion()
        XCTAssertFalse(firstOK)
        XCTAssertTrue(spy.terminated)
        XCTAssertFalse(spy.helperAuthorized, "a cancelled quit must revoke the restore helper")

        spy.terminationAccepted = true
        let retryOK = await c.restorePreviousVersion()
        XCTAssertTrue(retryOK, "restore must leave its in-flight gate retryable")
        XCTAssertTrue(spy.helperAuthorized)
    }

    func testCancelledRestoreBlocksRetryWhenHelperRevocationFails() async throws {
        let spy = SpyHandOff()
        spy.terminationAccepted = false
        spy.abandonResult = false
        let (c, _, _, _) = try controllerWithArchive(spy: spy)

        let firstResult = await c.restorePreviousVersion()
        XCTAssertFalse(firstResult)
        XCTAssertTrue(spy.helperAuthorized)
        XCTAssertFalse(c.canRestorePreviousVersion)
        guard case let .failed(failure) = c.phase else { return XCTFail("expected failed, got \(c.phase)") }
        XCTAssertEqual(failure.kind, .install)

        spy.terminationAccepted = true
        let retryResult = await c.restorePreviousVersion()
        XCTAssertFalse(retryResult, "failed revocation must keep the restore gate closed")
        XCTAssertEqual(spy.restoreLaunchCount, 1)
    }

    func testRestoreNotOfferedForTheVersionAlreadyRunning() throws {
        // After a restore relaunches into the archived version, its manifest still names that
        // same version — the menu must not then offer to "restore" the build you're already on.
        let previous = tmp.appendingPathComponent("Same.app")
        try FileManager.default.createDirectory(at: previous.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        try Data("same".utf8).write(to: previous.appendingPathComponent("Contents/marker"))
        let archiver = RollbackArchiver(directory: tmp.appendingPathComponent("RollbackSame"))
        _ = try archiver.archive(bundleURL: previous, version: "0.8.6", build: "12")   // == currentVersion below

        let c = UpdateController(
            transport: OrchTransport(outcome: .upToDate),
            downloader: OrchDownloader(result: .failure(URLError(.badURL))),
            defaults: defaults,
            currentVersion: UpdateVersion(string: "0.8.6")!,
            archiver: archiver,
            handOff: SpyHandOff(),
            now: { Date(timeIntervalSince1970: 1) }
        )
        XCTAssertFalse(c.canRestorePreviousVersion, "must not offer to restore the version already running")
    }

    func testRestoreIsNoOpWithoutAnArchive() async {
        let spy = SpyHandOff()
        let c = UpdateController(
            transport: OrchTransport(outcome: .upToDate),
            downloader: OrchDownloader(result: .failure(URLError(.badURL))),
            defaults: defaults,
            currentVersion: UpdateVersion(string: "0.8.6")!,
            archiver: RollbackArchiver(directory: tmp.appendingPathComponent("EmptyRollback")),
            handOff: spy,
            now: { Date(timeIntervalSince1970: 1) }
        )
        XCTAssertFalse(c.canRestorePreviousVersion)
        let ok = await c.restorePreviousVersion()
        XCTAssertFalse(ok)
        XCTAssertFalse(spy.terminated)
        XCTAssertNil(spy.restoreInputs)
    }

    func testRestoreAbortsWhenTheArchiveFailsItsChecksum() async throws {
        let spy = SpyHandOff()
        let (c, manifest, _, rollbackDir) = try controllerWithArchive(spy: spy)
        // Corrupt the archive after the manifest recorded its hash → integrity guard must trip,
        // and the app must NOT quit for a restore that would only fail.
        try Data("corrupted-bytes".utf8).write(to: rollbackDir.appendingPathComponent(manifest.archiveFileName))

        let ok = await c.restorePreviousVersion()
        XCTAssertFalse(ok)
        XCTAssertFalse(spy.terminated)
        XCTAssertNil(spy.restoreInputs, "a checksum mismatch must never reach the hand-off")
    }
}
