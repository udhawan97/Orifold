import PDFKit
import UniformTypeIdentifiers
import XCTest

@testable import Orifold

final class PDFImportNormalizerTests: XCTestCase {
    // MARK: - Fixtures

    /// A minimal but valid multi-line text PDF. PDFKit-generated, so its own bytes are a
    /// realistic "original" that a naive re-serialization would needlessly rewrite.
    private func makeTextPDF(lines: [String] = ["Reservation line one", "Guest detail two"]) throws -> (pdf: PDFDocument, data: Data) {
        let view = NormalizerFixturePageView(frame: CGRect(x: 0, y: 0, width: 612, height: 792), lines: lines)
        let data = view.dataWithPDF(inside: view.bounds)
        let pdf = try XCTUnwrap(PDFDocument(data: data))
        return (pdf, data)
    }

    // MARK: - Preservation (the root fix)

    func testPrefersQPDFPreservedOriginalOverPDFKitRebuild() throws {
        let (pdf, raw) = try makeTextPDF()
        let expectedHardened = try XCTUnwrap(QPDFService.sanitized(raw, removingMetadata: false))
        let pdfKitRebuild = try XCTUnwrap(PDFSerializer.data(from: pdf))

        let normalized = try XCTUnwrap(
            PDFImportNormalizer.normalizedData(
                originalPDFData: raw,
                renderedPDF: pdf,
                using: PDFKitProcessingEngineFallback()
            )
        )

        // The normalizer must return the qpdf-hardened ORIGINAL, never PDFKit's rebuild:
        // that rebuild is exactly what destroys Type 3 text layers and triggers the
        // "typed text lands on top of the original" bug.
        XCTAssertEqual(normalized, expectedHardened, "should keep the qpdf-preserved original")
        XCTAssertNotEqual(normalized, pdfKitRebuild, "should not fall through to the lossy PDFKit rebuild")

        // And it stays a readable, page-count-preserving document.
        let normalizedPDF = try XCTUnwrap(PDFDocument(data: normalized))
        XCTAssertEqual(normalizedPDF.pageCount, pdf.pageCount)
    }

    func testSynthesizedDocumentWithNoOriginalBytesUsesPDFKitRebuild() throws {
        // HTML/image/text imports have no faithful original byte stream; with no original
        // to preserve, the normalizer serializes from the rendered PDFDocument (PDFKit's
        // `dataRepresentation` embeds a nondeterministic document ID, so this is asserted
        // by loadability + page count, not byte-equality).
        let (pdf, raw) = try makeTextPDF()
        let normalized = try XCTUnwrap(
            PDFImportNormalizer.normalizedData(
                originalPDFData: nil,
                renderedPDF: pdf,
                using: PDFKitProcessingEngineFallback()
            )
        )
        let normalizedPDF = try XCTUnwrap(PDFDocument(data: normalized))
        XCTAssertEqual(normalizedPDF.pageCount, pdf.pageCount)
        // With no original supplied it must NOT be the qpdf-preserved-original bytes.
        XCTAssertNotEqual(normalized, QPDFService.sanitized(raw, removingMetadata: false))
    }

    // MARK: - Hardening (protect against weird / hostile PDFs)

    func testActiveContentIsStrippedThroughTheNormalizer() throws {
        // Same active-content fixture QPDFServiceTests uses, driven through the import
        // normalizer so the end-to-end import path is proven to neutralize it.
        let withActiveContent = Data("""
        %PDF-1.4
        1 0 obj<</Type/Catalog/Pages 2 0 R/OpenAction<</S/JavaScript/JS(app.alert\\('hi'\\))>>/Names<</JavaScript<</Names[(x) 5 0 R]>>>>>>endobj
        2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj
        3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 200 200]>>endobj
        5 0 obj<</S/JavaScript/JS(app.alert\\('named'\\))>>endobj
        trailer<</Root 1 0 R/Size 6>>
        %%EOF
        """.utf8)
        let pdf = try XCTUnwrap(PDFDocument(data: withActiveContent) ?? QPDFService.repaired(withActiveContent).flatMap(PDFDocument.init(data:)))

        let normalized = try XCTUnwrap(
            PDFImportNormalizer.normalizedData(
                originalPDFData: withActiveContent,
                renderedPDF: pdf,
                using: PDFKitProcessingEngineFallback()
            )
        )
        let text = String(decoding: normalized, as: UTF8.self)
        XCTAssertFalse(text.contains("OpenAction"), "OpenAction must be stripped on import")
        XCTAssertFalse(text.contains("JavaScript"), "JavaScript name tree must be stripped on import")
        XCTAssertFalse(text.contains("app.alert"), "JavaScript payload must be unreachable after import")
    }

    func testMalformedOriginalFallsBackToRebuildOfRenderedDocument() throws {
        // Original bytes are garbage neither qpdf nor PDFium can trust; the rendered
        // PDFDocument is fine. The normalizer must not return the garbage — it falls back
        // to a clean rebuild that still loads with the right page count.
        let (pdf, _) = try makeTextPDF()
        let garbage = Data("%PDF-1.4 totally broken not a real object graph".utf8)

        let normalized = try XCTUnwrap(
            PDFImportNormalizer.normalizedData(
                originalPDFData: garbage,
                renderedPDF: pdf,
                using: PDFKitProcessingEngineFallback()
            )
        )
        XCTAssertNotEqual(normalized, garbage)
        let normalizedPDF = try XCTUnwrap(PDFDocument(data: normalized))
        XCTAssertEqual(normalizedPDF.pageCount, pdf.pageCount)
    }

    func testPageCountDisagreementRejectsOriginalAndRebuilds() throws {
        // A valid 1-page original, but the rendered document the user sees has 2 pages:
        // the two parsers disagree about the file, so the agreement gate rejects the
        // original and the normalizer rebuilds to match what is displayed.
        let (_, oneRaw) = try makeTextPDF(lines: ["Only one page here"])
        let (twoPagePDF, _) = try makeTextPDF(lines: ["Page one"])
        let secondPage = try XCTUnwrap(PDFDocument(data: try makeTextPDF(lines: ["Page two"]).data).flatMap { $0.page(at: 0) })
        twoPagePDF.insert(secondPage, at: 1)
        XCTAssertEqual(twoPagePDF.pageCount, 2)

        let normalized = try XCTUnwrap(
            PDFImportNormalizer.normalizedData(
                originalPDFData: oneRaw,
                renderedPDF: twoPagePDF,
                using: PDFKitProcessingEngineFallback()
            )
        )
        let normalizedPDF = try XCTUnwrap(PDFDocument(data: normalized))
        XCTAssertEqual(normalizedPDF.pageCount, 2, "must match the displayed document, not the 1-page original")
    }

    // MARK: - End-to-end import path

    func testDocumentImportPersistsTextPreservingBytes() throws {
        let (_, raw) = try makeTextPDF()
        let wrapper = FileWrapper(regularFileWithContents: raw)
        wrapper.preferredFilename = "reservation.pdf"

        let document = try WorkspaceDocument(testingFile: wrapper, contentType: .pdf, filename: "reservation.pdf")

        let stored = try XCTUnwrap(document.memberPDFData.values.first)
        let expectedHardened = try XCTUnwrap(QPDFService.sanitized(raw, removingMetadata: false))
        XCTAssertEqual(stored, expectedHardened, "import must persist the qpdf-preserved original, not a PDFKit rebuild")
    }
}

/// Draws several distinct text lines so the fixture has a real, analyzable text layer.
private final class NormalizerFixturePageView: NSView {
    private let lines: [String]

    init(frame: NSRect, lines: [String]) {
        self.lines = lines
        super.init(frame: frame)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("unavailable") }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        bounds.fill()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 18),
            .foregroundColor: NSColor.black
        ]
        for (index, line) in lines.enumerated() {
            let y = 80 + CGFloat(index) * 40
            (line as NSString).draw(at: CGPoint(x: 60, y: y), withAttributes: attributes)
        }
    }
}
