import PDFKit
import AppKit
import Foundation
import UniformTypeIdentifiers
import WebKit

final class PDFKitEngine: PDFEngine {
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
}

enum DocumentImportConverter {
    enum ConversionError: Error {
        case unsupportedType
        case unreadableDocument
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
        guard url.isFileURL else { throw ConversionError.unsupportedType }
        let resourceType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType
        let type = resourceType ?? UTType(filenameExtension: url.pathExtension) ?? .data
        if let byteCount = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
            try validateByteCount(Int64(byteCount), contentType: type)
        }
        let data = try Data(contentsOf: url)
        return try pdfDocument(
            from: data,
            contentType: type,
            filename: url.lastPathComponent,
            // Let HTML resolve relative CSS and image URLs the same way it would
            // when opened directly in a browser.
            baseURL: type.conforms(to: .html) ? url.deletingLastPathComponent() : nil
        )
    }

    static func pdfDocument(from data: Data, contentType: UTType, filename: String, baseURL: URL?) throws -> PDFDocument {
        try validateByteCount(Int64(data.count), contentType: contentType)

        if contentType.conforms(to: .pdf) {
            guard let document = PDFDocument(data: data) else { throw ConversionError.unreadableDocument }
            return document
        }
        if contentType.conforms(to: .image) {
            return try renderImage(data, title: filename)
        }

        if contentType.conforms(to: .html) {
            return try renderHTML(data, title: filename, baseURL: baseURL)
        }

        let attributedString: NSAttributedString
        if contentType.conforms(to: .docx) {
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

    private static func renderHTML(_ data: Data, title: String, baseURL: URL?) throws -> PDFDocument {
        let html = try decodeText(data)
        let pdfData = try HTMLPDFRenderer.render(
            html: html,
            baseURL: baseURL,
            maxPages: maxRenderedHTMLPages
        )
        guard let document = PDFDocument(data: pdfData) else { throw ConversionError.renderingFailed }
        document.documentAttributes = [
            PDFDocumentAttribute.titleAttribute: URL(fileURLWithPath: title).deletingPathExtension().lastPathComponent
        ]
        return document
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

private final class HTMLPDFRenderer: NSObject, WKNavigationDelegate {
    private enum RenderState {
        case pending
        case succeeded(Data)
        case failed(Error)
    }

    private let html: String
    private let baseURL: URL?
    private let timeout: TimeInterval
    private let maxPages: Int
    private let webView: WKWebView
    private var state = RenderState.pending

    private static let pageSize = CGSize(width: 612, height: 792)

    static func render(
        html: String,
        baseURL: URL?,
        timeout: TimeInterval = 30,
        maxPages: Int
    ) throws -> Data {
        if Thread.isMainThread {
            return try renderOnMainThread(html: html, baseURL: baseURL, timeout: timeout, maxPages: maxPages)
        }

        var result: Result<Data, Error>?
        let semaphore = DispatchSemaphore(value: 0)
        DispatchQueue.main.async {
            result = Result {
                try renderOnMainThread(html: html, baseURL: baseURL, timeout: timeout, maxPages: maxPages)
            }
            semaphore.signal()
        }
        semaphore.wait()
        guard let result else {
            throw DocumentImportConverter.ConversionError.renderingFailed
        }
        return try result.get()
    }

    private static func renderOnMainThread(html: String, baseURL: URL?, timeout: TimeInterval, maxPages: Int) throws -> Data {
        let renderer = HTMLPDFRenderer(html: html, baseURL: baseURL, timeout: timeout, maxPages: maxPages)
        return try renderer.render()
    }

    private init(html: String, baseURL: URL?, timeout: TimeInterval, maxPages: Int) {
        self.html = html
        self.baseURL = baseURL
        self.timeout = timeout
        self.maxPages = maxPages

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true
        configuration.defaultWebpagePreferences = preferences

        webView = WKWebView(frame: CGRect(origin: .zero, size: Self.pageSize), configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        super.init()
        webView.navigationDelegate = self
    }

    private func render() throws -> Data {
        webView.loadHTMLString(html, baseURL: baseURL)

        let deadline = Date().addingTimeInterval(timeout)
        while case .pending = state {
            if Date() >= deadline {
                throw DocumentImportConverter.ConversionError.renderTimedOut
            }
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
        }

        switch state {
        case .pending:
            throw DocumentImportConverter.ConversionError.renderingFailed
        case .succeeded(let data):
            return data
        case .failed(let error):
            throw error
        }
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
            if let error {
                self?.state = .failed(error)
                return
            }
            guard let self else { return }

            let height = max((result as? NSNumber)?.doubleValue ?? Double(Self.pageSize.height), Double(Self.pageSize.height))
            let pageEstimate = Int(ceil(height / Double(Self.pageSize.height)))
            guard pageEstimate <= self.maxPages else {
                self.state = .failed(DocumentImportConverter.ConversionError.htmlRenderedTooLarge(
                    pageEstimate: pageEstimate,
                    maxPages: self.maxPages
                ))
                return
            }

            webView.frame = CGRect(origin: .zero, size: CGSize(width: Self.pageSize.width, height: height))

            let configuration = WKPDFConfiguration()
            configuration.rect = webView.bounds
            webView.createPDF(configuration: configuration) { result in
                switch result {
                case .success(let data) where !data.isEmpty:
                    self.state = .succeeded(data)
                case .success:
                    self.state = .failed(DocumentImportConverter.ConversionError.renderingFailed)
                case .failure(let error):
                    self.state = .failed(error)
                }
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        state = .failed(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        state = .failed(error)
    }
}
