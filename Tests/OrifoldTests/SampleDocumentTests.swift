import PDFKit
import UniformTypeIdentifiers
import XCTest
@testable import Orifold

/// Covers the bundled CC0 sample/onboarding document (Feature D).
final class SampleDocumentTests: XCTestCase {
    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Tests/OrifoldTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // repo root
    }

    /// Regenerates `Orifold/Resources/SampleDocument.pdf` from the committed markdown
    /// source, driving it through the *exact* markdown→PDF path a real import uses
    /// (`DocumentImportConverter.importedDocument`), so the asset looks like something
    /// Orifold produced. Env-gated: it writes into the source tree, so it only runs when
    /// explicitly asked. Run once locally:
    ///
    ///     ORIFOLD_GENERATE_SAMPLE=1 swift test --filter SampleDocumentTests
    func testGenerateSampleDocument() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["ORIFOLD_GENERATE_SAMPLE"] == "1")

        let sourceURL = repoRoot().appendingPathComponent("scripts/generate-sample-document.md")
        let markdownData = try Data(contentsOf: sourceURL)

        let imported = try DocumentImportConverter.importedDocument(
            from: markdownData,
            contentType: .markdown,
            filename: "SampleDocument.md",
            baseURL: nil
        )

        XCTAssertGreaterThanOrEqual(imported.pdfDocument.pageCount, 3, "sample must be at least 3 pages")
        let pdfData = try XCTUnwrap(imported.pdfDocument.dataRepresentation(), "could not serialize sample PDF")
        XCTAssertLessThanOrEqual(pdfData.count, 1_500_000, "sample PDF must stay under 1.5 MB")

        let outputURL = repoRoot().appendingPathComponent("Orifold/Resources/SampleDocument.pdf")
        try pdfData.write(to: outputURL)
        print("Wrote \(outputURL.path): \(pdfData.count) bytes, \(imported.pdfDocument.pageCount) pages")
    }

    /// Always-on: the asset is bundled, resolvable via `SampleDocument.url`, opens as a
    /// valid PDF, and carries the onboarding content (≥3 pages).
    func testSampleDocumentBundledAndOpens() throws {
        let url = try XCTUnwrap(SampleDocument.url, "SampleDocument.pdf not found in bundle")
        let doc = try XCTUnwrap(PDFDocument(url: url), "bundled SampleDocument.pdf is not a readable PDF")
        XCTAssertGreaterThanOrEqual(doc.pageCount, 3)
    }

    /// The shipped asset must actually exercise the nested table of contents, because the
    /// sample is the only document a first-run user is guaranteed to open. A sample with a
    /// flat outline silently hides the feature.
    ///
    /// Depths are asserted against `PDFOutlineReader`, the same path the TOC reads through.
    /// Chapters must sit at depth 0: `TOCView.isExpanded` opens depth-0 rows only, so a
    /// document whose chapters hang under a title heading would show one collapsed row.
    func testSampleDocumentShipsNestedBookmarksVisibleWhenThePopoverOpens() throws {
        let url = try XCTUnwrap(SampleDocument.url, "SampleDocument.pdf not found in bundle")
        let doc = try XCTUnwrap(PDFDocument(url: url), "bundled SampleDocument.pdf is not a readable PDF")

        let nodes = PDFOutlineReader.nodes(in: doc)
        XCTAssertFalse(nodes.isEmpty, "sample ships no embedded bookmarks — first run cannot discover the TOC")

        let chapters = nodes.filter { $0.depth == 0 }
        XCTAssertGreaterThanOrEqual(chapters.count, 3, "expected ≥3 chapters at the level that opens expanded")
        XCTAssertTrue(
            nodes.contains { $0.depth == 1 },
            "expected at least one nested subsection so the tree demonstrates nesting"
        )
        XCTAssertTrue(
            chapters.contains(where: \.hasChildren),
            "the nested subsection must hang off a chapter, so a disclosure control is visible on open"
        )
    }

    /// What the table-of-contents popover actually draws for a first-run user who opens the
    /// sample — composed through `tableOfContents` and flattened with the same default
    /// expansion rule as `TOCView.isExpanded` (depth-0 open, deeper levels collapsed).
    ///
    /// Guards the discoverability property, not just the bytes: every chapter must be on
    /// screen the moment the popover opens, with the nested pair one disclosure away.
    @MainActor
    func testOpeningTheTOCPopoverOnTheSampleShowsEveryChapterAndOneNestedPair() throws {
        let url = try XCTUnwrap(SampleDocument.url, "SampleDocument.pdf not found in bundle")
        let data = try Data(contentsOf: url)
        let pdf = try XCTUnwrap(PDFDocument(data: data))

        var member = MemberDocument(displayName: "Sample", sourcePDFRef: "SampleDocument.pdf")
        let refs = (0..<pdf.pageCount).map { PageRef(memberDocId: member.id, sourcePageIndex: $0) }
        member.pageRefs = refs.map(\.id)

        let document = WorkspaceDocument()
        document.workspace.documents = [member]
        document.workspace.pageOrder = refs
        document.memberPDFData[member.id] = data
        let viewModel = WorkspaceViewModel(document: document)
        let entries = viewModel.tableOfContents

        let onOpen = WorkspaceViewModel.TOCEntry.visibleEntries(in: entries) { $0.depth == 0 }
        XCTAssertEqual(
            onOpen.dropFirst().map(\.title),  // dropFirst: the file row itself
            [
                "The Serpent on the Bridge",
                "The Dragon King's Plea",
                "The Palace Beneath the Lake",
                "The Battle with the Centipede",
                "The Dragon King's Gifts"
            ],
            "every chapter must be visible without the user expanding anything"
        )
        XCTAssertTrue(
            onOpen.contains { $0.title == "The Battle with the Centipede" && $0.hasChildren },
            "the chapter holding the subsections must render a disclosure control"
        )

        let fullyExpanded = WorkspaceViewModel.TOCEntry.visibleEntries(in: entries) { _ in true }
        XCTAssertEqual(
            fullyExpanded.filter { $0.depth == 2 }.map(\.title),
            ["The First Two Arrows", "The Last Arrow"],
            "expanding the chapter must reveal its nested subsections"
        )
    }
}
