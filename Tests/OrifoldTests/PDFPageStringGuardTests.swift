import XCTest

/// Enforces CLAUDE.md's "never assert on `PDFPage.string`" rule, which until now was
/// documented but unchecked.
///
/// PDFKit reconstructs page text from CoreText glyph positions. Where an edit leaves a
/// replacement run overlapping the original, the interleaving is not stable across runs,
/// so `.contains(...)` can intermittently return false on bytes that are perfectly
/// correct. Two commits have already fixed this exact flake class — `ad3d9b3` and
/// `0e63e65` ("Fix last CI-only Xcode 16.4 test flake") — and it came back both times,
/// because nothing stopped a new call site appearing. Hence a scanner rather than a third
/// round of fixes.
///
/// Modelled on `RawLocalizationKeyLeakTests`: source-text based, because the bug is
/// invisible at runtime except as a rare failure on a machine under load.
///
/// This is a RATCHET, not a clean bill of health. The sites in `knownOffenders` predate
/// the guard and are tracked in issue #17; the guard's job is to stop the list growing.
/// Removing one is expected to make this test fail until its entry is deleted too, which
/// is the point — the allowlist can only shrink.
///
/// Scans tests only. The rule is about assertions: product code reads text through
/// `PDFTextAnalysisEngine`/`FPDFText`, and a test that asserts on PDFKit's rendition is
/// asserting on something the app does not rely on.
final class PDFPageStringGuardTests: XCTestCase {

    /// A `PDFPage`-shaped receiver followed by PDFKit's text accessors. Two forms:
    /// an identifier containing "page" (`editedPage.string`, `page2.attributedString`),
    /// and a `page(at:)` subscript call (`doc.page(at: 0)?.string`).
    private static let extractionPattern =
        #"(\b\w*[Pp]age\w*\s*[!?]?\s*\.\s*(string|attributedString)\b)"# +
        #"|(\.page\s*\([^)]*\)\s*[!?]?\s*\.\s*(string|attributedString)\b)"#

    // Entries below are verbatim copies of the offending source lines — shortening one
    // stops it matching, so line length is not negotiable here.
    // swiftlint:disable line_length
    /// Sites that predate this guard. Keyed by file name and the trimmed source line
    /// rather than by line number, so unrelated edits above them do not churn this list.
    /// Tracked in issue #17 — migrate to the PDFium-backed helper and delete the entry.
    private static let knownOffenders: Set<String> = [
        #"DocumentTypeEditHardeningTests.swift: .compactMap { reopened.page(at: $0)?.attributedString?.string }.joined()"#,
        #"DocumentTypeEditHardeningTests.swift: .compactMap { reopenedPDF.page(at: $0)?.attributedString?.string ?? reopenedPDF.page(at: $0)?.string }"#,
        #"ObjectEditWorkspaceTests.swift: XCTAssertTrue(PDFDocument(data: healedData)?.page(at: 0)?.string?.contains("Replayed mixed editing text") == true,"#,
        #"ObjectEditWorkspaceTests.swift: XCTAssertTrue(PDFDocument(data: replayedData)?.page(at: 0)?.string?.contains("Replayed mixed editing text") == true,"#,
        #"ObjectEditWorkspaceTests.swift: XCTAssertTrue(PDFDocument(data: replayedData)?.page(at: 0)?.string?.contains("hello") == true,"#,
        #"OrifoldTests.swift: XCTAssertEqual(viewModel.loadedPDFs[0].1.page(at: 2)?.string?.trimmed, "one")"#,
        #"OrifoldTests.swift: XCTAssertFalse(viewModel.loadedPDFs.first?.1.page(at: 0)?.string?.contains("edited") ?? true)"#,
        #"OrifoldTests.swift: XCTAssertTrue(editedPage.string?.contains("Edited searchable text") ?? false)"#,
        #"OrifoldTests.swift: XCTAssertTrue(exportedPage.string?.contains("Edited searchable text") ?? false)"#,
        #"OrifoldTests.swift: XCTAssertTrue(exportedPage1.string?.contains("Page one content") ?? false)"#,
        #"OrifoldTests.swift: XCTAssertTrue(exportedPage2.string?.contains("Page two edited") ?? false)"#,
        #"OrifoldTests.swift: XCTAssertTrue(page.string?.contains("Stale lower line") ?? false, "sanity check: fixture must contain this text before editing")"#,
        #"OrifoldTests.swift: XCTAssertTrue(page.string?.contains("Untouched transparent text") ?? false, "sanity check: fixture must contain this text before editing")"#,
        #"OrifoldTests.swift: XCTAssertTrue(page1.string?.contains("Page one content") ?? false, "editing an unrelated page must not disturb this page's content")"#,
        #"OrifoldTests.swift: XCTAssertTrue(page2.string?.contains("Page two edited") ?? false)"#,
        #"OrifoldTests.swift: XCTAssertTrue(pdf.page(at: 0)?.string?.contains("Page 1 of 3") ?? false)"#,
        #"OrifoldTests.swift: XCTAssertTrue(pdf.page(at: 0)?.string?.contains("third original") ?? false)"#,
        #"OrifoldTests.swift: XCTAssertTrue(pdf.page(at: 1)?.string?.contains("Anchor target") == true)"#,
        #"OrifoldTests.swift: XCTAssertTrue(pdf.page(at: 1)?.string?.contains("Check this claim.") == true)"#,
        #"OrifoldTests.swift: XCTAssertTrue(pdf.page(at: 2)?.string?.contains("Page 3 of 5") ?? false)"#,
        #"OrifoldTests.swift: XCTAssertTrue(viewModel.loadedPDFs.first?.1.page(at: 0)?.string?.contains("edited") ?? false)"#,
        #"OrifoldTests.swift: XCTAssertTrue(viewModel.loadedPDFs[1].1.page(at: 1)?.string?.contains("one") ?? false)"#,
        #"OrifoldTests.swift: let afterAttemptedStaleRedo = viewModel.loadedPDFs.first?.1.page(at: 0)?.string ?? """#,
        #"OrifoldTests.swift: let afterNewEdit = viewModel.loadedPDFs.first?.1.page(at: 0)?.string ?? """#,
        #"OrifoldTests.swift: let afterRedo = viewModel.loadedPDFs.first?.1.page(at: 0)?.string ?? """#,
        #"OrifoldTests.swift: let afterTwoUndos = viewModel.loadedPDFs.first?.1.page(at: 0)?.string ?? """#,
        #"OrifoldTests.swift: let afterUndoingEditFour = viewModel.loadedPDFs.first?.1.page(at: 0)?.string ?? """#,
        #"OrifoldTests.swift: let editedText = editedPage.string ?? """#,
        #"OrifoldTests.swift: let exportedString = try XCTUnwrap(exportedPage.string)"#,
        #"OrifoldTests.swift: let movedPageText = viewModel.loadedPDFs.first?.1.page(at: 0)?.string ?? """#,
        #"OrifoldTests.swift: let pageText = viewModel.loadedPDFs.first?.1.page(at: 0)?.string ?? """#,
        #"OrifoldTests.swift: let pageTextAfterRedo = viewModel.loadedPDFs.first?.1.page(at: 0)?.string ?? """#,
        #"OrifoldTests.swift: let pageTextAfterSecondUndo = viewModel.loadedPDFs.first?.1.page(at: 0)?.string ?? """#,
        #"OrifoldTests.swift: let textSelection = try XCTUnwrap(hostedPage.selection(for: (hostedPage.string! as NSString).range(of: "Untouched transparent text")))"#,
        #"PDFOCRTests.swift: XCTAssertTrue(outputPDF.page(at: 0)?.string?.contains("New scan text") == true)"#,
        #"PDFOCRTests.swift: XCTAssertTrue(outputPDF.page(at: 1)?.string?.contains("Existing searchable text") == true)"#,
        #"PDFOCRTests.swift: XCTAssertTrue(outputPage.string?.contains("Searchable invoice phrase") == true)"#,
        #"PDFOCRTests.swift: let outputString = try XCTUnwrap(outputPDF.page(at: 0)?.string)"#,
        #"SourceDocumentRoundTripTests.swift: let exportedString = try XCTUnwrap(exportedPage.string, sample.format.rawValue)"#,
        #"StressFixtureLifecycleTests.swift: let pdfkit = strip(page.attributedString?.string ?? page.string ?? "")"#,
        #"UserFlowRegressionRound2Tests.swift: XCTAssertFalse(exportedPDF.page(at: 0)?.string?.contains("First doc") ?? false, "the removed document's content must not appear in the export")"#
    ]
    // swiftlint:enable line_length

    private func testSourceFiles() throws -> [URL] {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let fileManager = FileManager.default
        var results: [URL] = []
        let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: nil)
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            // The guard quotes the very pattern it bans, so it would flag itself.
            guard url.lastPathComponent != URL(fileURLWithPath: #filePath).lastPathComponent
            else { continue }
            results.append(url)
        }
        return results
    }

    private func currentOffenders() throws -> Set<String> {
        let pattern = try NSRegularExpression(pattern: Self.extractionPattern)
        var found: Set<String> = []

        for file in try testSourceFiles() {
            let text = try String(contentsOf: file, encoding: .utf8)
            for line in text.components(separatedBy: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.hasPrefix("//"), !trimmed.hasPrefix("///") else { continue }
                // `uuidString` is not text extraction; `NSAttributedString.string` on an
                // in-memory string is safe and common in typesetting tests.
                guard !trimmed.contains("uuidString") else { continue }
                let range = NSRange(line.startIndex..<line.endIndex, in: line)
                guard pattern.firstMatch(in: line, range: range) != nil else { continue }
                found.insert("\(file.lastPathComponent): \(trimmed)")
            }
        }
        return found
    }

    func testNoNewPDFPageTextExtractionInTests() throws {
        let current = try currentOffenders()

        let added = current.subtracting(Self.knownOffenders).sorted()
        XCTAssertTrue(
            added.isEmpty,
            """
            New PDFPage text extraction in a test. PDFKit rebuilds page text from glyph \
            positions, so overlapping runs interleave unstably and this flakes under load \
            (see CLAUDE.md, and commits ad3d9b3 / 0e63e65). Extract with PDFium instead — \
            `PDFTextAnalysisEngine`, as in FindReplaceBodyTextTests.pageText(fromData:) — \
            or assert on thumbnail brightness.
            \(added.joined(separator: "\n"))
            """
        )

        let removed = Self.knownOffenders.subtracting(current).sorted()
        XCTAssertTrue(
            removed.isEmpty,
            """
            These allowlist entries no longer match any source line. If you migrated them \
            off PDFPage.string, delete them from `knownOffenders` so the ratchet tightens \
            (issue #17). If you only reworded the line, update the entry.
            \(removed.joined(separator: "\n"))
            """
        )
    }
}
