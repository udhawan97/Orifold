import AppKit
import PDFKit
import XCTest
@testable import Orifold

/// A bookmark to synthesize, nestable.
struct OutlineFixtureSpec {
    var title: String
    var page: Int
    var children: [OutlineFixtureSpec] = []
}

/// A member document plus the page refs and bytes a workspace needs to hold it.
struct OutlineFixtureMember {
    var member: MemberDocument
    var refs: [PageRef]
    var data: Data
}

/// Builders for PDFs carrying an embedded `/Outlines` tree.
///
/// Namespaced rather than free functions because `PDFOutlineTOCTests` still declares
/// its own file-private equivalents; distinct names keep the two from colliding.
enum OutlineFixtures {

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

    /// Round-trips through bytes after assigning the outline, matching production: the
    /// app only reads outlines from documents parsed out of `memberPDFData`, and PDFKit
    /// rejects `exchangePage` on a document whose `outlineRoot` was set programmatically.
    static func outlinedPDF(pageCount: Int, outline: [OutlineFixtureSpec]) -> PDFDocument {
        let document = blankPDF(pageCount: pageCount)
        let root = PDFOutline()
        for (index, spec) in outline.enumerated() {
            root.insertChild(node(spec, in: document), at: index)
        }
        document.outlineRoot = root
        guard let data = document.dataRepresentation(), let reloaded = PDFDocument(data: data) else {
            XCTFail("fixture PDF failed to round-trip through bytes")
            return document
        }
        return reloaded
    }

    static func outlinedMember(
        name: String,
        pageCount: Int,
        outline: [OutlineFixtureSpec]
    ) throws -> OutlineFixtureMember {
        let pdf = outlinedPDF(pageCount: pageCount, outline: outline)
        var member = MemberDocument(displayName: name, sourcePDFRef: "\(name).pdf")
        let refs = (0..<pdf.pageCount).map { PageRef(memberDocId: member.id, sourcePageIndex: $0) }
        member.pageRefs = refs.map(\.id)
        let data = try XCTUnwrap(pdf.dataRepresentation())
        return OutlineFixtureMember(member: member, refs: refs, data: data)
    }

    static func viewModel(members: [OutlineFixtureMember]) -> WorkspaceViewModel {
        let document = WorkspaceDocument()
        document.workspace.documents = members.map(\.member)
        document.workspace.pageOrder = members.flatMap(\.refs)
        for member in members {
            document.memberPDFData[member.member.id] = member.data
        }
        return WorkspaceViewModel(document: document, processingEngine: PDFiumProcessingEngine())
    }

    private static func node(_ spec: OutlineFixtureSpec, in document: PDFDocument) -> PDFOutline {
        let outline = PDFOutline()
        outline.label = spec.title
        if let page = document.page(at: spec.page) {
            outline.destination = PDFDestination(page: page, at: NSPoint(x: 0, y: 792))
        }
        for (index, child) in spec.children.enumerated() {
            outline.insertChild(node(child, in: document), at: index)
        }
        return outline
    }
}

/// Puts a known-black mark on a page and measures how much ink an exported page carries.
/// Lets a test assert "the decoration bake actually ran" as a pixel question rather than a
/// text-extraction one — `PDFPage.string` is off-limits on CI.
enum DecorationProbe {

    /// Solid black makes "did the bake run?" an unambiguous pixel question.
    static func addBlackDecoration(to viewModel: WorkspaceViewModel) throws {
        let pageRef = try XCTUnwrap(viewModel.document.workspace.pageOrder.first)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 64, pixelsHigh: 64, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.black.setFill()
        NSRect(x: 0, y: 0, width: 64, height: 64).fill()
        NSGraphicsContext.restoreGraphicsState()
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))

        viewModel.document.workspace.decorations.append(PageDecoration.image(
            imageData: png,
            pageRefID: pageRef.id,
            rect: CGRect(x: 40, y: 300, width: 400, height: 160)
        ))
    }

    /// Fraction of sampled pixels visibly non-white. Never asserts on `PDFPage.string`.
    static func inkCoverage(of data: Data, pageIndex: Int = 0) throws -> Double {
        let pdf = try XCTUnwrap(PDFDocument(data: data))
        let page = try XCTUnwrap(pdf.page(at: pageIndex))
        let bounds = page.bounds(for: .mediaBox)
        let thumbnail = page.thumbnail(of: CGSize(width: bounds.width, height: bounds.height), for: .mediaBox)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(thumbnail.tiffRepresentation)))

        var inked = 0
        var sampled = 0
        for sampleX in stride(from: 0, to: bitmap.pixelsWide, by: 7) {
            for sampleY in stride(from: 0, to: bitmap.pixelsHigh, by: 7) {
                guard let color = bitmap.colorAt(x: sampleX, y: sampleY)?.usingColorSpace(.deviceRGB) else { continue }
                sampled += 1
                if color.brightnessComponent < 0.85 { inked += 1 }
            }
        }
        guard sampled > 0 else { return 0 }
        return Double(inked) / Double(sampled)
    }
}
