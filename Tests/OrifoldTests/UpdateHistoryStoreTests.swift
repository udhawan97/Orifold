import XCTest
@testable import Orifold

final class UpdateHistoryStoreTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("orifold-history-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeRecord(from: String, to: String, at: TimeInterval) -> UpdateHistoryRecord {
        UpdateHistoryRecord(
            fromVersion: from, fromBuild: "1",
            toVersion: to, toBuild: "2",
            installedAt: Date(timeIntervalSince1970: at)
        )
    }

    func testRecordsPersistAcrossStoreInstances() {
        let store = UpdateHistoryStore(directory: directory)
        store.record(makeRecord(from: "0.8.4", to: "0.9.0", at: 1_700_000_000))

        let reopened = UpdateHistoryStore(directory: directory)
        XCTAssertEqual(reopened.records.count, 1)
        XCTAssertEqual(reopened.latest?.toVersion, "0.9.0")
    }

    func testRingBufferCapsAtMaxRecords() {
        let store = UpdateHistoryStore(directory: directory)
        for i in 0..<(UpdateHistoryStore.maxRecords + 5) {
            store.record(makeRecord(from: "0.\(i)", to: "0.\(i + 1)", at: TimeInterval(i)))
        }
        XCTAssertEqual(store.records.count, UpdateHistoryStore.maxRecords)
        // Oldest entries are the ones dropped; the most recent survive.
        XCTAssertEqual(store.latest?.toVersion, "0.\(UpdateHistoryStore.maxRecords + 5)")
    }

    func testUpdateFlipsLaunchVerifiedInPlace() {
        let store = UpdateHistoryStore(directory: directory)
        let record = store.record(makeRecord(from: "0.8.4", to: "0.9.0", at: 1))
        store.update(id: record.id) {
            $0.launchVerified = true
            $0.verifiedAt = Date(timeIntervalSince1970: 2)
        }
        let reopened = UpdateHistoryStore(directory: directory)
        XCTAssertEqual(reopened.latest?.launchVerified, true)
        XCTAssertEqual(reopened.latest?.verifiedAt, Date(timeIntervalSince1970: 2))
    }

    /// The additive-schema rule: a ledger written with only the v1-required fields (as a
    /// newer app that added fields, or a hand-authored file) must still decode. This
    /// guards the rollback case where an *older* app reads a *newer* app's ledger.
    func testDecodesMinimalRecordWithDefaultsForNewerFields() throws {
        let json = """
        {
          "schemaVersion": 1,
          "records": [
            {
              "fromVersion": "0.8.4",
              "toVersion": "0.9.0",
              "installedAt": "2026-07-08T00:00:00Z"
            }
          ]
        }
        """
        try json.data(using: .utf8)!.write(to: directory.appendingPathComponent("update-history.json"))

        let store = UpdateHistoryStore(directory: directory)
        let record = try XCTUnwrap(store.latest)
        XCTAssertEqual(record.fromVersion, "0.8.4")
        XCTAssertEqual(record.fromBuild, "")            // defaulted
        XCTAssertEqual(record.channel, "stable")        // defaulted
        XCTAssertFalse(record.launchVerified)           // defaulted
        XCTAssertFalse(record.rolledBack)               // defaulted
    }
}
