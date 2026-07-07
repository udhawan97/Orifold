# Smart Text Edit — Implementation Plan

**Status:** Plan only (no code yet). Hand-off document for execution.
**Date:** 2026-07-06
**Scope:** Make "Edit Text" detect the real text under the click, prefill the editor
with it, bind the edit to that text region, and export without ghosting — with an
*explicit* fallback for text that genuinely cannot be edited in place.

---

## 0. TL;DR — what is actually wrong

Orifold already ships a sophisticated inline text-edit pipeline (detection, glyph
reconstruction, font substitution, erase-and-redraw export, rotation handling). The
"blank white box" is **not** because the feature is missing — it's because the
detection pipeline **silently falls through to an insertion box** in several common
cases, and that fallthrough is invisible to the user. The three root causes:

1. **The PDFKit fallback block is unhittable by design.** When PDFium returns zero
   glyph boxes, `analyze()` falls back to `analyzeWithPDFKit()`, which returns a
   single whole-page block at `confidence: .low`
   ([`PDFTextAnalysisEngine.swift:527`](../../Orifold/Engine/PDFTextAnalysisEngine.swift)).
   But `hitTest()` filters out every `.low` block
   ([`PDFTextAnalysisEngine.swift:97`](../../Orifold/Engine/PDFTextAnalysisEngine.swift)).
   So on any PDF where PDFium yields no boxes — even though `page.string` clearly has
   the text — `hitTest()` returns `nil` and the click drops into
   `insertionTextBlock()` (an **empty** text box) at
   [`WorkspaceViewModel.swift:2268`](../../Orifold/ViewModels/WorkspaceViewModel.swift).

2. **No editability classification is surfaced.** The pipeline knows a lot about each
   region (confidence, font quality, whether text was found at all) but never tells the
   user *why* a region opened empty. Direct-edit, cover-and-replace, OCR, and pure
   insertion all look identical: a white box.

3. **Coordinate-space fragility.** Click points are PDFKit page-space (rotation-aware,
   crop-box relative); block bounds are PDFium **raw/unrotated media-box** content-stream
   coordinates (the export renderer documents this explicitly at
   [`PDFEditedPageRenderer.swift:19-31`](../../Orifold/Engine/PDFEditedPageRenderer.swift)).
   On rotated pages, or pages whose crop box is offset from the media box, the click and
   the block live in different spaces and `hitTest()` misses everywhere → blank box.

**The fix is a detection/classification upgrade, not a prettier overlay.** Make
fallback text hittable, classify each region's true editability, surface that in the
UX, wire OCR into the click path, and harden coordinates — all with real test coverage
(today the entire detection/render pipeline has **zero** unit tests; only
`PDFOCRTests.swift` exists).

---

## 1. Current architecture (as-built)

### 1.1 Component map

| Concern | File | Key symbols |
|---|---|---|
| Data models | `Orifold/Models/PDFTextEditingModels.swift` | `EditableTextBlock`, `PDFTextRun`, `PDFTextLine`, `PDFTextEditOperation`, `PDFTextEditFormat`, `PageEditState`, `PDFTextEditConfidence {high, medium, low}`, `CodableColor` |
| Detection engine | `Orifold/Engine/PDFTextAnalysisEngine.swift` | `analyze()`, `hitTest()`, `analyzeWithPDFium()`, `analyzeWithPDFKit()`, `blocksFromSamples()`, `resolveFontPostScriptName()`, column/wrapped-line merging |
| Click → edit orchestration | `Orifold/ViewModels/WorkspaceViewModel.swift` | `editableTextBlock(at:on:in:)` (2226), `textAnalysis(for:)` (5844, cached), `insertionTextBlock()` (2313), `applyInlineTextEdit(...)` (2402), revert/list APIs (2592–2681) |
| Canvas + inline editor UI | `Orifold/Views/ReadingCanvas.swift` | `handleClick()` (586, `.editText` case at 609), `showInlineTextEditor()` (723), `InlineTextEditorOverlay` (2306), commit/undo/match/restore controls |
| Export / render | `Orifold/Engine/PDFEditedPageRenderer.swift` | `regeneratedPage()` (14), `eraseBounds()` (98), `drawErasePatch()` + `sampledBackgroundColor()` (119/366), `drawReplacement()` (129), `measuredBounds()` (137), `regionIsBlankBackground()` (300) |
| Edit support helpers | `Orifold/Engine/PDFEditingSupport.swift` | `emptyEditAction()`, replacement bg color, bounds resize |
| OCR (document-level only) | `Orifold/Engine/PDFOCRService.swift` | `isLikelyScannedPage()`, `hasVisibleContent()`, batch "make searchable" (Vision) — **not** wired to click-to-edit |
| Export assembly | `WorkspaceViewModel.swift` | `applyTextEdits()` (4970), `inlineTextEdits(for:)` (4535) |

### 1.2 The click-to-edit flow, end to end

```
User picks "Edit Text" tool (AnnotationTool.editText, WorkspaceViewModel.swift:80)
        │
        ▼
ReadingCanvas.handleClick()  (ReadingCanvas.swift:586)
  case .editText (609):
    pagePoint = pdfView.convert(viewPoint, to: page)      // PDFKit page space
    viewModel.editableTextBlock(at: pagePoint, on: page, in: document)
        │
        ▼
WorkspaceViewModel.editableTextBlock()  (2226)
  1. analysis = textAnalysis(for: ref)                    // cached per pageRef
  2. if click ∈ an existing op's editedBounds/sourceBounds → reopen that op
  3. block = textAnalysisEngine.hitTest(pagePoint, analysis)   // ← nil ⇒ blank box
             ?? insertionTextBlock(...)                    // ← EMPTY text box
        │
        ▼
ReadingCanvas.showInlineTextEditor(block, pageRef, sourceFormat)  (723)
  InlineTextEditorOverlay:
    textView.string = block.text                          // prefill (2567)
    frame ← pdfView.convert(block.bounds, from: page)     // align over original
        │  (user edits, presses Done)
        ▼
WorkspaceViewModel.applyInlineTextEdit(...)  (2402)
  builds PDFTextEditOperation:
    isInsertion = source text empty && no lines           // blank box ⇒ insertion
    originalFormat captured once, verbatim
  stored in workspace.pageEditStates[pageRef].operations
        │  (on export / live render)
        ▼
PDFEditedPageRenderer.regeneratedPage(page, operations)  (14)
  draw background (rotation-neutralized) →
  erase source regions (sampled bg color) →
  draw replacement text
```

### 1.3 What already works well (do **not** rebuild)

- **Glyph-level extraction via PDFium** (`analyzeWithPDFium`): per-char Unicode, bbox,
  font size, fill color, weight, italic flag; reconstructs runs → lines → blocks;
  merges wrapped lines; splits/assigns columns; tightens column margins to paragraph.
- **Font substitution** (`resolveFontPostScriptName`): strips 6-char subset tags
  (`ABCDEF+Georgia-Bold`), honors descriptor weight/italic over name tokens, maps
  common families to installed substitutes, promotes to bold/italic faces.
- **Ghost-free export** (`PDFEditedPageRenderer`): erases only the true source region
  (or the destination box on manual move/resize/match — see `eraseBounds`), samples the
  local background color to fill the erase patch, redraws replacement with correct
  matrix; **rotation-safe** (renders in raw space, re-tags `/Rotate`).
- **Re-edit / reopen**: clicking an existing edit reopens the same operation and merges
  in place (`editableTextBlock` step 2); original formatting preserved verbatim in
  `PDFTextEditOperation.originalFormat` for Match/Copy/Restore.
- **Undo/redo**: snapshot-based (`InlineTextEditSnapshot`, `captureInlineTextEditSnapshot`
  / `restoreInlineTextEditSnapshot`).
- **Insertion vs replacement discipline**: `isInsertion` ops never paint erase patches
  (nothing to erase) — this is why brand-new text doesn't stamp a white rectangle.

---

## 2. Why the blank box appears (detailed failure taxonomy)

`hitTest()` returns `nil` (→ `insertionTextBlock` → empty box) under these conditions.
Each needs a distinct remedy:

| # | Condition | Current behavior | Root cause |
|---|---|---|---|
| A | PDFium extracts 0 glyphs, but `page.string` has text (some encodings, CID fonts, unusual ToUnicode) | Falls to `.low` whole-page block → filtered out of `hitTest` → blank box | Fallback block is `.low` and unhittable; also whole-page granularity is useless for hit testing |
| B | Genuinely scanned/flattened page (no text layer at all) | Blank box, no explanation | No OCR in click path; no "this is scanned" messaging |
| C | Vector-outline text (glyphs converted to paths) | Blank box | Same as B — no recoverable text; not classified |
| D | Rotated page (90/270) | `hitTest` misses (coordinate space mismatch) | Click is rotation-aware PDFKit space; block bounds are raw PDFium space |
| E | Crop box offset from media box | `hitTest` misses near edges/systematically | Same coordinate origin mismatch |
| F | Click lands just outside tight glyph bounds (leading/trailing whitespace, kerning) | Blank box | `tolerance: 5` too tight; no line-band fallback |
| G | Detected block exists but `confidence == .low` from a low-quality PDFium read | Filtered out | Binary confidence gate; no graceful degrade to "cover-and-replace" |
| H | Form field / AcroField text | Blank box or wrong region | Forms not represented in analysis at all (`PDFFormSupport` is separate) |

**Observation:** Cases A, D, E, F, G are *false negatives* — the text is editable but we
fail to bind to it. Cases B, C, H are *true negatives* — we should switch to an explicit
mode, not silently drop an empty box.

---

## 3. Target design

### 3.1 Editability classification (the core new concept)

Introduce an explicit per-region classification, computed at detection time and carried
on the block, so the UX and export can branch on it. Extend
`PDFTextEditingModels.swift`:

```swift
enum PDFTextEditability: String, Codable {
    case direct       // real glyphs, high-confidence bounds → edit in place, erase+redraw
    case replace      // text recoverable but geometry/font uncertain → cover matching bg + redraw
    case ocr          // no text layer; OCR produced a candidate → editable via replace path
    case overlayOnly  // vector outline / undecodable / image with failed OCR → cover + new text, labelled
    case insertion    // empty spot, user is adding brand-new text
}
```

Add to `EditableTextBlock`:
```swift
var editability: PDFTextEditability
var textSource: PDFTextSource   // .pdfiumGlyphs | .pdfKitString | .ocr | .none
var ocrConfidence: Float?       // when textSource == .ocr
```

**Classification rules (in `PDFTextAnalysisEngine`):**

- `analyzeWithPDFium` blocks with valid per-line bounds and resolvable font →
  `.direct`, `confidence .high`.
- `analyzeWithPDFium` blocks with text but implausible/missing bounds or unresolved font
  → `.replace`, `confidence .medium`.
- `analyzeWithPDFKit` → **stop returning a single whole-page `.low` block.** Instead
  reconstruct **line-level** blocks from PDFKit selections (`page.selectionForLine`,
  per-line `bounds(for:)`), classify `.replace`, `confidence .medium`, `textSource
  .pdfKitString`. These become hittable (see §3.3).
- OCR path (new, §3.6): `.ocr`, confidence from Vision, hittable.
- No text recoverable anywhere under the click → `.overlayOnly` (explicit cover mode),
  or `.insertion` if the region is blank background.

### 3.2 Hit testing upgrade

Rewrite `hitTest()` to be tiered and classification-aware
([`PDFTextAnalysisEngine.swift:97`](../../Orifold/Engine/PDFTextAnalysisEngine.swift)):

1. **Line-band priority:** find blocks whose bounds (or any constituent line bounds)
   contain the point within tolerance; among ties prefer the block whose column contains
   the point (reuse `closestTextBlock` column logic already in `WorkspaceViewModel`).
2. **Stop filtering by `.low`.** Filter by *editability* instead: `.direct`, `.replace`,
   `.ocr` are all hittable; only truly empty analysis yields insertion.
3. **Adaptive tolerance:** small for `.direct` (tight glyphs), larger vertical band for
   line selection (half the line height) so clicks in inter-word gaps still resolve.
4. **Return the smallest containing region**, not the first — so clicking a word in a
   dense table doesn't grab the whole paragraph.

### 3.3 Coordinate normalization (fix D/E)

Create one authoritative conversion so click space and block space always match. Add a
helper (engine or a small `PDFCoordinateSpace` util):

- Detection stores block bounds in **raw content-stream space** (what PDFium returns and
  what `PDFEditedPageRenderer` already assumes — keep this as the canonical space).
- Before `hitTest`, convert the incoming PDFKit `pagePoint` into raw space:
  - subtract `mediaBox.origin` vs `cropBox.origin` delta,
  - invert the page `/Rotate` (90/180/270) about the media box.
- Symmetric conversion already exists implicitly in the renderer's rotation-neutralizing
  trick; extract it into a shared, unit-tested function used by **both** hit testing and
  rendering so they can never drift.

**Acceptance for this step:** a click on visible text of a 90°-rotated page resolves to
the correct block (currently fails).

### 3.4 The click orchestration, revised

`editableTextBlock(at:on:in:)`
([`WorkspaceViewModel.swift:2226`](../../Orifold/ViewModels/WorkspaceViewModel.swift))
becomes:

```
1. analysis = textAnalysis(for: ref)                 // cached
2. reopen existing op if click ∈ its bounds          // unchanged
3. point' = normalizeToRawSpace(pagePoint, page)     // NEW (§3.3)
4. block = hitTest(point', analysis)                 // tiered (§3.2)
5. if block == nil AND page looks scanned/flattened:
       block = ocrProbe(point', page)                // NEW (§3.6), may be async
6. if block == nil:
       block = insertionTextBlock(...)               // last resort, .insertion
7. return (ref, block, sourceFormat)  // now also carries block.editability
```

`insertionTextBlock` stays as the **explicit** last resort only.

### 3.5 UX design

**Default = transparent edit mode.** No opaque white box ever appears for `.direct` /
`.replace` / `.ocr`. The overlay editor:

- Prefills `textView.string = block.text` (already done, `ReadingCanvas.swift:2567`).
- Frame aligns exactly over the original via `pdfView.convert(block.bounds, from: page)`
  (already done); with §3.3 fixed this is now correct on rotated/offset pages.
- Background is **transparent** while editing (the underlying page text is momentarily
  hidden via a live erase preview, so the user sees their edit replace the original in
  place — not a box floating above it).

**Per-classification affordances (small status chip on the editor):**

| Editability | Chip label (localized) | Behavior |
|---|---|---|
| `.direct` | *(none / "Editing text")* | Transparent in-place edit, erase+redraw on export |
| `.replace` | "Reconstructed — style matched to nearby text" | Edit in place; export covers matching background + redraws |
| `.ocr` | "Recognized text (OCR) — verify before saving" | Prefilled from OCR, user confirms; export covers + redraws |
| `.overlayOnly` | "This text is flattened/scanned — Orifold will cover and replace it." | Explicit cover box with sampled bg; user acknowledges |
| `.insertion` | "New text" | No erase; brand-new text |

- **No-op guard:** pressing **Done** with unchanged text must produce **zero** geometry
  change and **no** operation (or a no-op that renders identically). Today
  `commitChanges` has `emptyEditAction` guards; extend so "text identical to
  `block.text` AND no style/geometry change" short-circuits without creating an op →
  satisfies acceptance "No layout shifting when pressing Done without changes."
- **Undo/redo:** keep the existing snapshot mechanism; every classification path funnels
  through `applyInlineTextEdit` so undo already covers it. Add tests.
- **Accessibility / keyboard:** the editor is an `NSTextView`; ensure the classification
  chip has an `accessibilityLabel`, the editor is reachable/dismissable by keyboard
  (Esc = cancel, Cmd-Return = done), and VoiceOver announces the detected text on open.
- **Multi-language:** all new strings go through `L10n` into
  `Orifold/Resources/Localizable.xcstrings` for all 6 languages (there is a
  `LocalizationCoverageTests` gate — every key must exist in every language or CI fails;
  see memory `spm-localizable-xcstrings-ci-fix`). Detection itself is script-agnostic
  (works on Unicode scalars) — verify with CJK/RTL samples.

### 3.6 OCR fallback for scanned/flattened (fix B, and A when text is unusable)

Wire the existing `PDFOCRService` (Vision) into a **region-scoped** click path:

1. On click with no text hit, if `PDFOCRService.isLikelyScannedPage(page)` (or the
   clicked region has image content and no glyphs), run Vision OCR **on a cropped raster
   of the clicked line-band only** (fast; not the whole page).
2. Map recognized `VNRecognizedTextObservation` bounding boxes back into raw page space;
   pick the observation under the click.
3. Produce an `EditableTextBlock` with `editability .ocr`, prefilled recognized text,
   estimated font size from the observation height, `sampledBackgroundColor` for cover.
4. Show the OCR chip ("verify before saving"). On Done, export covers the source raster
   region with sampled bg + draws the replacement (same `PDFEditedPageRenderer` path as
   `.replace`).

**Performance:** region OCR is cheap; cache per-page OCR results keyed by pageRef (like
`textAnalysisCache`) so repeated clicks on the same page don't re-OCR. Keep OCR
**local** (Vision, on-device) — no cloud, matching the local-first constraint.

### 3.7 Export behavior (no duplication / no ghost)

The renderer already does the right thing; the plan is to **extend, not replace**:

- `.direct` / `.replace`: erase source line bounds with sampled bg (`eraseBounds` +
  `drawErasePatch`), draw replacement. Already implemented — verify per classification.
- `.ocr` / `.overlayOnly`: source has no vector text to erase (it's a raster). Erase =
  paint sampled-bg rectangle over the source raster region, then draw replacement.
  Extend `eraseBounds` to treat `.ocr`/`.overlayOnly` like a manual-geometry erase (the
  region **is** the thing to cover).
- **Ghost prevention for case A** (PDFium empty but real vector text present): a sampled-
  bg rectangle covers raster but **not** underlying vector glyphs if they're still in the
  content stream. For `.replace` derived from PDFKit strings we must **actually remove**
  the source text, not just paint over it — otherwise the old glyphs bleed through at high
  zoom / in Acrobat's text layer. Options, in preference order:
  1. **Content-stream redaction via QPDF/PDFium**: locate and remove the text-showing
     operators for the source region (true removal — best fidelity, hardest).
  2. **Rasterize-and-cover** the source line band (renderer already rasters background);
     acceptable for `.replace`/`.ocr`, loses selectable text under the patch only in that
     band.
  - Phase 3 ships (2) as the safe default; Phase 5 investigates (1) for `.direct`.
- **Cross-viewer validation:** exported PDFs must render identically in Preview, Acrobat,
  Chrome PDFium, and mobile (iOS/Android) viewers. Add a manual QA checklist + a golden-
  image regression harness (render page to bitmap, diff against approved baseline).

---

## 4. Technical feasibility matrix

| Text type | Detectable? | Editable path | Export strategy | Notes |
|---|---|---|---|---|
| Real embedded (selectable) text | ✅ PDFium glyphs | `.direct` | Erase source line bounds + redraw | Best case; already works when bounds/coords align |
| Fragmented glyph runs | ✅ (reconstructed) | `.direct`/`.replace` | Erase per-line bounds + redraw | `blocksFromSamples` already merges runs/lines/columns |
| Subset fonts (`ABCDEF+…`) | ✅ | `.direct` | Redraw with substitute face | `resolveFontPostScriptName` strips tag, matches weight/italic |
| Scanned OCR text | ⚠️ needs OCR | `.ocr` | Cover raster region + redraw | New region-OCR path (§3.6), Vision, local |
| Vector-outline text | ❌ no text layer | `.overlayOnly` | Cover + new text, labelled | Cannot recover characters; explicit cover mode |
| Rotated / skewed text | ✅ (after coord fix) | `.direct` | Renderer already rotation-safe | 90/180/270 via §3.3; arbitrary skew = `.replace` best-effort |
| Forms / AcroFields | ⚠️ separate | route to field editor | Update field value, not content stream | Detect field under click, hand to `PDFFormSupport` instead of text edit |
| Encrypted / permission-restricted | ⚠️ conditional | gated | n/a | If decrypted in-session, treat normally; if content-extraction/modify perms denied, disable Edit Text with a clear message (use `PDFEncryptionService`/QPDF perms) |

Legend: ✅ supported · ⚠️ conditional/new work · ❌ overlay-only fallback.

---

## 5. Staged implementation plan

Each phase is independently shippable and testable.

### Phase 1 — Detect & prefill the clicked text (fix the blank box for real text)
- Add `PDFTextEditability` + `textSource` to models (§3.1).
- **Make PDFKit fallback hittable**: replace the single `.low` whole-page block in
  `analyzeWithPDFKit` with **line-level** `.replace` blocks reconstructed from PDFKit
  line selections.
- Tiered `hitTest` that filters by editability, not `.low` (§3.2).
- Coordinate normalization for rotated/offset pages (§3.3), shared with renderer.
- **Exit criteria:** clicking visible text (embedded, fragmented, subset-font, rotated)
  opens the editor **prefilled** with the exact detected text; blank box only on
  genuinely empty spots.

### Phase 2 — Inline editor alignment & styling
- Editor frame exact over source (verify with §3.3 fix); transparent edit mode with live
  in-place erase preview (no floating white box).
- Classification chip UI + localized strings (§3.5).
- No-op guard on Done (unchanged text ⇒ no operation, no layout shift).
- Accessibility labels, keyboard (Esc/Cmd-Return), VoiceOver announce.
- **Exit criteria:** bold labels and normal values edit in place, aligned; Match/Copy/
  Paste/Reset formatting still work (already implemented — regression-test them).

### Phase 3 — Replace/export without ghosting
- Per-classification `eraseBounds` (`.ocr`/`.overlayOnly` cover the region).
- Rasterize-and-cover safe default for `.replace`; verify no ghost text behind new text.
- Golden-image export regression harness + cross-viewer QA checklist (§3.7).
- **Exit criteria:** exported PDF shows only final text, no duplicates/ghosts, correct in
  Preview/Acrobat/Chrome/mobile.

### Phase 4 — OCR fallback for scanned PDFs
- Region-scoped Vision OCR in the click path with per-page cache (§3.6).
- `.ocr` chip + "verify before saving" UX; export covers raster + redraws.
- **Exit criteria:** clicking a line on a scanned hotel reservation prefills recognized
  text and exports a clean cover-and-replace.

### Phase 5 — Advanced paragraph reflow + regression hardening
- Multi-line paragraph reflow (word wrap within column bounds already partially handled
  via `columnBounds`/`mergeWrappedLines`) — extend so editing a long line reflows the
  paragraph.
- Investigate true content-stream text removal (QPDF/PDFium) for `.direct` (§3.7 option 1).
- Full regression suite (see §7); performance pass on large PDFs.

---

## 6. Acceptance criteria & test cases

**Functional acceptance (map 1:1 to the brief):**
1. Click a hotel reservation line → editor opens **prefilled** with that line's text.
2. Bold labels and normal values both editable, with correct substitute font/weight.
3. Match / Copy / Paste / Reset formatting continue to work after the changes.
4. Undo/redo works after every edit, style change, move, and revert.
5. Pressing **Done** with no changes causes **no** layout shift and creates no op.
6. Exported file contains the final visible text only.
7. **No white blank boxes** unless `.overlayOnly` cover mode is explicitly active and
   labelled.

**Test cases (new `PDFTextEditingTests.swift` + `PDFTextAnalysisTests.swift`):**
- Unit: coordinate normalization round-trips for 0/90/180/270 and offset crop box.
- Unit: `hitTest` returns the correct block for embedded, fragmented, subset-font,
  and PDFKit-fallback (`.replace`) cases; returns `.insertion` only on blank areas.
- Unit: classification assignment per fixture (one PDF per type from a curated corpus).
- Unit: `eraseBounds` per editability; `isInsertion` never erases.
- Snapshot: `regeneratedPage` golden-image diff for direct/replace/ocr/rotated.
- Integration: `applyInlineTextEdit` → export → re-open round-trips text and formatting.
- Regression: no-op Done leaves bytes/geometry unchanged.
- L10n: `LocalizationCoverageTests` passes with all new keys in all 6 languages.

**Curated test corpus** (`Tests/OrifoldTests/Fixtures/textedit/`): embedded-text.pdf,
fragmented.pdf, subset-font.pdf, scanned.pdf, vector-outline.pdf, rotated-90.pdf,
offset-cropbox.pdf, acroform.pdf, encrypted-restricted.pdf, multi-column.pdf, CJK.pdf,
RTL.pdf.

---

## 7. Risks & mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| **Subset fonts** substitute imperfectly (metrics differ) | Replacement text width/kerning drifts | `resolveFontPostScriptName` + measure with substitute; erase full source line band so drift never reveals old text; allow manual width nudge (already supported) |
| **Editing content streams** to truly remove text (option 1) | High complexity, corruption risk | Ship rasterize-and-cover first (safe); gate content-stream removal behind fixtures + validation; always `PDFSerializer`-verify output before accepting |
| **Text drawn as image** | Cannot recover characters | Region OCR (`.ocr`), else explicit `.overlayOnly` cover mode — never a silent blank box |
| **Exact spacing / reflow** | Visible layout shift | Preserve `originalFormat` verbatim; erase per-line bounds; reflow only within `columnBounds`; golden-image diff catches regressions |
| **Malicious / malformed PDFs** | Crash, OOM, RCE surface | PDFium already sandboxed via `pdfiumLock` + size guards (`data.count <= Int32.max`); add fuzz fixtures; never trust reported bounds without sanity clamps; keep all processing local |
| **Encrypted / permission-restricted** | Illegal edit or crash | Check extract/modify perms (QPDF/`PDFEncryptionService`); disable Edit Text with a clear localized message when disallowed |
| **Performance on large PDFs** | UI stalls | Per-page `textAnalysisCache` (exists) + OCR cache; analyze lazily on first click per page; region-only OCR; run detection off the main actor, hop back to apply |
| **Coordinate regressions** | Silent blank boxes return | Single shared normalization function, unit-tested both directions; used by hit test **and** renderer so they can't drift |
| **Zero current test coverage** of detection/render | Regressions ship unnoticed | Phase 1 lands the test scaffold + corpus **before** behavior changes |

---

## 8. Engineering strategy / libraries

- **Reuse in-app, no new deps for core:** PDFium (`Packages/PDFiumBinary`) for glyph
  extraction; PDFKit for fallback selections + rendering; Vision (Apple, on-device) for
  OCR; QPDF (`Packages/QPDFBinary`) for permissions and future content-stream ops;
  Core Graphics for erase/redraw. All already vendored.
- **No paid APIs, no cloud, local-first only** — every path above is on-device.
- **If a helper is ever needed** (not expected): only OSS/free (e.g. keep within
  PDFium/QPDF). Do **not** add cloud OCR.
- **Concurrency:** detection and region-OCR run off-main; results applied on the main
  actor (the VM is `@Observation`-based). Respect existing cancellation tokens
  (`OperationCancellationToken`).

---

## 9. Where changes land (file-by-file)

- `Orifold/Models/PDFTextEditingModels.swift` — add `PDFTextEditability`, `textSource`,
  `ocrConfidence`; extend `EditableTextBlock` (+ `PDFTextEditOperation` carries
  editability for export branching).
- `Orifold/Engine/PDFTextAnalysisEngine.swift` — classification in
  `blocksFromSamples`/`buildBlock`; **line-level** `analyzeWithPDFKit`; tiered
  `hitTest`; extract coordinate normalization helper.
- `Orifold/ViewModels/WorkspaceViewModel.swift` — `editableTextBlock` orchestration
  (normalize → tiered hit → OCR probe → insertion); OCR cache; keep `applyInlineTextEdit`
  but thread `editability` through the op.
- `Orifold/Views/ReadingCanvas.swift` — `showInlineTextEditor`/`InlineTextEditorOverlay`:
  transparent in-place mode, classification chip, no-op-Done guard, a11y/keyboard.
- `Orifold/Engine/PDFEditedPageRenderer.swift` — per-editability `eraseBounds`; rasterize-
  and-cover for `.ocr`/`.overlayOnly`; share the coordinate helper.
- `Orifold/Engine/PDFOCRService.swift` — add region-scoped `recognizeText(in rect:on:)`.
- `Orifold/Resources/Localizable.xcstrings` — all new strings ×6 languages.
- `Tests/OrifoldTests/` — new `PDFTextAnalysisTests`, `PDFTextEditingTests`,
  `PDFEditedPageRendererTests` + `Fixtures/textedit/` corpus.

---

## 10. Explicit non-goals

- Do **not** "make the overlay textbox prettier." The white box is a symptom.
- Do **not** convert the whole page to editable rich text (this is a PDF, not a word
  processor); edit is region-bound.
- Overlay-only cover mode is acceptable **only** as an explicit, labelled fallback for
  scanned/flattened/vectorized/unsupported text — never the default and never silent.
