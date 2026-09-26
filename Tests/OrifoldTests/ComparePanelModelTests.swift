import XCTest
@testable import Orifold

@MainActor
final class ComparePanelModelTests: XCTestCase {
    func testRunPublishesProgressThenCompletes() async throws {
        let progressPublished = expectation(description: "progress published")
        let release = DispatchSemaphore(value: 0)
        let pair = makePair(id: 0, change: .unchanged)
        let model = ComparePanelModel(request: request()) { _, _, callbacks in
            callbacks.progress(0.4)
            progressPublished.fulfill()
            _ = release.wait(timeout: .now() + 2)
            callbacks.progress(1)
            return [pair]
        }
        let task = Task { await model.run() }
        await fulfillment(of: [progressPublished], timeout: 1)
        try await waitUntil { model.runState == .running(progress: 0.4) }

        release.signal()
        await task.value

        XCTAssertEqual(model.runState, .completed)
        XCTAssertEqual(model.pairs, [pair])
    }

    func testCancelRejectsLateProgressAndFinalPairs() async {
        let started = expectation(description: "comparison started")
        let release = DispatchSemaphore(value: 0)
        let pair = makePair(id: 0, change: .changed)
        let model = ComparePanelModel(request: request()) { _, _, callbacks in
            started.fulfill()
            _ = release.wait(timeout: .now() + 2)
            callbacks.progress(1)
            return [pair]
        }
        let task = Task { await model.run() }
        await fulfillment(of: [started], timeout: 1)

        model.cancel()
        release.signal()
        await task.value
        await Task.yield()

        XCTAssertEqual(model.runState, .cancelled)
        XCTAssertTrue(model.pairs.isEmpty)
    }

    func testOffsetChangeCancelsOldRunAndAcceptsOnlyNewestResult() async throws {
        let firstStarted = expectation(description: "first run started")
        let secondFinished = expectation(description: "second run finished")
        let releaseFirst = DispatchSemaphore(value: 0)
        let oldPair = makePair(id: 0, change: .leftOnly)
        let newPair = makePair(id: 1, change: .rightOnly)
        let model = ComparePanelModel(request: request()) { _, offset, callbacks in
            if offset == 0 {
                firstStarted.fulfill()
                _ = releaseFirst.wait(timeout: .now() + 2)
                callbacks.progress(1)
                return [oldPair]
            }
            callbacks.progress(1)
            secondFinished.fulfill()
            return [newPair]
        }
        let firstTask = Task { await model.run() }
        await fulfillment(of: [firstStarted], timeout: 1)

        model.setOffset(1)
        await fulfillment(of: [secondFinished], timeout: 1)
        try await waitUntil { model.runState == .completed }
        releaseFirst.signal()
        await firstTask.value
        await Task.yield()

        XCTAssertEqual(model.rightOffset, 1)
        XCTAssertEqual(model.runState, .completed)
        XCTAssertEqual(model.pairs, [newPair])
    }

    func testRunnerFailureHasExplicitFailedState() async {
        struct SyntheticFailure: Error {}
        let model = ComparePanelModel(request: request()) { _, _, _ in
            throw SyntheticFailure()
        }

        await model.run()

        XCTAssertEqual(model.runState, .failed)
        XCTAssertTrue(model.pairs.isEmpty)
    }

    private func request() -> PDFComparisonRequest {
        PDFComparisonRequest(
            engineRequest: PDFComparisonService.Request(
                leftDocuments: [Data()],
                leftVisualPages: [],
                leftTextPages: [],
                rightData: Data()
            ),
            leftTitle: "Workspace",
            rightTitle: "Draft"
        )
    }

    private func makePair(
        id: Int,
        change: PDFComparisonService.PairChange
    ) -> PDFComparisonService.PagePair {
        PDFComparisonService.PagePair(id: id, change: change, visual: nil, text: nil)
    }

    private func waitUntil(
        timeout: Duration = .seconds(1),
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition() {
            if clock.now >= deadline { XCTFail("Timed out waiting for condition"); return }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}
