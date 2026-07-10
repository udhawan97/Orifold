import PDFKit
import UniformTypeIdentifiers
import XCTest

@testable import Orifold

/// Round 1 of an end-to-end "does the whole pipeline hang together for a casual user"
/// pass: realistic multi-step sequences (import, edit, annotate, sign, export, undo,
/// re-open) driven through the real `WorkspaceViewModel`/`WorkspaceDocument`/PDF-engine
/// stack -- not mocks -- checking for crashes and for clear, actionable error messages.
final class UserFlowRegressionTests: XCTestCase {
    private func makeFlowMemberWithPDF(
        name: String,
        pageTexts: [String]
    ) throws -> (member: MemberDocument, refs: [PageRef], pdfData: Data) {
        let pdf = PDFDocument()
        for (index, text) in pageTexts.enumerated() {
            let view = FlowFixturePageView(frame: CGRect(x: 0, y: 0, width: 612, height: 792), text: text)
            let pageData = view.dataWithPDF(inside: view.bounds)
            guard let pageDocument = PDFDocument(data: pageData), let page = pageDocument.page(at: 0) else {
                throw XCTSkip("fixture page rendering failed")
            }
            pdf.insert(page, at: index)
        }
        var member = MemberDocument(displayName: name, sourcePDFRef: "\(name).pdf")
        let refs = (0..<pdf.pageCount).map { PageRef(memberDocId: member.id, sourcePageIndex: $0) }
        member.pageRefs = refs.map(\.id)
        let pdfData = try XCTUnwrap(pdf.dataRepresentation())
        return (member, refs, pdfData)
    }

    // MARK: - Import: weird/hostile input must fail clearly, never crash

    func testImportingGarbageBytesAsPDFFailsWithClearMessageNotCrash() {
        let garbage = Data("this is not a pdf at all, just some random bytes 12345".utf8)
        do {
            _ = try DocumentImportConverter.importedDocument(from: garbage, contentType: .pdf, filename: "garbage.pdf", baseURL: nil)
            XCTFail("expected garbage bytes to fail import")
        } catch {
            let message = DocumentImportConverter.userMessage(for: error)
            XCTAssertFalse(message.isEmpty)
            XCTAssertFalse(message.contains("couldn’t be completed") || message.contains("couldn't be completed"), "leaked generic Cocoa fallback: '\(message)'")
        }
    }

    func testImportingEmptyFileFailsWithClearMessageNotCrash() {
        do {
            _ = try DocumentImportConverter.importedDocument(from: Data(), contentType: .pdf, filename: "empty.pdf", baseURL: nil)
            XCTFail("expected empty data to fail import")
        } catch {
            let message = DocumentImportConverter.userMessage(for: error)
            XCTAssertEqual(message, L10n.string("error.import.emptyDocument"))
        }
    }

    func testImportingUnsupportedFileTypeFailsWithClearMessage() {
        let bogus = Data([0xDE, 0xAD, 0xBE, 0xEF])
        do {
            _ = try DocumentImportConverter.importedDocument(from: bogus, contentType: UTType(filenameExtension: "xyz123unknown") ?? .data, filename: "mystery.xyz123unknown", baseURL: nil)
        } catch {
            let message = DocumentImportConverter.userMessage(for: error)
            XCTAssertFalse(message.isEmpty)
        }
        // Whatever the outcome (throws or degrades to plain text), it must not crash --
        // reaching this line at all is the assertion.
    }

    // MARK: - Import -> edit -> export -> reopen -> edit again (full round trip)

    /// The realistic "casual user" happy path this whole audit started from: import a
    /// document, click text and replace it, export, reopen the export, and edit it AGAIN.
    /// The second edit is the regression-sensitive part -- it only works if the first
    /// export preserved a real, PDFium-detectable text layer (see
    /// `PDFImportNormalizer` / [[pdfkit-reserialization-destroys-text-layer]]).
    func testImportEditExportReopenEditAgainRoundTrip() throws {
        let fixture = try makeFlowMemberWithPDF(name: "RoundTrip", pageTexts: ["Original confirmation text"])
        let wrapper = FileWrapper(regularFileWithContents: fixture.pdfData)
        wrapper.preferredFilename = "RoundTrip.pdf"
        let document = try WorkspaceDocument(testingFile: wrapper, contentType: .pdf, filename: "RoundTrip.pdf")
        let viewModel = WorkspaceViewModel(document: document, processingEngine: PDFiumProcessingEngine())

        let page = try XCTUnwrap(viewModel.loadedPDFs.first?.1.page(at: 0))
        // `NSString.draw(in:)` top/left-aligns the fixture's text within its draw rect, so
        // its actual bounds sit near the top of the page, not at page center -- locate the
        // real detected block first (as a user's click naturally would land on visible ink)
        // rather than assuming a fixed page-center coordinate.
        let firstAnalysis = PDFTextAnalysisEngine().analyze(data: fixture.pdfData, pageIndex: 0, pageRefID: UUID(), fallbackPage: page)
        let firstBlock = try XCTUnwrap(firstAnalysis.blocks.first { $0.text.contains("Original") })
        let target = try XCTUnwrap(viewModel.editableTextBlock(at: CGPoint(x: firstBlock.bounds.midX, y: firstBlock.bounds.midY), on: page, in: viewModel.combinedPDF))
        XCTAssertEqual(target.block.editability, .direct, "first edit should hit real detected text, not a blank insertion box")

        let firstEditOK = viewModel.applyInlineTextEdit(
            pageRef: target.pageRef,
            sourceBlock: target.block,
            replacementText: "First replacement",
            editedBounds: target.block.bounds,
            fontName: target.block.fontName,
            fontSize: target.block.fontSize,
            textColor: .black,
            alignment: .left
        )
        XCTAssertTrue(firstEditOK)

        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("Orifold-roundtrip-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: outputURL) }
        XCTAssertTrue(viewModel.saveFlattenedPDF(to: outputURL))
        XCTAssertNil(viewModel.exportError)

        let reopenedData = try Data(contentsOf: outputURL)
        let reopenedWrapper = FileWrapper(regularFileWithContents: reopenedData)
        reopenedWrapper.preferredFilename = "RoundTrip.pdf"
        let reopenedDocument = try WorkspaceDocument(testingFile: reopenedWrapper, contentType: .pdf, filename: "RoundTrip.pdf")
        let reopenedViewModel = WorkspaceViewModel(document: reopenedDocument, processingEngine: PDFiumProcessingEngine())
        let reopenedPage = try XCTUnwrap(reopenedViewModel.loadedPDFs.first?.1.page(at: 0))
        // Not `.string`/`.attributedString`: confirmed via a CI-only investigation (Xcode 16.4 /
        // macOS 15, the toolchain pinned in ci.yml) that PDFKit's own CoreText-based extraction
        // undercounts THIS specific reimported page's characters by 2 (`numberOfCharacters` came
        // back 42 on CI vs. 44 locally), trimming the tail of "First replacement" to
        // "First replaceme" even via `.attributedString`. `PDFTextAnalysisEngine` (PDFium-backed,
        // not CoreText) extracted the full, correct text on that same CI run -- it's also what the
        // very next step already needs to locate the block for the second edit, so reuse that
        // analysis here rather than trusting PDFKit's own extractor for this presence check.
        let secondAnalysis = PDFTextAnalysisEngine().analyze(data: reopenedData, pageIndex: 0, pageRefID: UUID(), fallbackPage: reopenedPage)
        XCTAssertTrue(secondAnalysis.blocks.contains { $0.text.contains("First replacement") })
        let secondBlock = try XCTUnwrap(secondAnalysis.blocks.first { $0.text.contains("First replacement") })
        let secondTarget = try XCTUnwrap(reopenedViewModel.editableTextBlock(
            at: CGPoint(x: secondBlock.bounds.midX, y: secondBlock.bounds.midY),
            on: reopenedPage,
            in: reopenedViewModel.combinedPDF
        ))
        XCTAssertEqual(secondTarget.block.editability, .direct, "re-opened export must still be directly editable, not degraded to a blank insertion box")

        let secondEditOK = reopenedViewModel.applyInlineTextEdit(
            pageRef: secondTarget.pageRef,
            sourceBlock: secondTarget.block,
            replacementText: "Second replacement",
            editedBounds: secondTarget.block.bounds,
            fontName: secondTarget.block.fontName,
            fontSize: secondTarget.block.fontSize,
            textColor: .black,
            alignment: .left
        )
        XCTAssertTrue(secondEditOK)
        let finalData = try XCTUnwrap(reopenedViewModel.document.memberPDFData.values.first)
        let finalPage = try XCTUnwrap(PDFDocument(data: finalData)?.page(at: 0))
        // The visible/rendered outcome is what a user actually judges "did my edit work?"
        // by -- confirm the new text renders and the erase patch visually covers the old
        // ink (see `testEraseIsVisualOnlyNotContentStreamRemoval` for the separate, known
        // limitation that the ORIGINAL text remains structurally present/extractable
        // underneath, which `.string` would otherwise make this assertion misleading about).
        // Not `.string` here either, for the same CI-only PDFKit extraction-undercount
        // reason documented above at the first reopen -- use the same PDFium-backed
        // analysis for consistency instead of trusting PDFKit's own extractor.
        let finalAnalysis = PDFTextAnalysisEngine().analyze(data: finalData, pageIndex: 0, pageRefID: UUID(), fallbackPage: finalPage)
        XCTAssertTrue(finalAnalysis.blocks.contains { $0.text.contains("Second replacement") })
    }

    /// Documents a real, pre-existing limitation surfaced while building the round-trip
    /// flow test above: `PDFEditedPageRenderer` preserves the ORIGINAL page's content
    /// stream verbatim as the new page's background (via `CGContext.drawPDFPage`, which
    /// embeds the source page's own vector drawing operators, not a rasterized copy) and
    /// then draws an opaque erase-patch rectangle plus the replacement text ON TOP of it.
    /// The result LOOKS correctly edited (confirmed by rendering the page to an image),
    /// but the pre-edit text's own drawing operators are still present in the output PDF's
    /// content stream underneath the patch, so `PDFPage.string`, copy/paste selection,
    /// full-text search, and accessibility tools can all still see the ORIGINAL text a
    /// user believed they replaced. This is a real risk for anyone editing out sensitive
    /// values (a price, an ID, a name) expecting the old value to be gone, not just hidden.
    /// Not a regression from this session's changes (confirmed pre-existing in
    /// `PDFEditedPageRenderer`, unrelated to the PDFImportNormalizer work); flagged for a
    /// follow-up rather than fixed here, since a real fix means content-stream-level
    /// surgery (removing/clipping the original text operators for the erased region) --
    /// a substantially larger, higher-risk change than this pass's scope.
    func testEraseIsVisualOnlyNotContentStreamRemoval() throws {
        let fixture = try makeFlowMemberWithPDF(name: "EraseScope", pageTexts: ["Sensitive original value"])
        let document = WorkspaceDocument()
        document.workspace.documents = [fixture.member]
        document.workspace.pageOrder = fixture.refs
        document.memberPDFData[fixture.member.id] = fixture.pdfData
        let viewModel = WorkspaceViewModel(document: document, processingEngine: PDFiumProcessingEngine())

        let page = try XCTUnwrap(viewModel.loadedPDFs.first?.1.page(at: 0))
        let analysis = PDFTextAnalysisEngine().analyze(data: fixture.pdfData, pageIndex: 0, pageRefID: UUID(), fallbackPage: page)
        let block = try XCTUnwrap(analysis.blocks.first { $0.text.contains("Sensitive") })
        let target = try XCTUnwrap(viewModel.editableTextBlock(at: CGPoint(x: block.bounds.midX, y: block.bounds.midY), on: page, in: viewModel.combinedPDF))

        XCTAssertTrue(viewModel.applyInlineTextEdit(
            pageRef: target.pageRef,
            sourceBlock: target.block,
            replacementText: "Redacted",
            editedBounds: target.block.bounds,
            fontName: target.block.fontName,
            fontSize: target.block.fontSize,
            textColor: .black,
            alignment: .left
        ))

        // Neither `.string` nor `.attributedString`: this page has the replacement sitting
        // exactly where the still-present (visually-covered-only) original text is, and
        // both PDFKit extraction paths were confirmed unreliable for this exact overlapping-
        // runs shape on CI's pinned Xcode 16.4/macOS 15 toolchain -- `.string` interleaved
        // character order (" RSednsaictitveedoriginal value\n ", the same characters shuffled
        // together), and on a later CI run `.attributedString` came back empty/without either
        // substring instead. `PDFTextAnalysisEngine` (PDFium-backed, reads the content
        // stream's own text-showing operators directly rather than CoreText's glyph-position
        // reconstruction) is the same fix already applied to this exact class of bug in
        // `testImportEditExportReopenEditAgainRoundTrip` above, and was independently
        // confirmed locally (see the Find & Replace body-text test suite) to correctly
        // surface BOTH an original and a visually-overlapping replacement run rather than
        // merging or dropping either.
        let editedData = try XCTUnwrap(viewModel.document.memberPDFData[fixture.member.id])
        let editedPage = try XCTUnwrap(PDFDocument(data: editedData)?.page(at: 0))
        let editedAnalysis = PDFTextAnalysisEngine().analyze(data: editedData, pageIndex: 0, pageRefID: UUID(), fallbackPage: editedPage)
        let editedText = editedAnalysis.blocks.map(\.text).joined(separator: " ")
        XCTAssertTrue(editedText.contains("Redacted"), "the replacement text should be present")
        // KNOWN LIMITATION (see doc comment above): the original value remains
        // structurally present even though it is visually covered. If this assertion ever
        // starts failing because the original is gone, the underlying erase mechanism has
        // become a real structural removal -- update this test's expectation (and the doc
        // comment) to match, rather than treating that as a regression.
        XCTAssertTrue(editedText.contains("Sensitive original value"), "documents that the pre-edit text remains extractable beneath the visual erase patch")
    }

    // MARK: - Annotate, comment, undo/redo sequence

    func testCommentAddEditUndoRedoSequenceStaysConsistent() throws {
        let fixture = try makeFlowMemberWithPDF(name: "Commented", pageTexts: ["Body text"])
        let document = WorkspaceDocument()
        document.workspace.documents = [fixture.member]
        document.workspace.pageOrder = fixture.refs
        document.memberPDFData[fixture.member.id] = fixture.pdfData
        let viewModel = WorkspaceViewModel(document: document)
        let undoManager = UndoManager()
        // `groupsByEvent` (the default) groups every `registerUndo` call made in the same
        // call stack with no run-loop turn between them into ONE undo group -- in a real
        // app each comment-add is its own AppKit event so this never bites a real user,
        // but a synchronous test needs explicit grouping to isolate each action (same
        // pattern as `testRotateUndoResolvesPageAfterInlineEditRestore` in OrifoldTests.swift).
        undoManager.groupsByEvent = false
        viewModel.undoManager = undoManager

        undoManager.beginUndoGrouping()
        viewModel.addComment("First comment")
        undoManager.endUndoGrouping()
        XCTAssertEqual(document.workspace.comments.count, 1)

        undoManager.beginUndoGrouping()
        viewModel.addComment("Second comment")
        undoManager.endUndoGrouping()
        XCTAssertEqual(document.workspace.comments.count, 2)

        undoManager.undo()
        XCTAssertEqual(document.workspace.comments.count, 1, "undo should remove exactly the most recent comment")

        undoManager.redo()
        XCTAssertEqual(document.workspace.comments.count, 2, "redo should restore it")
    }

    // MARK: - Signing: no certificate placed yet

    @MainActor
    func testSigningWithNoCertificatePlacedShowsClearMessageNotCrash() throws {
        let fixture = try makeFlowMemberWithPDF(name: "Unsigned", pageTexts: ["Sign me"])
        let document = WorkspaceDocument()
        document.workspace.documents = [fixture.member]
        document.workspace.pageOrder = fixture.refs
        document.memberPDFData[fixture.member.id] = fixture.pdfData
        let viewModel = WorkspaceViewModel(document: document)

        viewModel.signAndExportCryptographicPDF(timestampRequested: false)

        // No crash reaching this line is the primary assertion; the secondary one is that
        // SOME clear status/error was surfaced rather than nothing at all.
        let sawSomeFeedback = viewModel.editingStatus != nil || viewModel.exportError != nil
        XCTAssertTrue(sawSomeFeedback, "signing with no certificate placed should tell the user why, not fail silently")
    }

    // MARK: - Export with encryption edge cases

    func testExportingWithEmptyOwnerPasswordShowsClearMessageNotCrash() throws {
        let fixture = try makeFlowMemberWithPDF(name: "ToEncrypt", pageTexts: ["Secret-ish content"])
        let document = WorkspaceDocument()
        document.workspace.documents = [fixture.member]
        document.workspace.pageOrder = fixture.refs
        document.memberPDFData[fixture.member.id] = fixture.pdfData
        let viewModel = WorkspaceViewModel(document: document, processingEngine: PDFKitProcessingEngineFallback())

        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("Orifold-encrypt-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let result = viewModel.saveFlattenedPDF(
            to: outputURL,
            options: WorkspaceExportOptions(encryption: PDFEncryptionOptions(userPassword: "user123", ownerPassword: ""))
        )

        // Whichever way this resolves (some builds treat an empty owner password as
        // "use the user password for both"), it must not crash, and any failure must
        // carry a real message -- never nil-message or a raw framework string.
        if !result {
            let message = try XCTUnwrap(viewModel.exportError?.message)
            XCTAssertFalse(message.isEmpty)
        }
    }

    // MARK: - Cancel mid-flight

    func testCancellingBeforeAnyImportStartedDoesNotCrash() {
        let viewModel = WorkspaceViewModel(document: WorkspaceDocument())
        viewModel.cancelActiveOperation()
        XCTAssertFalse(viewModel.isImporting)
    }
}

private final class FlowFixturePageView: NSView {
    private let text: String

    init(frame: CGRect, text: String) {
        self.text = text
        super.init(frame: frame)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("unavailable") }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        bounds.fill()
        NSString(string: text).draw(
            in: CGRect(x: 72, y: 72, width: 468, height: 648),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 16),
                .foregroundColor: NSColor.black
            ]
        )
    }
}
