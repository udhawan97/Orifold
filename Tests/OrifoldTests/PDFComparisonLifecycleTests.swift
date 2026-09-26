import AppKit
import PDFKit
import XCTest
@testable import Orifold

@MainActor
final class PDFComparisonLifecycleTests: XCTestCase {
    func testExtremePositiveOffsetExcludesEveryRightPageAndKeepsLeftPages() throws {
        let left = try makePDFData(pageTexts: ["Left one", "Left two"])
        let right = try makePDFData(pageTexts: ["Right one", "Right two"])

        let result = PDFComparisonService.compare(
            request(left: left, pageCount: 2, right: right),
            rightOffset: 5
        )

        XCTAssertEqual(result.coverage.excludedRightPageNumbers, [1, 2])
        XCTAssertEqual(result.pairs.map(\.change), [.leftOnly, .leftOnly])
        XCTAssertEqual(result.pairs.compactMap(\.left?.number), [1, 2])
        XCTAssertTrue(result.pairs.allSatisfy { $0.right == nil })
    }

    func testCancellationReturnsPartialPairsWithCancelledStatus() throws {
        let document = try makePDFData(pageTexts: ["Alpha", "Bravo"])
        let cancellation = OperationCancellationToken()

        let result = PDFComparisonService.compare(
            request(left: document, pageCount: 2, right: document),
            progress: { _ in cancellation.cancel() },
            isCancelled: { cancellation.isCancelled }
        )

        XCTAssertEqual(result.status, .cancelled)
        XCTAssertEqual(result.pairs.count, 1)
        XCTAssertEqual(result.pairs[0].left?.number, 1)
    }

    func testCancellationAfterOnlyPairStillReturnsCancelled() throws {
        let document = try makePDFData(pageTexts: ["Alpha"])
        let cancellation = OperationCancellationToken()

        let result = PDFComparisonService.compare(
            request(left: document, pageCount: 1, right: document),
            progress: { _ in cancellation.cancel() },
            isCancelled: { cancellation.isCancelled }
        )

        XCTAssertEqual(result.status, .cancelled)
        XCTAssertEqual(result.pairs.count, 1)
    }

    func testCancellationOnFortyPageSyntheticFixtureStopsAfterFirstPair() throws {
        let pageTexts = (1...40).map { "Synthetic comparison page \($0)" }
        let document = try makePDFData(pageTexts: pageTexts)
        let cancellation = OperationCancellationToken()
        let clock = ContinuousClock()
        let start = clock.now

        let result = PDFComparisonService.compare(
            request(left: document, pageCount: pageTexts.count, right: document),
            progress: { _ in cancellation.cancel() },
            isCancelled: { cancellation.isCancelled }
        )

        let duration = start.duration(to: clock.now)
        print("Comparison cancellation measurement: 40 US-Letter text pages, \(duration)")
        XCTAssertEqual(result.status, .cancelled)
        XCTAssertEqual(result.pairs.count, 1)
    }

    private func request(
        left: Data,
        pageCount: Int,
        right: Data
    ) -> PDFComparisonService.Request {
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

    private func makePDFData(pageTexts: [String]) throws -> Data {
        let pdf = PDFDocument()
        for (index, text) in pageTexts.enumerated() {
            let view = FixturePageView(
                frame: CGRect(x: 0, y: 0, width: 612, height: 792),
                text: text
            )
            let pageData = view.dataWithPDF(inside: view.bounds)
            guard let pageDocument = PDFDocument(data: pageData),
                  let page = pageDocument.page(at: 0) else {
                throw XCTSkip("fixture page rendering failed")
            }
            pdf.insert(page, at: index)
        }
        return try XCTUnwrap(pdf.dataRepresentation())
    }
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
            withAttributes: [
                .font: NSFont(name: "Helvetica", size: 14) ?? .systemFont(ofSize: 14),
                .foregroundColor: NSColor.black
            ]
        )
    }
}
