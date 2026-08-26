import CoreGraphics
import Foundation
import PDFKit

/// Side-by-side compare: pairs the workspace's pages with another PDF's pages and runs the
/// visual and text diffs over each pair. Synchronous and self-contained — callers run it
/// from `Task.detached` and hand it only `Sendable` inputs (bytes and indices, never
/// `PDFDocument`s).
enum PDFComparisonService {
    /// A page addressed as (document index into `Request.leftDocuments`, page index).
    struct PageLocator: Equatable, Sendable {
        var documentIndex: Int
        var pageIndex: Int
    }

    struct Request: Sendable {
        /// Byte sources for the left side. Index 0 is the serialized combined document (what
        /// the user sees — rotations and crops applied); later entries are the members' live
        /// preserved bytes, which the *text* diff reads so PDFKit re-serialization can't
        /// manufacture text differences.
        var leftDocuments: [Data]
        /// One entry per workspace page: where its visual render comes from.
        var leftVisualPages: [PageLocator]
        /// One entry per workspace page: where its faithful text comes from.
        var leftTextPages: [PageLocator]
        /// The other draft, as picked by the user.
        var rightData: Data
    }

    enum PairChange: Equatable, Sendable {
        case unchanged
        case changed
        case leftOnly
        case rightOnly
    }

    struct PagePair: Identifiable, Equatable, Sendable {
        /// Pair index — page `id + 1` on the left, page `id + 1 + rightOffset` on the right.
        let id: Int
        var change: PairChange
        var visual: PDFVisualDiff.Result?
        var text: PDFTextDiff.Result?
    }

    static let compareDPI: CGFloat = 150

    /// Runs the whole comparison. `rightOffset` shifts which right-side page each left page
    /// pairs with (index pairing; no automatic alignment in v1). Cancellation returns the
    /// pairs computed so far.
    static func compare(
        _ request: Request,
        rightOffset: Int = 0,
        progress: @escaping @Sendable (Double) -> Void = { _ in },
        isCancelled: @escaping @Sendable () -> Bool = { false }
    ) -> [PagePair] {
        let leftDocuments = request.leftDocuments.map { PDFDocument(data: $0) }
        guard let rightDocument = PDFDocument(data: request.rightData) else { return [] }

        let leftCount = request.leftVisualPages.count
        let rightCount = rightDocument.pageCount
        let pairCount = max(leftCount, max(0, rightCount - rightOffset))
        guard pairCount > 0 else { return [] }

        var pairs: [PagePair] = []
        for index in 0..<pairCount {
            if isCancelled() { break }
            let rightIndex = index + rightOffset
            let hasLeft = index < leftCount
            let hasRight = rightIndex >= 0 && rightIndex < rightCount

            if !hasLeft || !hasRight {
                pairs.append(PagePair(
                    id: index,
                    change: hasLeft ? .leftOnly : .rightOnly,
                    visual: nil,
                    text: nil
                ))
                progress(Double(index + 1) / Double(pairCount))
                continue
            }

            var visual: PDFVisualDiff.Result?
            let locator = request.leftVisualPages[index]
            if locator.documentIndex < leftDocuments.count,
               let leftPage = leftDocuments[locator.documentIndex]?.page(at: locator.pageIndex),
               let rightPage = rightDocument.page(at: rightIndex),
               let leftImage = PDFOCRService.rasterizedImage(for: leftPage, dpi: compareDPI),
               let rightImage = PDFOCRService.rasterizedImage(for: rightPage, dpi: compareDPI) {
                visual = PDFVisualDiff.diff(leftImage, rightImage)
            }

            var text: PDFTextDiff.Result?
            if index < request.leftTextPages.count,
               case let textLocator = request.leftTextPages[index],
               textLocator.documentIndex < request.leftDocuments.count {
                let leftText = PDFTextAnalysisEngine.readingOrderText(
                    data: request.leftDocuments[textLocator.documentIndex],
                    pageIndex: textLocator.pageIndex
                )
                let rightText = PDFTextAnalysisEngine.readingOrderText(
                    data: request.rightData,
                    pageIndex: rightIndex
                )
                text = PDFTextDiff.diff(old: rightText, new: leftText)
            }

            let changed = (visual?.hasChanges ?? false) || (text?.hasChanges ?? false)
            pairs.append(PagePair(
                id: index,
                change: changed ? .changed : .unchanged,
                visual: visual,
                text: text
            ))
            progress(Double(index + 1) / Double(pairCount))
        }
        return pairs
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
