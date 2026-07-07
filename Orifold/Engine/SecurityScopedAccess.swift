import Foundation

/// Centralizes the App Sandbox security-scoped resource lifecycle so no import/export
/// call site can forget to balance `start`/`stopAccessingSecurityScopedResource()`, and
/// so bookmark creation/resolution behaves identically everywhere (recents, exports,
/// folder imports). Requires `com.apple.security.files.bookmarks.app-scope` in the
/// app's entitlements — without it, `.withSecurityScope` bookmark creation throws and
/// resolution silently degrades to a plain path URL with no persisted sandbox grant.
enum SecurityScopedAccess {
    /// Folders granted via the "Grant Folder Access" import-recovery action, held open
    /// for the remainder of the app session (never explicitly stopped — macOS reclaims
    /// the grant at process exit) so files inside them stay readable after the user
    /// picks the folder once, rather than needing to reselect on every read.
    @MainActor private static var heldFolderScopes: [URL] = []

    /// Starts a folder's security scope and keeps it open for the app's lifetime.
    @MainActor
    @discardableResult
    static func grantFolderAccessForSession(_ folderURL: URL) -> Bool {
        let started = folderURL.startAccessingSecurityScopedResource()
        if started {
            heldFolderScopes.append(folderURL)
        }
        return started
    }

    struct ResolvedBookmark {
        var url: URL
        var wasStale: Bool
        /// Present only when `wasStale` and re-bookmarking the resolved URL succeeded.
        var refreshedBookmark: Data?
    }

    /// Runs `body` with the URL's security scope active for the duration of the call,
    /// always balancing the stop even if `body` throws. If the URL isn't actually
    /// security-scoped (e.g. a path already inside the sandbox container), `start…`
    /// simply returns `false` and `body` still runs — that's a normal, unscoped read,
    /// not a failure.
    static func withAccess<T>(to url: URL, _ body: (URL) throws -> T) rethrows -> T {
        let didStart = url.startAccessingSecurityScopedResource()
        defer { if didStart { url.stopAccessingSecurityScopedResource() } }
        return try body(url)
    }

    static func withAccessAsync<T>(to url: URL, _ body: (URL) async throws -> T) async rethrows -> T {
        let didStart = url.startAccessingSecurityScopedResource()
        defer { if didStart { url.stopAccessingSecurityScopedResource() } }
        return try await body(url)
    }

    /// Creates a durable, app-scope security-scoped bookmark for `url`. Returns `nil`
    /// (and logs) if bookmark creation fails — callers should fall back to the plain
    /// path but must expect that fallback to not survive a relaunch under sandbox.
    static func makeBookmark(for url: URL) -> Data? {
        do {
            return try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        } catch {
            ImportLog.log(event: .bookmarkCreateFailed, error: error)
            return nil
        }
    }

    /// Resolves a previously-created bookmark, reporting staleness. When stale, attempts
    /// to re-bookmark the resolved URL immediately so callers can self-heal storage.
    static func resolve(_ bookmarkData: Data) -> ResolvedBookmark? {
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return nil
        }
        guard isStale else {
            return ResolvedBookmark(url: url, wasStale: false, refreshedBookmark: nil)
        }
        let refreshed = makeBookmark(for: url)
        return ResolvedBookmark(url: url, wasStale: true, refreshedBookmark: refreshed)
    }
}
