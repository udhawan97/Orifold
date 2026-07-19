import Foundation
import PDFKit

/// Reads a PDF's embedded bookmark tree (`/Outlines`) as a flat, display-ready list.
///
/// Resolution happens at READ time against the document handed in — never against a
/// stored page index. `PDFDestination` holds a `PDFPage` *reference*, not a page
/// number, so when a page moves the destination follows the object and re-resolves to
/// the new index for free; when a page is deleted its destination is left pointing at a
/// page the document no longer contains, which surfaces as `NSNotFound`. That is why
/// this type keeps no state and the workspace persists nothing: PDFKit already
/// maintains the invariant a cached index would have to hand-maintain.
///
/// Deliberately never touches `PageRef.sourcePageIndex` — that value is renormalized to
/// a member's current local layout after every structural op, so it describes today's
/// ordering rather than the imported bytes.
enum PDFOutlineReader {

    /// Levels of nesting emitted. Beyond this the tree is truncated: the popover has no
    /// room to indent further, and a cap bounds traversal of a malformed or cyclic
    /// `/Outlines` graph, which is a real corruption mode in the wild.
    static let maximumDepth = 8

    /// Upper bound on emitted nodes. Checked as a traversal guard rather than only a
    /// collection guard, so a pathological tree cannot burn time walking branches whose
    /// results would be discarded.
    static let maximumNodeCount = 2000

    struct OutlineNode: Equatable {
        /// Trimmed bookmark label. Never blank — blank entries are dropped.
        let title: String
        /// 0 for a top-level bookmark.
        let depth: Int
        /// Index into the document handed to `nodes(in:)`, resolved at read time.
        let localPageIndex: Int
        /// True only when this node has children that were actually emitted, so a
        /// disclosure control never expands to nothing.
        let hasChildren: Bool

        /// Same node against a document where this one's pages start at `offset`.
        /// Used when concatenating members for export, where each member's
        /// bookmarks are indexed within that member but land in one page list.
        func offsetting(by offset: Int) -> OutlineNode {
            OutlineNode(
                title: title,
                depth: depth,
                localPageIndex: localPageIndex + offset,
                hasChildren: hasChildren
            )
        }
    }

    /// Returns the document's bookmarks in reading order, or an empty array when it has
    /// none. Never throws: an unreadable bookmark is dropped, not surfaced as an error,
    /// because a broken outline must degrade to "no table of contents" rather than block
    /// navigation.
    /// A node that survived resolution, before `hasChildren` can be known — that answer
    /// depends on what the rest of the walk emits.
    private struct ResolvedNode {
        let title: String
        let depth: Int
        let localPageIndex: Int
    }

    static func nodes(in document: PDFDocument) -> [OutlineNode] {
        guard let root = document.outlineRoot else { return [] }

        var collected: [ResolvedNode] = []
        collect(children: root, depth: 0, in: document, into: &collected)

        // `hasChildren` is derived from what was emitted rather than from the source
        // tree: a node whose only child was dropped (blank label, deleted page) or cut
        // by the depth cap must not advertise children it cannot show.
        return collected.enumerated().map { index, entry in
            let nextDepth = index + 1 < collected.count ? collected[index + 1].depth : entry.depth
            return OutlineNode(
                title: entry.title,
                depth: entry.depth,
                localPageIndex: entry.localPageIndex,
                hasChildren: nextDepth > entry.depth
            )
        }
    }

    private static func collect(
        children parent: PDFOutline,
        depth: Int,
        in document: PDFDocument,
        into collected: inout [ResolvedNode]
    ) {
        guard depth < maximumDepth else { return }

        for index in 0..<parent.numberOfChildren {
            guard collected.count < maximumNodeCount else { return }
            guard let child = parent.child(at: index) else { continue }

            if let resolved = resolve(child, in: document) {
                collected.append(ResolvedNode(
                    title: resolved.title,
                    depth: depth,
                    localPageIndex: resolved.page
                ))
                collect(children: child, depth: depth + 1, in: document, into: &collected)
            } else {
                // The node itself is unusable, but its children may still be good.
                // Promote them to this level rather than dropping the subtree or
                // leaving them indented under a parent that was never drawn.
                collect(children: child, depth: depth, in: document, into: &collected)
            }
        }
    }

    private static func resolve(
        _ outline: PDFOutline,
        in document: PDFDocument
    ) -> (title: String, page: Int)? {
        let title = (outline.label ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        guard let page = outline.destination?.page else { return nil }

        let pageIndex = document.index(for: page)
        guard pageIndex != NSNotFound else { return nil }

        return (title: title, page: pageIndex)
    }
}
