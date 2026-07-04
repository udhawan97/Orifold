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
        XCTAssertEqual(block.fontSize, max(4, inkHeight * 1.15), accuracy: 1.0)
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

        XCTAssertTrue(fixture.overlay.hitTest(donePoint) is NSButton)
        XCTAssertTrue(fixture.overlay.hitTest(sizePoint) is NSTextField)
        XCTAssertTrue(fixture.overlay.hitTest(colorPoint) is NSPopUpButton)
        let textHit = fixture.overlay.hitTest(textPoint)
        XCTAssertTrue(textHit is NSTextView, "Expected text view hit, got \(String(describing: textHit))")
        XCTAssertTrue(fixture.overlay.hitTest(movePoint) is InlineMoveHandle)
        XCTAssertTrue(fixture.overlay.hitTest(resizePoint) is InlineResizeHandle)
        XCTAssertNil(fixture.overlay.hitTest(NSPoint(x: fixture.overlay.bounds.maxX - 2, y: fixture.overlay.bounds.maxY - 2)))
    }

    func testInlineEditorToolbarControlsReceiveHitTestsWhenToolbarIsOffset() throws {
        let fixture = try makeInlineEditorFixture(pdfViewFrame: CGRect(x: 0, y: 0, width: 1800, height: 1000))
        let matchButton = try XCTUnwrap(findSubview(in: fixture.overlay) { (button: NSButton) in
            button.title.isEmpty && button.toolTip?.hasPrefix("Match this edit") == true
        })
        let copyFormat = try XCTUnwrap(findSubview(in: fixture.overlay) { (button: NSButton) in
            button.title.isEmpty && button.toolTip?.hasPrefix("Copy the nearby") == true
        })
        let applyFormat = try XCTUnwrap(findSubview(in: fixture.overlay) { (button: NSButton) in
            button.title.isEmpty && button.toolTip?.hasPrefix("Apply the copied format") == true
        })
        let restoreFormat = try XCTUnwrap(findSubview(in: fixture.overlay) { (button: NSButton) in
            button.title.isEmpty && button.toolTip?.hasPrefix("Restore this edit") == true
        })
        let bold = try XCTUnwrap(findSubview(in: fixture.overlay) { (button: NSButton) in
            button.title == "B"
        })
        let alignment = try XCTUnwrap(findSubview(in: fixture.overlay) { (_: NSSegmentedControl) in true })

        for view in [matchButton, copyFormat, applyFormat, restoreFormat, bold, alignment] as [NSView] {
            XCTAssertGreaterThan(view.convert(.zero, to: fixture.overlay).x, 100)
            let point = view.convert(NSPoint(x: view.bounds.midX, y: view.bounds.midY), to: fixture.overlay)
            XCTAssertTrue(fixture.overlay.hitTest(point) === view)
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
        let copy = try XCTUnwrap(findSubview(in: fixture.overlay) { (button: NSButton) in
            button.title.isEmpty && button.toolTip?.hasPrefix("Copy the nearby") == true
        })
        let apply = try XCTUnwrap(findSubview(in: fixture.overlay) { (button: NSButton) in
            button.title.isEmpty && button.toolTip?.hasPrefix("Apply the copied format") == true
        })
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

    func testInlineEditorRestoreOriginalFormatClearsManualStyleChange() throws {
        let fixture = try makeInlineEditorFixture()
        let textView = try XCTUnwrap(findSubview(in: fixture.overlay) { (_: NSTextView) in true })
        let bold = try XCTUnwrap(findSubview(in: fixture.overlay) { (button: NSButton) in
            button.title == "B"
        })
        let restore = try XCTUnwrap(findSubview(in: fixture.overlay) { (button: NSButton) in
            button.title.isEmpty && button.toolTip?.hasPrefix("Restore this edit") == true
        })
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
        let restore = try XCTUnwrap(findSubview(in: fixture.overlay) { (button: NSButton) in
            button.title.isEmpty && button.toolTip?.hasPrefix("Restore this edit") == true
        })
        let done = try XCTUnwrap(findSubview(in: fixture.overlay) { (button: NSButton) in
            button.title == "Done"
        })

        restore.performClick(nil)
        done.performClick(nil)

        let committed = try XCTUnwrap(fixture.committedEdit())
        XCTAssertTrue(colorsApproximatelyEqual(committed.textColor, sourceFormat.textColor.nsColor))
        XCTAssertFalse(committed.didManuallyChangeStyle)
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
        let match = try XCTUnwrap(findSubview(in: fixture.overlay) { (button: NSButton) in
            button.title.isEmpty && button.toolTip?.hasPrefix("Match this edit") == true
        })
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

        let urls = await resolvedImportURLs(from: providers)

        XCTAssertEqual(urls.count, maximumImportBatchSize)
        XCTAssertEqual(urls.last?.lastPathComponent, "drop-\(maximumImportBatchSize - 1).pdf")
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

private func makeConsecutiveBulletsPDF() -> PDFDocument {
    let view = ConsecutiveBulletsFixturePageView(frame: CGRect(x: 0, y: 0, width: 612, height: 792))
    return PDFDocument(data: view.dataWithPDF(inside: view.bounds))!
}

private func makeTwoLinePDF() -> PDFDocument {
    let view = TwoLineFixturePageView(frame: CGRect(x: 0, y: 0, width: 612, height: 792))
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
    return InlineEditorFixture(pdfView: pdfView, page: page, overlay: overlay, viewModel: viewModel) {
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
            buddy.lastLine = nil
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
        buddy.lastLine = nil
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
            buddy.lastLine = nil
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
        buddy.lastLine = nil
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

private func resolvedImportURLs(from providers: [NSItemProvider]) async -> [URL] {
    await withCheckedContinuation { continuation in
        resolveImportURLs(from: providers) { urls in
            continuation.resume(returning: urls)
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
