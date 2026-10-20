import PDFKit
import XCTest
@testable import Orifold

@MainActor
final class RestoredMemberIdentityTests: XCTestCase {
    func testDuplicateReadableMemberIDsRejectRecoverablyWithoutChangingInputBytes() throws {
        let directory = try disposableDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try editableFixture(duplicateIDs: true)
        let url = directory.appendingPathComponent("duplicate-members.pdf")
        try fixture.file.write(to: url)
        for matchingFingerprint in [false, true] {
            let store = WorkspaceFingerprintStore(directory: directory)
            if matchingFingerprint { store.record(data: fixture.file, for: fixture.workspaceID) }
            XCTAssertThrowsError(try WorkspaceDocument(testingFile: FileWrapper(url: url, options: []),
                                                       contentType: .pdf, fingerprintStore: store)) { error in
                XCTAssertEqual((error as NSError).domain, NSCocoaErrorDomain)
                XCTAssertEqual((error as NSError).code, CocoaError.fileReadCorruptFile.rawValue)
            }
            XCTAssertEqual(try Data(contentsOf: url), fixture.file)
        }
    }

    func testFingerprintMismatchStillDiscardsAmbiguousEditableStateForFlatVisibleContent() throws {
        let directory = try disposableDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try editableFixture(duplicateIDs: true)
        let store = WorkspaceFingerprintStore(directory: directory)
        store.record(data: Data("different prior bytes".utf8), for: fixture.workspaceID)
        let document = try WorkspaceDocument(testingFile: FileWrapper(regularFileWithContents: fixture.file),
                                             contentType: .pdf, fingerprintStore: store)
        XCTAssertTrue(document.externalModificationDetected)
        XCTAssertEqual(document.workspace.documents.count, 1)
        XCTAssertNotEqual(document.workspace.id, fixture.workspaceID)
    }

    func testValidLegacyRestorePreservesMemberBytesAndCanAddFiles() async throws {
        let directory = try disposableDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try editableFixture(duplicateIDs: false)
        let document = try WorkspaceDocument(testingFile: FileWrapper(regularFileWithContents: fixture.file),
                                             contentType: .pdf,
                                             fingerprintStore: WorkspaceFingerprintStore(directory: directory))
        XCTAssertEqual(document.workspace.id, fixture.workspaceID)
        XCTAssertEqual(document.workspace.schemaVersion, 1)
        XCTAssertEqual(document.memberPDFData, fixture.members)
        XCTAssertEqual(document.workspace.documents.map(\.id), fixture.ids)
        let viewModel = WorkspaceViewModel(document: document, processingEngine: PDFKitProcessingEngineFallback())
        let extra = directory.appendingPathComponent("extra.pdf")
        try blankPDF().write(to: extra)
        viewModel.importFiles(urls: [extra])
        for _ in 0..<1000 where viewModel.isImporting {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertFalse(viewModel.isImporting)
        XCTAssertNil(viewModel.importError)
        XCTAssertEqual(viewModel.memberDocuments.count, 3)
        XCTAssertEqual(Array(viewModel.memberDocuments.prefix(2)).map(\.id), fixture.ids)
    }

    private func disposableDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("member-identities-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func blankPDF() throws -> Data {
        let pdf = PDFDocument()
        pdf.insert(PDFPage(), at: 0)
        return try XCTUnwrap(PDFSerializer.data(from: pdf))
    }

    private func editableFixture(duplicateIDs: Bool) throws -> (file: Data, workspaceID: UUID, members: [UUID: Data], ids: [UUID]) {
        let base = try blankPDF()
        let pdf = try XCTUnwrap(PDFDocument(data: base))
        var first = MemberDocument(displayName: "First", sourcePDFRef: "first.pdf")
        var second = MemberDocument(displayName: "Second", sourcePDFRef: "second.pdf")
        if duplicateIDs { second.id = first.id }
        let refs = [PageRef(memberDocId: first.id, sourcePageIndex: 0), PageRef(memberDocId: second.id, sourcePageIndex: 0)]
        first.pageRefs = [refs[0].id]
        second.pageRefs = [refs[1].id]
        var workspace = Workspace()
        workspace.documents = [first, second]
        workspace.pageOrder = refs
        var members = [first.id: base]
        members[second.id] = base
        var workspaceJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(workspace)) as? [String: Any])
        workspaceJSON.removeValue(forKey: "schemaVersion")
        workspaceJSON.removeValue(forKey: "decorations")
        let metadata: [String: Any] = ["editableWorkspace": workspaceJSON,
                                     "editableMemberPDFData": try JSONSerialization.jsonObject(with: JSONEncoder().encode(members))]
        let json = try JSONSerialization.data(withJSONObject: metadata, options: [.sortedKeys])
        let annotation = PDFAnnotation(bounds: CGRect(x: -1000, y: -1000, width: 1, height: 1), forType: .text, withProperties: nil)
        annotation.setValue(try XCTUnwrap(String(data: json, encoding: .utf8)),
                            forAnnotationKey: PDFAnnotationKey(rawValue: "/OrifoldWorkspaceComments"))
        try XCTUnwrap(pdf.page(at: 0)).addAnnotation(annotation)
        return (try XCTUnwrap(PDFSerializer.data(from: pdf)), workspace.id, members, [first.id, second.id])
    }
}
