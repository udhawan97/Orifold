import AppKit
import PDFKit
import XCTest
@testable import Orifold

@MainActor
final class PDFComparisonServiceTests: XCTestCase {
    func testPairsClassifyUnchangedChangedAndExtraPages() throws {
        let left = try makePDFData(pageTexts: ["Alpha bravo charlie delta", "Echo foxtrot golf"])
        let right = try makePDFData(pageTexts: [
            "Alpha bravo charlie delta",
            "Echo foxtrot golf hotel india",
            "Juliet kilo lima"
        ])

        let result = PDFComparisonService.compare(request(left: left, pageCount: 2, right: right))

        XCTAssertEqual(result.status, .completed)
        XCTAssertEqual(result.pairs.count, 3)
        XCTAssertEqual(result.pairs[0].change, .unchanged)
        XCTAssertEqual(result.pairs[1].change, .changed)
        XCTAssertEqual(result.pairs[1].text.value?.hasChanges, true)
        XCTAssertEqual(result.pairs[2].change, .rightOnly)
        XCTAssertEqual(result.pairs[2].visual, .notApplicable)
    }

    func testTextDiffCountsSurviveExtraction() throws {
        let left = try makePDFData(pageTexts: ["Alpha bravo charlie"])
        let right = try makePDFData(pageTexts: ["Alpha bravo charlie delta echo"])

        let result = PDFComparisonService.compare(request(left: left, pageCount: 1, right: right))

        let text = try XCTUnwrap(result.pairs[0].text.value)
        XCTAssertTrue(text.comparedExhaustively)
        // `old` is the picked (right) file, `new` is the workspace: the two extra words on
        // the right side count as deletions relative to the workspace.
        XCTAssertEqual(text.insertedWords + text.deletedWords, 2)
    }

    func testValidEmptyTextLayersRemainAvailableAndUnchanged() throws {
        let left = try makePDFData(pageTexts: [""])
        let right = try makePDFData(pageTexts: [""])

        let result = PDFComparisonService.compare(request(left: left, pageCount: 1, right: right))

        XCTAssertEqual(result.pairs[0].text, .available(.unchanged))
        XCTAssertEqual(result.pairs[0].change, .unchanged)
    }

    func testImageOnlyPagesCompareWithoutInventingText() throws {
        let left = try makeImageOnlyPDFData(color: .black)
        let right = try makeImageOnlyPDFData(color: .white)

        let result = PDFComparisonService.compare(request(left: left, pageCount: 1, right: right))

        XCTAssertEqual(result.pairs[0].change, .changed)
        XCTAssertEqual(result.pairs[0].text, .available(.unchanged))
        XCTAssertEqual(result.pairs[0].visual.value?.hasChanges, true)
    }

    func testUnavailableChannelCannotProduceUnchanged() throws {
        let pdf = try makePDFData(pageTexts: ["Same text"])
        let analyzers = PDFComparisonService.Analyzers(
            visual: { _, _ in nil },
            text: PDFTextAnalysisEngine.readingOrderTextResult
        )

        let result = PDFComparisonService.compare(
            request(left: pdf, pageCount: 1, right: pdf),
            analyzers: analyzers
        )

        XCTAssertEqual(result.pairs[0].visual, .unavailable)
        XCTAssertEqual(result.pairs[0].text, .available(.unchanged))
        XCTAssertEqual(result.pairs[0].change, .incomplete)
        XCTAssertFalse(result.isComplete)
    }

    func testKnownVisualDifferenceSurvivesUnavailableTextDisclosure() throws {
        let pdf = try makePDFData(pageTexts: ["Same text"])
        let visualChange = PDFVisualDiff.Result(
            changedRects: [CGRect(x: 0, y: 0, width: 0.1, height: 0.1)],
            changedFraction: 0.01
        )
        let analyzers = PDFComparisonService.Analyzers(
            visual: { _, _ in visualChange },
            text: { _, _ in .unavailable }
        )

        let result = PDFComparisonService.compare(
            request(left: pdf, pageCount: 1, right: pdf),
            analyzers: analyzers
        )

        XCTAssertEqual(result.pairs[0].change, .changed)
        XCTAssertEqual(result.pairs[0].visual, .available(visualChange))
        XCTAssertEqual(result.pairs[0].text, .unavailable)
        XCTAssertFalse(result.isComplete)
    }

    func testCoarseTextResultRemainsExplicit() throws {
        let left = try makePDFData(pageTexts: ["Left"])
        let right = try makePDFData(pageTexts: ["Right"])
        let old = (0...PDFTextDiff.maxComparedWords).map { "old\($0)" }.joined(separator: " ")
        let new = old + " changed"
        let analyzers = PDFComparisonService.Analyzers(
            visual: { _, _ in .unchanged },
            text: { data, _ in .available(data == left ? new : old) }
        )

        let result = PDFComparisonService.compare(
            request(left: left, pageCount: 1, right: right),
            analyzers: analyzers
        )

        XCTAssertEqual(result.pairs[0].change, .changed)
        XCTAssertEqual(result.pairs[0].text.value?.comparedExhaustively, false)
    }

    func testPositiveOffsetRecordsExcludedLeadingRightPagesAndActualNumbers() throws {
        let shared = "Alpha bravo charlie delta"
        let left = try makePDFData(pageTexts: [shared])
        let right = try makePDFData(pageTexts: ["Cover page", shared])

        let result = PDFComparisonService.compare(
            request(left: left, pageCount: 1, right: right),
            rightOffset: 1
        )

        XCTAssertEqual(result.pairs.count, 1)
        XCTAssertEqual(result.pairs[0].change, .unchanged)
        XCTAssertEqual(result.pairs[0].left?.number, 1)
        XCTAssertEqual(result.pairs[0].right?.number, 2)
        XCTAssertEqual(result.coverage.excludedRightPageNumbers, [1])
        XCTAssertFalse(result.isComplete)
    }

    func testExtremeNegativeOffsetFiltersEmptySlotsAndKeepsBothUnmatchedPages() throws {
        let left = try makePDFData(pageTexts: ["Left"])
        let right = try makePDFData(pageTexts: ["Right"])

        let result = PDFComparisonService.compare(
            request(left: left, pageCount: 1, right: right),
            rightOffset: -3
        )

        XCTAssertEqual(result.pairs.map(\.alignmentIndex), [0, 3])
        XCTAssertEqual(result.pairs.map(\.change), [.leftOnly, .rightOnly])
        XCTAssertEqual(result.pairs[0].left?.number, 1)
        XCTAssertEqual(result.pairs[1].right?.number, 1)
    }

    func testExtraWorkspacePagesReportLeftOnly() throws {
        let left = try makePDFData(pageTexts: ["Alpha bravo", "Charlie delta", "Echo foxtrot"])
        let right = try makePDFData(pageTexts: ["Alpha bravo"])

        let result = PDFComparisonService.compare(request(left: left, pageCount: 3, right: right))

        XCTAssertEqual(result.pairs.count, 3)
        XCTAssertEqual(result.pairs[1].change, .leftOnly)
        XCTAssertEqual(result.pairs[2].change, .leftOnly)
    }

    func testMalformedRightBytesFailInsteadOfLookingIdentical() throws {
        let left = try makePDFData(pageTexts: ["Alpha"])
        let result = PDFComparisonService.compare(
            request(left: left, pageCount: 1, right: Data("not a pdf".utf8))
        )

        XCTAssertEqual(result.status, .failed)
        XCTAssertTrue(result.pairs.isEmpty)
    }

    func testPreparationPreservesPageIdentityWhenSourcesAreMissing() {
        let firstMember = UUID()
        let secondMember = UUID()
        let firstPageID = UUID()
        let secondPageID = UUID()
        let sources = [
            PDFComparisonService.WorkspacePageSource(
                id: firstPageID,
                number: 4,
                memberID: firstMember,
                sourcePageIndex: 2,
                combinedPageIndex: 7
            ),
            PDFComparisonService.WorkspacePageSource(
                id: secondPageID,
                number: 9,
                memberID: secondMember,
                sourcePageIndex: 5,
                combinedPageIndex: nil
            )
        ]

        let prepared = PDFComparisonService.prepareLeftSide(
            pages: sources,
            combinedData: Data("combined".utf8),
            memberData: [firstMember: Data("first".utf8)]
        )

        XCTAssertEqual(prepared.pages.count, 2)
        XCTAssertEqual(prepared.pages.map(\.workspacePageID), [firstPageID, secondPageID])
        XCTAssertEqual(prepared.pages.map(\.workspacePageNumber), [4, 9])
        XCTAssertEqual(prepared.pages[0].visualPage?.pageIndex, 7)
        XCTAssertEqual(prepared.pages[0].textPage?.pageIndex, 2)
        XCTAssertNil(prepared.pages[1].visualPage)
        XCTAssertNil(prepared.pages[1].textPage)
    }

    func testPreparedMissingSourcePageRunsAsIncompleteAtOriginalNumber() throws {
        let pageID = UUID()
        let prepared = PDFComparisonService.prepareLeftSide(
            pages: [PDFComparisonService.WorkspacePageSource(
                id: pageID,
                number: 7,
                memberID: UUID(),
                sourcePageIndex: 3,
                combinedPageIndex: nil
            )],
            combinedData: nil,
            memberData: [:]
        )
        let right = try makePDFData(pageTexts: ["Right page"])

        let result = PDFComparisonService.compare(PDFComparisonService.Request(
            leftDocuments: prepared.documents,
            leftPages: prepared.pages,
            rightData: right
        ))

        XCTAssertEqual(result.pairs[0].left?.workspacePageID, pageID)
        XCTAssertEqual(result.pairs[0].left?.number, 7)
        XCTAssertEqual(result.pairs[0].change, .incomplete)
        XCTAssertEqual(result.pairs[0].visual, .unavailable)
        XCTAssertEqual(result.pairs[0].text, .unavailable)
    }

    func testPreparationDeduplicatesReorderedMultiMemberDocuments() {
        let firstMember = UUID()
        let secondMember = UUID()
        let sources = [
            PDFComparisonService.WorkspacePageSource(
                id: UUID(), number: 1, memberID: firstMember, sourcePageIndex: 8, combinedPageIndex: 0
            ),
            PDFComparisonService.WorkspacePageSource(
                id: UUID(), number: 2, memberID: secondMember, sourcePageIndex: 3, combinedPageIndex: 1
            ),
            PDFComparisonService.WorkspacePageSource(
                id: UUID(), number: 3, memberID: firstMember, sourcePageIndex: 1, combinedPageIndex: 2
            )
        ]

        let prepared = PDFComparisonService.prepareLeftSide(
            pages: sources,
            combinedData: nil,
            memberData: [
                firstMember: Data("first".utf8),
                secondMember: Data("second".utf8)
            ]
        )

        XCTAssertEqual(prepared.documents.count, 2)
        XCTAssertEqual(prepared.pages.map(\.textPage?.documentIndex), [0, 1, 0])
        XCTAssertEqual(prepared.pages.map(\.textPage?.pageIndex), [8, 3, 1])
        XCTAssertTrue(prepared.pages.allSatisfy { $0.visualPage == nil })
    }

}

private extension PDFComparisonServiceTests {
    // MARK: - Fixtures

    private func request(left: Data, pageCount: Int, right: Data) -> PDFComparisonService.Request {
        let pages = (0..<pageCount).map { index in
            let locator = PDFComparisonService.PageLocator(documentIndex: 0, pageIndex: index)
            return PDFComparisonService.LeftPage(
                workspacePageID: UUID(),
                workspacePageNumber: index + 1,
                visualPage: locator,
                textPage: locator
            )
        }
        return PDFComparisonService.Request(
            leftDocuments: [left],
            leftPages: pages,
            rightData: right
        )
    }

    private final class FixturePageView: NSView {
        private let text: String
        init(frame: CGRect, text: String) {
            self.text = text
            super.init(frame: frame)
        }
        required init?(coder: NSCoder) { nil }
        override func draw(_ dirtyRect: NSRect) {
            NSColor.white.setFill()
            dirtyRect.fill()
            (text as NSString).draw(
                in: bounds.insetBy(dx: 54, dy: 54),
                withAttributes: [.font: NSFont(name: "Helvetica", size: 14) ?? .systemFont(ofSize: 14),
                                 .foregroundColor: NSColor.black]
            )
        }
    }

    private final class ImageOnlyPageView: NSView {
        private let color: NSColor
        init(frame: CGRect, color: NSColor) {
            self.color = color
            super.init(frame: frame)
        }
        required init?(coder: NSCoder) { nil }
        override func draw(_ dirtyRect: NSRect) {
            NSColor.white.setFill()
            dirtyRect.fill()
            color.setFill()
            NSRect(x: 96, y: 180, width: 280, height: 240).fill()
        }
    }

    private func makePDFData(pageTexts: [String]) throws -> Data {
        let pdf = PDFDocument()
        for (index, text) in pageTexts.enumerated() {
            let view = FixturePageView(frame: CGRect(x: 0, y: 0, width: 612, height: 792), text: text)
            let pageData = view.dataWithPDF(inside: view.bounds)
            guard let pageDocument = PDFDocument(data: pageData), let page = pageDocument.page(at: 0) else {
                throw XCTSkip("fixture page rendering failed")
            }
            pdf.insert(page, at: index)
        }
        return try XCTUnwrap(pdf.dataRepresentation())
    }

    private func makeImageOnlyPDFData(color: NSColor) throws -> Data {
        let view = ImageOnlyPageView(
            frame: CGRect(x: 0, y: 0, width: 612, height: 792),
            color: color
        )
        return view.dataWithPDF(inside: view.bounds)
    }
}
