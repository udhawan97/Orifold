import PDFKit
import AppKit
import Foundation
import UniformTypeIdentifiers

final class PDFKitEngine: PDFEngine {
    func loadDocument(from url: URL) throws -> PDFDocument {
        try DocumentImportConverter.pdfDocument(from: url)
    }

    /// Concatenate member documents into one PDFDocument for display.
    /// Each member is preceded by a styled BoundaryPage header.
    /// Pass `includeBanners: false` to build a plain export PDF.
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
            for i in 0..<pdf.pageCount {
                if let page = pdf.page(at: i) {
                    combined.insert(page, at: insertIndex)
                    insertIndex += 1
                }
            }
        }
        return combined
    }
}

enum DocumentImportConverter {
    enum ConversionError: Error {
        case unsupportedType
        case unreadableDocument
        case renderingFailed
        case fileTooLarge(Int64)
    }

    static let maxImportBytes: Int64 = 512 * 1024 * 1024

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
        case ConversionError.renderingFailed:
            return "The file opened, but PDFold could not render it into a PDF."
        case ConversionError.fileTooLarge(let byteCount):
            let actual = byteCountFormatter.string(fromByteCount: byteCount)
            let limit = byteCountFormatter.string(fromByteCount: maxImportBytes)
            return "The file is \(actual), which is larger than the \(limit) import safety limit."
        default:
            return "The file could not be opened: \(error.localizedDescription)"
        }
    }

    static func pdfDocument(from url: URL) throws -> PDFDocument {
        let type = UTType(filenameExtension: url.pathExtension) ?? .data
        if let byteCount = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
           Int64(byteCount) > maxImportBytes {
            throw ConversionError.fileTooLarge(Int64(byteCount))
        }
        let data = try Data(contentsOf: url)
        return try pdfDocument(
            from: data,
            contentType: type,
            filename: url.lastPathComponent,
            // Keep HTML/Markdown imports self-contained. A selected document should
            // not be able to pull arbitrary sibling files or remote resources.
            baseURL: nil
        )
    }

    static func pdfDocument(from data: Data, contentType: UTType, filename: String, baseURL: URL?) throws -> PDFDocument {
        if contentType.conforms(to: .pdf) {
            guard let document = PDFDocument(data: data) else { throw ConversionError.unreadableDocument }
            return document
        }
        if contentType.conforms(to: .image) {
            return try renderImage(data, title: filename)
        }

        let attributedString: NSAttributedString
        if contentType.conforms(to: .html) {
            attributedString = try loadAttributedString(from: data, documentType: .html, baseURL: baseURL)
        } else if contentType.conforms(to: .docx) {
            attributedString = try loadAttributedString(from: data, documentType: .officeOpenXML, baseURL: baseURL)
        } else if contentType.conforms(to: .wordDoc) {
            attributedString = try loadAttributedString(from: data, documentType: .docFormat, baseURL: baseURL)
        } else if contentType.conforms(to: .odt) {
            attributedString = try loadAttributedString(from: data, documentType: .openDocument, baseURL: baseURL)
        } else if contentType.conforms(to: .rtf) {
            attributedString = try loadAttributedString(from: data, documentType: .rtf, baseURL: baseURL)
        } else if contentType.conforms(to: .markdown) {
            attributedString = try loadMarkdown(from: data, baseURL: baseURL)
        } else if isPlainTextLike(contentType) {
            attributedString = try loadPlainText(from: data)
        } else {
            throw ConversionError.unsupportedType
        }

        return try renderAttributedString(attributedString, title: filename)
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
        let encodings: [String.Encoding] = [.utf8, .utf16, .utf16LittleEndian, .utf16BigEndian, .isoLatin1, .macOSRoman]
        for encoding in encodings {
            if let string = String(data: data, encoding: encoding) {
                return string
            }
        }
        throw ConversionError.unreadableDocument
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
            if pageIndex >= 500 { break }
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
