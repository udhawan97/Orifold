import Darwin
import Foundation
import XCTest
@testable import Orifold

final class RollbackArchiveTransactionTests: XCTestCase {
    private var root: URL!
    private var rollback: URL { root.appendingPathComponent("Rollback", isDirectory: true) }
    private var cache: URL { root.appendingPathComponent("UpdaterCache", isDirectory: true) }

    override func setUpWithError() throws {
        let temporary = ProcessInfo.processInfo.environment["ORIFOLD_TEST_TEMP_ROOT"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) } ?? FileManager.default.temporaryDirectory
        root = temporary.appendingPathComponent("orifold-rollback-transaction-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: rollback, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testCleanerKeepsIncompleteStagingAndCurrentArchiveWhilePruningSupersededZip() throws {
        try Data("old".utf8).write(to: rollback.appendingPathComponent("old.zip"))
        let current = rollback.appendingPathComponent("current.zip")
        try Data("current".utf8).write(to: current)
        let staging = rollback.appendingPathComponent(".Orifold-\(UUID().uuidString).partial")
        try Data("partial archive bytes".utf8).write(to: staging)
        let archiver = RollbackArchiver(directory: rollback)
        try archiver.writeManifest(manifest("current.zip"))
        let report = UpdateArtifactCleaner(updaterCacheDirectory: cache, rollbackDirectory: rollback).clean()
        XCTAssertEqual(report.removed, ["old.zip"])
        XCTAssertEqual(try Data(contentsOf: staging), Data("partial archive bytes".utf8))
        XCTAssertEqual(try Data(contentsOf: current), Data("current".utf8))
    }

    func testCleanerWaitsForPublicationTransactionAndThenKeepsNewManifestArchive() throws {
        try Data("old".utf8).write(to: rollback.appendingPathComponent("old.zip"))
        try RollbackArchiver(directory: rollback).writeManifest(manifest("old.zip"))
        let cleaner = UpdateArtifactCleaner(updaterCacheDirectory: cache, rollbackDirectory: rollback)
        let started = DispatchSemaphore(value: 0)
        let completed = DispatchSemaphore(value: 0)
        try RollbackArchiveTransaction.withLock(in: rollback) {
            DispatchQueue.global().async {
                started.signal()
                cleaner.clean()
                completed.signal()
            }
            XCTAssertEqual(started.wait(timeout: .now() + 2), .success)
            XCTAssertEqual(completed.wait(timeout: .now() + 0.1), .timedOut,
                           "cleanup cannot complete while publication owns the lock")
            try Data("new committed bytes".utf8).write(to: rollback.appendingPathComponent("new.zip"))
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(manifest("new.zip")).write(to: rollback.appendingPathComponent("rollback-manifest.json"), options: .atomic)
        }
        XCTAssertEqual(completed.wait(timeout: .now() + 2), .success)
        let current = try XCTUnwrap(RollbackArchiver(directory: rollback).loadManifest())
        XCTAssertEqual(current.archiveFileName, "new.zip")
        XCTAssertEqual(try Data(contentsOf: rollback.appendingPathComponent(current.archiveFileName)), Data("new committed bytes".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: rollback.appendingPathComponent("old.zip").path))
    }

    func testSymlinkLockRefusesArchiveAndLeavesCleanerInert() throws {
        let outside = root.appendingPathComponent("unrelated.lock")
        try Data().write(to: outside)
        try FileManager.default.createSymbolicLink(at: rollback.appendingPathComponent(".rollback-transaction.lock"), withDestinationURL: outside)
        let zip = rollback.appendingPathComponent("keep.zip")
        try Data("preserved".utf8).write(to: zip)
        let cleaner = UpdateArtifactCleaner(updaterCacheDirectory: cache, rollbackDirectory: rollback)
        XCTAssertTrue(cleaner.clean().removed.isEmpty)
        XCTAssertEqual(try Data(contentsOf: zip), Data("preserved".utf8))
        XCTAssertThrowsError(try RollbackArchiver(directory: rollback).archive(bundleURL: root.appendingPathComponent("missing.app"), version: "1", build: "1"))
    }

    func testFailedSameVersionManifestCommitPreservesPreviousManifestAndZipExactly() throws {
        let bundle = root.appendingPathComponent("Fictional.app", isDirectory: true)
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        let marker = bundle.appendingPathComponent("marker")
        try Data("previous bundle".utf8).write(to: marker)
        let archiver = RollbackArchiver(directory: rollback)
        let old = try archiver.archive(bundleURL: bundle, version: "1.0", build: "1", at: Date(timeIntervalSince1970: 100))
        let oldZip = try XCTUnwrap(archiver.archiveURL(for: old))
        let oldZipBytes = try Data(contentsOf: oldZip)
        let manifestURL = rollback.appendingPathComponent("rollback-manifest.json")
        let oldManifestBytes = try Data(contentsOf: manifestURL)
        XCTAssertEqual(Darwin.chflags(manifestURL.path, UInt32(UF_IMMUTABLE)), 0)
        defer { _ = Darwin.chflags(manifestURL.path, 0) }
        try Data("replacement bundle".utf8).write(to: marker)
        XCTAssertThrowsError(try archiver.archive(bundleURL: bundle, version: "1.0", build: "2"))
        XCTAssertEqual(try Data(contentsOf: manifestURL), oldManifestBytes)
        XCTAssertEqual(try Data(contentsOf: oldZip), oldZipBytes)
        XCTAssertEqual(archiver.loadManifest(), old)
        XCTAssertNoThrow(try archiver.verify(old))
        let entries = try FileManager.default.contentsOfDirectory(at: rollback, includingPropertiesForKeys: nil)
        XCTAssertEqual(entries.filter { $0.pathExtension == "zip" }.map(\.lastPathComponent), [old.archiveFileName])
        XCTAssertFalse(entries.contains { $0.pathExtension == "partial" })
    }

    private func manifest(_ name: String) -> RollbackManifest {
        RollbackManifest(version: "fictional", build: "1", sha256: "fictional", archivedAt: Date(), archiveFileName: name)
    }

    func testMultiplePendingHelpersAndUnknownSidecarsArePreservedDuringCleanup() throws {
        try checkMultiplePendingHelpersAndUnknownSidecars(rollbackDirectory: rollback)
    }

    func testMultiplePendingHelpersCleanupThroughRelativeDirectoryURL() throws {
        // FileManager enumerates absolute URLs even when the caller supplied a relative
        // directory. The same identity mismatch occurs for macOS /var -> /private/var.
        let base = URL(fileURLWithPath: root.path, isDirectory: true)
        let relative = URL(fileURLWithPath: "Rollback", isDirectory: true, relativeTo: base)
        XCTAssertNotEqual(relative, rollback)
        XCTAssertEqual(relative.path, rollback.path)
        try checkMultiplePendingHelpersAndUnknownSidecars(rollbackDirectory: relative)
    }

    private func checkMultiplePendingHelpersAndUnknownSidecars(rollbackDirectory: URL) throws {
        let bundle = root.appendingPathComponent("Orifold.app")
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        let marker = bundle.appendingPathComponent("marker")
        try Data("A".utf8).write(to: marker)
        let archiver = RollbackArchiver(directory: rollbackDirectory)
        let current = try archiver.archive(bundleURL: bundle, version: "1", build: "1")
        try Data("B".utf8).write(to: marker)
        let firstID = UUID(), secondID = UUID()
        let first = try archiver.prepare(bundleURL: bundle, version: "2", build: "2", sessionID: firstID, toVersion: "3")
        let second = try archiver.prepare(bundleURL: bundle, version: "2", build: "2", sessionID: secondID, toVersion: "4")
        let cleaner = UpdateArtifactCleaner(updaterCacheDirectory: cache, rollbackDirectory: rollbackDirectory)
        XCTAssertTrue(cleaner.clean().removed.isEmpty)
        for expected in [current, first, second] { XCTAssertNoThrow(try archiver.verify(expected)) }
        XCTAssertThrowsError(try archiver.prepare(bundleURL: bundle, version: "2", build: "2", sessionID: firstID, toVersion: "5"))
        try archiver.discardPreparation(sessionID: UUID())
        try archiver.discardPreparation(sessionID: firstID)
        XCTAssertNil(archiver.archiveURL(for: first))
        XCTAssertNoThrow(try archiver.verify(current))
        XCTAssertNoThrow(try archiver.verify(second))

        let malformed = rollbackDirectory.appendingPathComponent(".rollback-pending-unknown.json")
        try Data("{unknown".utf8).write(to: malformed)
        let orphan = rollbackDirectory.appendingPathComponent("unresolved.zip")
        try Data("preserve unknown recovery".utf8).write(to: orphan)
        XCTAssertTrue(cleaner.clean().removed.isEmpty)
        XCTAssertEqual(try Data(contentsOf: orphan), Data("preserve unknown recovery".utf8))
    }

    func testPromotionRejectsMismatchedAttemptAndCorruptedRescue() throws {
        let bundle = root.appendingPathComponent("Orifold.app")
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        try Data("A".utf8).write(to: bundle.appendingPathComponent("marker"))
        let archiver = RollbackArchiver(directory: rollback)
        let previous = try archiver.archive(bundleURL: bundle, version: "1", build: "1", at: Date(timeIntervalSince1970: 100))
        let session = UUID()
        let rescue = try archiver.prepare(bundleURL: bundle, version: "2", build: "2", sessionID: session, toVersion: "3")
        var attempt = InstallAttempt(sessionID: session, fromVersion: "2", toVersion: "4", dmgPath: "fictional", dmgSHA256: "", startedAt: Date())
        XCTAssertThrowsError(try archiver.commitPreparation(for: attempt))
        XCTAssertEqual(archiver.loadManifest(), previous)
        attempt.toVersion = "3"
        let rescueURL = try XCTUnwrap(archiver.archiveURL(for: rescue))
        try Data("damaged rescue".utf8).write(to: rescueURL)
        XCTAssertThrowsError(try archiver.commitPreparation(for: attempt))
        XCTAssertEqual(archiver.loadManifest(), previous)
        XCTAssertNoThrow(try archiver.verify(previous))
        XCTAssertTrue(FileManager.default.fileExists(atPath: rescueURL.path))
    }
}
