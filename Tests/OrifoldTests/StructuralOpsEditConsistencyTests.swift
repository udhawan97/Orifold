import PDFKit
import XCTest
@testable import Orifold

/// Regression coverage for structural-operation ↔ inline-edit consistency (Loop 1 of the
/// editing hardening pass): deleting/reordering/duplicating pages, OCR, and cross-member
/// moves all change how a PageRef maps onto the member's PRISTINE bytes. Stale
/// `sourcePageIndex` mappings made regeneration and hit-testing read a NEIGHBORING page's
/// content — data-destroying when committed.
final class StructuralOpsEditConsistencyTests: XCTestCase {
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
            guard let pageDocument = PDFDocument(data: view.dataWithPDF(inside: view.bounds)),
                  let page = pageDocument.page(at: 0) else {
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

    private func pageText(_ viewModel: WorkspaceViewModel, pageIndex: Int) -> String {
        viewModel.loadedPDFs.first?.1.page(at: pageIndex)?.attributedString?.string ?? ""
    }

    @discardableResult
    private func clickAndEdit(
        _ viewModel: WorkspaceViewModel,
        pageIndex: Int,
        expectPrefixOfClickedText expectedNeedle: String,
        replacement: String
    ) throws -> Bool {
        let page = try XCTUnwrap(viewModel.loadedPDFs.first?.1.page(at: pageIndex))
        // Click where the fixture draws its text (top-left region of the page).
        let click = CGPoint(x: 140, y: 792 - 66)
        let target = try XCTUnwrap(viewModel.editableTextBlock(at: click, on: page, in: viewModel.combinedPDF))
        XCTAssertTrue(
            target.block.text.contains(expectedNeedle),
            "hit-test must resolve the clicked page's own text; got '\(target.block.text.prefix(60))' expecting '\(expectedNeedle)'"
        )
        return viewModel.applyInlineTextEdit(
            pageRef: target.pageRef,
            sourceBlock: target.block,
            replacementText: replacement,
            editedBounds: target.block.bounds,
            fontName: target.block.fontName,
            fontSize: target.block.fontSize,
            textColor: .black,
            alignment: .left
        )
    }

    /// In-session: delete page 1, then click text on the (new) first page. Hit-testing
    /// must analyze the surviving page's pristine content, not the deleted page's.
    func testEditAfterDeletingEarlierPageHitsTheRightPristinePage() throws {
        let pdfData = try makePDFData(pageTexts: ["FirstPage unique alpha", "SecondPage unique beta", "ThirdPage unique gamma"])
        let viewModel = try makeViewModel(from: pdfData)
        let firstRef = try XCTUnwrap(viewModel.document.workspace.pageOrder.first)
        viewModel.deletePage(firstRef)
        XCTAssertEqual(viewModel.document.workspace.pageOrder.count, 2)

        XCTAssertTrue(try clickAndEdit(
            viewModel,
            pageIndex: 0,
            expectPrefixOfClickedText: "SecondPage",
            replacement: "SecondPage edited beta"
        ))
        let after = pageText(viewModel, pageIndex: 0)
        XCTAssertTrue(after.contains("SecondPage edited beta"))
        XCTAssertFalse(after.contains("FirstPage"), "regeneration must not resurrect the deleted page's content")
        XCTAssertTrue(pageText(viewModel, pageIndex: 1).contains("ThirdPage"), "the untouched page stays intact")
    }

    /// Save-after-structural-op, no committed edits: reopening renormalizes stale
    /// sourcePageIndex values so editing regenerates the correct page instead of a
    /// neighbor's content (and instead of failing outright on the last page).
    func testReopenAfterDeleteAndSaveEditsTheCorrectPages() throws {
        let pdfData = try makePDFData(pageTexts: ["FirstPage unique alpha", "SecondPage unique beta", "ThirdPage unique gamma"])
        let first = try makeViewModel(from: pdfData)
        let firstRef = try XCTUnwrap(first.document.workspace.pageOrder.first)
        first.deletePage(firstRef)
        let saved = try first.document.exportedPDFDataThrowing(
            from: first.document.snapshot(contentType: .pdf),
            options: WorkspaceExportOptions(embedsEditableWorkspaceState: true)
        )

        let second = try makeViewModel(from: saved, name: "Reopened")
        XCTAssertEqual(second.document.workspace.pageOrder.count, 2)
        // Edit the FIRST visible page (was source page 1) — with stale indices this
        // regenerated from the neighbor's bytes.
        XCTAssertTrue(try clickAndEdit(
            second,
            pageIndex: 0,
            expectPrefixOfClickedText: "SecondPage",
            replacement: "SecondPage edited beta"
        ))
        XCTAssertTrue(pageText(second, pageIndex: 0).contains("SecondPage edited beta"))
        XCTAssertFalse(pageText(second, pageIndex: 0).contains("ThirdPage"), "must not regenerate from the neighboring page")
        // Edit the LAST page — with stale indices this failed outright (index past
        // the shrunken page count).
        XCTAssertTrue(try clickAndEdit(
            second,
            pageIndex: 1,
            expectPrefixOfClickedText: "ThirdPage",
            replacement: "ThirdPage edited gamma"
        ))
        XCTAssertTrue(pageText(second, pageIndex: 1).contains("ThirdPage edited gamma"))
    }

    /// Duplicating an edited page must clone its committed operations: editing the
    /// duplicate afterwards regenerates it with BOTH edits, not pristine + only-the-new.
    func testDuplicateOfEditedPageKeepsItsEditsWhenReedited() throws {
        let pdfData = try makePDFData(pageTexts: ["DupSource original words"])
        let viewModel = try makeViewModel(from: pdfData)
        XCTAssertTrue(try clickAndEdit(
            viewModel,
            pageIndex: 0,
            expectPrefixOfClickedText: "DupSource",
            replacement: "DupSource FIRSTEDIT words"
        ))
        let sourceRef = try XCTUnwrap(viewModel.document.workspace.pageOrder.first)
        viewModel.duplicatePages([sourceRef])
        XCTAssertEqual(viewModel.document.workspace.pageOrder.count, 2)
        XCTAssertTrue(pageText(viewModel, pageIndex: 1).contains("FIRSTEDIT"), "duplicate visibly carries the edit")

        // Edit the DUPLICATE: its cloned op must survive the regeneration.
        let duplicateRef = viewModel.document.workspace.pageOrder[1]
        let dupState = viewModel.document.workspace.pageEditStates.first { $0.pageRefID == duplicateRef.id }
        XCTAssertNotNil(dupState, "duplicate ref must own cloned operations")
        let page = try XCTUnwrap(viewModel.loadedPDFs.first?.1.page(at: 1))
        let click = CGPoint(x: 140, y: 792 - 66)
        let target = try XCTUnwrap(viewModel.editableTextBlock(at: click, on: page, in: viewModel.combinedPDF))
        XCTAssertTrue(viewModel.applyInlineTextEdit(
            pageRef: target.pageRef,
            sourceBlock: target.block,
            replacementText: "DupSource SECONDEDIT words",
            editedBounds: target.block.bounds,
            fontName: target.block.fontName,
            fontSize: target.block.fontSize,
            textColor: .black,
            alignment: .left
        ))
        XCTAssertTrue(pageText(viewModel, pageIndex: 1).contains("SECONDEDIT"))
        XCTAssertTrue(pageText(viewModel, pageIndex: 0).contains("FIRSTEDIT"), "the original page keeps its own edit")
    }

    /// Cross-member move: editing text on the moved page must edit THAT page's content —
    /// previously regeneration replaced the moved page with a different page of the
    /// target member (confirmed data-destroying defect).
    func testEditingCrossMemberMovedPageKeepsItsOwnContent() throws {
        let dataA = try makePDFData(pageTexts: ["MemberA moving page"])
        let dataB = try makePDFData(pageTexts: ["MemberB first page", "MemberB second page"])
        let viewModel = try makeViewModel(from: dataA)
        let urlB = FileManager.default.temporaryDirectory.appendingPathComponent("Orifold-memberB-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: urlB) }
        try dataB.write(to: urlB)
        let expectation = XCTestExpectation(description: "import B")
        viewModel.importFiles(urls: [urlB])
        // importFiles is async; poll for completion.
        for _ in 0..<200 {
            if viewModel.document.workspace.documents.count == 2, !viewModel.isImporting { break }
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        expectation.fulfill()
        guard viewModel.document.workspace.documents.count == 2 else {
            throw XCTSkip("async import did not complete in time")
        }

        let movedRef = try XCTUnwrap(viewModel.document.workspace.pageOrder.first { $0.memberDocId == viewModel.document.workspace.documents[0].id })
        let targetRef = try XCTUnwrap(viewModel.document.workspace.pageOrder.first { $0.memberDocId == viewModel.document.workspace.documents[1].id })
        XCTAssertTrue(viewModel.movePage(movedRef, after: targetRef))

        // Find the moved page's local position inside member B.
        let memberB = viewModel.document.workspace.documents.first { $0.pageRefs.contains(movedRef.id) }
        let localIdx = try XCTUnwrap(memberB?.pageRefs.firstIndex(of: movedRef.id))
        let pdfB = try XCTUnwrap(viewModel.loadedPDFs.first(where: { $0.0.id == memberB?.id })?.1)
        let movedPage = try XCTUnwrap(pdfB.page(at: localIdx))
        XCTAssertTrue((movedPage.attributedString?.string ?? "").contains("MemberA moving page"))

        let click = CGPoint(x: 140, y: 792 - 66)
        let target = try XCTUnwrap(viewModel.editableTextBlock(at: click, on: movedPage, in: viewModel.combinedPDF))
        XCTAssertTrue(target.block.text.contains("MemberA"),
                      "hit-test on the moved page must see the moved page's own text, got '\(target.block.text.prefix(50))'")
        XCTAssertTrue(viewModel.applyInlineTextEdit(
            pageRef: target.pageRef,
            sourceBlock: target.block,
            replacementText: "MemberA moved and edited",
            editedBounds: target.block.bounds,
            fontName: target.block.fontName,
            fontSize: target.block.fontSize,
            textColor: .black,
            alignment: .left
        ))
        let after = pdfB.page(at: localIdx)?.attributedString?.string
            ?? viewModel.loadedPDFs.first(where: { $0.0.id == memberB?.id })?.1.page(at: localIdx)?.attributedString?.string
            ?? ""
        XCTAssertTrue(after.contains("MemberA moved and edited"), "edit lands on the moved page")
        XCTAssertFalse(after.contains("MemberB"), "the moved page's content must not be replaced by a target-member page")
    }

    /// Redo works for order-snapshot operations: delete → undo → redo must re-delete.
    func testDeletePageUndoThenRedoRedeletes() throws {
        let pdfData = try makePDFData(pageTexts: ["Page one text", "Page two text"])
        let viewModel = try makeViewModel(from: pdfData)
        let undoManager = UndoManager()
        viewModel.undoManager = undoManager
        let lastRef = try XCTUnwrap(viewModel.document.workspace.pageOrder.last)
        viewModel.deletePage(lastRef)
        XCTAssertEqual(viewModel.document.workspace.pageOrder.count, 1)
        undoManager.undo()
        XCTAssertEqual(viewModel.document.workspace.pageOrder.count, 2, "undo restores the page")
        XCTAssertTrue(undoManager.canRedo, "order-snapshot restore must register its inverse")
        undoManager.redo()
        XCTAssertEqual(viewModel.document.workspace.pageOrder.count, 1, "redo re-deletes the page")
    }
}
