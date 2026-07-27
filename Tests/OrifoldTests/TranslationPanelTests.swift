import PDFKit
import XCTest
@testable import Orifold

final class TranslationPanelTests: XCTestCase {
    private struct FakeTranslator: TextTranslating {
        let output: [String]

        func translate(_ chunks: [String]) async throws -> [String] {
            XCTAssertEqual(chunks.count, output.count)
            return output
        }
    }

    func testChunkerKeepsShortTextTogetherAndRejectsWhitespaceOnlyInput() {
        XCTAssertEqual(TranslationChunker.chunk("  One short sentence.  ", maxCharacters: 80), ["One short sentence."])
        XCTAssertTrue(TranslationChunker.chunk(" \n\t ", maxCharacters: 80).isEmpty)
    }

    func testChunkerHonorsLimitWithoutSplittingOrdinaryWords() {
        let source = "First sentence stays readable. Second sentence also stays readable. A final sentence closes the paragraph."
        let chunks = TranslationChunker.chunk(source, maxCharacters: 42)

        XCTAssertGreaterThan(chunks.count, 1)
        XCTAssertTrue(chunks.allSatisfy { !$0.isEmpty && $0.count <= 42 })
        XCTAssertEqual(
            chunks.joined(separator: " ").split(whereSeparator: \.isWhitespace).joined(separator: " "),
            source.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        )
    }

    func testSourceResolverPrefersSelectionThenFallsBackToCurrentPage() throws {
        let selected = try XCTUnwrap(
            TranslationSourceResolver.request(selection: " selected words ", currentPage: "whole page")
        )
        XCTAssertEqual(selected.sourceKind, .selection)
        XCTAssertEqual(selected.source, "selected words")

        let page = try XCTUnwrap(
            TranslationSourceResolver.request(selection: " ", currentPage: " whole page ")
        )
        XCTAssertEqual(page.sourceKind, .currentPage)
        XCTAssertEqual(page.source, "whole page")

        XCTAssertNil(TranslationSourceResolver.request(selection: nil, currentPage: "\n"))
    }

    @MainActor
    func testPanelModelPublishesTranslatedChunksInOrder() async {
        let request = TranslationRequestText(
            sourceKind: .selection,
            source: "One. Two.",
            chunks: ["One.", "Two."]
        )
        let model = TranslationPanelModel(
            request: request,
            translator: FakeTranslator(output: ["Uno.", "Dos."])
        )

        await model.translate()

        XCTAssertEqual(model.translatedText, "Uno.\n\nDos.")
        XCTAssertFalse(model.isTranslating)
        XCTAssertNil(model.errorMessage)
    }

    @MainActor
    func testWorkspaceTranslationRequestUsesPDFiumBackedCurrentPageText() throws {
        let source = "A local translation fixture"
        let data = EditingFixturePDFBuilder.makePDF(runs: [
            .init(string: source, origin: CGPoint(x: 72, y: 700))
        ])
        let wrapper = FileWrapper(regularFileWithContents: data)
        wrapper.preferredFilename = "Translation.pdf"
        let document = try WorkspaceDocument(
            testingFile: wrapper,
            contentType: .pdf,
            filename: "Translation.pdf"
        )
        let viewModel = WorkspaceViewModel(document: document, processingEngine: PDFiumProcessingEngine())
        viewModel.currentPageNumber = 1

        let request = try XCTUnwrap(viewModel.translationRequestText)

        XCTAssertEqual(request.sourceKind, .currentPage)
        XCTAssertTrue(request.source.contains(source))

        let page = try XCTUnwrap(PDFDocument(data: data)?.page(at: 0))
        let sourceBlock = try XCTUnwrap(
            PDFTextAnalysisEngine()
                .analyze(data: data, pageIndex: 0, pageRefID: UUID(), fallbackPage: page)
                .blocks
                .first
        )
        let pageRef = try XCTUnwrap(viewModel.document.workspace.pageOrder.first)
        let undoManager = UndoManager()
        viewModel.undoManager = undoManager
        XCTAssertTrue(viewModel.applyInlineTextEdit(
            pageRef: pageRef,
            sourceBlock: sourceBlock,
            replacementText: "Edited text shown to the reader",
            editedBounds: sourceBlock.bounds,
            fontName: sourceBlock.fontName,
            fontSize: sourceBlock.fontSize,
            textColor: .black,
            alignment: .left
        ))

        let editedRequest = try XCTUnwrap(viewModel.translationRequestText)
        XCTAssertTrue(editedRequest.source.contains("Edited text shown to the reader"))
        XCTAssertFalse(editedRequest.source.contains(source))
    }
}
