import PDFKit
import XCTest
@testable import Orifold

@MainActor
final class RestoredPageIdentityTests: XCTestCase {
    private enum Malformation: CaseIterable {
        case duplicatePageID
        case duplicateMemberPageID
        case missingMemberPageID
        case unknownMemberPageID
        case wrongOwner
        case unknownOwner
    }

    func testAmbiguousPageIdentitiesRejectRecoverablyWithoutChangingInputBytes() throws {
        for malformation in Malformation.allCases {
            for legacy in [false, true] {
                for matchingFingerprint in [false, true] {
                    let directory = try disposableDirectory()
                    defer { try? FileManager.default.removeItem(at: directory) }
                    let fixture = try editableFixture(legacy: legacy, malformation: malformation)
                    let url = directory.appendingPathComponent("ambiguous-pages.pdf")
                    try fixture.file.write(to: url)
                    let store = WorkspaceFingerprintStore(directory: directory)
                    if matchingFingerprint { store.record(data: fixture.file, for: fixture.fingerprintID) }
                    XCTAssertThrowsError(try WorkspaceDocument(testingFile: FileWrapper(url: url, options: []),
                                                               contentType: .pdf, fingerprintStore: store),
                                         "\(malformation), legacy: \(legacy), matching: \(matchingFingerprint)") { error in
                        XCTAssertEqual((error as NSError).domain, NSCocoaErrorDomain)
                        XCTAssertEqual((error as NSError).code, CocoaError.fileReadCorruptFile.rawValue)
                    }
                    XCTAssertEqual(try Data(contentsOf: url), fixture.file)
                }
            }
        }
    }

    func testFingerprintMismatchStillLoadsFlatVisibleContentDespiteAmbiguousPageIdentities() throws {
        for legacy in [false, true] {
            let directory = try disposableDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let fixture = try editableFixture(legacy: legacy, malformation: .duplicatePageID)
            let url = directory.appendingPathComponent("externally-modified.pdf")
            try fixture.file.write(to: url)
            let store = WorkspaceFingerprintStore(directory: directory)
            store.record(data: Data("different prior bytes".utf8), for: fixture.fingerprintID)
            let document = try WorkspaceDocument(testingFile: FileWrapper(url: url, options: []),
                                                 contentType: .pdf, fingerprintStore: store)
            XCTAssertTrue(document.externalModificationDetected)
            XCTAssertNotEqual(document.workspace.id, fixture.workspace.id)
            XCTAssertEqual(document.workspace.documents.count, 1)
            XCTAssertEqual(document.workspace.pageOrder.count, 1)
            XCTAssertEqual(document.workspace.documents[0].pageRefs, document.workspace.pageOrder.map(\.id))
            let data = try XCTUnwrap(document.memberPDFData[document.workspace.documents[0].id])
            XCTAssertEqual(try XCTUnwrap(PDFDocument(data: data)).pageCount, 1)
            XCTAssertEqual(try Data(contentsOf: url), fixture.file)
        }
    }

    func testValidLegacyAndCurrentRestorePreserveIdentityOwnershipAndBytes() throws {
        for legacy in [false, true] {
            for matchingFingerprint in [false, true] {
                let directory = try disposableDirectory()
                defer { try? FileManager.default.removeItem(at: directory) }
                let fixture = try editableFixture(legacy: legacy)
                let store = WorkspaceFingerprintStore(directory: directory)
                if matchingFingerprint { store.record(data: fixture.file, for: fixture.fingerprintID) }
                let document = try WorkspaceDocument(testingFile: FileWrapper(regularFileWithContents: fixture.file),
                                                     contentType: .pdf, fingerprintStore: store)
                XCTAssertFalse(document.externalModificationDetected)
                XCTAssertEqual(document.workspace.id, fixture.workspace.id)
                XCTAssertEqual(document.workspace.schemaVersion, legacy ? 1 : fixture.workspace.schemaVersion)
                XCTAssertEqual(document.workspace.pageOrder.map(\.id), fixture.workspace.pageOrder.map(\.id))
                XCTAssertEqual(document.workspace.pageOrder.map(\.memberDocId), fixture.workspace.pageOrder.map(\.memberDocId))
                XCTAssertEqual(document.workspace.pageOrder.map(\.sourcePageIndex), fixture.workspace.pageOrder.map(\.sourcePageIndex))
                XCTAssertEqual(document.workspace.documents.map(\.pageRefs), fixture.workspace.documents.map(\.pageRefs))
                XCTAssertEqual(document.memberPDFData, fixture.members)
            }
        }
    }

    private func disposableDirectory() throws -> URL {
        let temporary = ProcessInfo.processInfo.environment["ORIFOLD_TEST_TEMP_ROOT"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) } ?? FileManager.default.temporaryDirectory
        let directory = temporary.appendingPathComponent("page-identities-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func blankPDF(pageCount: Int) throws -> Data {
        let pdf = PDFDocument()
        for index in 0..<pageCount { pdf.insert(PDFPage(), at: index) }
        return try XCTUnwrap(PDFSerializer.data(from: pdf))
    }

    private func editableFixture(legacy: Bool, malformation: Malformation? = nil) throws ->
        (file: Data, workspace: Workspace, fingerprintID: UUID, members: [UUID: Data]) {
        var first = MemberDocument(displayName: "First", sourcePDFRef: "first.pdf")
        var second = MemberDocument(displayName: "Second", sourcePDFRef: "second.pdf")
        // Reordered refs can legitimately retain their pristine source indexes.
        let firstPage = PageRef(memberDocId: first.id, sourcePageIndex: 1)
        let secondPage = PageRef(memberDocId: first.id, sourcePageIndex: 0)
        let thirdPage = PageRef(memberDocId: second.id, sourcePageIndex: 0)
        first.pageRefs = [firstPage.id, secondPage.id]
        second.pageRefs = [thirdPage.id]
        var workspace = Workspace()
        workspace.documents = [first, second]
        workspace.pageOrder = [firstPage, secondPage, thirdPage]
        switch malformation {
        case .duplicatePageID:
            workspace.pageOrder.append(firstPage)
        case .duplicateMemberPageID:
            workspace.documents[0].pageRefs.append(firstPage.id)
        case .missingMemberPageID:
            workspace.documents[0].pageRefs.removeLast()
        case .unknownMemberPageID:
            workspace.documents[0].pageRefs[1] = UUID()
        case .wrongOwner:
            workspace.pageOrder[1].memberDocId = second.id
        case .unknownOwner:
            workspace.pageOrder[1].memberDocId = UUID()
        case nil:
            break
        }
        let members = [first.id: try blankPDF(pageCount: 2), second.id: try blankPDF(pageCount: 1)]
        var workspaceJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(workspace)) as? [String: Any])
        if legacy {
            workspaceJSON.removeValue(forKey: "schemaVersion")
            workspaceJSON.removeValue(forKey: "decorations")
        }
        let fingerprintID = legacy ? workspace.id : UUID()
        var metadata: [String: Any] = [
            "editableWorkspace": workspaceJSON,
            "editableMemberPDFData": try JSONSerialization.jsonObject(with: JSONEncoder().encode(members))
        ]
        if !legacy { metadata["savedSnapshotID"] = fingerprintID.uuidString }
        let json = try JSONSerialization.data(withJSONObject: metadata, options: [.sortedKeys])
        let pdf = try XCTUnwrap(PDFDocument(data: blankPDF(pageCount: 1)))
        let annotation = PDFAnnotation(bounds: CGRect(x: -1000, y: -1000, width: 1, height: 1), forType: .text, withProperties: nil)
        annotation.setValue(try XCTUnwrap(String(data: json, encoding: .utf8)),
                            forAnnotationKey: PDFAnnotationKey(rawValue: "/OrifoldWorkspaceComments"))
        try XCTUnwrap(pdf.page(at: 0)).addAnnotation(annotation)
        return (try XCTUnwrap(PDFSerializer.data(from: pdf)), workspace, fingerprintID, members)
    }
}
