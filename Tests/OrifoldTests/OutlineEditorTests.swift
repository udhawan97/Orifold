import PDFKit
import XCTest
@testable import Orifold

/// The outline/bookmark editor: edits live in a workspace-level override model
/// ("operations, not bytes" — member bytes are never touched), the TOC renders the
/// override, and export feeds it through the existing `.bookmarks` stage.
@MainActor
final class OutlineEditorTests: XCTestCase {

    // MARK: - Seeding

    func testBeginOutlineEditingSeedsOverrideFromMemberBookmarks() throws {
        let model = try viewModel()
        model.beginOutlineEditing()
        let nodes = try XCTUnwrap(model.editedOutline)
        XCTAssertEqual(nodes.map(\.title).first, "The Serpent on the Bridge")
        XCTAssertEqual(nodes.count, 7)
        XCTAssertEqual(nodes.map(\.depth), [0, 0, 0, 0, 1, 1, 0])
        let order = model.document.workspace.pageOrder
        XCTAssertEqual(nodes.map(\.pageRefID), [0, 0, 1, 2, 2, 2, 3].map { order[$0].id })
    }

    func testBeginOutlineEditingOnUnoutlinedWorkspaceStartsEmpty() throws {
        let model = try viewModel(data: try blankData(pageCount: 2))
        model.beginOutlineEditing()
        XCTAssertEqual(model.editedOutline, [])
    }

    // MARK: - Operations

    func testAddBookmarkAppendsAnchoredToTheGivenPage() throws {
        let model = try viewModel(data: try blankData(pageCount: 3))
        model.beginOutlineEditing()
        let order = model.document.workspace.pageOrder
        model.addBookmark(title: "Notes", at: order[2])
        let nodes = try XCTUnwrap(model.editedOutline)
        XCTAssertEqual(nodes.map(\.title), ["Notes"])
        XCTAssertEqual(nodes[0].pageRefID, order[2].id)
        XCTAssertEqual(nodes[0].depth, 0)
    }

    func testRenameBookmarkChangesOnlyTheTitle() throws {
        let model = try viewModel()
        model.beginOutlineEditing()
        let node = try XCTUnwrap(model.editedOutline?.first)
        model.renameBookmark(node.id, to: "Prologue")
        XCTAssertEqual(model.editedOutline?.first?.title, "Prologue")
        XCTAssertEqual(model.editedOutline?.count, 7)
    }

    func testDeleteBookmarkPromotesItsChildren() throws {
        let model = try viewModel()
        model.beginOutlineEditing()
        let parent = try XCTUnwrap(model.editedOutline?[3])
        XCTAssertEqual(parent.title, "The Battle with the Centipede")
        model.deleteBookmark(parent.id)
        let nodes = try XCTUnwrap(model.editedOutline)
        XCTAssertEqual(nodes.count, 6)
        XCTAssertFalse(nodes.map(\.title).contains("The Battle with the Centipede"))
        XCTAssertEqual(nodes.map(\.depth), [0, 0, 0, 0, 0, 0], "orphaned children are promoted, not dropped")
    }

    func testMoveBookmarkUpSwapsWithItsPredecessor() throws {
        let model = try viewModel()
        model.beginOutlineEditing()
        let second = try XCTUnwrap(model.editedOutline?[1])
        model.moveBookmark(second.id, up: true)
        XCTAssertEqual(model.editedOutline?[0].id, second.id)
    }

    func testFirstNodeDepthIsAlwaysNormalizedToZero() throws {
        let model = try viewModel()
        model.beginOutlineEditing()
        // Move the depth-1 node "The First Two Arrows" (index 4) to the front.
        let nested = try XCTUnwrap(model.editedOutline?[4])
        for _ in 0..<4 { model.moveBookmark(nested.id, up: true) }
        XCTAssertEqual(model.editedOutline?.first?.id, nested.id)
        XCTAssertEqual(model.editedOutline?.first?.depth, 0)
    }

    func testSetBookmarkDepthClampsToOneDeeperThanPredecessor() throws {
        let model = try viewModel()
        model.beginOutlineEditing()
        let second = try XCTUnwrap(model.editedOutline?[1])
        model.setBookmarkDepth(second.id, depth: 5)
        XCTAssertEqual(model.editedOutline?[1].depth, 1)
        model.setBookmarkDepth(second.id, depth: -2)
        XCTAssertEqual(model.editedOutline?[1].depth, 0)
    }

    func testClearOutlineOverrideRestoresTheSourceOutline() throws {
        let model = try viewModel()
        model.beginOutlineEditing()
        let node = try XCTUnwrap(model.editedOutline?.first)
        model.renameBookmark(node.id, to: "Changed")
        model.clearOutlineOverride()
        XCTAssertNil(model.editedOutline)
        let bookmarks = try exportedBookmarks(model)
        XCTAssertEqual(bookmarks.first?.title, "The Serpent on the Bridge")
    }

    // MARK: - Export

    func testExportCarriesTheEditedOutline() throws {
        let model = try viewModel()
        model.beginOutlineEditing()
        let node = try XCTUnwrap(model.editedOutline?.first)
        model.renameBookmark(node.id, to: "Prologue")
        let order = model.document.workspace.pageOrder
        model.addBookmark(title: "Appendix", at: order[4])

        let bookmarks = try exportedBookmarks(model)
        XCTAssertEqual(bookmarks.first?.title, "Prologue")
        XCTAssertEqual(bookmarks.last, Bookmark(title: "Appendix", depth: 0, page: 4))
    }

    func testBookmarksAnchoredToDeletedPagesDropFromExport() throws {
        let model = try viewModel()
        model.beginOutlineEditing()
        let order = model.document.workspace.pageOrder
        model.deletePages([order[3]])

        let bookmarks = try exportedBookmarks(model)
        XCTAssertFalse(bookmarks.map(\.title).contains("The Dragon King's Gifts"))
        XCTAssertEqual(bookmarks.count, 6)
    }

    // MARK: - TOC display

    func testTableOfContentsRendersTheOverride() throws {
        let model = try viewModel()
        model.beginOutlineEditing()
        let node = try XCTUnwrap(model.editedOutline?.first)
        model.renameBookmark(node.id, to: "Prologue")
        let titles = model.tableOfContents.map(\.title)
        XCTAssertTrue(titles.contains("Prologue"))
        XCTAssertFalse(titles.contains("The Serpent on the Bridge"))
    }

    // MARK: - Helpers

    private struct Bookmark: Equatable {
        let title: String
        let depth: Int
        let page: Int
    }

    private func exportedBookmarks(_ viewModel: WorkspaceViewModel) throws -> [Bookmark] {
        let data = try viewModel.dataForPDFExport()
        let reopened = try XCTUnwrap(PDFDocument(data: data))
        return PDFOutlineReader.nodes(in: reopened).map {
            Bookmark(title: $0.title, depth: $0.depth, page: $0.localPageIndex)
        }
    }

    private func viewModel(data: Data? = nil) throws -> WorkspaceViewModel {
        let bytes = try data ?? Data(contentsOf: try XCTUnwrap(SampleDocument.url))
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

    private func blankData(pageCount: Int) throws -> Data {
        let document = PDFDocument()
        let bounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        for index in 0..<pageCount {
            let image = NSImage(size: bounds.size)
            image.lockFocus()
            NSColor.white.setFill()
            bounds.fill()
            image.unlockFocus()
            if let page = PDFPage(image: image) { document.insert(page, at: index) }
        }
        return try XCTUnwrap(document.dataRepresentation())
    }
}
