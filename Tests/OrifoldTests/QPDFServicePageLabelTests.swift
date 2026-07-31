import XCTest
@testable import Orifold

/// `/PageLabels` presence detection. PDFKit cannot answer this question -- it
/// synthesizes "1", "2", "3" for documents that carry no number tree -- so the
/// catalog probe is what separates a real label from an invented one.
final class QPDFServicePageLabelTests: XCTestCase {

    func testReportsPageLabelsPresentWhenCatalogCarriesNumberTree() {
        XCTAssertTrue(QPDFService.hasPageLabels(fixture("page-labels.pdf")))
    }

    func testReportsPageLabelsAbsentWhenCatalogHasNoNumberTree() {
        XCTAssertFalse(QPDFService.hasPageLabels(fixture("no-page-labels.pdf")))
    }

    /// The two documents below render byte-identical labels through PDFKit
    /// (["1","2","3","4"]); only the catalog distinguishes them. This is the
    /// test that would fail if anyone ever "simplified" the gate to compare
    /// PDFPage.label against the ordinal.
    func testDistinguishesTrivialDecimalLabelsFromNoLabelsAtAll() {
        XCTAssertTrue(QPDFService.hasPageLabels(fixture("page-labels-decimal.pdf")))
        XCTAssertFalse(QPDFService.hasPageLabels(fixture("no-page-labels.pdf")))
    }

    func testReportsPageLabelsAbsentForUnreadableBytes() {
        XCTAssertFalse(QPDFService.hasPageLabels(Data("not a pdf".utf8)))
        XCTAssertFalse(QPDFService.hasPageLabels(Data()))
    }

    // MARK: - Fixtures

    private func fixture(_ name: String) -> Data {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(name)")
        // swiftlint:disable:next force_try
        return try! Data(contentsOf: url)
    }
}
