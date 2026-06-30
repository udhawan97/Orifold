import Foundation

#if canImport(PDFium)
import PDFium

final class PDFiumProcessingEngine: PDFProcessingEngine {
    let name = "PDFium"

    func validatePDF(data: Data, password: String? = nil) throws -> PDFProcessingValidation {
        guard !data.isEmpty else {
            throw PDFProcessingError.unreadableDocument
        }

        FPDF_InitLibrary()
        defer { FPDF_DestroyLibrary() }

        let document = try data.withUnsafeBytes { rawBuffer -> FPDF_DOCUMENT? in
            guard let baseAddress = rawBuffer.baseAddress else { return nil }
            if let password {
                return password.withCString { passwordPointer in
                    FPDF_LoadMemDocument(baseAddress, CInt(data.count), passwordPointer)
                }
            }
            return FPDF_LoadMemDocument(baseAddress, CInt(data.count), nil)
        }

        guard let document else {
            let error = FPDF_GetLastError()
            if error == FPDF_ERR_PASSWORD {
                throw PDFProcessingError.lockedOrEncrypted
            }
            throw PDFProcessingError.unreadableDocument
        }
        defer { FPDF_CloseDocument(document) }

        let pageCount = Int(FPDF_GetPageCount(document))
        guard pageCount > 0 else {
            throw PDFProcessingError.emptyDocument
        }

        return PDFProcessingValidation(
            engine: .pdfium,
            pageCount: pageCount,
            isEncrypted: false
        )
    }
}
#else
final class PDFiumProcessingEngine: PDFProcessingEngine {
    let name = "PDFium unavailable"

    func validatePDF(data: Data, password: String? = nil) throws -> PDFProcessingValidation {
        throw PDFProcessingError.unsupported
    }
}
#endif
