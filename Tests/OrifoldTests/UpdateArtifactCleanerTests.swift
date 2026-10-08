import XCTest
@testable import Orifold

final class UpdateArtifactCleanerTests: XCTestCase {
    private var root: URL!
    private var cacheDir: URL!
    private var rollbackDir: URL!

    override func setUpWithError() throws {
        let temporary = ProcessInfo.processInfo.environment["ORIFOLD_TEST_TEMP_ROOT"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) } ?? FileManager.default.temporaryDirectory
        root = temporary
            .appendingPathComponent("orifold-cleaner-\(UUID().uuidString)", isDirectory: true)
        // Named exactly as the cleaner's guard requires.
        cacheDir = root.appendingPathComponent("UpdaterCache", isDirectory: true)
        rollbackDir = root.appendingPathComponent("Rollback", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: rollbackDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func write(_ name: String, in dir: URL, bytes: String = "x", ageHours: Double? = nil) throws -> URL {
        let url = dir.appendingPathComponent(name)
        try bytes.data(using: .utf8)!.write(to: url)
        if let ageHours {
            let date = Date(timeIntervalSinceNow: -ageHours * 3600)
            try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
        }
        return url
    }

    private func cleaner() -> UpdateArtifactCleaner {
        UpdateArtifactCleaner(updaterCacheDirectory: cacheDir, rollbackDirectory: rollbackDir)
    }

    func testRemovesStaleDownloadButKeepsRecentOne() throws {
        let stale = try write("Orifold-0.9.0.dmg", in: cacheDir, ageHours: 48)
        let fresh = try write("Orifold-0.9.1.dmg", in: cacheDir, ageHours: 1)

        let report = cleaner().clean(now: Date(), retainDownloads: 24 * 3600)

        XCTAssertFalse(FileManager.default.fileExists(atPath: stale.path), "stale download should be removed")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fresh.path), "in-window download must be kept")
        XCTAssertEqual(report.removed, ["Orifold-0.9.0.dmg"])
    }

    func testNeverDeletesUserPDFsOrRecentsEvenInsideCache() throws {
        // Defence in depth: user content must survive even if it somehow lands in the cache.
        let pdf = try write("MyContract.pdf", in: cacheDir, ageHours: 99)
        let recents = try write("recents.json", in: cacheDir, ageHours: 99)

        let report = cleaner().clean(now: Date(), retainDownloads: 24 * 3600)

        XCTAssertTrue(FileManager.default.fileExists(atPath: pdf.path), "user PDF must never be deleted")
        XCTAssertTrue(FileManager.default.fileExists(atPath: recents.path), "recents store must never be deleted")
        XCTAssertTrue(report.skippedProtected.contains("MyContract.pdf"))
        XCTAssertTrue(report.skippedProtected.contains("recents.json"))
    }

    func testRollbackPruneKeepsTheCurrentArchiveAndDropsOthers() throws {
        // Current manifest points at 0.8.5; an older 0.8.4 archive should be pruned.
        let current = try write("Orifold-0.8.5.zip", in: rollbackDir, ageHours: 100)
        let old = try write("Orifold-0.8.4.zip", in: rollbackDir, ageHours: 100)
        let archiver = RollbackArchiver(directory: rollbackDir)
        try archiver.writeManifest(RollbackManifest(
            version: "0.8.5", build: "12", sha256: String(repeating: "a", count: 64),
            archivedAt: Date(timeIntervalSince1970: 0), archiveFileName: "Orifold-0.8.5.zip"
        ))

        cleaner().clean()

        XCTAssertTrue(FileManager.default.fileExists(atPath: current.path), "manifest-referenced archive is kept")
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.path), "unreferenced older archive is pruned")
    }

    func testRefusesDirectoryOutsideTheAllowlist() throws {
        // A cleaner mistakenly pointed at a non-owned directory (e.g. Recovery) must be inert.
        let recovery = root.appendingPathComponent("Recovery", isDirectory: true)
        try FileManager.default.createDirectory(at: recovery, withIntermediateDirectories: true)
        let userSnapshot = try write("important.orifold-recovery", in: recovery, ageHours: 999)

        let misaimed = UpdateArtifactCleaner(updaterCacheDirectory: recovery, rollbackDirectory: rollbackDir)
        let report = misaimed.clean()

        XCTAssertTrue(FileManager.default.fileExists(atPath: userSnapshot.path),
                      "cleaner must refuse any directory not in the owned-name allowlist")
        XCTAssertTrue(report.removed.isEmpty)
    }

    func testCleanIsSafeOnEmptyDirectories() {
        let report = cleaner().clean()
        XCTAssertEqual(report, UpdateArtifactCleaner.Report())
    }
}
