import PDFKit
import XCTest
@testable import Orifold

@MainActor
final class DecorationMetadataPreservationTests: XCTestCase {
    func testPageNumberWatermarkAndHankoPreserveUnicodeInfoThroughSaveExportAndReopen() throws {
        let metadata = PDFDocumentMetadata(title: "折り紙", author: "うまん", subject: "विषय", keywords: "标签, synthetic")
        for kind in [PageDecoration.Kind.pageNumber, .watermark, .hanko] {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("decoration-info-\(UUID())")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let store = WorkspaceFingerprintStore(directory: directory)
            let source = PDFDocument()
            source.insert(PDFPage(), at: 0)
            source.insert(PDFPage(), at: 1)
            let document = try WorkspaceDocument(
                testingFile: FileWrapper(regularFileWithContents: XCTUnwrap(PDFSerializer.data(from: source))),
                contentType: .pdf, fingerprintStore: store
            )
            let viewModel = WorkspaceViewModel(document: document, processingEngine: PDFiumProcessingEngine())
            XCTAssertTrue(viewModel.applyMetadataEdit(metadata))
            let ref = try XCTUnwrap(document.workspace.pageOrder.first)
            document.workspace.decorations = [PageDecoration(
                kind: kind, text: "Fictional", pageRefID: ref.id,
                rect: CGRect(x: 90, y: 300, width: 100, height: 60)
            )]

            let saved = try document.savedFileWrapper(from: document.snapshot(contentType: .pdf))
            XCTAssertEqual(try PDFMetadataService.read(from: XCTUnwrap(saved.regularFileContents)), metadata,
                           "\(kind): the visible saved PDF must retain all Info fields")
            let editableReopened = try WorkspaceDocument(testingFile: saved, contentType: .pdf, fingerprintStore: store)
            XCTAssertEqual(try PDFMetadataService.read(from: XCTUnwrap(editableReopened.memberPDFData[ref.memberDocId])), metadata)

            let exported = try viewModel.dataForPDFExport()
            XCTAssertEqual(try PDFMetadataService.read(from: exported), metadata,
                           "\(kind): flat export must retain all Info fields")
            let flatReopened = try WorkspaceDocument(testingFile: FileWrapper(regularFileWithContents: exported),
                                                     contentType: .pdf, fingerprintStore: store)
            XCTAssertEqual(try PDFMetadataService.read(from: XCTUnwrap(flatReopened.memberPDFData.values.first)), metadata,
                           "\(kind): a flat exported PDF must retain Info on reopen")

            let sanitized = try viewModel.dataForPDFExport(
                options: WorkspaceExportOptions(sanitization: PDFSanitizationOptions(removesMetadata: true))
            )
            XCTAssertEqual(try PDFMetadataService.read(from: sanitized), PDFDocumentMetadata(),
                           "\(kind): explicit sanitize still removes Info downstream")
        }
    }
}
