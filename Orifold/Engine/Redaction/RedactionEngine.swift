import CoreGraphics
import Foundation

// =============================================================================
// RedactionEngine — TRUE redaction: whatever lies under a region leaves the object graph.
//
//   1. PDFium edit — per page: refuse form-field widgets, snapshot the page as pixels with
//      every region painted black, then walk the top-level objects. Text and form XObjects
//      that touch a region are removed; the parts of them outside the region come back as an
//      image patch cut from that snapshot (PDFium can only delete whole text objects). Image
//      pixels under a region are zeroed; paths/shadings are removed only when wholly inside.
//      Intersecting annotations go too. A black box is burned in per region.
//   2. Verify — reload the saved bytes; any character box inside a region is a failure.
//
// No separate "orphan" pass: GenerateContent rewrites the page's /Resources with only what
// the new content uses (inherited /Pages resources included) and SaveAsCopy writes only
// reachable objects. RedactionEngineTests scans every stream in the output to hold that.
//
// Bindings use a `red_` prefix; each matches any other app-target binding of the same C
// symbol byte-for-byte (whole-module optimization merges them — release builds break
// otherwise). Everything else reuses the `poe_` set.
// =============================================================================

@_silgen_name("FPDF_RenderPageBitmap")
private func red_RenderPageBitmap(_ bitmap: OpaquePointer?, _ page: OpaquePointer?, _ startX: Int32,
                                  _ startY: Int32, _ sizeX: Int32, _ sizeY: Int32, _ rotate: Int32, _ flags: Int32)
@_silgen_name("FPDFBitmap_Create")
private func red_BitmapCreate(_ width: Int32, _ height: Int32, _ alpha: Int32) -> OpaquePointer?
@_silgen_name("FPDFBitmap_FillRect")
private func red_BitmapFillRect(_ bitmap: OpaquePointer?, _ left: Int32, _ top: Int32,
                                _ width: Int32, _ height: Int32, _ color: UInt) -> Int32
@_silgen_name("FPDFBitmap_GetFormat")
private func red_BitmapGetFormat(_ bitmap: OpaquePointer?) -> Int32
@_silgen_name("FPDFBitmap_GetWidth")
private func red_BitmapGetWidth(_ bitmap: OpaquePointer?) -> Int32
@_silgen_name("FPDFBitmap_GetHeight")
private func red_BitmapGetHeight(_ bitmap: OpaquePointer?) -> Int32
@_silgen_name("FPDF_GetPageBoundingBox")
private func red_GetPageBoundingBox(_ page: OpaquePointer?, _ rect: UnsafeMutablePointer<POEFSRect>?) -> Int32
@_silgen_name("FPDFPageObj_NewImageObj")
private func red_NewImageObj(_ document: OpaquePointer?) -> OpaquePointer?
@_silgen_name("FPDFImageObj_SetBitmap")
private func red_ImageSetBitmap(_ pages: UnsafeMutablePointer<OpaquePointer?>?, _ count: Int32,
                                _ imageObject: OpaquePointer?, _ bitmap: OpaquePointer?) -> Int32
@_silgen_name("FPDFPageObj_CreateNewRect")
private func red_CreateNewRect(_ x: Float, _ y: Float, _ width: Float, _ height: Float) -> OpaquePointer?
@_silgen_name("FPDFPath_SetDrawMode")
private func red_PathSetDrawMode(_ path: OpaquePointer?, _ fillMode: Int32, _ stroke: Int32) -> Int32
@_silgen_name("FPDFAnnot_GetSubtype")
private func red_AnnotGetSubtype(_ annotation: OpaquePointer?) -> Int32
@_silgen_name("FPDFAnnot_GetRect")
private func red_AnnotGetRect(_ annotation: OpaquePointer?, _ rect: UnsafeMutablePointer<POEFSRect>?) -> Int32
@_silgen_name("FPDFText_LoadPage")
private func red_TextLoadPage(_ page: OpaquePointer?) -> OpaquePointer?
@_silgen_name("FPDFText_ClosePage")
private func red_TextClosePage(_ textPage: OpaquePointer?)
@_silgen_name("FPDFText_CountChars")
private func red_TextCountChars(_ textPage: OpaquePointer?) -> Int32
@_silgen_name("FPDFText_GetCharBox")
private func red_TextGetCharBox(
    _ textPage: OpaquePointer?,
    _ index: Int32,
    _ left: UnsafeMutablePointer<Double>?,
    _ right: UnsafeMutablePointer<Double>?,
    _ bottom: UnsafeMutablePointer<Double>?,
    _ top: UnsafeMutablePointer<Double>?
) -> Int32

enum RedactionEngine {
    enum Failure: Error, Equatable {
        case unreadableDocument
        case formFieldInRegion(pageIndex: Int)
        case writeFailed
        case verificationFailed(pageIndex: Int)
    }

    private static let widgetSubtype: Int32 = 20        // FPDF_ANNOT_WIDGET
    private static let fillModeWinding: Int32 = 2       // FPDF_FILLMODE_WINDING
    private static let opaqueBlack: UInt = 0xFF00_0000
    private static let opaqueWhite: UInt = 0xFFFF_FFFF
    /// Patch resolution: 3× ≈ 216 dpi, capped so a poster-size page can't allocate gigabytes.
    private static let snapshotScale: CGFloat = 3
    private static let maxSnapshotSide: CGFloat = 6000

    /// Permanently removes everything under `regions` (member-local page index → rects in PDF
    /// user space, i.e. PDFKit page space). Throws rather than returning partially redacted
    /// bytes; the caller's transaction then leaves every lane untouched.
    static func redact(_ data: Data, regions: [Int: [CGRect]]) throws -> Data {
        let regions = regions
            .mapValues { $0.map(\.standardized).filter { !$0.isEmpty } }
            .filter { !$0.value.isEmpty }
        guard !regions.isEmpty else { return data }
        guard !data.isEmpty, data.count <= Int(Int32.max) else { throw Failure.unreadableDocument }

        return try withPDFium {
            let redacted = try applyRegions(regions, to: data)
            try verify(redacted, regions: regions)
            return redacted
        }
    }

    private static func withPDFium<T>(_ body: () throws -> T) rethrows -> T {
        pdfiumLock.lock()
        defer { pdfiumLock.unlock() }
        FPDF_InitLibrary()
        defer { FPDF_DestroyLibrary() }
        return try body()
    }

    // MARK: - Stage 1: PDFium edit

    private static func applyRegions(_ regions: [Int: [CGRect]], to data: Data) throws -> Data {
        try data.withUnsafeBytes { raw -> Data in
            guard let base = raw.baseAddress,
                  let document = FPDF_LoadMemDocument(base, Int32(data.count), nil) else {
                throw Failure.unreadableDocument
            }
            defer { FPDF_CloseDocument(document) }
            let pageCount = Int(FPDF_GetPageCount(document))
            for (pageIndex, rects) in regions.sorted(by: { $0.key < $1.key }) {
                guard pageIndex >= 0, pageIndex < pageCount,
                      let page = poe_LoadPage(document, Int32(pageIndex)) else {
                    throw Failure.unreadableDocument
                }
                defer { poe_ClosePage(page) }
                try redactPage(page, pageIndex: pageIndex, rects: rects, document: document)
            }
            let saved = PDFObjectEditEngine.saveAsCopy(document)
            guard !saved.isEmpty else { throw Failure.writeFailed }
            return saved
        }
    }

    private static func redactPage(_ page: OpaquePointer, pageIndex: Int, rects: [CGRect],
                                   document: OpaquePointer) throws {
        let doomedAnnotations = try intersectingAnnotations(on: page, pageIndex: pageIndex, rects: rects)
        let snapshot = try PageSnapshot(page: page, blackingOut: rects)
        defer { snapshot.destroy() }

        var patches: [OpaquePointer] = []
        for index in stride(from: poe_CountObjects(page) - 1, through: 0, by: -1) {
            guard let object = poe_GetObject(page, index),
                  let bounds = objectBounds(object),
                  rects.contains(where: { $0.intersects(bounds) }) else { continue }
            let whollyInside = rects.contains { $0.contains(bounds) }
            switch poe_GetType(object) {
            case POEObjType.path, POEObjType.shading:
                // Partly covered vector art stays (under the burned-in box): removing a page's
                // background fill would rasterize the whole page for nothing.
                if whollyInside { try remove(object, from: page) }
            case POEObjType.image where !whollyInside && blackOutPixels(of: object, under: rects):
                continue
            default:
                try remove(object, from: page)
                if !whollyInside { patches.append(try snapshot.patch(covering: bounds, in: document)) }
            }
        }
        for index in doomedAnnotations.reversed() where poe_RemoveAnnotation(page, index) == 0 {
            throw Failure.writeFailed
        }
        for patch in patches { try append(patch, to: page) }
        for rect in rects {
            guard let box = red_CreateNewRect(Float(rect.minX), Float(rect.minY),
                                              Float(rect.width), Float(rect.height)) else {
                throw Failure.writeFailed
            }
            _ = poe_SetFillColor(box, 0, 0, 0, 255)
            _ = red_PathSetDrawMode(box, fillModeWinding, 0)
            try append(box, to: page)
        }
        poeTouchPathColorsForGenerateContent(page)
        guard poe_GenerateContent(page) != 0 else { throw Failure.writeFailed }
    }

    /// Indices of annotations touching a region. A form-field widget refuses the whole
    /// redaction: its value lives in /AcroForm, outside the page, so removing the widget
    /// would still ship the secret.
    private static func intersectingAnnotations(on page: OpaquePointer, pageIndex: Int,
                                                rects: [CGRect]) throws -> [Int32] {
        var doomed: [Int32] = []
        for index in 0..<max(0, poe_GetAnnotationCount(page)) {
            guard let annotation = poe_GetAnnotation(page, index) else { continue }
            defer { poe_CloseAnnotation(annotation) }
            var raw = POEFSRect(left: 0, bottom: 0, right: 0, top: 0)
            guard red_AnnotGetRect(annotation, &raw) != 0 else { continue }
            let bounds = normalized(raw)
            guard rects.contains(where: { $0.intersects(bounds) }) else { continue }
            if red_AnnotGetSubtype(annotation) == widgetSubtype {
                throw Failure.formFieldInRegion(pageIndex: pageIndex)
            }
            doomed.append(index)
        }
        return doomed
    }

    /// Zeroes the image's own pixels under each region (mapped through the inverse image
    /// matrix; the pixel-space bounding box errs toward more black). False means "couldn't",
    /// and the caller falls back to remove + patch — never to leaving the pixels.
    private static func blackOutPixels(of image: OpaquePointer, under rects: [CGRect]) -> Bool {
        var matrix = POEFSMatrix()
        guard poe_GetMatrix(image, &matrix) != 0 else { return false }
        let (a, b, c, d) = (Double(matrix.a), Double(matrix.b), Double(matrix.c), Double(matrix.d))
        let (e, f) = (Double(matrix.e), Double(matrix.f))
        let determinant = a * d - b * c
        guard abs(determinant) > 1e-9, let bitmap = poe_ImageGetBitmap(image) else { return false }
        defer { poe_BitmapDestroy(bitmap) }

        let bytesPerPixel: Int
        switch red_BitmapGetFormat(bitmap) {
        case 1: bytesPerPixel = 1           // Gray
        case 2: bytesPerPixel = 3           // BGR
        case 3, 4, 5: bytesPerPixel = 4     // BGRx / BGRA / BGRA premultiplied
        default: return false
        }
        let width = Int(red_BitmapGetWidth(bitmap)), height = Int(red_BitmapGetHeight(bitmap))
        let stride = Int(poe_BitmapGetStride(bitmap))
        guard width > 0, height > 0, let buffer = poe_BitmapGetBuffer(bitmap) else { return false }
        let pixels = buffer.assumingMemoryBound(to: UInt8.self)

        for rect in rects {
            let corners = [(rect.minX, rect.minY), (rect.maxX, rect.minY),
                           (rect.minX, rect.maxY), (rect.maxX, rect.maxY)].map { x, y -> (Double, Double) in
                let dx = Double(x) - e, dy = Double(y) - f
                let u = (d * dx - c * dy) / determinant
                let v = (-b * dx + a * dy) / determinant
                return (u * Double(width), (1 - v) * Double(height))
            }
            let columns = corners.map(\.0), rows = corners.map(\.1)
            let col0 = max(0, Int(columns.min()!.rounded(.down))), col1 = min(width, Int(columns.max()!.rounded(.up)))
            let row0 = max(0, Int(rows.min()!.rounded(.down))), row1 = min(height, Int(rows.max()!.rounded(.up)))
            guard col0 < col1, row0 < row1 else { continue }
            for row in row0..<row1 {
                let line = pixels + row * stride
                for column in col0..<col1 {
                    let pixel = line + column * bytesPerPixel
                    for channel in 0..<min(bytesPerPixel, 3) { pixel[channel] = 0 }
                    if bytesPerPixel == 4 { pixel[3] = 255 }
                }
            }
        }
        return red_ImageSetBitmap(nil, 0, image, bitmap) != 0
    }

    private static func remove(_ object: OpaquePointer, from page: OpaquePointer) throws {
        guard poe_RemoveObject(page, object) != 0 else { throw Failure.writeFailed }
        poe_Destroy(object)
    }

    private static func append(_ object: OpaquePointer, to page: OpaquePointer) throws {
        guard poe_InsertObjectAtIndex(page, object, Int(poe_CountObjects(page))) != 0 else {
            poe_Destroy(object)
            throw Failure.writeFailed
        }
    }

    private static func objectBounds(_ object: OpaquePointer) -> CGRect? {
        var left: Float = 0, bottom: Float = 0, right: Float = 0, top: Float = 0
        guard poe_GetBounds(object, &left, &bottom, &right, &top) != 0 else { return nil }
        return CGRect(x: CGFloat(left), y: CGFloat(bottom),
                      width: CGFloat(right - left), height: CGFloat(top - bottom)).standardized
    }

    /// FS_RECTF's vertical fields are "top"/"bottom" by convention only; normalize either way.
    private static func normalized(_ rect: POEFSRect) -> CGRect {
        CGRect(x: CGFloat(min(rect.left, rect.right)), y: CGFloat(min(rect.bottom, rect.top)),
               width: CGFloat(abs(rect.right - rect.left)), height: CGFloat(abs(rect.top - rect.bottom)))
    }

    /// The page rendered (no annotations, rotation neutralized) with every region painted
    /// black — the only source patches are cut from, so a patch can never carry redacted ink.
    private struct PageSnapshot {
        let bitmap: OpaquePointer
        let box: CGRect
        let scale: CGFloat
        let pixelWidth: Int32
        let pixelHeight: Int32

        init(page: OpaquePointer, blackingOut rects: [CGRect]) throws {
            var raw = POEFSRect(left: 0, bottom: 0, right: 0, top: 0)
            guard red_GetPageBoundingBox(page, &raw) != 0 else { throw Failure.unreadableDocument }
            box = RedactionEngine.normalized(raw)
            guard box.width > 0, box.height > 0 else { throw Failure.unreadableDocument }
            scale = min(snapshotScale, maxSnapshotSide / max(box.width, box.height))
            pixelWidth = Int32((box.width * scale).rounded(.up))
            pixelHeight = Int32((box.height * scale).rounded(.up))
            guard let bitmap = red_BitmapCreate(pixelWidth, pixelHeight, 0) else { throw Failure.writeFailed }
            self.bitmap = bitmap
            _ = red_BitmapFillRect(bitmap, 0, 0, pixelWidth, pixelHeight, opaqueWhite)
            let rotation = poe_GetPageRotation(page)
            if rotation != 0 { poe_SetPageRotation(page, 0) }
            red_RenderPageBitmap(bitmap, page, 0, 0, pixelWidth, pixelHeight, 0, 0)
            if rotation != 0 { poe_SetPageRotation(page, rotation) }
            for rect in rects {
                let pixels = pixelRect(for: rect)
                guard pixels.width > 0, pixels.height > 0 else { continue }
                _ = red_BitmapFillRect(bitmap, pixels.x, pixels.y, pixels.width, pixels.height, opaqueBlack)
            }
        }

        func destroy() { poe_BitmapDestroy(bitmap) }

        /// User-space rect → clamped pixel rect, rounded outward.
        func pixelRect(for rect: CGRect) -> (x: Int32, y: Int32, width: Int32, height: Int32) {
            let x0 = max(0, Int32(((rect.minX - box.minX) * scale).rounded(.down)))
            let x1 = min(pixelWidth, Int32(((rect.maxX - box.minX) * scale).rounded(.up)))
            let y0 = max(0, Int32(((box.maxY - rect.maxY) * scale).rounded(.down)))
            let y1 = min(pixelHeight, Int32(((box.maxY - rect.minY) * scale).rounded(.up)))
            return (x0, y0, max(0, x1 - x0), max(0, y1 - y0))
        }

        /// A new image object showing this snapshot's pixels over `bounds`.
        func patch(covering bounds: CGRect, in document: OpaquePointer) throws -> OpaquePointer {
            let pixels = pixelRect(for: bounds)
            guard pixels.width > 0, pixels.height > 0,
                  let crop = red_BitmapCreate(pixels.width, pixels.height, 0) else { throw Failure.writeFailed }
            defer { poe_BitmapDestroy(crop) }
            guard let source = poe_BitmapGetBuffer(bitmap), let target = poe_BitmapGetBuffer(crop) else {
                throw Failure.writeFailed
            }
            let sourceStride = Int(poe_BitmapGetStride(bitmap)), targetStride = Int(poe_BitmapGetStride(crop))
            let rowBytes = Int(pixels.width) * 4
            for row in 0..<Int(pixels.height) {
                let from = source + (Int(pixels.y) + row) * sourceStride + Int(pixels.x) * 4
                (target + row * targetStride).copyMemory(from: from, byteCount: rowBytes)
            }
            guard let image = red_NewImageObj(document) else { throw Failure.writeFailed }
            guard red_ImageSetBitmap(nil, 0, image, crop) != 0 else {
                poe_Destroy(image)
                throw Failure.writeFailed
            }
            var matrix = POEFSMatrix(
                a: Float(CGFloat(pixels.width) / scale), b: 0, c: 0,
                d: Float(CGFloat(pixels.height) / scale),
                e: Float(box.minX + CGFloat(pixels.x) / scale),
                f: Float(box.maxY - CGFloat(pixels.y + pixels.height) / scale)
            )
            guard poe_SetMatrix(image, &matrix) != 0 else {
                poe_Destroy(image)
                throw Failure.writeFailed
            }
            return image
        }
    }

    // MARK: - Stage 2: verify

    /// The final bytes, reloaded: no character may sit inside a region. The 0.5pt inset
    /// absorbs rounding where a surviving glyph merely abuts a region's edge.
    private static func verify(_ data: Data, regions: [Int: [CGRect]]) throws {
        try data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress,
                  let document = FPDF_LoadMemDocument(base, Int32(data.count), nil) else {
                throw Failure.unreadableDocument
            }
            defer { FPDF_CloseDocument(document) }
            for (pageIndex, rects) in regions {
                guard let page = poe_LoadPage(document, Int32(pageIndex)) else {
                    throw Failure.verificationFailed(pageIndex: pageIndex)
                }
                defer { poe_ClosePage(page) }
                guard let textPage = red_TextLoadPage(page) else {
                    throw Failure.verificationFailed(pageIndex: pageIndex)
                }
                defer { red_TextClosePage(textPage) }
                let probes = rects.map { $0.insetBy(dx: 0.5, dy: 0.5) }
                for index in 0..<max(0, red_TextCountChars(textPage)) {
                    var left = 0.0, right = 0.0, bottom = 0.0, top = 0.0
                    guard red_TextGetCharBox(textPage, index, &left, &right, &bottom, &top) != 0 else { continue }
                    let glyph = CGRect(x: left, y: bottom, width: right - left, height: top - bottom)
                    if probes.contains(where: { $0.intersects(glyph) }) {
                        throw Failure.verificationFailed(pageIndex: pageIndex)
                    }
                }
            }
        }
    }
}
