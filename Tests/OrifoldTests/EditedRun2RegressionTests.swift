import PDFKit
import XCTest
@testable import Orifold

/// Regression tests against the real user fixture `editedrun2.pdf`. CI-SAFE: every test
/// skips cleanly when the file is absent (it lives outside the repo). Pins the concrete
/// page-1 header-merge and page-2 body-style failures the user reported.
final class EditedRun2RegressionTests: XCTestCase {
    private static let url = URL(fileURLWithPath: "/Users/umang/Documents/development/test-files-Orifold/editedrun2.pdf")

    private func loadViewModel() throws -> WorkspaceViewModel {
        guard FileManager.default.fileExists(atPath: Self.url.path) else {
            throw XCTSkip("editedrun2.pdf not present (expected outside the repo)")
        }
        let data = try Data(contentsOf: Self.url)
        let wrapper = FileWrapper(regularFileWithContents: data)
        wrapper.preferredFilename = "editedrun2.pdf"
        let document = try WorkspaceDocument(testingFile: wrapper, contentType: .pdf, filename: "editedrun2.pdf")
        return WorkspaceViewModel(document: document, processingEngine: PDFiumProcessingEngine())
    }

    private func analysis(_ viewModel: WorkspaceViewModel, page pageIndex: Int) throws -> PDFTextPageAnalysis {
        let data = try XCTUnwrap(viewModel.document.memberPDFData.values.first)
        let page = try XCTUnwrap(viewModel.loadedPDFs.first?.1.page(at: pageIndex))
        return PDFTextAnalysisEngine().analyze(data: data, pageIndex: pageIndex, pageRefID: UUID(), fallbackPage: page)
    }

    /// Page 1: tapping a header detail line returns only that line, not the merged title block.
    func testPage1HeaderLinesAreSeparate() throws {
        let viewModel = try loadViewModel()
        let a = try analysis(viewModel, page: 0)
        let page = try XCTUnwrap(viewModel.loadedPDFs.first?.1.page(at: 0))

        func tappedBlockText(containing needle: String) throws -> String {
            let block = try XCTUnwrap(a.blocks.first { $0.text.contains(needle) }, "‘\(needle)’ must be detected")
            let target = try XCTUnwrap(viewModel.editableTextBlock(
                at: CGPoint(x: block.bounds.midX, y: block.bounds.midY), on: page, in: viewModel.combinedPDF))
            return target.block.text
        }

        let demoClient = try tappedBlockText(containing: "Demo Client")
        XCTAssertFalse(demoClient.contains("SAMPLE PROJECT"), "tapping 'Demo Client' must not select the title")
        XCTAssertFalse(demoClient.contains("OVERVIEW"), "tapping 'Demo Client' must not merge the OVERVIEW header")

        if a.blocks.contains(where: { $0.text.contains("January 2026") }) {
            let date = try tappedBlockText(containing: "January 2026")
            XCTAssertFalse(date.contains("SAMPLE PROJECT"), "tapping the date must not include the title")
        }

        if a.blocks.contains(where: { $0.text == "OVERVIEW" || $0.text.hasPrefix("OVERVIEW") }) {
            let overview = try tappedBlockText(containing: "OVERVIEW")
            XCTAssertFalse(overview.contains("SAMPLE"), "OVERVIEW must not merge with the title")
            XCTAssertFalse(overview.contains("Demo Client"), "OVERVIEW must not merge with prepared-for")
        }
    }

    /// Page 2: tapping the first body paragraph resolves body text, and Match infers a body
    /// style (Helvetica ~10-11), not a heading (17-27pt bold) or a bullet.
    func testPage2BodyMatchInfersBodyStyle() throws {
        let viewModel = try loadViewModel()
        let a = try analysis(viewModel, page: 1)
        let page = try XCTUnwrap(viewModel.loadedPDFs.first?.1.page(at: 1))
        let firstPara = try XCTUnwrap(a.blocks.first { $0.text.contains("Vestibulum neque") }, "first body paragraph must be detected")
        let target = try XCTUnwrap(viewModel.editableTextBlock(
            at: CGPoint(x: firstPara.bounds.midX, y: firstPara.bounds.midY), on: page, in: viewModel.combinedPDF))

        XCTAssertLessThan(target.matchFormat.fontSize, 15, "Match must infer a body size (~10-11pt), not a 17-27pt heading; got \(target.matchFormat.fontSize)")
        XCTAssertGreaterThan(target.matchFormat.fontSize, 8, "Match body size sanity floor; got \(target.matchFormat.fontSize)")
    }

    /// Page 1: editing a header line keeps it one line at its original size (no reflow/enlarge).
    func testPage1HeaderEditStaysOneLine() throws {
        let viewModel = try loadViewModel()
        let a = try analysis(viewModel, page: 0)
        let page = try XCTUnwrap(viewModel.loadedPDFs.first?.1.page(at: 0))
        let block = try XCTUnwrap(a.blocks.first { $0.text.contains("Demo Client") })
        let target = try XCTUnwrap(viewModel.editableTextBlock(
            at: CGPoint(x: block.bounds.midX, y: block.bounds.midY), on: page, in: viewModel.combinedPDF))
        let sourceSize = target.block.fontSize
        XCTAssertEqual(target.block.lines.count, 1, "the tapped header block is a single line")

        XCTAssertTrue(viewModel.applyInlineTextEdit(
            pageRef: target.pageRef, sourceBlock: target.block,
            replacementText: "Prepared for: New Client",
            editedBounds: target.block.bounds,
            fontName: target.block.fontName, fontSize: target.block.fontSize,
            textColor: target.block.textColor.nsColor, alignment: (target.block.alignment ?? .left).nsTextAlignment))
        let op = try XCTUnwrap(viewModel.document.workspace.pageEditStates.first?.operations.first)
        XCTAssertEqual(op.fontSize, sourceSize, accuracy: sourceSize * 0.06, "committed size within 6% of source")
        XCTAssertLessThanOrEqual(op.editedBounds.height, block.bounds.height * 1.7, "committed box stays one line tall")
    }
}
