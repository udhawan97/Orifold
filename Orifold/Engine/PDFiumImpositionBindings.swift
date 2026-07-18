import Foundation

// =============================================================================
// PDFium page-imposition C bindings (fpdf_ppo.h + fpdf_edit.h) for booklet / N-up.
//
// Bound via @_silgen_name with an `imp_` (imposition) prefix so the Swift names never collide
// with the bindings already declared elsewhere (PDFiumProcessingEngine / PDFCompressionService /
// PDFiumObjectBindings / PDFTextAnalysisEngine). Multiple *external declarations* of the same C
// symbol are fine at link time ONLY when their Swift signatures are byte-identical; two bindings
// of one symbol with DIFFERENT Swift types are merged by whole-module optimization and break
// `swift build -c release` (the FPDF_SaveAsCopy-dup lesson, ff08f10). These three symbols are NOT
// bound anywhere else in the repo (verified via grep), so no duplicate-type hazard is introduced.
//
// The library lifecycle (FPDF_InitLibrary / LoadMemDocument / CloseDocument / GetPageCount),
// `pdfiumLock`, and the FPDF_SaveAsCopy save idiom (FPDFCompression_SaveAsCopy +
// FPDFCompressionFileWrite) live elsewhere and are REUSED, not re-declared. Page-size reads reuse
// the `poe_` page getters in PDFiumObjectBindings.swift.
//
// Ownership note (fpdf_ppo.h): FPDF_ImportNPagesToOne and FPDF_CreateNewDocument each return a NEW
// FPDF_DOCUMENT the caller owns and must FPDF_CloseDocument. `pagerange` in FPDF_ImportPages is
// 1-indexed ("1,3,5-7"); `index` (insert position) is 0-indexed. size_t params map to Swift `Int`.
// =============================================================================

/// fpdf_ppo.h: combine `src_doc`'s pages into `numPagesX x numPagesY` per output page. Returns a
/// NEW document handle the caller owns (→ FPDF_CloseDocument). `size_t` grid params → `Int`.
@_silgen_name("FPDF_ImportNPagesToOne")
func imp_ImportNPagesToOne(_ srcDoc: OpaquePointer?,
                           _ outputWidth: Float, _ outputHeight: Float,
                           _ numPagesX: Int, _ numPagesY: Int) -> OpaquePointer?   // size_t -> Int

/// fpdf_ppo.h: import `pageRange` (1-indexed, e.g. "1,3,5-7"; NULL = all) from `srcDoc` into
/// `destDoc` at 0-indexed `index`. Returns FPDF_BOOL (nonzero == success).
@_silgen_name("FPDF_ImportPages")
func imp_ImportPages(_ destDoc: OpaquePointer?, _ srcDoc: OpaquePointer?,
                     _ pageRange: UnsafePointer<CChar>?, _ index: Int32) -> Int32   // FPDF_BOOL, FPDF_BYTESTRING

/// fpdf_edit.h: create a new empty document. Returns a NEW handle the caller owns
/// (→ FPDF_CloseDocument), or NULL on failure.
@_silgen_name("FPDF_CreateNewDocument")
func imp_CreateNewDocument() -> OpaquePointer?
