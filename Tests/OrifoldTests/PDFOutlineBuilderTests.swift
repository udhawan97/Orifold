import PDFKit
import XCTest
@testable import Orifold

/// `PDFOutlineBuilder`'s export-side entry point in isolation. Its markdown-side
/// entry points are covered by `MarkdownOutlineTests`; both share one nesting rule,
/// so these also exercise the containment walk that import relies on.
final class PDFOutlineBuilderTests: XCTestCase {

    func testBuilderRebuildsNestingFromAFlatDepthOrderedList() throws {
        let document = OutlineFixtures.blankPDF(pageCount: 4)

        PDFOutlineBuilder.apply([
            outlineNode("Chapter One", depth: 0, page: 0),
            outlineNode("Section 1.1", depth: 1, page: 1),
            outlineNode("Section 1.2", depth: 1, page: 2),
            outlineNode("Chapter Two", depth: 0, page: 3)
        ], to: document)

        let root = try XCTUnwrap(document.outlineRoot)
        XCTAssertEqual(root.numberOfChildren, 2, "two top-level chapters, sections nested beneath the first")
        XCTAssertEqual(root.child(at: 0)?.numberOfChildren, 2)
        XCTAssertEqual(root.child(at: 1)?.numberOfChildren, 0)

        // Round-trip through bytes: an outline that cannot be re-read from
        // serialized output is not preserved in any sense that matters.
        let reopened = try XCTUnwrap(PDFDocument(data: try XCTUnwrap(document.dataRepresentation())))
        let nodes = PDFOutlineReader.nodes(in: reopened)
        XCTAssertEqual(nodes.map(\.title), ["Chapter One", "Section 1.1", "Section 1.2", "Chapter Two"])
        XCTAssertEqual(nodes.map(\.depth), [0, 1, 1, 0])
        XCTAssertEqual(nodes.map(\.localPageIndex), [0, 1, 2, 3])
    }

    func testBuilderSkipsNodesPointingOutsideTheDocument() throws {
        let document = OutlineFixtures.blankPDF(pageCount: 2)

        PDFOutlineBuilder.apply([
            outlineNode("Real", depth: 0, page: 0),
            outlineNode("Past the end", depth: 0, page: 7)
        ], to: document)

        XCTAssertEqual(PDFOutlineReader.nodes(in: document).map(\.title), ["Real"])
    }

    func testBuilderLeavesTheDocumentUntouchedWhenThereAreNoNodes() throws {
        let document = OutlineFixtures.blankPDF(pageCount: 2)

        PDFOutlineBuilder.apply([], to: document)

        XCTAssertNil(
            document.outlineRoot,
            "an empty outline root would show as an empty navigation pane rather than none"
        )
    }

    /// A child arriving without a parent must land somewhere rather than being dropped.
    /// Real `/Outlines` trees are not always well-formed, and the reader's own
    /// promotion rule (lifting an unreadable node's children) emits exactly this.
    func testBuilderClampsOrphanedDepthsToTheDeepestAvailableParent() throws {
        let document = OutlineFixtures.blankPDF(pageCount: 3)

        PDFOutlineBuilder.apply([
            outlineNode("Deep opener", depth: 2, page: 0),
            outlineNode("Chapter", depth: 0, page: 1),
            outlineNode("Skipped a level", depth: 2, page: 2)
        ], to: document)

        let nodes = PDFOutlineReader.nodes(in: document)
        XCTAssertEqual(nodes.map(\.title), ["Deep opener", "Chapter", "Skipped a level"])
        XCTAssertEqual(nodes.map(\.depth), [0, 0, 1], "orphans clamp to one level below what exists")
    }
}

/// Reader-shaped node, the input side of `PDFOutlineBuilder`. Stays local: it builds
/// `PDFOutlineReader.OutlineNode`, not a PDF, so it has nothing to share with
/// `OutlineFixtures`.
private func outlineNode(_ title: String, depth: Int, page: Int) -> PDFOutlineReader.OutlineNode {
    PDFOutlineReader.OutlineNode(title: title, depth: depth, localPageIndex: page, hasChildren: false)
}
