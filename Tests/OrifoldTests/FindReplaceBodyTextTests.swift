import PDFKit
import XCTest
@testable import Orifold

/// Coverage for Find & Replace on document BODY text (not just comments). Body replacements
/// go through the same op-based engine as click-to-edit (`applyInlineTextEdit`), so these
/// tests focus on the new matching/selection/batching layer in `WorkspaceViewModel` plus an
/// explicit export round trip, matching the fixture style already used by
/// `InlineEditReconciliationTests` (real PDF pages rendered from `NSView`, PDFium-backed text
/// extraction to sidestep the CI Xcode 16.4 `PDFPage.string` quirk).
final class FindReplaceBodyTextTests: XCTestCase {
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

    /// Reading-order text of `pageIndex` in `data`, PDFium-backed (not PDFKit's
    /// `.string`/`.attributedString`) — see [[ci-xcode164-pdfkit-string-extraction-quirk]].
    /// The sort itself now lives in `PDFTextAnalysisEngine.readingOrderText(data:pageIndex:)`.
    private static func pageText(fromData data: Data, pageIndex: Int) -> String {
        PDFTextAnalysisEngine.readingOrderText(data: data, pageIndex: pageIndex)
    }

    private func pageText(_ viewModel: WorkspaceViewModel, pageIndex: Int) -> String {
        guard let pdf = viewModel.loadedPDFs.first?.1, let data = pdf.dataRepresentation() else { return "" }
        return Self.pageText(fromData: data, pageIndex: pageIndex)
    }

    // MARK: - Tests

    func testFindSearchesBodyTextNotJustComments() throws {
        let data = try makePDFData(pageTexts: ["The quick brown widget jumps"])
        let viewModel = try makeViewModel(from: data)
        viewModel.searchQuery = "widget"
        viewModel.search(query: "widget")

        XCTAssertFalse(viewModel.searchResults.isEmpty, "PDFKit search must find body text, not just comments")
        XCTAssertGreaterThan(viewModel.bodyReplaceMatchCount, 0)
        XCTAssertTrue(viewModel.replaceableCommentMatches.isEmpty, "no comments exist in this fixture")
    }

    /// Note on what's asserted here: committed text edits erase the original ink VISUALLY
    /// (a background-colored patch + new text drawn on top) but the original page content
    /// is still replayed underneath first — a known, disclosed limitation (see
    /// `maybeShowTextEditPrivacyNotice` in `ReadingCanvas.swift`), not something Find &
    /// Replace changes. So "only one occurrence touched" is verified via the committed
    /// OPERATION set (the authoritative record of what Find & Replace acted on) rather than
    /// by asserting the old word is absent from raw extracted text, which it structurally
    /// isn't. `bodyReplaceMatchCount` — which reads live (op-overridden) text — is the
    /// property that actually reflects what a subsequent search would find.
    func testSingleReplaceChangesOnlyTheSelectedOccurrenceAndAdvancesMatchCount() throws {
        let data = try makePDFData(pageTexts: ["First widget page", "Second widget page"])
        let viewModel = try makeViewModel(from: data)
        viewModel.searchQuery = "widget"
        viewModel.replaceText = "gadget"
        viewModel.search(query: "widget")
        XCTAssertEqual(viewModel.searchResults.count, 2)
        XCTAssertEqual(viewModel.bodyReplaceMatchCount, 2)
        viewModel.searchResultIndex = 0

        XCTAssertTrue(viewModel.replaceCurrentMatch())

        let operations = viewModel.document.workspace.pageEditStates.flatMap(\.operations)
        XCTAssertEqual(operations.count, 1, "exactly one occurrence must be committed as an edit")
        let replacementText = try XCTUnwrap(operations.first?.replacementText)
        XCTAssertTrue(replacementText.contains("gadget"))
        XCTAssertFalse(replacementText.lowercased().contains("widget"), "the committed replacement text itself must not still contain the search term")
        XCTAssertEqual(viewModel.bodyReplaceMatchCount, 1, "match count must drop by exactly one")
    }

    func testReplaceAllReplacesEveryOccurrenceAndReturnsCorrectCount() throws {
        let data = try makePDFData(pageTexts: ["Widget one here", "Widget two here", "Widget three here"])
        let viewModel = try makeViewModel(from: data)
        viewModel.searchQuery = "widget"
        viewModel.replaceText = "gadget"

        let (replaced, skipped) = viewModel.replaceAllMatches()
        XCTAssertEqual(replaced, 3)
        XCTAssertEqual(skipped, 0)

        let operations = viewModel.document.workspace.pageEditStates.flatMap(\.operations)
        XCTAssertEqual(operations.count, 3, "one committed edit per page")
        XCTAssertTrue(operations.allSatisfy { $0.replacementText.contains("gadget") })
        for index in 0..<3 {
            XCTAssertTrue(pageText(viewModel, pageIndex: index).contains("gadget"))
        }
        XCTAssertEqual(viewModel.bodyReplaceMatchCount, 0, "no live occurrences of the search text should remain")
    }

    func testReplaceAllCombinesBodyAndCommentMatchesInOneUndoStep() throws {
        let data = try makePDFData(pageTexts: ["Body has widget text"])
        let viewModel = try makeViewModel(from: data)
        let undoManager = UndoManager()
        viewModel.undoManager = undoManager
        viewModel.document.workspace.comments = [WorkspaceComment(body: "Comment mentions widget too")]
        viewModel.searchQuery = "widget"
        viewModel.replaceText = "gadget"

        let (replaced, _) = viewModel.replaceAllMatches()
        XCTAssertEqual(replaced, 2, "one body occurrence plus one matching comment")
        XCTAssertTrue(viewModel.hasInlineTextEdits, "the body replacement must be committed as an inline-edit operation")
        XCTAssertEqual(viewModel.document.workspace.comments.first?.body, "Comment mentions gadget too")

        undoManager.undo()
        XCTAssertFalse(viewModel.hasInlineTextEdits, "undo must remove the body edit operation")
        XCTAssertEqual(viewModel.document.workspace.comments.first?.body, "Comment mentions widget too",
                       "undo must restore the comment in the SAME step as the body text")
    }

    /// An invisible (`Tr 3`) OCR-layer run is real, hittable text but unsafe to rewrite in
    /// bulk — Replace All must skip it and report the skip rather than silently omitting it
    /// from the count (see `PDFTextEditability.hiddenOCRLayer`).
    func testHiddenOCRLayerMatchIsSkippedNotSilentlyDropped() throws {
        let data = InlineEditStressFixture.buildData()
        let viewModel = try makeViewModel(from: data, name: "StressFixture")
        viewModel.searchQuery = "Invisible"
        viewModel.replaceText = "Replaced"

        let (replaced, skipped) = viewModel.replaceAllMatches()
        XCTAssertEqual(replaced, 0, "an invisible OCR-layer match must not be rewritten in bulk")
        XCTAssertGreaterThanOrEqual(skipped, 1, "the skip must be reported, not silently dropped")
    }

    func testEmptyQueryProducesNoReplacements() throws {
        let data = try makePDFData(pageTexts: ["Widget page text"])
        let viewModel = try makeViewModel(from: data)
        viewModel.searchQuery = ""
        viewModel.replaceText = "gadget"

        XCTAssertFalse(viewModel.replaceCurrentMatch())
        let (replaced, skipped) = viewModel.replaceAllMatches()
        XCTAssertEqual(replaced, 0)
        XCTAssertEqual(skipped, 0)
        XCTAssertFalse(viewModel.hasInlineTextEdits)
    }

    /// Uses matching case for search/replace so this is a genuine byte-for-byte no-op —
    /// a case-insensitive search with a differently-cased replacement (e.g. "Widget" →
    /// "widget") is a real text change, not the no-op this test targets.
    func testSameTextReplacementIsANoOp() throws {
        let data = try makePDFData(pageTexts: ["some widget page text"])
        let viewModel = try makeViewModel(from: data)
        viewModel.searchQuery = "widget"
        viewModel.replaceText = "widget"

        let (replaced, skipped) = viewModel.replaceAllMatches()
        XCTAssertEqual(replaced, 0, "replacing text with the same text must be a no-op")
        XCTAssertEqual(skipped, 0)
        XCTAssertFalse(viewModel.hasInlineTextEdits)
    }

    /// The end-to-end export verification the feature is built around: internal document
    /// state (committed inline-edit operations) must flow through `dataForPDFExport()` so
    /// the exported PDF actually reflects both a single replace and a subsequent Replace All.
    /// Only presence of the replacement is checked, not absence of the original word: a
    /// committed edit visually covers the original ink but the original page content is
    /// still replayed underneath first (a known, disclosed limitation — see
    /// `maybeShowTextEditPrivacyNotice` in `ReadingCanvas.swift` — not something Find &
    /// Replace changes). "Only the targeted page was touched" is verified via the
    /// committed operation set instead, which is unaffected by that limitation.
    func testExportReflectsSingleReplaceThenReplaceAllOfBodyText() throws {
        let data = try makePDFData(pageTexts: ["Widget alpha here", "Widget beta here", "Widget gamma here"])
        let viewModel = try makeViewModel(from: data)
        viewModel.searchQuery = "widget"
        viewModel.replaceText = "gadget"
        viewModel.search(query: "widget")
        XCTAssertEqual(viewModel.searchResults.count, 3)
        viewModel.searchResultIndex = 0
        XCTAssertTrue(viewModel.replaceCurrentMatch())

        let operationsAfterSingle = viewModel.document.workspace.pageEditStates.flatMap(\.operations)
        XCTAssertEqual(operationsAfterSingle.count, 1, "only the selected occurrence's page must be touched")

        let exportedAfterSingle = try viewModel.dataForPDFExport()
        let pagesAfterSingle = (0..<3).map { Self.pageText(fromData: exportedAfterSingle, pageIndex: $0) }
        XCTAssertEqual(pagesAfterSingle.filter { $0.contains("gadget") }.count, 1,
                       "exactly one page must contain the single replacement in the exported file")

        let (replaced, skipped) = viewModel.replaceAllMatches()
        XCTAssertEqual(replaced, 2, "the two remaining occurrences")
        XCTAssertEqual(skipped, 0)

        let exportedAfterAll = try viewModel.dataForPDFExport()
        for index in 0..<3 {
            let text = Self.pageText(fromData: exportedAfterAll, pageIndex: index)
            XCTAssertTrue(text.contains("gadget"), "page \(index) must contain the replacement after Replace All")
        }
    }
}
