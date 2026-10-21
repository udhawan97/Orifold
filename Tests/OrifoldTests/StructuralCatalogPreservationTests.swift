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

    private func fixture() throws -> Data {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        let ctx = try XCTUnwrap(CGContext(consumer: XCTUnwrap(CGDataConsumer(data: data as CFMutableData)), mediaBox: &box, nil))
        for index in 0..<3 {
            ctx.beginPDFPage(nil)
            ctx.setFillColor(CGColor(gray: 1, alpha: 1)); ctx.fill(box)
            ctx.setFillColor(NSColor.systemBlue.cgColor)
            ctx.fill(CGRect(x: 100, y: 200, width: 120, height: 60))
            ctx.textPosition = CGPoint(x: 72, y: 700)
            CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: "Fictional page \(index)",
                attributes: [.font: NSFont(name: "Helvetica", size: 14)!, .foregroundColor: NSColor.black])), ctx)
            ctx.endPDFPage()
        }
        ctx.closePDF()
        return data as Data
    }
}
