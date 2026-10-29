import AppKit
import PDFKit
import XCTest
@testable import Orifold

/// Guards against silent fallback-to-English gaps as Localizable.xcstrings grows:
/// every key that isn't a known interpolated-format-string exception should carry
/// a non-empty translation for every supported non-English language.
final class LocalizationCoverageTests: XCTestCase {
    private static let supportedLanguages: [String] = ["es", "fr", "hi", "zh-Hans", "ja"]

    private struct CatalogEntry: Decodable {
        struct Localization: Decodable {
            struct StringUnit: Decodable {
                let value: String
            }
            let stringUnit: StringUnit?
        }
        let localizations: [String: Localization]
    }

    private struct Catalog: Decodable {
        let strings: [String: CatalogEntry]
    }

    /// Xcode compiles Localizable.xcstrings into per-locale artifacts at build
    /// time and doesn't copy the raw source into the app bundle, so this reads
    /// the source file directly (relative to this test file) rather than
    /// trying to locate it via Bundle lookup.
    private func loadCatalog() throws -> Catalog {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let catalogURL = testFileURL
            .deletingLastPathComponent() // Tests/OrifoldTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // repo root
            .appendingPathComponent("Orifold/Resources/Localizable.xcstrings")

        let data = try XCTUnwrap(
            FileManager.default.contents(atPath: catalogURL.path),
            "Localizable.xcstrings not found at expected path: \(catalogURL.path)"
        )
        return try JSONDecoder().decode(Catalog.self, from: data)
    }

    func testEveryKeyHasEnglishSource() throws {
        let catalog = try loadCatalog()
        let missingEnglish = catalog.strings
            .filter { $0.value.localizations["en"]?.stringUnit?.value.isEmpty ?? true }
            .map(\.key)
            .sorted()

        XCTAssertTrue(missingEnglish.isEmpty, "Keys missing an English source value: \(missingEnglish)")
    }

    func testCertificateTrustCaveatResolvesInEveryAppLanguageWithoutEnglishFallback() throws {
        let catalog = try loadCatalog()
        let key = "signaturePalette.certificateTrust.caveat"
        let entry = try XCTUnwrap(catalog.strings[key])
        let english = try XCTUnwrap(entry.localizations["en"]?.stringUnit?.value)

        for language in ["en"] + Self.supportedLanguages {
            let expected = try XCTUnwrap(entry.localizations[language]?.stringUnit?.value)
            let actual = CertificateGuideResource.shortPopoverCopy(locale: Locale(identifier: language))
            XCTAssertEqual(actual, expected, "Caveat did not resolve in \(language)")
            XCTAssertFalse(actual.contains(key), "Raw key leaked in \(language)")
            if language != "en" {
                XCTAssertNotEqual(actual, english, "English fallback in \(language)")
            }
            for marker in ["Orifold", "Adobe Acrobat/Reader", "AATL", ".p12"] {
                XCTAssertTrue(actual.contains(marker), "Trust caveat lost \(marker) in \(language)")
            }
        }
    }

    func testExpandedCertificateHelpDisclosesEnglishInEveryAppLanguage() {
        let englishMarkers = [
            "en": "English", "es": "inglés", "fr": "anglais",
            "hi": "अंग्रेज़ी", "ja": "英語", "zh-Hans": "英文",
        ]
        for (language, marker) in englishMarkers {
            for key in ["signaturePalette.certificateTrust.howToGetOne", "signaturePalette.certificateGuide.title"] {
                let text = L10n.string(forKey: key, locale: Locale(identifier: language))
                XCTAssertTrue(text.contains(marker), "\(key) does not disclose English in \(language)")
                XCTAssertFalse(text.contains(key), "Raw key leaked in \(language)")
            }
        }
    }

    @MainActor
    func testAnnotationEditorsResolveHeadingsAndCommitActionNamesInEveryAppLanguage() throws {
        let catalog = try loadCatalog()
        for language in ["en"] + Self.supportedLanguages {
            let locale = Locale(identifier: language)
            for (subtype, replacement, key) in [
                (PDFAnnotationSubtype.text, false, "readingCanvas.noteEditor.title"),
                (.freeText, false, "inspector.annotationType.textBox.label"),
                (.freeText, true, "undo.editPDFText"),
            ] {
                let annotation = PDFAnnotation(bounds: CGRect(x: 20, y: 20, width: 200, height: 40),
                                               forType: subtype, withProperties: nil)
                annotation.contents = "Fictional original note"
                annotation.font = .systemFont(ofSize: 16)
                annotation.fontColor = .black
                annotation.setValue(replacement, forAnnotationKey: WorkspaceViewModel.textReplacementAnnotationKey)
                var actionNames: [String] = []
                let controller = NoteEditorViewController(
                    annotation: annotation,
                    changeHandler: { _, _, actionName in actionNames.append(actionName) },
                    locale: locale
                )
                controller.loadViewIfNeeded()
                let expected = try XCTUnwrap(catalog.strings[key]?.localizations[language]?.stringUnit?.value)
                let heading = try XCTUnwrap(annotationEditorDescendants(NSTextField.self, in: controller.view)
                    .first { $0.stringValue == expected }, "Missing \(key) in \(language)")
                XCTAssertLessThanOrEqual(heading.fittingSize.width, heading.bounds.width + 0.5,
                                         "Heading clips in \(language): \(expected)")
                let textView = try XCTUnwrap(annotationEditorDescendants(NSTextView.self, in: controller.view).first)
                textView.string = "Fictional edited note"
                controller.viewWillDisappear()
                XCTAssertEqual(annotation.contents, "Fictional edited note")
                XCTAssertEqual(actionNames, [expected], "Commit action name must match the localized heading")
            }
        }
    }

    @MainActor
    func testAnnotationEditorDefaultHeadingMatchesTheCurrentAppLocale() throws {
        let expected = L10n.string("readingCanvas.noteEditor.title", locale: L10n.currentLocale)
        let note = PDFAnnotation(bounds: CGRect(x: 20, y: 20, width: 24, height: 24),
                                 forType: .text, withProperties: nil)
        let controller = NoteEditorViewController(annotation: note)
        controller.loadViewIfNeeded()
        XCTAssertTrue(annotationEditorDescendants(NSTextField.self, in: controller.view)
            .contains { $0.stringValue == expected })
    }

    @MainActor
    func testAnnotationDetailCopyResolvesWithinConservativeWidthBudgetsInEveryAppLanguage() throws {
        let catalog = try loadCatalog()
        let labels = ["type", "bounds", "font", "mode"].map { "inspector.editingDetails.\($0).label" }
        let values = ["inspector.editingDetails.editable", "inspector.editingDetails.markup"]
        // Copy-only budgets: the label is fixed at 54pt; mode copy stays within 180pt.
        // These checks do not render SwiftUI or measure the available native inspector width.
        for language in ["en"] + Self.supportedLanguages {
            let locale = Locale(identifier: language)
            for key in labels + values + ["inspector.editingDetails.title", "inspector.annotationType.generic.label"] {
                let expected = try XCTUnwrap(catalog.strings[key]?.localizations[language]?.stringUnit?.value)
                let actual = L10n.string(forKey: key, locale: locale)
                XCTAssertEqual(actual, expected, "Incorrect annotation detail translation in \(language)")
                XCTAssertFalse(actual.contains(key))
                if labels.contains(key) {
                    let width = (actual.uppercased() as NSString).size(withAttributes: [
                        .font: NSFont.systemFont(ofSize: 9, weight: .medium)
                    ]).width
                    XCTAssertLessThanOrEqual(width, 54, "Label copy exceeds its 54pt budget in \(language): \(actual)")
                } else if values.contains(key) {
                    let width = (actual as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 12)]).width
                    XCTAssertLessThanOrEqual(width, 180, "Mode copy exceeds its 180pt budget in \(language): \(actual)")
                }
            }
        }
    }

    @MainActor
    private func annotationEditorDescendants<T: NSView>(_ type: T.Type, in view: NSView) -> [T] {
        var matches = (view as? T).map { [$0] } ?? []
        for child in view.subviews {
            matches.append(contentsOf: annotationEditorDescendants(type, in: child))
        }
        return matches
    }

    /// Interpolated-format-string keys (literal Swift source containing `\(`)
    /// can't carry hand-authored translations — Xcode's build-time extraction
    /// would need to derive the real %@ format key. These are a documented,
    /// accepted exception; everything else should be fully translated.
    func testStaticKeysAreTranslatedIntoAllSupportedLanguages() throws {
        let catalog = try loadCatalog()
        var gaps: [String: [String]] = [:]

        for (key, entry) in catalog.strings {
            guard !key.contains("\\(") else { continue }

            let missingLanguages = Self.supportedLanguages.filter { lang in
                let value = entry.localizations[lang]?.stringUnit?.value
                return value?.isEmpty ?? true
            }

            if !missingLanguages.isEmpty {
                gaps[key] = missingLanguages
            }
        }

        XCTAssertTrue(
            gaps.isEmpty,
            "Static keys missing translations: \(gaps.sorted { $0.key < $1.key })"
        )
    }
}
