import PDFKit
import XCTest
@testable import Orifold

/// The strings that carry a page label to the screen, in every shipped language.
///
/// These exist because the failure mode is not a wrong pixel, it is a crash or
/// a silently dropped argument: `L10n.format` is `String(format:arguments:)`
/// over `CVarArg`, so a `%lld` slot fed a Swift `String` produces garbage or
/// traps, and `ja`/`zh-Hans` reorder placeholders relative to `en`.
@MainActor
final class PageLabelCopyTests: XCTestCase {

    private static let languages = ["en", "es", "fr", "hi", "ja", "zh-Hans"]

    func testSearchCaptionWithSourceLabelKeepsBothArgumentsInEveryLanguage() throws {
        for language in Self.languages {
            let rendered = L10n.format(
                "search.pageLabelWithSource",
                "31", "A-7",
                locale: Locale(identifier: language)
            )
            XCTAssertTrue(
                rendered.contains("31"),
                "\(language): lost the workspace position — rendered \"\(rendered)\""
            )
            XCTAssertTrue(
                rendered.contains("A-7"),
                "\(language): lost the source label — rendered \"\(rendered)\""
            )
            XCTAssertFalse(
                rendered.contains("%"),
                "\(language): unconsumed format specifier — rendered \"\(rendered)\""
            )

            // Presence alone would still pass if the two %@ slots were swapped,
            // which is the live hazard: ja and zh-Hans reorder placeholders
            // relative to en, so a translator can silently invert them. Every
            // shipped translation puts the position first.
            let positionAt = try XCTUnwrap(rendered.range(of: "31"), "\(language)").lowerBound
            let labelAt = try XCTUnwrap(rendered.range(of: "A-7"), "\(language)").lowerBound
            XCTAssertLessThan(
                positionAt, labelAt,
                "\(language): arguments are swapped — rendered \"\(rendered)\""
            )
        }
    }

    func testSearchCaptionWithoutSourceLabelStillAcceptsAStringPosition() {
        for language in Self.languages {
            let rendered = L10n.format(
                "search.pageLabel",
                "31",
                locale: Locale(identifier: language)
            )
            XCTAssertTrue(rendered.contains("31"), "\(language): rendered \"\(rendered)\"")
            XCTAssertFalse(rendered.contains("%"), "\(language): rendered \"\(rendered)\"")
        }
    }

    func testPageBarSourceLabelSuffixKeepsItsArgumentInEveryLanguage() {
        for language in Self.languages {
            let rendered = L10n.format(
                "readingCanvas.pageBar.sourceLabel",
                "iii",
                locale: Locale(identifier: language)
            )
            XCTAssertTrue(rendered.contains("iii"), "\(language): rendered \"\(rendered)\"")
            XCTAssertFalse(rendered.contains("%"), "\(language): rendered \"\(rendered)\"")
        }
    }

    /// The value the page bar actually binds to, as opposed to the string it
    /// wraps that value in.
    func testCurrentPageSourceLabelTracksTheReaderPosition() throws {
        let viewModel = makeViewModel(fixture("page-labels.pdf"))

        viewModel.currentPageNumber = 1
        XCTAssertEqual(viewModel.currentPageSourceLabel, "i")

        viewModel.currentPageNumber = 4
        XCTAssertEqual(viewModel.currentPageSourceLabel, "A-7")
    }

    func testCurrentPageSourceLabelIsNilForADocumentWithoutLabels() {
        let viewModel = makeViewModel(fixture("no-page-labels.pdf"))

        viewModel.currentPageNumber = 1
        XCTAssertNil(viewModel.currentPageSourceLabel)
    }

    // MARK: - Fixtures

    private func fixture(_ name: String) -> Data {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(name)")
        // swiftlint:disable:next force_try
        return try! Data(contentsOf: url)
    }

    private func makeViewModel(_ memberData: Data) -> WorkspaceViewModel {
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
}
