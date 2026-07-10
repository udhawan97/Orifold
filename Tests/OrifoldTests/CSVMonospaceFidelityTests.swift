import PDFKit
import UniformTypeIdentifiers
import XCTest
@testable import Orifold

/// Regression suite for the CSV / system-monospace fidelity bugs (v0.8.11):
///
/// 1. `resolveFontPostScriptName` mapped the private system mono (`.SFNSMono-*` — what
///    every Quartz "print to PDF" of a CSV/log embeds) to sans-serif HelveticaNeue,
///    because the dot-prefix branch fired before any monospace check and the font
///    descriptor's FIXED_PITCH flag was never consulted.
/// 2. Quartz-generated PDFs write `… 1 Tf` with the true size in the text matrix, so
///    `FPDFText_GetFontSize` reports 1.0 for every glyph; the old `size >= 4` filter
///    emptied `validSizes` and left size detection to the ink model, whose per-line
///    scatter (11.1–13.9 for uniformly 11 pt CSV rows) broke committed line geometry.
/// 3. A text-only commit re-rendered in the editor's round-tripped style rather than
///    carrying the original format through verbatim.
///
/// End-to-end coverage runs the app's own CSV import (which itself now embeds Menlo
/// instead of the unresolvable system mono) through analysis, editor block resolution,
/// commit, export, and re-analysis of the exported bytes.
final class CSVMonospaceFidelityTests: XCTestCase {
    private static let csvFixture = """
    ticker,shares,avg_cost,is_watchlist,hold_class,notes
    AAPL,10,150.25,false,core,Long-term hold
    MSFT,5,310.5,false,anchor,
    TSLA,2,220,true,trade,Watching for dip
    VOO,15,410.75,false,auto,
    """

    private func resolvedFont(_ name: String, weightHint: Int? = nil, italicHint: Bool = false, fixedPitchHint: Bool = false) throws -> NSFont {
        let resolved = PDFTextAnalysisEngine.testResolveFontPostScriptName(
            from: name, weightHint: weightHint, italicHint: italicHint, fixedPitchHint: fixedPitchHint)
        return try XCTUnwrap(NSFont(name: resolved, size: 12), "resolved name '\(resolved)' for '\(name)' must be drawable")
    }

    // MARK: - Font resolution

    func testPrivateSystemMonoNamesResolveToFixedPitchFonts() throws {
        for name in [".SFNSMono-Regular", "AAAAAB+.SFNSMono-Regular", ".AppleSystemUIFontMonospaced-Regular", ".SFMono-Regular"] {
            let font = try resolvedFont(name)
            XCTAssertTrue(font.isFixedPitch, "'\(name)' must resolve to a monospaced stand-in, got '\(font.fontName)'")
        }
    }

    func testPrivateSystemMonoBoldKeepsBothMonospaceAndWeight() throws {
        let font = try resolvedFont(".SFNSMono-Bold")
        XCTAssertTrue(font.isFixedPitch, "bold system mono must stay monospaced, got '\(font.fontName)'")
        XCTAssertTrue(NSFontManager.shared.traits(of: font).contains(.boldFontMask),
                      "bold system mono must stay bold, got '\(font.fontName)'")
    }

    func testPrivateSystemSansStillResolvesToProportionalStandIn() throws {
        let font = try resolvedFont(".SFNS-Regular")
        XCTAssertFalse(font.isFixedPitch, "the proportional system face must keep its sans-serif stand-in, got '\(font.fontName)'")
    }

    func testFixedPitchDescriptorFlagForcesMonospaceForUnknownNames() throws {
        // Uninstalled third-party monos whose names carry no "mono"/"courier" token —
        // the descriptor flag is the only signal.
        for name in ["Inconsolata", "Hack-Regular", "SomeBespokeCodeFace"] {
            let font = try resolvedFont(name, fixedPitchHint: true)
            XCTAssertTrue(font.isFixedPitch, "fixed-pitch descriptor flag must force a monospace stand-in for '\(name)', got '\(font.fontName)'")
        }
    }

    func testInstalledFontNameStillWinsOverFixedPitchHint() throws {
        // An installed, resolvable name is exact fidelity — the flag must not override it.
        let font = try resolvedFont("Georgia", fixedPitchHint: true)
        XCTAssertEqual(font.familyName, "Georgia")
    }

    // MARK: - Matrix-scaled size recovery

    func testEffectiveReportedFontSizeRecoversQuartzMatrixScaledSizes() {
        let identity = PDFTextTransform(a: 1, b: 0, c: 0, d: 1, e: 0, f: 0)
        let scale11 = PDFTextTransform(a: 11, b: 0, c: 0, d: 11, e: 54, f: 727)
        // Plain reported size passes through untouched.
        XCTAssertEqual(PDFTextAnalysisEngine.effectiveReportedFontSize(rawSize: 11, transform: identity), 11)
        XCTAssertEqual(PDFTextAnalysisEngine.effectiveReportedFontSize(rawSize: 12, transform: nil), 12)
        // The Quartz shape: `1 Tf` + scale-11 text matrix = true 11 pt.
        XCTAssertEqual(try XCTUnwrap(PDFTextAnalysisEngine.effectiveReportedFontSize(rawSize: 1, transform: scale11)), 11, accuracy: 0.001)
        // Rotated-but-uniform matrix keeps the same determinant-derived scale.
        let rotated = PDFTextTransform(a: 7.778, b: 7.778, c: -7.778, d: 7.778, e: 0, f: 0) // 11pt rotated 45°
        XCTAssertEqual(try XCTUnwrap(PDFTextAnalysisEngine.effectiveReportedFontSize(rawSize: 1, transform: rotated)), 11, accuracy: 0.01)
        // Unrecoverable cases stay nil rather than feeding garbage into validSizes.
        XCTAssertNil(PDFTextAnalysisEngine.effectiveReportedFontSize(rawSize: 1, transform: nil))
        XCTAssertNil(PDFTextAnalysisEngine.effectiveReportedFontSize(rawSize: 1, transform: identity), "1 pt effective text is implausible, not a real size")
        XCTAssertNil(PDFTextAnalysisEngine.effectiveReportedFontSize(rawSize: 1, transform: PDFTextTransform(a: 0, b: 0, c: 0, d: 0, e: 0, f: 0)))
        XCTAssertNil(PDFTextAnalysisEngine.effectiveReportedFontSize(rawSize: 0, transform: scale11))
        XCTAssertNil(PDFTextAnalysisEngine.effectiveReportedFontSize(rawSize: 1, transform: PDFTextTransform(a: 900, b: 0, c: 0, d: 900, e: 0, f: 0)), "sizes past 400 pt are rejected as implausible")
    }

    // MARK: - CSV import → analysis fidelity

    private func importedCSVPDFData() throws -> Data {
        let imported = try DocumentImportConverter.importedDocument(
            from: Data(Self.csvFixture.utf8),
            contentType: .csv,
            filename: "holdings.csv",
            baseURL: nil
        )
        return try XCTUnwrap(imported.pdfDocument.dataRepresentation())
    }

    func testImportedCSVAnalyzesAsMonospaceAtTrueSizeWithVisibleColor() throws {
        let data = try importedCSVPDFData()
        let analysis = PDFTextAnalysisEngine().analyze(data: data, pageIndex: 0, pageRefID: UUID(), fallbackPage: nil)
        let textBlocks = analysis.blocks.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        XCTAssertFalse(textBlocks.isEmpty, "the imported CSV must produce editable text blocks")
        for block in textBlocks where block.text.contains(",") {
            let font = try XCTUnwrap(NSFont(name: block.fontName, size: block.fontSize),
                                      "block font '\(block.fontName)' must be drawable")
            XCTAssertTrue(font.isFixedPitch, "CSV rows are monospaced; got '\(block.fontName)' for '\(block.text.prefix(24))'")
            // Import renders at 11 pt; matrix-recovered reported sizes must pin the
            // detected size to it (the old ink-model-only path scattered 11.1–13.9).
            XCTAssertEqual(block.fontSize, 11, accuracy: 0.6,
                           "detected size for '\(block.text.prefix(24))' must match the imported 11 pt")
            let color = block.textColor
            XCTAssertGreaterThan(color.alpha, 0.9, "imported CSV ink must be opaque")
            let luma = 0.2126 * color.red + 0.7152 * color.green + 0.0722 * color.blue
            XCTAssertLessThan(luma, 0.3, "imported CSV ink must be dark (visible on paper) regardless of app appearance")
        }
    }

    // MARK: - Commit fidelity (text-only edit preserves everything)

    private func makeViewModel(from data: Data, name: String = "Holdings.pdf") throws -> WorkspaceViewModel {
        let wrapper = FileWrapper(regularFileWithContents: data)
        wrapper.preferredFilename = name
        let document = try WorkspaceDocument(testingFile: wrapper, contentType: .pdf, filename: name)
        return WorkspaceViewModel(document: document, processingEngine: PDFiumProcessingEngine())
    }

    func testTextOnlyEditOnImportedCSVPreservesFamilySizeAndBaseline() throws {
        let viewModel = try makeViewModel(from: try importedCSVPDFData())
        let memberData = try XCTUnwrap(viewModel.document.memberPDFData.values.first)
        let page = try XCTUnwrap(viewModel.loadedPDFs.first?.1.page(at: 0))
        let analysis = PDFTextAnalysisEngine().analyze(data: memberData, pageIndex: 0, pageRefID: UUID(), fallbackPage: page)
        let msft = try XCTUnwrap(analysis.blocks.first { $0.text.contains("MSFT") })
        XCTAssertEqual(msft.lines.count, 1, "each CSV row must stay its own editable line, not merge into a multi-row block")
        let sourceSize = msft.fontSize
        let sourceBaseline = msft.baseline

        let target = try XCTUnwrap(viewModel.editableTextBlock(
            at: CGPoint(x: msft.bounds.midX, y: msft.bounds.midY), on: page, in: viewModel.combinedPDF))
        XCTAssertFalse(target.block.text.contains("ticker"), "hit-testing the MSFT row must not resolve a block that swallowed the header row")
        XCTAssertTrue(viewModel.applyInlineTextEdit(
            pageRef: target.pageRef, sourceBlock: target.block,
            replacementText: "MSFT,5,310.5,false,anchor,Exploring",
            editedBounds: target.block.bounds,
            fontName: target.block.fontName, fontSize: target.block.fontSize,
            textColor: target.block.textColor.nsColor, alignment: (target.block.alignment ?? .left).nsTextAlignment
        ))

        let op = try XCTUnwrap(viewModel.document.workspace.pageEditStates.first?.operations.first)
        XCTAssertFalse(op.didManuallyChangeStyle, "no style control was touched")
        let opFont = try XCTUnwrap(NSFont(name: op.fontName, size: op.fontSize))
        XCTAssertTrue(opFont.isFixedPitch, "committed font must stay monospaced, got '\(op.fontName)'")
        XCTAssertEqual(op.fontSize, sourceSize, accuracy: sourceSize * 0.06, "committed size within 6% of the source")

        // Export and re-analyze the actual bytes: the shipped file is the contract.
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("Orifold-csv-fidelity-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: outputURL) }
        XCTAssertTrue(viewModel.saveFlattenedPDF(to: outputURL))
        let exported = try Data(contentsOf: outputURL)
        let exportedAnalysis = PDFTextAnalysisEngine().analyze(data: exported, pageIndex: 0, pageRefID: UUID(), fallbackPage: nil)
        let exportedLine = try XCTUnwrap(exportedAnalysis.blocks.first { $0.text.contains("Exploring") },
                                         "the replacement text must be present in the exported page")
        let exportedFont = try XCTUnwrap(NSFont(name: exportedLine.fontName, size: exportedLine.fontSize))
        XCTAssertTrue(exportedFont.isFixedPitch,
                      "exported replacement must render monospaced, got '\(exportedLine.fontName)'")
        XCTAssertEqual(exportedLine.fontSize, sourceSize, accuracy: sourceSize * 0.08,
                       "exported replacement size must match the document (was committed at 13.9 for an 11 pt line before the fix)")
        XCTAssertEqual(exportedLine.baseline, sourceBaseline, accuracy: 3,
                       "the edited line must stay on its original baseline, not drop onto the row below")
    }

    /// Re-opening an exported edited file and re-analyzing must not COMPOUND the size
    /// error (pre-fix: the covered original + replacement merged into one block whose
    /// doubled ink height re-estimated at 16 pt, so each edit round inflated further).
    func testExportedEditReanalyzesAtStableSize() throws {
        let viewModel = try makeViewModel(from: try importedCSVPDFData())
        let memberData = try XCTUnwrap(viewModel.document.memberPDFData.values.first)
        let page = try XCTUnwrap(viewModel.loadedPDFs.first?.1.page(at: 0))
        let analysis = PDFTextAnalysisEngine().analyze(data: memberData, pageIndex: 0, pageRefID: UUID(), fallbackPage: page)
        let msft = try XCTUnwrap(analysis.blocks.first { $0.text.contains("MSFT") })
        let target = try XCTUnwrap(viewModel.editableTextBlock(
            at: CGPoint(x: msft.bounds.midX, y: msft.bounds.midY), on: page, in: viewModel.combinedPDF))
        XCTAssertTrue(viewModel.applyInlineTextEdit(
            pageRef: target.pageRef, sourceBlock: target.block,
            replacementText: "MSFT,5,310.5,false,anchor,Exploring",
            editedBounds: target.block.bounds,
            fontName: target.block.fontName, fontSize: target.block.fontSize,
            textColor: target.block.textColor.nsColor, alignment: (target.block.alignment ?? .left).nsTextAlignment
        ))
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("Orifold-csv-reanalyze-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: outputURL) }
        XCTAssertTrue(viewModel.saveFlattenedPDF(to: outputURL))
        let exported = try Data(contentsOf: outputURL)
        let reanalysis = PDFTextAnalysisEngine().analyze(data: exported, pageIndex: 0, pageRefID: UUID(), fallbackPage: nil)
        for block in reanalysis.blocks where block.text.contains("Exploring") {
            XCTAssertEqual(block.fontSize, 11, accuracy: 1.2,
                           "re-analysis of the exported edit must not inflate the size (pre-fix: 16.1 for an 11 pt line)")
        }
    }
}
