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
    /// room to indent further. This is a *display* bound and nothing else — see
    /// `maximumTraversalDepth` for the one that bounds the walk itself.
    static let maximumDepth = 8

    /// Recursion frames one walk may consume, counting every level descended including
    /// the ones promotion hides.
    ///
    /// Neither other cap can do this job. Promotion re-descends at the *same* display
    /// depth on purpose, so `maximumDepth` freezes along a run of unresolvable nodes; and
    /// an unresolvable node emits nothing, so `maximumNodeCount` cannot advance either.
    /// Both measure what the walk produces, and this branch produces nothing — so without
    /// this cap a chain of blank-labelled or dead-destination nodes is walked all the way
    /// down: measured at ~0.9s for a 10,000-level chain, against ~0.2ms with the cap.
    /// `nodes(in:)` is reached from `tableOfContents`, a computed property read during a
    /// SwiftUI `body` pass, so that cost lands on the main thread on *every* render — a
    /// visible hang, with stack exhaustion the limit case past it.
    ///
    /// PDFKit truncates genuine `/Outlines` *cycles* on its own — it will not re-enter a
    /// node already on the path it is materialising, so a cycle arrives here as a short
    /// finite chain. But it passes deep finite nesting through intact, tens of thousands
    /// of levels deep. So a cycle is not the threat this cap answers; unbounded depth is,
    /// and this makes that guarantee ours rather than borrowed from undocumented
    /// framework behaviour.
    ///
    /// 64 leaves the 8 display levels roughly 56 levels of promotion headroom — far more
    /// than a real file stacks — while keeping the stack cost trivial on any thread.
    static let maximumTraversalDepth = 64

    /// Child slots one walk may examine, resolved or not, across the whole tree.
    ///
    /// `maximumTraversalDepth` bounds how *deep* the walk goes; this bounds how *much* it
    /// does, which is a genuinely different failure mode. A fan-out of unresolvable
    /// siblings is one level deep and would still be iterated in full: `maximumNodeCount`
    /// counts what was emitted, and an unresolvable node emits nothing.
    ///
    /// Counted before the child is materialised, so a run of nil slots spends budget too
    /// and the loop itself is bounded rather than only the nodes it yields.
    ///
    /// 10,000 is five times the emit cap. A legitimate outline cannot emit more than
    /// `maximumNodeCount`, so it has room for thousands of dead entries alongside its
    /// live ones before this is reached.
    ///
    /// Keeps this walk flat rather than linear in sibling count: measured at a steady
    /// ~3ms across 10k/20k/40k unresolvable siblings, against 4.6/14/16ms uncapped. Worth
    /// stating the honest proportion, though — for a *wide* outline the dominant cost is
    /// PDFKit materialising `outlineRoot` at all (~1.3s at 10k siblings, ~12.6s at 40k,
    /// quadratic, then cached), which nothing here can touch. This bounds our share of
    /// the work, not that.
    static let maximumTraversalSteps = 10_000

    /// Upper bound on emitted nodes: how long the table of contents may get. It also ends
    /// the walk once enough has been collected — but it can only advance when something
    /// resolves, so `maximumTraversalSteps` is what bounds work on a tree that resolves
    /// nothing.
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

    /// A node that survived resolution, before `hasChildren` can be known — that answer
    /// depends on what the rest of the walk emits.
    private struct ResolvedNode {
        let title: String
        let depth: Int
        let localPageIndex: Int
    }

    /// What one walk accumulates. The two values travel together because both must
    /// survive across siblings and across the recursion, unlike the depths, which are
    /// per-frame; bundling them also keeps the recursive call inside SwiftLint's
    /// parameter budget.
    private struct Walk {
        var collected: [ResolvedNode] = []
        var visited = 0
    }

    /// Returns the document's bookmarks in reading order, or an empty array when it has
    /// none. Never throws: an unreadable bookmark is dropped, not surfaced as an error,
    /// because a broken outline must degrade to "no table of contents" rather than block
    /// navigation.
    static func nodes(in document: PDFDocument) -> [OutlineNode] {
        guard let root = document.outlineRoot else { return [] }

        var walk = Walk()
        collect(children: root, displayDepth: 0, traversalDepth: 0, in: document, into: &walk)
        let collected = walk.collected

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

    /// `displayDepth` is where emitted rows land; `traversalDepth` is how far the
    /// recursion has actually gone. They are deliberately separate values: promotion
    /// advances only the second, and conflating them is what leaves the walk unbounded.
    private static func collect(
        children parent: PDFOutline,
        displayDepth: Int,
        traversalDepth: Int,
        in document: PDFDocument,
        into walk: inout Walk
    ) {
        guard displayDepth < maximumDepth, traversalDepth < maximumTraversalDepth else { return }

        for index in 0..<parent.numberOfChildren {
            guard walk.collected.count < maximumNodeCount,
                  walk.visited < maximumTraversalSteps else { return }
            walk.visited += 1
            guard let child = parent.child(at: index) else { continue }

            if let resolved = resolve(child, in: document) {
                walk.collected.append(ResolvedNode(
                    title: resolved.title,
                    depth: displayDepth,
                    localPageIndex: resolved.page
                ))
                collect(
                    children: child,
                    displayDepth: displayDepth + 1,
                    traversalDepth: traversalDepth + 1,
                    in: document,
                    into: &walk
                )
            } else {
                // The node itself is unusable, but its children may still be good.
                // Promote them to this level rather than dropping the subtree or
                // leaving them indented under a parent that was never drawn.
                //
                // `displayDepth` must NOT advance — that is what "promote" means — so
                // `traversalDepth` is the only thing standing between a malformed file
                // and unbounded recursion here. Advance it.
                collect(
                    children: child,
                    displayDepth: displayDepth,
                    traversalDepth: traversalDepth + 1,
                    in: document,
                    into: &walk
                )
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
