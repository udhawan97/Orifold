import AppKit
import CoreGraphics
import XCTest
@testable import Orifold

// =============================================================================
// PHASE 0 — Architecture gate for the Object Editing System (docs/OBJECT_EDITING_PLAN.md §16).
//
// Proves, on REAL bytes, that the PDFium structural chain
//     enumerate → mutate (SetMatrix / RemoveObject) → GenerateContent → SaveAsCopy → reopen
// round-trips move/delete WITHOUT perturbing untouched text/vectors, and that object identity
// survives (AddMark + translation-invariant structuralDigest).
//
// ── LOAD-BEARING FINDING (why this test is permanent, not throwaway) ─────────────────────────
// FPDFPage_GenerateContent DROPS the fill/stroke color of PARSED path objects — they re-emit as
// black. This corrupts any page with colored fills/backgrounds (incl. Orifold's own CGContext-
// generated pages). MITIGATION, proven here and MANDATORY in the production PDFObjectEditEngine:
// before GenerateContent, "touch" every path object's color (GetFillColor→SetFillColor, and the
// stroke pair) so PDFium re-emits the color operators. `editAndSave(preserveColors:)` below is
// exactly what production must do; `testColorTouchIsNecessary` is the regression guard.
//
// These @_silgen_name decls are the exact symbols PDFObjectEditEngine will use (verified linked
// via `nm`). Library lifecycle symbols + `pdfiumLock` come from the Orifold module (@testable).
// =============================================================================

// MARK: - FS_MATRIX (fpdfview.h: 6 floats — matches PDFTextTransform)
private struct P0Matrix { var a: Float; var b: Float; var c: Float; var d: Float; var e: Float; var f: Float }

// MARK: - PDFium page-object symbols
@_silgen_name("FPDF_LoadPage") private func p0_LoadPage(_ d: OpaquePointer?, _ i: Int32) -> OpaquePointer?
@_silgen_name("FPDF_ClosePage") private func p0_ClosePage(_ p: OpaquePointer?)
@_silgen_name("FPDFPage_CountObjects") private func p0_CountObjects(_ p: OpaquePointer?) -> Int32
@_silgen_name("FPDFPage_GetObject") private func p0_GetObject(_ p: OpaquePointer?, _ i: Int32) -> OpaquePointer?
@_silgen_name("FPDFPageObj_GetType") private func p0_GetType(_ o: OpaquePointer?) -> Int32
@_silgen_name("FPDFPageObj_GetBounds") private func p0_GetBounds(_ o: OpaquePointer?, _ l: UnsafeMutablePointer<Float>?, _ b: UnsafeMutablePointer<Float>?, _ r: UnsafeMutablePointer<Float>?, _ t: UnsafeMutablePointer<Float>?) -> Int32
@_silgen_name("FPDFPageObj_GetMatrix") private func p0_GetMatrix(_ o: OpaquePointer?, _ m: UnsafeMutablePointer<P0Matrix>?) -> Int32
@_silgen_name("FPDFPageObj_SetMatrix") private func p0_SetMatrix(_ o: OpaquePointer?, _ m: UnsafePointer<P0Matrix>?) -> Int32
@_silgen_name("FPDFPage_RemoveObject") private func p0_RemoveObject(_ p: OpaquePointer?, _ o: OpaquePointer?) -> Int32
@_silgen_name("FPDFPageObj_Destroy") private func p0_Destroy(_ o: OpaquePointer?)
@_silgen_name("FPDFPageObj_AddMark") private func p0_AddMark(_ o: OpaquePointer?, _ n: UnsafePointer<CChar>?) -> OpaquePointer?
@_silgen_name("FPDFPageObj_CountMarks") private func p0_CountMarks(_ o: OpaquePointer?) -> Int32
@_silgen_name("FPDFPageObj_GetMark") private func p0_GetMark(_ o: OpaquePointer?, _ i: UInt) -> OpaquePointer?
@_silgen_name("FPDFPageObjMark_GetName") private func p0_MarkGetName(_ m: OpaquePointer?, _ buf: UnsafeMutablePointer<UInt16>?, _ len: UInt, _ out: UnsafeMutablePointer<UInt>?) -> Int32
@_silgen_name("FPDFPageObj_GetFillColor") private func p0_GetFillColor(_ o: OpaquePointer?, _ r: UnsafeMutablePointer<UInt32>?, _ g: UnsafeMutablePointer<UInt32>?, _ b: UnsafeMutablePointer<UInt32>?, _ a: UnsafeMutablePointer<UInt32>?) -> Int32
@_silgen_name("FPDFPageObj_SetFillColor") private func p0_SetFillColor(_ o: OpaquePointer?, _ r: UInt32, _ g: UInt32, _ b: UInt32, _ a: UInt32) -> Int32
@_silgen_name("FPDFPageObj_GetStrokeColor") private func p0_GetStrokeColor(_ o: OpaquePointer?, _ r: UnsafeMutablePointer<UInt32>?, _ g: UnsafeMutablePointer<UInt32>?, _ b: UnsafeMutablePointer<UInt32>?, _ a: UnsafeMutablePointer<UInt32>?) -> Int32
@_silgen_name("FPDFPageObj_SetStrokeColor") private func p0_SetStrokeColor(_ o: OpaquePointer?, _ r: UInt32, _ g: UInt32, _ b: UInt32, _ a: UInt32) -> Int32
@_silgen_name("FPDFPage_GenerateContent") private func p0_GenerateContent(_ p: OpaquePointer?) -> Int32

// PDFium's own text extractor — used instead of PDFKit's `.attributedString` because PDFKit text
// extraction is unreliable on CI's pinned Xcode 16.4 SDK (see memory: ci-xcode164-pdfkit-string-
// extraction-quirk). Same symbols PDFTextAnalysisEngine.swift uses in production.
@_silgen_name("FPDFText_LoadPage") private func p0_TextLoadPage(_ p: OpaquePointer?) -> OpaquePointer?
@_silgen_name("FPDFText_ClosePage") private func p0_TextClosePage(_ tp: OpaquePointer?)
@_silgen_name("FPDFText_CountChars") private func p0_TextCountChars(_ tp: OpaquePointer?) -> Int32
@_silgen_name("FPDFText_GetUnicode") private func p0_TextGetUnicode(_ tp: OpaquePointer?, _ i: Int32) -> UInt32

// PDFium's own rasterizer — authoritative render of the produced bytes (PDFKit renders SaveAsCopy
// output unreliably in a headless test process).
@_silgen_name("FPDF_RenderPageBitmap") private func p0_RenderPageBitmap(_ bmp: OpaquePointer?, _ p: OpaquePointer?, _ sx: Int32, _ sy: Int32, _ w: Int32, _ h: Int32, _ rot: Int32, _ flags: Int32)
@_silgen_name("FPDFBitmap_Create") private func p0_BitmapCreate(_ w: Int32, _ h: Int32, _ alpha: Int32) -> OpaquePointer?
@_silgen_name("FPDFBitmap_FillRect") private func p0_BitmapFillRect(_ bmp: OpaquePointer?, _ l: Int32, _ t: Int32, _ w: Int32, _ h: Int32, _ color: UInt) -> Int32
@_silgen_name("FPDFBitmap_GetBuffer") private func p0_BitmapGetBuffer(_ bmp: OpaquePointer?) -> UnsafeMutableRawPointer?
@_silgen_name("FPDFBitmap_GetStride") private func p0_BitmapGetStride(_ bmp: OpaquePointer?) -> Int32
@_silgen_name("FPDFBitmap_Destroy") private func p0_BitmapDestroy(_ bmp: OpaquePointer?)

// MARK: - FPDF_SaveAsCopy plumbing (mirrors PDFCompressionService.swift:77-95)
private struct P0FileWrite {
    var version: Int32
    var writeBlock: (@convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?, CUnsignedLong) -> Int32)?
}
// flags is FPDF_DWORD = `unsigned long` (8 bytes on 64-bit) — bind as UInt, not UInt32, for ABI correctness.
@_silgen_name("FPDF_SaveAsCopy") private func p0_SaveAsCopy(_ d: OpaquePointer?, _ fw: UnsafeMutablePointer<P0FileWrite>?, _ flags: UInt) -> Int32
private var p0SaveBuffer = Data()   // guarded by pdfiumLock in the test body; not reentrant

private let fpdfPageObjTypeText: Int32 = 1
private let fpdfPageObjTypePath: Int32 = 2
private let fpdfPageObjTypeImage: Int32 = 3

final class Phase0PDFiumRoundTripSpikeTests: XCTestCase {

    private struct P0Object { let handle: OpaquePointer?; let index: Int32; let type: Int32; let bounds: CGRect }

    // MARK: - Raw-surface helpers

    private func enumerate(_ page: OpaquePointer?) -> [P0Object] {
        (0..<p0_CountObjects(page)).compactMap { i in
            guard let obj = p0_GetObject(page, i) else { return nil }
            var l: Float = 0, b: Float = 0, r: Float = 0, t: Float = 0
            _ = p0_GetBounds(obj, &l, &b, &r, &t)
            return P0Object(handle: obj, index: i, type: p0_GetType(obj),
                            bounds: CGRect(x: CGFloat(min(l, r)), y: CGFloat(min(b, t)),
                                           width: CGFloat(abs(r - l)), height: CGFloat(abs(t - b))))
        }
    }

    private func withDocument<T>(_ data: Data, _ body: (OpaquePointer) -> T) -> T? {
        data.withUnsafeBytes { raw -> T? in
            guard let base = raw.baseAddress, data.count <= Int(Int32.max),
                  let doc = FPDF_LoadMemDocument(base, Int32(data.count), nil) else { return nil }
            defer { FPDF_CloseDocument(doc) }
            return body(doc)
        }
    }

    private func saveAsCopy(_ doc: OpaquePointer?) -> Data {
        p0SaveBuffer = Data()
        var fw = P0FileWrite(version: 1, writeBlock: { _, data, size in
            if let data, size > 0 { p0SaveBuffer.append(data.assumingMemoryBound(to: UInt8.self), count: Int(size)) }
            return 1
        })
        return p0_SaveAsCopy(doc, &fw, UInt(1 << 1)) != 0 ? p0SaveBuffer : Data()   // FPDF_NO_INCREMENTAL
    }

    /// THE production write-back recipe. Loads `original`, lets `mutate` edit the object list, then
    /// (when `preserveColors`) touches every path's fill+stroke color so GenerateContent re-emits
    /// them, then GenerateContent + SaveAsCopy. Returns the new member bytes.
    private func editAndSave(_ original: Data, preserveColors: Bool = true,
                             _ mutate: (_ page: OpaquePointer?, _ objects: [P0Object]) -> Void) -> Data {
        (withDocument(original) { doc -> Data in
            guard let page = p0_LoadPage(doc, 0) else { return Data() }
            defer { p0_ClosePage(page) }
            mutate(page, enumerate(page))
            if preserveColors {
                for o in enumerate(page) where o.type == fpdfPageObjTypePath {
                    var r: UInt32 = 0, g: UInt32 = 0, b: UInt32 = 0, a: UInt32 = 0
                    if p0_GetFillColor(o.handle, &r, &g, &b, &a) != 0 { _ = p0_SetFillColor(o.handle, r, g, b, a) }
                    var sr: UInt32 = 0, sg: UInt32 = 0, sb: UInt32 = 0, sa: UInt32 = 0
                    if p0_GetStrokeColor(o.handle, &sr, &sg, &sb, &sa) != 0 { _ = p0_SetStrokeColor(o.handle, sr, sg, sb, sa) }
                }
            }
            return p0_GenerateContent(page) != 0 ? saveAsCopy(doc) : Data()
        }) ?? Data()
    }

    private func markNames(_ obj: OpaquePointer?) -> [String] {
        (0..<p0_CountMarks(obj)).compactMap { i in
            guard let mark = p0_GetMark(obj, UInt(i)) else { return nil }
            var needed: UInt = 0
            _ = p0_MarkGetName(mark, nil, 0, &needed)   // bytes (UTF-16LE incl. NUL)
            guard needed > 0 else { return nil }
            var buffer = [UInt16](repeating: 0, count: Int(needed) / 2)
            var written: UInt = 0
            _ = p0_MarkGetName(mark, &buffer, needed, &written)
            return String(decoding: Array(buffer.prefix { $0 != 0 }), as: UTF16.self)
        }
    }

    /// FNV-1a over quantized values — stand-in for PDFObjectStableKey.structuralDigest.
    private func digest(_ values: [Double]) -> UInt64 {
        var h: UInt64 = 0xcbf29ce484222325
        for v in values {
            var q = Int64((v * 100).rounded()).magnitude   // 0.01 quantization, sign-folded
            for _ in 0..<8 { h = (h ^ (q & 0xff)) &* 0x100000001b3; q >>= 8 }
        }
        return h
    }
    /// Translation-invariant image digest: matrix scale/shear (a,b,c,d) + bounds SIZE only.
    private func imageDigest(_ obj: P0Object) -> UInt64 {
        var m = P0Matrix(a: 1, b: 0, c: 0, d: 1, e: 0, f: 0)
        _ = p0_GetMatrix(obj.handle, &m)
        return digest([Double(m.a), Double(m.b), Double(m.c), Double(m.d),
                       Double(obj.bounds.width), Double(obj.bounds.height)])
    }

    // MARK: - Fixture: text + a filled black rect (deletable) + a blue rect (untouched) + an image

    private let canaryText = "PHASE0 CANARY TEXT"
    private let rectPDF = CGRect(x: 120, y: 120, width: 160, height: 70)
    private let imagePDF = CGRect(x: 380, y: 560, width: 60, height: 60)
    private let bluePDF = CGRect(x: 300, y: 380, width: 90, height: 50)

    private func makeFixture() -> Data {
        let data = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        let ctx = CGContext(consumer: CGDataConsumer(data: data as CFMutableData)!, mediaBox: &mediaBox, nil)!
        ctx.beginPDFPage(nil)
        ctx.setFillColor(NSColor.white.cgColor); ctx.fill(mediaBox)
        ctx.setFillColor(CGColor(red: 0.1, green: 0.2, blue: 0.9, alpha: 1)); ctx.fill(bluePDF)
        ctx.setFillColor(NSColor.black.cgColor); ctx.fill(rectPDF)
        ctx.draw(makeSolidImage(24, 24, .systemRed), in: imagePDF)
        let font = CTFontCreateWithName("Helvetica" as CFString, 18, nil)
        ctx.textPosition = CGPoint(x: 72, y: 700)
        CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(
            string: canaryText, attributes: [.font: font, .foregroundColor: NSColor.black.cgColor])), ctx)
        ctx.endPDFPage(); ctx.closePDF()
        return data as Data
    }

    private func makeSolidImage(_ w: Int, _ h: Int, _ color: NSColor) -> CGImage {
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(color.cgColor); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()!
    }

    /// RGB under PDF point `p` (y-up), rendered by PDFium at 1pt=1px. Library must be init'd.
    private func sampleColor(_ data: Data, at p: CGPoint) -> (r: Int, g: Int, b: Int)? {
        (withDocument(data) { doc -> (Int, Int, Int)? in
            guard let page = p0_LoadPage(doc, 0) else { return nil }
            defer { p0_ClosePage(page) }
            let w: Int32 = 612, h: Int32 = 792
            guard let bmp = p0_BitmapCreate(w, h, 0) else { return nil }   // BGRx
            defer { p0_BitmapDestroy(bmp) }
            _ = p0_BitmapFillRect(bmp, 0, 0, w, h, 0xFFFF_FFFF)             // white paper
            p0_RenderPageBitmap(bmp, page, 0, 0, w, h, 0, 0)
            guard let buf = p0_BitmapGetBuffer(bmp) else { return nil }
            let stride = Int(p0_BitmapGetStride(bmp)), ptr = buf.assumingMemoryBound(to: UInt8.self)
            let px = Int(p.x), py = Int(CGFloat(h) - p.y)                   // device top-left, y-down
            guard px >= 1, py >= 1, px < Int(w) - 1, py < Int(h) - 1 else { return nil }
            var rs = 0, gs = 0, bs = 0                                      // BGRx
            for oy in -1...1 { for ox in -1...1 {
                let off = (py + oy) * stride + (px + ox) * 4
                bs += Int(ptr[off]); gs += Int(ptr[off + 1]); rs += Int(ptr[off + 2])
            } }
            return (rs / 9, gs / 9, bs / 9)
        }) ?? nil
    }

    private func extractedText(_ data: Data) -> String {
        (withDocument(data) { doc -> String in
            guard let page = p0_LoadPage(doc, 0) else { return "" }
            defer { p0_ClosePage(page) }
            guard let textPage = p0_TextLoadPage(page) else { return "" }
            defer { p0_TextClosePage(textPage) }
            let count = p0_TextCountChars(textPage)
            guard count > 0 else { return "" }
            var result = ""
            for i in 0..<count {
                if let s = UnicodeScalar(p0_TextGetUnicode(textPage, i)), s.value != 0 {
                    result.unicodeScalars.append(s)
                }
            }
            return result
        }) ?? ""
    }

    private func isWhite(_ c: (r: Int, g: Int, b: Int)?) -> Bool { guard let c else { return false }; return c.r > 230 && c.g > 230 && c.b > 230 }
    private func isBlackish(_ c: (r: Int, g: Int, b: Int)?) -> Bool { guard let c else { return false }; return c.r + c.g + c.b < 120 }
    private func isBlue(_ c: (r: Int, g: Int, b: Int)?) -> Bool { guard let c else { return false }; return c.b > 170 && c.r < 130 && c.g < 170 }

    private func rectApprox(_ a: CGRect, _ b: CGRect, tol: CGFloat = 3) -> Bool {
        abs(a.minX - b.minX) <= tol && abs(a.minY - b.minY) <= tol && abs(a.width - b.width) <= tol && abs(a.height - b.height) <= tol
    }

    // MARK: - THE GATE

    func testPhase0StructuralRoundTripGate() throws {
        pdfiumLock.lock(); FPDF_InitLibrary()
        defer { FPDF_DestroyLibrary(); pdfiumLock.unlock() }

        let original = makeFixture()
        XCTAssertFalse(original.isEmpty, "fixture build failed")
        XCTAssertTrue(extractedText(original).contains("CANARY"), "fixture must contain extractable text")
        XCTAssertTrue(isBlackish(sampleColor(original, at: CGPoint(x: rectPDF.midX, y: rectPDF.midY))), "rect must render black pre-edit")
        XCTAssertTrue(isBlue(sampleColor(original, at: CGPoint(x: bluePDF.midX, y: bluePDF.midY))), "blue rect must render blue pre-edit")

        // Baseline enumeration.
        let base = try XCTUnwrap(withDocument(original) { doc -> (count: Int32, imageBounds: CGRect, rectThere: Bool, imageDigest: UInt64)? in
            guard let page = p0_LoadPage(doc, 0) else { return nil }
            defer { p0_ClosePage(page) }
            let objs = enumerate(page)
            guard let img = objs.first(where: { $0.type == fpdfPageObjTypeImage }) else { return nil }
            let rect = objs.contains { $0.type == fpdfPageObjTypePath && rectApprox($0.bounds, rectPDF) }
            return (Int32(objs.count), img.bounds, rect, imageDigest(img))
        } ?? nil, "baseline enumeration failed")
        XCTAssertGreaterThan(base.count, 0)
        XCTAssertTrue(base.rectThere, "deletable rect PATH not detected")
        print("PHASE0 baseline: count=\(base.count) imageBounds=\(base.imageBounds)")

        let blueCenter = CGPoint(x: bluePDF.midX, y: bluePDF.midY)
        let controlPoint = CGPoint(x: 300, y: 300)   // blank area
        let rectCenter = CGPoint(x: rectPDF.midX, y: rectPDF.midY)

        // ── (1) TRANSLATE the image (+ AddMark) via the production write-back recipe ──
        let dx: CGFloat = 90, dy: CGFloat = -40
        let addMarkName = "OrifoldObjID"
        let movedData = editAndSave(original) { _, objs in
            guard let image = objs.first(where: { $0.type == fpdfPageObjTypeImage })?.handle else { return }
            var m = P0Matrix(a: 1, b: 0, c: 0, d: 1, e: 0, f: 0); _ = p0_GetMatrix(image, &m)
            m.e += Float(dx); m.f += Float(dy)
            XCTAssertNotEqual(p0_SetMatrix(image, &m), 0, "SetMatrix failed")
            addMarkName.withCString { _ = p0_AddMark(image, $0) }
        }
        XCTAssertFalse(movedData.isEmpty, "translate produced no bytes")

        let moved = try XCTUnwrap(withDocument(movedData) { doc -> (count: Int32, imageBounds: CGRect, digest: UInt64, marks: [String])? in
            guard let page = p0_LoadPage(doc, 0) else { return nil }
            defer { p0_ClosePage(page) }
            let objs = enumerate(page)
            guard let img = objs.first(where: { $0.type == fpdfPageObjTypeImage }) else { return nil }
            return (Int32(objs.count), img.bounds, imageDigest(img), markNames(img.handle))
        } ?? nil, "reopen after translate failed")

        XCTAssertEqual(moved.count, base.count, "R0: object count changed across GenerateContent round-trip")
        XCTAssertEqual(moved.imageBounds.minX - base.imageBounds.minX, dx, accuracy: 1.5, "image X translate wrong")
        XCTAssertEqual(moved.imageBounds.minY - base.imageBounds.minY, dy, accuracy: 1.5, "image Y translate wrong")
        XCTAssertTrue(extractedText(movedData).contains("CANARY"), "R2: text layer dropped by round-trip")
        XCTAssertEqual(moved.digest, base.imageDigest, "R4: translation-invariant structuralDigest changed")
        XCTAssertTrue(isBlue(sampleColor(movedData, at: blueCenter)), "untouched blue rect must stay blue (color-preservation)")
        XCTAssertTrue(isWhite(sampleColor(movedData, at: controlPoint)), "background must stay white (color-preservation)")
        let addMarkSurvives = moved.marks.contains(addMarkName)
        print("PHASE0 translate: count=\(moved.count) newImageBounds=\(moved.imageBounds) digestMatch=\(moved.digest == base.imageDigest) marks=\(moved.marks)")

        // ── (2) DELETE the filled rect via RemoveObject+Destroy, same recipe ──
        let deletedData = editAndSave(original) { page, objs in
            guard let rect = objs.first(where: { $0.type == fpdfPageObjTypePath && rectApprox($0.bounds, rectPDF) })?.handle else { return }
            XCTAssertNotEqual(p0_RemoveObject(page, rect), 0, "RemoveObject failed")
            p0_Destroy(rect)   // ownership transferred by RemoveObject
        }
        XCTAssertFalse(deletedData.isEmpty, "delete produced no bytes")

        let del = try XCTUnwrap(withDocument(deletedData) { doc -> (count: Int32, rectThere: Bool)? in
            guard let page = p0_LoadPage(doc, 0) else { return nil }
            defer { p0_ClosePage(page) }
            let objs = enumerate(page)
            return (Int32(objs.count), objs.contains { $0.type == fpdfPageObjTypePath && rectApprox($0.bounds, rectPDF) })
        } ?? nil, "reopen after delete failed")

        XCTAssertEqual(del.count, base.count - 1, "R1: object count did not decrement by exactly 1 after delete")
        XCTAssertFalse(del.rectThere, "R1: deleted rect still present in the object graph (ghost)")
        XCTAssertTrue(isWhite(sampleColor(deletedData, at: rectCenter)), "R1: deleted rect region still has ink (visual ghost)")
        XCTAssertTrue(isBlue(sampleColor(deletedData, at: blueCenter)), "delete must not disturb the sibling blue rect")
        XCTAssertTrue(extractedText(deletedData).contains("CANARY"), "R2: text dropped after delete round-trip")
        print("PHASE0 delete: count=\(del.count) (was \(base.count)) rectThere=\(del.rectThere)")

        print("""
        =====================================================================
        PHASE 0 GATE: PASSED — PDFium structural editing validated on real bytes.
          R0  GenerateContent count-stable ............... OK
          R1  structural delete (no ghost, region blank) . OK
          R2  text layer survives whole-stream rebuild ... OK
          R4  structuralDigest translation-invariant ..... OK
          R4b AddMark survives round-trip ................ \(addMarkSurvives ? "OK (identity fast-path available)" : "NO (use structuralDigest identity)")
          COLOR-PRESERVATION mitigation (mandatory) ...... OK
        =====================================================================
        """)
    }

    /// Regression guard: proves the color-touch mitigation in `editAndSave(preserveColors:)` is
    /// NECESSARY — without it, GenerateContent re-emits parsed path fills as BLACK.
    func testColorTouchIsNecessary() throws {
        pdfiumLock.lock(); FPDF_InitLibrary()
        defer { FPDF_DestroyLibrary(); pdfiumLock.unlock() }
        let original = makeFixture()
        let blueCenter = CGPoint(x: bluePDF.midX, y: bluePDF.midY)

        // Same translate, but WITHOUT the color-touch pass.
        let unmitigated = editAndSave(original, preserveColors: false) { _, objs in
            guard let image = objs.first(where: { $0.type == fpdfPageObjTypeImage })?.handle else { return }
            var m = P0Matrix(a: 1, b: 0, c: 0, d: 1, e: 0, f: 0); _ = p0_GetMatrix(image, &m)
            m.e += 5; _ = p0_SetMatrix(image, &m)
        }
        XCTAssertFalse(unmitigated.isEmpty)
        XCTAssertTrue(isBlackish(sampleColor(unmitigated, at: blueCenter)),
                      "Expected the KNOWN GenerateContent color-loss (blue→black) without the mitigation. " +
                      "If this now stays blue, PDFium fixed the bug and editAndSave's color-touch may be simplified.")

        // And WITH the mitigation the same edit preserves the color.
        let mitigated = editAndSave(original) { _, objs in
            guard let image = objs.first(where: { $0.type == fpdfPageObjTypeImage })?.handle else { return }
            var m = P0Matrix(a: 1, b: 0, c: 0, d: 1, e: 0, f: 0); _ = p0_GetMatrix(image, &m)
            m.e += 5; _ = p0_SetMatrix(image, &m)
        }
        XCTAssertTrue(isBlue(sampleColor(mitigated, at: blueCenter)), "color-touch mitigation must preserve the blue fill")
    }
}
