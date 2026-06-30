import Foundation

let pdfiumPasswordErrorCode: UInt = 4
let pdfiumLock = NSLock()

@_silgen_name("FPDF_InitLibrary")
func FPDF_InitLibrary()

@_silgen_name("FPDF_DestroyLibrary")
func FPDF_DestroyLibrary()

@_silgen_name("FPDF_LoadMemDocument")
func FPDF_LoadMemDocument(
    _ data: UnsafeRawPointer?,
    _ size: Int32,
    _ password: UnsafePointer<CChar>?
) -> OpaquePointer?

@_silgen_name("FPDF_CloseDocument")
func FPDF_CloseDocument(_ document: OpaquePointer?)

@_silgen_name("FPDF_GetPageCount")
func FPDF_GetPageCount(_ document: OpaquePointer?) -> Int32

@_silgen_name("FPDF_GetLastError")
func FPDF_GetLastError() -> UInt

final class PDFiumProcessingEngine: PDFProcessingEngine {
    let name = "PDFium"

    func validatePDF(data: Data, password: String? = nil) throws -> PDFProcessingValidation {
        guard !data.isEmpty else {
            throw PDFProcessingError.unreadableDocument
        }
        guard data.count <= Int(Int32.max) else {
            throw PDFProcessingError.unreadableDocument
        }

        pdfiumLock.lock()
        defer { pdfiumLock.unlock() }
        FPDF_InitLibrary()
        defer { FPDF_DestroyLibrary() }
        let byteCount = Int32(data.count)

        let document = data.withUnsafeBytes { rawBuffer -> OpaquePointer? in
            guard let baseAddress = rawBuffer.baseAddress else { return nil }
            if let password {
                return password.withCString { passwordPointer in
                    FPDF_LoadMemDocument(baseAddress, byteCount, passwordPointer)
                }
            }
            return FPDF_LoadMemDocument(baseAddress, byteCount, nil)
        }

        guard let document else {
            let error = FPDF_GetLastError()
            if error == pdfiumPasswordErrorCode {
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
