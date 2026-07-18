import Combine
import Foundation

/// User-selectable read-aloud speed, as a multiplier of the platform's default speech rate.
/// Labels are numeric (×) and locale-independent, so they need no translation.
enum ReadAloudRate: Double, CaseIterable, Identifiable {
    case slow = 0.9
    case normal = 1.0
    case fast = 1.25

    var id: Double { rawValue }

    var label: String {
        switch self {
        case .slow: return "0.9×"
        case .normal: return "1×"
        case .fast: return "1.25×"
        }
    }
}

/// Drives read-aloud: a small state machine that speaks a document one sentence at a time,
/// advancing page by page, and publishes the sentence/word currently being spoken so the
/// canvas can follow along with a highlight.
///
/// Speaking one utterance at a time (rather than queueing a whole page) keeps pause/resume
/// simple and makes advancing precise: the controller only moves to the next chunk when the
/// synthesizer reports the current one finished. All page/text access is injected as closures
/// so the machine stays pure and unit-testable against a fake synthesizer.
@MainActor
final class ReadAloudController: ObservableObject {
    enum State: Equatable { case idle, speaking, paused }

    @Published private(set) var state: State = .idle
    /// The span currently being spoken, as a page index plus a UTF-16 range into that page's
    /// text. `nil` whenever nothing is being read. Set to the whole sentence when a chunk
    /// begins, then refined to the spoken word as `onWillSpeakRange` fires.
    @Published private(set) var highlight: (pageIndex: Int, rangeInPage: NSRange)?

    /// Speech rate as a multiplier of the platform default (1.0 == normal). Applies to the
    /// next chunk spoken; changing it mid-sentence does not restart the current utterance.
    var rate: Float = 1.0

    var isActive: Bool { state != .idle }

    private let synthesizer: SpeechSynthesizing
    private let pageTextProvider: (Int) -> String?
    private let pageCount: () -> Int

    private var currentPageIndex = 0
    private var chunks: [SpeechChunk] = []
    private var chunkIndex = 0

    init(
        synthesizer: SpeechSynthesizing,
        pageTextProvider: @escaping (Int) -> String?,
        pageCount: @escaping () -> Int
    ) {
        self.synthesizer = synthesizer
        self.pageTextProvider = pageTextProvider
        self.pageCount = pageCount

        synthesizer.onWillSpeakRange = { [weak self] range in
            self?.handleWillSpeak(range)
        }
        synthesizer.onFinishUtterance = { [weak self] in
            self?.handleFinishedUtterance()
        }
    }

    // MARK: - Commands

    /// Begins reading from `fromPage` (an index into the composed document). Pages with no
    /// speakable text — boundary banners, image-only pages — are skipped. If no page from
    /// `fromPage` onward has text, the controller returns to `.idle`.
    func start(fromPage: Int) {
        if state != .idle { synthesizer.stopSpeaking() }
        chunks = []
        chunkIndex = 0
        highlight = nil

        guard let (pageIndex, pageChunks) = firstSpeakablePage(from: max(0, fromPage)) else {
            state = .idle
            return
        }
        currentPageIndex = pageIndex
        chunks = pageChunks
        chunkIndex = 0
        state = .speaking
        speakCurrentChunk()
    }

    func pause() {
        guard state == .speaking else { return }
        synthesizer.pause()
        state = .paused
    }

    func resume() {
        guard state == .paused else { return }
        synthesizer.resume()
        state = .speaking
    }

    func stop() {
        synthesizer.stopSpeaking()
        state = .idle
        highlight = nil
        chunks = []
        chunkIndex = 0
    }

    // MARK: - Synthesizer callbacks

    private func handleWillSpeak(_ utteranceRange: NSRange) {
        guard state != .idle, chunks.indices.contains(chunkIndex) else { return }
        let chunk = chunks[chunkIndex]
        // The synthesizer can report a range past the end of the text it was handed: it
        // normalizes numbers/dates ("2020" → "twenty twenty") and counts offsets against the
        // expanded form. An out-of-bounds range would flow to `PDFPage.selection(for:)` and
        // throw `NSRangeException`, so clamp to the chunk's own UTF-16 bounds first.
        let chunkLength = (chunk.text as NSString).length
        let location = min(max(0, utteranceRange.location), chunkLength)
        let length = min(utteranceRange.length, chunkLength - location)
        // Nothing left to highlight once clamped — drop the word-level highlight rather than
        // publish a zero/negative-length span.
        guard length > 0 else {
            highlight = nil
            return
        }
        // Utterance-relative offsets → page-global offsets by adding the chunk's page offset.
        // Both operands are now within the chunk, so the result stays inside `chunk.rangeInPage`.
        let globalRange = NSRange(
            location: chunk.rangeInPage.location + location,
            length: length
        )
        highlight = (chunk.pageIndex, globalRange)
    }

    private func handleFinishedUtterance() {
        // Ignore any late "finished" that arrives after an explicit stop.
        guard state != .idle else { return }

        chunkIndex += 1
        if chunks.indices.contains(chunkIndex) {
            speakCurrentChunk()
            return
        }

        // Current page exhausted — move to the next page that has speakable text.
        guard let (pageIndex, pageChunks) = firstSpeakablePage(from: currentPageIndex + 1) else {
            state = .idle
            highlight = nil
            return
        }
        currentPageIndex = pageIndex
        chunks = pageChunks
        chunkIndex = 0
        speakCurrentChunk()
    }

    // MARK: - Helpers

    private func speakCurrentChunk() {
        guard chunks.indices.contains(chunkIndex) else { return }
        let chunk = chunks[chunkIndex]
        // Highlight the whole sentence immediately so there's feedback before the first
        // word-range callback lands; `onWillSpeakRange` then narrows it word by word.
        highlight = (chunk.pageIndex, chunk.rangeInPage)
        synthesizer.speak(chunk.text, rate: rate)
    }

    /// Returns the first page at index `>= from` that produces at least one speakable chunk,
    /// along with those chunks. `nil` if none remain within the document.
    private func firstSpeakablePage(from: Int) -> (pageIndex: Int, chunks: [SpeechChunk])? {
        let total = pageCount()
        var index = from
        while index < total {
            let text = pageTextProvider(index) ?? ""
            let pageChunks = SpeechChunker.chunks(forPageText: text, pageIndex: index)
            if !pageChunks.isEmpty { return (index, pageChunks) }
            index += 1
        }
        return nil
    }
}
