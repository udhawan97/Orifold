import Foundation

/// One row in the update ledger: what version replaced what, when, and how it fared.
///
/// Decoding is deliberately tolerant — every field added after v1 is optional with a
/// default — so an *older* app (after a rollback) can still read a ledger a newer app
/// wrote. That "additive-only" rule is enforced by `UpdateHistoryStoreTests`; breaking
/// it requires bumping `UpdateHistoryStore.schemaVersion`.
struct UpdateHistoryRecord: Codable, Equatable, Identifiable {
    enum RollbackReason: String, Codable {
        case crashLoop
        case userChoice
        case installFailed
    }

    var id: UUID = UUID()
    var fromVersion: String
    var fromBuild: String
    var toVersion: String
    var toBuild: String
    var channel: String = "stable"
    var installedAt: Date
    var launchVerified: Bool = false
    var verifiedAt: Date?
    var rolledBack: Bool = false
    var rollbackReason: RollbackReason?

    private enum CodingKeys: String, CodingKey {
        case id, fromVersion, fromBuild, toVersion, toBuild, channel
        case installedAt, launchVerified, verifiedAt, rolledBack, rollbackReason
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        fromVersion = try c.decode(String.self, forKey: .fromVersion)
        fromBuild = try c.decodeIfPresent(String.self, forKey: .fromBuild) ?? ""
        toVersion = try c.decode(String.self, forKey: .toVersion)
        toBuild = try c.decodeIfPresent(String.self, forKey: .toBuild) ?? ""
        channel = try c.decodeIfPresent(String.self, forKey: .channel) ?? "stable"
        installedAt = try c.decode(Date.self, forKey: .installedAt)
        launchVerified = try c.decodeIfPresent(Bool.self, forKey: .launchVerified) ?? false
        verifiedAt = try c.decodeIfPresent(Date.self, forKey: .verifiedAt)
        rolledBack = try c.decodeIfPresent(Bool.self, forKey: .rolledBack) ?? false
        rollbackReason = try c.decodeIfPresent(RollbackReason.self, forKey: .rollbackReason)
    }

    init(
        id: UUID = UUID(),
        fromVersion: String,
        fromBuild: String,
        toVersion: String,
        toBuild: String,
        channel: String = "stable",
        installedAt: Date,
        launchVerified: Bool = false,
        verifiedAt: Date? = nil,
        rolledBack: Bool = false,
        rollbackReason: RollbackReason? = nil
    ) {
        self.id = id
        self.fromVersion = fromVersion
        self.fromBuild = fromBuild
        self.toVersion = toVersion
        self.toBuild = toBuild
        self.channel = channel
        self.installedAt = installedAt
        self.launchVerified = launchVerified
        self.verifiedAt = verifiedAt
        self.rolledBack = rolledBack
        self.rollbackReason = rollbackReason
    }
}

/// Append-only-ish ledger of update installs, capped to the most recent `maxRecords`.
///
/// Persisted as `update-history.json` beside the other update stores under Application
/// Support. All mutations re-serialize the (tiny) file atomically, matching `RecentsStore`.
final class UpdateHistoryStore {
    static let schemaVersion = 1
    static let maxRecords = 10

    private struct Payload: Codable {
        var schemaVersion: Int
        var records: [UpdateHistoryRecord]
    }

    private let fileURL: URL
    private(set) var records: [UpdateHistoryRecord]

    /// - Parameter directory: where `update-history.json` lives. Defaults to the shared
    ///   Orifold Application Support directory; tests pass a temp directory.
    init(directory: URL = UpdateStorePaths.supportDirectory) {
        fileURL = directory.appendingPathComponent("update-history.json")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        records = Self.load(from: fileURL)
    }

    /// The most recent record, if any — used by launch verification to find the install
    /// it should be confirming.
    var latest: UpdateHistoryRecord? { records.last }

    @discardableResult
    func record(_ record: UpdateHistoryRecord) -> UpdateHistoryRecord {
        records.append(record)
        if records.count > Self.maxRecords {
            records.removeFirst(records.count - Self.maxRecords)
        }
        save()
        return record
    }

    /// Mutates the record with `id` in place (e.g. to flip `launchVerified`), then saves.
    func update(id: UUID, _ mutate: (inout UpdateHistoryRecord) -> Void) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        mutate(&records[index])
        save()
    }

    // MARK: - Persistence

    private static func load(from url: URL) -> [UpdateHistoryRecord] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(Payload.self, from: data))?.records ?? []
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(Payload(schemaVersion: Self.schemaVersion, records: records)) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
