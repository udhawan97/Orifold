import XCTest
import PDFKit
@testable import Orifold

/// J1 binding-link proof: exercises the three new `imp_*` @_silgen_name bindings end-to-end so a
/// missing/renamed symbol fails at link time (the release-build duplicate-type hazard the plan
/// guards against). The full `PDFImpositionEngine.impose` round-trip lands in J3
/// (`PDFImpositionEngineTests`); this keeps J1 green on its own.
final class PDFiumImpositionBindingsTests: XCTestCase {
    private func twoPageFixture() -> Data {
        let doc = PDFDocument()
        for _ in 0..<2 { doc.insert(PDFPage(), at: doc.pageCount) }
        return doc.dataRepresentation()!   // fixture only — never product code
    }

    func testImpositionSymbolsLinkAndRoundTrip() throws {
        let fixture = twoPageFixture()
        pdfiumLock.lock()
        defer { pdfiumLock.unlock() }
        FPDF_InitLibrary()
        defer { FPDF_DestroyLibrary() }

        // FPDF_CreateNewDocument links and yields an owned handle.
        let created = imp_CreateNewDocument()
        XCTAssertNotNil(created)
        defer { FPDF_CloseDocument(created) }

        try fixture.withUnsafeBytes { raw in
            let base = try XCTUnwrap(raw.baseAddress)
            let src = try XCTUnwrap(FPDF_LoadMemDocument(base, Int32(fixture.count), nil))
            defer { FPDF_CloseDocument(src) }
            XCTAssertEqual(FPDF_GetPageCount(src), 2)

            // FPDF_ImportPages links: pull page 1 (1-indexed) into the new doc at index 0.
            XCTAssertNotEqual(imp_ImportPages(created, src, "1", 0), 0)
            XCTAssertEqual(FPDF_GetPageCount(created), 1)

            // FPDF_ImportNPagesToOne links: 2 src pages -> 1 sheet (2x1), owned handle.
            let imposed = imp_ImportNPagesToOne(src, 1224, 792, 2, 1)
            XCTAssertNotNil(imposed)
            defer { FPDF_CloseDocument(imposed) }
            XCTAssertEqual(FPDF_GetPageCount(imposed), 1)
        }
    }
}
