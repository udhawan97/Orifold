import PDFKit
import XCTest
@testable import Orifold

final class QPDFServiceTests: XCTestCase {
    func testRepairedRecoversPDFWithMissingCrossReferenceTable() throws {
        // No xref table and no `startxref` at all -- CoreGraphics happens to
        // tolerate this particular shape via its own leniency, but it's still
        // a structurally invalid PDF (no valid xref, per the spec) that many
        // other readers reject outright. qpdf's recovery scans for objects by
        // brute force and rebuilds a real, spec-compliant xref table, which is
        // the actual value of this pass: defense in depth ahead of PDFKit,
        // not a replacement for it.
        let broken = Data("""
        %PDF-1.4
        1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj
        2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj
        3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 200 200]>>endobj
        trailer<</Root 1 0 R/Size 4>>
        %%EOF
        """.utf8)
        XCTAssertFalse(
            String(decoding: broken, as: UTF8.self).contains("startxref"),
            "fixture should have no xref table or startxref pointer before repair"
        )

        let repaired = try XCTUnwrap(QPDFService.repaired(broken))
        XCTAssertTrue(
            String(decoding: repaired, as: UTF8.self).contains("startxref"),
            "repair should have written a real cross-reference table"
        )
        XCTAssertTrue(QPDFService.isStructurallySound(repaired))
        let repairedPDF = try XCTUnwrap(PDFDocument(data: repaired))
        XCTAssertEqual(repairedPDF.pageCount, 1)
    }

    func testRepairedReturnsNilForNonPDFData() {
        let notAPDF = Data("this is not a pdf".utf8)
        XCTAssertNil(QPDFService.repaired(notAPDF))
    }

    func testIsStructurallySoundAcceptsValidPDFAndRejectsGarbage() throws {
        let pdf = PDFDocument()
        pdf.insert(makeBlankPage(), at: 0)
        let data = try XCTUnwrap(pdf.dataRepresentation())

        XCTAssertTrue(QPDFService.isStructurallySound(data))
        XCTAssertFalse(QPDFService.isStructurallySound(Data("not a pdf".utf8)))
    }

    func testOptimizedProducesStructurallySoundReadableOutput() throws {
        let pdf = PDFDocument()
        for _ in 0..<5 { pdf.insert(makeBlankPage(), at: pdf.pageCount) }
        let data = try XCTUnwrap(pdf.dataRepresentation())

        let optimized = try XCTUnwrap(QPDFService.optimized(data, linearize: false))
        XCTAssertTrue(QPDFService.isStructurallySound(optimized))
        let optimizedPDF = try XCTUnwrap(PDFDocument(data: optimized))
        XCTAssertEqual(optimizedPDF.pageCount, 5)
    }

    func testOptimizedWithLinearizationStillProducesValidPDF() throws {
        let pdf = PDFDocument()
        pdf.insert(makeBlankPage(), at: 0)
        let data = try XCTUnwrap(pdf.dataRepresentation())

        let linearized = try XCTUnwrap(QPDFService.optimized(data, linearize: true))
        XCTAssertTrue(QPDFService.isStructurallySound(linearized))
        XCTAssertEqual(PDFDocument(data: linearized)?.pageCount, 1)
    }

    func testEncryptedAES256ProducesR6EncryptionDictionaryAndUnlocks() throws {
        let pdf = PDFDocument()
        pdf.insert(makeBlankPage(), at: 0)
        let data = try XCTUnwrap(pdf.dataRepresentation())

        let encrypted = try QPDFService.encryptedAES256(
            data,
            userPassword: "reader-pass",
            ownerPassword: "owner-pass",
            allowsPrinting: false,
            allowsCopying: false
        )

        // /V 5 /R 6 is the PDF 2.0 marker for AES-256; PDFKit's own CoreGraphics
        // path (kCGPDFContextEncryptionKeyLength: 128) never produces this.
        let raw = String(decoding: encrypted, as: UTF8.self)
        XCTAssertTrue(raw.contains("/V 5"), "expected AES-256 (/V 5) encryption dictionary")
        XCTAssertTrue(raw.contains("/R 6"), "expected revision 6 encryption dictionary")

        let encryptedPDF = try XCTUnwrap(PDFDocument(data: encrypted))
        XCTAssertTrue(encryptedPDF.isLocked)
        XCTAssertFalse(encryptedPDF.unlock(withPassword: "wrong-pass"))
        XCTAssertTrue(encryptedPDF.unlock(withPassword: "reader-pass"))
        XCTAssertFalse(encryptedPDF.allowsPrinting)
        XCTAssertFalse(encryptedPDF.allowsCopying)
    }

    func testIsStructurallySoundRequiresThePasswordForEncryptedData() throws {
        // Regression test: qpdf cannot parse encrypted content it can't
        // decrypt, so checking encrypted output without its password makes
        // qpdf report it as unsound even though the file is perfectly valid.
        let pdf = PDFDocument()
        pdf.insert(makeBlankPage(), at: 0)
        let data = try XCTUnwrap(pdf.dataRepresentation())
        let encrypted = try QPDFService.encryptedAES256(
            data,
            userPassword: "reader-pass",
            ownerPassword: "owner-pass",
            allowsPrinting: true,
            allowsCopying: true
        )

        XCTAssertFalse(
            QPDFService.isStructurallySound(encrypted),
            "without the password qpdf cannot decrypt the content, so this legitimately can't confirm soundness"
        )
        XCTAssertTrue(QPDFService.isStructurallySound(encrypted, password: "reader-pass"))
    }

    func testEncryptedAES256ThrowsForUnreadableSourceData() {
        XCTAssertThrowsError(try QPDFService.encryptedAES256(
            Data("not a pdf".utf8),
            userPassword: "a",
            ownerPassword: "b",
            allowsPrinting: true,
            allowsCopying: true
        )) { error in
            XCTAssertEqual(error as? QPDFService.QPDFServiceError, .cannotOpenSourcePDF)
        }
    }

    func testSanitizedRemovesOpenActionJavaScriptAndEmbeddedFiles() throws {
        let withActiveContent = Data("""
        %PDF-1.6
        1 0 obj<</Type/Catalog/Pages 2 0 R/OpenAction<</S/JavaScript/JS(app.alert\\('hi'\\))>>/Names<</JavaScript<</Names[(x) 5 0 R]>>/EmbeddedFiles<</Names[(payload.txt) 6 0 R]>>>>>>endobj
        2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj
        3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 200 200]>>endobj
        4 0 obj<</Author(Someone)/Producer(Orifold)>>endobj
        5 0 obj<</S/JavaScript/JS(app.alert\\('named'\\))>>endobj
        6 0 obj<</Type/Filespec/F(payload.txt)>>endobj
        trailer<</Root 1 0 R/Info 4 0 R/Size 7>>
        %%EOF
        """.utf8)

        let sanitized = try XCTUnwrap(QPDFService.sanitized(withActiveContent, removingMetadata: true))
        XCTAssertTrue(QPDFService.isStructurallySound(sanitized))

        let raw = String(decoding: sanitized, as: UTF8.self)
        XCTAssertFalse(raw.contains("OpenAction"), "OpenAction should be stripped")
        XCTAssertFalse(raw.contains("JavaScript"), "JavaScript name tree should be stripped")
        XCTAssertFalse(raw.contains("app.alert"), "JavaScript action content should be unreachable")
        XCTAssertFalse(raw.contains("EmbeddedFiles"), "EmbeddedFiles name tree should be stripped")
        XCTAssertFalse(raw.contains("Someone"), "Info dictionary (Author) should be stripped when removingMetadata is true")

        let sanitizedPDF = try XCTUnwrap(PDFDocument(data: sanitized))
        XCTAssertEqual(sanitizedPDF.pageCount, 1, "sanitizing must not remove actual page content")
    }

    func testSanitizedPreservesMetadataWhenNotRequested() throws {
        let withActiveContent = Data("""
        %PDF-1.6
        1 0 obj<</Type/Catalog/Pages 2 0 R/OpenAction<</S/JavaScript/JS(app.alert\\('hi'\\))>>>>endobj
        2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj
        3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 200 200]>>endobj
        4 0 obj<</Author(Someone)>>endobj
        trailer<</Root 1 0 R/Info 4 0 R/Size 5>>
        %%EOF
        """.utf8)

        let sanitized = try XCTUnwrap(QPDFService.sanitized(withActiveContent, removingMetadata: false))
        let raw = String(decoding: sanitized, as: UTF8.self)
        XCTAssertFalse(raw.contains("OpenAction"))
        XCTAssertTrue(raw.contains("Someone"), "Info dictionary should survive when removingMetadata is false")
    }

    func testSanitizedReturnsNilForUnreadableData() {
        XCTAssertNil(QPDFService.sanitized(Data("not a pdf".utf8), removingMetadata: true))
    }

    private func makeBlankPage() -> PDFPage {
        let view = NSView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        let data = view.dataWithPDF(inside: view.bounds)
        return PDFDocument(data: data)!.page(at: 0)!
    }
}
