import CryptoKit
import Foundation

/// Per-machine record of the SHA-256 of the exact bytes Orifold last wrote for each
/// workspace, kept in a small JSON sidecar. Its sole job is to answer one question at load
/// time: *did something other than Orifold change this file since we saved it?* When the
/// on-disk hash no longer matches what we recorded, the embedded editable workspace (edit
/// operations, pristine bases) is stale relative to the visible content, and the loader
/// must let the visible content win rather than resurrect edits over a file a third-party
/// tool rewrote.
///
/// This is intentionally a sidecar, not embedded metadata: the fingerprint has to describe
/// the *whole file including its own embedded metadata*, so it cannot live inside the file
/// it measures. The trade-off is that the signal is per-machine — a file opened on a
/// different machine (or after the sidecar is cleared) simply has "no fingerprint", which
/// falls back to the legacy trust-the-embedded-state behavior. That is the safe direction:
/// we only ever *discard* edits on a positive mismatch, never on absence.
final class WorkspaceFingerprintStore {
    static let shared = WorkspaceFingerprintStore()

    private let fileURL: URL
    private let maxEntries: Int
    private let lock = NSLock()
    /// id → hash. `order` tracks access recency (least-recent first) for LRU eviction.
    private var hashes: [String: String] = [:]
    private var order: [String] = []
    private var loaded = false

    /// - Parameters:
    ///   - directory: where the sidecar lives. Defaults to Application Support/Orifold.
    ///     Injectable so tests never touch the real user directory.
    ///   - maxEntries: LRU cap (default 200).
    init(directory: URL? = nil, maxEntries: Int = 200) {
        let base = directory ?? Self.defaultDirectory()
        self.fileURL = base.appendingPathComponent("workspace-fingerprints.json")
        self.maxEntries = max(1, maxEntries)
    }

    private static func defaultDirectory() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return support.appendingPathComponent("Orifold", isDirectory: true)
    }

    /// SHA-256 hex digest of arbitrary bytes — the canonical fingerprint of a saved file.
    static func hash(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// The recorded hash for a workspace, or nil if this machine has never saved it (or the
    /// entry was evicted). Nil MUST be treated as "unknown", never as "changed".
    func fingerprint(for workspaceID: UUID) -> String? {
        lock.lock(); defer { lock.unlock() }
        loadIfNeeded()
        return hashes[workspaceID.uuidString]
    }

    /// Record the hash of the bytes just written for `workspaceID`, promoting it to
    /// most-recently-used and evicting the oldest entries past the cap. Write-through to disk.
    func record(hash: String, for workspaceID: UUID) {
        lock.lock(); defer { lock.unlock() }
        loadIfNeeded()
        let key = workspaceID.uuidString
        hashes[key] = hash
        order.removeAll { $0 == key }
        order.append(key)
        while order.count > maxEntries, let evict = order.first {
            order.removeFirst()
            hashes.removeValue(forKey: evict)
        }
        persist()
    }

    /// Convenience: hash `data` and record it for `workspaceID`.
    func record(data: Data, for workspaceID: UUID) {
        record(hash: Self.hash(of: data), for: workspaceID)
    }

    // MARK: - Persistence

    private struct Payload: Codable {
        var order: [String]
        var hashes: [String: String]
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let data = try? Data(contentsOf: fileURL),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return }
        hashes = payload.hashes
        // Keep only ids that still have a hash, in recorded recency order.
        order = payload.order.filter { hashes[$0] != nil }
        // Any hash without an order entry (older/hand-edited file) goes to the front (oldest).
        let missing = hashes.keys.filter { !order.contains($0) }
        order.insert(contentsOf: missing, at: 0)
    }

    private func persist() {
        let payload = Payload(order: order, hashes: hashes)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}
