import PDFKit
import Foundation

protocol PDFEngine {
    func loadDocument(from url: URL) throws -> PDFDocument
    func concatenate(documents: [(MemberDocument, PDFDocument)], includeBanners: Bool) -> PDFDocument
}
