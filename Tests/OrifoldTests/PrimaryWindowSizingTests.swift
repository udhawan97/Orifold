import AppKit
import XCTest
@testable import Orifold

final class PrimaryWindowSizingTests: XCTestCase {
    func testDefaultSizeIsLargerThanMinimumSize() {
        XCTAssertGreaterThan(
            PrimaryWindowSizing.defaultContentSize.width,
            PrimaryWindowSizing.minimumContentSize.width
        )
        XCTAssertGreaterThan(
            PrimaryWindowSizing.defaultContentSize.height,
            PrimaryWindowSizing.minimumContentSize.height
        )
    }

    func testMinimumMatchesTheAuditedCompactWindowSize() {
        XCTAssertEqual(PrimaryWindowSizing.minimumContentSize.width, 641)
        XCTAssertEqual(PrimaryWindowSizing.minimumContentSize.height, 500)
    }

    func testClampRepairsOnlyDimensionsBelowTheMinimum() {
        XCTAssertEqual(
            PrimaryWindowSizing.clampedContentSize(NSSize(width: 125, height: 700)),
            NSSize(width: 641, height: 700)
        )
        XCTAssertEqual(
            PrimaryWindowSizing.clampedContentSize(NSSize(width: 900, height: 110)),
            NSSize(width: 900, height: 500)
        )
        XCTAssertEqual(
            PrimaryWindowSizing.clampedContentSize(NSSize(width: 851, height: 629)),
            NSSize(width: 851, height: 629)
        )
    }

    @MainActor
    func testConfigureRepairsTinyWindowAndInstallsResizeFloor() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 125, height: 110),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )

        PrimaryWindowSizing.configure(window)

        XCTAssertEqual(window.contentMinSize, PrimaryWindowSizing.minimumContentSize)
        XCTAssertGreaterThanOrEqual(
            window.contentLayoutRect.width,
            PrimaryWindowSizing.minimumContentSize.width
        )
        XCTAssertGreaterThanOrEqual(
            window.contentLayoutRect.height,
            PrimaryWindowSizing.minimumContentSize.height
        )
    }
}
