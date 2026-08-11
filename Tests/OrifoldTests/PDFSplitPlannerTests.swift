import XCTest
@testable import Orifold

final class PDFSplitPlannerTests: XCTestCase {

    // MARK: - Every N pages

    func testEveryNChunksPagesIntoSequentialPartsWithRemainder() {
        let parts = PDFSplitPlanner.parts(totalPages: 10, rule: .everyN(4))
        XCTAssertEqual(parts.map(\.pageIndices), [[0, 1, 2, 3], [4, 5, 6, 7], [8, 9]])
        XCTAssertEqual(parts.map(\.name), ["part1", "part2", "part3"])
    }

    func testEveryNCoveringWholeDocumentProducesSinglePart() {
        let parts = PDFSplitPlanner.parts(totalPages: 3, rule: .everyN(5))
        XCTAssertEqual(parts.map(\.pageIndices), [[0, 1, 2]])
    }

    func testEveryNWithNonPositiveStrideProducesNoParts() {
        XCTAssertEqual(PDFSplitPlanner.parts(totalPages: 10, rule: .everyN(0)), [])
        XCTAssertEqual(PDFSplitPlanner.parts(totalPages: 10, rule: .everyN(-2)), [])
    }

    func testZeroPagesProducesNoParts() {
        XCTAssertEqual(PDFSplitPlanner.parts(totalPages: 0, rule: .everyN(3)), [])
    }

    // MARK: - Explicit ranges

    func testRangesProduceOnePartPerRangeInGivenOrder() {
        let parts = PDFSplitPlanner.parts(totalPages: 10, rule: .ranges([6...8, 0...2]))
        XCTAssertEqual(parts.map(\.pageIndices), [[6, 7, 8], [0, 1, 2]])
        XCTAssertEqual(parts.map(\.name), ["part1", "part2"])
    }

    func testRangesOutsideDocumentAreClampedOrDropped() {
        let parts = PDFSplitPlanner.parts(totalPages: 5, rule: .ranges([3...9, 7...9]))
        XCTAssertEqual(parts.map(\.pageIndices), [[3, 4]])
    }

    // MARK: - Bookmark boundaries

    func testBookmarkBoundariesSplitAtEachTopLevelBookmark() {
        let boundaries = [
            PDFSplitPlanner.Boundary(title: "Intro", pageIndex: 0),
            PDFSplitPlanner.Boundary(title: "Methods", pageIndex: 3),
            PDFSplitPlanner.Boundary(title: "Results", pageIndex: 7)
        ]
        let parts = PDFSplitPlanner.parts(totalPages: 10, rule: .bookmarks(boundaries))
        XCTAssertEqual(parts.map(\.pageIndices), [[0, 1, 2], [3, 4, 5, 6], [7, 8, 9]])
        XCTAssertEqual(parts.map(\.name), ["Intro", "Methods", "Results"])
    }

    func testPagesBeforeFirstBookmarkFormAnUnnamedLeadingPart() {
        let boundaries = [PDFSplitPlanner.Boundary(title: "Chapter 1", pageIndex: 2)]
        let parts = PDFSplitPlanner.parts(totalPages: 5, rule: .bookmarks(boundaries))
        XCTAssertEqual(parts.map(\.pageIndices), [[0, 1], [2, 3, 4]])
        XCTAssertEqual(parts.map(\.name), ["part1", "Chapter 1"])
    }

    func testDuplicateBookmarkTitlesGetUniqueSuffixes() {
        let boundaries = [
            PDFSplitPlanner.Boundary(title: "Chapter", pageIndex: 0),
            PDFSplitPlanner.Boundary(title: "Chapter", pageIndex: 2)
        ]
        let parts = PDFSplitPlanner.parts(totalPages: 4, rule: .bookmarks(boundaries))
        XCTAssertEqual(parts.map(\.name), ["Chapter", "Chapter-2"])
    }

    func testBookmarksSharingAPageCollapseToOneBoundary() {
        let boundaries = [
            PDFSplitPlanner.Boundary(title: "A", pageIndex: 0),
            PDFSplitPlanner.Boundary(title: "B", pageIndex: 0),
            PDFSplitPlanner.Boundary(title: "C", pageIndex: 2)
        ]
        let parts = PDFSplitPlanner.parts(totalPages: 4, rule: .bookmarks(boundaries))
        XCTAssertEqual(parts.map(\.pageIndices), [[0, 1], [2, 3]])
        XCTAssertEqual(parts.map(\.name), ["A", "C"])
    }

    func testBookmarksBeyondDocumentAreIgnored() {
        let boundaries = [
            PDFSplitPlanner.Boundary(title: "Real", pageIndex: 0),
            PDFSplitPlanner.Boundary(title: "Ghost", pageIndex: 12)
        ]
        let parts = PDFSplitPlanner.parts(totalPages: 3, rule: .bookmarks(boundaries))
        XCTAssertEqual(parts.map(\.pageIndices), [[0, 1, 2]])
        XCTAssertEqual(parts.map(\.name), ["Real"])
    }

    func testNoBookmarksProducesNoParts() {
        XCTAssertEqual(PDFSplitPlanner.parts(totalPages: 5, rule: .bookmarks([])), [])
    }

    // MARK: - Range text parsing (1-based user input → 0-based ranges)

    func testParseRangesAcceptsMixedSinglePagesAndSpans() {
        let ranges = PDFSplitPlanner.parseRanges("1-3, 7, 9-10", totalPages: 10)
        XCTAssertEqual(ranges, [0...2, 6...6, 8...9])
    }

    func testParseRangesClampsSpansPastTheLastPage() {
        XCTAssertEqual(PDFSplitPlanner.parseRanges("4-99", totalPages: 5), [3...4])
    }

    func testParseRangesRejectsMalformedInput() {
        XCTAssertNil(PDFSplitPlanner.parseRanges("abc", totalPages: 5))
        XCTAssertNil(PDFSplitPlanner.parseRanges("3-1", totalPages: 5))
        XCTAssertNil(PDFSplitPlanner.parseRanges("0-2", totalPages: 5))
        XCTAssertNil(PDFSplitPlanner.parseRanges("", totalPages: 5))
    }

    func testParseRangesRejectsRangesEntirelyPastTheDocument() {
        XCTAssertNil(PDFSplitPlanner.parseRanges("7-9", totalPages: 5))
    }

    // MARK: - Filename safety

    func testPartNamesAreFilenameSafe() {
        let boundaries = [PDFSplitPlanner.Boundary(title: "Q3/Q4: Results?", pageIndex: 0)]
        let parts = PDFSplitPlanner.parts(totalPages: 2, rule: .bookmarks(boundaries))
        XCTAssertEqual(parts.count, 1)
        let name = parts[0].name
        XCTAssertFalse(name.contains("/"))
        XCTAssertFalse(name.contains(":"))
        XCTAssertFalse(name.isEmpty)
    }
}
