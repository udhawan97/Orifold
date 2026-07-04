import Foundation
import PDFKit

enum PDFSerializer {
    /// Returns the first non-nil byte representation of `pdf`, trying three paths:
    ///   (a) PDFDocument.dataRepresentation() — fast path, works for most PDFs
    ///   (b) write to a unique temp file, read bytes back, delete — works when (a) returns nil
    ///       for linearized / encrypted-but-unlocked / unusual-structure PDFs
    ///   (c) return nil — caller decides how to handle (keep live edit, show error, etc.)
    static func data(from pdf: PDFDocument) -> Data? {
        if let data = pdf.dataRepresentation() {
            return data
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".pdf")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        if pdf.write(to: tempURL), let data = try? Data(contentsOf: tempURL) {
            return data
        }

        return nil
    }
}
