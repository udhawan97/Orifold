import Foundation
import PDFKit

final class PDFKitProcessingEngineFallback: PDFProcessingEngine {
    let name = "PDFKit"

    func validatePDF(data: Data, password: String? = nil) throws -> PDFProcessingValidation {
        guard let document = PDFDocument(data: data) else {
            throw PDFProcessingError.unreadableDocument
        }

        if document.isLocked {
            guard let password, document.unlock(withPassword: password) else {
                throw PDFProcessingError.lockedOrEncrypted
            }
        }

        guard document.pageCount > 0 else {
            throw PDFProcessingError.emptyDocument
        }

        return PDFProcessingValidation(
            engine: .pdfKit,
            pageCount: document.pageCount,
            isEncrypted: document.isEncrypted
        )
    }
}
