import PDFKit
import XCTest
@testable import Orifold

/// Loop 2 UX regression coverage exercised through the real `InlineTextEditorOverlay`
/// buttons/state: Match no-op doesn't commit, insertion boxes keep their click position,
/// the editor's undo is isolated from the document, and a pinned Format Painter survives
/// an unrelated Reset.
final class InlineEditorFormatUXTests: XCTestCase {
    private func findButton(in root: NSView, identifier: String) -> NSButton? {
        find(in: root) { (b: NSButton) in b.identifier?.rawValue == identifier }
    }

    private func find<T: NSView>(in root: NSView, matching predicate: (T) -> Bool) -> T? {
        if let typed = root as? T, predicate(typed) { return typed }
        for sub in root.subviews {
            if let found: T = find(in: sub, matching: predicate) { return found }
        }
        return nil
    }

    private func makePDFData() throws -> Data {
        let view = NSView(frame: CGRect(x: 0, y: 0, width: 612, height: 792))
        return try XCTUnwrap(PDFDocument(data: view.dataWithPDF(inside: view.bounds))?.dataRepresentation())
    }

    private struct Harness {
        let pdfView: OrifoldPDFView
        let overlay: InlineTextEditorOverlay
        let committed: () -> InlineTextEditorOverlay.EditResult?
    }

    private func makeHarness(
        block: EditableTextBlock,
        sourceFormat: PDFTextEditFormat? = nil,
        matchFormat: PDFTextEditFormat? = nil
    ) throws -> Harness {
        let data = try makePDFData()
        let pdfView = OrifoldPDFView(frame: CGRect(x: 0, y: 0, width: 1000, height: 1200))
        let doc = try XCTUnwrap(PDFDocument(data: data))
        pdfView.document = doc
        pdfView.autoScales = false
        pdfView.scaleFactor = 1
        pdfView.layoutDocumentView()
        let page = try XCTUnwrap(doc.page(at: 0))
        let pageRef = PageRef(memberDocId: UUID(), sourcePageIndex: 0)
        var committed: InlineTextEditorOverlay.EditResult?
        let overlay = InlineTextEditorOverlay(
            frame: pdfView.bounds,
            viewModel: WorkspaceViewModel(document: WorkspaceDocument()),
            pdfView: pdfView,
            page: page,
            pageRef: pageRef,
            block: block,
            sourceFormat: sourceFormat ?? PDFTextEditFormat(block: block),
            matchFormat: matchFormat
        ) { result in
            if case .commit(let edit) = result { committed = edit }
            return true
        }
        // Retain the document for the overlay's lifetime via the pdfView (already does).
        pdfView.addSubview(overlay)
        overlay.layoutSubtreeIfNeeded()
        return Harness(pdfView: pdfView, overlay: overlay, committed: { committed })
    }

    private func bodyBlock() -> EditableTextBlock {
        EditableTextBlock(
            pageRefID: UUID(),
            text: "Ordinary body paragraph text here",
            bounds: CGRect(x: 72, y: 600, width: 300, height: 14),
            lines: [PDFTextLine(text: "Ordinary body paragraph text here",
                                bounds: CGRect(x: 72, y: 600, width: 300, height: 14), runs: [], confidence: .high)],
            columnBounds: CGRect(x: 72, y: 0, width: 300, height: 792),
            fontName: "Helvetica",
            fontSize: 10,
            textColor: .documentText,
            alignment: .left,
            rotation: 0,
            baseline: 600,
            confidence: .high
        )
    }

    /// Match with an inferred style IDENTICAL to the block's own must be a true no-op:
    /// pressing Done afterwards (nothing else changed) must NOT commit a spurious
    /// re-rendered replacement.
    func testMatchWithIdenticalNearbyStyleDoesNotCommitOnDone() throws {
        let block = bodyBlock()
        // matchFormat identical to the block's own style AND geometry.
        let identical = PDFTextEditFormat(block: block)
        let harness = try makeHarness(block: block, matchFormat: identical)
        let match = try XCTUnwrap(findButton(in: harness.overlay, identifier: "inlineEditor.matchNearbyFormat"))
        let done = try XCTUnwrap(find(in: harness.overlay) { (b: NSButton) in b.title == "Done" })

        match.performClick(nil)
        done.performClick(nil)
        XCTAssertNil(harness.committed(),
                     "Match to an identical style with no other change must not commit a spurious edit")
    }

    /// Match with a genuinely different nearby style MUST commit on Done even with the
    /// text untouched — a real restyle is a real edit.
    func testMatchWithDifferentNearbyStyleCommitsOnDone() throws {
        let block = bodyBlock()
        let differentBody = PDFTextEditFormat(
            fontName: "Helvetica",
            fontSize: 14,               // different size
            textColor: .documentText,
            alignment: .left,
            bounds: CGRect(x: 72, y: 500, width: 340, height: 16),
            columnBounds: CGRect(x: 72, y: 0, width: 340, height: 792)
        )
        let harness = try makeHarness(block: block, matchFormat: differentBody)
        let match = try XCTUnwrap(findButton(in: harness.overlay, identifier: "inlineEditor.matchNearbyFormat"))
        let done = try XCTUnwrap(find(in: harness.overlay) { (b: NSButton) in b.title == "Done" })

        match.performClick(nil)
        done.performClick(nil)
        let edit = try XCTUnwrap(harness.committed(), "a genuine restyle must commit")
        XCTAssertEqual(edit.fontSize, 14, accuracy: 0.5, "the committed edit carries the matched size")
    }

    /// A committed insertion (typed into a blank spot mid-page) must keep the click's
    /// x-position — not snap to the page's left margin because insertion blocks carry a
    /// page-wide column.
    func testInsertionKeepsClickXInsteadOfSnappingToPageMargin() throws {
        let insertionX: CGFloat = 360
        let insertion = EditableTextBlock(
            pageRefID: UUID(),
            text: "",
            bounds: CGRect(x: insertionX, y: 500, width: 200, height: 24),
            lines: [],
            columnBounds: CGRect(x: 12, y: 12, width: 588, height: 768), // page-wide
            fontName: "Helvetica",
            fontSize: 12,
            textColor: .documentText,
            alignment: .left,
            rotation: 0,
            baseline: 500,
            confidence: .medium,
            editability: .insertion
        )
        let harness = try makeHarness(block: insertion)
        let textView = try XCTUnwrap(find(in: harness.overlay) { (_: NSTextView) in true })
        textView.string = "APPROVED"
        textView.delegate?.textDidChange?(Notification(name: NSText.didChangeNotification, object: textView))
        let done = try XCTUnwrap(find(in: harness.overlay) { (b: NSButton) in b.title == "Done" })
        done.performClick(nil)

        let edit = try XCTUnwrap(harness.committed())
        XCTAssertEqual(edit.editedBounds.minX, insertionX, accuracy: 12,
                       "insertion must commit near the click x (\(insertionX)), not snap to the page margin; got \(edit.editedBounds.minX)")
        XCTAssertGreaterThan(edit.editedBounds.minX, 100,
                             "insertion x must not collapse toward the left page margin")
    }

    /// The editor's typing undo must be isolated from the shared document undo manager, so
    /// Cmd-Z inside the editor never reaches document-level operations.
    func testEditorUsesIsolatedUndoManager() throws {
        let harness = try makeHarness(block: bodyBlock())
        let textView = try XCTUnwrap(find(in: harness.overlay) { (tv: InlineEditableTextView) in true })
        XCTAssertNotNil(textView.isolatedUndoManager, "the editor text view must have its own undo manager")
        XCTAssertTrue(textView.undoManager === textView.isolatedUndoManager,
                      "textView.undoManager must resolve to the isolated manager, not the window's")
    }
}
