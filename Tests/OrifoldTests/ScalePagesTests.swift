import PDFKit
import XCTest
@testable import Orifold

/// Scale-to-paper-size as a 1×1 imposition: every page lands on a uniform target sheet,
/// and — unlike booklet/N-up — the page mapping stays faithful, so the bookmark write
/// stage keeps running.
@MainActor
final class ScalePagesTests: XCTestCase {

    private static let a4 = (width: 595.0, height: 842.0)

    func testScaleImposesEveryPageOntoTheTargetSheetSize() throws {
        let baked = BakedPDFData(alreadyFlattened: try lettersizedData(pageCount: 3))
        let scaled = try PDFImpositionEngine.impose(
            baked,
            layout: .scale(width: Self.a4.width, height: Self.a4.height)
        )
        let reopened = try XCTUnwrap(PDFDocument(data: scaled))
        XCTAssertEqual(reopened.pageCount, 3, "1x1 scale must preserve page count")
        for index in 0..<reopened.pageCount {
            let bounds = try XCTUnwrap(reopened.page(at: index)).bounds(for: .mediaBox)
            XCTAssertEqual(bounds.width, Self.a4.width, accuracy: 1)
            XCTAssertEqual(bounds.height, Self.a4.height, accuracy: 1)
        }
    }

    func testOnlyScalePreservesThePageMapping() {
        XCTAssertTrue(ImpositionLayout.scale(width: 595, height: 842).preservesPageMapping)
        XCTAssertFalse(ImpositionLayout.booklet.preservesPageMapping)
        XCTAssertFalse(ImpositionLayout.nUp(rows: 2, cols: 2).preservesPageMapping)
    }

    func testScaledExportKeepsBookmarks() throws {
        let bytes = try Data(contentsOf: try XCTUnwrap(SampleDocument.url))
        let document = WorkspaceDocument()
        let pdf = try XCTUnwrap(PDFDocument(data: bytes))
        var member = MemberDocument(displayName: "Fixture", sourcePDFRef: "Fixture.pdf")
        let refs = (0..<pdf.pageCount).map { PageRef(memberDocId: member.id, sourcePageIndex: $0) }
        member.pageRefs = refs.map(\.id)
        document.workspace.documents.append(member)
        document.memberPDFData[member.id] = bytes
        document.workspace.pageOrder = refs
        let model = WorkspaceViewModel(document: document)

        var options = WorkspaceExportOptions()
        options.imposition = .scale(width: Self.a4.width, height: Self.a4.height)
        let data = try model.dataForPDFExport(options: options)
        let reopened = try XCTUnwrap(PDFDocument(data: data))

        let bookmarks = PDFOutlineReader.nodes(in: reopened)
        XCTAssertEqual(bookmarks.count, 7, "a faithful 1x1 mapping must keep the outline")
        let bounds = try XCTUnwrap(reopened.page(at: 0)).bounds(for: .mediaBox)
        XCTAssertEqual(bounds.width, Self.a4.width, accuracy: 1)
    }

    // MARK: - Helpers

    private func lettersizedData(pageCount: Int) throws -> Data {
        let pdf = PDFDocument()
        let bounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        for index in 0..<pageCount {
            let image = NSImage(size: bounds.size)
            image.lockFocus()
            NSColor.white.setFill()
            bounds.fill()
            ("Page \(index)" as NSString).draw(
                at: NSPoint(x: 40, y: 400),
                withAttributes: [.font: NSFont.systemFont(ofSize: 24), .foregroundColor: NSColor.black]
            )
            image.unlockFocus()
            if let page = PDFPage(image: image) { pdf.insert(page, at: index) }
        }
        return try XCTUnwrap(PDFSerializer.data(from: pdf))
    }
}
