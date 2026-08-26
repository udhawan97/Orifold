import XCTest
@testable import Orifold

/// "Read Aloud from Here": the character-offset start added to the read-aloud state machine
/// plus the selection-to-offset mapping, both exercised deterministically through a fake
/// synthesizer (no audio device, CI-safe — same idiom as ReadAloudControllerTests).
@MainActor
final class ReadAloudFromHereTests: XCTestCase {
    private final class FakeSynthesizer: SpeechSynthesizing {
        var onWillSpeakRange: ((NSRange) -> Void)?
        var onFinishUtterance: (() -> Void)?
        private(set) var spokenTexts: [String] = []

        func speak(_ text: String, rate: Float) { spokenTexts.append(text) }
        func pause() {}
        func resume() {}
        func stopSpeaking() {}
    }

    private func makeController(
        pages: [Int: String],
        pageCount: Int,
        synth: FakeSynthesizer
    ) -> ReadAloudController {
        ReadAloudController(
            synthesizer: synth,
            pageTextProvider: { pages[$0] },
            pageCount: { pageCount }
        )
    }

    // MARK: - Controller: character offset chooses the starting sentence

    func testOffsetInsideSecondSentenceStartsThere() {
        let synth = FakeSynthesizer()
        let text = "Alpha one. Beta two. Gamma three."
        let controller = makeController(pages: [0: text], pageCount: 1, synth: synth)
        let secondChunk = SpeechChunker.chunks(forPageText: text, pageIndex: 0)[1]

        controller.start(fromPage: 0, characterOffset: secondChunk.rangeInPage.location + 2)

        XCTAssertEqual(controller.state, .speaking)
        XCTAssertTrue(synth.spokenTexts.first?.contains("Beta two") == true)
        XCTAssertEqual(controller.highlight?.rangeInPage, secondChunk.rangeInPage)
    }

    func testZeroOffsetKeepsTheExistingStartBehavior() {
        let synth = FakeSynthesizer()
        let controller = makeController(pages: [0: "Alpha one. Beta two."], pageCount: 1, synth: synth)

        controller.start(fromPage: 0)

        XCTAssertTrue(synth.spokenTexts.first?.contains("Alpha one") == true)
    }

    func testOffsetPastPageEndAdvancesToNextSpeakablePage() {
        let synth = FakeSynthesizer()
        let controller = makeController(
            pages: [0: "Short page.", 1: "Next page sentence."],
            pageCount: 2,
            synth: synth
        )

        let started = controller.start(fromPage: 0, characterOffset: 10_000)

        XCTAssertTrue(started)
        XCTAssertTrue(synth.spokenTexts.first?.contains("Next page sentence") == true)
    }

    func testOffsetPastEndOfLastPageReturnsFalse() {
        let synth = FakeSynthesizer()
        let controller = makeController(pages: [0: "Only sentence."], pageCount: 1, synth: synth)

        XCTAssertFalse(controller.start(fromPage: 0, characterOffset: 10_000))
        XCTAssertEqual(controller.state, .idle)
        XCTAssertTrue(synth.spokenTexts.isEmpty)
    }

    func testOffsetOnlyAppliesToTheRequestedPage() {
        let synth = FakeSynthesizer()
        // Page 0 has no speakable text, so reading starts on page 1 — from its beginning,
        // because the offset was captured on page 0.
        let controller = makeController(
            pages: [0: "   ", 1: "First here. Second here."],
            pageCount: 2,
            synth: synth
        )

        controller.start(fromPage: 0, characterOffset: 15)

        XCTAssertTrue(synth.spokenTexts.first?.contains("First here") == true)
    }

    // MARK: - Selection → offset mapping (pure)

    func testSelectionPrefixLocatesItsOffsetInPageText() {
        let pageText = "Alpha one. Beta two. Gamma three."
        let offset = WorkspaceViewModel.readAloudStartOffset(selection: "Beta two. Gamma", pageText: pageText)
        XCTAssertEqual(offset, (pageText as NSString).range(of: "Beta two.").location)
    }

    func testMissingSelectionMapsToPageStart() {
        XCTAssertEqual(WorkspaceViewModel.readAloudStartOffset(selection: nil, pageText: "Alpha."), 0)
        XCTAssertEqual(WorkspaceViewModel.readAloudStartOffset(selection: "  ", pageText: "Alpha."), 0)
    }

    func testUnlocatableSelectionMapsToPageStart() {
        XCTAssertEqual(
            WorkspaceViewModel.readAloudStartOffset(selection: "Not on this page", pageText: "Alpha one."),
            0
        )
    }

    func testEmptyPageTextMapsToPageStart() {
        XCTAssertEqual(WorkspaceViewModel.readAloudStartOffset(selection: "Alpha", pageText: nil), 0)
        XCTAssertEqual(WorkspaceViewModel.readAloudStartOffset(selection: "Alpha", pageText: ""), 0)
    }

    func testLongSelectionAnchorsOnItsPrefix() {
        let sentence = String(repeating: "word ", count: 30).trimmingCharacters(in: .whitespaces)
        let pageText = "Lead-in first. \(sentence)."
        let offset = WorkspaceViewModel.readAloudStartOffset(selection: sentence, pageText: pageText)
        XCTAssertEqual(offset, (pageText as NSString).range(of: "word").location)
    }
}
