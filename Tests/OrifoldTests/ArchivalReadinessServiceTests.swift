import Foundation
import PDFKit
import XCTest
@testable import Orifold

/// Archival-readiness *hints*.
///
/// The framing is load-bearing and these tests exist partly to hold it: every signal here
/// is a cheap introspection result, never a verdict. Real PDF/A validation is hundreds of
/// clauses, so nothing in this feature may claim a document is valid, compliant, or
/// validated — false positives are acceptable precisely because the output is advisory.
final class ArchivalReadinessServiceTests: XCTestCase {

    // MARK: - Core flags

    func testEncryptedDocumentIsFlagged() throws {
        let options = PDFEncryptionOptions(userPassword: "reader", ownerPassword: "owner")
        let encrypted = try PDFEncryptionService.encryptedData(
            from: untaggedFixture(),
            options: options
        )

        let readiness = try XCTUnwrap(ArchivalReadinessService.evaluate(encrypted, password: "reader"))

        XCTAssertTrue(readiness.isEncrypted)
    }

    func testUnencryptedDocumentIsNotFlagged() throws {
        let readiness = try XCTUnwrap(ArchivalReadinessService.evaluate(untaggedFixture()))

        XCTAssertFalse(readiness.isEncrypted)
    }

    func testJavaScriptAndAutoActionsCountAsActiveContent() throws {
        let readiness = try XCTUnwrap(ArchivalReadinessService.evaluate(activeContentFixture()))

        XCTAssertTrue(readiness.hasActiveContent)
    }

    func testCleanDocumentHasNoActiveContent() throws {
        let readiness = try XCTUnwrap(ArchivalReadinessService.evaluate(untaggedFixture()))

        XCTAssertFalse(readiness.hasActiveContent)
    }

    func testXMPMetadataIsDetected() throws {
        XCTAssertTrue(try XCTUnwrap(ArchivalReadinessService.evaluate(xmpFixture())).hasXMPMetadata)
        XCTAssertFalse(try XCTUnwrap(ArchivalReadinessService.evaluate(untaggedFixture())).hasXMPMetadata)
    }

    func testTaggedDocumentIsDetected() throws {
        XCTAssertTrue(try XCTUnwrap(ArchivalReadinessService.evaluate(taggedFixture())).isTagged)
        XCTAssertFalse(try XCTUnwrap(ArchivalReadinessService.evaluate(untaggedFixture())).isTagged)
    }

    // MARK: - Font embedding

    /// A base-14 font reference with no FontDescriptor is not embedded. PDF/A requires
    /// even Helvetica to be embedded, so flagging it is correct rather than pedantic —
    /// that is exactly the kind of thing archival readiness is for.
    func testUnembeddedBaseFourteenFontIsFlagged() throws {
        let readiness = try XCTUnwrap(ArchivalReadinessService.evaluate(untaggedFixture()))

        XCTAssertFalse(readiness.allFontsEmbedded)
    }

    /// A page referencing no fonts is vacuously fine — there is nothing unembedded on it.
    func testPageWithNoFontsCountsAsEmbedded() throws {
        let readiness = try XCTUnwrap(ArchivalReadinessService.evaluate(outputIntentFixture()))

        XCTAssertTrue(readiness.allFontsEmbedded)
    }

    // MARK: - Output intent

    func testOutputIntentIsDetected() throws {
        XCTAssertTrue(try XCTUnwrap(ArchivalReadinessService.evaluate(outputIntentFixture())).hasOutputIntent)
        XCTAssertFalse(try XCTUnwrap(ArchivalReadinessService.evaluate(untaggedFixture())).hasOutputIntent)
    }

    // MARK: - Failure modes

    func testUnreadableBytesYieldNilRatherThanAllClear() {
        // Returning a default-constructed all-green result for garbage would be the worst
        // possible failure mode for an advisory panel.
        XCTAssertNil(ArchivalReadinessService.evaluate(Data("not a pdf".utf8)))
    }

    // MARK: - View-model accessor

    @MainActor
    func testActiveMemberDataIsTheDocumentTheReaderIsLookingAt() throws {
        let viewModel = makeViewModel(memberData: taggedFixture())

        let data = try XCTUnwrap(viewModel.activeMemberDataForArchivalReadiness())

        XCTAssertTrue(try XCTUnwrap(ArchivalReadinessService.evaluate(data)).isTagged)
    }

    @MainActor
    func testActiveMemberDataIsNilForAnEmptyWorkspace() {
        let viewModel = WorkspaceViewModel(document: WorkspaceDocument())

        XCTAssertNil(viewModel.activeMemberDataForArchivalReadiness())
    }

    @MainActor
    private func makeViewModel(memberData: Data) -> WorkspaceViewModel {
        let document = WorkspaceDocument()
        var member = MemberDocument(displayName: "Fixture", sourcePDFRef: "fixture.pdf")
        let pageCount = PDFDocument(data: memberData)?.pageCount ?? 0
        let refs = (0..<pageCount).map { PageRef(memberDocId: member.id, sourcePageIndex: $0) }
        member.pageRefs = refs.map(\.id)
        document.workspace.documents = [member]
        document.workspace.pageOrder = refs
        document.memberPDFData[member.id] = memberData
        return WorkspaceViewModel(document: document)
    }

    // MARK: - Fixtures

    private func fixture(_ name: String) -> Data {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(name)")
        // swiftlint:disable:next force_try
        return try! Data(contentsOf: url)
    }

    private func taggedFixture() -> Data { fixture("tagged-sample.pdf") }
    private func untaggedFixture() -> Data { fixture("untagged-sample.pdf") }
    private func activeContentFixture() -> Data { fixture("active-content.pdf") }
    private func outputIntentFixture() -> Data { fixture("output-intent.pdf") }
    private func xmpFixture() -> Data { fixture("xmp-metadata.pdf") }
}
