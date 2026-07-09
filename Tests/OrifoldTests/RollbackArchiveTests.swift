import XCTest
@testable import Orifold

final class RollbackArchiveTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("orifold-rollback-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testSHA256MatchesShasumFormat() throws {
        // Known-answer test: SHA-256 of "abc" is the canonical NIST vector, lowercase hex,
        // exactly what `shasum -a 256` prints — so a manifest hash checks against a
        // published `.sha256` sidecar without reformatting.
        let file = directory.appendingPathComponent("abc.txt")
        try "abc".data(using: .utf8)!.write(to: file)
        let digest = try RollbackArchiver.sha256(of: file)
        XCTAssertEqual(digest, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    func testArchiveCreatesZipManifestAndVerifies() throws {
        // Build a fake "bundle" directory tree to zip.
        let bundle = directory.appendingPathComponent("Orifold.app", isDirectory: true)
        try FileManager.default.createDirectory(at: bundle.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
        try "binary".data(using: .utf8)!.write(to: bundle.appendingPathComponent("Contents/MacOS/Orifold"))

        let archiver = RollbackArchiver(directory: directory.appendingPathComponent("Rollback"))
        let manifest = try archiver.archive(bundleURL: bundle, version: "0.8.4", build: "11", at: Date(timeIntervalSince1970: 100))

        XCTAssertEqual(manifest.version, "0.8.4")
        XCTAssertEqual(manifest.archiveFileName, "Orifold-0.8.4.zip")
        XCTAssertEqual(manifest.sha256.count, 64)
        XCTAssertNotNil(archiver.archiveURL(for: manifest))
        XCTAssertNoThrow(try archiver.verify(manifest))

        // The manifest survives a fresh archiver over the same directory.
        let reopened = RollbackArchiver(directory: directory.appendingPathComponent("Rollback"))
        XCTAssertEqual(reopened.loadManifest(), manifest)
    }

    func testVerifyDetectsCorruptedArchive() throws {
        let bundle = directory.appendingPathComponent("Orifold.app", isDirectory: true)
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        try "x".data(using: .utf8)!.write(to: bundle.appendingPathComponent("marker"))

        let archiver = RollbackArchiver(directory: directory.appendingPathComponent("Rollback"))
        let manifest = try archiver.archive(bundleURL: bundle, version: "0.8.4", build: "11")

        // Tamper with the archive on disk.
        let archiveURL = try XCTUnwrap(archiver.archiveURL(for: manifest))
        try Data([0xDE, 0xAD, 0xBE, 0xEF]).write(to: archiveURL)

        XCTAssertThrowsError(try archiver.verify(manifest)) { error in
            XCTAssertEqual(error as? RollbackArchiver.ArchiveError, .hashMismatch)
        }
    }

    func testArchivePrunesEarlierArchive() throws {
        let rollbackDir = directory.appendingPathComponent("Rollback")
        let archiver = RollbackArchiver(directory: rollbackDir)

        let bundle = directory.appendingPathComponent("Orifold.app", isDirectory: true)
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        try "one".data(using: .utf8)!.write(to: bundle.appendingPathComponent("marker"))
        try archiver.archive(bundleURL: bundle, version: "0.8.3", build: "10")

        try "two".data(using: .utf8)!.write(to: bundle.appendingPathComponent("marker"))
        try archiver.archive(bundleURL: bundle, version: "0.8.4", build: "11")

        let zips = try FileManager.default.contentsOfDirectory(at: rollbackDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "zip" }
        XCTAssertEqual(zips.map(\.lastPathComponent), ["Orifold-0.8.4.zip"], "Only the immediate predecessor is retained")
    }
}
