# Source page labels (`/PageLabels`) — design

**Date:** 2026-07-31
**Status:** Approved, ready for planning
**Scope:** Read-only. Surface a source document's own page labels in the page bar and the
search results list, gated on the document genuinely carrying them.

## Problem

A PDF may carry a `/PageLabels` number tree — the numbering the document prints on its own
pages. Front matter runs `i, ii, iii`, the body restarts at `1`, an offprint starts at `247`,
a legal exhibit reads `A-7`. Orifold has never surfaced this in the page bar: a reader looking
at the page the document calls `iv` sees `4`.

There is one exception, and it is wrong in two ways. `SearchView.swift:275` calls
`PDFPage.label` directly:

```swift
private var pageLabel: String {
    result.pages.first.flatMap { $0.label } ?? "?"
}
```

1. **Banner pages render `"Page ?"`.** `BoundaryPage` instances return `nil` from `.label`
   and hit the `?? "?"` fallback.
2. **Labels stay source-derived after reparenting into the combined document.** Probed
   directly: a two-member workspace assembled the way `PDFKitEngine.swift:63-67` assembles it
   yields labels `["nil", "1", "2", "nil", "1", "2"]` even though `page.document === combined`.
   So search shows "Page 1, Page 2, Page 1, Page 2" while the page bar reads 1, 2, 3, 4.

This design makes the two surfaces agree, and makes both of them honest.

## Decisions taken

| # | Decision | Rationale |
|---|---|---|
| 1 | **Position primary, source label appended only when it differs** | Navigation never becomes ambiguous in a merged workspace; fidelity is added exactly where it carries information. |
| 2 | **Scope: page bar + search, driven by one shared helper** | Both surfaces stop deriving their own answer, so the banner bug and the merge collision die at the root rather than being guarded. |
| 3 | **Jump field stays integer-only** | Keeps this a read-only display feature end to end. No collision rules to invent, no field widening. |
| 4 | **qpdf gates presence, PDFKit renders the string** | PDFKit already implements the `/S` `/P` `/St` grammar. The probe neutralizes its one flaw — silent synthesis. Zero new bindings. |

## Why the gate is mandatory

`PDFPage.label` **synthesizes** ordinals for documents with no `/PageLabels` and never returns
nil for a real page. Probed:

```
labeled:   ["i", "ii", "1", "A-7"]     ← real /PageLabels
unlabeled: ["1", "2"]                  ← SYNTHESIZED, not nil
```

PDFKit alone can therefore never answer "does this document carry real page labels?" Without a
gate, decision 1 ("append when it differs") fires on every unlabeled member of a merged
workspace: member B's synthesized `"1"` differs from workspace position 31, so the page bar
would append `· 1` — a number the source never claimed.

The gate is free. `QPDFService.swift:122` `hasXMPMetadata` is already exactly this shape:

```swift
static func hasXMPMetadata(_ data: Data, password: String? = nil) -> Bool {
    withQPDF(data, description: "xmp-probe", password: password) { qpdf in
        qpdf_oh_has_key(qpdf, qpdf_get_root(qpdf), "/Metadata") == QPDF_TRUE
    } ?? false
}
```

`/PageLabels` hangs off the same catalog root. No PDFium binding, so no
`@_silgen_name` whole-module-optimization hazard.

`FPDF_GetPageLabel` **is** exported by the vendored PDFium in both slices and would also work,
but it costs a new binding to answer a question qpdf answers with an existing helper. Rejected
on that basis, not on capability.

## Architecture

```
member bytes (Data)
  └─ QPDFService.hasPageLabels(_:)             ← qpdf, once per member, cached by member UUID
        └─ WorkspaceViewModel.pageReference(for:in:)
              ├─ position ← workspacePageNumber(for:in:)      (unchanged, basis W)
              └─ label    ← gate ? page.label : nil
                             then suppressed when == String(position)
                    ├─ ZoomPageBar        → "Page [3] / 320 · iii"
                    └─ SearchView parent  → SearchResultRow(position:label:)
```

### The gate — `QPDFService.hasPageLabels(_:)`

```swift
/// True when the document catalog carries a `/PageLabels` number tree.
static func hasPageLabels(_ data: Data) -> Bool
```

Added **next to `hasXMPMetadata` in `QPDFService.swift`**, not in a new file. It is the same
kind of catalog-key probe, six lines long, and `QPDFService` is already the sanctioned home for
them. A separate `PageLabelService` file would only earn its keep if we were also parsing the
number tree, and decision 4 explicitly declines to.

Pure function of bytes. Takes **no password parameter**: the sibling precedent at
`WorkspaceViewModel.swift:2604` calls `PDFMetadataService.read(from: data)` with no password,
so encrypted members already degrade silently in this class of read. Matching that is honest;
adding a parameter nothing passes is not.

### View-model helper — new `// MARK: - Page reference` section

```swift
struct PageReference {
    let position: Int
    let label: String?
}

func pageReference(for page: PDFPage, in pdfDocument: PDFDocument?) -> PageReference?
```

- Returns `nil` for `BoundaryPage`. Banners are not pages and get no caption.
- `position` delegates to the existing `workspacePageNumber(for:in:)`
  (`WorkspaceViewModel.swift:1419`). Basis W stays a pure ordinal; nothing about the existing
  numbering changes.
- `label` resolves `page → PageRef → member`, consults the presence cache, and reads
  `page.label` only when that member genuinely carries `/PageLabels`. Suppressed when the
  result equals `String(position)`.

Backed by `private var pageLabelPresence: [UUID: Bool]`, keyed by `MemberDocument.id`,
**in-memory only**.

Not persisted and not added to `MemberDocument`. `PageRef.swift:6-8` is the cautionary
precedent in this repo: `rotation` and `cropBox` are declared, `Codable`, persisted, and never
written by any mutation. A derived fact does not need a schema, and skipping persistence avoids
both a `Workspace` version bump and the dual-write hazard that `applyRename`
(`WorkspaceViewModel.swift:1507-1511`) already has to manage.

Invalidation: drop the member's entry in `mutateMemberBytes`, the single atomic entry point for
document-level byte changes. Nothing is needed on member add or remove — a member UUID is never
reused, so an entry left behind by a removed member is inert rather than stale, and a newly
added member simply has no entry yet.

### View edits

**Page bar** — `ReadingCanvas.swift:468`, append after the existing `/ 320`.

`ZoomPageBar` (`ReadingCanvas.swift:343`) already reads `@Environment(\.locale)` at `:348`
and forces the dependency with `let _ = locale` at `:351`, so live language switching already
works there and the new string needs no additional plumbing.

**Search row** — `SearchView.swift:150`. `viewModel` is already in scope at the call site, so
the parent computes the reference and passes `position` and `label` into `SearchResultRow`.
The row keeps rendering values and loses its own `PDFPage.label` access entirely. That is what
removes `"Page ?"` at the root instead of guarding it.

## Localization — two new keys, zero edits to existing translations

`L10n.format` (`L10n.swift:118-119`) is:

```swift
String(format: string(String.LocalizationValue(key), locale: locale), arguments: args)
```

The `locale` argument reaches the **catalog lookup only**, never `String(format:)`. So `%lld`
and `%@` both render ASCII digits and there is no locale-digit advantage to either. This
removes any need to flip `search.pageLabel`'s specifier across six languages.

| Key | Value | State |
|---|---|---|
| `search.pageLabel` | `"Page %@"` | **unchanged**, now fed `String(position)`. Sole call site `SearchView.swift:288`, verified. |
| `search.pageLabelWithSource` | `"Page %@ · %@"` | **new**, × 6. Argument order: position, then label. |
| `readingCanvas.pageBar.sourceLabel` | `"· %@"` | **new**, × 6. Single argument: label. |

When `pageReference` returns nil the search row renders no caption line at all, rather than a
placeholder.

Both new strings go through `L10n.format` deliberately. `RawLocalizationKeyLeakTests` skips
lines containing `L10n.format` wholesale (`:83`), and its dotted-identifier regex
`[a-z][a-zA-Z0-9]*(\.[a-zA-Z0-9]+)+` would otherwise flag a legitimate document label such as
`a.1` as a leaked key.

`LocalizationCoverageTests` fails on any key missing `en` or any of
`es, fr, hi, zh-Hans, ja`. Both new keys need all six at the same commit.

## Error handling

Every failure path collapses to "no label", which is exactly today's behavior:

| Failure | Result |
|---|---|
| Corrupt or encrypted member bytes | `withQPDF` returns nil → `?? false` → gate closed |
| Member lookup fails | `pageReference` returns nil → caption omitted |
| `BoundaryPage` | nil by construction — `"Page ?"` disappears rather than being special-cased |
| Label present but equal to position | suppressed, page bar reads as it does today |

## Tests

**`QPDFServicePageLabelTests`** — fixture carrying a real `/PageLabels` number tree returns `true`;
fixture without returns `false`.

Fixture built with `Tests/OrifoldTests/Fixtures/make-tagged-fixtures.py`, whose `build_pdf`
emits byte-exact xref offsets. A 714-byte 4-page fixture with
`/Nums [0 << /S /r >> 2 << /S /D /St 1 >> 3 << /S /D /P (A-) /St 7 >>]` has already been shown
to read back `["i", "ii", "1", "A-7"]`. Loaded `#filePath`-relative, as
`StructureInspectionServiceTests.swift:143` does — `Package.swift:46-50` declares the test
target with no `resources:` block, so no manifest edit and no `xcodegen generate` is needed.

**`PageReferenceTests`** (`@MainActor`) —

| Case | Expectation |
|---|---|
| Labeled single member, front matter | position 3 → label `"iii"` |
| Unlabeled single member | label nil at every page |
| Merged labeled + unlabeled | each page resolves against its own member |
| Label equals position | suppressed |
| `BoundaryPage` | `pageReference` returns nil |

**Traps to route around:**

- The fixture must **not** round-trip through `dataRepresentation()` the way
  `OutlineFixturePDFBuilder.swift:48` deliberately does. Outlines survive that round trip;
  `/PageLabels` does not — probed: `["i","ii","1","A-7"]` becomes `["1","2","3","4"]` and the
  bytes no longer contain `/PageLabels`.
- `PDFPageStringGuardTests` matches on **identifier name**, not type. No test symbol may be
  named such that `pageLabel.string` or `pageLabels.first.string` appears in source.
- Never assert on `PDFPage.string`; use `PDFTextAnalysisEngine` text extraction or
  thumbnail-brightness checks.

## Non-goals

Stated so they do not creep in during implementation:

- **No label writing.** Export continues to drop `/PageLabels` through the PDFKit round trip in
  `PDFKitEngine.swift:70-71` and `:90-91` — unchanged from today, not a regression introduced
  here. Writing would require the `qpdfjob` argv route (`--set-page-labels`, flag strings
  confirmed present in the vendored `libQPDF.a`) and would have to slot after the late bookmark
  write in the documented export order.
- **Jump field stays integer-only.** `Int(_:)` parse and the 34pt frame are untouched.
- **Sidebar member-local `p. N` untouched.** That is a different numbering basis, not a label.
- **No member name in the search row.** Today's row does not show one; adding it is a separate
  feature.

## Filed separately, not fixed here

Found while mapping the numbering surface. All real, none in scope:

1. **Recents thumbnail reads the wrong index space.** `ContentView.swift:233` passes a 0-based,
   banner-excluded workspace index; `RecentsStore.swift:64-65` uses it directly as a
   banner-included `combinedPDF` index. For a never-scrolled workspace it renders the
   `BoundaryPage` banner as the file's thumbnail.
2. **"Resume at page N" is written, displayed, and never honored.** `RecentFilesSection.swift:152`
   shows it, but nothing reads `lastPageOpened` back on open. Both reopen paths land on page 1.
3. **Four unlocalized `"p. N"` formatters** at `WorkspaceViewModel.swift:2014`, `:8020`,
   `WorkspaceDocument.swift:553`, and `:7235`. `RawLocalizationKeyLeakTests` only scans
   `/Views/`, `/Pet/`, `/App/`, which is why they survived. Two of the four write into files the
   user ships to someone else.
4. **`PDFDecorationExportBaker.swift:142`** — `String(localized: "Page \(x) of \(y)")` produces a
   compiler-derived key with no catalog entry, so the only page number that persists into
   exported bytes is English in all six languages.
5. **`hi` `search.results.position` looks argument-reversed** — `"%lld में से %lld"` against `en`
   `"%lld of %lld"`. Flagged as probable, not confirmed.
6. **`SearchView.swift:27` lacks the `max(_, 1)` floor** that `ReadingCanvas.swift:406` applies
   to the same key, so the two disagree in the pre-selection state where `searchResultIndex` is
   `-1`.

## Verification

- `swift build && swift test` (~900 tests)
- `swift build -c release` — mandatory per CLAUDE.md, even though this change adds no
  `@_silgen_name` binding
- `swiftlint lint --quiet`
- Hands-on: open a PDF with roman front matter, confirm the page bar reads `· iii`; merge a
  second unlabeled PDF, confirm no phantom label appears on its pages; search across both and
  confirm the rows agree with the page bar.
