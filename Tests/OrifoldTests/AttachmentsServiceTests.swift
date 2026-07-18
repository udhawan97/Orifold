import PDFKit
import XCTest
@testable import Orifold

final class AttachmentsServiceTests: XCTestCase {
    func testListEmptyWhenNoAttachments() throws {
        let bare = PDFDocument()
        bare.insert(PDFPage(), at: 0)
        XCTAssertEqual(try AttachmentsService.list(in: try XCTUnwrap(bare.dataRepresentation())), [])
    }
    // round-trip lives in the add/remove test (add -> list -> extract byte-identical)
}
