import AppKit
import CoreText
import PDFKit
import XCTest
@testable import Orifold

@MainActor
final class StructuralCatalogPreservationTests: XCTestCase {
    private let metadata = PDFDocumentMetadata(title: "折り紙", author: "うまん", subject: "विषय", keywords: "标签")
    private let payload = Data("fictional attachment\0exact".utf8)
    private var directories: [URL] = []
    private var retainedUndo: UndoManager?

    override func tearDown() {
        directories.forEach { try? FileManager.default.removeItem(at: $0) }
        super.tearDown()
    }

    func testStructuralChangesThenObjectOrTextReplayPreserveInfoAndAttachmentThroughUndoSaveExportAndReopen() throws {
        for operation in ["reorder", "duplicate", "delete"] {
            for edit in ["object", "text"] {
                let vm = try model()
                XCTAssertTrue(vm.applyMetadataEdit(metadata))
                let attachment = try directory().appendingPathComponent("fictional.txt")
                try payload.write(to: attachment)
                XCTAssertTrue(vm.addAttachment(attachment))
                let initial = vm.document.workspace.pageOrder
                let undo = try XCTUnwrap(retainedUndo)
                undo.beginUndoGrouping()
                if operation == "reorder" { XCTAssertTrue(vm.movePage(initial[0], toIndex: 3)) }
                if operation == "duplicate" { vm.duplicatePages([initial[0]]) }
                if operation == "delete" { vm.deletePage(initial[0]) }
                undo.endUndoGrouping()
                let ref = try XCTUnwrap(vm.document.workspace.pageOrder.first)
                if edit == "object" {
                    let object = try XCTUnwrap(vm.objectMap(for: ref).objects.first {
                        ($0.objectType == .rectangle || $0.objectType == .filledShape) && $0.boundsPdf.width < 300
                    })
                    var transform = object.transform
                    transform.e += 15
                    XCTAssertTrue(vm.applyObjectEdit([ObjectEditOperation(
                        type: .objectTransform, documentID: ref.memberDocId, pageRefID: ref.id,
                        sourceObjectKey: object.stableKey, objectType: object.objectType, editability: object.editability,
                        originalBoundsPdf: object.boundsPdf, newBoundsPdf: object.boundsPdf.offsetBy(dx: 15, dy: 0),
                        originalTransform: object.transform, newTransform: transform, pageRotation: Int(object.pageRotation),
                        originalZIndex: object.zOrder, newZIndex: object.zOrder, replacementStrategy: .pdfiumStructural
                    )]))
                    XCTAssertTrue(vm.objectMap(for: ref).objects.contains {
                        abs($0.boundsPdf.minX - (object.boundsPdf.minX + 15)) < 2
                    })
                } else {
                    let page = try XCTUnwrap(vm.loadedPDFs.first?.1.page(at: ref.sourcePageIndex))
                    let analysis = PDFTextAnalysisEngine().analyze(
                        data: try XCTUnwrap(vm.document.memberPDFData[ref.memberDocId]), pageIndex: ref.sourcePageIndex,
                        pageRefID: ref.id, fallbackPage: page
                    )
                    let block = try XCTUnwrap(analysis.blocks.first { $0.text.contains("Fictional") })
                    let target = try XCTUnwrap(vm.editableTextBlock(
                        at: CGPoint(x: block.bounds.midX, y: block.bounds.midY), on: page, in: vm.combinedPDF
                    ))
                    XCTAssertTrue(vm.applyInlineTextEdit(
                        pageRef: target.pageRef, sourceBlock: target.block, replacementText: "Fictional replacement",
                        editedBounds: target.block.bounds, fontName: target.block.fontName, fontSize: target.block.fontSize,
                        textColor: .black, alignment: .left
                    ))
                    XCTAssertTrue(PDFTextAnalysisEngine.readingOrderText(
                        data: try XCTUnwrap(vm.document.memberPDFData[ref.memberDocId]), pageIndex: ref.sourcePageIndex
                    ).contains("Fictional replacement"))
                }
                try assertCatalog(try XCTUnwrap(vm.document.memberPDFData[ref.memberDocId]))
                undo.undo()
                try assertCatalog(try XCTUnwrap(vm.document.memberPDFData[ref.memberDocId]))
                undo.undo()
                XCTAssertEqual(vm.document.workspace.pageOrder.map(\.id), initial.map(\.id))
                try assertCatalog(try XCTUnwrap(vm.document.memberPDFData[ref.memberDocId]))
                undo.redo()
                undo.redo()
                try assertCatalog(try XCTUnwrap(vm.document.memberPDFData[ref.memberDocId]))
                XCTAssertEqual(vm.hasObjectEdits, edit == "object")
                XCTAssertEqual(vm.hasInlineTextEdits, edit == "text")
                let saved = try vm.document.savedFileWrapper(from: vm.document.snapshot(contentType: .pdf))
                try assertCatalog(try XCTUnwrap(saved.regularFileContents))
                let reopened = try WorkspaceDocument(testingFile: saved, contentType: .pdf,
                    fingerprintStore: WorkspaceFingerprintStore(directory: try directory()))
                try assertCatalog(try XCTUnwrap(reopened.memberPDFData[ref.memberDocId]))
                let exported = try vm.dataForPDFExport()
                try assertCatalog(exported)
                let flat = try WorkspaceDocument(testingFile: FileWrapper(regularFileWithContents: exported), contentType: .pdf,
                    fingerprintStore: WorkspaceFingerprintStore(directory: try directory()))
                XCTAssertEqual(try PDFMetadataService.read(from: XCTUnwrap(flat.memberPDFData.values.first)), metadata)
                // Flat import deliberately strips embedded files; editable reopen above retains them.
                XCTAssertEqual(try AttachmentsService.list(in: XCTUnwrap(flat.memberPDFData.values.first)), [])
                let sanitized = try vm.dataForPDFExport(options: WorkspaceExportOptions(
                    sanitization: PDFSanitizationOptions(removesMetadata: true)
                ))
                XCTAssertEqual(try PDFMetadataService.read(from: sanitized), PDFDocumentMetadata())
                XCTAssertEqual(try AttachmentsService.list(in: sanitized), [])
            }
        }
    }

    func testFailedCanonicalRealignmentRollsBackStructureBytesSelectionsDirtyDateAndUndo() throws {
        for operation in ["reorder", "duplicate", "delete", "delete-batch"] {
            let vm = try model(invalidPristine: true)
            let refs = vm.document.workspace.pageOrder
            let undo = try XCTUnwrap(retainedUndo)
            vm.selectedPageRefID = refs[0].id
            vm.selectedPageRefIDs = [refs[0].id, refs[1].id]
            let decoration = PageDecoration(kind: .hanko, text: "Fictional", pageRefID: refs[0].id,
                                             rect: CGRect(x: 90, y: 300, width: 100, height: 60))
            vm.document.workspace.decorations = [decoration]
            vm.selectedStampDecorationID = decoration.id
            vm.document.workspace.comments = [WorkspaceComment(body: "Fictional", anchor: WorkspaceCommentAnchor(
                pageRefID: refs[0].id, rect: CGRect(x: 72, y: 700, width: 80, height: 20), kind: .text
            ))]
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            let before = try encoder.encode(vm.document.workspace)
            let bytes = vm.document.memberPDFData
            let commentRevision = vm.commentRevision
            let decorationRevision = vm.decorationStateVersion
            if operation == "reorder" { XCTAssertFalse(vm.movePage(refs[0], toIndex: 3)) }
            if operation == "duplicate" { vm.duplicatePages([refs[0]]) }
            if operation == "delete" { vm.deletePage(refs[0]) }
            if operation == "delete-batch" { vm.deletePages([refs[0], refs[1]]) }
            XCTAssertEqual(try encoder.encode(vm.document.workspace), before)
            XCTAssertEqual(vm.document.memberPDFData, bytes)
            XCTAssertEqual(vm.selectedPageRefID, refs[0].id)
            XCTAssertEqual(vm.selectedPageRefIDs, [refs[0].id, refs[1].id])
            XCTAssertEqual(vm.selectedStampDecorationID, decoration.id)
            XCTAssertEqual(vm.commentRevision, commentRevision)
            XCTAssertEqual(vm.decorationStateVersion, decorationRevision)
            XCTAssertEqual(vm.editingStatus?.message, PDFTextEditWarning.serializationFailed.message)
            XCTAssertFalse(undo.canUndo)
            XCTAssertFalse(undo.canRedo)
        }
    }

    func testCanonicalCatalogGraftRejectsUnreadableSourceOrDestination() throws {
        let valid = try fixture()
        XCTAssertNil(QPDFService.preservingCanonicalMetadataAndAttachments(in: valid, from: Data("invalid".utf8)))
        XCTAssertNil(QPDFService.preservingCanonicalMetadataAndAttachments(in: Data("invalid".utf8), from: valid))
    }

    func testLateStructuralLaneFailureRestoresBytesRefsEditsAndUndoBeforeRetry() throws {
        for operation in ["reorder", "duplicate", "delete", "delete-batch"] {
            let vm = try model()
            let ref = try XCTUnwrap(vm.document.workspace.pageOrder.first)
            let object = try XCTUnwrap(vm.objectMap(for: ref).objects.first {
                ($0.objectType == .rectangle || $0.objectType == .filledShape) && $0.boundsPdf.width < 300
            })
            var transform = object.transform
            transform.e += 15
            XCTAssertTrue(vm.applyObjectEdit([ObjectEditOperation(
                type: .objectTransform, documentID: ref.memberDocId, pageRefID: ref.id,
                sourceObjectKey: object.stableKey, objectType: object.objectType, editability: object.editability,
                originalBoundsPdf: object.boundsPdf, newBoundsPdf: object.boundsPdf.offsetBy(dx: 15, dy: 0),
                originalTransform: object.transform, newTransform: transform, pageRotation: Int(object.pageRotation),
                originalZIndex: object.zOrder, newZIndex: object.zOrder, replacementStrategy: .pdfiumStructural
            )]))
            let refs = vm.document.workspace.pageOrder
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            let beforeWorkspace = try encoder.encode(vm.document.workspace)
            let beforeBytes = vm.document.memberPDFData
            let undo = try XCTUnwrap(retainedUndo)
            undo.removeAllActions()
            var failedInputs: [Data] = []
            vm.structuralPageTransformForTesting = { data, indexes in
                failedInputs.append(data)
                let prepared = QPDFService.selectingPages(data, pageIndices: indexes)
                return failedInputs.count == 3 ? nil : prepared
            }
            func perform(groupsUndo: Bool = false) {
                if groupsUndo { undo.beginUndoGrouping() }
                defer { if groupsUndo { undo.endUndoGrouping() } }
                switch operation {
                case "reorder": _ = vm.movePage(refs[0], toIndex: 3)
                case "duplicate": vm.duplicatePages([refs[0]])
                case "delete": vm.deletePage(refs[0])
                default: vm.deletePages([refs[0], refs[1]])
                }
            }
            perform()
            XCTAssertEqual(failedInputs.count, 3, "live, pristine and object lanes must each be prepared")
            XCTAssertNotEqual(failedInputs.first, failedInputs.dropFirst().first, "live edits must not replace the pristine lane")
            XCTAssertEqual(vm.document.memberPDFData, beforeBytes)
            XCTAssertEqual(try encoder.encode(vm.document.workspace), beforeWorkspace)
            XCTAssertFalse(undo.canUndo)
            XCTAssertFalse(undo.canRedo)
            XCTAssertEqual(vm.editingStatus?.message, PDFTextEditWarning.serializationFailed.message)

            var retryInputs: [Data] = []
            vm.structuralPageTransformForTesting = { data, indexes in
                retryInputs.append(data)
                return QPDFService.selectingPages(data, pageIndices: indexes)
            }
            perform(groupsUndo: true)
            XCTAssertEqual(retryInputs, failedInputs, "rollback must retain the exact bytes of all three independent lanes")
            XCTAssertNotEqual(try encoder.encode(vm.document.workspace), beforeWorkspace)
            XCTAssertNoThrow(try vm.currentPDFDataForOCR())
        }
    }

    func testPageSelectionPreservesSourceLabelsAndCatalogAcrossDuplicates() throws {
        let labeled = try Data(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/page-labels.pdf"))
        let titled = try PDFMetadataService.write(metadata, to: labeled)
        let source = try AttachmentsService.add(payload, name: "fictional.txt", mimeType: "text/plain", to: titled)
        let output = try XCTUnwrap(QPDFService.selectingPages(source, pageIndices: [3, 0, 0]))
        let pdf = try XCTUnwrap(PDFDocument(data: output))
        XCTAssertEqual(pdf.pageCount, 3)
        XCTAssertEqual(pdf.page(at: 0)?.label, "A-7")
        XCTAssertEqual(pdf.page(at: 1)?.label, "i")
        XCTAssertEqual(pdf.page(at: 2)?.label, "i")
        try assertCatalog(output)
        XCTAssertTrue(QPDFService.isStructurallySound(output))
        for indexes in [[], [-1], [4], [Int.max]] {
            XCTAssertNil(QPDFService.selectingPages(source, pageIndices: indexes))
        }
        XCTAssertNil(QPDFService.selectingPages(Data("invalid".utf8), pageIndices: [0]))
    }

    func testCrossMemberMovePreparesCanonicalLayoutsCatalogsUndoAndEditableReopen() throws {
        for sourcePageCount in [1, 2] {
            let vm = try crossMemberModel(sourcePageCount: sourcePageCount, includeSourceAttachment: sourcePageCount > 1)
            let initialRefs = vm.document.workspace.pageOrder
            let sourceID = initialRefs[0].memberDocId
            let targetRef = initialRefs[sourcePageCount]
            let initialBytes = vm.document.memberPDFData
            let undo = try XCTUnwrap(retainedUndo)
            undo.beginUndoGrouping()
            XCTAssertTrue(vm.movePage(initialRefs[0], after: targetRef))
            undo.endUndoGrouping()

            func assertMoved(_ model: WorkspaceViewModel) throws {
                let prepared = try model.currentPDFDataForOCR()
                let target = try XCTUnwrap(prepared[targetRef.memberDocId])
                XCTAssertEqual(PDFDocument(data: target)?.pageCount, 4)
                for (index, token) in ["Target page 0", "Source page 0", "Target page 1", "Target page 2"].enumerated() {
                    XCTAssertTrue(PDFTextAnalysisEngine.readingOrderText(data: target, pageIndex: index).contains(token))
                }
                for member in model.document.workspace.documents {
                    let role = member.id == sourceID ? "Source" : "Target"
                    let bytes = try XCTUnwrap(model.document.memberPDFData[member.id])
                    XCTAssertEqual(try PDFMetadataService.read(from: bytes).title, role)
                    XCTAssertEqual(try AttachmentsService.extract("\(role).txt", from: bytes), Data(role.utf8))
                }
                if sourcePageCount == 2 {
                    XCTAssertTrue(PDFTextAnalysisEngine.readingOrderText(data: try XCTUnwrap(prepared[sourceID]), pageIndex: 0).contains("Source page 1"))
                } else {
                    XCTAssertNil(prepared[sourceID])
                }
            }
            try assertMoved(vm)
            undo.undo()
            XCTAssertEqual(vm.document.memberPDFData, initialBytes, "undo restores exact canonical bytes")
            XCTAssertEqual(vm.document.workspace.pageOrder.map(\.id), initialRefs.map(\.id))
            undo.redo()
            try assertMoved(vm)
            let saved = try vm.document.savedFileWrapper(from: vm.document.snapshot(contentType: .pdf))
            let reopened = try WorkspaceDocument(testingFile: saved, contentType: .pdf,
                fingerprintStore: WorkspaceFingerprintStore(directory: try directory()))
            try assertMoved(WorkspaceViewModel(document: reopened, processingEngine: PDFiumProcessingEngine()))
        }
    }

    func testLastSourcePageWithAttachmentsRefusesBeforeMutationAndPreservesExistingUndoOrRedo() throws {
        final class UndoProbe { var value = 1 }
        for name in ["Source.txt", "Target.txt"] {
            for sourceComesFirst in [true, false] {
                for history in ["undo", "redo"] {
                    let vm = try crossMemberModel(sourcePageCount: 1, sourceAttachmentName: name)
                    let undo = try XCTUnwrap(retainedUndo)
                    if !sourceComesFirst { vm.moveDocument(from: IndexSet(integer: 0), to: 2) }
                    undo.removeAllActions()
                    undo.groupsByEvent = false
                    let source = try XCTUnwrap(vm.document.workspace.documents.first { $0.displayName == "Source" })
                    let target = try XCTUnwrap(vm.document.workspace.documents.first { $0.displayName == "Target" })
                    let sourceRef = try XCTUnwrap(vm.workspacePageRef(XCTUnwrap(source.pageRefs.first)))
                    let targetRef = try XCTUnwrap(vm.workspacePageRef(XCTUnwrap(target.pageRefs.first)))
                    vm.selectedPageRefID = sourceRef.id
                    vm.selectedPageRefIDs = [sourceRef.id, targetRef.id]
                    let decoration = PageDecoration(kind: .hanko, text: "Fictional", pageRefID: sourceRef.id,
                        rect: CGRect(x: 90, y: 300, width: 100, height: 60))
                    vm.document.workspace.decorations = [decoration]
                    vm.selectedStampDecorationID = decoration.id
                    vm.document.sourcePayloads[source.id] = SourceDocumentPayload(
                        format: .plainText, originalFilename: "fictional.txt", originalContentTypeIdentifier: "public.plain-text",
                        originalData: Data("Fictional source".utf8), plainText: "Fictional source", renderedPageCount: 1)
                    let probe = UndoProbe()
                    undo.beginUndoGrouping()
                    undo.registerUndo(withTarget: probe) { probe in
                        probe.value = 0
                        undo.registerUndo(withTarget: probe) { $0.value = 1 }
                    }
                    undo.setActionName("Existing fictional edit")
                    undo.endUndoGrouping()
                    if history == "redo" { undo.undo() }
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = .sortedKeys
                    let beforeWorkspace = try encoder.encode(vm.document.workspace)
                    let beforeBytes = vm.document.memberPDFData
                    let beforePayloads = try encoder.encode(vm.document.sourcePayloads)
                    let beforeOriginals = vm.document.currentOriginalPDFDataProvider?()
                    let loadedObjects = vm.loadedPDFs.map { ObjectIdentifier($0.1) }
                    let combinedObject = ObjectIdentifier(vm.combinedPDF)
                    let beforeCanUndo = undo.canUndo
                    let beforeCanRedo = undo.canRedo
                    let beforeUndoName = undo.undoActionName
                    let beforeRedoName = undo.redoActionName

                    XCTAssertFalse(vm.movePage(sourceRef, after: targetRef))

                    XCTAssertEqual(try encoder.encode(vm.document.workspace), beforeWorkspace)
                    XCTAssertEqual(vm.document.memberPDFData, beforeBytes)
                    XCTAssertEqual(try encoder.encode(vm.document.sourcePayloads), beforePayloads)
                    XCTAssertEqual(vm.document.currentOriginalPDFDataProvider?(), beforeOriginals)
                    XCTAssertEqual(vm.loadedPDFs.map { ObjectIdentifier($0.1) }, loadedObjects)
                    XCTAssertEqual(ObjectIdentifier(vm.combinedPDF), combinedObject)
                    XCTAssertEqual(vm.selectedPageRefID, sourceRef.id)
                    XCTAssertEqual(vm.selectedPageRefIDs, [sourceRef.id, targetRef.id])
                    XCTAssertEqual(vm.selectedStampDecorationID, decoration.id)
                    XCTAssertEqual(undo.canUndo, beforeCanUndo)
                    XCTAssertEqual(undo.canRedo, beforeCanRedo)
                    XCTAssertEqual(undo.undoActionName, beforeUndoName)
                    XCTAssertEqual(undo.redoActionName, beforeRedoName)
                    XCTAssertEqual(vm.editingStatus?.message, L10n.string("status.pageMove.lastPageAttachments"))
                    XCTAssertEqual(try AttachmentsService.extract(name, from: XCTUnwrap(vm.document.memberPDFData[source.id])), Data("Source".utf8))
                    XCTAssertEqual(try AttachmentsService.extract("Target.txt", from: XCTUnwrap(vm.document.memberPDFData[target.id])), Data("Target".utf8))
                    if history == "redo" {
                        undo.redo()
                        XCTAssertEqual(probe.value, 1)
                    } else {
                        undo.undo()
                        XCTAssertEqual(probe.value, 0)
                    }
                }
            }
        }
    }

    func testLastSourcePageRefusesUnreadableAttachmentInventoryBeforeSnapshotAndAllowsRetry() throws {
        let vm = try crossMemberModel(sourcePageCount: 1, includeSourceAttachment: false)
        let refs = vm.document.workspace.pageOrder
        let sourceID = refs[0].memberDocId
        let validSource = try XCTUnwrap(vm.document.memberPDFData[sourceID])
        vm.document.memberPDFData[sourceID] = Data("invalid attachment inventory".utf8)
        let beforeBytes = vm.document.memberPDFData
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let beforeWorkspace = try encoder.encode(vm.document.workspace)
        let loadedObjects = vm.loadedPDFs.map { ObjectIdentifier($0.1) }
        let combinedObject = ObjectIdentifier(vm.combinedPDF)

        XCTAssertFalse(vm.movePage(refs[0], after: refs[1]))

        XCTAssertEqual(vm.document.memberPDFData, beforeBytes)
        XCTAssertEqual(try encoder.encode(vm.document.workspace), beforeWorkspace)
        XCTAssertEqual(vm.loadedPDFs.map { ObjectIdentifier($0.1) }, loadedObjects)
        XCTAssertEqual(ObjectIdentifier(vm.combinedPDF), combinedObject)
        XCTAssertFalse(try XCTUnwrap(retainedUndo).canUndo)
        XCTAssertEqual(vm.editingStatus?.message, L10n.string("status.pageMove.attachmentCheckFailed"))
        vm.document.memberPDFData[sourceID] = validSource
        XCTAssertTrue(vm.movePage(refs[0], after: refs[1]))
        XCTAssertEqual(try AttachmentsService.extract("Target.txt", from: XCTUnwrap(vm.document.memberPDFData[refs[1].memberDocId])), Data("Target".utf8))
        XCTAssertEqual(try AttachmentsService.extract("Target.txt", from: vm.dataForPDFExport()), Data("Target".utf8))
    }

    func testLastSourcePageRefusesLoadableUninspectableAttachmentCatalogsBeforeMutation() throws {
        final class UndoProbe { var value = 1 }
        for catalog in ["invalid-root-names", "invalid-embedded-files", "invalid-leaf", "invalid-kids", "odd-leaf", "deep-tree", "empty-tree"] {
            for history in ["undo", "redo"] {
                let data = try attachmentCatalogFixture(catalog)
                XCTAssertNotNil(PDFDocument(data: data), catalog)
                XCTAssertEqual(QPDFService.hasAcroForm(data), false, catalog)
                XCTAssertEqual(try AttachmentsService.list(in: data), [], "best-effort inventory cannot establish absence: \(catalog)")
                let vm = try crossMemberModel(sourcePageCount: 1, sourceData: data, includeSourceAttachment: false)
                let refs = vm.document.workspace.pageOrder
                let undo = try XCTUnwrap(retainedUndo)
                undo.groupsByEvent = false
                vm.selectedPageRefID = refs[0].id
                vm.selectedPageRefIDs = [refs[0].id, refs[1].id]
                vm.document.sourcePayloads[refs[0].memberDocId] = SourceDocumentPayload(
                    format: .plainText, originalFilename: "fictional.txt", originalContentTypeIdentifier: "public.plain-text",
                    originalData: Data("Fictional source".utf8), plainText: "Fictional source", renderedPageCount: 1)
                let probe = UndoProbe()
                undo.beginUndoGrouping()
                undo.registerUndo(withTarget: probe) { probe in
                    probe.value = 0
                    undo.registerUndo(withTarget: probe) { $0.value = 1 }
                }
                undo.setActionName("Existing fictional edit")
                undo.endUndoGrouping()
                if history == "redo" { undo.undo() }
                undo.groupsByEvent = true
                let encoder = JSONEncoder()
                encoder.outputFormatting = .sortedKeys
                let beforeWorkspace = try encoder.encode(vm.document.workspace)
                let beforeBytes = vm.document.memberPDFData
                let beforePayloads = try encoder.encode(vm.document.sourcePayloads)
                let loadedObjects = vm.loadedPDFs.map { ObjectIdentifier($0.1) }
                let combinedObject = ObjectIdentifier(vm.combinedPDF)
                let beforeHistory = [undo.canUndo, undo.canRedo]
                let beforeNames = [undo.undoActionName, undo.redoActionName]

                XCTAssertFalse(vm.movePage(refs[0], after: refs[1]), catalog)

                XCTAssertEqual(try encoder.encode(vm.document.workspace), beforeWorkspace, catalog)
                XCTAssertEqual(vm.document.memberPDFData, beforeBytes, catalog)
                XCTAssertEqual(try encoder.encode(vm.document.sourcePayloads), beforePayloads, catalog)
                XCTAssertEqual(vm.loadedPDFs.map { ObjectIdentifier($0.1) }, loadedObjects, catalog)
                XCTAssertEqual(ObjectIdentifier(vm.combinedPDF), combinedObject, catalog)
                XCTAssertEqual(vm.selectedPageRefID, refs[0].id, catalog)
                XCTAssertEqual(vm.selectedPageRefIDs, [refs[0].id, refs[1].id], catalog)
                XCTAssertEqual([undo.canUndo, undo.canRedo], beforeHistory, catalog)
                XCTAssertEqual([undo.undoActionName, undo.redoActionName], beforeNames, catalog)
                let warningKey = catalog == "invalid-root-names"
                    ? "status.pageMove.attachmentCheckFailed" : "status.pageMove.lastPageAttachments"
                XCTAssertEqual(vm.editingStatus?.message, L10n.string(forKey: warningKey), catalog)
                if history == "redo" { undo.redo(); XCTAssertEqual(probe.value, 1, catalog) }
                else { undo.undo(); XCTAssertEqual(probe.value, 0, catalog) }
            }
        }
    }

    func testLastSourcePageMovesWhenAttachmentCatalogAbsenceIsProven() throws {
        for catalog in ["absent-names", "empty-names", "unrelated-names"] {
            let vm = try crossMemberModel(sourcePageCount: 1,
                sourceData: attachmentCatalogFixture(catalog), includeSourceAttachment: false)
            let refs = vm.document.workspace.pageOrder
            XCTAssertTrue(vm.movePage(refs[0], after: refs[1]), catalog)
            XCTAssertEqual(vm.document.workspace.documents.count, 1, catalog)
            XCTAssertEqual(try AttachmentsService.extract("Target.txt", from: vm.dataForPDFExport()), Data("Target".utf8), catalog)
        }
    }

    func testCrossMemberMoveCanImmediatelyRedactOrCleanTheMovedPage() async throws {
        for consumer in ["redaction", "cleanup"] {
            let vm = try crossMemberModel(sourcePageCount: 2)
            let refs = vm.document.workspace.pageOrder
            XCTAssertTrue(vm.movePage(refs[0], after: refs[2]))
            let moved = try XCTUnwrap(vm.workspacePageRef(refs[0].id))
            let neighborBefore = PDFTextAnalysisEngine.readingOrderText(
                data: try XCTUnwrap(vm.document.memberPDFData[moved.memberDocId]), pageIndex: 0)
            if consumer == "redaction" {
                vm.addRedactionMark(rect: CGRect(x: 0, y: 0, width: 612, height: 792), pageRefID: moved.id)
                XCTAssertTrue(vm.applyRedactions())
            } else {
                let succeeded = await vm.applyScanCleanup(pageRefIDs: [moved.id],
                    options: ScanCleanupOptions(deskew: false, binarize: true, despeckle: false))
                XCTAssertTrue(succeeded)
            }
            let bytes = try XCTUnwrap(vm.document.memberPDFData[moved.memberDocId])
            XCTAssertFalse(PDFTextAnalysisEngine.readingOrderText(data: bytes, pageIndex: 1).contains("Source page 0"))
            XCTAssertEqual(PDFTextAnalysisEngine.readingOrderText(data: bytes, pageIndex: 0), neighborBefore)
            XCTAssertEqual(try AttachmentsService.extract("Target.txt", from: bytes), Data("Target".utf8))
            XCTAssertNoThrow(try vm.currentPDFDataForOCR())
        }
    }

    func testCrossMemberPreparationFailurePreservesBothMembersAndUndoBeforeRetry() throws {
        let vm = try crossMemberModel(sourcePageCount: 2)
        let refs = vm.document.workspace.pageOrder
        let targetID = refs[2].memberDocId
        let targetBytes = try XCTUnwrap(vm.document.memberPDFData[targetID])
        vm.document.memberPDFData[targetID] = Data("invalid target".utf8)
        let beforeBytes = vm.document.memberPDFData
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let beforeWorkspace = try encoder.encode(vm.document.workspace)
        XCTAssertFalse(vm.movePage(refs[0], after: refs[2]))
        XCTAssertEqual(try encoder.encode(vm.document.workspace), beforeWorkspace)
        XCTAssertEqual(vm.document.memberPDFData, beforeBytes)
        XCTAssertEqual(vm.loadedPDFs.map { $0.1.pageCount }, [2, 3])
        XCTAssertFalse(try XCTUnwrap(retainedUndo).canUndo)
        vm.document.memberPDFData[targetID] = targetBytes
        XCTAssertTrue(vm.movePage(refs[0], after: refs[2]))
        XCTAssertNoThrow(try vm.currentPDFDataForOCR())
    }

    func testCrossMemberMoveRefusesFormsInEitherMemberWithoutChangingStateOrUndo() throws {
        final class UndoProbe { var value = 1 }
        for scenario in ["moved-field", "remaining-source-field", "target-field", "empty-acroform", "loaded-widget", "displayed-widget"] {
            for history in ["undo", "redo"] {
                let sourceData = try ["moved-field", "remaining-source-field", "empty-acroform"].contains(scenario)
                    ? formFixture(pageCount: 2, fieldPage: scenario == "moved-field" ? 0 : scenario == "remaining-source-field" ? 1 : nil)
                    : nil
                let targetData = try scenario == "target-field" ? formFixture(pageCount: 3, fieldPage: 2) : nil
                let vm = try crossMemberModel(sourcePageCount: 2, sourceData: sourceData, targetData: targetData)
                let refs = vm.document.workspace.pageOrder
                if scenario == "loaded-widget" || scenario == "displayed-widget" {
                    let page = try XCTUnwrap(scenario == "loaded-widget" ? vm.loadedPDFs.first?.1.page(at: 0) : vm.combinedPDF.page(at: 1))
                    let widget = PDFAnnotation(bounds: CGRect(x: 40, y: 350, width: 120, height: 30), forType: .widget, withProperties: nil)
                    widget.widgetFieldType = .text
                    widget.fieldName = "Unsaved new field"
                    widget.widgetStringValue = "Unsaved native answer"
                    page.addAnnotation(widget)
                    XCTAssertEqual(QPDFService.hasAcroForm(try XCTUnwrap(vm.document.memberPDFData[refs[0].memberDocId])), false)
                } else {
                    for index in 0..<vm.combinedPDF.pageCount {
                        for widget in vm.combinedPDF.page(at: index)?.annotations.filter(\.isPDFWidget) ?? [] {
                            widget.widgetStringValue = "Unsaved reader answer"
                        }
                    }
                }
                vm.selectedPageRefID = refs[1].id
                vm.selectedPageRefIDs = [refs[0].id, refs[1].id]
                let decoration = PageDecoration(kind: .hanko, text: "Fictional", pageRefID: refs[0].id,
                    rect: CGRect(x: 90, y: 300, width: 100, height: 60))
                vm.document.workspace.decorations = [decoration]
                vm.selectedStampDecorationID = decoration.id
                vm.markAnnotationsModified(warnAboutSignatureInvalidation: false)
                let undo = try XCTUnwrap(retainedUndo)
                undo.groupsByEvent = false
                let probe = UndoProbe()
                undo.beginUndoGrouping()
                undo.registerUndo(withTarget: probe) { probe in
                    probe.value = 0
                    undo.registerUndo(withTarget: probe) { $0.value = 1 }
                }
                undo.setActionName("Existing fictional edit")
                undo.endUndoGrouping()
                if history == "redo" { undo.undo() }

                let encoder = JSONEncoder()
                encoder.outputFormatting = .sortedKeys
                let beforeWorkspace = try encoder.encode(vm.document.workspace)
                let beforeBytes = vm.document.memberPDFData
                let beforeSourcePayloads = try encoder.encode(vm.document.sourcePayloads)
                let beforePristine = vm.document.currentOriginalPDFDataProvider?()
                let loadedObjects = vm.loadedPDFs.map { ObjectIdentifier($0.1) }
                let displayedObject = ObjectIdentifier(vm.combinedPDF)
                // PDFKit generates a new trailer ID on each serialization. Canonical bytes
                // must stay exact; loaded page identities prove refusal never detaches them.
                let beforePages = vm.loadedPDFs.map { pageObjects(in: $0.1) }
                let beforeLoadedWidgets = vm.loadedPDFs.map { widgetValues(in: $0.1) }
                let beforeDisplayedWidgets = widgetValues(in: vm.combinedPDF)
                let beforeRevisions = [vm.commentRevision, vm.decorationStateVersion]
                let beforeDirty = vm.hasUnsavedChanges
                let beforeUndo = [undo.canUndo, undo.canRedo]
                let beforeUndoNames = [undo.undoActionName, undo.redoActionName]
                XCTAssertFalse(vm.movePage(refs[0], after: refs[2]), "\(scenario)/\(history)")
                XCTAssertEqual(try encoder.encode(vm.document.workspace), beforeWorkspace)
                XCTAssertEqual(vm.document.memberPDFData, beforeBytes)
                XCTAssertEqual(try encoder.encode(vm.document.sourcePayloads), beforeSourcePayloads)
                XCTAssertEqual(vm.document.currentOriginalPDFDataProvider?(), beforePristine)
                XCTAssertEqual(vm.loadedPDFs.map { ObjectIdentifier($0.1) }, loadedObjects)
                XCTAssertEqual(ObjectIdentifier(vm.combinedPDF), displayedObject)
                XCTAssertEqual(vm.loadedPDFs.map { pageObjects(in: $0.1) }, beforePages)
                XCTAssertEqual(vm.loadedPDFs.map { widgetValues(in: $0.1) }, beforeLoadedWidgets)
                XCTAssertEqual(widgetValues(in: vm.combinedPDF), beforeDisplayedWidgets)
                XCTAssertEqual(vm.selectedPageRefID, refs[1].id)
                XCTAssertEqual(vm.selectedPageRefIDs, [refs[0].id, refs[1].id])
                XCTAssertEqual(vm.selectedStampDecorationID, decoration.id)
                XCTAssertEqual([vm.commentRevision, vm.decorationStateVersion], beforeRevisions)
                XCTAssertEqual(vm.hasUnsavedChanges, beforeDirty)
                XCTAssertEqual([undo.canUndo, undo.canRedo], beforeUndo)
                XCTAssertEqual([undo.undoActionName, undo.redoActionName], beforeUndoNames)
                XCTAssertEqual(vm.editingStatus?.message, PDFTextEditWarning.serializationFailed.message)
                if history == "undo" { undo.undo(); XCTAssertEqual(probe.value, 0) }
                else { undo.redo(); XCTAssertEqual(probe.value, 1) }
            }
        }
    }

    func testAcroFormPresenceIsStructuralAndUnreadableInputFailsClosed() throws {
        XCTAssertEqual(QPDFService.hasAcroForm(try formFixture(pageCount: 2, fieldPage: nil)), true)
        XCTAssertEqual(QPDFService.hasAcroForm(try formFixture(pageCount: 2, fieldPage: 1)), true)
        XCTAssertEqual(QPDFService.hasAcroForm(try fixture(prefix: "Text /AcroForm is not a catalog key")), false)
        XCTAssertNil(QPDFService.hasAcroForm(Data("invalid".utf8)))
    }

    private func widgetValues(in pdf: PDFDocument) -> [[String]] {
        (0..<pdf.pageCount).flatMap { index in
            (pdf.page(at: index)?.annotations.filter(\.isPDFWidget) ?? []).map {
                [$0.fieldName ?? "nil", $0.widgetStringValue ?? "nil", String(describing: $0.buttonWidgetState)]
            }
        }
    }

    private func pageObjects(in pdf: PDFDocument) -> [ObjectIdentifier] {
        (0..<pdf.pageCount).compactMap { pdf.page(at: $0) }.map(ObjectIdentifier.init)
    }

    private func formFixture(pageCount: Int, fieldPage: Int?) throws -> Data {
        let fieldID = 3 + pageCount
        let fields = fieldPage == nil ? "" : "\(fieldID) 0 R"
        var objects = ["1 0 obj<</Type/Catalog/Pages 2 0 R/AcroForm<</Fields[\(fields)]/NeedAppearances true>>>>endobj",
            "2 0 obj<</Type/Pages/Kids[\((0..<pageCount).map { "\(3 + $0) 0 R" }.joined(separator: " "))]/Count \(pageCount)>>endobj"]
        for index in 0..<pageCount {
            let annots = fieldPage == index ? "/Annots[\(fieldID) 0 R]" : ""
            objects.append("\(3 + index) 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 612 792]\(annots)>>endobj")
        }
        if let fieldPage {
            objects.append("\(fieldID) 0 obj<</Type/Annot/Subtype/Widget/FT/Tx/T(Existing field)/V(Initial answer)/Rect[40 350 220 380]/P \(3 + fieldPage) 0 R>>endobj")
        }
        return try XCTUnwrap(QPDFService.repaired(Data(("%PDF-1.4\n" + objects.joined(separator: "\n")
            + "\ntrailer<</Root 1 0 R/Size \(fieldID + 1)>>\n%%EOF").utf8)))
    }

    private func attachmentCatalogFixture(_ catalog: String) throws -> Data {
        let rootNames: String
        switch catalog {
        case "absent-names": rootNames = ""
        case "empty-names": rootNames = "/Names << >>"
        case "unrelated-names": rootNames = "/Names << /Dests << /Names [] >> >>"
        case "invalid-root-names": rootNames = "/Names 4 0 R"
        default: rootNames = "/Names << /EmbeddedFiles 4 0 R >>"
        }
        var objects = [
            "1 0 obj << /Type /Catalog /Pages 2 0 R \(rootNames) >> endobj",
            "2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 >> endobj",
            "3 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] >> endobj"
        ]
        switch catalog {
        case "invalid-root-names", "invalid-embedded-files": objects.append("4 0 obj (uninspectable) endobj")
        case "invalid-leaf": objects.append("4 0 obj << /Names (uninspectable) >> endobj")
        case "invalid-kids": objects.append("4 0 obj << /Kids (uninspectable) >> endobj")
        case "odd-leaf": objects.append("4 0 obj << /Names [(orphan)] >> endobj")
        case "deep-tree":
            for index in 4..<68 { objects.append("\(index) 0 obj << /Kids [\(index + 1) 0 R] >> endobj") }
            objects.append("68 0 obj << /Names [(Deep.txt) 69 0 R] >> endobj")
            objects.append("69 0 obj << /Type /Filespec /F (Deep.txt) /EF << /F 70 0 R >> >> endobj")
            objects.append("70 0 obj << /Type /EmbeddedFile /Length 9 >> stream\nFictional\nendstream endobj")
        case "empty-tree": objects.append("4 0 obj << /Names [] >> endobj")
        default: break
        }
        let raw = Data(("%PDF-1.4\n" + objects.joined(separator: "\n")
            + "\ntrailer << /Root 1 0 R /Size 71 >>\n%%EOF").utf8)
        return try XCTUnwrap(QPDFService.repaired(raw))
    }

    private func crossMemberModel(sourcePageCount: Int, sourceData: Data? = nil, targetData: Data? = nil,
                                  includeSourceAttachment: Bool = true, sourceAttachmentName: String = "Source.txt") throws -> WorkspaceViewModel {
        let document = WorkspaceDocument()
        for (role, count) in [("Source", sourcePageCount), ("Target", 3)] {
            let data = try PDFMetadataService.write(PDFDocumentMetadata(title: role),
                to: (role == "Source" ? sourceData : targetData) ?? fixture(prefix: role, pageCount: count))
            var member = MemberDocument(displayName: role, sourcePDFRef: "\(role).pdf")
            let refs = (0..<count).map { PageRef(memberDocId: member.id, sourcePageIndex: $0) }
            member.pageRefs = refs.map(\.id)
            document.workspace.documents.append(member)
            document.workspace.pageOrder.append(contentsOf: refs)
            document.memberPDFData[member.id] = role == "Source" && !includeSourceAttachment ? data
                : try AttachmentsService.add(Data(role.utf8),
                    name: role == "Source" ? sourceAttachmentName : "Target.txt", mimeType: "text/plain", to: data)
        }
        let vm = WorkspaceViewModel(document: document, processingEngine: PDFiumProcessingEngine())
        let undo = UndoManager()
        retainedUndo = undo
        vm.undoManager = undo
        return vm
    }

    private func assertCatalog(_ data: Data, file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertEqual(try PDFMetadataService.read(from: data), metadata, file: file, line: line)
        XCTAssertEqual(try AttachmentsService.extract("fictional.txt", from: data), payload, file: file, line: line)
    }

    private func model(invalidPristine: Bool = false) throws -> WorkspaceViewModel {
        var document = try WorkspaceDocument(testingFile: FileWrapper(regularFileWithContents: fixture()), contentType: .pdf,
                                             fingerprintStore: WorkspaceFingerprintStore(directory: try directory()))
        if invalidPristine {
            let memberID = try XCTUnwrap(document.workspace.documents.first?.id)
            let pdf = try XCTUnwrap(PDFDocument(data: XCTUnwrap(document.memberPDFData[memberID])))
            let persisted: [String: Any] = [
                "editableWorkspace": try JSONSerialization.jsonObject(with: JSONEncoder().encode(document.workspace)),
                "editableMemberPDFData": try JSONSerialization.jsonObject(with: JSONEncoder().encode(document.memberPDFData)),
                "editableOriginalMemberPDFData": try JSONSerialization.jsonObject(with: JSONEncoder().encode([memberID: Data("invalid".utf8)]))
            ]
            let annotation = PDFAnnotation(bounds: CGRect(x: -1000, y: -1000, width: 1, height: 1),
                                           forType: .text, withProperties: nil)
            annotation.setValue(String(decoding: try JSONSerialization.data(withJSONObject: persisted), as: UTF8.self),
                                forAnnotationKey: PDFAnnotationKey(rawValue: "/OrifoldWorkspaceComments"))
            try XCTUnwrap(pdf.page(at: 0)).addAnnotation(annotation)
            document = try WorkspaceDocument(testingFile: FileWrapper(regularFileWithContents: XCTUnwrap(PDFSerializer.data(from: pdf))),
                contentType: .pdf, fingerprintStore: WorkspaceFingerprintStore(directory: try directory()))
        }
        let vm = WorkspaceViewModel(document: document, processingEngine: PDFiumProcessingEngine())
        let undo = UndoManager()
        undo.groupsByEvent = false
        retainedUndo = undo
        vm.undoManager = undo
        return vm
    }

    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("structural-catalog-\(UUID())")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        directories.append(url)
        return url
    }

    private func fixture(prefix: String = "Fictional", pageCount: Int = 3) throws -> Data {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        let ctx = try XCTUnwrap(CGContext(consumer: XCTUnwrap(CGDataConsumer(data: data as CFMutableData)), mediaBox: &box, nil))
        for index in 0..<pageCount {
            ctx.beginPDFPage(nil)
            ctx.setFillColor(CGColor(gray: 1, alpha: 1)); ctx.fill(box)
            ctx.setFillColor(NSColor.systemBlue.cgColor)
            ctx.fill(CGRect(x: 100, y: 200, width: 120, height: 60))
            ctx.textPosition = CGPoint(x: 72, y: 700)
            CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: "\(prefix) page \(index)",
                attributes: [.font: NSFont(name: "Helvetica", size: 14)!, .foregroundColor: NSColor.black])), ctx)
            ctx.endPDFPage()
        }
        ctx.closePDF()
        return data as Data
    }
}
