import Foundation
import AppKit

/// Builds the list of documents to reopen after an update relaunch, from the app's currently
/// open documents.
///
/// Only documents backed by a file on disk are captured — an unsaved/untitled window has no
/// reference to reopen, and the install preflight has already forced any *dirty* document to
/// be saved or closed, so by install time every capturable document is clean and on disk.
/// The last-viewed page comes from `RecentsStore` (best-effort; nil just reopens at page 1).
@MainActor
enum UpdateReopenGatherer {
    /// Production entry point: gathers from the shared document controller + recents.
    static func currentDocuments() -> [ReopenDocument] {
        currentDocuments(controller: .shared, recents: .shared)
    }

    static func currentDocuments(
        controller: NSDocumentController,
        recents: RecentsStore
    ) -> [ReopenDocument] {
        controller.documents.compactMap { document in
            guard let url = document.fileURL else { return nil }
            let page = recents.entries.first { $0.path == url.path }?.lastPageOpened
            let name = document.displayName ?? url.deletingPathExtension().lastPathComponent
            return ReopenDocument(
                path: url.path,
                bookmarkData: SecurityScopedAccess.makeBookmark(for: url),
                pageIndex: page,
                displayName: name
            )
        }
    }
}
