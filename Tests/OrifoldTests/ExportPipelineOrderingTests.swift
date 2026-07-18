import AppKit
import PDFKit
import XCTest
@testable import Orifold

/// The export pipeline's stage ORDER is load-bearing and its failures are silent:
///
/// - Imposition must run after the decoration bake. `FPDF_ImportNPagesToOne`
///   rebuilds pages as form XObjects and drops any annotation still live, so
///   imposing first yields a structurally valid PDF with the stamps simply gone.
/// - Attachments must be re-grafted after every page-content pass (assembly,
///   compression, imposition all drop them) but before sanitize, which
///   deliberately strips embedded files.
///
/// Neither combination was covered: the imposition suite feeds synthetic
/// fixtures with nothing to lose, and the decoration/attachment suites never
/// switch imposition on. These exercise the real export path with both at once.
final class ExportPipelineOrderingTests: XCTestCase {
    private var retainedUndoManager: UndoManager?

    /// Four US-Letter pages, each with a distinguishing glyph, so imposition has
    /// something to lay out and the assertions have real content to find.
    private func makeFourPagePDF() throws -> Data {
        let data = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        let consumer = try XCTUnwrap(CGDataConsumer(data: data as CFMutableData))
        let ctx = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &mediaBox, nil))
        for _ in 0..<4 {
            ctx.beginPDFPage(nil)
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fill(mediaBox)
            ctx.endPDFPage()
        }
        ctx.closePDF()
        return data as Data
    }

    private func makeViewModel() throws -> WorkspaceViewModel {
        let wrapper = FileWrapper(regularFileWithContents: try makeFourPagePDF())
        wrapper.preferredFilename = "impose.pdf"
        let document = try WorkspaceDocument(testingFile: wrapper, contentType: .pdf, filename: "impose.pdf")
        let viewModel = WorkspaceViewModel(document: document, processingEngine: PDFiumProcessingEngine())
        let undo = UndoManager()
        retainedUndoManager = undo
        viewModel.undoManager = undo
        return viewModel
    }

    /// Puts a solid-black image decoration on the first page. Deliberately an image
    /// rather than a text stamp: a stamp renders as a light tinted wash (~0.93
    /// brightness) that is hard to tell from paper, whereas solid black makes "did
    /// this survive?" an unambiguous pixel question — never a text-extraction one.
    private func addBlackDecoration(to viewModel: WorkspaceViewModel) throws {
        let pageRef = try XCTUnwrap(viewModel.document.workspace.pageOrder.first)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 64, pixelsHigh: 64, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.black.setFill()
        NSRect(x: 0, y: 0, width: 64, height: 64).fill()
        NSGraphicsContext.restoreGraphicsState()
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))

        viewModel.document.workspace.decorations.append(PageDecoration.image(
            imageData: png,
            pageRefID: pageRef.id,
            rect: CGRect(x: 40, y: 300, width: 400, height: 160)
        ))
    }

    /// Fraction of sampled pixels that are visibly non-white, across the whole sheet.
    /// A blank imposed sheet stays ~0; a sheet carrying the baked stamp does not.
    private func inkCoverage(of data: Data, pageIndex: Int = 0) throws -> Double {
        let pdf = try XCTUnwrap(PDFDocument(data: data))
        let page = try XCTUnwrap(pdf.page(at: pageIndex))
        let bounds = page.bounds(for: .mediaBox)
        let thumbnail = page.thumbnail(of: CGSize(width: bounds.width, height: bounds.height), for: .mediaBox)
        let tiff = try XCTUnwrap(thumbnail.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))

        var inked = 0
        var sampled = 0
        for px in stride(from: 0, to: bitmap.pixelsWide, by: 7) {
            for py in stride(from: 0, to: bitmap.pixelsHigh, by: 7) {
                guard let color = bitmap.colorAt(x: px, y: py)?.usingColorSpace(.deviceRGB) else { continue }
                sampled += 1
                if color.brightnessComponent < 0.85 { inked += 1 }
            }
        }
        guard sampled > 0 else { return 0 }
        return Double(inked) / Double(sampled)
    }

    // Imposition after the bake: the stamp is flattened into page content before
    // N-up rebuilds the pages, so it survives onto the imposed sheet. Imposing
    // first would produce a valid PDF with no stamp and no error.
    func testDecorationSurvivesAnImposedExport() throws {
        let viewModel = try makeViewModel()
        try addBlackDecoration(to: viewModel)

        let plain = try viewModel.dataForPDFExport()
        let plainCoverage = try inkCoverage(of: plain)
        XCTAssertGreaterThan(plainCoverage, 0.01,
                             "precondition: the stamp bakes into a normal export")

        let imposed = try viewModel.dataForPDFExport(
            options: WorkspaceExportOptions(imposition: .nUp(rows: 1, cols: 2)))

        let imposedPDF = try XCTUnwrap(PDFDocument(data: imposed))
        XCTAssertEqual(imposedPDF.pageCount, 2, "4 pages 2-up should impose onto 2 sheets")
        XCTAssertGreaterThan(try inkCoverage(of: imposed), 0.005,
                             "the baked stamp must survive imposition — imposing before the bake drops it silently")
    }

    // Attachments are re-grafted after imposition (which drops them) and before
    // sanitize (which strips them deliberately).
    func testAttachmentSurvivesAnImposedExport() throws {
        let viewModel = try makeViewModel()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Orifold-impose-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let payloadURL = directory.appendingPathComponent("note.txt")
        try Data("attach-me".utf8).write(to: payloadURL)

        XCTAssertTrue(viewModel.addAttachment(payloadURL))

        let imposed = try viewModel.dataForPDFExport(
            options: WorkspaceExportOptions(imposition: .nUp(rows: 1, cols: 2)))

        XCTAssertEqual(try AttachmentsService.list(in: imposed).map(\.name), ["note.txt"],
                       "attachments must be re-grafted after the imposition pass that drops them")
    }

    // The other half of that ordering rule: re-injection happens BEFORE sanitize,
    // so asking for both still strips the attachments. That is a deliberate product
    // decision — sanitize-for-sharing removes embedded files — and it currently
    // lives only in a comment beside the call.
    func testSanitizeStillStripsAttachmentsWhenCombinedWithImposition() throws {
        let viewModel = try makeViewModel()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Orifold-impose-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let payloadURL = directory.appendingPathComponent("note.txt")
        try Data("attach-me".utf8).write(to: payloadURL)
        XCTAssertTrue(viewModel.addAttachment(payloadURL))

        let sanitized = try viewModel.dataForPDFExport(options: WorkspaceExportOptions(
            sanitization: PDFSanitizationOptions(removesMetadata: false),
            imposition: .nUp(rows: 1, cols: 2)
        ))

        XCTAssertEqual(try AttachmentsService.list(in: sanitized), [],
                       "sanitize runs after re-injection and must still strip embedded files")
    }
}
