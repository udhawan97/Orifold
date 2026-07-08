import XCTest

/// Regression guard for the v0.8.4 "raw translation key on screen" bug class.
///
/// Because Orifold is built with pure SwiftPM (no Xcode project), `Bundle.main`
/// can never resolve a `LocalizedStringKey` — the string catalog lives in a nested
/// `Orifold_Orifold.bundle`, not `Bundle.main`. So any SwiftUI API that takes a
/// `LocalizedStringKey` and is handed a bare dotted-key *string literal*
/// (e.g. `Text("inspector.title")`, `Link("help.viewDocumentation.button", ...)`,
/// `.confirmationDialog("foo.bar.title", ...)`) renders the RAW KEY on screen in
/// every language. The fix is to resolve through `L10n.string(...)` instead.
///
/// This test scans the UI source and fails if any such literal reappears, so the
/// whole class can't silently regress. It is deliberately source-text based (not a
/// runtime check) because the bug is invisible at runtime unless a human reads the
/// exact panel in question.
final class RawLocalizationKeyLeakTests: XCTestCase {

    /// SwiftUI initializers/modifiers whose relevant parameter is `LocalizedStringKey`
    /// and therefore silently swallow a raw key literal.
    private static let localizedStringKeyAPIs = [
        "Text", "Label", "Button", "Link", "Toggle", "TextField", "SecureField",
        "Picker", "Stepper", "Menu", "Section", "GroupBox", "DisclosureGroup",
        "NavigationLink",
    ]
    private static let localizedStringKeyModifiers = [
        "help", "navigationTitle", "navigationSubtitle", "accessibilityLabel",
        "accessibilityHint", "accessibilityValue", "tabItem", "alert",
        "confirmationDialog", "searchable",
    ]

    /// A dotted key literal: lowerCamel segment(s) joined by dots, e.g.
    /// `"inspector.title"` or `"emptyState.option.assemble.title"`. Excludes
    /// file-extension-looking literals (handled by the caller's context checks).
    private static let dottedKeyLiteral = #""[a-z][a-zA-Z0-9]*(\.[a-zA-Z0-9]+)+""#

    private func uiSourceFiles() throws -> [URL] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Tests/OrifoldTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // repo root
            .appendingPathComponent("Orifold")

        let fm = FileManager.default
        var results: [URL] = []
        let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: nil)
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            // Only UI-layer sources present LocalizedStringKey text to users.
            let path = url.path
            if path.contains("/Views/") || path.contains("/Pet/") || path.contains("/App/") {
                results.append(url)
            }
        }
        return results
    }

    func testNoRawDottedKeyLiteralReachesALocalizedStringKeyAPI() throws {
        let apiAlternation = Self.localizedStringKeyAPIs.joined(separator: "|")
        let modAlternation = Self.localizedStringKeyModifiers.joined(separator: "|")

        // Matches e.g.  Text("inspector.title"   or   .confirmationDialog("foo.bar",
        // but NOT   Text(L10n.string("inspector.title"))  because the "(" must be
        // immediately followed (modulo whitespace) by the quote.
        let initPattern = try NSRegularExpression(
            pattern: "\\b(\(apiAlternation))\\(\\s*\(Self.dottedKeyLiteral)"
        )
        let modPattern = try NSRegularExpression(
            pattern: "\\.(\(modAlternation))\\(\\s*\(Self.dottedKeyLiteral)"
        )

        var offenders: [String] = []

        for file in try uiSourceFiles() {
            let text = try String(contentsOf: file, encoding: .utf8)
            let lines = text.components(separatedBy: "\n")
            for (index, line) in lines.enumerated() {
                // Skip anything already routed through L10n — that's the correct path.
                if line.contains("L10n.string") || line.contains("L10n.format") { continue }
                let range = NSRange(line.startIndex..<line.endIndex, in: line)
                if initPattern.firstMatch(in: line, range: range) != nil
                    || modPattern.firstMatch(in: line, range: range) != nil {
                    offenders.append("\(file.lastPathComponent):\(index + 1): \(line.trimmingCharacters(in: .whitespaces))")
                }
            }
        }

        XCTAssertTrue(
            offenders.isEmpty,
            """
            Found raw translation-key literal(s) passed to a LocalizedStringKey API. \
            These render the raw key on screen (SwiftPM build can't resolve \
            LocalizedStringKey via Bundle.main). Wrap the key in L10n.string(...):
            \(offenders.joined(separator: "\n"))
            """
        )
    }
}
