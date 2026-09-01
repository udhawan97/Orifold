import XCTest
@testable import Orifold

final class ScanCleanupAccessibilityTests: XCTestCase {
    private static let locales = ["en", "es", "fr", "hi", "ja", "zh-Hans"]

    func testCleanupOptionsExposeThreeOrderedDistinctLocalizedSemanticDescriptors() {
        for identifier in Self.locales {
            let locale = Locale(identifier: identifier)
            let descriptors = [
                ScanCleanupOptionAccessibility(
                    titleKey: "scanCleanup.option.deskew",
                    detailKey: "scanCleanup.option.deskew.detail",
                    isOn: false,
                    locale: locale
                ),
                ScanCleanupOptionAccessibility(
                    titleKey: "scanCleanup.option.binarize",
                    detailKey: "scanCleanup.option.binarize.detail",
                    isOn: true,
                    locale: locale
                ),
                ScanCleanupOptionAccessibility(
                    titleKey: "scanCleanup.option.despeckle",
                    detailKey: "scanCleanup.option.despeckle.detail",
                    isOn: false,
                    locale: locale
                ),
            ]

            XCTAssertEqual(
                descriptors.map(\.label),
                [
                    L10n.string("scanCleanup.option.deskew", locale: locale),
                    L10n.string("scanCleanup.option.binarize", locale: locale),
                    L10n.string("scanCleanup.option.despeckle", locale: locale),
                ],
                identifier
            )
            XCTAssertEqual(descriptors.map(\.isOn), [false, true, false], identifier)
            XCTAssertEqual(
                descriptors.map(\.hint),
                [
                    L10n.string("scanCleanup.option.deskew.detail", locale: locale),
                    L10n.string("scanCleanup.option.binarize.detail", locale: locale),
                    L10n.string("scanCleanup.option.despeckle.detail", locale: locale),
                ],
                identifier
            )
            XCTAssertEqual(Set(descriptors.map(\.label)).count, 3, identifier)
            XCTAssertEqual(Set(descriptors.map(\.hint)).count, 3, identifier)
            XCTAssertTrue(descriptors.allSatisfy { !$0.label.isEmpty && !$0.hint.isEmpty }, identifier)
        }
    }

}
