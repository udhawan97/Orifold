import XCTest
@testable import Orifold

final class PDFTextDiffTests: XCTestCase {
    func testIdenticalTextIsUnchanged() {
        let result = PDFTextDiff.diff(old: "alpha bravo charlie", new: "alpha bravo charlie")
        XCTAssertEqual(result, .unchanged)
    }

    func testWhitespaceVariantsCompareEqualWordwise() {
        let result = PDFTextDiff.diff(old: "alpha  bravo\ncharlie", new: "alpha bravo\tcharlie")
        XCTAssertEqual(result, .unchanged)
    }

    func testInsertionCountsAddedWords() {
        let result = PDFTextDiff.diff(old: "alpha bravo charlie", new: "alpha bravo delta charlie")
        XCTAssertEqual(result.insertedWords, 1)
        XCTAssertEqual(result.deletedWords, 0)
        XCTAssertTrue(result.hasChanges)
        XCTAssertTrue(result.comparedExhaustively)
    }

    func testDeletionCountsRemovedWords() {
        let result = PDFTextDiff.diff(old: "alpha bravo delta charlie", new: "alpha bravo charlie")
        XCTAssertEqual(result.insertedWords, 0)
        XCTAssertEqual(result.deletedWords, 1)
    }

    func testReplacementCountsBothSides() {
        let result = PDFTextDiff.diff(old: "alpha bravo charlie", new: "alpha delta charlie")
        XCTAssertEqual(result.insertedWords, 1)
        XCTAssertEqual(result.deletedWords, 1)
    }

    func testEmptyOldSideCountsEverythingInserted() {
        let result = PDFTextDiff.diff(old: "", new: "alpha bravo")
        XCTAssertEqual(result.insertedWords, 2)
        XCTAssertEqual(result.deletedWords, 0)
    }

    func testOverlongPagesFallBackToCoarseComparison() {
        let old = (0..<(PDFTextDiff.maxComparedWords + 1)).map { "word\($0)" }.joined(separator: " ")
        let new = old + " extra"
        let result = PDFTextDiff.diff(old: old, new: new)
        XCTAssertFalse(result.comparedExhaustively)
        XCTAssertTrue(result.hasChanges)
        XCTAssertEqual(result.insertedWords, 0)
        XCTAssertEqual(result.deletedWords, 0)
    }

    func testOverlongIdenticalPagesStillCompareEqual() {
        let text = (0..<(PDFTextDiff.maxComparedWords + 1)).map { "word\($0)" }.joined(separator: " ")
        XCTAssertEqual(PDFTextDiff.diff(old: text, new: text), .unchanged)
    }
}
