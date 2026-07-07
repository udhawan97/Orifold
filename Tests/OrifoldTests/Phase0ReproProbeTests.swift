import PDFKit
import XCTest
@testable import Orifold

/// PHASE 0 PROBE — temporary diagnostic harness against the real user fixture
/// `test-text-edit-latest.pdf` (page 2, paragraph ending "maximus ultricies").
/// Not a durable regression test; prints pipeline state at every stage so the
/// break point can be located precisely. Will be replaced by fixture-based
/// regression tests once the root cause is identified.
final class Phase0ReproProbeTests: XCTestCase {
    private static let fixtureURL = URL(fileURLWithPath: "/Users/umang/Documents/development/test-files-Orifold/test-text-edit-latest.pdf")

    private func loadViewModel() throws -> WorkspaceViewModel {
        let data = try Data(contentsOf: Self.fixtureURL)
        let wrapper = FileWrapper(regularFileWithContents: data)
        wrapper.preferredFilename = "test-text-edit-latest.pdf"
        let document = try WorkspaceDocument(testingFile: wrapper, contentType: .pdf, filename: "test-text-edit-latest.pdf")
        return WorkspaceViewModel(document: document, processingEngine: PDFiumProcessingEngine())
    }

    private func darkPixelCount(on page: PDFPage, in region: CGRect) throws -> Int {
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
        let clamped = region.insetBy(dx: -5, dy: -5)
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

    /// Stage A: what does analysis actually see on page 2?
    func testProbe_A_analyzePage2Blocks() throws {
        let data = try Data(contentsOf: Self.fixtureURL)
        let pdf = try XCTUnwrap(PDFDocument(data: data))
        print("PROBE[A] pageCount=\(pdf.pageCount)")
        let page = try XCTUnwrap(pdf.page(at: 1))
        print("PROBE[A] page2 mediaBox=\(page.bounds(for: .mediaBox)) crop=\(page.bounds(for: .cropBox)) rotation=\(page.rotation)")
        let analysis = PDFTextAnalysisEngine().analyze(data: data, pageIndex: 1, pageRefID: UUID(), fallbackPage: page)
        print("PROBE[A] blocks=\(analysis.blocks.count) source=\(analysis.blocks.first?.textSource.rawValue ?? "n/a")")
        for (i, b) in analysis.blocks.enumerated() {
            let t = b.text.replacingOccurrences(of: "\n", with: "⏎")
            print(String(format: "PROBE[A] #%02d edit=%@ conf=%@ font=%@ size=%.1f color=(%.2f,%.2f,%.2f,%.2f) bounds=(%.1f,%.1f,%.1f,%.1f) lines=%d col=%@ text=%@",
                         i, b.editability.rawValue, b.confidence.rawValue, b.fontName, b.fontSize,
                         b.textColor.red, b.textColor.green, b.textColor.blue, b.textColor.alpha,
                         b.bounds.minX, b.bounds.minY, b.bounds.width, b.bounds.height,
                         b.lines.count,
                         b.columnBounds.map { String(format: "(%.0f..%.0f)", $0.minX, $0.maxX) } ?? "nil",
                         String(t.prefix(70))))
        }
        XCTAssertTrue(analysis.blocks.contains { $0.text.contains("maximus ultricies") }, "target paragraph must be detectable")
    }

    /// Stage B: full user flow — click paragraph line, append ' yolo', Done, export, reopen.
    func testProbe_B_editParagraphFullRoundTrip() throws {
        let viewModel = try loadViewModel()
        let memberPDF = try XCTUnwrap(viewModel.loadedPDFs.first?.1)
        let page = try XCTUnwrap(memberPDF.page(at: 1))
        let data = try XCTUnwrap(viewModel.document.memberPDFData.values.first)
        let analysis = PDFTextAnalysisEngine().analyze(data: data, pageIndex: 1, pageRefID: UUID(), fallbackPage: page)
        let paragraph = try XCTUnwrap(analysis.blocks.first { $0.text.contains("maximus ultricies") })
        print("PROBE[B] paragraph bounds=\(paragraph.bounds) font=\(paragraph.fontName)@\(paragraph.fontSize) editability=\(paragraph.editability.rawValue)")

        // Simulate the click exactly where a user would: middle of the paragraph's last line.
        let lastLine = paragraph.lines.last.map(\.bounds) ?? paragraph.bounds
        let click = CGPoint(x: lastLine.midX, y: lastLine.midY)
        let target = try XCTUnwrap(viewModel.editableTextBlock(at: click, on: page, in: viewModel.combinedPDF))
        print("PROBE[B] clicked block text=\(String(target.block.text.prefix(60))) editability=\(target.block.editability.rawValue) bounds=\(target.block.bounds)")
        print("PROBE[B] sourceFormat font=\(target.sourceFormat.fontName)@\(target.sourceFormat.fontSize) bounds=\(String(describing: target.sourceFormat.bounds))")

        let replacement = target.block.text + " yolo"
        let ok = viewModel.applyInlineTextEdit(
            pageRef: target.pageRef,
            sourceBlock: target.block,
            replacementText: replacement,
            editedBounds: target.block.bounds,
            fontName: target.block.fontName,
            fontSize: target.block.fontSize,
            textColor: target.block.textColor.nsColor,
            alignment: (target.block.alignment ?? .left).nsTextAlignment
        )
        print("PROBE[B] applyInlineTextEdit ok=\(ok) editingStatus=\(String(describing: viewModel.editingStatus))")
        XCTAssertTrue(ok)

        let op = try XCTUnwrap(viewModel.document.workspace.pageEditStates.first?.operations.first)
        print("PROBE[B] committed op editedBounds=\(op.editedBounds) font=\(op.fontName)@\(op.fontSize) color=(\(op.textColor.red),\(op.textColor.green),\(op.textColor.blue),\(op.textColor.alpha)) isInsertion=\(op.isInsertion)")

        // Live document check — what the page shows right after Done.
        let livePage = try XCTUnwrap(viewModel.loadedPDFs.first?.1.page(at: 1))
        let liveText = livePage.attributedString?.string ?? ""
        print("PROBE[B] live page contains yolo=\(liveText.contains("yolo"))")
        let liveDark = try darkPixelCount(on: livePage, in: op.editedBounds)
        print("PROBE[B] live dark pixels in editedBounds=\(liveDark)")

        // Export → reopen fresh.
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("Orifold-phase0-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: outputURL) }
        let saved = viewModel.saveFlattenedPDF(to: outputURL)
        print("PROBE[B] saveFlattenedPDF=\(saved) exportError=\(String(describing: viewModel.exportError))")
        XCTAssertTrue(saved)

        let reopenedData = try Data(contentsOf: outputURL)
        let reopenedPDF = try XCTUnwrap(PDFDocument(data: reopenedData))
        print("PROBE[B] reopened pageCount=\(reopenedPDF.pageCount)")
        var foundOnPage: Int? = nil
        for i in 0..<reopenedPDF.pageCount {
            guard let p = reopenedPDF.page(at: i) else { continue }
            let reAnalysis = PDFTextAnalysisEngine().analyze(data: reopenedData, pageIndex: i, pageRefID: UUID(), fallbackPage: p)
            if reAnalysis.blocks.contains(where: { $0.text.contains("yolo") }) { foundOnPage = i; break }
        }
        print("PROBE[B] reopened export contains yolo on page index=\(String(describing: foundOnPage))")
        XCTAssertNotNil(foundOnPage, "exported+reopened file must contain the committed edit")
        if let idx = foundOnPage, let p = reopenedPDF.page(at: idx) {
            let dark = try darkPixelCount(on: p, in: op.editedBounds)
            print("PROBE[B] reopened dark pixels in editedBounds=\(dark)")
            XCTAssertGreaterThan(dark, 0)
        }
    }

    /// Stage C: same flow but with Match Format pressed (geometry adoption path) before Done.
    func testProbe_C_editWithMatchFormatThenDone() throws {
        let viewModel = try loadViewModel()
        let memberPDF = try XCTUnwrap(viewModel.loadedPDFs.first?.1)
        let page = try XCTUnwrap(memberPDF.page(at: 1))
        let data = try XCTUnwrap(viewModel.document.memberPDFData.values.first)
        let analysis = PDFTextAnalysisEngine().analyze(data: data, pageIndex: 1, pageRefID: UUID(), fallbackPage: page)
        let paragraph = try XCTUnwrap(analysis.blocks.first { $0.text.contains("maximus ultricies") })
        let lastLine = paragraph.lines.last.map(\.bounds) ?? paragraph.bounds
        let click = CGPoint(x: lastLine.midX, y: lastLine.midY)
        let target = try XCTUnwrap(viewModel.editableTextBlock(at: click, on: page, in: viewModel.combinedPDF))

        // Match Format applies sourceFormat (font/size/color/alignment) + geometry.
        let fmt = target.sourceFormat
        let matchedBounds = fmt.bounds ?? target.block.bounds
        print("PROBE[C] matched font=\(fmt.fontName)@\(fmt.fontSize) matchedBounds=\(matchedBounds)")
        let ok = viewModel.applyInlineTextEdit(
            pageRef: target.pageRef,
            sourceBlock: target.block,
            replacementText: target.block.text + " yolo",
            editedBounds: matchedBounds,
            fontName: fmt.fontName,
            fontSize: fmt.fontSize,
            textColor: fmt.textColor.nsColor,
            alignment: fmt.alignment.nsTextAlignment,
            underline: fmt.underline,
            didManuallyChangeStyle: true,
            didApplyMatchedGeometry: true
        )
        print("PROBE[C] applyInlineTextEdit ok=\(ok)")
        XCTAssertTrue(ok)
        let op = try XCTUnwrap(viewModel.document.workspace.pageEditStates.first?.operations.first)
        print("PROBE[C] op editedBounds=\(op.editedBounds)")
        let livePage = try XCTUnwrap(viewModel.loadedPDFs.first?.1.page(at: 1))
        let liveDark = try darkPixelCount(on: livePage, in: op.editedBounds)
        let liveText = livePage.attributedString?.string ?? ""
        print("PROBE[C] live yolo=\(liveText.contains("yolo")) dark=\(liveDark)")
        XCTAssertTrue(liveText.contains("yolo"))
    }

    /// Stage D: click on blank space just below the paragraph (insertion path) — the
    /// literal "add text near that paragraph" reading of the bug report.
    func testProbe_D_insertionNearParagraph() throws {
        let viewModel = try loadViewModel()
        let memberPDF = try XCTUnwrap(viewModel.loadedPDFs.first?.1)
        let page = try XCTUnwrap(memberPDF.page(at: 1))
        let data = try XCTUnwrap(viewModel.document.memberPDFData.values.first)
        let analysis = PDFTextAnalysisEngine().analyze(data: data, pageIndex: 1, pageRefID: UUID(), fallbackPage: page)
        let paragraph = try XCTUnwrap(analysis.blocks.first { $0.text.contains("maximus ultricies") })

        // A few points below the paragraph's bottom edge — blank line gap territory.
        let click = CGPoint(x: paragraph.bounds.minX + 40, y: paragraph.bounds.minY - 9)
        let target = try XCTUnwrap(viewModel.editableTextBlock(at: click, on: page, in: viewModel.combinedPDF))
        print("PROBE[D] clicked block text='\(String(target.block.text.prefix(60)))' editability=\(target.block.editability.rawValue) bounds=\(target.block.bounds) font=\(target.block.fontName)@\(target.block.fontSize)")

        let ok = viewModel.applyInlineTextEdit(
            pageRef: target.pageRef,
            sourceBlock: target.block,
            replacementText: "yolo",
            editedBounds: target.block.bounds,
            fontName: target.block.fontName,
            fontSize: target.block.fontSize,
            textColor: target.block.textColor.nsColor,
            alignment: (target.block.alignment ?? .left).nsTextAlignment
        )
        print("PROBE[D] applyInlineTextEdit ok=\(ok) status=\(String(describing: viewModel.editingStatus))")
        XCTAssertTrue(ok)
        let op = try XCTUnwrap(viewModel.document.workspace.pageEditStates.first?.operations.first)
        print("PROBE[D] op isInsertion=\(op.isInsertion) editedBounds=\(op.editedBounds)")

        let livePage = try XCTUnwrap(viewModel.loadedPDFs.first?.1.page(at: 1))
        let liveText = livePage.attributedString?.string ?? ""
        let liveDark = try darkPixelCount(on: livePage, in: op.editedBounds)
        print("PROBE[D] live yolo=\(liveText.contains("yolo")) dark=\(liveDark)")

        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("Orifold-phase0d-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: outputURL) }
        XCTAssertTrue(viewModel.saveFlattenedPDF(to: outputURL))
        let reopenedData = try Data(contentsOf: outputURL)
        let reopenedPDF = try XCTUnwrap(PDFDocument(data: reopenedData))
        var found = false
        for i in 0..<reopenedPDF.pageCount {
            guard let p = reopenedPDF.page(at: i) else { continue }
            if (p.attributedString?.string ?? "").contains("yolo") { found = true; print("PROBE[D] yolo on reopened page \(i)"); break }
        }
        XCTAssertTrue(found, "insertion edit must survive export+reopen")
    }
}
