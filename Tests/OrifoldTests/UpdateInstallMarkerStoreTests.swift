import XCTest
@testable import Orifold

final class UpdateInstallMarkerStoreTests: XCTestCase {
    private var dir: URL!
    private var store: UpdateInstallMarkerStore!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("orifold-markers-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        store = UpdateInstallMarkerStore(directory: dir)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func manifest() -> UpdateReopenManifest {
        UpdateReopenManifest(
            fromVersion: "0.8.6", toVersion: "0.8.7",
            savedAt: Date(timeIntervalSince1970: 1_700_000_000),
            documents: [
                ReopenDocument(path: "/Users/x/A.pdf", bookmarkData: Data([1, 2, 3]), pageIndex: 4, displayName: "A"),
                ReopenDocument(path: "/Users/x/B.pdf", bookmarkData: nil, pageIndex: nil, displayName: "B"),
            ]
        )
    }

    func testReopenManifestRoundTrips() throws {
        try store.writeReopenManifest(manifest())
        XCTAssertEqual(store.readReopenManifest(), manifest())
    }

    func testConsumeReturnsThenDeletes() throws {
        try store.writeReopenManifest(manifest())
        XCTAssertEqual(store.consumeReopenManifest(), manifest())
        XCTAssertNil(store.readReopenManifest(), "consume must delete so reopen can't repeat")
        XCTAssertNil(store.consumeReopenManifest())
    }

    func testInstallAttemptRoundTripsAndClears() throws {
        let attempt = InstallAttempt(fromVersion: "0.8.6", toVersion: "0.8.7",
                                     dmgPath: "/cache/Orifold-0.8.7.dmg", dmgSHA256: String(repeating: "a", count: 64),
                                     startedAt: Date(timeIntervalSince1970: 42))
        try store.writeAttempt(attempt)
        XCTAssertEqual(store.readAttempt(), attempt)
        store.clearAttempt()
        XCTAssertNil(store.readAttempt())
    }

    func testAbsentMarkersReadNil() {
        XCTAssertNil(store.readReopenManifest())
        XCTAssertNil(store.readAttempt())
    }

    /// Additive-schema: a manifest written with only the required field decodes, defaulting
    /// the rest — the rollback case where an older app reads a newer manifest.
    func testReopenManifestDecodesMinimalJSON() throws {
        let json = """
        { "toVersion": "0.9.0" }
        """
        try json.data(using: .utf8)!.write(to: dir.appendingPathComponent("reopen-manifest.json"))
        let m = try XCTUnwrap(store.readReopenManifest())
        XCTAssertEqual(m.toVersion, "0.9.0")
        XCTAssertEqual(m.fromVersion, "")
        XCTAssertTrue(m.documents.isEmpty)
        XCTAssertEqual(m.schemaVersion, 1)
    }
}
