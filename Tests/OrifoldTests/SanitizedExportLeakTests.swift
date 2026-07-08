import PDFKit
import XCTest
@testable import Orifold

/// WP-8: "Sanitize for sharing (remove metadata)" must strip Orifold's embedded workspace
/// metadata — the invisible /OrifoldWorkspaceComments JSON blob (edit history, base64 member
/// bytes, extracted source text, comments) — not just qpdf's /Info + /Metadata. A normal
/// (non-sanitized) export must still carry it for round-tripping.
final class SanitizedExportLeakTests: XCTestCase {
    /// Returns the VM too so the caller keeps it alive — `document.snapshot()` reads member
    /// bytes through `currentPDFDataProvider`, a `[weak self]` closure on the VM.
    private func makeEditedWorkspaceWithComment() throws -> (WorkspaceDocument, WorkspaceViewModel) {
        let data = EditingFixturePDFBuilder.makePDF(runs: [
            .init(string: "Confidential body text SECRETMARK", origin: CGPoint(x: 72, y: 700), fontSize: 12)
        ])
        let wrapper = FileWrapper(regularFileWithContents: data)
        wrapper.preferredFilename = "Secret.pdf"
        let document = try WorkspaceDocument(testingFile: wrapper, contentType: .pdf, filename: "Secret.pdf")
        let viewModel = WorkspaceViewModel(document: document, processingEngine: PDFiumProcessingEngine())
        // Add a workspace comment (goes into the embedded JSON blob) and an inline edit.
        viewModel.addComment("PRIVATEREVIEWNOTE do not ship")
        let memberData = try XCTUnwrap(document.memberPDFData.values.first)
        let page = try XCTUnwrap(viewModel.loadedPDFs.first?.1.page(at: 0))
        let block = try XCTUnwrap(PDFTextAnalysisEngine().analyze(data: memberData, pageIndex: 0, pageRefID: UUID(), fallbackPage: page).blocks.first)
        _ = viewModel.applyInlineTextEdit(
            pageRef: try XCTUnwrap(document.workspace.pageOrder.first),
            sourceBlock: block, replacementText: "Redacted body text", editedBounds: block.bounds,
            fontName: block.fontName, fontSize: block.fontSize, textColor: .black, alignment: .left
        )
        return (document, viewModel)
    }

    private func contains(_ data: Data, _ needle: String) -> Bool {
        data.range(of: Data(needle.utf8)) != nil
    }

    func testSanitizedExportStripsOrifoldMetadata() throws {
        let (document, viewModel) = try makeEditedWorkspaceWithComment()
        _ = viewModel // keep alive for snapshot's data provider
        let snapshot = try document.snapshot(contentType: .pdf)

        // A normal workspace export embeds the metadata (needed for round-trip editing).
        let normal = try document.exportedPDFDataThrowing(from: snapshot, options: WorkspaceExportOptions(embedsEditableWorkspaceState: true))
        XCTAssertTrue(contains(normal, "OrifoldWorkspaceComments"), "normal export embeds workspace metadata")

        // Sanitized export must strip it.
        let sanitized = try WorkspaceViewModel.sanitized(normal, options: PDFSanitizationOptions(removesMetadata: true))
        XCTAssertFalse(contains(sanitized, "OrifoldWorkspaceComments"), "sanitized export must not contain the metadata annotation key")
        XCTAssertFalse(contains(sanitized, "editableMemberPDFData"), "sanitized export must not contain embedded member bytes payload")
        XCTAssertFalse(contains(sanitized, "editableWorkspace"), "sanitized export must not contain embedded workspace JSON")
        XCTAssertFalse(contains(sanitized, "PRIVATEREVIEWNOTE"), "sanitized export must not contain workspace comment text")

        // The sanitized file must still be a valid, openable PDF.
        XCTAssertNotNil(PDFDocument(data: sanitized), "sanitized output must still be a valid PDF")
    }

    func testNonSanitizedExportKeepsMetadata() throws {
        let (document, viewModel) = try makeEditedWorkspaceWithComment()
        _ = viewModel
        let snapshot = try document.snapshot(contentType: .pdf)
        let normal = try document.exportedPDFDataThrowing(from: snapshot, options: WorkspaceExportOptions(embedsEditableWorkspaceState: true))
        // sanitized with nil options is a pass-through.
        let passthrough = try WorkspaceViewModel.sanitized(normal, options: nil)
        XCTAssertTrue(contains(passthrough, "OrifoldWorkspaceComments"), "a non-sanitized export must keep its metadata")
    }
}
