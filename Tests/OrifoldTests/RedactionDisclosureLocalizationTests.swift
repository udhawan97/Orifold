import XCTest

final class RedactionDisclosureLocalizationTests: XCTestCase {
    func testDecisionPointCopyDisclosesPageScaleVectorPolicyInEveryLocale() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("Orifold/Resources/Localizable.xcstrings"))
        let catalog = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try XCTUnwrap(catalog["strings"] as? [String: Any])
        let keys = [
            "annotationTool.redact.helpText",
            "redaction.confirm.message",
            "status.redaction.applied",
            "status.redaction.pageScaleVector",
        ]
        let localeMarkers = [
            "en": "vector",
            "es": "vectorial",
            "fr": "vectoriel",
            "hi": "वेक्टर",
            "ja": "ベクター",
            "zh-Hans": "矢量",
        ]

        for key in keys {
            let entry = try XCTUnwrap(strings[key] as? [String: Any])
            let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any])
            for (locale, marker) in localeMarkers {
                let localization = try XCTUnwrap(localizations[locale] as? [String: Any], "\(key) missing \(locale)")
                let unit = try XCTUnwrap(localization["stringUnit"] as? [String: Any])
                let value = try XCTUnwrap(unit["value"] as? String)
                XCTAssertTrue(value.localizedCaseInsensitiveContains(marker), "\(key) does not disclose the vector limit in \(locale)")
            }
        }
    }
}
