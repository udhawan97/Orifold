import Foundation

enum PDFImpositionError: LocalizedError {
    case invalidPDF
    case impositionFailed
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .invalidPDF:
            return L10n.string("error.imposition.invalidPDF")
        case .impositionFailed:
            return L10n.string("error.imposition.failed")
        case .saveFailed:
            return L10n.string("error.imposition.saveFailed")
        }
    }
}

/// Save accumulator for the PDFium write callback — a file-private global mirroring
/// `PDFCompressionService`'s pattern, safe only because `pdfiumLock` serialises every call.
private var impositionSaveData = Data()

/// Byte-level imposition (booklet / N-up) on top of PDFium's page-porting API.
///
/// `FPDF_ImportNPagesToOne` flattens every source page into a form XObject, which DROPS
/// annotations (stamps, signatures, markup). That is why `impose` takes `BakedPDFData` rather
/// than raw bytes: the requirement is a type, not a comment, because the failure is silent —
/// imposing a live document yields structurally valid output with the annotations quietly
/// missing, so no error and no soundness check can catch it.
///
/// All PDFium calls hold the global `pdfiumLock`. Lifecycle
/// (`FPDF_LoadMemDocument`/`FPDF_CloseDocument`/`FPDF_GetPageCount`), the save binding
/// (`FPDFCompression_SaveAsCopy` + `FPDFCompressionFileWrite`) and the page-size getters
/// (`poe_*`) are REUSED, not re-declared — only the `imp_*` port bindings are new.
enum PDFImpositionEngine {
    /// Imposes already-flattened export bytes per `layout` and returns new bytes.
    /// Holds `pdfiumLock` for the whole call. The output is gated through
    /// `QPDFService.isStructurallySound` before it is returned.
    static func impose(_ baked: BakedPDFData, layout: ImpositionLayout) throws -> Data {
        let data = baked.bytes
        guard !data.isEmpty, data.count <= Int(Int32.max) else { throw PDFImpositionError.invalidPDF }

        pdfiumLock.lock()
        defer { pdfiumLock.unlock() }
        FPDF_InitLibrary()
        defer { FPDF_DestroyLibrary() }

        return try data.withUnsafeBytes { rawBuffer -> Data in
            guard let baseAddress = rawBuffer.baseAddress,
                  let source = FPDF_LoadMemDocument(baseAddress, Int32(data.count), nil) else {
                throw PDFImpositionError.invalidPDF
            }
            defer { FPDF_CloseDocument(source) }

            let pageCount = Int(FPDF_GetPageCount(source))
            guard pageCount > 0 else { throw PDFImpositionError.invalidPDF }
            let (width, height) = try pageZeroSize(source)

            switch layout {
            case let .nUp(rows, cols):
                guard rows > 0, cols > 0 else { throw PDFImpositionError.impositionFailed }
                // Tile source pages at 1:1 — the output sheet grows to hold the grid (matches the
                // booklet convention of a 2*W x H sheet), so nothing is scaled down.
                let outputWidth = Float(width) * Float(cols)
                let outputHeight = Float(height) * Float(rows)
                guard let imposed = imp_ImportNPagesToOne(source, outputWidth, outputHeight, cols, rows) else {
                    throw PDFImpositionError.impositionFailed
                }
                defer { FPDF_CloseDocument(imposed) }
                return try save(imposed)

            case .booklet:
                let reordered = try makeBookletReorderedDocument(from: source, pageCount: pageCount,
                                                                 width: width, height: height)
                defer { FPDF_CloseDocument(reordered) }
                // 2-up saddle stitch: each sheet side holds 2 booklet-ordered pages (2 x 1),
                // producing a 2*W x H landscape sheet.
                guard let imposed = imp_ImportNPagesToOne(reordered, Float(width) * 2, Float(height), 2, 1) else {
                    throw PDFImpositionError.impositionFailed
                }
                defer { FPDF_CloseDocument(imposed) }
                return try save(imposed)
            }
        }
    }

    /// Builds an intermediate document whose pages are the source pages reordered into booklet
    /// (saddle-stitch) sequence, with real blank leaves inserted for the `-1` padding slots so the
    /// page count is a multiple of 4. Caller owns the returned handle.
    private static func makeBookletReorderedDocument(
        from source: OpaquePointer?,
        pageCount: Int,
        width: Double,
        height: Double
    ) throws -> OpaquePointer {
        let order = ImpositionService.bookletPageOrder(pageCount: pageCount)
        guard let reordered = imp_CreateNewDocument() else { throw PDFImpositionError.impositionFailed }
        var insertIndex: Int32 = 0
        for sourceIndex in order {
            if sourceIndex < 0 {
                // A blank leaf: create a real empty page so the folio grid stays aligned.
                guard let blank = imp_NewPage(reordered, insertIndex, width, height) else {
                    FPDF_CloseDocument(reordered)
                    throw PDFImpositionError.impositionFailed
                }
                poe_ClosePage(blank)
            } else {
                // FPDF_ImportPages page ranges are 1-indexed.
                let imported = "\(sourceIndex + 1)".withCString {
                    imp_ImportPages(reordered, source, $0, insertIndex)
                }
                guard imported != 0 else {
                    FPDF_CloseDocument(reordered)
                    throw PDFImpositionError.impositionFailed
                }
            }
            insertIndex += 1
        }
        return reordered
    }

    /// Page-0 size in points, reusing the already-bound `poe_*` page getters (no extra binding).
    private static func pageZeroSize(_ document: OpaquePointer?) throws -> (Double, Double) {
        guard let page = poe_LoadPage(document, 0) else { throw PDFImpositionError.impositionFailed }
        defer { poe_ClosePage(page) }
        let width = poe_GetPageWidth(page)
        let height = poe_GetPageHeight(page)
        guard width > 0, height > 0 else { throw PDFImpositionError.impositionFailed }
        return (width, height)
    }

    /// Serialises `document` via the reused `FPDF_SaveAsCopy` binding into a fresh byte buffer and
    /// gates it through qpdf's structural check. Full (non-incremental) save — the imposed document
    /// is brand new, so there is no base revision to increment against.
    private static func save(_ document: OpaquePointer?) throws -> Data {
        impositionSaveData = Data()
        var fileWrite = FPDFCompressionFileWrite(version: 1, writeBlock: { _, data, size in
            guard let data, size > 0 else { return 0 }
            impositionSaveData.append(data.assumingMemoryBound(to: UInt8.self), count: Int(size))
            return 1
        })
        defer { impositionSaveData.removeAll(keepingCapacity: false) }
        guard FPDFCompression_SaveAsCopy(document, &fileWrite, 0) != 0, !impositionSaveData.isEmpty else {
            throw PDFImpositionError.saveFailed
        }
        let output = impositionSaveData
        guard QPDFService.isStructurallySound(output) else { throw PDFImpositionError.saveFailed }
        return output
    }
}
