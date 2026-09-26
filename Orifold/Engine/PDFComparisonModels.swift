import CoreGraphics
import Foundation
import PDFKit

extension PDFComparisonService {
    /// A page addressed as (document index into `Request.leftDocuments`, page index).
    struct PageLocator: Equatable, Sendable {
        var documentIndex: Int
        var pageIndex: Int
    }

    /// One original workspace page before comparison sources are resolved. Optional source
    /// indices preserve pages whose visual or text bytes could not be prepared.
    struct WorkspacePageSource: Equatable, Sendable {
        var id: UUID
        var number: Int
        var memberID: UUID
        var sourcePageIndex: Int
        var combinedPageIndex: Int?
    }

    struct LeftPage: Equatable, Sendable {
        var workspacePageID: UUID
        var workspacePageNumber: Int
        var visualPage: PageLocator?
        var textPage: PageLocator?
    }

    struct PreparedLeftSide: Equatable, Sendable {
        var documents: [Data]
        var pages: [LeftPage]
    }

    struct Request: Sendable {
        /// Byte sources used by the left page locators. The combined workspace document and
        /// live member documents are included only when their preparation succeeded.
        var leftDocuments: [Data]
        /// Exactly one entry per original workspace page, including pages with unavailable
        /// visual or text sources.
        var leftPages: [LeftPage]
        /// The other draft, as picked by the user.
        var rightData: Data
    }

    enum PairChange: Equatable, Sendable {
        case unchanged
        case changed
        case incomplete
        case leftOnly
        case rightOnly
    }

    enum ChannelResult<Value: Equatable & Sendable>: Equatable, Sendable {
        case available(Value)
        case unavailable
        case notApplicable

        var value: Value? {
            guard case .available(let value) = self else { return nil }
            return value
        }

        var isUnavailable: Bool {
            self == .unavailable
        }
    }

    struct PageIdentity: Equatable, Sendable {
        var index: Int
        var number: Int
        var workspacePageID: UUID?
    }

    struct PagePair: Identifiable, Equatable, Sendable {
        /// Stable sequence index within this run. Actual document indices and displayed page
        /// numbers live in `left` and `right` and are never inferred from this value.
        let id: Int
        var alignmentIndex: Int
        var left: PageIdentity?
        var right: PageIdentity?
        var change: PairChange
        var visual: ChannelResult<PDFVisualDiff.Result>
        var text: ChannelResult<PDFTextDiff.Result>

        var hasUnavailableChannels: Bool {
            visual.isUnavailable || text.isUnavailable
        }
    }

    enum TerminalStatus: Equatable, Sendable {
        case completed
        case cancelled
        case failed
    }

    struct Coverage: Equatable, Sendable {
        var leftPageCount: Int
        var rightPageCount: Int
        var excludedRightPageNumbers: [Int]
    }

    struct RunResult: Equatable, Sendable {
        var status: TerminalStatus
        var pairs: [PagePair]
        var coverage: Coverage

        var hasUnavailableChannels: Bool {
            pairs.contains(where: \.hasUnavailableChannels)
        }

        var isComplete: Bool {
            status == .completed
                && coverage.excludedRightPageNumbers.isEmpty
                && !hasUnavailableChannels
        }
    }

    struct Analyzers {
        var visual: (PDFPage, PDFPage) -> PDFVisualDiff.Result?
        var text: (Data, Int) -> PDFTextAnalysisEngine.ReadingOrderTextResult

        static var live: Self {
            Self(
                visual: { leftPage, rightPage in
                    guard let leftImage = PDFOCRService.rasterizedImage(for: leftPage, dpi: compareDPI),
                          let rightImage = PDFOCRService.rasterizedImage(for: rightPage, dpi: compareDPI) else {
                        return nil
                    }
                    return PDFVisualDiff.diff(leftImage, rightImage)
                },
                text: PDFTextAnalysisEngine.readingOrderTextResult
            )
        }
    }

    static let compareDPI: CGFloat = 150

    /// Builds the left-side byte table without dropping workspace pages. A missing combined
    /// index disables only that page's visual channel; missing member bytes disable only its
    /// text channel.
    static func prepareLeftSide(
        pages: [WorkspacePageSource],
        combinedData: Data?,
        memberData: [UUID: Data]
    ) -> PreparedLeftSide {
        var documents: [Data] = []
        let combinedDocumentIndex = combinedData.map { data -> Int in
            documents.append(data)
            return documents.count - 1
        }
        var memberDocumentIndices: [UUID: Int] = [:]
        let preparedPages = pages.map { page in
            let visualPage = combinedDocumentIndex.flatMap { documentIndex in
                page.combinedPageIndex.map {
                    PageLocator(documentIndex: documentIndex, pageIndex: $0)
                }
            }
            let textPage = memberPageLocator(
                for: page,
                memberData: memberData,
                documents: &documents,
                documentIndices: &memberDocumentIndices
            )
            return LeftPage(
                workspacePageID: page.id,
                workspacePageNumber: page.number,
                visualPage: visualPage,
                textPage: textPage
            )
        }
        return PreparedLeftSide(documents: documents, pages: preparedPages)
    }

    private static func memberPageLocator(
        for page: WorkspacePageSource,
        memberData: [UUID: Data],
        documents: inout [Data],
        documentIndices: inout [UUID: Int]
    ) -> PageLocator? {
        if let existing = documentIndices[page.memberID] {
            return PageLocator(documentIndex: existing, pageIndex: page.sourcePageIndex)
        }
        guard let bytes = memberData[page.memberID] else { return nil }
        let documentIndex = documents.count
        documents.append(bytes)
        documentIndices[page.memberID] = documentIndex
        return PageLocator(documentIndex: documentIndex, pageIndex: page.sourcePageIndex)
    }
}
