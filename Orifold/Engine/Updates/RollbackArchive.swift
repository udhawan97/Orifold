import Foundation
import Crypto

/// Describes the single archived previous-version bundle kept for rollback.
///
/// The archive itself is a zip of the `.app` that was running *before* the current
/// update was installed. Restoring it is not done in-process — a sandboxed app can't
/// replace its own bundle — so restore hands this manifest to a trusted unsandboxed recovery
/// command, which re-verifies `sha256` before swapping.
struct RollbackManifest: Codable, Equatable, Sendable {
    var version: String
    var build: String
    var sha256: String
    var archivedAt: Date
    /// File name of the archive within the rollback directory (not an absolute path, so
    /// the manifest stays valid if the container is relocated).
    var archiveFileName: String
    /// Exact installed bundle path this archive can restore. Older manifests omit this and are
    /// intentionally not eligible for automatic recovery.
    var targetBundlePath: String? = nil
    /// Publisher identity captured from the archived trusted build. `nil` means ad-hoc/legacy
    /// and is never accepted by the production automatic restore hand-off.
    var bundleIdentifier: String? = nil
    var teamIdentifier: String? = nil
}

/// Keeps exactly one previous-version archive so a bad update can be reverted, and owns
/// the integrity checks that make that revert safe.
///
/// The hashing and manifest round-trip here are pure and unit-tested. Creating the zip
/// uses `ditto` and is exercised by `swift test` (which runs unsandboxed); whether the
/// *shipping sandboxed app* may spawn `ditto` in-process is a Phase-0 spike question — if
/// it can't, archiving moves into the installer script alongside restore.
struct RollbackArchiver {
    enum ArchiveError: Error, Equatable {
        case dittoFailed(Int32)
        case archiveMissing
        case hashMismatch
    }

    let directory: URL

    init(directory: URL = UpdateStorePaths.rollbackDirectory()) {
        self.directory = directory
    }

    private var manifestURL: URL { directory.appendingPathComponent("rollback-manifest.json") }

    /// Streaming SHA-256 of a file, lowercase hex — the same digest form the release
    /// pipeline's `shasum -a 256` emits, so a manifest hash can be checked against a
    /// published `.sha256` sidecar without reformatting.
    static func sha256(of fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = handle.readData(ofLength: 1 << 20)
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Zips `bundleURL` into the rollback directory, writes the manifest, and prunes any
    /// earlier archive so only the immediate predecessor is retained.
    @discardableResult
    func archive(bundleURL: URL, version: String, build: String, at date: Date = Date()) throws -> RollbackManifest {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let archiveName = "Orifold-\(version).zip"
        let archiveURL = directory.appendingPathComponent(archiveName)
        try? FileManager.default.removeItem(at: archiveURL)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--keepParent", bundleURL.path, archiveURL.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw ArchiveError.dittoFailed(process.terminationStatus) }

        let publisher = UpdatePublisherIdentity.current(for: bundleURL)
        let manifest = RollbackManifest(
            version: version,
            build: build,
            sha256: try Self.sha256(of: archiveURL),
            archivedAt: date,
            archiveFileName: archiveName,
            targetBundlePath: bundleURL.path,
            bundleIdentifier: publisher?.bundleIdentifier,
            teamIdentifier: publisher?.teamIdentifier
        )
        try writeManifest(manifest)
        pruneArchivesExcept(keeping: archiveName)
        return manifest
    }

    /// The stored manifest, if a rollback archive currently exists.
    func loadManifest() -> RollbackManifest? {
        guard let data = try? Data(contentsOf: manifestURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(RollbackManifest.self, from: data)
    }

    /// Absolute URL of the archive named by a manifest, or `nil` if the file is gone.
    func archiveURL(for manifest: RollbackManifest) -> URL? {
        let name = manifest.archiveFileName
        // Manifests are persisted input. Keep the archive lookup inside the exact
        // rollback directory and reject symlinks/non-regular files before any hash
        // or restore hand-off can follow them.
        guard !name.isEmpty,
              name != ".",
              name != "..",
              !name.contains("/"),
              !name.contains("\\"),
              name == URL(fileURLWithPath: name).lastPathComponent else { return nil }
        let url = directory.appendingPathComponent(name, isDirectory: false)
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
              values.isRegularFile == true,
              values.isSymbolicLink != true else { return nil }
        return url
    }

    /// Confirms the on-disk archive still matches the hash recorded at archive time —
    /// the check the installer repeats before swapping bundles.
    func verify(_ manifest: RollbackManifest) throws {
        guard let url = archiveURL(for: manifest) else { throw ArchiveError.archiveMissing }
        guard try Self.sha256(of: url) == manifest.sha256 else { throw ArchiveError.hashMismatch }
    }

    func writeManifest(_ manifest: RollbackManifest) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: manifestURL, options: .atomic)
    }

    private func pruneArchivesExcept(keeping name: String) {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for url in entries where url.pathExtension == "zip" && url.lastPathComponent != name {
            try? fm.removeItem(at: url)
        }
    }
}
