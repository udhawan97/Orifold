import XCTest
@testable import Orifold

final class RecoveryStoreTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("orifold-recovery-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func save(_ store: RecoveryStore, name: String, bytes: String, at: TimeInterval, reason: RecoveryMetadata.Reason = .preUpdate) throws -> RecoveryMetadata {
        try store.saveCheckpoint(
            payload: bytes.data(using: .utf8)!,
            sourceURLPath: "/Users/test/\(name).pdf",
            sourceBookmark: nil,
            displayName: name,
            reason: reason,
            appVersion: "0.9.0",
            dirtyAtCapture: true,
            capturedAt: Date(timeIntervalSince1970: at)
        )
    }

    func testCheckpointRoundTripsPayloadAndMetadata() throws {
        let store = RecoveryStore(directory: directory)
        let meta = try save(store, name: "Report", bytes: "SNAPSHOT-BYTES", at: 10)

        let entries = store.list()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.metadata.displayName, "Report")
        XCTAssertEqual(entries.first?.metadata.reason, .preUpdate)
        XCTAssertEqual(try store.payloadData(for: meta), "SNAPSHOT-BYTES".data(using: .utf8))
    }

    func testListIsNewestFirst() throws {
        let store = RecoveryStore(directory: directory)
        _ = try save(store, name: "Old", bytes: "a", at: 100)
        _ = try save(store, name: "New", bytes: "b", at: 200)
        XCTAssertEqual(store.list().map { $0.metadata.displayName }, ["New", "Old"])
    }

    func testDiscardRemovesPayloadAndSidecar() throws {
        let store = RecoveryStore(directory: directory)
        let meta = try save(store, name: "Doomed", bytes: "x", at: 10)
        store.discard(id: meta.id)
        XCTAssertTrue(store.list().isEmpty)
        // Both files are gone.
        let remaining = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        XCTAssertTrue(remaining.isEmpty)
    }

    /// A crash between the payload write and the sidecar write leaves an orphan payload.
    /// It must never surface as a half-broken recovery card.
    func testOrphanPayloadWithoutSidecarIsIgnored() throws {
        let orphan = directory.appendingPathComponent("\(UUID().uuidString).\(RecoveryStore.payloadExtension)")
        try "torn".data(using: .utf8)!.write(to: orphan)

        let store = RecoveryStore(directory: directory)
        XCTAssertTrue(store.list().isEmpty)
    }

    func testMetadataDecodesMinimalSidecarWithDefaults() throws {
        let id = UUID()
        let payloadName = "\(id.uuidString).\(RecoveryStore.payloadExtension)"
        try "bytes".data(using: .utf8)!.write(to: directory.appendingPathComponent(payloadName))
        let json = """
        {
          "id": "\(id.uuidString)",
          "displayName": "Legacy",
          "capturedAt": "2026-07-08T00:00:00Z",
          "payloadFileName": "\(payloadName)"
        }
        """
        try json.data(using: .utf8)!.write(to: directory.appendingPathComponent("\(id.uuidString).json"))

        let store = RecoveryStore(directory: directory)
        let entry = try XCTUnwrap(store.list().first)
        XCTAssertEqual(entry.metadata.reason, .preUpdate)   // defaulted
        XCTAssertTrue(entry.metadata.dirtyAtCapture)        // defaulted
        XCTAssertEqual(entry.metadata.appVersion, "")       // defaulted
    }
}
