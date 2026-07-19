import AppKit
import PDFKit
import XCTest
@testable import Orifold

/// Embedded PDF bookmarks (`/Outlines`) surviving the export pipeline.
///
/// Two defects, two repairs, and both are load-bearing:
///
/// - Every rebuild drops the tree. Assembly starts from a fresh `PDFDocument`, and the
///   form-flatten and decoration bakes re-render pages through a `CGContext`. So the
///   outline is captured as page INDICES and written once, late, by
///   `WorkspaceViewModel.applyingOutline` — indices because a `PDFDestination` holds a
///   `PDFPage` reference that stops resolving once assembly moves pages elsewhere.
/// - Serializing a document the app has held open writes destinations a page LATE, while
///   a pristine parse of the same bytes writes them correctly. `PDFOutlineBuilder
///   .reanchoring` repairs that in the member byte lane, which the late write cannot
///   reach — see the embedded-workspace-state test.
///
/// Assert on page indices, not titles. Titles survive both defects; a tree pointing one
/// page past every heading passes a title-only check, which is how this stayed invisible.
/// Each test also states what went IN: asserting only that an export HAS an outline would
/// pass against a fixture whose bookmarks were never at risk.
///
/// Imposition is the deliberate exception; qpdf sanitize is exonerated. Both tested below.
final class PDFOutlineExportTests: XCTestCase {

    // MARK: - Preservation through the pipeline

    func testExportPreservesNestedBookmarks() throws {
        let fixture = try OutlineFixtures.outlinedMember(
            name: "Manual",
            pageCount: 4,
            outline: [
                OutlineFixtureSpec(title: "Chapter One", page: 0, children: [
                    OutlineFixtureSpec(title: "Section 1.1", page: 1)
                ]),
                OutlineFixtureSpec(title: "Chapter Two", page: 2)
            ]
        )
        let viewModel = OutlineFixtures.viewModel(members: [fixture])

        // Precondition: the workspace really does carry bookmarks going in, so
        // the assertions below cannot pass against a fixture with nothing to lose.
        XCTAssertEqual(
            viewModel.tableOfContents.filter { $0.depth > 0 }.map(\.title),
            ["Chapter One", "Section 1.1", "Chapter Two"],
            "precondition: the TOC reads the fixture's embedded bookmarks"
        )

        let exported = try viewModel.dataForPDFExport()
        let reopened = try XCTUnwrap(PDFDocument(data: exported))

        XCTAssertEqual(reopened.pageCount, 4)
        let nodes = PDFOutlineReader.nodes(in: reopened)
        XCTAssertEqual(nodes.map(\.title), ["Chapter One", "Section 1.1", "Chapter Two"])
        XCTAssertEqual(nodes.map(\.depth), [0, 1, 0], "nesting survives, not just the labels")
        XCTAssertEqual(nodes.map(\.localPageIndex), [0, 1, 2], "each bookmark still points at its own page")
    }

    /// The part a naive fix gets wrong: each member's bookmarks are indexed within
    /// that member, and assembly concatenates members into one page list.
    func testExportOffsetsBookmarkPagesAcrossMembers() throws {
        let first = try OutlineFixtures.outlinedMember(
            name: "First", pageCount: 3,
            outline: [OutlineFixtureSpec(title: "Alpha", page: 0), OutlineFixtureSpec(title: "Beta", page: 2)]
        )
        let second = try OutlineFixtures.outlinedMember(
            name: "Second", pageCount: 2,
            outline: [OutlineFixtureSpec(title: "Gamma", page: 1)]
        )
        let viewModel = OutlineFixtures.viewModel(members: [first, second])

        let exported = try viewModel.dataForPDFExport()
        let reopened = try XCTUnwrap(PDFDocument(data: exported))

        XCTAssertEqual(reopened.pageCount, 5)
        let nodes = PDFOutlineReader.nodes(in: reopened)
        XCTAssertEqual(nodes.map(\.title), ["Alpha", "Beta", "Gamma"])
        XCTAssertEqual(
            nodes.map(\.localPageIndex), [0, 2, 4],
            "the second member's bookmark shifts by the first member's page count"
        )
    }

    /// The decoration bake re-renders pages through a `CGContext`, producing a PDF with
    /// no `/Outlines` at all — so without the late write, bookmarks survive a plain
    /// export and vanish the moment a stamp is present. Silent, conditional data loss.
    func testExportPreservesBookmarksThroughTheDecorationBake() throws {
        let fixture = try OutlineFixtures.outlinedMember(
            name: "Manual", pageCount: 3,
            outline: [
                OutlineFixtureSpec(title: "Chapter One", page: 0),
                OutlineFixtureSpec(title: "Chapter Two", page: 2)
            ]
        )
        let viewModel = OutlineFixtures.viewModel(members: [fixture])
        try DecorationProbe.addBlackDecoration(to: viewModel)

        let exported = try viewModel.dataForPDFExport()
        let reopened = try XCTUnwrap(PDFDocument(data: exported))

        XCTAssertGreaterThan(
            try DecorationProbe.inkCoverage(of: exported), 0.01,
            "precondition: the decoration really did bake, so the CGContext rebuild really did run"
        )
        XCTAssertEqual(PDFOutlineReader.nodes(in: reopened).map(\.title), ["Chapter One", "Chapter Two"])
        XCTAssertEqual(PDFOutlineReader.nodes(in: reopened).map(\.localPageIndex), [0, 2])
    }

    func testExportPreservesBookmarksThroughSanitize() throws {
        let fixture = try OutlineFixtures.outlinedMember(
            name: "Manual", pageCount: 3,
            outline: [OutlineFixtureSpec(title: "Chapter One", page: 0)]
        )
        let viewModel = OutlineFixtures.viewModel(members: [fixture])

        let exported = try viewModel.dataForPDFExport(
            options: WorkspaceExportOptions(sanitization: PDFSanitizationOptions(removesMetadata: true))
        )
        let reopened = try XCTUnwrap(PDFDocument(data: exported))

        XCTAssertEqual(PDFOutlineReader.nodes(in: reopened).map(\.title), ["Chapter One"])
    }

    /// The outline write is a PDFKit round-trip, and those drop embedded files, so it
    /// must sit BEFORE attachments are re-grafted. Moving it after re-injection keeps
    /// bookmarks and silently loses every attachment — no other test catches that.
    func testBookmarksAndAttachmentsBothSurviveTheSameExport() throws {
        let fixture = try OutlineFixtures.outlinedMember(
            name: "Manual", pageCount: 3,
            outline: [
                OutlineFixtureSpec(title: "Chapter One", page: 0),
                OutlineFixtureSpec(title: "Chapter Two", page: 2)
            ]
        )
        let viewModel = OutlineFixtures.viewModel(members: [fixture])

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Orifold-outline-att-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let payloadURL = directory.appendingPathComponent("keep.txt")
        try Data("survive-export".utf8).write(to: payloadURL)
        XCTAssertTrue(viewModel.addAttachment(payloadURL))

        let exported = try viewModel.dataForPDFExport()

        XCTAssertEqual(
            try AttachmentsService.list(in: exported).map(\.name), ["keep.txt"],
            "the outline stage must not run after attachment re-injection"
        )
        XCTAssertEqual(try AttachmentsService.extract("keep.txt", from: exported), Data("survive-export".utf8))
        let reopened = try XCTUnwrap(PDFDocument(data: exported))
        XCTAssertEqual(PDFOutlineReader.nodes(in: reopened).map(\.title), ["Chapter One", "Chapter Two"])
        XCTAssertEqual(PDFOutlineReader.nodes(in: reopened).map(\.localPageIndex), [0, 2])
    }

    /// `exportCompressedPDF` compresses AFTER the outline is written, and compression's
    /// primary path is a PDFKit optimizing write — the parse-then-serialize shape that
    /// shifts destinations elsewhere here. Exercised as the raw operation because
    /// `reducedData` refuses any fixture it cannot make smaller.
    func testCompressionsOptimizingWriteDoesNotShiftDestinations() throws {
        let pdf = OutlineFixtures.outlinedPDF(
            pageCount: 4,
            outline: [
                OutlineFixtureSpec(title: "Chapter One", page: 0),
                OutlineFixtureSpec(title: "Chapter Two", page: 2)
            ]
        )
        XCTAssertEqual(
            PDFOutlineReader.nodes(in: pdf).map(\.localPageIndex), [0, 2],
            "precondition: the fixture points where we think it does"
        )

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertTrue(pdf.write(to: url, withOptions: [
            .saveImagesAsJPEGOption: true,
            .optimizeImagesForScreenOption: true
        ]))

        let reopened = try XCTUnwrap(PDFDocument(data: try Data(contentsOf: url)))
        let nodes = PDFOutlineReader.nodes(in: reopened)
        XCTAssertEqual(nodes.map(\.title), ["Chapter One", "Chapter Two"])
        XCTAssertEqual(nodes.map(\.localPageIndex), [0, 2], "compression must not shift destinations")
    }

    /// Where the two halves of the bookmark feature meet: markdown import GENERATES an
    /// outline, and export preserves it. Each side is covered alone — `MarkdownOutlineTests`
    /// stops at the imported document, and the tests above start from a synthetic fixture —
    /// so nothing else would notice if generated bookmarks were the one kind that did not
    /// survive. Markdown is now the app's main source of bookmarks, which makes this the
    /// path most users actually hit.
    func testMarkdownGeneratedBookmarksSurviveExport() throws {
        let markdown = """
        # Title

        ## Chapter One

        Body.

        ## Chapter Two

        Body.
        """
        let imported = try DocumentImportConverter.importedDocument(
            from: Data(markdown.utf8),
            contentType: .markdown,
            filename: "Outline.md",
            baseURL: nil
        )
        XCTAssertEqual(
            PDFOutlineReader.nodes(in: imported.pdfDocument).map(\.title),
            ["Title", "Chapter One", "Chapter Two"],
            "precondition: import generated the outline"
        )

        var member = MemberDocument(displayName: "Outline", sourcePDFRef: "Outline.md")
        let pdf = imported.pdfDocument
        let refs = (0..<pdf.pageCount).map { PageRef(memberDocId: member.id, sourcePageIndex: $0) }
        member.pageRefs = refs.map(\.id)
        let data = try XCTUnwrap(PDFSerializer.data(from: pdf))
        let viewModel = OutlineFixtures.viewModel(members: [
            OutlineFixtureMember(member: member, refs: refs, data: data)
        ])

        let exported = try viewModel.dataForPDFExport()
        let reopened = try XCTUnwrap(PDFDocument(data: exported))
        let nodes = PDFOutlineReader.nodes(in: reopened)

        XCTAssertEqual(nodes.map(\.title), ["Title", "Chapter One", "Chapter Two"])
        XCTAssertEqual(nodes.map(\.depth), [0, 1, 1], "the generated nesting survives too")
    }

    /// The export's *flattened* outline and its *embedded member bytes* are two different
    /// artefacts, and fixing the first does not fix the second. `embedsEditableWorkspaceState`
    /// stores `snapshot.memberPDFData` inside the PDF so a workspace can be reopened from
    /// it; those bytes come off the serializer that writes destinations a page late, so
    /// without `PDFOutlineBuilder.reanchoring` a reopened workspace shows every bookmark
    /// pointing one page past its heading — while the flattened outline beside it reads
    /// correctly. Measured: pages 1 and 3 with the repair, 2 and 4 without.
    func testReopenedWorkspaceKeepsBookmarkPagesAfterAnEmbeddedStateExport() throws {
        let fixture = try OutlineFixtures.outlinedMember(
            name: "Manual", pageCount: 4,
            outline: [
                OutlineFixtureSpec(title: "Chapter One", page: 0),
                OutlineFixtureSpec(title: "Chapter Two", page: 2)
            ]
        )
        let viewModel = OutlineFixtures.viewModel(members: [fixture])

        let exported = try viewModel.dataForPDFExport(
            options: WorkspaceExportOptions(embedsEditableWorkspaceState: true)
        )
        let reopened = WorkspaceViewModel(
            document: try WorkspaceDocument(
                testingFile: FileWrapper(regularFileWithContents: exported),
                contentType: .pdf,
                filename: "Manual.pdf"
            ),
            processingEngine: PDFiumProcessingEngine()
        )

        let member = try XCTUnwrap(reopened.loadedPDFs.first?.1)
        XCTAssertEqual(
            PDFOutlineReader.nodes(in: member).map(\.localPageIndex), [0, 2],
            "restored member bookmarks must not drift a page on the way through the byte lane"
        )
        XCTAssertEqual(
            reopened.tableOfContents.filter { $0.depth > 0 }.map(\.displayPageNumber), [1, 3]
        )
    }

    // MARK: - The deliberate exception

    /// The one stage where dropping bookmarks is correct rather than lossy.
    /// `imp_ImportNPagesToOne` wraps N pages onto one sheet, so a page-anchored
    /// bookmark no longer identifies a page — and booklet order interleaves the
    /// sequence besides. Preserving it would mean confidently wrong navigation.
    func testImpositionDropsBookmarksBecausePagesNoLongerMapOneToOne() throws {
        let fixture = try OutlineFixtures.outlinedMember(
            name: "Manual", pageCount: 4,
            outline: [
                OutlineFixtureSpec(title: "Chapter One", page: 0),
                OutlineFixtureSpec(title: "Chapter Two", page: 2)
            ]
        )
        let viewModel = OutlineFixtures.viewModel(members: [fixture])

        XCTAssertFalse(
            PDFOutlineReader.nodes(in: try XCTUnwrap(PDFDocument(data: try viewModel.dataForPDFExport()))).isEmpty,
            "precondition: the same workspace keeps its bookmarks without imposition"
        )

        let imposed = try viewModel.dataForPDFExport(
            options: WorkspaceExportOptions(imposition: .nUp(rows: 1, cols: 2))
        )
        let reopened = try XCTUnwrap(PDFDocument(data: imposed))

        XCTAssertEqual(reopened.pageCount, 2, "4 pages 2-up onto 2 sheets")
        XCTAssertNil(reopened.outlineRoot, "bookmarks are dropped rather than pointed at merged sheets")
    }

    // MARK: - Sanitize is not the culprit

    func testSanitizePreservesAnOutlineTree() throws {
        let pdf = OutlineFixtures.outlinedPDF(
            pageCount: 3, outline: [OutlineFixtureSpec(title: "Chapter One", page: 0)]
        )
        let bytes = try XCTUnwrap(pdf.dataRepresentation())

        let sanitized = try WorkspaceViewModel.sanitized(
            bytes, options: PDFSanitizationOptions(removesMetadata: true)
        )
        let reopened = try XCTUnwrap(PDFDocument(data: sanitized))

        XCTAssertNotNil(
            reopened.outlineRoot,
            "sanitize strips /OpenAction, /AA, JavaScript, EmbeddedFiles, /Info and /Metadata — not /Outlines"
        )
        XCTAssertEqual(PDFOutlineReader.nodes(in: reopened).map(\.title), ["Chapter One"])
    }
}

// MARK: - Fixtures
