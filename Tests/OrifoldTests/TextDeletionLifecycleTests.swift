import PDFKit
import XCTest
@testable import Orifold

/// WP-3: emptying a text block and committing is a DELETION — the visible text is removed,
/// survives export + reopen, and undo/redo restore/remove it. Previously empty text was
/// silently treated as Cancel, so the app "kept restoring" the text the user tried to delete.
final class TextDeletionLifecycleTests: XCTestCase {
    private func makeViewModel(from data: Data, name: String = "DeleteFixture") throws -> WorkspaceViewModel {
        let wrapper = FileWrapper(regularFileWithContents: data)
        wrapper.preferredFilename = "\(name).pdf"
        let document = try WorkspaceDocument(testingFile: wrapper, contentType: .pdf, filename: "\(name).pdf")
        return WorkspaceViewModel(document: document, processingEngine: PDFiumProcessingEngine())
    }

    /// Dark-pixel count in a page region — the VISUAL check. Deletion here is visual
    /// (an erase patch over the text): the glyphs remain in the content stream and stay
    /// extractable (documented "erase is visual-only" limitation, not secure redaction),
    /// so correctness is measured by what the user SEES, not by text extraction.
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

    private func livePage(_ viewModel: WorkspaceViewModel, _ index: Int) -> PDFPage? {
        guard let pdf = viewModel.loadedPDFs.first?.1, let data = pdf.dataRepresentation() else { return nil }
        return PDFDocument(data: data)?.page(at: index)
    }

    /// Full deletion lifecycle, verified VISUALLY (pixels), the way the user judges "gone".
    func testEmptyEditDeletesVisibleTextAndSurvivesExportReopen() throws {
        let data = EditingFixturePDFBuilder.makePDF(runs: [
            .init(string: "Keep this line", origin: CGPoint(x: 72, y: 720), fontSize: 12),
            .init(string: "DELETEME name here", origin: CGPoint(x: 72, y: 690), fontSize: 12)
        ])
        let viewModel = try makeViewModel(from: data)
        let undoManager = UndoManager()
        viewModel.undoManager = undoManager

        let memberData = try XCTUnwrap(viewModel.document.memberPDFData.values.first)
        let page = try XCTUnwrap(viewModel.loadedPDFs.first?.1.page(at: 0))
        let analysis = PDFTextAnalysisEngine().analyze(data: memberData, pageIndex: 0, pageRefID: UUID(), fallbackPage: page)
        let target = try XCTUnwrap(analysis.blocks.first { $0.text.contains("DELETEME") })
        let deletedRegion = target.bounds.standardized
        let keepRegion = try XCTUnwrap(analysis.blocks.first { $0.text.contains("Keep") }).bounds.standardized

        XCTAssertGreaterThan(try darkPixels(on: page, in: deletedRegion), 0, "sanity: text is inked before deletion")

        XCTAssertTrue(viewModel.applyInlineTextEdit(
            pageRef: try XCTUnwrap(viewModel.document.workspace.pageOrder.first),
            sourceBlock: target,
            replacementText: "",
            editedBounds: target.bounds,
            fontName: target.fontName,
            fontSize: target.fontSize,
            textColor: .black,
            alignment: .left
        ))

        // Visually gone; the sibling line still inked.
        let afterPage = try XCTUnwrap(livePage(viewModel, 0))
        XCTAssertEqual(try darkPixels(on: afterPage, in: deletedRegion), 0, "the deleted text must be visually gone")
        XCTAssertGreaterThan(try darkPixels(on: afterPage, in: keepRegion), 0, "the untouched line must remain visible")

        // Export + reopen: still visually gone.
        let outURL = FileManager.default.temporaryDirectory.appendingPathComponent("Orifold-delete-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: outURL) }
        XCTAssertTrue(viewModel.saveFlattenedPDF(to: outURL))
        let reopened = try XCTUnwrap(PDFDocument(data: Data(contentsOf: outURL)))
        let reopenedPage = try XCTUnwrap(reopened.page(at: 0))
        XCTAssertEqual(try darkPixels(on: reopenedPage, in: deletedRegion), 0, "deletion must survive export + reopen (visually)")

        // Undo restores the ink, redo removes it again.
        undoManager.undo()
        XCTAssertGreaterThan(try darkPixels(on: try XCTUnwrap(livePage(viewModel, 0)), in: deletedRegion), 0, "undo must restore the deleted text")
        undoManager.redo()
        XCTAssertEqual(try darkPixels(on: try XCTUnwrap(livePage(viewModel, 0)), in: deletedRegion), 0, "redo must remove it again")
    }

    /// The committed operation for a deletion is a real op (not skipped), with empty
    /// replacement and the original text preserved for undo/inspector history.
    func testDeletionCommitsRealOperation() throws {
        let data = EditingFixturePDFBuilder.makePDF(runs: [
            .init(string: "Removable text", origin: CGPoint(x: 72, y: 700), fontSize: 12)
        ])
        let viewModel = try makeViewModel(from: data)
        let memberData = try XCTUnwrap(viewModel.document.memberPDFData.values.first)
        let page = try XCTUnwrap(viewModel.loadedPDFs.first?.1.page(at: 0))
        let target = try XCTUnwrap(PDFTextAnalysisEngine().analyze(data: memberData, pageIndex: 0, pageRefID: UUID(), fallbackPage: page).blocks.first)

        XCTAssertTrue(viewModel.applyInlineTextEdit(
            pageRef: try XCTUnwrap(viewModel.document.workspace.pageOrder.first),
            sourceBlock: target,
            replacementText: "",
            editedBounds: target.bounds,
            fontName: target.fontName,
            fontSize: target.fontSize,
            textColor: .black,
            alignment: .left
        ))
        let op = try XCTUnwrap(viewModel.document.workspace.pageEditStates.first?.operations.first)
        XCTAssertTrue(op.replacementText.isEmpty, "a deletion op carries empty replacement text")
        XCTAssertFalse(op.isInsertion, "deleting existing text is not an insertion")
        XCTAssertTrue(op.sourceText.contains("Removable"), "the original text is preserved for undo/history")
    }
}
