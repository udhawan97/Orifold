# Source Page Labels Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show a PDF's own page labels (`i`, `A-7`, `247`) beside the workspace position in the page bar and search results, but only when the source document genuinely carries a `/PageLabels` number tree.

**Architecture:** A six-line qpdf catalog probe answers "does this member have real labels?"; a single `WorkspaceViewModel.pageReference(for:in:)` helper combines that gate with PDFKit's `PDFPage.label` and the existing workspace ordinal; two views consume the helper instead of deriving their own answers.

**Tech Stack:** Swift 5.9 / SwiftUI (macOS 14 target), PDFKit, qpdf 12.3 via the `CQPDF` module, XCTest.

Spec: `docs/superpowers/specs/2026-07-31-page-labels-design.md`

## Global Constraints

- Deployment target stays **macOS 14.0**. This change needs no `#available` gate.
- **Every user-facing string** goes through `L10n` and gets all **six** languages — `en, es, fr, hi, ja, zh-Hans`. `LocalizationCoverageTests` fails on any gap.
- **Never pass a bare dotted key** to `Text`/`Button`/`navigationTitle`. `RawLocalizationKeyLeakTests` regex-scans `/Views/`, `/Pet/`, `/App/` and fails.
- Use `L10n.format(key, args…)`, never `Text("key \(arg)")`.
- **Never assert on `PDFPage.string`** — `PDFPageStringGuardTests` matches on *identifier name*, so no test symbol may produce the source text `pageLabel.string` or `pageLabels.first.string` either.
- **No new SPM dependency, no new resource, no `project.yml` change** — so **no `xcodegen generate` is needed** in this plan.
- Test target has **no `resources:` block** (`Package.swift:46-50`); fixtures load `#filePath`-relative.
- `swift build -c release` is mandatory before merge, per CLAUDE.md, even though this adds no `@_silgen_name` binding.
- XCTest only. `final class <Subject>Tests: XCTestCase`, long behavior-describing method names.

---

### Task 1: The qpdf presence gate + fixtures

**Files:**
- Modify: `Tests/OrifoldTests/Fixtures/make-tagged-fixtures.py` (add generator + 2 entries in `__main__`)
- Create: `Tests/OrifoldTests/Fixtures/page-labels.pdf` (generated)
- Create: `Tests/OrifoldTests/Fixtures/no-page-labels.pdf` (generated)
- Modify: `Orifold/Engine/QPDFService.swift` (add `hasPageLabels` after `hasXMPMetadata`, which ends at `:126`)
- Test: `Tests/OrifoldTests/QPDFServicePageLabelTests.swift`

**Interfaces:**
- Consumes: `QPDFService.withQPDF(_:description:password:_:)` — `static func withQPDF<T>(_ data: Data, description: String, password: String? = nil, _ body: (qpdf_data) -> T?) -> T?`
- Produces: `QPDFService.hasPageLabels(_ data: Data) -> Bool`, and the two fixture files consumed by Task 2.

- [ ] **Step 1: Add the fixture generator**

Add this function to `Tests/OrifoldTests/Fixtures/make-tagged-fixtures.py`, after `xmp_metadata()`:

```python
def page_labels(nums: str | None) -> bytes:
    """Four pages, optionally carrying a /PageLabels number tree.

    With `nums`, PDFKit reports ["i", "ii", "1", "A-7"]. WITHOUT it PDFKit
    SYNTHESIZES ["1", "2", "3", "4"] rather than returning nil -- which is
    precisely why QPDFService.hasPageLabels gates on the catalog key instead
    of trusting PDFPage.label to admit the absence.
    """
    ops = "BT /F1 24 Tf 72 700 Td (Page) Tj ET\n"
    labels = f" /PageLabels << /Nums [{nums}] >>" if nums else ""
    page = (
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 3 0 R "
        "/Resources << /Font << /F1 4 0 R >> >> >>"
    )
    return build_pdf([
        f"<< /Type /Catalog /Pages 2 0 R{labels} >>",
        "<< /Type /Pages /Kids [5 0 R 6 0 R 7 0 R 8 0 R] /Count 4 >>",
        f"<< /Length {len(ops)} >>\nstream\n{ops}endstream",
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
        page,
        page,
        page,
        page,
    ])
```

And add these two entries to the `written` dict in `__main__`:

```python
        "page-labels.pdf": page_labels(
            "0 << /S /r >> 2 << /S /D /St 1 >> 3 << /S /D /P (A-) /St 7 >>"
        ),
        "page-labels-decimal.pdf": page_labels("0 << /S /D >>"),
        "no-page-labels.pdf": page_labels(None),
```

`page-labels-decimal.pdf` is the case that separates the two suppression rules: it genuinely
carries `/PageLabels`, so the gate opens, but its labels are `"1","2","3","4"` — identical to
the workspace positions, so the *equality* rule must close it. Plenty of real PDFs are like
this, and without it nothing exercises that branch.

- [ ] **Step 2: Generate the fixtures and verify what PDFKit reports**

Run:

```bash
python3 Tests/OrifoldTests/Fixtures/make-tagged-fixtures.py
```

Expected: prints `wrote page-labels.pdf (...)` and `wrote no-page-labels.pdf (...)` among the others.

Then confirm the labels and the synthesis behaviour that justifies the gate:

```bash
python3 - <<'PY'
import subprocess, textwrap
swift = textwrap.dedent('''
import PDFKit
for name in ["page-labels", "no-page-labels"] {
    let url = URL(fileURLWithPath: "Tests/OrifoldTests/Fixtures/\\(name).pdf")
    let doc = PDFDocument(url: url)!
    let labels = (0..<doc.pageCount).map { doc.page(at: $0)?.label ?? "nil" }
    print(name, labels)
}
''')
open("/tmp/probe.swift","w").write(swift)
subprocess.run(["swift","/tmp/probe.swift"])
PY
```

(Add `"page-labels-decimal"` to the `for name in [...]` list in that probe.)

Expected output:

```
page-labels ["i", "ii", "1", "A-7"]
page-labels-decimal ["1", "2", "3", "4"]
no-page-labels ["1", "2", "3", "4"]
```

The last two lines are identical, and that is the whole reason the gate exists: PDFKit invents
labels rather than returning nil, so the rendered label alone cannot tell those two documents
apart. Only the catalog can.

- [ ] **Step 3: Write the failing test**

Create `Tests/OrifoldTests/QPDFServicePageLabelTests.swift`:

```swift
import XCTest
@testable import Orifold

/// `/PageLabels` presence detection. PDFKit cannot answer this question -- it
/// synthesizes "1", "2", "3" for documents that carry no number tree -- so the
/// catalog probe is what separates a real label from an invented one.
final class QPDFServicePageLabelTests: XCTestCase {

    func testReportsPageLabelsPresentWhenCatalogCarriesNumberTree() {
        XCTAssertTrue(QPDFService.hasPageLabels(fixture("page-labels.pdf")))
    }

    func testReportsPageLabelsAbsentWhenCatalogHasNoNumberTree() {
        XCTAssertFalse(QPDFService.hasPageLabels(fixture("no-page-labels.pdf")))
    }

    /// The two documents below render byte-identical labels through PDFKit
    /// (["1","2","3","4"]); only the catalog distinguishes them. This is the
    /// test that would fail if anyone ever "simplified" the gate to compare
    /// PDFPage.label against the ordinal.
    func testDistinguishesTrivialDecimalLabelsFromNoLabelsAtAll() {
        XCTAssertTrue(QPDFService.hasPageLabels(fixture("page-labels-decimal.pdf")))
        XCTAssertFalse(QPDFService.hasPageLabels(fixture("no-page-labels.pdf")))
    }

    func testReportsPageLabelsAbsentForUnreadableBytes() {
        XCTAssertFalse(QPDFService.hasPageLabels(Data("not a pdf".utf8)))
        XCTAssertFalse(QPDFService.hasPageLabels(Data()))
    }

    // MARK: - Fixtures

    private func fixture(_ name: String) -> Data {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(name)")
        // swiftlint:disable:next force_try
        return try! Data(contentsOf: url)
    }
}
```

- [ ] **Step 4: Run the test to verify it fails**

Run:

```bash
swift test --filter QPDFServicePageLabelTests 2>&1 | tail -20
```

Expected: compile error — `type 'QPDFService' has no member 'hasPageLabels'`.

- [ ] **Step 5: Implement the probe**

In `Orifold/Engine/QPDFService.swift`, immediately after the closing brace of `hasXMPMetadata` (line 126), add:

```swift
    /// True when the document catalog carries a `/PageLabels` number tree.
    ///
    /// This exists because `PDFPage.label` cannot be asked the question:
    /// for a document with no `/PageLabels` it *synthesizes* "1", "2", "3"
    /// rather than returning nil, so a UI that shows "the label when it
    /// differs from the position" would invent labels for every unlabeled
    /// member of a merged workspace. The catalog key is the only honest signal.
    static func hasPageLabels(_ data: Data) -> Bool {
        withQPDF(data, description: "page-labels-probe") { qpdf in
            qpdf_oh_has_key(qpdf, qpdf_get_root(qpdf), "/PageLabels") == QPDF_TRUE
        } ?? false
    }
```

- [ ] **Step 6: Run the test to verify it passes**

Run:

```bash
swift test --filter QPDFServicePageLabelTests 2>&1 | tail -10
```

Expected: `Executed 3 tests, with 0 failures`.

- [ ] **Step 7: Commit**

```bash
git add Tests/OrifoldTests/Fixtures/make-tagged-fixtures.py \
        Tests/OrifoldTests/Fixtures/page-labels.pdf \
        Tests/OrifoldTests/Fixtures/no-page-labels.pdf \
        Orifold/Engine/QPDFService.swift \
        Tests/OrifoldTests/QPDFServicePageLabelTests.swift
git commit -m "feat: detect /PageLabels presence via the catalog

PDFPage.label synthesizes ordinals for documents that carry no number
tree, so it can never report absence. Probe the catalog key instead."
```

---

### Task 2: The shared `pageReference` helper

**Files:**
- Modify: `Orifold/ViewModels/WorkspaceViewModel.swift` (new `// MARK: - Page reference` section, placed immediately before the existing `// MARK: - Print` section; plus one line inside `mutateMemberBytes`, which starts at `:2804`)
- Test: `Tests/OrifoldTests/PageReferenceTests.swift`

**Interfaces:**
- Consumes: `QPDFService.hasPageLabels(_:) -> Bool` (Task 1); existing `workspacePageNumber(for:in:) -> Int` (`:1419`); existing `pageRef(for:in:) -> PageRef?` (`:8980`); `combinedPDF: PDFDocument` (`:268`); `document.memberPDFData: [UUID: Data]`.
- Produces:
  - `WorkspaceViewModel.PageReference` — `struct PageReference: Equatable { let position: Int; let label: String? }`
  - `func pageReference(for page: PDFPage, in pdfDocument: PDFDocument) -> PageReference?`
  - `func pageReference(for selection: PDFSelection) -> PageReference?`
  - `var currentPageSourceLabel: String?`

- [ ] **Step 1: Write the failing test**

Create `Tests/OrifoldTests/PageReferenceTests.swift`:

```swift
import PDFKit
import XCTest
@testable import Orifold

/// The single source of truth for "what number does this page carry?".
/// Position is always the workspace ordinal; the source label rides along only
/// when the owning member genuinely has a /PageLabels tree AND the label says
/// something the position does not already say.
@MainActor
final class PageReferenceTests: XCTestCase {

    func testSurfacesSourceLabelWhenMemberCarriesPageLabels() throws {
        let viewModel = makeViewModel(members: [labeledFixture()])
        let page = try XCTUnwrap(viewModel.combinedPDF.page(at: 1))

        let reference = try XCTUnwrap(viewModel.pageReference(for: page, in: viewModel.combinedPDF))

        XCTAssertEqual(reference.position, 1)
        XCTAssertEqual(reference.label, "i")
    }

    func testSuppressesLabelWhenMemberHasNoPageLabels() throws {
        let viewModel = makeViewModel(members: [unlabeledFixture()])
        let page = try XCTUnwrap(viewModel.combinedPDF.page(at: 1))

        let reference = try XCTUnwrap(viewModel.pageReference(for: page, in: viewModel.combinedPDF))

        XCTAssertEqual(reference.position, 1)
        XCTAssertNil(reference.label, "PDFKit synthesizes \"1\" here; the gate must reject it")
    }

    /// A document that DOES carry /PageLabels, but whose labels are plain
    /// decimals identical to the position. The gate opens; the equality rule
    /// must then close it, so the page bar does not render "3 · 3".
    func testSuppressesLabelWhenItMatchesTheWorkspacePosition() throws {
        let viewModel = makeViewModel(members: [decimalLabeledFixture()])

        XCTAssertTrue(
            QPDFService.hasPageLabels(decimalLabeledFixture()),
            "precondition: this fixture really does carry a number tree"
        )

        for combinedIndex in 1...4 {
            let page = try XCTUnwrap(viewModel.combinedPDF.page(at: combinedIndex))
            let reference = try XCTUnwrap(viewModel.pageReference(for: page, in: viewModel.combinedPDF))
            XCTAssertEqual(reference.position, combinedIndex)
            XCTAssertNil(
                reference.label,
                "label \"\(combinedIndex)\" says nothing the position does not already say"
            )
        }
    }

    func testResolvesEachPageAgainstItsOwnMemberInAMergedWorkspace() throws {
        let viewModel = makeViewModel(members: [labeledFixture(), unlabeledFixture()])

        // Member A page 1 -> workspace position 1, labelled "i".
        let first = try XCTUnwrap(viewModel.combinedPDF.page(at: 1))
        let firstReference = try XCTUnwrap(viewModel.pageReference(for: first, in: viewModel.combinedPDF))
        XCTAssertEqual(firstReference.position, 1)
        XCTAssertEqual(firstReference.label, "i")

        // Member B page 1 -> workspace position 5, no labels at all.
        // Combined layout: [banner, A1, A2, A3, A4, banner, B1, ...] -> index 6.
        let second = try XCTUnwrap(viewModel.combinedPDF.page(at: 6))
        let secondReference = try XCTUnwrap(viewModel.pageReference(for: second, in: viewModel.combinedPDF))
        XCTAssertEqual(secondReference.position, 5)
        XCTAssertNil(secondReference.label, "member B has no /PageLabels; its synthesized \"1\" must not leak")
    }

    func testReturnsNilForBoundaryPages() throws {
        let viewModel = makeViewModel(members: [labeledFixture()])
        let banner = try XCTUnwrap(viewModel.combinedPDF.page(at: 0))

        XCTAssertTrue(banner is BoundaryPage, "index 0 is expected to be the member banner")
        XCTAssertNil(viewModel.pageReference(for: banner, in: viewModel.combinedPDF))
    }

    // MARK: - Fixtures

    private func labeledFixture() -> Data { fixture("page-labels.pdf") }
    private func decimalLabeledFixture() -> Data { fixture("page-labels-decimal.pdf") }
    private func unlabeledFixture() -> Data { fixture("no-page-labels.pdf") }

    private func fixture(_ name: String) -> Data {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(name)")
        // swiftlint:disable:next force_try
        return try! Data(contentsOf: url)
    }

    /// Builds a workspace holding every page of every supplied member.
    ///
    /// Do not try to build a partial workspace by handing out fewer `PageRef`s
    /// than the member has pages: `PDFKitEngine.concatenate` walks the loaded
    /// `PDFDocument`, not `pageRefs`, so `combinedPDF` would still contain all
    /// of them while `pageCount` counted fewer — and `WorkspaceViewModel.init`
    /// renormalizes every `sourcePageIndex` to its member-local ordinal anyway.
    private func makeViewModel(members: [Data]) -> WorkspaceViewModel {
        let document = WorkspaceDocument()
        var allRefs: [PageRef] = []
        var memberRecords: [MemberDocument] = []

        for (offset, data) in members.enumerated() {
            var member = MemberDocument(displayName: "Member \(offset)", sourcePDFRef: "member\(offset).pdf")
            let pageCount = PDFDocument(data: data)?.pageCount ?? 0
            let refs = (0..<pageCount).map { PageRef(memberDocId: member.id, sourcePageIndex: $0) }
            member.pageRefs = refs.map(\.id)
            memberRecords.append(member)
            allRefs.append(contentsOf: refs)
            document.memberPDFData[member.id] = data
        }

        document.workspace.documents = memberRecords
        document.workspace.pageOrder = allRefs
        return WorkspaceViewModel(document: document)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
swift test --filter PageReferenceTests 2>&1 | tail -20
```

Expected: compile error — `value of type 'WorkspaceViewModel' has no member 'pageReference'`.

- [ ] **Step 3: Implement the helper**

In `Orifold/ViewModels/WorkspaceViewModel.swift`, add this section immediately **before** the existing `// MARK: - Print` marker:

```swift
    // MARK: - Page reference

    /// Where a page sits in the workspace, plus the label its own source document
    /// gives it. `label` is non-nil only when that member genuinely carries a
    /// `/PageLabels` number tree *and* the label says something the position does
    /// not already say.
    struct PageReference: Equatable {
        let position: Int
        let label: String?
    }

    /// `/PageLabels` presence per member, derived on first use.
    ///
    /// Deliberately not persisted and not a field on `MemberDocument`:
    /// `PageRef.rotation` and `PageRef.cropBox` are the local cautionary
    /// precedent for stored properties that are declared, encoded, and never
    /// written by any mutation. Entries left behind by removed members are inert
    /// because member UUIDs are never reused.
    private var pageLabelPresence: [UUID: Bool] = [:]

    private func memberHasPageLabels(_ memberID: UUID) -> Bool {
        if let known = pageLabelPresence[memberID] { return known }
        guard let data = document.memberPDFData[memberID] else { return false }
        let present = QPDFService.hasPageLabels(data)
        pageLabelPresence[memberID] = present
        return present
    }

    /// The workspace position of `page`, and its source label when it carries one.
    /// Returns nil for `BoundaryPage` -- banners are separators, not pages.
    func pageReference(for page: PDFPage, in pdfDocument: PDFDocument) -> PageReference? {
        guard !(page is BoundaryPage) else { return nil }
        let position = workspacePageNumber(for: page, in: pdfDocument)
        guard position > 0 else { return nil }

        guard let ref = pageRef(for: page, in: pdfDocument),
              memberHasPageLabels(ref.memberDocId),
              let label = page.label,
              label != String(position)
        else {
            return PageReference(position: position, label: nil)
        }
        return PageReference(position: position, label: label)
    }

    /// Convenience for search rows, which hold a selection rather than a page.
    func pageReference(for selection: PDFSelection) -> PageReference? {
        guard let page = selection.pages.first else { return nil }
        return pageReference(for: page, in: combinedPDF)
    }

    /// The source label for the page the reader is currently on, if any.
    var currentPageSourceLabel: String? {
        guard let index = combinedPageIndex(forWorkspacePageNumber: currentPageNumber),
              let page = combinedPDF.page(at: index)
        else { return nil }
        return pageReference(for: page, in: combinedPDF)?.label
    }
```

- [ ] **Step 4: Invalidate the cache when member bytes change**

In `mutateMemberBytes` (starts at `:2804`), immediately after the line `guard let newLive = transform(currentLive) else { return failed() }`, add:

```swift
        // Byte-level rewrites can add or drop /PageLabels; re-probe on next use.
        pageLabelPresence[memberID] = nil
```

- [ ] **Step 5: Run the tests to verify they pass**

Run:

```bash
swift test --filter PageReferenceTests 2>&1 | tail -10
```

Expected: `Executed 5 tests, with 0 failures`.

If `testResolvesEachPageAgainstItsOwnMemberInAMergedWorkspace` fails on the combined index, print the actual layout first rather than guessing:

```bash
swift test --filter testResolvesEachPageAgainstItsOwnMemberInAMergedWorkspace 2>&1 | tail -30
```

The banner is inserted once per member immediately before that member's pages (`PDFKitEngine.swift:51-60`), so a 4+4 workspace is `[banner, A1…A4, banner, B1…B4]` and member B's first page is combined index 6.

- [ ] **Step 6: Commit**

```bash
git add Orifold/ViewModels/WorkspaceViewModel.swift Tests/OrifoldTests/PageReferenceTests.swift
git commit -m "feat: add pageReference, one answer for what number a page carries

Combines the workspace ordinal with the source document's own label,
gated on the member actually having a /PageLabels tree."
```

---

### Task 3: Page bar shows the source label

**Files:**
- Modify: `Orifold/Resources/Localizable.xcstrings` (add `readingCanvas.pageBar.sourceLabel`)
- Modify: `Orifold/Views/ReadingCanvas.swift:468-470`

**Interfaces:**
- Consumes: `WorkspaceViewModel.currentPageSourceLabel: String?` (Task 2)
- Produces: nothing consumed downstream.

- [ ] **Step 1: Add the localization key**

Add this entry to the `strings` object in `Orifold/Resources/Localizable.xcstrings`, in alphabetical position among the other `readingCanvas.pageBar.*` keys:

```json
    "readingCanvas.pageBar.sourceLabel" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "· %@" } },
        "es" : { "stringUnit" : { "state" : "translated", "value" : "· %@" } },
        "fr" : { "stringUnit" : { "state" : "translated", "value" : "· %@" } },
        "hi" : { "stringUnit" : { "state" : "translated", "value" : "· %@" } },
        "ja" : { "stringUnit" : { "state" : "translated", "value" : "・%@" } },
        "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "·%@" } }
      }
    },
```

The `ja` and `zh-Hans` values differ deliberately: CJK typography uses the fullwidth middle dot `・` / no surrounding space, not the spaced Latin `·`.

- [ ] **Step 2: Verify the catalog still parses and the coverage test passes**

Run:

```bash
python3 -c "import json; d=json.load(open('Orifold/Resources/Localizable.xcstrings')); print(len(d['strings']), 'keys'); print(d['strings']['readingCanvas.pageBar.sourceLabel']['localizations'].keys())"
```

Expected: prints a key count one higher than before (1259) and `dict_keys(['en', 'es', 'fr', 'hi', 'ja', 'zh-Hans'])`.

```bash
swift test --filter LocalizationCoverageTests 2>&1 | tail -5
```

Expected: `0 failures`.

- [ ] **Step 3: Wire the page bar**

In `Orifold/Views/ReadingCanvas.swift`, replace lines 468-470:

```swift
                    Text("/ \(viewModel.pageCount)")
                        .monospacedDigit()
                        .foregroundStyle(Color.dsTextSecondary)
```

with:

```swift
                    Text("/ \(viewModel.pageCount)")
                        .monospacedDigit()
                        .foregroundStyle(Color.dsTextSecondary)
                    if let sourceLabel = viewModel.currentPageSourceLabel {
                        Text(L10n.format("readingCanvas.pageBar.sourceLabel", sourceLabel, locale: locale))
                            .foregroundStyle(Color.dsTextTertiary)
                            .lineLimit(1)
                            .help(L10n.string("readingCanvas.pageBar.sourceLabel.help", locale: locale))
                    }
```

- [ ] **Step 4: Add the help-tooltip key**

Add to `Orifold/Resources/Localizable.xcstrings`:

```json
    "readingCanvas.pageBar.sourceLabel.help" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "The page number this document prints on the page" } },
        "es" : { "stringUnit" : { "state" : "translated", "value" : "El número de página que este documento imprime en la página" } },
        "fr" : { "stringUnit" : { "state" : "translated", "value" : "Le numéro de page que ce document imprime sur la page" } },
        "hi" : { "stringUnit" : { "state" : "translated", "value" : "इस दस्तावेज़ द्वारा पृष्ठ पर छापा गया पृष्ठ संख्या" } },
        "ja" : { "stringUnit" : { "state" : "translated", "value" : "この文書がページに印刷しているページ番号" } },
        "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "此文档印在页面上的页码" } }
      }
    },
```

- [ ] **Step 5: Build and run the localization + leak gates**

Run:

```bash
swift build 2>&1 | tail -5 && swift test --filter "LocalizationCoverageTests|RawLocalizationKeyLeakTests" 2>&1 | tail -5
```

Expected: build succeeds; `0 failures`.

- [ ] **Step 6: Commit**

```bash
git add Orifold/Views/ReadingCanvas.swift Orifold/Resources/Localizable.xcstrings
git commit -m "feat: show the source page label in the page bar

Appends the document's own label after the position, and only when the
document actually carries one."
```

---

### Task 4: Search rows agree with the page bar

**Files:**
- Modify: `Orifold/Resources/Localizable.xcstrings` (add `search.pageLabelWithSource`)
- Modify: `Orifold/Views/SearchView.swift:150-153` (call site) and `:266-295` (`SearchResultRow`)

**Interfaces:**
- Consumes: `WorkspaceViewModel.pageReference(for selection: PDFSelection) -> PageReference?` (Task 2)
- Produces: nothing consumed downstream.

- [ ] **Step 1: Add the localization key**

Add to `Orifold/Resources/Localizable.xcstrings`, next to the existing `search.pageLabel`:

```json
    "search.pageLabelWithSource" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Page %@ · %@" } },
        "es" : { "stringUnit" : { "state" : "translated", "value" : "Página %@ · %@" } },
        "fr" : { "stringUnit" : { "state" : "translated", "value" : "Page %@ · %@" } },
        "hi" : { "stringUnit" : { "state" : "translated", "value" : "पृष्ठ %@ · %@" } },
        "ja" : { "stringUnit" : { "state" : "translated", "value" : "%@ ページ・%@" } },
        "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "第 %@ 页·%@" } }
      }
    },
```

Argument order in every language: **position first, label second**.

- [ ] **Step 2: Pass the reference in at the call site**

In `Orifold/Views/SearchView.swift`, replace lines 150-153:

```swift
                        SearchResultRow(
                            result: result,
                            isActive: i == viewModel.searchResultIndex
                        )
```

with:

```swift
                        SearchResultRow(
                            result: result,
                            isActive: i == viewModel.searchResultIndex,
                            reference: viewModel.pageReference(for: result)
                        )
```

- [ ] **Step 3: Rewrite the row to render the reference**

Replace the whole of `SearchResultRow` (lines 266-295) with:

```swift
struct SearchResultRow: View {
    var result: PDFSelection
    var isActive: Bool
    /// Resolved by the parent, which has the view model. The row deliberately
    /// does not read `PDFPage.label` itself: doing so reported member-local
    /// labels that collided across a merged workspace, and rendered "Page ?"
    /// for banner pages.
    var reference: WorkspaceViewModel.PageReference?
    // Passed into L10n.format() below so this view's `body` actually reads it —
    // SwiftUI only re-invokes `body` on a locale change for views that read
    // `\.locale` during the previous evaluation.
    @Environment(\.locale) private var locale

    private var snippet: String {
        result.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private var caption: String? {
        guard let reference else { return nil }
        let position = String(reference.position)
        guard let label = reference.label else {
            return L10n.format("search.pageLabel", position, locale: locale)
        }
        return L10n.format("search.pageLabelWithSource", position, label, locale: locale)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(snippet)
                .font(.dsBody())
                .foregroundStyle(isActive ? Color.dsAccent : Color.dsTextPrimary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let caption {
                Text(caption)
                    .font(.dsCaption())
                    .foregroundStyle(Color.dsTextTertiary)
            }
        }
        .padding(.vertical, .dsXS)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
```

- [ ] **Step 4: Build and run the gates**

Run:

```bash
swift build 2>&1 | tail -5 && swift test --filter "LocalizationCoverageTests|RawLocalizationKeyLeakTests|PDFPageStringGuardTests" 2>&1 | tail -5
```

Expected: build succeeds; `0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Orifold/Views/SearchView.swift Orifold/Resources/Localizable.xcstrings
git commit -m "fix: make search rows agree with the page bar

The row read PDFPage.label directly, which reported member-local labels
that collided across a merged workspace and rendered \"Page ?\" for
banner separators. It now renders the shared page reference."
```

---

### Task 5: Full verification

**Files:** none modified — this task only runs gates.

**Interfaces:**
- Consumes: everything from Tasks 1-4.
- Produces: a green build suitable for merge.

- [ ] **Step 1: Full test suite**

Run:

```bash
swift test 2>&1 | tail -15
```

Expected: `0 failures`. Roughly 900+ tests.

- [ ] **Step 2: Release build**

Run:

```bash
swift build -c release 2>&1 | tail -10
```

Expected: `Build complete`. Mandatory per CLAUDE.md — this is the build that catches duplicate `@_silgen_name` bindings merged by whole-module optimization. This change adds none, but the gate is unconditional.

- [ ] **Step 3: Lint**

Run:

```bash
swiftlint lint --quiet 2>&1 | tail -20
```

Expected: no new violations. If `WorkspaceViewModel.swift` trips a file-length rule that it was already tripping, leave it — do not restructure the file in this change.

- [ ] **Step 4: Hands-on check**

Build and install locally, then verify by hand — view-layer bugs are invisible to these tests:

1. Open `Tests/OrifoldTests/Fixtures/page-labels.pdf` and step through all four pages. Expect, in order: `· i`, `· ii`, `· 1`, `· A-7`. Page 3 does show `· 1` — the label differs from position 3, so it is real information.
2. Open `page-labels-decimal.pdf`. Expect **no** suffix on any page: it carries labels, but each says exactly what the position already says.
3. Merge `no-page-labels.pdf` into the first workspace. Its four pages must show **no** label suffix at all — this is the phantom-label case the gate exists to prevent.
4. Search for `Page` across the merged workspace. Every row's number must match the page bar when you click it, and no row may read `Page ?`.
5. Switch the app language to Japanese. The separator should render as `・` and the page bar should update live without reopening the document.

- [ ] **Step 5: Commit any fixes, then stop**

If the hands-on check surfaces a defect, fix it with a test first, then commit. Do not merge from inside this plan — merging is the caller's step.

---

## Self-review notes

- **Spec coverage:** decision 1 → Task 2 Step 3 (suppression rule); decision 2 → Tasks 3 and 4 both consuming one helper; decision 3 → untouched, `Int(_:)` parse never edited; decision 4 → Task 1. Localization table → Tasks 3 and 4. Error-handling table → Task 1 Step 3 (unreadable bytes), Task 2 Step 3 (`BoundaryPage`, member lookup). Test table → Task 2 Step 1.
- **Type consistency:** `PageReference` is referenced as `WorkspaceViewModel.PageReference` in Task 4 (nested type, declared inside the view model in Task 2) and bare inside the view model's own methods. `hasPageLabels` takes one unlabeled `Data` argument at every call site.
- **Fixture arithmetic, verified against the assembly code:** `PDFKitEngine.concatenate` inserts one `BoundaryPage` per member immediately before that member's pages, so a two-member 4+4 workspace lays out as `[banner, A0…A3, banner, B0…B3]` — member B's first page is combined index **6**, workspace position **5**. Single-member workspaces put page *n* at combined index *n*.
- **Why three fixtures and not two:** `page-labels.pdf` exercises the visible path, `no-page-labels.pdf` the gate, and `page-labels-decimal.pdf` the equality rule. The last one is not redundant — it and `no-page-labels.pdf` are indistinguishable through PDFKit, which is the exact confusion the gate exists to prevent.
