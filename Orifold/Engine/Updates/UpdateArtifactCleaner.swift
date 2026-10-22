import Foundation

/// Removes *only* stale updater-owned artifacts, never user data.
///
/// Safety is structural, not incidental:
/// - It operates on two explicitly-passed directories and refuses any whose last path
///   component isn't in `UpdateStorePaths.cleanerOwnedDirectoryNames` — so it can never be
///   aimed at `Recovery/` (the user's pre-update work), the Application Support root,
///   `recents.json`, or the home folder.
/// - It only ever deletes **direct children** of those directories; it never recurses
///   upward and never removes the directory itself.
/// - As defence in depth it refuses to delete anything that looks like user content
///   (`.pdf`) or the recents store even if it somehow appeared inside a cache directory.
///
/// The `Recovery/` directory is deliberately out of scope: those snapshots are the user's
/// work and are only ever removed by an explicit discard, never by cleanup.
struct UpdateArtifactCleaner {
    struct Report: Equatable {
        var removed: [String] = []
        var freedBytes: Int64 = 0
        var skippedProtected: [String] = []
    }

    /// Updater-owned cache of downloaded/staged artifacts. Emptied of anything older than
    /// the retention window (so an in-flight download isn't nuked).
    let updaterCacheDirectory: URL
    /// Keep both the previous installed version and every unresolved helper's rescue copy.
    let rollbackDirectory: URL

    init(
        updaterCacheDirectory: URL = UpdateStorePaths.updaterCacheDirectory(),
        rollbackDirectory: URL = UpdateStorePaths.rollbackDirectory()
    ) {
        self.updaterCacheDirectory = updaterCacheDirectory
        self.rollbackDirectory = rollbackDirectory
    }

    /// Extensions that unambiguously indicate user content — never deleted by cleanup, as a
    /// backstop against a misconfiguration ever dropping user files into a cache directory.
    private static let protectedExtensions: Set<String> = ["pdf"]
    /// Filenames that must never be deleted regardless of location.
    private static let protectedNames: Set<String> = ["recents.json"]

    @discardableResult
    func clean(now: Date = Date(), retainDownloads: TimeInterval = 24 * 3600) -> Report {
        var report = Report()
        pruneUpdaterCache(now: now, retain: retainDownloads, into: &report)
        pruneRollbackArchives(into: &report)
        return report
    }

    // MARK: - Updater cache

    private func pruneUpdaterCache(now: Date, retain: TimeInterval, into report: inout Report) {
        guard isCleanerOwned(updaterCacheDirectory) else { return }
        for child in directChildren(of: updaterCacheDirectory) {
            if isProtected(child) { report.skippedProtected.append(child.lastPathComponent); continue }
            // Keep artifacts newer than the retention window so an in-progress download,
            // whose file was just written, is never removed mid-flight.
            let modified = modificationDate(of: child) ?? .distantPast
            guard now.timeIntervalSince(modified) >= retain else { continue }
            remove(child, into: &report)
        }
    }

    // MARK: - Rollback archives

    private func pruneRollbackArchives(into report: inout Report) {
        guard isCleanerOwned(rollbackDirectory),
              FileManager.default.fileExists(atPath: rollbackDirectory.path) else { return }
        do {
            try RollbackArchiveTransaction.withLock(in: rollbackDirectory) {
                let archiver = RollbackArchiver(directory: rollbackDirectory)
                // Without a usable current archive, every ZIP may be the remaining recovery copy.
                guard let keepNames = archiver.retainedArchiveNames() else { return }
                for child in directChildren(of: rollbackDirectory) {
                    guard child.pathExtension == "zip" else { continue } // staging `.partial` files are never pruned
                    if isProtected(child) { report.skippedProtected.append(child.lastPathComponent); continue }
                    if keepNames.contains(child.lastPathComponent) { continue }
                    remove(child, into: &report)
                }
            }
        } catch {
            // No valid lock means no safe rollback snapshot. Leave recovery evidence intact.
        }
    }

    // MARK: - Guards & helpers

    /// The blast-radius guard: only directories the cleaner is explicitly allowed to own.
    private func isCleanerOwned(_ dir: URL) -> Bool {
        UpdateStorePaths.cleanerOwnedDirectoryNames.contains(dir.lastPathComponent)
    }

    private func isProtected(_ url: URL) -> Bool {
        Self.protectedNames.contains(url.lastPathComponent)
            || Self.protectedExtensions.contains(url.pathExtension.lowercased())
    }

    private func directChildren(of dir: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
    }

    private func modificationDate(of url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    private func remove(_ url: URL, into report: inout Report) {
        let size = byteSize(of: url)
        do {
            try FileManager.default.removeItem(at: url)
            report.removed.append(url.lastPathComponent)
            report.freedBytes += size
        } catch {
            // A file we couldn't remove is left untouched — cleanup never fails loudly.
        }
    }

    /// Total size of a file, or the recursive size of a directory (staging dirs).
    private func byteSize(of url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
        if values?.isDirectory == true {
            let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey])
            var total: Int64 = 0
            while let child = enumerator?.nextObject() as? URL {
                total += Int64((try? child.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
            }
            return total
        }
        return Int64(values?.fileSize ?? 0)
    }
}
