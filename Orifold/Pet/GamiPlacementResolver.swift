import CoreGraphics

/// Where a Gami hint bubble should render relative to the companion chip, resolved
/// against the current exclusion zones. `origin` is the bubble's top-leading point
/// in the overlay's coordinate space (y grows downward, matching SwiftUI/AppKit
/// overlay geometry as used by `GamiCompanionOverlay`).
enum GamiPlacement: Equatable {
    /// Bubble sits above the chip, trailing-aligned — the default, with a
    /// down-pointing anchor notch.
    case aboveChip(origin: CGPoint)
    /// Bubble sits to the leading (left) side of the chip, vertically centered,
    /// with a right-pointing anchor notch.
    case leadingChip(origin: CGPoint)
    /// Bubble sits above the chip but shifted left to dodge a collision, with a
    /// down-pointing anchor notch offset from center.
    case shifted(origin: CGPoint)
    /// No room for a bubble anywhere safe: collapse to a small hint-chip badge on
    /// the companion chip itself instead of floating free content.
    case hintChip

    var origin: CGPoint? {
        switch self {
        case .aboveChip(let o), .leadingChip(let o), .shifted(let o): return o
        case .hintChip: return nil
        }
    }

    /// Which edge of the bubble the anchor notch should point from, toward the chip.
    var notchEdge: GamiNotchEdge? {
        switch self {
        case .aboveChip, .shifted: return .bottom
        case .leadingChip: return .trailing
        case .hintChip: return nil
        }
    }
}

enum GamiNotchEdge {
    case bottom
    case trailing
}

/// Pure geometry resolver: given the chip's frame, the bubble's size, the
/// container's safe bounds, and the current exclusion zones, picks the first
/// candidate placement that doesn't collide with anything — falling back to a
/// collapsed hint-chip badge if nothing fits. No SwiftUI dependency, so this is
/// exercised directly by unit tests.
enum GamiPlacementResolver {
    /// - Parameters:
    ///   - chipFrame: the companion chip's current (possibly hover-scaled) frame,
    ///     in the overlay's coordinate space.
    ///   - bubbleSize: the size the bubble would render at.
    ///   - containerBounds: the overlay's full bounds (the workspace window area).
    ///   - exclusions: zones the bubble must not intersect, already inflated by the
    ///     caller if extra clearance beyond `edgeInset` is desired.
    ///   - bubbleGap: minimum gap between chip and bubble.
    ///   - edgeInset: minimum inset from `containerBounds`' edges.
    ///   - contentClearance: minimum clearance from any exclusion rect.
    static func resolve(
        chipFrame: CGRect,
        bubbleSize: CGSize,
        containerBounds: CGRect,
        exclusions: GamiExclusionContext,
        bubbleGap: CGFloat,
        edgeInset: CGFloat,
        contentClearance: CGFloat
    ) -> GamiPlacement {
        let safeBounds = containerBounds.insetBy(dx: edgeInset, dy: edgeInset)
        let inflatedExclusions = exclusions.allRects.map { $0.insetBy(dx: -contentClearance, dy: -contentClearance) }

        func fits(_ rect: CGRect) -> Bool {
            guard safeBounds.contains(rect) else { return false }
            return !inflatedExclusions.contains { $0.intersects(rect) }
        }

        // A. Above the chip, trailing-aligned (bubble's trailing edge lines up with
        // the chip's trailing edge).
        let aboveOrigin = CGPoint(
            x: chipFrame.maxX - bubbleSize.width,
            y: chipFrame.minY - bubbleGap - bubbleSize.height
        )
        let aboveRect = CGRect(origin: aboveOrigin, size: bubbleSize)
        if fits(aboveRect) {
            return .aboveChip(origin: aboveOrigin)
        }

        // B. Leading (left) of the chip, vertically centered.
        let leadingOrigin = CGPoint(
            x: chipFrame.minX - bubbleGap - bubbleSize.width,
            y: chipFrame.midY - bubbleSize.height / 2
        )
        let leadingRect = CGRect(origin: leadingOrigin, size: bubbleSize)
        if fits(leadingRect) {
            return .leadingChip(origin: leadingOrigin)
        }

        // C. Above the chip, shifted left up to 96pt to dodge a collision.
        let maxShift: CGFloat = 96
        let shiftStep: CGFloat = 24
        var shift: CGFloat = shiftStep
        while shift <= maxShift {
            let shiftedOrigin = CGPoint(x: aboveOrigin.x - shift, y: aboveOrigin.y)
            let shiftedRect = CGRect(origin: shiftedOrigin, size: bubbleSize)
            if fits(shiftedRect) {
                return .shifted(origin: shiftedOrigin)
            }
            shift += shiftStep
        }

        // D. Nothing fits safely — collapse to the hint-chip badge.
        return .hintChip
    }
}
