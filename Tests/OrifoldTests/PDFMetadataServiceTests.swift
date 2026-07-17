import XCTest
import PDFKit
@testable import Orifold

final class PDFMetadataServiceTests: XCTestCase {
    private func fixture(title: String?, author: String?) -> Data {
        let doc = PDFDocument()
        let page = PDFPage()
        doc.insert(page, at: 0)
        var attrs: [PDFDocumentAttribute: Any] = [:]
        if let title { attrs[.titleAttribute] = title }
        if let author { attrs[.authorAttribute] = author }
        doc.documentAttributes = attrs
        return doc.dataRepresentation()!  // fixture creation only — never product code
    }

    func testReadsTitleAndAuthor() throws {
        let data = fixture(title: "折り紙", author: "Gami")
        let meta = try PDFMetadataService.read(from: data, password: nil)
        XCTAssertEqual(meta.title, "折り紙")
        XCTAssertEqual(meta.author, "Gami")
        XCTAssertNil(meta.subject)
    }

    func testMissingInfoDictYieldsAllNil() throws {
        let meta = try PDFMetadataService.read(from: fixture(title: nil, author: nil), password: nil)
        XCTAssertEqual(meta, PDFDocumentMetadata())
    }

    func testWriteRoundTrip() throws {
        let edited = try PDFMetadataService.write(
            PDFDocumentMetadata(title: "New Title", author: "Ori", subject: "S", keywords: "a, b"),
            to: fixture(title: "Old", author: nil), password: nil)
        let meta = try PDFMetadataService.read(from: edited, password: nil)
        XCTAssertEqual(meta.title, "New Title")
        XCTAssertEqual(meta.keywords, "a, b")
        XCTAssertEqual(PDFDocument(data: edited)?.pageCount, 1)   // structure intact
    }

    func testNilClearsKey() throws {
        let edited = try PDFMetadataService.write(
            PDFDocumentMetadata(), to: fixture(title: "Old", author: "A"), password: nil)
        let meta = try PDFMetadataService.read(from: edited, password: nil)
        XCTAssertNil(meta.title)
        XCTAssertNil(meta.author)
    }

    // Round-trips a non-ASCII value: the write path must encode UTF-8 into a
    // valid PDF string (UTF-16BE + BOM) the same way the read path decodes it,
    // or CJK/RTL titles corrupt silently.
    func testWritePreservesUnicode() throws {
        let edited = try PDFMetadataService.write(
            PDFDocumentMetadata(title: "折り紙", author: "うまん", subject: "विषय", keywords: "标签"),
            to: fixture(title: "Old", author: nil), password: nil)
        let meta = try PDFMetadataService.read(from: edited, password: nil)
        XCTAssertEqual(meta.title, "折り紙")
        XCTAssertEqual(meta.author, "うまん")
        XCTAssertEqual(meta.subject, "विषय")
        XCTAssertEqual(meta.keywords, "标签")
    }
}
