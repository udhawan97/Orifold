import Foundation

/// The `pdfold-manifest.json` schema embedded inside a `.pdfold` bundle.
/// It lets a future PDFold import recover the original source-document map
/// from an otherwise ordinary exported PDF.
struct PDFoldManifest: Codable {
    var format: String = "pdfold"
    var version: Int = 1
    var title: String
    var createdWith: String = "PDFold 2.0"
    var documents: [ManifestDocument]

    struct ManifestDocument: Codable {
        var id: String        // MemberDocument.id.uuidString
        var name: String      // displayName
        var pageCount: Int
    }

    /// Validates that page counts sum to `totalPages`.
    func isValid(totalPages: Int) -> Bool {
        documents.reduce(0) { $0 + $1.pageCount } == totalPages
    }
}
