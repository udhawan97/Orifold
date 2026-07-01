import AppKit
import PDFKit
import UniformTypeIdentifiers
import XCTest
@testable import PDFold

final class SourceDocumentRoundTripTests: XCTestCase {
    func testContentSniffingPreservesSourcePayloadsForSupportedTextFormats() throws {
        let samples = try makeSupportedSamples()

        for sample in samples {
            let imported = try DocumentImportConverter.importedDocument(
                from: sample.data,
                contentType: .data,
                filename: sample.filename,
                baseURL: nil
            )

            XCTAssertGreaterThan(imported.pdfDocument.pageCount, 0, sample.format.rawValue)
            XCTAssertEqual(imported.sourcePayload?.format, sample.format, sample.format.rawValue)
            XCTAssertEqual(imported.sourcePayload?.originalData, sample.data, sample.format.rawValue)
        }
    }

    func testSameFormatUnchangedMarkdownExportReturnsOriginalBytes() throws {
        let markdown = """
        # Heading

        - **Bold** item
        - [Link](https://example.com)
        """
        let viewModel = try makeViewModel(
            data: Data(markdown.utf8),
            contentType: .markdown,
            filename: "wrong-extension.bin"
        )

        let exported = try viewModel.dataForWorkspaceExport(as: .markdown)

        XCTAssertEqual(exported, Data(markdown.utf8))
    }

    func testSameFormatUnchangedExportsReturnOriginalBytesForAllSupportedTextFormats() throws {
        for sample in try makeSupportedSamples() {
            let viewModel = try makeViewModel(
                data: sample.data,
                contentType: sample.format.contentType,
                filename: "sample.\(sample.format.fileExtension)"
            )

            let exported = try viewModel.dataForWorkspaceExport(as: exportFormat(for: sample.format))

            XCTAssertEqual(exported, sample.data, sample.format.rawValue)
        }
    }

    func testSameFormatEditedExportsContainReplacementForAllSupportedTextFormats() throws {
        for sample in try makeSupportedSamples() where [.plainText, .markdown, .html, .rtf].contains(sample.format) {
            let viewModel = try makeViewModel(
                data: sample.data,
                contentType: sample.format.contentType,
                filename: "sample.\(sample.format.fileExtension)"
            )
            let member = try XCTUnwrap(viewModel.loadedPDFs.first?.0, sample.format.rawValue)
            let pageRefID = try XCTUnwrap(member.pageRefs.first, sample.format.rawValue)
            viewModel.document.workspace.pageEditStates = [
                PageEditState(pageRefID: pageRefID, operations: [
                    PDFTextEditOperation(
                        pageRefID: pageRefID,
                        sourceBlockID: UUID(),
                        sourceBounds: .zero,
                        sourceText: "Bold item",
                        editedBounds: .zero,
                        replacementText: "Crisp edit",
                        fontName: "Helvetica",
                        fontSize: 12,
                        textColor: .documentText,
                        alignment: .left
                    )
                ])
            ]

            let exported = try viewModel.dataForWorkspaceExport(as: exportFormat(for: sample.format))
            let exportedText = try extractedText(from: exported, format: sample.format)

            XCTAssertTrue(exportedText.contains("Heading"), sample.format.rawValue)
            XCTAssertTrue(exportedText.contains("Crisp edit"), sample.format.rawValue)
            XCTAssertFalse(exportedText.contains("Bold item"), sample.format.rawValue)
        }
    }

    func testEditedPackageFormatsFailCleanlyInsteadOfLossyRewrite() throws {
        for sample in try makeSupportedSamples() where [.docx, .wordDoc, .odt].contains(sample.format) {
            let viewModel = try makeViewModel(
                data: sample.data,
                contentType: sample.format.contentType,
                filename: "sample.\(sample.format.fileExtension)"
            )
            let member = try XCTUnwrap(viewModel.loadedPDFs.first?.0, sample.format.rawValue)
            let pageRefID = try XCTUnwrap(member.pageRefs.first, sample.format.rawValue)
            viewModel.document.workspace.pageEditStates = [
                PageEditState(pageRefID: pageRefID, operations: [
                    PDFTextEditOperation(
                        pageRefID: pageRefID,
                        sourceBlockID: UUID(),
                        sourceBounds: .zero,
                        sourceText: "Bold item",
                        editedBounds: .zero,
                        replacementText: "Crisp edit",
                        fontName: "Helvetica",
                        fontSize: 12,
                        textColor: .documentText,
                        alignment: .left
                    )
                ])
            ]

            XCTAssertThrowsError(try viewModel.dataForWorkspaceExport(as: exportFormat(for: sample.format))) { error in
                guard case WorkspaceViewModel.ExportBuildError.editedPackageFormatRequiresPDF = error else {
                    return XCTFail("Expected editedPackageFormatRequiresPDF, got \(error)")
                }
            }
        }
    }

    func testSameFormatEditedMarkdownExportPatchesOriginalSource() throws {
        let markdown = """
        # Heading

        Hello **world**
        """
        let viewModel = try makeViewModel(
            data: Data(markdown.utf8),
            contentType: .markdown,
            filename: "notes.md"
        )
        let member = try XCTUnwrap(viewModel.loadedPDFs.first?.0)
        let pageRefID = try XCTUnwrap(member.pageRefs.first)
        viewModel.document.workspace.pageEditStates = [
            PageEditState(pageRefID: pageRefID, operations: [
                PDFTextEditOperation(
                    pageRefID: pageRefID,
                    sourceBlockID: UUID(),
                    sourceBounds: .zero,
                    sourceText: "world",
                    editedBounds: .zero,
                    replacementText: "pdFold",
                    fontName: "Helvetica",
                    fontSize: 12,
                    textColor: .documentText,
                    alignment: .left
                )
            ])
        ]

        let exported = try viewModel.dataForWorkspaceExport(as: .markdown)
        let exportedMarkdown = try XCTUnwrap(String(data: exported, encoding: .utf8))

        XCTAssertTrue(exportedMarkdown.contains("Hello **pdFold**"))
        XCTAssertTrue(exportedMarkdown.contains("# Heading"))
    }

    func testUnmappedSourceEditFailsCleanlyInsteadOfFlattening() throws {
        let viewModel = try makeViewModel(
            data: Data("# Heading\n\nBody".utf8),
            contentType: .markdown,
            filename: "notes.md"
        )
        let member = try XCTUnwrap(viewModel.loadedPDFs.first?.0)
        let pageRefID = try XCTUnwrap(member.pageRefs.first)
        viewModel.document.workspace.pageEditStates = [
            PageEditState(pageRefID: pageRefID, operations: [
                PDFTextEditOperation(
                    pageRefID: pageRefID,
                    sourceBlockID: UUID(),
                    sourceBounds: .zero,
                    sourceText: "missing source text",
                    editedBounds: .zero,
                    replacementText: "replacement",
                    fontName: "Helvetica",
                    fontSize: 12,
                    textColor: .documentText,
                    alignment: .left
                )
            ])
        ]

        XCTAssertThrowsError(try viewModel.dataForWorkspaceExport(as: .markdown)) { error in
            guard case WorkspaceViewModel.ExportBuildError.cannotMapEdit(let memberName, let sourceText) = error else {
                return XCTFail("Expected cannotMapEdit, got \(error)")
            }
            XCTAssertEqual(memberName, "notes")
            XCTAssertEqual(sourceText, "missing source text")
        }
    }

    func testDuplicateSourceTextFailsCleanlyInsteadOfPatchingFirstMatch() throws {
        let viewModel = try makeViewModel(
            data: Data("# Heading\n\nTotal\nTotal\n".utf8),
            contentType: .markdown,
            filename: "notes.md"
        )
        let member = try XCTUnwrap(viewModel.loadedPDFs.first?.0)
        let pageRefID = try XCTUnwrap(member.pageRefs.first)
        viewModel.document.workspace.pageEditStates = [
            PageEditState(pageRefID: pageRefID, operations: [
                PDFTextEditOperation(
                    pageRefID: pageRefID,
                    sourceBlockID: UUID(),
                    sourceBounds: .zero,
                    sourceText: "Total",
                    editedBounds: .zero,
                    replacementText: "Subtotal",
                    fontName: "Helvetica",
                    fontSize: 12,
                    textColor: .documentText,
                    alignment: .left
                )
            ])
        ]

        XCTAssertThrowsError(try viewModel.dataForWorkspaceExport(as: .markdown)) { error in
            guard case WorkspaceViewModel.ExportBuildError.ambiguousSourceText(let memberName, let sourceText) = error else {
                return XCTFail("Expected ambiguousSourceText, got \(error)")
            }
            XCTAssertEqual(memberName, "notes")
            XCTAssertEqual(sourceText, "Total")
        }
    }

    func testPDFOnlyTextBoxFailsSourceExportCleanly() throws {
        let viewModel = try makeViewModel(
            data: Data("# Heading\n\nBody".utf8),
            contentType: .markdown,
            filename: "notes.md"
        )
        let page = try XCTUnwrap(viewModel.loadedPDFs.first?.1.page(at: 0))
        let annotation = PDFAnnotation(bounds: CGRect(x: 10, y: 10, width: 100, height: 30), forType: .freeText, withProperties: nil)
        annotation.contents = "PDF-only"
        page.addAnnotation(annotation)

        XCTAssertThrowsError(try viewModel.dataForWorkspaceExport(as: .markdown)) { error in
            guard case WorkspaceViewModel.ExportBuildError.pdfOnlyEditsCannotMap(let memberName) = error else {
                return XCTFail("Expected pdfOnlyEditsCannotMap, got \(error)")
            }
            XCTAssertEqual(memberName, "notes")
        }
    }

    func testSavedPDFMetadataRestoresSourcePayloadForReopen() throws {
        let markdown = Data("# Heading\n\n- **Bold item**\n".utf8)
        let viewModel = try makeViewModel(data: markdown, contentType: .markdown, filename: "notes.md")
        let saved = try XCTUnwrap(viewModel.document.exportedPDFData(from: try viewModel.document.snapshot(contentType: .pdf)))
        let reopenedPDF = try XCTUnwrap(PDFDocument(data: saved))

        let reopened = WorkspaceDocument()
        try reopened.importPDFDocumentForTesting(reopenedPDF, filename: "notes.pdf")

        XCTAssertEqual(reopened.sourcePayloads.values.first?.format, .markdown)
        XCTAssertEqual(reopened.sourcePayloads.values.first?.originalData, markdown)
    }

    func testMarkdownMarkersBeatPlainTextSuggestion() throws {
        let markdown = Data("# Heading\nBody".utf8)

        let detected = DocumentImportConverter.detectedContentType(
            data: markdown,
            suggestedContentType: .plainText,
            filename: "notes.txt"
        )

        XCTAssertTrue(detected.conforms(to: .markdown))
    }

    func testBinaryGarbageMislabelledAsTextFailsCleanly() {
        let garbage = Data([0x00, 0x01, 0x02, 0x03, 0xFF, 0x00, 0x10])

        XCTAssertThrowsError(
            try DocumentImportConverter.importedDocument(
                from: garbage,
                contentType: .plainText,
                filename: "garbage.txt",
                baseURL: nil
            )
        ) { error in
            guard case DocumentImportConverter.ConversionError.binaryDataMislabelledAsText = error else {
                return XCTFail("Expected binaryDataMislabelledAsText, got \(error)")
            }
        }
    }

    private struct Sample {
        var format: SourceDocumentFormat
        var data: Data
        var filename: String
    }

    private func makeSupportedSamples() throws -> [Sample] {
        let rich = NSMutableAttributedString(string: "Heading\nBold item\nLink")
        rich.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: 18), range: NSRange(location: 0, length: 7))
        rich.addAttribute(.link, value: URL(string: "https://example.com")!, range: NSRange(location: 18, length: 4))

        var samples: [Sample] = [
            Sample(format: .plainText, data: Data("Heading\nBold item\nLink".utf8), filename: "no-extension"),
            Sample(format: .markdown, data: Data("# Heading\n\n- **Bold item**\n".utf8), filename: "wrong.bin"),
            Sample(format: .html, data: Data("<!doctype html><html><body><h1>Heading</h1><p><strong>Bold item</strong></p></body></html>".utf8), filename: "wrong.bin"),
            Sample(format: .rtf, data: try richData(from: rich, documentType: .rtf), filename: "wrong.bin")
        ]

        samples.append(Sample(format: .docx, data: try richData(from: rich, documentType: .officeOpenXML), filename: "wrong.bin"))
        samples.append(Sample(format: .odt, data: try richData(from: rich, documentType: .openDocument), filename: "wrong.bin"))
        samples.append(Sample(format: .wordDoc, data: try richData(from: rich, documentType: .docFormat), filename: "legacy.doc"))
        return samples
    }

    private func richData(from attributed: NSAttributedString, documentType: NSAttributedString.DocumentType) throws -> Data {
        try attributed.data(
            from: NSRange(location: 0, length: attributed.length),
            documentAttributes: [.documentType: documentType]
        )
    }

    private func exportFormat(for sourceFormat: SourceDocumentFormat) -> WorkspaceExportFormat {
        switch sourceFormat {
        case .docx: return .word
        case .wordDoc: return .legacyWord
        case .odt: return .odt
        case .rtf: return .rtf
        case .markdown: return .markdown
        case .html: return .html
        case .plainText: return .text
        }
    }

    private func extractedText(from data: Data, format: SourceDocumentFormat) throws -> String {
        switch format {
        case .markdown, .html, .plainText:
            return try XCTUnwrap(String(data: data, encoding: .utf8), format.rawValue)
        case .docx, .wordDoc, .odt, .rtf:
            let documentType = try XCTUnwrap(format.documentType, format.rawValue)
            let attributed = try NSAttributedString(
                data: data,
                options: [.documentType: documentType],
                documentAttributes: nil
            )
            return attributed.string
        }
    }

    private func makeViewModel(data: Data, contentType: UTType, filename: String) throws -> WorkspaceViewModel {
        let imported = try DocumentImportConverter.importedDocument(
            from: data,
            contentType: contentType,
            filename: filename,
            baseURL: nil
        )
        let pdfData = try XCTUnwrap(PDFSerializer.data(from: imported.pdfDocument))
        var member = MemberDocument(
            displayName: URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent,
            sourcePDFRef: filename
        )
        let refs = (0..<imported.pdfDocument.pageCount).map { PageRef(memberDocId: member.id, sourcePageIndex: $0) }
        member.pageRefs = refs.map(\.id)

        let document = WorkspaceDocument()
        document.workspace.title = member.displayName
        document.workspace.documents = [member]
        document.workspace.pageOrder = refs
        document.memberPDFData[member.id] = pdfData
        if let payload = imported.sourcePayload {
            document.sourcePayloads[member.id] = payload
        }
        return WorkspaceViewModel(document: document, processingEngine: PDFKitProcessingEngineFallback())
    }
}
