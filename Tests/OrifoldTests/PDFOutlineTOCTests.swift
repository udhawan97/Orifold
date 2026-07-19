import AppKit
import PDFKit
import XCTest
@testable import Orifold

/// Embedded PDF bookmarks (`/Outlines`) feeding the table of contents.
///
/// The load-bearing decision under test: outline entries are resolved at read
/// time against the member's LIVE `PDFDocument`, never against a stored page
/// index. `PDFDestination` holds a `PDFPage` reference rather than a page
/// number, so a reorder moves the object and the destination follows it for
/// free, while a deleted page leaves a destination whose page is no longer in
/// the document — detectable as `NSNotFound`.
///
/// `PageRef.sourcePageIndex` must never be used as the anchor here: it is
/// renormalized to the member's current local layout after every structural op
/// (`realignCanonicalReplayBaseAfterStructuralChange`), so it is a layout
/// artifact, not a pointer into the imported bytes.
@MainActor
final class PDFOutlineTOCTests: XCTestCase {

    // MARK: - PDFOutlineReader

    func testReadsNestedOutlineWithDepthsAndPageIndices() throws {
        let pdf = OutlineFixturePDFBuilder.outlinedPDF(
            pageCount: 5,
            outline: [
                .init(title: "Chapter 1", page: 0, children: [
                    .init(title: "Section 1.1", page: 1),
                    .init(title: "Section 1.2", page: 2)
                ]),
                .init(title: "Chapter 2", page: 3)
            ]
        )

        let nodes = PDFOutlineReader.nodes(in: pdf)

        XCTAssertEqual(nodes.map(\.title), ["Chapter 1", "Section 1.1", "Section 1.2", "Chapter 2"])
        XCTAssertEqual(nodes.map(\.depth), [0, 1, 1, 0])
        XCTAssertEqual(nodes.map(\.localPageIndex), [0, 1, 2, 3])
    }

    func testMarksOnlyNodesWhoseChildrenWereEmitted() throws {
        let pdf = OutlineFixturePDFBuilder.outlinedPDF(
            pageCount: 3,
            outline: [
                .init(title: "Has children", page: 0, children: [.init(title: "Child", page: 1)]),
                .init(title: "Leaf", page: 2)
            ]
        )

        let nodes = PDFOutlineReader.nodes(in: pdf)

        XCTAssertEqual(nodes.map(\.hasChildren), [true, false, false])
    }

    func testReturnsNoNodesForDocumentWithoutOutline() throws {
        let pdf = OutlineFixturePDFBuilder.blankPDF(pageCount: 3)

        XCTAssertTrue(PDFOutlineReader.nodes(in: pdf).isEmpty)
    }

    func testResolvesNewPageIndexAfterPagesAreReordered() throws {
        let pdf = OutlineFixturePDFBuilder.outlinedPDF(
            pageCount: 5,
            outline: [.init(title: "Chapter 1", page: 0), .init(title: "Chapter 2", page: 3)]
        )

        pdf.exchangePage(at: 0, withPageAt: 4)
        let nodes = PDFOutlineReader.nodes(in: pdf)

        // The destination followed the page object to its new home; no bookkeeping ran.
        XCTAssertEqual(nodes.map(\.title), ["Chapter 1", "Chapter 2"])
        XCTAssertEqual(nodes.map(\.localPageIndex), [4, 3])
    }

    func testDropsEntriesWhoseDestinationPageWasRemoved() throws {
        let pdf = OutlineFixturePDFBuilder.outlinedPDF(
            pageCount: 4,
            outline: [
                .init(title: "Kept", page: 0),
                .init(title: "Doomed", page: 1),
                .init(title: "Also kept", page: 2)
            ]
        )

        pdf.removePage(at: 1)
        let nodes = PDFOutlineReader.nodes(in: pdf)

        XCTAssertEqual(nodes.map(\.title), ["Kept", "Also kept"])
        XCTAssertEqual(nodes.map(\.localPageIndex), [0, 1])
    }

    func testSkipsEntriesWithBlankLabels() throws {
        let pdf = OutlineFixturePDFBuilder.outlinedPDF(
            pageCount: 3,
            outline: [
                .init(title: "Real", page: 0),
                .init(title: "   ", page: 1),
                .init(title: "", page: 2)
            ]
        )

        XCTAssertEqual(PDFOutlineReader.nodes(in: pdf).map(\.title), ["Real"])
    }

    func testStopsDescendingPastTheDepthCap() throws {
        // A chain 12 levels deep; only the first `maximumDepth` levels may be emitted.
        var deepest = OutlineFixturePDFBuilder.Spec(title: "level-11", page: 0)
        for level in stride(from: 10, through: 0, by: -1) {
            deepest = OutlineFixturePDFBuilder.Spec(title: "level-\(level)", page: 0, children: [deepest])
        }
        let pdf = OutlineFixturePDFBuilder.outlinedPDF(pageCount: 1, outline: [deepest])

        let nodes = PDFOutlineReader.nodes(in: pdf)

        XCTAssertEqual(nodes.count, PDFOutlineReader.maximumDepth)
        XCTAssertEqual(nodes.map(\.depth), Array(0..<PDFOutlineReader.maximumDepth))
        XCTAssertEqual(nodes.last?.title, "level-\(PDFOutlineReader.maximumDepth - 1)")
        // The deepest emitted node's children were cut, so it must not offer a
        // disclosure triangle that would expand to nothing.
        XCTAssertEqual(nodes.last?.hasChildren, false)
    }

    func testStopsAtTheNodeCap() throws {
        let overCap = PDFOutlineReader.maximumNodeCount + 50
        let pdf = OutlineFixturePDFBuilder.outlinedPDF(
            pageCount: 1,
            outline: (0..<overCap).map { OutlineFixturePDFBuilder.Spec(title: "entry-\($0)", page: 0) }
        )

        XCTAssertEqual(PDFOutlineReader.nodes(in: pdf).count, PDFOutlineReader.maximumNodeCount)
    }

    // MARK: - Table of contents composition

    func testTableOfContentsNestsBookmarksUnderTheirFile() throws {
        let outlined = try makeOutlinedMember(
            name: "Manual",
            pageCount: 4,
            outline: [
                .init(title: "Intro", page: 0, children: [.init(title: "Scope", page: 1)]),
                .init(title: "Appendix", page: 3)
            ]
        )
        let plain = try makeMember(name: "Notes", pageCount: 2)
        let viewModel = makeViewModel(members: [outlined, plain])

        let toc = viewModel.tableOfContents

        XCTAssertEqual(toc.map(\.title), ["Manual", "Intro", "Scope", "Appendix", "Notes"])
        XCTAssertEqual(toc.map(\.depth), [0, 1, 2, 1, 0])
    }

    func testBookmarkEntriesJumpToCombinedIndexIncludingBanners() throws {
        let outlined = try makeOutlinedMember(
            name: "Manual",
            pageCount: 3,
            outline: [.init(title: "Intro", page: 0), .init(title: "Middle", page: 2)]
        )
        let second = try makeOutlinedMember(
            name: "Second",
            pageCount: 2,
            outline: [.init(title: "Later", page: 1)]
        )
        let viewModel = makeViewModel(members: [outlined, second])

        let toc = viewModel.tableOfContents
        let byTitle = Dictionary(uniqueKeysWithValues: toc.map { ($0.title, $0) })

        // Layout: banner 0 | pages 1,2,3 | banner 4 | pages 5,6
        XCTAssertEqual(byTitle["Manual"]?.jumpPageIndex, 1)
        XCTAssertEqual(byTitle["Intro"]?.jumpPageIndex, 1)
        XCTAssertEqual(byTitle["Middle"]?.jumpPageIndex, 3)
        XCTAssertEqual(byTitle["Second"]?.jumpPageIndex, 5)
        XCTAssertEqual(byTitle["Later"]?.jumpPageIndex, 6)

        // The jump index must agree with the one mapping helper the app already trusts.
        let middleRef = viewModel.document.workspace.pageOrder[2]
        XCTAssertEqual(byTitle["Middle"]?.jumpPageIndex, viewModel.combinedPageIndex(for: middleRef))
    }

    func testBookmarkEntriesReportTheWorkspacePageNumberTheyLandOn() throws {
        let outlined = try makeOutlinedMember(
            name: "Manual",
            pageCount: 3,
            outline: [.init(title: "Middle", page: 2)]
        )
        let viewModel = makeViewModel(members: [outlined])

        let middle = try XCTUnwrap(viewModel.tableOfContents.first { $0.title == "Middle" })

        XCTAssertEqual(middle.displayPageNumber, 3)
    }

    func testFileWithoutBookmarksStillProducesExactlyOneEntry() throws {
        let plain = try makeMember(name: "Notes", pageCount: 3)
        let viewModel = makeViewModel(members: [plain])

        let toc = viewModel.tableOfContents

        XCTAssertEqual(toc.map(\.title), ["Notes"])
        XCTAssertEqual(toc.map(\.depth), [0])
        XCTAssertEqual(toc.first?.hasChildren, false)
    }

    func testDeletingABookmarkedPageDropsThatBookmarkFromTheTOC() throws {
        let outlined = try makeOutlinedMember(
            name: "Manual",
            pageCount: 3,
            outline: [
                .init(title: "Intro", page: 0),
                .init(title: "Doomed", page: 1),
                .init(title: "Tail", page: 2)
            ]
        )
        let viewModel = makeViewModel(members: [outlined])
        let doomedRef = viewModel.document.workspace.pageOrder[1]

        viewModel.deletePage(doomedRef)

        let toc = viewModel.tableOfContents
        XCTAssertEqual(toc.map(\.title), ["Manual", "Intro", "Tail"])
        // "Tail" was page 2, is now page 1 — combined index 2 behind the banner.
        XCTAssertEqual(toc.last?.jumpPageIndex, 2)
    }

    func testTableOfContentsEntryIdentifiersAreUnique() throws {
        let outlined = try makeOutlinedMember(
            name: "Manual",
            pageCount: 3,
            outline: [
                .init(title: "Repeated", page: 0),
                .init(title: "Repeated", page: 1),
                .init(title: "Repeated", page: 2)
            ]
        )
        let viewModel = makeViewModel(members: [outlined])

        let toc = viewModel.tableOfContents

        // `ForEach` silently drops duplicate ids, so identical bookmark titles
        // pointing at different pages must still yield distinct entries.
        XCTAssertEqual(Set(toc.map(\.id)).count, toc.count)
    }

    // MARK: - Expand / collapse flattening

    func testCollapsedRowHidesItsWholeSubtree() throws {
        let entries = outlineShapedEntries()

        let visible = WorkspaceViewModel.TOCEntry.visibleEntries(in: entries) { entry in
            entry.title != "Intro"  // everything expanded except Intro
        }

        XCTAssertEqual(visible.map(\.title), ["Manual", "Intro", "Appendix", "Notes"])
    }

    func testCollapsedFileHidesEveryBookmarkBeneathItButNotTheNextFile() throws {
        let entries = outlineShapedEntries()

        let visible = WorkspaceViewModel.TOCEntry.visibleEntries(in: entries) { entry in
            entry.title != "Manual"
        }

        XCTAssertEqual(visible.map(\.title), ["Manual", "Notes"])
    }

    func testEverythingExpandedShowsEveryRow() throws {
        let entries = outlineShapedEntries()

        let visible = WorkspaceViewModel.TOCEntry.visibleEntries(in: entries) { _ in true }

        XCTAssertEqual(visible.map(\.title), ["Manual", "Intro", "Scope", "Appendix", "Notes"])
    }

    /// Shape: Manual(0) > [Intro(1) > Scope(2), Appendix(1)], Notes(0)
    private func outlineShapedEntries() -> [WorkspaceViewModel.TOCEntry] {
        [
            .init(id: "m", title: "Manual", jumpPageIndex: 1, displayPageNumber: 1,
                  depth: 0, hasChildren: true),
            .init(id: "m#0", title: "Intro", jumpPageIndex: 1, displayPageNumber: 1,
                  depth: 1, hasChildren: true),
            .init(id: "m#1", title: "Scope", jumpPageIndex: 2, displayPageNumber: 2,
                  depth: 2, hasChildren: false),
            .init(id: "m#2", title: "Appendix", jumpPageIndex: 3, displayPageNumber: 3,
                  depth: 1, hasChildren: false),
            .init(id: "n", title: "Notes", jumpPageIndex: 5, displayPageNumber: 4,
                  depth: 0, hasChildren: false)
        ]
    }
}

// MARK: - Fixtures

/// File-scope rather than members of the test class: keeping them out of the class body
/// keeps it inside SwiftLint's type-body-length budget. The PDF builders themselves live
/// in `Support/OutlineFixturePDFBuilder.swift`, shared with `PDFOutlinePromotionTests`.
private struct Fixture {
    var member: MemberDocument
    var refs: [PageRef]
    var data: Data
}

private func makeMember(name: String, pageCount: Int) throws -> Fixture {
    try makeFixture(name: name, pdf: OutlineFixturePDFBuilder.blankPDF(pageCount: pageCount))
}

private func makeOutlinedMember(
    name: String,
    pageCount: Int,
    outline: [OutlineFixturePDFBuilder.Spec]
) throws -> Fixture {
    try makeFixture(
        name: name,
        pdf: OutlineFixturePDFBuilder.outlinedPDF(pageCount: pageCount, outline: outline)
    )
}

private func makeFixture(name: String, pdf: PDFDocument) throws -> Fixture {
    var member = MemberDocument(displayName: name, sourcePDFRef: "\(name).pdf")
    let refs = (0..<pdf.pageCount).map { PageRef(memberDocId: member.id, sourcePageIndex: $0) }
    member.pageRefs = refs.map(\.id)
    let data = try XCTUnwrap(pdf.dataRepresentation())
    return Fixture(member: member, refs: refs, data: data)
}

@MainActor
private func makeViewModel(members: [Fixture]) -> WorkspaceViewModel {
    let document = WorkspaceDocument()
    document.workspace.documents = members.map(\.member)
    document.workspace.pageOrder = members.flatMap(\.refs)
    for member in members {
        document.memberPDFData[member.member.id] = member.data
    }
    return WorkspaceViewModel(document: document)
}
