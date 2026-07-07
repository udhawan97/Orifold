import Foundation
import PDFKit

/// Decides which byte stream Orifold persists for an imported PDF.
///
/// The naive choice — always re-serialize the loaded `PDFDocument` through PDFKit
/// (`PDFSerializer.data(from:)`) — rebuilds the entire PDF object graph and can silently
/// destroy an intact text layer. Chrome / Skia "Save as PDF" (and other producers) emit
/// body text as Type 3 fonts that PDFKit's rewrite drops: the page still *renders*, but
/// PDFium/PDFKit can no longer see the text, so clicking a line finds no editable block
/// and inline edits stamp new text ON TOP of the original instead of replacing it.
///
/// Instead, when the source was already a PDF we keep its original object graph and run it
/// through a qpdf hardening pass (`QPDFService.sanitized`), which strips active content
/// (`/OpenAction`, `/AA`, JavaScript, embedded files) while preserving fonts and content
/// streams faithfully — text layer intact, attack surface reduced. Only when qpdf cannot
/// handle the file at all do we fall back to PDFKit's forgiving-but-lossy rebuild.
///
/// Every candidate additionally passes a two-parser agreement gate before we trust it:
/// PDFium (the engine that renders and text-analyzes the bytes) must load it with a page
/// count that matches the PDFKit document the user sees. Divergence means the two parsers
/// disagree about the file's structure — precisely the malformed/hostile case we refuse to
/// persist, falling through to the sanitized rebuild instead.
enum PDFImportNormalizer {
    /// Produces the bytes to persist for `renderedPDF`, or `nil` when no candidate is even
    /// loadable (callers surface this as an "unreadable / could not prepare" import error,
    /// matching the pre-existing `PDFSerializer.data(from:) == nil` contract).
    ///
    /// - Parameters:
    ///   - originalPDFData: exact bytes of the source when it was already a PDF file (raw,
    ///     or qpdf-repaired if PDFKit needed repair to open it). `nil` for documents
    ///     synthesized from HTML/image/text/RTFD — those have no faithful original byte
    ///     stream and must be serialized from `renderedPDF`.
    ///   - renderedPDF: the `PDFDocument` the user will actually see; its page count is the
    ///     reference the agreement gate checks candidates against.
    ///   - processingEngine: the parser used for the agreement gate (PDFium in production;
    ///     injectable for tests).
    static func normalizedData(
        originalPDFData: Data?,
        renderedPDF: PDFDocument,
        using processingEngine: PDFProcessingEngine = PDFiumProcessingEngine()
    ) -> Data? {
        let expectedPageCount = renderedPDF.pageCount

        // 1. Source was a PDF file: preserve its object graph. Prefer the qpdf-hardened
        //    bytes; accept the untouched original only if hardening failed but both parsers
        //    still read it. Either way the faithful text layer survives.
        if let originalPDFData {
            if let hardened = QPDFService.sanitized(originalPDFData, removingMetadata: false),
               isTrustworthy(hardened, expectedPageCount: expectedPageCount, using: processingEngine) {
                return hardened
            }
            if isTrustworthy(originalPDFData, expectedPageCount: expectedPageCount, using: processingEngine) {
                return originalPDFData
            }
        }

        // 2. Synthesized document, or an original both qpdf and the agreement gate rejected:
        //    fall back to PDFKit's serialization of the loaded document.
        guard let rebuilt = PDFSerializer.data(from: renderedPDF) else { return nil }
        if isTrustworthy(rebuilt, expectedPageCount: expectedPageCount, using: processingEngine) {
            return rebuilt
        }

        // 3. Last resort: the agreement gate could not be satisfied (e.g. PDFium disagrees
        //    on page count, or is unavailable), but the PDFKit rebuild is itself loadable.
        //    Persist it rather than fail outright — this preserves the historical behavior
        //    of "always trust the PDFKit rebuild" for the rare files that reach here.
        if (PDFDocument(data: rebuilt)?.pageCount ?? 0) > 0 {
            return rebuilt
        }
        return nil
    }

    /// Two-parser agreement gate: `data` must load in PDFium (the engine that renders and
    /// text-analyzes it downstream) with a positive page count equal to the PDFKit document
    /// the user sees. A mismatch means the parsers interpret the file differently — the
    /// "weird PDF" signal we refuse to trust.
    private static func isTrustworthy(
        _ data: Data,
        expectedPageCount: Int,
        using processingEngine: PDFProcessingEngine
    ) -> Bool {
        guard expectedPageCount > 0 else { return false }
        do {
            let validation = try processingEngine.validatePDF(data: data, password: nil)
            return validation.pageCount == expectedPageCount
        } catch {
            return false
        }
    }
}
