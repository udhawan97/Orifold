import PDFKit
import XCTest
@testable import Orifold

@MainActor
final class RestoredPageIdentityTests: XCTestCase {
    private enum Malformation: CaseIterable {
        case swappedGlobalOrder
        case swappedMemberOrder
        case tooFewMemberPages
        case tooManyMemberPages
        case missingMemberPayload
        case unreadableMemberPayload
        case lockedMemberPayload
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
            for malformation in Malformation.allCases {
                let directory = try disposableDirectory()
                defer { try? FileManager.default.removeItem(at: directory) }
                let fixture = try editableFixture(legacy: legacy, malformation: malformation)
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
    }

    func testAbsentEditableMemberBytesKeepTheExistingFlatImportFallback() throws {
        for legacy in [false, true] {
            let directory = try disposableDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let fixture = try editableFixture(legacy: legacy, omitAllMemberPayloads: true)
            let url = directory.appendingPathComponent("no-editable-members.pdf")
            try fixture.file.write(to: url)
            let document = try WorkspaceDocument(testingFile: FileWrapper(url: url, options: []),
                contentType: .pdf, fingerprintStore: WorkspaceFingerprintStore(directory: directory))
            XCTAssertFalse(document.externalModificationDetected)
            XCTAssertNotEqual(document.workspace.id, fixture.workspace.id)
            XCTAssertEqual(document.workspace.documents.count, 1)
            XCTAssertEqual(document.workspace.pageOrder.count, 1)
            XCTAssertEqual(document.workspace.documents[0].pageRefs, document.workspace.pageOrder.map(\.id))
            let bytes = try XCTUnwrap(document.memberPDFData[document.workspace.documents[0].id])
            XCTAssertEqual(PDFDocument(data: bytes)?.pageCount, 1)
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

                let saved = try document.savedFileWrapper(from: document.snapshot(contentType: .pdf))
                let reopened = try WorkspaceDocument(testingFile: saved, contentType: .pdf, fingerprintStore: store)
                XCTAssertFalse(reopened.externalModificationDetected)
                XCTAssertEqual(reopened.workspace.id, fixture.workspace.id)
                XCTAssertEqual(reopened.workspace.pageOrder.map(\.id), document.workspace.pageOrder.map(\.id))
                XCTAssertEqual(reopened.workspace.pageOrder.map(\.memberDocId), document.workspace.pageOrder.map(\.memberDocId))
                XCTAssertEqual(reopened.workspace.pageOrder.map(\.sourcePageIndex), document.workspace.pageOrder.map(\.sourcePageIndex))
                XCTAssertEqual(reopened.memberPDFData, fixture.members)
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

    private func editableFixture(legacy: Bool, malformation: Malformation? = nil,
                                 omitAllMemberPayloads: Bool = false) throws ->
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
        case .swappedGlobalOrder:
            workspace.pageOrder = [thirdPage, firstPage, secondPage]
        case .swappedMemberOrder:
            workspace.documents[0].pageRefs.reverse()
        case .tooFewMemberPages, .tooManyMemberPages, .missingMemberPayload,
             .unreadableMemberPayload, .lockedMemberPayload:
            break
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
        let firstPageCount = malformation == .tooFewMemberPages ? 1 : (malformation == .tooManyMemberPages ? 3 : 2)
        var members = [first.id: try blankPDF(pageCount: firstPageCount), second.id: try blankPDF(pageCount: 1)]
        if malformation == .missingMemberPayload { members.removeValue(forKey: first.id) }
        if malformation == .unreadableMemberPayload { members[first.id] = Data("unreadable fictional PDF".utf8) }
        if malformation == .lockedMemberPayload {
            let encrypted = try PDFEncryptionService.encryptedData(from: XCTUnwrap(members[first.id]),
                options: PDFEncryptionOptions(userPassword: "fictional-user", ownerPassword: "fictional-owner"))
            XCTAssertTrue(try XCTUnwrap(PDFDocument(data: encrypted)).isLocked)
            members[first.id] = encrypted
        }
        if omitAllMemberPayloads { members.removeAll() }
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
