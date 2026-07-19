import AppKit
import PDFKit
import XCTest
@testable import Orifold

/// Embedded PDF bookmarks (`/Outlines`) surviving the export pipeline.
///
/// Export rebuilds the object graph repeatedly — assembly starts from a fresh
/// `PDFDocument`, and the form-flatten and decoration bakes re-render pages
/// through a `CGContext` — and no rebuild carries `/Outlines` across. So the
/// tree is not preserved by leaving it alone: it is captured as page indices up
/// front and written once, late, by `WorkspaceViewModel.applyingOutline`.
///
/// Indices rather than `PDFDestination` objects, because a destination holds a
/// `PDFPage` reference that stops resolving the moment assembly moves pages
/// into a new document. Written once and late, because re-serializing a parsed
/// outline can slip every destination forward a page — reliably so through the
/// member byte lane, which is what makes "apply at assembly and let it ride"
/// quietly wrong. The index assertions below are the part that catches it;
/// asserting titles alone passes against a tree pointing at the wrong pages.
///
/// Imposition is the deliberate exception; qpdf sanitize is exonerated. Both
/// have their own test below.
///
/// Note the assertions on the input side: asserting only that an export HAS an
/// outline would pass against a fixture whose bookmarks were never at risk.
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
        try addBlackDecoration(to: viewModel)

        let exported = try viewModel.dataForPDFExport()
        let reopened = try XCTUnwrap(PDFDocument(data: exported))

        XCTAssertGreaterThan(
            try inkCoverage(of: exported), 0.01,
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

    // MARK: - PDFOutlineBuilder

    func testBuilderRebuildsNestingFromAFlatDepthOrderedList() throws {
        let document = OutlineFixtures.blankPDF(pageCount: 4)

        PDFOutlineBuilder.apply([
            outlineNode("Chapter One", depth: 0, page: 0),
            outlineNode("Section 1.1", depth: 1, page: 1),
            outlineNode("Section 1.2", depth: 1, page: 2),
            outlineNode("Chapter Two", depth: 0, page: 3)
        ], to: document)

        let root = try XCTUnwrap(document.outlineRoot)
        XCTAssertEqual(root.numberOfChildren, 2, "two top-level chapters, sections nested beneath the first")
        XCTAssertEqual(root.child(at: 0)?.numberOfChildren, 2)
        XCTAssertEqual(root.child(at: 1)?.numberOfChildren, 0)

        // Round-trip through bytes: an outline that cannot be re-read from
        // serialized output is not preserved in any sense that matters.
        let reopened = try XCTUnwrap(PDFDocument(data: try XCTUnwrap(document.dataRepresentation())))
        let nodes = PDFOutlineReader.nodes(in: reopened)
        XCTAssertEqual(nodes.map(\.title), ["Chapter One", "Section 1.1", "Section 1.2", "Chapter Two"])
        XCTAssertEqual(nodes.map(\.depth), [0, 1, 1, 0])
        XCTAssertEqual(nodes.map(\.localPageIndex), [0, 1, 2, 3])
    }

    func testBuilderSkipsNodesPointingOutsideTheDocument() throws {
        let document = OutlineFixtures.blankPDF(pageCount: 2)

        PDFOutlineBuilder.apply([
            outlineNode("Real", depth: 0, page: 0),
            outlineNode("Past the end", depth: 0, page: 7)
        ], to: document)

        XCTAssertEqual(PDFOutlineReader.nodes(in: document).map(\.title), ["Real"])
    }

    func testBuilderLeavesTheDocumentUntouchedWhenThereAreNoNodes() throws {
        let document = OutlineFixtures.blankPDF(pageCount: 2)

        PDFOutlineBuilder.apply([], to: document)

        XCTAssertNil(
            document.outlineRoot,
            "an empty outline root would show as an empty navigation pane rather than none"
        )
    }

    /// A child arriving without a parent must land somewhere rather than being dropped.
    /// Real `/Outlines` trees are not always well-formed, and the reader's own
    /// promotion rule (lifting an unreadable node's children) emits exactly this.
    func testBuilderClampsOrphanedDepthsToTheDeepestAvailableParent() throws {
        let document = OutlineFixtures.blankPDF(pageCount: 3)

        PDFOutlineBuilder.apply([
            outlineNode("Deep opener", depth: 2, page: 0),
            outlineNode("Chapter", depth: 0, page: 1),
            outlineNode("Skipped a level", depth: 2, page: 2)
        ], to: document)

        let nodes = PDFOutlineReader.nodes(in: document)
        XCTAssertEqual(nodes.map(\.title), ["Deep opener", "Chapter", "Skipped a level"])
        XCTAssertEqual(nodes.map(\.depth), [0, 0, 1], "orphans clamp to one level below what exists")
    }

    // MARK: - Harness

    /// Solid black makes "did the bake run?" an unambiguous pixel question.
    private func addBlackDecoration(to viewModel: WorkspaceViewModel) throws {
        let pageRef = try XCTUnwrap(viewModel.document.workspace.pageOrder.first)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 64, pixelsHigh: 64, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.black.setFill()
        NSRect(x: 0, y: 0, width: 64, height: 64).fill()
        NSGraphicsContext.restoreGraphicsState()
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))

        viewModel.document.workspace.decorations.append(PageDecoration.image(
            imageData: png,
            pageRefID: pageRef.id,
            rect: CGRect(x: 40, y: 300, width: 400, height: 160)
        ))
    }

    /// Fraction of sampled pixels visibly non-white. Never asserts on `PDFPage.string`.
    private func inkCoverage(of data: Data, pageIndex: Int = 0) throws -> Double {
        let pdf = try XCTUnwrap(PDFDocument(data: data))
        let page = try XCTUnwrap(pdf.page(at: pageIndex))
        let bounds = page.bounds(for: .mediaBox)
        let thumbnail = page.thumbnail(of: CGSize(width: bounds.width, height: bounds.height), for: .mediaBox)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(thumbnail.tiffRepresentation)))

        var inked = 0
        var sampled = 0
        for sampleX in stride(from: 0, to: bitmap.pixelsWide, by: 7) {
            for sampleY in stride(from: 0, to: bitmap.pixelsHigh, by: 7) {
                guard let color = bitmap.colorAt(x: sampleX, y: sampleY)?.usingColorSpace(.deviceRGB) else { continue }
                sampled += 1
                if color.brightnessComponent < 0.85 { inked += 1 }
            }
        }
        guard sampled > 0 else { return 0 }
        return Double(inked) / Double(sampled)
    }
}

// MARK: - Fixtures

/// Reader-shaped node, the input side of `PDFOutlineBuilder`. Stays local: it builds
/// `PDFOutlineReader.OutlineNode`, not a PDF, so it has nothing to share with
/// `OutlineFixtures`.
private func outlineNode(_ title: String, depth: Int, page: Int) -> PDFOutlineReader.OutlineNode {
    PDFOutlineReader.OutlineNode(title: title, depth: depth, localPageIndex: page, hasChildren: false)
}
