import Foundation

struct PDFProcessingValidation: Equatable {
    enum Engine: String, Equatable {
        case pdfium = "PDFium"
        case pdfKit = "PDFKit"
    }

    var engine: Engine
    var pageCount: Int
    var isEncrypted: Bool
}

protocol PDFProcessingEngine {
    var name: String { get }
    func validatePDF(data: Data, password: String?) throws -> PDFProcessingValidation
}

enum PDFProcessingError: Error, Equatable {
    case unreadableDocument
    case lockedOrEncrypted
    case emptyDocument
    case unsupported
}
