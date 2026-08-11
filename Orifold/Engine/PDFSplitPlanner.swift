import Foundation

/// Pure partition logic for "split this document into several files". Works on page
/// indices only — the view model resolves indices to `PageRef`s and writes the files,
/// so every rule here is testable without a PDF in sight.
enum PDFSplitPlanner {

    /// A top-level bookmark's position in the concatenated workspace page list,
    /// produced by the same member-offset walk the export tail uses.
    struct Boundary: Equatable {
        let title: String
        let pageIndex: Int
    }

    /// One output file: a filename-safe stem and the 0-based pages it contains.
    struct Part: Equatable {
        let name: String
        let pageIndices: [Int]
    }

    enum Rule: Equatable {
        case everyN(Int)
        case ranges([ClosedRange<Int>])
        case bookmarks([Boundary])
    }

    static func parts(totalPages: Int, rule: Rule) -> [Part] {
        guard totalPages > 0 else { return [] }
        switch rule {
        case .everyN(let stride):
            guard stride > 0 else { return [] }
            let chunks = Swift.stride(from: 0, to: totalPages, by: stride).map { start in
                Array(start..<min(start + stride, totalPages))
            }
            return named(chunks.map { (nil, $0) })
        case .ranges(let ranges):
            let chunks = ranges.compactMap { range -> [Int]? in
                let low = max(range.lowerBound, 0)
                let high = min(range.upperBound, totalPages - 1)
                guard low <= high else { return nil }
                return Array(low...high)
            }
            return named(chunks.map { (nil, $0) })
        case .bookmarks(let boundaries):
            // First title wins when several bookmarks share a page; a leading segment
            // before the first bookmark becomes an unnamed part.
            var starts: [Boundary] = []
            for boundary in boundaries.sorted(by: { $0.pageIndex < $1.pageIndex })
            where boundary.pageIndex < totalPages && boundary.pageIndex != starts.last?.pageIndex {
                starts.append(boundary)
            }
            guard !starts.isEmpty else { return [] }
            var chunks: [(String?, [Int])] = []
            if starts[0].pageIndex > 0 {
                chunks.append((nil, Array(0..<starts[0].pageIndex)))
            }
            for (index, start) in starts.enumerated() {
                let end = index + 1 < starts.count ? starts[index + 1].pageIndex : totalPages
                chunks.append((start.title, Array(start.pageIndex..<end)))
            }
            return named(chunks)
        }
    }

    /// Parses 1-based user input like "1-3, 7, 9-12" into 0-based ranges. Returns nil on
    /// anything malformed or entirely outside the document; spans past the last page clamp.
    static func parseRanges(_ text: String, totalPages: Int) -> [ClosedRange<Int>]? {
        let tokens = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard !tokens.isEmpty else { return nil }
        var ranges: [ClosedRange<Int>] = []
        for token in tokens {
            let bounds = token.split(separator: "-", omittingEmptySubsequences: false)
                .map { Int($0.trimmingCharacters(in: .whitespaces)) }
            let range: ClosedRange<Int>
            if bounds.count == 1, let single = bounds[0] {
                range = single...single
            } else if bounds.count == 2, let low = bounds[0], let high = bounds[1], low <= high {
                range = low...high
            } else {
                return nil
            }
            guard range.lowerBound >= 1, range.lowerBound <= totalPages else { return nil }
            ranges.append((range.lowerBound - 1)...(min(range.upperBound, totalPages) - 1))
        }
        return ranges
    }

    /// Assigns filename-safe, unique names: bookmark titles where given (sanitized,
    /// deduplicated with -2/-3…), positional "partN" otherwise.
    private static func named(_ chunks: [(title: String?, pages: [Int])]) -> [Part] {
        var seen: [String: Int] = [:]
        return chunks.enumerated().map { index, chunk in
            var name = chunk.title.map(sanitized) ?? ""
            if name.isEmpty { name = "part\(index + 1)" }
            let count = (seen[name] ?? 0) + 1
            seen[name] = count
            return Part(name: count > 1 ? "\(name)-\(count)" : name, pageIndices: chunk.pages)
        }
    }

    private static func sanitized(_ title: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:?%*|\"<>").union(.newlines)
        return title.components(separatedBy: forbidden).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
    }
}
