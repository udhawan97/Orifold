import PDFKit
import UniformTypeIdentifiers
import XCTest
@testable import Orifold

/// Hardening sweep for the PDF import path: feeds a battery of malformed,
/// truncated, and structurally-adversarial byte sequences through the same
/// entry point real imports use, and asserts the pipeline never crashes --
/// only ever succeeds cleanly or fails with a typed `ConversionError`. This
/// is the local, always-run equivalent of fuzzing against public malformed-
/// PDF corpora (pdf.js's and qpdf's test suites take the same approach):
/// import must be bulletproof against garbage input, not just clean ones.
final class ImportStressTests: XCTestCase {
    private func assertNeverCrashes(_ data: Data, file: StaticString = #filePath, line: UInt = #line) {
        do {
            let imported = try DocumentImportConverter.importedDocument(
                from: data,
                contentType: .pdf,
                filename: "stress.pdf",
                baseURL: nil
            )
            XCTAssertGreaterThan(imported.pdfDocument.pageCount, 0, "a document reported as imported must have pages", file: file, line: line)
        } catch is DocumentImportConverter.ConversionError {
            // Expected outcome for genuinely unrecoverable input.
        } catch {
            XCTFail("unexpected error type: \(error)", file: file, line: line)
        }
    }

    func testTruncationSweepOfAValidMultiPageDocumentNeverCrashes() throws {
        let pdf = PDFDocument()
        for index in 0..<6 {
            let view = NSView(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
            let page = try XCTUnwrap(PDFDocument(data: view.dataWithPDF(inside: view.bounds))?.page(at: 0))
            pdf.insert(page, at: index)
        }
        let full = try XCTUnwrap(pdf.dataRepresentation())

        // Truncate at every 5% boundary -- covers cutting mid-header, mid-object,
        // mid-stream, mid-xref, and mid-trailer without a 6600-byte-by-byte sweep.
        for percent in stride(from: 5, through: 95, by: 5) {
            let cutoff = full.count * percent / 100
            assertNeverCrashes(full.prefix(cutoff))
        }
    }

    func testByteFlipSweepOfAValidDocumentNeverCrashes() throws {
        let pdf = PDFDocument()
        pdf.insert(try XCTUnwrap(makeSinglePagePDF()), at: 0)
        let original = try XCTUnwrap(pdf.dataRepresentation())

        // Flip one byte at a time across evenly spaced offsets. A single bit
        // flip in the xref table, an object header, or the trailer is exactly
        // the class of corruption real-world "the download got interrupted"
        // or "the disk had a bad sector" bugs produce.
        let stride = max(1, original.count / 40)
        for offset in Swift.stride(from: 0, to: original.count, by: stride) {
            var mutated = original
            mutated[offset] = mutated[offset] ^ 0xFF
            assertNeverCrashes(mutated)
        }
    }

    func testStructurallyAdversarialFixturesNeverCrash() {
        let fixtures: [Data] = [
            Data(), // empty
            Data("%PDF-1.4".utf8), // header only
            Data("%PDF-1.4\n%%EOF".utf8), // header + EOF, no objects
            Data("not a pdf at all, just text".utf8),
            Data(repeating: 0, count: 4096), // all zero bytes
            Data((0..<4096).map { UInt8($0 % 256) }), // pseudo-random binary
            // Trailer references a Root object that doesn't exist.
            Data("""
            %PDF-1.4
            1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj
            trailer<</Root 99 0 R/Size 100>>
            %%EOF
            """.utf8),
            // Circular Pages reference (Pages points to itself as a Kid).
            Data("""
            %PDF-1.4
            1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj
            2 0 obj<</Type/Pages/Kids[2 0 R]/Count 1>>endobj
            trailer<</Root 1 0 R/Size 3>>
            %%EOF
            """.utf8),
            // Page claims a stream /Length far larger than the actual data.
            Data("""
            %PDF-1.4
            1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj
            2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj
            3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 200 200]/Contents 4 0 R>>endobj
            4 0 obj<</Length 999999999>>stream
            short
            endstream endobj
            trailer<</Root 1 0 R/Size 5>>
            %%EOF
            """.utf8),
            // Negative and absurdly large object/generation numbers in xref-like text.
            Data("""
            %PDF-1.4
            1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj
            2 0 obj<</Type/Pages/Kids[3 0 R]/Count -1>>endobj
            3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 -100 999999999]>>endobj
            trailer<</Root 1 0 R/Size 4>>
            %%EOF
            """.utf8),
            // Deeply nested arrays, a classic stack-overflow-by-parser probe.
            Data("%PDF-1.4\n1 0 obj\(String(repeating: "[", count: 5000))1\(String(repeating: "]", count: 5000))endobj\ntrailer<</Root 1 0 R/Size 2>>\n%%EOF".utf8),
        ]

        for fixture in fixtures {
            assertNeverCrashes(fixture)
        }
    }

    func testQPDFServiceNeverCrashesOnTheSameAdversarialFixtures() {
        let fixtures: [Data] = [
            Data(),
            Data("%PDF-1.4".utf8),
            Data(repeating: 0, count: 4096),
            Data((0..<4096).map { UInt8($0 % 256) }),
            Data("%PDF-1.4\n1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj\ntrailer<</Root 99 0 R/Size 100>>\n%%EOF".utf8),
        ]
        for fixture in fixtures {
            _ = QPDFService.repaired(fixture)
            _ = QPDFService.isStructurallySound(fixture)
            _ = QPDFService.optimized(fixture, linearize: false)
            _ = QPDFService.sanitized(fixture, removingMetadata: true)
            // Reaching this line without a crash is the assertion.
        }
    }

    private func makeSinglePagePDF() -> PDFPage? {
        let view = NSView(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
        return PDFDocument(data: view.dataWithPDF(inside: view.bounds))?.page(at: 0)
    }
}
