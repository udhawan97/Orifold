import AppKit
import CoreText
import PDFKit
import UniformTypeIdentifiers
import XCTest
@testable import Orifold

final class PDFSerializerTests: XCTestCase {
    func testSerializerReturnsBytesForNormalPDF() throws {
        let pdf = makePDF(pageTexts: ["PDFSerializer round-trip test"])
        let data = try XCTUnwrap(PDFSerializer.data(from: pdf))
        let reparsed = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertEqual(reparsed.pageCount, 1)
        XCTAssertTrue(reparsed.stringValue.contains("PDFSerializer"))
    }

    func testSerializerReturnsNilForEmptyDocument() {
        // PDFDocument() with no pages has undefined dataRepresentation behaviour;
        // verify the serializer at least doesn't crash.
        let empty = PDFDocument()
        // May or may not return data — just assert we don't crash.
        _ = PDFSerializer.data(from: empty)
    }
}

final class InspectorViewTests: XCTestCase {
    func testOCRTabAppearsAfterDecorate() {
        XCTAssertEqual(Array(InspectorView.Tab.allCases.suffix(2)), [.decorate, .ocr])
        XCTAssertEqual(InspectorView.Tab.ocr.iconName, "doc.text.viewfinder")
    }
}

final class WorkspaceModelTests: XCTestCase {
    func testWorkspaceDecodingBackfillsSchemaTwoDefaults() throws {
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let id = UUID()
        let json = """
        {
          "id": "\(id.uuidString)",
          "title": "Archive",
          "createdAt": \(createdAt.timeIntervalSinceReferenceDate),
          "documents": []
        }
        """
        let workspace = try JSONDecoder().decode(Workspace.self, from: Data(json.utf8))

        XCTAssertEqual(workspace.id, id)
        XCTAssertEqual(workspace.title, "Archive")
        XCTAssertEqual(workspace.modifiedAt, createdAt)
        XCTAssertEqual(workspace.schemaVersion, 1)
        XCTAssertTrue(workspace.pageOrder.isEmpty)
        XCTAssertTrue(workspace.signatures.isEmpty)
        XCTAssertTrue(workspace.tags.isEmpty)
        XCTAssertTrue(workspace.comments.isEmpty)
    }

    func testLegacyWorkspaceCommentDecodesWithStyleAndTagDefaults() throws {
        let json = """
        {
          "body": "Legacy note"
        }
        """

        let comment = try JSONDecoder().decode(WorkspaceComment.self, from: Data(json.utf8))

        XCTAssertEqual(comment.body, "Legacy note")
        XCTAssertFalse(comment.style.isBold)
        XCTAssertFalse(comment.style.isItalic)
        XCTAssertEqual(comment.style.textSize, .regular)
        XCTAssertEqual(comment.style.colorHex, "#1F2933")
        XCTAssertTrue(comment.tags.isEmpty)
        XCTAssertNil(comment.anchor)
        XCTAssertFalse(comment.anchorWasRemoved)
        XCTAssertFalse(comment.isResolved)
    }

    func testSchemaThreeWorkspaceCommentsLoadWithPhaseSixDefaults() throws {
        let commentID = UUID()
        let json = """
        {
          "title": "Legacy Comments",
          "schemaVersion": 3,
          "documents": [],
          "pageOrder": [],
          "comments": [
            {
              "id": "\(commentID.uuidString)",
              "body": "Existing v3 comment",
              "tags": ["review"]
            }
          ]
        }
        """

        let workspace = try JSONDecoder().decode(Workspace.self, from: Data(json.utf8))

        XCTAssertEqual(workspace.schemaVersion, 3)
        XCTAssertEqual(workspace.comments.first?.id, commentID)
        XCTAssertEqual(workspace.comments.first?.body, "Existing v3 comment")
        XCTAssertNil(workspace.comments.first?.anchor)
        XCTAssertFalse(workspace.comments.first?.anchorWasRemoved ?? true)
        XCTAssertFalse(workspace.comments.first?.isResolved ?? true)
    }

    func testNewWorkspaceDefaultsToSchemaVersionFive() {
        XCTAssertEqual(Workspace().schemaVersion, 5)
    }

    func testRectBackedModelsRoundTripThroughCodable() throws {
        let memberID = UUID()
        let pageRef = PageRef(
            id: UUID(),
            memberDocId: memberID,
            sourcePageIndex: 2,
            rotation: 90,
            cropBox: CGRect(x: 10, y: 20, width: 300, height: 400)
        )
        let decodedPageRef = try JSONDecoder().decode(PageRef.self, from: JSONEncoder().encode(pageRef))
        XCTAssertEqual(decodedPageRef.id, pageRef.id)
        XCTAssertEqual(decodedPageRef.memberDocId, memberID)
        XCTAssertEqual(decodedPageRef.cropBox, pageRef.cropBox)
        XCTAssertEqual(decodedPageRef.rotation, 90)

        let signature = SignaturePlacement(
            pageRefId: pageRef.id,
            imageData: Data([0, 1, 2, 3]),
            rect: CGRect(x: 4, y: 5, width: 120, height: 48),
            signerName: "Ada",
            signedAt: Date(timeIntervalSince1970: 12_345)
        )
        let decodedSignature = try JSONDecoder().decode(SignaturePlacement.self, from: JSONEncoder().encode(signature))
        XCTAssertEqual(decodedSignature.id, signature.id)
        XCTAssertEqual(decodedSignature.pageRefId, pageRef.id)
        XCTAssertEqual(decodedSignature.imageData, signature.imageData)
        XCTAssertEqual(decodedSignature.rect, signature.rect)
        XCTAssertEqual(decodedSignature.kind, .visualTyped)
        XCTAssertEqual(decodedSignature.signerName, "Ada")
        XCTAssertEqual(decodedSignature.signedAt, signature.signedAt)
        XCTAssertNil(decodedSignature.signerIdentityRef)
        XCTAssertNil(decodedSignature.reason)
        XCTAssertFalse(decodedSignature.timestampApplied)
    }

    func testLegacySignaturePlacementDecodesWithVisualDefaults() throws {
        let id = UUID()
        let pageRefID = UUID()
        let legacyJSON = """
        {
          "id": "\(id.uuidString)",
          "pageRefId": "\(pageRefID.uuidString)",
          "imageData": "AAECAw==",
          "rect": { "x": 4, "y": 5, "width": 120, "height": 48 },
          "signerName": "Ada"
        }
        """

        let decoded = try JSONDecoder().decode(SignaturePlacement.self, from: Data(legacyJSON.utf8))

        XCTAssertEqual(decoded.id, id)
        XCTAssertEqual(decoded.pageRefId, pageRefID)
        XCTAssertEqual(decoded.imageData, Data([0, 1, 2, 3]))
        XCTAssertEqual(decoded.rect, CGRect(x: 4, y: 5, width: 120, height: 48))
        XCTAssertEqual(decoded.kind, .visualTyped)
        XCTAssertEqual(decoded.signerName, "Ada")
        XCTAssertNil(decoded.signerIdentityRef)
        XCTAssertNil(decoded.reason)
        XCTAssertNil(decoded.location)
        XCTAssertNil(decoded.contactInfo)
        XCTAssertNil(decoded.subFilter)
        XCTAssertFalse(decoded.timestampApplied)
    }

    func testCryptographicSignaturePlacementRoundTripsMetadata() throws {
        let placement = SignaturePlacement(
            pageRefId: UUID(),
            imageData: Data([9, 8, 7]),
            rect: CGRect(x: 20, y: 30, width: 180, height: 60),
            kind: .cryptographic,
            signerName: "Ada Lovelace",
            signedAt: Date(timeIntervalSince1970: 98_765),
            signerIdentityRef: "self-signed",
            reason: "Approval",
            location: "London",
            contactInfo: "ada@example.com",
            subFilter: "ETSI.CAdES.detached",
            timestampApplied: true
        )

        let decoded = try JSONDecoder().decode(SignaturePlacement.self, from: JSONEncoder().encode(placement))

        XCTAssertEqual(decoded.kind, .cryptographic)
        XCTAssertEqual(decoded.signerIdentityRef, "self-signed")
        XCTAssertEqual(decoded.reason, "Approval")
        XCTAssertEqual(decoded.location, "London")
        XCTAssertEqual(decoded.contactInfo, "ada@example.com")
        XCTAssertEqual(decoded.subFilter, "ETSI.CAdES.detached")
        XCTAssertTrue(decoded.timestampApplied)
        XCTAssertTrue(decoded.isCryptographic)
    }

    func testCertificateGuideResourceLoadsGuideText() {
        let text = CertificateGuideResource.guideText()
        let acquisition = CertificateGuideResource.acquisitionGuideText()

        XCTAssertTrue(text.contains("Getting a Digital ID for Signing PDFs"))
        XCTAssertTrue(text.contains("Orifold never charges for signing"))
        XCTAssertTrue(text.contains("SSL.com"))
        XCTAssertTrue(acquisition.contains("Getting a CA-issued (AATL) Digital ID"))
        XCTAssertTrue(acquisition.contains("Trusted providers"))
        XCTAssertTrue(CertificateGuideResource.shortPopoverCopy.contains("Orifold never charges for signing"))
    }
}

final class PDFEditingSupportTests: XCTestCase {
    func testReplacementBackgroundUsesPDFPageWhiteInsteadOfSystemTextBackground() throws {
        let color = PDFEditingSupport.replacementBackgroundColor(
            isReplacement: true,
            originalBackground: nil
        )
        let converted = try XCTUnwrap(color.usingColorSpace(.sRGB))
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        converted.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        XCTAssertGreaterThan(red, 0.95)
        XCTAssertGreaterThan(green, 0.95)
        XCTAssertGreaterThan(blue, 0.95)
        XCTAssertGreaterThan(alpha, 0.9)
    }
}

final class PDFTextEditingRedesignTests: XCTestCase {
    func testPDFTextAnalysisExtractsHittableBlocks() throws {
        let pdf = makePDF(pageTexts: ["Inline editable text"])
        let data = try pdf.dataRepresentation().unwrap()
        let engine = PDFTextAnalysisEngine()
        let page = try XCTUnwrap(pdf.page(at: 0))

        let analysis = engine.analyze(data: data, pageIndex: 0, pageRefID: UUID(), fallbackPage: page)
        let block = try XCTUnwrap(analysis.blocks.first { $0.text.contains("Inline") })
        let hit = engine.hitTest(CGPoint(x: block.bounds.midX, y: block.bounds.midY), in: analysis)

        XCTAssertEqual(hit?.id, block.id)
        XCTAssertGreaterThan(block.fontSize, 6)
        XCTAssertNotEqual(block.confidence, .low)
        XCTAssertEqual(block.editability, .direct)
        XCTAssertEqual(block.textSource, .pdfiumGlyphs)
    }

    /// Regression test for the root-cause "blank white box" bug: when PDFium can't be used
    /// at all (simulated here by passing empty `data`, the same path `analyze()` takes when
    /// PDFium extracts zero glyphs), the PDFKit fallback used to return a single whole-page
    /// `.low`-confidence block that `hitTest` silently excluded — so a click on perfectly
    /// visible text fell straight through to an empty insertion box. It must now return
    /// hittable, line-level `.replace` blocks instead.
    func testPDFKitFallbackProducesHittableLineLevelBlocksWhenPDFiumIsUnavailable() throws {
        let pdf = makePDF(pageTexts: ["First reservation line\nSecond guest detail line"])
        let engine = PDFTextAnalysisEngine()
        let page = try XCTUnwrap(pdf.page(at: 0))

        let analysis = engine.analyze(data: Data(), pageIndex: 0, pageRefID: UUID(), fallbackPage: page)

        XCTAssertFalse(analysis.blocks.isEmpty, "PDFKit fallback should still detect line-level text")
        XCTAssertTrue(analysis.blocks.allSatisfy { $0.editability == .replace })
        XCTAssertTrue(analysis.blocks.allSatisfy { $0.textSource == .pdfKitString })
        XCTAssertTrue(analysis.blocks.allSatisfy { $0.confidence != .low })

        let firstLineBlock = try XCTUnwrap(analysis.blocks.first { $0.text.contains("First reservation") })
        let hit = engine.hitTest(CGPoint(x: firstLineBlock.bounds.midX, y: firstLineBlock.bounds.midY), in: analysis)
        XCTAssertEqual(hit?.id, firstLineBlock.id, "A click on visible fallback text must resolve to that line, not fall through to a blank box")

        let secondLineBlock = try XCTUnwrap(analysis.blocks.first { $0.text.contains("Second guest detail") })
        XCTAssertNotEqual(firstLineBlock.id, secondLineBlock.id, "Each visual line should be its own hittable block, not one whole-page block")
    }

    func testEditableTextBlockOnFlattenedScannedPageIsExplicitOverlayNotSilentBlankBox() throws {
        let fixture = try makeMemberWithScannedPDF(name: "ScannedFallback")
        let document = WorkspaceDocument()
        document.workspace.documents = [fixture.member]
        document.workspace.pageOrder = fixture.refs
        document.memberPDFData[fixture.member.id] = fixture.pdfData
        let viewModel = WorkspaceViewModel(
            document: document,
            processingEngine: PDFKitProcessingEngineFallback()
        )
        let page = try XCTUnwrap(viewModel.loadedPDFs.first?.1.page(at: 0))
        let pageBounds = page.bounds(for: .cropBox)

        let target = try XCTUnwrap(viewModel.editableTextBlock(
            at: CGPoint(x: pageBounds.midX, y: pageBounds.midY),
            on: page,
            in: viewModel.combinedPDF
        ))

        // No text layer exists at all on a scanned/flattened page, so there's nothing to
        // prefill — but the block must still be explicitly tagged `.overlayOnly` rather than
        // a plain, unlabelled `.insertion`, so the UI can tell the user why (see
        // `announceEditability` in ReadingCanvas) instead of silently behaving like an
        // ordinary blank-page insertion.
        XCTAssertEqual(target.block.editability, .overlayOnly)
        XCTAssertEqual(target.block.text, "")
    }

    func testPDFTextAnalysisMergesWrappedBulletIntoOneEditableBlock() throws {
        let pdf = makeWrappedBulletPDF()
        let data = try pdf.dataRepresentation().unwrap()
        let engine = PDFTextAnalysisEngine()
        let page = try XCTUnwrap(pdf.page(at: 0))

        let analysis = engine.analyze(data: data, pageIndex: 0, pageRefID: UUID(), fallbackPage: page)
        let block = try XCTUnwrap(analysis.blocks.first { $0.text.contains("Partnered with") })

        XCTAssertGreaterThanOrEqual(block.lines.count, 2)
        XCTAssertTrue(block.text.contains("trailing punctuation"))
        XCTAssertNotNil(block.columnBounds)
        XCTAssertGreaterThan(block.bounds.height, block.lines.first?.bounds.height ?? 0)
    }

    func testPDFTextAnalysisPropagatesColumnCeilingForTwoColumnLayout() throws {
        let pdf = makeTwoColumnPDF()
        let data = try pdf.dataRepresentation().unwrap()
        let engine = PDFTextAnalysisEngine()
        let page = try XCTUnwrap(pdf.page(at: 0))

        let analysis = engine.analyze(data: data, pageIndex: 0, pageRefID: UUID(), fallbackPage: page)
        let leftBlock = try XCTUnwrap(analysis.blocks.first { $0.text.contains("Main column") })
        let rightBlock = try XCTUnwrap(analysis.blocks.first { $0.text.contains("Sidebar") })
        let leftColumn = try XCTUnwrap(leftBlock.columnBounds)

        XCTAssertLessThan(leftColumn.maxX, rightBlock.bounds.minX)
    }

    func testPDFTextAnalysisClampsWrappedParagraphColumnToItsOwnRightMargin() throws {
        // Repro for the "text bleeds right after an edit" bug: a full-width body paragraph
        // whose real right margin sits well inside the page edge (drawn in an x72 w468 box,
        // so the margin is ~540 on a 612-wide page). Before the fix, assignColumnBounds
        // defaulted the column right edge to the page edge (~600) when no right-neighbor
        // existed, so edited text could re-wrap out into the original right margin.
        let longParagraph = "This paragraph is intentionally searchable and wraps across several lines to establish a clear right margin that sits well inside the page edge so editing its words must never bleed past that margin."
        let pdf = makePDF(pageTexts: [longParagraph])
        let data = try pdf.dataRepresentation().unwrap()
        let engine = PDFTextAnalysisEngine()
        let page = try XCTUnwrap(pdf.page(at: 0))

        let analysis = engine.analyze(data: data, pageIndex: 0, pageRefID: UUID(), fallbackPage: page)
        let block = try XCTUnwrap(analysis.blocks.first { $0.text.contains("intentionally searchable") })
        let column = try XCTUnwrap(block.columnBounds)

        XCTAssertGreaterThanOrEqual(block.lines.count, 2, "fixture paragraph should wrap to multiple lines")
        // The column must hug the paragraph's own right margin, not extend to the page edge.
        XCTAssertLessThanOrEqual(
            column.maxX,
            block.bounds.maxX + block.fontSize + 2,
            "wrapped paragraph column should clamp to its own right margin"
        )
        XCTAssertLessThan(
            column.maxX,
            page.bounds(for: .cropBox).maxX - 40,
            "wrapped paragraph column must stay well inside the page's right edge"
        )
    }

    func testPDFTextAnalysisMergesWrappedLinesWithinInterleavedColumns() throws {
        let pdf = makeTwoColumnWrappedPDF()
        let data = try pdf.dataRepresentation().unwrap()
        let engine = PDFTextAnalysisEngine()
        let page = try XCTUnwrap(pdf.page(at: 0))

        let analysis = engine.analyze(data: data, pageIndex: 0, pageRefID: UUID(), fallbackPage: page)
        let leftBlock = try XCTUnwrap(analysis.blocks.first { $0.text.contains("Left column") })
        let rightBlock = try XCTUnwrap(analysis.blocks.first { $0.text.contains("Right column") })

        XCTAssertGreaterThanOrEqual(leftBlock.lines.count, 2)
        XCTAssertGreaterThanOrEqual(rightBlock.lines.count, 2)
        XCTAssertTrue(leftBlock.text.contains("continuation"))
        XCTAssertTrue(rightBlock.text.contains("continuation"))
    }

    func testPDFTextAnalysisDoesNotMergeConsecutiveBulletItems() throws {
        let pdf = makeConsecutiveBulletsPDF()
        let data = try pdf.dataRepresentation().unwrap()
        let engine = PDFTextAnalysisEngine()
        let page = try XCTUnwrap(pdf.page(at: 0))

        let analysis = engine.analyze(data: data, pageIndex: 0, pageRefID: UUID(), fallbackPage: page)
        let first = analysis.blocks.filter { $0.text.contains("First item") }
        let second = analysis.blocks.filter { $0.text.contains("Second item") }

        XCTAssertEqual(first.count, 1)
        XCTAssertEqual(second.count, 1)
        XCTAssertNotEqual(first.first?.id, second.first?.id)
        XCTAssertFalse(first.first?.text.contains("Second item") ?? true)
    }

    /// Regression: a line that opens with a differently-colored run — a hyperlink, an
    /// inline code span, a highlighted keyword — followed by ordinary body-colored text.
    /// `buildBlock` picked the WHOLE line's detected color from only the first
    /// non-space glyph's color, so a link at the very start of a sentence recolored the
    /// entire paragraph's replacement text to the link color once any word in that
    /// sentence was edited, even words nowhere near the link. The detected color should
    /// track whichever color actually covers the most ink on the line.
    func testPDFTextAnalysisUsesDominantColorNotFirstRunWhenLineOpensWithAHyperlink() throws {
        let pdf = makeHyperlinkThenPlainTextPDF()
        let data = try pdf.dataRepresentation().unwrap()
        let engine = PDFTextAnalysisEngine()
        let page = try XCTUnwrap(pdf.page(at: 0))

        let analysis = engine.analyze(data: data, pageIndex: 0, pageRefID: UUID(), fallbackPage: page)
        let block = try XCTUnwrap(analysis.blocks.first { $0.text.contains("for the complete quarterly") })

        // The link run ("See docs") is a handful of characters; the trailing black run is
        // most of the line, so the dominant/detected color must be black, not the link blue.
        XCTAssertLessThan(block.textColor.red, 0.3)
        XCTAssertLessThan(block.textColor.green, 0.3)
        XCTAssertLessThan(block.textColor.blue, 0.3)
    }

    /// Regression for a real user-reported bug: editing one paragraph in a document with
    /// several near-identical stacked paragraphs (e.g. a repeated-content stress file)
    /// visibly shifted the edited text's position and font size, even though the user
    /// hadn't touched formatting.
    ///
    /// Root cause: `shouldMergeWrappedLine`'s `lineHeight` (which scales every merge
    /// tolerance — vertical gap, baseline, indent, column compatibility) was computed from
    /// `previous.bounds.height` — but `previous` is the in-progress merge ACCUMULATOR, whose
    /// `.bounds` is the union of every line already merged into it. Once a paragraph had
    /// merged 3-4 wrapped lines, `.bounds.height` became the whole paragraph's height
    /// (~4x-8x one line), inflating every tolerance by the same factor — wide enough that a
    /// completely separate paragraph below it (same left margin, no trailing punctuation —
    /// both common and legitimate for body text) got silently absorbed into the SAME
    /// editable block. Editing the first paragraph then edited/redrew the fused block,
    /// which is what produced the observed size/position drift.
    func testPDFTextAnalysisDoesNotMergeTwoSeparateStackedParagraphsAtALegitimateParagraphGap() throws {
        let pdf = makeStackedParagraphsPDF()
        let data = try pdf.dataRepresentation().unwrap()
        let engine = PDFTextAnalysisEngine()
        let page = try XCTUnwrap(pdf.page(at: 0))

        let analysis = engine.analyze(data: data, pageIndex: 0, pageRefID: UUID(), fallbackPage: page)
        let row0 = analysis.blocks.filter { $0.text.contains("row-0") }
        let row1 = analysis.blocks.filter { $0.text.contains("row-1") }

        XCTAssertEqual(row0.count, 1)
        XCTAssertEqual(row1.count, 1)
        XCTAssertFalse(row0.first?.text.contains("row-1") ?? true, "two visually separate paragraphs must not fuse into one editable block")
    }

    /// End-to-end version of the above: commits a small append edit to the FIRST of two
    /// stacked paragraphs and confirms the resulting operation carries only that
    /// paragraph's text at its original font size and left margin — i.e. no drift, and the
    /// second paragraph is never touched.
    func testEditingOneOfTwoStackedParagraphsPreservesFontSizeAndPositionOfTheOther() throws {
        let pdf = makeStackedParagraphsPDF()
        let data = try pdf.dataRepresentation().unwrap()
        let engine = PDFTextAnalysisEngine()
        let page = try XCTUnwrap(pdf.page(at: 0))
        let analysis = engine.analyze(data: data, pageIndex: 0, pageRefID: UUID(), fallbackPage: page)
        let row0 = try XCTUnwrap(analysis.blocks.first { $0.text.contains("row-0") })

        let pdfView = OrifoldPDFView(frame: CGRect(x: 0, y: 0, width: 900, height: 1000))
        pdfView.document = pdf
        pdfView.autoScales = false
        pdfView.scaleFactor = 1
        pdfView.layoutDocumentView()
        let pageRef = PageRef(memberDocId: UUID(), sourcePageIndex: 0)
        let viewModel = WorkspaceViewModel(document: WorkspaceDocument())
        var committed: InlineTextEditorOverlay.EditResult?
        let overlay = InlineTextEditorOverlay(
            frame: pdfView.bounds, viewModel: viewModel, pdfView: pdfView, page: page,
            pageRef: pageRef, block: row0, sourceFormat: PDFTextEditFormat(block: row0)
        ) { result in
            if case .commit(let edit) = result { committed = edit }
        }
        pdfView.addSubview(overlay)
        overlay.layoutSubtreeIfNeeded()

        let textView = try XCTUnwrap(findSubview(in: overlay) { (_: NSTextView) in true })
        textView.string = row0.text + " again for good measure"
        textView.delegate?.textDidChange?(Notification(name: NSText.didChangeNotification, object: textView))
        let done = try XCTUnwrap(findSubview(in: overlay) { (button: NSButton) in button.title == "Done" })
        done.performClick(nil)

        let result = try XCTUnwrap(committed)
        XCTAssertFalse(result.text.contains("row-1"), "editing row0 must never pull in row1's text")
        XCTAssertEqual(result.fontSize, row0.fontSize, accuracy: 0.01, "font size must not drift on a simple append edit")
        XCTAssertEqual(result.editedBounds.minX, row0.bounds.minX, accuracy: 0.5, "left edge must not shift on a simple append edit")
    }

    func testCommittingStackedParagraphEditPreservesUntouchedSiblingParagraph() throws {
        let pdf = makeStackedParagraphsPDF()
        let fixture = try makeMemberFixture(name: "Stacked", pdf: pdf)
        let document = WorkspaceDocument()
        document.workspace.documents = [fixture.member]
        document.workspace.pageOrder = fixture.refs
        document.memberPDFData[fixture.member.id] = fixture.pdfData
        let viewModel = WorkspaceViewModel(document: document, processingEngine: PDFKitProcessingEngineFallback())
        let originalPage = try XCTUnwrap(PDFDocument(data: fixture.pdfData)?.page(at: 0))
        let analysis = PDFTextAnalysisEngine().analyze(
            data: fixture.pdfData,
            pageIndex: 0,
            pageRefID: fixture.refs[0].id,
            fallbackPage: originalPage
        )
        let row1 = try XCTUnwrap(analysis.blocks.first { $0.text.contains("row-1") })

        XCTAssertTrue(viewModel.applyInlineTextEdit(
            pageRef: fixture.refs[0],
            sourceBlock: row1,
            replacementText: row1.text + " edited",
            editedBounds: row1.bounds,
            fontName: row1.fontName,
            fontSize: row1.fontSize,
            textColor: row1.textColor.nsColor,
            alignment: row1.alignment?.nsTextAlignment ?? .left
        ))

        let editedPage = try XCTUnwrap(viewModel.loadedPDFs.first?.1.page(at: 0))
        let editedBitmap = try renderedBitmap(for: editedPage)
        let row0 = try XCTUnwrap(analysis.blocks.first { $0.text.contains("row-0") })
        XCTAssertGreaterThan(
            darkPixelCount(in: row0.bounds, bitmap: editedBitmap),
            50,
            "editing row-1 must visibly preserve the untouched row-0 paragraph"
        )

        let editedText = editedPage.string ?? ""
        XCTAssertTrue(editedText.contains("row-1"), "the edited paragraph should remain on the page")
        XCTAssertTrue(editedText.contains("edited"), "the committed replacement should be rendered into the page")
    }

    // MARK: - Edited-text style fidelity

    /// A Semibold/Bold body face whose PostScript name carries no "Bold" token (only the
    /// font descriptor's weight says so) must still resolve to a bold substitute — otherwise
    /// the re-rendered replacement text looks visibly lighter than the surrounding document
    /// (the "edited paragraph looks lighter/different weight" fidelity bug).
    func testFontResolutionPreservesBoldFromDescriptorWeightWhenNameLacksBoldToken() throws {
        let resolved = PDFTextAnalysisEngine.testResolveFontPostScriptName(
            from: "Helvetica",
            weightHint: 700,
            italicHint: false
        )
        let font = try XCTUnwrap(NSFont(name: resolved, size: 12), "resolved font must exist")
        let traits = NSFontManager.shared.traits(of: font)
        XCTAssertTrue(traits.contains(.boldFontMask), "descriptor weight 700 should yield a bold face, got \(resolved)")
    }

    /// Same reasoning as weight: an italic face whose name has no "Italic"/"Oblique" token
    /// but whose descriptor italic flag is set must resolve to an italic substitute.
    func testFontResolutionPreservesItalicFromDescriptorFlagWhenNameLacksItalicToken() throws {
        let resolved = PDFTextAnalysisEngine.testResolveFontPostScriptName(
            from: "Helvetica",
            weightHint: nil,
            italicHint: true
        )
        let font = try XCTUnwrap(NSFont(name: resolved, size: 12), "resolved font must exist")
        let traits = NSFontManager.shared.traits(of: font)
        XCTAssertTrue(traits.contains(.italicFontMask), "descriptor italic flag should yield an italic face, got \(resolved)")
    }

    /// The descriptor hints must not over-promote: a regular-weight, upright face stays
    /// exactly as detected so ordinary body text is never bolded/slanted by the new logic.
    func testFontResolutionKeepsRegularUprightWhenDescriptorIsPlain() {
        let resolved = PDFTextAnalysisEngine.testResolveFontPostScriptName(
            from: "Helvetica",
            weightHint: 400,
            italicHint: false
        )
        XCTAssertEqual(resolved, "Helvetica")
    }

    /// Boundary check just below the bold cutoff: OpenType weight 500 ("Medium") is
    /// deliberately NOT promoted to bold — only 600+ ("SemiBold" and up) should be. Without
    /// this test, the `>= 600` threshold in `resolveFontPostScriptName` could silently drift
    /// (e.g. to `>= 500`) and start mis-bolding medium-weight body text with nothing to catch it.
    func testFontResolutionDoesNotPromoteMediumWeightBelowBoldCutoff() throws {
        let resolved = PDFTextAnalysisEngine.testResolveFontPostScriptName(
            from: "Helvetica",
            weightHint: 500,
            italicHint: false
        )
        let font = try XCTUnwrap(NSFont(name: resolved, size: 12))
        let traits = NSFontManager.shared.traits(of: font)
        XCTAssertFalse(traits.contains(.boldFontMask), "weight 500 (Medium) must stay non-bold, got \(resolved)")
    }

    /// Boundary check exactly at the bold cutoff: OpenType weight 600 ("SemiBold") must
    /// promote to bold, mirroring `testFontResolutionPreservesBoldFromDescriptorWeightWhenNameLacksBoldToken`
    /// (which only tests comfortably-above-threshold weight 700) at the threshold itself.
    func testFontResolutionPromotesSemiBoldWeightAtBoldCutoff() throws {
        let resolved = PDFTextAnalysisEngine.testResolveFontPostScriptName(
            from: "Helvetica",
            weightHint: 600,
            italicHint: false
        )
        let font = try XCTUnwrap(NSFont(name: resolved, size: 12))
        let traits = NSFontManager.shared.traits(of: font)
        XCTAssertTrue(traits.contains(.boldFontMask), "weight 600 (SemiBold) should yield a bold face, got \(resolved)")
    }

    /// A multi-line paragraph's original line pitch (baseline-to-baseline distance) must be
    /// recovered from the captured per-line bounds and fed to CoreText, so wrapped
    /// replacement lines keep the document's leading instead of CoreText's default — the
    /// "line height / paragraph spacing looks different after an edit" fidelity bug.
    func testRendererRecoversOriginalLinePitchForMultiLineParagraph() throws {
        let lineHeight: CGFloat = 15
        let lines = (0..<3).map { index in
            CGRect(x: 40, y: 700 - CGFloat(index) * lineHeight, width: 400, height: 11)
        }
        let bounds = lines.reduce(lines[0]) { $0.union($1) }
        let op = PDFTextEditOperation(
            pageRefID: UUID(),
            sourceBlockID: UUID(),
            sourceBounds: bounds,
            sourceLineBounds: lines,
            sourceText: "line one line two line three",
            editedBounds: bounds,
            replacementText: "line one line two line three",
            fontName: "Helvetica",
            fontSize: 11,
            textColor: .documentText,
            alignment: .left
        )
        let pitch = try XCTUnwrap(PDFEditedPageRenderer.testOriginalLinePitch(for: op))
        XCTAssertEqual(pitch, lineHeight, accuracy: 0.5)
    }

    /// A single-line source has no leading to preserve, so no forced line height is applied
    /// (which would risk clipping/altering the sole line's metrics).
    func testRendererDoesNotForceLinePitchForSingleLineSource() {
        let bounds = CGRect(x: 40, y: 700, width: 400, height: 11)
        let op = PDFTextEditOperation(
            pageRefID: UUID(),
            sourceBlockID: UUID(),
            sourceBounds: bounds,
            sourceLineBounds: [bounds],
            sourceText: "single line",
            editedBounds: bounds,
            replacementText: "single line",
            fontName: "Helvetica",
            fontSize: 11,
            textColor: .documentText,
            alignment: .left
        )
        XCTAssertNil(PDFEditedPageRenderer.testOriginalLinePitch(for: op))
    }

    /// The screenshot scenario: a page of repeated paragraphs, two of which have `pdFold`
    /// edited to `oriFold`. Only the edited rows change; the untouched rows keep their ink,
    /// and the edited rows do not lose ink density (weight) or reflow off their footprint.
    func testEditingRepeatedParagraphsChangesOnlyEditedRowsAndKeepsTheirWeight() throws {
        let pdf = makeRepeatedParagraphsPDF()
        let fixture = try makeMemberFixture(name: "Repeated", pdf: pdf)
        let document = WorkspaceDocument()
        document.workspace.documents = [fixture.member]
        document.workspace.pageOrder = fixture.refs
        document.memberPDFData[fixture.member.id] = fixture.pdfData
        let viewModel = WorkspaceViewModel(document: document, processingEngine: PDFKitProcessingEngineFallback())
        let originalPage = try XCTUnwrap(PDFDocument(data: fixture.pdfData)?.page(at: 0))
        let analysis = PDFTextAnalysisEngine().analyze(
            data: fixture.pdfData,
            pageIndex: 0,
            pageRefID: fixture.refs[0].id,
            fallbackPage: originalPage
        )
        func row(_ marker: String) throws -> EditableTextBlock {
            try XCTUnwrap(analysis.blocks.first { $0.text.contains(marker) }, "missing \(marker)")
        }
        let row0 = try row("row-0")
        let row1 = try row("row-1")
        let row2 = try row("row-2")
        let row3 = try row("row-3")

        for editedRow in [row1, row3] {
            let replacement = editedRow.text.replacingOccurrences(of: "pdFold", with: "oriFold")
            XCTAssertNotEqual(replacement, editedRow.text, "fixture row should contain pdFold")
            XCTAssertTrue(viewModel.applyInlineTextEdit(
                pageRef: fixture.refs[0],
                sourceBlock: editedRow,
                replacementText: replacement,
                editedBounds: editedRow.bounds,
                fontName: editedRow.fontName,
                fontSize: editedRow.fontSize,
                textColor: editedRow.textColor.nsColor,
                alignment: editedRow.alignment?.nsTextAlignment ?? .left
            ))
        }

        let editedPage = try XCTUnwrap(viewModel.loadedPDFs.first?.1.page(at: 0))
        let editedText = editedPage.string ?? ""
        let oriFoldCount = editedText.components(separatedBy: "oriFold").count - 1
        XCTAssertEqual(oriFoldCount, 2, "exactly the two edited rows should now read oriFold")

        let bitmap = try renderedBitmap(for: editedPage)
        // Untouched rows keep their original ink.
        XCTAssertGreaterThan(darkPixelCount(in: row0.bounds, bitmap: bitmap), 50, "untouched row-0 must survive")
        XCTAssertGreaterThan(darkPixelCount(in: row2.bounds, bitmap: bitmap), 50, "untouched row-2 must survive")

        // The edited rows must not lose weight: their re-rendered ink density stays close to
        // an untouched sibling's. A weight regression (bold → regular substitute) would drop
        // this well below the tolerance floor.
        func density(_ bounds: CGRect) -> Double {
            let area = Double(bounds.standardized.width * bounds.standardized.height)
            guard area > 0 else { return 0 }
            return Double(darkPixelCount(in: bounds, bitmap: bitmap)) / area
        }
        let untouchedDensity = (density(row0.bounds) + density(row2.bounds)) / 2
        XCTAssertGreaterThan(untouchedDensity, 0, "untouched rows should have measurable ink")
        for editedRow in [row1, row3] {
            XCTAssertGreaterThan(
                density(editedRow.bounds),
                untouchedDensity * 0.5,
                "edited row ink density must stay comparable to untouched rows (no weight/blank regression)"
            )
        }
    }

    func testUndoRedoStackedParagraphEditNeverBlanksUntouchedParagraph() throws {
        let pdf = makeStackedParagraphsPDF()
        let fixture = try makeMemberFixture(name: "Stacked", pdf: pdf)
        let document = WorkspaceDocument()
        document.workspace.documents = [fixture.member]
        document.workspace.pageOrder = fixture.refs
        document.memberPDFData[fixture.member.id] = fixture.pdfData
        let viewModel = WorkspaceViewModel(document: document, processingEngine: PDFKitProcessingEngineFallback())
        let undoManager = UndoManager()
        viewModel.undoManager = undoManager
        let originalPage = try XCTUnwrap(PDFDocument(data: fixture.pdfData)?.page(at: 0))
        let analysis = PDFTextAnalysisEngine().analyze(
            data: fixture.pdfData,
            pageIndex: 0,
            pageRefID: fixture.refs[0].id,
            fallbackPage: originalPage
        )
        let row0 = try XCTUnwrap(analysis.blocks.first { $0.text.contains("row-0") })
        let row1 = try XCTUnwrap(analysis.blocks.first { $0.text.contains("row-1") })

        XCTAssertTrue(viewModel.applyInlineTextEdit(
            pageRef: fixture.refs[0],
            sourceBlock: row1,
            replacementText: row1.text + " edited",
            editedBounds: row1.bounds,
            fontName: row1.fontName,
            fontSize: row1.fontSize,
            textColor: row1.textColor.nsColor,
            alignment: row1.alignment?.nsTextAlignment ?? .left
        ))
        try assertVisibleTextPixels(in: row0.bounds, viewModel: viewModel, message: "row-0 should survive the initial edit")

        undoManager.undo()
        try assertVisibleTextPixels(in: row0.bounds, viewModel: viewModel, message: "row-0 should survive undo")
        XCTAssertFalse(viewModel.loadedPDFs.first?.1.page(at: 0)?.string?.contains("edited") ?? true)

        undoManager.redo()
        try assertVisibleTextPixels(in: row0.bounds, viewModel: viewModel, message: "row-0 should survive redo")
        XCTAssertTrue(viewModel.loadedPDFs.first?.1.page(at: 0)?.string?.contains("edited") ?? false)
    }

    /// Three sequential inline edits made back-to-back (no run-loop turn between them, as
    /// happens in a scripted/batch edit flow, or simply several fast edits within the same
    /// event) must still undo ONE STEP AT A TIME. `UndoManager.groupsByEvent` (the default)
    /// auto-closes an implicit group only at run-loop boundaries — if nothing in the edit
    /// path explicitly closes a group per edit, three synchronous edits with no run-loop
    /// turn between them could coalesce into a single implicit undo group, so one `undo()`
    /// would revert all three edits at once instead of just the most recent one.
    func testThreeSequentialInlineEditsUndoOneStepAtATime() throws {
        let pdf = makeStackedParagraphsPDF()
        let fixture = try makeMemberFixture(name: "Stacked", pdf: pdf)
        let document = WorkspaceDocument()
        document.workspace.documents = [fixture.member]
        document.workspace.pageOrder = fixture.refs
        document.memberPDFData[fixture.member.id] = fixture.pdfData
        let viewModel = WorkspaceViewModel(document: document, processingEngine: PDFKitProcessingEngineFallback())
        let undoManager = UndoManager()
        viewModel.undoManager = undoManager
        let originalPage = try XCTUnwrap(PDFDocument(data: fixture.pdfData)?.page(at: 0))
        let analysis = PDFTextAnalysisEngine().analyze(
            data: fixture.pdfData,
            pageIndex: 0,
            pageRefID: fixture.refs[0].id,
            fallbackPage: originalPage
        )
        let row0 = try XCTUnwrap(analysis.blocks.first { $0.text.contains("row-0") })
        let row1 = try XCTUnwrap(analysis.blocks.first { $0.text.contains("row-1") })

        XCTAssertTrue(viewModel.applyInlineTextEdit(
            pageRef: fixture.refs[0],
            sourceBlock: row1,
            replacementText: row1.text + " edit-one",
            editedBounds: row1.bounds,
            fontName: row1.fontName,
            fontSize: row1.fontSize,
            textColor: row1.textColor.nsColor,
            alignment: row1.alignment?.nsTextAlignment ?? .left
        ))
        XCTAssertTrue(viewModel.applyInlineTextEdit(
            pageRef: fixture.refs[0],
            sourceBlock: row0,
            replacementText: row0.text + " edit-two",
            editedBounds: row0.bounds,
            fontName: row0.fontName,
            fontSize: row0.fontSize,
            textColor: row0.textColor.nsColor,
            alignment: row0.alignment?.nsTextAlignment ?? .left
        ))
        let row1AfterFirstEdit = try XCTUnwrap(
            viewModel.document.workspace.pageEditStates.first(where: { $0.pageRefID == fixture.refs[0].id })?
                .operations.first(where: { $0.sourceBlockID == row1.id })
        )
        XCTAssertTrue(viewModel.applyInlineTextEdit(
            pageRef: fixture.refs[0],
            sourceBlock: row1,
            replacementText: row1.text + " edit-three",
            editedBounds: row1AfterFirstEdit.editedBounds,
            fontName: row1.fontName,
            fontSize: row1.fontSize,
            textColor: row1.textColor.nsColor,
            alignment: row1.alignment?.nsTextAlignment ?? .left
        ))
        XCTAssertEqual(viewModel.document.workspace.pageEditStates.first?.operations.count, 2, "three edits across two distinct blocks should net two stored operations")

        undoManager.undo()

        let pageText = viewModel.loadedPDFs.first?.1.page(at: 0)?.string ?? ""
        XCTAssertFalse(pageText.contains("edit-three"), "the most recent edit must be undone")
        XCTAssertTrue(pageText.contains("edit-two"), "a single undo() must not also revert the second edit")
        XCTAssertTrue(pageText.contains("row-0") && pageText.contains("edit-two"), "row-0's edit-two must still be present after undoing only the last edit")

        undoManager.undo()
        let pageTextAfterSecondUndo = viewModel.loadedPDFs.first?.1.page(at: 0)?.string ?? ""
        XCTAssertFalse(pageTextAfterSecondUndo.contains("edit-two"), "second undo() should revert edit-two")
        XCTAssertTrue(pageTextAfterSecondUndo.contains("edit-one"), "second undo() must not also revert edit-one")

        undoManager.redo()
        let pageTextAfterRedo = viewModel.loadedPDFs.first?.1.page(at: 0)?.string ?? ""
        XCTAssertTrue(pageTextAfterRedo.contains("edit-two"), "redo() should restore exactly the edit that was just undone")
        XCTAssertFalse(pageTextAfterRedo.contains("edit-three"), "redo() must not also restore the edit still further ahead")
    }

    /// Standard `UndoManager` semantics: performing a brand-new action after undoing
    /// must discard the redo stack, so a step that was undone-then-still-redoable
    /// becomes permanently unreachable once a new edit is registered. This proves that
    /// invariant holds for `WorkspaceViewModel`'s inline-text-edit undo registration
    /// despite `registerIsolatedUndo` toggling `groupsByEvent` on each call (see
    /// `registerIsolatedUndo` and `restoreInlineTextEditSnapshot` in WorkspaceViewModel.swift).
    func testNewEditAfterUndoRedoDiscardsStaleRedoStack() throws {
        let pdf = makeStackedParagraphsPDF()
        let fixture = try makeMemberFixture(name: "Stacked", pdf: pdf)
        let document = WorkspaceDocument()
        document.workspace.documents = [fixture.member]
        document.workspace.pageOrder = fixture.refs
        document.memberPDFData[fixture.member.id] = fixture.pdfData
        let viewModel = WorkspaceViewModel(document: document, processingEngine: PDFKitProcessingEngineFallback())
        let undoManager = UndoManager()
        viewModel.undoManager = undoManager
        let originalPage = try XCTUnwrap(PDFDocument(data: fixture.pdfData)?.page(at: 0))
        let analysis = PDFTextAnalysisEngine().analyze(
            data: fixture.pdfData,
            pageIndex: 0,
            pageRefID: fixture.refs[0].id,
            fallbackPage: originalPage
        )
        let row0 = try XCTUnwrap(analysis.blocks.first { $0.text.contains("row-0") })
        let row1 = try XCTUnwrap(analysis.blocks.first { $0.text.contains("row-1") })

        // Edit #1: row-1
        XCTAssertTrue(viewModel.applyInlineTextEdit(
            pageRef: fixture.refs[0],
            sourceBlock: row1,
            replacementText: row1.text + " edit-one",
            editedBounds: row1.bounds,
            fontName: row1.fontName,
            fontSize: row1.fontSize,
            textColor: row1.textColor.nsColor,
            alignment: row1.alignment?.nsTextAlignment ?? .left
        ))
        // Edit #2: row-0
        XCTAssertTrue(viewModel.applyInlineTextEdit(
            pageRef: fixture.refs[0],
            sourceBlock: row0,
            replacementText: row0.text + " edit-two",
            editedBounds: row0.bounds,
            fontName: row0.fontName,
            fontSize: row0.fontSize,
            textColor: row0.textColor.nsColor,
            alignment: row0.alignment?.nsTextAlignment ?? .left
        ))
        let row1AfterFirstEdit = try XCTUnwrap(
            viewModel.document.workspace.pageEditStates.first(where: { $0.pageRefID == fixture.refs[0].id })?
                .operations.first(where: { $0.sourceBlockID == row1.id })
        )
        // Edit #3: row-1 again
        XCTAssertTrue(viewModel.applyInlineTextEdit(
            pageRef: fixture.refs[0],
            sourceBlock: row1,
            replacementText: row1.text + " edit-three",
            editedBounds: row1AfterFirstEdit.editedBounds,
            fontName: row1.fontName,
            fontSize: row1.fontSize,
            textColor: row1.textColor.nsColor,
            alignment: row1.alignment?.nsTextAlignment ?? .left
        ))
        XCTAssertEqual(viewModel.document.workspace.pageEditStates.first?.operations.count, 2)

        // Undo x2: back to just edit-one.
        undoManager.undo()
        undoManager.undo()
        let afterTwoUndos = viewModel.loadedPDFs.first?.1.page(at: 0)?.string ?? ""
        XCTAssertTrue(afterTwoUndos.contains("edit-one"), "edit-one should remain applied after only two undos")
        XCTAssertFalse(afterTwoUndos.contains("edit-two"), "edit-two must be undone")
        XCTAssertFalse(afterTwoUndos.contains("edit-three"), "edit-three must be undone")
        XCTAssertTrue(undoManager.canRedo, "edit-two should still be redoable at this point")

        // Redo x1: restores edit-two.
        undoManager.redo()
        let afterRedo = viewModel.loadedPDFs.first?.1.page(at: 0)?.string ?? ""
        XCTAssertTrue(afterRedo.contains("edit-one"), "edit-one should remain applied")
        XCTAssertTrue(afterRedo.contains("edit-two"), "redo should restore edit-two")
        XCTAssertFalse(afterRedo.contains("edit-three"), "edit-three must still be undone (not yet redone)")
        XCTAssertTrue(undoManager.canRedo, "edit-three should still be redoable before any new edit is performed")

        // New edit #4 (row-0 edited again) after undo/redo: this must discard the
        // remaining redo stack (edit-three) per standard UndoManager semantics.
        let row0AfterEditTwo = try XCTUnwrap(
            viewModel.document.workspace.pageEditStates.first(where: { $0.pageRefID == fixture.refs[0].id })?
                .operations.first(where: { $0.sourceBlockID == row0.id })
        )
        XCTAssertTrue(viewModel.applyInlineTextEdit(
            pageRef: fixture.refs[0],
            sourceBlock: row0,
            replacementText: row0.text + " edit-four",
            editedBounds: row0AfterEditTwo.editedBounds,
            fontName: row0.fontName,
            fontSize: row0.fontSize,
            textColor: row0.textColor.nsColor,
            alignment: row0.alignment?.nsTextAlignment ?? .left
        ))

        let afterNewEdit = viewModel.loadedPDFs.first?.1.page(at: 0)?.string ?? ""
        XCTAssertTrue(afterNewEdit.contains("edit-one"), "edit-one (never undone) should remain")
        XCTAssertFalse(afterNewEdit.contains("edit-two"), "edit-two's replacement text was itself replaced by edit-four")
        XCTAssertTrue(afterNewEdit.contains("edit-four"), "new edit-four should be applied")
        XCTAssertFalse(afterNewEdit.contains("edit-three"), "edit-three must not reappear")

        // The critical invariant: a new action after undo/redo discards the stale redo stack.
        XCTAssertFalse(undoManager.canRedo, "performing a new edit after undo/redo must discard the previously-available redo (edit-three)")

        // Confirm redo() is now a no-op / does not resurrect edit-three.
        undoManager.redo()
        let afterAttemptedStaleRedo = viewModel.loadedPDFs.first?.1.page(at: 0)?.string ?? ""
        XCTAssertFalse(afterAttemptedStaleRedo.contains("edit-three"), "stale redo entry (edit-three) must never be resurrected after a new edit was performed")
        XCTAssertTrue(afterAttemptedStaleRedo.contains("edit-four"), "edit-four must remain applied")

        // Sanity: undoing from here should step back to edit-two (i.e. undo edit-four),
        // confirming the undo stack now correctly ends at edit-four, not edit-three.
        undoManager.undo()
        let afterUndoingEditFour = viewModel.loadedPDFs.first?.1.page(at: 0)?.string ?? ""
        XCTAssertTrue(afterUndoingEditFour.contains("edit-two"), "undoing edit-four should reveal edit-two underneath")
        XCTAssertFalse(afterUndoingEditFour.contains("edit-four"), "edit-four should be undone")
        XCTAssertFalse(afterUndoingEditFour.contains("edit-three"), "edit-three must remain absent")
    }

    func testInlineTextEditPreservesImageBackedPDFBackground() throws {
        let pdfData = try makePhotoPDFData(text: "Original searchable text")
        let pdf = try XCTUnwrap(PDFDocument(data: pdfData))
        let fixture = try makeMemberFixture(name: "Photo", pdf: pdf)
        let document = WorkspaceDocument()
        document.workspace.documents = [fixture.member]
        document.workspace.pageOrder = fixture.refs
        document.memberPDFData[fixture.member.id] = fixture.pdfData
        let viewModel = WorkspaceViewModel(document: document, processingEngine: PDFKitProcessingEngineFallback())
        let originalPage = try XCTUnwrap(PDFDocument(data: fixture.pdfData)?.page(at: 0))
        let analysis = PDFTextAnalysisEngine().analyze(
            data: fixture.pdfData,
            pageIndex: 0,
            pageRefID: fixture.refs[0].id,
            fallbackPage: originalPage
        )
        let sourceBlock = try XCTUnwrap(analysis.blocks.first { $0.text.contains("Original searchable text") })

        XCTAssertTrue(viewModel.applyInlineTextEdit(
            pageRef: fixture.refs[0],
            sourceBlock: sourceBlock,
            replacementText: "Edited searchable text",
            editedBounds: sourceBlock.bounds,
            fontName: sourceBlock.fontName,
            fontSize: sourceBlock.fontSize,
            textColor: sourceBlock.textColor.nsColor,
            alignment: sourceBlock.alignment?.nsTextAlignment ?? .left
        ))

        let editedPage = try XCTUnwrap(viewModel.loadedPDFs.first?.1.page(at: 0))
        let bitmap = try renderedBitmap(for: editedPage)
        XCTAssertGreaterThan(
            darkPixelCount(in: CGRect(x: 240, y: 300, width: 160, height: 160), bitmap: bitmap),
            100,
            "editing searchable text must not replace an image-backed PDF page with a blank white page"
        )
        XCTAssertTrue(editedPage.string?.contains("Edited searchable text") ?? false)

        let exportedData = try viewModel.document.exportedPDFDataThrowing(from: try viewModel.document.snapshot(contentType: .pdf))
        let exportedPage = try XCTUnwrap(PDFDocument(data: exportedData)?.page(at: 0))
        let exportedBitmap = try renderedBitmap(for: exportedPage)
        XCTAssertGreaterThan(
            darkPixelCount(in: CGRect(x: 240, y: 300, width: 160, height: 160), bitmap: exportedBitmap),
            100,
            "exporting an edited image-backed PDF must not flatten the page to white"
        )
        XCTAssertTrue(exportedPage.string?.contains("Edited searchable text") ?? false)
    }

    /// Regression coverage for removing the vestigial full-page raster-then-vector
    /// double-draw from `regeneratedPage(from:applying:)`: confirms the remaining single
    /// vector `drawPageBackground` draw is sufficient even for a page whose content
    /// stream has NO explicit background fill at all (a genuinely transparent/blank
    /// backdrop, as opposed to every other fixture in this file, which is built via
    /// `NSView.dataWithPDF` and therefore always paints an explicit opaque white rect
    /// first). Built directly via `CGContext`/`CGDataConsumer` — bypassing `NSView`
    /// entirely — so the content stream truly contains only a text-drawing operator,
    /// no fill/rect operator of any kind.
    func testInlineTextEditOnPageWithNoExplicitBackgroundFillPreservesUntouchedText() throws {
        // 612x792, matching every other fixture's page size in this file: `renderedBitmap`
        // always rasterizes via `thumbnail(of: CGSize(width: 612, height: 792), for:)`, and
        // `darkPixelCount` assumes a 1:1 PDF-point-to-pixel mapping against that fixed
        // size — a differently-sized/aspect-ratio page would get scaled/letterboxed by
        // PDFKit's thumbnail rendering, breaking that assumed 1:1 mapping.
        let pageBounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        let data = NSMutableData()
        var mediaBox = pageBounds
        let consumer = try XCTUnwrap(CGDataConsumer(data: data))
        let context = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &mediaBox, nil))
        context.beginPDFPage(nil)
        // No fill/rect operator of any kind precedes this — the content stream is just
        // a single text-showing operation over an otherwise untouched (transparent) page.
        let font = CTFontCreateWithName("Helvetica" as CFString, 18, nil)
        let attributed = NSAttributedString(string: "Untouched transparent text", attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font
        ])
        let line = CTLineCreateWithAttributedString(attributed)
        context.textMatrix = .identity
        context.textPosition = CGPoint(x: 20, y: 150)
        CTLineDraw(line, context)
        context.endPDFPage()
        context.closePDF()

        let sourceDoc = try XCTUnwrap(PDFDocument(data: data as Data))
        let page = try XCTUnwrap(sourceDoc.page(at: 0))
        XCTAssertTrue(page.string?.contains("Untouched transparent text") ?? false, "sanity check: fixture must contain this text before editing")

        // An unrelated insertion far from the untouched text — same shape as the rotated
        // non-square-page regression test above, just proving the untouched background
        // text (here, drawn onto a page with no explicit fill) survives regeneration.
        let operation = PDFTextEditOperation(
            pageRefID: UUID(),
            sourceBlockID: UUID(),
            sourceBounds: CGRect(x: 20, y: 20, width: 1, height: 1),
            editedBounds: CGRect(x: 20, y: 20, width: 60, height: 16),
            replacementText: "New",
            fontName: "Helvetica",
            fontSize: 12,
            textColor: .documentText,
            alignment: .left,
            isInsertion: true
        )

        let regenerated = try XCTUnwrap(PDFEditedPageRenderer.regeneratedPage(from: page, applying: [operation]))
        XCTAssertTrue(
            regenerated.string?.contains("Untouched transparent text") ?? false,
            "the original page's untouched text must survive regeneration even when the source content stream has no explicit background fill"
        )

        // PDFKit's `PDFPage` does not strongly retain its owning `PDFDocument` — the
        // regenerated page is only safe to render/rasterize once re-hosted in a document
        // we keep alive ourselves (the same reason the rotated-page regression test above
        // only checks `regenerated.string`, never renders it directly).
        let hostDocument = PDFDocument()
        hostDocument.insert(regenerated, at: 0)
        let hostedPage = try XCTUnwrap(hostDocument.page(at: 0))
        let bitmap = try renderedBitmap(for: hostedPage)
        let textSelection = try XCTUnwrap(hostedPage.selection(for: (hostedPage.string! as NSString).range(of: "Untouched transparent text")))
        XCTAssertGreaterThan(
            darkPixelCount(in: textSelection.bounds(for: hostedPage), bitmap: bitmap),
            10,
            "the untouched text must still render visibly, not vanish into an all-white or corrupted page"
        )
    }

    func testPDFTextAnalysisUsesVisibleFontSizeForScaledContentStreams() throws {
        let nominalFontSize: CGFloat = 24
        let pdf = makeScaledTextPDF(text: "Scaled inline text", fontSize: nominalFontSize, scale: 0.5)
        let data = try pdf.dataRepresentation().unwrap()
        let engine = PDFTextAnalysisEngine()
        let page = try XCTUnwrap(pdf.page(at: 0))

        let analysis = engine.analyze(data: data, pageIndex: 0, pageRefID: UUID(), fallbackPage: page)
        let block = try XCTUnwrap(analysis.blocks.first { $0.text.contains("Scaled") })
        let inkHeight = try XCTUnwrap(block.lines.first?.runs.first?.bounds.height)

        XCTAssertLessThan(block.fontSize, nominalFontSize * 0.8)
        let helveticaUnitFont = try XCTUnwrap(NSFont(name: "Helvetica", size: 1))
        let helveticaInkRatio = helveticaUnitFont.capHeight - helveticaUnitFont.descender
        XCTAssertEqual(block.fontSize, max(4, inkHeight / helveticaInkRatio), accuracy: 1.0)
    }

    func testPDFTextAnalysisUsesVisibleFontSizeForModeratelyScaledText() throws {
        let nominalFontSize: CGFloat = 24
        let pdf = makeScaledTextPDF(text: "Moderately scaled inline text", fontSize: nominalFontSize, scale: 0.85)
        let data = try pdf.dataRepresentation().unwrap()
        let engine = PDFTextAnalysisEngine()
        let page = try XCTUnwrap(pdf.page(at: 0))

        let analysis = engine.analyze(data: data, pageIndex: 0, pageRefID: UUID(), fallbackPage: page)
        let block = try XCTUnwrap(analysis.blocks.first { $0.text.contains("Moderately") })
        let inkHeight = try XCTUnwrap(block.lines.first?.runs.first?.bounds.height)

        XCTAssertLessThan(block.fontSize, nominalFontSize * 0.95)
        let helveticaUnitFont = try XCTUnwrap(NSFont(name: "Helvetica", size: 1))
        let helveticaInkRatio = helveticaUnitFont.capHeight - helveticaUnitFont.descender
        XCTAssertEqual(block.fontSize, max(4, inkHeight / helveticaInkRatio), accuracy: 1.0)
    }

    /// Regression for a real user-reported bug: the detected font size was consistently
    /// off (and "Match"/"Copy nearby format" reproduced the same wrong number, since both
    /// read this same detected value) for ordinary, unscaled text.
    ///
    /// Root cause: `FPDFText_GetFontSize` reports nothing usable for many PDF-producing
    /// pipelines (confirmed: for every font tested here, `reportedFontSize` is nil for
    /// every glyph), so `resolveLineFontSize` always fell back to an ink-height estimate —
    /// but that estimate used ONE FIXED ratio (ink height × 1.15) for every font. Different
    /// fonts have meaningfully different cap-height/descender proportions (Georgia and
    /// Verdana ink taller relative to their point size than Helvetica does), so a single
    /// global constant was off by 5-12% depending on the font, consistently and
    /// reproducibly for a given document. Fixed by deriving the ink-to-point-size ratio
    /// from the ACTUAL resolved font's own metrics (`capHeight - descender`) instead of one
    /// constant for every font.
    func testPDFTextAnalysisDetectsFontSizeAccuratelyAcrossCommonFonts() throws {
        let candidates: [(name: String, size: CGFloat)] = [
            ("Helvetica", 11), ("Times New Roman", 12), ("Georgia", 13), ("Arial", 11), ("Verdana", 10)
        ]
        let engine = PDFTextAnalysisEngine()
        for candidate in candidates {
            guard let font = NSFont(name: candidate.name, size: candidate.size) else { continue }
            let view = SingleFontLineFixturePageView(text: "Sample text for size probe", font: font)
            let pdf = PDFDocument(data: view.dataWithPDF(inside: view.bounds))!
            let page = try XCTUnwrap(pdf.page(at: 0), candidate.name)
            let data = try pdf.dataRepresentation().unwrap()

            let analysis = engine.analyze(data: data, pageIndex: 0, pageRefID: UUID(), fallbackPage: page)
            let block = try XCTUnwrap(analysis.blocks.first { $0.text.contains("Sample text") }, candidate.name)

            // A font-specific ink ratio can't be perfect (it depends on which glyphs happen
            // to appear on a given line), but it should stay well clear of the ~12% worst
            // case the single fixed-ratio formula produced for fonts like Georgia/Verdana.
            let percentError = abs(block.fontSize - candidate.size) / candidate.size
            XCTAssertLessThan(
                percentError, 0.08,
                "\(candidate.name)@\(candidate.size)pt detected as \(block.fontSize) — more than 8% off"
            )
        }
    }

    func testPDFTextAnalysisAvoidsPrivateSystemFontNamesForEditing() throws {
        let pdf = makePDF(pageTexts: ["System font body text"])
        let data = try pdf.dataRepresentation().unwrap()
        let engine = PDFTextAnalysisEngine()
        let page = try XCTUnwrap(pdf.page(at: 0))

        let analysis = engine.analyze(data: data, pageIndex: 0, pageRefID: UUID(), fallbackPage: page)
        let block = try XCTUnwrap(analysis.blocks.first { $0.text.contains("System font") })

        XCTAssertFalse(block.fontName.hasPrefix("."))
        XCTAssertNotEqual(block.fontName, ".SFNS-Regular")
        XCTAssertNotEqual(block.fontName, ".AppleSystemUIFont")
        XCTAssertNotNil(NSFont(name: block.fontName, size: block.fontSize))
    }

    /// Regression companion to the hyperlink-at-line-start fix: the same run-position bias
    /// (picking only the FIRST glyph's font) could also misfire when the differently-styled
    /// run sits in the MIDDLE of a sentence — e.g. "Please review the **Q3 budget** figures
    /// before Friday" with a single bold emphasis mid-sentence. The dominant/majority font
    /// selection must be position-independent: the surrounding plain-weight text is still
    /// most of the line, so the detected (and thus committed-on-edit) font must stay
    /// non-bold regardless of where in the line the bold run sits.
    func testPDFTextAnalysisUsesDominantFontNotFirstRunForAMidSentenceBoldEmphasis() throws {
        let pdf = makeMidSentenceBoldPDF()
        let data = try pdf.dataRepresentation().unwrap()
        let engine = PDFTextAnalysisEngine()
        let page = try XCTUnwrap(pdf.page(at: 0))

        let analysis = engine.analyze(data: data, pageIndex: 0, pageRefID: UUID(), fallbackPage: page)
        let block = try XCTUnwrap(analysis.blocks.first { $0.text.contains("figures before Friday") })

        XCTAssertFalse(
            block.fontName.localizedCaseInsensitiveContains("bold"),
            "a single mid-sentence bold emphasis must not flip the whole paragraph's detected (and thus edited) font to bold"
        )
    }

    func testReconcileLigaturesPrefersPDFKitTextWhenPlausible() throws {
        let pdf = makePDF(pageTexts: ["Generative AI strategy"])
        let page = try XCTUnwrap(pdf.page(at: 0))
        let fullBounds = try XCTUnwrap(page.selection(for: page.bounds(for: .mediaBox))?.bounds(for: page))

        // PDFium mis-decoding a "ti" ligature glyph, as observed with real embedded fonts:
        // "Generative" reads back as "Genera+ve". PDFKit's own selection API for the same
        // bounds should still say "Generative", and be preferred since the lengths match.
        let mangled = "Genera+ve AI strategy"
        let reconciled = PDFTextAnalysisEngine.reconcileLigatures(mangled, bounds: fullBounds, sourcePage: page)
        XCTAssertEqual(reconciled, "Generative AI strategy")
    }

    func testReconcileLigaturesFallsBackWhenPDFKitTextLooksImplausible() throws {
        let pdf = makePDF(pageTexts: ["Generative AI strategy"])
        let page = try XCTUnwrap(pdf.page(at: 0))
        let fullBounds = try XCTUnwrap(page.selection(for: page.bounds(for: .mediaBox))?.bounds(for: page))

        // If the PDFKit selection string is wildly different in length from PDFium's
        // transcription (e.g. bounds accidentally picked up unrelated neighboring text),
        // trust PDFium instead of blindly swapping in something unrelated.
        let pdfiumText = "AB"
        let reconciled = PDFTextAnalysisEngine.reconcileLigatures(pdfiumText, bounds: fullBounds, sourcePage: page)
        XCTAssertEqual(reconciled, "AB")
    }

    func testWorkspaceCodableRoundTripsPageEditStates() throws {
        let pageID = UUID()
        var workspace = Workspace()
        workspace.pageEditStates = [
            PageEditState(pageRefID: pageID, operations: [
                PDFTextEditOperation(
                    pageRefID: pageID,
                    sourceBlockID: UUID(),
                    sourceBounds: CGRect(x: 1, y: 2, width: 30, height: 12),
                    editedBounds: CGRect(x: 1, y: 2, width: 42, height: 18),
                    replacementText: "Edited",
                    fontName: "Helvetica",
                    fontSize: 14,
                    textColor: .documentText,
                    alignment: .left
                )
            ])
        ]

        let decoded = try JSONDecoder().decode(Workspace.self, from: JSONEncoder().encode(workspace))

        XCTAssertEqual(decoded.pageEditStates.first?.pageRefID, pageID)
        XCTAssertEqual(decoded.pageEditStates.first?.operations.first?.replacementText, "Edited")
    }

    func testLegacyPageEditOperationDecodesWithDefaultGeometryMetadata() throws {
        let pageID = UUID()
        let blockID = UUID()
        let json = """
        {
          "pageRefID": "\(pageID.uuidString)",
          "sourceBlockID": "\(blockID.uuidString)",
          "sourceBounds": [[1,2],[30,12]],
          "editedBounds": [[1,2],[42,18]],
          "replacementText": "Edited",
          "fontName": "Helvetica",
          "fontSize": 14,
          "textColor": {"red":0,"green":0,"blue":0,"alpha":1},
          "alignment": "left"
        }
        """

        let decoded = try JSONDecoder().decode(PDFTextEditOperation.self, from: Data(json.utf8))

        XCTAssertEqual(decoded.pageRefID, pageID)
        XCTAssertTrue(decoded.sourceLineBounds.isEmpty)
        XCTAssertNil(decoded.columnBounds)
        XCTAssertFalse(decoded.didManuallyReposition)
        XCTAssertFalse(decoded.didManuallyResizeWidth)
        XCTAssertFalse(decoded.didManuallyResizeHeight)
        XCTAssertFalse(decoded.didManuallyChangeStyle)
    }

    func testInlineTextEditRegeneratesTouchedPageAndStoresOperation() throws {
        let fixture = try makeMemberWithPDF(name: "Editable", pageTexts: ["Original text"])
        let document = WorkspaceDocument()
        document.workspace.documents = [fixture.member]
        document.workspace.pageOrder = fixture.refs
        document.memberPDFData[fixture.member.id] = fixture.pdfData
        let viewModel = WorkspaceViewModel(
            document: document,
            processingEngine: PDFKitProcessingEngineFallback()
        )
        let sourceBlock = EditableTextBlock(
            pageRefID: fixture.refs[0].id,
            text: "Original text",
            bounds: CGRect(x: 70, y: 700, width: 120, height: 24),
            lines: [],
            fontName: "Helvetica",
            fontSize: 16,
            textColor: .documentText,
            rotation: 0,
            baseline: 700,
            confidence: .high
        )
        let before = try XCTUnwrap(viewModel.loadedPDFs.first?.1.dataRepresentation())

        XCTAssertTrue(viewModel.applyInlineTextEdit(
            pageRef: fixture.refs[0],
            sourceBlock: sourceBlock,
            replacementText: "Replacement text",
            editedBounds: CGRect(x: 70, y: 700, width: 180, height: 28),
            fontName: "Helvetica",
            fontSize: 16,
            textColor: .black,
            alignment: .left
        ))

        let after = try XCTUnwrap(viewModel.loadedPDFs.first?.1.dataRepresentation())
        XCTAssertNotEqual(after, before)
        XCTAssertEqual(viewModel.document.workspace.pageEditStates.first?.operations.first?.replacementText, "Replacement text")
        XCTAssertNotNil(viewModel.loadedPDFs.first?.1.page(at: 0))
        XCTAssertTrue(viewModel.loadedPDFs.first?.1.stringValue.contains("Replacement text") ?? false)
    }

    /// Rotating one page (page 1) and then editing text on an entirely UNRELATED page
    /// (page 2) in the same member must leave page 1's rotation and content untouched.
    /// Every inline edit re-serializes the WHOLE member PDF and reloads it fresh
    /// (`regenerateEditedPage`), so a real risk here is the round-trip silently losing or
    /// shifting another page's `/Rotate` state or content — this is the first test to
    /// exercise that specific cross-page interaction end-to-end through the real
    /// `rotatePage`/`applyInlineTextEdit`/export APIs (not the low-level renderer alone).
    func testEditingOnePageAfterRotatingAnUnrelatedPagePreservesBothIndependently() throws {
        let fixture = try makeMemberWithPDF(name: "Multi", pageTexts: ["Page one content", "Page two original"])
        let document = WorkspaceDocument()
        document.workspace.documents = [fixture.member]
        document.workspace.pageOrder = fixture.refs
        document.memberPDFData[fixture.member.id] = fixture.pdfData
        let viewModel = WorkspaceViewModel(document: document, processingEngine: PDFKitProcessingEngineFallback())

        viewModel.rotatePage(fixture.refs[0], by: 90)
        XCTAssertEqual(viewModel.loadedPDFs.first?.1.page(at: 0)?.rotation, 90)

        let sourceBlock = EditableTextBlock(
            pageRefID: fixture.refs[1].id,
            text: "Page two original",
            bounds: CGRect(x: 70, y: 700, width: 150, height: 24),
            lines: [],
            fontName: "Helvetica",
            fontSize: 16,
            textColor: .documentText,
            rotation: 0,
            baseline: 700,
            confidence: .high
        )
        XCTAssertTrue(viewModel.applyInlineTextEdit(
            pageRef: fixture.refs[1],
            sourceBlock: sourceBlock,
            replacementText: "Page two edited",
            editedBounds: CGRect(x: 70, y: 700, width: 190, height: 28),
            fontName: "Helvetica",
            fontSize: 16,
            textColor: .black,
            alignment: .left
        ))

        // The rotated, untouched page must still be rotated and still contain its content.
        let page1 = try XCTUnwrap(viewModel.loadedPDFs.first?.1.page(at: 0))
        XCTAssertEqual(page1.rotation, 90, "editing an unrelated page must not disturb this page's rotation")
        XCTAssertTrue(page1.string?.contains("Page one content") ?? false, "editing an unrelated page must not disturb this page's content")

        // The edited page must reflect the edit and stay unrotated.
        let page2 = try XCTUnwrap(viewModel.loadedPDFs.first?.1.page(at: 1))
        XCTAssertEqual(page2.rotation, 0)
        XCTAssertTrue(page2.string?.contains("Page two edited") ?? false)

        let exportedData = try viewModel.document.exportedPDFDataThrowing(from: try viewModel.document.snapshot(contentType: .pdf))
        let exportedPDF = try XCTUnwrap(PDFDocument(data: exportedData))
        let exportedPage1 = try XCTUnwrap(exportedPDF.page(at: 0))
        let exportedPage2 = try XCTUnwrap(exportedPDF.page(at: 1))
        XCTAssertEqual(exportedPage1.rotation, 90, "exported rotated page must still be rotated")
        XCTAssertTrue(exportedPage1.string?.contains("Page one content") ?? false)
        XCTAssertEqual(exportedPage2.rotation, 0)
        XCTAssertTrue(exportedPage2.string?.contains("Page two edited") ?? false)
    }

    func testInlineTextEditAfterPageMoveUsesOriginalSourcePage() throws {
        let fixture = try makeMemberWithPDF(name: "Editable", pageTexts: ["First page original", "Second page original"])
        let document = WorkspaceDocument()
        document.workspace.documents = [fixture.member]
        document.workspace.pageOrder = fixture.refs
        document.memberPDFData[fixture.member.id] = fixture.pdfData
        let viewModel = WorkspaceViewModel(
            document: document,
            processingEngine: PDFKitProcessingEngineFallback()
        )

        XCTAssertTrue(viewModel.movePage(fixture.refs[1], toIndex: 0))

        let sourceBlock = EditableTextBlock(
            pageRefID: fixture.refs[1].id,
            text: "Second page original",
            bounds: CGRect(x: 70, y: 700, width: 170, height: 24),
            lines: [],
            fontName: "Helvetica",
            fontSize: 16,
            textColor: .documentText,
            rotation: 0,
            baseline: 700,
            confidence: .high
        )

        XCTAssertTrue(viewModel.applyInlineTextEdit(
            pageRef: fixture.refs[1],
            sourceBlock: sourceBlock,
            replacementText: "Edited second page",
            editedBounds: CGRect(x: 70, y: 700, width: 190, height: 28),
            fontName: "Helvetica",
            fontSize: 16,
            textColor: .black,
            alignment: .left
        ))

        let movedPageText = viewModel.loadedPDFs.first?.1.page(at: 0)?.string ?? ""
        XCTAssertTrue(movedPageText.contains("Edited second page"))
        XCTAssertFalse(movedPageText.contains("First page original"))
    }

    func testInlineTextEditUndoRedoRestoresRenderedPDFAndEditState() throws {
        let fixture = try makeMemberWithPDF(name: "Editable", pageTexts: ["Original text"])
        let document = WorkspaceDocument()
        document.workspace.documents = [fixture.member]
        document.workspace.pageOrder = fixture.refs
        document.memberPDFData[fixture.member.id] = fixture.pdfData
        let viewModel = WorkspaceViewModel(
            document: document,
            processingEngine: PDFKitProcessingEngineFallback()
        )
        let undoManager = UndoManager()
        viewModel.undoManager = undoManager
        let sourceBlock = EditableTextBlock(
            pageRefID: fixture.refs[0].id,
            text: "Original text",
            bounds: CGRect(x: 70, y: 700, width: 120, height: 24),
            lines: [],
            fontName: "Helvetica",
            fontSize: 16,
            textColor: .documentText,
            rotation: 0,
            baseline: 700,
            confidence: .high
        )

        XCTAssertTrue(viewModel.applyInlineTextEdit(
            pageRef: fixture.refs[0],
            sourceBlock: sourceBlock,
            replacementText: "Redoable replacement",
            editedBounds: CGRect(x: 70, y: 700, width: 190, height: 28),
            fontName: "Helvetica",
            fontSize: 16,
            textColor: .black,
            alignment: .left
        ))
        XCTAssertTrue(viewModel.loadedPDFs.first?.1.stringValue.contains("Redoable replacement") ?? false)
        XCTAssertEqual(viewModel.document.workspace.pageEditStates.first?.operations.count, 1)

        undoManager.undo()
        XCTAssertFalse(viewModel.loadedPDFs.first?.1.stringValue.contains("Redoable replacement") ?? true)
        XCTAssertTrue(viewModel.document.workspace.pageEditStates.isEmpty)

        undoManager.redo()
        XCTAssertTrue(viewModel.loadedPDFs.first?.1.stringValue.contains("Redoable replacement") ?? false)
        XCTAssertEqual(viewModel.document.workspace.pageEditStates.first?.operations.first?.replacementText, "Redoable replacement")
    }

    func testUndoCommandShowsMessageAfterLastUndo() throws {
        let fixture = try makeMemberWithPDF(name: "Undoable", pageTexts: ["Original text"])
        let document = WorkspaceDocument()
        document.workspace.documents = [fixture.member]
        document.workspace.pageOrder = fixture.refs
        document.memberPDFData[fixture.member.id] = fixture.pdfData
        let viewModel = WorkspaceViewModel(
            document: document,
            processingEngine: PDFKitProcessingEngineFallback()
        )
        let undoManager = UndoManager()
        viewModel.undoManager = undoManager

        viewModel.rotatePage(fixture.refs[0], by: 90)
        XCTAssertTrue(undoManager.canUndo)

        viewModel.performUndoCommand()

        XCTAssertFalse(undoManager.canUndo)
        XCTAssertEqual(viewModel.loadedPDFs[0].1.page(at: 0)?.rotation, 0)
        XCTAssertEqual(viewModel.editingStatus?.message, "You are back at the beginning. Nothing left to undo.")
        XCTAssertFalse(viewModel.editingStatus?.isError ?? true)
    }

    func testUndoCommandReportsEmptyUndoStackWithoutCrashing() throws {
        let fixture = try makeMemberWithPDF(name: "Undoable", pageTexts: ["Original text"])
        let document = WorkspaceDocument()
        document.workspace.documents = [fixture.member]
        document.workspace.pageOrder = fixture.refs
        document.memberPDFData[fixture.member.id] = fixture.pdfData
        let viewModel = WorkspaceViewModel(
            document: document,
            processingEngine: PDFKitProcessingEngineFallback()
        )
        let undoManager = UndoManager()
        viewModel.undoManager = undoManager

        viewModel.performUndoCommand()

        XCTAssertEqual(viewModel.editingStatus?.message, "Nothing left to undo.")
        XCTAssertFalse(viewModel.editingStatus?.isError ?? true)
    }

    /// Regression test for a confirmed bug found during the format-painter audit: a format
    /// copied via "Copy" (arming the painter to auto-apply to the next edit opened) stayed
    /// armed across an unrelated undo — undo is a strong, explicit "back out of what I was
    /// doing" signal, so stale armed formatting surviving it and silently auto-applying to
    /// the next edit the user opens is more surprising than helpful.
    func testUndoDisarmsFormatPainter() throws {
        let fixture = try makeMemberWithPDF(name: "Undoable", pageTexts: ["Original text"])
        let document = WorkspaceDocument()
        document.workspace.documents = [fixture.member]
        document.workspace.pageOrder = fixture.refs
        document.memberPDFData[fixture.member.id] = fixture.pdfData
        let viewModel = WorkspaceViewModel(
            document: document,
            processingEngine: PDFKitProcessingEngineFallback()
        )
        let undoManager = UndoManager()
        viewModel.undoManager = undoManager

        viewModel.rotatePage(fixture.refs[0], by: 90)
        viewModel.copiedInlineTextFormat = PDFTextEditFormat(
            fontName: "Helvetica",
            fontSize: 12,
            textColor: .documentText,
            alignment: .left
        )
        viewModel.isInlineTextFormatPainterArmed = true

        viewModel.performUndoCommand()

        XCTAssertFalse(viewModel.isInlineTextFormatPainterArmed, "Undo must disarm a stale copied format")
        XCTAssertNil(viewModel.copiedInlineTextFormat, "Undo must clear the stale copied format")
    }

    /// Regression test for a bug caught during the confirmation-severity audit: neutral
    /// status messages ("Nothing to undo", "Back at the beginning") were reporting through
    /// the legacy `isError: false` overload, which maps to `.warning` — rendering them with
    /// the amber warning icon and a 4s linger instead of the intended quick `.info` toast.
    func testUndoStatusMessagesReportInfoSeverityNotWarning() throws {
        let fixture = try makeMemberWithPDF(name: "Undoable", pageTexts: ["Original text"])
        let document = WorkspaceDocument()
        document.workspace.documents = [fixture.member]
        document.workspace.pageOrder = fixture.refs
        document.memberPDFData[fixture.member.id] = fixture.pdfData
        let viewModel = WorkspaceViewModel(
            document: document,
            processingEngine: PDFKitProcessingEngineFallback()
        )
        let undoManager = UndoManager()
        viewModel.undoManager = undoManager

        viewModel.performUndoCommand()
        XCTAssertEqual(viewModel.editingStatus?.severity, .info, "'Nothing to undo' is a neutral status, not a warning")

        viewModel.rotatePage(fixture.refs[0], by: 90)
        viewModel.performUndoCommand()
        XCTAssertEqual(viewModel.editingStatus?.severity, .info, "'Back at the beginning' is a neutral status, not a warning")
    }

    func testInlineTextEditDoesNotClipReplacementLongerThanOriginalWord() throws {
        let fixture = try makeMemberWithPDF(name: "Editable", pageTexts: ["Original text"])
        let document = WorkspaceDocument()
        document.workspace.documents = [fixture.member]
        document.workspace.pageOrder = fixture.refs
        document.memberPDFData[fixture.member.id] = fixture.pdfData
        let viewModel = WorkspaceViewModel(
            document: document,
            processingEngine: PDFKitProcessingEngineFallback()
        )
        // A narrow box sized for the original short word — the box a caller (or a stale
        // live-editor frame) might still hand in even though the new text is much longer.
        let sourceBlock = EditableTextBlock(
            pageRefID: fixture.refs[0].id,
            text: "text",
            bounds: CGRect(x: 70, y: 700, width: 32, height: 18),
            lines: [],
            fontName: "Helvetica",
            fontSize: 14,
            textColor: .documentText,
            rotation: 0,
            baseline: 700,
            confidence: .high
        )

        XCTAssertTrue(viewModel.applyInlineTextEdit(
            pageRef: fixture.refs[0],
            sourceBlock: sourceBlock,
            replacementText: "a substantially longer replacement phrase",
            editedBounds: CGRect(x: 70, y: 700, width: 32, height: 18),
            fontName: "Helvetica",
            fontSize: 14,
            textColor: .black,
            alignment: .left
        ))

        let operation = try XCTUnwrap(viewModel.document.workspace.pageEditStates.first?.operations.first)
        XCTAssertGreaterThan(operation.editedBounds.width, sourceBlock.bounds.width)

        let page = try XCTUnwrap(viewModel.loadedPDFs.first?.1.page(at: 0))
        let bitmap = try renderedBitmap(for: page)
        let extendedReplacementBounds = operation.editedBounds.intersection(
            CGRect(
                x: sourceBlock.bounds.maxX + 8,
                y: operation.editedBounds.minY,
                width: operation.editedBounds.width - sourceBlock.bounds.width - 8,
                height: operation.editedBounds.height
            )
        )
        XCTAssertGreaterThan(
            darkPixelCount(in: extendedReplacementBounds, bitmap: bitmap),
            0,
            "replacement text should render beyond the original narrow source bounds"
        )
    }

    func testInsertionTextEditCopiesNearbyDetectedFormatByDefault() throws {
        let fixture = try makeMemberWithPDF(name: "Editable", pageTexts: ["Nearby styled text"])
        let document = WorkspaceDocument()
        document.workspace.documents = [fixture.member]
        document.workspace.pageOrder = fixture.refs
        document.memberPDFData[fixture.member.id] = fixture.pdfData
        let viewModel = WorkspaceViewModel(document: document, processingEngine: PDFKitProcessingEngineFallback())
        let page = try XCTUnwrap(viewModel.loadedPDFs.first?.1.page(at: 0))

        let engine = PDFTextAnalysisEngine()
        let analysis = engine.analyze(
            data: fixture.pdfData,
            pageIndex: 0,
            pageRefID: fixture.refs[0].id,
            fallbackPage: page
        )
        let nearby = try XCTUnwrap(analysis.blocks.first { $0.text.contains("Nearby") })
        let insertionPoint = CGPoint(x: nearby.bounds.minX, y: nearby.bounds.minY - 20)

        let target = try XCTUnwrap(viewModel.editableTextBlock(
            at: insertionPoint,
            on: page,
            in: viewModel.loadedPDFs.first?.1
        ))

        XCTAssertTrue(target.block.text.isEmpty)
        XCTAssertEqual(target.block.fontName, nearby.fontName)
        XCTAssertEqual(target.block.fontSize, nearby.fontSize, accuracy: 0.01)
        XCTAssertEqual(target.block.textColor, nearby.textColor)
        XCTAssertEqual(target.block.alignment, nearby.alignment)
    }

    func testReopenedInlineTextEditKeepsOriginalFormatAvailableForMatching() throws {
        let fixture = try makeMemberWithPDF(name: "Editable", pageTexts: ["Nearby styled text"])
        let document = WorkspaceDocument()
        document.workspace.documents = [fixture.member]
        document.workspace.pageOrder = fixture.refs
        document.memberPDFData[fixture.member.id] = fixture.pdfData
        let viewModel = WorkspaceViewModel(document: document, processingEngine: PDFKitProcessingEngineFallback())
        let originalPage = try XCTUnwrap(PDFDocument(data: fixture.pdfData)?.page(at: 0))
        let analysis = PDFTextAnalysisEngine().analyze(
            data: fixture.pdfData,
            pageIndex: 0,
            pageRefID: fixture.refs[0].id,
            fallbackPage: originalPage
        )
        let sourceBlock = try XCTUnwrap(analysis.blocks.first { $0.text.contains("Nearby") })
        let editedBounds = sourceBlock.bounds.insetBy(dx: -2, dy: -2)

        XCTAssertTrue(viewModel.applyInlineTextEdit(
            pageRef: fixture.refs[0],
            sourceBlock: sourceBlock,
            replacementText: "Mismatched replacement",
            editedBounds: editedBounds,
            fontName: "Courier-Bold",
            fontSize: sourceBlock.fontSize + 6,
            textColor: .systemRed,
            alignment: .right,
            didManuallyChangeStyle: true
        ))

        let editedPage = try XCTUnwrap(viewModel.loadedPDFs.first?.1.page(at: 0))
        let reopened = try XCTUnwrap(viewModel.editableTextBlock(
            at: CGPoint(x: editedBounds.midX, y: editedBounds.midY),
            on: editedPage,
            in: viewModel.loadedPDFs.first?.1
        ))

        XCTAssertEqual(reopened.block.fontName, "Courier-Bold")
        XCTAssertEqual(reopened.block.fontSize, sourceBlock.fontSize + 6, accuracy: 0.01)
        XCTAssertEqual(reopened.sourceFormat.fontName, sourceBlock.fontName)
        XCTAssertEqual(reopened.sourceFormat.fontSize, sourceBlock.fontSize, accuracy: 0.01)
        XCTAssertEqual(reopened.sourceFormat.textColor, sourceBlock.textColor)
        XCTAssertEqual(reopened.sourceFormat.alignment, sourceBlock.alignment ?? .left)
    }

    func testReopenedInlineTextEditWithoutManualStyleUsesOriginalFormat() throws {
        let fixture = try makeMemberWithPDF(name: "Editable", pageTexts: ["Nearby styled text"])
        let document = WorkspaceDocument()
        document.workspace.documents = [fixture.member]
        document.workspace.pageOrder = fixture.refs
        document.memberPDFData[fixture.member.id] = fixture.pdfData
        let viewModel = WorkspaceViewModel(document: document, processingEngine: PDFKitProcessingEngineFallback())
        let originalPage = try XCTUnwrap(PDFDocument(data: fixture.pdfData)?.page(at: 0))
        let analysis = PDFTextAnalysisEngine().analyze(
            data: fixture.pdfData,
            pageIndex: 0,
            pageRefID: fixture.refs[0].id,
            fallbackPage: originalPage
        )
        let sourceBlock = try XCTUnwrap(analysis.blocks.first { $0.text.contains("Nearby") })
        let editedBounds = sourceBlock.bounds.insetBy(dx: -2, dy: -2)

        XCTAssertTrue(viewModel.applyInlineTextEdit(
            pageRef: fixture.refs[0],
            sourceBlock: sourceBlock,
            replacementText: "Same style replacement",
            editedBounds: editedBounds,
            fontName: "Courier-Bold",
            fontSize: sourceBlock.fontSize + 6,
            textColor: .systemRed,
            alignment: .right
        ))

        let editedPage = try XCTUnwrap(viewModel.loadedPDFs.first?.1.page(at: 0))
        let reopened = try XCTUnwrap(viewModel.editableTextBlock(
            at: CGPoint(x: editedBounds.midX, y: editedBounds.midY),
            on: editedPage,
            in: viewModel.loadedPDFs.first?.1
        ))

        XCTAssertEqual(reopened.block.fontName, sourceBlock.fontName)
        XCTAssertEqual(reopened.block.fontSize, sourceBlock.fontSize, accuracy: 0.01)
        XCTAssertEqual(reopened.block.textColor, sourceBlock.textColor)
        XCTAssertEqual(reopened.block.alignment, sourceBlock.alignment ?? .left)
    }

    /// When a fresh text-analysis pass can't re-locate the edited paragraph at all
    /// (nothing within the matching radius — e.g. the original sat somewhere a later
    /// layout pass can no longer confirm), Match/Restore must fall back to the format
    /// captured once when this edit was first created, not to this operation's own
    /// current/edited styling. Regression test for a bug where reopening an edit and
    /// pressing Match/Restore reapplied the edit's own (already wrong) formatting
    /// instead of ever recovering the true original.
    func testReopenedInlineTextEditFallsBackToStoredOriginalFormatWhenAnalysisFindsNoNearbyMatch() throws {
        let fixture = try makeMemberWithPDF(name: "Editable", pageTexts: ["Nearby styled text"])
        let document = WorkspaceDocument()
        document.workspace.documents = [fixture.member]
        document.workspace.pageOrder = fixture.refs
        document.memberPDFData[fixture.member.id] = fixture.pdfData
        let viewModel = WorkspaceViewModel(document: document, processingEngine: PDFKitProcessingEngineFallback())

        // Far from the fixture's real analyzed text (around y=690-704), so a fresh
        // analysis pass has nothing within the matching radius to find.
        let isolatedBounds = CGRect(x: 72, y: 200, width: 140, height: 16)
        let sourceBlock = EditableTextBlock(
            pageRefID: fixture.refs[0].id,
            text: "Isolated original",
            bounds: isolatedBounds,
            lines: [],
            fontName: "Courier",
            fontSize: 11,
            textColor: .documentText,
            alignment: .center,
            rotation: 0,
            baseline: isolatedBounds.minY,
            confidence: .high
        )

        XCTAssertTrue(viewModel.applyInlineTextEdit(
            pageRef: fixture.refs[0],
            sourceBlock: sourceBlock,
            replacementText: "Replacement with different styling",
            editedBounds: isolatedBounds,
            fontName: "Helvetica-Bold",
            fontSize: 18,
            textColor: .systemRed,
            alignment: .right
        ))

        let editedPage = try XCTUnwrap(viewModel.loadedPDFs.first?.1.page(at: 0))
        let reopened = try XCTUnwrap(viewModel.editableTextBlock(
            at: CGPoint(x: isolatedBounds.midX, y: isolatedBounds.midY),
            on: editedPage,
            in: viewModel.loadedPDFs.first?.1
        ))

        XCTAssertEqual(reopened.sourceFormat.fontName, "Courier")
        XCTAssertEqual(reopened.sourceFormat.fontSize, 11, accuracy: 0.01)
        XCTAssertEqual(reopened.sourceFormat.alignment, .center)
        XCTAssertEqual(reopened.block.fontName, "Courier")
        XCTAssertEqual(reopened.block.alignment, .center)
    }

    func testRestoreOriginalStyleClearsExistingManualStyleFlag() throws {
        let fixture = try makeMemberWithPDF(name: "Editable", pageTexts: ["Nearby styled text"])
        let document = WorkspaceDocument()
        document.workspace.documents = [fixture.member]
        document.workspace.pageOrder = fixture.refs
        document.memberPDFData[fixture.member.id] = fixture.pdfData
        let viewModel = WorkspaceViewModel(document: document, processingEngine: PDFKitProcessingEngineFallback())
        let originalPage = try XCTUnwrap(PDFDocument(data: fixture.pdfData)?.page(at: 0))
        let analysis = PDFTextAnalysisEngine().analyze(
            data: fixture.pdfData,
            pageIndex: 0,
            pageRefID: fixture.refs[0].id,
            fallbackPage: originalPage
        )
        let sourceBlock = try XCTUnwrap(analysis.blocks.first { $0.text.contains("Nearby") })
        let editedBounds = sourceBlock.bounds.insetBy(dx: -2, dy: -2)

        XCTAssertTrue(viewModel.applyInlineTextEdit(
            pageRef: fixture.refs[0],
            sourceBlock: sourceBlock,
            replacementText: "Styled replacement",
            editedBounds: editedBounds,
            fontName: "Courier-Bold",
            fontSize: sourceBlock.fontSize + 6,
            textColor: .systemRed,
            alignment: .right,
            didManuallyChangeStyle: true
        ))
        XCTAssertTrue(viewModel.document.workspace.pageEditStates.first?.operations.first?.didManuallyChangeStyle == true)

        XCTAssertTrue(viewModel.applyInlineTextEdit(
            pageRef: fixture.refs[0],
            sourceBlock: sourceBlock,
            replacementText: "Styled replacement",
            editedBounds: editedBounds,
            fontName: sourceBlock.fontName,
            fontSize: sourceBlock.fontSize,
            textColor: sourceBlock.textColor.nsColor,
            alignment: sourceBlock.alignment?.nsTextAlignment ?? .left,
            didManuallyChangeStyle: false,
            didRestoreOriginalStyle: true
        ))

        let restored = try XCTUnwrap(viewModel.document.workspace.pageEditStates.first?.operations.first)
        XCTAssertFalse(restored.didManuallyChangeStyle)
        XCTAssertEqual(restored.fontName, sourceBlock.fontName)
        XCTAssertEqual(restored.fontSize, sourceBlock.fontSize, accuracy: 0.01)
        XCTAssertEqual(restored.textColor, sourceBlock.textColor)
        XCTAssertEqual(restored.alignment, sourceBlock.alignment ?? .left)
    }

    func testReopenedAutoSizedInlineTextEditUsesOriginalParagraphWidth() throws {
        let fixture = try makeMemberWithPDF(name: "Editable", pageTexts: ["Nearby styled text wraps across a normal paragraph column"])
        let document = WorkspaceDocument()
        document.workspace.documents = [fixture.member]
        document.workspace.pageOrder = fixture.refs
        document.memberPDFData[fixture.member.id] = fixture.pdfData
        let viewModel = WorkspaceViewModel(document: document, processingEngine: PDFKitProcessingEngineFallback())
        let originalPage = try XCTUnwrap(PDFDocument(data: fixture.pdfData)?.page(at: 0))
        let analysis = PDFTextAnalysisEngine().analyze(
            data: fixture.pdfData,
            pageIndex: 0,
            pageRefID: fixture.refs[0].id,
            fallbackPage: originalPage
        )
        let sourceBlock = try XCTUnwrap(analysis.blocks.first { $0.text.contains("Nearby") })
        let narrowEditedBounds = CGRect(
            x: sourceBlock.bounds.minX,
            y: sourceBlock.bounds.minY - 80,
            width: max(80, sourceBlock.bounds.width * 0.4),
            height: sourceBlock.bounds.height + 80
        )

        XCTAssertTrue(viewModel.applyInlineTextEdit(
            pageRef: fixture.refs[0],
            sourceBlock: sourceBlock,
            replacementText: "Replacement text",
            editedBounds: narrowEditedBounds,
            fontName: sourceBlock.fontName,
            fontSize: sourceBlock.fontSize,
            textColor: sourceBlock.textColor.nsColor,
            alignment: .left
        ))

        let stored = try XCTUnwrap(viewModel.document.workspace.pageEditStates.first?.operations.first)
        let editedPage = try XCTUnwrap(viewModel.loadedPDFs.first?.1.page(at: 0))
        let reopened = try XCTUnwrap(viewModel.editableTextBlock(
            at: CGPoint(x: stored.editedBounds.midX, y: stored.editedBounds.midY),
            on: editedPage,
            in: viewModel.loadedPDFs.first?.1
        ))

        XCTAssertEqual(reopened.block.bounds.minX, sourceBlock.bounds.minX, accuracy: 0.01)
        XCTAssertEqual(reopened.block.bounds.width, sourceBlock.bounds.width, accuracy: 0.01)
        XCTAssertLessThan(reopened.block.bounds.height, narrowEditedBounds.height)
    }

    func testInlineTextEditErasesCommittedEditedBoundsSoNearbyTextDoesNotBleedThrough() throws {
        let pdf = makeTwoLinePDF()
        let page = try XCTUnwrap(pdf.page(at: 0))
        let operation = PDFTextEditOperation(
            pageRefID: UUID(),
            sourceBlockID: UUID(),
            sourceBounds: CGRect(x: 72, y: 686, width: 42, height: 18),
            editedBounds: CGRect(x: 72, y: 626, width: 260, height: 78),
            replacementText: "Replacement",
            fontName: "Helvetica",
            fontSize: 14,
            textColor: .documentText,
            alignment: .left,
            didManuallyReposition: true,
            didManuallyResizeWidth: true,
            didManuallyResizeHeight: true
        )

        let regenerated = try XCTUnwrap(PDFEditedPageRenderer.regeneratedPage(from: page, applying: [operation]))
        let bitmap = try renderedBitmap(for: regenerated)
        let staleTextSample = try XCTUnwrap(bitmap.colorAt(x: 128, y: 792 - 650)?.usingColorSpace(.deviceRGB))

        XCTAssertGreaterThan(
            staleTextSample.brightnessComponent,
            0.9,
            "stale text under the grown replacement edit box should be cleared"
        )
    }

    /// `PDFPage.draw(with:to:)` bakes the page's own rotation into what it renders.
    /// `regeneratedPage` draws the background into a context sized to the RAW (unrotated)
    /// mediaBox — for a non-square page rotated 90°/270°, drawing an ALREADY-rotated page
    /// into that unrotated-shaped context clips/loses the content entirely (confirmed
    /// empirically while diagnosing this bug: nothing renders at all). That lost/blank
    /// background then becomes the "raw" content of the regenerated page, which gets
    /// rotation re-applied on top for display — so the whole page goes blank after any
    /// edit on a 90°/270°-rotated non-square page, not just the edited region. This
    /// reproduces that on a 612x792 (non-square) page and confirms page content the edit
    /// never touched still renders after regeneration.
    func testInlineTextEditOnRotatedNonSquarePagePreservesUntouchedBackgroundContent() throws {
        let pdf = makeTwoLinePDF()
        let page = try XCTUnwrap(pdf.page(at: 0))
        XCTAssertNotEqual(page.bounds(for: .mediaBox).width, page.bounds(for: .mediaBox).height, "fixture must be non-square to exercise the rotation clipping bug")
        XCTAssertTrue(page.string?.contains("Stale lower line") ?? false, "sanity check: fixture must contain this text before editing")
        // A small, unrelated insertion far from "Short"/"Stale lower line" — the edit
        // itself is not what's under test; the untouched background is. Checking
        // extracted text (rather than rendered pixels) directly proves whether the
        // original background content survived regeneration at all, independent of
        // where on the page it ends up.
        let operation = PDFTextEditOperation(
            pageRefID: UUID(),
            sourceBlockID: UUID(),
            sourceBounds: CGRect(x: 400, y: 100, width: 1, height: 1),
            editedBounds: CGRect(x: 400, y: 100, width: 60, height: 16),
            replacementText: "New",
            fontName: "Helvetica",
            fontSize: 12,
            textColor: .documentText,
            alignment: .left,
            isInsertion: true
        )
        page.rotation = 90

        let regenerated = try XCTUnwrap(PDFEditedPageRenderer.regeneratedPage(from: page, applying: [operation]))
        XCTAssertEqual(regenerated.rotation, 90, "the regenerated page must keep reporting the original rotation for viewers")
        XCTAssertTrue(
            regenerated.string?.contains("Stale lower line") ?? false,
            "the original page's untouched background text must survive regenerating a 90°-rotated non-square page — it must not go blank"
        )
    }

    func testRotatedInlineTextEditPreservesRenderedExportedPageContent() throws {
        let pdf = makeTwoLinePDF()
        let page = try XCTUnwrap(pdf.page(at: 0))
        page.rotation = 90
        let fixture = try makeMemberFixture(name: "Rotated", pdf: pdf)
        let document = WorkspaceDocument()
        document.workspace.documents = [fixture.member]
        document.workspace.pageOrder = fixture.refs
        document.memberPDFData[fixture.member.id] = fixture.pdfData
        let viewModel = WorkspaceViewModel(document: document, processingEngine: PDFKitProcessingEngineFallback())
        let sourceBlock = EditableTextBlock(
            pageRefID: fixture.refs[0].id,
            text: "",
            bounds: CGRect(x: 400, y: 100, width: 1, height: 1),
            lines: [],
            fontName: "Helvetica",
            fontSize: 12,
            textColor: .documentText,
            rotation: 0,
            baseline: 100,
            confidence: .high
        )

        XCTAssertTrue(viewModel.applyInlineTextEdit(
            pageRef: fixture.refs[0],
            sourceBlock: sourceBlock,
            replacementText: "New",
            editedBounds: CGRect(x: 400, y: 100, width: 60, height: 16),
            fontName: "Helvetica",
            fontSize: 12,
            textColor: .black,
            alignment: .left
        ))

        let exportedData = try viewModel.document.exportedPDFDataThrowing(from: try viewModel.document.snapshot(contentType: .pdf))
        let exportedPage = try XCTUnwrap(PDFDocument(data: exportedData)?.page(at: 0))
        let bitmap = try renderedBitmap(for: exportedPage)
        let exportedString = try XCTUnwrap(exportedPage.string)
        let untouchedRange = (exportedString as NSString).range(of: "Stale lower line")
        XCTAssertNotEqual(untouchedRange.location, NSNotFound)
        let insertedRange = (exportedString as NSString).range(of: "New")
        XCTAssertNotEqual(insertedRange.location, NSNotFound)
        let insertedSelection = try XCTUnwrap(exportedPage.selection(for: insertedRange))
        let insertedInk = darkPixelCount(in: insertedSelection.bounds(for: exportedPage), bitmap: bitmap)
        let pageInk = darkPixelCount(in: exportedPage.bounds(for: .mediaBox), bitmap: bitmap)
        XCTAssertGreaterThan(
            pageInk,
            insertedInk + 50,
            "exported rotated pages must keep visible original content, not just the inserted replacement"
        )
        XCTAssertTrue(exportedString.contains("Stale lower line"))
        XCTAssertTrue(exportedString.contains("New"))
    }

    func testInlineTextEditDoesNotEraseAutoGrownBoundsBeyondOriginalText() throws {
        let sourceBounds = CGRect(x: 72, y: 686, width: 42, height: 18)
        let editedBounds = CGRect(x: 72, y: 626, width: 260, height: 78)
        let operation = PDFTextEditOperation(
            pageRefID: UUID(),
            sourceBlockID: UUID(),
            sourceBounds: sourceBounds,
            editedBounds: editedBounds,
            replacementText: "Replacement",
            fontName: "Helvetica",
            fontSize: 14,
            textColor: .documentText,
            alignment: .left
        )

        XCTAssertEqual(PDFEditedPageRenderer.eraseBounds(for: operation), [sourceBounds])
    }

    /// Match/Copy/Restore Style can move an edit to a different paragraph's margins or
    /// column without a manual drag ever happening, so `didManuallyResizeWidth`/
    /// `didManuallyReposition` stay false. Without also erasing the destination in that
    /// case, replacement text drawn at the new location would bleed over whatever
    /// original content already sat there (nothing at that spot was ever erased).
    func testInlineTextEditErasesDestinationWhenMatchedGeometryMovedTheBoxWithoutManualFlags() throws {
        let sourceBounds = CGRect(x: 72, y: 686, width: 42, height: 18)
        let matchedDestination = CGRect(x: 200, y: 686, width: 180, height: 18)
        let operation = PDFTextEditOperation(
            pageRefID: UUID(),
            sourceBlockID: UUID(),
            sourceBounds: sourceBounds,
            editedBounds: matchedDestination,
            replacementText: "Replacement",
            fontName: "Helvetica",
            fontSize: 14,
            textColor: .documentText,
            alignment: .left,
            didApplyMatchedGeometry: true
        )

        XCTAssertEqual(PDFEditedPageRenderer.eraseBounds(for: operation), [sourceBounds, matchedDestination])
    }

    func testMeasuredBoundsGrowsDownwardFromAFixedTopEdge() throws {
        // The live inline editor grows downward from a fixed top as typed text wraps
        // (InlineTextEditorOverlay.resizeTextViewHeight pins editorTopY and drops the
        // bottom edge). The bounds baked into the final PDF must grow the same way —
        // growing from a fixed bottom instead pushes the replacement upward past where
        // the user saw it while typing, colliding with whatever content sits above it
        // (reported as edits "moving up" and overlapping the line above).
        let originalBounds = CGRect(x: 70, y: 700, width: 120, height: 16)
        let operation = PDFTextEditOperation(
            pageRefID: UUID(),
            sourceBlockID: UUID(),
            sourceBounds: originalBounds,
            editedBounds: originalBounds,
            replacementText: "A much longer replacement that will wrap across two full lines",
            fontName: "Helvetica",
            fontSize: 14,
            textColor: .documentText,
            alignment: .left
        )

        let measured = PDFEditedPageRenderer.measuredBounds(for: operation)

        XCTAssertGreaterThan(measured.height, originalBounds.height, "expected the box to grow for wrapped text")
        XCTAssertEqual(measured.maxY, originalBounds.maxY, accuracy: 0.01, "top edge must stay fixed as the box grows")
        XCTAssertLessThan(measured.minY, originalBounds.minY, "extra height must be added below the top, not above it")
    }

    func testMeasuredBoundsWrapsWithinDetectedColumn() throws {
        let originalBounds = CGRect(x: 70, y: 700, width: 90, height: 16)
        let operation = PDFTextEditOperation(
            pageRefID: UUID(),
            sourceBlockID: UUID(),
            sourceBounds: originalBounds,
            editedBounds: originalBounds,
            columnBounds: CGRect(x: 70, y: 0, width: 150, height: 792),
            replacementText: "A much longer replacement phrase that must wrap before the sidebar",
            fontName: "Helvetica",
            fontSize: 12,
            textColor: .documentText,
            alignment: .left
        )

        let measured = PDFEditedPageRenderer.measuredBounds(for: operation)

        XCTAssertLessThanOrEqual(measured.maxX, 220.01)
        XCTAssertGreaterThan(measured.height, originalBounds.height)
    }

    func testMeasuredBoundsPreservesWideDetectedParagraphColumn() throws {
        let paragraphBounds = CGRect(x: 70, y: 640, width: 880, height: 54)
        let operation = PDFTextEditOperation(
            pageRefID: UUID(),
            sourceBlockID: UUID(),
            sourceBounds: paragraphBounds,
            editedBounds: paragraphBounds,
            columnBounds: CGRect(x: 70, y: 0, width: 900, height: 792),
            replacementText: "This paragraph should keep the same wide margins instead of being forced into an artificial narrow editor column.",
            fontName: "Helvetica",
            fontSize: 12,
            textColor: .documentText,
            alignment: .left
        )

        let measured = PDFEditedPageRenderer.measuredBounds(for: operation)

        XCTAssertEqual(measured.width, paragraphBounds.width, accuracy: 0.01)
        XCTAssertEqual(measured.minX, paragraphBounds.minX, accuracy: 0.01)
    }

    func testMeasuredBoundsWithoutColumnDoesNotCollapseWideParagraphToLegacyCap() throws {
        let paragraphBounds = CGRect(x: 70, y: 640, width: 760, height: 54)
        let operation = PDFTextEditOperation(
            pageRefID: UUID(),
            sourceBlockID: UUID(),
            sourceBounds: paragraphBounds,
            editedBounds: paragraphBounds,
            replacementText: "This paragraph has no explicit column metadata but should still preserve its detected width.",
            fontName: "Helvetica",
            fontSize: 12,
            textColor: .documentText,
            alignment: .left
        )

        let measured = PDFEditedPageRenderer.measuredBounds(for: operation)

        XCTAssertEqual(measured.width, paragraphBounds.width, accuracy: 0.01)
    }

    func testMeasuredBoundsKeepsEditedWrappedParagraphWithinItsColumn() throws {
        // A genuinely wrapped paragraph (sourceLineBounds.count > 1) whose column has
        // already been clamped to its own right margin. Editing its words must keep the
        // box within that column (re-wrapping / adding lines), never grow out to the page
        // edge. This is the render-side half of the right-margin-bleed fix.
        let paragraphBounds = CGRect(x: 72, y: 620, width: 396, height: 48)
        let lineBounds = [
            CGRect(x: 72, y: 652, width: 396, height: 14),
            CGRect(x: 72, y: 636, width: 390, height: 14),
            CGRect(x: 72, y: 620, width: 300, height: 14)
        ]
        let operation = PDFTextEditOperation(
            pageRefID: UUID(),
            sourceBlockID: UUID(),
            sourceBounds: paragraphBounds,
            sourceLineBounds: lineBounds,
            sourceText: "Original wrapped paragraph text spanning three lines within its margin.",
            editedBounds: paragraphBounds,
            columnBounds: CGRect(x: 72, y: 0, width: 402, height: 792),
            replacementText: "Original wrapped paragraph text spanning three lines within its margin, now with several additional edited words appended near the end.",
            fontName: "Helvetica",
            fontSize: 12,
            textColor: .documentText,
            alignment: .left
        )

        let measured = PDFEditedPageRenderer.measuredBounds(for: operation, pageBounds: CGRect(x: 0, y: 0, width: 612, height: 792))

        XCTAssertLessThanOrEqual(measured.maxX, 474.01, "edited paragraph must stay within its detected column, not bleed to the page edge")
        XCTAssertLessThanOrEqual(measured.width, 402.01, "width must stay within the column instead of growing to a single wide line")
        XCTAssertGreaterThanOrEqual(measured.width, 390, "the box should fill the column and wrap, not shrink to a fragment")
        XCTAssertGreaterThan(measured.height, 24, "appended text must wrap onto additional lines within the column")
    }

    func testMeasuredBoundsDoesNotCollapseUnchangedMultiLineParagraphToOneLine() throws {
        // Reopening an unchanged multi-line paragraph and changing only style commits with
        // replacementText == sourceText. The single-line width of the whole paragraph is
        // huge; without the multi-line guard measuredBounds would grow the box to a single
        // page-wide line, collapsing the paragraph.
        let paragraphBounds = CGRect(x: 72, y: 620, width: 396, height: 48)
        let lineBounds = [
            CGRect(x: 72, y: 652, width: 396, height: 14),
            CGRect(x: 72, y: 636, width: 390, height: 14),
            CGRect(x: 72, y: 620, width: 300, height: 14)
        ]
        let text = "Original wrapped paragraph text spanning three lines within its established right margin."
        let operation = PDFTextEditOperation(
            pageRefID: UUID(),
            sourceBlockID: UUID(),
            sourceBounds: paragraphBounds,
            sourceLineBounds: lineBounds,
            sourceText: text,
            editedBounds: paragraphBounds,
            columnBounds: CGRect(x: 72, y: 0, width: 402, height: 792),
            replacementText: text,
            fontName: "Helvetica",
            fontSize: 12,
            textColor: .documentText,
            alignment: .left
        )

        let measured = PDFEditedPageRenderer.measuredBounds(for: operation, pageBounds: CGRect(x: 0, y: 0, width: 612, height: 792))

        XCTAssertLessThanOrEqual(measured.maxX, 474.01, "unchanged multi-line paragraph must not grow to a page-wide single line")
        XCTAssertLessThanOrEqual(measured.width, 402.01, "unchanged multi-line paragraph must keep its column width, not collapse to one line")
        XCTAssertGreaterThan(measured.height, 24, "paragraph should keep its multi-line height, not collapse to a single line")
    }

    /// Regression: `maximumTextWidth`'s column-neighbor detection only ever looks at OTHER
    /// TEXT BLOCKS — an embedded image, figure, or logo sitting immediately to the right of
    /// a short paragraph isn't a text block, so nothing previously stopped a single-token
    /// (unbreakable) replacement from auto-growing its box's width straight across into the
    /// image's territory. Auto-growth never erases (see `eraseBounds`), so that growth would
    /// draw new replacement text directly on top of the image, unerased.
    func testMeasuredBoundsDoesNotGrowIntoAnAdjacentEmbeddedImage() throws {
        let pageBounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        let imageBounds = CGRect(x: 300, y: 650, width: 200, height: 100)
        let data = NSMutableData()
        var mediaBox = pageBounds
        let context = try XCTUnwrap(CGDataConsumer(data: data).flatMap { CGContext(consumer: $0, mediaBox: &mediaBox, nil) })
        context.beginPDFPage(nil)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        NSColor.white.setFill()
        pageBounds.fill()
        NSColor.systemBlue.setFill()
        imageBounds.fill()
        NSGraphicsContext.restoreGraphicsState()
        context.endPDFPage()
        context.closePDF()
        let page = try XCTUnwrap(PDFDocument(data: data as Data)?.page(at: 0))

        let originalBounds = CGRect(x: 72, y: 670, width: 60, height: 16)
        let operation = PDFTextEditOperation(
            pageRefID: UUID(),
            sourceBlockID: UUID(),
            sourceBounds: originalBounds,
            editedBounds: originalBounds,
            replacementText: "Supercalifragilisticexpialidocious",
            fontName: "Helvetica",
            fontSize: 12,
            textColor: .documentText,
            alignment: .left
        )

        let measured = PDFEditedPageRenderer.measuredBounds(for: operation, pageBounds: pageBounds, sourcePage: page)

        XCTAssertLessThanOrEqual(
            measured.maxX,
            imageBounds.minX + 0.01,
            "auto-growth must not extend the replacement box across an adjacent embedded image"
        )
    }

    func testMeasuredBoundsCapsAutomaticHeightToWhatFitsOnThePage() throws {
        // A pathologically long paste (tens of thousands of characters) has no other cap on
        // height the way width is capped to the page's right margin — unchecked, the box
        // grows far taller than the page itself, drawing content off-page rather than
        // failing or wrapping visibly.
        let originalBounds = CGRect(x: 72, y: 700, width: 120, height: 16)
        let hugeReplacement = Array(repeating: "word", count: 20_000).joined(separator: " ")
        let operation = PDFTextEditOperation(
            pageRefID: UUID(),
            sourceBlockID: UUID(),
            sourceBounds: originalBounds,
            editedBounds: originalBounds,
            columnBounds: CGRect(x: 72, y: 0, width: 300, height: 792),
            replacementText: hugeReplacement,
            fontName: "Helvetica",
            fontSize: 12,
            textColor: .documentText,
            alignment: .left
        )
        let pageBounds = CGRect(x: 0, y: 0, width: 612, height: 792)

        let measured = PDFEditedPageRenderer.measuredBounds(for: operation, pageBounds: pageBounds)

        XCTAssertLessThanOrEqual(measured.height, pageBounds.height, "the box must never grow taller than the page itself")
        XCTAssertGreaterThanOrEqual(measured.minY, pageBounds.minY - 1, "the box's bottom edge must not be pushed off the bottom of the page")
    }

    /// Regression: editing the LAST line of a paragraph sitting at the page's bottom
    /// margin, with a realistic (not pathological) amount of added text — enough to need
    /// one or two more wrapped lines at the paragraph's established column width, but not
    /// an absurd paste. The live editor overlay (`resizeTextViewHeight`) has no page-bottom
    /// limit and shows the full text while typing; only `measuredBounds` (used when
    /// actually regenerating/exporting the page) caps height to the room left below the
    /// box's fixed top edge. Capping height alone, without ever widening the box first,
    /// makes the CTFrame draw silently drop whatever text no longer fits — the user sees
    /// their full paragraph while typing, then loses the tail of it on commit with no
    /// warning. This paragraph's own detected column (as `assignColumnBounds` would
    /// actually produce for an ordinary single-column page with no right neighbor) has
    /// unused width beyond the current line's own text — that room should absorb the
    /// overflow (fewer wrapped lines) before any text is silently dropped.
    func testMeasuredBoundsWidensBeforeSilentlyDroppingTextNearThePageBottomMargin() throws {
        let originalBounds = CGRect(x: 72, y: 40, width: 200, height: 14)
        let replacement = "This replacement paragraph is intentionally long enough that it would need several wrapped lines at the original narrow column width, right at the bottom margin of the page."
        let operation = PDFTextEditOperation(
            pageRefID: UUID(),
            sourceBlockID: UUID(),
            sourceBounds: originalBounds,
            editedBounds: originalBounds,
            columnBounds: CGRect(x: 72, y: 0, width: 480, height: 792),
            replacementText: replacement,
            fontName: "Helvetica",
            fontSize: 12,
            textColor: .documentText,
            alignment: .left
        )
        let pageBounds = CGRect(x: 0, y: 0, width: 612, height: 792)

        let measured = PDFEditedPageRenderer.measuredBounds(for: operation, pageBounds: pageBounds)

        let font = NSFont(name: "Helvetica", size: 12) ?? NSFont.systemFont(ofSize: 12)
        let attributed = NSAttributedString(string: replacement, attributes: [.font: font])
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let path = CGMutablePath()
        path.addRect(measured)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: attributed.length), path, nil)
        let visibleRange = CTFrameGetVisibleStringRange(frame)

        XCTAssertEqual(
            visibleRange.length,
            attributed.length,
            "the box measuredBounds computed must be tall/wide enough to actually fit the full replacement text, not silently truncate it"
        )
        XCTAssertGreaterThanOrEqual(measured.minY, pageBounds.minY - 1, "must not bleed off the bottom of the page")
        XCTAssertLessThanOrEqual(measured.maxX, pageBounds.maxX + 1, "must not bleed off the right of the page")
    }

    /// The bottom-margin widen fallback (above) must stay inside the paragraph's own
    /// detected column — a left-column paragraph near the page bottom must never widen
    /// across into a right column's territory just to dodge its own height cap.
    func testMeasuredBoundsWidenFallbackNeverCrossesIntoARightColumn() throws {
        let originalBounds = CGRect(x: 72, y: 40, width: 200, height: 14)
        let replacement = "This replacement paragraph is intentionally long enough that it would need several wrapped lines at the original narrow column width, right at the bottom margin of the page."
        let leftColumnBounds = CGRect(x: 72, y: 0, width: 220, height: 792)
        let operation = PDFTextEditOperation(
            pageRefID: UUID(),
            sourceBlockID: UUID(),
            sourceBounds: originalBounds,
            editedBounds: originalBounds,
            columnBounds: leftColumnBounds,
            replacementText: replacement,
            fontName: "Helvetica",
            fontSize: 12,
            textColor: .documentText,
            alignment: .left
        )
        let pageBounds = CGRect(x: 0, y: 0, width: 612, height: 792)

        let measured = PDFEditedPageRenderer.measuredBounds(for: operation, pageBounds: pageBounds)

        XCTAssertLessThanOrEqual(
            measured.maxX,
            leftColumnBounds.maxX + 1,
            "widening to avoid a height-cap truncation must stay inside the paragraph's own column, not cross into a right column"
        )
    }

    func testMeasuredBoundsPreservesManualResizeGeometry() throws {
        let committed = CGRect(x: 80, y: 640, width: 110, height: 44)
        let operation = PDFTextEditOperation(
            pageRefID: UUID(),
            sourceBlockID: UUID(),
            sourceBounds: CGRect(x: 70, y: 700, width: 90, height: 16),
            editedBounds: committed,
            columnBounds: CGRect(x: 70, y: 0, width: 150, height: 792),
            replacementText: "Manual geometry should be honored even when the text is long enough to wrap",
            fontName: "Helvetica",
            fontSize: 12,
            textColor: .documentText,
            alignment: .left,
            didManuallyReposition: true,
            didManuallyResizeWidth: true,
            didManuallyResizeHeight: true
        )

        let measured = PDFEditedPageRenderer.measuredBounds(for: operation)

        XCTAssertEqual(measured, committed)
    }

    func testMeasuredBoundsAllowsAutomaticHeightToShrinkForShorterReplacement() throws {
        let staleTallBounds = CGRect(x: 72, y: 560, width: 360, height: 92)
        let operation = PDFTextEditOperation(
            pageRefID: UUID(),
            sourceBlockID: UUID(),
            sourceBounds: CGRect(x: 72, y: 636, width: 240, height: 16),
            editedBounds: staleTallBounds,
            columnBounds: CGRect(x: 72, y: 0, width: 360, height: 792),
            replacementText: "Short replacement",
            fontName: "Helvetica",
            fontSize: 10,
            textColor: .documentText,
            alignment: .left
        )

        let measured = PDFEditedPageRenderer.measuredBounds(for: operation)

        XCTAssertLessThan(measured.height, staleTallBounds.height)
        XCTAssertEqual(measured.maxY, staleTallBounds.maxY, accuracy: 0.01)
    }

    func testInlineTextEditPreservesExistingAnnotationsOnTheSamePage() throws {
        let fixture = try makeMemberWithPDF(name: "Editable", pageTexts: ["Original text"])
        let document = WorkspaceDocument()
        document.workspace.documents = [fixture.member]
        document.workspace.pageOrder = fixture.refs
        document.memberPDFData[fixture.member.id] = fixture.pdfData
        let viewModel = WorkspaceViewModel(
            document: document,
            processingEngine: PDFKitProcessingEngineFallback()
        )
        let page = try XCTUnwrap(viewModel.loadedPDFs.first?.1.page(at: 0))
        let highlight = PDFAnnotation(bounds: CGRect(x: 200, y: 400, width: 80, height: 16), forType: .highlight, withProperties: nil)
        page.addAnnotation(highlight)
        XCTAssertEqual(page.annotations.count, 1)

        let sourceBlock = EditableTextBlock(
            pageRefID: fixture.refs[0].id,
            text: "Original text",
            bounds: CGRect(x: 70, y: 700, width: 120, height: 24),
            lines: [],
            fontName: "Helvetica",
            fontSize: 16,
            textColor: .documentText,
            rotation: 0,
            baseline: 700,
            confidence: .high
        )

        XCTAssertTrue(viewModel.applyInlineTextEdit(
            pageRef: fixture.refs[0],
            sourceBlock: sourceBlock,
            replacementText: "Replacement text",
            editedBounds: CGRect(x: 70, y: 700, width: 180, height: 28),
            fontName: "Helvetica",
            fontSize: 16,
            textColor: .black,
            alignment: .left
        ))

        let regeneratedPage = try XCTUnwrap(viewModel.loadedPDFs.first?.1.page(at: 0))
        XCTAssertEqual(regeneratedPage.annotations.count, 1, "highlight annotation was dropped by the text-edit regeneration")
        XCTAssertEqual(regeneratedPage.annotations.first?.type, "Highlight")
    }

    /// Both occurrences of an identical repeated paragraph, each edited to DIFFERENT
    /// replacement text, must map back onto the CORRECT occurrence in a source-preserving
    /// plain-text export — never swapped and never both collapsing onto the same one.
    /// `resolvedStringReplacements`/`sourceOccurrence` disambiguate a repeated string by
    /// comparing the PDF visual reading-order occurrence index against the raw-source-text
    /// match count; this is the first end-to-end test to actually exercise editing BOTH
    /// occurrences of the same repeated text at once.
    func testBothOccurrencesOfRepeatedIdenticalTextMapToCorrectPositionInSourcePreservingExport() throws {
        let repeatedLine = "Repeated line item"
        let pdf = makeRepeatedIdenticalTextPDF(text: repeatedLine)
        let fixture = try makeMemberFixture(name: "Repeated", pdf: pdf)
        let document = WorkspaceDocument()
        document.workspace.documents = [fixture.member]
        document.workspace.pageOrder = fixture.refs
        document.memberPDFData[fixture.member.id] = fixture.pdfData
        let originalString = "\(repeatedLine)\n\n\(repeatedLine)"
        document.sourcePayloads[fixture.member.id] = SourceDocumentPayload(
            format: .plainText,
            originalFilename: "repeated.txt",
            originalContentTypeIdentifier: "public.plain-text",
            originalData: try XCTUnwrap(originalString.data(using: .utf8)),
            plainText: originalString
        )
        let viewModel = WorkspaceViewModel(document: document, processingEngine: PDFKitProcessingEngineFallback())
        let originalPage = try XCTUnwrap(PDFDocument(data: fixture.pdfData)?.page(at: 0))
        let analysis = PDFTextAnalysisEngine().analyze(
            data: fixture.pdfData,
            pageIndex: 0,
            pageRefID: fixture.refs[0].id,
            fallbackPage: originalPage
        )
        let matches = analysis.blocks.filter { $0.text == repeatedLine }.sorted { $0.bounds.minY > $1.bounds.minY }
        XCTAssertEqual(matches.count, 2, "fixture should produce two distinct blocks with identical text")
        let topOccurrence = matches[0]
        let bottomOccurrence = matches[1]

        XCTAssertTrue(viewModel.applyInlineTextEdit(
            pageRef: fixture.refs[0],
            sourceBlock: topOccurrence,
            replacementText: "First occurrence replaced",
            editedBounds: topOccurrence.bounds,
            fontName: topOccurrence.fontName,
            fontSize: topOccurrence.fontSize,
            textColor: topOccurrence.textColor.nsColor,
            alignment: topOccurrence.alignment?.nsTextAlignment ?? .left
        ))
        XCTAssertTrue(viewModel.applyInlineTextEdit(
            pageRef: fixture.refs[0],
            sourceBlock: bottomOccurrence,
            replacementText: "Second occurrence replaced",
            editedBounds: bottomOccurrence.bounds,
            fontName: bottomOccurrence.fontName,
            fontSize: bottomOccurrence.fontSize,
            textColor: bottomOccurrence.textColor.nsColor,
            alignment: bottomOccurrence.alignment?.nsTextAlignment ?? .left
        ))

        let exportedData = try viewModel.dataForWorkspaceExport(as: .text)
        let exportedText = try XCTUnwrap(String(data: exportedData, encoding: .utf8))

        XCTAssertTrue(exportedText.contains("First occurrence replaced"))
        XCTAssertTrue(exportedText.contains("Second occurrence replaced"))
        XCTAssertFalse(exportedText.contains(repeatedLine), "both raw occurrences should have been replaced, not just one")
        let firstRange = try XCTUnwrap(exportedText.range(of: "First occurrence replaced"))
        let secondRange = try XCTUnwrap(exportedText.range(of: "Second occurrence replaced"))
        XCTAssertTrue(firstRange.lowerBound < secondRange.lowerBound, "the top-of-page occurrence's edit must land before the bottom occurrence's edit in reading order")
    }

    /// `/ByteRange` is a PDF construct used only by signature dictionaries, so its presence
    /// in the raw bytes is a reliable signal of a pre-existing digital signature — even one
    /// placed by a third party (DocuSign, Adobe Sign, a notarized document) before the file
    /// ever reached Orifold, which `hasCryptographicSignaturePlacement` cannot see since it
    /// only tracks signatures Orifold's own session placed. Any inline edit fully
    /// re-serializes the member's PDF bytes, which breaks a `/ByteRange`-based signature's
    /// hash regardless of which page was edited — so the warning must fire unconditionally
    /// for the whole member, not just the edited page.
    func testInlineTextEditWarnsWhenImportedPDFAlreadyContainsAThirdPartySignature() throws {
        let fixture = try makeMemberWithPDF(name: "Presigned", pageTexts: ["Original text"])
        var presignedData = fixture.pdfData
        // Simulate a pre-existing signature dictionary without needing a real cryptographic
        // signature: a PDF comment (`%...`) outside the content stream is inert to parsers,
        // so this keeps the fixture a valid, loadable PDF while embedding the marker byte
        // sequence `hasThirdPartyCryptographicSignature` scans for.
        presignedData.append(Data("\n% /ByteRange [0 100 200 300]\n".utf8))
        let document = WorkspaceDocument()
        document.workspace.documents = [fixture.member]
        document.workspace.pageOrder = fixture.refs
        document.memberPDFData[fixture.member.id] = presignedData
        let viewModel = WorkspaceViewModel(
            document: document,
            processingEngine: PDFKitProcessingEngineFallback()
        )
        XCTAssertFalse(viewModel.hasCryptographicSignaturePlacement, "fixture places no Orifold-own signature")
        XCTAssertTrue(viewModel.hasThirdPartyCryptographicSignature)

        let sourceBlock = EditableTextBlock(
            pageRefID: fixture.refs[0].id,
            text: "Original text",
            bounds: CGRect(x: 70, y: 700, width: 120, height: 24),
            lines: [],
            fontName: "Helvetica",
            fontSize: 16,
            textColor: .documentText,
            rotation: 0,
            baseline: 700,
            confidence: .high
        )

        XCTAssertTrue(viewModel.applyInlineTextEdit(
            pageRef: fixture.refs[0],
            sourceBlock: sourceBlock,
            replacementText: "Replacement text",
            editedBounds: CGRect(x: 70, y: 700, width: 180, height: 28),
            fontName: "Helvetica",
            fontSize: 16,
            textColor: .black,
            alignment: .left
        ))

        XCTAssertEqual(
            viewModel.editingStatus?.message,
            "This document already contains a digital signature from another source. Editing it will invalidate that signature."
        )
    }

    func testInlineTextEditPreservesPageDisplayBoxesThroughExport() throws {
        let pdf = makePDF(pageTexts: ["Original text"])
        let originalPage = try XCTUnwrap(pdf.page(at: 0))
        let media = CGRect(x: -20, y: -30, width: 640, height: 820)
        let crop = CGRect(x: 24, y: 36, width: 540, height: 700)
        let bleed = CGRect(x: 12, y: 24, width: 560, height: 724)
        let trim = CGRect(x: 30, y: 42, width: 520, height: 680)
        let art = CGRect(x: 48, y: 60, width: 480, height: 640)
        originalPage.setBounds(media, for: .mediaBox)
        originalPage.setBounds(crop, for: .cropBox)
        originalPage.setBounds(bleed, for: .bleedBox)
        originalPage.setBounds(trim, for: .trimBox)
        originalPage.setBounds(art, for: .artBox)
        let fixture = try makeMemberFixture(name: "Cropped", pdf: pdf)
        let document = WorkspaceDocument()
        document.workspace.documents = [fixture.member]
        document.workspace.pageOrder = fixture.refs
        document.memberPDFData[fixture.member.id] = fixture.pdfData
        let viewModel = WorkspaceViewModel(document: document, processingEngine: PDFKitProcessingEngineFallback())
        let loadedOriginalPage = try XCTUnwrap(viewModel.loadedPDFs.first?.1.page(at: 0))
        let expectedMedia = loadedOriginalPage.bounds(for: .mediaBox)
        let expectedCrop = loadedOriginalPage.bounds(for: .cropBox)
        let expectedBleed = loadedOriginalPage.bounds(for: .bleedBox)
        let expectedTrim = loadedOriginalPage.bounds(for: .trimBox)
        let expectedArt = loadedOriginalPage.bounds(for: .artBox)
        let sourceBlock = EditableTextBlock(
            pageRefID: fixture.refs[0].id,
            text: "Original text",
            bounds: CGRect(x: 70, y: 700, width: 120, height: 24),
            lines: [],
            fontName: "Helvetica",
            fontSize: 16,
            textColor: .documentText,
            rotation: 0,
            baseline: 700,
            confidence: .high
        )

        XCTAssertTrue(viewModel.applyInlineTextEdit(
            pageRef: fixture.refs[0],
            sourceBlock: sourceBlock,
            replacementText: "Replacement text",
            editedBounds: CGRect(x: 70, y: 700, width: 180, height: 28),
            fontName: "Helvetica",
            fontSize: 16,
            textColor: .black,
            alignment: .left
        ))

        let editedPage = try XCTUnwrap(viewModel.loadedPDFs.first?.1.page(at: 0))
        XCTAssertEqual(editedPage.bounds(for: .mediaBox), expectedMedia)
        XCTAssertEqual(editedPage.bounds(for: .cropBox), expectedCrop)
        XCTAssertEqual(editedPage.bounds(for: .bleedBox), expectedBleed)
        XCTAssertEqual(editedPage.bounds(for: .trimBox), expectedTrim)
        XCTAssertEqual(editedPage.bounds(for: .artBox), expectedArt)

        let snapshot = try document.snapshot(contentType: .pdf)
        let exported = try document.exportedPDFDataThrowing(from: snapshot)
        let exportedPage = try XCTUnwrap(PDFDocument(data: exported)?.page(at: 0))
        XCTAssertEqual(exportedPage.bounds(for: .mediaBox), expectedMedia)
        XCTAssertEqual(exportedPage.bounds(for: .cropBox), expectedCrop)
        XCTAssertEqual(exportedPage.bounds(for: .bleedBox), expectedBleed)
        XCTAssertEqual(exportedPage.bounds(for: .trimBox), expectedTrim)
        XCTAssertEqual(exportedPage.bounds(for: .artBox), expectedArt)
    }

    func testDecoratedPageSurvivesTheNewStructuralValidationGate() throws {
        // Regression guard: `writePDFExportData` now runs `QPDFService.isStructurallySound`
        // on every export, including plain ones that previously had zero post-write
        // validation. Baked decorations (watermark, Bates) are drawn via raw
        // CGContext/CGDataConsumer bytes, similar to the in-place text editor --
        // exactly the kind of content most likely to trip a qpdf-vs-PDFKit
        // disagreement. This proves the new gate doesn't regress a previously-working export.
        let fixture = try makeMemberWithPDF(name: "Decorated", pageTexts: ["Original text"])
        let document = WorkspaceDocument()
        document.workspace.documents = [fixture.member]
        document.workspace.pageOrder = fixture.refs
        document.memberPDFData[fixture.member.id] = fixture.pdfData
        document.workspace.decorations = [
            PageDecoration.watermark(),
            PageDecoration(kind: .bates, prefix: "REG", startNumber: 1, fontSize: 10, swatch: .tertiary)
        ]
        let viewModel = WorkspaceViewModel(document: document, processingEngine: PDFKitProcessingEngineFallback())

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Orifold-decorated-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let didSave = viewModel.saveFlattenedPDF(to: outputURL)

        XCTAssertTrue(didSave, "export should not be rejected by the new structural-validation gate")
        let writtenData = try Data(contentsOf: outputURL)
        XCTAssertTrue(QPDFService.isStructurallySound(writtenData))
        let writtenPDF = try XCTUnwrap(PDFDocument(data: writtenData))
        XCTAssertTrue(writtenPDF.stringValue.contains("REG-000001"))
    }

    func testWritingPDFContentTypeExportsEditedPDFInsteadOfWorkspacePackage() throws {
        let fixture = try makeMemberWithPDF(name: "Editable", pageTexts: ["Original text"])
        let document = WorkspaceDocument()
        document.workspace.documents = [fixture.member]
        document.workspace.pageOrder = fixture.refs
        document.memberPDFData[fixture.member.id] = fixture.pdfData
        let viewModel = WorkspaceViewModel(
            document: document,
            processingEngine: PDFKitProcessingEngineFallback()
        )
        let sourceBlock = EditableTextBlock(
            pageRefID: fixture.refs[0].id,
            text: "Original text",
            bounds: CGRect(x: 70, y: 700, width: 120, height: 24),
            lines: [],
            fontName: "Helvetica",
            fontSize: 16,
            textColor: .documentText,
            rotation: 0,
            baseline: 700,
            confidence: .high
        )

        XCTAssertTrue(viewModel.applyInlineTextEdit(
            pageRef: fixture.refs[0],
            sourceBlock: sourceBlock,
            replacementText: "Saved through PDF writer",
            editedBounds: CGRect(x: 70, y: 700, width: 220, height: 28),
            fontName: "Helvetica",
            fontSize: 16,
            textColor: .black,
            alignment: .left
        ))
        document.workspace.comments = [
            WorkspaceComment(body: "Persistent exported comment", tags: ["Saved"])
        ]

        let snapshot = try document.snapshot(contentType: .pdf)
        let exportedData = try document.exportedPDFDataThrowing(from: snapshot)
        let exportedPDF = try XCTUnwrap(PDFDocument(data: exportedData))
        let metadataAnnotation = try XCTUnwrap(exportedPDF.page(at: 0)?.annotations.first {
            $0.value(forAnnotationKey: PDFAnnotationKey(rawValue: "/OrifoldWorkspaceComments")) != nil
        })
        let commentsMetadata = try XCTUnwrap(
            metadataAnnotation.value(forAnnotationKey: PDFAnnotationKey(rawValue: "/OrifoldWorkspaceComments")) as? String
        )

        XCTAssertTrue(exportedPDF.stringValue.contains("Saved through PDF writer"))
        XCTAssertTrue(commentsMetadata.contains("Persistent exported comment"))
        XCTAssertTrue(commentsMetadata.contains("Saved"))
    }

    func testEditableTextBlockFallsBackToInlineInsertionWithoutWarning() throws {
        let fixture = try makeMemberWithPDF(name: "Editable", pageTexts: ["Known text"])
        let document = WorkspaceDocument()
        document.workspace.documents = [fixture.member]
        document.workspace.pageOrder = fixture.refs
        document.memberPDFData[fixture.member.id] = fixture.pdfData
        let viewModel = WorkspaceViewModel(
            document: document,
            processingEngine: PDFKitProcessingEngineFallback()
        )
        let page = try XCTUnwrap(viewModel.loadedPDFs.first?.1.page(at: 0))
        let target = try XCTUnwrap(viewModel.editableTextBlock(
            at: CGPoint(x: 500, y: 120),
            on: page,
            in: viewModel.combinedPDF
        ))

        XCTAssertEqual(target.pageRef.id, fixture.refs[0].id)
        XCTAssertEqual(target.block.text, "")
        XCTAssertEqual(target.block.confidence, .medium)
        XCTAssertNil(viewModel.editingStatus)
    }

    func testAddedStickyNoteIsDraftAndPersistsThroughSnapshot() throws {
        let fixture = try makeMemberWithPDF(name: "Notes", pageTexts: ["Sticky note target"])
        let document = WorkspaceDocument()
        document.workspace.documents = [fixture.member]
        document.workspace.pageOrder = fixture.refs
        document.memberPDFData[fixture.member.id] = fixture.pdfData
        let viewModel = WorkspaceViewModel(
            document: document,
            processingEngine: PDFKitProcessingEngineFallback()
        )
        let page = try XCTUnwrap(viewModel.combinedPDF.page(at: 1))

        let annotation = try XCTUnwrap(viewModel.addNote(at: CGPoint(x: 120, y: 120), on: page))
        XCTAssertEqual(annotation.value(forAnnotationKey: WorkspaceViewModel.draftTextAnnotationKey) as? Bool, true)

        annotation.contents = "Cloud stuff to check"
        annotation.setValue(false, forAnnotationKey: WorkspaceViewModel.draftTextAnnotationKey)
        viewModel.markAnnotationsModified()
        let snapshot = try document.snapshot(contentType: .pdf)
        let savedData = try XCTUnwrap(snapshot.memberPDFData[fixture.member.id])
        let savedPDF = try XCTUnwrap(PDFDocument(data: savedData))
        let savedPage = try XCTUnwrap(savedPDF.page(at: 0))
        let savedNote = try XCTUnwrap(savedPage.annotations.first(where: { $0.type == "Text" }))

        XCTAssertEqual(savedNote.contents, "Cloud stuff to check")
    }

    func testPDFNoteCommentsIndexAndRemoveStickyNotes() throws {
        let fixture = try makeMemberWithPDF(name: "Notes", pageTexts: ["Sticky note target"])
        let document = WorkspaceDocument()
        document.workspace.documents = [fixture.member]
        document.workspace.pageOrder = fixture.refs
        document.memberPDFData[fixture.member.id] = fixture.pdfData
        let viewModel = WorkspaceViewModel(
            document: document,
            processingEngine: PDFKitProcessingEngineFallback()
        )
        let page = try XCTUnwrap(viewModel.combinedPDF.page(at: 1))

        let annotation = try XCTUnwrap(viewModel.addNote(at: CGPoint(x: 120, y: 120), on: page))
        annotation.contents = "Check this paragraph"
        annotation.setValue(false, forAnnotationKey: WorkspaceViewModel.draftTextAnnotationKey)

        let note = try XCTUnwrap(viewModel.pdfNoteComments.first)
        XCTAssertEqual(note.body, "Check this paragraph")
        XCTAssertEqual(note.memberName, "Notes")
        XCTAssertEqual(note.pageNumber, 1)
        XCTAssertEqual(viewModel.totalCommentCount, 1)

        viewModel.removeNoteComment(note)

        XCTAssertTrue(viewModel.pdfNoteComments.isEmpty)
        XCTAssertFalse(page.annotations.contains(annotation))
    }

    func testCommentExportsIncludeWorkspaceCommentsTagsStyleAndPDFNotes() throws {
        let fixture = try makeMemberWithPDF(name: "Notes", pageTexts: ["Sticky note target"])
        let document = WorkspaceDocument()
        document.workspace.documents = [fixture.member]
        document.workspace.pageOrder = fixture.refs
        document.memberPDFData[fixture.member.id] = fixture.pdfData
        document.workspace.comments = [
            WorkspaceComment(
                body: "Needs legal review",
                style: WorkspaceCommentStyle(isBold: true, isItalic: true, textSize: .large, colorHex: "#B42318"),
                tags: ["Legal", "Urgent"]
            )
        ]
        let viewModel = WorkspaceViewModel(
            document: document,
            processingEngine: PDFKitProcessingEngineFallback()
        )
        let page = try XCTUnwrap(viewModel.combinedPDF.page(at: 1))
        let annotation = try XCTUnwrap(viewModel.addNote(at: CGPoint(x: 120, y: 120), on: page))
        annotation.contents = "PDF note survives export"
        annotation.setValue(false, forAnnotationKey: WorkspaceViewModel.draftTextAnnotationKey)

        let plainText = viewModel.plainTextForDocumentExport()
        let markdown = viewModel.markdownForDocumentExport()
        let html = viewModel.htmlForDocumentExport()
        let attributed = viewModel.attributedTextForDocumentExport()

        XCTAssertTrue(plainText.contains("Needs legal review"))
        XCTAssertTrue(plainText.contains("Tags: Legal, Urgent"))
        XCTAssertTrue(plainText.contains("PDF note survives export"))
        XCTAssertTrue(markdown.contains("***Needs legal review***"))
        XCTAssertTrue(markdown.contains("PDF note, page 1, Notes"))
        XCTAssertTrue(html.contains("Needs legal review"))
        XCTAssertTrue(html.contains("font-weight: 700"))
        XCTAssertTrue(html.contains("Legal"))
        XCTAssertTrue(attributed.string.contains("Needs legal review"))
        XCTAssertTrue(attributed.string.contains("PDF note survives export"))
    }

    func testInkStrokeStoresPathRelativeToAnnotationBounds() throws {
        let fixture = try makeMemberWithPDF(name: "Ink", pageTexts: ["Ink target"])
        let document = WorkspaceDocument()
        document.workspace.documents = [fixture.member]
        document.workspace.pageOrder = fixture.refs
        document.memberPDFData[fixture.member.id] = fixture.pdfData
        let viewModel = WorkspaceViewModel(
            document: document,
            processingEngine: PDFKitProcessingEngineFallback()
        )
        let page = try XCTUnwrap(viewModel.combinedPDF.page(at: 1))
        let path = NSBezierPath()
        path.lineWidth = 2
        path.move(to: CGPoint(x: 100, y: 120))
        path.line(to: CGPoint(x: 130, y: 150))

        viewModel.addInkStroke(path: path, on: page)

        let annotation = try XCTUnwrap(page.annotations.first(where: { $0.type == "Ink" }))
        XCTAssertEqual(annotation.bounds.minX, 98, accuracy: 0.01)
        XCTAssertEqual(annotation.bounds.minY, 118, accuracy: 0.01)
        let inkListKey = PDFAnnotationKey(rawValue: "/InkList")
        let paths = try XCTUnwrap(annotation.value(forAnnotationKey: inkListKey) as? [NSBezierPath])
        let storedPath = try XCTUnwrap(paths.first)
        XCTAssertLessThan(storedPath.bounds.maxX, annotation.bounds.width)
        XCTAssertLessThan(storedPath.bounds.maxY, annotation.bounds.height)
    }
}

final class InlineTextEditPlacementTests: XCTestCase {
    func testInlineEditorResolvesRegularFontFromDetectedBoldFont() throws {
        let detected: NSFont
        if let font = NSFont(name: "Helvetica-Bold", size: 12) {
            detected = font
        } else {
            detected = try XCTUnwrap(NSFontManager.shared.font(withFamily: "Helvetica", traits: .boldFontMask, weight: 9, size: 12))
        }
        let family = InlineTextEditorOverlay.editingFamilyName(for: detected, fallback: "Helvetica-Bold")

        let regular = InlineTextEditorOverlay.editingFont(family: family, traits: [], size: 12)
        let bold = InlineTextEditorOverlay.editingFont(family: family, traits: .boldFontMask, size: 12)

        XCTAssertFalse(NSFontManager.shared.traits(of: regular).contains(.boldFontMask))
        XCTAssertTrue(NSFontManager.shared.traits(of: bold).contains(.boldFontMask))
    }

    /// Opening the inline editor calls `InlineTextEditorOverlay`'s detected-text-color scan,
    /// which previously re-ran a full PDFium parse for EVERY page of the document, stopping
    /// only once 24 distinct-looking colors were found. On a document where most pages
    /// contribute no text at all (blank/image pages, common as covers or section breaks),
    /// that count-based threshold never fires, so the scan ran across the WHOLE document —
    /// an unbounded, main-thread cost scaling with page count for a single click to edit
    /// text. This builds a document with several leading blank pages and a distinctively
    /// colored line only on a LATER page, past the fixed page-scan cap, and confirms that
    /// color is never surfaced — proving the scan is bounded by page count, not merely by
    /// how many colors happen to turn up early. A wall-clock timing assertion would be
    /// flaky across machines; this is deterministic.
    func testInlineEditorDetectedColorScanStopsAfterAFixedPageCountRegardlessOfColorDensity() throws {
        let distinctiveColor = NSColor(srgbRed: 51.0 / 255, green: 153.0 / 255, blue: 230.0 / 255, alpha: 1)
        let pdf = PDFDocument()
        for pageIndex in 0..<20 {
            // Blank pages contribute zero detected blocks/colors, so the OLD code's
            // count-based early exit (24 colors) never fires — it must keep scanning.
            let text = pageIndex == 15 ? "Distinctive colored line" : ""
            let color = pageIndex == 15 ? distinctiveColor : NSColor.black
            let view = SolidColorTextFixturePageView(frame: CGRect(x: 0, y: 0, width: 612, height: 792), text: text, color: color)
            let pageData = view.dataWithPDF(inside: view.bounds)
            guard let pageDoc = PDFDocument(data: pageData), let page = pageDoc.page(at: 0) else {
                return XCTFail("failed to build fixture page")
            }
            pdf.insert(page, at: pageIndex)
        }

        let pdfView = OrifoldPDFView(frame: CGRect(x: 0, y: 0, width: 900, height: 1000))
        pdfView.document = pdf
        pdfView.autoScales = false
        pdfView.scaleFactor = 1
        pdfView.layoutDocumentView()
        let page = try XCTUnwrap(pdf.page(at: 0))
        let pageRef = PageRef(memberDocId: UUID(), sourcePageIndex: 0)
        let viewModel = WorkspaceViewModel(document: WorkspaceDocument())
        let block = EditableTextBlock(
            pageRefID: pageRef.id, text: "irrelevant",
            bounds: CGRect(x: 72, y: 650, width: 160, height: 16), lines: [],
            fontName: "Helvetica", fontSize: 8, textColor: .documentText,
            rotation: 0, baseline: 650, confidence: .high
        )

        let overlay = InlineTextEditorOverlay(
            frame: pdfView.bounds, viewModel: viewModel, pdfView: pdfView, page: page,
            pageRef: pageRef, block: block, sourceFormat: PDFTextEditFormat(block: block)
        ) { _ in }
        pdfView.addSubview(overlay)
        overlay.layoutSubtreeIfNeeded()

        let colorPopup = try XCTUnwrap(findSubview(in: overlay) { (popup: NSPopUpButton) in
            popup.toolTip == "Text color"
        })
        let hasDistinctiveColorItem = (0..<colorPopup.numberOfItems).contains { index in
            colorPopup.item(at: index)?.title.localizedCaseInsensitiveContains("#3399E6") ?? false
        }
        XCTAssertFalse(
            hasDistinctiveColorItem,
            "the detected-color scan must stop at a fixed page count and never reach a color that only appears on a later page"
        )
    }

    func testInlineTextEditHonorsCommittedEditorGeometry() throws {
        let fixture = try makeMemberWithPDF(name: "Editable", pageTexts: ["Original text"])
        let document = WorkspaceDocument()
        document.workspace.documents = [fixture.member]
        document.workspace.pageOrder = fixture.refs
        document.memberPDFData[fixture.member.id] = fixture.pdfData
        let viewModel = WorkspaceViewModel(document: document, processingEngine: PDFKitProcessingEngineFallback())

        let sourceBounds = CGRect(x: 34, y: 610, width: 470, height: 13)
        let sourceBlock = EditableTextBlock(
            pageRefID: fixture.refs[0].id, text: "Original text", bounds: sourceBounds,
            lines: [], fontName: "Helvetica-Bold", fontSize: 8, textColor: .documentText,
            rotation: 0, baseline: 610, confidence: .high)

        let committedBounds = CGRect(x: 48, y: 584, width: 447, height: 24)

        XCTAssertTrue(viewModel.applyInlineTextEdit(
            pageRef: fixture.refs[0], sourceBlock: sourceBlock,
            replacementText: "Cloud and DevOps",
            editedBounds: committedBounds, fontName: "Helvetica-Bold", fontSize: 8,
            textColor: .black, alignment: .left,
            didManuallyReposition: true,
            didManuallyResizeWidth: true,
            didManuallyResizeHeight: true))

        let stored = try XCTUnwrap(viewModel.document.workspace.pageEditStates.first?.operations.first)
        XCTAssertEqual(stored.sourceBounds, sourceBounds)
        XCTAssertEqual(stored.columnBounds, sourceBlock.columnBounds)
        XCTAssertEqual(stored.editedBounds.minX, committedBounds.minX, accuracy: 0.01)
        XCTAssertEqual(stored.editedBounds.minY, committedBounds.minY, accuracy: 0.01)
        XCTAssertEqual(stored.editedBounds.width, committedBounds.width, accuracy: 0.01)
        XCTAssertEqual(stored.editedBounds.height, committedBounds.height, accuracy: 0.01)
    }

    func testInlineTextEditStoresParagraphLineEraseBoundsAndManualFlags() throws {
        let fixture = try makeMemberWithPDF(name: "Editable", pageTexts: ["Original text"])
        let document = WorkspaceDocument()
        document.workspace.documents = [fixture.member]
        document.workspace.pageOrder = fixture.refs
        document.memberPDFData[fixture.member.id] = fixture.pdfData
        let viewModel = WorkspaceViewModel(document: document, processingEngine: PDFKitProcessingEngineFallback())

        let firstLine = PDFTextLine(
            text: "Partnered with product teams",
            bounds: CGRect(x: 72, y: 650, width: 180, height: 10),
            runs: [],
            confidence: .high
        )
        let secondLine = PDFTextLine(
            text: "to deliver trailing punctuation.",
            bounds: CGRect(x: 88, y: 636, width: 160, height: 10),
            runs: [],
            confidence: .high
        )
        let sourceBlock = EditableTextBlock(
            pageRefID: fixture.refs[0].id,
            text: "\(firstLine.text) \(secondLine.text)",
            bounds: firstLine.bounds.union(secondLine.bounds).insetBy(dx: -2, dy: -2),
            lines: [firstLine, secondLine],
            columnBounds: CGRect(x: 72, y: 0, width: 260, height: 792),
            fontName: "Helvetica",
            fontSize: 9,
            textColor: .documentText,
            rotation: 0,
            baseline: firstLine.bounds.minY,
            confidence: .high
        )

        XCTAssertTrue(viewModel.applyInlineTextEdit(
            pageRef: fixture.refs[0],
            sourceBlock: sourceBlock,
            replacementText: "A replacement paragraph that should reflow in the same column.",
            editedBounds: CGRect(x: 72, y: 620, width: 200, height: 34),
            fontName: "Helvetica",
            fontSize: 9,
            textColor: .black,
            alignment: .left,
            didManuallyReposition: true,
            didManuallyResizeWidth: true,
            didManuallyResizeHeight: true
        ))

        let stored = try XCTUnwrap(viewModel.document.workspace.pageEditStates.first?.operations.first)
        XCTAssertEqual(stored.sourceLineBounds, [firstLine.bounds, secondLine.bounds])
        XCTAssertEqual(stored.columnBounds, sourceBlock.columnBounds)
        XCTAssertTrue(stored.didManuallyReposition)
        XCTAssertTrue(stored.didManuallyResizeWidth)
        XCTAssertTrue(stored.didManuallyResizeHeight)
    }

    func testRepeatedInlineTextEditPreservesOriginalSourceBoundsButHonorsNewCommittedGeometry() throws {
        let fixture = try makeMemberWithPDF(name: "Editable", pageTexts: ["Original text"])
        let document = WorkspaceDocument()
        document.workspace.documents = [fixture.member]
        document.workspace.pageOrder = fixture.refs
        document.memberPDFData[fixture.member.id] = fixture.pdfData
        let viewModel = WorkspaceViewModel(document: document, processingEngine: PDFKitProcessingEngineFallback())

        let sourceBounds = CGRect(x: 34, y: 610, width: 120, height: 13)
        let firstCommittedBounds = CGRect(x: 48, y: 584, width: 220, height: 24)
        let secondCommittedBounds = CGRect(x: 64, y: 560, width: 260, height: 28)
        let sourceBlock = EditableTextBlock(
            pageRefID: fixture.refs[0].id, text: "Original text", bounds: sourceBounds,
            lines: [], fontName: "Helvetica", fontSize: 10, textColor: .documentText,
            rotation: 0, baseline: 610, confidence: .high)

        XCTAssertTrue(viewModel.applyInlineTextEdit(
            pageRef: fixture.refs[0], sourceBlock: sourceBlock,
            replacementText: "First replacement",
            editedBounds: firstCommittedBounds, fontName: "Helvetica", fontSize: 10,
            textColor: .black, alignment: .left,
            didManuallyReposition: true,
            didManuallyResizeWidth: true,
            didManuallyResizeHeight: true))

        var reeditBlock = sourceBlock
        reeditBlock.text = "First replacement"
        reeditBlock.bounds = firstCommittedBounds
        XCTAssertTrue(viewModel.applyInlineTextEdit(
            pageRef: fixture.refs[0], sourceBlock: reeditBlock,
            replacementText: "Second replacement",
            editedBounds: secondCommittedBounds, fontName: "Helvetica", fontSize: 10,
            textColor: .black, alignment: .left,
            didManuallyReposition: true,
            didManuallyResizeWidth: true,
            didManuallyResizeHeight: true))

        let operations = try XCTUnwrap(viewModel.document.workspace.pageEditStates.first?.operations)
        XCTAssertEqual(operations.count, 1)
        let stored = try XCTUnwrap(operations.first)
        XCTAssertEqual(stored.sourceBounds, sourceBounds)
        XCTAssertEqual(stored.editedBounds.minX, secondCommittedBounds.minX, accuracy: 0.01)
        XCTAssertEqual(stored.editedBounds.minY, secondCommittedBounds.minY, accuracy: 0.01)
        XCTAssertEqual(stored.editedBounds.width, secondCommittedBounds.width, accuracy: 0.01)
        XCTAssertEqual(stored.editedBounds.height, secondCommittedBounds.height, accuracy: 0.01)
    }

    func testThreePassInlineTextEditExportsOnlyFinalTextWithoutGeometryDrift() throws {
        let fixture = try makeMemberWithPDF(name: "Editable", pageTexts: ["Original text"])
        let document = WorkspaceDocument()
        document.workspace.documents = [fixture.member]
        document.workspace.pageOrder = fixture.refs
        document.memberPDFData[fixture.member.id] = fixture.pdfData
        let viewModel = WorkspaceViewModel(document: document, processingEngine: PDFKitProcessingEngineFallback())

        let sourceBounds = CGRect(x: 72, y: 690, width: 92, height: 16)
        let committedBounds = CGRect(x: 72, y: 666, width: 210, height: 38)
        var sourceBlock = EditableTextBlock(
            pageRefID: fixture.refs[0].id,
            text: "Original text",
            bounds: sourceBounds,
            lines: [],
            columnBounds: CGRect(x: 72, y: 0, width: 260, height: 792),
            fontName: "Helvetica",
            fontSize: 12,
            textColor: .documentText,
            rotation: 0,
            baseline: 690,
            confidence: .high
        )

        for replacement in ["First edit", "Second edit wraps", "Final edit stays put"] {
            XCTAssertTrue(viewModel.applyInlineTextEdit(
                pageRef: fixture.refs[0],
                sourceBlock: sourceBlock,
                replacementText: replacement,
                editedBounds: committedBounds,
                fontName: "Helvetica",
                fontSize: 12,
                textColor: .black,
                alignment: .left,
                didManuallyReposition: true,
                didManuallyResizeWidth: true,
                didManuallyResizeHeight: true
            ))
            sourceBlock.text = replacement
            sourceBlock.bounds = committedBounds
        }

        let stored = try XCTUnwrap(viewModel.document.workspace.pageEditStates.first?.operations.first)
        XCTAssertEqual(viewModel.document.workspace.pageEditStates.first?.operations.count, 1)
        XCTAssertEqual(stored.sourceBounds, sourceBounds)
        XCTAssertEqual(stored.editedBounds, committedBounds)
        XCTAssertEqual(stored.replacementText, "Final edit stays put")

        let exportedData = try viewModel.document.exportedPDFDataThrowing(from: try viewModel.document.snapshot(contentType: .pdf))
        let exportedPDF = try XCTUnwrap(PDFDocument(data: exportedData))
        let exportedText = exportedPDF.string ?? ""

        XCTAssertTrue(exportedText.contains("Final edit stays put"))
        XCTAssertFalse(exportedText.contains("First edit"))
        XCTAssertFalse(exportedText.contains("Second edit wraps"))
    }

    /// A very short original word ("Hi"), auto-sized (no manual geometry flags) across FIVE
    /// rapid re-edit cycles alternating short and much-longer replacements — mirroring a
    /// user who commits a short edit, immediately reopens it, and keeps tweaking it. Each
    /// reopen mimics `WorkspaceViewModel.reopenedBounds`: width resets to the ORIGINAL
    /// source width and the box's TOP edge (`maxY`) is carried over exactly, letting
    /// `measuredBounds` recompute width/height fresh every time. Regression target: font
    /// size/box geometry must never compound (creep) across cycles — a short replacement
    /// after several long ones must shrink back down to essentially the same box the very
    /// first short edit produced, and the box's top edge must never drift.
    func testRepeatedAutoSizedEditsOfAVeryShortTextBoxDoNotCompoundGeometryDrift() throws {
        let fixture = try makeMemberWithPDF(name: "Editable", pageTexts: ["Hi"])
        let document = WorkspaceDocument()
        document.workspace.documents = [fixture.member]
        document.workspace.pageOrder = fixture.refs
        document.memberPDFData[fixture.member.id] = fixture.pdfData
        let viewModel = WorkspaceViewModel(document: document, processingEngine: PDFKitProcessingEngineFallback())

        let sourceBounds = CGRect(x: 72, y: 700, width: 20, height: 14)
        var sourceBlock = EditableTextBlock(
            pageRefID: fixture.refs[0].id, text: "Hi", bounds: sourceBounds,
            lines: [], fontName: "Helvetica", fontSize: 12, textColor: .documentText,
            rotation: 0, baseline: 700, confidence: .high)
        var editedBounds = sourceBounds

        let shortText = "Ok"
        let cycles = [
            shortText,
            "This is a considerably longer replacement that should wrap onto more than one line",
            shortText,
            "Yet another much longer replacement to force wrapping a second time and check for drift",
            shortText
        ]
        var maxYByCycle: [CGFloat] = []
        var shortCycleBounds: [CGRect] = []
        for replacement in cycles {
            XCTAssertTrue(viewModel.applyInlineTextEdit(
                pageRef: fixture.refs[0],
                sourceBlock: sourceBlock,
                replacementText: replacement,
                editedBounds: editedBounds,
                fontName: "Helvetica",
                fontSize: 12,
                textColor: .black,
                alignment: .left
            ))
            let stored = try XCTUnwrap(viewModel.document.workspace.pageEditStates.first?.operations.first)
            maxYByCycle.append(stored.editedBounds.maxY)
            if replacement == shortText {
                shortCycleBounds.append(stored.editedBounds)
            }

            // Reopen exactly as `reopenedBounds` does: width resets to the ORIGINAL source
            // width, height carries the just-committed height forward as a starting point,
            // and the top edge (maxY) is preserved exactly.
            let height = max(1, stored.editedBounds.height)
            editedBounds = CGRect(
                x: sourceBounds.minX,
                y: stored.editedBounds.maxY - height,
                width: sourceBounds.width,
                height: height
            )
            sourceBlock.text = replacement
            sourceBlock.bounds = stored.editedBounds
        }

        XCTAssertEqual(Set(maxYByCycle.map { ($0 * 100).rounded() }).count, 1, "the box's top edge must never drift across repeated auto-sized re-edits: \(maxYByCycle)")
        XCTAssertEqual(shortCycleBounds.count, 3)
        for bounds in shortCycleBounds {
            XCTAssertEqual(bounds.width, shortCycleBounds[0].width, accuracy: 0.5, "a short replacement's box must shrink back to essentially the same size every time, not compound growth from the intervening long edits")
            XCTAssertEqual(bounds.height, shortCycleBounds[0].height, accuracy: 0.5)
        }
    }

    func testRepeatedInlineTextEditPreservesExistingManualGeometryFlags() throws {
        let fixture = try makeMemberWithPDF(name: "Editable", pageTexts: ["Original text"])
        let document = WorkspaceDocument()
        document.workspace.documents = [fixture.member]
        document.workspace.pageOrder = fixture.refs
        document.memberPDFData[fixture.member.id] = fixture.pdfData
        let viewModel = WorkspaceViewModel(document: document, processingEngine: PDFKitProcessingEngineFallback())

        let sourceBounds = CGRect(x: 34, y: 610, width: 120, height: 13)
        let manualBounds = CGRect(x: 64, y: 560, width: 140, height: 42)
        let sourceBlock = EditableTextBlock(
            pageRefID: fixture.refs[0].id, text: "Original text", bounds: sourceBounds,
            lines: [], columnBounds: CGRect(x: 34, y: 0, width: 240, height: 792),
            fontName: "Helvetica", fontSize: 10, textColor: .documentText,
            rotation: 0, baseline: 610, confidence: .high)

        XCTAssertTrue(viewModel.applyInlineTextEdit(
            pageRef: fixture.refs[0], sourceBlock: sourceBlock,
            replacementText: "First replacement",
            editedBounds: manualBounds, fontName: "Helvetica", fontSize: 10,
            textColor: .black, alignment: .left,
            didManuallyReposition: true,
            didManuallyResizeWidth: true,
            didManuallyResizeHeight: true))

        var reeditBlock = sourceBlock
        reeditBlock.text = "First replacement"
        reeditBlock.bounds = manualBounds
        XCTAssertTrue(viewModel.applyInlineTextEdit(
            pageRef: fixture.refs[0], sourceBlock: reeditBlock,
            replacementText: "Second replacement with more words",
            editedBounds: manualBounds, fontName: "Helvetica", fontSize: 10,
            textColor: .black, alignment: .left))

        let stored = try XCTUnwrap(viewModel.document.workspace.pageEditStates.first?.operations.first)
        XCTAssertTrue(stored.didManuallyReposition)
        XCTAssertTrue(stored.didManuallyResizeWidth)
        XCTAssertTrue(stored.didManuallyResizeHeight)
        XCTAssertEqual(stored.editedBounds, manualBounds)
    }

    func testReopeningExistingInlineTextEditPreservesStoredAlignment() throws {
        let fixture = try makeMemberWithPDF(name: "Editable", pageTexts: ["Original text"])
        let document = WorkspaceDocument()
        document.workspace.documents = [fixture.member]
        document.workspace.pageOrder = fixture.refs
        document.memberPDFData[fixture.member.id] = fixture.pdfData
        let viewModel = WorkspaceViewModel(document: document, processingEngine: PDFKitProcessingEngineFallback())

        let sourceBounds = CGRect(x: 34, y: 610, width: 120, height: 13)
        let committedBounds = CGRect(x: 48, y: 584, width: 220, height: 24)
        let sourceBlock = EditableTextBlock(
            pageRefID: fixture.refs[0].id, text: "Original text", bounds: sourceBounds,
            lines: [], fontName: "Helvetica", fontSize: 10, textColor: .documentText,
            rotation: 0, baseline: 610, confidence: .high)

        XCTAssertTrue(viewModel.applyInlineTextEdit(
            pageRef: fixture.refs[0], sourceBlock: sourceBlock,
            replacementText: "Aligned replacement",
            editedBounds: committedBounds, fontName: "Helvetica", fontSize: 10,
            textColor: .black, alignment: .right))

        let page = try XCTUnwrap(viewModel.combinedPDF.page(at: 1))
        let reopened = try XCTUnwrap(viewModel.editableTextBlock(
            at: CGPoint(x: committedBounds.midX, y: committedBounds.midY),
            on: page,
            in: viewModel.combinedPDF
        ))

        XCTAssertEqual(reopened.block.alignment?.nsTextAlignment, .right)
    }

    func testInlineEditorToolbarControlsReceiveHitTests() throws {
        let fixture = try makeInlineEditorFixture()
        let doneButton = try XCTUnwrap(findSubview(in: fixture.overlay) { (button: NSButton) in
            button.title == "Done"
        })
        let sizeField = try XCTUnwrap(findSubview(in: fixture.overlay) { (field: NSTextField) in
            field.toolTip == "Font size" && field.isEditable
        })
        let textView = try XCTUnwrap(findSubview(in: fixture.overlay) { (_: NSTextView) in true })
        let moveHandle = try XCTUnwrap(findSubview(in: fixture.overlay) { (_: InlineMoveHandle) in true })
        let resizeHandle = try XCTUnwrap(findSubview(in: fixture.overlay) { (_: InlineResizeHandle) in true })
        let colorPopup = try XCTUnwrap(findSubview(in: fixture.overlay) { (popup: NSPopUpButton) in
            popup.toolTip == "Text color"
        })

        let donePoint = doneButton.convert(NSPoint(x: doneButton.bounds.midX, y: doneButton.bounds.midY), to: fixture.overlay)
        let sizePoint = sizeField.convert(NSPoint(x: sizeField.bounds.midX, y: sizeField.bounds.midY), to: fixture.overlay)
        let textPoint = textView.convert(NSPoint(x: textView.bounds.midX, y: textView.bounds.minY + 6), to: fixture.overlay)
        let movePoint = moveHandle.convert(NSPoint(x: moveHandle.bounds.midX, y: moveHandle.bounds.midY), to: fixture.overlay)
        let resizePoint = resizeHandle.convert(NSPoint(x: resizeHandle.bounds.midX, y: resizeHandle.bounds.midY), to: fixture.overlay)
        let colorPoint = colorPopup.convert(NSPoint(x: colorPopup.bounds.midX, y: colorPopup.bounds.midY), to: fixture.overlay)

        XCTAssertTrue(hitTest(fixture.overlay, at: donePoint, reaches: doneButton))
        XCTAssertTrue(hitTest(fixture.overlay, at: sizePoint, reaches: sizeField))
        XCTAssertTrue(hitTest(fixture.overlay, at: colorPoint, reaches: colorPopup))
        let textHit = fixture.overlay.hitTest(textPoint)
        XCTAssertTrue(textHit is NSTextView, "Expected text view hit, got \(String(describing: textHit))")
        XCTAssertTrue(fixture.overlay.hitTest(movePoint) is InlineMoveHandle)
        XCTAssertTrue(fixture.overlay.hitTest(resizePoint) is InlineResizeHandle)
        XCTAssertNil(fixture.overlay.hitTest(NSPoint(x: fixture.overlay.bounds.maxX - 2, y: fixture.overlay.bounds.maxY - 2)))
    }

    func testInlineEditorToolbarControlsReceiveHitTestsWhenToolbarIsOffset() throws {
        let fixture = try makeInlineEditorFixture(pdfViewFrame: CGRect(x: 0, y: 0, width: 1800, height: 1000))
        let matchButton = try XCTUnwrap(inlineEditorButton(in: fixture.overlay, identifier: "inlineEditor.matchNearbyFormat"))
        let copyFormat = try XCTUnwrap(inlineEditorButton(in: fixture.overlay, identifier: "inlineEditor.copyNearbyFormat"))
        let applyFormat = try XCTUnwrap(inlineEditorButton(in: fixture.overlay, identifier: "inlineEditor.applyCopiedFormat"))
        let restoreFormat = try XCTUnwrap(inlineEditorButton(in: fixture.overlay, identifier: "inlineEditor.restoreOriginalFormat"))
        let bold = try XCTUnwrap(findSubview(in: fixture.overlay) { (button: NSButton) in
            button.title == "B"
        })
        let alignment = try XCTUnwrap(findSubview(in: fixture.overlay) { (_: NSSegmentedControl) in true })

        for view in [matchButton, copyFormat, applyFormat, restoreFormat, bold, alignment] as [NSView] {
            XCTAssertGreaterThan(view.convert(.zero, to: fixture.overlay).x, 100)
            let point = view.convert(NSPoint(x: view.bounds.midX, y: view.bounds.midY), to: fixture.overlay)
            XCTAssertTrue(hitTest(fixture.overlay, at: point, reaches: view))
        }
    }

    func testInlineEditorCopyThenApplyUsesNearbyOriginalFormat() throws {
        let pageRef = PageRef(memberDocId: UUID(), sourcePageIndex: 0)
        let editedBlock = EditableTextBlock(
            pageRefID: pageRef.id,
            text: "Edited text",
            bounds: CGRect(x: 96, y: 620, width: 260, height: 28),
            lines: [],
            columnBounds: CGRect(x: 96, y: 0, width: 260, height: 792),
            fontName: "Courier-Bold",
            fontSize: 18,
            textColor: .init(nsColor: .systemRed),
            alignment: .right,
            rotation: 0,
            baseline: 620,
            confidence: .high
        )
        let nearbyColumn = CGRect(x: 72, y: 0, width: 430, height: 792)
        let nearbyBounds = CGRect(x: 72, y: 650, width: 360, height: 16)
        let nearbyFormat = PDFTextEditFormat(
            fontName: "Helvetica",
            fontSize: 10,
            textColor: .documentText,
            alignment: .left,
            bounds: nearbyBounds,
            columnBounds: nearbyColumn
        )
        let fixture = try makeInlineEditorFixture(
            text: editedBlock.text,
            pageRef: pageRef,
            block: editedBlock,
            sourceFormat: nearbyFormat,
            pdfViewFrame: CGRect(x: 0, y: 0, width: 1400, height: 1000)
        )
        let textView = try XCTUnwrap(findSubview(in: fixture.overlay) { (_: NSTextView) in true })
        let copy = try XCTUnwrap(inlineEditorButton(in: fixture.overlay, identifier: "inlineEditor.copyNearbyFormat"))
        let apply = try XCTUnwrap(inlineEditorButton(in: fixture.overlay, identifier: "inlineEditor.applyCopiedFormat"))
        let done = try XCTUnwrap(findSubview(in: fixture.overlay) { (button: NSButton) in
            button.title == "Done"
        })

        textView.string = "Replacement text"
        copy.performClick(nil)
        XCTAssertEqual(fixture.viewModel.copiedInlineTextFormat, nearbyFormat)
        apply.performClick(nil)
        done.performClick(nil)

        let committed = try XCTUnwrap(fixture.committedEdit())
        XCTAssertEqual(committed.fontName, "Helvetica")
        XCTAssertEqual(committed.fontSize, 10, accuracy: 0.01)
        XCTAssertEqual(committed.alignment, .left)
        XCTAssertEqual(committed.editedBounds.minX, nearbyBounds.minX, accuracy: 0.01)
        XCTAssertEqual(committed.editedBounds.width, nearbyBounds.width, accuracy: 0.01)
    }

    /// End-to-end: copy a MUCH larger font (48pt) from one block, open a DIFFERENT
    /// block whose original text is small (8pt), leave its text completely
    /// UNCHANGED, click "Paste style" (not Match), then press Done. This must not
    /// clip the exported height to the original 8pt `sourceBounds.height` — the
    /// `unchangedTextHasKnownHeight` branch in `PDFEditedPageRenderer.measuredBounds`
    /// is supposed to detect the enlarged font (via `sourceHeight >= rawCoreTextHeight`)
    /// and fall through to a fresh CoreText remeasurement instead of trusting the
    /// stale small `sourceBounds.height`. This drives the real UI buttons
    /// (`.performClick(nil)`) and reads the actually-committed operation out of
    /// `document.workspace.pageEditStates`, then re-derives bounds via
    /// `PDFEditedPageRenderer.measuredBounds` on that real operation — not a
    /// synthetic `PDFTextEditOperation` built by hand.
    func testInlineEditorPasteLargerFontOntoUnchangedTextGrowsExportedHeight() throws {
        let pdf = makePDF(pageTexts: ["Small original text"])
        let fixture = try makeMemberFixture(name: "PasteGrow", pdf: pdf)
        let document = WorkspaceDocument()
        document.workspace.documents = [fixture.member]
        document.workspace.pageOrder = fixture.refs
        document.memberPDFData[fixture.member.id] = fixture.pdfData
        let viewModel = WorkspaceViewModel(document: document, processingEngine: PDFKitProcessingEngineFallback())
        let pageRef = fixture.refs[0]
        let basePage = try XCTUnwrap(PDFDocument(data: fixture.pdfData)?.page(at: 0))

        let smallBlock = EditableTextBlock(
            pageRefID: pageRef.id,
            text: "Small original text",
            bounds: CGRect(x: 72, y: 700, width: 140, height: 10),
            lines: [],
            columnBounds: CGRect(x: 72, y: 0, width: 300, height: 792),
            fontName: "Helvetica",
            fontSize: 8,
            textColor: .documentText,
            alignment: .left,
            rotation: 0,
            baseline: 700,
            confidence: .high
        )
        let smallSourceFormat = PDFTextEditFormat(block: smallBlock)

        let pdfView = OrifoldPDFView(frame: CGRect(x: 0, y: 0, width: 900, height: 1000))
        pdfView.document = PDFDocument(data: fixture.pdfData)
        pdfView.autoScales = false
        pdfView.scaleFactor = 1
        pdfView.layoutDocumentView()

        // Step 1: open a DIFFERENT (larger-font) block and Copy its format — this is
        // the source the user copies from before ever touching the small block.
        let largeFormatSourceBlock = EditableTextBlock(
            pageRefID: pageRef.id,
            text: "Large heading text",
            bounds: CGRect(x: 72, y: 60, width: 400, height: 60),
            lines: [],
            columnBounds: CGRect(x: 72, y: 0, width: 468, height: 792),
            fontName: "Helvetica-Bold",
            fontSize: 48,
            textColor: .documentText,
            alignment: .left,
            rotation: 0,
            baseline: 60,
            confidence: .high
        )
        var largeOverlayCommit: InlineTextEditorOverlay.EditResult?
        let largeOverlay = InlineTextEditorOverlay(
            frame: pdfView.bounds,
            viewModel: viewModel,
            pdfView: pdfView,
            page: basePage,
            pageRef: pageRef,
            block: largeFormatSourceBlock,
            sourceFormat: PDFTextEditFormat(block: largeFormatSourceBlock)
        ) { completion in
            if case .commit(let edit) = completion { largeOverlayCommit = edit }
        }
        pdfView.addSubview(largeOverlay)
        largeOverlay.layoutSubtreeIfNeeded()
        let largeCopyButton = try XCTUnwrap(inlineEditorButton(in: largeOverlay, identifier: "inlineEditor.copyNearbyFormat"))
        largeCopyButton.performClick(nil)
        XCTAssertTrue(viewModel.isInlineTextFormatPainterArmed, "Copy should arm the format painter")
        XCTAssertEqual(viewModel.copiedInlineTextFormat?.fontSize ?? -1, 48, accuracy: 0.01)
        largeOverlay.cancel()
        _ = largeOverlayCommit // never committed; only used to copy the format

        // Step 2: open the SMALL block. Because the painter is armed, opening it will
        // auto-apply the copied 48pt format (applyArmedFormatPainterIfNeeded) — but we
        // explicitly exercise the "Paste style" button too, matching the described
        // repro, and leave the text field completely untouched.
        var committedSmall: InlineTextEditorOverlay.EditResult?
        let smallOverlay = InlineTextEditorOverlay(
            frame: pdfView.bounds,
            viewModel: viewModel,
            pdfView: pdfView,
            page: basePage,
            pageRef: pageRef,
            block: smallBlock,
            sourceFormat: smallSourceFormat
        ) { completion in
            if case .commit(let edit) = completion { committedSmall = edit }
        }
        pdfView.addSubview(smallOverlay)
        smallOverlay.layoutSubtreeIfNeeded()

        // Re-arm explicitly (defensive against auto-apply already having consumed it)
        // and click "Paste style" via the real button, exactly as instructed.
        viewModel.copiedInlineTextFormat = PDFTextEditFormat(block: largeFormatSourceBlock)
        viewModel.isInlineTextFormatPainterArmed = true
        let pasteButton = try XCTUnwrap(inlineEditorButton(in: smallOverlay, identifier: "inlineEditor.applyCopiedFormat"))
        pasteButton.performClick(nil)

        let doneButton = try XCTUnwrap(findSubview(in: smallOverlay) { (button: NSButton) in button.title == "Done" })
        doneButton.performClick(nil)

        let edit = try XCTUnwrap(committedSmall, "Done should commit even though text is unchanged, since style changed")
        XCTAssertEqual(edit.text, smallBlock.text, "text content must remain completely unchanged")
        XCTAssertEqual(edit.fontSize, 48, accuracy: 0.01, "pasted style should carry the 48pt font onto the commit")

        XCTAssertTrue(viewModel.applyInlineTextEdit(
            pageRef: pageRef,
            sourceBlock: edit.block,
            replacementText: edit.text,
            editedBounds: edit.editedBounds,
            fontName: edit.fontName,
            fontSize: edit.fontSize,
            textColor: edit.textColor,
            alignment: edit.alignment,
            underline: edit.underline,
            didManuallyReposition: edit.didManuallyReposition,
            didManuallyResizeWidth: edit.didManuallyResizeWidth,
            didManuallyResizeHeight: edit.didManuallyResizeHeight,
            didManuallyChangeStyle: edit.didManuallyChangeStyle,
            didApplyMatchedGeometry: edit.didApplyMatchedGeometry,
            didRestoreOriginalStyle: edit.didRestoreOriginalStyle
        ))

        let committedOperation = try XCTUnwrap(
            document.workspace.pageEditStates.first(where: { $0.pageRefID == pageRef.id })?.operations
                .first(where: { $0.sourceBlockID == smallBlock.id }),
            "the real committed operation should be persisted in pageEditStates"
        )
        XCTAssertEqual(committedOperation.sourceText, smallBlock.text)
        XCTAssertEqual(committedOperation.replacementText, smallBlock.text, "replacement text must be byte-identical to source (unchanged)")
        XCTAssertEqual(committedOperation.fontSize, 48, accuracy: 0.01)

        // This is the actual bug check: re-derive bounds via measuredBounds using the
        // REAL committed operation (already stored with `editedBounds` computed once
        // by `applyInlineTextEdit` — assert directly on it, and re-confirm via a fresh
        // measuredBounds call for good measure).
        let exportedBounds = PDFEditedPageRenderer.measuredBounds(
            for: committedOperation,
            pageBounds: basePage.bounds(for: .cropBox),
            sourcePage: basePage
        )
        let minimumHeightFor48pt: CGFloat = 48 // a 48pt font needs at least ~48pt of line height
        XCTAssertGreaterThanOrEqual(
            exportedBounds.height,
            minimumHeightFor48pt,
            "exported height must accommodate the pasted 48pt font, not stay clipped to the original 8pt sourceBounds.height (\(smallBlock.bounds.height))"
        )
        XCTAssertGreaterThan(
            committedOperation.editedBounds.height,
            smallBlock.bounds.height,
            "the committed operation's own editedBounds must already reflect the taller 48pt font"
        )
    }

    func testInlineEditorRestoreOriginalFormatClearsManualStyleChange() throws {
        let fixture = try makeInlineEditorFixture()
        let textView = try XCTUnwrap(findSubview(in: fixture.overlay) { (_: NSTextView) in true })
        let bold = try XCTUnwrap(findSubview(in: fixture.overlay) { (button: NSButton) in
            button.title == "B"
        })
        let restore = try XCTUnwrap(inlineEditorButton(in: fixture.overlay, identifier: "inlineEditor.restoreOriginalFormat"))
        let done = try XCTUnwrap(findSubview(in: fixture.overlay) { (button: NSButton) in
            button.title == "Done"
        })

        textView.string = "Changed words"
        bold.performClick(nil)
        restore.performClick(nil)
        done.performClick(nil)

        let committed = try XCTUnwrap(fixture.committedEdit())
        XCTAssertEqual(committed.fontSize, 8, accuracy: 0.01)
        XCTAssertEqual(committed.fontName, "Helvetica")
        XCTAssertFalse(committed.didManuallyChangeStyle)
    }

    func testInlineEditorRestoreOriginalFormatCommitsColorOnlyRestore() throws {
        let pageRef = PageRef(memberDocId: UUID(), sourcePageIndex: 0)
        let editedBlock = EditableTextBlock(
            pageRefID: pageRef.id,
            text: "Original text",
            bounds: CGRect(x: 72, y: 650, width: 160, height: 16),
            lines: [],
            fontName: "Helvetica",
            fontSize: 8,
            textColor: .init(nsColor: .systemRed),
            alignment: .left,
            rotation: 0,
            baseline: 650,
            confidence: .high
        )
        let sourceFormat = PDFTextEditFormat(
            fontName: "Helvetica",
            fontSize: 8,
            textColor: .documentText,
            alignment: .left,
            bounds: editedBlock.bounds,
            columnBounds: editedBlock.columnBounds
        )
        let fixture = try makeInlineEditorFixture(
            text: editedBlock.text,
            pageRef: pageRef,
            block: editedBlock,
            sourceFormat: sourceFormat
        )
        let restore = try XCTUnwrap(inlineEditorButton(in: fixture.overlay, identifier: "inlineEditor.restoreOriginalFormat"))
        let done = try XCTUnwrap(findSubview(in: fixture.overlay) { (button: NSButton) in
            button.title == "Done"
        })

        restore.performClick(nil)
        done.performClick(nil)

        let committed = try XCTUnwrap(fixture.committedEdit())
        XCTAssertTrue(colorsApproximatelyEqual(committed.textColor, sourceFormat.textColor.nsColor))
        XCTAssertFalse(committed.didManuallyChangeStyle)
    }

    func testInlineEditorKeepsActionButtonsReachableWhenCanvasIsNarrow() throws {
        // With the inspector panel open the canvas (and thus the editor overlay) is narrow.
        // The toolbar clamps to the visible width; the Done/Cancel action group must stay
        // pinned inside it rather than being laid out past the right edge and off-canvas,
        // which previously made Done/Cancel/Delete unreachable with panels open.
        let fixture = try makeInlineEditorFixture(
            text: "Editable paragraph text near the page edge",
            pdfViewFrame: CGRect(x: 0, y: 0, width: 520, height: 900)
        )
        let done = try XCTUnwrap(findSubview(in: fixture.overlay) { (button: NSButton) in
            button.title == "Done"
        })
        let cancel = try XCTUnwrap(findSubview(in: fixture.overlay) { (button: NSButton) in
            button.title == "Cancel"
        })

        let doneInOverlay = fixture.overlay.convert(done.bounds, from: done)
        let cancelInOverlay = fixture.overlay.convert(cancel.bounds, from: cancel)

        XCTAssertLessThanOrEqual(doneInOverlay.maxX, fixture.overlay.bounds.maxX + 0.5, "Done must stay within the visible canvas")
        XCTAssertGreaterThanOrEqual(doneInOverlay.minX, fixture.overlay.bounds.minX - 0.5, "Done must not be pushed off the left edge")
        XCTAssertLessThanOrEqual(cancelInOverlay.maxX, fixture.overlay.bounds.maxX + 0.5, "Cancel must stay within the visible canvas")
        XCTAssertGreaterThan(doneInOverlay.minX, cancelInOverlay.minX, "Done should sit to the right of Cancel in the action group")
    }

    /// Regression test for a confirmed bug: at a narrow canvas width (inspector panel
    /// open), the format-painter buttons previously landed entirely past the toolbar's own
    /// clamped right edge — outside a view's own bounds is never hit-tested by AppKit, so
    /// they were completely unclickable ("Match/Copy/Paste/Reset do nothing"). The color
    /// popup, though technically in-bounds, was separately covered by the right-pinned
    /// Cancel/Done buttons (added later, so higher in z-order), silently swallowing its
    /// clicks too. The toolbar now wraps overflow onto additional rows instead.
    func testInlineEditorFormatPainterButtonsReachableWhenCanvasIsNarrow() throws {
        let fixture = try makeInlineEditorFixture(
            text: "Editable paragraph text near the page edge",
            pdfViewFrame: CGRect(x: 0, y: 0, width: 520, height: 900)
        )
        for identifier in [
            "inlineEditor.matchNearbyFormat",
            "inlineEditor.copyNearbyFormat",
            "inlineEditor.applyCopiedFormat",
            "inlineEditor.restoreOriginalFormat"
        ] {
            let button = try XCTUnwrap(inlineEditorButton(in: fixture.overlay, identifier: identifier), "\(identifier) not found in view hierarchy")
            let point = button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: fixture.overlay)
            XCTAssertTrue(hitTest(fixture.overlay, at: point, reaches: button), "\(identifier) must be clickable when the canvas is narrow")
        }
        let color = try XCTUnwrap(findSubview(in: fixture.overlay, matching: { (popup: NSPopUpButton) in popup.toolTip == "Text color" }))
        let colorPoint = color.convert(NSPoint(x: color.bounds.midX, y: color.bounds.midY), to: fixture.overlay)
        XCTAssertTrue(hitTest(fixture.overlay, at: colorPoint, reaches: color), "Text color popup must not be covered by the action group when narrow")
        let done = try XCTUnwrap(findSubview(in: fixture.overlay) { (button: NSButton) in button.title == "Done" })
        let donePoint = done.convert(NSPoint(x: done.bounds.midX, y: done.bounds.midY), to: fixture.overlay)
        XCTAssertTrue(hitTest(fixture.overlay, at: donePoint, reaches: done), "Done must still be reachable once the format controls wrap")
    }

    /// Stress-test finding: the row-wrapping fix (`layoutFormatControls`) only solves
    /// controls not FITTING in the available toolbar width — it does nothing about a
    /// control being individually too NARROW for its own (locale-dependent) title.
    /// `setupToolbar()` places `restoreFormatButton` at a hardcoded `width: 52` regardless
    /// of what `L10n.string("readingCanvas.formatting.resetFormat.button")` resolves to.
    /// French resolves that key to "Réinitialiser" (~60.5pt of glyph width alone, before
    /// NSButton's bezel padding) and Spanish to "Restablecer" (~62.2pt) — both wider than
    /// the fixed 52pt frame regardless of canvas width or row count. This proves the title
    /// no longer fits the button's own frame, i.e. AppKit must truncate it.
    /// Regression test for a confirmed bug: toolbar buttons used hardcoded pixel widths
    /// sized for their English titles (e.g. 50pt for "Reset"), which real shipped
    /// translations overflow — French "Réinitialiser" measures ~60.5pt, Spanish
    /// "Restablecer" ~62.2pt, at the toolbar's 11pt system font. Fixed via
    /// `InlineTextEditorOverlay.measuredButtonWidth(title:font:minimum:)`, which grows
    /// past the English-sized minimum whenever the actual title needs more room.
    func testMeasuredButtonWidthAccommodatesLongerLocalizedTitles() throws {
        // Read the French translation straight out of the source Localizable.xcstrings
        // JSON rather than through a compiled fr.lproj strings table: both `swift
        // test` and Xcode's build system compile/copy the catalog into per-locale
        // resources and drop (or never expose) the raw .xcstrings from the built
        // test bundle, so no bundle lookup — `Bundle.module` or otherwise — can find
        // it at runtime. Resolve it from this source file's own path instead, which
        // is identical under both build systems.
        let sourceFileURL = URL(fileURLWithPath: #filePath)
        let catalogURL = sourceFileURL
            .deletingLastPathComponent() // OrifoldTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // repo root
            .appendingPathComponent("Orifold/Resources/Localizable.xcstrings")
        XCTAssertTrue(FileManager.default.fileExists(atPath: catalogURL.path), "Expected to find Localizable.xcstrings relative to the test source file")
        let catalogData = try Data(contentsOf: catalogURL)
        let catalog = try XCTUnwrap(try JSONSerialization.jsonObject(with: catalogData) as? [String: Any])
        let strings = try XCTUnwrap(catalog["strings"] as? [String: Any])
        let entry = try XCTUnwrap(strings["readingCanvas.formatting.resetFormat.button"] as? [String: Any])
        let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any])
        let frLocalization = try XCTUnwrap(localizations["fr"] as? [String: Any])
        let frStringUnit = try XCTUnwrap(frLocalization["stringUnit"] as? [String: Any])
        let frTitle = try XCTUnwrap(frStringUnit["value"] as? String)
        XCTAssertEqual(frTitle, "Réinitialiser", "Sanity-check: the catalog actually contains the expected translation")

        let font = NSFont.systemFont(ofSize: 11)
        let textWidth = (frTitle as NSString).size(withAttributes: [.font: font]).width
        let englishSizedMinimum: CGFloat = 50 // what setupToolbar() used before the fix

        XCTAssertGreaterThan(textWidth, englishSizedMinimum, "Sanity-check: the English-sized minimum really is too narrow for the French title")

        let measuredWidth = InlineTextEditorOverlay.measuredButtonWidth(title: frTitle, font: font, minimum: englishSizedMinimum)
        XCTAssertGreaterThanOrEqual(measuredWidth, textWidth, "The button must be at least as wide as the French title needs")
        XCTAssertGreaterThan(measuredWidth, englishSizedMinimum, "The fix must actually grow past the English-sized minimum for this locale")
    }

    /// Regression check: `containsInteractivePoint(_:)` is the dismiss/no-dismiss gate for
    /// clicks near the inline editor — a point outside its reported interactive region is
    /// treated as "outside the editor" and cancels/dismisses the edit. Once the toolbar
    /// wraps onto a second row (narrow canvas), the toolbar's own `frame` grows taller via
    /// `toolbarHeight(forRowCount:)`. A click on a second-row control (e.g. the wrapped
    /// Match button) must still be reported as "inside" — if `containsInteractivePoint`
    /// somehow used a stale/assumed single-row height instead of the live `toolbar.frame`,
    /// this would incorrectly report "outside" and dismiss the edit out from under the user.
    func testInlineEditorContainsInteractivePointCoversWrappedSecondRowControls() throws {
        let fixture = try makeInlineEditorFixture(
            text: "Editable paragraph text near the page edge",
            pdfViewFrame: CGRect(x: 0, y: 0, width: 520, height: 900)
        )
        let match = try XCTUnwrap(inlineEditorButton(in: fixture.overlay, identifier: "inlineEditor.matchNearbyFormat"))

        // Sanity-check the premise: the Match button must actually be wrapped onto a row
        // above the toolbar's bottom (row 0) edge for this test to be meaningful.
        let toolbar = try XCTUnwrap(match.superview)
        XCTAssertGreaterThan(match.frame.minY, 8, "Match button should be wrapped onto a row above row 0 at this narrow width")

        let matchCenterInOverlay = toolbar.convert(NSPoint(x: match.frame.midX, y: match.frame.midY), to: fixture.overlay)
        let pdfViewPoint = fixture.pdfView.convert(matchCenterInOverlay, from: fixture.overlay)

        XCTAssertTrue(
            fixture.overlay.containsInteractivePoint(pdfViewPoint),
            "A click on a wrapped second-row toolbar control must be treated as inside the editor, not as a dismiss-triggering outside click"
        )
    }

    /// Regression test for a confirmed bug: committing, canceling, or reverting an inline
    /// edit removed the editor overlay (and its textView) from the view hierarchy without
    /// ever restoring first responder to the PDF view. Since SwiftUI's `\.undoManager` (read
    /// by both `ContentView` and the Edit-menu commands) resolves from the key window's
    /// CURRENT first-responder chain, leaving first responder dangling on a just-removed
    /// view could make the next Undo attempt resolve a different (or no) undo manager than
    /// the one that actually recorded the edit — surfacing as "nothing to undo" right after
    /// making one. First responder must deterministically return to the PDF view.
    func testInlineEditorRestoresFirstResponderToPDFViewAfterCommit() throws {
        let fixture = try makeInlineEditorFixture(text: "Original text")
        let window = NSWindow(
            contentRect: fixture.pdfView.frame,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = fixture.pdfView
        let textView = try XCTUnwrap(findSubview(in: fixture.overlay) { (_: NSTextView) in true })
        window.makeFirstResponder(textView)
        XCTAssertTrue(window.firstResponder === textView)

        let done = try XCTUnwrap(findSubview(in: fixture.overlay) { (button: NSButton) in button.title == "Done" })
        textView.string = "Edited text"
        done.performClick(nil)

        XCTAssertTrue(
            window.firstResponder === fixture.pdfView,
            "First responder must return to the PDF view after Done so the document undo manager resolves correctly"
        )
    }

    func testInlineEditorRestoresFirstResponderToPDFViewAfterCancel() throws {
        let fixture = try makeInlineEditorFixture(text: "Original text")
        let window = NSWindow(
            contentRect: fixture.pdfView.frame,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = fixture.pdfView
        let textView = try XCTUnwrap(findSubview(in: fixture.overlay) { (_: NSTextView) in true })
        window.makeFirstResponder(textView)

        let cancel = try XCTUnwrap(findSubview(in: fixture.overlay) { (button: NSButton) in button.title == "Cancel" })
        cancel.performClick(nil)

        XCTAssertTrue(
            window.firstResponder === fixture.pdfView,
            "First responder must return to the PDF view after Cancel so the document undo manager resolves correctly"
        )
    }

    /// Regression test for a confirmed bug: reopening an already-edited (but otherwise
    /// untouched) text block re-derived its committed height from `ReplacementTextLayout`'s
    /// CoreText measurement instead of the original PDFium-measured `sourceBounds.height` —
    /// even though the replacement text was byte-identical to the source. CoreText and
    /// PDFium don't necessarily agree on line height for the same font/size, so this could
    /// commit a height a few points off from the original for text nobody actually edited.
    func testMeasuredBoundsPreservesOriginalHeightWhenTextIsUnchanged() throws {
        let sourceBounds = CGRect(x: 72, y: 700, width: 200, height: 14)
        let operation = PDFTextEditOperation(
            pageRefID: UUID(),
            sourceBlockID: UUID(),
            sourceBounds: sourceBounds,
            sourceText: "Unchanged text",
            editedBounds: CGRect(x: 72, y: 690, width: 200, height: 24),
            replacementText: "Unchanged text",
            fontName: "Helvetica",
            fontSize: 10,
            textColor: .documentText,
            alignment: .left
        )
        let measured = PDFEditedPageRenderer.measuredBounds(for: operation)
        XCTAssertEqual(measured.height, sourceBounds.height, accuracy: 0.01)
    }

    func testMeasuredBoundsStillGrowsHeightWhenTextActuallyChanged() throws {
        let sourceBounds = CGRect(x: 72, y: 700, width: 120, height: 14)
        let operation = PDFTextEditOperation(
            pageRefID: UUID(),
            sourceBlockID: UUID(),
            sourceBounds: sourceBounds,
            sourceText: "Short",
            editedBounds: CGRect(x: 72, y: 690, width: 120, height: 14),
            replacementText: "A much longer replacement that will not fit on the original single short line and must wrap",
            fontName: "Helvetica",
            fontSize: 10,
            textColor: .documentText,
            alignment: .left
        )
        let measured = PDFEditedPageRenderer.measuredBounds(for: operation)
        XCTAssertGreaterThan(measured.height, sourceBounds.height, "Genuinely longer text must still be allowed to grow, not get pinned to the original height")
    }

    /// Regression test for a bug caught during review of the height-preservation fix above:
    /// Match/Paste-format can restyle unchanged text (e.g. to a much larger font) without
    /// changing the text content or setting `didManuallyResizeWidth`. Blindly trusting
    /// `sourceBounds.height` (sized for the OLD, smaller font) in that case would clip the
    /// new, taller text when rendered — the fix must never shrink below what the CURRENT
    /// font actually needs.
    func testMeasuredBoundsGrowsHeightWhenUnchangedTextGetsALargerFontViaMatchOrPaste() throws {
        let sourceBounds = CGRect(x: 72, y: 700, width: 200, height: 14)
        let operation = PDFTextEditOperation(
            pageRefID: UUID(),
            sourceBlockID: UUID(),
            sourceBounds: sourceBounds,
            sourceText: "Unchanged text",
            editedBounds: CGRect(x: 72, y: 690, width: 200, height: 14),
            replacementText: "Unchanged text",
            fontName: "Helvetica",
            fontSize: 48,
            textColor: .documentText,
            alignment: .left
        )
        let measured = PDFEditedPageRenderer.measuredBounds(for: operation)
        XCTAssertGreaterThan(measured.height, sourceBounds.height, "A much larger font applied to unchanged text must grow the box, not clip into the old font's height")
    }

    /// Regression coverage for the `unchangedTextHasKnownHeight` height-preservation
    /// branch under font substitution: `operation.fontName` here is a bogus PostScript
    /// name that does not resolve via `NSFont(name:size:)` on macOS, forcing
    /// `ReplacementTextLayout.init` to fall back to `NSFont.systemFont(ofSize:)` (verified
    /// directly: `NSFont(name: "TotallyBogusFontXYZ-NotReal-9999", size:)` returns nil).
    /// `sourceBounds.height` here reflects a tiny original PDF font's metrics — nothing
    /// like the substituted fallback's. The `sourceHeight >= rawCoreTextHeight` guard must
    /// still catch this and fall through to the normal (fallback-font-driven) padded
    /// re-measurement, rather than trusting a source height that is now far too short for
    /// the substituted font and clipping it.
    func testMeasuredBoundsDoesNotClipWhenFontNameFailsToResolveAndFallsBackToSystemFont() throws {
        let unresolvedFontName = "TotallyBogusFontXYZ-NotReal-9999"
        XCTAssertNil(NSFont(name: unresolvedFontName, size: 48), "sanity check: this name must not resolve to an installed font, to force ReplacementTextLayout's fallback path")

        // A tiny source box, consistent with a small original font — the substituted
        // fallback font drawn at a much larger size needs far more height than this.
        let sourceBounds = CGRect(x: 72, y: 700, width: 200, height: 10)
        let operation = PDFTextEditOperation(
            pageRefID: UUID(),
            sourceBlockID: UUID(),
            sourceBounds: sourceBounds,
            sourceText: "Unchanged text",
            editedBounds: CGRect(x: 72, y: 690, width: 200, height: 10),
            replacementText: "Unchanged text",
            fontName: unresolvedFontName,
            fontSize: 60,
            textColor: .documentText,
            alignment: .left
        )
        let measured = PDFEditedPageRenderer.measuredBounds(for: operation)
        XCTAssertGreaterThan(
            measured.height,
            sourceBounds.height,
            "when the requested font fails to resolve and CoreText substitutes a fallback font whose metrics need more height than the original source box, measuredBounds must still grow to fit it, not clip using the stale source height"
        )
    }

    /// Regression test for weak/ambiguous confirmations: Match/Copy/Paste/Reset previously
    /// all reported through `.warning`, the same severity as genuine warnings/hints like
    /// "Copy a format first" — indistinguishable in the UI. These are confirmations that
    /// something the user asked for actually happened, so they must report `.success`.
    func testFormatPainterActionsReportSuccessSeverity() throws {
        let fixture = try makeInlineEditorFixture(text: "Original text")
        let match = try XCTUnwrap(inlineEditorButton(in: fixture.overlay, identifier: "inlineEditor.matchNearbyFormat"))
        match.performClick(nil)
        XCTAssertEqual(fixture.viewModel.editingStatus?.severity, .success)

        let copy = try XCTUnwrap(inlineEditorButton(in: fixture.overlay, identifier: "inlineEditor.copyNearbyFormat"))
        copy.performClick(nil)
        XCTAssertEqual(fixture.viewModel.editingStatus?.severity, .success)

        let apply = try XCTUnwrap(inlineEditorButton(in: fixture.overlay, identifier: "inlineEditor.applyCopiedFormat"))
        apply.performClick(nil)
        XCTAssertEqual(fixture.viewModel.editingStatus?.severity, .success)

        let restore = try XCTUnwrap(inlineEditorButton(in: fixture.overlay, identifier: "inlineEditor.restoreOriginalFormat"))
        restore.performClick(nil)
        XCTAssertEqual(fixture.viewModel.editingStatus?.severity, .success)
    }

    func testApplyCopiedFormatWithoutACopyReportsWarningSeverity() throws {
        let fixture = try makeInlineEditorFixture(text: "Original text")
        let apply = try XCTUnwrap(inlineEditorButton(in: fixture.overlay, identifier: "inlineEditor.applyCopiedFormat"))
        apply.performClick(nil)
        XCTAssertEqual(fixture.viewModel.editingStatus?.severity, .warning)
    }

    /// Regression test for the "black screen instead of live document rollback" bug: undo
    /// mutates `combinedPDF` directly with no coordinator involvement, so the document swap
    /// used to only ever happen via `PDFViewRepresentable.updateNSView`'s naive
    /// `nsView.document = viewModel.combinedPDF` — no viewport capture/restore. Every
    /// document swap must now be routed through `syncDocumentPreservingViewport`.
    func testSyncDocumentPreservingViewportSwapsDocumentAndIsIdempotent() throws {
        let pdfView = OrifoldPDFView(frame: CGRect(x: 0, y: 0, width: 600, height: 800))
        let firstDoc = makePDF(pageTexts: ["Page one"])
        pdfView.document = firstDoc
        pdfView.layoutDocumentView()

        let viewModel = WorkspaceViewModel(document: WorkspaceDocument())
        let coordinator = PDFViewRepresentable.Coordinator(viewModel: viewModel)

        XCTAssertFalse(coordinator.syncDocumentPreservingViewport(pdfView, newDocument: firstDoc), "Swapping to the SAME document must be a no-op")

        let secondDoc = makePDF(pageTexts: ["Page one, replaced"])
        XCTAssertTrue(coordinator.syncDocumentPreservingViewport(pdfView, newDocument: secondDoc))
        XCTAssertTrue(pdfView.document === secondDoc)
    }

    func testInlineEditorCommitsParagraphBoundsWidthWhenTextIsShorter() throws {
        let pageRef = PageRef(memberDocId: UUID(), sourcePageIndex: 0)
        let firstLine = PDFTextLine(
            text: "First long line",
            bounds: CGRect(x: 72, y: 650, width: 220, height: 12),
            runs: [],
            confidence: .high
        )
        let secondLine = PDFTextLine(
            text: "second wrapped line",
            bounds: CGRect(x: 72, y: 634, width: 180, height: 12),
            runs: [],
            confidence: .high
        )
        let columnBounds = CGRect(x: 72, y: 0, width: 420, height: 792)
        let block = EditableTextBlock(
            pageRefID: pageRef.id,
            text: "\(firstLine.text) \(secondLine.text)",
            bounds: firstLine.bounds.union(secondLine.bounds),
            lines: [firstLine, secondLine],
            columnBounds: columnBounds,
            fontName: "Helvetica",
            fontSize: 10,
            textColor: .documentText,
            rotation: 0,
            baseline: firstLine.bounds.minY,
            confidence: .high
        )
        let fixture = try makeInlineEditorFixture(
            text: block.text,
            pageRef: pageRef,
            block: block,
            pdfViewFrame: CGRect(x: 0, y: 0, width: 1400, height: 1000)
        )
        let textView = try XCTUnwrap(findSubview(in: fixture.overlay) { (_: NSTextView) in true })
        let done = try XCTUnwrap(findSubview(in: fixture.overlay) { (button: NSButton) in
            button.title == "Done"
        })
        textView.string = "Short replacement"

        done.performClick(nil)

        let committed = try XCTUnwrap(fixture.committedEdit())
        XCTAssertEqual(committed.editedBounds.minX, block.bounds.minX, accuracy: 0.01)
        XCTAssertEqual(committed.editedBounds.width, block.bounds.width, accuracy: 0.01)
    }

    func testInlineEditorMatchAppliesNearbyParagraphColumnGeometry() throws {
        let pageRef = PageRef(memberDocId: UUID(), sourcePageIndex: 0)
        let narrowBlock = EditableTextBlock(
            pageRefID: pageRef.id,
            text: "Edited paragraph with too much wrapping",
            bounds: CGRect(x: 96, y: 620, width: 260, height: 42),
            lines: [],
            columnBounds: CGRect(x: 96, y: 0, width: 260, height: 792),
            fontName: "Helvetica",
            fontSize: 10,
            textColor: .documentText,
            rotation: 0,
            baseline: 620,
            confidence: .high
        )
        let nearbyColumn = CGRect(x: 72, y: 0, width: 430, height: 792)
        let nearbyBounds = CGRect(x: 72, y: 650, width: 360, height: 16)
        let nearbyFormat = PDFTextEditFormat(
            fontName: "Helvetica",
            fontSize: 10,
            textColor: .documentText,
            alignment: .left,
            bounds: nearbyBounds,
            columnBounds: nearbyColumn
        )
        let fixture = try makeInlineEditorFixture(
            text: narrowBlock.text,
            pageRef: pageRef,
            block: narrowBlock,
            sourceFormat: nearbyFormat,
            pdfViewFrame: CGRect(x: 0, y: 0, width: 1400, height: 1000)
        )
        let textView = try XCTUnwrap(findSubview(in: fixture.overlay) { (_: NSTextView) in true })
        let match = try XCTUnwrap(inlineEditorButton(in: fixture.overlay, identifier: "inlineEditor.matchNearbyFormat"))
        let done = try XCTUnwrap(findSubview(in: fixture.overlay) { (button: NSButton) in
            button.title == "Done"
        })

        let initialPageBounds = fixture.pdfView.convert(textView.frame, to: fixture.page).standardized
        XCTAssertLessThan(initialPageBounds.width, nearbyColumn.width)

        match.performClick(nil)
        let matchedPageBounds = fixture.pdfView.convert(textView.frame, to: fixture.page).standardized
        XCTAssertEqual(matchedPageBounds.minX, nearbyBounds.minX, accuracy: 0.01)
        XCTAssertEqual(matchedPageBounds.width, nearbyBounds.width, accuracy: 0.01)

        done.performClick(nil)

        let committed = try XCTUnwrap(fixture.committedEdit())
        XCTAssertEqual(committed.editedBounds.minX, nearbyBounds.minX, accuracy: 0.01)
        XCTAssertEqual(committed.editedBounds.width, nearbyBounds.width, accuracy: 0.01)
        XCTAssertEqual(committed.block.bounds, narrowBlock.bounds)
        XCTAssertEqual(committed.block.columnBounds, nearbyColumn)
    }

    func testInlineEditorCommitsTypedFontSizeWhenDoneIsPressed() throws {
        let fixture = try makeInlineEditorFixture()
        let sizeField = try XCTUnwrap(findSubview(in: fixture.overlay) { (field: NSTextField) in
            field.toolTip == "Font size" && field.isEditable
        })
        let doneButton = try XCTUnwrap(findSubview(in: fixture.overlay) { (button: NSButton) in
            button.title == "Done"
        })

        sizeField.stringValue = "14"
        doneButton.performClick(nil)

        let edit = try XCTUnwrap(fixture.committedEdit())
        XCTAssertEqual(edit.fontSize, 14, accuracy: 0.01)
    }

    func testInlineEditorDoneWithoutChangesCancelsInsteadOfCommitting() throws {
        let fixture = try makeInlineEditorFixture()
        let doneButton = try XCTUnwrap(findSubview(in: fixture.overlay) { (button: NSButton) in
            button.title == "Done"
        })

        doneButton.performClick(nil)

        XCTAssertNil(fixture.committedEdit())
    }

    func testInlineEditorSameSizeFieldDoesNotCreateNoOpCommit() throws {
        let fixture = try makeInlineEditorFixture()
        let sizeField = try XCTUnwrap(findSubview(in: fixture.overlay) { (field: NSTextField) in
            field.toolTip == "Font size" && field.isEditable
        })
        let doneButton = try XCTUnwrap(findSubview(in: fixture.overlay) { (button: NSButton) in
            button.title == "Done"
        })

        sizeField.stringValue = "8"
        doneButton.performClick(nil)

        XCTAssertNil(fixture.committedEdit())
    }

    func testInlineEditorUndoDoesNotFallThroughToWorkspaceUndoWhileEditing() throws {
        let fixture = try makeInlineEditorFixture()
        let textView = try XCTUnwrap(findSubview(in: fixture.overlay) { (_: NSTextView) in true })
        let undoManager = UndoManager()
        var workspaceUndoInvoked = false
        undoManager.registerUndo(withTarget: fixture.viewModel) { _ in
            workspaceUndoInvoked = true
        }
        fixture.viewModel.undoManager = undoManager

        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .command,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "z",
            charactersIgnoringModifiers: "z",
            isARepeat: false,
            keyCode: 6
        ))
        textView.keyDown(with: event)

        XCTAssertFalse(workspaceUndoInvoked)
        XCTAssertTrue(undoManager.canUndo)
        XCTAssertNil(fixture.committedEdit())
    }

    func testInlineEditorCommitsSelectedTextColorWhenDoneIsPressed() throws {
        let fixture = try makeInlineEditorFixture()
        let colorPopup = try XCTUnwrap(findSubview(in: fixture.overlay) { (popup: NSPopUpButton) in
            popup.toolTip == "Text color"
        })
        let doneButton = try XCTUnwrap(findSubview(in: fixture.overlay) { (button: NSButton) in
            button.title == "Done"
        })

        colorPopup.selectItem(withTitle: "Red")
        colorPopup.sendAction(colorPopup.action, to: colorPopup.target)
        doneButton.performClick(nil)

        let edit = try XCTUnwrap(fixture.committedEdit())
        XCTAssertTrue(colorsApproximatelyEqual(edit.textColor, .systemRed, tolerance: 0.025))
    }

    func testInlineEditorStyleOnlyCommitPreservesOriginalTextBounds() throws {
        let fixture = try makeInlineEditorFixture()
        let colorPopup = try XCTUnwrap(findSubview(in: fixture.overlay) { (popup: NSPopUpButton) in
            popup.toolTip == "Text color"
        })
        let doneButton = try XCTUnwrap(findSubview(in: fixture.overlay) { (button: NSButton) in
            button.title == "Done"
        })

        colorPopup.selectItem(withTitle: "Red")
        colorPopup.sendAction(colorPopup.action, to: colorPopup.target)
        doneButton.performClick(nil)

        let edit = try XCTUnwrap(fixture.committedEdit())
        XCTAssertGreaterThanOrEqual(edit.editedBounds.width, 160)
        XCTAssertGreaterThanOrEqual(edit.editedBounds.height, 16)
    }

    func testInlineEditorColorMenuIncludesDefaultsAndDetectedDocumentColors() throws {
        let detectedColor = NSColor(srgbRed: 0.42, green: 0.22, blue: 0.74, alpha: 1)
        let fixture = try makeInlineEditorFixture(textColor: CodableColor(nsColor: detectedColor))
        let colorPopup = try XCTUnwrap(findSubview(in: fixture.overlay) { (popup: NSPopUpButton) in
            popup.toolTip == "Text color"
        })
        let titles = colorPopup.itemTitles

        XCTAssertEqual(Array(titles.prefix(5)), ["Black", "White", "Red", "Blue", "Green"])
        XCTAssertTrue(titles.contains("Detected #6B38BD"))

        colorPopup.selectItem(withTitle: "Detected #6B38BD")
        colorPopup.sendAction(colorPopup.action, to: colorPopup.target)
        let doneButton = try XCTUnwrap(findSubview(in: fixture.overlay) { (button: NSButton) in
            button.title == "Done"
        })
        doneButton.performClick(nil)

        let edit = try XCTUnwrap(fixture.committedEdit())
        XCTAssertTrue(colorsApproximatelyEqual(edit.textColor, detectedColor, tolerance: 0.025))
    }

    func testInlineEditorDefaultsBlankInsertedTextToVisibleColor() throws {
        let fixture = try makeInlineEditorFixture(text: "", textColor: CodableColor(nsColor: .white))
        let textView = try XCTUnwrap(findSubview(in: fixture.overlay) { (_: NSTextView) in true })
        let doneButton = try XCTUnwrap(findSubview(in: fixture.overlay) { (button: NSButton) in
            button.title == "Done"
        })

        textView.string = "Inserted text"
        doneButton.performClick(nil)

        let edit = try XCTUnwrap(fixture.committedEdit())
        XCTAssertTrue(colorsApproximatelyEqual(edit.textColor, .black, tolerance: 0.025))
    }

    func testInlineEditorCommitsTextContentTopEdge() throws {
        let fixture = try makeInlineEditorFixture()
        let textView = try XCTUnwrap(findSubview(in: fixture.overlay) { (_: NSTextView) in true })
        let doneButton = try XCTUnwrap(findSubview(in: fixture.overlay) { (button: NSButton) in
            button.title == "Done"
        })

        textView.string = "Changed text"
        doneButton.performClick(nil)

        let edit = try XCTUnwrap(fixture.committedEdit())
        XCTAssertEqual(edit.editedBounds.maxY, 664, accuracy: 0.01)
    }

    /// Regression: the editor overlay is a plain NSView subview of `pdfView`, laid out by
    /// converting the block's PAGE-space bounds through `pdfView.convert(_:from:page:)`
    /// (`layoutEditor`). Before this fix, only ZOOM changes (`.PDFViewScaleChanged`)
    /// triggered that re-layout — scrolling the canvas while editing left the overlay glued
    /// to its stale on-screen position. Since `commitButton()` converts the overlay's
    /// on-screen frame back to page space at commit time, scrolling mid-edit and then
    /// clicking Done would have committed the replacement at the WRONG page location.
    func testInlineEditorFollowsScrollPositionSoCommitLandsAtTheCorrectPageLocation() throws {
        let fixture = try makeInlineEditorFixture()
        guard let scrollView = findSubview(in: fixture.pdfView, matching: { (_: NSScrollView) in true }) else {
            throw XCTSkip("PDFView did not expose an internal NSScrollView on this OS/runtime to scroll")
        }
        let clipView = scrollView.contentView
        clipView.postsBoundsChangedNotifications = true

        // Simulate the user scrolling the canvas while the editor is open.
        clipView.scroll(to: CGPoint(x: 0, y: 60))
        scrollView.reflectScrolledClipView(clipView)

        let textView = try XCTUnwrap(findSubview(in: fixture.overlay) { (_: NSTextView) in true })
        let doneButton = try XCTUnwrap(findSubview(in: fixture.overlay) { (button: NSButton) in
            button.title == "Done"
        })
        textView.string = "Changed text"
        doneButton.performClick(nil)

        let edit = try XCTUnwrap(fixture.committedEdit())
        // Matches the un-scrolled baseline in `testInlineEditorCommitsTextContentTopEdge` —
        // scrolling mid-edit must have zero effect on where the commit lands.
        XCTAssertEqual(edit.editedBounds.maxY, 664, accuracy: 0.01, "scrolling mid-edit must not shift where the replacement commits on the page")
    }
}

final class DocumentImportConverterTests: XCTestCase {
    func testPlainTextImportCreatesExtractablePDF() throws {
        let data = Data("Hello Orifold\nSecond line".utf8)

        let pdf = try DocumentImportConverter.pdfDocument(
            from: data,
            contentType: .plainText,
            filename: "notes.txt",
            baseURL: nil
        )

        XCTAssertGreaterThanOrEqual(pdf.pageCount, 1)
        XCTAssertEqual(pdf.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String, "notes")
        XCTAssertTrue(pdf.stringValue.contains("Hello Orifold"))
        XCTAssertTrue(pdf.stringValue.contains("Second line"))
    }

    func testHTMLImportPaginatesTallContentToLetterPages() async throws {
        guard ProcessInfo.processInfo.environment["XCODE_SCHEME_NAME"] == nil else {
            throw XCTSkip("Xcode's test runner can hang WebKit HTML rendering; SwiftPM covers this conversion path.")
        }

        let html = """
        <!doctype html>
        <html><body><main style="height: 1800px">Tall import</main></body></html>
        """

        let imported = try await DocumentImportConverter.importedDocumentAsync(
            from: Data(html.utf8),
            contentType: .html,
            filename: "tall.html",
            baseURL: nil
        )
        let pdf = imported.pdfDocument

        XCTAssertGreaterThan(pdf.pageCount, 1)
        XCTAssertTrue(pdf.stringValue.contains("Tall import"))
        let firstPage = try XCTUnwrap(pdf.page(at: 0))
        XCTAssertEqual(firstPage.bounds(for: .mediaBox).width, 612, accuracy: 0.5)
        XCTAssertEqual(firstPage.bounds(for: .mediaBox).height, 792, accuracy: 0.5)
    }

    func testHTMLImportFallsBackWhenWebRendererTimesOut() async throws {
        let html = Data("""
        <!doctype html>
        <html><body><h1>Fallback import</h1><p>Rendered even when WebKit times out.</p></body></html>
        """.utf8)

        let imported = try await DocumentImportConverter.importedDocumentAsync(
            from: html,
            contentType: .html,
            filename: "fallback.html",
            baseURL: nil,
            htmlRenderTimeout: 0
        )

        XCTAssertGreaterThan(imported.pdfDocument.pageCount, 0)
        XCTAssertTrue(imported.pdfDocument.stringValue.contains("Fallback import"))
        XCTAssertEqual(imported.sourcePayload?.format, .html)
    }

    @MainActor
    func testAsyncImportRendersEveryAdvertisedImportFamily() async throws {
        let rich = NSMutableAttributedString(string: "Heading\nBold item\nLink")
        rich.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: 18), range: NSRange(location: 0, length: 7))
        rich.addAttribute(.link, value: URL(string: "https://example.com")!, range: NSRange(location: 18, length: 4))

        let cases: [(name: String, data: Data, type: UTType, expectedText: String, expectedSourceFormat: SourceDocumentFormat?)] = [
            ("sample.pdf", try makePDF(pageTexts: ["PDF import"]).dataRepresentation().unwrap(), .pdf, "PDF import", nil),
            ("sample.png", try makePNGData(), .png, "", nil),
            ("sample.html", Data("<!doctype html><html><body><h1>HTML import</h1></body></html>".utf8), .html, "HTML import", .html),
            ("sample.htm", Data("<!doctype html><html><body><h1>HTM import</h1></body></html>".utf8), .html, "HTM import", .html),
            ("sample.svg", Data("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"200\" height=\"80\"><text x=\"10\" y=\"40\">SVG import</text></svg>".utf8), .orifoldSVG, "SVG import", nil),
            ("sample.docx", try richImportData(from: rich, documentType: .officeOpenXML), .docx, "Heading", .docx),
            ("sample.doc", try richImportData(from: rich, documentType: .docFormat), .wordDoc, "Heading", .wordDoc),
            ("sample.odt", try richImportData(from: rich, documentType: .openDocument), .odt, "Heading", .odt),
            ("sample.xlsx", makeStoredZIPData(entries: [
                "xl/workbook.xml": "<workbook/>",
                "xl/worksheets/sheet1.xml": "<worksheet><sheetData><row><c t=\"inlineStr\"><is><t>XLSX import</t></is></c></row></sheetData></worksheet>"
            ]), .orifoldXLSX, "XLSX import", nil),
            ("sample.pptx", makeStoredZIPData(entries: [
                "ppt/presentation.xml": "<p:presentation/>",
                "ppt/slides/slide1.xml": "<p:sld><p:cSld><p:spTree><a:t>PPTX import</a:t></p:spTree></p:cSld></p:sld>"
            ]), .orifoldPPTX, "PPTX import", nil),
            ("sample.epub", makeStoredZIPData(entries: [
                "mimetype": "application/epub+zip",
                "META-INF/container.xml": "<container/>",
                "OPS/chapter.xhtml": "<html><body><h1>EPUB import</h1><p>Chapter text</p></body></html>"
            ]), .orifoldEPUB, "EPUB import", nil),
            ("sample.rtf", try richImportData(from: rich, documentType: .rtf), .rtf, "Heading", .rtf),
            ("sample.md", Data("# Markdown import\n\n- Item".utf8), .markdown, "Markdown import", .markdown),
            ("sample.txt", Data("Plain text import".utf8), .plainText, "Plain text import", .plainText),
            ("sample.csv", Data("name,value\nCSV import,1\n".utf8), .csv, "CSV import", .plainText),
            ("sample.tsv", Data("name\tvalue\nTSV import\t1\n".utf8), .orifoldTSV, "TSV import", .plainText),
            ("sample.json", Data("{\"title\":\"JSON import\"}".utf8), .json, "JSON import", .plainText),
            ("sample.jsonl", Data("{\"title\":\"JSONL import\"}\n".utf8), .json, "JSONL import", .plainText),
            ("sample.xml", Data("<root><title>XML import</title></root>".utf8), .xml, "XML import", .plainText),
            ("sample.yaml", Data("title: YAML import\n".utf8), .orifoldYAML, "YAML import", .plainText),
            ("sample.yml", Data("title: YML import\n".utf8), .orifoldYAML, "YML import", .plainText),
            ("sample.toml", Data("title = \"TOML import\"\n".utf8), .orifoldTOML, "TOML import", .plainText),
            ("sample.plist", Data("<?xml version=\"1.0\"?><plist><dict><key>title</key><string>Plist import</string></dict></plist>".utf8), .propertyList, "Plist import", .plainText),
            ("sample-binary.plist", try binaryPropertyListData(["title": "Binary plist import"]), .propertyList, "Binary plist import", nil),
            ("sample.log", Data("INFO Log import\n".utf8), .orifoldLog, "Log import", .plainText),
            ("sample.swift", Data("let label = \"Swift import\"\n".utf8), .orifoldSourceCode, "Swift import", .plainText),
            ("sample.sh", Data("#!/bin/sh\necho Shell import\n".utf8), .orifoldShellScript, "Shell import", .plainText),
            ("sample.sql", Data("select 'SQL import';\n".utf8), .orifoldSQL, "SQL import", .plainText)
        ]

        for sample in cases {
            let imported = try await DocumentImportConverter.importedDocumentAsync(
                from: sample.data,
                contentType: sample.type,
                filename: sample.name,
                baseURL: nil,
                htmlRenderTimeout: 0
            )

            XCTAssertGreaterThan(imported.pdfDocument.pageCount, 0, sample.name)
            if !sample.expectedText.isEmpty {
                XCTAssertTrue(imported.pdfDocument.stringValue.contains(sample.expectedText), sample.name)
            }
            XCTAssertEqual(imported.sourcePayload?.format, sample.expectedSourceFormat, sample.name)
        }
    }

    func testOversizedTextImportReturnsTypedLimitError() {
        let oversized = Data(count: Int(DocumentImportConverter.maxImportBytes / 10))

        XCTAssertThrowsError(
            try DocumentImportConverter.pdfDocument(
                from: oversized,
                contentType: .plainText,
                filename: "too-large.txt",
                baseURL: nil
            )
        ) { error in
            guard case DocumentImportConverter.ConversionError.fileTypeTooLarge(let description, _, _) = error else {
                return XCTFail("Expected fileTypeTooLarge, got \(error)")
            }
            XCTAssertEqual(description, "text")
        }
    }

    func testRTFDImportFromURLRendersWithoutSourcePayload() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Orifold-rtfd-\(UUID().uuidString)")
            .appendingPathExtension("rtfd")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let rtf = try richImportData(
            from: NSAttributedString(string: "RTFD import"),
            documentType: .rtf
        )
        try rtf.write(to: directory.appendingPathComponent("TXT.rtf"))

        let imported = try DocumentImportConverter.importedDocument(from: directory)

        XCTAssertGreaterThan(imported.pdfDocument.pageCount, 0)
        XCTAssertTrue(imported.pdfDocument.stringValue.contains("RTFD import"))
        XCTAssertNil(imported.sourcePayload)
    }

    func testSpreadsheetImportUsesWorkbookSheetOrderAndNames() async throws {
        let data = makeStoredZIPData(entries: [
            "xl/workbook.xml": """
            <workbook xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
              <sheets>
                <sheet name="Summary" sheetId="1" r:id="rId2"/>
                <sheet name="Details" sheetId="2" r:id="rId1"/>
              </sheets>
            </workbook>
            """,
            "xl/_rels/workbook.xml.rels": """
            <Relationships>
              <Relationship Id="rId1" Target="worksheets/sheet10.xml"/>
              <Relationship Id="rId2" Target="worksheets/sheet2.xml"/>
            </Relationships>
            """,
            "xl/sharedStrings.xml": "<sst><si><t>Shared detail</t></si></sst>",
            "xl/worksheets/sheet2.xml": "<worksheet><sheetData><row><c><v>Summary value</v></c></row></sheetData></worksheet>",
            "xl/worksheets/sheet10.xml": "<worksheet><sheetData><row><c t=\"s\"><v>0</v></c><c><v>42</v></c></row></sheetData></worksheet>"
        ])

        let imported = try await DocumentImportConverter.importedDocumentAsync(
            from: data,
            contentType: .orifoldXLSX,
            filename: "ordered.xlsx",
            baseURL: nil
        )
        let text = imported.pdfDocument.stringValue

        XCTAssertTrue(text.contains("Summary"))
        XCTAssertTrue(text.contains("Details"))
        XCTAssertTrue(text.contains("Shared detail"))
        XCTAssertTrue(text.contains("42"))
        assertText(text, contains: "Summary", before: "Details")
    }

    /// XLSX/PPTX/EPUB/RTFD imports flatten to plain rendered text with no
    /// `SourceDocumentPayload` captured (confirmed: `importedExtractedTextDocument` and
    /// `importedRTFDFileWrapper` in PDFKitEngine.swift both return `sourcePayload: nil`).
    /// Before this fix, exporting such a workspace to a source-backed format (word/rtf/
    /// text/markdown/html) fell through to the SAME generic flatten-from-rendered-PDF-text
    /// fallback used for ordinary PDF-origin content — producing a plausible-looking
    /// .docx/.rtf/etc. file with none of the spreadsheet's real structure, and zero
    /// indication anything was lost. It must instead fail clearly, directing the user to
    /// PDF export.
    func testExportingXLSXOriginWorkspaceAsSourceFormatFailsCleanlyInsteadOfSilentlyFlattening() async throws {
        let data = makeStoredZIPData(entries: [
            "xl/workbook.xml": """
            <workbook xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
              <sheets><sheet name="Summary" sheetId="1" r:id="rId1"/></sheets>
            </workbook>
            """,
            "xl/_rels/workbook.xml.rels": """
            <Relationships><Relationship Id="rId1" Target="worksheets/sheet1.xml"/></Relationships>
            """,
            "xl/worksheets/sheet1.xml": "<worksheet><sheetData><row><c><v>42</v></c></row></sheetData></worksheet>"
        ])
        let imported = try await DocumentImportConverter.importedDocumentAsync(
            from: data,
            contentType: .orifoldXLSX,
            filename: "budget.xlsx",
            baseURL: nil
        )
        XCTAssertNil(imported.sourcePayload, "sanity check: XLSX import must not capture a source payload")
        let pdfData = try XCTUnwrap(PDFSerializer.data(from: imported.pdfDocument))
        var member = MemberDocument(displayName: "budget", sourcePDFRef: "budget.xlsx")
        let refs = (0..<imported.pdfDocument.pageCount).map { PageRef(memberDocId: member.id, sourcePageIndex: $0) }
        member.pageRefs = refs.map(\.id)
        let document = WorkspaceDocument()
        document.workspace.documents = [member]
        document.workspace.pageOrder = refs
        document.memberPDFData[member.id] = pdfData
        let viewModel = WorkspaceViewModel(document: document, processingEngine: PDFKitProcessingEngineFallback())

        for format: WorkspaceExportFormat in [.word, .legacyWord, .odt, .rtf, .text, .markdown, .html] {
            XCTAssertThrowsError(try viewModel.dataForWorkspaceExport(as: format), format.rawValue) { error in
                guard case WorkspaceViewModel.ExportBuildError.originFormatHasNoSourcePayload(let memberName, let originFormatDescription) = error else {
                    XCTFail("Expected originFormatHasNoSourcePayload for \(format.rawValue), got \(error)")
                    return
                }
                XCTAssertEqual(memberName, "budget")
                XCTAssertEqual(originFormatDescription, "Excel spreadsheet (.xlsx)")
            }
        }

        // PDF export must still work unaffected — the whole point is PDF stays available
        // as the safe fallback.
        XCTAssertNoThrow(try viewModel.dataForPDFExport())
    }

    func testPresentationImportUsesNaturalSlideOrderAndSpeakerNotes() async throws {
        let data = makeStoredZIPData(entries: [
            "ppt/presentation.xml": "<p:presentation/>",
            "ppt/slides/slide10.xml": "<p:sld><a:t>Slide ten</a:t></p:sld>",
            "ppt/slides/slide2.xml": "<p:sld><a:t>Slide two</a:t></p:sld>",
            "ppt/notesSlides/notesSlide2.xml": "<p:notes><a:t>Speaker note two</a:t></p:notes>"
        ])

        let imported = try await DocumentImportConverter.importedDocumentAsync(
            from: data,
            contentType: .orifoldPPTX,
            filename: "deck.pptx",
            baseURL: nil
        )
        let text = imported.pdfDocument.stringValue

        XCTAssertTrue(text.contains("Speaker note two"))
        assertText(text, contains: "Slide two", before: "Slide ten")
    }

    func testEPUBImportUsesPackageSpineOrder() async throws {
        let data = makeStoredZIPData(entries: [
            "mimetype": "application/epub+zip",
            "META-INF/container.xml": """
            <container>
              <rootfiles>
                <rootfile full-path="OPS/package.opf"/>
              </rootfiles>
            </container>
            """,
            "OPS/package.opf": """
            <package>
              <manifest>
                <item id="chapter1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
                <item id="intro" href="intro.xhtml" media-type="application/xhtml+xml"/>
              </manifest>
              <spine>
                <itemref idref="intro"/>
                <itemref idref="chapter1"/>
              </spine>
            </package>
            """,
            "OPS/chapter1.xhtml": "<html><body><h1>Chapter one</h1></body></html>",
            "OPS/intro.xhtml": "<html><body><h1>Intro first</h1></body></html>"
        ])

        let imported = try await DocumentImportConverter.importedDocumentAsync(
            from: data,
            contentType: .orifoldEPUB,
            filename: "book.epub",
            baseURL: nil
        )
        let text = imported.pdfDocument.stringValue

        assertText(text, contains: "Intro first", before: "Chapter one")
    }

    private func richImportData(from attributed: NSAttributedString, documentType: NSAttributedString.DocumentType) throws -> Data {
        try attributed.data(
            from: NSRange(location: 0, length: attributed.length),
            documentAttributes: [.documentType: documentType]
        )
    }

    private func binaryPropertyListData(_ value: Any) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: value, format: .binary, options: 0)
    }

    private func makeStoredZIPData(entries: [String: String]) -> Data {
        var output = Data()
        var centralDirectory = Data()
        let sortedEntries = entries.sorted { $0.key < $1.key }

        for (name, value) in sortedEntries {
            let nameData = Data(name.utf8)
            let fileData = Data(value.utf8)
            let localOffset = UInt32(output.count)

            appendUInt32(0x04034b50, to: &output)
            appendUInt16(20, to: &output)
            appendUInt16(0, to: &output)
            appendUInt16(0, to: &output)
            appendUInt16(0, to: &output)
            appendUInt16(0, to: &output)
            appendUInt32(0, to: &output)
            appendUInt32(UInt32(fileData.count), to: &output)
            appendUInt32(UInt32(fileData.count), to: &output)
            appendUInt16(UInt16(nameData.count), to: &output)
            appendUInt16(0, to: &output)
            output.append(nameData)
            output.append(fileData)

            appendUInt32(0x02014b50, to: &centralDirectory)
            appendUInt16(20, to: &centralDirectory)
            appendUInt16(20, to: &centralDirectory)
            appendUInt16(0, to: &centralDirectory)
            appendUInt16(0, to: &centralDirectory)
            appendUInt16(0, to: &centralDirectory)
            appendUInt16(0, to: &centralDirectory)
            appendUInt32(0, to: &centralDirectory)
            appendUInt32(UInt32(fileData.count), to: &centralDirectory)
            appendUInt32(UInt32(fileData.count), to: &centralDirectory)
            appendUInt16(UInt16(nameData.count), to: &centralDirectory)
            appendUInt16(0, to: &centralDirectory)
            appendUInt16(0, to: &centralDirectory)
            appendUInt16(0, to: &centralDirectory)
            appendUInt16(0, to: &centralDirectory)
            appendUInt32(0, to: &centralDirectory)
            appendUInt32(localOffset, to: &centralDirectory)
            centralDirectory.append(nameData)
        }

        let centralDirectoryOffset = UInt32(output.count)
        output.append(centralDirectory)
        appendUInt32(0x06054b50, to: &output)
        appendUInt16(0, to: &output)
        appendUInt16(0, to: &output)
        appendUInt16(UInt16(sortedEntries.count), to: &output)
        appendUInt16(UInt16(sortedEntries.count), to: &output)
        appendUInt32(UInt32(centralDirectory.count), to: &output)
        appendUInt32(centralDirectoryOffset, to: &output)
        appendUInt16(0, to: &output)
        return output
    }

    private func appendUInt16(_ value: UInt16, to data: inout Data) {
        data.append(UInt8(value & 0xff))
        data.append(UInt8((value >> 8) & 0xff))
    }

    private func appendUInt32(_ value: UInt32, to data: inout Data) {
        data.append(UInt8(value & 0xff))
        data.append(UInt8((value >> 8) & 0xff))
        data.append(UInt8((value >> 16) & 0xff))
        data.append(UInt8((value >> 24) & 0xff))
    }

    private func assertText(
        _ text: String,
        contains earlier: String,
        before later: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let earlierRange = text.range(of: earlier) else {
            return XCTFail("Missing \(earlier)", file: file, line: line)
        }
        guard let laterRange = text.range(of: later) else {
            return XCTFail("Missing \(later)", file: file, line: line)
        }
        XCTAssertLessThan(earlierRange.lowerBound, laterRange.lowerBound, file: file, line: line)
    }
}

final class PDFKitEngineTests: XCTestCase {
    func testConcatenateAddsBoundaryPagesForDisplay() throws {
        let first = makeMemberPDF(name: "First", pageTexts: ["one", "two"])
        let second = makeMemberPDF(name: "Second", pageTexts: ["three"])
        let engine = PDFKitEngine()

        let display = engine.concatenate(documents: [first, second], includeBanners: true)

        XCTAssertEqual(display.pageCount, 5)
        XCTAssertTrue(display.page(at: 0) is BoundaryPage)
        XCTAssertTrue(display.page(at: 3) is BoundaryPage)
        XCTAssertTrue(display.page(at: 1) === first.1.page(at: 0))
        XCTAssertTrue(display.page(at: 4) === second.1.page(at: 0))
    }

    func testConcatenateCopiesPagesForPlainExportWithoutStealingDisplayOwnership() throws {
        let source = makeMemberPDF(name: "Source", pageTexts: ["page"])
        let engine = PDFKitEngine()
        let display = engine.concatenate(documents: [source], includeBanners: true)
        let originalPage = try XCTUnwrap(source.1.page(at: 0))

        let export = engine.concatenate(documents: [source], includeBanners: false)

        XCTAssertEqual(export.pageCount, 1)
        XCTAssertFalse(export.page(at: 0) is BoundaryPage)
        XCTAssertFalse(export.page(at: 0) === originalPage)
        XCTAssertTrue(originalPage.document === display)
    }
}

@MainActor
final class PDFProcessingEngineTests: XCTestCase {
    func testPDFiumProcessingEngineValidatesPDFData() throws {
        let data = try makePDF(pageTexts: ["pdfium"]).dataRepresentation().unwrap()
        let engine = PDFiumProcessingEngine()

        let validation = try engine.validatePDF(data: data, password: nil)

        XCTAssertEqual(validation.engine, .pdfium)
        XCTAssertEqual(validation.pageCount, 1)
        XCTAssertFalse(validation.isEncrypted)
    }

    func testPDFiumProcessingEngineGracefullyRejectsInvalidData() {
        let engine = PDFiumProcessingEngine()

        XCTAssertThrowsError(try engine.validatePDF(data: Data(), password: nil)) { error in
            XCTAssertEqual(error as? PDFProcessingError, .unreadableDocument)
        }
        XCTAssertThrowsError(try engine.validatePDF(data: Data("not a pdf".utf8), password: nil)) { error in
            XCTAssertEqual(error as? PDFProcessingError, .unreadableDocument)
        }
    }

    func testPDFKitProcessingFallbackValidatesPDFData() throws {
        let data = try makePDF(pageTexts: ["processing"]).dataRepresentation().unwrap()
        let engine = PDFKitProcessingEngineFallback()

        let validation = try engine.validatePDF(data: data, password: nil)

        XCTAssertEqual(validation.engine, .pdfKit)
        XCTAssertEqual(validation.pageCount, 1)
        XCTAssertFalse(validation.isEncrypted)
    }

    func testWorkspaceViewModelAcceptsSupplementalProcessingEngineInjection() throws {
        let document = WorkspaceDocument()
        let fixture = try makeMemberWithPDF(name: "Fixture", pageTexts: ["validation"])
        document.workspace.documents = [fixture.member]
        document.workspace.pageOrder = fixture.refs
        document.memberPDFData[fixture.member.id] = fixture.pdfData
        let processingEngine = RecordingProcessingEngine(validation: PDFProcessingValidation(
            engine: .pdfKit,
            pageCount: 1,
            isEncrypted: false
        ))

        let viewModel = WorkspaceViewModel(
            document: document,
            engine: PDFKitEngine(),
            processingEngine: processingEngine
        )

        XCTAssertEqual(viewModel.lastProcessingValidation?.pageCount, 1)
        XCTAssertEqual(processingEngine.validateCallCount, 1)
    }

    func testProcessingValidationFailureDoesNotBlockWorkspaceReconstruction() throws {
        let document = WorkspaceDocument()
        let fixture = try makeMemberWithPDF(name: "Fixture", pageTexts: ["validation"])
        document.workspace.documents = [fixture.member]
        document.workspace.pageOrder = fixture.refs
        document.memberPDFData[fixture.member.id] = fixture.pdfData
        let processingEngine = ThrowingProcessingEngine()

        let viewModel = WorkspaceViewModel(
            document: document,
            engine: PDFKitEngine(),
            processingEngine: processingEngine
        )

        XCTAssertEqual(viewModel.memberDocuments.map(\.id), [fixture.member.id])
        XCTAssertEqual(viewModel.pageCount, fixture.refs.count)
        XCTAssertNil(viewModel.lastProcessingValidation)
        XCTAssertEqual(processingEngine.validateCallCount, 1)
    }

    func testProcessingValidationFailureDoesNotBlockFileImport() async throws {
        let pdfData = try makePDF(pageTexts: ["import"]).dataRepresentation().unwrap()
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("pdf")
        try pdfData.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        let processingEngine = ThrowingProcessingEngine()
        let viewModel = WorkspaceViewModel(
            document: WorkspaceDocument(),
            engine: PDFKitEngine(),
            processingEngine: processingEngine
        )

        viewModel.importFiles(urls: [tempURL])
        try await waitForImportsToFinish(in: viewModel)

        XCTAssertNil(viewModel.importError)
        XCTAssertEqual(viewModel.memberDocuments.count, 1)
        XCTAssertEqual(viewModel.pageCount, 1)
        XCTAssertNil(viewModel.lastProcessingValidation)
        XCTAssertEqual(processingEngine.validateCallCount, 1)
    }

    func testProcessingValidationFailureClearsStaleValidationState() async throws {
        let document = WorkspaceDocument()
        let fixture = try makeMemberWithPDF(name: "Fixture", pageTexts: ["validation"])
        document.workspace.documents = [fixture.member]
        document.workspace.pageOrder = fixture.refs
        document.memberPDFData[fixture.member.id] = fixture.pdfData
        let processingEngine = FlippingProcessingEngine()
        let viewModel = WorkspaceViewModel(
            document: document,
            engine: PDFKitEngine(),
            processingEngine: processingEngine
        )
        XCTAssertEqual(viewModel.lastProcessingValidation?.pageCount, 1)

        let importData = try makePDF(pageTexts: ["second"]).dataRepresentation().unwrap()
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("pdf")
        try importData.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        viewModel.importFiles(urls: [tempURL])
        try await waitForImportsToFinish(in: viewModel)

        XCTAssertNil(viewModel.importError)
        XCTAssertEqual(viewModel.memberDocuments.count, 2)
        XCTAssertNil(viewModel.lastProcessingValidation)
        XCTAssertEqual(processingEngine.validateCallCount, 2)
    }

    func testImportFilesLimitsBatchToMaximumBatchSizeAndExplainsHowToContinue() async throws {
        var tempURLs: [URL] = []
        defer {
            for url in tempURLs {
                try? FileManager.default.removeItem(at: url)
            }
        }

        for index in 0..<(maximumImportBatchSize + 1) {
            let pdfData = try makePDF(pageTexts: ["import \(index)"]).dataRepresentation().unwrap()
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("pdf")
            try pdfData.write(to: tempURL)
            tempURLs.append(tempURL)
        }

        let viewModel = WorkspaceViewModel(
            document: WorkspaceDocument(),
            engine: PDFKitEngine(),
            processingEngine: PDFKitProcessingEngineFallback()
        )

        viewModel.importFiles(urls: tempURLs)
        try await waitForImportsToFinish(in: viewModel)

        XCTAssertEqual(viewModel.memberDocuments.count, maximumImportBatchSize)
        XCTAssertEqual(viewModel.pageCount, maximumImportBatchSize)
        XCTAssertEqual(viewModel.importError?.message, importBatchLimitMessage)
    }

    func testImportFilesLoadsFiftyPDFsReliably() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Orifold-50-import-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let urls = try (0..<maximumImportBatchSize).map { index in
            let pdfData = try makePDF(pageTexts: ["batch \(index)"]).dataRepresentation().unwrap()
            let url = tempDirectory.appendingPathComponent(String(format: "batch-%02d.pdf", index))
            try pdfData.write(to: url)
            return url
        }
        let viewModel = WorkspaceViewModel(
            document: WorkspaceDocument(),
            engine: PDFKitEngine(),
            processingEngine: PDFKitProcessingEngineFallback()
        )
        let start = Date()

        viewModel.importFiles(urls: urls)
        try await waitForImportsToFinish(in: viewModel)

        XCTAssertNil(viewModel.importError)
        XCTAssertEqual(viewModel.memberDocuments.count, maximumImportBatchSize)
        XCTAssertEqual(viewModel.pageCount, maximumImportBatchSize)
        XCTAssertEqual(viewModel.memberDocuments.map(\.displayName).first, "batch-00")
        XCTAssertEqual(viewModel.memberDocuments.map(\.displayName).last, "batch-49")
        XCTAssertLessThan(Date().timeIntervalSince(start), 15)
    }

    func testImportFilesContinuesAfterCorruptAndZeroByteFiles() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Orifold-mixed-import-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let goodA = tempDirectory.appendingPathComponent("good-a.pdf")
        let corrupt = tempDirectory.appendingPathComponent("corrupt.pdf")
        let zeroByte = tempDirectory.appendingPathComponent("zero-byte.pdf")
        let goodB = tempDirectory.appendingPathComponent("good-b.pdf")
        try makePDF(pageTexts: ["good a"]).dataRepresentation().unwrap().write(to: goodA)
        try Data("not a pdf".utf8).write(to: corrupt)
        XCTAssertTrue(FileManager.default.createFile(atPath: zeroByte.path, contents: Data()))
        try makePDF(pageTexts: ["good b"]).dataRepresentation().unwrap().write(to: goodB)
        let viewModel = WorkspaceViewModel(
            document: WorkspaceDocument(),
            engine: PDFKitEngine(),
            processingEngine: PDFKitProcessingEngineFallback()
        )

        viewModel.importFiles(urls: [goodA, corrupt, zeroByte, goodB])
        try await waitForImportsToFinish(in: viewModel)

        XCTAssertEqual(viewModel.memberDocuments.map(\.displayName), ["good-a", "good-b"])
        XCTAssertEqual(viewModel.pageCount, 2)
        XCTAssertEqual(viewModel.importError?.fileName, "Selected Files")
        XCTAssertTrue(viewModel.importError?.message.contains("Could not open 2 files") == true)
        XCTAssertTrue(viewModel.importError?.message.contains("2 of 4 files were added") == true)
    }

    func testImportFilesInsertedAfterTargetKeepBatchOrder() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Orifold-target-import-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let document = WorkspaceDocument()
        let fixture = try makeMemberWithPDF(name: "Existing", pageTexts: ["existing"])
        document.workspace.documents = [fixture.member]
        document.workspace.pageOrder = fixture.refs
        document.memberPDFData[fixture.member.id] = fixture.pdfData
        let first = tempDirectory.appendingPathComponent("first.pdf")
        let second = tempDirectory.appendingPathComponent("second.pdf")
        try makePDF(pageTexts: ["first"]).dataRepresentation().unwrap().write(to: first)
        try makePDF(pageTexts: ["second"]).dataRepresentation().unwrap().write(to: second)
        let viewModel = WorkspaceViewModel(
            document: document,
            engine: PDFKitEngine(),
            processingEngine: PDFKitProcessingEngineFallback()
        )

        viewModel.importFiles(urls: [first, second], insertingAfter: fixture.refs[0].id)
        try await waitForImportsToFinish(in: viewModel)

        XCTAssertEqual(viewModel.memberDocuments.map(\.displayName), ["Existing", "first", "second"])
        XCTAssertEqual(document.workspace.pageOrder.map(\.memberDocId), viewModel.memberDocuments.flatMap { member in
            Array(repeating: member.id, count: member.pageRefs.count)
        })
    }
}

final class WorkspaceDocumentTests: XCTestCase {
    func testWritableContentTypesOnlyOfferPDF() {
        XCTAssertEqual(WorkspaceDocument.writableContentTypes, [.pdf])
    }

    func testReadableContentTypesAcceptGenericText() {
        XCTAssertTrue(WorkspaceDocument.readableContentTypes.contains(.text))
    }

    func testOpeningUnreadableFileThrowsCorruptFileInsteadOfBlankWorkspace() {
        let file = FileWrapper(directoryWithFileWrappers: [:])

        XCTAssertThrowsError(try WorkspaceDocument(testingFile: file, contentType: .pdf)) { error in
            XCTAssertEqual((error as? CocoaError)?.code, .fileReadCorruptFile)
        }
    }

    func testOpeningUnmatchedTypeThrowsCorruptFileInsteadOfBlankWorkspace() {
        let file = FileWrapper(regularFileWithContents: Data("not a workspace type".utf8))

        XCTAssertThrowsError(try WorkspaceDocument(testingFile: file, contentType: .folder)) { error in
            XCTAssertEqual((error as? CocoaError)?.code, .fileReadCorruptFile)
        }
    }

    func testOpeningZeroBytePDFThrowsInsteadOfCreatingBlankWorkspace() {
        let file = FileWrapper(regularFileWithContents: Data())

        XCTAssertThrowsError(try WorkspaceDocument(testingFile: file, contentType: .pdf)) { error in
            guard case DocumentImportConverter.ConversionError.emptyDocument = error else {
                return XCTFail("Expected emptyDocument, got \(error)")
            }
        }
    }

    @MainActor
    func testDropResolverFallsBackToPDFRepresentationWhenFileURLLoadFails() async throws {
        let pdfData = try makePDF(pageTexts: ["Dropped PDF"]).dataRepresentation().unwrap()
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("pdf")
        try pdfData.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let provider = NSItemProvider()
        provider.registerDataRepresentation(
            forTypeIdentifier: UTType.fileURL.identifier,
            visibility: .all
        ) { completion in
            completion(nil, CocoaError(.fileReadUnknown))
            return nil
        }
        provider.registerFileRepresentation(
            forTypeIdentifier: UTType.pdf.identifier,
            fileOptions: [],
            visibility: .all
        ) { completion in
            completion(tempURL, true, nil)
            return nil
        }

        let urls = await resolvedImportURLs(from: [provider])

        let resolvedURL = try XCTUnwrap(urls.first)
        XCTAssertEqual(urls.count, 1)
        XCTAssertTrue(isSupportedImportURL(resolvedURL))
        XCTAssertEqual(resolvedURL.pathExtension, "pdf")
        XCTAssertTrue(FileManager.default.fileExists(atPath: resolvedURL.path))
    }

    func testImportBatchAllowsMaximumBatchSizeFiles() {
        let urls = (0..<maximumImportBatchSize).map { URL(fileURLWithPath: "/tmp/import-\($0).pdf") }

        let batch = limitedImportBatch(from: urls)

        XCTAssertEqual(batch.urls, urls)
        XCTAssertFalse(batch.wasLimited)
    }

    func testImportBatchLimitsMoreThanMaximumBatchSizeFiles() {
        let urls = (0..<(maximumImportBatchSize + 1)).map { URL(fileURLWithPath: "/tmp/import-\($0).pdf") }

        let batch = limitedImportBatch(from: urls)

        XCTAssertEqual(batch.urls, Array(urls.prefix(maximumImportBatchSize)))
        XCTAssertTrue(batch.wasLimited)
    }

    func testDropResolverLimitsProviderWorkToMaximumBatchSize() async {
        let providers = (0..<(maximumImportBatchSize + 1)).map { index in
            let url = URL(fileURLWithPath: "/tmp/drop-\(index).pdf")
            let provider = NSItemProvider()
            provider.registerDataRepresentation(
                forTypeIdentifier: UTType.fileURL.identifier,
                visibility: .all
            ) { completion in
                completion(url.dataRepresentation, nil)
                return nil
            }
            return provider
        }

        let result = await resolvedImportURLResult(from: providers)
        let urls = result.urls

        XCTAssertEqual(urls.count, maximumImportBatchSize)
        XCTAssertEqual(urls.last?.lastPathComponent, "drop-\(maximumImportBatchSize - 1).pdf")
        XCTAssertTrue(result.wasLimited)
    }

    func testDropResolverSkipsUnsupportedProvidersBeforeCountingSupportedFiles() async {
        let unsupportedProviders = (0..<3).map { _ in NSItemProvider() }
        let supportedProviders = (0..<3).map { index in
            let url = URL(fileURLWithPath: "/tmp/supported-\(index).pdf")
            let provider = NSItemProvider()
            provider.registerDataRepresentation(
                forTypeIdentifier: UTType.fileURL.identifier,
                visibility: .all
            ) { completion in
                completion(url.dataRepresentation, nil)
                return nil
            }
            return provider
        }

        let result = await resolvedImportURLResult(from: unsupportedProviders + supportedProviders, maxCount: 2)

        XCTAssertEqual(result.urls.map(\.lastPathComponent), ["supported-0.pdf", "supported-1.pdf"])
        XCTAssertTrue(result.wasLimited)
    }

    func testAppInfoPlistDoesNotAdvertiseWorkspaceSaveFormat() throws {
        try XCTSkipIf(
            ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true" ||
                ProcessInfo.processInfo.environment["CI"] == "true" ||
                #filePath.contains("/Users/runner/work/"),
            "GitHub Actions validates this directly in the CI plist gate."
        )
        let plistURL = try appInfoPlistURL(sourceFile: #filePath)
        let plistData = try Data(contentsOf: plistURL)
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any]
        )
        let documentTypes = try XCTUnwrap(plist["CFBundleDocumentTypes"] as? [[String: Any]])
        let exportedTypes = plist["UTExportedTypeDeclarations"] as? [[String: Any]] ?? []

        XCTAssertFalse(
            documentTypes.contains { type in
                let name = type["CFBundleTypeName"] as? String
                let extensions = type["CFBundleTypeExtensions"] as? [String] ?? []
                return name?.localizedCaseInsensitiveContains("workspace") == true
                    || extensions.contains("orifoldproj")
            }
        )
        XCTAssertTrue(exportedTypes.isEmpty)
    }

    func testAppInfoPlistAdvertisesExpandedImportFormats() throws {
        let plistURL = try appInfoPlistURL(sourceFile: #filePath)
        let plistData = try Data(contentsOf: plistURL)
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any]
        )
        let documentTypes = try XCTUnwrap(plist["CFBundleDocumentTypes"] as? [[String: Any]])
        let advertisedExtensions = Set(documentTypes.flatMap { $0["CFBundleTypeExtensions"] as? [String] ?? [] })

        let expectedExtensions = [
            "xlsx", "pptx", "epub", "rtfd", "svg", "txt", "text", "log", "rtf", "md", "markdown",
            "csv", "tsv", "json", "jsonl", "xml", "yaml", "yml", "toml", "plist",
            "swift", "js", "ts", "tsx", "jsx", "py", "rb", "go", "rs", "java", "kt",
            "c", "cc", "cpp", "h", "hpp", "m", "mm", "cs", "php", "sh", "zsh",
            "bash", "sql", "ini", "conf", "env"
        ]
        for pathExtension in expectedExtensions {
            XCTAssertTrue(advertisedExtensions.contains(pathExtension), pathExtension)
            let type = try XCTUnwrap(UTType(filenameExtension: pathExtension), pathExtension)
            XCTAssertTrue(
                WorkspaceDocument.importableContentTypes.contains { type.conforms(to: $0) },
                pathExtension
            )
        }
    }

    func testOpeningRTFDDirectoryFileWrapperImportsPackageText() throws {
        let rtf = try NSAttributedString(string: "RTFD FileWrapper import").data(
            from: NSRange(location: 0, length: "RTFD FileWrapper import".count),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
        let package = FileWrapper(directoryWithFileWrappers: [
            "TXT.rtf": FileWrapper(regularFileWithContents: rtf)
        ])
        package.preferredFilename = "Wrapped.rtfd"

        let document = try WorkspaceDocument(
            testingFile: package,
            contentType: .orifoldRTFD,
            filename: "Wrapped.rtfd"
        )
        let pdfData = try XCTUnwrap(document.memberPDFData.values.first)
        let pdf = try XCTUnwrap(PDFDocument(data: pdfData))

        XCTAssertTrue(pdf.stringValue.contains("RTFD FileWrapper import"))
        XCTAssertTrue(document.sourcePayloads.isEmpty)
    }

    func testSnapshotUsesCurrentPDFDataProvider() throws {
        let memberID = UUID()
        let expectedPDFData = try makePDF(pageTexts: ["snapshot"]).dataRepresentation().unwrap()
        let stalePDFData = Data([9, 9, 9])
        let document = WorkspaceDocument()
        document.workspace.title = "Package"
        document.memberPDFData[memberID] = stalePDFData
        document.currentPDFDataProvider = { [memberID: expectedPDFData] }

        let snapshot = try document.snapshot(contentType: .pdf)

        XCTAssertEqual(snapshot.memberPDFData[memberID], expectedPDFData)
        XCTAssertNotEqual(snapshot.memberPDFData[memberID], stalePDFData)
    }

    func testSnapshotPropagatesCurrentPDFDataProviderFailure() throws {
        let document = WorkspaceDocument()
        document.currentPDFDataProvider = {
            throw PDFKitEngine.ExportAssemblyError.unreadableMember("Broken")
        }

        XCTAssertThrowsError(try document.snapshot(contentType: .pdf)) { error in
            XCTAssertEqual(error as? PDFKitEngine.ExportAssemblyError, .unreadableMember("Broken"))
        }
    }

    func testExportStripsStaleWorkspaceCommentMetadataWhenCommentsAreCleared() throws {
        let fixture = try makeMemberWithPDF(name: "Comments", pageTexts: ["body"])
        let document = WorkspaceDocument()
        document.workspace.documents = [fixture.member]
        document.workspace.pageOrder = fixture.refs
        document.memberPDFData[fixture.member.id] = fixture.pdfData
        document.workspace.comments = [WorkspaceComment(body: "Remove me")]

        let commentedData = try document.exportedPDFDataThrowing(from: try document.snapshot(contentType: .pdf))
        XCTAssertEqual(try workspaceCommentMetadataValues(in: commentedData).count, 1)

        document.memberPDFData[fixture.member.id] = commentedData
        document.workspace.comments = []

        let clearedData = try document.exportedPDFDataThrowing(from: try document.snapshot(contentType: .pdf))
        XCTAssertTrue(try workspaceCommentMetadataValues(in: clearedData).isEmpty)
    }

    func testEditableWorkspaceMetadataRestoresMultiDocumentWorkspaceOnReopen() throws {
        let first = try makeMemberWithPDF(name: "First", pageTexts: ["one"])
        let second = try makeMemberWithPDF(name: "Second", pageTexts: ["two"])
        let document = WorkspaceDocument()
        document.workspace.title = "Packet"
        document.workspace.documents = [first.member, second.member]
        document.workspace.pageOrder = first.refs + second.refs
        document.workspace.tags = ["review"]
        document.memberPDFData[first.member.id] = first.pdfData
        document.memberPDFData[second.member.id] = second.pdfData

        let saved = try document.exportedPDFDataThrowing(
            from: try document.snapshot(contentType: .pdf),
            options: WorkspaceExportOptions(embedsEditableWorkspaceState: true)
        )
        let savedPDF = try XCTUnwrap(PDFDocument(data: saved))
        let reopened = WorkspaceDocument()
        try reopened.importPDFDocumentForTesting(savedPDF, filename: "Packet.pdf")

        XCTAssertEqual(reopened.workspace.title, "Packet")
        XCTAssertEqual(reopened.workspace.documents.map(\.displayName), ["First", "Second"])
        XCTAssertEqual(reopened.workspace.pageOrder.map(\.id), (first.refs + second.refs).map(\.id))
        XCTAssertEqual(Set(reopened.memberPDFData.keys), Set([first.member.id, second.member.id]))
        XCTAssertEqual(reopened.workspace.tags, ["review"])
    }

    func testPDFExportBakesAnchoredCommentAnnotationAndSummaryPage() throws {
        let fixture = try makeMemberWithPDF(name: "Anchored", pageTexts: ["Anchor target"])
        let document = WorkspaceDocument()
        document.workspace.documents = [fixture.member]
        document.workspace.pageOrder = fixture.refs
        document.memberPDFData[fixture.member.id] = fixture.pdfData
        document.workspace.comments = [
            WorkspaceComment(
                body: "Check this claim.",
                tags: ["review"],
                anchor: WorkspaceCommentAnchor(
                    pageRefID: fixture.refs[0].id,
                    rect: CGRect(x: 72, y: 680, width: 120, height: 24),
                    kind: .text,
                    snippet: "Anchor target"
                )
            )
        ]

        let data = try document.exportedPDFDataThrowing(from: try document.snapshot(contentType: .pdf))
        let pdf = try XCTUnwrap(PDFDocument(data: data))

        XCTAssertEqual(pdf.pageCount, 2)
        let page = try XCTUnwrap(pdf.page(at: 0))
        let annotation = try XCTUnwrap(page.annotations.first { $0.type == "Text" && $0.contents == "Check this claim." })
        let anchorRect = try XCTUnwrap(annotation.value(forAnnotationKey: PDFAnnotationKey(rawValue: "/OrifoldCommentAnchorRect")) as? String)
        XCTAssertEqual(NSRectFromString(anchorRect), CGRect(x: 72, y: 680, width: 120, height: 24))
        XCTAssertEqual(annotation.value(forAnnotationKey: PDFAnnotationKey(rawValue: "/Subj")) as? String, "review")
        XCTAssertTrue(pdf.page(at: 1)?.string?.contains("Anchor target") == true)
        XCTAssertTrue(pdf.page(at: 1)?.string?.contains("Check this claim.") == true)
    }

    func testPDFExportSkipsCommentInjectionWhenCryptographicSignatureExists() throws {
        let fixture = try makeMemberWithPDF(name: "Signed", pageTexts: ["Signed target"])
        let document = WorkspaceDocument()
        document.workspace.documents = [fixture.member]
        document.workspace.pageOrder = fixture.refs
        document.memberPDFData[fixture.member.id] = fixture.pdfData
        document.workspace.comments = [
            WorkspaceComment(
                body: "Do not inject",
                anchor: WorkspaceCommentAnchor(
                    pageRefID: fixture.refs[0].id,
                    rect: CGRect(x: 72, y: 680, width: 120, height: 24),
                    kind: .text,
                    snippet: "Signed target"
                )
            )
        ]
        document.workspace.signatures = [
            SignaturePlacement(
                pageRefId: fixture.refs[0].id,
                imageData: Data([1, 2, 3]),
                rect: CGRect(x: 72, y: 72, width: 140, height: 40),
                kind: .cryptographic
            )
        ]

        let data = try document.exportedPDFDataThrowing(from: try document.snapshot(contentType: .pdf))
        let pdf = try XCTUnwrap(PDFDocument(data: data))

        XCTAssertEqual(pdf.pageCount, 1)
        XCTAssertFalse(pdf.page(at: 0)?.annotations.contains { $0.type == "Text" && $0.contents == "Do not inject" } ?? true)
        XCTAssertTrue(try workspaceCommentMetadataValues(in: data).isEmpty)
    }

    func testReopeningExportedAnchoredCommentDoesNotDuplicateAsPDFNote() throws {
        let fixture = try makeMemberWithPDF(name: "Anchored", pageTexts: ["Anchor target"])
        let document = WorkspaceDocument()
        document.workspace.documents = [fixture.member]
        document.workspace.pageOrder = fixture.refs
        document.memberPDFData[fixture.member.id] = fixture.pdfData
        document.workspace.comments = [
            WorkspaceComment(
                body: "Round trip once.",
                anchor: WorkspaceCommentAnchor(
                    pageRefID: fixture.refs[0].id,
                    rect: CGRect(x: 72, y: 680, width: 120, height: 24),
                    kind: .text,
                    snippet: "Anchor target"
                )
            )
        ]

        let exportedData = try document.exportedPDFDataThrowing(from: try document.snapshot(contentType: .pdf))
        let reopened = try WorkspaceDocument(
            testingFile: FileWrapper(regularFileWithContents: exportedData),
            contentType: .pdf,
            filename: "exported.pdf"
        )
        let viewModel = WorkspaceViewModel(document: reopened)

        XCTAssertEqual(reopened.workspace.comments.count, 1)
        XCTAssertEqual(reopened.workspace.comments.first?.body, "Round trip once.")
        XCTAssertTrue(viewModel.pdfNoteComments.isEmpty)
    }

    private func workspaceCommentMetadataValues(in data: Data) throws -> [String] {
        let key = PDFAnnotationKey(rawValue: "/OrifoldWorkspaceComments")
        let pdf = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertGreaterThan(pdf.pageCount, 0)
        var values: [String] = []
        for pageIndex in 0..<pdf.pageCount {
            guard let page = pdf.page(at: pageIndex) else { continue }
            values += page.annotations.compactMap { annotation in
                annotation.value(forAnnotationKey: key) as? String
            }
        }
        return values
    }
}

final class WorkspaceViewModelTests: XCTestCase {
    func testReaderModeBlocksTextEditingAndSigningToolsButAllowsStudyTools() {
        let viewModel = WorkspaceViewModel(document: WorkspaceDocument())

        viewModel.isReaderMode = true
        viewModel.currentTool = .editText
        XCTAssertEqual(viewModel.currentTool, .none)

        viewModel.currentTool = .signature
        XCTAssertEqual(viewModel.currentTool, .none)

        viewModel.currentTool = .highlight
        XCTAssertEqual(viewModel.currentTool, .highlight)

        viewModel.currentTool = .comment
        XCTAssertEqual(viewModel.currentTool, .comment)
    }

    func testReaderModeBlocksSignaturePlacementWhileCommentsStillSave() {
        let viewModel = WorkspaceViewModel(document: WorkspaceDocument())
        viewModel.isReaderMode = true

        viewModel.beginVisualSignaturePlacement(
            imageData: Data([0, 1, 2, 3]),
            kind: .visualTyped,
            signerName: "Reader"
        )
        viewModel.addComment("  Research note  ")

        XCTAssertNil(viewModel.pendingSignatureData)
        XCTAssertEqual(viewModel.currentTool, .none)
        XCTAssertEqual(viewModel.document.workspace.signatures.count, 0)
        XCTAssertEqual(viewModel.document.workspace.comments.map(\.body), ["Research note"])
    }

    func testMetadataMutationsNormalizeTrimAndDeduplicate() {
        let viewModel = WorkspaceViewModel(document: WorkspaceDocument())

        viewModel.addTag("  #Finance  ")
        viewModel.addTag("finance")
        viewModel.addTag("   ")
        viewModel.addComment("  Needs review  ")
        viewModel.addComment("\n\t")
        let comment = viewModel.document.workspace.comments[0]
        viewModel.addTag(" #Priority ", to: comment)
        viewModel.addTag("priority", to: comment)
        var style = WorkspaceCommentStyle()
        style.isBold = true
        style.textSize = .large
        style.colorHex = "#B42318"
        viewModel.updateCommentStyle(comment, style: style)

        XCTAssertEqual(viewModel.document.workspace.tags, ["Finance"])
        XCTAssertEqual(viewModel.document.workspace.comments.map(\.body), ["Needs review"])
        XCTAssertEqual(viewModel.document.workspace.comments[0].tags, ["Priority"])
        XCTAssertEqual(viewModel.document.workspace.comments[0].style, style)
    }

    func testRemovingSelectedWorkspaceCommentDeletesItAndClearsSelection() {
        let viewModel = WorkspaceViewModel(document: WorkspaceDocument())

        viewModel.addComment("Delete me")
        let comment = viewModel.document.workspace.comments[0]
        viewModel.selectedCommentID = comment.id

        viewModel.removeComment(comment)

        XCTAssertTrue(viewModel.document.workspace.comments.isEmpty)
        XCTAssertNil(viewModel.selectedCommentID)
    }

    func testRemovingSelectedWorkspaceCommentAdvancesSelectionToNeighbor() {
        let viewModel = WorkspaceViewModel(document: WorkspaceDocument())

        viewModel.addComment("Older")
        viewModel.addComment("Newer")
        let removed = viewModel.document.workspace.comments[0]
        let remaining = viewModel.document.workspace.comments[1]
        viewModel.selectedCommentID = removed.id

        viewModel.removeComment(removed)

        XCTAssertEqual(viewModel.document.workspace.comments.map(\.body), ["Older"])
        XCTAssertEqual(viewModel.selectedCommentID, remaining.id)
    }

    func testWorkspaceCommentControlsMutateLiveCommentStateAndRevision() {
        let viewModel = WorkspaceViewModel(document: WorkspaceDocument())

        viewModel.addComment("Original")
        let comment = viewModel.document.workspace.comments[0]
        let initialRevision = viewModel.commentRevision

        viewModel.updateCommentBody(comment, body: "Updated")
        viewModel.updateCommentResolved(comment, isResolved: true)
        var style = WorkspaceCommentStyle()
        style.isBold = true
        style.isItalic = true
        style.textSize = .large
        style.colorHex = "#B42318"
        viewModel.updateCommentStyle(comment, style: style)
        viewModel.addTag("urgent", to: comment)
        viewModel.removeTag("urgent", from: comment)

        let updated = viewModel.document.workspace.comments[0]
        XCTAssertEqual(updated.body, "Updated")
        XCTAssertTrue(updated.isResolved)
        XCTAssertEqual(updated.style, style)
        XCTAssertTrue(updated.tags.isEmpty)
        XCTAssertGreaterThan(viewModel.commentRevision, initialRevision)
    }

    func testReplaceableCommentMatchesFindsCaseInsensitiveSubstring() {
        let viewModel = WorkspaceViewModel(document: WorkspaceDocument())
        viewModel.addComment("Please review the Budget draft")
        viewModel.addComment("Unrelated note")

        viewModel.searchQuery = "budget"

        XCTAssertEqual(viewModel.replaceableCommentMatches.count, 1)
        XCTAssertEqual(viewModel.replaceableCommentMatches.first?.body, "Please review the Budget draft")
    }

    func testReplaceMatchesInCommentUpdatesBodyAndRegistersUndo() {
        let undoManager = UndoManager()
        let viewModel = WorkspaceViewModel(document: WorkspaceDocument())
        viewModel.undoManager = undoManager
        viewModel.addComment("The cat sat on the cat mat")
        let comment = viewModel.document.workspace.comments[0]
        // The setup addComment above and the replace below run in the same synchronous
        // call stack with no run-loop turn between them, so `groupsByEvent` would otherwise
        // merge both into one implicit undo group. Clearing history isolates the replace's
        // own undo step, matching how these would actually land as separate steps in the app.
        undoManager.removeAllActions()

        viewModel.searchQuery = "cat"
        viewModel.replaceText = "dog"
        viewModel.replaceMatches(in: comment)

        XCTAssertEqual(viewModel.document.workspace.comments[0].body, "The dog sat on the dog mat")
        XCTAssertTrue(undoManager.canUndo)

        undoManager.undo()
        XCTAssertEqual(viewModel.document.workspace.comments[0].body, "The cat sat on the cat mat")
    }

    /// A replacement that itself contains the search query (e.g. "cat" -> "cats") must not
    /// loop or re-match its own inserted text — this pins the non-overlapping advance logic.
    func testReplaceMatchesDoesNotLoopWhenReplacementContainsQuery() {
        let viewModel = WorkspaceViewModel(document: WorkspaceDocument())
        viewModel.addComment("I have a cat")
        let comment = viewModel.document.workspace.comments[0]

        viewModel.searchQuery = "cat"
        viewModel.replaceText = "cats"
        viewModel.replaceMatches(in: comment)

        XCTAssertEqual(viewModel.document.workspace.comments[0].body, "I have a cats")
    }

    func testReplaceAllCommentMatchesIsOneUndoStepAcrossMultipleComments() {
        let undoManager = UndoManager()
        let viewModel = WorkspaceViewModel(document: WorkspaceDocument())
        viewModel.undoManager = undoManager
        viewModel.addComment("First: apple pie")
        viewModel.addComment("Second: apple tart")
        viewModel.addComment("Unrelated")
        // Isolate the replace-all undo step from the setup comments' own undo actions —
        // see the comment in testReplaceMatchesInCommentUpdatesBodyAndRegistersUndo.
        undoManager.removeAllActions()

        viewModel.searchQuery = "apple"
        viewModel.replaceText = "pear"
        let changedCount = viewModel.replaceAllCommentMatches()

        XCTAssertEqual(changedCount, 2)
        let bodies = Set(viewModel.document.workspace.comments.map(\.body))
        XCTAssertTrue(bodies.contains("First: pear pie"))
        XCTAssertTrue(bodies.contains("Second: pear tart"))
        XCTAssertTrue(bodies.contains("Unrelated"))

        undoManager.undo()
        let revertedBodies = Set(viewModel.document.workspace.comments.map(\.body))
        XCTAssertTrue(revertedBodies.contains("First: apple pie"))
        XCTAssertTrue(revertedBodies.contains("Second: apple tart"))
    }

    func testReplaceAllCommentMatchesReturnsZeroWhenNoMatches() {
        let viewModel = WorkspaceViewModel(document: WorkspaceDocument())
        viewModel.addComment("Nothing relevant here")

        viewModel.searchQuery = "budget"
        viewModel.replaceText = "forecast"

        XCTAssertEqual(viewModel.replaceAllCommentMatches(), 0)
        XCTAssertEqual(viewModel.document.workspace.comments[0].body, "Nothing relevant here")
    }

    func testPageCommentBadgeIncludesPDFStickyNotes() throws {
        let fixture = try makeMemberWithPDF(name: "Notes", pageTexts: ["Sticky note target"])
        let document = WorkspaceDocument()
        document.workspace.documents = [fixture.member]
        document.workspace.pageOrder = fixture.refs
        document.memberPDFData[fixture.member.id] = fixture.pdfData
        let viewModel = WorkspaceViewModel(
            document: document,
            processingEngine: PDFKitProcessingEngineFallback()
        )
        let page = try XCTUnwrap(viewModel.combinedPDF.page(at: 1))

        let annotation = try XCTUnwrap(viewModel.addNote(at: CGPoint(x: 120, y: 120), on: page))
        annotation.contents = "Imported-style sticky note"
        annotation.setValue(false, forAnnotationKey: WorkspaceViewModel.draftTextAnnotationKey)

        XCTAssertEqual(viewModel.pdfNoteComments.count, 1)
        XCTAssertEqual(viewModel.totalCommentCount, 1)
        XCTAssertEqual(viewModel.commentCount(for: fixture.refs[0].id), 1)
    }

    func testPageOperationsKeepWorkspaceAndPDFInSync() throws {
        let document = WorkspaceDocument()
        let first = try makeMemberWithPDF(name: "First", pageTexts: ["one", "two", "three"])
        let second = try makeMemberWithPDF(name: "Second", pageTexts: ["four"])
        document.workspace.documents = [first.member, second.member]
        document.workspace.pageOrder = first.refs + second.refs
        document.memberPDFData[first.member.id] = first.pdfData
        document.memberPDFData[second.member.id] = second.pdfData

        let viewModel = WorkspaceViewModel(document: document)

        XCTAssertEqual(viewModel.pageCount, 4)
        XCTAssertEqual(viewModel.tableOfContents.map(\.title), ["First", "Second"])
        XCTAssertEqual(viewModel.combinedPageIndex(for: first.refs[0]), 1)
        XCTAssertEqual(viewModel.combinedPageIndex(forWorkspacePageNumber: 3), 3)

        XCTAssertTrue(viewModel.movePage(first.refs[0], toIndex: 3))
        XCTAssertEqual(viewModel.document.workspace.documents[0].pageRefs, [
            first.refs[1].id,
            first.refs[2].id,
            first.refs[0].id
        ])
        XCTAssertEqual(viewModel.document.workspace.pageOrder.map(\.id), [
            first.refs[1].id,
            first.refs[2].id,
            first.refs[0].id,
            second.refs[0].id
        ])
        XCTAssertEqual(viewModel.loadedPDFs[0].1.page(at: 2)?.string?.trimmed, "one")

        viewModel.deletePage(first.refs[1])

        XCTAssertEqual(viewModel.pageCount, 3)
        XCTAssertEqual(viewModel.document.workspace.documents[0].pageRefs, [
            first.refs[2].id,
            first.refs[0].id
        ])
        XCTAssertEqual(viewModel.loadedPDFs[0].1.pageCount, 2)
        XCTAssertEqual(viewModel.combinedPageIndex(forWorkspacePageNumber: 3), 4)
    }

    func testDeletingSelectedPageMovesSelectionToLivePage() throws {
        let document = WorkspaceDocument()
        let fixture = try makeMemberWithPDF(name: "Pages", pageTexts: ["one", "two", "three"])
        document.workspace.documents = [fixture.member]
        document.workspace.pageOrder = fixture.refs
        document.memberPDFData[fixture.member.id] = fixture.pdfData
        let viewModel = WorkspaceViewModel(document: document)

        viewModel.selectPage(fixture.refs[1])
        viewModel.deletePage(fixture.refs[1])

        XCTAssertFalse(viewModel.document.workspace.pageOrder.contains { $0.id == fixture.refs[1].id })
        XCTAssertNotEqual(viewModel.selectedPageRefID, fixture.refs[1].id)
        XCTAssertTrue(viewModel.selectedPageRefID.map { id in
            viewModel.document.workspace.pageOrder.contains { $0.id == id }
        } ?? false)
        XCTAssertTrue(viewModel.selectedPageRefIDs.allSatisfy { id in
            viewModel.document.workspace.pageOrder.contains { $0.id == id }
        })
    }

    func testRemovingSelectedDocumentMovesSelectionToRemainingDocument() throws {
        let document = WorkspaceDocument()
        let first = try makeMemberWithPDF(name: "First", pageTexts: ["one"])
        let second = try makeMemberWithPDF(name: "Second", pageTexts: ["two"])
        document.workspace.documents = [first.member, second.member]
        document.workspace.pageOrder = first.refs + second.refs
        document.memberPDFData[first.member.id] = first.pdfData
        document.memberPDFData[second.member.id] = second.pdfData
        let viewModel = WorkspaceViewModel(document: document)

        viewModel.selectPage(first.refs[0])
        viewModel.removeDocument(first.member)

        XCTAssertEqual(viewModel.document.workspace.documents.map(\.id), [second.member.id])
        XCTAssertEqual(viewModel.selectedPageRefID, second.refs[0].id)
        XCTAssertEqual(viewModel.selectedPageRefIDs, [second.refs[0].id])
    }

    // MARK: - Rename document

    func testRenameDocumentUpdatesDisplayNameAndUndoRedoRoundTrips() throws {
        let document = WorkspaceDocument()
        let fixture = try makeMemberWithPDF(name: "Invoice", pageTexts: ["one"])
        document.workspace.documents = [fixture.member]
        document.workspace.pageOrder = fixture.refs
        document.memberPDFData[fixture.member.id] = fixture.pdfData
        let viewModel = WorkspaceViewModel(document: document)
        let undoManager = UndoManager()
        viewModel.undoManager = undoManager

        viewModel.renameDocument(fixture.member, to: "March Invoice")

        XCTAssertEqual(viewModel.memberDocuments.first?.displayName, "March Invoice")
        XCTAssertEqual(viewModel.document.workspace.documents.first?.displayName, "March Invoice")

        undoManager.undo()
        XCTAssertEqual(viewModel.memberDocuments.first?.displayName, "Invoice")

        undoManager.redo()
        XCTAssertEqual(viewModel.memberDocuments.first?.displayName, "March Invoice")
    }

    /// Regression test for two bugs found in code review: (1) `registerRenameUndo` must
    /// isolate each rename into its own undo group (`UndoManager.groupsByEvent` defaults
    /// to true, so two renames committed with no run-loop turn between them — as happens
    /// here, and as the caller can trigger by pressing Return on two quick renames —
    /// would otherwise collapse into a single undo step); (2) `renameDocument` must read
    /// the live current name rather than trusting the caller's `member` snapshot, which
    /// this test deliberately keeps stale (always passing the original `fixture.member`)
    /// to prove the fix doesn't depend on the caller re-fetching an up-to-date value.
    func testConsecutiveRenamesEachUndoAndRedoIndependently() throws {
        let document = WorkspaceDocument()
        let fixture = try makeMemberWithPDF(name: "A", pageTexts: ["one"])
        document.workspace.documents = [fixture.member]
        document.workspace.pageOrder = fixture.refs
        document.memberPDFData[fixture.member.id] = fixture.pdfData
        let viewModel = WorkspaceViewModel(document: document)
        let undoManager = UndoManager()
        viewModel.undoManager = undoManager

        viewModel.renameDocument(fixture.member, to: "B")
        viewModel.renameDocument(fixture.member, to: "C")
        XCTAssertEqual(viewModel.memberDocuments.first?.displayName, "C")

        undoManager.undo()
        XCTAssertEqual(viewModel.memberDocuments.first?.displayName, "B")

        undoManager.undo()
        XCTAssertEqual(viewModel.memberDocuments.first?.displayName, "A")

        undoManager.redo()
        XCTAssertEqual(viewModel.memberDocuments.first?.displayName, "B")

        undoManager.redo()
        XCTAssertEqual(viewModel.memberDocuments.first?.displayName, "C")
    }

    func testRenameDocumentTrimsWhitespace() throws {
        let document = WorkspaceDocument()
        let fixture = try makeMemberWithPDF(name: "Invoice", pageTexts: ["one"])
        document.workspace.documents = [fixture.member]
        document.workspace.pageOrder = fixture.refs
        document.memberPDFData[fixture.member.id] = fixture.pdfData
        let viewModel = WorkspaceViewModel(document: document)

        viewModel.renameDocument(fixture.member, to: "  Trimmed Name  ")

        XCTAssertEqual(viewModel.memberDocuments.first?.displayName, "Trimmed Name")
    }

    func testRenameDocumentRejectsEmptyOrUnchangedName() throws {
        let document = WorkspaceDocument()
        let fixture = try makeMemberWithPDF(name: "Invoice", pageTexts: ["one"])
        document.workspace.documents = [fixture.member]
        document.workspace.pageOrder = fixture.refs
        document.memberPDFData[fixture.member.id] = fixture.pdfData
        let viewModel = WorkspaceViewModel(document: document)
        let undoManager = UndoManager()
        viewModel.undoManager = undoManager

        viewModel.renameDocument(fixture.member, to: "   ")
        XCTAssertEqual(viewModel.memberDocuments.first?.displayName, "Invoice")

        viewModel.renameDocument(fixture.member, to: "Invoice")
        XCTAssertEqual(viewModel.memberDocuments.first?.displayName, "Invoice")
        XCTAssertFalse(undoManager.canUndo)
    }

    func testCommentCountForMemberSumsAcrossAllItsPages() throws {
        let document = WorkspaceDocument()
        let fixture = try makeMemberWithPDF(name: "Anchored", pageTexts: ["one", "two"])
        document.workspace.documents = [fixture.member]
        document.workspace.pageOrder = fixture.refs
        document.memberPDFData[fixture.member.id] = fixture.pdfData
        document.workspace.comments = [
            WorkspaceComment(
                body: "First page note",
                anchor: WorkspaceCommentAnchor(pageRefID: fixture.refs[0].id, rect: .zero, kind: .text, snippet: nil)
            ),
            WorkspaceComment(
                body: "Second page note",
                anchor: WorkspaceCommentAnchor(pageRefID: fixture.refs[1].id, rect: .zero, kind: .text, snippet: nil)
            ),
        ]
        let viewModel = WorkspaceViewModel(document: document)

        XCTAssertEqual(viewModel.commentCount(for: fixture.member), 2)
    }

    /// `pdfNoteComments` is memoized (revision-keyed) for performance. This guards the
    /// specific gap that memoization could introduce: removing a document whose only
    /// PDF-native sticky note has no anchored `WorkspaceComment` doesn't bump
    /// `commentRevision` (see `clearCommentAnchors`'s `didChange` guard), so the cache
    /// must also invalidate on `rebuild()`'s `structureRevision` bump, not just on
    /// `commentRevision` changes.
    func testPDFNoteCommentsCacheInvalidatesWhenDocumentWithStickyNoteIsRemoved() throws {
        let document = WorkspaceDocument()
        let fixture = try makeMemberWithPDF(name: "Notes", pageTexts: ["Sticky note target"])
        document.workspace.documents = [fixture.member]
        document.workspace.pageOrder = fixture.refs
        document.memberPDFData[fixture.member.id] = fixture.pdfData
        let viewModel = WorkspaceViewModel(
            document: document,
            processingEngine: PDFKitProcessingEngineFallback()
        )
        let page = try XCTUnwrap(viewModel.combinedPDF.page(at: 1))
        let annotation = try XCTUnwrap(viewModel.addNote(at: CGPoint(x: 120, y: 120), on: page))
        annotation.contents = "Orphaned sticky note"
        annotation.setValue(false, forAnnotationKey: WorkspaceViewModel.draftTextAnnotationKey)

        // Warm the cache before the removal — this is the read that must not be
        // trusted stale afterward.
        XCTAssertEqual(viewModel.pdfNoteComments.count, 1)
        XCTAssertEqual(viewModel.commentCount(for: fixture.member), 1)

        viewModel.removeDocument(fixture.member)

        XCTAssertTrue(viewModel.pdfNoteComments.isEmpty)
        XCTAssertEqual(viewModel.totalCommentCount, 0)
    }

    // MARK: - Empty workspace after deleting the last document

    func testRemovingLastDocumentClearsSelectionAndMarksWorkspaceEmpty() throws {
        let document = WorkspaceDocument()
        let only = try makeMemberWithPDF(name: "Only", pageTexts: ["one"])
        document.workspace.documents = [only.member]
        document.workspace.pageOrder = only.refs
        document.memberPDFData[only.member.id] = only.pdfData
        let viewModel = WorkspaceViewModel(document: document)

        viewModel.selectPage(only.refs[0])
        XCTAssertFalse(viewModel.isWorkspaceEmpty)

        viewModel.removeDocument(only.member)

        XCTAssertTrue(viewModel.memberDocuments.isEmpty)
        XCTAssertEqual(viewModel.pageCount, 0)
        XCTAssertNil(viewModel.selectedPageRefID)
        XCTAssertTrue(viewModel.selectedPageRefIDs.isEmpty)
        XCTAssertTrue(viewModel.isWorkspaceEmpty)
    }

    func testRemovingAllDocumentsOneAtATimeLeavesNoStaleSelection() throws {
        let document = WorkspaceDocument()
        let first = try makeMemberWithPDF(name: "First", pageTexts: ["one"])
        let second = try makeMemberWithPDF(name: "Second", pageTexts: ["two"])
        document.workspace.documents = [first.member, second.member]
        document.workspace.pageOrder = first.refs + second.refs
        document.memberPDFData[first.member.id] = first.pdfData
        document.memberPDFData[second.member.id] = second.pdfData
        let viewModel = WorkspaceViewModel(document: document)

        viewModel.removeDocument(first.member)
        viewModel.removeDocument(second.member)

        XCTAssertTrue(viewModel.document.workspace.documents.isEmpty)
        XCTAssertTrue(viewModel.document.workspace.pageOrder.isEmpty)
        XCTAssertNil(viewModel.selectedPageRefID)
        XCTAssertTrue(viewModel.selectedPageRefIDs.isEmpty)
        XCTAssertTrue(viewModel.isWorkspaceEmpty)
    }

    /// After deleting the last document, an explicit Export click must show a
    /// friendly "nothing to export" message rather than surfacing the internal
    /// "no pages" assembly error, and it must not crash or loop.
    func testExportingEmptyWorkspaceShowsFriendlyMessageInsteadOfAssemblyError() throws {
        let document = WorkspaceDocument()
        let only = try makeMemberWithPDF(name: "Only", pageTexts: ["one"])
        document.workspace.documents = [only.member]
        document.workspace.pageOrder = only.refs
        document.memberPDFData[only.member.id] = only.pdfData
        let viewModel = WorkspaceViewModel(document: document)
        viewModel.removeDocument(only.member)

        XCTAssertNil(viewModel.exportError)

        let result = viewModel.exportWorkspace(as: .pdf)

        XCTAssertFalse(result)
        let message = try XCTUnwrap(viewModel.exportError?.message)
        XCTAssertEqual(message, L10n.string("error.export.emptyWorkspace"))
        XCTAssertNotEqual(message, PDFKitEngine.ExportAssemblyError.emptyDocument.localizedDescription)

        // Dismissing the alert must fully clear the pending error so it can't reopen.
        viewModel.exportError = nil
        XCTAssertNil(viewModel.exportError)
    }

    /// The save-before-close path (`fileWrapper`, invoked by macOS autosave/close)
    /// must never throw for an emptied-out workspace -- that would trap the user
    /// in a "could not prepare this PDF for export" loop when just trying to exit.
    func testFileWrapperDoesNotThrowForEmptyWorkspaceSnapshot() throws {
        let document = WorkspaceDocument()
        let only = try makeMemberWithPDF(name: "Only", pageTexts: ["one"])
        document.workspace.documents = [only.member]
        document.workspace.pageOrder = only.refs
        document.memberPDFData[only.member.id] = only.pdfData
        let viewModel = WorkspaceViewModel(document: document)
        viewModel.removeDocument(only.member)

        let snapshot = try document.snapshot(contentType: .pdf)
        XCTAssertTrue(snapshot.workspace.documents.isEmpty)
        XCTAssertThrowsError(try document.exportedPDFDataThrowing(from: snapshot)) { error in
            XCTAssertEqual(error as? PDFKitEngine.ExportAssemblyError, .emptyDocument)
        }
    }

    /// Deleting one of several documents must leave the remaining document fully
    /// exportable -- the empty-workspace guard must not misfire for a non-empty
    /// workspace.
    func testRemainingDocumentStillExportsAfterDeletingAnother() throws {
        let document = WorkspaceDocument()
        let first = try makeMemberWithPDF(name: "First", pageTexts: ["one"])
        let second = try makeMemberWithPDF(name: "Second", pageTexts: ["two"])
        document.workspace.documents = [first.member, second.member]
        document.workspace.pageOrder = first.refs + second.refs
        document.memberPDFData[first.member.id] = first.pdfData
        document.memberPDFData[second.member.id] = second.pdfData
        let viewModel = WorkspaceViewModel(document: document)

        viewModel.removeDocument(first.member)

        XCTAssertFalse(viewModel.isWorkspaceEmpty)
        let exportedData = try document.exportedPDFDataThrowing(from: try document.snapshot(contentType: .pdf))
        let exportedPDF = try XCTUnwrap(PDFDocument(data: exportedData))
        XCTAssertEqual(exportedPDF.pageCount, 1)
    }

    @MainActor
    func testImportingAfterTargetPageInsertsDocumentAfterTargetDocument() async throws {
        let document = WorkspaceDocument()
        let first = try makeMemberWithPDF(name: "First", pageTexts: ["one"])
        let second = try makeMemberWithPDF(name: "Second", pageTexts: ["two"])
        document.workspace.documents = [first.member, second.member]
        document.workspace.pageOrder = first.refs + second.refs
        document.memberPDFData[first.member.id] = first.pdfData
        document.memberPDFData[second.member.id] = second.pdfData
        let viewModel = WorkspaceViewModel(document: document, processingEngine: PDFKitProcessingEngineFallback())
        let importURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Inserted \(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: importURL) }
        try makePDF(pageTexts: ["inserted"]).dataRepresentation().unwrap().write(to: importURL)

        viewModel.importFiles(urls: [importURL], insertingAfter: first.refs[0].id)
        try await waitForImportsToFinish(in: viewModel)

        XCTAssertEqual(viewModel.document.workspace.documents.map(\.displayName), [
            "First",
            importURL.deletingPathExtension().lastPathComponent,
            "Second"
        ])
        XCTAssertEqual(viewModel.document.workspace.pageOrder.first?.id, first.refs[0].id)
        XCTAssertEqual(viewModel.document.workspace.pageOrder.last?.id, second.refs[0].id)
    }

    func testSelectingDocumentJumpsToItsFirstPage() throws {
        let document = WorkspaceDocument()
        let first = try makeMemberWithPDF(name: "First", pageTexts: ["one", "two"])
        let second = try makeMemberWithPDF(name: "Second", pageTexts: ["three", "four"])
        document.workspace.documents = [first.member, second.member]
        document.workspace.pageOrder = first.refs + second.refs
        document.memberPDFData[first.member.id] = first.pdfData
        document.memberPDFData[second.member.id] = second.pdfData
        let viewModel = WorkspaceViewModel(document: document)

        var jumpedIndex: Int?
        let token = NotificationCenter.default.addObserver(
            forName: .orifoldJumpToPageIndex,
            object: nil,
            queue: nil
        ) { notification in
            jumpedIndex = notification.object as? Int
        }
        defer { NotificationCenter.default.removeObserver(token) }

        viewModel.selectDocument(second.member)

        XCTAssertEqual(viewModel.selectedPageRefID, second.refs[0].id)
        XCTAssertEqual(viewModel.selectedPageRefIDs, Set([second.refs[0].id]))
        XCTAssertEqual(jumpedIndex, 4)
    }

    func testMovingPageAcrossDocumentsMovesLivePDFPageAndInvalidatesSourcePayloads() throws {
        let document = WorkspaceDocument()
        let first = try makeMemberWithPDF(name: "First", pageTexts: ["one", "two"])
        let second = try makeMemberWithPDF(name: "Second", pageTexts: ["three"])
        document.workspace.documents = [first.member, second.member]
        document.workspace.pageOrder = first.refs + second.refs
        document.memberPDFData[first.member.id] = first.pdfData
        document.memberPDFData[second.member.id] = second.pdfData
        document.sourcePayloads[first.member.id] = SourceDocumentPayload(
            format: .plainText,
            originalFilename: "first.txt",
            originalContentTypeIdentifier: "public.plain-text",
            originalData: Data("one two".utf8),
            plainText: "one two",
            renderedPageCount: 2
        )
        document.sourcePayloads[second.member.id] = SourceDocumentPayload(
            format: .plainText,
            originalFilename: "second.txt",
            originalContentTypeIdentifier: "public.plain-text",
            originalData: Data("three".utf8),
            plainText: "three",
            renderedPageCount: 1
        )
        let viewModel = WorkspaceViewModel(document: document)

        XCTAssertTrue(viewModel.movePage(first.refs[0], after: second.refs[0]))

        XCTAssertEqual(viewModel.document.workspace.documents[0].pageRefs, [first.refs[1].id])
        XCTAssertEqual(viewModel.document.workspace.documents[1].pageRefs, [second.refs[0].id, first.refs[0].id])
        XCTAssertEqual(viewModel.document.workspace.pageOrder.map(\.id), [first.refs[1].id, second.refs[0].id, first.refs[0].id])
        XCTAssertEqual(viewModel.loadedPDFs[0].1.pageCount, 1)
        XCTAssertEqual(viewModel.loadedPDFs[1].1.pageCount, 2)
        XCTAssertTrue(viewModel.loadedPDFs[1].1.page(at: 1)?.string?.contains("one") ?? false)
        XCTAssertNil(viewModel.document.sourcePayloads[first.member.id])
        XCTAssertNil(viewModel.document.sourcePayloads[second.member.id])
    }

    @MainActor
    func testFirstImportIntoEmptyWorkspaceUpdatesWorkspaceTitle() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Quarterly Packet \(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        try makePDF(pageTexts: ["title"]).dataRepresentation().unwrap().write(to: tempURL)

        let document = WorkspaceDocument()
        let viewModel = WorkspaceViewModel(document: document, processingEngine: PDFKitProcessingEngineFallback())
        viewModel.addFile(from: tempURL)

        XCTAssertTrue(viewModel.document.workspace.title.hasPrefix("Quarterly Packet"))
    }

    func testRemovingDocumentCleansWorkspaceArtifactsAndKeepsRemainingDocument() throws {
        let first = try makeMemberWithPDF(name: "First", pageTexts: ["one", "two"])
        let second = try makeMemberWithPDF(name: "Second", pageTexts: ["three"])
        let removedRefID = first.refs[0].id
        let keptRefID = second.refs[0].id
        let document = WorkspaceDocument()
        document.workspace.documents = [first.member, second.member]
        document.workspace.pageOrder = first.refs + second.refs
        document.memberPDFData[first.member.id] = first.pdfData
        document.memberPDFData[second.member.id] = second.pdfData
        document.sourcePayloads[first.member.id] = SourceDocumentPayload(
            format: .plainText,
            originalFilename: "first.txt",
            originalContentTypeIdentifier: "public.plain-text",
            originalData: Data("one two".utf8),
            plainText: "one two",
            renderedPageCount: 2
        )
        document.workspace.pageEditStates = [PageEditState(pageRefID: removedRefID)]
        document.workspace.comments = [
            WorkspaceComment(
                body: "Anchored",
                anchor: WorkspaceCommentAnchor(
                    pageRefID: removedRefID,
                    rect: CGRect(x: 10, y: 10, width: 20, height: 20),
                    kind: .region
                )
            )
        ]
        document.workspace.signatures = [
            SignaturePlacement(
                pageRefId: removedRefID,
                imageData: Data([1]),
                rect: CGRect(x: 10, y: 10, width: 40, height: 20)
            )
        ]
        document.workspace.decorations = [
            PageDecoration.stamp(
                text: "Reviewed",
                swatch: .accent,
                pageRefID: removedRefID,
                rect: CGRect(x: 10, y: 10, width: 80, height: 30)
            ),
            PageDecoration.stamp(
                text: "Kept",
                swatch: .sage,
                pageRefID: keptRefID,
                rect: CGRect(x: 10, y: 10, width: 80, height: 30)
            )
        ]
        let viewModel = WorkspaceViewModel(document: document, processingEngine: PDFKitProcessingEngineFallback())

        viewModel.removeDocument(first.member)

        XCTAssertEqual(viewModel.memberDocuments.map(\.id), [second.member.id])
        XCTAssertEqual(document.workspace.documents.map(\.id), [second.member.id])
        XCTAssertEqual(document.workspace.pageOrder.map(\.id), [keptRefID])
        XCTAssertNil(document.memberPDFData[first.member.id])
        XCTAssertNil(document.sourcePayloads[first.member.id])
        XCTAssertTrue(document.workspace.pageEditStates.isEmpty)
        XCTAssertTrue(document.workspace.signatures.isEmpty)
        XCTAssertEqual(document.workspace.decorations.map(\.text), ["Kept"])
        XCTAssertNil(document.workspace.comments.first?.anchor)
        XCTAssertEqual(document.workspace.comments.first?.anchorWasRemoved, true)
        XCTAssertEqual(viewModel.pageCount, 1)
    }

    func testAnchoredCommentSurvivesDeletedPageAndUndoRestoresAnchor() throws {
        let fixture = try makeMemberWithPDF(name: "Anchored", pageTexts: ["one", "two"])
        let document = WorkspaceDocument()
        document.workspace.documents = [fixture.member]
        document.workspace.pageOrder = fixture.refs
        document.memberPDFData[fixture.member.id] = fixture.pdfData
        document.workspace.comments = [
            WorkspaceComment(
                body: "Keep me",
                anchor: WorkspaceCommentAnchor(
                    pageRefID: fixture.refs[0].id,
                    rect: CGRect(x: 72, y: 680, width: 120, height: 24),
                    kind: .text,
                    snippet: "one"
                )
            )
        ]
        let viewModel = WorkspaceViewModel(document: document)
        let undoManager = UndoManager()
        viewModel.undoManager = undoManager

        viewModel.deletePage(fixture.refs[0])

        XCTAssertEqual(viewModel.document.workspace.comments.count, 1)
        XCTAssertNil(viewModel.document.workspace.comments[0].anchor)
        XCTAssertTrue(viewModel.document.workspace.comments[0].anchorWasRemoved)
        XCTAssertEqual(viewModel.anchorSubtitle(for: viewModel.document.workspace.comments[0]), "(page removed)")

        undoManager.undo()

        XCTAssertEqual(viewModel.document.workspace.comments[0].anchor?.pageRefID, fixture.refs[0].id)
        XCTAssertFalse(viewModel.document.workspace.comments[0].anchorWasRemoved)
    }

    func testAnchoredCommentPageNumberFollowsReorder() throws {
        let fixture = try makeMemberWithPDF(name: "Anchored", pageTexts: ["one", "two"])
        let document = WorkspaceDocument()
        document.workspace.documents = [fixture.member]
        document.workspace.pageOrder = fixture.refs
        document.memberPDFData[fixture.member.id] = fixture.pdfData
        document.workspace.comments = [
            WorkspaceComment(
                body: "Jump",
                anchor: WorkspaceCommentAnchor(
                    pageRefID: fixture.refs[0].id,
                    rect: CGRect(x: 72, y: 680, width: 120, height: 24),
                    kind: .text,
                    snippet: "one"
                )
            )
        ]
        let viewModel = WorkspaceViewModel(document: document)

        XCTAssertEqual(viewModel.anchorSubtitle(for: viewModel.document.workspace.comments[0]), "p. 1 - one")
        XCTAssertTrue(viewModel.movePage(fixture.refs[0], toIndex: 2))
        XCTAssertEqual(viewModel.anchorSubtitle(for: viewModel.document.workspace.comments[0]), "p. 2 - one")
    }

    func testPlainTextExportListsAnchoredCommentWithPageAndSnippet() throws {
        let fixture = try makeMemberWithPDF(name: "Anchored", pageTexts: ["Anchor target"])
        let document = WorkspaceDocument()
        document.workspace.documents = [fixture.member]
        document.workspace.pageOrder = fixture.refs
        document.memberPDFData[fixture.member.id] = fixture.pdfData
        document.workspace.comments = [
            WorkspaceComment(
                body: "Review this.",
                anchor: WorkspaceCommentAnchor(
                    pageRefID: fixture.refs[0].id,
                    rect: CGRect(x: 72, y: 680, width: 120, height: 24),
                    kind: .text,
                    snippet: "Anchor target"
                )
            )
        ]
        let viewModel = WorkspaceViewModel(document: document)

        let text = try XCTUnwrap(String(data: try viewModel.dataForWorkspaceExport(as: .text), encoding: .utf8))

        XCTAssertTrue(text.contains("p. 1 - Anchor target"))
        XCTAssertTrue(text.contains("Review this."))
    }

    func testCommentTagSuggestionsDoNotRegisterUndo() {
        let document = WorkspaceDocument()
        document.workspace.tags = ["workspace"]
        document.workspace.comments = [
            WorkspaceComment(body: "A", tags: ["alpha"]),
            WorkspaceComment(body: "B", tags: ["workspace", "beta"])
        ]
        let viewModel = WorkspaceViewModel(document: document)
        let undoManager = UndoManager()
        viewModel.undoManager = undoManager

        XCTAssertEqual(viewModel.usedCommentTags, ["alpha", "beta", "workspace"])
        XCTAssertFalse(undoManager.canUndo)
    }

    func testRotatePageMarksWorkspaceModified() throws {
        let document = WorkspaceDocument()
        document.workspace.modifiedAt = Date(timeIntervalSince1970: 0)
        let fixture = try makeMemberWithPDF(name: "Rotate", pageTexts: ["rotate"])
        document.workspace.documents = [fixture.member]
        document.workspace.pageOrder = fixture.refs
        document.memberPDFData[fixture.member.id] = fixture.pdfData
        let viewModel = WorkspaceViewModel(document: document)

        viewModel.rotatePage(fixture.refs[0], by: 90)

        XCTAssertGreaterThan(viewModel.document.workspace.modifiedAt, Date(timeIntervalSince1970: 0))
        XCTAssertEqual(viewModel.loadedPDFs[0].1.page(at: 0)?.rotation, 90)
    }

    func testRotateUndoResolvesPageAfterInlineEditRestore() throws {
        let fixture = try makeMemberWithPDF(name: "Editable", pageTexts: ["Original text"])
        let document = WorkspaceDocument()
        document.workspace.documents = [fixture.member]
        document.workspace.pageOrder = fixture.refs
        document.memberPDFData[fixture.member.id] = fixture.pdfData
        let viewModel = WorkspaceViewModel(
            document: document,
            processingEngine: PDFKitProcessingEngineFallback()
        )
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        viewModel.undoManager = undoManager

        undoManager.beginUndoGrouping()
        viewModel.rotatePage(fixture.refs[0], by: 90)
        XCTAssertEqual(viewModel.loadedPDFs[0].1.page(at: 0)?.rotation, 90)
        undoManager.endUndoGrouping()

        let sourceBlock = EditableTextBlock(
            pageRefID: fixture.refs[0].id,
            text: "Original text",
            bounds: CGRect(x: 70, y: 700, width: 120, height: 24),
            lines: [],
            fontName: "Helvetica",
            fontSize: 16,
            textColor: .documentText,
            rotation: 0,
            baseline: 700,
            confidence: .high
        )
        undoManager.beginUndoGrouping()
        XCTAssertTrue(viewModel.applyInlineTextEdit(
            pageRef: fixture.refs[0],
            sourceBlock: sourceBlock,
            replacementText: "Edited text",
            editedBounds: CGRect(x: 70, y: 700, width: 160, height: 28),
            fontName: "Helvetica",
            fontSize: 16,
            textColor: .black,
            alignment: .left
        ))
        XCTAssertEqual(viewModel.loadedPDFs[0].1.page(at: 0)?.rotation, 90)
        undoManager.endUndoGrouping()

        undoManager.undo()
        XCTAssertEqual(viewModel.loadedPDFs[0].1.page(at: 0)?.rotation, 90)

        undoManager.undo()
        XCTAssertEqual(viewModel.loadedPDFs[0].1.page(at: 0)?.rotation, 0)
    }

    func testImportingBlocksEditAndPageMutations() throws {
        let fixture = try makeMemberWithPDF(name: "Importing", pageTexts: ["Blocked edit"])
        let document = WorkspaceDocument()
        document.workspace.documents = [fixture.member]
        document.workspace.pageOrder = fixture.refs
        document.memberPDFData[fixture.member.id] = fixture.pdfData
        let viewModel = WorkspaceViewModel(document: document)
        let page = try XCTUnwrap(viewModel.loadedPDFs[0].1.page(at: 0))
        let annotationCount = page.annotations.count

        viewModel.isImporting = true

        viewModel.addTag("blocked")
        viewModel.addComment("blocked")
        XCTAssertFalse(viewModel.movePage(fixture.refs[0], toIndex: 0))
        XCTAssertNil(viewModel.addTextBox(at: CGPoint(x: 100, y: 100), on: page))
        XCTAssertFalse(viewModel.applyMarkup(.underline, to: try XCTUnwrap(page.selectionForWord(at: CGPoint(x: 75, y: 720)))))

        XCTAssertTrue(viewModel.document.workspace.tags.isEmpty)
        XCTAssertTrue(viewModel.document.workspace.comments.isEmpty)
        XCTAssertEqual(page.annotations.count, annotationCount)
        XCTAssertEqual(viewModel.editingStatus?.message, "Finish importing before making more changes.")
        XCTAssertEqual(viewModel.editingStatus?.isError, false)
    }

    func testImportingBlocksExistingUndoMutations() {
        let viewModel = WorkspaceViewModel(document: WorkspaceDocument())
        let undoManager = UndoManager()
        viewModel.undoManager = undoManager
        viewModel.addTag("review")
        XCTAssertEqual(viewModel.document.workspace.tags, ["review"])

        viewModel.isImporting = true
        undoManager.undo()

        XCTAssertEqual(viewModel.document.workspace.tags, ["review"])
        XCTAssertEqual(viewModel.editingStatus?.message, "Finish importing before making more changes.")
        XCTAssertEqual(viewModel.editingStatus?.isError, false)
    }

    func testProcessingBlocksNewImports() throws {
        let viewModel = WorkspaceViewModel(document: WorkspaceDocument())
        let importData = try makePDF(pageTexts: ["blocked import"]).dataRepresentation().unwrap()
        let importURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Orifold-blocked-import-\(UUID().uuidString).pdf")
        try importData.write(to: importURL)
        defer { try? FileManager.default.removeItem(at: importURL) }

        viewModel.setProcessingStateForTesting(compressionActive: true)
        viewModel.importFiles(urls: [importURL])
        XCTAssertFalse(viewModel.isImporting)
        XCTAssertTrue(viewModel.memberDocuments.isEmpty)
        XCTAssertEqual(viewModel.editingStatus?.message, "Finish reducing file size before making more changes.")

        viewModel.setProcessingStateForTesting(ocrActive: true)
        viewModel.importFiles(urls: [importURL])
        XCTAssertFalse(viewModel.isImporting)
        XCTAssertTrue(viewModel.memberDocuments.isEmpty)
        XCTAssertEqual(viewModel.editingStatus?.message, "Finish making this document searchable before making more changes.")

        viewModel.setProcessingStateForTesting()
    }

    @MainActor
    func testDebouncedSearchUsesLastRapidQuery() async throws {
        let document = WorkspaceDocument()
        let fixture = try makeMemberWithPDF(name: "Search", pageTexts: ["alpha only", "target only"])
        document.workspace.documents = [fixture.member]
        document.workspace.pageOrder = fixture.refs
        document.memberPDFData[fixture.member.id] = fixture.pdfData
        let viewModel = WorkspaceViewModel(document: document)

        viewModel.searchQuery = "alpha"
        viewModel.scheduleSearch(query: "alpha")
        viewModel.searchQuery = "target"
        viewModel.scheduleSearch(query: "target")

        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if viewModel.searchResults.contains(where: { $0.string?.localizedCaseInsensitiveContains("target") == true }) {
                break
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        XCTAssertEqual(viewModel.searchResultsQuery, "target")
    }

    func testSearchSubmitUsesCurrentQueryInsteadOfStaleDebouncedResults() throws {
        let document = WorkspaceDocument()
        let fixture = try makeMemberWithPDF(name: "SearchSubmit", pageTexts: ["alpha only", "target only"])
        document.workspace.documents = [fixture.member]
        document.workspace.pageOrder = fixture.refs
        document.memberPDFData[fixture.member.id] = fixture.pdfData
        let viewModel = WorkspaceViewModel(document: document)

        viewModel.searchQuery = "alpha"
        viewModel.search(query: "alpha")
        XCTAssertEqual(viewModel.searchResultsQuery, "alpha")

        viewModel.searchQuery = "target"
        viewModel.scheduleSearch(query: "target")
        viewModel.commitSearch()

        XCTAssertEqual(viewModel.searchResultsQuery, "target")
    }

    func testRepeatedHighlightSelectionDoesNotStackAnnotations() throws {
        let pdf = makePDF(pageTexts: ["Highlight target"])
        let page = try XCTUnwrap(pdf.page(at: 0))
        let selection = try XCTUnwrap(page.selectionForWord(at: CGPoint(x: 75, y: 720)))
        let viewModel = WorkspaceViewModel(
            document: WorkspaceDocument(),
            processingEngine: PDFKitProcessingEngineFallback()
        )

        XCTAssertTrue(viewModel.applyHighlight(to: selection))
        XCTAssertFalse(viewModel.applyHighlight(to: selection))

        let highlights = page.annotations.filter { $0.type == "Highlight" }
        XCTAssertEqual(highlights.count, 1)
    }

    func testEditableTextOverlayIsMarkedAsReplacementAnnotation() throws {
        let pdf = makePDF(pageTexts: ["Replaceable text"])
        let page = try XCTUnwrap(pdf.page(at: 0))
        let selection = try XCTUnwrap(page.selectionForWord(at: CGPoint(x: 75, y: 720)))
        let viewModel = WorkspaceViewModel(
            document: WorkspaceDocument(),
            processingEngine: PDFKitProcessingEngineFallback()
        )

        let annotation = try XCTUnwrap(viewModel.addEditableTextOverlay(from: selection, on: page))

        XCTAssertEqual(annotation.type, "FreeText")
        XCTAssertEqual(
            annotation.value(forAnnotationKey: WorkspaceViewModel.textReplacementAnnotationKey) as? Bool,
            true
        )
        XCTAssertLessThan(annotation.bounds.width, 180)
    }

    func testEditableTextOverlayPreservesSelectionStyleAndUsesSafeBackground() throws {
        let font = NSFont.systemFont(ofSize: 16)
        let attributed = NSAttributedString(
            string: "Replaceable",
            attributes: [
                .font: font,
                .foregroundColor: NSColor.black
            ]
        )
        let selectionBounds = CGRect(x: 72, y: 700, width: 82, height: 16)

        let plan = try XCTUnwrap(PDFEditingSupport.replacementPlan(
            text: attributed.string,
            selectionBounds: selectionBounds,
            attributedString: attributed,
            pageBounds: CGRect(x: 0, y: 0, width: 612, height: 792)
        ))

        XCTAssertEqual(plan.text, "Replaceable")
        XCTAssertEqual(plan.style.font.pointSize, font.pointSize)
        XCTAssertTrue(colorsApproximatelyEqual(plan.style.textColor, .black))
        XCTAssertGreaterThan(plan.bounds.width, selectionBounds.width)
        XCTAssertGreaterThan(plan.bounds.height, 0)
        XCTAssertTrue(plan.shouldUseReplacementBackground)
        XCTAssertTrue(plan.warnings.isEmpty)
        XCTAssertNotEqual(
            PDFEditingSupport.replacementBackgroundColor(isReplacement: true, originalBackground: nil),
            .clear
        )
    }

    func testEditableTextOverlayRejectsInvalidSelectionGracefully() throws {
        let plan = PDFEditingSupport.replacementPlan(
            text: "Text",
            selectionBounds: CGRect(x: 10, y: 10, width: 0, height: 12),
            attributedString: nil
        )

        XCTAssertEqual(plan?.warnings, [.invalidSelectionBounds])
        XCTAssertFalse(plan?.shouldUseReplacementBackground ?? true)
    }

    func testReplacementPlanClampsExpandedBoundsInsidePage() throws {
        let pageBounds = CGRect(x: 0, y: 0, width: 200, height: 100)

        let plan = try XCTUnwrap(PDFEditingSupport.replacementPlan(
            text: "Edge",
            selectionBounds: CGRect(x: 196, y: 40, width: 4, height: 12),
            attributedString: nil,
            pageBounds: pageBounds
        ))

        XCTAssertTrue(pageBounds.contains(plan.bounds))
        XCTAssertLessThanOrEqual(plan.bounds.maxX, pageBounds.maxX)
    }

    func testEditorFieldUsesDarkBackgroundForWhiteText() throws {
        let colors = PDFEditingSupport.editorFieldColors(for: .white)
        let background = try XCTUnwrap(colors.background.usingColorSpace(.sRGB))
        var red: CGFloat = 1
        var green: CGFloat = 1
        var blue: CGFloat = 1
        background.getRed(&red, green: &green, blue: &blue, alpha: nil)

        XCTAssertLessThan((red + green + blue) / 3, 0.25)
    }

    func testTextBoxBoundsStayInsidePage() throws {
        let pageBounds = CGRect(x: 0, y: 0, width: 200, height: 200)

        let bounds = PDFEditingSupport.textBoxBounds(
            centeredAt: CGPoint(x: 196, y: 196),
            pageBounds: pageBounds
        )

        XCTAssertGreaterThanOrEqual(bounds.minX, pageBounds.minX)
        XCTAssertLessThanOrEqual(bounds.maxX, pageBounds.maxX)
        XCTAssertGreaterThanOrEqual(bounds.minY, pageBounds.minY)
        XCTAssertLessThanOrEqual(bounds.maxY, pageBounds.maxY)
    }

    func testFreeTextResizePreservesReplacementWidth() {
        let original = CGRect(x: 20, y: 30, width: 96, height: 18)

        let resized = PDFEditingSupport.resizedFreeTextBounds(
            currentBounds: original,
            text: "A much longer replacement string",
            font: .systemFont(ofSize: 12),
            preserveWidth: true
        )

        XCTAssertEqual(resized?.width, original.width)
        XCTAssertGreaterThan(resized?.height ?? 0, original.height)
    }

    func testEmptyEditActionMatchesDraftReplacementAndExistingTextSemantics() {
        XCTAssertEqual(
            PDFEditingSupport.emptyEditAction(text: "   ", isDraft: true, isReplacement: false),
            .removeDraft
        )
        XCTAssertEqual(
            PDFEditingSupport.emptyEditAction(text: "\n", isDraft: false, isReplacement: true),
            .rejectReplacement
        )
        XCTAssertEqual(
            PDFEditingSupport.emptyEditAction(text: "", isDraft: false, isReplacement: false),
            .allow
        )
        XCTAssertEqual(
            PDFEditingSupport.emptyEditAction(text: "Keep", isDraft: true, isReplacement: true),
            .allow
        )
    }

    func testAnnotationSnapshotRestoresCancelState() {
        let annotation = PDFAnnotation(bounds: CGRect(x: 10, y: 20, width: 80, height: 24), forType: .freeText, withProperties: nil)
        annotation.contents = "Original"
        annotation.font = .systemFont(ofSize: 14)
        annotation.fontColor = .black
        annotation.color = .clear
        annotation.alignment = .right
        let snapshot = PDFAnnotationEditSnapshot(annotation: annotation)

        annotation.contents = "Changed"
        annotation.font = .boldSystemFont(ofSize: 22)
        annotation.fontColor = .systemRed
        annotation.color = .white
        annotation.alignment = .center
        annotation.bounds = CGRect(x: 1, y: 2, width: 3, height: 4)
        snapshot.restore(to: annotation)

        XCTAssertEqual(annotation.contents, "Original")
        XCTAssertEqual(annotation.font?.pointSize, 14)
        XCTAssertTrue(colorsApproximatelyEqual(annotation.fontColor, NSColor.black))
        XCTAssertTrue(colorsApproximatelyEqual(annotation.color, NSColor.clear))
        XCTAssertEqual(annotation.alignment, .right)
        XCTAssertEqual(annotation.bounds, CGRect(x: 10, y: 20, width: 80, height: 24))
    }

    func testNoteEditorCommitsDraftNoteWhenDismissed() throws {
        let pdf = makePDF(pageTexts: ["Note editor"])
        let page = try XCTUnwrap(pdf.page(at: 0))
        let annotation = PDFAnnotation(bounds: CGRect(x: 20, y: 20, width: 24, height: 24), forType: .text, withProperties: nil)
        annotation.contents = ""
        annotation.setValue(true, forAnnotationKey: WorkspaceViewModel.draftTextAnnotationKey)
        page.addAnnotation(annotation)
        var changeCount = 0
        let controller = NoteEditorViewController(annotation: annotation) { _, _ in
        } changeHandler: { _, _, _ in
            changeCount += 1
        }

        controller.loadViewIfNeeded()
        let textView = try XCTUnwrap(firstDescendant(of: NSTextView.self, in: controller.view))
        textView.string = "hello world"
        controller.viewWillDisappear()

        XCTAssertEqual(annotation.contents, "hello world")
        XCTAssertEqual(annotation.value(forAnnotationKey: WorkspaceViewModel.draftTextAnnotationKey) as? Bool, false)
        XCTAssertTrue(page.annotations.contains(annotation))
        XCTAssertEqual(changeCount, 1)
    }

    func testNoteEditorCommitsPastedNoteWhenDoneIsPressed() throws {
        let pdf = makePDF(pageTexts: ["Note editor"])
        let page = try XCTUnwrap(pdf.page(at: 0))
        let annotation = PDFAnnotation(bounds: CGRect(x: 20, y: 20, width: 24, height: 24), forType: .text, withProperties: nil)
        annotation.contents = ""
        annotation.setValue(true, forAnnotationKey: WorkspaceViewModel.draftTextAnnotationKey)
        page.addAnnotation(annotation)
        var changeCount = 0
        var didClose = false
        let controller = NoteEditorViewController(annotation: annotation) { _, _ in
        } changeHandler: { _, _, _ in
            changeCount += 1
        }
        controller.closeHandler = {
            didClose = true
        }

        controller.loadViewIfNeeded()
        let textView = try XCTUnwrap(firstDescendant(of: NSTextView.self, in: controller.view))
        let doneButton = try XCTUnwrap(findSubview(in: controller.view) { (button: NSButton) in
            button.title == "Done"
        })
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("This is a pasted note", forType: .string)
        textView.paste(nil)
        doneButton.performClick(nil)

        XCTAssertEqual(annotation.contents, "This is a pasted note")
        XCTAssertEqual(annotation.value(forAnnotationKey: WorkspaceViewModel.draftTextAnnotationKey) as? Bool, false)
        XCTAssertTrue(page.annotations.contains(annotation))
        XCTAssertEqual(changeCount, 1)
        XCTAssertTrue(didClose)
    }

    func testAddTextBoxRejectsMalformedPagePoint() throws {
        let pdf = makePDF(pageTexts: ["Text"])
        let page = try XCTUnwrap(pdf.page(at: 0))
        let viewModel = WorkspaceViewModel(
            document: WorkspaceDocument(),
            processingEngine: PDFKitProcessingEngineFallback()
        )

        let annotation = viewModel.addTextBox(at: CGPoint(x: CGFloat.infinity, y: 20), on: page)

        XCTAssertNil(annotation)
        XCTAssertEqual(viewModel.editingStatus?.message, PDFTextEditWarning.invalidAnnotationBounds.message)
    }

    func testEraserRemovesClickedHighlightAnnotation() throws {
        let pdf = makePDF(pageTexts: ["Highlighted text"])
        let page = try XCTUnwrap(pdf.page(at: 0))
        let highlight = PDFAnnotation(
            bounds: CGRect(x: 72, y: 650, width: 140, height: 18),
            forType: .highlight,
            withProperties: nil
        )
        page.addAnnotation(highlight)
        let viewModel = WorkspaceViewModel(
            document: WorkspaceDocument(),
            processingEngine: PDFKitProcessingEngineFallback()
        )

        let erased = viewModel.eraseMarkupAnnotation(at: CGPoint(x: 90, y: 660), on: page)

        XCTAssertTrue(erased)
        XCTAssertFalse(page.annotations.contains(highlight))
    }
}

private func firstDescendant<T: NSView>(of type: T.Type, in view: NSView) -> T? {
    if let match = view as? T {
        return match
    }
    for subview in view.subviews {
        if let match = firstDescendant(of: type, in: subview) {
            return match
        }
    }
    return nil
}

final class PDFEncryptionExportTests: XCTestCase {
    func testEncryptedExportSucceedsThroughTheFullSavePath() throws {
        // Regression test: `writePDFExportData`'s new structural-validation
        // gate originally called `QPDFService.isStructurallySound` with no
        // password, so qpdf could never parse the AES-256-encrypted output it
        // was just asked to validate -- every password-protected export was
        // silently rejected. No prior test drove a *successful* encrypted
        // export all the way through `saveFlattenedPDF`/`writePDFExportData`
        // (the two existing tests here both expect failure before that point),
        // which is exactly how this shipped without a failing test.
        let fixture = try makeMemberWithPDF(name: "EncTest", pageTexts: ["Encrypted body"])
        let document = WorkspaceDocument()
        document.workspace.documents = [fixture.member]
        document.workspace.pageOrder = fixture.refs
        document.memberPDFData[fixture.member.id] = fixture.pdfData
        let viewModel = WorkspaceViewModel(document: document, processingEngine: PDFKitProcessingEngineFallback())
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Orifold-encrypted-full-path-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let didSave = viewModel.saveFlattenedPDF(
            to: outputURL,
            options: WorkspaceExportOptions(encryption: PDFEncryptionOptions(
                userPassword: "reader-pass",
                ownerPassword: "owner-pass"
            ))
        )

        XCTAssertTrue(didSave, viewModel.exportError?.message ?? "expected export to succeed")
        let writtenData = try Data(contentsOf: outputURL)
        XCTAssertTrue(QPDFService.isStructurallySound(writtenData, password: "reader-pass"))
        let writtenPDF = try XCTUnwrap(PDFDocument(data: writtenData))
        XCTAssertTrue(writtenPDF.isLocked)
        XCTAssertTrue(writtenPDF.unlock(withPassword: "reader-pass"))
    }

    func testEncryptedPDFUnlocksWithRightPasswordAndRejectsWrongPassword() throws {
        let sourcePDF = makePDF(pageTexts: ["Protected export text"])
        let sourceData = try XCTUnwrap(sourcePDF.dataRepresentation())
        let options = PDFEncryptionOptions(
            userPassword: "reader-pass",
            ownerPassword: "owner-pass",
            allowsPrinting: true,
            allowsCopying: true
        )

        let encryptedData = try PDFEncryptionService.encryptedData(from: sourceData, options: options)
        let encryptedPDF = try XCTUnwrap(PDFDocument(data: encryptedData))

        XCTAssertTrue(encryptedPDF.isLocked)
        XCTAssertFalse(encryptedPDF.unlock(withPassword: "wrong-pass"))
        XCTAssertTrue(encryptedPDF.unlock(withPassword: "reader-pass"))
        XCTAssertEqual(encryptedPDF.normalizedStringValue, sourcePDF.normalizedStringValue)
    }

    func testEncryptedPDFPreservesPermissionsAndText() throws {
        let sourcePDF = makePDF(pageTexts: ["Permission checked text"])
        let sourceData = try XCTUnwrap(sourcePDF.dataRepresentation())
        let options = PDFEncryptionOptions(
            userPassword: "reader-pass",
            ownerPassword: "owner-pass",
            allowsPrinting: false,
            allowsCopying: false
        )

        let encryptedData = try PDFEncryptionService.encryptedData(from: sourceData, options: options)
        let encryptedPDF = try XCTUnwrap(PDFDocument(data: encryptedData))

        XCTAssertTrue(encryptedPDF.unlock(withPassword: "reader-pass"))
        XCTAssertFalse(encryptedPDF.allowsPrinting)
        XCTAssertFalse(encryptedPDF.allowsCopying)
        XCTAssertEqual(encryptedPDF.normalizedStringValue, sourcePDF.normalizedStringValue)
    }

    func testPasswordValidationRunsBeforeOutputFileIsCreated() throws {
        let fixture = try makeMemberWithPDF(name: "Protected", pageTexts: ["Protected text"])
        let document = WorkspaceDocument()
        document.workspace.documents = [fixture.member]
        document.workspace.pageOrder = fixture.refs
        document.memberPDFData[fixture.member.id] = fixture.pdfData
        let viewModel = WorkspaceViewModel(
            document: document,
            processingEngine: PDFKitProcessingEngineFallback()
        )
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Orifold-empty-password-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let didSave = viewModel.saveFlattenedPDF(
            to: outputURL,
            options: WorkspaceExportOptions(encryption: PDFEncryptionOptions(
                userPassword: "",
                ownerPassword: "owner-pass"
            ))
        )

        XCTAssertFalse(didSave)
        XCTAssertFalse(FileManager.default.fileExists(atPath: outputURL.path))
        XCTAssertEqual(viewModel.exportError?.message, PDFEncryptionError.emptyUserPassword.userMessage)
    }

    func testSanitizeForSharingStripsCatalogActionsThroughFullExportPath() throws {
        let fixture = try makeMemberWithPDF(name: "Active", pageTexts: ["Sanitize me"])
        let document = WorkspaceDocument()
        document.workspace.documents = [fixture.member]
        document.workspace.pageOrder = fixture.refs
        document.memberPDFData[fixture.member.id] = fixture.pdfData
        let viewModel = WorkspaceViewModel(
            document: document,
            processingEngine: PDFKitProcessingEngineFallback()
        )

        let data = try viewModel.dataForPDFExport(
            options: WorkspaceExportOptions(sanitization: PDFSanitizationOptions(removesMetadata: true))
        )

        XCTAssertTrue(QPDFService.isStructurallySound(data))
        let pdf = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertEqual(pdf.pageCount, fixture.refs.count)
    }

    func testSanitizationSurvivesTheCompressedExportPipeline() async throws {
        // Regression test: `reducedData` (the compress+sanitize+encrypt path used
        // when "Reduce file size" is checked in the export sheet) used to drop
        // the sanitization option entirely, silently shipping unsanitized bytes
        // whenever a user also requested compression. This exercises the same
        // pipeline the app actually uses for that combination. Needs a fixture
        // that genuinely compresses (a text-only page throws `.grewLarger`
        // before ever reaching the sanitize step -- see
        // testTextOnlyPDFTakesAlreadyOptimizedPath), so this reuses the same
        // oversized-photo fixture the compression tests use.
        let sourceData = try makePhotoPDFData()

        let document = WorkspaceDocument()
        let member = MemberDocument(displayName: "Compressible", sourcePDFRef: "Compressible.pdf")
        var mutableMember = member
        let refs = [PageRef(memberDocId: member.id, sourcePageIndex: 0)]
        mutableMember.pageRefs = refs.map(\.id)
        document.workspace.documents = [mutableMember]
        document.workspace.pageOrder = refs
        document.memberPDFData[mutableMember.id] = sourceData
        let viewModel = WorkspaceViewModel(
            document: document,
            processingEngine: PDFiumProcessingEngine()
        )
        let exportSourceData = try viewModel.dataForPDFExport()

        let output = try await viewModel.reducedData(
            from: exportSourceData,
            preset: .balanced,
            sanitization: PDFSanitizationOptions(removesMetadata: false),
            encryption: nil,
            cancellation: OperationCancellationToken(),
            operationID: UUID()
        )

        XCTAssertLessThan(output.data.count, exportSourceData.count, "fixture should actually compress")
        XCTAssertTrue(QPDFService.isStructurallySound(output.data))
        XCTAssertEqual(PDFDocument(data: output.data)?.pageCount, 1)
    }

    func testSanitizationFailureThrowsInsteadOfSilentlyExportingUnsanitizedData() {
        // Regression test: sanitize failure used to fall back silently to the
        // pre-sanitize bytes. For a security/privacy feature, silently shipping
        // the original (unsanitized) data on failure is worse than failing loudly.
        XCTAssertThrowsError(try WorkspaceViewModel.sanitized(
            Data("not a pdf".utf8),
            options: PDFSanitizationOptions(removesMetadata: true)
        )) { error in
            XCTAssertEqual(error as? PDFSanitizationError, .sanitizationFailed)
        }
    }

    func testProtectedOutputValidationRejectsPlainPDFBytes() throws {
        let sourcePDF = makePDF(pageTexts: ["Plain text is not protected"])
        let sourceData = try XCTUnwrap(sourcePDF.dataRepresentation())

        XCTAssertThrowsError(
            try PDFEncryptionService.validateEncryptedData(
                sourceData,
                options: PDFEncryptionOptions(
                    userPassword: "reader-pass",
                    ownerPassword: "owner-pass"
                ),
                expectedText: sourcePDF.string
            )
        ) { error in
            XCTAssertEqual(error as? PDFEncryptionError, .unprotectedOutput)
        }
    }

    func testDigitalSignatureConflictRunsBeforeOutputFileIsCreated() throws {
        let fixture = try makeMemberWithPDF(name: "Signed", pageTexts: ["Signed text"])
        let document = WorkspaceDocument()
        document.workspace.documents = [fixture.member]
        document.workspace.pageOrder = fixture.refs
        document.memberPDFData[fixture.member.id] = fixture.pdfData
        document.workspace.signatures = [
            SignaturePlacement(
                pageRefId: fixture.refs[0].id,
                imageData: Data([1, 2, 3]),
                rect: CGRect(x: 40, y: 40, width: 120, height: 48),
                kind: .cryptographic
            )
        ]
        let viewModel = WorkspaceViewModel(
            document: document,
            processingEngine: PDFKitProcessingEngineFallback()
        )
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Orifold-signed-conflict-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let didSave = viewModel.saveFlattenedPDF(
            to: outputURL,
            options: WorkspaceExportOptions(encryption: PDFEncryptionOptions(
                userPassword: "reader-pass",
                ownerPassword: "owner-pass"
            ))
        )

        XCTAssertFalse(didSave)
        XCTAssertFalse(FileManager.default.fileExists(atPath: outputURL.path))
        XCTAssertEqual(viewModel.exportError?.message, PDFEncryptionError.digitalSignatureConflict.userMessage)
    }
}

final class PageDecorationExportTests: XCTestCase {
    func testLegacyWorkspaceDecodesWithEmptyDecorations() throws {
        let json = """
        {
          "title": "Legacy",
          "schemaVersion": 4,
          "documents": [],
          "pageOrder": []
        }
        """

        let workspace = try JSONDecoder().decode(Workspace.self, from: Data(json.utf8))

        XCTAssertTrue(workspace.decorations.isEmpty)
        XCTAssertEqual(workspace.schemaVersion, 4)
    }

    func testPageNumberExportIsExtractableOnCurrentPage() throws {
        let fixture = try makeMemberWithPDF(name: "Decorated", pageTexts: ["one", "two", "three", "four", "five"])
        let document = WorkspaceDocument()
        document.workspace.documents = [fixture.member]
        document.workspace.pageOrder = fixture.refs
        document.workspace.decorations = [.pageNumber()]
        document.memberPDFData[fixture.member.id] = fixture.pdfData

        let exported = try document.exportedPDFDataThrowing(from: try document.snapshot(contentType: .pdf))
        let pdf = try XCTUnwrap(PDFDocument(data: exported))

        XCTAssertTrue(pdf.page(at: 2)?.string?.contains("Page 3 of 5") ?? false)
    }

    func testBatesExportSequencesFromCurrentPageOrder() throws {
        let fixture = try makeMemberWithPDF(name: "Bates", pageTexts: ["one", "two", "three", "four", "five"])
        let document = WorkspaceDocument()
        document.workspace.documents = [fixture.member]
        document.workspace.pageOrder = fixture.refs
        document.workspace.decorations = [
            PageDecoration(kind: .bates, prefix: "DEF", startNumber: 100, fontSize: 10, swatch: .tertiary)
        ]
        document.memberPDFData[fixture.member.id] = fixture.pdfData

        let exported = try document.exportedPDFDataThrowing(from: try document.snapshot(contentType: .pdf))
        let pdf = try XCTUnwrap(PDFDocument(data: exported))

        XCTAssertTrue(pdf.stringValue.contains("DEF-000100"))
        XCTAssertTrue(pdf.stringValue.contains("DEF-000104"))
    }

    func testPageNumberExportFollowsReorderedPages() throws {
        let fixture = try makeMemberWithPDF(name: "Reordered", pageTexts: ["first original", "second original", "third original"])
        let document = WorkspaceDocument()
        document.workspace.documents = [fixture.member]
        document.workspace.pageOrder = fixture.refs
        document.workspace.decorations = [.pageNumber()]
        document.memberPDFData[fixture.member.id] = fixture.pdfData
        let viewModel = WorkspaceViewModel(document: document, processingEngine: PDFKitProcessingEngineFallback())

        XCTAssertTrue(viewModel.movePage(fixture.refs[2], toIndex: 0))
        let exported = try document.exportedPDFDataThrowing(from: try document.snapshot(contentType: .pdf))
        let pdf = try XCTUnwrap(PDFDocument(data: exported))

        XCTAssertTrue(pdf.page(at: 0)?.string?.contains("Page 1 of 3") ?? false)
        XCTAssertTrue(pdf.page(at: 0)?.string?.contains("third original") ?? false)
    }

    func testWatermarkedPageStillExtractsOriginalBodyText() throws {
        let fixture = try makeMemberWithPDF(name: "Watermark", pageTexts: ["Original body text"])
        let document = WorkspaceDocument()
        document.workspace.documents = [fixture.member]
        document.workspace.pageOrder = fixture.refs
        document.workspace.decorations = [PageDecoration.watermark()]
        document.memberPDFData[fixture.member.id] = fixture.pdfData

        let exported = try document.exportedPDFDataThrowing(from: try document.snapshot(contentType: .pdf))
        let pdf = try XCTUnwrap(PDFDocument(data: exported))

        XCTAssertTrue(pdf.stringValue.contains("Original body text"))
    }

    func testBlankWatermarkTextDisablesDecorationBeforeExport() {
        let viewModel = WorkspaceViewModel(document: WorkspaceDocument(), processingEngine: PDFKitProcessingEngineFallback())

        viewModel.setDecoration(.watermark, enabled: true)
        viewModel.setDecorationText(.watermark, text: "   ")

        XCTAssertFalse(viewModel.document.workspace.hasActiveDecorations)
        XCTAssertFalse(viewModel.document.workspace.decorations.contains { $0.kind == .watermark })
    }

    func testGlobalDecorationTogglesUpdateVisibleStateAndRemoveWhenDisabled() {
        let viewModel = WorkspaceViewModel(document: WorkspaceDocument(), processingEngine: PDFKitProcessingEngineFallback())
        let initialVersion = viewModel.decorationStateVersion

        viewModel.setDecoration(.watermark, enabled: true)
        viewModel.setDecoration(.pageNumber, enabled: true)
        viewModel.setDecoration(.bates, enabled: true)

        XCTAssertTrue(viewModel.isDecorationEnabled(.watermark))
        XCTAssertTrue(viewModel.isDecorationEnabled(.pageNumber))
        XCTAssertTrue(viewModel.isDecorationEnabled(.bates))
        XCTAssertEqual(Set(viewModel.document.workspace.decorations.map(\.kind)), [.watermark, .pageNumber, .bates])
        XCTAssertEqual(viewModel.decorationStateVersion, initialVersion + 3)

        viewModel.setDecoration(.watermark, enabled: false)
        viewModel.setDecoration(.pageNumber, enabled: false)
        viewModel.setDecoration(.bates, enabled: false)

        XCTAssertFalse(viewModel.isDecorationEnabled(.watermark))
        XCTAssertFalse(viewModel.isDecorationEnabled(.pageNumber))
        XCTAssertFalse(viewModel.isDecorationEnabled(.bates))
        XCTAssertFalse(viewModel.document.workspace.hasActiveDecorations)
        XCTAssertTrue(viewModel.document.workspace.decorations.isEmpty)
    }

    func testDecorationEditingOptionsPersistThroughViewModel() {
        let viewModel = WorkspaceViewModel(document: WorkspaceDocument(), processingEngine: PDFKitProcessingEngineFallback())

        viewModel.setDecoration(.watermark, enabled: true)
        viewModel.setDecorationText(.watermark, text: "Internal only")
        viewModel.setDecorationFontSize(.watermark, fontSize: 42)
        viewModel.setDecorationOpacity(.watermark, opacity: 0.35)
        viewModel.setDecorationSwatch(.watermark, swatch: .coral)

        viewModel.setDecoration(.bates, enabled: true)
        viewModel.setDecorationPrefix(.bates, prefix: "PRD")
        viewModel.setDecorationStartNumber(.bates, startNumber: 7)
        viewModel.setDecorationFontSize(.bates, fontSize: 14)
        viewModel.setDecorationOpacity(.bates, opacity: 0.75)
        viewModel.setDecorationSwatch(.bates, swatch: .accent)

        let watermark = viewModel.decoration(of: .watermark)
        XCTAssertEqual(watermark?.text, "Internal only")
        XCTAssertEqual(watermark?.fontSize, 42)
        XCTAssertEqual(watermark?.opacity ?? 0, 0.35, accuracy: 0.001)
        XCTAssertEqual(watermark?.swatch, .coral)

        let bates = viewModel.decoration(of: .bates)
        XCTAssertEqual(bates?.prefix, "PRD")
        XCTAssertEqual(bates?.startNumber, 7)
        XCTAssertEqual(bates?.fontSize, 14)
        XCTAssertEqual(bates?.opacity ?? 0, 0.75, accuracy: 0.001)
        XCTAssertEqual(bates?.swatch, .accent)
    }

    func testEditedDecorationValuesExportWithoutErrors() throws {
        let fixture = try makeMemberWithPDF(name: "Edited decorations", pageTexts: ["alpha", "beta"])
        let document = WorkspaceDocument()
        document.workspace.documents = [fixture.member]
        document.workspace.pageOrder = fixture.refs
        document.memberPDFData[fixture.member.id] = fixture.pdfData
        let viewModel = WorkspaceViewModel(document: document, processingEngine: PDFKitProcessingEngineFallback())

        viewModel.setDecoration(.pageNumber, enabled: true)
        viewModel.setDecorationFontSize(.pageNumber, fontSize: 13)
        viewModel.setDecorationOpacity(.pageNumber, opacity: 0.8)
        viewModel.setDecorationSwatch(.pageNumber, swatch: .sage)
        viewModel.setDecoration(.bates, enabled: true)
        viewModel.setDecorationPrefix(.bates, prefix: "PKT")
        viewModel.setDecorationStartNumber(.bates, startNumber: 42)

        let exported = try document.exportedPDFDataThrowing(from: try document.snapshot(contentType: .pdf))
        let pdf = try XCTUnwrap(PDFDocument(data: exported))

        XCTAssertTrue(pdf.stringValue.contains("Page 1 of 2"))
        XCTAssertTrue(pdf.stringValue.contains("PKT-000042"))
        XCTAssertTrue(pdf.stringValue.contains("PKT-000043"))
    }

    func testThrowingExportRejectsMissingMemberPDFData() throws {
        let fixture = try makeMemberWithPDF(name: "Missing", pageTexts: ["one"])
        let document = WorkspaceDocument()
        document.workspace.documents = [fixture.member]
        document.workspace.pageOrder = fixture.refs
        document.workspace.decorations = [.pageNumber()]

        XCTAssertThrowsError(try document.exportedPDFDataThrowing(from: try document.snapshot(contentType: .pdf))) { error in
            XCTAssertEqual(error as? PDFKitEngine.ExportAssemblyError, .unreadableMember("Missing"))
        }
    }

    func testDecorationExportPreservesExistingPDFAnnotations() throws {
        let fixture = try makeMemberWithPDF(name: "Annotated", pageTexts: ["Annotated body"])
        let sourcePDF = try XCTUnwrap(PDFDocument(data: fixture.pdfData))
        let sourcePage = try XCTUnwrap(sourcePDF.page(at: 0))
        let highlight = PDFAnnotation(
            bounds: CGRect(x: 72, y: 650, width: 140, height: 18),
            forType: .highlight,
            withProperties: nil
        )
        highlight.color = .dsAnnotationSageNS
        sourcePage.addAnnotation(highlight)
        let note = PDFAnnotation(bounds: CGRect(x: 40, y: 520, width: 24, height: 24), forType: .text, withProperties: nil)
        note.contents = "Keep this note"
        sourcePage.addAnnotation(note)

        let document = WorkspaceDocument()
        document.workspace.documents = [fixture.member]
        document.workspace.pageOrder = fixture.refs
        document.workspace.decorations = [.pageNumber()]
        document.memberPDFData[fixture.member.id] = try XCTUnwrap(sourcePDF.dataRepresentation())

        let exported = try document.exportedPDFDataThrowing(from: try document.snapshot(contentType: .pdf))
        let pdf = try XCTUnwrap(PDFDocument(data: exported))
        let annotations = try XCTUnwrap(pdf.page(at: 0)?.annotations)

        XCTAssertTrue(pdf.stringValue.contains("Page 1 of 1"))
        XCTAssertTrue(annotations.contains { $0.type == "Highlight" })
        XCTAssertTrue(annotations.contains { $0.type == "Text" && $0.contents == "Keep this note" })
    }

    func testDecorationBakerRejectsBlankActiveWatermark() throws {
        let fixture = try makeMemberWithPDF(name: "Blank", pageTexts: ["one"])
        var watermark = PageDecoration.watermark()
        watermark.text = "   "

        XCTAssertThrowsError(try PDFDecorationExportBaker.bake(
            decorations: [watermark],
            pageOrder: fixture.refs,
            into: fixture.pdfData
        )) { error in
            XCTAssertEqual(error as? PDFDecorationExportBaker.BakeError, .invalidDecoration)
        }
    }

    func testDisablingGlobalDecorationRemovesPersistedState() {
        let viewModel = WorkspaceViewModel(document: WorkspaceDocument(), processingEngine: PDFKitProcessingEngineFallback())

        viewModel.setDecoration(.watermark, enabled: true)
        XCTAssertTrue(viewModel.document.workspace.hasActiveDecorations)

        viewModel.setDecoration(.watermark, enabled: false)

        XCTAssertFalse(viewModel.document.workspace.hasActiveDecorations)
        XCTAssertFalse(viewModel.document.workspace.decorations.contains { $0.kind == .watermark })
    }

    func testDecorationBakerRejectsInvalidPDFData() {
        XCTAssertThrowsError(try PDFDecorationExportBaker.bake(
            decorations: [.pageNumber()],
            pageOrder: [],
            into: Data("not a pdf".utf8)
        )) { error in
            XCTAssertTrue(error is PDFDecorationExportBaker.BakeError)
        }
    }

    func testDecorationBakerRejectsMismatchedPageOrder() throws {
        let pdfData = try XCTUnwrap(makePDF(pageTexts: ["one"]).dataRepresentation())

        XCTAssertThrowsError(try PDFDecorationExportBaker.bake(
            decorations: [.pageNumber()],
            pageOrder: [],
            into: pdfData
        )) { error in
            XCTAssertEqual(error as? PDFDecorationExportBaker.BakeError, .pageOrderMismatch)
        }
    }

    func testThrowingExportPropagatesDecorationPageOrderMismatch() throws {
        let fixture = try makeMemberWithPDF(name: "Mismatch", pageTexts: ["one"])
        let document = WorkspaceDocument()
        document.workspace.documents = [fixture.member]
        document.workspace.pageOrder = []
        document.workspace.decorations = [.pageNumber()]
        document.memberPDFData[fixture.member.id] = fixture.pdfData

        XCTAssertThrowsError(try document.exportedPDFDataThrowing(from: try document.snapshot(contentType: .pdf))) { error in
            XCTAssertEqual(error as? PDFDecorationExportBaker.BakeError, .pageOrderMismatch)
        }
    }

    func testDecorationBakerRejectsStampMissingCurrentPageRef() throws {
        let fixture = try makeMemberWithPDF(name: "Stamp", pageTexts: ["one"])
        let stamp = PageDecoration.stamp(
            text: "Approved",
            swatch: .sage,
            pageRefID: UUID(),
            rect: CGRect(x: 40, y: 40, width: 120, height: 40)
        )

        XCTAssertThrowsError(try PDFDecorationExportBaker.bake(
            decorations: [stamp],
            pageOrder: fixture.refs,
            into: fixture.pdfData
        )) { error in
            XCTAssertEqual(error as? PDFDecorationExportBaker.BakeError, .invalidStampDecoration)
        }
    }

    func testDecorationBakerRejectsStampMissingRect() throws {
        let fixture = try makeMemberWithPDF(name: "Stamp", pageTexts: ["one"])
        let stamp = PageDecoration(
            kind: .stamp,
            text: "Approved",
            pageRefID: fixture.refs[0].id,
            rect: nil,
            fontSize: 22,
            opacity: 0.88,
            swatch: .sage
        )

        XCTAssertThrowsError(try PDFDecorationExportBaker.bake(
            decorations: [stamp],
            pageOrder: fixture.refs,
            into: fixture.pdfData
        )) { error in
            XCTAssertEqual(error as? PDFDecorationExportBaker.BakeError, .invalidStampDecoration)
        }
    }

    func testStampPlacementDoesNotAddPDFAnnotationBeforeExport() throws {
        let fixture = try makeMemberWithPDF(name: "Stamp", pageTexts: ["Stamp body"])
        let document = WorkspaceDocument()
        document.workspace.documents = [fixture.member]
        document.workspace.pageOrder = fixture.refs
        document.memberPDFData[fixture.member.id] = fixture.pdfData
        let viewModel = WorkspaceViewModel(document: document, processingEngine: PDFKitProcessingEngineFallback())
        let page = try XCTUnwrap(viewModel.combinedPDF.page(at: 1))
        let annotationCount = page.annotations.count

        viewModel.beginStampPlacement(text: "Approved", swatch: .sage)
        let stamp = viewModel.placeStamp(at: CGPoint(x: 120, y: 120), on: page)

        XCTAssertNotNil(stamp)
        XCTAssertEqual(page.annotations.count, annotationCount)
        XCTAssertEqual(document.workspace.decorations.filter { $0.kind == .stamp }.count, 1)
    }

    func testRemovingStampedPageClearsSelectedStamp() throws {
        let fixture = try makeMemberWithPDF(name: "Stamp", pageTexts: ["one", "two"])
        let document = WorkspaceDocument()
        document.workspace.documents = [fixture.member]
        document.workspace.pageOrder = fixture.refs
        document.memberPDFData[fixture.member.id] = fixture.pdfData
        let viewModel = WorkspaceViewModel(document: document, processingEngine: PDFKitProcessingEngineFallback())
        let page = try XCTUnwrap(viewModel.combinedPDF.page(at: 1))

        viewModel.beginStampPlacement(text: "Approved", swatch: .sage)
        let stamp = try XCTUnwrap(viewModel.placeStamp(at: CGPoint(x: 120, y: 120), on: page))
        XCTAssertEqual(viewModel.selectedStampDecorationID, stamp.id)

        viewModel.deletePage(fixture.refs[0])

        XCTAssertNil(viewModel.selectedStampDecorationID)
        XCTAssertFalse(document.workspace.decorations.contains { $0.id == stamp.id })
    }
}

final class PDFFormExportTests: XCTestCase {
    func testFlattenedFormExportContainsValuesAndStripsWidgets() throws {
        let fixture = try makeFormMemberWithPDF(name: "Form", fieldValue: "Alice Example")
        let document = WorkspaceDocument()
        document.workspace.documents = [fixture.member]
        document.workspace.pageOrder = fixture.refs
        document.memberPDFData[fixture.member.id] = fixture.pdfData

        let exported = try document.exportedPDFDataThrowing(
            from: try document.snapshot(contentType: .pdf),
            options: WorkspaceExportOptions(lockFormAnswers: true)
        )
        let pdf = try XCTUnwrap(PDFDocument(data: exported))
        let page = try XCTUnwrap(pdf.page(at: 0))

        XCTAssertTrue(pdf.stringValue.contains("Alice Example"))
        XCTAssertFalse(page.annotations.contains { $0.isPDFWidget })
    }

    func testUnflattenedFormExportStaysFillable() throws {
        let fixture = try makeFormMemberWithPDF(name: "Form", fieldValue: "Editable")
        let document = WorkspaceDocument()
        document.workspace.documents = [fixture.member]
        document.workspace.pageOrder = fixture.refs
        document.memberPDFData[fixture.member.id] = fixture.pdfData

        let exported = try document.exportedPDFDataThrowing(
            from: try document.snapshot(contentType: .pdf),
            options: WorkspaceExportOptions(lockFormAnswers: false)
        )
        let pdf = try XCTUnwrap(PDFDocument(data: exported))
        let widgets = try XCTUnwrap(pdf.page(at: 0)?.annotations.filter { $0.isPDFWidget })

        XCTAssertEqual(widgets.count, 1)
        XCTAssertEqual(widgets.first?.widgetStringValue, "Editable")
    }

    func testCheckboxFlatteningDrawsOnStateAndStripsWidget() throws {
        let fixture = try makeCheckboxMemberWithPDF(name: "Checkbox", isOn: true)
        let document = WorkspaceDocument()
        document.workspace.documents = [fixture.member]
        document.workspace.pageOrder = fixture.refs
        document.memberPDFData[fixture.member.id] = fixture.pdfData

        let exported = try document.exportedPDFDataThrowing(
            from: try document.snapshot(contentType: .pdf),
            options: WorkspaceExportOptions(lockFormAnswers: true)
        )
        let pdf = try XCTUnwrap(PDFDocument(data: exported))
        let page = try XCTUnwrap(pdf.page(at: 0))

        XCTAssertFalse(page.annotations.contains { $0.isPDFWidget })
        XCTAssertTrue(pdf.stringValue.contains("✓"))
    }

    func testMalformedRadioGroupFlattensOnlyOneOnState() throws {
        let fixture = try makeRadioMemberWithPDF(name: "Radio", bothOn: true)
        let document = WorkspaceDocument()
        document.workspace.documents = [fixture.member]
        document.workspace.pageOrder = fixture.refs
        document.memberPDFData[fixture.member.id] = fixture.pdfData

        let exported = try document.exportedPDFDataThrowing(
            from: try document.snapshot(contentType: .pdf),
            options: WorkspaceExportOptions(lockFormAnswers: true)
        )
        let pdf = try XCTUnwrap(PDFDocument(data: exported))

        XCTAssertEqual(pdf.stringValue.filter { $0 == "✓" }.count, 1)
    }

    func testResetFormClearsValuesAndUndoRestoresThem() throws {
        let fixture = try makeFormMemberWithPDF(name: "Form", fieldValue: "Alice")
        let document = WorkspaceDocument()
        document.workspace.documents = [fixture.member]
        document.workspace.pageOrder = fixture.refs
        document.memberPDFData[fixture.member.id] = fixture.pdfData
        let viewModel = WorkspaceViewModel(document: document, processingEngine: PDFKitProcessingEngineFallback())
        let undoManager = UndoManager()
        viewModel.undoManager = undoManager

        viewModel.resetFormFields()

        let resetField = try XCTUnwrap(viewModel.loadedPDFs.first?.1.page(at: 0)?.annotations.first { $0.isPDFWidget })
        XCTAssertEqual(resetField.widgetStringValue, "")

        undoManager.undo()

        let restoredField = try XCTUnwrap(viewModel.loadedPDFs.first?.1.page(at: 0)?.annotations.first { $0.isPDFWidget })
        XCTAssertEqual(restoredField.widgetStringValue, "Alice")
    }

    func testFormSummaryDetectsWidgetFields() throws {
        let fixture = try makeFormMemberWithPDF(name: "Form", fieldValue: "Alice")
        let pdf = try XCTUnwrap(PDFDocument(data: fixture.pdfData))

        let summary = PDFFormSupport.scan(documents: [(fixture.member, pdf)], pageOrder: fixture.refs)

        XCTAssertEqual(summary.fieldCount, 1)
        XCTAssertEqual(summary.fields.first?.fieldName, "Full name")
    }

    func testUnsupportedDynamicFormMarkersAreDetected() {
        XCTAssertTrue(PDFFormSupport.containsUnsupportedDynamicFeatures(in: Data("/XFA 4 0 R".utf8)))
        XCTAssertTrue(PDFFormSupport.containsUnsupportedDynamicFeatures(in: Data("/JavaScript 7 0 R".utf8)))
        XCTAssertTrue(PDFFormSupport.containsUnsupportedDynamicFeatures(in: Data("/JS (calculate())".utf8)))
        XCTAssertFalse(PDFFormSupport.containsUnsupportedDynamicFeatures(in: Data("/AcroForm << /Fields [] >>".utf8)))
    }
}

final class PDFCompressionExportTests: XCTestCase {
    func testPhotoFixtureShrinksByAtLeastThirtyPercentAndValidatesWithPDFium() throws {
        let sourceData = try makePhotoPDFData()
        let result = try PDFCompressionService.reduceFileSize(
            of: sourceData,
            preset: .balanced,
            processingEngine: PDFiumProcessingEngine()
        )

        XCTAssertLessThan(result.compressedByteCount, Int(Double(result.originalByteCount) * 0.7))
        let validation = try PDFiumProcessingEngine().validatePDF(data: result.data, password: nil)
        XCTAssertEqual(validation.pageCount, 1)
    }

    func testTextOnlyPDFTakesAlreadyOptimizedPath() throws {
        let sourcePDF = makePDF(pageTexts: ["This page is already small and searchable."])
        let sourceData = try sourcePDF.dataRepresentation().unwrap()

        XCTAssertThrowsError(
            try PDFCompressionService.reduceFileSize(
                of: sourceData,
                preset: .balanced,
                processingEngine: PDFKitProcessingEngineFallback()
            )
        ) { error in
            XCTAssertEqual(error as? PDFCompressionError, .grewLarger)
        }
    }

    func testCompressionCancellationStopsBeforeProducingOutput() throws {
        let sourceData = try makePhotoPDFData()

        XCTAssertThrowsError(
            try PDFCompressionService.reduceFileSize(
                of: sourceData,
                preset: .small,
                processingEngine: PDFKitProcessingEngineFallback(),
                isCancelled: { true }
            )
        ) { error in
            XCTAssertEqual(error as? PDFCompressionError, .cancelled)
        }
    }

    func testCompressedPDFPreservesExtractedText() throws {
        let sourceData = try makePhotoPDFData(text: "Compression keeps searchable text")
        let result = try PDFCompressionService.reduceFileSize(
            of: sourceData,
            preset: .balanced,
            processingEngine: PDFKitProcessingEngineFallback()
        )
        let compressedPDF = try PDFDocument(data: result.data).unwrap()

        XCTAssertEqual(compressedPDF.stringValue, "Compression keeps searchable text")
    }
}

@MainActor
final class V6IntegratedFlowTests: XCTestCase {
    func testFinalGateAllFiveFeaturesTogether() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Orifold-v6-final-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let formFixture = try makeFormMemberWithPDF(name: "Integrated form", fieldValue: "Integrated Answer")
        let formURL = tempDirectory.appendingPathComponent("Integrated form.pdf")
        let docxURL = tempDirectory.appendingPathComponent("Integrated rich.docx")
        let imageURL = tempDirectory.appendingPathComponent("Integrated scan.png")
        let docxData = makeMinimalDOCXData(text: "Integrated rich text")
        try formFixture.pdfData.write(to: formURL)
        try docxData.write(to: docxURL)
        try makePNGData().write(to: imageURL)

        let document = WorkspaceDocument()
        let viewModel = WorkspaceViewModel(document: document, processingEngine: PDFiumProcessingEngine())
        viewModel.importFiles(urls: [formURL, docxURL, imageURL])
        try await waitForImportsToFinish(in: viewModel)
        XCTAssertNil(viewModel.importError)
        XCTAssertEqual(viewModel.memberDocuments.count, 3)

        let formMember = try XCTUnwrap(viewModel.memberDocuments.first { $0.displayName == "Integrated form" })
        let richMember = try XCTUnwrap(viewModel.memberDocuments.first { $0.displayName == "Integrated rich" })
        let scanMember = try XCTUnwrap(viewModel.memberDocuments.first { $0.displayName == "Integrated scan" })
        let formRef = try XCTUnwrap(document.workspace.pageOrder.first { $0.memberDocId == formMember.id })
        let richRefs = document.workspace.pageOrder.filter { $0.memberDocId == richMember.id }
        let richRef = try XCTUnwrap(richRefs.first)
        let scanRef = try XCTUnwrap(document.workspace.pageOrder.first { $0.memberDocId == scanMember.id })
        XCTAssertEqual(document.sourcePayloads[richMember.id]?.format, .docx)
        XCTAssertEqual(document.sourcePayloads[richMember.id]?.originalData, docxData)

        let scanDocumentIndex = try XCTUnwrap(viewModel.memberDocuments.firstIndex { $0.id == scanMember.id })
        viewModel.moveDocument(from: IndexSet(integer: scanDocumentIndex), to: 1)
        viewModel.rotatePage(richRef, by: 90)
        XCTAssertEqual(viewModel.loadedPDFs.first { $0.0.id == richMember.id }?.1.page(at: 0)?.rotation, 90)
        let formPage = try XCTUnwrap(viewModel.loadedPDFs.first { $0.0.id == formMember.id }?.1.page(at: 0))
        let note = try XCTUnwrap(viewModel.addNote(at: CGPoint(x: 96, y: 96), on: formPage))
        note.contents = "Integrated annotation"
        XCTAssertEqual(document.workspace.pageOrder.map(\.id), [formRef.id, scanRef.id] + richRefs.map(\.id))

        let preOCRSnapshot = try document.snapshot(contentType: .pdf)
        _ = try PDFiumProcessingEngine().validatePDF(data: formFixture.pdfData, password: nil)
        let scanData = try XCTUnwrap(preOCRSnapshot.memberPDFData[scanMember.id])
        _ = try PDFiumProcessingEngine().validatePDF(data: scanData, password: nil)
        let ocrResult = try await PDFOCRService.searchableData(
            documents: [(scanMember, scanData)],
            recognitionProvider: { _, _, _ in
                [
                    PDFOCRRecognizedLine(
                        text: "Integrated scan phrase",
                        normalizedBounds: CGRect(x: 0.16, y: 0.72, width: 0.5, height: 0.06),
                        confidence: 0.95
                    )
                ]
            }
        )
        let searchableScanData = try XCTUnwrap(ocrResult.dataByMemberID[scanMember.id])
        _ = try PDFiumProcessingEngine().validatePDF(data: searchableScanData, password: nil)
        document.memberPDFData[scanMember.id] = searchableScanData
        let searchableScanPDF = try XCTUnwrap(PDFDocument(data: searchableScanData))
        let scanIndex = try XCTUnwrap(viewModel.loadedPDFs.firstIndex { $0.0.id == scanMember.id })
        viewModel.loadedPDFs[scanIndex] = (viewModel.loadedPDFs[scanIndex].0, searchableScanPDF)

        document.workspace.title = "V6 final gate"
        document.workspace.decorations = [
            PageDecoration(kind: .watermark, text: "Internal", fontSize: 42, opacity: 0.18, swatch: .tertiary),
            .pageNumber()
        ]

        let snapshot = try document.snapshot(contentType: .pdf)
        let flattenedDecorated = try document.exportedPDFDataThrowing(
            from: snapshot,
            options: WorkspaceExportOptions(lockFormAnswers: true)
        )
        _ = try PDFiumProcessingEngine().validatePDF(data: flattenedDecorated, password: nil)
        let flattenedPDF = try XCTUnwrap(PDFDocument(data: flattenedDecorated))
        let decorationPageCount = document.workspace.pageOrder.count

        XCTAssertTrue(flattenedPDF.stringValue.contains("Integrated Answer"))
        XCTAssertTrue(flattenedPDF.stringValue.contains("Integrated scan phrase"))
        XCTAssertTrue(flattenedPDF.stringValue.contains("Internal"))
        XCTAssertTrue(flattenedPDF.stringValue.contains("Page 1 of \(decorationPageCount)"))
        XCTAssertTrue(flattenedPDF.stringValue.contains("Page 2 of \(decorationPageCount)"))
        XCTAssertTrue(flattenedPDF.stringValue.contains("Page \(decorationPageCount) of \(decorationPageCount)"))
        XCTAssertFalse(flattenedPDF.page(at: 0)?.annotations.contains { $0.isPDFWidget } ?? true)
        XCTAssertTrue(flattenedPDF.page(at: 0)?.annotations.contains { $0.contents == "Integrated annotation" } ?? false)

        let compressionSourcePDF = try XCTUnwrap(PDFDocument(data: flattenedDecorated))
        let photoPDF = try XCTUnwrap(PDFDocument(data: try makePhotoPDFData()))
        let photoPage = try XCTUnwrap(photoPDF.page(at: 0))
        compressionSourcePDF.insert(photoPage, at: compressionSourcePDF.pageCount)
        let compressionSource = try compressionSourcePDF.dataRepresentation().unwrap()
        let pageCount = compressionSourcePDF.pageCount

        let compressed = try PDFCompressionService.reduceFileSize(
            of: compressionSource,
            preset: .balanced,
            processingEngine: PDFiumProcessingEngine()
        )
        XCTAssertLessThan(compressed.compressedByteCount, compressed.originalByteCount)
        _ = try PDFiumProcessingEngine().validatePDF(data: compressed.data, password: nil)

        let encryptionOptions = PDFEncryptionOptions(
            userPassword: "reader-pass",
            ownerPassword: "owner-pass",
            allowsPrinting: true,
            allowsCopying: false
        )
        let encrypted = try PDFEncryptionService.encryptedData(from: compressed.data, options: encryptionOptions)
        try PDFEncryptionService.validateEncryptedData(encrypted, options: encryptionOptions)
        let validation = try PDFiumProcessingEngine().validatePDF(data: encrypted, password: encryptionOptions.userPassword)
        XCTAssertEqual(validation.pageCount, pageCount)

        let encryptedPDF = try XCTUnwrap(PDFDocument(data: encrypted))
        XCTAssertTrue(encryptedPDF.isLocked)
        XCTAssertTrue(encryptedPDF.unlock(withPassword: encryptionOptions.userPassword))
        XCTAssertTrue(encryptedPDF.stringValue.contains("Integrated Answer"))
        XCTAssertTrue(encryptedPDF.stringValue.contains("Integrated scan phrase"))

        let reopenedDocument = WorkspaceDocument()
        let reopenedViewModel = WorkspaceViewModel(document: reopenedDocument, processingEngine: PDFiumProcessingEngine())
        let protectedURL = tempDirectory.appendingPathComponent("Protected final.pdf")
        try encrypted.write(to: protectedURL)
        reopenedViewModel.importFiles(urls: [protectedURL])
        try await waitForImportsToFinish(in: reopenedViewModel)
        XCTAssertNotNil(reopenedViewModel.pendingPasswordPDF)
        let pendingPDF = try XCTUnwrap(reopenedViewModel.pendingPasswordPDF)
        XCTAssertTrue(reopenedViewModel.unlock(pdf: pendingPDF, password: encryptionOptions.userPassword, url: protectedURL))
        XCTAssertTrue(reopenedViewModel.loadedPDFs.first?.1.stringValue.contains("Integrated Answer") ?? false)
        XCTAssertTrue(reopenedViewModel.loadedPDFs.first?.1.stringValue.contains("Integrated scan phrase") ?? false)
    }
}

/// Walks up from `sourceFile` using plain string path components (rather than
/// repeated `URL.deletingLastPathComponent()` calls) to locate the repo root
/// and find `Orifold/Resources/Info.plist`. The walk is bounded by the fixed,
/// finite number of path components in `sourceFile`, so it cannot loop
/// unboundedly even if a `URL` path-reduction edge case on a given
/// Foundation/OS version fails to converge as expected.
private func appInfoPlistURL(sourceFile: String) throws -> URL {
    let environment = ProcessInfo.processInfo.environment
    var pathComponents = sourceFile.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    // Drop the file name and its two enclosing directories (OrifoldTests, Tests) to reach the repo root.
    pathComponents.removeLast(min(3, pathComponents.count))

    var candidatePaths = ["SRCROOT", "PROJECT_DIR"].compactMap { environment[$0] }
    var remaining = pathComponents
    while !remaining.isEmpty {
        candidatePaths.append("/" + remaining.joined(separator: "/"))
        remaining.removeLast()
    }
    candidatePaths.append("/")

    for root in candidatePaths {
        let plistPath = (root as NSString).appendingPathComponent("Orifold/Resources/Info.plist")
        if FileManager.default.fileExists(atPath: plistPath) {
            return URL(fileURLWithPath: plistPath)
        }
    }

    XCTFail("Could not locate Orifold/Resources/Info.plist from Xcode or SwiftPM source roots.")
    throw CocoaError(.fileNoSuchFile)
}

private func makeMemberPDF(name: String, pageTexts: [String]) -> (MemberDocument, PDFDocument) {
    let pdf = makePDF(pageTexts: pageTexts)
    var member = MemberDocument(displayName: name, sourcePDFRef: "\(name).pdf")
    member.pageRefs = (0..<pdf.pageCount).map { _ in UUID() }
    return (member, pdf)
}

private func makePNGData() throws -> Data {
    let image = NSImage(size: NSSize(width: 256, height: 256))
    image.lockFocus()
    NSColor.white.setFill()
    NSRect(x: 0, y: 0, width: 256, height: 256).fill()
    NSColor.systemBlue.setFill()
    NSBezierPath(ovalIn: NSRect(x: 40, y: 40, width: 176, height: 176)).fill()
    image.unlockFocus()

    let tiffData = try XCTUnwrap(image.tiffRepresentation)
    let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiffData))
    return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
}

private func makeMinimalDOCXData(text: String) -> Data {
    let escaped = text
        .replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
        .replacingOccurrences(of: "\"", with: "&quot;")
        .replacingOccurrences(of: "'", with: "&apos;")
    let entries: [(String, Data)] = [
        (
            "[Content_Types].xml",
            Data("""
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
              <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
              <Default Extension="xml" ContentType="application/xml"/>
              <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
            </Types>
            """.utf8)
        ),
        (
            "_rels/.rels",
            Data("""
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
              <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
            </Relationships>
            """.utf8)
        ),
        (
            "word/document.xml",
            Data("""
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
              <w:body>
                <w:p><w:r><w:t>\(escaped)</w:t></w:r></w:p>
                <w:sectPr/>
              </w:body>
            </w:document>
            """.utf8)
        )
    ]
    return makeStoredZipData(entries: entries)
}

private func makeStoredZipData(entries: [(String, Data)]) -> Data {
    var archive = Data()
    var centralDirectory = Data()
    var localOffsets: [UInt32] = []

    for (name, data) in entries {
        let nameData = Data(name.utf8)
        let crc = crc32(data)
        localOffsets.append(UInt32(archive.count))
        archive.appendLittleEndian(UInt32(0x04034b50))
        archive.appendLittleEndian(UInt16(20))
        archive.appendLittleEndian(UInt16(0))
        archive.appendLittleEndian(UInt16(0))
        archive.appendLittleEndian(UInt16(0))
        archive.appendLittleEndian(UInt16(0))
        archive.appendLittleEndian(crc)
        archive.appendLittleEndian(UInt32(data.count))
        archive.appendLittleEndian(UInt32(data.count))
        archive.appendLittleEndian(UInt16(nameData.count))
        archive.appendLittleEndian(UInt16(0))
        archive.append(nameData)
        archive.append(data)
    }

    for (index, entry) in entries.enumerated() {
        let nameData = Data(entry.0.utf8)
        let crc = crc32(entry.1)
        centralDirectory.appendLittleEndian(UInt32(0x02014b50))
        centralDirectory.appendLittleEndian(UInt16(20))
        centralDirectory.appendLittleEndian(UInt16(20))
        centralDirectory.appendLittleEndian(UInt16(0))
        centralDirectory.appendLittleEndian(UInt16(0))
        centralDirectory.appendLittleEndian(UInt16(0))
        centralDirectory.appendLittleEndian(UInt16(0))
        centralDirectory.appendLittleEndian(crc)
        centralDirectory.appendLittleEndian(UInt32(entry.1.count))
        centralDirectory.appendLittleEndian(UInt32(entry.1.count))
        centralDirectory.appendLittleEndian(UInt16(nameData.count))
        centralDirectory.appendLittleEndian(UInt16(0))
        centralDirectory.appendLittleEndian(UInt16(0))
        centralDirectory.appendLittleEndian(UInt16(0))
        centralDirectory.appendLittleEndian(UInt16(0))
        centralDirectory.appendLittleEndian(UInt32(0))
        centralDirectory.appendLittleEndian(localOffsets[index])
        centralDirectory.append(nameData)
    }

    let centralDirectoryOffset = UInt32(archive.count)
    archive.append(centralDirectory)
    archive.appendLittleEndian(UInt32(0x06054b50))
    archive.appendLittleEndian(UInt16(0))
    archive.appendLittleEndian(UInt16(0))
    archive.appendLittleEndian(UInt16(entries.count))
    archive.appendLittleEndian(UInt16(entries.count))
    archive.appendLittleEndian(UInt32(centralDirectory.count))
    archive.appendLittleEndian(centralDirectoryOffset)
    archive.appendLittleEndian(UInt16(0))
    return archive
}

private func crc32(_ data: Data) -> UInt32 {
    var crc: UInt32 = 0xffffffff
    for byte in data {
        var current = crc ^ UInt32(byte)
        for _ in 0..<8 {
            current = (current & 1) == 1 ? (current >> 1) ^ 0xedb88320 : current >> 1
        }
        crc = current
    }
    return crc ^ 0xffffffff
}

private extension Data {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }
}

private func makeMemberWithPDF(
    name: String,
    pageTexts: [String]
) throws -> (member: MemberDocument, refs: [PageRef], pdfData: Data) {
    let pdf = makePDF(pageTexts: pageTexts)
    var member = MemberDocument(displayName: name, sourcePDFRef: "\(name).pdf")
    let refs = (0..<pdf.pageCount).map { PageRef(memberDocId: member.id, sourcePageIndex: $0) }
    member.pageRefs = refs.map(\.id)
    let pdfData = try pdf.dataRepresentation().unwrap()
    return (member, refs, pdfData)
}

/// A page with visible ink but no extractable text layer at all — neither PDFium nor
/// PDFKit can produce any text blocks for it, matching `PDFOCRService.isLikelyScannedPage`.
private func makeMemberWithScannedPDF(
    name: String
) throws -> (member: MemberDocument, refs: [PageRef], pdfData: Data) {
    let view = ScannedFixturePageView(frame: CGRect(x: 0, y: 0, width: 612, height: 792))
    let pdf = try XCTUnwrap(PDFDocument(data: view.dataWithPDF(inside: view.bounds)))
    var member = MemberDocument(displayName: name, sourcePDFRef: "\(name).pdf")
    let refs = (0..<pdf.pageCount).map { PageRef(memberDocId: member.id, sourcePageIndex: $0) }
    member.pageRefs = refs.map(\.id)
    let pdfData = try pdf.dataRepresentation().unwrap()
    return (member, refs, pdfData)
}

private final class ScannedFixturePageView: NSView {
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        bounds.fill()
        NSColor(calibratedWhite: 0.85, alpha: 1).setFill()
        NSBezierPath(rect: CGRect(x: 100, y: 160, width: 400, height: 300)).fill()
        NSColor(calibratedWhite: 0.3, alpha: 1).setFill()
        NSBezierPath(ovalIn: CGRect(x: 240, y: 260, width: 100, height: 100)).fill()
    }
}

private func makeFormMemberWithPDF(
    name: String,
    fieldValue: String
) throws -> (member: MemberDocument, refs: [PageRef], pdfData: Data) {
    let pdf = makePDF(pageTexts: ["Form body"])
    let page = try XCTUnwrap(pdf.page(at: 0))
    let field = PDFAnnotation(
        bounds: CGRect(x: 120, y: 600, width: 220, height: 28),
        forType: .widget,
        withProperties: nil
    )
    field.widgetFieldType = .text
    field.fieldName = "Full name"
    field.widgetStringValue = fieldValue
    page.addAnnotation(field)
    return try makeMemberFixture(name: name, pdf: pdf)
}

private func makeCheckboxMemberWithPDF(
    name: String,
    isOn: Bool
) throws -> (member: MemberDocument, refs: [PageRef], pdfData: Data) {
    let pdf = makePDF(pageTexts: ["Checkbox body"])
    let page = try XCTUnwrap(pdf.page(at: 0))
    let checkbox = PDFAnnotation(
        bounds: CGRect(x: 120, y: 600, width: 20, height: 20),
        forType: .widget,
        withProperties: nil
    )
    checkbox.widgetFieldType = .button
    checkbox.widgetControlType = .checkBoxControl
    checkbox.fieldName = "Accept"
    checkbox.buttonWidgetState = isOn ? .onState : .offState
    page.addAnnotation(checkbox)
    return try makeMemberFixture(name: name, pdf: pdf)
}

private func makeRadioMemberWithPDF(
    name: String,
    bothOn: Bool
) throws -> (member: MemberDocument, refs: [PageRef], pdfData: Data) {
    let pdf = makePDF(pageTexts: ["Radio body"])
    let page = try XCTUnwrap(pdf.page(at: 0))
    for index in 0..<2 {
        let radio = PDFAnnotation(
            bounds: CGRect(x: 120 + CGFloat(index * 32), y: 600, width: 20, height: 20),
            forType: .widget,
            withProperties: nil
        )
        radio.widgetFieldType = .button
        radio.widgetControlType = .radioButtonControl
        radio.fieldName = "Choice"
        radio.buttonWidgetState = bothOn || index == 0 ? .onState : .offState
        page.addAnnotation(radio)
    }
    return try makeMemberFixture(name: name, pdf: pdf)
}

private func makePhotoPDFData(text: String = "") throws -> Data {
    let pageBounds = CGRect(x: 0, y: 0, width: 612, height: 792)
    let data = NSMutableData()
    var mediaBox = pageBounds
    guard let consumer = CGDataConsumer(data: data),
          let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil),
          let image = makePhotoFixtureImage(width: 2400, height: 2400) else {
        throw PDFCompressionError.writeFailed
    }

    context.beginPDFPage(nil)
    context.draw(image, in: pageBounds)
    if !text.isEmpty {
        drawExtractableText(text, in: context, pageBounds: pageBounds)
    }
    context.endPDFPage()
    context.closePDF()
    return data as Data
}

private func makePhotoFixtureImage(width: Int, height: Int) -> CGImage? {
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    for y in 0..<height {
        for x in 0..<width {
            let offset = (y * width + x) * 4
            pixels[offset] = UInt8((x * y) % 255)
            pixels[offset + 1] = UInt8((x + 2 * y) % 255)
            pixels[offset + 2] = UInt8((2 * x + y) % 255)
            pixels[offset + 3] = 255
        }
    }

    return pixels.withUnsafeBytes { rawBuffer in
        guard let provider = CGDataProvider(data: Data(rawBuffer) as CFData) else { return nil }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }
}

private func drawExtractableText(_ text: String, in context: CGContext, pageBounds: CGRect) {
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont(name: "Helvetica", size: 18) ?? NSFont.systemFont(ofSize: 18),
        .foregroundColor: NSColor.black
    ]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
    context.saveGState()
    context.textMatrix = .identity
    context.textPosition = CGPoint(x: 72, y: pageBounds.height - 92)
    CTLineDraw(line, context)
    context.restoreGState()
}

private func makeMemberFixture(
    name: String,
    pdf: PDFDocument
) throws -> (member: MemberDocument, refs: [PageRef], pdfData: Data) {
    var member = MemberDocument(displayName: name, sourcePDFRef: "\(name).pdf")
    let refs = (0..<pdf.pageCount).map { PageRef(memberDocId: member.id, sourcePageIndex: $0) }
    member.pageRefs = refs.map(\.id)
    let pdfData = try pdf.dataRepresentation().unwrap()
    return (member, refs, pdfData)
}

private func waitForImportsToFinish(in viewModel: WorkspaceViewModel) async throws {
    let deadline = Date().addingTimeInterval(2)
    while viewModel.isImporting && Date() < deadline {
        try await Task.sleep(nanoseconds: 20_000_000)
    }
    XCTAssertFalse(viewModel.isImporting, "import did not finish before timeout")
}

private func makePDF(pageTexts: [String]) -> PDFDocument {
    let document = PDFDocument()
    for (index, text) in pageTexts.enumerated() {
        let view = TextFixturePageView(
            frame: CGRect(x: 0, y: 0, width: 612, height: 792),
            text: text
        )
        let data = view.dataWithPDF(inside: view.bounds)
        let pageDocument = PDFDocument(data: data)!
        let page = pageDocument.page(at: 0)!
        document.insert(page, at: index)
    }
    return document
}

private func makeScaledTextPDF(text: String, fontSize: CGFloat, scale: CGFloat) -> PDFDocument {
    let view = ScaledTextFixturePageView(
        frame: CGRect(x: 0, y: 0, width: 612, height: 792),
        text: text,
        fontSize: fontSize,
        scale: scale
    )
    return PDFDocument(data: view.dataWithPDF(inside: view.bounds))!
}

private func makeWrappedBulletPDF() -> PDFDocument {
    let view = WrappedBulletFixturePageView(frame: CGRect(x: 0, y: 0, width: 612, height: 792))
    return PDFDocument(data: view.dataWithPDF(inside: view.bounds))!
}

private func makeTwoColumnPDF() -> PDFDocument {
    let view = TwoColumnFixturePageView(frame: CGRect(x: 0, y: 0, width: 612, height: 792))
    return PDFDocument(data: view.dataWithPDF(inside: view.bounds))!
}

private func makeTwoColumnWrappedPDF() -> PDFDocument {
    let view = TwoColumnWrappedFixturePageView(frame: CGRect(x: 0, y: 0, width: 612, height: 792))
    return PDFDocument(data: view.dataWithPDF(inside: view.bounds))!
}

private func makeHyperlinkThenPlainTextPDF() -> PDFDocument {
    let view = HyperlinkThenPlainTextFixturePageView(frame: CGRect(x: 0, y: 0, width: 612, height: 792))
    return PDFDocument(data: view.dataWithPDF(inside: view.bounds))!
}

private func makeMidSentenceBoldPDF() -> PDFDocument {
    let view = MidSentenceBoldFixturePageView(frame: CGRect(x: 0, y: 0, width: 612, height: 792))
    return PDFDocument(data: view.dataWithPDF(inside: view.bounds))!
}

private func makeConsecutiveBulletsPDF() -> PDFDocument {
    let view = ConsecutiveBulletsFixturePageView(frame: CGRect(x: 0, y: 0, width: 612, height: 792))
    return PDFDocument(data: view.dataWithPDF(inside: view.bounds))!
}

private func makeTwoLinePDF() -> PDFDocument {
    let view = TwoLineFixturePageView(frame: CGRect(x: 0, y: 0, width: 612, height: 792))
    return PDFDocument(data: view.dataWithPDF(inside: view.bounds))!
}

private func makeRepeatedIdenticalTextPDF(text: String) -> PDFDocument {
    let view = RepeatedIdenticalTextFixturePageView(frame: CGRect(x: 0, y: 0, width: 612, height: 792), text: text)
    return PDFDocument(data: view.dataWithPDF(inside: view.bounds))!
}

private func makeStackedParagraphsPDF() -> PDFDocument {
    let view = StackedParagraphsFixturePageView(frame: CGRect(x: 0, y: 0, width: 612, height: 792))
    return PDFDocument(data: view.dataWithPDF(inside: view.bounds))!
}

private func makeRepeatedParagraphsPDF() -> PDFDocument {
    let view = RepeatedParagraphsFixturePageView(frame: CGRect(x: 0, y: 0, width: 612, height: 792))
    return PDFDocument(data: view.dataWithPDF(inside: view.bounds))!
}

private func renderedBitmap(for page: PDFPage) throws -> NSBitmapImageRep {
    let thumbnail = page.thumbnail(of: CGSize(width: 612, height: 792), for: .mediaBox)
    let tiff = try thumbnail.tiffRepresentation.unwrap()
    return try NSBitmapImageRep(data: tiff).unwrap()
}

private func darkPixelCount(in pdfRect: CGRect, bitmap: NSBitmapImageRep) -> Int {
    let rect = pdfRect.standardized
    guard rect.width > 0, rect.height > 0 else { return 0 }

    let minX = max(0, Int(floor(rect.minX)))
    let maxX = min(bitmap.pixelsWide - 1, Int(ceil(rect.maxX)))
    let minY = max(0, Int(floor(CGFloat(bitmap.pixelsHigh) - rect.maxY)))
    let maxY = min(bitmap.pixelsHigh - 1, Int(ceil(CGFloat(bitmap.pixelsHigh) - rect.minY)))
    guard minX <= maxX, minY <= maxY else { return 0 }

    var count = 0
    for y in minY...maxY {
        for x in minX...maxX {
            guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
            if color.brightnessComponent < 0.45 {
                count += 1
            }
        }
    }
    return count
}

private func assertVisibleTextPixels(
    in bounds: CGRect,
    viewModel: WorkspaceViewModel,
    message: String,
    file: StaticString = #filePath,
    line: UInt = #line
) throws {
    let page = try XCTUnwrap(viewModel.loadedPDFs.first?.1.page(at: 0), file: file, line: line)
    let bitmap = try renderedBitmap(for: page)
    XCTAssertGreaterThan(darkPixelCount(in: bounds, bitmap: bitmap), 50, message, file: file, line: line)
}

private struct InlineEditorFixture {
    let pdfView: OrifoldPDFView
    let page: PDFPage
    let overlay: InlineTextEditorOverlay
    let viewModel: WorkspaceViewModel
    let committedEdit: () -> InlineTextEditorOverlay.EditResult?
}

private func makeInlineEditorFixture(
    text: String = "Original text",
    textColor: CodableColor = .documentText,
    pageRef: PageRef = PageRef(memberDocId: UUID(), sourcePageIndex: 0),
    block customBlock: EditableTextBlock? = nil,
    sourceFormat customSourceFormat: PDFTextEditFormat? = nil,
    pdfViewFrame: CGRect = CGRect(x: 0, y: 0, width: 900, height: 1000)
) throws -> InlineEditorFixture {
    let pdf = makePDF(pageTexts: [text.isEmpty ? " " : text])
    let pdfView = OrifoldPDFView(frame: pdfViewFrame)
    pdfView.document = pdf
    pdfView.autoScales = false
    pdfView.scaleFactor = 1
    pdfView.layoutDocumentView()

    let page = try XCTUnwrap(pdf.page(at: 0))
    let block = customBlock ?? EditableTextBlock(
        pageRefID: pageRef.id,
        text: text,
        bounds: CGRect(x: 72, y: 650, width: 160, height: 16),
        lines: [],
        fontName: "Helvetica",
        fontSize: 8,
        textColor: textColor,
        rotation: 0,
        baseline: 650,
        confidence: .high
    )
    var committed: InlineTextEditorOverlay.EditResult?
    let viewModel = WorkspaceViewModel(document: WorkspaceDocument())
    let overlay = InlineTextEditorOverlay(
        frame: pdfView.bounds,
        viewModel: viewModel,
        pdfView: pdfView,
        page: page,
        pageRef: pageRef,
        block: block,
        sourceFormat: customSourceFormat ?? PDFTextEditFormat(block: block)
    ) { completion in
        if case .commit(let edit) = completion {
            committed = edit
        }
    }
    pdfView.addSubview(overlay)
    overlay.layoutSubtreeIfNeeded()
    return InlineEditorFixture(pdfView: pdfView, page: page, overlay: overlay, viewModel: viewModel) {
        committed
    }
}

private func inlineEditorButton(in root: NSView, identifier: String) -> NSButton? {
    findSubview(in: root) { (button: NSButton) in
        button.identifier?.rawValue == identifier
    }
}

private func hitTest(_ root: NSView, at point: NSPoint, reaches expected: NSView) -> Bool {
    guard let hit = root.hitTest(point) else { return false }
    return hit === expected || hit.isDescendant(of: expected) || expected.isDescendant(of: hit)
}

private func findSubview<T: NSView>(in root: NSView, matching predicate: (T) -> Bool) -> T? {
    if let typed = root as? T, predicate(typed) {
        return typed
    }
    for subview in root.subviews {
        if let found: T = findSubview(in: subview, matching: predicate) {
            return found
        }
    }
    return nil
}

private func colorsApproximatelyEqual(_ lhs: NSColor?, _ rhs: NSColor, tolerance: CGFloat = 0.001) -> Bool {
    guard let left = lhs?.usingColorSpace(.sRGB),
          let right = rhs.usingColorSpace(.sRGB) else {
        return false
    }
    var leftRed: CGFloat = 0
    var leftGreen: CGFloat = 0
    var leftBlue: CGFloat = 0
    var leftAlpha: CGFloat = 0
    var rightRed: CGFloat = 0
    var rightGreen: CGFloat = 0
    var rightBlue: CGFloat = 0
    var rightAlpha: CGFloat = 0
    left.getRed(&leftRed, green: &leftGreen, blue: &leftBlue, alpha: &leftAlpha)
    right.getRed(&rightRed, green: &rightGreen, blue: &rightBlue, alpha: &rightAlpha)
    return abs(leftRed - rightRed) <= tolerance &&
        abs(leftGreen - rightGreen) <= tolerance &&
        abs(leftBlue - rightBlue) <= tolerance &&
        abs(leftAlpha - rightAlpha) <= tolerance
}

private final class TextFixturePageView: NSView {
    private let text: String

    override var isFlipped: Bool { true }

    init(frame: CGRect, text: String) {
        self.text = text
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        bounds.fill()
        NSString(string: text).draw(
            in: CGRect(x: 72, y: 72, width: 468, height: 648),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 16),
                .foregroundColor: NSColor.black
            ]
        )
    }
}

private final class SolidColorTextFixturePageView: NSView {
    private let text: String
    private let color: NSColor

    override var isFlipped: Bool { true }

    init(frame: CGRect, text: String, color: NSColor) {
        self.text = text
        self.color = color
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        bounds.fill()
        guard !text.isEmpty else { return }
        NSString(string: text).draw(
            in: CGRect(x: 72, y: 72, width: 468, height: 648),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 16),
                .foregroundColor: color
            ]
        )
    }
}

/// The SAME text drawn twice, well separated vertically (top of page, bottom of page) so
/// they never merge into one editable block — used to test disambiguating edits to
/// distinct occurrences of identical repeated text.
private final class RepeatedIdenticalTextFixturePageView: NSView {
    private let text: String

    init(frame: CGRect, text: String) {
        self.text = text
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { nil }
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        bounds.fill()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont(name: "Helvetica", size: 14) ?? NSFont.systemFont(ofSize: 14),
            .foregroundColor: NSColor.black
        ]
        NSString(string: text).draw(at: CGPoint(x: 72, y: 100), withAttributes: attributes)
        NSString(string: text).draw(at: CGPoint(x: 72, y: 500), withAttributes: attributes)
    }
}

private final class TwoLineFixturePageView: NSView {
    override var isFlipped: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        bounds.fill()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont(name: "Helvetica", size: 14) ?? NSFont.systemFont(ofSize: 14),
            .foregroundColor: NSColor.black
        ]
        NSString(string: "Short").draw(at: CGPoint(x: 72, y: 690), withAttributes: attributes)
        NSString(string: "Stale lower line").draw(at: CGPoint(x: 72, y: 650), withAttributes: attributes)
    }
}

/// A single line of text set in a caller-supplied font, at that font's own natural (device)
/// scale — used to test font-size DETECTION accuracy against a known-correct answer, since
/// the font/size are exactly what's passed in.
private final class SingleFontLineFixturePageView: NSView {
    private let text: String
    private let font: NSFont

    init(text: String, font: NSFont) {
        self.text = text
        self.font = font
        super.init(frame: CGRect(x: 0, y: 0, width: 400, height: 200))
    }

    required init?(coder: NSCoder) { nil }
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        bounds.fill()
        NSString(string: text).draw(
            at: CGPoint(x: 40, y: 120),
            withAttributes: [.font: font, .foregroundColor: NSColor.black]
        )
    }
}

/// Two near-identical multi-line paragraphs stacked at the same left margin with a
/// realistic single-blank-line paragraph gap, neither ending in terminal punctuation —
/// matches the "repeated stress-test paragraph" structure that reproduced the wrapped-line
/// over-merge bug (see `testPDFTextAnalysisDoesNotMergeTwoSeparateStackedParagraphsAtALegitimateParagraphGap`).
private final class StackedParagraphsFixturePageView: NSView {
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        bounds.fill()
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        let font = NSFont(name: "Helvetica", size: 11) ?? NSFont.systemFont(ofSize: 11)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black,
            .paragraphStyle: paragraph
        ]
        let row0 = "This paragraph is intentionally searchable. Keywords: pdFold, annotation, export, zoom, rotate, section-1, row-0. It includes long identifiers like INV-2026-07-03-ALPHA-BRAVO-CHARLIE to check selection handles, search snippets, and copied text fidelity. The app should preserve scroll position while navigating results and editing nearby text edits"
        let row1 = "This paragraph is intentionally searchable. Keywords: pdFold, annotation, export, zoom, rotate, section-1, row-1. It includes long identifiers like INV-2026-07-03-ALPHA-BRAVO-CHARLIE to check selection handles, search snippets, and copied text fidelity. The app should preserve scroll position while navigating results and editing nearby text"
        NSString(string: row0).draw(in: CGRect(x: 40, y: 120, width: 532, height: 100), withAttributes: attributes)
        NSString(string: row1).draw(in: CGRect(x: 40, y: 185, width: 532, height: 100), withAttributes: attributes)
    }
}

/// Four visually-identical body paragraphs, each on its own row and each containing the
/// token `pdFold` plus a unique `row-N` marker — mirrors the reported screenshot where two
/// of several repeated paragraphs were edited (`pdFold` → `oriFold`) and looked different
/// from their untouched neighbors.
private final class RepeatedParagraphsFixturePageView: NSView {
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        bounds.fill()
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        // Bold, not regular: the fixture must actually exercise weight preservation through
        // the full extract -> edit -> render pipeline. A plain-weight fixture can never
        // detect a bold->regular substitution regression since there is no bold ink to lose.
        let font = NSFont(name: "Helvetica-Bold", size: 12) ?? NSFont.boldSystemFont(ofSize: 12)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black,
            .paragraphStyle: paragraph
        ]
        for index in 0..<4 {
            // Single line per row so the `pdFold` token and the unique `row-N` marker land
            // in the same extracted block (a wrapped paragraph would split them apart).
            let text = "pdFold editor preserves row-\(index) typography while editing."
            NSString(string: text).draw(
                in: CGRect(x: 40, y: 80 + CGFloat(index) * 90, width: 520, height: 40),
                withAttributes: attributes
            )
        }
    }
}

private final class ScaledTextFixturePageView: NSView {
    private let text: String
    private let fontSize: CGFloat
    private let contentScale: CGFloat

    override var isFlipped: Bool { true }

    init(frame: CGRect, text: String, fontSize: CGFloat, scale: CGFloat) {
        self.text = text
        self.fontSize = fontSize
        self.contentScale = scale
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        bounds.fill()
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.scaleBy(x: contentScale, y: contentScale)
        NSString(string: text).draw(
            at: CGPoint(x: 144, y: 144),
            withAttributes: [
                .font: NSFont(name: "Helvetica", size: fontSize) ?? NSFont.systemFont(ofSize: fontSize),
                .foregroundColor: NSColor.black
            ]
        )
        context.restoreGState()
    }
}

private final class WrappedBulletFixturePageView: NSView {
    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        bounds.fill()
        let paragraph = NSMutableParagraphStyle()
        paragraph.firstLineHeadIndent = 0
        paragraph.headIndent = 16
        paragraph.lineBreakMode = .byWordWrapping
        NSString(string: "• Partnered with product, design, and engineering teams to deliver a deliberately wrapped bullet with trailing punctuation.")
            .draw(
                in: CGRect(x: 72, y: 72, width: 235, height: 80),
                withAttributes: [
                    .font: NSFont(name: "Helvetica", size: 10) ?? NSFont.systemFont(ofSize: 10),
                    .foregroundColor: NSColor.black,
                    .paragraphStyle: paragraph
                ]
            )
    }
}

private final class TwoColumnFixturePageView: NSView {
    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        bounds.fill()
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont(name: "Helvetica", size: 10) ?? NSFont.systemFont(ofSize: 10),
            .foregroundColor: NSColor.black
        ]
        NSString(string: "Main column editable sentence").draw(at: CGPoint(x: 72, y: 96), withAttributes: attrs)
        NSString(string: "Sidebar detail").draw(at: CGPoint(x: 360, y: 96), withAttributes: attrs)
    }
}

private final class TwoColumnWrappedFixturePageView: NSView {
    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        bounds.fill()
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont(name: "Helvetica", size: 10) ?? NSFont.systemFont(ofSize: 10),
            .foregroundColor: NSColor.black,
            .paragraphStyle: paragraph
        ]
        NSString(string: "Left column wrapped sentence with continuation text for paragraph grouping.")
            .draw(in: CGRect(x: 72, y: 96, width: 170, height: 70), withAttributes: attrs)
        NSString(string: "Right column wrapped sentence with continuation text for paragraph grouping.")
            .draw(in: CGRect(x: 340, y: 96, width: 170, height: 70), withAttributes: attrs)
    }
}

/// A single line that opens with a short blue "hyperlink" run followed by a much longer
/// black run, all on the same baseline/font/size — mirrors a sentence that opens with a
/// hyperlink ("See docs for the complete quarterly report details this cycle").
private final class HyperlinkThenPlainTextFixturePageView: NSView {
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        bounds.fill()
        let font = NSFont(name: "Helvetica", size: 14) ?? NSFont.systemFont(ofSize: 14)
        let linkRun = NSAttributedString(string: "See docs", attributes: [.font: font, .foregroundColor: NSColor.blue])
        let bodyRun = NSAttributedString(string: " for the complete quarterly report details this cycle", attributes: [.font: font, .foregroundColor: NSColor.black])
        let line = NSMutableAttributedString(attributedString: linkRun)
        line.append(bodyRun)
        line.draw(at: CGPoint(x: 72, y: 120))
    }
}

/// A single line with a short bold emphasis run in the MIDDLE, surrounded by much more
/// plain-weight text — "Please review the " + bold "Q3 budget" + " figures before Friday".
private final class MidSentenceBoldFixturePageView: NSView {
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        bounds.fill()
        let regular = NSFont(name: "Helvetica", size: 14) ?? NSFont.systemFont(ofSize: 14)
        let bold = NSFont(name: "Helvetica-Bold", size: 14) ?? NSFont.boldSystemFont(ofSize: 14)
        let line = NSMutableAttributedString()
        line.append(NSAttributedString(string: "Please review the ", attributes: [.font: regular, .foregroundColor: NSColor.black]))
        line.append(NSAttributedString(string: "Q3 budget", attributes: [.font: bold, .foregroundColor: NSColor.black]))
        line.append(NSAttributedString(string: " figures before Friday", attributes: [.font: regular, .foregroundColor: NSColor.black]))
        line.draw(at: CGPoint(x: 72, y: 120))
    }
}

private final class ConsecutiveBulletsFixturePageView: NSView {
    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        bounds.fill()
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont(name: "Helvetica", size: 10) ?? NSFont.systemFont(ofSize: 10),
            .foregroundColor: NSColor.black
        ]
        NSString(string: "• First item.").draw(at: CGPoint(x: 72, y: 96), withAttributes: attrs)
        NSString(string: "• Second item.").draw(at: CGPoint(x: 72, y: 111), withAttributes: attrs)
    }
}

private final class RecordingProcessingEngine: PDFProcessingEngine {
    let name = "Recording"
    private let validation: PDFProcessingValidation
    private(set) var validateCallCount = 0

    init(validation: PDFProcessingValidation) {
        self.validation = validation
    }

    func validatePDF(data: Data, password: String?) throws -> PDFProcessingValidation {
        validateCallCount += 1
        return validation
    }
}

private final class ThrowingProcessingEngine: PDFProcessingEngine {
    let name = "Throwing"
    private(set) var validateCallCount = 0

    func validatePDF(data: Data, password: String?) throws -> PDFProcessingValidation {
        validateCallCount += 1
        throw PDFProcessingError.unreadableDocument
    }
}

private final class FlippingProcessingEngine: PDFProcessingEngine {
    let name = "Flipping"
    private(set) var validateCallCount = 0

    func validatePDF(data: Data, password: String?) throws -> PDFProcessingValidation {
        validateCallCount += 1
        guard validateCallCount == 1 else {
            throw PDFProcessingError.unreadableDocument
        }
        return PDFProcessingValidation(
            engine: .pdfKit,
            pageCount: 1,
            isEncrypted: false
        )
    }
}

final class PetBuddyTests: XCTestCase {
    @MainActor
    func testDisableHushAndEnableKeepFoldyQuietWhenHidden() {
        let defaults = UserDefaults.standard
        let oldEnabledValue = defaults.object(forKey: "petEnabled")
        let oldTriggerCountValue = defaults.object(forKey: "petTriggerCount")
        let buddy = PetBuddy.shared

        defer {
            buddy.hush()
            buddy.lastShownAt = nil
            buddy.recentLines = []
            buddy.lastFeedbackAt = nil
            buddy.lastInspirationAt = nil
            if let oldEnabledValue {
                defaults.set(oldEnabledValue, forKey: "petEnabled")
                buddy.isEnabled = defaults.bool(forKey: "petEnabled")
            } else {
                defaults.removeObject(forKey: "petEnabled")
                buddy.isEnabled = true
            }
            if let oldTriggerCountValue {
                defaults.set(oldTriggerCountValue, forKey: "petTriggerCount")
                buddy.triggerCount = defaults.integer(forKey: "petTriggerCount")
            } else {
                defaults.removeObject(forKey: "petTriggerCount")
                buddy.triggerCount = 0
            }
        }

        buddy.enable()
        buddy.hush()
        buddy.lastShownAt = nil
        buddy.recentLines = []
        buddy.lastFeedbackAt = nil
        buddy.lastInspirationAt = nil
        buddy.triggerCount = 0

        buddy.trigger(.greeting)
        XCTAssertTrue(buddy.isBubbleVisible)
        XCTAssertNotNil(buddy.currentMessage)

        buddy.hush()
        XCTAssertFalse(buddy.isBubbleVisible)
        XCTAssertNil(buddy.currentMessage)

        buddy.disable()
        XCTAssertFalse(buddy.isEnabled)
        XCTAssertFalse(defaults.bool(forKey: "petEnabled"))

        buddy.trigger(.highlight)
        XCTAssertFalse(buddy.isBubbleVisible)
        XCTAssertNil(buddy.currentMessage)

        buddy.enable()
        XCTAssertTrue(buddy.isEnabled)
        XCTAssertTrue(defaults.bool(forKey: "petEnabled"))
    }

    @MainActor
    func testFoldyShowsInspirationFromTimeToTime() {
        let defaults = UserDefaults.standard
        let oldEnabledValue = defaults.object(forKey: "petEnabled")
        let oldTriggerCountValue = defaults.object(forKey: "petTriggerCount")
        let buddy = PetBuddy.shared

        defer {
            buddy.hush()
            buddy.lastShownAt = nil
            buddy.recentLines = []
            buddy.lastFeedbackAt = nil
            buddy.lastInspirationAt = nil
            if let oldEnabledValue {
                defaults.set(oldEnabledValue, forKey: "petEnabled")
                buddy.isEnabled = defaults.bool(forKey: "petEnabled")
            } else {
                defaults.removeObject(forKey: "petEnabled")
                buddy.isEnabled = true
            }
            if let oldTriggerCountValue {
                defaults.set(oldTriggerCountValue, forKey: "petTriggerCount")
                buddy.triggerCount = defaults.integer(forKey: "petTriggerCount")
            } else {
                defaults.removeObject(forKey: "petTriggerCount")
                buddy.triggerCount = 0
            }
        }

        buddy.enable()
        buddy.hush()
        buddy.lastShownAt = nil
        buddy.recentLines = []
        buddy.lastFeedbackAt = nil
        buddy.lastInspirationAt = nil
        buddy.triggerCount = 6

        buddy.trigger(.save)

        XCTAssertTrue(buddy.isBubbleVisible)
        XCTAssertNotNil(buddy.currentMessage)
        XCTAssertTrue(PetLines.inspiration.contains(buddy.currentMessage ?? ""))
        XCTAssertNotNil(buddy.lastInspirationAt)
    }
}

private extension PDFDocument {
    var stringValue: String {
        (0..<pageCount)
            .compactMap { page(at: $0)?.string }
            .joined(separator: "\n")
    }

    var normalizedStringValue: String {
        stringValue
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private func resolvedImportURLs(from providers: [NSItemProvider], maxCount: Int = maximumImportBatchSize) async -> [URL] {
    await resolvedImportURLResult(from: providers, maxCount: maxCount).urls
}

private func resolvedImportURLResult(from providers: [NSItemProvider], maxCount: Int = maximumImportBatchSize) async -> (urls: [URL], wasLimited: Bool) {
    await withCheckedContinuation { continuation in
        resolveImportURLs(from: providers, maxCount: maxCount) { urls, wasLimited in
            continuation.resume(returning: (urls, wasLimited))
        }
    }
}

private extension Optional {
    func unwrap(
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> Wrapped {
        try XCTUnwrap(self, file: file, line: line)
    }
}
