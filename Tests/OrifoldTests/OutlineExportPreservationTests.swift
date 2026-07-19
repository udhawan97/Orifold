import PDFKit
import XCTest
@testable import Orifold

/// Embedded bookmarks (`/Outlines`) must survive the export pipeline.
///
/// The assembly step builds a fresh `PDFDocument` and moves pages into it, so every
/// document-level structure has to be carried across deliberately — the same reason
/// `concatenateForExport` already re-adopts `documentAttributes`. Everything downstream
/// (`PDFSerializer`, qpdf sanitize) preserves an outline that is present, so these tests
/// go through the real `dataForPDFExport` to catch a loss at ANY stage, not just assembly.
@MainActor
final class OutlineExportPreservationTests: XCTestCase {

    private struct Bookmark: Equatable {
        let title: String
        let depth: Int
        /// 0-based page in the exported document.
        let page: Int
    }

    private func exportedBookmarks(_ viewModel: WorkspaceViewModel) throws -> [Bookmark] {
        let data = try viewModel.dataForPDFExport()
        let reopened = try XCTUnwrap(PDFDocument(data: data), "exported bytes are unreadable")
        return PDFOutlineReader.nodes(in: reopened).map {
            Bookmark(title: $0.title, depth: $0.depth, page: $0.localPageIndex)
        }
    }

    private func viewModel(members: [(name: String, data: Data)]) throws -> WorkspaceViewModel {
        let document = WorkspaceDocument()
        var allRefs: [PageRef] = []
        for entry in members {
            let pdf = try XCTUnwrap(PDFDocument(data: entry.data))
            var member = MemberDocument(displayName: entry.name, sourcePDFRef: "\(entry.name).pdf")
            let refs = (0..<pdf.pageCount).map { PageRef(memberDocId: member.id, sourcePageIndex: $0) }
            member.pageRefs = refs.map(\.id)
            document.workspace.documents.append(member)
            document.memberPDFData[member.id] = entry.data
            allRefs.append(contentsOf: refs)
        }
        document.workspace.pageOrder = allRefs
        return WorkspaceViewModel(document: document)
    }

    private func sampleData() throws -> Data {
        try Data(contentsOf: try XCTUnwrap(SampleDocument.url))
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

    func testExportKeepsTheBookmarkTreeIntact() throws {
        let model = try viewModel(members: [("Sample", try sampleData())])

        let bookmarks = try exportedBookmarks(model)

        XCTAssertEqual(bookmarks.map(\.title), [
            "The Serpent on the Bridge",
            "The Dragon King's Plea",
            "The Palace Beneath the Lake",
            "The Battle with the Centipede",
            "The First Two Arrows",
            "The Last Arrow",
            "The Dragon King's Gifts"
        ])
        XCTAssertEqual(bookmarks.map(\.depth), [0, 0, 0, 0, 1, 1, 0], "nesting must survive the round trip")
        XCTAssertEqual(bookmarks.map(\.page), [0, 0, 1, 2, 2, 2, 3], "destinations must resolve to the same pages")
    }

    func testExportOffsetsLaterMembersBookmarksOntoTheirAssembledPages() throws {
        let sample = try sampleData()
        let model = try viewModel(members: [("First", sample), ("Second", sample)])

        let bookmarks = try exportedBookmarks(model)

        XCTAssertEqual(bookmarks.count, 14, "both members' bookmarks must appear")
        // The second copy's pages sit behind the first member's 5 pages.
        // `dropFirst`, not a range slice: on a regression this array is empty, and a
        // trapping slice would kill the whole test process instead of failing one case.
        let second = Array(bookmarks.dropFirst(7))
        XCTAssertEqual(second.map(\.page), [5, 5, 6, 7, 7, 7, 8])
        // Each member's own tree keeps its shape; neither nests under the other.
        XCTAssertEqual(second.map(\.depth), [0, 0, 0, 0, 1, 1, 0])
    }

    func testExportOfMembersWithoutBookmarksProducesNoOutline() throws {
        let model = try viewModel(members: [("Blank", try blankData(pageCount: 3))])

        let data = try model.dataForPDFExport()
        let reopened = try XCTUnwrap(PDFDocument(data: data))

        // Absent, not an empty root — a childless root makes the TOC advertise a
        // disclosure control that expands to nothing.
        XCTAssertNil(reopened.outlineRoot)
    }

    func testExportKeepsBookmarksOfAnOutlinedMemberFollowingAnUnoutlinedOne() throws {
        let model = try viewModel(members: [
            ("Blank", try blankData(pageCount: 2)),
            ("Sample", try sampleData())
        ])

        let bookmarks = try exportedBookmarks(model)

        XCTAssertEqual(bookmarks.count, 7)
        // Offset by the leading member's 2 pages even though it contributed no bookmarks.
        XCTAssertEqual(bookmarks.map(\.page), [2, 2, 3, 4, 4, 4, 5])
    }
}
