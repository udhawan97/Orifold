import Foundation
import PDFKit
import XCTest
@testable import Orifold

/// Read-only tagged-PDF structure inspection.
///
/// Fixtures are hand-authored raw PDF bytes (`Fixtures/make-tagged-fixtures.py`) because
/// PDFKit cannot emit a structure tree and nothing else in the repo writes tags. They are
/// loaded `#filePath`-relative, mirroring `LocalizationCoverageTests`, so neither manifest
/// needs a test-resource entry.
final class StructureInspectionServiceTests: XCTestCase {

    // MARK: - Tree shape

    func testTaggedFixtureYieldsItsDocumentWrapperAndRoles() throws {
        let structure = try StructureInspectionService.inspect(taggedFixture(), pageIndex: 0)

        XCTAssertTrue(structure.isTagged)
        let roles = flatten(structure.roots).map(\.role)
        XCTAssertEqual(roles, ["Document", "H1", "P", "Figure"])
    }

    func testElementTitleAndAltTextAreRead() throws {
        let structure = try StructureInspectionService.inspect(taggedFixture(), pageIndex: 0)
        let nodes = flatten(structure.roots)

        XCTAssertEqual(nodes.first { $0.role == "H1" }?.title, "Heading One")
        XCTAssertEqual(nodes.first { $0.role == "Figure" }?.altText, "A red rectangle")
        XCTAssertNil(nodes.first { $0.role == "P" }?.title)
    }

    /// The trap this pins: every tagged leaf reports `CountChildren == 1`, but that child
    /// is a marked-content reference (an MCID into the content stream), not a structure
    /// element — `GetChildAtIndex` returns nil for it. A walk that trusts the count
    /// invents phantom children under every heading and paragraph.
    func testMarkedContentReferencesAreNotTreatedAsStructureNodes() throws {
        let structure = try StructureInspectionService.inspect(taggedFixture(), pageIndex: 0)
        let nodes = flatten(structure.roots)

        let heading = try XCTUnwrap(nodes.first { $0.role == "H1" })
        XCTAssertTrue(heading.children.isEmpty)
        XCTAssertEqual(nodes.count, 4, "phantom nodes leaked in from marked-content kids")
    }

    // MARK: - Alt-text tally

    func testFigureWithoutAltTextIsCounted() throws {
        let structure = try StructureInspectionService.inspect(taggedNoAltFixture(), pageIndex: 0)

        XCTAssertEqual(structure.imagesMissingAltText, 1)
    }

    func testFigureWithAltTextIsNotCounted() throws {
        let structure = try StructureInspectionService.inspect(taggedFixture(), pageIndex: 0)

        XCTAssertEqual(structure.imagesMissingAltText, 0)
    }

    // MARK: - Untagged documents

    func testUntaggedFixtureIsFlaggedAndHasNoTree() throws {
        let structure = try StructureInspectionService.inspect(untaggedFixture(), pageIndex: 0)

        XCTAssertFalse(structure.isTagged)
        XCTAssertTrue(structure.roots.isEmpty)
        XCTAssertEqual(structure.imagesMissingAltText, 0)
    }

    func testDocumentIsTaggedReadsTheCatalogNotThePage() throws {
        XCTAssertTrue(StructureInspectionService.documentIsTagged(taggedFixture()))
        XCTAssertFalse(StructureInspectionService.documentIsTagged(untaggedFixture()))
    }

    // MARK: - Failure modes

    func testInvalidBytesThrowRatherThanReturningAnEmptyTree() {
        let garbage = Data("not a pdf".utf8)

        XCTAssertThrowsError(try StructureInspectionService.inspect(garbage, pageIndex: 0)) { error in
            XCTAssertEqual(error as? StructureInspectionError, .invalidPDF)
        }
    }

    func testPageIndexOutOfRangeThrows() throws {
        XCTAssertThrowsError(
            try StructureInspectionService.inspect(taggedFixture(), pageIndex: 99)
        ) { error in
            XCTAssertEqual(error as? StructureInspectionError, .pageOutOfRange)
        }
    }

    func testDocumentIsTaggedReturnsFalseForUnreadableBytesRatherThanThrowing() {
        XCTAssertFalse(StructureInspectionService.documentIsTagged(Data("nope".utf8)))
    }

    // MARK: - View-model accessor

    @MainActor
    func testCurrentPageStructureReadsTheActivePageOfTheActiveMember() throws {
        let viewModel = makeViewModel(memberData: taggedFixture())
        viewModel.currentPageNumber = 1

        let structure = try XCTUnwrap(viewModel.currentPageStructure())

        XCTAssertTrue(structure.isTagged)
        XCTAssertEqual(flatten(structure.roots).map(\.role), ["Document", "H1", "P", "Figure"])
    }

    @MainActor
    func testCurrentPageStructureIsNilWhenTheWorkspaceHasNoPages() {
        let viewModel = WorkspaceViewModel(document: WorkspaceDocument())

        XCTAssertNil(viewModel.currentPageStructure())
    }

    @MainActor
    func testCurrentPageStructureFlagsAnUntaggedMember() throws {
        let viewModel = makeViewModel(memberData: untaggedFixture())
        viewModel.currentPageNumber = 1

        let structure = try XCTUnwrap(viewModel.currentPageStructure())

        XCTAssertFalse(structure.isTagged)
        XCTAssertTrue(structure.roots.isEmpty)
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
    private func taggedNoAltFixture() -> Data { fixture("tagged-no-alt.pdf") }
    private func untaggedFixture() -> Data { fixture("untagged-sample.pdf") }

    private func flatten(_ nodes: [StructureNode]) -> [StructureNode] {
        nodes.flatMap { [$0] + flatten($0.children) }
    }
}
