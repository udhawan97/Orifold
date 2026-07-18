import Foundation

/// Finalizes replay bookkeeping with PDFium so mixed edit output ends on `SaveAsCopy` bytes.
/// Existing bake stamps are removed from every page after live annotations are grafted, then
/// exact current stamps and rotations are applied in one final preserving write.
enum PDFReplayMetadataEngine {
    // The stamp convention — key spelling, annotation subtype, off-page rect — is defined
    // once in `BakeStamp` and read here, so this PDFium writer and the PDFKit reader that
    // detects its output can never disagree about what a stamp looks like.
    private static let bakeStampKey = BakeStamp.pdfiumAnnotationKey
    private static let freeTextAnnotationSubtype = BakeStamp.pdfiumFreeTextSubtype

    static func finalize(
        memberData: Data,
        rotations: [Int: Int],
        bakeStamps: [Int: String]
    ) -> Data? {
        guard !memberData.isEmpty, memberData.count <= Int(Int32.max) else { return nil }

        pdfiumLock.lock()
        defer { pdfiumLock.unlock() }
        FPDF_InitLibrary()
        defer { FPDF_DestroyLibrary() }

        return memberData.withUnsafeBytes { raw -> Data? in
            guard let base = raw.baseAddress,
                  let document = FPDF_LoadMemDocument(base, Int32(memberData.count), nil) else { return nil }
            defer { FPDF_CloseDocument(document) }
            let pageCount = Int(FPDF_GetPageCount(document))

            for pageIndex in 0..<pageCount {
                guard let page = poe_LoadPage(document, Int32(pageIndex)) else { return nil }

                if let rotation = rotations[pageIndex] {
                    let quarterTurns = ((rotation / 90) % 4 + 4) % 4
                    poe_SetPageRotation(page, Int32(quarterTurns))
                }
                removeBakeStamps(from: page)
                if let hash = bakeStamps[pageIndex], !attachBakeStamp(hash, to: page) {
                    poe_ClosePage(page)
                    return nil
                }
                poe_ClosePage(page)
            }

            let saved = PDFObjectEditEngine.saveAsCopy(document)
            return saved.isEmpty ? nil : saved
        }
    }

    private static func removeBakeStamps(from page: OpaquePointer?) {
        bakeStampKey.withCString { key in
            var index = poe_GetAnnotationCount(page) - 1
            while index >= 0 {
                if let annotation = poe_GetAnnotation(page, index) {
                    let isStamp = poe_AnnotationHasKey(annotation, key) != 0
                    poe_CloseAnnotation(annotation)
                    if isStamp { _ = poe_RemoveAnnotation(page, index) }
                }
                index -= 1
            }
        }
    }

    private static func attachBakeStamp(_ hash: String, to page: OpaquePointer?) -> Bool {
        guard let annotation = poe_CreateAnnotation(page, freeTextAnnotationSubtype) else { return false }
        defer { poe_CloseAnnotation(annotation) }
        var rect = POEFSRect(
            left: Float(BakeStamp.bounds.minX),
            bottom: Float(BakeStamp.bounds.minY),
            right: Float(BakeStamp.bounds.maxX),
            top: Float(BakeStamp.bounds.maxY)
        )
        guard poe_SetAnnotationRect(annotation, &rect) != 0 else { return false }
        let utf16 = Array(hash.utf16) + [0]
        return bakeStampKey.withCString { key in
            utf16.withUnsafeBufferPointer { buffer in
                poe_SetAnnotationString(annotation, key, buffer.baseAddress) != 0
            }
        }
    }
}
