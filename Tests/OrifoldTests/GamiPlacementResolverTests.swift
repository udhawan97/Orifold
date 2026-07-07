import XCTest
@testable import Orifold

final class GamiPlacementResolverTests: XCTestCase {
    private let container = CGRect(x: 0, y: 0, width: 1000, height: 800)
    private let chip = CGRect(x: 900, y: 700, width: 60, height: 60)
    private let bubbleSize = CGSize(width: 200, height: 80)

    func testDefaultPlacementIsAboveChipWhenNothingBlocks() {
        let placement = GamiPlacementResolver.resolve(
            chipFrame: chip,
            bubbleSize: bubbleSize,
            containerBounds: container,
            exclusions: .empty,
            bubbleGap: 12,
            edgeInset: 16,
            contentClearance: 24
        )
        guard case .aboveChip(let origin) = placement else {
            return XCTFail("expected aboveChip, got \(placement)")
        }
        // Trailing-aligned with the chip.
        XCTAssertEqual(origin.x, chip.maxX - bubbleSize.width, accuracy: 0.001)
        XCTAssertLessThan(origin.y + bubbleSize.height, chip.minY)
    }

    func testFallsBackToLeadingWhenAboveCollides() {
        // Exclude only the area directly above the chip (not the leading side); a
        // small clearance keeps the two candidates from bleeding into each other.
        let aboveOrigin = CGPoint(x: chip.maxX - bubbleSize.width, y: chip.minY - 12 - bubbleSize.height)
        let exclusion = GamiExclusionContext(
            selectionRects: [CGRect(origin: aboveOrigin, size: bubbleSize)]
        )
        let placement = GamiPlacementResolver.resolve(
            chipFrame: chip,
            bubbleSize: bubbleSize,
            containerBounds: container,
            exclusions: exclusion,
            bubbleGap: 12,
            edgeInset: 16,
            contentClearance: 0
        )
        guard case .leadingChip(let origin) = placement else {
            return XCTFail("expected leadingChip, got \(placement)")
        }
        XCTAssertLessThan(origin.x + bubbleSize.width, chip.minX)
    }

    func testCollapsesToHintChipWhenNothingFits() {
        // Exclude essentially the whole container.
        let exclusion = GamiExclusionContext(
            selectionRects: [container]
        )
        let placement = GamiPlacementResolver.resolve(
            chipFrame: chip,
            bubbleSize: bubbleSize,
            containerBounds: container,
            exclusions: exclusion,
            bubbleGap: 12,
            edgeInset: 16,
            contentClearance: 24
        )
        XCTAssertEqual(placement, .hintChip)
    }

    func testNeverExceedsContainerSafeBounds() {
        // A chip pinned right at the container's corner, tiny container — the
        // resolver must not place a bubble outside the edge-inset safe area.
        let tinyContainer = CGRect(x: 0, y: 0, width: 300, height: 200)
        let cornerChip = CGRect(x: 240, y: 140, width: 56, height: 56)
        let placement = GamiPlacementResolver.resolve(
            chipFrame: cornerChip,
            bubbleSize: bubbleSize,
            containerBounds: tinyContainer,
            exclusions: .empty,
            bubbleGap: 12,
            edgeInset: 16,
            contentClearance: 24
        )
        if let origin = placement.origin {
            let bubbleRect = CGRect(origin: origin, size: bubbleSize)
            let safeBounds = tinyContainer.insetBy(dx: 16, dy: 16)
            XCTAssertTrue(safeBounds.contains(bubbleRect), "bubble \(bubbleRect) escaped safe bounds \(safeBounds)")
        } else {
            XCTAssertEqual(placement, .hintChip)
        }
    }

    func testExclusionRectIsInflatedByContentClearance() {
        // A selection rect that ends exactly where the default bubble would start
        // (no gap) should still push placement away once inflated by clearance.
        let aboveOrigin = CGPoint(x: chip.maxX - bubbleSize.width, y: chip.minY - 12 - bubbleSize.height)
        let tightSize = CGSize(width: bubbleSize.width, height: bubbleSize.height + 1)
        let tightRect = CGRect(origin: aboveOrigin, size: tightSize)
        let exclusion = GamiExclusionContext(selectionRects: [tightRect])
        let placement = GamiPlacementResolver.resolve(
            chipFrame: chip,
            bubbleSize: bubbleSize,
            containerBounds: container,
            exclusions: exclusion,
            bubbleGap: 12,
            edgeInset: 16,
            contentClearance: 24
        )
        XCTAssertNotEqual(placement, .aboveChip(origin: aboveOrigin))
    }
}
