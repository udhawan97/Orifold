import PDFKit
import XCTest
@testable import Orifold

/// Loop 2 coverage for the format-inference contract: Match Format must adopt a NEARBY
/// body-paragraph style, not the target's own style (Reset's job), not the bold heading
/// below it, and not the table below it — the exact page-2 requirement from the
/// editing-experience hardening spec ("text near 'maximus ultricies' must match the
/// nearby body paragraph, not the bold heading and not the table").
final class MatchFormatInferenceTests: XCTestCase {
    private static let fixtureURL = URL(fileURLWithPath: "/Users/umang/Documents/development/test-files-Orifold/test-text-edit-latest.pdf")

    private func loadViewModel() throws -> WorkspaceViewModel {
        guard FileManager.default.fileExists(atPath: Self.fixtureURL.path) else {
            throw XCTSkip("test-text-edit-latest.pdf not present (expected outside the repo)")
        }
        let data = try Data(contentsOf: Self.fixtureURL)
        let wrapper = FileWrapper(regularFileWithContents: data)
        wrapper.preferredFilename = "test-text-edit-latest.pdf"
        let document = try WorkspaceDocument(testingFile: wrapper, contentType: .pdf, filename: "test-text-edit-latest.pdf")
        return WorkspaceViewModel(document: document, processingEngine: PDFiumProcessingEngine())
    }

    /// The core page-2 inference: clicking to insert near the body paragraph must produce
    /// a `matchFormat` in the body-text size range (~10.2pt Helvetica), NOT the 17pt
    /// bold heading below it, and NOT the ~8pt table text.
    func testMatchFormatInfersBodyParagraphNotHeadingOrTable() throws {
        let viewModel = try loadViewModel()
        let page = try XCTUnwrap(viewModel.loadedPDFs.first?.1.page(at: 1))
        let data = try XCTUnwrap(viewModel.document.memberPDFData.values.first)
        let analysis = PDFTextAnalysisEngine().analyze(data: data, pageIndex: 1, pageRefID: UUID(), fallbackPage: page)
        let bodyParagraph = try XCTUnwrap(analysis.blocks.first { $0.text.contains("maximus ultricies") })

        // Click on a blank spot just below the body paragraph's baseline — an insertion.
        let click = CGPoint(x: bodyParagraph.bounds.minX + 30, y: bodyParagraph.bounds.minY - 8)
        let target = try XCTUnwrap(viewModel.editableTextBlock(at: click, on: page, in: viewModel.combinedPDF))
        XCTAssertEqual(target.block.editability, .insertion, "clicking blank space near the paragraph is an insertion")

        // The inferred match style must be body-sized, not heading-sized (17.7pt bold) and
        // not table-sized (~8.5pt). The surrounding body runs sit near 10.2pt Helvetica.
        let matched = target.matchFormat
        XCTAssertEqual(matched.fontSize, 10.2, accuracy: 1.6,
                       "Match must infer the nearby body paragraph size (~10pt), not the bold heading (17pt) or table text (~8.5pt); got \(matched.fontSize)")
        XCTAssertFalse(matched.fontName.lowercased().contains("bold"),
                       "Match must not pick the bold heading as the body style source; got \(matched.fontName)")
    }

    /// Match Format on a heading must NOT re-suggest the heading's own (bold, 17pt) style —
    /// it should infer the dominant body style, distinct from the clicked block.
    func testMatchFormatOnHeadingInfersBodyNotItself() throws {
        let viewModel = try loadViewModel()
        let page = try XCTUnwrap(viewModel.loadedPDFs.first?.1.page(at: 1))
        let data = try XCTUnwrap(viewModel.document.memberPDFData.values.first)
        let analysis = PDFTextAnalysisEngine().analyze(data: data, pageIndex: 1, pageRefID: UUID(), fallbackPage: page)
        let heading = try XCTUnwrap(analysis.blocks.first { $0.fontName.contains("Bold") && $0.fontSize > 15 })

        let target = try XCTUnwrap(viewModel.editableTextBlock(
            at: CGPoint(x: heading.bounds.midX, y: heading.bounds.midY),
            on: page,
            in: viewModel.combinedPDF
        ))
        XCTAssertTrue(target.block.fontName.contains("Bold"), "clicked the heading itself")
        // sourceFormat is the heading's own style (what Reset restores).
        XCTAssertTrue(target.sourceFormat.fontName.contains("Bold"))
        // matchFormat must differ — the inferred body style, much smaller and not bold.
        XCTAssertLessThan(target.matchFormat.fontSize, heading.fontSize - 3,
                          "Match on a heading must infer a smaller body style, not the heading's own 17pt")
        XCTAssertFalse(target.matchFormat.fontName.lowercased().contains("bold"),
                       "inferred body style must not be the bold heading")
    }
}
