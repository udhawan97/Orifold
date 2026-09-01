import XCTest
@testable import Orifold

/// Format-specifier agreement across the six shipped languages.
///
/// `L10n.format` is `String(format:arguments:)` over `CVarArg` — a positional
/// passthrough with no reordering layer. So when a translation puts the
/// arguments in a different order from English (natural in ja, zh-Hans and hi),
/// it MUST say so with explicit `%1$`/`%2$` markers. Without them the arguments
/// bind left to right, and a slot that changed type between languages hands
/// `String(format:)` an `Int` where it expects an object pointer — which
/// segfaults rather than printing something odd.
///
/// `LocalizationCoverageTests` cannot catch this: every one of these strings is
/// fully translated. Only the shape disagrees.
final class LocalizationFormatSpecifierTests: XCTestCase {

    private static let languages = ["es", "fr", "hi", "ja", "zh-Hans"]

    func testEveryTranslationBindsTheSameArgumentTypesAsEnglish() throws {
        let catalog = try loadCatalog()
        var problems: [String] = []

        for (key, entry) in catalog.sorted(by: { $0.key < $1.key }) {
            guard let english = entry["en"] else { continue }
            let englishTypes = specifierTypes(in: english)
            guard !englishTypes.isEmpty else { continue }

            for language in Self.languages {
                guard let translated = entry[language] else { continue }
                for (slot, type) in specifierTypes(in: translated) {
                    guard let expected = englishTypes[slot] else {
                        problems.append(
                            "\(key) [\(language)]: binds argument \(slot + 1), but English has only "
                                + "\(englishTypes.count) — \"\(translated)\""
                        )
                        continue
                    }
                    if expected != type {
                        problems.append(
                            "\(key) [\(language)]: argument \(slot + 1) is %\(type) here but "
                                + "%\(expected) in English — \"\(translated)\". "
                                + "Reordered translations need explicit %1$/%2$ markers; without them "
                                + "String(format:) crashes when the types differ."
                        )
                    }
                }
            }
        }

        XCTAssertTrue(
            problems.isEmpty,
            "Format specifiers disagree with English:\n" + problems.joined(separator: "\n")
        )
    }

    func testScanCleanupSemanticConflictHasExactlyOneIntegerArgumentInEveryLocale() throws {
        let entry = try XCTUnwrap(loadCatalog()["status.scanCleanup.semanticConflict"])

        for language in ["en"] + Self.languages {
            let value = try XCTUnwrap(entry[language], "Missing \(language) translation")
            XCTAssertEqual(specifierTypes(in: value), [0: "lld"], "\(language): \(value)")
        }
    }

    // MARK: - Parsing

    /// Maps zero-based argument slot to its specifier type. Honors explicit
    /// `%N$` positions; otherwise slots are assigned left to right, exactly as
    /// `String(format:)` binds them. `%%` is an escape, not an argument.
    private func specifierTypes(in format: String) -> [Int: String] {
        let pattern = #"%(?:(\d+)\$)?(@|lld|ld|d|%)"#
        // swiftlint:disable:next force_try
        let regex = try! NSRegularExpression(pattern: pattern)
        let range = NSRange(format.startIndex..., in: format)

        var types: [Int: String] = [:]
        var nextSequentialSlot = 0

        for match in regex.matches(in: format, range: range) {
            guard let typeRange = Range(match.range(at: 2), in: format) else { continue }
            let type = String(format[typeRange])
            if type == "%" { continue }

            let slot: Int
            if let positionRange = Range(match.range(at: 1), in: format),
               let explicit = Int(format[positionRange]) {
                slot = explicit - 1
            } else {
                slot = nextSequentialSlot
                nextSequentialSlot += 1
            }
            types[slot] = type
        }
        return types
    }

    // MARK: - Catalog

    /// `[key: [language: value]]`, read from source rather than the bundle so
    /// this runs identically under SwiftPM and Xcode.
    private func loadCatalog() throws -> [String: [String: String]] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Orifold/Resources/Localizable.xcstrings")
        let data = try Data(contentsOf: url)
        let root = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let strings = try XCTUnwrap(root["strings"] as? [String: Any])

        var catalog: [String: [String: String]] = [:]
        for (key, raw) in strings {
            guard let entry = raw as? [String: Any],
                  let localizations = entry["localizations"] as? [String: Any] else { continue }
            var byLanguage: [String: String] = [:]
            for (language, payload) in localizations {
                guard let payload = payload as? [String: Any],
                      let unit = payload["stringUnit"] as? [String: Any],
                      let value = unit["value"] as? String else { continue }
                byLanguage[language] = value
            }
            catalog[key] = byLanguage
        }
        return catalog
    }
}
