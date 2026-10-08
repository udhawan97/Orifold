import Foundation
import PDFKit
import XCTest
@testable import Orifold

@MainActor
final class BatesNumberSafetyTests: XCTestCase {
    func testMalformedPersistedStartsRejectRatherThanClampOrDefault() throws {
        for value in ["-1", "1000000", String(Int.max), String(Int.max - 1), "1.5", "\"invalid\"",
                      "18446744073709551616"] {
            let json = "{\"kind\":\"bates\",\"startNumber\":\(value)}"
            XCTAssertThrowsError(try JSONDecoder().decode(PageDecoration.self, from: Data(json.utf8))) { error in
                guard case PageDecoration.ValidationError.invalidBatesStartNumber = error else {
                    return XCTFail("Unexpected error: \(error)")
                }
            }
        }
    }

    func testLegacyDefaultsAndValidStartingDomainStillDecode() throws {
        let legacy = try JSONDecoder().decode(PageDecoration.self, from: Data("{\"kind\":\"bates\"}".utf8))
        XCTAssertEqual(legacy.startNumber, 100)
        XCTAssertEqual(legacy.prefix, "DEF")
        for start in [0, 100, 999_999] {
            let decoration = PageDecoration(kind: .bates, startNumber: start)
            let restored = try JSONDecoder().decode(PageDecoration.self, from: JSONEncoder().encode(decoration))
            XCTAssertEqual(restored, decoration)
        }
    }

    func testSharedFormatterPreservesSequenceAndFullWidthNumbers() {
        let normal = PageDecoration(kind: .bates, prefix: "DEF", startNumber: 100)
        XCTAssertEqual((0..<5).map { PDFDecorationExportBaker.text(for: normal, pageIndex: $0, pageCount: 5) },
                       ["DEF-000100", "DEF-000101", "DEF-000102", "DEF-000103", "DEF-000104"])
        let boundary = PageDecoration(kind: .bates, prefix: "EDGE", startNumber: 999_999)
        XCTAssertEqual(PDFDecorationExportBaker.text(for: boundary, pageIndex: 0, pageCount: 2), "EDGE-999999")
        XCTAssertEqual(PDFDecorationExportBaker.text(for: boundary, pageIndex: 1, pageCount: 2), "EDGE-1000000")
        let zero = PageDecoration(kind: .bates, prefix: "ZERO", startNumber: 0)
        XCTAssertEqual(PDFDecorationExportBaker.text(for: zero, pageIndex: Int.max, pageCount: Int.max),
                       "ZERO-\(Int.max)")
    }

    func testSharedFormatterReturnsNoFabricatedIdentifierForInvalidOrOverflowingInput() {
        for (start, index) in [(Int.max, 1), (Int.max - 1, 2), (-1, 0), (1_000_000, 0),
                               (100, Int.max), (100, -1)] {
            let decoration = PageDecoration(kind: .bates, startNumber: start)
            XCTAssertEqual(PDFDecorationExportBaker.text(for: decoration, pageIndex: index, pageCount: 3), "")
        }
    }

    func testTwoPageIntMaxAndThreePageIntMaxMinusOneRejectOnReopenWithoutChangingFileBytes() throws {
        for (pageCount, start) in [(2, Int.max), (3, Int.max - 1)] {
            let directory = try disposableDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let data = try editableFixture(pageCount: pageCount, start: start).file
            let url = directory.appendingPathComponent("invalid-bates.pdf")
            try data.write(to: url)
            let wrapper = try FileWrapper(url: url, options: [])
            XCTAssertThrowsError(try WorkspaceDocument(
                testingFile: wrapper, contentType: .pdf, filename: "invalid-bates.pdf",
                fingerprintStore: WorkspaceFingerprintStore(directory: directory)
            )) { error in
                XCTAssertEqual((error as NSError).domain, NSCocoaErrorDomain)
                XCTAssertEqual((error as NSError).code, CocoaError.fileReadCorruptFile.rawValue)
            }
            XCTAssertEqual(try Data(contentsOf: url), data)
        }
    }

    func testLegacyEditableWorkspaceReopensWithBatesDefaultsAndOriginalMemberBytes() throws {
        let directory = try disposableDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try editableFixture(pageCount: 2, start: 100, omitsStartNumber: true)
        let reopened = try WorkspaceDocument(testingFile: FileWrapper(regularFileWithContents: fixture.file),
                                             contentType: .pdf, filename: "legacy.pdf",
                                             fingerprintStore: WorkspaceFingerprintStore(directory: directory))
        XCTAssertEqual(reopened.workspace.decorations.first?.startNumber, 100)
        XCTAssertEqual(reopened.workspace.schemaVersion, 4)
        XCTAssertEqual(reopened.memberPDFData.values.first, fixture.member)
        XCTAssertEqual(reopened.workspace.pageOrder.count, 2)
    }

    func testExportRejectsInvalidInMemoryStateBeforeDrawing() throws {
        let data = try blankPDF(pageCount: 2)
        let member = UUID()
        let refs = (0..<2).map { PageRef(memberDocId: member, sourcePageIndex: $0) }
        for start in [Int.max, Int.max - 1, -1, 1_000_000] {
            XCTAssertThrowsError(try PDFDecorationExportBaker.bake(
                decorations: [PageDecoration(kind: .bates, startNumber: start)], pageOrder: refs, into: data
            )) { error in
                guard case PDFDecorationExportBaker.BakeError.invalidDecoration = error else {
                    return XCTFail("Unexpected error: \(error)")
                }
            }
        }
    }

    func testBoundaryEditableSaveReopenAndNumberingUndoPreserveMemberBytes() throws {
        let directory = try disposableDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WorkspaceFingerprintStore(directory: directory)
        let input = try blankPDF(pageCount: 2)
        let document = try WorkspaceDocument(testingFile: FileWrapper(regularFileWithContents: input),
                                             contentType: .pdf, filename: "boundary.pdf", fingerprintStore: store)
        document.workspace.decorations = [PageDecoration(kind: .bates, startNumber: 999_999)]
        let originalMembers = document.memberPDFData
        let viewModel = WorkspaceViewModel(document: document, processingEngine: PDFKitProcessingEngineFallback())
        let undo = UndoManager()
        undo.groupsByEvent = false
        viewModel.undoManager = undo
        undo.beginUndoGrouping()
        viewModel.setDecorationStartNumber(.bates, startNumber: 100)
        undo.endUndoGrouping()
        XCTAssertEqual(document.workspace.decorations.first?.startNumber, 100)
        undo.undo()
        XCTAssertEqual(document.workspace.decorations.first?.startNumber, 999_999)
        XCTAssertEqual(document.memberPDFData, originalMembers)

        let snapshot = try document.snapshot(contentType: .pdf)
        let saved = try document.savedFileWrapper(from: snapshot)
        let visible = try XCTUnwrap(saved.regularFileContents)
        XCTAssertTrue(PDFTextAnalysisEngine.readingOrderText(data: visible, pageIndex: 0).contains("DEF-999999"))
        XCTAssertTrue(PDFTextAnalysisEngine.readingOrderText(data: visible, pageIndex: 1).contains("DEF-1000000"))
        let reopened = try WorkspaceDocument(testingFile: saved, contentType: .pdf,
                                             filename: "boundary.pdf", fingerprintStore: store)
        XCTAssertEqual(reopened.workspace.decorations.first?.startNumber, 999_999)
        XCTAssertEqual(reopened.workspace.pageOrder.map(\.id), document.workspace.pageOrder.map(\.id))
        XCTAssertEqual(reopened.memberPDFData, snapshot.memberPDFData)
    }

    private func disposableDirectory() throws -> URL {
        let root = ProcessInfo.processInfo.environment["ORIFOLD_TEST_TEMP_ROOT"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) } ?? FileManager.default.temporaryDirectory
        let directory = root.appendingPathComponent("bates-safety-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func blankPDF(pageCount: Int) throws -> Data {
        let output = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        let consumer = try XCTUnwrap(CGDataConsumer(data: output as CFMutableData))
        let context = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &mediaBox, nil))
        for _ in 0..<pageCount {
            context.beginPDFPage(nil)
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(mediaBox)
            context.endPDFPage()
        }
        context.closePDF()
        return output as Data
    }

    private func editableFixture(pageCount: Int, start: Int,
                                 omitsStartNumber: Bool = false) throws -> (file: Data, member: Data) {
        let base = try blankPDF(pageCount: pageCount)
        let pdf = try XCTUnwrap(PDFDocument(data: base))
        var member = MemberDocument(displayName: "Disposable Bates", sourcePDFRef: "fixture.pdf")
        let refs = (0..<pageCount).map { PageRef(memberDocId: member.id, sourcePageIndex: $0) }
        member.pageRefs = refs.map(\.id)
        var workspace = Workspace()
        workspace.documents = [member]
        workspace.pageOrder = refs
        workspace.decorations = [PageDecoration(kind: .bates, startNumber: start)]
        var workspaceJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(workspace)) as? [String: Any])
        if omitsStartNumber {
            workspaceJSON["schemaVersion"] = 4
            var decorations = try XCTUnwrap(workspaceJSON["decorations"] as? [[String: Any]])
            decorations[0].removeValue(forKey: "startNumber")
            workspaceJSON["decorations"] = decorations
        }
        let memberJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode([member.id: base]))
        let metadata: [String: Any] = ["editableWorkspace": workspaceJSON, "editableMemberPDFData": memberJSON]
        let encoded = try JSONSerialization.data(withJSONObject: metadata, options: [.sortedKeys])
        let annotation = PDFAnnotation(bounds: CGRect(x: -1000, y: -1000, width: 1, height: 1),
                                       forType: .text, withProperties: nil)
        annotation.setValue(try XCTUnwrap(String(data: encoded, encoding: .utf8)),
                            forAnnotationKey: PDFAnnotationKey(rawValue: "/OrifoldWorkspaceComments"))
        try XCTUnwrap(pdf.page(at: 0)).addAnnotation(annotation)
        return (try XCTUnwrap(PDFSerializer.data(from: pdf)), base)
    }
}
