import PDFKit
import XCTest
@testable import Orifold

/// Link-proof for the read-only tagged-PDF structure surface (`fpdf_structtree.h`).
///
/// These assert almost nothing about *content* on purpose — their job is to prove the
/// `pst_*` symbols resolve against the vendored PDFium and that the tree handle obeys
/// its lifecycle. Semantic coverage lives in `StructureInspectionServiceTests`.
final class PDFiumStructureBindingsTests: XCTestCase {

    func testUntaggedPageHasNoStructureTree() throws {
        let document = PDFDocument()
        document.insert(PDFPage(), at: 0)
        let data = try XCTUnwrap(document.dataRepresentation())

        pdfiumLock.lock()
        defer { pdfiumLock.unlock() }
        FPDF_InitLibrary()
        defer { FPDF_DestroyLibrary() }

        let handle = data.withUnsafeBytes {
            FPDF_LoadMemDocument($0.baseAddress, Int32(data.count), nil)
        }
        defer { FPDF_CloseDocument(handle) }

        let page = poe_LoadPage(handle, 0)
        defer { poe_ClosePage(page) }

        let tree = pst_StructTree_GetForPage(page)
        defer { if tree != nil { pst_StructTree_Close(tree) } }

        // An untagged page yields either a nil tree or one reporting zero children.
        // Both prove the symbols linked; neither is a content assertion.
        XCTAssertTrue(tree == nil || pst_StructTree_CountChildren(tree) == 0)
    }

    func testUTF16HelperReturnsNilForAnEmptyGetter() {
        // A getter reporting 2 bytes is just the UTF-16 NUL — i.e. an absent string.
        // Callers must see nil rather than "".
        let empty = pst_utf16String { _, _ in 2 }

        XCTAssertNil(empty)
    }

    func testUTF16HelperDecodesLittleEndianPayload() {
        // "H1" as UTF-16LE plus the terminating NUL: 6 bytes reported by PDFium.
        let payload: [UInt8] = [0x48, 0x00, 0x31, 0x00, 0x00, 0x00]

        let decoded = pst_utf16String { buffer, length in
            guard let buffer else { return UInt(payload.count) }
            let count = min(Int(length), payload.count)
            payload.withUnsafeBytes { source in
                buffer.copyMemory(from: source.baseAddress!, byteCount: count)
            }
            return UInt(payload.count)
        }

        XCTAssertEqual(decoded, "H1")
    }
}
