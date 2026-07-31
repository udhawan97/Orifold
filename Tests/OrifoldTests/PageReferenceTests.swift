import PDFKit
import XCTest
@testable import Orifold

/// The single source of truth for "what number does this page carry?".
/// Position is always the workspace ordinal; the source label rides along only
/// when the owning member genuinely has a /PageLabels tree AND the label says
/// something the position does not already say.
@MainActor
final class PageReferenceTests: XCTestCase {

    func testSurfacesSourceLabelWhenMemberCarriesPageLabels() throws {
        let viewModel = makeViewModel(members: [labeledFixture()])
        let page = try XCTUnwrap(viewModel.combinedPDF.page(at: 1))

        let reference = try XCTUnwrap(viewModel.pageReference(for: page, in: viewModel.combinedPDF))

        XCTAssertEqual(reference.position, 1)
        XCTAssertEqual(reference.label, "i")
    }

    func testSuppressesLabelWhenMemberHasNoPageLabels() throws {
        let viewModel = makeViewModel(members: [unlabeledFixture()])
        let page = try XCTUnwrap(viewModel.combinedPDF.page(at: 1))

        let reference = try XCTUnwrap(viewModel.pageReference(for: page, in: viewModel.combinedPDF))

        XCTAssertEqual(reference.position, 1)
        XCTAssertNil(reference.label, "PDFKit synthesizes \"1\" here; the gate must reject it")
    }

    /// A document that DOES carry /PageLabels, but whose labels are plain
    /// decimals identical to the position. The gate opens; the equality rule
    /// must then close it, so the page bar does not render "3 · 3".
    func testSuppressesLabelWhenItMatchesTheWorkspacePosition() throws {
        let viewModel = makeViewModel(members: [decimalLabeledFixture()])

        XCTAssertTrue(
            QPDFService.hasPageLabels(decimalLabeledFixture()),
            "precondition: this fixture really does carry a number tree"
        )

        for combinedIndex in 1...4 {
            let page = try XCTUnwrap(viewModel.combinedPDF.page(at: combinedIndex))
            let reference = try XCTUnwrap(viewModel.pageReference(for: page, in: viewModel.combinedPDF))
            XCTAssertEqual(reference.position, combinedIndex)
            XCTAssertNil(
                reference.label,
                "label \"\(combinedIndex)\" says nothing the position does not already say"
            )
        }
    }

    func testResolvesEachPageAgainstItsOwnMemberInAMergedWorkspace() throws {
        let viewModel = makeViewModel(members: [labeledFixture(), unlabeledFixture()])

        // Member A page 1 -> workspace position 1, labelled "i".
        let first = try XCTUnwrap(viewModel.combinedPDF.page(at: 1))
        let firstReference = try XCTUnwrap(viewModel.pageReference(for: first, in: viewModel.combinedPDF))
        XCTAssertEqual(firstReference.position, 1)
        XCTAssertEqual(firstReference.label, "i")

        // Member B page 1 -> workspace position 5, no labels at all.
        // Combined layout: [banner, A1...A4, banner, B1...B4] -> index 6.
        let second = try XCTUnwrap(viewModel.combinedPDF.page(at: 6))
        let secondReference = try XCTUnwrap(viewModel.pageReference(for: second, in: viewModel.combinedPDF))
        XCTAssertEqual(secondReference.position, 5)
        XCTAssertNil(secondReference.label, "member B has no /PageLabels; its synthesized \"1\" must not leak")
    }

    func testReturnsNilForBoundaryPages() throws {
        let viewModel = makeViewModel(members: [labeledFixture()])
        let banner = try XCTUnwrap(viewModel.combinedPDF.page(at: 0))

        XCTAssertTrue(banner is BoundaryPage, "index 0 is expected to be the member banner")
        XCTAssertNil(viewModel.pageReference(for: banner, in: viewModel.combinedPDF))
    }

    // MARK: - Fixtures

    private func labeledFixture() -> Data { fixture("page-labels.pdf") }
    private func decimalLabeledFixture() -> Data { fixture("page-labels-decimal.pdf") }
    private func unlabeledFixture() -> Data { fixture("no-page-labels.pdf") }

    private func fixture(_ name: String) -> Data {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(name)")
        // swiftlint:disable:next force_try
        return try! Data(contentsOf: url)
    }

    /// Builds a workspace holding every page of every supplied member.
    ///
    /// Do not try to build a partial workspace by handing out fewer `PageRef`s
    /// than the member has pages: `PDFKitEngine.concatenate` walks the loaded
    /// `PDFDocument`, not `pageRefs`, so `combinedPDF` would still contain all
    /// of them while `pageCount` counted fewer -- and `WorkspaceViewModel.init`
    /// renormalizes every `sourcePageIndex` to its member-local ordinal anyway.
    private func makeViewModel(members: [Data]) -> WorkspaceViewModel {
        let document = WorkspaceDocument()
        var allRefs: [PageRef] = []
        var memberRecords: [MemberDocument] = []

        for (offset, data) in members.enumerated() {
            var member = MemberDocument(displayName: "Member \(offset)", sourcePDFRef: "member\(offset).pdf")
            let pageCount = PDFDocument(data: data)?.pageCount ?? 0
            let refs = (0..<pageCount).map { PageRef(memberDocId: member.id, sourcePageIndex: $0) }
            member.pageRefs = refs.map(\.id)
            memberRecords.append(member)
            allRefs.append(contentsOf: refs)
            document.memberPDFData[member.id] = data
        }

        document.workspace.documents = memberRecords
        document.workspace.pageOrder = allRefs
        return WorkspaceViewModel(document: document)
    }
}
