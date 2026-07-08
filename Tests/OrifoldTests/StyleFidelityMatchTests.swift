import PDFKit
import XCTest
@testable import Orifold

/// WP-4: Match Format must infer the nearby body style and exclude table cells (when the
/// target is outside a grid) and standalone list markers. Detected-font surfacing is
/// covered indirectly via the analysis the menu builds on.
final class StyleFidelityMatchTests: XCTestCase {
    private func makeViewModel(from data: Data) throws -> WorkspaceViewModel {
        let wrapper = FileWrapper(regularFileWithContents: data)
        wrapper.preferredFilename = "Style.pdf"
        let document = try WorkspaceDocument(testingFile: wrapper, contentType: .pdf, filename: "Style.pdf")
        return WorkspaceViewModel(document: document, processingEngine: PDFiumProcessingEngine())
    }

    /// On the mixed-font fixture, clicking blank space near the body paragraph must infer a
    /// body-sized style (~10pt Helvetica), not the 13pt bold heading and not the italic caption.
    func testMatchInfersBodyNotHeadingOrCaption() throws {
        let data = EditingFixturePDFBuilder.mixedFonts()
        let viewModel = try makeViewModel(from: data)
        let page = try XCTUnwrap(viewModel.loadedPDFs.first?.1.page(at: 0))
        let memberData = try XCTUnwrap(viewModel.document.memberPDFData.values.first)
        let analysis = PDFTextAnalysisEngine().analyze(data: memberData, pageIndex: 0, pageRefID: UUID(), fallbackPage: page)
        let body = try XCTUnwrap(analysis.blocks.first { $0.text.contains("body paragraph") })

        // Click just below the body line — an insertion whose match should be body style.
        let click = CGPoint(x: body.bounds.minX + 10, y: body.bounds.minY - 6)
        let target = try XCTUnwrap(viewModel.editableTextBlock(at: click, on: page, in: viewModel.combinedPDF))
        XCTAssertEqual(target.matchFormat.fontSize, 10, accuracy: 1.5,
                       "Match must infer ~10pt body, not the 13pt heading; got \(target.matchFormat.fontSize)")
        XCTAssertFalse(target.matchFormat.fontName.lowercased().contains("italic"),
                       "Match must not pick the italic caption as the body style")
    }

    /// On the table fixture, editing text OUTSIDE the grid (the heading area) must not adopt
    /// a table cell's style as the body source.
    func testMatchExcludesTableCellsWhenTargetOutsideGrid() throws {
        let data = EditingFixturePDFBuilder.tableWithRules()
        let viewModel = try makeViewModel(from: data)
        let page = try XCTUnwrap(viewModel.loadedPDFs.first?.1.page(at: 0))
        let memberData = try XCTUnwrap(viewModel.document.memberPDFData.values.first)
        let analysis = PDFTextAnalysisEngine().analyze(data: memberData, pageIndex: 0, pageRefID: UUID(), fallbackPage: page)
        let heading = try XCTUnwrap(analysis.blocks.first { $0.text.contains("Quarterly Summary") })

        // Confirm the grid is detected and the heading is outside it.
        XCTAssertFalse(analysis.graphics.isInsideRuledGrid(heading.bounds.standardized),
                       "the heading sits outside the ruled grid")
        let anyCellInGrid = analysis.blocks.contains { $0.text.contains("North") && analysis.graphics.isInsideRuledGrid($0.bounds.standardized) }
        XCTAssertTrue(anyCellInGrid, "a body cell must be recognized as inside the grid")

        // Click near the heading; the inferred match must not be a table cell's tiny style.
        let target = try XCTUnwrap(viewModel.editableTextBlock(
            at: CGPoint(x: heading.bounds.midX, y: heading.bounds.midY), on: page, in: viewModel.combinedPDF))
        // The heading itself is the clicked block; matchFormat should come from a non-cell
        // neighbor. There are few non-cell blocks here, so at minimum it must not equal a
        // known cell's geometry/size drawn from inside the grid.
        let cell = try XCTUnwrap(analysis.blocks.first { $0.text == "North" })
        XCTAssertFalse(abs(target.matchFormat.fontSize - cell.fontSize) < 0.1 && target.matchFormat.bounds == cell.bounds,
                       "Match on the heading must not adopt a table cell's style/geometry")
    }
}
