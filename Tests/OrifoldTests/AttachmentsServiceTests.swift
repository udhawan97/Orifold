import PDFKit
import XCTest
@testable import Orifold

final class AttachmentsServiceTests: XCTestCase {
    func testListEmptyWhenNoAttachments() throws {
        let bare = PDFDocument()
        bare.insert(PDFPage(), at: 0)
        XCTAssertEqual(try AttachmentsService.list(in: try XCTUnwrap(bare.dataRepresentation())), [])
    }
    func testAddListExtractRoundTrip() throws {
        let base: Data = {
            let document = PDFDocument()
            document.insert(PDFPage(), at: 0)
            return document.dataRepresentation()!
        }()
        let payload = Data("hello-orifold".utf8)

        let withAttachment = try AttachmentsService.add(payload, name: "note.txt", mimeType: "text/plain", to: base)
        let listed = try AttachmentsService.list(in: withAttachment)
        XCTAssertEqual(listed.map(\.name), ["note.txt"])
        XCTAssertEqual(listed.first?.byteCount, payload.count)
        XCTAssertEqual(listed.first?.mimeType, "text/plain")
        XCTAssertEqual(try AttachmentsService.extract("note.txt", from: withAttachment), payload) // byte-identical

        let removed = try AttachmentsService.remove("note.txt", from: withAttachment)
        XCTAssertEqual(try AttachmentsService.list(in: removed), [])
        XCTAssertTrue(QPDFService.isStructurallySound(removed))
    }

    func testAddDisambiguatesDuplicateKey() throws {
        let base: Data = {
            let document = PDFDocument()
            document.insert(PDFPage(), at: 0)
            return document.dataRepresentation()!
        }()
        let first = try AttachmentsService.add(Data("one".utf8), name: "note.txt", mimeType: nil, to: base)
        let second = try AttachmentsService.add(Data("two".utf8), name: "note.txt", mimeType: nil, to: first)
        // qpdf refuses a duplicate name-tree key, so the second add must land under
        // a distinct key rather than silently failing or overwriting the first.
        XCTAssertEqual(Set(try AttachmentsService.list(in: second).map(\.name)), ["note.txt", "note-2.txt"])
        XCTAssertEqual(try AttachmentsService.extract("note.txt", from: second), Data("one".utf8))
        XCTAssertEqual(try AttachmentsService.extract("note-2.txt", from: second), Data("two".utf8))
    }

    func testExtractThrowsNotFoundForMissingAttachment() throws {
        let base: Data = {
            let document = PDFDocument()
            document.insert(PDFPage(), at: 0)
            return document.dataRepresentation()!
        }()
        let withAttachment = try AttachmentsService.add(Data("x".utf8), name: "a.txt", mimeType: nil, to: base)
        XCTAssertThrowsError(try AttachmentsService.extract("missing.txt", from: withAttachment)) { error in
            XCTAssertEqual(error as? AttachmentsError, .notFound)
        }
    }
}
