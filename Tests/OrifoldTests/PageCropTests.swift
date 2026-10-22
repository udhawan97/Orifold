import AppKit
import CoreGraphics
import PDFKit
import UniformTypeIdentifiers
import XCTest
@testable import Orifold

final class PageCropTests: XCTestCase {
    private var retainedUndoManager: UndoManager?

    func testSettingCropBoxWritesRequestedPageBox() throws {
        let source = makeSinglePagePDF()
        let requested = CGRect(x: 36, y: 54, width: 540, height: 684)

        let cropped = try XCTUnwrap(
            QPDFService.settingCropBox(source, pageIndex: 0, rect: requested)
        )
        let page = try XCTUnwrap(PDFDocument(data: cropped)?.page(at: 0))

        XCTAssertEqual(page.bounds(for: .cropBox).minX, requested.minX, accuracy: 0.01)
        XCTAssertEqual(page.bounds(for: .cropBox).minY, requested.minY, accuracy: 0.01)
        XCTAssertEqual(page.bounds(for: .cropBox).width, requested.width, accuracy: 0.01)
        XCTAssertEqual(page.bounds(for: .cropBox).height, requested.height, accuracy: 0.01)
        XCTAssertTrue(QPDFService.isStructurallySound(cropped))
    }

    func testCropBoxSurvivesDecorationExport() throws {
        let requested = CGRect(x: 30, y: 40, width: 552, height: 712)
        let cropped = try XCTUnwrap(
            QPDFService.settingCropBox(makeSinglePagePDF(), pageIndex: 0, rect: requested)
        )
        let pageRef = PageRef(memberDocId: UUID(), sourcePageIndex: 0)

        let baked = try PDFDecorationExportBaker.bake(
            decorations: [.overlayPDF(pdfData: makeSinglePagePDF(), placement: .under)],
            pageOrder: [pageRef],
            into: cropped
        )

        assertBox(try cropBox(in: baked), equals: requested)
    }

    func testApplyingCropMarginsUpdatesReaderBytesAndUndoRestoresOriginalBox() throws {
        let viewModel = try makeViewModel()
        let pageRef = try XCTUnwrap(viewModel.document.workspace.pageOrder.first)
        let originalBox = try cropBox(in: viewModel.document.memberPDFData[pageRef.memberDocId])

        XCTAssertTrue(viewModel.applyPageCrop(
            margins: PageCropMargins(top: 54, bottom: 54, left: 36, right: 36),
            to: [pageRef]
        ))

        let expected = CGRect(x: 36, y: 54, width: 540, height: 684)
        assertBox(try cropBox(in: viewModel.document.memberPDFData[pageRef.memberDocId]), equals: expected)
        assertBox(try XCTUnwrap(viewModel.loadedPDFs.first?.1.page(at: 0)).bounds(for: .cropBox), equals: expected)

        let undo = try XCTUnwrap(viewModel.undoManager)
        undo.undo()
        assertBox(try cropBox(in: viewModel.document.memberPDFData[pageRef.memberDocId]), equals: originalBox)

        undo.redo()
        assertBox(try cropBox(in: viewModel.document.memberPDFData[pageRef.memberDocId]), equals: expected)
    }

    func testCropPreservesAttachmentAndUndoRestoresExactPriorBytes() throws {
        let payload = Data("keep-through-crop".utf8)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let attachmentURL = directory.appendingPathComponent("evidence.txt")
        try payload.write(to: attachmentURL)

        let viewModel = try makeViewModel()
        let pageRef = try XCTUnwrap(viewModel.document.workspace.pageOrder.first)
        let memberID = pageRef.memberDocId
        XCTAssertTrue(viewModel.addAttachment(attachmentURL))
        let exactBefore = try XCTUnwrap(viewModel.document.memberPDFData[memberID])

        XCTAssertTrue(viewModel.applyPageCrop(
            margins: PageCropMargins(top: 24, bottom: 24, left: 18, right: 18),
            to: [pageRef]
        ))

        let cropped = try XCTUnwrap(viewModel.document.memberPDFData[memberID])
        XCTAssertEqual(try AttachmentsService.list(in: cropped).map(\.name), ["evidence.txt"])
        XCTAssertEqual(try AttachmentsService.extract("evidence.txt", from: cropped), payload)

        viewModel.undoManager?.undo()
        XCTAssertEqual(viewModel.document.memberPDFData[memberID], exactBefore)
        XCTAssertEqual(try AttachmentsService.extract("evidence.txt", from: exactBefore), payload)
    }

    @MainActor
    func testCropUndoRestoresSignedMemberBytesAndSignatureValidity() async throws {
        let signerName = "Crop undo signer \(UUID().uuidString)"
        let identity = try SelfSignedSigningIdentityProvider.generate(
            request: SelfSignedIdentityRequest(commonName: signerName)
        )
        let signed = try PDFIncrementalSigner().sign(
            pdf: makeSinglePagePDF(),
            field: SignatureFieldSpec(
                pageIndex: 0,
                rect: CGRect(x: 40, y: 60, width: 180, height: 50),
                signerName: signerName
            ),
            appearance: nil
        ) { bytes in
            try CMSSignatureBuilder.buildCMS(
                byteRangeBytes: bytes,
                identity: identity,
                signingTime: Date(timeIntervalSince1970: 1_786_240_000)
            )
        }
        let document = WorkspaceDocument()
        var member = MemberDocument(displayName: "Signed", sourcePDFRef: "signed.pdf")
        let pageRef = PageRef(memberDocId: member.id, sourcePageIndex: 0)
        member.pageRefs = [pageRef.id]
        document.workspace.documents = [member]
        document.workspace.pageOrder = [pageRef]
        document.memberPDFData[member.id] = signed
        let viewModel = WorkspaceViewModel(
            document: document,
            processingEngine: PDFKitProcessingEngineFallback()
        )
        let undoManager = UndoManager()
        retainedUndoManager = undoManager
        viewModel.undoManager = undoManager

        XCTAssertTrue(viewModel.applyPageCrop(
            margins: PageCropMargins(top: 24, bottom: 24, left: 18, right: 18),
            to: [pageRef]
        ))
        undoManager.undo()

        let restored = try XCTUnwrap(document.memberPDFData[member.id])
        XCTAssertEqual(restored, signed)
        let reports = await PDFSignatureValidationService.validate(pdf: restored)
        let report = try XCTUnwrap(reports.first)
        XCTAssertEqual(report.integrity, .valid)
        XCTAssertEqual(report.coverage, .entireDocument)
    }

    func testCropPersistsWhenPristineAndObjectBaseLanesReplay() throws {
        let viewModel = try makeViewModel()
        let pageRef = try XCTUnwrap(viewModel.document.workspace.pageOrder.first)
        let memberID = pageRef.memberDocId

        XCTAssertTrue(viewModel.applyPageCrop(
            margins: PageCropMargins(top: 54, bottom: 54, left: 36, right: 36),
            to: [pageRef]
        ))
        let firstCrop = CGRect(x: 36, y: 54, width: 540, height: 684)

        let firstImage = try XCTUnwrap(
            viewModel.objectMap(for: pageRef).objects.first { $0.objectType == .imageXObject }
        )
        XCTAssertTrue(viewModel.applyObjectEdit([
            transformOperation(firstImage, pageRef: pageRef, memberID: memberID, deltaX: 12, deltaY: -8)
        ]))
        assertBox(
            try cropBox(in: viewModel.document.memberPDFData[memberID]),
            equals: firstCrop,
            "the first object replay must start from the already-cropped pristine lane"
        )

        XCTAssertTrue(viewModel.applyPageCrop(
            margins: PageCropMargins(top: 72, bottom: 72, left: 48, right: 48),
            to: [pageRef]
        ))
        let secondCrop = CGRect(x: 48, y: 72, width: 516, height: 648)

        let movedImage = try XCTUnwrap(
            viewModel.objectMap(for: pageRef).objects.first { $0.objectType == .imageXObject }
        )
        XCTAssertTrue(viewModel.applyObjectEdit([
            transformOperation(movedImage, pageRef: pageRef, memberID: memberID, deltaX: 6, deltaY: -4)
        ]))
        assertBox(
            try cropBox(in: viewModel.document.memberPDFData[memberID]),
            equals: secondCrop,
            "a later object replay must start from the newly-cropped object-base lane"
        )
    }

    func testCropPreservesUnsavedLivePageRotation() throws {
        let viewModel = try makeViewModel()
        let pageRef = try XCTUnwrap(viewModel.document.workspace.pageOrder.first)

        viewModel.rotatePage(pageRef, by: 90)
        XCTAssertEqual(viewModel.loadedPDFs.first?.1.page(at: 0)?.rotation, 90)

        XCTAssertTrue(viewModel.applyPageCrop(
            margins: PageCropMargins(top: 20, bottom: 20, left: 20, right: 20),
            to: [pageRef]
        ))

        XCTAssertEqual(viewModel.loadedPDFs.first?.1.page(at: 0)?.rotation, 90)
        let stored = try XCTUnwrap(viewModel.document.memberPDFData[pageRef.memberDocId])
        XCTAssertEqual(PDFDocument(data: stored)?.page(at: 0)?.rotation, 90)
    }

    func testCropPreventsSilentSourcePreservingExport() throws {
        let viewModel = try makeMarkdownViewModel()
        let pageRef = try XCTUnwrap(viewModel.document.workspace.pageOrder.first)

        XCTAssertTrue(viewModel.applyPageCrop(
            margins: PageCropMargins(top: 20, bottom: 20, left: 20, right: 20),
            to: [pageRef]
        ))

        XCTAssertThrowsError(try viewModel.dataForWorkspaceExport(as: .markdown)) { error in
            guard case WorkspaceViewModel.ExportBuildError.pdfOnlyEditsCannotMap = error else {
                return XCTFail("Expected pdfOnlyEditsCannotMap, got \(error)")
            }
        }
    }

    func testCroppingPagesAcrossMembersIsOneAtomicUndoStep() throws {
        let document = WorkspaceDocument()
        let firstMember = MemberDocument(displayName: "First", sourcePDFRef: "first.pdf")
        let secondMember = MemberDocument(displayName: "Second", sourcePDFRef: "second.pdf")
        let firstRef = PageRef(memberDocId: firstMember.id, sourcePageIndex: 0)
        let secondRef = PageRef(memberDocId: secondMember.id, sourcePageIndex: 0)
        var members = [firstMember, secondMember]
        members[0].pageRefs = [firstRef.id]
        members[1].pageRefs = [secondRef.id]
        document.workspace.documents = members
        document.workspace.pageOrder = [firstRef, secondRef]
        document.memberPDFData[firstMember.id] = makeSinglePagePDF()
        document.memberPDFData[secondMember.id] = makeSinglePagePDF()

        let viewModel = WorkspaceViewModel(
            document: document,
            processingEngine: PDFKitProcessingEngineFallback()
        )
        let undoManager = UndoManager()
        retainedUndoManager = undoManager
        viewModel.undoManager = undoManager

        XCTAssertTrue(viewModel.applyPageCrop(
            margins: PageCropMargins(top: 40, bottom: 30, left: 20, right: 10),
            to: [firstRef, secondRef]
        ))
        XCTAssertEqual(try cropBox(in: document.memberPDFData[firstMember.id]).width, 582, accuracy: 0.01)
        XCTAssertEqual(try cropBox(in: document.memberPDFData[secondMember.id]).width, 582, accuracy: 0.01)

        undoManager.undo()
        XCTAssertEqual(try cropBox(in: document.memberPDFData[firstMember.id]).width, 612, accuracy: 0.01)
        XCTAssertEqual(try cropBox(in: document.memberPDFData[secondMember.id]).width, 612, accuracy: 0.01)
        XCTAssertFalse(undoManager.canUndo, "one undo must restore every member in the crop transaction")
    }

    func testCropPreservesLabelsCatalogAndLiveStateThroughUndoRedoAndEditableReopen() throws {
        let viewModel = try makeLabeledViewModel()
        let ref = try XCTUnwrap(viewModel.document.workspace.pageOrder.first)
        let exactBefore = try XCTUnwrap(viewModel.document.memberPDFData[ref.memberDocId])
        let page = try XCTUnwrap(viewModel.loadedPDFs.first?.1.page(at: 0))
        let note = PDFAnnotation(bounds: CGRect(x: 40, y: 400, width: 80, height: 40), forType: .text, withProperties: nil)
        note.contents = "Unsaved crop note"
        page.addAnnotation(note)
        let widget = PDFAnnotation(bounds: CGRect(x: 40, y: 350, width: 120, height: 30), forType: .widget, withProperties: nil)
        widget.widgetFieldType = .text
        widget.fieldName = "Crop answer"
        widget.widgetStringValue = "Unsaved crop answer"
        page.addAnnotation(widget)
        page.rotation = 90
        let expectedBox = CGRect(x: 18, y: 24, width: 576, height: 744)

        XCTAssertTrue(viewModel.applyPageCrop(margins: PageCropMargins(top: 24, bottom: 24, left: 18, right: 18), to: [ref]))
        func assertCropped(_ model: WorkspaceViewModel) throws {
            let data = try XCTUnwrap(model.document.memberPDFData[ref.memberDocId])
            try assertLabeledCatalog(data)
            let cropped = try XCTUnwrap(PDFDocument(data: data)?.page(at: 0))
            assertBox(cropped.bounds(for: .cropBox), equals: expectedBox)
            XCTAssertEqual(cropped.rotation, 90)
            XCTAssertTrue(cropped.annotations.contains { $0.contents == "Unsaved crop note" })
            XCTAssertTrue(cropped.annotations.contains { $0.fieldName == "Crop answer" && $0.widgetStringValue == "Unsaved crop answer" })
            try assertLabeledCatalog(XCTUnwrap(model.currentPDFDataForOCR()[ref.memberDocId]))
            let visible = try XCTUnwrap(model.combinedPDF.page(at: 1))
            XCTAssertEqual(model.pageReference(for: visible, in: model.combinedPDF)?.label, "i")
        }
        try assertCropped(viewModel)
        viewModel.undoManager?.undo()
        XCTAssertEqual(viewModel.document.memberPDFData[ref.memberDocId], exactBefore)
        try assertLabeledCatalog(XCTUnwrap(viewModel.document.memberPDFData[ref.memberDocId]))
        let restoredVisible = try XCTUnwrap(viewModel.combinedPDF.page(at: 1))
        XCTAssertEqual(viewModel.pageReference(for: restoredVisible, in: viewModel.combinedPDF)?.label, "i")
        XCTAssertEqual(viewModel.loadedPDFs.first?.1.page(at: 0)?.rotation, 90)
        XCTAssertTrue(viewModel.loadedPDFs.first?.1.page(at: 0)?.annotations.contains { $0.contents == "Unsaved crop note" } == true)
        viewModel.undoManager?.redo()
        try assertCropped(viewModel)
        let snapshot = try viewModel.document.snapshot(contentType: .pdf)
        try assertLabeledCatalog(XCTUnwrap(snapshot.memberPDFData[ref.memberDocId]))
        let saved = try viewModel.document.savedFileWrapper(from: snapshot)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let reopened = try WorkspaceDocument(testingFile: saved, contentType: .pdf,
            fingerprintStore: WorkspaceFingerprintStore(directory: directory))
        try assertCropped(WorkspaceViewModel(document: reopened, processingEngine: PDFiumProcessingEngine()))
    }

    func testCropKeepsEachReplayLaneLabeledAndRollsBackLateFailureBeforeRetry() throws {
        let model = try makeLabeledViewModel()
        let ref = try XCTUnwrap(model.document.workspace.pageOrder.first)
        let image = try XCTUnwrap(model.objectMap(for: ref).objects.first { $0.objectType == .imageXObject })
        XCTAssertTrue(model.applyObjectEdit([transformOperation(image, pageRef: ref, memberID: ref.memberDocId, deltaX: 12, deltaY: -8)]))
        let beforeBytes = model.document.memberPDFData
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let beforeWorkspace = try encoder.encode(model.document.workspace)
        let undo = try XCTUnwrap(model.undoManager)
        undo.removeAllActions()
        var failedInputs: [Data] = []
        model.cropBoxTransformForTesting = { data, boxes in
            failedInputs.append(data)
            let output = QPDFService.settingCropBoxes(data, pageCropBoxes: boxes)
            return failedInputs.count == 3 ? nil : output
        }
        let margins = PageCropMargins(top: 24, bottom: 24, left: 18, right: 18)
        XCTAssertFalse(model.applyPageCrop(margins: margins, to: [ref]))
        XCTAssertEqual(failedInputs.count, 3, "live, pristine and object lanes must all be prepared")
        XCTAssertNotEqual(failedInputs.first, failedInputs.dropFirst().first, "baked live edits must not replace pristine content")
        XCTAssertEqual(model.document.memberPDFData, beforeBytes)
        XCTAssertEqual(try encoder.encode(model.document.workspace), beforeWorkspace)
        XCTAssertFalse(undo.canUndo)
        XCTAssertFalse(undo.canRedo)

        var retryInputs: [Data] = []
        var outputs: [Data] = []
        model.cropBoxTransformForTesting = { data, boxes in
            retryInputs.append(data)
            guard let output = QPDFService.settingCropBoxes(data, pageCropBoxes: boxes) else { return nil }
            outputs.append(output)
            return output
        }
        XCTAssertTrue(model.applyPageCrop(margins: margins, to: [ref]))
        // The live lane is serialized anew, so qpdf refreshes only its second trailer ID.
        // Pristine and object inputs must remain byte-for-byte identical.
        XCTAssertEqual(try pdfIgnoringUpdatedDocumentID(XCTUnwrap(retryInputs.first)),
                       try pdfIgnoringUpdatedDocumentID(XCTUnwrap(failedInputs.first)))
        XCTAssertEqual(Array(retryInputs.dropFirst()), Array(failedInputs.dropFirst()),
                       "failure must retain exact pristine and object inputs for retry")
        XCTAssertEqual(outputs.count, 3)
        for output in outputs {
            try assertLabeledCatalog(output)
            assertBox(try cropBox(in: output), equals: CGRect(x: 18, y: 24, width: 576, height: 744))
        }
        undo.undo()
        XCTAssertEqual(model.document.memberPDFData, beforeBytes)
        undo.redo()
        let movedImage = try XCTUnwrap(model.objectMap(for: ref).objects.first { $0.objectType == .imageXObject })
        XCTAssertTrue(model.applyObjectEdit([transformOperation(movedImage, pageRef: ref, memberID: ref.memberDocId, deltaX: 6, deltaY: -4)]))
        let replayed = try XCTUnwrap(model.document.memberPDFData[ref.memberDocId])
        try assertLabeledCatalog(replayed)
        assertBox(try cropBox(in: replayed), equals: CGRect(x: 18, y: 24, width: 576, height: 744))
        let snapshot = try model.document.snapshot(contentType: .pdf)
        try assertLabeledCatalog(XCTUnwrap(snapshot.originalMemberPDFData[ref.memberDocId]))
        try assertLabeledCatalog(XCTUnwrap(snapshot.memberPDFData[ref.memberDocId]))
    }

    func testLabelGraftPreservesDestinationOutlineAndRejectsDifferentPageCounts() throws {
        let model = try makeLabeledViewModel()
        let canonical = try XCTUnwrap(model.document.memberPDFData.values.first)
        let pdf = try XCTUnwrap(PDFDocument(data: canonical))
        PDFOutlineBuilder.apply([PDFOutlineReader.OutlineNode(title: "Edited destination", depth: 0, localPageIndex: 2, hasChildren: false)], to: pdf)
        let serialized = try XCTUnwrap(PDFSerializer.data(from: pdf))
        XCTAssertFalse(QPDFService.hasPageLabels(serialized))
        let output = try XCTUnwrap(QPDFService.preservingPageLabels(in: serialized, from: canonical))
        let result = try XCTUnwrap(PDFDocument(data: output))
        XCTAssertEqual((0..<result.pageCount).map { result.page(at: $0)?.label }, ["i", "ii", "1", "A-7"])
        XCTAssertEqual(PDFOutlineReader.nodes(in: result).map(\.title), ["Edited destination"])
        XCTAssertEqual(PDFOutlineReader.nodes(in: result).map(\.localPageIndex), [2])
        XCTAssertNil(QPDFService.preservingPageLabels(in: makeSinglePagePDF(), from: canonical))
        XCTAssertNil(QPDFService.preservingPageLabels(in: serialized, from: Data("invalid".utf8)))
        XCTAssertNil(QPDFService.preservingPageLabels(in: Data("invalid".utf8), from: canonical))
        let unlabeled = try XCTUnwrap(QPDFService.preservingPageLabels(in: canonical, from: serialized))
        XCTAssertFalse(QPDFService.hasPageLabels(unlabeled))
    }

}

private extension PageCropTests {
    func makeLabeledViewModel() throws -> WorkspaceViewModel {
        let fixtureURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/page-labels.pdf")
        let labeled = try XCTUnwrap(QPDFService.replacingPageContent(in: Data(contentsOf: fixtureURL),
            pageIndex: 0, with: makeSinglePagePDF()))
        let titled = try PDFMetadataService.write(PDFDocumentMetadata(title: "Crop catalog"), to: labeled)
        let source = try AttachmentsService.add(Data("Exact crop payload".utf8), name: "crop-proof.txt", mimeType: "text/plain", to: titled)
        let document = WorkspaceDocument()
        var member = MemberDocument(displayName: "Labeled crop", sourcePDFRef: "crop.pdf")
        let refs = (0..<4).map { PageRef(memberDocId: member.id, sourcePageIndex: $0) }
        member.pageRefs = refs.map(\.id)
        document.workspace.documents = [member]
        document.workspace.pageOrder = refs
        document.memberPDFData[member.id] = source
        let model = WorkspaceViewModel(document: document, processingEngine: PDFiumProcessingEngine())
        let undo = UndoManager()
        undo.groupsByEvent = false
        retainedUndoManager = undo
        model.undoManager = undo
        return model
    }

    func assertLabeledCatalog(_ data: Data) throws {
        XCTAssertTrue(QPDFService.hasPageLabels(data))
        let pdf = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertEqual((0..<pdf.pageCount).map { pdf.page(at: $0)?.label }, ["i", "ii", "1", "A-7"])
        XCTAssertEqual(try PDFMetadataService.read(from: data).title, "Crop catalog")
        XCTAssertEqual(try AttachmentsService.extract("crop-proof.txt", from: data), Data("Exact crop payload".utf8))
    }

    func makeViewModel() throws -> WorkspaceViewModel {
        try makeViewModel(pdfData: makeSinglePagePDF())
    }

    func makeViewModel(pdfData: Data) throws -> WorkspaceViewModel {
        let wrapper = FileWrapper(regularFileWithContents: pdfData)
        wrapper.preferredFilename = "crop.pdf"
        let document = try WorkspaceDocument(
            testingFile: wrapper,
            contentType: .pdf,
            filename: "crop.pdf"
        )
        let viewModel = WorkspaceViewModel(document: document, processingEngine: PDFiumProcessingEngine())
        let undoManager = UndoManager()
        retainedUndoManager = undoManager
        viewModel.undoManager = undoManager
        return viewModel
    }

    func makeMarkdownViewModel() throws -> WorkspaceViewModel {
        let source = Data("# Wave 6\n\nCrop source protection".utf8)
        let imported = try DocumentImportConverter.importedDocument(
            from: source,
            contentType: .markdown,
            filename: "wave6.md",
            baseURL: nil
        )
        let pdfData = try XCTUnwrap(PDFSerializer.data(from: imported.pdfDocument))
        var member = MemberDocument(displayName: "wave6", sourcePDFRef: "wave6.md")
        let refs = (0..<imported.pdfDocument.pageCount).map {
            PageRef(memberDocId: member.id, sourcePageIndex: $0)
        }
        member.pageRefs = refs.map(\.id)
        let document = WorkspaceDocument()
        document.workspace.documents = [member]
        document.workspace.pageOrder = refs
        document.memberPDFData[member.id] = pdfData
        document.sourcePayloads[member.id] = try XCTUnwrap(imported.sourcePayload)
        return WorkspaceViewModel(
            document: document,
            processingEngine: PDFKitProcessingEngineFallback()
        )
    }

    func cropBox(in data: Data?) throws -> CGRect {
        try XCTUnwrap(PDFDocument(data: try XCTUnwrap(data))?.page(at: 0)).bounds(for: .cropBox)
    }

    func assertBox(
        _ actual: CGRect,
        equals expected: CGRect,
        _ message: String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual.minX, expected.minX, accuracy: 0.01, message, file: file, line: line)
        XCTAssertEqual(actual.minY, expected.minY, accuracy: 0.01, message, file: file, line: line)
        XCTAssertEqual(actual.width, expected.width, accuracy: 0.01, message, file: file, line: line)
        XCTAssertEqual(actual.height, expected.height, accuracy: 0.01, message, file: file, line: line)
    }

    func transformOperation(
        _ object: DetectedObject,
        pageRef: PageRef,
        memberID: UUID,
        deltaX: CGFloat,
        deltaY: CGFloat
    ) -> ObjectEditOperation {
        var transform = object.transform
        transform.e += deltaX
        transform.f += deltaY
        return ObjectEditOperation(
            type: .objectTransform,
            documentID: memberID,
            pageRefID: pageRef.id,
            sourceObjectKey: object.stableKey,
            objectType: object.objectType,
            editability: object.editability,
            originalBoundsPdf: object.boundsPdf,
            newBoundsPdf: object.boundsPdf.offsetBy(dx: deltaX, dy: deltaY),
            originalTransform: object.transform,
            newTransform: transform,
            pageRotation: Int(object.pageRotation),
            originalZIndex: object.zOrder,
            newZIndex: object.zOrder,
            replacementStrategy: .pdfiumStructural
        )
    }

    func makeSinglePagePDF() -> Data {
        let data = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        let consumer = CGDataConsumer(data: data as CFMutableData)!
        let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)!
        context.beginPDFPage(nil)
        context.setFillColor(NSColor.white.cgColor)
        context.fill(mediaBox)
        let bitmap = CGContext(
            data: nil,
            width: 16,
            height: 16,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        bitmap.setFillColor(NSColor.systemBlue.cgColor)
        bitmap.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
        context.draw(bitmap.makeImage()!, in: CGRect(x: 180, y: 300, width: 80, height: 80))
        context.endPDFPage()
        context.closePDF()
        return data as Data
    }
}
