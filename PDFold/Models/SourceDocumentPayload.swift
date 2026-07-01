import AppKit
import Foundation
import UniformTypeIdentifiers

enum SourceDocumentFormat: String, Codable, Equatable {
    case docx
    case wordDoc
    case odt
    case rtf
    case markdown
    case html
    case plainText

    var fileExtension: String {
        switch self {
        case .docx: return "docx"
        case .wordDoc: return "doc"
        case .odt: return "odt"
        case .rtf: return "rtf"
        case .markdown: return "md"
        case .html: return "html"
        case .plainText: return "txt"
        }
    }

    var contentType: UTType {
        switch self {
        case .docx: return .docx
        case .wordDoc: return .wordDoc
        case .odt: return .odt
        case .rtf: return .rtf
        case .markdown: return .markdown
        case .html: return .html
        case .plainText: return .plainText
        }
    }

    var documentType: NSAttributedString.DocumentType? {
        switch self {
        case .docx: return .officeOpenXML
        case .wordDoc: return .docFormat
        case .odt: return .openDocument
        case .rtf: return .rtf
        case .html: return .html
        case .markdown, .plainText: return nil
        }
    }

    init?(contentType: UTType) {
        if contentType.conforms(to: .docx) {
            self = .docx
        } else if contentType.conforms(to: .wordDoc) {
            self = .wordDoc
        } else if contentType.conforms(to: .odt) {
            self = .odt
        } else if contentType.conforms(to: .rtf) {
            self = .rtf
        } else if contentType.conforms(to: .markdown) {
            self = .markdown
        } else if contentType.conforms(to: .html) {
            self = .html
        } else if [.plainText, .text, .utf8PlainText, .csv, .json, .xml].contains(where: { contentType.conforms(to: $0) }) {
            self = .plainText
        } else {
            return nil
        }
    }
}

struct SourceDocumentPayload: Codable, Equatable {
    var format: SourceDocumentFormat
    var originalFilename: String
    var originalContentTypeIdentifier: String
    var originalData: Data
    var richTextRTFData: Data?
    var plainText: String?

    var originalString: String? {
        plainText ?? String(data: originalData, encoding: .utf8)
    }

    func attributedString() -> NSAttributedString? {
        if let richTextRTFData {
            return try? NSAttributedString(
                data: richTextRTFData,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil
            )
        }
        if let plainText {
            return NSAttributedString(string: plainText)
        }
        return nil
    }

    static func richTextRTFData(from attributedString: NSAttributedString) -> Data? {
        guard attributedString.length > 0 else { return nil }
        return try? attributedString.data(
            from: NSRange(location: 0, length: attributedString.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
    }
}
