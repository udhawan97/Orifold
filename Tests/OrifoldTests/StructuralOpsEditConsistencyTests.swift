import PDFKit
import XCTest
@testable import Orifold

/// Regression coverage for structural-operation ↔ inline-edit consistency (Loop 1 of the
/// editing hardening pass): deleting/reordering/duplicating pages, OCR, and cross-member
/// moves all change how a PageRef maps onto the member's PRISTINE bytes. Stale
/// `sourcePageIndex` mappings made regeneration and hit-testing read a NEIGHBORING page's
/// content — data-destroying when committed.
final class StructuralOpsEditConsistencyTests: XCTestCase {
    private final class FixturePageView: NSView {
        private let text: String
        init(frame: CGRect, text: String) {
            self.text = text
            super.init(frame: frame)
        }
        required init?(coder: NSCoder) { nil }
        override func draw(_ dirtyRect: NSRect) {
            NSColor.white.setFill()
            dirtyRect.fill()
            (text as NSString).draw(
                in: bounds.insetBy(dx: 54, dy: 54),
                withAttributes: [.font: NSFont(name: "Helvetica", size: 14) ?? .systemFont(ofSize: 14),
                                 .foregroundColor: NSColor.black]
            )
        }
    }

    private func makePDFData(pageTexts: [String]) throws -> Data {
        let pdf = PDFDocument()
        for (index, text) in pageTexts.enumerated() {
            let view = FixturePageView(frame: CGRect(x: 0, y: 0, width: 612, height: 792), text: text)
            guard let pageDocument = PDFDocument(data: view.dataWithPDF(inside: view.bounds)),
                  let page = pageDocument.page(at: 0) else {
                throw XCTSkip("fixture page rendering failed")
            }
            pdf.insert(page, at: index)
        }
        return try XCTUnwrap(pdf.dataRepresentation())
    }

    private func makeViewModel(from pdfData: Data, name: String = "Fixture") throws -> WorkspaceViewModel {
        let wrapper = FileWrapper(regularFileWithContents: pdfData)
        wrapper.preferredFilename = "\(name).pdf"
        let document = try WorkspaceDocument(testingFile: wrapper, contentType: .pdf, filename: "\(name).pdf")
        return WorkspaceViewModel(document: document, processingEngine: PDFiumProcessingEngine())
    }

    /// Reading-order text of the member's `pageIndex`, extracted via PDFium re-analysis
    /// (`PDFTextAnalysisEngine`), NOT PDFKit's `.attributedString`/`.string`. PDFKit's
    /// CoreText-based extraction scrambles/undercounts characters on regenerated (edited)
    /// pages under CI's older Xcode 16.4 PDFKit — the exact toolchain quirk documented in
    /// [[ci-xcode164-pdfkit-string-extraction-quirk]] — which made these assertions pass
    /// locally (Xcode 26.6) but fail on CI. PDFium extraction is run-preserving and
    /// reliable on both. Blocks are joined in reading order with spaces so the multi-word
    /// tokens the assertions check for read back contiguously.
    private func pageText(_ viewModel: WorkspaceViewModel, pageIndex: Int) -> String {
        // Inspect the display lane independently from the authoritative bytes/OCR inputs.
        guard let pdf = viewModel.loadedPDFs.first?.1 else { return "" }
        return pageText(fromLivePDF: pdf, pageIndex: pageIndex)
    }

    /// Reading-order text of `pageIndex` in the CURRENT bytes of `pdf`, joined with spaces.
    private func pageText(fromLivePDF pdf: PDFDocument, pageIndex: Int) -> String {
        guard let data = pdf.dataRepresentation() else { return "" }
        return pageText(fromMemberData: data, pageIndex: pageIndex)
    }

    /// Reading-order text of `pageIndex` in `data`, joined with spaces.
    private func pageText(fromMemberData data: Data, pageIndex: Int) -> String {
        guard let page = PDFDocument(data: data)?.page(at: pageIndex) else { return "" }
        let ordered = PDFTextAnalysisEngine()
            .analyze(data: data, pageIndex: pageIndex, pageRefID: UUID(), fallbackPage: page)
            .blocks
            .sorted { lhs, rhs in
                let ly = lhs.bounds.standardized.midY, ry = rhs.bounds.standardized.midY
                if abs(ly - ry) > max(lhs.bounds.height, rhs.bounds.height) { return ly > ry }
                return lhs.bounds.standardized.midX < rhs.bounds.standardized.midX
            }
        return ordered.map(\.text).joined(separator: " ")
    }

    @discardableResult
    private func clickAndEdit(
        _ viewModel: WorkspaceViewModel,
        pageIndex: Int,
        expectPrefixOfClickedText expectedNeedle: String,
        replacement: String
    ) throws -> Bool {
        let page = try XCTUnwrap(viewModel.loadedPDFs.first?.1.page(at: pageIndex))
        // Click where the fixture draws its text (top-left region of the page).
        let click = CGPoint(x: 140, y: 792 - 66)
        let target = try XCTUnwrap(viewModel.editableTextBlock(at: click, on: page, in: viewModel.combinedPDF))
        XCTAssertTrue(
            target.block.text.contains(expectedNeedle),
            "hit-test must resolve the clicked page's own text; got '\(target.block.text.prefix(60))' expecting '\(expectedNeedle)'"
        )
        return viewModel.applyInlineTextEdit(
            pageRef: target.pageRef,
            sourceBlock: target.block,
            replacementText: replacement,
            editedBounds: target.block.bounds,
            fontName: target.block.fontName,
            fontSize: target.block.fontSize,
            textColor: .black,
            alignment: .left
        )
    }

    func testStructuralChangesImmediatelyPrepareTheCurrentPageContentForOCR() throws {
        for operation in ["reorder", "delete", "delete-batch", "duplicate"] {
            let vm = try makeViewModel(from: makePDFData(pageTexts: ["Alpha page", "Beta page", "Gamma page"]))
            let refs = vm.document.workspace.pageOrder
            let expected: [String]
            switch operation {
            case "reorder":
                XCTAssertTrue(vm.movePage(refs[0], toIndex: 3))
                expected = ["Beta", "Gamma", "Alpha"]
            case "delete":
                vm.deletePage(refs[0])
                expected = ["Beta", "Gamma"]
            case "delete-batch":
                vm.deletePages([refs[0], refs[1]])
                expected = ["Gamma"]
            default:
                vm.duplicatePages([refs[0]])
                expected = ["Alpha", "Alpha", "Beta", "Gamma"]
            }
            let memberID = try XCTUnwrap(vm.document.workspace.documents.first?.id)
            let live = try XCTUnwrap(vm.document.memberPDFData[memberID])
            XCTAssertEqual(PDFDocument(data: live)?.pageCount, expected.count, operation)
            let prepared = try XCTUnwrap(vm.currentPDFDataForOCR()[memberID])
            for (index, needle) in expected.enumerated() {
                XCTAssertTrue(pageText(vm, pageIndex: index).contains(needle), operation)
                XCTAssertTrue(pageText(fromMemberData: live, pageIndex: index).contains(needle), operation)
                XCTAssertTrue(pageText(fromMemberData: prepared, pageIndex: index).contains(needle), operation)
            }
        }
    }

    func testReorderKeepsCommittedTextInLiveOCRBytesAndUneditedPristineForReplay() throws {
        let vm = try makeViewModel(from: makePDFData(pageTexts: ["Alpha original words", "Beta original words"]))
        XCTAssertTrue(try clickAndEdit(vm, pageIndex: 0, expectPrefixOfClickedText: "Alpha", replacement: "Alpha FIRSTEDIT words"))
        let first = try XCTUnwrap(vm.document.workspace.pageOrder.first)
        XCTAssertTrue(vm.movePage(first, toIndex: 2))
        let memberID = first.memberDocId
        let prepared = try XCTUnwrap(vm.currentPDFDataForOCR()[memberID])
        XCTAssertTrue(pageText(fromMemberData: prepared, pageIndex: 0).contains("Beta"))
        XCTAssertTrue(pageText(fromMemberData: prepared, pageIndex: 1).contains("FIRSTEDIT"))
        XCTAssertTrue(try clickAndEdit(vm, pageIndex: 1, expectPrefixOfClickedText: "Alpha", replacement: "Alpha SECONDEDIT words"))
        let live = try XCTUnwrap(vm.document.memberPDFData[memberID])
        XCTAssertTrue(pageText(fromMemberData: live, pageIndex: 0).contains("Beta"))
        XCTAssertTrue(pageText(fromMemberData: live, pageIndex: 1).contains("SECONDEDIT"))
        XCTAssertFalse(pageText(fromMemberData: live, pageIndex: 1).contains("FIRSTEDIT"))
    }

    @MainActor
    func testStructuralChangesImmediatelyFollowedByCleanupAndRedactionTargetTheVisiblePage() async throws {
        for operation in ["reorder", "delete", "duplicate"] {
            for consumer in ["cleanup", "redaction"] {
                let vm = try makeViewModel(from: makePDFData(pageTexts: ["Alpha unique", "Beta unique", "Gamma unique"]))
                let refs = vm.document.workspace.pageOrder
                switch operation {
                case "reorder": XCTAssertTrue(vm.movePage(refs[0], toIndex: 3))
                case "delete": vm.deletePage(refs[0])
                default: vm.duplicatePages([refs[0]])
                }
                let order = vm.document.workspace.pageOrder
                let target = order[0]
                let memberID = target.memberDocId
                let neighborBefore = pageText(vm, pageIndex: 1)
                let removedNeedle = operation == "duplicate" ? "Alpha" : "Beta"
                if consumer == "cleanup" {
                    let succeeded = await vm.applyScanCleanup(pageRefIDs: [target.id],
                        options: ScanCleanupOptions(deskew: false, binarize: true, despeckle: false))
                    XCTAssertTrue(succeeded, operation)
                } else {
                    _ = vm.addRedactionMark(rect: CGRect(x: 0, y: 0, width: 612, height: 792), pageRefID: target.id)
                    XCTAssertTrue(vm.applyRedactions(), operation)
                }
                let live = try XCTUnwrap(vm.document.memberPDFData[memberID])
                XCTAssertEqual(PDFDocument(data: live)?.pageCount, order.count)
                XCTAssertFalse(pageText(fromMemberData: live, pageIndex: 0).contains(removedNeedle))
                XCTAssertEqual(pageText(fromMemberData: live, pageIndex: 1), neighborBefore,
                    "the neighboring page must keep its content after \(operation) + \(consumer)")
                XCTAssertNoThrow(try vm.currentPDFDataForOCR())
            }
        }
    }

    func testStructuralChangesPreserveLiveNotesFormsAndRotationsThroughOCRUndoAndReopen() throws {
        for operation in ["reorder", "delete", "duplicate"] {
            let vm = try makeViewModel(from: makePDFData(pageTexts: ["Alpha page", "Beta page", "Gamma page"]))
            let pdf = try XCTUnwrap(vm.loadedPDFs.first?.1)
            for index in 0..<pdf.pageCount {
                let page = try XCTUnwrap(pdf.page(at: index))
                let note = PDFAnnotation(bounds: CGRect(x: 40, y: 400, width: 80, height: 40), forType: .text, withProperties: nil)
                note.contents = "Note \(index)"
                page.addAnnotation(note)
                let widget = PDFAnnotation(bounds: CGRect(x: 40, y: 350, width: 120, height: 30), forType: .widget, withProperties: nil)
                widget.widgetFieldType = .text
                widget.fieldName = "Field\(index)"
                widget.widgetStringValue = "Value \(index)"
                page.addAnnotation(widget)
                page.rotation = index * 90
            }
            let undo = UndoManager()
            undo.groupsByEvent = false
            vm.undoManager = undo
            let refs = vm.document.workspace.pageOrder
            let expected: [Int]
            undo.beginUndoGrouping()
            switch operation {
            case "reorder":
                XCTAssertTrue(vm.movePage(refs[0], toIndex: 3))
                expected = [1, 2, 0]
            case "delete":
                vm.deletePage(refs[0])
                expected = [1, 2]
            default:
                vm.duplicatePages([refs[0]])
                expected = [0, 0, 1, 2]
            }
            undo.endUndoGrouping()
            let memberID = refs[0].memberDocId
            func assertInteractive(_ data: Data, _ indexes: [Int]) throws {
                let document = try XCTUnwrap(PDFDocument(data: data))
                XCTAssertEqual(document.pageCount, indexes.count)
                for (localIndex, sourceIndex) in indexes.enumerated() {
                    let page = try XCTUnwrap(document.page(at: localIndex))
                    XCTAssertEqual(page.rotation, sourceIndex * 90, operation)
                    XCTAssertTrue(page.annotations.contains { $0.contents == "Note \(sourceIndex)" }, operation)
                    XCTAssertTrue(page.annotations.contains { $0.widgetStringValue == "Value \(sourceIndex)" }, operation)
                }
                XCTAssertTrue(QPDFService.formFieldsReferencePageAnnotations(data))
            }
            try assertInteractive(XCTUnwrap(vm.document.memberPDFData[memberID]), expected)
            try assertInteractive(XCTUnwrap(vm.currentPDFDataForOCR()[memberID]), expected)
            undo.undo()
            try assertInteractive(XCTUnwrap(vm.currentPDFDataForOCR()[memberID]), [0, 1, 2])
            undo.redo()
            try assertInteractive(XCTUnwrap(vm.document.memberPDFData[memberID]), expected)
            let saved = try vm.document.savedFileWrapper(from: vm.document.snapshot(contentType: .pdf))
            let reopened = try WorkspaceDocument(testingFile: saved, contentType: .pdf, filename: "reopened.pdf")
            let reopenedVM = WorkspaceViewModel(document: reopened, processingEngine: PDFiumProcessingEngine())
            try assertInteractive(XCTUnwrap(reopenedVM.currentPDFDataForOCR()[memberID]), expected)
        }
    }

    /// In-session: delete page 1, then click text on the (new) first page. Hit-testing
    /// must analyze the surviving page's pristine content, not the deleted page's.
    func testEditAfterDeletingEarlierPageHitsTheRightPristinePage() throws {
        let pdfData = try makePDFData(pageTexts: ["FirstPage unique alpha", "SecondPage unique beta", "ThirdPage unique gamma"])
        let viewModel = try makeViewModel(from: pdfData)
        let firstRef = try XCTUnwrap(viewModel.document.workspace.pageOrder.first)
        viewModel.deletePage(firstRef)
        XCTAssertEqual(viewModel.document.workspace.pageOrder.count, 2)

        XCTAssertTrue(try clickAndEdit(
            viewModel,
            pageIndex: 0,
            expectPrefixOfClickedText: "SecondPage",
            replacement: "SecondPage edited beta"
        ))
        let after = pageText(viewModel, pageIndex: 0)
        XCTAssertTrue(after.contains("SecondPage edited beta"))
        XCTAssertFalse(after.contains("FirstPage"), "regeneration must not resurrect the deleted page's content")
        XCTAssertTrue(pageText(viewModel, pageIndex: 1).contains("ThirdPage"), "the untouched page stays intact")
    }

    /// Save-after-structural-op, no committed edits: reopening renormalizes stale
    /// sourcePageIndex values so editing regenerates the correct page instead of a
    /// neighbor's content (and instead of failing outright on the last page).
    func testReopenAfterDeleteAndSaveEditsTheCorrectPages() throws {
        let pdfData = try makePDFData(pageTexts: ["FirstPage unique alpha", "SecondPage unique beta", "ThirdPage unique gamma"])
        let first = try makeViewModel(from: pdfData)
        let firstRef = try XCTUnwrap(first.document.workspace.pageOrder.first)
        first.deletePage(firstRef)
        let saved = try first.document.exportedPDFDataThrowing(
            from: first.document.snapshot(contentType: .pdf),
            options: WorkspaceExportOptions(embedsEditableWorkspaceState: true)
        )

        let second = try makeViewModel(from: saved, name: "Reopened")
        XCTAssertEqual(second.document.workspace.pageOrder.count, 2)
        // Edit the FIRST visible page (was source page 1) — with stale indices this
        // regenerated from the neighbor's bytes.
        XCTAssertTrue(try clickAndEdit(
            second,
            pageIndex: 0,
            expectPrefixOfClickedText: "SecondPage",
            replacement: "SecondPage edited beta"
        ))
        XCTAssertTrue(pageText(second, pageIndex: 0).contains("SecondPage edited beta"))
        XCTAssertFalse(pageText(second, pageIndex: 0).contains("ThirdPage"), "must not regenerate from the neighboring page")
        // Edit the LAST page — with stale indices this failed outright (index past
        // the shrunken page count).
        XCTAssertTrue(try clickAndEdit(
            second,
            pageIndex: 1,
            expectPrefixOfClickedText: "ThirdPage",
            replacement: "ThirdPage edited gamma"
        ))
        XCTAssertTrue(pageText(second, pageIndex: 1).contains("ThirdPage edited gamma"))
    }

    /// Duplicating an edited page must clone its committed operations: editing the
    /// duplicate afterwards regenerates it with BOTH edits, not pristine + only-the-new.
    func testDuplicateOfEditedPageKeepsItsEditsWhenReedited() throws {
        let pdfData = try makePDFData(pageTexts: ["DupSource original words"])
        let viewModel = try makeViewModel(from: pdfData)
        XCTAssertTrue(try clickAndEdit(
            viewModel,
            pageIndex: 0,
            expectPrefixOfClickedText: "DupSource",
            replacement: "DupSource FIRSTEDIT words"
        ))
        let sourceRef = try XCTUnwrap(viewModel.document.workspace.pageOrder.first)
        viewModel.duplicatePages([sourceRef])
        XCTAssertEqual(viewModel.document.workspace.pageOrder.count, 2)
        XCTAssertTrue(pageText(viewModel, pageIndex: 1).contains("FIRSTEDIT"), "duplicate visibly carries the edit")

        // Edit the DUPLICATE: its cloned op must survive the regeneration.
        let duplicateRef = viewModel.document.workspace.pageOrder[1]
        let dupState = viewModel.document.workspace.pageEditStates.first { $0.pageRefID == duplicateRef.id }
        XCTAssertNotNil(dupState, "duplicate ref must own cloned operations")
        let page = try XCTUnwrap(viewModel.loadedPDFs.first?.1.page(at: 1))
        let click = CGPoint(x: 140, y: 792 - 66)
        let target = try XCTUnwrap(viewModel.editableTextBlock(at: click, on: page, in: viewModel.combinedPDF))
        XCTAssertTrue(viewModel.applyInlineTextEdit(
            pageRef: target.pageRef,
            sourceBlock: target.block,
            replacementText: "DupSource SECONDEDIT words",
            editedBounds: target.block.bounds,
            fontName: target.block.fontName,
            fontSize: target.block.fontSize,
            textColor: .black,
            alignment: .left
        ))
        XCTAssertTrue(pageText(viewModel, pageIndex: 1).contains("SECONDEDIT"))
        XCTAssertTrue(pageText(viewModel, pageIndex: 0).contains("FIRSTEDIT"), "the original page keeps its own edit")
    }

    /// Cross-member move: editing text on the moved page must edit THAT page's content —
    /// previously regeneration replaced the moved page with a different page of the
    /// target member (confirmed data-destroying defect).
    func testEditingCrossMemberMovedPageKeepsItsOwnContent() throws {
        let dataA = try makePDFData(pageTexts: ["MemberA moving page"])
        let dataB = try makePDFData(pageTexts: ["MemberB first page", "MemberB second page"])
        let viewModel = try makeViewModel(from: dataA)
        let urlB = FileManager.default.temporaryDirectory.appendingPathComponent("Orifold-memberB-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: urlB) }
        try dataB.write(to: urlB)
        let expectation = XCTestExpectation(description: "import B")
        viewModel.importFiles(urls: [urlB])
        // importFiles is async; poll for completion.
        for _ in 0..<200 {
            if viewModel.document.workspace.documents.count == 2, !viewModel.isImporting { break }
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        expectation.fulfill()
        guard viewModel.document.workspace.documents.count == 2 else {
            throw XCTSkip("async import did not complete in time")
        }

        let movedRef = try XCTUnwrap(viewModel.document.workspace.pageOrder.first { $0.memberDocId == viewModel.document.workspace.documents[0].id })
        let targetRef = try XCTUnwrap(viewModel.document.workspace.pageOrder.first { $0.memberDocId == viewModel.document.workspace.documents[1].id })
        XCTAssertTrue(viewModel.movePage(movedRef, after: targetRef))

        // Find the moved page's local position inside member B.
        let memberB = viewModel.document.workspace.documents.first { $0.pageRefs.contains(movedRef.id) }
        let localIdx = try XCTUnwrap(memberB?.pageRefs.firstIndex(of: movedRef.id))
        let pdfB = try XCTUnwrap(viewModel.loadedPDFs.first(where: { $0.0.id == memberB?.id })?.1)
        let movedPage = try XCTUnwrap(pdfB.page(at: localIdx))
        XCTAssertTrue(pageText(fromLivePDF: pdfB, pageIndex: localIdx).contains("MemberA moving page"))

        let click = CGPoint(x: 140, y: 792 - 66)
        let target = try XCTUnwrap(viewModel.editableTextBlock(at: click, on: movedPage, in: viewModel.combinedPDF))
        XCTAssertTrue(target.block.text.contains("MemberA"),
                      "hit-test on the moved page must see the moved page's own text, got '\(target.block.text.prefix(50))'")
        XCTAssertTrue(viewModel.applyInlineTextEdit(
            pageRef: target.pageRef,
            sourceBlock: target.block,
            replacementText: "MemberA moved and edited",
            editedBounds: target.block.bounds,
            fontName: target.block.fontName,
            fontSize: target.block.fontSize,
            textColor: .black,
            alignment: .left
        ))
        let livePdfB = try XCTUnwrap(viewModel.loadedPDFs.first(where: { $0.0.id == memberB?.id })?.1)
        let after = pageText(fromLivePDF: livePdfB, pageIndex: localIdx)
        XCTAssertTrue(after.contains("MemberA moved and edited"), "edit lands on the moved page")
        XCTAssertFalse(after.contains("MemberB"), "the moved page's content must not be replaced by a target-member page")
    }

    func testCrossMemberMoveRefusesTextEditsOnMovedOrStationaryInvolvedPagesWithoutChangingStateOrUndo() throws {
        final class UndoProbe { var value = 1 }
        for editedIndex in [0, 1, 3] {
            for history in ["undo", "redo"] {
                let (vm, undo) = try crossMemberTextModel()
                let refs = vm.document.workspace.pageOrder
                try applyCrossMemberTextEdit(vm, ref: refs[editedIndex])
                undo.removeAllActions()
                vm.selectedPageRefID = refs[editedIndex].id
                vm.selectedPageRefIDs = [refs[0].id, refs[editedIndex].id]
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
                let beforePristine = vm.document.currentOriginalPDFDataProvider?()
                let beforePayloads = try encoder.encode(vm.document.sourcePayloads)
                let loadedObjects = vm.loadedPDFs.map { ObjectIdentifier($0.1) }
                let combinedObject = ObjectIdentifier(vm.combinedPDF)
                let beforeHistory = [undo.canUndo, undo.canRedo]
                let beforeNames = [undo.undoActionName, undo.redoActionName]

                XCTAssertFalse(vm.movePage(refs[0], after: refs[2]))

                XCTAssertEqual(try encoder.encode(vm.document.workspace), beforeWorkspace)
                XCTAssertEqual(vm.document.memberPDFData, beforeBytes)
                XCTAssertEqual(vm.document.currentOriginalPDFDataProvider?(), beforePristine)
                XCTAssertEqual(try encoder.encode(vm.document.sourcePayloads), beforePayloads)
                XCTAssertEqual(vm.loadedPDFs.map { ObjectIdentifier($0.1) }, loadedObjects)
                XCTAssertEqual(ObjectIdentifier(vm.combinedPDF), combinedObject)
                XCTAssertEqual(vm.selectedPageRefID, refs[editedIndex].id)
                XCTAssertEqual(vm.selectedPageRefIDs, [refs[0].id, refs[editedIndex].id])
                XCTAssertEqual([undo.canUndo, undo.canRedo], beforeHistory)
                XCTAssertEqual([undo.undoActionName, undo.redoActionName], beforeNames)
                XCTAssertEqual(vm.editingStatus?.message, L10n.string("status.pageMove.committedTextEdits"))
                if history == "redo" { undo.redo(); XCTAssertEqual(probe.value, 1) }
                else { undo.undo(); XCTAssertEqual(probe.value, 0) }
            }
        }
    }

    func testRefusedCrossMemberMoveKeepsRevertOneAndAllHonestIncludingEditableReopen() throws {
        for reopen in [false, true] {
            for revertAll in [false, true] {
                var (vm, undo) = try crossMemberTextModel()
                let refs = vm.document.workspace.pageOrder
                let edited = refs[1]
                let original = try XCTUnwrap(vm.document.memberPDFData[edited.memberDocId])
                let originalPixels = try pagePixels(original, pageIndex: 1)
                try applyCrossMemberTextEdit(vm, ref: edited)
                let editedBytes = try XCTUnwrap(vm.document.memberPDFData[edited.memberDocId])
                XCTAssertNotEqual(try pagePixels(editedBytes, pageIndex: 1), originalPixels, "pixel control must detect the visible replacement")
                XCTAssertTrue(PDFTextAnalysisEngine.readingOrderText(data: editedBytes, pageIndex: 1).contains("Fictional replacement"))
                if reopen {
                    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Orifold-text-move-\(UUID())")
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    defer { try? FileManager.default.removeItem(at: directory) }
                    let saved = try vm.document.savedFileWrapper(from: vm.document.snapshot(contentType: .pdf))
                    let document = try WorkspaceDocument(testingFile: saved, contentType: .pdf,
                        fingerprintStore: WorkspaceFingerprintStore(directory: directory))
                    vm = WorkspaceViewModel(document: document, processingEngine: PDFiumProcessingEngine())
                    undo = UndoManager()
                    vm.undoManager = undo
                }
                undo.groupsByEvent = true
                let operation = try XCTUnwrap(vm.document.workspace.pageEditStates.first?.operations.first)
                XCTAssertFalse(vm.movePage(try XCTUnwrap(vm.workspacePageRef(refs[0].id)),
                    after: try XCTUnwrap(vm.workspacePageRef(refs[2].id))))
                if revertAll { XCTAssertTrue(vm.revertAllInlineTextEdits()) }
                else { XCTAssertTrue(vm.revertInlineTextEdit(pageRefID: edited.id, operationID: operation.id)) }
                XCTAssertFalse(vm.hasInlineTextEdits)
                let reverted = try XCTUnwrap(vm.document.memberPDFData[edited.memberDocId])
                let member = try XCTUnwrap(vm.document.workspace.documents.first { $0.id == edited.memberDocId })
                let revertedIndex = try XCTUnwrap(member.pageRefs.firstIndex(of: edited.id))
                let text = PDFTextAnalysisEngine.readingOrderText(data: reverted, pageIndex: revertedIndex)
                XCTAssertFalse(text.contains("Fictional replacement"))
                XCTAssertTrue(text.contains("Source page 1"))
                XCTAssertEqual(try pagePixels(reverted, pageIndex: revertedIndex), originalPixels)
            }
        }
    }

    func testCrossMemberMoveKeepsTextEditsInUntouchedThirdMemberReversible() throws {
        let (vm, undo) = try crossMemberTextModel(includeThird: true)
        let refs = vm.document.workspace.pageOrder
        let edited = refs[4]
        let originalPixels = try pagePixels(XCTUnwrap(vm.document.memberPDFData[edited.memberDocId]), pageIndex: 0)
        try applyCrossMemberTextEdit(vm, ref: edited)
        let thirdBytes = vm.document.memberPDFData[edited.memberDocId]
        let thirdOps = vm.document.workspace.pageEditStates
        undo.groupsByEvent = true
        XCTAssertTrue(vm.movePage(refs[0], after: refs[2]))
        XCTAssertEqual(vm.document.memberPDFData[edited.memberDocId], thirdBytes)
        XCTAssertEqual(vm.document.workspace.pageEditStates, thirdOps)
        XCTAssertTrue(vm.revertAllInlineTextEdits())
        let reverted = try XCTUnwrap(vm.document.memberPDFData[edited.memberDocId])
        XCTAssertFalse(PDFTextAnalysisEngine.readingOrderText(data: reverted, pageIndex: 0).contains("Fictional replacement"))
        XCTAssertEqual(try pagePixels(reverted, pageIndex: 0), originalPixels)
    }

    func testCrossMemberMoveStillAllowsObjectOnlyEditsInEitherInvolvedMember() throws {
        for editedIndex in [0, 3] {
            let (vm, undo) = try crossMemberTextModel()
            let refs = vm.document.workspace.pageOrder
            let edited = refs[editedIndex]
            let object = try XCTUnwrap(vm.objectMap(for: edited).objects.first {
                $0.objectType == .rectangle || $0.objectType == .filledShape
            })
            var transform = object.transform
            transform.e += 20
            XCTAssertTrue(vm.applyObjectEdit([ObjectEditOperation(
                type: .objectTransform, documentID: edited.memberDocId, pageRefID: edited.id,
                sourceObjectKey: object.stableKey, objectType: object.objectType, editability: object.editability,
                originalBoundsPdf: object.boundsPdf, newBoundsPdf: object.boundsPdf.offsetBy(dx: 20, dy: 0),
                originalTransform: object.transform, newTransform: transform, pageRotation: Int(object.pageRotation),
                originalZIndex: object.zOrder, newZIndex: object.zOrder, replacementStrategy: .pdfiumStructural
            )]))
            XCTAssertFalse(vm.hasInlineTextEdits)
            undo.groupsByEvent = true
            XCTAssertTrue(vm.movePage(refs[0], after: refs[2]))
            let movedRef = try XCTUnwrap(vm.workspacePageRef(edited.id))
            XCTAssertTrue(vm.objectMap(for: movedRef).objects.contains {
                abs($0.boundsPdf.minX - (object.boundsPdf.minX + 20)) < 2 && $0.objectType == object.objectType
            })
        }
    }

    private func crossMemberTextModel(includeThird: Bool = false) throws -> (WorkspaceViewModel, UndoManager) {
        let document = WorkspaceDocument()
        for name in includeThird ? ["Source", "Target", "Third"] : ["Source", "Target"] {
            let pdf = PDFDocument()
            for index in 0..<2 {
                let data = EditingFixturePDFBuilder.makePDF(runs: [
                    .init(string: "\(name) page \(index)", origin: CGPoint(x: 72, y: 700), fontSize: 18)
                ], rules: [.init(rect: CGRect(x: 100, y: 200, width: 100, height: 50))])
                pdf.insert(try XCTUnwrap(PDFDocument(data: data)?.page(at: 0)), at: index)
            }
            var member = MemberDocument(displayName: name, sourcePDFRef: "\(name).pdf")
            let refs = (0..<2).map { PageRef(memberDocId: member.id, sourcePageIndex: $0) }
            member.pageRefs = refs.map(\.id)
            document.workspace.documents.append(member)
            document.workspace.pageOrder += refs
            document.memberPDFData[member.id] = try XCTUnwrap(PDFSerializer.data(from: pdf))
        }
        let vm = WorkspaceViewModel(document: document, processingEngine: PDFiumProcessingEngine())
        let undo = UndoManager()
        undo.groupsByEvent = false
        vm.undoManager = undo
        return (vm, undo)
    }

    private func applyCrossMemberTextEdit(_ vm: WorkspaceViewModel, ref: PageRef) throws {
        let member = try XCTUnwrap(vm.loadedPDFs.first { $0.0.id == ref.memberDocId })
        let index = try XCTUnwrap(member.0.pageRefs.firstIndex(of: ref.id))
        let page = try XCTUnwrap(member.1.page(at: index))
        let data = try XCTUnwrap(vm.document.memberPDFData[ref.memberDocId])
        let block = try XCTUnwrap(PDFTextAnalysisEngine().analyze(data: data, pageIndex: index,
            pageRefID: ref.id, fallbackPage: page).blocks.first)
        XCTAssertTrue(vm.applyInlineTextEdit(pageRef: ref, sourceBlock: block,
            replacementText: "Fictional replacement", editedBounds: block.bounds,
            fontName: block.fontName, fontSize: block.fontSize, textColor: .black, alignment: .left))
    }

    private func pagePixels(_ data: Data, pageIndex: Int) throws -> Data {
        let document = try XCTUnwrap(CGPDFDocument(XCTUnwrap(CGDataProvider(data: data as CFData))))
        let page = try XCTUnwrap(document.page(at: pageIndex + 1))
        let context = try XCTUnwrap(CGContext(data: nil, width: 612, height: 792,
            bitsPerComponent: 8, bytesPerRow: 612, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0))
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 612, height: 792))
        context.drawPDFPage(page)
        return Data(bytes: try XCTUnwrap(context.data), count: context.bytesPerRow * context.height)
    }

    /// Redo works for order-snapshot operations: delete → undo → redo must re-delete.
    func testDeletePageUndoThenRedoRedeletes() throws {
        let pdfData = try makePDFData(pageTexts: ["Page one text", "Page two text"])
        let viewModel = try makeViewModel(from: pdfData)
        let undoManager = UndoManager()
        viewModel.undoManager = undoManager
        let lastRef = try XCTUnwrap(viewModel.document.workspace.pageOrder.last)
        viewModel.deletePage(lastRef)
        XCTAssertEqual(viewModel.document.workspace.pageOrder.count, 1)
        undoManager.undo()
        XCTAssertEqual(viewModel.document.workspace.pageOrder.count, 2, "undo restores the page")
        XCTAssertTrue(undoManager.canRedo, "order-snapshot restore must register its inverse")
        undoManager.redo()
        XCTAssertEqual(viewModel.document.workspace.pageOrder.count, 1, "redo re-deletes the page")
    }
}
