import Foundation
import PDFKit

/// Writes a `/Outlines` tree onto a document from the flat, depth-ordered node
/// list `PDFOutlineReader` produces. The write half of the outline round-trip.
///
/// It exists because export rebuilds the page objects. Assembly concatenates
/// members into a fresh `PDFDocument`, and the form-flatten and decoration
/// bakes re-render every page through a `CGContext`; none of those carries a
/// catalog `/Outlines` across, so a preserved outline has to be re-applied
/// after the last stage that rebuilds pages.
///
/// The round-trip is anchored on page INDEX rather than on `PDFDestination`,
/// which is the whole reason it can work at all. A destination holds a
/// `PDFPage` reference, so a destination cloned out of the source document
/// points at a page the rebuilt document does not contain and resolves to
/// `NSNotFound`. Indices survive because every rebuild stage is page-for-page.
/// That also sets the limit: imposition merges N pages onto one sheet and
/// booklet order interleaves them, so no index mapping is faithful there and
/// the tree is deliberately dropped instead (see `PDFOutlineExportTests`).
enum PDFOutlineBuilder {

    /// Applies `nodes` to `document`, replacing any existing outline.
    ///
    /// `localPageIndex` is interpreted as an index into `document`; callers
    /// spanning several source documents offset it themselves. Nodes pointing
    /// past the end are skipped rather than clamped — a bookmark aimed at a
    /// page that is not there is worse than a missing one.
    ///
    /// A node whose depth jumps more than one level past its predecessor is
    /// attached to the deepest parent that does exist. Malformed `/Outlines`
    /// trees are common, and the reader's own promotion rule (which lifts the
    /// children of an unreadable node to its level) can emit such a jump from
    /// input that was well-formed.
    static func apply(_ nodes: [PDFOutlineReader.OutlineNode], to document: PDFDocument) {
        guard !nodes.isEmpty else { return }

        let root = PDFOutline()
        // Index i holds the node that a child of depth i attaches to, so the
        // root sits at 0 and the list is truncated back on each level change.
        var ancestors: [PDFOutline] = [root]

        for node in nodes {
            guard let page = document.page(at: node.localPageIndex) else { continue }

            let depth = min(max(node.depth, 0), ancestors.count - 1)
            if ancestors.count > depth + 1 {
                ancestors.removeSubrange((depth + 1)...)
            }

            let child = PDFOutline()
            child.label = node.title
            child.destination = PDFDestination(
                page: page,
                at: NSPoint(x: 0, y: page.bounds(for: .mediaBox).height)
            )

            let parent = ancestors[depth]
            parent.insertChild(child, at: parent.numberOfChildren)
            ancestors.append(child)
        }

        // Leave `outlineRoot` nil rather than assigning an empty root: viewers
        // show an empty navigation pane for the latter and none for the former.
        guard root.numberOfChildren > 0 else { return }
        document.outlineRoot = root
    }
}
