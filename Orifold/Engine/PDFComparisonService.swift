import Foundation
import PDFKit

/// Side-by-side compare: pairs the workspace's pages with another PDF's pages and runs the
/// visual and text diffs over each pair. Synchronous and self-contained — callers run it
/// from `Task.detached` and hand it only `Sendable` inputs (bytes and indices, never
/// `PDFDocument`s).
enum PDFComparisonService {
    /// Runs the whole comparison. `rightOffset` shifts which right-side page each left page
    /// pairs with (index pairing; no automatic alignment). Cancellation is cooperative
    /// between planned pairs and returns a terminal status with the pairs completed so far.
    static func compare(
        _ request: Request,
        rightOffset: Int = 0,
        progress: @escaping @Sendable (Double) -> Void = { _ in },
        isCancelled: @escaping @Sendable () -> Bool = { false },
        analyzers: Analyzers = .live
    ) -> RunResult {
        let leftDocuments = request.leftDocuments.map { PDFDocument(data: $0) }
        guard let rightDocument = PDFDocument(data: request.rightData), !rightDocument.isLocked else {
            return RunResult(
                status: .failed,
                pairs: [],
                coverage: coverage(
                    leftCount: request.leftPages.count,
                    rightCount: 0,
                    rightOffset: rightOffset
                )
            )
        }

        let leftCount = request.leftPages.count
        let rightCount = rightDocument.pageCount
        let plans = pairPlans(leftCount: leftCount, rightCount: rightCount, rightOffset: rightOffset)
        let runCoverage = coverage(leftCount: leftCount, rightCount: rightCount, rightOffset: rightOffset)
        let context = PairContext(
            request: request,
            leftDocuments: leftDocuments,
            rightDocument: rightDocument,
            analyzers: analyzers
        )
        guard !plans.isEmpty else {
            return RunResult(status: .completed, pairs: [], coverage: runCoverage)
        }

        var pairs: [PagePair] = []
        pairs.reserveCapacity(plans.count)
        for (sequenceIndex, plan) in plans.enumerated() {
            if isCancelled() {
                return RunResult(status: .cancelled, pairs: pairs, coverage: runCoverage)
            }
            pairs.append(comparePair(id: sequenceIndex, plan: plan, context: context))
            progress(Double(sequenceIndex + 1) / Double(plans.count))
            if isCancelled() {
                return RunResult(status: .cancelled, pairs: pairs, coverage: runCoverage)
            }
        }
        return RunResult(status: .completed, pairs: pairs, coverage: runCoverage)
    }

    private struct PairPlan {
        var alignmentIndex: Int
        var leftIndex: Int?
        var rightIndex: Int?
    }

    private struct PairContext {
        var request: Request
        var leftDocuments: [PDFDocument?]
        var rightDocument: PDFDocument
        var analyzers: Analyzers
    }

    private static func pairPlans(
        leftCount: Int,
        rightCount: Int,
        rightOffset: Int
    ) -> [PairPlan] {
        let slotCount = max(leftCount, max(0, rightCount - rightOffset))
        guard slotCount > 0 else { return [] }
        return (0..<slotCount).compactMap { alignmentIndex in
            let rightIndex = alignmentIndex + rightOffset
            let left = alignmentIndex < leftCount ? alignmentIndex : nil
            let right = rightIndex >= 0 && rightIndex < rightCount ? rightIndex : nil
            guard left != nil || right != nil else { return nil }
            return PairPlan(alignmentIndex: alignmentIndex, leftIndex: left, rightIndex: right)
        }
    }

    private static func coverage(
        leftCount: Int,
        rightCount: Int,
        rightOffset: Int
    ) -> Coverage {
        let excludedCount = min(max(rightOffset, 0), rightCount)
        return Coverage(
            leftPageCount: leftCount,
            rightPageCount: rightCount,
            excludedRightPageNumbers: excludedCount > 0 ? Array(1...excludedCount) : []
        )
    }

    private static func comparePair(
        id: Int,
        plan: PairPlan,
        context: PairContext
    ) -> PagePair {
        let leftIdentity = plan.leftIndex.map { index in
            let page = context.request.leftPages[index]
            return PageIdentity(
                index: index,
                number: page.workspacePageNumber,
                workspacePageID: page.workspacePageID
            )
        }
        let rightIdentity = plan.rightIndex.map {
            PageIdentity(index: $0, number: $0 + 1, workspacePageID: nil)
        }
        guard let leftIndex = plan.leftIndex else {
            return oneSidedPair(id: id, plan: plan, left: nil, right: rightIdentity)
        }
        guard let rightIndex = plan.rightIndex else {
            return oneSidedPair(id: id, plan: plan, left: leftIdentity, right: nil)
        }

        let leftPage = context.request.leftPages[leftIndex]
        let visual = visualResult(
            leftPage: leftPage,
            rightIndex: rightIndex,
            leftDocuments: context.leftDocuments,
            rightDocument: context.rightDocument,
            analyzer: context.analyzers.visual
        )
        let text = textResult(
            leftPage: leftPage,
            rightIndex: rightIndex,
            request: context.request,
            analyzer: context.analyzers.text
        )
        return PagePair(
            id: id,
            alignmentIndex: plan.alignmentIndex,
            left: leftIdentity,
            right: rightIdentity,
            change: classify(visual: visual, text: text),
            visual: visual,
            text: text
        )
    }

    private static func oneSidedPair(
        id: Int,
        plan: PairPlan,
        left: PageIdentity?,
        right: PageIdentity?
    ) -> PagePair {
        PagePair(
            id: id,
            alignmentIndex: plan.alignmentIndex,
            left: left,
            right: right,
            change: left == nil ? .rightOnly : .leftOnly,
            visual: .notApplicable,
            text: .notApplicable
        )
    }

    private static func classify(
        visual: ChannelResult<PDFVisualDiff.Result>,
        text: ChannelResult<PDFTextDiff.Result>
    ) -> PairChange {
        if (visual.value?.hasChanges ?? false) || (text.value?.hasChanges ?? false) {
            return .changed
        }
        return visual.value != nil && text.value != nil ? .unchanged : .incomplete
    }

    private static func visualResult(
        leftPage: LeftPage,
        rightIndex: Int,
        leftDocuments: [PDFDocument?],
        rightDocument: PDFDocument,
        analyzer: (PDFPage, PDFPage) -> PDFVisualDiff.Result?
    ) -> ChannelResult<PDFVisualDiff.Result> {
        guard let locator = leftPage.visualPage,
              leftDocuments.indices.contains(locator.documentIndex),
              let leftDocument = leftDocuments[locator.documentIndex],
              let leftPDFPage = leftDocument.page(at: locator.pageIndex),
              let rightPDFPage = rightDocument.page(at: rightIndex),
              let result = analyzer(leftPDFPage, rightPDFPage) else {
            return .unavailable
        }
        return .available(result)
    }

    private static func textResult(
        leftPage: LeftPage,
        rightIndex: Int,
        request: Request,
        analyzer: (Data, Int) -> PDFTextAnalysisEngine.ReadingOrderTextResult
    ) -> ChannelResult<PDFTextDiff.Result> {
        guard let locator = leftPage.textPage,
              request.leftDocuments.indices.contains(locator.documentIndex),
              case .available(let leftText) = analyzer(
                request.leftDocuments[locator.documentIndex],
                locator.pageIndex
              ),
              case .available(let rightText) = analyzer(request.rightData, rightIndex) else {
            return .unavailable
        }
        return .available(PDFTextDiff.diff(old: rightText, new: leftText))
    }
}

/// One prepared comparison, ready for the panel: the engine request plus display metadata.
/// Identifiable so `.sheet(item:)` drives presentation.
struct PDFComparisonRequest: Identifiable {
    let id = UUID()
    var engineRequest: PDFComparisonService.Request
    var leftTitle: String
    var rightTitle: String
}
