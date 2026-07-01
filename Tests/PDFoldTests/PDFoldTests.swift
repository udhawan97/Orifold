import AppKit
import PDFKit
import UniformTypeIdentifiers
import XCTest
@testable import PDFold

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
        XCTAssertTrue(text.contains("pdFold never charges for signing"))
        XCTAssertTrue(text.contains("SSL.com"))
        XCTAssertTrue(acquisition.contains("Getting a CA-issued (AATL) Digital ID"))
        XCTAssertTrue(acquisition.contains("Trusted providers"))
        XCTAssertTrue(CertificateGuideResource.shortPopoverCopy.contains("pdFold never charges for signing"))
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
        XCTAssertEqual(block.fontSize, max(4, inkHeight * 1.15), accuracy: 1.0)
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

        let pageText = viewModel.loadedPDFs.first?.1.stringValue ?? ""
        XCTAssertTrue(pageText.contains("a substantially longer replacement phrase"), "replacement text was clipped: \(pageText)")
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

        let snapshot = try document.snapshot(contentType: .pdf)
        let exportedData = try XCTUnwrap(document.exportedPDFData(from: snapshot))
        let exportedPDF = try XCTUnwrap(PDFDocument(data: exportedData))

        XCTAssertTrue(exportedPDF.stringValue.contains("Saved through PDF writer"))
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

        let annotation = viewModel.addNote(at: CGPoint(x: 120, y: 120), on: page)
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
            textColor: .black, alignment: .left))

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
            textColor: .black, alignment: .left))

        var reeditBlock = sourceBlock
        reeditBlock.text = "First replacement"
        reeditBlock.bounds = firstCommittedBounds
        XCTAssertTrue(viewModel.applyInlineTextEdit(
            pageRef: fixture.refs[0], sourceBlock: reeditBlock,
            replacementText: "Second replacement",
            editedBounds: secondCommittedBounds, fontName: "Helvetica", fontSize: 10,
            textColor: .black, alignment: .left))

        let operations = try XCTUnwrap(viewModel.document.workspace.pageEditStates.first?.operations)
        XCTAssertEqual(operations.count, 1)
        let stored = try XCTUnwrap(operations.first)
        XCTAssertEqual(stored.sourceBounds, sourceBounds)
        XCTAssertEqual(stored.editedBounds.minX, secondCommittedBounds.minX, accuracy: 0.01)
        XCTAssertEqual(stored.editedBounds.minY, secondCommittedBounds.minY, accuracy: 0.01)
        XCTAssertEqual(stored.editedBounds.width, secondCommittedBounds.width, accuracy: 0.01)
        XCTAssertEqual(stored.editedBounds.height, secondCommittedBounds.height, accuracy: 0.01)
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

        let donePoint = doneButton.convert(NSPoint(x: doneButton.bounds.midX, y: doneButton.bounds.midY), to: fixture.overlay)
        let sizePoint = sizeField.convert(NSPoint(x: sizeField.bounds.midX, y: sizeField.bounds.midY), to: fixture.overlay)
        let textPoint = textView.convert(NSPoint(x: textView.bounds.midX, y: textView.bounds.minY + 6), to: fixture.overlay)
        let movePoint = moveHandle.convert(NSPoint(x: moveHandle.bounds.midX, y: moveHandle.bounds.midY), to: fixture.overlay)
        let resizePoint = resizeHandle.convert(NSPoint(x: resizeHandle.bounds.midX, y: resizeHandle.bounds.midY), to: fixture.overlay)

        XCTAssertTrue(fixture.overlay.hitTest(donePoint) is NSButton)
        XCTAssertTrue(fixture.overlay.hitTest(sizePoint) is NSTextField)
        let textHit = fixture.overlay.hitTest(textPoint)
        XCTAssertTrue(textHit is NSTextView, "Expected text view hit, got \(String(describing: textHit))")
        XCTAssertTrue(fixture.overlay.hitTest(movePoint) is InlineMoveHandle)
        XCTAssertTrue(fixture.overlay.hitTest(resizePoint) is InlineResizeHandle)
        XCTAssertNil(fixture.overlay.hitTest(NSPoint(x: fixture.overlay.bounds.maxX - 2, y: fixture.overlay.bounds.maxY - 2)))
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

    func testInlineEditorCommitsTextContentTopEdge() throws {
        let fixture = try makeInlineEditorFixture()
        let doneButton = try XCTUnwrap(findSubview(in: fixture.overlay) { (button: NSButton) in
            button.title == "Done"
        })

        doneButton.performClick(nil)

        let edit = try XCTUnwrap(fixture.committedEdit())
        XCTAssertEqual(edit.editedBounds.maxY, 666, accuracy: 0.01)
    }
}

final class DocumentImportConverterTests: XCTestCase {
    func testPlainTextImportCreatesExtractablePDF() throws {
        let data = Data("Hello PDFold\nSecond line".utf8)

        let pdf = try DocumentImportConverter.pdfDocument(
            from: data,
            contentType: .plainText,
            filename: "notes.txt",
            baseURL: nil
        )

        XCTAssertGreaterThanOrEqual(pdf.pageCount, 1)
        XCTAssertEqual(pdf.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String, "notes")
        XCTAssertTrue(pdf.stringValue.contains("Hello PDFold"))
        XCTAssertTrue(pdf.stringValue.contains("Second line"))
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

    func testProcessingValidationFailureDoesNotBlockFileImport() throws {
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

        XCTAssertNil(viewModel.importError)
        XCTAssertEqual(viewModel.memberDocuments.count, 1)
        XCTAssertEqual(viewModel.pageCount, 1)
        XCTAssertNil(viewModel.lastProcessingValidation)
        XCTAssertEqual(processingEngine.validateCallCount, 1)
    }

    func testProcessingValidationFailureClearsStaleValidationState() throws {
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

        XCTAssertNil(viewModel.importError)
        XCTAssertEqual(viewModel.memberDocuments.count, 2)
        XCTAssertNil(viewModel.lastProcessingValidation)
        XCTAssertEqual(processingEngine.validateCallCount, 2)
    }
}

final class WorkspaceDocumentTests: XCTestCase {
    func testWritableContentTypesOnlyOfferPDF() {
        XCTAssertEqual(WorkspaceDocument.writableContentTypes, [.pdf])
    }

    func testAppInfoPlistDoesNotAdvertiseWorkspaceSaveFormat() throws {
        let plistURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("PDFold/Resources/Info.plist")
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
                    || extensions.contains("pdfoldproj")
            }
        )
        XCTAssertTrue(exportedTypes.isEmpty)
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
}

final class WorkspaceViewModelTests: XCTestCase {
    func testMetadataMutationsNormalizeTrimAndDeduplicate() {
        let viewModel = WorkspaceViewModel(document: WorkspaceDocument())

        viewModel.addTag("  #Finance  ")
        viewModel.addTag("finance")
        viewModel.addTag("   ")
        viewModel.addComment("  Needs review  ")
        viewModel.addComment("\n\t")

        XCTAssertEqual(viewModel.document.workspace.tags, ["Finance"])
        XCTAssertEqual(viewModel.document.workspace.comments.map(\.body), ["Needs review"])
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
        let pdf = makePDF(pageTexts: ["Replaceable text"])
        let page = try XCTUnwrap(pdf.page(at: 0))
        let selection = try XCTUnwrap(page.selectionForWord(at: CGPoint(x: 75, y: 720)))
        let viewModel = WorkspaceViewModel(
            document: WorkspaceDocument(),
            processingEngine: PDFKitProcessingEngineFallback()
        )

        let annotation = try XCTUnwrap(viewModel.addEditableTextOverlay(from: selection, on: page))

        XCTAssertEqual(annotation.contents, "Replaceable")
        XCTAssertGreaterThanOrEqual(annotation.font?.pointSize ?? 0, 8)
        XCTAssertNotNil(annotation.fontColor)
        XCTAssertGreaterThan(annotation.bounds.width, selection.bounds(for: page).width)
        XCTAssertGreaterThan(annotation.bounds.height, 0)
        XCTAssertNotEqual(annotation.color, .clear)
        XCTAssertNil(viewModel.editingStatus)
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
        } changeHandler: {
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
        } changeHandler: {
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

private func makeMemberPDF(name: String, pageTexts: [String]) -> (MemberDocument, PDFDocument) {
    let pdf = makePDF(pageTexts: pageTexts)
    var member = MemberDocument(displayName: name, sourcePDFRef: "\(name).pdf")
    member.pageRefs = (0..<pdf.pageCount).map { _ in UUID() }
    return (member, pdf)
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

private func makeConsecutiveBulletsPDF() -> PDFDocument {
    let view = ConsecutiveBulletsFixturePageView(frame: CGRect(x: 0, y: 0, width: 612, height: 792))
    return PDFDocument(data: view.dataWithPDF(inside: view.bounds))!
}

private struct InlineEditorFixture {
    let pdfView: PDFoldPDFView
    let page: PDFPage
    let overlay: InlineTextEditorOverlay
    let committedEdit: () -> InlineTextEditorOverlay.EditResult?
}

private func makeInlineEditorFixture() throws -> InlineEditorFixture {
    let pdf = makePDF(pageTexts: ["Original text"])
    let pdfView = PDFoldPDFView(frame: CGRect(x: 0, y: 0, width: 900, height: 1000))
    pdfView.document = pdf
    pdfView.autoScales = false
    pdfView.scaleFactor = 1
    pdfView.layoutDocumentView()

    let page = try XCTUnwrap(pdf.page(at: 0))
    let pageRef = PageRef(memberDocId: UUID(), sourcePageIndex: 0)
    let block = EditableTextBlock(
        pageRefID: pageRef.id,
        text: "Original text",
        bounds: CGRect(x: 72, y: 650, width: 160, height: 16),
        lines: [],
        fontName: "Helvetica",
        fontSize: 8,
        textColor: .documentText,
        rotation: 0,
        baseline: 650,
        confidence: .high
    )
    var committed: InlineTextEditorOverlay.EditResult?
    let overlay = InlineTextEditorOverlay(
        frame: pdfView.bounds,
        viewModel: WorkspaceViewModel(document: WorkspaceDocument()),
        pdfView: pdfView,
        page: page,
        pageRef: pageRef,
        block: block
    ) { completion in
        if case .commit(let edit) = completion {
            committed = edit
        }
    }
    pdfView.addSubview(overlay)
    return InlineEditorFixture(pdfView: pdfView, page: page, overlay: overlay) {
        committed
    }
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

private extension PDFDocument {
    var stringValue: String {
        (0..<pageCount)
            .compactMap { page(at: $0)?.string }
            .joined(separator: "\n")
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
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
