import AppKit
import PDFKit
import UniformTypeIdentifiers
import XCTest
@testable import PDFold

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
        XCTAssertEqual(decodedSignature.signerName, "Ada")
        XCTAssertEqual(decodedSignature.signedAt, signature.signedAt)
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
}

final class WorkspaceDocumentTests: XCTestCase {
    func testSnapshotUsesCurrentPDFDataProvider() throws {
        let memberID = UUID()
        let expectedPDFData = try makePDF(pageTexts: ["snapshot"]).dataRepresentation().unwrap()
        let stalePDFData = Data([9, 9, 9])
        let document = WorkspaceDocument()
        document.workspace.title = "Package"
        document.memberPDFData[memberID] = stalePDFData
        document.currentPDFDataProvider = { [memberID: expectedPDFData] }

        let snapshot = try document.snapshot(contentType: .pdfoldproj)

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
