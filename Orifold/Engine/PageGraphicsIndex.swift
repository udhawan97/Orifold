import Foundation

/// A lightweight classification of a page's thin vector PATH objects into "rule lines" —
/// the horizontal and vertical strokes that make up table grids, cell separators, footer
/// dividers, and text underlines. Built once per page during PDFium analysis (see
/// `PDFTextAnalysisEngine.pathRuleRegions`) from the page-object API that is already linked
/// and used for render-mode detection, so it costs one extra bounds-only pass.
///
/// Everything here is expressed in RAW (unrotated) page/content-stream coordinates — the
/// same space `EditableTextBlock.bounds` and the inline-edit geometry use — so consumers
/// (underline detection, table-aware merge/split vetoes, erase-patch clipping, Match-Format
/// grid exclusion) can compare directly without any coordinate conversion.
struct PageGraphicsIndex: Equatable {
    /// A thin stroked rectangle: a table rule, separator, or text underline. `bounds` is the
    /// object's reported bounding box; a rule's "thickness" is its short side.
    struct RuleLine: Equatable {
        var bounds: CGRect
        var isHorizontal: Bool
    }

    var horizontalRules: [RuleLine] = []
    var verticalRules: [RuleLine] = []

    /// True when the object-object scan hit its safety cap and stopped early, so consumers
    /// know the rule set may be incomplete (they still degrade gracefully — a missing rule
    /// just means the pre-graphics-index behavior for that region).
    var didTruncateScan: Bool = false

    var isEmpty: Bool { horizontalRules.isEmpty && verticalRules.isEmpty }

    static let empty = PageGraphicsIndex()

    // MARK: - Classification

    /// The largest short-side thickness (in points) a stroked rect may have and still count
    /// as a "rule" rather than a filled block/box. Table rules and underlines are hairline
    /// to a couple of points; anything thicker is treated as fill, not a line.
    static let maxRuleThickness: CGFloat = 2.5
    /// The minimum long-side length for a rule — shorter marks (stray ticks, glyph fragments
    /// mis-reported as paths) are ignored.
    static let minRuleLength: CGFloat = 6
    /// A rule is "horizontal" when its long side is at least this multiple of its short side.
    static let ruleAspectRatio: CGFloat = 4

    /// Classifies a path object's bounds as a rule line, or returns nil if it isn't thin
    /// enough (a filled box, a square, or too short to be a separator).
    static func classify(bounds rect: CGRect) -> RuleLine? {
        let box = rect.standardized
        guard box.width.isFinite, box.height.isFinite else { return nil }
        let shortSide = min(box.width, box.height)
        let longSide = max(box.width, box.height)
        guard shortSide <= maxRuleThickness,
              longSide >= minRuleLength,
              longSide >= shortSide * ruleAspectRatio else {
            return nil
        }
        return RuleLine(bounds: box, isHorizontal: box.width >= box.height)
    }

    mutating func add(_ rule: RuleLine) {
        if rule.isHorizontal { horizontalRules.append(rule) } else { verticalRules.append(rule) }
    }

    // MARK: - Queries used by the editing pipeline

    /// A horizontal rule that plausibly underlines the run occupying `runBounds` with the
    /// given `baseline` and `fontSize`: it sits just below the baseline and overlaps the
    /// run's x-range enough to be that run's underline (not an unrelated separator).
    func underlineRule(forRun runBounds: CGRect, baseline: CGFloat, fontSize: CGFloat) -> RuleLine? {
        let run = runBounds.standardized
        guard run.width > 0, fontSize > 0 else { return nil }
        // The stroke centre lives in a band from a little below the baseline up to a hair
        // above it (PDF underlines are typically ~0.05–0.15em below the baseline).
        let lowerBound = baseline - fontSize * 0.35
        let upperBound = baseline + fontSize * 0.08
        return horizontalRules.first { rule in
            let midY = rule.bounds.midY
            guard midY >= lowerBound, midY <= upperBound else { return false }
            let overlap = min(rule.bounds.maxX, run.maxX) - max(rule.bounds.minX, run.minX)
            return overlap >= run.width * 0.6
        }
    }

    /// True when a horizontal rule separates the two vertical bands `upper` and `lower`
    /// (upper sits higher in y-up page space): a rule whose y is between the two bands and
    /// which spans at least half their combined x-range. Used to veto merging text across a
    /// table rule. `ignoring` excludes rules already claimed as the upper block's underline.
    func hasHorizontalRuleBetween(_ upper: CGRect, _ lower: CGRect, ignoring: [CGRect] = []) -> Bool {
        let upperBox = upper.standardized
        let lowerBox = lower.standardized
        let top = max(upperBox.minY, lowerBox.minY)
        let bottom = min(upperBox.maxY, lowerBox.maxY)
        guard top >= bottom else { return false } // overlapping bands — no clean separator
        let unionMinX = min(upperBox.minX, lowerBox.minX)
        let unionMaxX = max(upperBox.maxX, lowerBox.maxX)
        let unionWidth = unionMaxX - unionMinX
        guard unionWidth > 0 else { return false }
        return horizontalRules.contains { rule in
            let center = CGPoint(x: rule.bounds.midX, y: rule.bounds.midY)
            guard !ignoring.contains(where: { $0.standardized.insetBy(dx: -0.5, dy: -0.5).contains(center) }) else {
                return false
            }
            let midY = rule.bounds.midY
            guard midY <= top, midY >= bottom else { return false }
            let overlap = min(rule.bounds.maxX, unionMaxX) - max(rule.bounds.minX, unionMinX)
            return overlap >= unionWidth * 0.5
        }
    }

    /// The x-position of a vertical rule that falls strictly inside the horizontal gap
    /// `(leftMaxX ..< rightMinX)` and overlaps `yBand` vertically — i.e. a genuine column
    /// gutter between two glyph clusters on the same line. Returns nil when no rule splits
    /// that gap.
    func verticalRuleSplittingGap(leftMaxX: CGFloat, rightMinX: CGFloat, yBand: ClosedRange<CGFloat>) -> CGFloat? {
        guard rightMinX > leftMaxX else { return nil }
        return verticalRules.first { rule in
            let ruleX = rule.bounds.midX
            guard ruleX > leftMaxX, ruleX < rightMinX else { return false }
            // The rule must actually run through this line's vertical band, not just clip it.
            return rule.bounds.maxY >= yBand.lowerBound && rule.bounds.minY <= yBand.upperBound
        }?.bounds.midX
    }

    /// The rule rects (horizontal and vertical) that sit close enough to `rect` that an
    /// erase patch covering `rect` could paint over them — within `margin` points of the
    /// box. Excludes any rule listed in `excluding` (typically the block's own underline,
    /// which is meant to be erased, not preserved). Used to punch holes in the erase patch
    /// so editing a table cell never wipes the surrounding rules.
    func rulesNear(_ rect: CGRect, margin: CGFloat, excluding: [CGRect] = []) -> [CGRect] {
        let box = rect.standardized.insetBy(dx: -margin, dy: -margin)
        func isExcluded(_ rect: CGRect) -> Bool {
            excluding.contains { $0.standardized.insetBy(dx: -0.5, dy: -0.5).intersects(rect.standardized) }
        }
        return (horizontalRules + verticalRules)
            .map(\.bounds)
            .filter { $0.standardized.intersects(box) && !isExcluded($0) }
    }

    /// True when `rect` sits inside a ruled grid — it is FLANKED by vertical rules on both
    /// sides (a table cell lives BETWEEN rules, not on them) within a cell-width reach, and
    /// each flanking rule vertically overlaps the box. Used to exclude table cells from
    /// body-style Match inference when the edit target is not itself in a grid.
    func isInsideRuledGrid(_ rect: CGRect, maxCellReach: CGFloat = 400) -> Bool {
        let box = rect.standardized
        func overlapsVertically(_ rule: CGRect) -> Bool {
            rule.maxY >= box.minY && rule.minY <= box.maxY
        }
        let hasLeft = verticalRules.contains { rule in
            rule.bounds.midX <= box.minX && box.minX - rule.bounds.midX <= maxCellReach
                && overlapsVertically(rule.bounds)
        }
        let hasRight = verticalRules.contains { rule in
            rule.bounds.midX >= box.maxX && rule.bounds.midX - box.maxX <= maxCellReach
                && overlapsVertically(rule.bounds)
        }
        return hasLeft && hasRight
    }
}
