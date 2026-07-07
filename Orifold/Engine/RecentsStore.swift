import AppKit
import Observation
import PDFKit

/// Backs the "Recently Viewed Files" section on the empty-state screen.
///
/// Metadata lives in a small JSON file under Application Support; thumbnails are
/// cached as separate PNGs alongside it. Both are local-first — nothing here ever
/// leaves the machine. Reads happen once at launch (off the main thread) and every
/// mutation re-serializes the (tiny, ≤12-entry) JSON atomically.
@MainActor @Observable final class RecentsStore {
    static let shared = RecentsStore()

    private(set) var entries: [RecentFileEntry] = []

    static let maxEntries = 12
    static let defaultVisibleCount = 4
    /// Thumbnails are rendered at 2× the card's display size (140×187pt @1x card),
    /// per the plan's "never store full-page renders" guidance.
    static let thumbnailPixelSize = CGSize(width: 280, height: 374)

    private let storeURL: URL
    private let thumbnailDirectory: URL

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let root = support.appendingPathComponent("Orifold", isDirectory: true)
        storeURL = root.appendingPathComponent("recents.json")
        thumbnailDirectory = root.appendingPathComponent("RecentThumbnails", isDirectory: true)

        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: thumbnailDirectory, withIntermediateDirectories: true)

        entries = Self.load(from: storeURL)
    }

    // MARK: - Recording

    /// Called when a document with an on-disk file becomes the active window content
    /// (i.e. the workspace stopped being empty). Inserts or bumps the entry without
    /// touching thumbnail/page data — that's filled in by `recordVisit` at close time.
    func recordOpen(url: URL) {
        upsert(url: url) { entry in
            entry.lastOpened = Date()
        }
        trimAndSave()
    }

    /// Called when a workspace window is about to go away (or the document is saved),
    /// capturing the last-viewed page and (re)generating its thumbnail if needed.
    func recordVisit(url: URL, pageCount: Int, currentPage: Int, combinedPDF: PDFDocument?) {
        upsert(url: url) { entry in
            entry.lastOpened = Date()
            entry.pageCount = pageCount
            entry.lastPageOpened = currentPage
        }
        trimAndSave()

        guard let index = entries.firstIndex(where: { $0.path == url.path }) else { return }
        guard !entries[index].thumbnailFailed else { return }

        let key = entries[index].thumbnailCacheKey ?? UUID().uuidString
        let pageIndex = max(0, currentPage)
        guard let pdf = combinedPDF, let page = pdf.page(at: pageIndex) ?? pdf.page(at: 0) else {
            markThumbnailFailed(path: url.path)
            return
        }

        let destination = thumbnailDirectory.appendingPathComponent("\(key).png")
        let image = page.thumbnail(of: Self.thumbnailPixelSize, for: .mediaBox)
        guard let data = Self.pngData(for: image) else {
            markThumbnailFailed(path: url.path)
            return
        }

        do {
            try data.write(to: destination, options: .atomic)
            entries[index].thumbnailCacheKey = key
            entries[index].thumbnailFailed = false
            save()
        } catch {
            markThumbnailFailed(path: url.path)
        }
    }

    private func markThumbnailFailed(path: String) {
        guard let idx = entries.firstIndex(where: { $0.path == path }) else { return }
        entries[idx].thumbnailFailed = true
        save()
    }

    // MARK: - Removal

    func remove(id: UUID) {
        guard let entry = entries.first(where: { $0.id == id }) else { return }
        if let key = entry.thumbnailCacheKey {
            try? FileManager.default.removeItem(at: thumbnailDirectory.appendingPathComponent("\(key).png"))
        }
        entries.removeAll { $0.id == id }
        save()
    }

    func clear() {
        for entry in entries {
            if let key = entry.thumbnailCacheKey {
                try? FileManager.default.removeItem(at: thumbnailDirectory.appendingPathComponent("\(key).png"))
            }
        }
        entries.removeAll()
        save()
    }

    // MARK: - Resolution

    /// Resolves the entry's URL, preferring the security-scoped bookmark (which
    /// survives a move/rename) over the raw path. Self-heals `path`/`bookmarkData`
    /// in place when the bookmark resolves to a different location or goes stale.
    /// The returned URL's security scope is NOT held open — callers that actually
    /// read/open the file must bracket it themselves with `SecurityScopedAccess`
    /// (see `EmptyStateView.openRecentFile`, which holds the scope across the
    /// asynchronous `NSDocumentController.openDocument` completion).
    func resolvedURL(for entry: RecentFileEntry) -> URL? {
        if let bookmarkData = entry.bookmarkData {
            if let resolved = SecurityScopedAccess.resolve(bookmarkData) {
                if resolved.wasStale, let refreshed = resolved.refreshedBookmark {
                    updateBookmark(id: entry.id, path: resolved.url.path, bookmarkData: refreshed)
                } else if resolved.url.path != entry.path {
                    updateBookmark(id: entry.id, path: resolved.url.path, bookmarkData: bookmarkData)
                }
                return resolved.url
            }
            ImportLog.log(event: .bookmarkResolveFailed)
        }
        return FileManager.default.fileExists(atPath: entry.path) ? entry.url : nil
    }

    /// True only when the file both exists AND the sandbox can actually read it —
    /// `fileExists` alone can't tell a permission-denied file from a healthy one, which
    /// is why stale bookmarks previously showed as "available" right up until the open
    /// attempt failed.
    func isAvailable(_ entry: RecentFileEntry) -> Bool {
        guard let url = resolvedURL(for: entry) else { return false }
        return SecurityScopedAccess.withAccess(to: url) {
            FileManager.default.isReadableFile(atPath: $0.path)
        }
    }

    func thumbnailImage(for entry: RecentFileEntry) -> NSImage? {
        guard let key = entry.thumbnailCacheKey else { return nil }
        let url = thumbnailDirectory.appendingPathComponent("\(key).png")
        return NSImage(contentsOf: url)
    }

    func revealInFinder(_ entry: RecentFileEntry) {
        guard let url = resolvedURL(for: entry) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: - Private helpers

    private func upsert(url: URL, mutate: (inout RecentFileEntry) -> Void) {
        if let index = entries.firstIndex(where: { $0.path == url.path }) {
            mutate(&entries[index])
        } else {
            var entry = RecentFileEntry(
                id: UUID(),
                bookmarkData: SecurityScopedAccess.makeBookmark(for: url),
                path: url.path,
                displayName: url.deletingPathExtension().lastPathComponent,
                lastOpened: Date(),
                pageCount: nil,
                lastPageOpened: nil,
                thumbnailCacheKey: nil,
                thumbnailFailed: false
            )
            mutate(&entry)
            entries.insert(entry, at: 0)
        }
    }

    private func updateBookmark(id: UUID, path: String, bookmarkData: Data) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].path = path
        entries[index].bookmarkData = bookmarkData
        save()
    }

    private func trimAndSave() {
        entries.sort { $0.lastOpened > $1.lastOpened }
        if entries.count > Self.maxEntries {
            let overflow = entries[Self.maxEntries...]
            for entry in overflow {
                if let key = entry.thumbnailCacheKey {
                    try? FileManager.default.removeItem(at: thumbnailDirectory.appendingPathComponent("\(key).png"))
                }
            }
            entries.removeLast(entries.count - Self.maxEntries)
        }
        save()
    }

    private func save() {
        let snapshot = entries
        let url = storeURL
        Task.detached(priority: .utility) {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    private static func load(from url: URL) -> [RecentFileEntry] {
        guard let data = FileManager.default.contents(atPath: url.path),
              let decoded = try? JSONDecoder().decode([RecentFileEntry].self, from: data) else { return [] }
        return decoded
    }

    private static func pngData(for image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
