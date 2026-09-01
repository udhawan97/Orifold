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
/// The original pattern's quote matcher missed escaped-quote call sites. Strengthening it exposed
/// five pre-existing sites outside this operational-progress/recovery repair. They remain an exact
/// inventory below rather than widening this finding into unrelated export copy or a security
/// specialist's file. Any new interpolated call still fails, and the second assertion removes each
/// inventory entry as soon as its producer is migrated.
///
/// Scans product code only: a `String(localized:)` in a test is not shipped to anyone.
final class InterpolatedLocalizedStringGuardTests: XCTestCase {

    /// `String(localized: "…\(` — a literal opening quote followed by an interpolation
    /// before it closes. Passing a *variable* key (`String(localized: key, bundle:…)`, as
    /// `L10n` itself does) is the sanctioned path and does not match.
    private static let interpolationPattern = #"String\(localized:\s*"(?:\\.|[^"\\])*\\\("#

    /// Exact residual inventory discovered when escaped quotes became visible to the matcher.
    /// These are unrelated source-export messages plus PDFKitEngine's export-preparation copy;
    /// DR-29b3f928-009 authorizes only WorkspaceViewModel operational progress/recovery producers.
    private static let knownOffenders: Set<String> = [
        #"PDFKitEngine.swift: return String(localized: "Orifold could not prepare \"\(name)\" for export. Reopen the document and try exporting again.", locale: L10n.currentLocale)"#,
        #"WorkspaceViewModel.swift: return String(localized: "Orifold could not map an edit in \"\(memberName)\" back to the original \(format.menuTitle) source\(detail) Export as PDF to preserve the visual edit, or edit text that exists in the original document.", locale: L10n.currentLocale)"#,
        #"WorkspaceViewModel.swift: return String(localized: "Orifold found more than one matching source text in \"\(memberName)\"\(detail) Export as PDF to preserve the visual edit.", locale: L10n.currentLocale)"#,
        #"WorkspaceViewModel.swift: return String(localized: "Orifold found PDF-only annotations, signatures, or page changes in \"\(memberName)\". Export as PDF to preserve those visual edits.", locale: L10n.currentLocale)"#,
        #"WorkspaceViewModel.swift: return String(localized: "\"\(memberName)\" was imported from a \(originFormatDescription) file, which Orifold flattens to plain text and cannot reconstruct into \(format.menuTitle). Export as PDF to keep the current content, or re-export from the original \(originFormatDescription) file if you need it in another format.", locale: L10n.currentLocale)"#,
    ]

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

    private func matchesInterpolatedLocalizedString(_ source: String) throws -> Bool {
        let pattern = try NSRegularExpression(pattern: Self.interpolationPattern)
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        return pattern.firstMatch(in: source, range: range) != nil
    }

    func testPatternDetectsInterpolationAfterEscapedQuote() throws {
        let specimen = #"message: String(localized: "Could not open \"\(fileName)\". Try again.")"#
        XCTAssertTrue(try matchesInterpolatedLocalizedString(specimen))
    }

    func testPatternDoesNotRejectDynamicCatalogKey() throws {
        let specimen = #"String(localized: key, bundle: bundle, locale: locale)"#
        XCTAssertFalse(try matchesInterpolatedLocalizedString(specimen))
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
