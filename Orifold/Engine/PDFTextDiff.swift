import Foundation

/// Pure word-level text comparison for page pairs: longest-common-subsequence counts of
/// inserted and deleted words. Whitespace-tokenized, so scripts written without word
/// separators (Japanese, Chinese) compare in coarser runs — a documented v1 limitation.
enum PDFTextDiff {
    struct Result: Equatable, Sendable {
        var insertedWords: Int
        var deletedWords: Int
        /// False when either side exceeded `maxComparedWords` and the diff fell back to a
        /// whole-page equality check instead of exact counts.
        var comparedExhaustively: Bool
        var hasChanges: Bool

        static let unchanged = Result(
            insertedWords: 0, deletedWords: 0, comparedExhaustively: true, hasChanges: false
        )
    }

    /// Beyond this many words per side, the O(n·m) LCS is too slow for an interactive
    /// panel; the diff degrades to "changed / unchanged".
    static let maxComparedWords = 1_500

    static func diff(old: String, new: String) -> Result {
        let oldWords = tokenize(old)
        let newWords = tokenize(new)
        if oldWords == newWords { return .unchanged }
        guard oldWords.count <= maxComparedWords, newWords.count <= maxComparedWords else {
            return Result(insertedWords: 0, deletedWords: 0, comparedExhaustively: false, hasChanges: true)
        }
        let common = lcsLength(oldWords, newWords)
        return Result(
            insertedWords: newWords.count - common,
            deletedWords: oldWords.count - common,
            comparedExhaustively: true,
            hasChanges: true
        )
    }

    private static func tokenize(_ text: String) -> [String] {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).map(String.init)
    }

    /// Two-row LCS over interned word ids — the classic DP, kept allocation-light.
    private static func lcsLength(_ old: [String], _ new: [String]) -> Int {
        guard !old.isEmpty, !new.isEmpty else { return 0 }
        var ids: [String: Int] = [:]
        func intern(_ word: String) -> Int {
            if let id = ids[word] { return id }
            let id = ids.count
            ids[word] = id
            return id
        }
        let oldIDs = old.map(intern)
        let newIDs = new.map(intern)

        var previous = [Int](repeating: 0, count: newIDs.count + 1)
        var current = [Int](repeating: 0, count: newIDs.count + 1)
        for row in 1...oldIDs.count {
            let oldID = oldIDs[row - 1]
            for column in 1...newIDs.count {
                if oldID == newIDs[column - 1] {
                    current[column] = previous[column - 1] + 1
                } else {
                    current[column] = max(previous[column], current[column - 1])
                }
            }
            swap(&previous, &current)
        }
        return previous[newIDs.count]
    }
}
