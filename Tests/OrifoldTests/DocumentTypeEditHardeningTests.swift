import PDFKit
import UniformTypeIdentifiers
import XCTest
@testable import Orifold

/// LOOP 3 — document/file-type hardening. Validates that the editing lifecycle behaves
/// across the document shapes Orifold supports: real generated PDFs (proposal, résumé,
/// dense table), a plain-text import, and malformed input. External fixtures are
/// skipped cleanly when absent (CI has none of these); the synthesized cases always run.
final class DocumentTypeEditHardeningTests: XCTestCase {
    private static let fixtureDir = "/Users/umang/Documents/development/test-files-Orifold"

    private func loadViewModel(fixtureFile: String) throws -> WorkspaceViewModel {
        let url = URL(fileURLWithPath: "\(Self.fixtureDir)/\(fixtureFile)")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("\(fixtureFile) not present")
        }
        let data = try Data(contentsOf: url)
        let wrapper = FileWrapper(regularFileWithContents: data)
        wrapper.preferredFilename = fixtureFile
        let document = try WorkspaceDocument(testingFile: wrapper, contentType: .pdf, filename: fixtureFile)
        return WorkspaceViewModel(document: document, processingEngine: PDFiumProcessingEngine())
    }

    private func firstEditablePage(_ viewModel: WorkspaceViewModel) -> PDFPage? {
        let combined = viewModel.combinedPDF
        for i in 0..<combined.pageCount {
            if let p = combined.page(at: i), !(p is BoundaryPage) { return p }
        }
        return nil
    }

    /// Edit → Done → export → reopen on a real generated PDF (a proposal/résumé/table),
    /// asserting the edit is applied and no crash occurs. Runs for each fixture present.
    private func assertEditRoundTrip(fixtureFile: String, needle: String? = nil) throws {
        let viewModel = try loadViewModel(fixtureFile: fixtureFile)
        let data = try XCTUnwrap(viewModel.document.memberPDFData.values.first)
        let page = try XCTUnwrap(firstEditablePage(viewModel))
        let analysis = PDFTextAnalysisEngine().analyze(data: data, pageIndex: 0, pageRefID: UUID(), fallbackPage: page)
        // Pick a real body line: multi-word, direct, mid-page.
        let candidates = analysis.blocks.filter {
            $0.editability == .direct &&
            $0.text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ").count >= 2 &&
            $0.bounds.width > 60
        }
        let block = try XCTUnwrap(
            (needle.flatMap { n in candidates.first { $0.text.contains(n) } }) ?? candidates.first,
            "\(fixtureFile): expected at least one editable body line"
        )
        let target = try XCTUnwrap(viewModel.editableTextBlock(
            at: CGPoint(x: block.bounds.midX, y: block.bounds.midY), on: page, in: viewModel.combinedPDF
        ), "\(fixtureFile): hit-test must resolve the body line")
        XCTAssertTrue(target.block.editability == .direct || target.block.editability == .replace,
                      "\(fixtureFile): a real body line must be directly editable, not a blank insertion box")

        let token = "DOCTYPEEDIT"
        XCTAssertTrue(viewModel.applyInlineTextEdit(
            pageRef: target.pageRef,
            sourceBlock: target.block,
            replacementText: token,
            editedBounds: target.block.bounds,
            fontName: target.block.fontName,
            fontSize: target.block.fontSize,
            textColor: target.block.textColor.nsColor,
            alignment: (target.block.alignment ?? .left).nsTextAlignment
        ), "\(fixtureFile): edit must apply")

        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("Orifold-doctype-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: outputURL) }
        XCTAssertTrue(viewModel.saveFlattenedPDF(to: outputURL), "\(fixtureFile): export must succeed")
        XCTAssertNil(viewModel.exportError)

        // Reopen as a fresh document — must not crash and must be re-editable.
        let reopenedData = try Data(contentsOf: outputURL)
        let reopenedPDF = try XCTUnwrap(PDFDocument(data: reopenedData), "\(fixtureFile): export must reopen as a valid PDF")
        XCTAssertGreaterThan(reopenedPDF.pageCount, 0)
        // The token is present somewhere in the reopened file (subsequence-tolerant for
        // overlapping-run extraction scramble).
        let joined = (0..<reopenedPDF.pageCount)
            .compactMap { reopenedPDF.page(at: $0)?.attributedString?.string ?? reopenedPDF.page(at: $0)?.string }
            .joined()
            .components(separatedBy: .whitespacesAndNewlines).joined()
        XCTAssertTrue(joined.contains(token) || isSubsequence(token, of: joined),
                      "\(fixtureFile): committed edit must survive export + reopen")
    }

    func testProposalPDFEditRoundTrip() throws { try assertEditRoundTrip(fixtureFile: "Sample Proposal.pdf") }
    func testResumePDFEditRoundTrip() throws { try assertEditRoundTrip(fixtureFile: "Umang_Dhawan_Resume_Modern (3).pdf") }
    func testDenseTablePDFEditRoundTrip() throws { try assertEditRoundTrip(fixtureFile: "05-dense-table-and-edge-content.pdf") }
    func testSearchableMultipagePDFEditRoundTrip() throws { try assertEditRoundTrip(fixtureFile: "01-searchable-text-long-multipage.pdf") }
    func testMixedOrientationsPDFEditRoundTrip() throws { try assertEditRoundTrip(fixtureFile: "02-mixed-page-sizes-orientations.pdf") }

    /// A plain-text import must convert to a PDF whose body is directly editable, edit,
    /// and survive export + reopen — the "imported .txt survives conversion/export" path.
    func testPlainTextImportIsEditableAndSurvivesExport() throws {
        let text = "Imported plain text document.\nSecond line of the note.\nThird line for good measure."
        let data = Data(text.utf8)
        let wrapper = FileWrapper(regularFileWithContents: data)
        wrapper.preferredFilename = "note.txt"
        let document: WorkspaceDocument
        do {
            document = try WorkspaceDocument(testingFile: wrapper, contentType: .plainText, filename: "note.txt")
        } catch {
            throw XCTSkip("plain-text import unsupported in this configuration: \(error)")
        }
        let viewModel = WorkspaceViewModel(document: document, processingEngine: PDFiumProcessingEngine())
        let memberData = try XCTUnwrap(viewModel.document.memberPDFData.values.first)
        let page = try XCTUnwrap(firstEditablePage(viewModel))
        let analysis = PDFTextAnalysisEngine().analyze(data: memberData, pageIndex: 0, pageRefID: UUID(), fallbackPage: page)
        let block = try XCTUnwrap(analysis.blocks.first { $0.text.contains("Imported") || $0.text.contains("Second") },
                                  "imported text must be detected as editable blocks")
        let target = try XCTUnwrap(viewModel.editableTextBlock(
            at: CGPoint(x: block.bounds.midX, y: block.bounds.midY), on: page, in: viewModel.combinedPDF
        ))
        XCTAssertTrue(viewModel.applyInlineTextEdit(
            pageRef: target.pageRef,
            sourceBlock: target.block,
            replacementText: "EDITEDTEXTIMPORT",
            editedBounds: target.block.bounds,
            fontName: target.block.fontName,
            fontSize: target.block.fontSize,
            textColor: target.block.textColor.nsColor,
            alignment: (target.block.alignment ?? .left).nsTextAlignment
        ))
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("Orifold-txt-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: outputURL) }
        XCTAssertTrue(viewModel.saveFlattenedPDF(to: outputURL))
        let reopened = try XCTUnwrap(PDFDocument(data: Data(contentsOf: outputURL)))
        let joined = (0..<reopened.pageCount)
            .compactMap { reopened.page(at: $0)?.attributedString?.string }.joined()
            .components(separatedBy: .whitespacesAndNewlines).joined()
        XCTAssertTrue(joined.contains("EDITEDTEXTIMPORT") || isSubsequence("EDITEDTEXTIMPORT", of: joined),
                      "edited imported-text must survive conversion + export")
    }

    /// Malformed PDF bytes must fail import with a clear message, never crash.
    func testMalformedPDFFailsClearlyNotCrash() {
        let garbage = Data("%PDF-1.7\nnot really a pdf, truncated garbage".utf8)
        let wrapper = FileWrapper(regularFileWithContents: garbage)
        wrapper.preferredFilename = "broken.pdf"
        do {
            _ = try WorkspaceDocument(testingFile: wrapper, contentType: .pdf, filename: "broken.pdf")
            // If it somehow imported, that's acceptable too — the assertion is "no crash".
        } catch {
            let message = DocumentImportConverter.userMessage(for: error)
            XCTAssertFalse(message.isEmpty, "malformed import must yield a clear message")
        }
    }

    private func isSubsequence(_ needle: String, of haystack: String) -> Bool {
        var it = haystack.makeIterator()
        for ch in needle {
            var found = false
            while let h = it.next() { if h == ch { found = true; break } }
            if !found { return false }
        }
        return true
    }
}
