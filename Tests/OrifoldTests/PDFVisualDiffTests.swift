import CoreGraphics
import XCTest
@testable import Orifold

final class PDFVisualDiffTests: XCTestCase {
    func testIdenticalImagesReportNoChanges() throws {
        let image = try solidImage()
        let result = PDFVisualDiff.diff(image, try solidImage())
        XCTAssertFalse(result.hasChanges)
        XCTAssertEqual(result.changedFraction, 0)
        XCTAssertTrue(result.changedRects.isEmpty)
    }

    func testBlackSquareIsLocatedInNormalizedCoordinates() throws {
        let blank = try solidImage()
        // CGContext coordinates are bottom-left-origin: this square fills the TOP-LEFT
        // visual quadrant (x 0…100, y 100…200 of a 200-point canvas).
        let marked = try solidImage { context in
            context.setFillColor(gray: 0, alpha: 1)
            context.fill(CGRect(x: 0, y: 100, width: 100, height: 100))
        }

        let result = PDFVisualDiff.diff(blank, marked)

        XCTAssertTrue(result.hasChanges)
        let union = result.changedRects.reduce(CGRect.null) { $0.union($1) }
        XCTAssertEqual(union.minX, 0, accuracy: 0.06)
        XCTAssertEqual(union.maxX, 0.5, accuracy: 0.06)
        XCTAssertEqual(union.minY, 0.5, accuracy: 0.06)
        XCTAssertEqual(union.maxY, 1.0, accuracy: 0.06)
        XCTAssertEqual(result.changedFraction, 0.25, accuracy: 0.06)
    }

    func testFaintDifferenceBelowThresholdIsIgnored() throws {
        let blank = try solidImage()
        let faint = try solidImage { context in
            context.setFillColor(gray: 0.95, alpha: 1)
            context.fill(CGRect(x: 40, y: 40, width: 120, height: 120))
        }
        XCTAssertFalse(PDFVisualDiff.diff(blank, faint).hasChanges)
    }

    func testDifferentResolutionsOfTheSameContentCompareEqual() throws {
        // Left half black in both renders; the grid resample normalizes the sizes away.
        let large = try solidImage(width: 200, height: 200) { context in
            context.setFillColor(gray: 0, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: 100, height: 200))
        }
        let small = try solidImage(width: 100, height: 100) { context in
            context.setFillColor(gray: 0, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: 50, height: 100))
        }
        let result = PDFVisualDiff.diff(large, small)
        XCTAssertLessThan(result.changedFraction, 0.05)
    }

    func testChangedFractionTracksPaintedArea() throws {
        let quarter = try solidImage { context in
            context.setFillColor(gray: 0, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        }
        let half = try solidImage { context in
            context.setFillColor(gray: 0, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: 100, height: 200))
        }
        // The differing region is the quarter above the shared quarter.
        let result = PDFVisualDiff.diff(quarter, half)
        XCTAssertEqual(result.changedFraction, 0.25, accuracy: 0.06)
    }

    // MARK: - Fixtures

    private func solidImage(
        width: Int = 200,
        height: Int = 200,
        draw: ((CGContext) -> Void)? = nil
    ) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ))
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        draw?(context)
        return try XCTUnwrap(context.makeImage())
    }
}
