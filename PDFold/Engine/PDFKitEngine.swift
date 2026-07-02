import PDFKit
import AppKit
import Foundation
import UniformTypeIdentifiers
import WebKit

final class PDFKitEngine: PDFEngine {
    enum ExportAssemblyError: LocalizedError, Equatable {
        case unreadableMember(String)
        case emptyDocument

        var errorDescription: String? {
            switch self {
            case .unreadableMember(let name):
                return "pdFold could not prepare \"\(name)\" for export. Reopen the document and try exporting again."
            case .emptyDocument:
                return "pdFold could not prepare this PDF for export because it has no pages."
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
        for (member, pdf) in documents {
            guard let memberData = PDFSerializer.data(from: pdf),
                  let freshMemberDoc = PDFDocument(data: memberData),
                  freshMemberDoc.pageCount == pdf.pageCount else {
                throw ExportAssemblyError.unreadableMember(member.displayName)
            }
            for pageIndex in 0..<freshMemberDoc.pageCount {
                guard let page = freshMemberDoc.page(at: pageIndex) else {
                    throw ExportAssemblyError.unreadableMember(member.displayName)
                }
                combined.insert(page, at: insertIndex)
                insertIndex += 1
            }
        }
        guard combined.pageCount > 0 else {
            throw ExportAssemblyError.emptyDocument
        }
        return combined
    }
}

enum DocumentImportConverter {
    struct ImportedDocument {
        var pdfDocument: PDFDocument
        var sourcePayload: SourceDocumentPayload?
    }

    enum ConversionError: Error {
        case unsupportedType
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
        case ConversionError.unsupportedType:
            return "This file type is not supported yet."
        case ConversionError.unreadableDocument:
            return "The file could not be read. It may be corrupt, encrypted, or incomplete."
        case ConversionError.emptyDocument:
            return "The file is empty."
        case ConversionError.binaryDataMislabelledAsText:
            return "This looks like binary data, not a supported text document. Check the file type and try again."
        case ConversionError.renderingFailed:
            return "The file opened, but pdFold could not render it into a PDF."
        case ConversionError.renderTimedOut:
            return "The file took too long to render. Try exporting it to PDF from its original app, then import the PDF."
        case ConversionError.fileTooLarge(let byteCount):
            let actual = byteCountFormatter.string(fromByteCount: byteCount)
            let limit = byteCountFormatter.string(fromByteCount: maxImportBytes)
            return "The file is \(actual), which is larger than the \(limit) import safety limit."
        case ConversionError.fileTypeTooLarge(let typeDescription, let actualBytes, let limitBytes):
            let actual = byteCountFormatter.string(fromByteCount: actualBytes)
            let limit = byteCountFormatter.string(fromByteCount: limitBytes)
            return "This \(typeDescription) file is \(actual), which is larger than pdFold can safely convert directly (\(limit)). Try exporting it to PDF first, then import the PDF."
        case ConversionError.htmlRenderedTooLarge(let pageEstimate, let maxPages):
            return "This HTML file would render to about \(pageEstimate) pages, which is over pdFold's \(maxPages)-page HTML conversion limit. Try printing or exporting it to PDF from a browser, then import the PDF."
        case ConversionError.documentRenderedTooLarge(let maxPages):
            return "This file would render to more than \(maxPages) pages, so pdFold stopped the import before creating a partial PDF. Try exporting it to PDF first, then import the PDF."
        default:
            return "The file could not be opened: \(error.localizedDescription)"
        }
    }

    static func pdfDocument(from url: URL) throws -> PDFDocument {
        try importedDocument(from: url).pdfDocument
    }

    static func importedDocument(from url: URL) throws -> ImportedDocument {
        guard url.isFileURL else { throw ConversionError.unsupportedType }
        let resourceType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType
        let suggestedType = resourceType ?? UTType(filenameExtension: url.pathExtension) ?? .data
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
            baseURL: detectedType.conforms(to: .html) ? url.deletingLastPathComponent() : nil
        )
    }

    static func importedDocumentAsync(from url: URL) async throws -> ImportedDocument {
        guard url.isFileURL else { throw ConversionError.unsupportedType }
        let resourceType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType
        let suggestedType = resourceType ?? UTType(filenameExtension: url.pathExtension) ?? .data
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
            baseURL: detectedType.conforms(to: .html) ? url.deletingLastPathComponent() : nil
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
            guard let document = PDFDocument(data: data) else { throw ConversionError.unreadableDocument }
            return ImportedDocument(pdfDocument: document, sourcePayload: nil)
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
                plainText: isPlainTextLike(detectedType) || detectedType.conforms(to: .markdown) ? (try? decodeText(data)) : nil,
                renderedPageCount: pdf.pageCount
            )
        )
    }

    static func importedDocumentAsync(from data: Data, contentType: UTType, filename: String, baseURL: URL?) async throws -> ImportedDocument {
        let detectedType = detectedContentType(data: data, suggestedContentType: contentType, filename: filename)
        try validateByteCount(Int64(data.count), contentType: detectedType)

        if data.isEmpty && !detectedType.conforms(to: .plainText) && !detectedType.conforms(to: .text) {
            throw ConversionError.emptyDocument
        }

        if !detectedType.conforms(to: .html) {
            return try await MainActor.run {
                try importedDocument(from: data, contentType: detectedType, filename: filename, baseURL: baseURL)
            }
        }

        let plainHTML = try decodeText(data)
        let pdf = try await renderHTML(data, title: filename, baseURL: baseURL)
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

    static func detectedContentType(data: Data, suggestedContentType: UTType, filename: String) -> UTType {
        if let strongType = stronglyDetectedContentType(data: data, suggestedContentType: suggestedContentType, filename: filename) {
            return strongType
        }
        if looksLikeMarkdown(data) {
            return .markdown
        }
        if SourceDocumentFormat(contentType: suggestedContentType) != nil || suggestedContentType.conforms(to: .pdf) || suggestedContentType.conforms(to: .image) {
            return suggestedContentType
        }
        if let extensionType = UTType(filenameExtension: URL(fileURLWithPath: filename).pathExtension),
           SourceDocumentFormat(contentType: extensionType) != nil || extensionType.conforms(to: .pdf) || extensionType.conforms(to: .image) {
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
        } else if contentType.conforms(to: .docx) || contentType.conforms(to: .wordDoc) || contentType.conforms(to: .odt) || contentType.conforms(to: .rtf) {
            typedLimit = ("document", maxRichDocumentImportBytes)
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

    private static func renderHTML(_ data: Data, title: String, baseURL: URL?) async throws -> PDFDocument {
        let html = try decodeText(data)
        let pdfData = try await HTMLPDFRenderer.render(
            html: html,
            baseURL: baseURL,
            maxPages: maxRenderedHTMLPages
        )
        let paginatedData = try paginateRenderedHTMLPDFData(pdfData)
        guard let document = PDFDocument(data: paginatedData) else { throw ConversionError.renderingFailed }
        document.documentAttributes = [
            PDFDocumentAttribute.titleAttribute: URL(fileURLWithPath: title).deletingPathExtension().lastPathComponent
        ]
        return document
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

    private static func loadMarkdown(from data: Data, baseURL: URL?) throws -> NSAttributedString {
        let string = try decodeText(data)
        do {
            let attributed = try AttributedString(markdown: string, options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .full), baseURL: baseURL)
            return NSAttributedString(attributed)
        } catch {
            return try loadPlainText(from: data)
        }
    }

    private static func loadPlainText(from data: Data) throws -> NSAttributedString {
        let string = try decodeText(data)
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byWordWrapping
        style.paragraphSpacing = 6
        return NSAttributedString(
            string: string.isEmpty ? " " : string,
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
                .foregroundColor: NSColor.textColor,
                .paragraphStyle: style
            ]
        )
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
        }
        if looksLikeHTML(data) {
            return .html
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
        [.plainText, .text, .csv, .json, .xml].contains { contentType.conforms(to: $0) }
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

            pageIndex += 1
            if NSMaxRange(glyphRange) >= layoutManager.numberOfGlyphs { break }
            if pageIndex >= maxRenderedTextPages {
                throw ConversionError.documentRenderedTooLarge(maxPages: maxRenderedTextPages)
            }
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

                let configuration = WKPDFConfiguration()
                configuration.rect = webView.bounds
                webView.createPDF(configuration: configuration) { result in
                    Task { @MainActor in
                        switch result {
                        case .success(let data) where !data.isEmpty:
                            self.finish(.success(data))
                        case .success:
                            self.finish(.failure(DocumentImportConverter.ConversionError.renderingFailed))
                        case .failure(let error):
                            self.finish(.failure(error))
                        }
                    }
                }
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(.failure(error))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(.failure(error))
    }
}
