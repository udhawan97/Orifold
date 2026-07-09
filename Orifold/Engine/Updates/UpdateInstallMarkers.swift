import Foundation

/// One document to reopen after an update relaunch. Identified primarily by a
/// security-scoped bookmark (survives a move/rename); `path` is the fallback.
struct ReopenDocument: Codable, Equatable {
    var path: String
    var bookmarkData: Data?
    /// 0-based page the user was viewing, restored via the existing resume path.
    var pageIndex: Int?
    var displayName: String

    private enum CodingKeys: String, CodingKey { case path, bookmarkData, pageIndex, displayName }

    init(path: String, bookmarkData: Data?, pageIndex: Int?, displayName: String) {
        self.path = path
        self.bookmarkData = bookmarkData
        self.pageIndex = pageIndex
        self.displayName = displayName
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        path = try c.decode(String.self, forKey: .path)
        bookmarkData = try c.decodeIfPresent(Data.self, forKey: .bookmarkData)
        pageIndex = try c.decodeIfPresent(Int.self, forKey: .pageIndex)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName) ?? ""
    }
}

/// Written just before an update install quits the app; consumed exactly once on the next
/// launch to reopen the documents the user had on screen. Additive-decodable so a rolled-back
/// older app can still read (and safely ignore) a newer app's manifest.
struct UpdateReopenManifest: Codable, Equatable {
    var schemaVersion: Int = 1
    var fromVersion: String
    var toVersion: String
    var savedAt: Date
    var documents: [ReopenDocument]

    private enum CodingKeys: String, CodingKey { case schemaVersion, fromVersion, toVersion, savedAt, documents }

    init(fromVersion: String, toVersion: String, savedAt: Date, documents: [ReopenDocument]) {
        self.fromVersion = fromVersion
        self.toVersion = toVersion
        self.savedAt = savedAt
        self.documents = documents
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        fromVersion = try c.decodeIfPresent(String.self, forKey: .fromVersion) ?? ""
        toVersion = try c.decode(String.self, forKey: .toVersion)
        savedAt = try c.decodeIfPresent(Date.self, forKey: .savedAt) ?? Date(timeIntervalSince1970: 0)
        documents = try c.decodeIfPresent([ReopenDocument].self, forKey: .documents) ?? []
    }
}

/// Records that an install was handed off, so the next launch can tell success (running the
/// new version) from failure/abandonment (still the old version).
struct InstallAttempt: Codable, Equatable {
    var schemaVersion: Int = 1
    var fromVersion: String
    var toVersion: String
    var dmgPath: String
    var dmgSHA256: String
    var startedAt: Date

    private enum CodingKeys: String, CodingKey { case schemaVersion, fromVersion, toVersion, dmgPath, dmgSHA256, startedAt }

    init(fromVersion: String, toVersion: String, dmgPath: String, dmgSHA256: String, startedAt: Date) {
        self.fromVersion = fromVersion
        self.toVersion = toVersion
        self.dmgPath = dmgPath
        self.dmgSHA256 = dmgSHA256
        self.startedAt = startedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        fromVersion = try c.decode(String.self, forKey: .fromVersion)
        toVersion = try c.decode(String.self, forKey: .toVersion)
        dmgPath = try c.decodeIfPresent(String.self, forKey: .dmgPath) ?? ""
        dmgSHA256 = try c.decodeIfPresent(String.self, forKey: .dmgSHA256) ?? ""
        startedAt = try c.decodeIfPresent(Date.self, forKey: .startedAt) ?? Date(timeIntervalSince1970: 0)
    }
}

/// Persists the two one-shot install markers as JSON beside `recents.json` in the support
/// root — NOT in `UpdaterCache/`, so the artifact cleaner (which only touches cache/rollback)
/// can never sweep a pending marker before the next launch reads it.
struct UpdateInstallMarkerStore {
    private let reopenURL: URL
    private let attemptURL: URL

    init(directory: URL = UpdateStorePaths.supportDirectory) {
        reopenURL = directory.appendingPathComponent("reopen-manifest.json")
        attemptURL = directory.appendingPathComponent("install-attempt.json")
    }

    // MARK: - Reopen manifest

    func writeReopenManifest(_ manifest: UpdateReopenManifest) throws {
        try write(manifest, to: reopenURL)
    }

    func readReopenManifest() -> UpdateReopenManifest? {
        read(UpdateReopenManifest.self, from: reopenURL)
    }

    /// Reads and deletes in one shot — reopen must happen at most once per install.
    func consumeReopenManifest() -> UpdateReopenManifest? {
        let manifest = readReopenManifest()
        clearReopenManifest()
        return manifest
    }

    func clearReopenManifest() { try? FileManager.default.removeItem(at: reopenURL) }

    // MARK: - Install attempt

    func writeAttempt(_ attempt: InstallAttempt) throws {
        try write(attempt, to: attemptURL)
    }

    func readAttempt() -> InstallAttempt? {
        read(InstallAttempt.self, from: attemptURL)
    }

    func clearAttempt() { try? FileManager.default.removeItem(at: attemptURL) }

    // MARK: - Codable helpers

    private func write<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(value).write(to: url, options: .atomic)
    }

    private func read<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(type, from: data)
    }
}
