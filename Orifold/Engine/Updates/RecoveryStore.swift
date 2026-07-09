import Foundation

/// Sidecar describing one recovered workspace snapshot. The payload it points at is an
/// opaque blob (the bytes `WorkspaceDocument.snapshot()` serializes) — this store never
/// interprets it, which keeps the store free of any PDF dependency and unit-testable.
struct RecoveryMetadata: Codable, Equatable, Identifiable {
    enum Reason: String, Codable {
        /// Captured just before an update install, as a belt-and-suspenders checkpoint.
        case preUpdate
        /// Reconstructed after an unclean shutdown was detected at launch.
        case crashRecovery
    }

    var id: UUID
    /// Original file path, if the workspace was backed by one on disk. Untouched by
    /// recovery — the recovered copy is always a separate file the user opts to keep.
    var sourceURLPath: String?
    /// Security-scoped bookmark to the original, preferred over the raw path for reopen.
    var sourceBookmark: Data?
    var displayName: String
    var capturedAt: Date
    var reason: Reason
    var appVersion: String
    /// Whether the workspace had unsaved changes when captured — drives whether recovery
    /// is even worth surfacing versus a pristine on-disk file.
    var dirtyAtCapture: Bool
    var payloadFileName: String

    private enum CodingKeys: String, CodingKey {
        case id, sourceURLPath, sourceBookmark, displayName, capturedAt
        case reason, appVersion, dirtyAtCapture, payloadFileName
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        sourceURLPath = try c.decodeIfPresent(String.self, forKey: .sourceURLPath)
        sourceBookmark = try c.decodeIfPresent(Data.self, forKey: .sourceBookmark)
        displayName = try c.decode(String.self, forKey: .displayName)
        capturedAt = try c.decode(Date.self, forKey: .capturedAt)
        reason = try c.decodeIfPresent(Reason.self, forKey: .reason) ?? .preUpdate
        appVersion = try c.decodeIfPresent(String.self, forKey: .appVersion) ?? ""
        dirtyAtCapture = try c.decodeIfPresent(Bool.self, forKey: .dirtyAtCapture) ?? true
        payloadFileName = try c.decode(String.self, forKey: .payloadFileName)
    }

    init(
        id: UUID,
        sourceURLPath: String?,
        sourceBookmark: Data?,
        displayName: String,
        capturedAt: Date,
        reason: Reason,
        appVersion: String,
        dirtyAtCapture: Bool,
        payloadFileName: String
    ) {
        self.id = id
        self.sourceURLPath = sourceURLPath
        self.sourceBookmark = sourceBookmark
        self.displayName = displayName
        self.capturedAt = capturedAt
        self.reason = reason
        self.appVersion = appVersion
        self.dirtyAtCapture = dirtyAtCapture
        self.payloadFileName = payloadFileName
    }
}

/// Stores and lists pre-update / crash recovery snapshots under Application Support.
///
/// Each snapshot is two atomic writes: the opaque payload (`<uuid>.orifold-recovery`) and
/// its JSON sidecar (`<uuid>.json`). Writing payload-then-sidecar means a crash between
/// the two leaves an orphan payload with no sidecar, which `list()` simply ignores — a
/// partial capture never surfaces as a half-broken recovery card.
final class RecoveryStore {
    static let payloadExtension = "orifold-recovery"

    struct Entry: Equatable, Identifiable {
        var metadata: RecoveryMetadata
        var payloadURL: URL
        var id: UUID { metadata.id }
    }

    private let directory: URL

    init(directory: URL = UpdateStorePaths.recoveryDirectory()) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Persists a snapshot. Returns the sidecar that now describes it.
    @discardableResult
    func saveCheckpoint(
        payload: Data,
        sourceURLPath: String?,
        sourceBookmark: Data?,
        displayName: String,
        reason: RecoveryMetadata.Reason,
        appVersion: String,
        dirtyAtCapture: Bool,
        id: UUID = UUID(),
        capturedAt: Date = Date()
    ) throws -> RecoveryMetadata {
        let payloadName = "\(id.uuidString).\(Self.payloadExtension)"
        let payloadURL = directory.appendingPathComponent(payloadName)
        try payload.write(to: payloadURL, options: .atomic)

        let metadata = RecoveryMetadata(
            id: id,
            sourceURLPath: sourceURLPath,
            sourceBookmark: sourceBookmark,
            displayName: displayName,
            capturedAt: capturedAt,
            reason: reason,
            appVersion: appVersion,
            dirtyAtCapture: dirtyAtCapture,
            payloadFileName: payloadName
        )
        try writeSidecar(metadata)
        return metadata
    }

    /// All recoverable snapshots, newest first. Sidecars without a matching payload (a
    /// torn write) are skipped.
    func list() -> [Entry] {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var entries: [Entry] = []
        for url in urls where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url),
                  let metadata = try? decoder.decode(RecoveryMetadata.self, from: data) else { continue }
            let payloadURL = directory.appendingPathComponent(metadata.payloadFileName)
            guard fm.fileExists(atPath: payloadURL.path) else { continue }
            entries.append(Entry(metadata: metadata, payloadURL: payloadURL))
        }
        return entries.sorted { $0.metadata.capturedAt > $1.metadata.capturedAt }
    }

    func payloadData(for metadata: RecoveryMetadata) throws -> Data {
        try Data(contentsOf: directory.appendingPathComponent(metadata.payloadFileName))
    }

    func discard(id: UUID) {
        let fm = FileManager.default
        let sidecar = directory.appendingPathComponent("\(id.uuidString).json")
        if let data = try? Data(contentsOf: sidecar),
           let metadata = try? decodeSidecar(data) {
            try? fm.removeItem(at: directory.appendingPathComponent(metadata.payloadFileName))
        }
        try? fm.removeItem(at: sidecar)
    }

    func discardAll() {
        for entry in list() { discard(id: entry.id) }
    }

    // MARK: - Private

    private func writeSidecar(_ metadata: RecoveryMetadata) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let url = directory.appendingPathComponent("\(metadata.id.uuidString).json")
        try encoder.encode(metadata).write(to: url, options: .atomic)
    }

    private func decodeSidecar(_ data: Data) throws -> RecoveryMetadata {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(RecoveryMetadata.self, from: data)
    }
}
