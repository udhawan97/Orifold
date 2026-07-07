import PDFKit
import XCTest
@testable import Orifold

/// Regression coverage for the "edit remembered but invisible" trap (Loop 1 of the
/// editing-experience hardening pass): committed inline-edit OPERATIONS live in workspace
/// state while the visible/exported result lives in the member PDF bytes, and the two
/// used to be able to diverge with no reconciliation — a file saved in that state showed
/// the edit only inside the reopened inline editor, never on the page and never in any
/// export. These tests pin the self-healing + pristine-base machinery that closes it.
final class InlineEditReconciliationTests: XCTestCase {
    // MARK: - Fixture plumbing

    private final class FixturePageView: NSView {
        private let text: String
        init(frame: CGRect, text: String) {
            self.text = text
            super.init(frame: frame)
        }
        required init?(coder: NSCoder) { nil }
        override func draw(_ dirtyRect: NSRect) {
            NSColor.white.setFill()
            dirtyRect.fill()
            (text as NSString).draw(
                in: bounds.insetBy(dx: 54, dy: 54),
                withAttributes: [.font: NSFont(name: "Helvetica", size: 14) ?? .systemFont(ofSize: 14),
                                 .foregroundColor: NSColor.black]
            )
        }
    }

    private func makePDFData(pageTexts: [String]) throws -> Data {
        let pdf = PDFDocument()
        for (index, text) in pageTexts.enumerated() {
            let view = FixturePageView(frame: CGRect(x: 0, y: 0, width: 612, height: 792), text: text)
            let pageData = view.dataWithPDF(inside: view.bounds)
            guard let pageDocument = PDFDocument(data: pageData), let page = pageDocument.page(at: 0) else {
                throw XCTSkip("fixture page rendering failed")
            }
            pdf.insert(page, at: index)
        }
        return try XCTUnwrap(pdf.dataRepresentation())
    }

    private func makeViewModel(from pdfData: Data, name: String = "Fixture") throws -> WorkspaceViewModel {
        let wrapper = FileWrapper(regularFileWithContents: pdfData)
        wrapper.preferredFilename = "\(name).pdf"
        let document = try WorkspaceDocument(testingFile: wrapper, contentType: .pdf, filename: "\(name).pdf")
        return WorkspaceViewModel(document: document, processingEngine: PDFiumProcessingEngine())
    }

    @discardableResult
    private func applyEdit(
        _ viewModel: WorkspaceViewModel,
        pageIndex: Int,
        matching needle: String,
        replacement: String
    ) throws -> PDFTextEditOperation {
        let memberID = try XCTUnwrap(viewModel.loadedPDFs.first?.0.id)
        let data = try XCTUnwrap(viewModel.document.memberPDFData[memberID])
        let page = try XCTUnwrap(viewModel.loadedPDFs.first?.1.page(at: pageIndex))
        let analysis = PDFTextAnalysisEngine().analyze(data: data, pageIndex: pageIndex, pageRefID: UUID(), fallbackPage: page)
        let block = try XCTUnwrap(analysis.blocks.first { $0.text.contains(needle) })
        let target = try XCTUnwrap(viewModel.editableTextBlock(
            at: CGPoint(x: block.bounds.midX, y: block.bounds.midY),
            on: page,
            in: viewModel.combinedPDF
        ))
        XCTAssertTrue(viewModel.applyInlineTextEdit(
            pageRef: target.pageRef,
            sourceBlock: target.block,
            replacementText: replacement,
            editedBounds: target.block.bounds,
            fontName: target.block.fontName,
            fontSize: target.block.fontSize,
            textColor: .black,
            alignment: .left
        ))
        return try XCTUnwrap(
            viewModel.document.workspace.pageEditStates
                .first(where: { $0.pageRefID == target.pageRef.id })?
                .operations.first(where: { $0.sourceBlockID == target.block.id })
        )
    }

    private func pageText(_ viewModel: WorkspaceViewModel, pageIndex: Int) -> String {
        viewModel.loadedPDFs.first?.1.page(at: pageIndex)?.attributedString?.string ?? ""
    }

    /// Builds a LEGACY trapped file byte-for-byte the way older builds left them: flat
    /// pages WITHOUT the bake + embedded workspace state WITH the committed operation
    /// (and no pristine payload). Mirrors `WorkspaceDocument.OrifoldMetadata`'s JSON shape.
    private struct TrappedMetadata: Codable {
        var comments: [WorkspaceComment] = []
        var editableWorkspace: Workspace?
        var editableMemberPDFData: [UUID: Data] = [:]
    }

    private func makeTrappedLegacyFile(preEditData: Data, workspaceWithOps: Workspace, memberID: UUID) throws -> Data {
        let pdf = try XCTUnwrap(PDFDocument(data: preEditData))
        let metadata = TrappedMetadata(
            editableWorkspace: workspaceWithOps,
            editableMemberPDFData: [memberID: preEditData]
        )
        let json = try XCTUnwrap(String(data: JSONEncoder().encode(metadata), encoding: .utf8))
        let annotation = PDFAnnotation(bounds: CGRect(x: -10, y: -10, width: 1, height: 1), forType: .freeText, withProperties: nil)
        annotation.color = .clear
        annotation.setValue(json, forAnnotationKey: PDFAnnotationKey(rawValue: "/OrifoldWorkspaceComments"))
        try XCTUnwrap(pdf.page(at: 0)).addAnnotation(annotation)
        return try XCTUnwrap(pdf.dataRepresentation())
    }

    // MARK: - Tests

    /// The literal user-reported bug, synthesized: a file whose embedded state carries a
    /// committed edit the page bytes never received. Opening it must bake the edit into
    /// the visible page immediately — no clicks — and exports must carry it.
    func testTrappedLegacyFileSelfHealsAtLoadAndExport() throws {
        let preEditData = try makePDFData(pageTexts: ["Alpha original paragraph text", "Beta page"])
        // Drive a real edit through a scratch view model purely to obtain a faithful
        // committed operation (correct bounds/format capture), then throw its bake away.
        let scratch = try makeViewModel(from: preEditData)
        try applyEdit(scratch, pageIndex: 0, matching: "Alpha original", replacement: "Alpha healed paragraph yolo")
        let trappedWorkspace = scratch.document.workspace
        let memberID = try XCTUnwrap(scratch.loadedPDFs.first?.0.id)
        let trappedFile = try makeTrappedLegacyFile(
            preEditData: preEditData,
            workspaceWithOps: trappedWorkspace,
            memberID: memberID
        )

        let viewModel = try makeViewModel(from: trappedFile, name: "Trapped")
        XCTAssertTrue(pageText(viewModel, pageIndex: 0).contains("Alpha healed paragraph yolo"),
                      "opening a trapped file must self-heal: the committed edit becomes visible with no interaction")

        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("Orifold-reconcile-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: outputURL) }
        XCTAssertTrue(viewModel.saveFlattenedPDF(to: outputURL))
        let reopened = try XCTUnwrap(PDFDocument(data: Data(contentsOf: outputURL)))
        let reopenedText = (0..<reopened.pageCount).compactMap { reopened.page(at: $0)?.attributedString?.string }.joined()
        XCTAssertTrue(reopenedText.contains("Alpha healed paragraph yolo"),
                      "the healed edit must survive export + fresh reopen")
    }

    /// Re-editing across sessions must regenerate from the PRISTINE base, not the baked
    /// bytes — otherwise the first replacement's ink/text stays buried under the second
    /// bake (ghost text) and the file grows a layer per session.
    func testReeditAfterReopenRegeneratesFromPristineBaseWithoutStackingBakes() throws {
        let preEditData = try makePDFData(pageTexts: ["Gamma original sentence here"])
        let first = try makeViewModel(from: preEditData)
        try applyEdit(first, pageIndex: 0, matching: "Gamma original", replacement: "FIRSTREPLACEMENT unique token")
        let saved = try first.document.exportedPDFDataThrowing(
            from: first.document.snapshot(contentType: .pdf),
            options: WorkspaceExportOptions(embedsEditableWorkspaceState: true)
        )

        let second = try makeViewModel(from: saved, name: "Reopened")
        XCTAssertFalse(second.document.restoredOriginalMemberPDFData.isEmpty,
                       "saved workspace must carry pristine bytes for the edited member")
        XCTAssertTrue(pageText(second, pageIndex: 0).contains("FIRSTREPLACEMENT"),
                      "reopened workspace shows the first edit")

        try applyEdit(second, pageIndex: 0, matching: "FIRSTREPLACEMENT", replacement: "SECONDREPLACEMENT different token")
        let after = pageText(second, pageIndex: 0)
        XCTAssertTrue(after.contains("SECONDREPLACEMENT"), "second edit must be visible")
        XCTAssertFalse(after.contains("FIRSTREPLACEMENT"),
                       "regeneration must start from the pristine base — the first bake's text must be gone, not buried")
    }

    /// Order-mutation undo snapshots restore member bytes; they must restore the edit
    /// operations captured at the same instant, or the two diverge exactly like the
    /// trapped-file bug. Sequence: edit page 1 → delete page 2 → undo the delete →
    /// the edit must still be visible AND still present as an operation.
    func testUndoingPageDeleteKeepsEditOpsAndBytesConsistent() throws {
        let pdfData = try makePDFData(pageTexts: ["Delta editable text", "Removable page"])
        let viewModel = try makeViewModel(from: pdfData)
        let undoManager = UndoManager()
        viewModel.undoManager = undoManager

        try applyEdit(viewModel, pageIndex: 0, matching: "Delta editable", replacement: "Delta edited text token")
        XCTAssertTrue(pageText(viewModel, pageIndex: 0).contains("Delta edited text token"))

        let removablePage = try XCTUnwrap(viewModel.document.workspace.pageOrder.last)
        viewModel.deletePage(removablePage)
        XCTAssertEqual(viewModel.document.workspace.pageOrder.count, 1)

        undoManager.undo()
        XCTAssertEqual(viewModel.document.workspace.pageOrder.count, 2, "page delete undone")
        XCTAssertTrue(pageText(viewModel, pageIndex: 0).contains("Delta edited text token"),
                      "the text edit must still be visible after undoing an unrelated page delete")
        XCTAssertTrue(viewModel.hasInlineTextEdits,
                      "the committed operation must still exist after undoing an unrelated page delete")
    }

    /// Export must self-heal any in-memory divergence: even if member bytes are forcibly
    /// reverted to pre-edit while operations remain committed (simulating any historical
    /// divergence vector), exported bytes must contain the committed edit.
    func testExportSelfHealsInMemoryDivergence() throws {
        let preEditData = try makePDFData(pageTexts: ["Epsilon paragraph for export"])
        let viewModel = try makeViewModel(from: preEditData)
        try applyEdit(viewModel, pageIndex: 0, matching: "Epsilon paragraph", replacement: "Epsilon exported edit token")

        // Manufacture the divergence: bytes revert, operations stay.
        let memberID = try XCTUnwrap(viewModel.loadedPDFs.first?.0.id)
        viewModel.document.memberPDFData[memberID] = preEditData
        viewModel.loadedPDFs[0] = (viewModel.loadedPDFs[0].0, try XCTUnwrap(PDFDocument(data: preEditData)))
        XCTAssertFalse(pageText(viewModel, pageIndex: 0).contains("Epsilon exported edit token"),
                       "divergence precondition: live page no longer shows the edit")
        XCTAssertTrue(viewModel.hasInlineTextEdits)

        let exported = try viewModel.dataForPDFExport()
        let exportedPDF = try XCTUnwrap(PDFDocument(data: exported))
        let exportedText = (0..<exportedPDF.pageCount).compactMap { exportedPDF.page(at: $0)?.attributedString?.string }.joined()
        XCTAssertTrue(exportedText.contains("Epsilon exported edit token"),
                      "export must reconcile committed operations into the bytes it writes")
    }
}
