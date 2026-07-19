import Foundation

/// One node of a tagged PDF's structure tree.
///
/// Deliberately has no identifier: the tree is derived fresh from bytes, and a per-walk
/// UUID would make two inspections of identical bytes compare unequal. SwiftUI callers
/// that need identity wrap these in an index-path key rather than pushing one in here.
struct StructureNode: Equatable {
    /// The `/S` role, normalized to a standard name where the producer used one.
    let role: String
    /// The `/T` title, when the producer supplied one.
    let title: String?
    /// The `/Alt` alternate description — what a screen reader announces.
    let altText: String?
    let children: [StructureNode]

    /// Roles whose whole purpose is to convey something visual, so a missing `/Alt`
    /// means a screen-reader user gets nothing at all.
    var isImageLike: Bool { role == "Figure" || role == "Formula" }
}

/// The structure of one page, plus the document-level tagging verdict.
struct PageStructure: Equatable {
    let pageIndex: Int
    /// Read from the document catalog, not this page — a tagged document may legitimately
    /// have pages with no tags of their own.
    let isTagged: Bool
    let roots: [StructureNode]

    /// Image-like nodes with no usable alternate text. Computed rather than stored so it
    /// cannot drift out of step with `roots`.
    var imagesMissingAltText: Int {
        func count(_ nodes: [StructureNode]) -> Int {
            nodes.reduce(0) { total, node in
                let missing = node.isImageLike && (node.altText?.isEmpty ?? true)
                return total + (missing ? 1 : 0) + count(node.children)
            }
        }
        return count(roots)
    }
}

enum StructureInspectionError: Error, Equatable {
    case invalidPDF
    case pageOutOfRange
}

/// Reads a PDF's tagged-structure tree. Read-only throughout: PDFium exposes no
/// tag-writing API, so this can report that a document is inaccessible but never fix it.
enum StructureInspectionService {

    /// Mirrors the field-walk cap in `QPDFService` — a malformed or cyclic tree must not
    /// be able to recurse without bound.
    static let maximumDepth = 64

    static func inspect(_ data: Data, pageIndex: Int) throws -> PageStructure {
        try withDocument(data) { document in
            guard pageIndex >= 0, pageIndex < Int(FPDF_GetPageCount(document)) else {
                throw StructureInspectionError.pageOutOfRange
            }

            let tagged = pst_Catalog_IsTagged(document) != 0

            guard let page = poe_LoadPage(document, Int32(pageIndex)) else {
                return PageStructure(pageIndex: pageIndex, isTagged: tagged, roots: [])
            }
            defer { poe_ClosePage(page) }

            guard let tree = pst_StructTree_GetForPage(page) else {
                return PageStructure(pageIndex: pageIndex, isTagged: tagged, roots: [])
            }
            defer { pst_StructTree_Close(tree) }

            var roots: [StructureNode] = []
            for index in 0..<pst_StructTree_CountChildren(tree) {
                if let node = node(from: pst_StructTree_GetChildAtIndex(tree, index), depth: 0) {
                    roots.append(node)
                }
            }
            return PageStructure(pageIndex: pageIndex, isTagged: tagged, roots: roots)
        }
    }

    /// Whether the document catalog marks this as a tagged PDF. Returns false rather than
    /// throwing for unreadable bytes — callers use this to decide whether to show a
    /// warning, and an unreadable document should not crash that decision.
    static func documentIsTagged(_ data: Data) -> Bool {
        (try? withDocument(data) { pst_Catalog_IsTagged($0) != 0 }) ?? false
    }

    // MARK: - Walking

    private static func node(from element: OpaquePointer?, depth: Int) -> StructureNode? {
        guard let element, depth < maximumDepth else { return nil }

        let role = pst_utf16String { pst_StructElement_GetType(element, $0, $1) } ?? "?"
        let title = pst_utf16String { pst_StructElement_GetTitle(element, $0, $1) }
        let altText = pst_utf16String { pst_StructElement_GetAltText(element, $0, $1) }

        // `CountChildren` counts marked-content references too — the MCIDs pointing into
        // the content stream that a tag actually wraps. Those are not structure elements
        // and `GetChildAtIndex` returns nil for them, so filtering nils here is what keeps
        // phantom children from appearing under every heading and paragraph.
        var children: [StructureNode] = []
        for index in 0..<pst_StructElement_CountChildren(element) {
            let child = pst_StructElement_GetChildAtIndex(element, index)
            if let node = node(from: child, depth: depth + 1) {
                children.append(node)
            }
        }

        return StructureNode(
            role: normalized(role),
            title: title,
            altText: altText,
            children: children
        )
    }

    /// Producers spell roles inconsistently. Map the common aliases onto the standard
    /// names the UI knows how to label, and pass anything unrecognized through untouched
    /// rather than silently relabelling a role we do not understand.
    private static func normalized(_ role: String) -> String {
        switch role {
        case "Sect", "Section": return "Section"
        case "Art", "Article": return "Article"
        case "NonStruct": return "NonStruct"
        default: return role
        }
    }

    // MARK: - PDFium lifecycle

    /// Serializes every PDFium entry point behind the process-wide lock and pairs
    /// init/destroy with load/close, matching the convention in `PDFiumProcessingEngine`.
    private static func withDocument<T>(
        _ data: Data,
        _ body: (OpaquePointer?) throws -> T
    ) throws -> T {
        pdfiumLock.lock()
        defer { pdfiumLock.unlock() }
        FPDF_InitLibrary()
        defer { FPDF_DestroyLibrary() }

        let document = data.withUnsafeBytes {
            FPDF_LoadMemDocument($0.baseAddress, Int32(data.count), nil)
        }
        guard let document else { throw StructureInspectionError.invalidPDF }
        defer { FPDF_CloseDocument(document) }

        return try body(document)
    }
}
