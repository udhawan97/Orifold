import PDFKit
import XCTest
@testable import Orifold

/// WP-C: editing a one-line header block must not enlarge the font or reflow the text onto
/// new lines. Verified at the committed-operation + rendered-pixel level (the editor overlay
/// sizes from the block, so the committed geometry is the deterministic proxy for "no
/// reflow"); the interactive overlay's cancel/no-op semantics are covered by the existing
/// InlineEditorFormatUXTests / editor-lifecycle suites.
final class EditorNoReflowTests: XCTestCase {
    private func makeViewModel(from data: Data) throws -> WorkspaceViewModel {
        let wrapper = FileWrapper(regularFileWithContents: data)
        wrapper.preferredFilename = "Header.pdf"
        let document = try WorkspaceDocument(testingFile: wrapper, contentType: .pdf, filename: "Header.pdf")
        return WorkspaceViewModel(document: document, processingEngine: PDFiumProcessingEngine())
    }

    private func darkPixels(on page: PDFPage, in region: CGRect) throws -> Int {
        let bounds = page.bounds(for: .mediaBox)
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(bounds.width), pixelsHigh: Int(bounds.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        let ctx = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: rep)?.cgContext)
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(CGRect(origin: .zero, size: bounds.size))
        page.draw(with: .mediaBox, to: ctx)
        var count = 0
        let clamped = region.standardized
        for y in stride(from: max(0, Int(clamped.minY)), to: min(Int(bounds.height), Int(clamped.maxY)), by: 1) {
            for x in stride(from: max(0, Int(clamped.minX)), to: min(Int(bounds.width), Int(clamped.maxX)), by: 1) {
                guard let color = rep.colorAt(x: x, y: Int(bounds.height) - y - 1)?.usingColorSpace(.sRGB) else { continue }
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                color.getRed(&r, green: &g, blue: &b, alpha: &a)
                if a > 0.5, max(r, g, b) < 0.5 { count += 1 }
            }
        }
        return count
    }

    func testEditingHeaderLineStaysOneLineAndKeepsFontSize() throws {
        let data = EditingFixturePDFBuilder.monospacedHeaderPage()
        let viewModel = try makeViewModel(from: data)
        let memberData = try XCTUnwrap(viewModel.document.memberPDFData.values.first)
        let page = try XCTUnwrap(viewModel.loadedPDFs.first?.1.page(at: 0))
        let analysis = PDFTextAnalysisEngine().analyze(data: memberData, pageIndex: 0, pageRefID: UUID(), fallbackPage: page)
        let block = try XCTUnwrap(analysis.blocks.first { $0.text.contains("Demo Client") })
        XCTAssertEqual(block.lines.count, 1, "the header line is a single line before editing")
        let sourceSize = block.fontSize
        let lineHeight = block.bounds.height

        let target = try XCTUnwrap(viewModel.editableTextBlock(
            at: CGPoint(x: block.bounds.midX, y: block.bounds.midY), on: page, in: viewModel.combinedPDF))
        XCTAssertFalse(target.block.text.contains("SAMPLE PROJECT"), "hit-test must NOT return the merged title block")
        XCTAssertEqual(target.block.fontSize, sourceSize, accuracy: 0.5, "opening the editor must not change the detected size")

        XCTAssertTrue(viewModel.applyInlineTextEdit(
            pageRef: target.pageRef, sourceBlock: target.block,
            replacementText: "Prepared for: Demo Person",   // same length class, one line
            editedBounds: target.block.bounds,
            fontName: target.block.fontName, fontSize: target.block.fontSize,
            textColor: target.block.textColor.nsColor, alignment: (target.block.alignment ?? .left).nsTextAlignment
        ))
        let op = try XCTUnwrap(viewModel.document.workspace.pageEditStates.first?.operations.first)
        XCTAssertEqual(op.fontSize, sourceSize, accuracy: sourceSize * 0.06, "committed font size within 6% of source (no enlargement)")
        XCTAssertLessThanOrEqual(op.editedBounds.height, lineHeight * 1.7, "the committed box must stay one line tall (no reflow)")

        // Rendered check: the new text renders on the original line's y-band. (A below-band
        // pixel check isn't reliable here — the header lines are only ~20pt apart, so any
        // band below one line overlaps the next header line's ink. The op geometry above is
        // the deterministic "no reflow" signal: a reflow would have grown editedBounds.height
        // past a single line.)
        let live = try XCTUnwrap(viewModel.loadedPDFs.first?.1.page(at: 0))
        let lineBand = CGRect(x: block.bounds.minX, y: block.bounds.minY - 1, width: 260, height: block.bounds.height + 2)
        XCTAssertGreaterThan(try darkPixels(on: live, in: lineBand), 0, "edited text renders on its original line")
    }

    /// Reading the block / opening the editor path must not mutate the document (no op
    /// created just by resolving the editable block).
    func testResolvingEditableBlockDoesNotMutate() throws {
        let data = EditingFixturePDFBuilder.monospacedHeaderPage()
        let viewModel = try makeViewModel(from: data)
        let page = try XCTUnwrap(viewModel.loadedPDFs.first?.1.page(at: 0))
        _ = viewModel.editableTextBlock(at: CGPoint(x: 100, y: 710), on: page, in: viewModel.combinedPDF)
        XCTAssertTrue(viewModel.document.workspace.pageEditStates.allSatisfy { $0.operations.isEmpty },
                      "resolving an editable block must not create an edit operation")
        // Text content still analyzes identically (dataRepresentation() re-serializes with
        // non-deterministic byte ordering, so compare analyzed text, not raw bytes).
        let after = try XCTUnwrap(viewModel.loadedPDFs.first?.1.dataRepresentation())
        let afterText = PDFTextAnalysisEngine()
            .analyze(data: after, pageIndex: 0, pageRefID: UUID(), fallbackPage: page)
            .blocks.map(\.text).joined(separator: " ")
        XCTAssertTrue(afterText.contains("Demo Client"), "content unchanged after resolving an editable block")
    }
}
