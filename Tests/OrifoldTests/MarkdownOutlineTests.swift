import PDFKit
import UniformTypeIdentifiers
import XCTest
@testable import Orifold

/// Markdown headings become embedded PDF bookmarks (`/Outlines`) on import.
///
/// Asserted through `PDFOutlineReader` rather than raw `PDFOutline` walking, so these
/// tests exercise the same read path the table of contents uses — a bookmark that the
/// reader would drop (blank label, unresolvable destination) is a bookmark this feature
/// did not really produce.
///
/// Nesting is RELATIVE, not absolute: the shallowest heading present becomes depth 0.
/// A document whose author started at `##` must not render uniformly indented under an
/// `#` that was never written.
final class MarkdownOutlineTests: XCTestCase {
    private func outlineNodes(for markdown: String) throws -> [PDFOutlineReader.OutlineNode] {
        let imported = try DocumentImportConverter.importedDocument(
            from: Data(markdown.utf8),
            contentType: .markdown,
            filename: "Outline.md",
            baseURL: nil
        )
        return PDFOutlineReader.nodes(in: imported.pdfDocument)
    }

    /// Filler long enough to force the next heading onto a later page.
    private func pageFillingBody() -> String {
        Array(repeating: "Body text that fills the page with enough words to force pagination.", count: 60)
            .joined(separator: " ")
    }

    func testHeadingsBecomeBookmarksInReadingOrder() throws {
        let nodes = try outlineNodes(for: """
        # Title

        ## Chapter One

        Body.

        ## Chapter Two

        Body.
        """)

        XCTAssertEqual(nodes.map(\.title), ["Title", "Chapter One", "Chapter Two"])
    }

    func testSubsectionsNestBeneathTheirChapter() throws {
        let nodes = try outlineNodes(for: """
        ## Chapter One

        Body.

        ### First Subsection

        Body.

        ### Second Subsection

        Body.

        ## Chapter Two

        Body.
        """)

        XCTAssertEqual(
            nodes.map(\.title),
            ["Chapter One", "First Subsection", "Second Subsection", "Chapter Two"]
        )
        // Shallowest heading present (`##`) anchors depth 0 — see type comment.
        XCTAssertEqual(nodes.map(\.depth), [0, 1, 1, 0])
        XCTAssertEqual(nodes.map(\.hasChildren), [true, false, false, false])
    }

    func testBookmarkPointsAtThePageItsHeadingLandedOn() throws {
        let nodes = try outlineNodes(for: """
        # Opening

        \(pageFillingBody())

        # Later Chapter

        Tail.
        """)

        XCTAssertEqual(nodes.map(\.title), ["Opening", "Later Chapter"])
        XCTAssertEqual(nodes.first?.localPageIndex, 0)
        // Resolved from where the heading actually laid out, not from its ordinal.
        let later = try XCTUnwrap(nodes.last?.localPageIndex)
        XCTAssertGreaterThan(later, 0, "second heading should resolve to a later page")
    }

    func testDocumentWithoutHeadingsGetsNoOutline() throws {
        let imported = try DocumentImportConverter.importedDocument(
            from: Data("Just a paragraph.\n\nAnd another one.".utf8),
            contentType: .markdown,
            filename: "Flat.md",
            baseURL: nil
        )

        // Absent, not empty: an outline root with no children is a malformed artifact
        // that still makes the TOC advertise a disclosure control.
        XCTAssertNil(imported.pdfDocument.outlineRoot)
        XCTAssertTrue(PDFOutlineReader.nodes(in: imported.pdfDocument).isEmpty)
    }

    func testSkippedHeadingLevelIndentsOnlyOneStep() throws {
        // `#` → `###` with no `##` between. The gap is a formatting choice, not three
        // levels of structure; collapsing it keeps the popover's indentation honest.
        let nodes = try outlineNodes(for: """
        # Title

        ### Deep Subsection

        Body.

        # Second Title

        Body.
        """)

        XCTAssertEqual(nodes.map(\.title), ["Title", "Deep Subsection", "Second Title"])
        XCTAssertEqual(nodes.map(\.depth), [0, 1, 0])
    }
}
