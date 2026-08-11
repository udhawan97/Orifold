import Foundation
import XCTest
@testable import Orifold

final class LocalizationBundleSelectionTests: XCTestCase {
    func testSwiftPackageRawCatalogUsesTheRequestedRegionalLanguage() {
        XCTAssertEqual(
            L10n.string("emptyState.headline", locale: Locale(identifier: "ja_JP")),
            "バラバラのページを1つの整ったPDFに。"
        )
        XCTAssertEqual(
            L10n.string("emptyState.headline", locale: Locale(identifier: "zh_CN")),
            "把零散的页面折叠成一份精美的 PDF。"
        )
    }

    func testJapaneseLocaleSelectsJapaneseResourcesInsteadOfHostPreference() throws {
        let fixture = try makeLocalizedBundle()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        let selected = L10n.localizedBundle(
            for: Locale(identifier: "ja_JP"),
            in: fixture.bundle
        )

        XCTAssertEqual(
            selected.localizedString(forKey: "fixture.headline", value: nil, table: nil),
            "日本語"
        )
    }

    func testSimplifiedChineseRegionSelectsHansResources() throws {
        let fixture = try makeLocalizedBundle()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        let selected = L10n.localizedBundle(
            for: Locale(identifier: "zh_CN"),
            in: fixture.bundle
        )

        XCTAssertEqual(
            selected.localizedString(forKey: "fixture.headline", value: nil, table: nil),
            "简体中文"
        )
    }

    func testUnsupportedLocaleFallsBackToEnglishResources() throws {
        let fixture = try makeLocalizedBundle()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        let selected = L10n.localizedBundle(
            for: Locale(identifier: "de_DE"),
            in: fixture.bundle
        )

        XCTAssertEqual(
            selected.localizedString(forKey: "fixture.headline", value: nil, table: nil),
            "English"
        )
    }

    private func makeLocalizedBundle() throws -> (rootURL: URL, bundle: Bundle) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrifoldLocalizationTests-\(UUID().uuidString).bundle")
        let contents = root.appendingPathComponent("Contents")
        let resources = contents.appendingPathComponent("Resources")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)

        let info: [String: Any] = [
            "CFBundleIdentifier": "com.ud.Orifold.LocalizationTests.\(UUID().uuidString)",
            "CFBundleDevelopmentRegion": "en",
            "CFBundleLocalizations": ["en", "ja", "zh-Hans"]
        ]
        let infoData = try PropertyListSerialization.data(
            fromPropertyList: info,
            format: .xml,
            options: 0
        )
        try infoData.write(to: contents.appendingPathComponent("Info.plist"))

        try writeStrings(language: "en", value: "English", resources: resources)
        try writeStrings(language: "ja", value: "日本語", resources: resources)
        try writeStrings(language: "zh-Hans", value: "简体中文", resources: resources)

        let bundle = try XCTUnwrap(Bundle(url: root))
        return (root, bundle)
    }

    private func writeStrings(language: String, value: String, resources: URL) throws {
        let directory = resources.appendingPathComponent("\(language).lproj")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try "\"fixture.headline\" = \"\(value)\";\n"
            .write(
                to: directory.appendingPathComponent("Localizable.strings"),
                atomically: true,
                encoding: .utf8
            )
    }
}
