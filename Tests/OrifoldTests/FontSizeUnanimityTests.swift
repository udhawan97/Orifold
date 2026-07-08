import XCTest
@testable import Orifold

/// WP-B.3: `PDFTextAnalysisEngine.resolvedSize` — trust a unanimous reported font size over
/// the ink estimate unless it contradicts it catastrophically (content-stream-scaled text).
/// A pure function so it can be tested directly (generated CoreText fixtures carry no
/// PDFium-reported sizes, so this path can't be exercised end-to-end there).
final class FontSizeUnanimityTests: XCTestCase {
    func testUnanimousReportedSizeIsTrustedOverSmallInkDrift() {
        // 8 glyphs all report 12.0; ink model estimates 12.9 (a ~7% metric drift). Trust 12.0.
        let resolved = PDFTextAnalysisEngine.resolvedSize(reported: 12.0, sampleCount: 8, spread: 0.0, inkEstimate: 12.9)
        XCTAssertEqual(resolved, 12.0, accuracy: 0.001, "a unanimous reported size wins over a small ink-model drift")
    }

    func testUnanimousReportedSizeRejectedWhenCatastrophicallyContradicted() {
        // Content-stream-scaled text: nominal Tf 24 but the glyphs are drawn at ~12pt (est 12).
        // 24 > 12 * 1.35 → reject the reported size, keep the visible (ink) size.
        let resolved = PDFTextAnalysisEngine.resolvedSize(reported: 24.0, sampleCount: 20, spread: 0.0, inkEstimate: 12.0)
        XCTAssertEqual(resolved, 12.0, accuracy: 0.001, "a reported size that grossly disagrees with visible ink must lose")
    }

    func testSparseOrDisagreeingReportedSizesUseNarrowBand() {
        // Only 2 samples (not unanimous): the historical narrow band applies. Reported 13 vs
        // estimate 12 → within 1.08× → accepted. Reported 20 vs 12 → outside band → estimate.
        XCTAssertEqual(PDFTextAnalysisEngine.resolvedSize(reported: 12.9, sampleCount: 2, spread: 0.0, inkEstimate: 12.0), 12.9, accuracy: 0.001)
        XCTAssertEqual(PDFTextAnalysisEngine.resolvedSize(reported: 20.0, sampleCount: 2, spread: 0.0, inkEstimate: 12.0), 12.0, accuracy: 0.001)
    }

    func testWideSpreadDisqualifiesUnanimity() {
        // Many samples but wide spread (10..14): not unanimous → narrow band, so a reported
        // median of 14 that's outside 1.08× of estimate 12 falls back to the estimate.
        let resolved = PDFTextAnalysisEngine.resolvedSize(reported: 14.0, sampleCount: 10, spread: 4.0, inkEstimate: 12.0)
        XCTAssertEqual(resolved, 12.0, accuracy: 0.001, "wide-spread reported sizes don't earn unanimity trust")
    }

    func testZeroInkEstimateFallsBackToReported() {
        XCTAssertEqual(PDFTextAnalysisEngine.resolvedSize(reported: 11.0, sampleCount: 6, spread: 0.0, inkEstimate: 0), 11.0, accuracy: 0.001)
    }
}
