import Foundation

// `fpdf_structtree.h` — the read-only tagged-PDF structure surface.
//
// Every symbol here was verified exported by the vendored PDFium
// (`nm -gU …/PDFium.framework/PDFium`) and verified NOT already bound elsewhere in
// the module. The `pst_` prefix exists to keep that true: two `@_silgen_name`
// declarations of one C symbol with different Swift signatures compile fine in debug
// and under `swift test`, then break `swift build -c release` when whole-module
// optimization merges them. Page and document lifecycle are deliberately NOT re-bound
// here — reuse `poe_LoadPage`/`poe_ClosePage` (PDFiumObjectBindings) and
// `FPDF_LoadMemDocument`/`FPDF_CloseDocument` (PDFiumProcessingEngine).
//
// Nothing in this file writes. PDFium exposes no tag-writing API and no permissive
// tooling exists for it, so "tell the user their document is untagged" is in scope
// while "make it tagged" is not.

/// `fpdf_catalog.h` — whether the catalog marks this as a tagged PDF (`/MarkInfo
/// /Marked true`). It lives in this file rather than alongside the archival-readiness
/// checks that also want it, because the WAVE_4 plan scheduled the same C symbol to be
/// bound by two features under two prefixes. Two `@_silgen_name` declarations of one
/// symbol with different signatures are exactly what breaks `swift build -c release`,
/// so it is bound once, here, and archival readiness reuses it.
@_silgen_name("FPDFCatalog_IsTagged")
func pst_Catalog_IsTagged(_ document: OpaquePointer?) -> Int32

@_silgen_name("FPDF_StructTree_GetForPage")
func pst_StructTree_GetForPage(_ page: OpaquePointer?) -> OpaquePointer?

@_silgen_name("FPDF_StructTree_Close")
func pst_StructTree_Close(_ structTree: OpaquePointer?)

@_silgen_name("FPDF_StructTree_CountChildren")
func pst_StructTree_CountChildren(_ structTree: OpaquePointer?) -> Int32

@_silgen_name("FPDF_StructTree_GetChildAtIndex")
func pst_StructTree_GetChildAtIndex(
    _ structTree: OpaquePointer?,
    _ index: Int32
) -> OpaquePointer?

@_silgen_name("FPDF_StructElement_GetType")
func pst_StructElement_GetType(
    _ element: OpaquePointer?,
    _ buffer: UnsafeMutableRawPointer?,
    _ buflen: UInt
) -> UInt

@_silgen_name("FPDF_StructElement_GetTitle")
func pst_StructElement_GetTitle(
    _ element: OpaquePointer?,
    _ buffer: UnsafeMutableRawPointer?,
    _ buflen: UInt
) -> UInt

@_silgen_name("FPDF_StructElement_GetAltText")
func pst_StructElement_GetAltText(
    _ element: OpaquePointer?,
    _ buffer: UnsafeMutableRawPointer?,
    _ buflen: UInt
) -> UInt

@_silgen_name("FPDF_StructElement_CountChildren")
func pst_StructElement_CountChildren(_ element: OpaquePointer?) -> Int32

@_silgen_name("FPDF_StructElement_GetChildAtIndex")
func pst_StructElement_GetChildAtIndex(
    _ element: OpaquePointer?,
    _ index: Int32
) -> OpaquePointer?

/// Drives PDFium's two-call UTF-16LE string idiom: call once with a nil buffer to learn
/// the byte length, then again to fill it.
///
/// The reported length *includes* the terminating UTF-16 NUL, so a return of 2 means the
/// string is present but empty — callers want nil there, not `""`, since an empty
/// `/Alt` is as absent as a missing one for accessibility purposes.
func pst_utf16String(_ read: (UnsafeMutableRawPointer?, UInt) -> UInt) -> String? {
    let needed = read(nil, 0)
    guard needed > 2 else { return nil }

    var buffer = [UInt8](repeating: 0, count: Int(needed))
    _ = buffer.withUnsafeMutableBytes { raw in
        read(raw.baseAddress, UInt(raw.count))
    }
    return String(bytes: buffer.prefix(Int(needed) - 2), encoding: .utf16LittleEndian)
}
