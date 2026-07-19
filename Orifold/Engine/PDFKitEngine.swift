import AppKit
import Compression
import Foundation
import PDFKit
import UniformTypeIdentifiers
import WebKit

final class PDFKitEngine: PDFEngine {
    enum ExportAssemblyError: LocalizedError, Equatable {
        case unreadableMember(String)
        case emptyDocument
        case metadataEmbedFailed

        var errorDescription: String? {
            switch self {
            case .unreadableMember(let name):
                return String(localized: "Orifold could not prepare \"\(name)\" for export. Reopen the document and try exporting again.", locale: L10n.currentLocale)
            case .emptyDocument:
                return L10n.string("error.export.emptyDocument")
            case .metadataEmbedFailed:
                return L10n.string("error.export.metadataEmbedFailed")
            }
        }
    }

    func loadDocument(from url: URL) throws -> PDFDocument {
        try DocumentImportConverter.pdfDocument(from: url)
    }

    /// Concatenate member documents into one PDFDocument for display.
    /// Each member is preceded by a styled BoundaryPage header.
    /// Pass `includeBanners: false` to build a plain export PDF.
    ///
    /// The display path (`includeBanners: true`) shares the live PDFPage objects with
    /// their member PDFDocuments so that annotations written to a page are reflected in
    /// combinedPDF without a rebuild. Do NOT change this sharing intentionally.
    ///
    /// The export path (`includeBanners: false`) must not hand out pages that are still
    /// live in a member PDFDocument, so the live combinedPDF retains sole ownership.
    /// It intentionally does NOT use `PDFPage.copy()` to get there: pages produced by
    /// `PDFEditedPageRenderer` are built from raw CGContext/CGDataConsumer PDF bytes, and
    /// `PDFPage.copy()` on such a page silently discards all of its content (verified —
    /// every page in the resulting document serializes as blank, not just the edited one).
    /// Instead each member is re-serialized and re-decoded into a standalone PDFDocument;
    /// its pages are then independent objects that were never inserted anywhere else, so
    /// they can be moved into `combined` directly with no sharing risk and no data loss.
    func concatenate(documents: [(MemberDocument, PDFDocument)], includeBanners: Bool = true) -> PDFDocument {
        let combined = PDFDocument()
        var insertIndex = 0
        for (member, pdf) in documents {
            if includeBanners {
                let width = pdf.page(at: 0)?.bounds(for: .mediaBox).width ?? 612
                let banner = BoundaryPage(
                    documentName: member.displayName,
                    pageCount: pdf.pageCount,
                    width: width
                )
                combined.insert(banner, at: insertIndex)
                insertIndex += 1
            }
            if includeBanners {
                // Display: share the live page so annotations persist across rebuilds.
                for i in 0..<pdf.pageCount {
                    if let page = pdf.page(at: i) {
                        combined.insert(page, at: insertIndex)
                        insertIndex += 1
                    }
                }
            } else {
                guard let memberData = PDFSerializer.data(from: pdf),
                      let freshMemberDoc = PDFDocument(data: memberData) else { continue }
                for i in 0..<freshMemberDoc.pageCount {
                    if let page = freshMemberDoc.page(at: i) {
                        combined.insert(page, at: insertIndex)
                        insertIndex += 1
                    }
                }
            }
        }
        return combined
    }

    func concatenateForExport(documents: [(MemberDocument, PDFDocument)]) throws -> PDFDocument {
        let combined = PDFDocument()
        var insertIndex = 0
        /// Every member's bookmarks, rebased onto the assembled page numbering as we go.
        /// Collected during the walk because a member's page offset is only known here.
        var bookmarks: [PDFOutlineBuilder.Heading] = []
        for (member, pdf) in documents {
            guard let memberData = PDFSerializer.data(from: pdf),
                  let freshMemberDoc = PDFDocument(data: memberData),
                  freshMemberDoc.pageCount == pdf.pageCount else {
                throw ExportAssemblyError.unreadableMember(member.displayName)
            }
            let pageOffset = insertIndex
            for pageIndex in 0..<freshMemberDoc.pageCount {
                guard let page = freshMemberDoc.page(at: pageIndex) else {
                    throw ExportAssemblyError.unreadableMember(member.displayName)
                }
                combined.insert(page, at: insertIndex)
                insertIndex += 1
            }
            // Read the flattened tree rather than walking `PDFOutline` again: the reader
            // already drops blank labels and destinations whose page has gone, so only
            // bookmarks that still resolve are carried forward. `depth + 1` becomes the
            // builder's level, which reproduces the original nesting by containment and
            // keeps each member's top level top-level instead of nesting members.
            //
            // Read from `pdf`, whose destinations callers have already re-anchored (see
            // `PDFOutlineBuilder.reanchoring`), not from `freshMemberDoc` — one more
            // serialization hop is one more chance to inherit a drifted destination.
            bookmarks += PDFOutlineReader.nodes(in: pdf).map { node in
                PDFOutlineBuilder.Heading(
                    title: node.title,
                    level: node.depth + 1,
                    pageIndex: pageOffset + node.localPageIndex
                )
            }
        }
        guard combined.pageCount > 0 else {
            throw ExportAssemblyError.emptyDocument
        }
        // `combined` is a fresh PDFDocument that only received pages, so its
        // document-level `/Info` dictionary (Title/Author/Subject/Keywords) is empty.
        // Without this, every Save/Export drops the metadata the editor wrote onto the
        // member docs. The merged file is one document with one `/Info` dict; for a
        // multi-member workspace we adopt the first member's attributes — the same
        // member whose identity the assembled document effectively takes on.
        if let attributes = documents.first?.1.documentAttributes {
            combined.documentAttributes = attributes
        }
        // Bookmarks are document-level state too, and are lost for the same reason the
        // attributes above were. Rebuilt rather than reassigned: the members' own
        // `PDFDestination`s point at pages in their source documents, so handing that tree
        // over verbatim would give the export destinations pointing outside it.
        combined.outlineRoot = PDFOutlineBuilder.outline(from: bookmarks, in: combined)
        return combined
    }
}

enum DocumentImportConverter {
    struct ImportedDocument {
        var pdfDocument: PDFDocument
        var sourcePayload: SourceDocumentPayload?
        /// Exact PDF bytes that produced `pdfDocument`, set only when the source was
        /// already a PDF file (raw bytes, or qpdf-repaired bytes if PDFKit needed repair
        /// to open it). `nil` when the document was synthesized from HTML/image/text/RTFD
        /// — those have no faithful original byte stream. Import prefers these bytes (after
        /// a qpdf hardening pass, see `PDFImportNormalizer`) over re-serializing through
        /// PDFKit, whose rebuild can destroy an intact text layer (e.g. Chrome/Skia
        /// print-to-PDF Type 3 fonts).
        var originalPDFData: Data?
    }

    enum ConversionError: Error {
        case unsupportedType
        case passwordProtected
        case unreadableDocument
        case emptyDocument
        case binaryDataMislabelledAsText
        case renderingFailed
        case renderTimedOut
        case fileTooLarge(Int64)
        case fileTypeTooLarge(typeDescription: String, actualBytes: Int64, limitBytes: Int64)
        case htmlRenderedTooLarge(pageEstimate: Int, maxPages: Int)
        case documentRenderedTooLarge(maxPages: Int)
    }

    static let maxImportBytes: Int64 = 512 * 1024 * 1024
    private static let maxHTMLImportBytes: Int64 = 25 * 1024 * 1024
    private static let maxTextImportBytes: Int64 = 50 * 1024 * 1024
    private static let maxImageImportBytes: Int64 = 100 * 1024 * 1024
    private static let maxRichDocumentImportBytes: Int64 = 100 * 1024 * 1024
    private static let maxPackageImportBytes: Int64 = 100 * 1024 * 1024
    private static let maxUnknownPreSniffBytes: Int64 = 100 * 1024 * 1024
    static let maxRenderedHTMLPages = 300
    static let maxRenderedTextPages = 500

    private static let byteCountFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    static func userMessage(for error: Error) -> String {
        switch error {
        case ImportFailureKind.permissionDenied:
            return L10n.string("error.import.permissionDenied")
        case ImportFailureKind.staleBookmark:
            return L10n.string("error.import.staleBookmark")
        case ImportFailureKind.fileMissing:
            return L10n.string("error.import.fileMissing")
        case ImportFailureKind.corruptOrEncrypted:
            return L10n.string("error.import.corruptOrEncrypted")
        case ImportFailureKind.iCloudNotDownloaded:
            return L10n.string("error.import.iCloudNotDownloaded")
        case ImportFailureKind.exportTempMissing:
            return L10n.string("error.import.exportTempMissing")
        case ImportFailureKind.unsupportedType:
            return L10n.string("error.import.unsupportedFileType")
        case ImportFailureKind.tooLarge:
            return L10n.string("error.import.fileTooLarge")
        case ConversionError.unsupportedType:
            return L10n.string("error.import.unsupportedFileType")
        case ConversionError.passwordProtected:
            return L10n.string("error.import.passwordProtected")
        case ConversionError.unreadableDocument:
            return L10n.string("error.import.unreadableDocument")
        case ConversionError.emptyDocument:
            return L10n.string("error.import.emptyDocument")
        case ConversionError.binaryDataMislabelledAsText:
            return L10n.string("error.import.binaryDataMislabelledAsText")
        case ConversionError.renderingFailed:
            return L10n.string("error.import.renderingFailed")
        case ConversionError.renderTimedOut:
            return L10n.string("error.import.renderTimedOut")
        case ConversionError.fileTooLarge(let byteCount):
            let actual = byteCountFormatter.string(fromByteCount: byteCount)
            let limit = byteCountFormatter.string(fromByteCount: maxImportBytes)
            return String(localized: "The file is \(actual), which is larger than the \(limit) import safety limit.", locale: L10n.currentLocale)
        case ConversionError.fileTypeTooLarge(let typeDescription, let actualBytes, let limitBytes):
            let actual = byteCountFormatter.string(fromByteCount: actualBytes)
            let limit = byteCountFormatter.string(fromByteCount: limitBytes)
            return String(localized: "This \(typeDescription) file is \(actual), which is larger than Orifold can safely convert directly (\(limit)). Try exporting it to PDF first, then import the PDF.", locale: L10n.currentLocale)
        case ConversionError.htmlRenderedTooLarge(let pageEstimate, let maxPages):
            return String(localized: "This HTML file would render to about \(pageEstimate) pages, which is over Orifold's \(maxPages)-page HTML conversion limit. Try printing or exporting it to PDF from a browser, then import the PDF.", locale: L10n.currentLocale)
        case ConversionError.documentRenderedTooLarge(let maxPages):
            return String(localized: "This file would render to more than \(maxPages) pages, so Orifold stopped the import before creating a partial PDF. Try exporting it to PDF first, then import the PDF.", locale: L10n.currentLocale)
        default:
            return String(localized: "The file could not be opened: \(error.localizedDescription)", locale: L10n.currentLocale)
        }
    }

    static func pdfDocument(from url: URL) throws -> PDFDocument {
        try importedDocument(from: url).pdfDocument
    }

    static func importedDocument(from url: URL) throws -> ImportedDocument {
        guard url.isFileURL else { throw ConversionError.unsupportedType }
        let resourceType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType
        let suggestedType = suggestedContentType(for: url, resourceType: resourceType)
        if suggestedType.conforms(to: .orifoldRTFD) {
            return try importedRTFDDocument(from: url)
        }
        if let byteCount = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
            try validateByteCount(Int64(byteCount), contentType: suggestedType)
            if SourceDocumentFormat(contentType: suggestedType) == nil,
               !suggestedType.conforms(to: .pdf),
               !suggestedType.conforms(to: .image),
               Int64(byteCount) > maxUnknownPreSniffBytes {
                throw ConversionError.fileTypeTooLarge(
                    typeDescription: "unknown",
                    actualBytes: Int64(byteCount),
                    limitBytes: maxUnknownPreSniffBytes
                )
            }
        }
        let data = try Data(contentsOf: url)
        let detectedType = detectedContentType(data: data, suggestedContentType: suggestedType, filename: url.lastPathComponent)
        return try importedDocument(
            from: data,
            contentType: detectedType,
            filename: url.lastPathComponent,
            // Let HTML resolve relative CSS and image URLs the same way it would
            // when opened directly in a browser.
            baseURL: detectedType.conforms(to: .html) || detectedType.conforms(to: .orifoldSVG) ? url.deletingLastPathComponent() : nil
        )
    }

    static func importedDocumentAsync(from url: URL) async throws -> ImportedDocument {
        guard url.isFileURL else { throw ConversionError.unsupportedType }
        let resourceType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType
        let suggestedType = suggestedContentType(for: url, resourceType: resourceType)
        if suggestedType.conforms(to: .orifoldRTFD) {
            return try await MainActor.run {
                try importedRTFDDocument(from: url)
            }
        }
        if let byteCount = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
            try validateByteCount(Int64(byteCount), contentType: suggestedType)
            if SourceDocumentFormat(contentType: suggestedType) == nil,
               !suggestedType.conforms(to: .pdf),
               !suggestedType.conforms(to: .image),
               Int64(byteCount) > maxUnknownPreSniffBytes {
                throw ConversionError.fileTypeTooLarge(
                    typeDescription: "unknown",
                    actualBytes: Int64(byteCount),
                    limitBytes: maxUnknownPreSniffBytes
                )
            }
        }
        let data = try Data(contentsOf: url)
        let detectedType = detectedContentType(data: data, suggestedContentType: suggestedType, filename: url.lastPathComponent)
        return try await importedDocumentAsync(
            from: data,
            contentType: detectedType,
            filename: url.lastPathComponent,
            baseURL: detectedType.conforms(to: .html) || detectedType.conforms(to: .orifoldSVG) ? url.deletingLastPathComponent() : nil
        )
    }

    static func pdfDocument(from data: Data, contentType: UTType, filename: String, baseURL: URL?) throws -> PDFDocument {
        try importedDocument(from: data, contentType: contentType, filename: filename, baseURL: baseURL).pdfDocument
    }

    static func importedDocument(from data: Data, contentType: UTType, filename: String, baseURL: URL?) throws -> ImportedDocument {
        let detectedType = detectedContentType(data: data, suggestedContentType: contentType, filename: filename)
        try validateByteCount(Int64(data.count), contentType: detectedType)

        if data.isEmpty && !detectedType.conforms(to: .plainText) && !detectedType.conforms(to: .text) {
            throw ConversionError.emptyDocument
        }

        if detectedType.conforms(to: .pdf) {
            var document = PDFDocument(data: data)
            // The exact bytes that produced `document`, threaded to the importer so it can
            // preserve this PDF's real object graph (and text layer) instead of a lossy
            // PDFKit re-serialization. See `PDFImportNormalizer`.
            var sourceBytes: Data? = data
            if document == nil {
                // PDFKit gave up; qpdf's recovery scans for objects by brute
                // force and can often rebuild a valid document from a broken
                // xref table, missing trailer, or other structural damage
                // PDFKit won't tolerate.
                if let repaired = QPDFService.repaired(data) {
                    document = PDFDocument(data: repaired)
                    sourceBytes = repaired
                }
            }
            guard let document else { throw ConversionError.unreadableDocument }
            // A locked document's page count is unreliable before unlocking --
            // PDFKit can't read the page tree if it lives inside an encrypted
            // object stream, so it reports 0 pages even for a normal,
            // non-empty encrypted PDF. Defer the empty check until after the
            // password prompt unlocks it.
            guard document.isLocked || document.pageCount > 0 else { throw ConversionError.emptyDocument }
            // Encrypted PDFs keep the serialize-from-PDFDocument path (originalPDFData nil):
            // their on-disk bytes are ciphertext qpdf/PDFium can't harden or agreement-check
            // without the password, and unlocking already forces a re-encode.
            return ImportedDocument(
                pdfDocument: document,
                sourcePayload: nil,
                originalPDFData: document.isLocked ? nil : sourceBytes
            )
        }
        if detectedType.conforms(to: .orifoldSVG) {
            return ImportedDocument(pdfDocument: try renderImage(data, title: filename), sourcePayload: nil)
        }
        if detectedType.conforms(to: .image) {
            return ImportedDocument(pdfDocument: try renderImage(data, title: filename), sourcePayload: nil)
        }

        if detectedType.conforms(to: .html) {
            let plainHTML = try decodeText(data)
            let attributedString = try loadAttributedString(from: data, documentType: .html, baseURL: baseURL)
            let pdf = try renderAttributedString(attributedString, title: filename)
            return ImportedDocument(
                pdfDocument: pdf,
                sourcePayload: sourcePayload(
                    for: data,
                    contentType: detectedType,
                    filename: filename,
                    attributedString: NSAttributedString(string: plainHTML),
                    plainText: plainHTML,
                    renderedPageCount: pdf.pageCount
                )
            )
        }
        if detectedType.conforms(to: .orifoldXLSX) {
            return try importedExtractedTextDocument(
                text: OfficePackageTextExtractor.spreadsheetText(from: data),
                sourceData: data,
                filename: filename,
                contentType: detectedType
            )
        }
        if detectedType.conforms(to: .orifoldPPTX) {
            return try importedExtractedTextDocument(
                text: OfficePackageTextExtractor.presentationText(from: data),
                sourceData: data,
                filename: filename,
                contentType: detectedType
            )
        }
        if detectedType.conforms(to: .orifoldEPUB) {
            return try importedExtractedTextDocument(
                text: OfficePackageTextExtractor.epubText(from: data),
                sourceData: data,
                filename: filename,
                contentType: detectedType
            )
        }

        let attributedString: NSAttributedString
        if detectedType.conforms(to: .docx) {
            attributedString = try loadAttributedString(from: data, documentType: .officeOpenXML, baseURL: baseURL)
        } else if detectedType.conforms(to: .wordDoc) {
            attributedString = try loadAttributedString(from: data, documentType: .docFormat, baseURL: baseURL)
        } else if detectedType.conforms(to: .odt) {
            attributedString = try loadAttributedString(from: data, documentType: .openDocument, baseURL: baseURL)
        } else if detectedType.conforms(to: .rtf) {
            attributedString = try loadAttributedString(from: data, documentType: .rtf, baseURL: baseURL)
        } else if detectedType.conforms(to: .markdown) {
            attributedString = try loadMarkdown(from: data, baseURL: baseURL)
        } else if detectedType.conforms(to: .propertyList) {
            attributedString = try loadPlainText(from: Data(propertyListText(from: data).utf8))
        } else if isPlainTextLike(detectedType) {
            attributedString = try loadPlainText(from: data)
        } else {
            throw ConversionError.unsupportedType
        }

        let pdf = try renderAttributedString(attributedString, title: filename)
        return ImportedDocument(
            pdfDocument: pdf,
            sourcePayload: sourcePayload(
                for: data,
                contentType: detectedType,
                filename: filename,
                attributedString: attributedString,
                plainText: plainTextForSourcePayload(data, contentType: detectedType),
                renderedPageCount: pdf.pageCount
            )
        )
    }

    static func importedDocumentAsync(
        from data: Data,
        contentType: UTType,
        filename: String,
        baseURL: URL?,
        htmlRenderTimeout: TimeInterval = 30
    ) async throws -> ImportedDocument {
        let detectedType = detectedContentType(data: data, suggestedContentType: contentType, filename: filename)
        try validateByteCount(Int64(data.count), contentType: detectedType)

        if data.isEmpty && !detectedType.conforms(to: .plainText) && !detectedType.conforms(to: .text) {
            throw ConversionError.emptyDocument
        }

        if !detectedType.conforms(to: .html) && !detectedType.conforms(to: .orifoldSVG) {
            return try await MainActor.run {
                try importedDocument(from: data, contentType: detectedType, filename: filename, baseURL: baseURL)
            }
        }

        let plainMarkup = try decodeText(data)
        let pdf = try await renderMarkup(data, contentType: detectedType, title: filename, baseURL: baseURL, timeout: htmlRenderTimeout)
        if detectedType.conforms(to: .orifoldSVG) {
            return ImportedDocument(pdfDocument: pdf, sourcePayload: nil)
        }
        return ImportedDocument(
            pdfDocument: pdf,
            sourcePayload: sourcePayload(
                for: data,
                contentType: detectedType.conforms(to: .html) ? detectedType : .plainText,
                filename: filename,
                attributedString: NSAttributedString(string: plainMarkup),
                plainText: plainMarkup,
                renderedPageCount: pdf.pageCount
            )
        )
    }

    static func detectedContentType(data: Data, suggestedContentType: UTType, filename: String) -> UTType {
        if let strongType = stronglyDetectedContentType(data: data, suggestedContentType: suggestedContentType, filename: filename) {
            return strongType
        }
        if looksLikeMarkdown(data) {
            return .markdown
        }
        if SourceDocumentFormat(contentType: suggestedContentType) != nil || suggestedContentType.conforms(to: .pdf) || suggestedContentType.conforms(to: .image) || suggestedContentType.conforms(to: .orifoldSVG) {
            return suggestedContentType
        }
        if let extensionType = UTType(filenameExtension: URL(fileURLWithPath: filename).pathExtension),
           SourceDocumentFormat(contentType: extensionType) != nil || extensionType.conforms(to: .pdf) || extensionType.conforms(to: .image) || extensionType.conforms(to: .orifoldSVG) {
            return extensionType
        }
        if isDecodableText(data), !looksLikeBinary(data) {
            return .plainText
        }
        return suggestedContentType
    }

    private static func sourcePayload(
        for data: Data,
        contentType: UTType,
        filename: String,
        attributedString: NSAttributedString,
        plainText: String?,
        renderedPageCount: Int
    ) -> SourceDocumentPayload? {
        guard let format = SourceDocumentFormat(contentType: contentType) else { return nil }
        return SourceDocumentPayload(
            format: format,
            originalFilename: filename,
            originalContentTypeIdentifier: contentType.identifier,
            originalData: data,
            richTextRTFData: SourceDocumentPayload.richTextRTFData(from: attributedString),
            plainText: plainText,
            renderedPageCount: renderedPageCount
        )
    }

    private static func validateByteCount(_ byteCount: Int64, contentType: UTType) throws {
        guard byteCount <= maxImportBytes else {
            throw ConversionError.fileTooLarge(byteCount)
        }

        let typedLimit: (description: String, bytes: Int64)?
        if contentType.conforms(to: .html) {
            typedLimit = ("HTML", maxHTMLImportBytes)
        } else if contentType.conforms(to: .image) {
            typedLimit = ("image", maxImageImportBytes)
        } else if contentType.conforms(to: .docx) || contentType.conforms(to: .wordDoc) || contentType.conforms(to: .odt) || contentType.conforms(to: .rtf) || contentType.conforms(to: .orifoldRTFD) {
            typedLimit = ("document", maxRichDocumentImportBytes)
        } else if contentType.conforms(to: .orifoldXLSX) || contentType.conforms(to: .orifoldPPTX) || contentType.conforms(to: .orifoldEPUB) {
            typedLimit = ("package", maxPackageImportBytes)
        } else if isPlainTextLike(contentType) || contentType.conforms(to: .markdown) {
            typedLimit = ("text", maxTextImportBytes)
        } else {
            typedLimit = nil
        }

        if let typedLimit, byteCount > typedLimit.bytes {
            throw ConversionError.fileTypeTooLarge(
                typeDescription: typedLimit.description,
                actualBytes: byteCount,
                limitBytes: typedLimit.bytes
            )
        }
    }

    private static func renderMarkup(_ data: Data, contentType: UTType, title: String, baseURL: URL?, timeout: TimeInterval) async throws -> PDFDocument {
        let markup = try decodeText(data)
        let html = contentType.conforms(to: .orifoldSVG)
            ? svgHTMLDocument(markup)
            : markup
        let document: PDFDocument
        do {
            let pdfData = try await HTMLPDFRenderer.render(
                html: html,
                baseURL: baseURL,
                timeout: timeout,
                maxPages: maxRenderedHTMLPages
            )
            let paginatedData = try paginateRenderedHTMLPDFData(pdfData)
            guard let webDocument = PDFDocument(data: paginatedData) else { throw ConversionError.renderingFailed }
            document = webDocument
        } catch ConversionError.htmlRenderedTooLarge(let pageEstimate, let maxPages) {
            throw ConversionError.htmlRenderedTooLarge(pageEstimate: pageEstimate, maxPages: maxPages)
        } catch ConversionError.renderTimedOut {
            document = try await MainActor.run {
                return try renderAttributedString(try loadPlainText(from: data), title: title)
            }
        } catch {
            document = try await MainActor.run {
                let attributed = try loadAttributedString(from: data, documentType: .html, baseURL: baseURL)
                return try renderAttributedString(attributed, title: title)
            }
        }
        document.documentAttributes = [
            PDFDocumentAttribute.titleAttribute: URL(fileURLWithPath: title).deletingPathExtension().lastPathComponent
        ]
        return document
    }

    private static func svgHTMLDocument(_ svg: String) -> String {
        """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <style>
            html, body { margin: 0; width: 612px; min-height: 792px; background: white; }
            body { display: flex; align-items: center; justify-content: center; }
            svg { max-width: 100%; max-height: 100vh; }
          </style>
        </head>
        <body>
        \(svg)
        </body>
        </html>
        """
    }

    private static func paginateRenderedHTMLPDFData(_ data: Data) throws -> Data {
        guard let source = PDFDocument(data: data), source.pageCount > 0 else {
            throw ConversionError.renderingFailed
        }

        let pageSize = HTMLPDFRenderer.pageSize
        let output = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let consumer = CGDataConsumer(data: output as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw ConversionError.renderingFailed
        }

        for pageIndex in 0..<source.pageCount {
            guard let sourcePage = source.page(at: pageIndex) else { continue }
            let sourceBox = sourcePage.bounds(for: .mediaBox)
            guard sourceBox.width > 0, sourceBox.height > 0 else { continue }

            let sliceCount = max(1, Int(ceil(sourceBox.height / pageSize.height)))
            for sliceIndex in 0..<sliceCount {
                context.beginPDFPage(nil)
                context.saveGState()
                context.setFillColor(NSColor.white.cgColor)
                context.fill(mediaBox)
                context.clip(to: mediaBox)

                let topOffset = max(0, sourceBox.height - CGFloat(sliceIndex + 1) * pageSize.height)
                context.translateBy(x: -sourceBox.minX, y: -sourceBox.minY - topOffset)
                sourcePage.draw(with: .mediaBox, to: context)
                context.restoreGState()
                context.endPDFPage()
            }
        }

        context.closePDF()
        guard output.length > 0 else { throw ConversionError.renderingFailed }
        return output as Data
    }

    private static func loadAttributedString(
        from data: Data,
        documentType: NSAttributedString.DocumentType,
        baseURL: URL?
    ) throws -> NSAttributedString {
        var options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: documentType
        ]
        if documentType == .html {
            options[.characterEncoding] = String.Encoding.utf8.rawValue
        }
        if let baseURL {
            options[.baseURL] = baseURL
        }
        return try NSAttributedString(data: data, options: options, documentAttributes: nil)
    }

    static func importedRTFDDocument(fromFileWrappers fileWrappers: [String: FileWrapper], filename: String) throws -> ImportedDocument {
        let wrapper = FileWrapper(directoryWithFileWrappers: fileWrappers)
        try validateByteCount(Int64(rtfdPackageByteCount(in: wrapper)), contentType: .orifoldRTFD)
        return try importedRTFDFileWrapper(wrapper, title: filename)
    }

    private static func importedRTFDDocument(from url: URL) throws -> ImportedDocument {
        try validateByteCount(Int64(rtfdPackageByteCount(at: url)), contentType: .orifoldRTFD)
        let wrapper = try FileWrapper(url: url, options: [.immediate])
        return try importedRTFDFileWrapper(wrapper, title: url.lastPathComponent)
    }

    private static func importedRTFDFileWrapper(_ wrapper: FileWrapper, title: String) throws -> ImportedDocument {
        guard let attributed = NSAttributedString(rtfdFileWrapper: wrapper, documentAttributes: nil) else {
            throw ConversionError.unreadableDocument
        }
        let pdf = try renderAttributedString(attributed, title: title)
        return ImportedDocument(pdfDocument: pdf, sourcePayload: nil)
    }

    private static func rtfdPackageByteCount(at url: URL) throws -> Int {
        let resourceKeys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles]
        ) else {
            throw ConversionError.unreadableDocument
        }
        var byteCount = 0
        for case let child as URL in enumerator {
            let values = try child.resourceValues(forKeys: resourceKeys)
            if values.isRegularFile == true {
                byteCount += values.fileSize ?? 0
            }
        }
        return byteCount
    }

    private static func rtfdPackageByteCount(in wrapper: FileWrapper) -> Int {
        if wrapper.isRegularFile {
            return wrapper.regularFileContents?.count ?? 0
        }
        return wrapper.fileWrappers?.values.reduce(0) { total, child in
            total + rtfdPackageByteCount(in: child)
        } ?? 0
    }

    private static func suggestedContentType(for url: URL, resourceType: UTType?) -> UTType {
        let extensionType = UTType(filenameExtension: url.pathExtension)
        if extensionType?.conforms(to: .orifoldRTFD) == true {
            return extensionType!
        }
        return resourceType ?? extensionType ?? .data
    }

    private static func importedExtractedTextDocument(
        text: String,
        sourceData: Data,
        filename: String,
        contentType: UTType
    ) throws -> ImportedDocument {
        let payloadText = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? L10n.string("content.noExtractableText")
            : text
        let data = Data(payloadText.utf8)
        let attributed = try loadPlainText(from: data)
        let pdf = try renderAttributedString(attributed, title: filename)
        return ImportedDocument(pdfDocument: pdf, sourcePayload: nil)
    }

    private static func loadMarkdown(from data: Data, baseURL: URL?) throws -> NSAttributedString {
        let string = try decodeText(data)
        if let rendered = markdownAttributedString(from: string, baseURL: baseURL) {
            return rendered
        }
        return try loadPlainText(from: data)
    }

    /// Strips HTML comments, parses `.full` markdown, and typesets it (see
    /// `typesetMarkdown`). Returns `nil` when the text can't be parsed as markdown, so
    /// `loadMarkdown` can fall back to plain-text rendering. Internal (not private) so the
    /// typesetting regression suite can assert on the laid-out `NSAttributedString`
    /// directly, without depending on flaky PDF text re-extraction.
    static func markdownAttributedString(from string: String, baseURL: URL?) -> NSAttributedString? {
        // Strip HTML comments (`<!-- … -->`) before parsing: `.full` markdown keeps them
        // as visible text runs, so an authoring/provenance note would otherwise render
        // straight into the page. Comments carry no document content.
        let withoutComments = string.replacingOccurrences(
            of: "<!--[\\s\\S]*?-->", with: "", options: .regularExpression
        )
        guard let attributed = try? AttributedString(
            markdown: withoutComments,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .full),
            baseURL: baseURL
        ) else {
            return nil
        }
        return typesetMarkdown(attributed)
    }

    /// Block-structure classification recovered from a run's `PresentationIntent`,
    /// used to pick fonts and paragraph spacing when typesetting markdown.
    private enum MarkdownBlockKind {
        case heading(level: Int)
        case listItem(ordinal: Int?)
        case blockQuote
        case codeBlock
        case body
    }

    /// Lays out a parsed markdown `AttributedString` into an `NSAttributedString` the PDF
    /// text renderer can actually paginate and style.
    ///
    /// `AttributedString(markdown:, interpretedSyntax: .full)` records block structure
    /// (headings, paragraphs, lists) as `PresentationIntent` attributes and drops the
    /// literal newlines *between* blocks. AppKit's layout system ignores
    /// `PresentationIntent` entirely, so bridging straight through
    /// `NSAttributedString(attributed)` collapses every block into a single run: adjacent
    /// paragraphs' words fuse with no separator ("…Bag of Rice.One day…") and headings
    /// render at body size. This walks the runs, re-inserts a paragraph break at each
    /// block boundary, and assigns fonts by block kind and inline emphasis so imported
    /// markdown reads as a real document.
    ///
    /// Fonts are explicitly *named* (Georgia family), never `NSFont.systemFont`: the system
    /// face embeds into the generated PDF under a private PostScript name (".SFNS-…") that
    /// `NSFont(name:)` later refuses to resolve, which would break reopening this text in
    /// the inline editor — the same trap the plain-text path sidesteps by pinning Menlo.
    /// A FIXED black color (not the dynamic `NSColor.textColor`) keeps text dark even when
    /// the import runs while the app is in dark mode, so it can't bake near-white glyphs
    /// onto the white page.
    private static func typesetMarkdown(_ attributed: AttributedString) -> NSAttributedString {
        let bodySize: CGFloat = 12

        let bodyStyle = NSMutableParagraphStyle()
        bodyStyle.lineSpacing = 3
        bodyStyle.paragraphSpacing = 10
        bodyStyle.lineBreakMode = .byWordWrapping
        let headingStyle = NSMutableParagraphStyle()
        headingStyle.paragraphSpacingBefore = 16
        headingStyle.paragraphSpacing = 6
        headingStyle.lineBreakMode = .byWordWrapping

        func font(bold: Bool, italic: Bool, size: CGFloat) -> NSFont {
            let name: String
            switch (bold, italic) {
            case (true, true): name = "Georgia-BoldItalic"
            case (true, false): name = "Georgia-Bold"
            case (false, true): name = "Georgia-Italic"
            case (false, false): name = "Georgia"
            }
            return NSFont(name: name, size: size)
                ?? NSFont(name: "Georgia", size: size)
                ?? .systemFont(ofSize: size)
        }

        func classify(_ intent: PresentationIntent?) -> MarkdownBlockKind {
            guard let intent else { return .body }
            for component in intent.components {
                if case .header(let level) = component.kind { return .heading(level: level) }
                if case .codeBlock = component.kind { return .codeBlock }
            }
            for component in intent.components {
                if case .listItem(let ordinal) = component.kind {
                    let ordered = intent.components.contains { if case .orderedList = $0.kind { return true }; return false }
                    return .listItem(ordinal: ordered ? ordinal : nil)
                }
                if case .blockQuote = component.kind { return .blockQuote }
            }
            return .body
        }

        func baseSize(_ kind: MarkdownBlockKind) -> CGFloat {
            switch kind {
            case .heading(let level) where level <= 1: return 24
            case .heading(let level) where level == 2: return 17
            case .heading: return 14
            case .codeBlock: return 11
            default: return bodySize
            }
        }

        func paragraphStyle(_ kind: MarkdownBlockKind) -> NSParagraphStyle {
            if case .heading = kind { return headingStyle }
            return bodyStyle
        }

        func prefix(_ kind: MarkdownBlockKind) -> String {
            if case .listItem(let ordinal) = kind {
                if let ordinal { return "\(ordinal).  " }
                return "•  "
            }
            return ""
        }

        let result = NSMutableAttributedString()
        var lastIdentity: Int?
        var isFirstBlock = true
        var currentKind: MarkdownBlockKind = .body

        for run in attributed.runs {
            let intent = run.presentationIntent
            // Runs without a block intent are structural (stripped-comment remnants,
            // inter-block whitespace) — never rendered content in `.full` mode.
            guard let intent else { continue }
            let text = String(attributed[run.range].characters)
            if text.isEmpty { continue }

            let identity = intent.components.first?.identity
            if identity != lastIdentity {
                if !isFirstBlock {
                    // Terminate the previous block; its paragraph style carries the
                    // spacing that follows it.
                    result.append(NSAttributedString(string: "\n", attributes: [
                        .font: font(bold: false, italic: false, size: baseSize(currentKind)),
                        .foregroundColor: NSColor.black,
                        .paragraphStyle: paragraphStyle(currentKind)
                    ]))
                }
                isFirstBlock = false
                lastIdentity = identity
                currentKind = classify(intent)
                let marker = prefix(currentKind)
                if !marker.isEmpty {
                    result.append(NSAttributedString(string: marker, attributes: [
                        .font: font(bold: false, italic: false, size: baseSize(currentKind)),
                        .foregroundColor: NSColor.black,
                        .paragraphStyle: paragraphStyle(currentKind)
                    ]))
                }
            }

            let inline = run.inlinePresentationIntent ?? []
            let headingLevel: Int? = { if case .heading(let level) = currentKind { return level }; return nil }()
            let bold = headingLevel != nil || inline.contains(.stronglyEmphasized)
            let italic = inline.contains(.emphasized) || { if case .blockQuote = currentKind { return true }; return false }()
            var attributes: [NSAttributedString.Key: Any] = [
                .font: font(bold: bold, italic: italic, size: baseSize(currentKind)),
                .foregroundColor: NSColor.black,
                .paragraphStyle: paragraphStyle(currentKind)
            ]
            // Carried to `renderAttributedString`, which turns headings into bookmarks once
            // pagination reveals what page each landed on. Stamped on heading CONTENT only,
            // never the block-terminating newline above — that gap is what keeps two
            // adjacent same-level headings from merging into one bookmark.
            if let headingLevel {
                attributes[PDFOutlineBuilder.headingLevelAttribute] = headingLevel
            }
            result.append(NSAttributedString(string: text, attributes: attributes))
        }

        if result.length == 0 { return NSAttributedString(string: " ") }
        return result
    }

    private static func loadPlainText(from data: Data) throws -> NSAttributedString {
        let string = try decodeText(data)
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byWordWrapping
        style.paragraphSpacing = 6
        // Menlo, not `.monospacedSystemFont`: the system mono embeds into the generated
        // PDF as the private name ".SFNSMono-…", which `NSFont(name:)` refuses to resolve
        // later — so the text-edit pipeline couldn't reopen imported CSV/log/plain-text
        // lines in their own face. Menlo ships on every macOS, embeds under its real
        // PostScript name, and round-trips cleanly through analysis → editor → commit.
        // Likewise a FIXED color, not the dynamic `NSColor.textColor`: a dynamic color is
        // resolved against the CURRENT appearance at draw time, so importing while the
        // app is in dark mode would bake near-WHITE text into the PDF's white page.
        return NSAttributedString(
            string: string.isEmpty ? " " : string,
            attributes: [
                .font: NSFont(name: "Menlo-Regular", size: 11) ?? .monospacedSystemFont(ofSize: 11, weight: .regular),
                .foregroundColor: NSColor.black,
                .paragraphStyle: style
            ]
        )
    }

    private static func propertyListText(from data: Data) throws -> String {
        let propertyList = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        let xml = try PropertyListSerialization.data(fromPropertyList: propertyList, format: .xml, options: 0)
        guard let text = String(data: xml, encoding: .utf8) else {
            throw ConversionError.unreadableDocument
        }
        return text
    }

    private static func plainTextForSourcePayload(_ data: Data, contentType: UTType) -> String? {
        if contentType.conforms(to: .propertyList) {
            return try? propertyListText(from: data)
        }
        if isPlainTextLike(contentType) || contentType.conforms(to: .markdown) {
            return try? decodeText(data)
        }
        return nil
    }

    private static func decodeText(_ data: Data) throws -> String {
        if looksLikeBinary(data) {
            throw ConversionError.binaryDataMislabelledAsText
        }
        let encodings: [String.Encoding] = [.utf8, .utf16, .utf16LittleEndian, .utf16BigEndian, .isoLatin1, .macOSRoman]
        for encoding in encodings {
            if let string = String(data: data, encoding: encoding) {
                return string
            }
        }
        throw ConversionError.unreadableDocument
    }

    private static func stronglyDetectedContentType(data: Data, suggestedContentType: UTType, filename: String) -> UTType? {
        guard !data.isEmpty else { return nil }
        if data.starts(with: Data("%PDF".utf8)) {
            return .pdf
        }
        if data.starts(with: Data([0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1])) {
            let extensionType = UTType(filenameExtension: URL(fileURLWithPath: filename).pathExtension)
            return suggestedContentType.conforms(to: .wordDoc) || extensionType?.conforms(to: .wordDoc) == true ? .wordDoc : nil
        }
        if data.starts(with: Data("{\\rtf".utf8)) {
            return .rtf
        }
        if data.starts(with: Data([0x50, 0x4B, 0x03, 0x04])) ||
            data.starts(with: Data([0x50, 0x4B, 0x05, 0x06])) ||
            data.starts(with: Data([0x50, 0x4B, 0x07, 0x08])) {
            if containsASCII("word/document.xml", in: data) ||
                containsASCII("application/vnd.openxmlformats-officedocument.wordprocessingml.document", in: data) {
                return .docx
            }
            if containsASCII("mimetypeapplication/vnd.oasis.opendocument.text", in: data) ||
                containsASCII("application/vnd.oasis.opendocument.text", in: data) ||
                containsASCII("content.xml", in: data) && containsASCII("office:document-content", in: data) {
                return .odt
            }
            if containsASCII("xl/workbook.xml", in: data) ||
                containsASCII("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", in: data) {
                return .orifoldXLSX
            }
            if containsASCII("ppt/presentation.xml", in: data) ||
                containsASCII("application/vnd.openxmlformats-officedocument.presentationml.presentation", in: data) {
                return .orifoldPPTX
            }
            if containsASCII("mimetypeapplication/epub+zip", in: data) ||
                containsASCII("META-INF/container.xml", in: data) {
                return .orifoldEPUB
            }
        }
        if looksLikeHTML(data) {
            return .html
        }
        if looksLikeSVG(data) {
            return .orifoldSVG
        }
        return nil
    }

    private static func containsASCII(_ needle: String, in data: Data) -> Bool {
        data.range(of: Data(needle.utf8)) != nil
    }

    private static func looksLikeHTML(_ data: Data) -> Bool {
        guard let prefix = String(data: data.prefix(4096), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        else { return false }
        return prefix.hasPrefix("<!doctype html") ||
            prefix.hasPrefix("<html") ||
            prefix.contains("<html") ||
            prefix.contains("<body") ||
            prefix.contains("<head")
    }

    private static func looksLikeSVG(_ data: Data) -> Bool {
        guard let prefix = String(data: data.prefix(4096), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        else { return false }
        return prefix.hasPrefix("<svg") || prefix.contains("<svg")
    }

    private static func looksLikeMarkdown(_ data: Data) -> Bool {
        guard let text = String(data: data.prefix(16 * 1024), encoding: .utf8), !looksLikeBinary(data) else {
            return false
        }
        let lines = text.split(whereSeparator: \.isNewline)
        guard !lines.isEmpty else { return false }
        let markdownMarkers = lines.filter { line in
            line.hasPrefix("# ") ||
                line.hasPrefix("## ") ||
                line.hasPrefix("- ") ||
                line.hasPrefix("* ") ||
                line.hasPrefix("> ") ||
                line.contains("](") ||
                line.contains("**") ||
                line.contains("__")
        }
        return markdownMarkers.count >= min(1, lines.count)
    }

    private static func isDecodableText(_ data: Data) -> Bool {
        guard !data.isEmpty else { return true }
        return String(data: data, encoding: .utf8) != nil ||
            String(data: data, encoding: .utf16) != nil ||
            String(data: data, encoding: .isoLatin1) != nil
    }

    private static func looksLikeBinary(_ data: Data) -> Bool {
        guard !data.isEmpty else { return false }
        let sample = data.prefix(8192)
        if sample.contains(0) { return true }
        let controlCount = sample.reduce(0) { count, byte in
            if byte == 9 || byte == 10 || byte == 13 { return count }
            return byte < 32 ? count + 1 : count
        }
        return Double(controlCount) / Double(sample.count) > 0.05
    }

    private static func isPlainTextLike(_ contentType: UTType) -> Bool {
        [.plainText, .text, .csv, .orifoldTSV, .json, .xml, .orifoldYAML, .orifoldTOML, .propertyList, .orifoldLog, .orifoldSourceCode, .orifoldShellScript, .orifoldSQL].contains { contentType.conforms(to: $0) }
    }

    private static func renderImage(_ data: Data, title: String) throws -> PDFDocument {
        guard let image = NSImage(data: data) else { throw ConversionError.unreadableDocument }
        let pageSize = CGSize(width: 612, height: 792)
        let margin: CGFloat = 36
        let pageView = ImagePDFPageView(
            frame: CGRect(origin: .zero, size: pageSize),
            image: image,
            margin: margin
        )
        let data = pageView.dataWithPDF(inside: pageView.bounds)
        guard let document = PDFDocument(data: data) else { throw ConversionError.renderingFailed }
        document.documentAttributes = [
            PDFDocumentAttribute.titleAttribute: URL(fileURLWithPath: title).deletingPathExtension().lastPathComponent
        ]
        return document
    }

    private static func renderAttributedString(_ source: NSAttributedString, title: String) throws -> PDFDocument {
        let content = source.length == 0 ? NSAttributedString(string: " ") : source
        let pageSize = CGSize(width: 612, height: 792)
        let margin: CGFloat = 54
        let textSize = CGSize(width: pageSize.width - margin * 2, height: pageSize.height - margin * 2)
        let storage = NSTextStorage(attributedString: content)
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)

        let output = PDFDocument()
        var pageIndex = 0
        /// Character range each emitted page covers, held parallel to `output`'s pages.
        /// A heading's page is only knowable here, once the layout manager has decided
        /// where the text broke.
        var pageCharacterRanges: [NSRange] = []

        while pageIndex == 0 || layoutManager.numberOfGlyphs > 0 {
            let textContainer = NSTextContainer(size: textSize)
            textContainer.lineFragmentPadding = 0
            layoutManager.addTextContainer(textContainer)

            let glyphRange = layoutManager.glyphRange(for: textContainer)
            if glyphRange.length == 0 && pageIndex > 0 {
                layoutManager.removeTextContainer(at: layoutManager.textContainers.count - 1)
                break
            }

            let pageView = TextPDFPageView(
                frame: CGRect(origin: .zero, size: pageSize),
                layoutManager: layoutManager,
                textContainer: textContainer,
                glyphRange: glyphRange,
                margin: margin
            )
            let data = pageView.dataWithPDF(inside: pageView.bounds)
            guard let singlePagePDF = PDFDocument(data: data),
                  let page = singlePagePDF.page(at: 0) else {
                throw ConversionError.renderingFailed
            }
            output.insert(page, at: output.pageCount)
            pageCharacterRanges.append(
                layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
            )

            pageIndex += 1
            if NSMaxRange(glyphRange) >= layoutManager.numberOfGlyphs { break }
            if pageIndex >= maxRenderedTextPages {
                throw ConversionError.documentRenderedTooLarge(maxPages: maxRenderedTextPages)
            }
        }

        // Markdown headings become embedded bookmarks, so an imported document arrives with
        // a real table of contents. Every other caller of this renderer (plain text, CSV,
        // extracted OCR text) stamps no heading attribute and falls through with no outline.
        let headings = PDFOutlineBuilder.headings(in: content, pageCharacterRanges: pageCharacterRanges)
        if let outline = PDFOutlineBuilder.outline(from: headings, in: output) {
            output.outlineRoot = outline
        }

        output.documentAttributes = [
            PDFDocumentAttribute.titleAttribute: URL(fileURLWithPath: title).deletingPathExtension().lastPathComponent
        ]
        return output
    }
}

private final class ImagePDFPageView: NSView {
    private let image: NSImage
    private let margin: CGFloat

    override var isFlipped: Bool { true }

    init(frame: CGRect, image: NSImage, margin: CGFloat) {
        self.image = image
        self.margin = margin
        super.init(frame: frame)
        wantsLayer = false
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        bounds.fill()

        let available = bounds.insetBy(dx: margin, dy: margin)
        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0 else { return }

        let scale = min(available.width / imageSize.width, available.height / imageSize.height)
        let drawSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let rect = CGRect(
            x: available.midX - drawSize.width / 2,
            y: available.midY - drawSize.height / 2,
            width: drawSize.width,
            height: drawSize.height
        )
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
    }
}

private final class TextPDFPageView: NSView {
    private let layoutManager: NSLayoutManager
    private let textContainer: NSTextContainer
    private let glyphRange: NSRange
    private let margin: CGFloat

    override var isFlipped: Bool { true }

    init(
        frame: CGRect,
        layoutManager: NSLayoutManager,
        textContainer: NSTextContainer,
        glyphRange: NSRange,
        margin: CGFloat
    ) {
        self.layoutManager = layoutManager
        self.textContainer = textContainer
        self.glyphRange = glyphRange
        self.margin = margin
        super.init(frame: frame)
        wantsLayer = false
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        bounds.fill()
        let origin = CGPoint(x: margin, y: margin)
        layoutManager.drawBackground(forGlyphRange: glyphRange, at: origin)
        layoutManager.drawGlyphs(forGlyphRange: glyphRange, at: origin)
    }
}

private enum OfficePackageTextExtractor {
    static func spreadsheetText(from data: Data) throws -> String {
        let archive = try SimpleZIPArchive(data: data)
        let sharedStrings = archive.text(named: "xl/sharedStrings.xml")
            .map { xmlText(in: $0, elementName: "t") } ?? []
        let orderedSheets = spreadsheetSheetOrder(in: archive)
        let fallbackSheets = archive.entryNames
            .filter { $0.hasPrefix("xl/worksheets/sheet") && $0.hasSuffix(".xml") }
            .sorted(by: naturalPathCompare)
            .map { (name: sheetDisplayName(from: $0), path: $0) }
        let sheets = orderedSheets.isEmpty ? fallbackSheets : orderedSheets

        var sections: [String] = []
        for (index, sheet) in sheets.enumerated() {
            guard let xml = archive.text(named: sheet.path) else { continue }
            let body = spreadsheetCellValues(in: xml, sharedStrings: sharedStrings)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            if !body.isEmpty {
                let title = sheet.name.isEmpty ? "Sheet \(index + 1)" : sheet.name
                sections.append("\(title)\n\(body)")
            }
        }
        return sections.joined(separator: "\n\n")
    }

    static func presentationText(from data: Data) throws -> String {
        let archive = try SimpleZIPArchive(data: data)
        let slides = archive.entryNames
            .filter { $0.hasPrefix("ppt/slides/slide") && $0.hasSuffix(".xml") }
            .sorted(by: naturalPathCompare)

        return slides.enumerated().compactMap { index, slide in
            guard let xml = archive.text(named: slide) else { return nil }
            let body = xmlText(in: xml, elementName: "t")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            let notesPath = slide.replacingOccurrences(of: "ppt/slides/slide", with: "ppt/notesSlides/notesSlide")
            let notes = archive.text(named: notesPath)
                .map { xmlText(in: $0, elementName: "t") }?
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n") ?? ""
            let combined = [body, notes.isEmpty ? nil : "Notes\n\(notes)"]
                .compactMap { $0 }
                .joined(separator: "\n")
            return combined.isEmpty ? nil : "Slide \(index + 1)\n\(combined)"
        }.joined(separator: "\n\n")
    }

    static func epubText(from data: Data) throws -> String {
        let archive = try SimpleZIPArchive(data: data)
        let spineDocuments = epubSpineOrder(in: archive)
        let fallbackDocuments = archive.entryNames
            .filter { name in
                let lower = name.lowercased()
                return lower.hasSuffix(".xhtml") || lower.hasSuffix(".html") || lower.hasSuffix(".htm")
            }
            .sorted(by: naturalPathCompare)
        let documents = spineDocuments.isEmpty ? fallbackDocuments : spineDocuments

        return documents.compactMap { name in
            guard let html = archive.text(named: name) else { return nil }
            let text = plainTextFromMarkup(html)
            return text.isEmpty ? nil : text
        }.joined(separator: "\n\n")
    }

    private static func xmlText(in xml: String, elementName: String) -> [String] {
        let pattern = "<(?:[A-Za-z0-9_\\-]+:)?\(NSRegularExpression.escapedPattern(for: elementName))\\b[^>]*>(.*?)</(?:[A-Za-z0-9_\\-]+:)?\(NSRegularExpression.escapedPattern(for: elementName))>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]) else {
            return []
        }
        let nsRange = NSRange(xml.startIndex..<xml.endIndex, in: xml)
        return regex.matches(in: xml, range: nsRange).compactMap { match in
            guard let range = Range(match.range(at: 1), in: xml) else { return nil }
            return xmlUnescaped(String(xml[range]))
        }
    }

    private static func spreadsheetCellValues(in xml: String, sharedStrings: [String]) -> [String] {
        let pattern = "<c\\b([^>]*)>(.*?)</c>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]) else {
            return []
        }
        let nsRange = NSRange(xml.startIndex..<xml.endIndex, in: xml)
        return regex.matches(in: xml, range: nsRange).flatMap { match -> [String] in
            guard let attributeRange = Range(match.range(at: 1), in: xml),
                  let bodyRange = Range(match.range(at: 2), in: xml) else { return [] }
            let attributes = String(xml[attributeRange])
            let body = String(xml[bodyRange])
            if xmlAttribute("t", in: attributes) == "s",
               let rawValue = xmlText(in: body, elementName: "v").first,
               let sharedIndex = Int(rawValue.trimmingCharacters(in: .whitespacesAndNewlines)),
               sharedStrings.indices.contains(sharedIndex) {
                return [sharedStrings[sharedIndex]]
            }
            let inlineStrings = xmlText(in: body, elementName: "t")
            if !inlineStrings.isEmpty {
                return inlineStrings
            }
            return xmlText(in: body, elementName: "v")
        }
    }

    private static func plainTextFromMarkup(_ markup: String) -> String {
        var text = markup
        text = text.replacingOccurrences(of: "(?is)<script\\b.*?</script>", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?is)<style\\b.*?</style>", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?is)<br\\s*/?>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?is)</(p|div|section|article|h[1-6]|li|tr)>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?is)<[^>]+>", with: " ", options: .regularExpression)
        text = xmlUnescaped(text)
        return text
            .components(separatedBy: .newlines)
            .map { $0.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private static func xmlUnescaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    private static func spreadsheetSheetOrder(in archive: SimpleZIPArchive) -> [(name: String, path: String)] {
        guard let workbook = archive.text(named: "xl/workbook.xml") else { return [] }
        let relationships = workbookRelationships(in: archive)
        let pattern = "<sheet\\b([^>]*)>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let nsRange = NSRange(workbook.startIndex..<workbook.endIndex, in: workbook)
        return regex.matches(in: workbook, range: nsRange).compactMap { match in
            guard let attributeRange = Range(match.range(at: 1), in: workbook) else { return nil }
            let attributes = String(workbook[attributeRange])
            let name = xmlUnescaped(xmlAttribute("name", in: attributes) ?? "")
            let relationshipID = xmlAttribute("r:id", in: attributes) ?? xmlAttribute("id", in: attributes)
            guard let relationshipID,
                  let target = relationships[relationshipID] else { return nil }
            return (name: name, path: normalizedArchivePath(base: "xl", target: target))
        }
    }

    private static func workbookRelationships(in archive: SimpleZIPArchive) -> [String: String] {
        guard let rels = archive.text(named: "xl/_rels/workbook.xml.rels") else { return [:] }
        let pattern = "<Relationship\\b([^>]*)>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [:] }
        let nsRange = NSRange(rels.startIndex..<rels.endIndex, in: rels)
        var output: [String: String] = [:]
        for match in regex.matches(in: rels, range: nsRange) {
            guard let attributeRange = Range(match.range(at: 1), in: rels) else { continue }
            let attributes = String(rels[attributeRange])
            guard let id = xmlAttribute("Id", in: attributes) ?? xmlAttribute("id", in: attributes),
                  let target = xmlAttribute("Target", in: attributes) ?? xmlAttribute("target", in: attributes),
                  target.contains("worksheets/") else { continue }
            output[id] = target
        }
        return output
    }

    private static func epubSpineOrder(in archive: SimpleZIPArchive) -> [String] {
        let container = archive.text(named: "META-INF/container.xml")
        let opfPath = container.flatMap { xmlAttribute("full-path", in: $0) }
            ?? archive.entryNames.first { $0.lowercased().hasSuffix(".opf") }
        guard let opfPath,
              let opf = archive.text(named: opfPath) else { return [] }
        let base = URL(fileURLWithPath: opfPath).deletingLastPathComponent().relativePath
        let manifest = epubManifest(in: opf, base: base == "." ? "" : base)
        let itemRefs = xmlElements(named: "itemref", in: opf).compactMap { xmlAttribute("idref", in: $0) }
        return itemRefs.compactMap { manifest[$0] }
    }

    private static func epubManifest(in opf: String, base: String) -> [String: String] {
        var output: [String: String] = [:]
        for attributes in xmlElements(named: "item", in: opf) {
            guard let id = xmlAttribute("id", in: attributes),
                  let href = xmlAttribute("href", in: attributes) else { continue }
            let lower = href.lowercased()
            guard lower.hasSuffix(".xhtml") || lower.hasSuffix(".html") || lower.hasSuffix(".htm") else { continue }
            output[id] = normalizedArchivePath(base: base, target: href)
        }
        return output
    }

    private static func xmlElements(named name: String, in xml: String) -> [String] {
        let escapedName = NSRegularExpression.escapedPattern(for: name)
        let pattern = "<(?:[A-Za-z0-9_\\-]+:)?\(escapedName)\\b([^>]*)>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let nsRange = NSRange(xml.startIndex..<xml.endIndex, in: xml)
        return regex.matches(in: xml, range: nsRange).compactMap { match in
            guard let range = Range(match.range(at: 1), in: xml) else { return nil }
            return String(xml[range])
        }
    }

    private static func xmlAttribute(_ name: String, in attributes: String) -> String? {
        let escapedName = NSRegularExpression.escapedPattern(for: name)
        let pattern = "(?:^|\\s)(?:[A-Za-z0-9_\\-]+:)?\(escapedName)\\s*=\\s*(['\"])(.*?)\\1"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let nsRange = NSRange(attributes.startIndex..<attributes.endIndex, in: attributes)
        guard let match = regex.firstMatch(in: attributes, range: nsRange),
              let range = Range(match.range(at: 2), in: attributes) else { return nil }
        return xmlUnescaped(String(attributes[range]))
    }

    private static func normalizedArchivePath(base: String, target: String) -> String {
        let pieces = (base.split(separator: "/") + target.split(separator: "/"))
            .reduce(into: [String]()) { result, piece in
                if piece == "." || piece.isEmpty {
                    return
                } else if piece == ".." {
                    _ = result.popLast()
                } else {
                    result.append(String(piece))
                }
            }
        return pieces.joined(separator: "/")
    }

    private static func sheetDisplayName(from path: String) -> String {
        let name = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        guard name.lowercased().hasPrefix("sheet") else { return name }
        return "Sheet \(name.dropFirst(5))"
    }

    private static func naturalPathCompare(_ lhs: String, _ rhs: String) -> Bool {
        lhs.compare(rhs, options: [.numeric, .caseInsensitive]) == .orderedAscending
    }
}

private struct SimpleZIPArchive {
    enum ZIPError: Error {
        case unreadable
        case unsupportedCompression
    }

    struct Entry {
        var name: String
        var compressionMethod: UInt16
        var compressedSize: Int
        var uncompressedSize: Int
        var localHeaderOffset: Int
    }

    private let data: Data
    private let entries: [String: Entry]
    private static let maxEntryUncompressedBytes = 25 * 1024 * 1024
    private static let maxArchiveUncompressedBytes = 100 * 1024 * 1024

    var entryNames: [String] { Array(entries.keys) }

    init(data: Data) throws {
        self.data = data
        self.entries = try Self.readCentralDirectory(from: data)
    }

    func text(named name: String) -> String? {
        guard let entry = entries[name],
              let data = try? entryData(entry),
              let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) ?? String(data: data, encoding: .isoLatin1) else {
            return nil
        }
        return text
    }

    private func entryData(_ entry: Entry) throws -> Data {
        let offset = entry.localHeaderOffset
        guard offset + 30 <= data.count,
              Self.uint32(in: data, at: offset) == 0x04034b50 else {
            throw ZIPError.unreadable
        }
        let nameLength = Int(Self.uint16(in: data, at: offset + 26))
        let extraLength = Int(Self.uint16(in: data, at: offset + 28))
        let start = offset + 30 + nameLength + extraLength
        guard start >= 0, start + entry.compressedSize <= data.count else {
            throw ZIPError.unreadable
        }
        let compressed = data[start..<start + entry.compressedSize]
        if entry.compressionMethod == 0 {
            guard entry.compressedSize == entry.uncompressedSize,
                  entry.compressedSize <= Self.maxEntryUncompressedBytes else {
                throw ZIPError.unreadable
            }
            return Data(compressed)
        }
        guard entry.compressionMethod == 8 else {
            throw ZIPError.unsupportedCompression
        }
        // A zero-byte deflate entry (a malformed/adversarial .docx/.xlsx/.pptx central
        // directory can declare this) makes `compressed` an empty slice, whose
        // `withUnsafeBytes` buffer has a nil `baseAddress` -- force-unwrapping that used to
        // crash the app on import instead of just failing this one entry. An empty deflate
        // entry can only validly decode to zero bytes; anything else is inconsistent
        // metadata, not real content.
        guard !compressed.isEmpty else {
            guard entry.uncompressedSize == 0 else { throw ZIPError.unreadable }
            return Data()
        }

        var output = [UInt8](repeating: 0, count: entry.uncompressedSize)
        let decoded = compressed.withUnsafeBytes { input -> Int in
            guard let baseAddress = input.bindMemory(to: UInt8.self).baseAddress else { return -1 }
            return compression_decode_buffer(
                &output,
                output.count,
                baseAddress,
                compressed.count,
                nil,
                COMPRESSION_ZLIB
            )
        }
        guard decoded == entry.uncompressedSize else {
            throw ZIPError.unreadable
        }
        return Data(output)
    }

    private static func readCentralDirectory(from data: Data) throws -> [String: Entry] {
        guard let eocd = findEndOfCentralDirectory(in: data),
              eocd + 22 <= data.count else {
            throw ZIPError.unreadable
        }
        let entryCount = Int(uint16(in: data, at: eocd + 10))
        let directorySize = Int(uint32(in: data, at: eocd + 12))
        let directoryOffset = Int(uint32(in: data, at: eocd + 16))
        guard directoryOffset >= 0,
              directorySize >= 0,
              directoryOffset + directorySize <= data.count else {
            throw ZIPError.unreadable
        }

        var result: [String: Entry] = [:]
        var cursor = directoryOffset
        var totalUncompressedSize = 0
        for _ in 0..<entryCount {
            guard cursor + 46 <= data.count,
                  uint32(in: data, at: cursor) == 0x02014b50 else {
                throw ZIPError.unreadable
            }
            let method = uint16(in: data, at: cursor + 10)
            let compressedSize = Int(uint32(in: data, at: cursor + 20))
            let uncompressedSize = Int(uint32(in: data, at: cursor + 24))
            guard uncompressedSize <= maxEntryUncompressedBytes else {
                throw ZIPError.unreadable
            }
            totalUncompressedSize += uncompressedSize
            guard totalUncompressedSize <= maxArchiveUncompressedBytes else {
                throw ZIPError.unreadable
            }
            let nameLength = Int(uint16(in: data, at: cursor + 28))
            let extraLength = Int(uint16(in: data, at: cursor + 30))
            let commentLength = Int(uint16(in: data, at: cursor + 32))
            let localHeaderOffset = Int(uint32(in: data, at: cursor + 42))
            let nameStart = cursor + 46
            let nameEnd = nameStart + nameLength
            guard nameEnd <= data.count,
                  let name = String(data: data[nameStart..<nameEnd], encoding: .utf8) else {
                throw ZIPError.unreadable
            }
            result[name] = Entry(
                name: name,
                compressionMethod: method,
                compressedSize: compressedSize,
                uncompressedSize: uncompressedSize,
                localHeaderOffset: localHeaderOffset
            )
            cursor = nameEnd + extraLength + commentLength
        }
        return result
    }

    private static func findEndOfCentralDirectory(in data: Data) -> Int? {
        guard data.count >= 22 else { return nil }
        let lowerBound = max(0, data.count - 65_557)
        var cursor = data.count - 22
        while cursor >= lowerBound {
            if uint32(in: data, at: cursor) == 0x06054b50 {
                return cursor
            }
            cursor -= 1
        }
        return nil
    }

    private static func uint16(in data: Data, at offset: Int) -> UInt16 {
        UInt16(data[offset]) | UInt16(data[offset + 1]) << 8
    }

    private static func uint32(in data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset]) |
            UInt32(data[offset + 1]) << 8 |
            UInt32(data[offset + 2]) << 16 |
            UInt32(data[offset + 3]) << 24
    }
}

@MainActor
private final class HTMLPDFRenderer: NSObject, WKNavigationDelegate {
    private let html: String
    private let baseURL: URL?
    private let timeout: TimeInterval
    private let maxPages: Int
    private let webView: WKWebView
    private var continuation: CheckedContinuation<Data, Error>?
    private var timeoutTask: Task<Void, Never>?

    nonisolated fileprivate static let pageSize = CGSize(width: 612, height: 792)

    static func render(
        html: String,
        baseURL: URL?,
        timeout: TimeInterval = 30,
        maxPages: Int
    ) async throws -> Data {
        let renderer = HTMLPDFRenderer(html: html, baseURL: baseURL, timeout: timeout, maxPages: maxPages)
        return try await renderer.render()
    }

    private init(html: String, baseURL: URL?, timeout: TimeInterval, maxPages: Int) {
        self.html = html
        self.baseURL = baseURL
        self.timeout = timeout
        self.maxPages = maxPages

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = false
        configuration.defaultWebpagePreferences = preferences

        webView = WKWebView(frame: CGRect(origin: .zero, size: Self.pageSize), configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        super.init()
        webView.navigationDelegate = self
    }

    private func render() async throws -> Data {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                self.timeoutTask = Task { [weak self] in
                    let nanoseconds = UInt64(max(0, self?.timeout ?? 0) * 1_000_000_000)
                    try? await Task.sleep(nanoseconds: nanoseconds)
                    self?.finish(.failure(DocumentImportConverter.ConversionError.renderTimedOut))
                }
                self.webView.loadHTMLString(self.html, baseURL: self.baseURL)
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.finish(.failure(CancellationError()))
            }
        }
    }

    private func finish(_ result: Result<Data, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        webView.stopLoading()
        webView.navigationDelegate = nil
        continuation.resume(with: result)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let script = """
        (() => {
          const style = document.createElement('style');
          style.textContent = `
            html, body { box-sizing: border-box; max-width: 612px; overflow-wrap: anywhere; }
            *, *::before, *::after { box-sizing: inherit; }
            body { margin: 0; width: 612px; }
            img, svg, canvas, video, iframe, table { max-width: 100%; }
            pre, code { white-space: pre-wrap; overflow-wrap: anywhere; }
          `;
          document.head.appendChild(style);
          document.documentElement.style.width = '612px';
          document.body.style.width = '612px';
          return Math.max(
            document.documentElement.scrollHeight,
            document.body.scrollHeight,
            792
          );
        })()
        """
        webView.evaluateJavaScript(script) { [weak self] result, error in
            Task { @MainActor in
                if let error {
                    self?.finish(.failure(error))
                    return
                }
                guard let self else { return }

                let height = max((result as? NSNumber)?.doubleValue ?? Double(Self.pageSize.height), Double(Self.pageSize.height))
                let pageEstimate = Int(ceil(height / Double(Self.pageSize.height)))
                guard pageEstimate <= self.maxPages else {
                    self.finish(.failure(DocumentImportConverter.ConversionError.htmlRenderedTooLarge(
                        pageEstimate: pageEstimate,
                        maxPages: self.maxPages
                    )))
                    return
                }

                webView.frame = CGRect(origin: .zero, size: CGSize(width: Self.pageSize.width, height: height))
                self.createPDFSlices(pageCount: pageEstimate)
            }
        }
    }

    private func createPDFSlices(pageCount: Int) {
        let output = PDFDocument()

        func renderSlice(_ pageIndex: Int) {
            guard pageIndex < pageCount else {
                guard let data = output.dataRepresentation(), !data.isEmpty else {
                    finish(.failure(DocumentImportConverter.ConversionError.renderingFailed))
                    return
                }
                finish(.success(data))
                return
            }

            let configuration = WKPDFConfiguration()
            configuration.rect = CGRect(
                x: 0,
                y: CGFloat(pageIndex) * Self.pageSize.height,
                width: Self.pageSize.width,
                height: Self.pageSize.height
            )
            webView.createPDF(configuration: configuration) { [weak self] result in
                Task { @MainActor in
                    guard let self else { return }
                    switch result {
                    case .success(let data) where !data.isEmpty:
                        guard let slice = PDFDocument(data: data),
                              let page = slice.page(at: 0) else {
                            self.finish(.failure(DocumentImportConverter.ConversionError.renderingFailed))
                            return
                        }
                        output.insert(page, at: output.pageCount)
                        renderSlice(pageIndex + 1)
                    case .success:
                        self.finish(.failure(DocumentImportConverter.ConversionError.renderingFailed))
                    case .failure(let error):
                        self.finish(.failure(error))
                    }
                }
            }
        }

        renderSlice(0)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(.failure(error))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(.failure(error))
    }
}
