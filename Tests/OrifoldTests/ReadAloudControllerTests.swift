import XCTest
@testable import Orifold

/// Feature C2: the read-aloud state machine, exercised entirely through a fake synthesizer
/// so the tests are deterministic and never touch a real audio device (CI-safe).
@MainActor
final class ReadAloudControllerTests: XCTestCase {

    /// Deterministic stand-in for `AVSpeechSynthesizer`: records what it was asked to speak
    /// and lets the test fire the "will speak range" / "finished" callbacks by hand, so no
    /// real audio is ever produced.
    final class FakeSynthesizer: SpeechSynthesizing {
        var onWillSpeakRange: ((NSRange) -> Void)?
        var onFinishUtterance: (() -> Void)?
        private(set) var spokenTexts: [String] = []
        private(set) var pauseCount = 0
        private(set) var resumeCount = 0
        private(set) var stopCount = 0
        var lastRate: Float?

        func speak(_ text: String, rate: Float) {
            spokenTexts.append(text)
            lastRate = rate
        }
        func pause() { pauseCount += 1 }
        func resume() { resumeCount += 1 }
        func stopSpeaking() { stopCount += 1 }

        // Test hooks that stand in for the AVSpeechSynthesizerDelegate callbacks.
        func fireWillSpeakRange(_ range: NSRange) { onWillSpeakRange?(range) }
        func finishUtterance() { onFinishUtterance?() }
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

    func testStartSpeaksFirstChunkOfGivenPage() {
        let synth = FakeSynthesizer()
        let controller = makeController(
            pages: [0: "Alpha one. Alpha two.", 1: "Beta one. Beta two."],
            pageCount: 2,
            synth: synth
        )
        controller.start(fromPage: 1)

        XCTAssertEqual(controller.state, .speaking)
        XCTAssertEqual(synth.spokenTexts.count, 1)
        XCTAssertTrue(synth.spokenTexts.first?.contains("Beta one") == true)
    }

    func testWillSpeakRangeMapsToPageGlobalHighlight() {
        let synth = FakeSynthesizer()
        let text = "Alpha one. Alpha two."
        let controller = makeController(pages: [0: text], pageCount: 1, synth: synth)
        controller.start(fromPage: 0)

        // Advance to the second chunk so the chunk's page offset is non-zero.
        synth.finishUtterance()
        let secondChunkOffset = SpeechChunker.chunks(forPageText: text, pageIndex: 0)[1].rangeInPage.location

        // Fire an utterance-relative range (word "two" inside "Alpha two.").
        synth.fireWillSpeakRange(NSRange(location: 6, length: 3))

        let highlight = controller.highlight
        XCTAssertEqual(highlight?.pageIndex, 0)
        XCTAssertEqual(highlight?.rangeInPage.location, secondChunkOffset + 6)
        XCTAssertEqual(highlight?.rangeInPage.length, 3)
    }

    func testFinishingLastChunkOfPageAdvancesToNextPage() {
        let synth = FakeSynthesizer()
        let controller = makeController(
            pages: [0: "Only sentence here.", 1: "Next page sentence."],
            pageCount: 2,
            synth: synth
        )
        controller.start(fromPage: 0)
        XCTAssertEqual(synth.spokenTexts.count, 1)

        synth.finishUtterance()  // page 0's only chunk finished

        XCTAssertEqual(controller.state, .speaking)
        XCTAssertEqual(synth.spokenTexts.count, 2)
        XCTAssertTrue(synth.spokenTexts.last?.contains("Next page") == true)
        XCTAssertEqual(controller.highlight?.pageIndex, 1)
    }

    /// Boundary banners and image-only pages return no text; read-aloud must skip them
    /// rather than stalling.
    func testSkipsPagesWithNoText() {
        let synth = FakeSynthesizer()
        let controller = makeController(
            pages: [0: "First.", 1: "   ", 2: "Third."],
            pageCount: 3,
            synth: synth
        )
        controller.start(fromPage: 0)
        synth.finishUtterance()  // finish page 0; page 1 is blank → skip to page 2

        XCTAssertEqual(controller.highlight?.pageIndex, 2)
        XCTAssertTrue(synth.spokenTexts.last?.contains("Third") == true)
    }

    func testFinishingLastPageGoesIdleAndClearsHighlight() {
        let synth = FakeSynthesizer()
        let controller = makeController(pages: [0: "Single sentence."], pageCount: 1, synth: synth)
        controller.start(fromPage: 0)
        XCTAssertNotNil(controller.highlight)

        synth.finishUtterance()

        XCTAssertEqual(controller.state, .idle)
        XCTAssertNil(controller.highlight)
    }

    func testPauseResumeTransitions() {
        let synth = FakeSynthesizer()
        let controller = makeController(pages: [0: "A. B."], pageCount: 1, synth: synth)
        controller.start(fromPage: 0)

        controller.pause()
        XCTAssertEqual(controller.state, .paused)
        XCTAssertEqual(synth.pauseCount, 1)

        controller.resume()
        XCTAssertEqual(controller.state, .speaking)
        XCTAssertEqual(synth.resumeCount, 1)
    }

    func testStopClearsHighlightAndGoesIdle() {
        let synth = FakeSynthesizer()
        let controller = makeController(pages: [0: "A. B."], pageCount: 1, synth: synth)
        controller.start(fromPage: 0)

        controller.stop()

        XCTAssertEqual(controller.state, .idle)
        XCTAssertNil(controller.highlight)
        XCTAssertEqual(synth.stopCount, 1)
    }

    func testStartBeyondPageCountGoesIdle() {
        let synth = FakeSynthesizer()
        let controller = makeController(pages: [0: "A."], pageCount: 1, synth: synth)
        controller.start(fromPage: 5)

        XCTAssertEqual(controller.state, .idle)
        XCTAssertTrue(synth.spokenTexts.isEmpty)
    }

    // MARK: - Highlight range clamping (crash guard for PDFPage.selection(for:))

    /// AVSpeechSynthesizer can report a will-speak range that runs past the text it was handed:
    /// it normalizes numbers/dates ("2020" → "twenty twenty") and counts offsets against the
    /// expanded form. That range flows through to `PDFPage.selection(for:)`, which throws an
    /// `NSRangeException` when it's out of bounds — so the controller must clamp it to the
    /// current chunk's UTF-16 bounds before composing the page-global highlight.
    func testWillSpeakRangeLongerThanChunkIsClampedToChunkBounds() {
        let synth = FakeSynthesizer()
        let text = "Alpha one."
        let controller = makeController(pages: [0: text], pageCount: 1, synth: synth)
        controller.start(fromPage: 0)

        let chunk = SpeechChunker.chunks(forPageText: text, pageIndex: 0)[0]
        let chunkLength = (chunk.text as NSString).length
        // Length overruns the chunk; the highlight must be clamped to end at the chunk's bound.
        synth.fireWillSpeakRange(NSRange(location: 0, length: chunkLength + 50))

        let highlight = controller.highlight
        XCTAssertEqual(highlight?.pageIndex, 0)
        XCTAssertEqual(highlight?.rangeInPage.location, chunk.rangeInPage.location)
        XCTAssertEqual(highlight?.rangeInPage.length, chunkLength)
        // The composed range must stay inside the chunk's page span — the invariant that keeps
        // `selection(for:)` from reading past the page's text.
        let end = (highlight?.rangeInPage.location ?? 0) + (highlight?.rangeInPage.length ?? 0)
        XCTAssertLessThanOrEqual(end, chunk.rangeInPage.location + chunkLength)
    }

    /// A will-speak range whose start is already past the end of the chunk has nothing to
    /// highlight; the controller must publish no highlight rather than an out-of-bounds one.
    func testWillSpeakRangeStartingBeyondChunkPublishesNoHighlight() {
        let synth = FakeSynthesizer()
        let text = "Alpha one."
        let controller = makeController(pages: [0: text], pageCount: 1, synth: synth)
        controller.start(fromPage: 0)
        XCTAssertNotNil(controller.highlight)  // sentence-level highlight is set when a chunk starts

        let chunkLength = (text as NSString).length
        synth.fireWillSpeakRange(NSRange(location: chunkLength + 10, length: 5))

        XCTAssertNil(controller.highlight)
    }

    /// Guards: `pause` is a no-op unless speaking; `resume` a no-op unless paused. Prevents
    /// the capsule's buttons from desyncing the synthesizer.
    func testPauseIsIgnoredWhenIdle() {
        let synth = FakeSynthesizer()
        let controller = makeController(pages: [0: "A."], pageCount: 1, synth: synth)

        controller.pause()

        XCTAssertEqual(controller.state, .idle)
        XCTAssertEqual(synth.pauseCount, 0)
    }
}
