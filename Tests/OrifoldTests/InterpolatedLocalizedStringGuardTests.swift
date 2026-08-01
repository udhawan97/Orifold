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
/// This is a RATCHET, not a clean bill of health. The sites in `knownOffenders` predate the
/// guard; most are error messages interpolating `error.localizedDescription`, which needs a
/// real decision about how much of a system error to show rather than a mechanical rewrite.
/// The guard's job is to stop the list growing. Fixing one is expected to fail this test until
/// its entry is deleted too — that is the point, the allowlist can only shrink.
///
/// Scans product code only: a `String(localized:)` in a test is not shipped to anyone.
final class InterpolatedLocalizedStringGuardTests: XCTestCase {

    /// `String(localized: "…\(` — a literal opening quote followed by an interpolation
    /// before it closes. Passing a *variable* key (`String(localized: key, bundle:…)`, as
    /// `L10n` itself does) is the sanctioned path and does not match.
    private static let interpolationPattern = #"String\(localized:\s*"[^"]*\\\("#

    // Entries are verbatim copies of the offending source lines — shortening one stops it
    // matching, so line length is not negotiable here.
    // swiftlint:disable line_length
    /// Sites that predate this guard. Keyed by file name and the trimmed source line rather
    /// than by line number, so unrelated edits above them do not churn this list.
    private static let knownOffenders: Set<String> = [
        #"InspectorView.swift: return String(localized: "\(days)d ago", locale: locale)"#,
        #"InspectorView.swift: return String(localized: "\(hours)h ago", locale: locale)"#,
        #"InspectorView.swift: return String(localized: "\(minutes)m ago", locale: locale)"#,
        #"PDFKitEngine.swift: return String(localized: "The file could not be opened: \(error.localizedDescription)", locale: L10n.currentLocale)"#,
        #"PDFKitEngine.swift: return String(localized: "The file is \(actual), which is larger than the \(limit) import safety limit.", locale: L10n.currentLocale)"#,
        #"PDFKitEngine.swift: return String(localized: "This HTML file would render to about \(pageEstimate) pages, which is over Orifold's \(maxPages)-page HTML conversion limit. Try printing or exporting it to PDF from a browser, then import the PDF.", locale: L10n.currentLocale)"#,
        #"PDFKitEngine.swift: return String(localized: "This \(typeDescription) file is \(actual), which is larger than Orifold can safely convert directly (\(limit)). Try exporting it to PDF first, then import the PDF.", locale: L10n.currentLocale)"#,
        #"PDFKitEngine.swift: return String(localized: "This file would render to more than \(maxPages) pages, so Orifold stopped the import before creating a partial PDF. Try exporting it to PDF first, then import the PDF.", locale: L10n.currentLocale)"#,
        #"PDFOCRService.swift: return String(localized: "Orifold could not make page \(pageNumber) searchable. Try a clearer scan or skip this page.", locale: L10n.currentLocale)"#,
        #"PDFOCRService.swift: return String(localized: "Orifold could not read page \(pageNumber) to make it searchable. Try exporting that page to PDF, then import it again.", locale: L10n.currentLocale)"#,
        #"SigningIdentity.swift: return String(localized: "Orifold couldn't generate the secure random data signing requires (code \(status)). Try again.", locale: L10n.currentLocale)"#,
        #"SigningIdentity.swift: return String(localized: "Orifold doesn't support this certificate's private key algorithm (\(details)). Try a different certificate.", locale: L10n.currentLocale)"#,
        #"SigningIdentity.swift: return String(localized: "This certificate's private key can't create \(algorithm.rawValue) signatures. Try a different certificate.", locale: L10n.currentLocale)"#,
        #"SigningIdentity.swift: return String(localized: "\(operation) failed (code \(status)). Try again, and if it keeps happening, check the certificate in Keychain Access.", locale: L10n.currentLocale)"#,
        #"SigningIdentity.swift: return String(localized: "\(operation) failed: \(message)", locale: L10n.currentLocale)"#,
        #"WorkspaceViewModel.swift: exportError = ExportError(message: String(localized: "Orifold couldn’t export page images. \(error.localizedDescription) Check that the destination folder exists and has free space, then try again.", locale: L10n.currentLocale))"#,
        #"WorkspaceViewModel.swift: exportError = ExportError(message: String(localized: "Orifold couldn’t export the selected pages. \(error.localizedDescription)", locale: L10n.currentLocale))"#,
        #"WorkspaceViewModel.swift: exportError = ExportError(message: String(localized: "Orifold couldn’t prepare the signing identity. \(error.localizedDescription)", locale: L10n.currentLocale))"#,
        #"WorkspaceViewModel.swift: exportError = ExportError(message: String(localized: "Orifold couldn’t prepare the visible signature. \(error.localizedDescription)", locale: L10n.currentLocale))"#,
        #"WorkspaceViewModel.swift: exportError = ExportError(message: String(localized: "Orifold couldn’t save the PDF. \(error.localizedDescription) Check that the destination still exists and that you have permission to write there, then try again.", locale: L10n.currentLocale))"#,
        #"WorkspaceViewModel.swift: exportError = ExportError(message: String(localized: "Orifold couldn’t write the \(format.menuTitle) export. \(error.localizedDescription) Check that the destination folder exists and has free space, then try again.", locale: L10n.currentLocale))"#,
        #"WorkspaceViewModel.swift: message: String(localized: "Could not open \(failures.count) files: \(names)\(suffix).\(importedText)", locale: L10n.currentLocale)"#,
        #"WorkspaceViewModel.swift: panel.title = String(localized: "Export \(format.menuTitle)", locale: L10n.currentLocale)"#,
        #"WorkspaceViewModel.swift: return String(localized: "Orifold can preserve the original \(formatName) bytes when unchanged, but edited package exports are not faithful enough yet. Export as PDF to preserve the edit.", locale: L10n.currentLocale)"#,
        #"WorkspaceViewModel.swift: return String(localized: "Orifold could not encode the \(formatName) export.", locale: L10n.currentLocale)"#,
        #"WorkspaceViewModel.swift: return String(localized: "Orifold couldn’t create the \(format.menuTitle) export. \(error.localizedDescription)", locale: L10n.currentLocale)"#,
        #"WorkspaceViewModel.swift: return String(localized: "Orifold does not have a rich-text writer for \(format.menuTitle).", locale: L10n.currentLocale)"#,
        #"WorkspaceViewModel.swift: return String(localized: "\(original) → \(compressed), \(percent)% smaller", locale: L10n.currentLocale)"#,
        #"WorkspaceViewModel.swift: self.exportError = ExportError(message: String(localized: "Orifold couldn’t sign the PDF. \(error.localizedDescription)", locale: L10n.currentLocale))"#
    ]
    // swiftlint:enable line_length

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
