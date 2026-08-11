import XCTest
import PDFKit
@testable import Orifold

/// View-model half of blank-page removal: detection proposes candidate `PageRef`s for a
/// review sheet; actual deletion goes through the shipped `deletePages`.
@MainActor
final class BlankPageRemovalTests: XCTestCase {

    func testDetectBlankPagesProposesExactlyTheBlankRefsInOrder() async throws {
        let viewModel = try makeViewModel(from: makePDFData(kinds: [.white, .text, .white, .text]))
        await viewModel.detectBlankPages()
        let order = viewModel.document.workspace.pageOrder
        XCTAssertEqual(viewModel.blankPageReview?.refs.map(\.id), [order[0].id, order[2].id])
    }

    func testDetectBlankPagesWithNoBlanksReportsNoneFound() async throws {
        let viewModel = try makeViewModel(from: makePDFData(kinds: [.text, .text]))
        await viewModel.detectBlankPages()
        XCTAssertNil(viewModel.blankPageReview)
        XCTAssertTrue(viewModel.blankPageDetectionFoundNothing)
    }

    func testConfirmingReviewDeletesTheCandidatePages() async throws {
        let viewModel = try makeViewModel(from: makePDFData(kinds: [.white, .text, .white, .text]))
        await viewModel.detectBlankPages()
        let review = try XCTUnwrap(viewModel.blankPageReview)
        viewModel.removeBlankPages(review.refs)
        XCTAssertEqual(viewModel.pageCount, 2)
        XCTAssertNil(viewModel.blankPageReview)
    }

    // MARK: - Fixtures

    private enum PageKind { case white, text }

    private func makePDFData(kinds: [PageKind]) throws -> Data {
        let pdf = PDFDocument()
        for (index, kind) in kinds.enumerated() {
            let size = CGSize(width: 300, height: 300)
            let image = NSImage(size: size)
            image.lockFocus()
            NSColor.white.setFill()
            NSRect(origin: .zero, size: size).fill()
            if case .text = kind {
                ("Body text that clearly is not blank" as NSString).draw(
                    in: NSRect(x: 10, y: 30, width: 280, height: 240),
                    withAttributes: [.font: NSFont.systemFont(ofSize: 28), .foregroundColor: NSColor.black]
                )
            }
            image.unlockFocus()
            let page = try XCTUnwrap(PDFPage(image: image))
            pdf.insert(page, at: index)
        }
        return try XCTUnwrap(PDFSerializer.data(from: pdf))
    }

    private func makeViewModel(from data: Data) throws -> WorkspaceViewModel {
        let wrapper = FileWrapper(regularFileWithContents: data)
        wrapper.preferredFilename = "BlankFixture.pdf"
        let document = try WorkspaceDocument(testingFile: wrapper, contentType: .pdf, filename: "BlankFixture.pdf")
        return WorkspaceViewModel(document: document, processingEngine: PDFiumProcessingEngine())
    }
}
