import AppKit
import Foundation
import PDFKit
import XCTest

/// Builds PDFs carrying a chosen `/Outlines` tree, for the bookmark and
/// table-of-contents tests.
///
/// Lives in `Support` rather than beside one test class because two suites need the same
/// shapes: `PDFOutlineTOCTests` (what a well-formed outline turns into) and
/// `PDFOutlinePromotionTests` (what a malformed one must not do).
enum OutlineFixturePDFBuilder {

    /// One bookmark to write. A blank `title` leaves a perfectly valid outline entry that
    /// `PDFOutlineReader` cannot resolve — the shape that exercises promotion, and the
    /// one PDFKit preserves verbatim through a serialize/reload cycle, children included.
    struct Spec {
        var title: String
        var page: Int
        var children: [Spec] = []
    }

    static func blankPDF(pageCount: Int) -> PDFDocument {
        let document = PDFDocument()
        let bounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        for index in 0..<pageCount {
            let image = NSImage(size: bounds.size)
            image.lockFocus()
            NSColor.white.setFill()
            bounds.fill()
            ("page \(index)" as NSString).draw(
                at: NSPoint(x: 72, y: 700),
                withAttributes: [.font: NSFont.systemFont(ofSize: 24)]
            )
            image.unlockFocus()
            if let page = PDFPage(image: image) {
                document.insert(page, at: index)
            }
        }
        return document
    }

    /// Builds the outline, then round-trips through bytes before handing the document
    /// back. This is not incidental: the app only ever reads outlines from documents
    /// parsed out of `memberPDFData`, and PDFKit rejects `exchangePage` on an in-memory
    /// document whose `outlineRoot` was assigned programmatically. Serializing first both
    /// matches production and keeps the fixture out of that quirk.
    static func outlinedPDF(pageCount: Int, outline: [Spec]) -> PDFDocument {
        let document = blankPDF(pageCount: pageCount)
        let root = PDFOutline()
        for (index, spec) in outline.enumerated() {
            root.insertChild(outlineNode(spec, in: document), at: index)
        }
        document.outlineRoot = root
        guard let data = document.dataRepresentation(),
              let reloaded = PDFDocument(data: data) else {
            XCTFail("fixture PDF failed to round-trip through bytes")
            return document
        }
        return reloaded
    }

    /// `wrappers` blank-labelled nodes nested one inside the next, the innermost holding a
    /// single resolvable bookmark.
    ///
    /// Every wrapper carries a valid destination — only the blank label makes it
    /// unresolvable — so the chain is a plausible file rather than a contrived one, and
    /// each level exercises the promotion branch rather than any other drop path.
    static func unresolvableChain(wrappers: Int, around leaf: String) -> Spec {
        var spec = Spec(title: leaf, page: 0)
        for _ in 0..<wrappers {
            spec = Spec(title: "", page: 0, children: [spec])
        }
        return spec
    }

    private static func outlineNode(_ spec: Spec, in document: PDFDocument) -> PDFOutline {
        let node = PDFOutline()
        node.label = spec.title
        if let page = document.page(at: spec.page) {
            node.destination = PDFDestination(page: page, at: NSPoint(x: 0, y: 792))
        }
        for (index, child) in spec.children.enumerated() {
            node.insertChild(outlineNode(child, in: document), at: index)
        }
        return node
    }
}
