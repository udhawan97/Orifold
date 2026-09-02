import AppKit
import CoreGraphics
import CoreText
import PDFKit
import Vision
import XCTest
@testable import Orifold

@MainActor
final class ScanCleanupTests: XCTestCase {
    private var retainedUndoManager: UndoManager?

    func testBinarizeProducesOnlyBlackAndWhitePixels() throws {
        let source = try grayscaleGradient(width: 96, height: 48)

        let output = ScanCleanup.binarize(source)
        let samples = try grayscaleSamples(in: output)

        XCTAssertFalse(samples.isEmpty)
        XCTAssertTrue(samples.allSatisfy { $0 == 0 || $0 == 255 })
        XCTAssertTrue(samples.contains(0))
        XCTAssertTrue(samples.contains(255))
    }

    func testDespeckleRemovesAnIsolatedBlackPixelWithoutErasingAStroke() throws {
        var pixels = [UInt8](repeating: 255, count: 9 * 9 * 4)
        for index in stride(from: 3, to: pixels.count, by: 4) { pixels[index] = 255 }
        setGray(0, x: 1, y: 1, width: 9, pixels: &pixels)
        for y in 2...6 { setGray(0, x: 5, y: y, width: 9, pixels: &pixels) }
        let source = try makeImage(pixels: &pixels, width: 9, height: 9)

        let output = ScanCleanup.despeckle(source)
        let samples = try grayscaleSamples(in: output)

        XCTAssertEqual(samples[1 * 9 + 1], 255)
        XCTAssertEqual(samples[4 * 9 + 5], 0)
    }

    func testDeskewStraightensAndCropsAPhotographedPage() throws {
        let source = try photographedPage(angleDegrees: 7)

        let output = ScanCleanup.clean(
            source,
            options: ScanCleanupOptions(deskew: true, binarize: false, despeckle: false)
        )

        XCTAssertLessThan(abs(darkBorderSlope(in: output)), 0.03)
        XCTAssertEqual(Double(output.width) / Double(output.height), 500.0 / 360.0, accuracy: 0.12)
        XCTAssertLessThan(output.width, source.width)
        XCTAssertLessThan(output.height, source.height)
    }

    func testCleanupQualitySpikeDoesNotReduceVisionConfidence() throws {
        let source = try photographedPage(angleDegrees: 7)
        let before = try visionRecognition(in: source)

        let cleaned = ScanCleanup.clean(source, options: ScanCleanupOptions())
        let after = try visionRecognition(in: cleaned)

        XCTAssertTrue(after.text.localizedCaseInsensitiveContains("ORIFOLD RECEIPT 7429"))
        XCTAssertGreaterThanOrEqual(after.averageConfidence + 0.001, before.averageConfidence)
    }

    func testPipelineRasterizesAndCleansAPDFPage() throws {
        let image = try photographedPage(angleDegrees: 7)
        let document = PDFDocument()
        document.insert(try XCTUnwrap(PDFPage(image: NSImage(cgImage: image, size: .zero))), at: 0)
        let page = try XCTUnwrap(document.page(at: 0))

        let cleaned = try XCTUnwrap(
            ScanCleanupPipeline.cleanedImage(for: page, options: ScanCleanupOptions())
        )

        let recognized = try visionRecognition(in: cleaned)
        XCTAssertTrue(recognized.text.localizedCaseInsensitiveContains("ORIFOLD RECEIPT 7429"))
        XCTAssertLessThan(cleaned.width, try XCTUnwrap(PDFOCRService.rasterizedImage(for: page)).width)
    }

    func testPreviewCleansAtProductionResolutionBeforeDownsamplingForDisplay() throws {
        let image = try photographedPage(angleDegrees: 7)
        let document = PDFDocument()
        document.insert(try XCTUnwrap(PDFPage(image: NSImage(cgImage: image, size: .zero))), at: 0)
        let page = try XCTUnwrap(document.page(at: 0))
        let options = ScanCleanupOptions()
        let productionBefore = try XCTUnwrap(PDFOCRService.rasterizedImage(for: page))
        let productionAfter = ScanCleanup.clean(productionBefore, options: options)

        let preview = try XCTUnwrap(ScanCleanupPipeline.previewImages(
            for: page,
            options: options,
            displayLongEdgePixels: 1_200
        ))
        let expectedBefore = try resizedForComparison(
            productionBefore,
            width: preview.before.width,
            height: preview.before.height
        )
        let expectedAfter = try resizedForComparison(
            productionAfter,
            width: preview.after.width,
            height: preview.after.height
        )

        XCTAssertEqual(max(preview.before.width, preview.before.height), 1_200)
        XCTAssertEqual(max(preview.after.width, preview.after.height), 1_200)
        XCTAssertGreaterThan(max(productionBefore.width, productionBefore.height), 1_200)
        XCTAssertGreaterThan(max(productionAfter.width, productionAfter.height), 1_200)
        XCTAssertLessThan(try pixelDifference(preview.before, expectedBefore), 0.000_1)
        XCTAssertLessThan(try pixelDifference(preview.after, expectedAfter), 0.000_1)
    }

    func testPreviewCooperativelyCancelsAfterProductionRenderBeforeCleanup() throws {
        let image = try photographedPage(angleDegrees: 4)
        let document = PDFDocument()
        document.insert(try XCTUnwrap(PDFPage(image: NSImage(cgImage: image, size: .zero))), at: 0)
        let page = try XCTUnwrap(document.page(at: 0))
        let cancellation = ScanCleanupCancellationProbe(cancelOnCheck: 2)

        let preview = ScanCleanupPipeline.previewImages(
            for: page,
            options: ScanCleanupOptions(),
            displayLongEdgePixels: 320,
            isCancelled: { cancellation.shouldCancel() }
        )

        XCTAssertNil(preview)
        XCTAssertEqual(cancellation.checkCount, 2)
    }

    func testReplacingPageContentPreservesMemberStructureAndOtherPages() throws {
        let source = PDFDocument()
        source.insert(
            try XCTUnwrap(PDFPage(image: NSImage(cgImage: photographedPage(angleDegrees: 7), size: .zero))),
            at: 0
        )
        source.insert(
            try XCTUnwrap(PDFPage(image: NSImage(cgImage: grayscaleGradient(width: 320, height: 220), size: .zero))),
            at: 1
        )
        let note = PDFAnnotation(
            bounds: CGRect(x: 20, y: 20, width: 24, height: 24),
            forType: .text,
            withProperties: nil
        )
        note.contents = "Keep this review note"
        source.page(at: 0)?.addAnnotation(note)
        let sourceData = try XCTUnwrap(PDFSerializer.data(from: source))
        let attachment = Data("scan-cleanup-structure-proof".utf8)
        let withAttachment = try AttachmentsService.add(
            attachment,
            name: "proof.txt",
            mimeType: "text/plain",
            to: sourceData
        )
        let untouchedBefore = try XCTUnwrap(PDFOCRService.rasterizedImage(for: XCTUnwrap(source.page(at: 1)), dpi: 72))

        let output = try ScanCleanupPipeline.replacingPageContents(
            in: withAttachment,
            pageIndices: [0],
            options: ScanCleanupOptions()
        )

        XCTAssertTrue(QPDFService.isStructurallySound(output))
        XCTAssertEqual(try AttachmentsService.extract("proof.txt", from: output), attachment)
        let reopened = try XCTUnwrap(PDFDocument(data: output))
        XCTAssertEqual(reopened.pageCount, 2)
        let cleanedPage = try XCTUnwrap(reopened.page(at: 0))
        XCTAssertTrue(cleanedPage.annotations.contains { $0.contents == "Keep this review note" })
        XCTAssertTrue(
            try visionRecognition(in: XCTUnwrap(PDFOCRService.rasterizedImage(for: cleanedPage)))
                .text.localizedCaseInsensitiveContains("ORIFOLD RECEIPT 7429")
        )
        let untouchedAfter = try XCTUnwrap(
            PDFOCRService.rasterizedImage(for: XCTUnwrap(reopened.page(at: 1)), dpi: 72)
        )
        XCTAssertLessThan(try pixelDifference(untouchedBefore, untouchedAfter), 0.001)
    }

    func testReplacingPageContentPreservesRotationAndMediaBox() throws {
        let source = PDFDocument()
        let page = try XCTUnwrap(
            PDFPage(image: NSImage(cgImage: photographedPage(angleDegrees: 4), size: .zero))
        )
        page.rotation = 90
        source.insert(page, at: 0)
        let sourceData = try XCTUnwrap(PDFSerializer.data(from: source))
        let serializedSource = try XCTUnwrap(PDFDocument(data: sourceData))
        let serializedPage = try XCTUnwrap(serializedSource.page(at: 0))
        let serializedMediaBox = serializedPage.bounds(for: .mediaBox)
        XCTAssertTrue(
            try visionRecognition(in: XCTUnwrap(PDFOCRService.rasterizedImage(for: serializedPage)))
                .text.localizedCaseInsensitiveContains("ORIFOLD RECEIPT 7429")
        )

        let output = try ScanCleanupPipeline.replacingPageContents(
            in: sourceData,
            pageIndices: [0],
            options: ScanCleanupOptions()
        )

        let reopened = try XCTUnwrap(PDFDocument(data: output))
        let reopenedPage = try XCTUnwrap(reopened.page(at: 0))
        XCTAssertEqual(reopenedPage.rotation, 90)
        XCTAssertEqual(reopenedPage.bounds(for: .mediaBox).minX, serializedMediaBox.minX, accuracy: 0.01)
        XCTAssertEqual(reopenedPage.bounds(for: .mediaBox).minY, serializedMediaBox.minY, accuracy: 0.01)
        XCTAssertEqual(reopenedPage.bounds(for: .mediaBox).width, serializedMediaBox.width, accuracy: 0.01)
        XCTAssertEqual(reopenedPage.bounds(for: .mediaBox).height, serializedMediaBox.height, accuracy: 0.01)
        let rendered = try XCTUnwrap(PDFOCRService.rasterizedImage(for: reopenedPage))
        let recognition = try visionRecognition(in: rendered)
        XCTAssertTrue(
            recognition.text.localizedCaseInsensitiveContains("RECEIPT 7429"),
            "Recognized text: \(recognition.text)"
        )
    }

    func testViewModelCleanupIsAtomicAndByteExactAcrossUndoRedo() async throws {
        let source = PDFDocument()
        source.insert(
            try XCTUnwrap(PDFPage(image: NSImage(cgImage: photographedPage(angleDegrees: 7), size: .zero))),
            at: 0
        )
        source.insert(
            try XCTUnwrap(PDFPage(image: NSImage(cgImage: grayscaleGradient(width: 320, height: 220), size: .zero))),
            at: 1
        )
        let attachment = Data("scan-cleanup-undo-proof".utf8)
        let sourceData = try XCTUnwrap(PDFSerializer.data(from: source))
        let wrapper = FileWrapper(regularFileWithContents: sourceData)
        wrapper.preferredFilename = "scan.pdf"
        let attachmentDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Orifold-scan-cleanup-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: attachmentDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: attachmentDirectory) }
        let fingerprintStore = WorkspaceFingerprintStore(directory: attachmentDirectory)
        let document = try WorkspaceDocument(
            testingFile: wrapper,
            contentType: .pdf,
            filename: "scan.pdf",
            fingerprintStore: fingerprintStore
        )
        let viewModel = WorkspaceViewModel(document: document, processingEngine: PDFiumProcessingEngine())
        let undoManager = UndoManager()
        retainedUndoManager = undoManager
        viewModel.undoManager = undoManager
        let attachmentURL = attachmentDirectory.appendingPathComponent("proof.txt")
        try attachment.write(to: attachmentURL)
        XCTAssertTrue(viewModel.addAttachment(attachmentURL))
        undoManager.removeAllActions()
        let memberID = try XCTUnwrap(viewModel.document.workspace.documents.first?.id)
        let firstPageRefID = try XCTUnwrap(viewModel.document.workspace.pageOrder.first?.id)
        let original = try XCTUnwrap(viewModel.document.memberPDFData[memberID])

        let applied = await viewModel.applyScanCleanup(
            pageRefIDs: [firstPageRefID],
            options: ScanCleanupOptions()
        )

        XCTAssertTrue(applied)
        let cleaned = try XCTUnwrap(viewModel.document.memberPDFData[memberID])
        XCTAssertNotEqual(cleaned, original)
        XCTAssertTrue(QPDFService.isStructurallySound(cleaned))
        XCTAssertEqual(try AttachmentsService.extract("proof.txt", from: cleaned), attachment)
        XCTAssertEqual(viewModel.document.workspace.pageOrder.map(\.id), sourcePageIDs(in: viewModel))
        XCTAssertEqual(undoManager.undoActionName, L10n.string("undo.cleanScan"))

        let cleanedSnapshot = try document.snapshot(contentType: .pdf)
        let exportedData = try document.exportedPDFDataThrowing(from: cleanedSnapshot)
        XCTAssertTrue(QPDFService.isStructurallySound(exportedData))
        let exportedPDF = try XCTUnwrap(PDFDocument(data: exportedData))
        XCTAssertEqual(exportedPDF.pageCount, 2)
        XCTAssertTrue(
            try visionRecognition(
                in: XCTUnwrap(PDFOCRService.rasterizedImage(for: XCTUnwrap(exportedPDF.page(at: 0))))
            ).text.localizedCaseInsensitiveContains("RECEIPT 7429")
        )

        let savedWrapper = try document.savedFileWrapper(from: cleanedSnapshot)
        savedWrapper.preferredFilename = "scan.pdf"
        let reopenedDocument = try WorkspaceDocument(
            testingFile: savedWrapper,
            contentType: .pdf,
            filename: "scan.pdf",
            fingerprintStore: fingerprintStore
        )
        let reopenedViewModel = WorkspaceViewModel(
            document: reopenedDocument,
            processingEngine: PDFiumProcessingEngine()
        )
        let reopenedMemberData = try XCTUnwrap(reopenedDocument.memberPDFData[memberID])
        XCTAssertTrue(QPDFService.isStructurallySound(reopenedMemberData))
        XCTAssertEqual(
            reopenedDocument.workspace.pageOrder.map(\.id),
            document.workspace.pageOrder.map(\.id)
        )
        let reopenedPDF = try XCTUnwrap(reopenedViewModel.loadedPDFs.first?.1)
        XCTAssertEqual(reopenedPDF.pageCount, 2)
        XCTAssertTrue(
            try visionRecognition(
                in: XCTUnwrap(PDFOCRService.rasterizedImage(for: XCTUnwrap(reopenedPDF.page(at: 0))))
            ).text.localizedCaseInsensitiveContains("RECEIPT 7429")
        )

        undoManager.undo()
        XCTAssertEqual(viewModel.document.memberPDFData[memberID], original)

        undoManager.redo()
        XCTAssertEqual(viewModel.document.memberPDFData[memberID], cleaned)
    }

    func testDocumentScopeCleanupRejectsMixedCommittedTextEditBeforeAnyMutation() async throws {
        let source = PDFDocument()
        for index in 0..<2 {
            source.insert(
                try XCTUnwrap(PDFPage(image: NSImage(cgImage: photographedPage(angleDegrees: CGFloat(index)), size: .zero))),
                at: index
            )
        }
        let sourceData = try XCTUnwrap(PDFSerializer.data(from: source))
        let wrapper = FileWrapper(regularFileWithContents: sourceData)
        wrapper.preferredFilename = "mixed-edit.pdf"
        let document = try WorkspaceDocument(testingFile: wrapper, contentType: .pdf, filename: "mixed-edit.pdf")
        let viewModel = WorkspaceViewModel(document: document, processingEngine: PDFiumProcessingEngine())
        let undoManager = UndoManager()
        retainedUndoManager = undoManager
        viewModel.undoManager = undoManager
        let refs = document.workspace.pageOrder
        let blockedRef = try XCTUnwrap(refs.last)
        document.workspace.pageEditStates = [
            PageEditState(pageRefID: blockedRef.id, operations: [
                PDFTextEditOperation(
                    pageRefID: blockedRef.id,
                    sourceBlockID: UUID(),
                    sourceBounds: CGRect(x: 40, y: 40, width: 120, height: 24),
                    sourceText: "Original",
                    editedBounds: CGRect(x: 40, y: 40, width: 120, height: 24),
                    replacementText: "Edited",
                    fontName: "Helvetica",
                    fontSize: 12,
                    textColor: .documentText,
                    alignment: .left
                )
            ])
        ]
        let beforeSnapshot = try document.snapshot(contentType: .pdf)
        let beforeMemberPDFData = document.memberPDFData
        let beforeLoadedPDFs = viewModel.loadedPDFs.map(\.1)
        let beforeUndoName = undoManager.undoActionName

        let applied = await viewModel.applyScanCleanup(
            pageRefIDs: viewModel.scanCleanupTargetPageRefIDs(scope: .document),
            options: ScanCleanupOptions()
        )

        let afterSnapshot = try document.snapshot(contentType: .pdf)
        XCTAssertFalse(applied)
        XCTAssertEqual(document.memberPDFData, beforeMemberPDFData)
        XCTAssertEqual(afterSnapshot.originalMemberPDFData, beforeSnapshot.originalMemberPDFData)
        XCTAssertEqual(afterSnapshot.workspace.pageEditStates, beforeSnapshot.workspace.pageEditStates)
        XCTAssertEqual(afterSnapshot.workspace.objectEditStates, beforeSnapshot.workspace.objectEditStates)
        XCTAssertEqual(afterSnapshot.workspace.modifiedAt, beforeSnapshot.workspace.modifiedAt)
        XCTAssertEqual(viewModel.loadedPDFs.count, beforeLoadedPDFs.count)
        for (before, after) in zip(beforeLoadedPDFs, viewModel.loadedPDFs.map(\.1)) {
            XCTAssertTrue(before === after)
        }
        XCTAssertFalse(viewModel.operationProgress.isActive)
        XCTAssertFalse(viewModel.isApplyingScanCleanup)
        XCTAssertFalse(undoManager.canUndo)
        XCTAssertEqual(undoManager.undoActionName, beforeUndoName)
        XCTAssertEqual(viewModel.editingStatus?.severity, .warning)
    }

    func testCleanupRejectsCommittedObjectOperationWithoutChangingState() async throws {
        let source = PDFDocument()
        source.insert(
            try XCTUnwrap(PDFPage(image: NSImage(cgImage: photographedPage(angleDegrees: 0), size: .zero))),
            at: 0
        )
        let sourceData = try XCTUnwrap(PDFSerializer.data(from: source))
        let wrapper = FileWrapper(regularFileWithContents: sourceData)
        wrapper.preferredFilename = "object-edit.pdf"
        let document = try WorkspaceDocument(testingFile: wrapper, contentType: .pdf, filename: "object-edit.pdf")
        let viewModel = WorkspaceViewModel(document: document, processingEngine: PDFiumProcessingEngine())
        let undoManager = UndoManager()
        retainedUndoManager = undoManager
        viewModel.undoManager = undoManager
        let ref = try XCTUnwrap(document.workspace.pageOrder.first)
        let memberID = ref.memberDocId
        let operation = ObjectEditOperation(
            type: .objectDelete,
            documentID: memberID,
            pageRefID: ref.id,
            sourceObjectKey: PDFObjectStableKey(pageRefID: ref.id, structuralDigest: 1),
            objectType: .imageXObject,
            editability: .directImageEdit,
            originalBoundsPdf: CGRect(x: 0, y: 0, width: 10, height: 10),
            newBoundsPdf: CGRect(x: 0, y: 0, width: 10, height: 10),
            originalTransform: .identity,
            newTransform: .identity,
            pageRotation: 0,
            originalZIndex: 0,
            newZIndex: 0,
            replacementStrategy: .pdfiumStructural
        )
        document.workspace.objectEditStates = [
            PageObjectEditState(pageRefID: ref.id, operations: [operation])
        ]
        let beforeSnapshot = try document.snapshot(contentType: .pdf)
        let beforeMemberPDFData = document.memberPDFData
        let beforeLoadedPDFs = viewModel.loadedPDFs.map(\.1)

        let applied = await viewModel.applyScanCleanup(
            pageRefIDs: [ref.id],
            options: ScanCleanupOptions()
        )

        let afterSnapshot = try document.snapshot(contentType: .pdf)
        XCTAssertFalse(applied)
        XCTAssertEqual(document.memberPDFData, beforeMemberPDFData)
        XCTAssertEqual(afterSnapshot.originalMemberPDFData, beforeSnapshot.originalMemberPDFData)
        XCTAssertEqual(afterSnapshot.workspace.objectEditStates, beforeSnapshot.workspace.objectEditStates)
        XCTAssertEqual(afterSnapshot.workspace.modifiedAt, beforeSnapshot.workspace.modifiedAt)
        XCTAssertEqual(viewModel.loadedPDFs.count, beforeLoadedPDFs.count)
        for (before, after) in zip(beforeLoadedPDFs, viewModel.loadedPDFs.map(\.1)) {
            XCTAssertTrue(before === after)
        }
        XCTAssertFalse(viewModel.operationProgress.isActive)
        XCTAssertFalse(viewModel.isApplyingScanCleanup)
        XCTAssertFalse(undoManager.canUndo)
        XCTAssertEqual(viewModel.editingStatus?.severity, .warning)
    }

    func testCleanupRejectsCountedButUnloadableAuthoritativePageDespiteLoadedPDFPage() async throws {
        let source = PDFDocument()
        source.insert(
            try XCTUnwrap(PDFPage(image: NSImage(cgImage: photographedPage(angleDegrees: 0), size: .zero))),
            at: 0
        )
        let sourceData = try XCTUnwrap(PDFSerializer.data(from: source))
        let wrapper = FileWrapper(regularFileWithContents: sourceData)
        wrapper.preferredFilename = "parser-disagreement.pdf"
        let document = try WorkspaceDocument(
            testingFile: wrapper,
            contentType: .pdf,
            filename: "parser-disagreement.pdf"
        )
        let viewModel = WorkspaceViewModel(document: document, processingEngine: PDFiumProcessingEngine())
        let undoManager = UndoManager()
        retainedUndoManager = undoManager
        viewModel.undoManager = undoManager
        let ref = try XCTUnwrap(document.workspace.pageOrder.first)
        let memberID = ref.memberDocId
        let loadedPDFsBefore = viewModel.loadedPDFs.map(\.1)

        // Model a parser/lane disagreement: PDFKit still has the valid loaded page that the
        // cleanup pipeline could rasterize, while the authoritative member lane is unreadable
        // to the structure inspector. Preflight must reject rather than treating it as untagged.
        let unreadableData = countedButUnloadablePageFixture()
        XCTAssertThrowsError(try StructureInspectionService.inspect(unreadableData, pageIndex: 0))
        document.memberPDFData[memberID] = unreadableData
        let memberDataBefore = document.memberPDFData
        let modifiedAtBefore = document.workspace.modifiedAt
        let undoNameBefore = undoManager.undoActionName
        XCTAssertFalse(viewModel.operationProgress.isActive)
        XCTAssertFalse(viewModel.isApplyingScanCleanup)

        let applied = await viewModel.applyScanCleanup(
            pageRefIDs: [ref.id],
            options: ScanCleanupOptions()
        )

        XCTAssertFalse(applied)
        XCTAssertEqual(document.memberPDFData, memberDataBefore)
        XCTAssertEqual(document.workspace.modifiedAt, modifiedAtBefore)
        XCTAssertEqual(viewModel.loadedPDFs.count, loadedPDFsBefore.count)
        for (before, after) in zip(loadedPDFsBefore, viewModel.loadedPDFs.map(\.1)) {
            XCTAssertTrue(before === after)
        }
        XCTAssertFalse(viewModel.operationProgress.isActive)
        XCTAssertFalse(viewModel.isApplyingScanCleanup)
        XCTAssertFalse(undoManager.canUndo)
        XCTAssertEqual(undoManager.undoActionName, undoNameBefore)
        XCTAssertEqual(viewModel.editingStatus?.severity, .error)
    }

    func testCleanupRejectsTargetedTaggedPageBeforeMutation() async throws {
        let taggedData = fixture("tagged-sample.pdf")
        let (document, taggedRef, taggedMemberID) = makeSingleMemberDocument(
            data: taggedData,
            displayName: "Tagged"
        )
        let viewModel = WorkspaceViewModel(document: document, processingEngine: PDFiumProcessingEngine())
        let undoManager = UndoManager()
        retainedUndoManager = undoManager
        viewModel.undoManager = undoManager
        let beforeStructure = try StructureInspectionService.inspect(taggedData, pageIndex: 0)
        let beforeModifiedAt = document.workspace.modifiedAt

        let applied = await viewModel.applyScanCleanup(
            pageRefIDs: [taggedRef.id],
            options: ScanCleanupOptions()
        )

        XCTAssertFalse(applied)
        let afterData = try XCTUnwrap(document.memberPDFData[taggedMemberID])
        XCTAssertEqual(afterData, taggedData)
        XCTAssertEqual(try StructureInspectionService.inspect(afterData, pageIndex: 0), beforeStructure)
        XCTAssertEqual(document.workspace.modifiedAt, beforeModifiedAt)
        XCTAssertFalse(viewModel.operationProgress.isActive)
        XCTAssertFalse(viewModel.isApplyingScanCleanup)
        XCTAssertFalse(undoManager.canUndo)
        XCTAssertEqual(viewModel.editingStatus?.severity, .warning)
    }

    func testCleanupEligiblePageLeavesNonTargetTaggedPageFunctionalInSameMember() async throws {
        let sourceData = twoPagePartiallyTaggedFixture()
        let document = WorkspaceDocument()
        var member = MemberDocument(displayName: "Partially tagged", sourcePDFRef: "partially-tagged.pdf")
        let refs = (0..<2).map { PageRef(memberDocId: member.id, sourcePageIndex: $0) }
        member.pageRefs = refs.map(\.id)
        document.workspace.documents = [member]
        document.workspace.pageOrder = refs
        document.memberPDFData[member.id] = sourceData
        let viewModel = WorkspaceViewModel(document: document, processingEngine: PDFiumProcessingEngine())
        let untaggedBefore = try StructureInspectionService.inspect(sourceData, pageIndex: 0)
        let taggedBefore = try StructureInspectionService.inspect(sourceData, pageIndex: 1)
        XCTAssertTrue(untaggedBefore.roots.isEmpty)
        XCTAssertFalse(taggedBefore.roots.isEmpty)

        let applied = await viewModel.applyScanCleanup(
            pageRefIDs: [refs[0].id],
            options: ScanCleanupOptions()
        )

        XCTAssertTrue(applied)
        let cleanedData = try XCTUnwrap(document.memberPDFData[member.id])
        XCTAssertNotEqual(cleanedData, sourceData)
        XCTAssertEqual(try StructureInspectionService.inspect(cleanedData, pageIndex: 1), taggedBefore)
    }

    func testCleanupScopeDefaultsToCurrentPageAndCanExpandToDocument() throws {
        let source = PDFDocument()
        for index in 0..<2 {
            source.insert(
                try XCTUnwrap(PDFPage(image: NSImage(cgImage: grayscaleGradient(width: 120, height: 90), size: .zero))),
                at: index
            )
        }
        let wrapper = FileWrapper(regularFileWithContents: try XCTUnwrap(PDFSerializer.data(from: source)))
        wrapper.preferredFilename = "scope.pdf"
        let document = try WorkspaceDocument(testingFile: wrapper, contentType: .pdf, filename: "scope.pdf")
        let viewModel = WorkspaceViewModel(document: document, processingEngine: PDFiumProcessingEngine())
        let refs = viewModel.document.workspace.pageOrder
        viewModel.selectPage(refs[1])

        XCTAssertEqual(viewModel.scanCleanupTargetPageRefIDs(scope: .currentPage), [refs[1].id])
        XCTAssertEqual(viewModel.scanCleanupTargetPageRefIDs(scope: .document), refs.map(\.id))
    }

    private func fixture(_ name: String) -> Data {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(name)")
        // swiftlint:disable:next force_try
        return try! Data(contentsOf: url)
    }

    private func makeMember(data: Data, displayName: String) -> (MemberDocument, PageRef) {
        var member = MemberDocument(displayName: displayName, sourcePDFRef: "\(displayName).pdf")
        let ref = PageRef(memberDocId: member.id, sourcePageIndex: 0)
        member.pageRefs = [ref.id]
        return (member, ref)
    }

    private func makeSingleMemberDocument(
        data: Data,
        displayName: String
    ) -> (WorkspaceDocument, PageRef, UUID) {
        let document = WorkspaceDocument()
        let (member, ref) = makeMember(data: data, displayName: displayName)
        document.workspace.documents = [member]
        document.workspace.pageOrder = [ref]
        document.memberPDFData[member.id] = data
        return (document, ref, member.id)
    }

    private func countedButUnloadablePageFixture() -> Data {
        let objects = [
            "<< /Type /Catalog /Pages 2 0 R >>",
            "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            "<< /Type /NotAPage >>",
        ]
        var output = Data("%PDF-1.7\n".utf8)
        output.append(contentsOf: [0x25, 0xE2, 0xE3, 0xCF, 0xD3, 0x0A])
        var offsets = [0]
        for (index, body) in objects.enumerated() {
            offsets.append(output.count)
            output.append(Data("\(index + 1) 0 obj\n\(body)\nendobj\n".utf8))
        }
        let xrefOffset = output.count
        output.append(Data("xref\n0 \(objects.count + 1)\n0000000000 65535 f \n".utf8))
        for offset in offsets.dropFirst() {
            output.append(Data("\(String(format: "%010d", offset)) 00000 n \n".utf8))
        }
        output.append(Data(
            "trailer\n<< /Size \(objects.count + 1) /Root 1 0 R >>\nstartxref\n\(xrefOffset)\n%%EOF\n".utf8
        ))
        return output
    }

    /// A two-page tagged PDF whose first page has no structure participation and whose second
    /// page owns the document's marked content. This exercises cleanup within the same member as
    /// an untouched tagged page, rather than relying on the easier cross-member isolation case.
    private func twoPagePartiallyTaggedFixture() -> Data {
        let untaggedOps = "BT /F1 20 Tf 72 700 Td (Eligible untagged page) Tj ET\n"
        let taggedOps = """
        /H1 <</MCID 0>> BDC
        BT /F1 24 Tf 72 700 Td (Tagged heading) Tj ET
        EMC
        /P <</MCID 1>> BDC
        BT /F1 12 Tf 72 660 Td (Tagged body) Tj ET
        EMC

        """
        let objects = [
            "<< /Type /Catalog /Pages 2 0 R /MarkInfo << /Marked true >> /StructTreeRoot 8 0 R >>",
            "<< /Type /Pages /Kids [3 0 R 5 0 R] /Count 2 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << /Font << /F1 7 0 R >> >> >>",
            "<< /Length \(untaggedOps.utf8.count) >>\nstream\n\(untaggedOps)endstream",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 6 0 R /Resources << /Font << /F1 7 0 R >> >> /StructParents 0 >>",
            "<< /Length \(taggedOps.utf8.count) >>\nstream\n\(taggedOps)endstream",
            "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
            "<< /Type /StructTreeRoot /K [9 0 R] /ParentTree 12 0 R /ParentTreeNextKey 1 >>",
            "<< /Type /StructElem /S /Document /P 8 0 R /Pg 5 0 R /K [10 0 R 11 0 R] >>",
            "<< /Type /StructElem /S /H1 /P 9 0 R /Pg 5 0 R /K 0 /T (Tagged heading) >>",
            "<< /Type /StructElem /S /P /P 9 0 R /Pg 5 0 R /K 1 >>",
            "<< /Nums [0 [10 0 R 11 0 R]] >>",
        ]
        var output = Data("%PDF-1.7\n".utf8)
        output.append(contentsOf: [0x25, 0xE2, 0xE3, 0xCF, 0xD3, 0x0A])
        var offsets = [0]
        for (index, body) in objects.enumerated() {
            offsets.append(output.count)
            output.append(Data("\(index + 1) 0 obj\n\(body)\nendobj\n".utf8))
        }
        let xrefOffset = output.count
        output.append(Data("xref\n0 \(objects.count + 1)\n0000000000 65535 f \n".utf8))
        for offset in offsets.dropFirst() {
            output.append(Data("\(String(format: "%010d", offset)) 00000 n \n".utf8))
        }
        output.append(Data("trailer\n<< /Size \(objects.count + 1) /Root 1 0 R >>\nstartxref\n\(xrefOffset)\n%%EOF\n".utf8))
        return output
    }
}

@MainActor
private func sourcePageIDs(in viewModel: WorkspaceViewModel) -> [UUID] {
    viewModel.document.workspace.documents.flatMap(\.pageRefs)
}

private func setGray(_ value: UInt8, x: Int, y: Int, width: Int, pixels: inout [UInt8]) {
    let offset = (y * width + x) * 4
    pixels[offset] = value
    pixels[offset + 1] = value
    pixels[offset + 2] = value
    pixels[offset + 3] = 255
}

private func photographedPage(angleDegrees: CGFloat) throws -> CGImage {
    let width = 800
    let height = 650
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
          ) else { throw ScanCleanupTestError.imageCreationFailed }
    context.setFillColor(CGColor(gray: 0.35, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.saveGState()
    context.translateBy(x: CGFloat(width) / 2, y: CGFloat(height) / 2)
    context.rotate(by: angleDegrees * .pi / 180)
    let paper = CGRect(x: -250, y: -180, width: 500, height: 360)
    context.setShadow(offset: CGSize(width: 8, height: -8), blur: 12, color: CGColor(gray: 0, alpha: 0.5))
    context.setFillColor(CGColor(gray: 0.96, alpha: 1))
    context.fill(paper)
    context.setShadow(offset: .zero, blur: 0, color: nil)
    context.setStrokeColor(CGColor(gray: 0.03, alpha: 1))
    context.setLineWidth(5)
    context.stroke(paper.insetBy(dx: 2.5, dy: 2.5))
    context.setLineWidth(3)
    for offset in stride(from: -110, through: 100, by: 42) {
        context.move(to: CGPoint(x: -180, y: offset))
        context.addLine(to: CGPoint(x: 170, y: offset))
        context.strokePath()
    }
    let attributes: [NSAttributedString.Key: Any] = [
        .font: CTFontCreateWithName("Helvetica-Bold" as CFString, 27, nil),
        .foregroundColor: CGColor(gray: 0.02, alpha: 1),
    ]
    let line = CTLineCreateWithAttributedString(
        NSAttributedString(string: "ORIFOLD RECEIPT 7429", attributes: attributes)
    )
    context.textPosition = CGPoint(x: -180, y: 125)
    CTLineDraw(line, context)
    context.restoreGState()
    return try XCTUnwrap(context.makeImage())
}

private func visionRecognition(in image: CGImage) throws -> (text: String, averageConfidence: Float) {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    try VNImageRequestHandler(cgImage: image, orientation: .up, options: [:]).perform([request])
    let candidates = (request.results ?? []).compactMap { $0.topCandidates(1).first }
    let average = candidates.isEmpty
        ? 0
        : candidates.map(\.confidence).reduce(0, +) / Float(candidates.count)
    return (candidates.map(\.string).joined(separator: "\n"), average)
}

/// Independent test oracle: estimate the slope of the upper dark border by taking the first
/// dark pixel in each interior column and fitting a least-squares line.
private func darkBorderSlope(in image: CGImage) -> Double {
    let width = image.width
    let height = image.height
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
          ) else { return .infinity }
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    var points: [(Double, Double)] = []
    let inset = max(2, width / 5)
    for x in stride(from: inset, to: width - inset, by: max(1, width / 80)) {
        for y in 0..<height {
            let offset = (y * width + x) * 4
            let red = Int(pixels[offset])
            let green = Int(pixels[offset + 1])
            let blue = Int(pixels[offset + 2])
            if red + green + blue < 180 {
                points.append((Double(x), Double(y)))
                break
            }
        }
    }
    guard points.count > 8 else { return .infinity }
    let meanX = points.map(\.0).reduce(0, +) / Double(points.count)
    let meanY = points.map(\.1).reduce(0, +) / Double(points.count)
    let numerator = points.reduce(0) { $0 + ($1.0 - meanX) * ($1.1 - meanY) }
    let denominator = points.reduce(0) { $0 + ($1.0 - meanX) * ($1.0 - meanX) }
    return numerator / max(denominator, 0.000_001)
}

private func grayscaleGradient(width: Int, height: Int) throws -> CGImage {
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    for y in 0..<height {
        for x in 0..<width {
            let value = UInt8((Double(x) / Double(max(width - 1, 1)) * 255).rounded())
            let offset = (y * width + x) * 4
            pixels[offset] = value
            pixels[offset + 1] = value
            pixels[offset + 2] = value
            pixels[offset + 3] = 255
        }
    }
    return try makeImage(pixels: &pixels, width: width, height: height)
}

private func grayscaleSamples(in image: CGImage) throws -> [UInt8] {
    let width = image.width
    let height = image.height
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
          ) else {
        throw ScanCleanupTestError.imageCreationFailed
    }
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return stride(from: 0, to: pixels.count, by: 4).map { pixels[$0] }
}

private func pixelDifference(_ lhs: CGImage, _ rhs: CGImage) throws -> Double {
    guard lhs.width == rhs.width, lhs.height == rhs.height else { return 1 }
    func bytes(_ image: CGImage) throws -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: &pixels,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: image.width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { throw ScanCleanupTestError.imageCreationFailed }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return pixels
    }
    let left = try bytes(lhs)
    let right = try bytes(rhs)
    let total = zip(left, right).reduce(0.0) { partial, pair in
        partial + Double(abs(Int(pair.0) - Int(pair.1)))
    }
    return total / Double(max(left.count, 1)) / 255
}

private func resizedForComparison(_ image: CGImage, width: Int, height: Int) throws -> CGImage {
    guard width > 0, height > 0,
          let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
          ) else { throw ScanCleanupTestError.imageCreationFailed }
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    guard let output = context.makeImage() else { throw ScanCleanupTestError.imageCreationFailed }
    return output
}

private final class ScanCleanupCancellationProbe: @unchecked Sendable {
    private let lock = NSLock()
    private let cancelOnCheck: Int
    private var storedCheckCount = 0

    init(cancelOnCheck: Int) {
        self.cancelOnCheck = cancelOnCheck
    }

    func shouldCancel() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        storedCheckCount += 1
        return storedCheckCount >= cancelOnCheck
    }

    var checkCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedCheckCount
    }
}

private func makeImage(pixels: inout [UInt8], width: Int, height: Int) throws -> CGImage {
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
          ),
          let image = context.makeImage() else {
        throw ScanCleanupTestError.imageCreationFailed
    }
    return image
}

private enum ScanCleanupTestError: Error {
    case imageCreationFailed
}
