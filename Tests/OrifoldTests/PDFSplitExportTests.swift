import XCTest
import PDFKit
@testable import Orifold

/// View-model half of split-by-rule: turning planner parts into per-file PDF data and
/// reading top-level bookmark boundaries off the live workspace. The interactive
/// panel/write path reuses the shipped `writeExportData`/`verifyExportedFile` helpers.
@MainActor
final class PDFSplitExportTests: XCTestCase {

    func testSplitExportPartsProducesOnePDFPerPartWithMatchingPageCounts() throws {
        let viewModel = try makeViewModel(from: makePDFData(pageCount: 5))
        let parts = viewModel.splitExportParts(rule: .everyN(2))
        XCTAssertEqual(parts.map(\.name), ["part1", "part2", "part3"])
        let pageCounts = parts.map { PDFDocument(data: $0.data)?.pageCount }
        XCTAssertEqual(pageCounts, [2, 2, 1])
    }

    func testSplitExportPartsWithInvalidRuleReturnsNothing() throws {
        let viewModel = try makeViewModel(from: makePDFData(pageCount: 3))
        XCTAssertTrue(viewModel.splitExportParts(rule: .everyN(0)).isEmpty)
    }

    func testTopLevelBookmarkBoundariesReadDepthZeroNodesOnly() throws {
        let pdf = try XCTUnwrap(PDFDocument(data: makePDFData(pageCount: 4)))
        PDFOutlineBuilder.apply([
            .init(title: "One", depth: 0, localPageIndex: 0, hasChildren: true),
            .init(title: "Nested", depth: 1, localPageIndex: 1, hasChildren: false),
            .init(title: "Two", depth: 0, localPageIndex: 2, hasChildren: false)
        ], to: pdf)
        let data = try XCTUnwrap(PDFSerializer.data(from: pdf))
        let viewModel = try makeViewModel(from: data)

        let boundaries = viewModel.topLevelBookmarkBoundaries()
        XCTAssertEqual(boundaries, [
            PDFSplitPlanner.Boundary(title: "One", pageIndex: 0),
            PDFSplitPlanner.Boundary(title: "Two", pageIndex: 2)
        ])
    }

    func testSplitByBookmarksEndToEndSplitsAtBookmarkPages() throws {
        let pdf = try XCTUnwrap(PDFDocument(data: makePDFData(pageCount: 4)))
        PDFOutlineBuilder.apply([
            .init(title: "Alpha", depth: 0, localPageIndex: 0, hasChildren: false),
            .init(title: "Beta", depth: 0, localPageIndex: 3, hasChildren: false)
        ], to: pdf)
        let data = try XCTUnwrap(PDFSerializer.data(from: pdf))
        let viewModel = try makeViewModel(from: data)

        let parts = viewModel.splitExportParts(rule: .bookmarks(viewModel.topLevelBookmarkBoundaries()))
        XCTAssertEqual(parts.map(\.name), ["Alpha", "Beta"])
        XCTAssertEqual(parts.map { PDFDocument(data: $0.data)?.pageCount }, [3, 1])
    }

    // MARK: - Helpers

    private func makeViewModel(from data: Data, name: String = "SplitFixture") throws -> WorkspaceViewModel {
        let wrapper = FileWrapper(regularFileWithContents: data)
        wrapper.preferredFilename = "\(name).pdf"
        let document = try WorkspaceDocument(testingFile: wrapper, contentType: .pdf, filename: "\(name).pdf")
        return WorkspaceViewModel(document: document, processingEngine: PDFiumProcessingEngine())
    }

    private func makePDFData(pageCount: Int) throws -> Data {
        let pdf = PDFDocument()
        for index in 0..<pageCount {
            let image = NSImage(size: CGSize(width: 200, height: 200))
            image.lockFocus()
            NSColor.white.setFill()
            NSRect(x: 0, y: 0, width: 200, height: 200).fill()
            ("Page \(index + 1)" as NSString).draw(
                at: NSPoint(x: 20, y: 100),
                withAttributes: [.font: NSFont.systemFont(ofSize: 18), .foregroundColor: NSColor.black]
            )
            image.unlockFocus()
            let page = try XCTUnwrap(PDFPage(image: image))
            pdf.insert(page, at: index)
        }
        return try XCTUnwrap(PDFSerializer.data(from: pdf))
    }
}
