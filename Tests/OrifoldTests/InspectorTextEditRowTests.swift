import PDFKit
import XCTest
@testable import Orifold

/// WP-7: the inspector Text Edits list items carry a correct edit KIND (insertion /
/// deletion / style-only / edit) and stable per-page ordering, so multiple edits on the
/// same page stay distinguishable with clear labels.
final class InspectorTextEditRowTests: XCTestCase {
    private func makeViewModel() throws -> WorkspaceViewModel {
        let data = EditingFixturePDFBuilder.makePDF(runs: [
            .init(string: "First editable line here", origin: CGPoint(x: 72, y: 720), fontSize: 12),
            .init(string: "Second editable line here", origin: CGPoint(x: 72, y: 690), fontSize: 12),
            .init(string: "Third editable line here", origin: CGPoint(x: 72, y: 660), fontSize: 12)
        ])
        let wrapper = FileWrapper(regularFileWithContents: data)
        wrapper.preferredFilename = "Rows.pdf"
        let document = try WorkspaceDocument(testingFile: wrapper, contentType: .pdf, filename: "Rows.pdf")
        return WorkspaceViewModel(document: document, processingEngine: PDFiumProcessingEngine())
    }

    private func blocks(_ viewModel: WorkspaceViewModel) throws -> [EditableTextBlock] {
        let data = try XCTUnwrap(viewModel.document.memberPDFData.values.first)
        let page = try XCTUnwrap(viewModel.loadedPDFs.first?.1.page(at: 0))
        return PDFTextAnalysisEngine().analyze(data: data, pageIndex: 0, pageRefID: UUID(), fallbackPage: page).blocks
    }

    func testEditKindsAndOrderingAreDerivedCorrectly() throws {
        let viewModel = try makeViewModel()
        let ref = try XCTUnwrap(viewModel.document.workspace.pageOrder.first)
        let all = try blocks(viewModel)
        let first = try XCTUnwrap(all.first { $0.text.contains("First") })
        let second = try XCTUnwrap(all.first { $0.text.contains("Second") })
        let third = try XCTUnwrap(all.first { $0.text.contains("Third") })

        // An ordinary text change.
        _ = viewModel.applyInlineTextEdit(pageRef: ref, sourceBlock: first, replacementText: "First CHANGED line",
            editedBounds: first.bounds, fontName: first.fontName, fontSize: first.fontSize, textColor: .black, alignment: .left)
        // A deletion (empty replacement).
        _ = viewModel.applyInlineTextEdit(pageRef: ref, sourceBlock: second, replacementText: "",
            editedBounds: second.bounds, fontName: second.fontName, fontSize: second.fontSize, textColor: .black, alignment: .left)
        // A style-only change (same text, different color, flagged as manual style change).
        _ = viewModel.applyInlineTextEdit(pageRef: ref, sourceBlock: third, replacementText: third.text,
            editedBounds: third.bounds, fontName: third.fontName, fontSize: third.fontSize, textColor: .red, alignment: .left,
            didManuallyChangeStyle: true)

        let items = viewModel.inlineTextEditListItems()
        XCTAssertEqual(items.count, 3)
        let byOriginal = Dictionary(uniqueKeysWithValues: items.map { ($0.originalText.prefix(5).description, $0) })
        XCTAssertEqual(byOriginal["First"]?.kind, .edit)
        XCTAssertEqual(byOriginal["Secon"]?.kind, .deletion)
        XCTAssertEqual(byOriginal["Third"]?.kind, .styleOnly)

        // All three are on the same page → totalOnPage == 3 and order 1...3 distinct.
        XCTAssertTrue(items.allSatisfy { $0.totalOnPage == 3 })
        XCTAssertEqual(Set(items.map(\.orderOnPage)), [1, 2, 3])
    }
}
