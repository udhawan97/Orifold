import PDFKit
import UniformTypeIdentifiers
import XCTest
@testable import Orifold

/// Corpus-wide TEXT-FIDELITY stress battery (v0.8.11). Where DocumentTypeEditHardening
/// asserts "the edit survives", this suite asserts "the edit LOOKS the same": for every
/// real-world fixture shape (Quartz print, ReportLab, WeasyPrint CID subsets, prior
/// Orifold exports, dense tables, mixed orientations, giant canvases) it checks
///
/// 1. analysis invariants — every directly-editable high-confidence block resolves to a
///    drawable font, a plausible size, and visible ink;
/// 2. default-commit fidelity — a text-only edit re-exports in the same fixed-pitch
///    class, within a tight size band, on the original baseline.
///
/// External fixtures skip cleanly when absent (CI has none of these).
final class ExternalCorpusFidelityStressTests: XCTestCase {
    private static let fixtureDir = "/Users/umang/Documents/development/test-files-Orifold"

    private struct Anomaly: CustomStringConvertible {
        var file: String
        var detail: String
        var description: String { "\(file): \(detail)" }
    }

    /// True when `needle`'s characters appear in order (not necessarily contiguously)
    /// inside `haystack` — tolerant of covered-original glyphs interleaving with the
    /// replacement during extraction of a baked page.
    private static func isSubsequence(_ needle: String, of haystack: String) -> Bool {
        var iterator = needle.makeIterator()
        var current = iterator.next()
        for char in haystack {
            guard let target = current else { return true }
            if char == target { current = iterator.next() }
        }
        return current == nil
    }

    private func fixtureData(_ name: String) throws -> Data {
        let url = URL(fileURLWithPath: "\(Self.fixtureDir)/\(name)")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("\(name) not present")
        }
        return try Data(contentsOf: url)
    }

    private func makeViewModel(from data: Data, name: String) throws -> WorkspaceViewModel {
        let wrapper = FileWrapper(regularFileWithContents: data)
        wrapper.preferredFilename = name
        let document = try WorkspaceDocument(testingFile: wrapper, contentType: .pdf, filename: name)
        return WorkspaceViewModel(document: document, processingEngine: PDFiumProcessingEngine())
    }

    // MARK: - 1. Analysis invariants across every text-bearing fixture

    /// Every direct high-confidence block in the corpus must carry a drawable font, a
    /// plausible size, and visible ink — the exact inputs the inline editor opens with.
    /// (Low-visibility/hidden-OCR blocks are excused by their editability class; the
    /// stress fixture contains those deliberately.)
    func testCorpusAnalysisInvariants() throws {
        guard FileManager.default.fileExists(atPath: Self.fixtureDir) else {
            throw XCTSkip("external fixture corpus not present")
        }
        let files = [
            "testcsv.pdf",
            "Sample Proposal.pdf",
            "Umang_Dhawan_Resume_Modern (3).pdf",
            "01-searchable-text-long-multipage.pdf",
            "02-mixed-page-sizes-orientations.pdf",
            "03-image-vector-transparency-stress.pdf",
            "04-acroform-fields.pdf",
            "05-dense-table-and-edge-content.pdf",
            "06-links-comments-annotations.pdf",
            "08-large-canvas-blueprint-page.pdf",
            "inline-edit-stress-test.pdf",
            "editedrun2.pdf",
            "test-text-edit-latest.pdf",
            "testing_inline_notmatching.pdf",
            "test123.pdf",
            "edited.pdf",
        ]
        var anomalies: [Anomaly] = []
        var checkedBlocks = 0
        for file in files {
            guard let data = try? fixtureData(file) else { continue } // per-file skip without aborting the sweep
            guard let pdf = PDFDocument(data: data), pdf.pageCount > 0 else {
                anomalies.append(Anomaly(file: file, detail: "unreadable as PDFDocument"))
                continue
            }
            let engine = PDFTextAnalysisEngine()
            for pageIndex in 0..<min(pdf.pageCount, 3) {
                let analysis = engine.analyze(data: data, pageIndex: pageIndex, pageRefID: UUID(), fallbackPage: pdf.page(at: pageIndex))
                for block in analysis.blocks where block.editability == .direct && block.confidence == .high {
                    checkedBlocks += 1
                    if NSFont(name: block.fontName, size: max(block.fontSize, 1)) == nil {
                        anomalies.append(Anomaly(file: file, detail: "p\(pageIndex) block '\(block.text.prefix(28))' font '\(block.fontName)' not drawable"))
                    }
                    if !(4...220).contains(block.fontSize) {
                        anomalies.append(Anomaly(file: file, detail: "p\(pageIndex) block '\(block.text.prefix(28))' implausible size \(block.fontSize)"))
                    }
                    if block.textColor.alpha < 0.5 {
                        anomalies.append(Anomaly(file: file, detail: "p\(pageIndex) block '\(block.text.prefix(28))' near-transparent ink (alpha \(block.textColor.alpha)) classified as direct"))
                    }
                }
            }
        }
        XCTAssertGreaterThan(checkedBlocks, 50, "the sweep must actually cover the corpus")
        XCTAssertTrue(anomalies.isEmpty, "corpus analysis anomalies:\n\(anomalies.map(\.description).joined(separator: "\n"))")
    }

    // MARK: - 2. Default-commit fidelity round trips

    /// Text-only edit on a body line: exported bytes must re-analyze in the same
    /// fixed-pitch class, within a tight size band, on the original baseline.
    private func assertFidelityRoundTrip(fixtureFile: String, needle: String? = nil, sizeTolerance: CGFloat = 0.15) throws {
        let data = try fixtureData(fixtureFile)
        let viewModel = try makeViewModel(from: data, name: fixtureFile)
        let memberData = try XCTUnwrap(viewModel.document.memberPDFData.values.first)
        let combined = viewModel.combinedPDF
        var page: PDFPage?
        for i in 0..<combined.pageCount where !(combined.page(at: i) is BoundaryPage) {
            page = combined.page(at: i); break
        }
        let firstPage = try XCTUnwrap(page, "\(fixtureFile): needs a page")
        let analysis = PDFTextAnalysisEngine().analyze(data: memberData, pageIndex: 0, pageRefID: UUID(), fallbackPage: firstPage)
        let candidates = analysis.blocks.filter {
            $0.editability == .direct && $0.confidence == .high &&
            $0.text.trimmingCharacters(in: .whitespacesAndNewlines).count >= 8 &&
            $0.bounds.width > 60 && $0.lines.count == 1
        }
        let block = try XCTUnwrap(
            (needle.flatMap { n in candidates.first { $0.text.contains(n) } }) ?? candidates.first,
            "\(fixtureFile): expected an editable single-line body block"
        )
        let sourceFont = NSFont(name: block.fontName, size: max(block.fontSize, 1))
        let sourceFixedPitch = sourceFont?.isFixedPitch == true
        let sourceSize = block.fontSize
        let sourceBaseline = block.baseline

        let target = try XCTUnwrap(viewModel.editableTextBlock(
            at: CGPoint(x: block.bounds.midX, y: block.bounds.midY), on: firstPage, in: combined))
        let token = "FIDELITYSTRESS\(Int(sourceSize))"
        XCTAssertTrue(viewModel.applyInlineTextEdit(
            pageRef: target.pageRef, sourceBlock: target.block,
            replacementText: token,
            editedBounds: target.block.bounds,
            fontName: target.block.fontName, fontSize: target.block.fontSize,
            textColor: target.block.textColor.nsColor, alignment: (target.block.alignment ?? .left).nsTextAlignment
        ), "\(fixtureFile): edit must apply")

        // Locate OUR op by its replacement text: overlapping neighbor bands can make the
        // app synthesize additional re-render ops for adjacent lines (correct behavior —
        // each carries ITS OWN detected format), so `.operations.first` is not ours.
        let op = try XCTUnwrap(
            viewModel.document.workspace.pageEditStates.flatMap(\.operations).first { $0.replacementText == token },
            "\(fixtureFile): the committed operation must exist"
        )
        XCTAssertFalse(op.didManuallyChangeStyle, "\(fixtureFile): text-only edit must not mark a style change")
        XCTAssertEqual(op.fontSize, sourceSize, accuracy: sourceSize * 0.06,
                       "\(fixtureFile): committed op size must track the detected size")

        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("Orifold-fidelity-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: outputURL) }
        XCTAssertTrue(viewModel.saveFlattenedPDF(to: outputURL), "\(fixtureFile): export must succeed")
        let exported = try Data(contentsOf: outputURL)
        let reanalysis = PDFTextAnalysisEngine().analyze(data: exported, pageIndex: 0, pageRefID: UUID(), fallbackPage: nil)
        // Erase is visual-only, so the covered original's glyphs can interleave with the
        // replacement char-by-char during extraction — locate the replacement with an
        // interleave-tolerant subsequence match, preferring a block that carries the
        // token contiguously when the extraction came out clean.
        let exportedLine = try XCTUnwrap(
            reanalysis.blocks.first { $0.text.contains(token) }
                ?? reanalysis.blocks.first { Self.isSubsequence(token, of: $0.text) },
            "\(fixtureFile): replacement text must be present in the exported page"
        )
        let exportedFont = NSFont(name: exportedLine.fontName, size: max(exportedLine.fontSize, 1))
        XCTAssertEqual(exportedFont?.isFixedPitch == true, sourceFixedPitch,
                       "\(fixtureFile): fixed-pitch class must survive commit (source '\(block.fontName)' → exported '\(exportedLine.fontName)')")
        XCTAssertEqual(exportedLine.fontSize, sourceSize, accuracy: sourceSize * sizeTolerance,
                       "\(fixtureFile): exported size \(exportedLine.fontSize) vs source \(sourceSize)")
        XCTAssertEqual(exportedLine.baseline, sourceBaseline, accuracy: 4.5,
                       "\(fixtureFile): edited line must stay on its baseline")
    }

    func testQuartzCSVPrintFidelity() throws {
        // THE user-reported file: Quartz print-to-PDF of a CSV in '.SFNSMono-Regular'.
        // Target a pristine row (the MSFT band already contains a broken pre-fix edit
        // baked by an older build).
        try assertFidelityRoundTrip(fixtureFile: "testcsv.pdf", needle: "TSLA")
    }

    func testQuartzProposalFidelity() throws { try assertFidelityRoundTrip(fixtureFile: "Sample Proposal.pdf") }
    func testWeasyPrintCIDResumeFidelity() throws { try assertFidelityRoundTrip(fixtureFile: "Umang_Dhawan_Resume_Modern (3).pdf") }
    func testReportLabMultipageFidelity() throws { try assertFidelityRoundTrip(fixtureFile: "01-searchable-text-long-multipage.pdf") }
    func testDenseTableFidelity() throws { try assertFidelityRoundTrip(fixtureFile: "05-dense-table-and-edge-content.pdf") }
    func testPriorOrifoldExportMonacoFidelity() throws { try assertFidelityRoundTrip(fixtureFile: "editedrun2.pdf") }
    func testPriorOrifoldExportLegacyFidelity() throws { try assertFidelityRoundTrip(fixtureFile: "test-text-edit-latest.pdf") }

    /// The pristine rows of the user's CSV print must now analyze as fixed-pitch at the
    /// true 11 pt (pre-fix: HelveticaNeue at 11.1–13.9 scatter).
    func testQuartzCSVPrintAnalyzesAsElevenPointMonospace() throws {
        let data = try fixtureData("testcsv.pdf")
        let pdf = try XCTUnwrap(PDFDocument(data: data))
        let analysis = PDFTextAnalysisEngine().analyze(data: data, pageIndex: 0, pageRefID: UUID(), fallbackPage: pdf.page(at: 0))
        var checked = 0
        for needle in ["ticker", "AAPL", "TSLA", "VOO"] {
            guard let row = analysis.blocks.first(where: { $0.text.contains(needle) }) else { continue }
            checked += 1
            let font = try XCTUnwrap(NSFont(name: row.fontName, size: row.fontSize))
            XCTAssertTrue(font.isFixedPitch, "row '\(needle)' must analyze monospaced, got '\(row.fontName)'")
            XCTAssertEqual(row.fontSize, 11, accuracy: 0.4, "row '\(needle)' true size is 11 pt")
            XCTAssertEqual(row.lines.count, 1, "row '\(needle)' must stay its own line")
        }
        XCTAssertGreaterThanOrEqual(checked, 3, "expected the CSV rows to be present")
    }
}
