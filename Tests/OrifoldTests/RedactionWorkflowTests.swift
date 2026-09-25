import AppKit
import PDFKit
import XCTest
@testable import Orifold

/// Mark → apply through the view model: every byte lane, undo/redo, the edit-conflict
/// refusal, and the side stores (comment snippets, source payloads, the saved file) that
/// would otherwise keep a copy of what was redacted.
@MainActor
final class RedactionWorkflowTests: XCTestCase {
    private var retainedUndoManager: UndoManager?
    private let secretRegion = CGRect(x: 60, y: 690, width: 200, height: 30)

    func testApplyRemovesTextFromLiveBytes() throws {
        let viewModel = try makeViewModel()
        let ref = try pageRef(viewModel, 0)

        viewModel.addRedactionMark(rect: secretRegion, pageRefID: ref.id)
        XCTAssertTrue(viewModel.applyRedactions())

        let live = try liveBytes(viewModel, ref)
        XCTAssertFalse(text(live).contains("SECRET"))
        XCTAssertTrue(text(live).contains("KEEPME"))
        XCTAssertTrue(viewModel.pendingRedactions.isEmpty)
    }

    func testUndoRestoresAndRedoRemovesAgain() throws {
        let viewModel = try makeViewModel()
        let ref = try pageRef(viewModel, 0)
        let undo = try XCTUnwrap(viewModel.undoManager)

        viewModel.addRedactionMark(rect: secretRegion, pageRefID: ref.id)
        XCTAssertTrue(viewModel.applyRedactions())
        undo.undo()
        XCTAssertTrue(text(try liveBytes(viewModel, ref)).contains("SECRET"))
        undo.redo()
        XCTAssertFalse(text(try liveBytes(viewModel, ref)).contains("SECRET"))
    }

    func testPageWithObjectEditsIsRefusedAndBytesUnchanged() throws {
        let viewModel = try makeViewModel()
        let ref = try pageRef(viewModel, 0)
        let image = try XCTUnwrap(viewModel.objectMap(for: ref).objects.first { $0.objectType == .imageXObject })
        XCTAssertTrue(viewModel.applyObjectEdit([move(image, ref: ref)]))
        let before = try liveBytes(viewModel, ref)

        viewModel.addRedactionMark(rect: secretRegion, pageRefID: ref.id)
        XCTAssertFalse(viewModel.applyRedactions())

        XCTAssertEqual(try liveBytes(viewModel, ref), before)
        XCTAssertEqual(viewModel.pendingRedactions.count, 1, "refusal keeps the marks for a retry")
    }

    func testRedactionSurvivesObjectReplayFromBaseLanes() throws {
        let viewModel = try makeViewModel()
        let first = try pageRef(viewModel, 0), second = try pageRef(viewModel, 1)
        // Edit page 2 first so the member already has pristine/object base lanes that still
        // hold page 1's secret when the redaction runs.
        XCTAssertTrue(viewModel.applyObjectEdit([move(try image(on: second, viewModel), ref: second)]))

        viewModel.addRedactionMark(rect: secretRegion, pageRefID: first.id)
        XCTAssertTrue(viewModel.applyRedactions())
        // Another object edit regenerates the member from those base lanes. Unredacted
        // bases would bring the secret back here.
        XCTAssertTrue(viewModel.applyObjectEdit([move(try image(on: second, viewModel), ref: second)]))

        XCTAssertFalse(text(try liveBytes(viewModel, first)).contains("SECRET"))
        XCTAssertTrue(text(try liveBytes(viewModel, first)).contains("KEEPME"))
    }

    private func image(on ref: PageRef, _ viewModel: WorkspaceViewModel) throws -> DetectedObject {
        try XCTUnwrap(viewModel.objectMap(for: ref).objects.first { $0.objectType == .imageXObject })
    }

    func testIntersectingCommentSnippetIsScrubbed() throws {
        let viewModel = try makeViewModel()
        let ref = try pageRef(viewModel, 0)
        viewModel.document.workspace.comments = [
            WorkspaceComment(body: "check this", anchor: WorkspaceCommentAnchor(
                pageRefID: ref.id, rect: CGRect(x: 70, y: 695, width: 60, height: 14), kind: .text, snippet: "SECRET")),
            WorkspaceComment(body: "fine", anchor: WorkspaceCommentAnchor(
                pageRefID: ref.id, rect: CGRect(x: 70, y: 395, width: 60, height: 14), kind: .text, snippet: "KEEPME"))
        ]

        viewModel.addRedactionMark(rect: secretRegion, pageRefID: ref.id)
        XCTAssertTrue(viewModel.applyRedactions())

        XCTAssertEqual(viewModel.document.workspace.comments.map(\.anchor?.snippet), [nil, "KEEPME"])
        XCTAssertEqual(viewModel.document.workspace.comments.first?.body, "check this", "the user's own note stays")
    }

    func testSourcePayloadIsDroppedForRedactedMember() throws {
        let viewModel = try makeMarkdownViewModel(source: "# Report\n\nSECRET plan")
        let ref = try pageRef(viewModel, 0)
        XCTAssertNotNil(viewModel.document.sourcePayloads[ref.memberDocId])

        let page = try XCTUnwrap(PDFDocument(data: try liveBytes(viewModel, ref))?.page(at: 0))
        viewModel.addRedactionMark(rect: page.bounds(for: .mediaBox), pageRefID: ref.id)
        XCTAssertTrue(viewModel.applyRedactions())

        XCTAssertNil(viewModel.document.sourcePayloads[ref.memberDocId])
    }

    func testSavedFileNoLongerCarriesTheSecret() throws {
        let viewModel = try makeViewModel()
        let ref = try pageRef(viewModel, 0)
        viewModel.addRedactionMark(rect: secretRegion, pageRefID: ref.id)
        XCTAssertTrue(viewModel.applyRedactions())

        let saved = try viewModel.document.savedFileWrapper(from: viewModel.document.snapshot(contentType: .pdf))
        let savedBytes = try XCTUnwrap(saved.regularFileContents)
        XCTAssertFalse(text(savedBytes).contains("SECRET"))
        let reopened = try WorkspaceDocument(testingFile: saved, contentType: .pdf)
        for bytes in reopened.memberPDFData.values {
            XCTAssertFalse(text(bytes).contains("SECRET"), "embedded workspace state must not keep the secret")
        }
    }

    func testMarkUndoRemovesMark() throws {
        let viewModel = try makeViewModel()
        let ref = try pageRef(viewModel, 0)

        viewModel.addRedactionMark(rect: secretRegion, pageRefID: ref.id)
        XCTAssertEqual(viewModel.pendingRedactions.count, 1)
        viewModel.undoManager?.undo()
        XCTAssertTrue(viewModel.pendingRedactions.isEmpty)
        viewModel.undoManager?.redo()
        XCTAssertEqual(viewModel.pendingRedactions.count, 1)
        viewModel.clearRedactionMarks()
        XCTAssertTrue(viewModel.pendingRedactions.isEmpty)
    }

    // MARK: - Fixtures

    private func makeViewModel() throws -> WorkspaceViewModel {
        let wrapper = FileWrapper(regularFileWithContents: twoPageFixture())
        wrapper.preferredFilename = "redact.pdf"
        let document = try WorkspaceDocument(testingFile: wrapper, contentType: .pdf, filename: "redact.pdf")
        return attachUndo(WorkspaceViewModel(document: document, processingEngine: PDFiumProcessingEngine()))
    }

    private func makeMarkdownViewModel(source: String) throws -> WorkspaceViewModel {
        let imported = try DocumentImportConverter.importedDocument(
            from: Data(source.utf8), contentType: .markdown, filename: "report.md", baseURL: nil)
        var member = MemberDocument(displayName: "report", sourcePDFRef: "report.md")
        let refs = (0..<imported.pdfDocument.pageCount).map { PageRef(memberDocId: member.id, sourcePageIndex: $0) }
        member.pageRefs = refs.map(\.id)
        let document = WorkspaceDocument()
        document.workspace.documents = [member]
        document.workspace.pageOrder = refs
        document.memberPDFData[member.id] = try XCTUnwrap(PDFSerializer.data(from: imported.pdfDocument))
        document.sourcePayloads[member.id] = try XCTUnwrap(imported.sourcePayload)
        return attachUndo(WorkspaceViewModel(document: document, processingEngine: PDFiumProcessingEngine()))
    }

    private func attachUndo(_ viewModel: WorkspaceViewModel) -> WorkspaceViewModel {
        let undoManager = UndoManager()
        retainedUndoManager = undoManager
        viewModel.undoManager = undoManager
        return viewModel
    }

    /// Page 1: "SECRET" / "KEEPME" and a small image; page 2: an image (object-edit target).
    private func twoPageFixture() -> Data {
        let data = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        let context = CGContext(consumer: CGDataConsumer(data: data as CFMutableData)!, mediaBox: &mediaBox, nil)!
        let pixels = CGContext(data: nil, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 0,
                               space: CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        pixels.setFillColor(NSColor.systemBlue.cgColor)
        pixels.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
        let image = pixels.makeImage()!
        let font = CTFontCreateWithName("Helvetica" as CFString, 12, nil)

        context.beginPDFPage(nil)
        for (string, y) in [("SECRET", 700.0), ("KEEPME", 400.0)] {
            context.textPosition = CGPoint(x: 72, y: y)
            CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: [.font: font])), context)
        }
        context.draw(image, in: CGRect(x: 400, y: 100, width: 60, height: 60))
        context.endPDFPage()
        context.beginPDFPage(nil)
        context.draw(image, in: CGRect(x: 180, y: 300, width: 80, height: 80))
        context.endPDFPage()
        context.closePDF()
        return data as Data
    }

    private func pageRef(_ viewModel: WorkspaceViewModel, _ index: Int) throws -> PageRef {
        let order = viewModel.document.workspace.pageOrder
        XCTAssertGreaterThan(order.count, index)
        return order[index]
    }

    /// The member's live bytes, as the page's own single-page view for text reading.
    private func liveBytes(_ viewModel: WorkspaceViewModel, _ ref: PageRef) throws -> Data {
        try XCTUnwrap(viewModel.document.memberPDFData[ref.memberDocId])
    }

    private func text(_ data: Data) -> String {
        guard let count = PDFDocument(data: data)?.pageCount else { return "" }
        return (0..<count).map { PDFTextAnalysisEngine.readingOrderText(data: data, pageIndex: $0) }.joined(separator: "\n")
    }

    private func move(_ object: DetectedObject, ref: PageRef) -> ObjectEditOperation {
        var transform = object.transform
        transform.e += 12
        return ObjectEditOperation(
            type: .objectTransform,
            documentID: ref.memberDocId,
            pageRefID: ref.id,
            sourceObjectKey: object.stableKey,
            objectType: object.objectType,
            editability: object.editability,
            originalBoundsPdf: object.boundsPdf,
            newBoundsPdf: object.boundsPdf.offsetBy(dx: 12, dy: 0),
            originalTransform: object.transform,
            newTransform: transform,
            pageRotation: Int(object.pageRotation),
            originalZIndex: object.zOrder,
            newZIndex: object.zOrder,
            replacementStrategy: .pdfiumStructural
        )
    }
}
