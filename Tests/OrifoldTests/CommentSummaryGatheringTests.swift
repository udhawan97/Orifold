import PDFKit
import XCTest
@testable import Orifold

/// View-model half of comment export: collecting comments (with page numbers resolved
/// from anchors) and user highlight/underline/strikeout annotations (with quoted text
/// recovered from the page's text geometry).
@MainActor
final class CommentSummaryGatheringTests: XCTestCase {

    func testGatherResolvesCommentAnchorsToPageNumbers() throws {
        let model = try viewModel()
        let order = model.document.workspace.pageOrder
        model.document.workspace.comments.append(WorkspaceComment(
            body: "Check this citation.",
            tags: ["todo"],
            anchor: WorkspaceCommentAnchor(
                pageRefID: order[1].id,
                rect: CGRect(x: 10, y: 10, width: 100, height: 20),
                kind: .text,
                snippet: "a snippet"
            )
        ))
        model.document.workspace.comments.append(WorkspaceComment(body: "Loose note", isResolved: true))

        let content = model.commentSummaryContent()
        XCTAssertEqual(content.comments.count, 2)
        XCTAssertEqual(content.comments[0].pageNumber, 2)
        XCTAssertEqual(content.comments[0].snippet, "a snippet")
        XCTAssertNil(content.comments[1].pageNumber)
        XCTAssertTrue(content.comments[1].isResolved)
    }

    func testGatherFindsHighlightAnnotationsAndQuotesPageText() throws {
        let model = try viewModel()
        let order = model.document.workspace.pageOrder
        let page = try XCTUnwrap(model.pdfPage(for: order[0]))
        let bounds = page.bounds(for: .mediaBox)
        let annotation = PDFAnnotation(bounds: bounds, forType: .highlight, withProperties: nil)
        page.addAnnotation(annotation)

        let content = model.commentSummaryContent()
        XCTAssertEqual(content.highlights.count, 1)
        XCTAssertEqual(content.highlights[0].pageNumber, 1)
        XCTAssertEqual(content.highlights[0].kind, .highlight)
        let quote = try XCTUnwrap(content.highlights[0].quote)
        XCTAssertFalse(quote.isEmpty, "a whole-page highlight on a text page must quote something")
    }

    // MARK: - Helpers

    private func viewModel() throws -> WorkspaceViewModel {
        let bytes = try Data(contentsOf: try XCTUnwrap(SampleDocument.url))
        let document = WorkspaceDocument()
        let pdf = try XCTUnwrap(PDFDocument(data: bytes))
        var member = MemberDocument(displayName: "Fixture", sourcePDFRef: "Fixture.pdf")
        let refs = (0..<pdf.pageCount).map { PageRef(memberDocId: member.id, sourcePageIndex: $0) }
        member.pageRefs = refs.map(\.id)
        document.workspace.documents.append(member)
        document.memberPDFData[member.id] = bytes
        document.workspace.pageOrder = refs
        return WorkspaceViewModel(document: document)
    }
}
