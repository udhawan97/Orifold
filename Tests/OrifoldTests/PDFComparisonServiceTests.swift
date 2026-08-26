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

        let pairs = PDFComparisonService.compare(request(left: left, pageCount: 2, right: right))

        XCTAssertEqual(pairs.count, 3)
        XCTAssertEqual(pairs[0].change, .unchanged)
        XCTAssertEqual(pairs[1].change, .changed)
        XCTAssertEqual(pairs[1].text?.hasChanges, true)
        XCTAssertEqual(pairs[2].change, .rightOnly)
        XCTAssertNil(pairs[2].visual)
    }

    func testTextDiffCountsSurviveExtraction() throws {
        let left = try makePDFData(pageTexts: ["Alpha bravo charlie"])
        let right = try makePDFData(pageTexts: ["Alpha bravo charlie delta echo"])

        let pairs = PDFComparisonService.compare(request(left: left, pageCount: 1, right: right))

        let text = try XCTUnwrap(pairs[0].text)
        XCTAssertTrue(text.comparedExhaustively)
        // `old` is the picked (right) file, `new` is the workspace: the two extra words on
        // the right side count as deletions relative to the workspace.
        XCTAssertEqual(text.insertedWords + text.deletedWords, 2)
    }

    func testRightOffsetShiftsThePairing() throws {
        let shared = "Alpha bravo charlie delta"
        let left = try makePDFData(pageTexts: [shared])
        let right = try makePDFData(pageTexts: ["Completely different cover page", shared])

        let aligned = PDFComparisonService.compare(
            request(left: left, pageCount: 1, right: right),
            rightOffset: 1
        )
        XCTAssertEqual(aligned.first?.change, .unchanged)

        let misaligned = PDFComparisonService.compare(request(left: left, pageCount: 1, right: right))
        XCTAssertEqual(misaligned.first?.change, .changed)
    }

    func testExtraWorkspacePagesReportLeftOnly() throws {
        let left = try makePDFData(pageTexts: ["Alpha bravo", "Charlie delta", "Echo foxtrot"])
        let right = try makePDFData(pageTexts: ["Alpha bravo"])

        let pairs = PDFComparisonService.compare(request(left: left, pageCount: 3, right: right))

        XCTAssertEqual(pairs.count, 3)
        XCTAssertEqual(pairs[1].change, .leftOnly)
        XCTAssertEqual(pairs[2].change, .leftOnly)
    }

    func testCancellationReturnsNothingWhenCancelledUpFront() throws {
        let left = try makePDFData(pageTexts: ["Alpha bravo"])
        let right = try makePDFData(pageTexts: ["Alpha bravo"])

        let pairs = PDFComparisonService.compare(
            request(left: left, pageCount: 1, right: right),
            isCancelled: { true }
        )
        XCTAssertTrue(pairs.isEmpty)
    }

    // MARK: - Fixtures

    private func request(left: Data, pageCount: Int, right: Data) -> PDFComparisonService.Request {
        let locators = (0..<pageCount).map {
            PDFComparisonService.PageLocator(documentIndex: 0, pageIndex: $0)
        }
        return PDFComparisonService.Request(
            leftDocuments: [left],
            leftVisualPages: locators,
            leftTextPages: locators,
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
}
