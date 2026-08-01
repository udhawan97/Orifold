import PDFKit
import XCTest
@testable import Orifold

/// `currentPageNumber` is banner-excluded and `combinedPDF` is banner-included,
/// so anything that wants "the page the reader is looking at" as a real
/// `PDFPage` has to go through the mapping rather than subtracting one.
///
/// The recents thumbnail did the subtraction, which is why an unscrolled
/// workspace saved the `BoundaryPage` separator as its cover image.
@MainActor
final class CurrentCombinedPageTests: XCTestCase {

    func testResolvesTheReaderPageAndNeverABanner() throws {
        let viewModel = makeViewModel(members: [fourPager(), fourPager()])

        // 2 members x 4 pages, plus one banner each -> 10 slots in combinedPDF,
        // 8 real pages in the workspace.
        XCTAssertEqual(viewModel.combinedPDF.pageCount, 10)
        XCTAssertEqual(viewModel.pageCount, 8)

        for position in 1...8 {
            viewModel.currentPageNumber = position
            let page = try XCTUnwrap(
                viewModel.currentCombinedPage,
                "no page resolved for workspace position \(position)"
            )
            XCTAssertFalse(
                page is BoundaryPage,
                "workspace position \(position) resolved to a separator, not a page"
            )
            XCTAssertEqual(
                viewModel.workspacePageNumber(for: page, in: viewModel.combinedPDF), position,
                "round trip disagrees at workspace position \(position)"
            )
        }
    }

    /// The state a freshly opened, never-scrolled workspace is in.
    func testResolvesAPageBeforeTheReaderHasScrolled() throws {
        let viewModel = makeViewModel(members: [fourPager(), fourPager()])
        viewModel.currentPageNumber = 0

        let page = try XCTUnwrap(viewModel.currentCombinedPage)
        XCTAssertFalse(page is BoundaryPage, "an unscrolled workspace must not resolve to a separator")
        XCTAssertEqual(viewModel.workspacePageNumber(for: page, in: viewModel.combinedPDF), 1)
    }

    /// The contract between RecentsStore, ContentView and ReadingCanvas: what the
    /// store persists as `lastPageOpened` must round-trip back to the page the
    /// reader actually left off at.
    ///
    /// `lastPageOpened` is 0-based workspace; `pendingResumeWorkspacePage` is
    /// 1-based workspace; `combinedPageIndex(forWorkspacePageNumber:)` yields a
    /// banner-included index. Three representations of one page, which is exactly
    /// how the thumbnail bug happened.
    func testResumeTargetRoundTripsToThePageTheReaderLeftOff() throws {
        let viewModel = makeViewModel(members: [fourPager(), fourPager()])

        for position in 1...8 {
            viewModel.currentPageNumber = position

            // What ContentView hands the store on close.
            let stored = max(0, viewModel.currentPageNumber - 1)

            // What ContentView seeds on the next open.
            viewModel.pendingResumeWorkspacePage = stored + 1

            let index = try XCTUnwrap(
                viewModel.combinedPageIndex(
                    forWorkspacePageNumber: try XCTUnwrap(viewModel.pendingResumeWorkspacePage)
                ),
                "no combined index for resume target at position \(position)"
            )
            let page = try XCTUnwrap(viewModel.combinedPDF.page(at: index))

            XCTAssertFalse(page is BoundaryPage, "resume at position \(position) landed on a separator")
            XCTAssertEqual(
                viewModel.workspacePageNumber(for: page, in: viewModel.combinedPDF), position,
                "resume at position \(position) landed somewhere else"
            )
        }
    }

    // MARK: - Fixtures

    private func fourPager() -> Data {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/no-page-labels.pdf")
        // swiftlint:disable:next force_try
        return try! Data(contentsOf: url)
    }

    private func makeViewModel(members: [Data]) -> WorkspaceViewModel {
        let document = WorkspaceDocument()
        var allRefs: [PageRef] = []
        var memberRecords: [MemberDocument] = []

        for (offset, data) in members.enumerated() {
            var member = MemberDocument(displayName: "Member \(offset)", sourcePDFRef: "member\(offset).pdf")
            let pageCount = PDFDocument(data: data)?.pageCount ?? 0
            let refs = (0..<pageCount).map { PageRef(memberDocId: member.id, sourcePageIndex: $0) }
            member.pageRefs = refs.map(\.id)
            memberRecords.append(member)
            allRefs.append(contentsOf: refs)
            document.memberPDFData[member.id] = data
        }

        document.workspace.documents = memberRecords
        document.workspace.pageOrder = allRefs
        return WorkspaceViewModel(document: document)
    }
}
