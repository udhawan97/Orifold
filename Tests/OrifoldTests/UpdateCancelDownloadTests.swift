import XCTest
@testable import Orifold

private struct StubTransport2: UpdateTransport {
    var outcome: UpdateCheckOutcome
    func checkForUpdate(currentVersion: UpdateVersion) async throws -> UpdateCheckOutcome { outcome }
}

/// Suspends until cancelled, so the controller's real cancel path can be exercised.
private struct HangingDownloader: UpdateDownloading {
    func download(_ update: AvailableUpdate, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        try await Task.sleep(nanoseconds: 5_000_000_000)
        return URL(fileURLWithPath: "/never/reached")
    }
}

/// Throws a specific error immediately, to test error→phase mapping.
private struct ThrowingDownloader: UpdateDownloading {
    var error: Error
    func download(_ update: AvailableUpdate, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        throw error
    }
}

@MainActor
final class UpdateCancelDownloadTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    private var rollbackDir: URL!

    override func setUpWithError() throws {
        suite = "orifold-cancel-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        rollbackDir = FileManager.default.temporaryDirectory.appendingPathComponent(suite, isDirectory: true)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: rollbackDir)
    }

    private func update() -> AvailableUpdate {
        AvailableUpdate(version: "0.9.0", currentVersion: "0.8.6", releaseNotesURL: nil, downloadPageURL: nil,
                        publishedAt: nil, assetSizeBytes: nil, dmgDownloadURL: URL(string: "https://example.com/u.dmg"))
    }

    private func controller(_ downloader: UpdateDownloading) -> UpdateController {
        UpdateController(
            transport: StubTransport2(outcome: .available(update())),
            downloader: downloader,
            defaults: defaults,
            currentVersion: UpdateVersion(string: "0.8.6")!,
            archiver: RollbackArchiver(directory: rollbackDir),
            now: { Date(timeIntervalSince1970: 1) }
        )
    }

    // MARK: - Phase classification

    func testInstallingPhaseIsBusyAndCarriesTheUpdate() {
        let phase = UpdatePhase.installing(update())
        XCTAssertTrue(phase.isBusy)
        XCTAssertEqual(phase.availableUpdate?.version, "0.9.0")
    }

    // MARK: - Error mapping

    func testURLErrorCancelledReturnsToUpdateAvailable() async {
        let c = controller(ThrowingDownloader(error: URLError(.cancelled)))
        await c.checkForUpdates(userInitiated: true)
        await c.downloadUpdate()
        XCTAssertEqual(c.phase, .updateAvailable(update()), "a cancelled transfer is not a failure")
    }

    func testCancellationErrorReturnsToUpdateAvailable() async {
        let c = controller(ThrowingDownloader(error: CancellationError()))
        await c.checkForUpdates(userInitiated: true)
        await c.downloadUpdate()
        XCTAssertEqual(c.phase, .updateAvailable(update()))
    }

    // MARK: - Real cancel via begin/cancel

    func testBeginThenCancelDownloadReturnsToUpdateAvailable() async {
        let c = controller(HangingDownloader())
        await c.checkForUpdates(userInitiated: true)

        c.beginDownload()
        // Let the download Task start and reach `.downloading`.
        for _ in 0..<1000 {
            if case .downloading = c.phase { break }
            await Task.yield()
        }
        guard case .downloading = c.phase else { return XCTFail("download did not start; phase \(c.phase)") }

        let inflight = c.downloadTask          // capture before cancel nils it
        c.cancelDownload()
        await inflight?.value                  // wait for the cancelled download to unwind

        XCTAssertEqual(c.phase, .updateAvailable(update()))
    }

    func testCancelIsIgnoredWhenNotDownloading() async {
        let c = controller(HangingDownloader())
        await c.checkForUpdates(userInitiated: true)
        c.cancelDownload()   // no-op; still just an available update
        XCTAssertEqual(c.phase, .updateAvailable(update()))
    }
}
