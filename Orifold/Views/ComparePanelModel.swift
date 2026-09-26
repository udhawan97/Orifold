import AppKit
import PDFKit
import SwiftUI

/// State for the compare panel: runs the comparison off the main actor, then serves
/// per-pair display images (main-thread thumbnails, display-only — the diff itself already
/// ran on the engine's own renders).
@MainActor
@Observable
final class ComparePanelModel {
    enum RunState: Equatable {
        case idle
        case running(progress: Double)
        case completed
        case cancelled
        case failed
    }

    struct Callbacks: Sendable {
        var progress: @Sendable (Double) -> Void
        var isCancelled: @Sendable () -> Bool
    }

    typealias Runner = @Sendable (
        PDFComparisonService.Request,
        Int,
        Callbacks
    ) throws -> PDFComparisonService.RunResult

    private(set) var pairs: [PDFComparisonService.PagePair] = []
    private(set) var runResult: PDFComparisonService.RunResult?
    private(set) var runState: RunState = .running(progress: 0)
    var currentIndex = 0
    var showsHighlights = true
    private(set) var rightOffset = 0

    private let request: PDFComparisonRequest
    private let runner: Runner
    private let leftDocuments: [PDFDocument?]
    private let rightDocument: PDFDocument?
    private var runToken = UUID()
    private var cancellation: OperationCancellationToken?
    private var restartTask: Task<Void, Never>?
    private var restartToken = UUID()

    init(
        request: PDFComparisonRequest,
        runner: @escaping Runner = { request, offset, callbacks in
            PDFComparisonService.compare(
                request,
                rightOffset: offset,
                progress: callbacks.progress,
                isCancelled: callbacks.isCancelled
            )
        }
    ) {
        self.request = request
        self.runner = runner
        leftDocuments = request.engineRequest.leftDocuments.map { PDFDocument(data: $0) }
        rightDocument = PDFDocument(data: request.engineRequest.rightData)
    }

    var isComparing: Bool {
        if case .running = runState { return true }
        return false
    }

    var currentPair: PDFComparisonService.PagePair? {
        pairs.indices.contains(currentIndex) ? pairs[currentIndex] : nil
    }

    var changedPairs: [PDFComparisonService.PagePair] {
        pairs.filter {
            $0.change == .changed || $0.change == .leftOnly || $0.change == .rightOnly
        }
    }

    var incompletePairCount: Int {
        pairs.filter { $0.change == .incomplete }.count
    }

    func run() async {
        cancelPendingRestart()
        await performRun()
    }

    private func performRun() async {
        guard !Task.isCancelled else { return }
        cancelCurrentRun(transitionToCancelled: false)
        let token = UUID()
        runToken = token
        let cancellation = OperationCancellationToken()
        self.cancellation = cancellation
        pairs = []
        runResult = nil
        runState = .running(progress: 0)
        let result = await executeRun(token: token, cancellation: cancellation)
        guard runToken == token else { return }
        self.cancellation = nil
        guard !cancellation.isCancelled else {
            runState = .cancelled
            return
        }
        switch result {
        case .success(let result):
            runResult = result
            pairs = result.pairs
            if currentIndex >= pairs.count {
                currentIndex = max(0, pairs.count - 1)
            }
            switch result.status {
            case .completed:
                runState = .completed
            case .cancelled:
                runState = .cancelled
            case .failed:
                runState = .failed
            }
        case .failure:
            pairs = []
            runResult = nil
            runState = .failed
        }
    }

    func setOffset(_ newOffset: Int) {
        guard newOffset != rightOffset else { return }
        cancelPendingRestart()
        cancelCurrentRun(transitionToCancelled: false)
        rightOffset = newOffset
        let token = UUID()
        restartToken = token
        restartTask = Task { [weak self] in
            guard !Task.isCancelled else { return }
            await self?.performPendingRestart(token: token)
        }
    }

    func cancel() {
        cancelPendingRestart()
        cancelCurrentRun(transitionToCancelled: true)
    }

    func leftImage(for pair: PDFComparisonService.PagePair) -> NSImage? {
        guard let left = pair.left,
              request.engineRequest.leftPages.indices.contains(left.index),
              let locator = request.engineRequest.leftPages[left.index].visualPage,
              leftDocuments.indices.contains(locator.documentIndex),
              let page = leftDocuments[locator.documentIndex]?.page(at: locator.pageIndex) else {
            return nil
        }
        return pageImage(page, highlight: highlightResult(for: pair))
    }

    func rightImage(for pair: PDFComparisonService.PagePair) -> NSImage? {
        guard let right = pair.right,
              let page = rightDocument?.page(at: right.index) else { return nil }
        return pageImage(page, highlight: highlightResult(for: pair))
    }

    private func highlightResult(for pair: PDFComparisonService.PagePair) -> PDFVisualDiff.Result? {
        guard showsHighlights else { return nil }
        return pair.visual.value
    }

    private func acceptProgress(_ progress: Double, token: UUID) {
        guard runToken == token, case .running(let current) = runState else { return }
        runState = .running(progress: max(current, min(max(progress, 0), 1)))
    }

    private func executeRun(
        token: UUID,
        cancellation: OperationCancellationToken
    ) async -> Result<PDFComparisonService.RunResult, Error> {
        let runner = self.runner
        let engineRequest = request.engineRequest
        let offset = rightOffset
        let throttle = CompareProgressThrottle()
        let progressUpdates = AsyncStream<Double>.makeStream()
        let progressTask = Task { [weak self] in
            for await progress in progressUpdates.stream {
                self?.acceptProgress(progress, token: token)
            }
        }
        let result: Result<PDFComparisonService.RunResult, Error> = await Task.detached(
            priority: .userInitiated
        ) {
            do {
                return .success(try runner(
                    engineRequest,
                    offset,
                    Callbacks(
                        progress: { value in
                            guard let progress = throttle.accept(value) else { return }
                            progressUpdates.continuation.yield(progress)
                        },
                        isCancelled: { cancellation.isCancelled }
                    )
                ))
            } catch {
                return .failure(error)
            }
        }.value
        progressUpdates.continuation.finish()
        await progressTask.value
        return result
    }

    private func cancelCurrentRun(transitionToCancelled: Bool) {
        cancellation?.cancel()
        cancellation = nil
        runToken = UUID()
        if transitionToCancelled, isComparing {
            pairs = []
            runResult = nil
            currentIndex = 0
            runState = .cancelled
        }
    }

    private func performPendingRestart(token: UUID) async {
        guard restartToken == token, !Task.isCancelled else { return }
        restartTask = nil
        await performRun()
    }

    private func cancelPendingRestart() {
        restartTask?.cancel()
        restartTask = nil
        restartToken = UUID()
    }

    /// A display thumbnail, with the changed regions composited in when highlighting is on.
    /// Normalized rects are bottom-left-origin, exactly like `NSImage.lockFocus` space.
    private func pageImage(_ page: PDFPage, highlight: PDFVisualDiff.Result?) -> NSImage {
        let bounds = page.bounds(for: .mediaBox)
        let maxEdge: CGFloat = 640
        let scale = min(maxEdge / max(bounds.width, 1), maxEdge / max(bounds.height, 1))
        let size = CGSize(width: max(bounds.width * scale, 1), height: max(bounds.height * scale, 1))
        let thumbnail = page.thumbnail(of: size, for: .mediaBox)
        guard let highlight, highlight.hasChanges else { return thumbnail }

        let composed = NSImage(size: thumbnail.size)
        composed.lockFocus()
        thumbnail.draw(in: NSRect(origin: .zero, size: thumbnail.size))
        for rect in highlight.changedRects {
            let drawRect = NSRect(
                x: rect.minX * thumbnail.size.width,
                y: rect.minY * thumbnail.size.height,
                width: rect.width * thumbnail.size.width,
                height: rect.height * thumbnail.size.height
            )
            NSColor.systemRed.withAlphaComponent(0.22).setFill()
            drawRect.fill(using: .sourceOver)
            NSColor.systemRed.withAlphaComponent(0.85).setStroke()
            NSBezierPath(rect: drawRect).stroke()
        }
        composed.unlockFocus()
        return composed
    }
}

private final class CompareProgressThrottle: @unchecked Sendable {
    private let lock = NSLock()
    private var lastProgress = 0.0

    func accept(_ rawValue: Double) -> Double? {
        let value = min(max(rawValue, 0), 1)
        lock.lock()
        defer { lock.unlock() }
        guard value >= 1 || value - lastProgress >= 0.01 else { return nil }
        lastProgress = max(lastProgress, value)
        return lastProgress
    }
}
