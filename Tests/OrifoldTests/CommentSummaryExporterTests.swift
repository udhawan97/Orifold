import XCTest
@testable import Orifold

final class CommentSummaryExporterTests: XCTestCase {

    func testMarkdownListsCommentsWithPageSnippetTagsAndBody() {
        let markdown = CommentSummaryExporter.markdown(
            workspaceTitle: "Thesis",
            comments: [
                .init(pageNumber: 3, snippet: "the serpent", body: "Check this citation.",
                      tags: ["review", "todo"], isResolved: false)
            ],
            highlights: [],
            locale: Locale(identifier: "en")
        )
        XCTAssertTrue(markdown.contains("# "))
        XCTAssertTrue(markdown.contains("Thesis"))
        XCTAssertTrue(markdown.contains("3"))
        XCTAssertTrue(markdown.contains("the serpent"))
        XCTAssertTrue(markdown.contains("> Check this citation."))
        XCTAssertTrue(markdown.contains("review"))
        XCTAssertTrue(markdown.contains("todo"))
    }

    func testResolvedCommentIsMarked() {
        let markdown = CommentSummaryExporter.markdown(
            workspaceTitle: "T",
            comments: [.init(pageNumber: nil, snippet: nil, body: "Done item", tags: [], isResolved: true)],
            highlights: [],
            locale: Locale(identifier: "en")
        )
        XCTAssertTrue(markdown.contains("Resolved"))
    }

    func testMarkdownListsHighlightsWithQuotes() {
        let markdown = CommentSummaryExporter.markdown(
            workspaceTitle: "T",
            comments: [],
            highlights: [
                .init(pageNumber: 2, kind: .highlight, quote: "quoted passage"),
                .init(pageNumber: 5, kind: .strikeout, quote: nil)
            ],
            locale: Locale(identifier: "en")
        )
        XCTAssertTrue(markdown.contains("quoted passage"))
        XCTAssertTrue(markdown.contains("2"))
        XCTAssertTrue(markdown.contains("5"))
    }

    func testMultilineCommentBodyStaysInsideItsQuoteBlock() {
        let markdown = CommentSummaryExporter.markdown(
            workspaceTitle: "T",
            comments: [.init(pageNumber: 1, snippet: nil, body: "line one\nline two", tags: [], isResolved: false)],
            highlights: [],
            locale: Locale(identifier: "en")
        )
        XCTAssertTrue(markdown.contains("> line one\n> line two"))
    }

    func testEmptyInputsProduceNoSectionHeaders() {
        let markdown = CommentSummaryExporter.markdown(
            workspaceTitle: "T", comments: [], highlights: [], locale: Locale(identifier: "en")
        )
        XCTAssertEqual(markdown.components(separatedBy: "\n## ").count, 1, "no empty sections")
    }
}
