import XCTest

/// Enforces CLAUDE.md's "use `L10n.format(key, args…)`, not `Text("key \(arg)")`" rule for
/// the `String(localized:)` spelling of the same mistake.
///
/// An interpolated `String(localized:)` does not look up the text you wrote. The compiler
/// derives a format-string key from the interpolation — `"Page %lld of %lld"` — and that key
/// is in no catalog, so the call silently returns its English argument in all six languages.
/// It is invisible to every other gate: `LocalizationCoverageTests` only checks keys that
/// exist, and `RawLocalizationKeyLeakTests` scans `/Views/`, `/Pet/` and `/App/` for bare
/// dotted keys, which this is not.
///
/// Two shipped instances of this were fixed on 2026-07-31 — the baked "Page N of M" stamp
/// (the only page number that reaches exported bytes) and the comment-anchor labels. Both had
/// survived because nothing stopped a new call site appearing.
///
/// The allowlist this guard shipped with has been worked down to zero, so product code is
/// now clean and this is a plain guard rather than a ratchet. The mechanism is kept because
/// the failure is silent — a new interpolated call compiles, runs, and quietly ships English
/// — so "nobody will do that again" is not a control. If a site ever genuinely has to be
/// exempted, add it to `knownOffenders` with a comment saying why; the second assertion still
/// forces the entry out again once it is fixed.
///
/// Scans product code only: a `String(localized:)` in a test is not shipped to anyone.
final class InterpolatedLocalizedStringGuardTests: XCTestCase {

    /// `String(localized: "…\(` — a literal opening quote followed by an interpolation
    /// before it closes. Passing a *variable* key (`String(localized: key, bundle:…)`, as
    /// `L10n` itself does) is the sanctioned path and does not match.
    private static let interpolationPattern = #"String\(localized:\s*"[^"]*\\\("#

    /// Empty, and meant to stay that way. The 29 sites this guard was born with were
    /// migrated to `L10n.format` on 2026-08-01; anything appearing here again is a
    /// regression, not debt.
    private static let knownOffenders: Set<String> = []

    private func productSourceFiles() throws -> [URL] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // OrifoldTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("Orifold")
        var results: [URL] = []
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            results.append(url)
        }
        return results
    }

    private func currentOffenders() throws -> Set<String> {
        let pattern = try NSRegularExpression(pattern: Self.interpolationPattern)
        var found: Set<String> = []

        for file in try productSourceFiles() {
            let text = try String(contentsOf: file, encoding: .utf8)
            for line in text.components(separatedBy: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.hasPrefix("//") else { continue }
                let range = NSRange(line.startIndex..<line.endIndex, in: line)
                guard pattern.firstMatch(in: line, range: range) != nil else { continue }
                found.insert("\(file.lastPathComponent): \(trimmed)")
            }
        }
        return found
    }

    func testNoNewInterpolatedLocalizedStringsInProductCode() throws {
        let current = try currentOffenders()

        let added = current.subtracting(Self.knownOffenders).sorted()
        XCTAssertTrue(
            added.isEmpty,
            """
            New interpolated String(localized:) in product code. The compiler derives the \
            lookup key from the interpolation, so this never matches a catalog entry and \
            ships English to all six languages. Add a key to Localizable.xcstrings (all six \
            translations) and call L10n.format(_:_:) instead — see \
            PDFDecorationExportBaker.text(for:pageIndex:pageCount:) for the shape.
            \(added.joined(separator: "\n"))
            """
        )

        let removed = Self.knownOffenders.subtracting(current).sorted()
        XCTAssertTrue(
            removed.isEmpty,
            """
            These allowlist entries no longer match any source line. If you migrated them to \
            L10n.format, delete them from `knownOffenders` so the ratchet tightens. If you \
            only reworded the line, update the entry.
            \(removed.joined(separator: "\n"))
            """
        )
    }
}
