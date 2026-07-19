import AppKit
import Foundation
import PDFKit

/// Builds a PDF's embedded bookmark tree (`/Outlines`). The write-side counterpart to
/// `PDFOutlineReader`, with two entry points that share one nesting rule:
///
/// - `headings(in:pageCharacterRanges:)` + `outline(from:in:)` recover headings from a
///   laid-out `NSAttributedString` (markdown/text import).
/// - `apply(_:to:)` re-applies an outline already read off member documents, which is how
///   export preserves the bookmarks of an *imported* PDF.
///
/// Still deliberately not a general outline editor. Persisting `outlineRoot` costs a
/// `dataRepresentation()` round trip, which destroys the qpdf-preserved text layer of an
/// imported PDF — the hazard recorded against the bookmark-editor roadmap item. Both entry
/// points are safe for the narrow reason that neither has such a layer to lose: a document
/// born from `renderAttributedString` never had one, and by the time export writes an
/// outline it has already rebuilt and re-serialized those bytes through PDFKit. Writing
/// onto bytes the app means to *keep* is the case that remains off-limits.
enum PDFOutlineBuilder {

    /// Marks a run as belonging to a markdown heading block, carrying its level (1–6).
    /// The contract between `typesetMarkdown`, which knows block structure, and
    /// `renderAttributedString`, which knows pagination — neither alone can place a
    /// bookmark, because a heading's page is not known until the text is laid out.
    static let headingLevelAttribute = NSAttributedString.Key("OrifoldMarkdownHeadingLevel")

    struct Heading: Equatable {
        /// Trimmed heading text. Never blank — blank headings are dropped.
        let title: String
        /// Markdown heading level, 1 for `#`. Compared only against other headings in the
        /// same document; absolute value never sets indentation.
        let level: Int
        /// Index of the page the heading laid out on.
        let pageIndex: Int
    }

    /// Recovers headings in reading order, resolving each to the page it laid out on.
    ///
    /// `pageCharacterRanges` must tile the string in page order — the renderer collects
    /// them from `NSLayoutManager` as it fills one text container per page, which is the
    /// only point at which a heading's page is knowable.
    static func headings(
        in attributed: NSAttributedString,
        pageCharacterRanges: [NSRange]
    ) -> [Heading] {
        var result: [Heading] = []
        let whole = NSRange(location: 0, length: attributed.length)

        attributed.enumerateAttribute(headingLevelAttribute, in: whole) { value, range, _ in
            guard let level = value as? Int else { return }
            let title = attributed.attributedSubstring(from: range).string
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return }

            // The last page starting at or before the heading is the page containing it.
            // A heading that wraps across a page break belongs to the page it STARTS on,
            // which is where a reader jumping to it expects to land.
            guard let pageIndex = pageCharacterRanges.lastIndex(where: { $0.location <= range.location })
            else { return }

            result.append(Heading(title: title, level: level, pageIndex: pageIndex))
        }
        return result
    }

    /// Assembles a nested outline, or `nil` when there is nothing to show.
    ///
    /// Nesting is by CONTAINMENT, not by level arithmetic: each heading hangs off the
    /// nearest preceding heading of a shallower level. So a document that starts at `##`
    /// is not uniformly indented under an `#` its author never wrote, and a `#` → `###`
    /// jump indents one step rather than three — the popover shows document structure,
    /// not markdown syntax.
    ///
    /// Returns `nil` rather than an empty root: a childless `outlineRoot` still makes the
    /// table of contents advertise a disclosure control that expands to nothing.
    static func outline(from headings: [Heading], in document: PDFDocument) -> PDFOutline? {
        let root = PDFOutline()
        var ancestors: [(level: Int, node: PDFOutline)] = []

        for heading in headings {
            guard let page = document.page(at: heading.pageIndex) else { continue }

            let node = PDFOutline()
            node.label = heading.title
            // Top of the page, not the heading's exact baseline: the table of contents
            // resolves `destination.page` only, and a page-top anchor is what other
            // readers show for a chapter mark.
            node.destination = PDFDestination(
                page: page,
                at: CGPoint(x: 0, y: page.bounds(for: .mediaBox).height)
            )

            while let deepest = ancestors.last, deepest.level >= heading.level {
                ancestors.removeLast()
            }
            let parent = ancestors.last?.node ?? root
            parent.insertChild(node, at: parent.numberOfChildren)
            ancestors.append((level: heading.level, node: node))
        }

        return root.numberOfChildren > 0 ? root : nil
    }

    /// Re-applies bookmarks read off member documents onto `document`, replacing any
    /// existing outline. The export path's counterpart to the markdown one above.
    ///
    /// `localPageIndex` is an index into `document`; callers spanning several source
    /// documents offset it themselves. Nodes pointing past the end are skipped rather
    /// than clamped — a bookmark aimed at a page that is not there is worse than a
    /// missing one.
    ///
    /// Reuses `outline(from:in:)` rather than walking the list itself. The reader's
    /// `depth` is already the 0-based nesting the outline should show, so it maps onto a
    /// 1-based `level` directly, and containment then reproduces that nesting exactly —
    /// including the awkward cases, where a node whose depth jumps more than one level
    /// past its predecessor lands under the deepest parent that does exist. Malformed
    /// `/Outlines` trees are common, and the reader's own promotion rule (which lifts an
    /// unreadable node's children to its level) emits such jumps from well-formed input.
    static func apply(_ nodes: [PDFOutlineReader.OutlineNode], to document: PDFDocument) {
        let headings = nodes.map {
            Heading(title: $0.title, level: $0.depth + 1, pageIndex: $0.localPageIndex)
        }
        guard let root = outline(from: headings, in: document) else { return }
        document.outlineRoot = root
    }
}
