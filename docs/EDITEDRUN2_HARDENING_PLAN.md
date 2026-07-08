# editedrun2.pdf Hardening — Implementation Plan

**Status:** SHIPPED (P0 + P1) 2026-07-08. P3 (WP-G/H/I) deferred by design — see below.

## Implementation status

**Shipped and verified:**
- **WP-A (P0)** — wrap-plausibility + role/label-colon vetoes + reliably-narrowed-column
  gate: header/table-cell lines stay separate; wrapped control paragraphs still merge.
- **WP-B (P0)** — font-size unanimity decision helper (`resolvedSize`); union-clamp and
  measured-ratio sub-parts intentionally dropped (regressed the size-accuracy suite —
  documented deferral).
- **WP-C (P0)** — editor no-reflow: 1-line stays 1-line, committed size within 6% of source.
- **WP-D (P1)** — `hitTest` line-containment tie-break (smallest line-containing block wins).
- **WP-E (P1)** — detected-font mono tag (`NSFont.isFixedPitch`), 0.5pt rounding, 0.3pt dedup.
- **WP-F (P0)** — bake-stamp (`/OrifoldBakeStamp`) stamp-first reconciliation + per-machine
  external-modification fingerprint sidecar (visible content wins, stale edits discarded,
  one-line notice).

**Deferred (P3 — each individually droppable per §3; precise TODOs remain in this doc and
`docs/EDITING_HARDENING_V2_PLAN.md`):**
- **WP-G rotated bakers** — riskiest package (visual-signature save path); the plan itself
  said drop if ambiguous. Deferred to a focused, review-gated pass.
- **WP-H annotation-undo stable handles** — a ~12-site refactor of the markup undo/redo
  system; high regression surface (a subtle error corrupts all markup undo). Deferred to a
  dedicated pass with full undo-suite coverage rather than landed autonomously.
- **WP-I Type3/Skia dirty-tracking** — export-side verbatim-bytes optimization; safe only
  with exhaustive enumeration of every annotation mutation vector (a missed vector = silent
  save loss). Deferred pending that enumeration.
- **Cross-member pristine lockstep (item G)** — deferred again, same rationale as v2.

_Original planning text preserved below for the deferred packages._

**Status (original):** Planning only. Written 2026-07-08 for execution by Opus.
**Baseline:** `main` @ `4195a9d` (post editing-hardening-v2: PageGraphicsIndex, underline
survival, table-safe erase, deletion-as-commit, detected-fonts menu, Match
grid/marker/dominant-cluster ranking, bullet split, patch dimming, inspector badges,
sanitize strip — see `docs/EDITING_HARDENING_V2_PLAN.md` status banner).
**Fixture:** `/Users/umang/Documents/development/test-files-Orifold/editedrun2.pdf`
(local-only, CI-skip-guarded — established pattern). Generated CI equivalents specified in §4.
**Branch:** `edit-hardening-v3/<slug>` off latest `main`. Two green verification loops
(§8), merge, post-merge validation (§9), report (§10).

Everything in §1 was verified **empirically by running the current engine against the
fixture** (probe results inline). Line anchors are for `4195a9d`; anchor by symbol.

---

## 0. Fixture facts (probed, don't re-derive)

- 5 pages, **no embedded Orifold workspace state** (it's a flat export, not a workspace
  save). No prior-op re-routing is involved in any of the reported failures.
- **Page 1** (index 0) is a monospaced (**Monaco**) text-import render: title block, a
  "Prepared by:" line, an OVERVIEW section, a bullet-numbered objectives list, and a
  rule-LESS table (Phase/Duration/Owner columns, no vector rules — `hRules=0 vRules=0`).
- **Page 2** (index 1) is a Helvetica lorem-ipsum body page with headings (Helvetica-Bold
  17-27pt), body paragraphs (Helvetica 10.7), Symbol bullets, and 10 detected h-rules.
  It **contains the user's earlier bad bake**: the first paragraph's middle lines are
  Helvetica-**Bold** 10.7 (the old wrong Match result, now baked page content).
- Bullets are already split correctly (Symbol markers are separate blocks — v2 WP-5 holds
  on this fixture). The current `inferredNearbyMatchFormat` on page 2's first paragraph
  ALREADY returns Helvetica@10.7 (correct): the dominant-cluster ranking fixed the Match
  substrate; page-2 work is mostly regression-pinning plus the detection fixes below.

## 1. Confirmed root causes (probe evidence inline)

### RC-1 — Header lines merge into one 4-line block (user failure #1, page 1) — P0
Probe: block `y=732 x=15 w=191 h=86 Monaco@12.7 lines=4` =
`SAMPLE PROJECT PROPOSAL / Prepared for: Demo Client / Date: January 2026 / …` merged.
All lines share font/size/color/left-x, are single-spaced, and the title has no terminal
punctuation → every guard in `shouldMergeWrappedLine` (`PDFTextAnalysisEngine.swift:~1100-1160`)
passes. The missing signal: **none of these lines comes close to filling its column** — a
line only word-wraps when its text reached the right margin. `lineLooksWrapped` (`:1164`)
only compares `next.maxX - previous.maxX` (shortfall ≤ 2×lineHeight), which trivially
passes when both lines are short.

Consequences chain: tapping "Demo Client" → whole 4-line block → editor opens a tall box
("editable block too large"), CoreText re-wraps 4 concatenated lines at editor width
("creates its own lines"), commit re-renders the whole header.

### RC-2 — Rule-less table cells merge vertically (page 1 table) — P0
Probe: `Phase DiscoveryBuild Build Review Launch` = one 5-line block (the Phase column's
stacked cells). No vector rules exist (`hRules=0`), so v2's rule-veto can't fire. Row
leading gap (~10pt at 12pt font ≈ 0.7×lineHeight) squeaks under the current
`verticalGap <= lineHeight * 0.9` ceiling (`:1142`). Same missing wrap-plausibility
signal as RC-1: 'Discovery' ends ~42pt short of its (narrow, neighbor-bounded) column
right edge — it never wrapped.

### RC-3 — Font-size scatter from the ink model (user failure #2) — P0
Probe: uniform 12pt Monaco detects as 12.0–14.9 (per-run: `SAMPLE PROJECT PROPOSAL`
@12.72, `Prepared for:` @12.07, `Date:` @11.99, `Owner Owner` @14.89).
**Instrumentation-verified: `validSizes` is EMPTY on every line of this fixture** —
Orifold's own CoreText-rendered exports carry no usable `FPDFText_GetFontSize` readings,
so `resolveLineFontSize` always falls to the ink estimate; a reported-size-trust rule
alone cannot fix this file. Two real mechanisms:
1. **Double-draw union inflation (the big outliers, 14.9/13.7):** this page contains
   faux-bold DOUBLE-DRAWN text (probe: literal `wwoorrkkssppaaccee`, `Owner Owner`,
   `DiscoveryBuild`); the offset duplicate glyphs inflate the line's UNION bounds height
   well past any single glyph's ink (union ≈ 11.3pt vs Monaco cap ink ≈ 9.3pt at 12pt),
   and est = union/ratio overshoots ~25%.
2. **Metric-vs-ink drift (the ±6% scatter):** extent-class ratios are derived from
   `NSFont` METRICS (capHeight 0.758em for Monaco), but real glyph ink differs per font
   (Monaco caps ink ≈ 0.80em) — metrics ≠ ink, the same class of error as v1/v2 size bugs,
   just smaller.
Downstream: scatter pollutes `fontsMatch` clustering, Match/Copy size fidelity, the
editor's initial `documentFontSize`, and detected-font dedup (Monaco appears as
12.1/12.3/12.7/14.9 variants).

### RC-4 — hitTest overlap tie-break (secondary) — P1
Probe: with the merged header block present, a point inside BOTH the 4-line union and the
overlapping single "Prepared by" line resolves by `smallestBlock` area alone
(`hitTest`, `:~220-246`). Fixing RC-1 removes the big unions, but harden anyway: among
tight hits, prefer a block one of whose LINES actually contains the point, then smallest.

### RC-5 — Page-2 Copy/Match — substrate already fixed; pin it — P0 (tests only + verify)
Probe: `P2-first: match=Helvetica@10.7` (correct; heading 17-27pt bold excluded, bullets
excluded, bad-bake Bold lines lose to the dominant regular cluster). Copy/Paste path is
v2-verified. Remaining risk: tapping one of the baked BOLD middle lines must still infer
regular body via dominant cluster (add explicit test); Paste must not alter text (existing
tests). If any of this fails during implementation, the fallback lever is RC-3's size fix
(reduces stray cluster keys) — no new ranking logic is planned.

### Prior deferrals re-confirmed still open (user items B–G)
- **A sanitize leak: ALREADY SHIPPED in v2** (`SanitizedExportLeakTests` green). Verify,
  don't re-implement.
- **B external-mod discard** — still open; design ready (v2 plan TODO): SHA-256 sidecar.
- **C Type3/Skia** — still open; dirty-tracking design ready (v2 WP-10).
- **D rotated bakers ×3** — still open; shared rotation-neutralize helper design ready.
- **E annotation-undo stale captures** — still open; `/OrifoldAnnID` design ready.
- **F style-only reconcile** — still open; bake-stamp design ready (pairs with B).
- **G cross-member pristine** — defer again (lowest value/risk ratio; v2 rebase behavior
  is consistent).

---

## 2. Work packages (execute in order)

### WP-A (P0) — Wrap-plausibility + leading-gap merge fixes (RC-1, RC-2)
File: `PDFTextAnalysisEngine.swift` (`shouldMergeWrappedLine`, `lineLooksWrapped`).

1. **Wrap-plausibility veto:** merging `previous`+`next` additionally requires that
   `previous`'s last line plausibly wrapped: its `maxX` reaches within
   `max(30, lineHeight * 2.5)` of the effective right edge
   (`min(previous.columnBounds?.maxX ?? pageRight, page right margin)`). A title,
   "Label: value" header line, or table cell ends far short of its column → never merges
   downward. Real wrapped prose ends within a word of the margin → unaffected.
   - Guard the guard: when `previous.columnBounds` is nil or degenerate (width ≤ 1.2×
     block width), fall back to requiring the SHORTFALL rule only (current behavior) so
     tightly-bounded single-cell columns (e.g. the Phase column, whose column IS the cell)
     don't accidentally satisfy "fills column" trivially — for those, rely on fix 2.
2. **Leading-gap ceiling:** `verticalGap <= lineHeight * 0.9` → `* 0.6`. Single-spaced
   prose leading gap ≈ 0.15–0.45×; table rows / chip stacks ≈ 0.7–1.0× (probe: Phase rows
   ≈ 0.7×). Kills RC-2 even where fix 1's column fallback applies.
3. Belt-and-braces role veto (cheap, last): don't merge when `previous` is ALL-CAPS
   (≥4 letters, no lowercase) and `next` is not ALL-CAPS — titles never wrap into
   mixed-case body. Regex-free check on the trimmed text.
4. **Regression watch (critical):** page 2's real paragraphs must STAY merged — probe
   shows `y=529 …lines=5` and `y=610 …lines=2` genuine wrapped paragraphs whose lines end
   near maxX≈540 of a ≈540 column → both new rules pass. Existing suites that pin
   paragraph merging: `PDFTextEditingRedesignTests`, `InlineEditStressFixtureAnalysisTests`,
   the v1 fixture tests (local), `MatchFormatInferenceTests`. Run after each change.

Acceptance (generated fixture §4.1 + local editedrun2):
- "Demo Client" tap → block is exactly the `Prepared for: Demo Client` line (1 line).
- "Date: January 2026" tap → 1-line block; no `SAMPLE PROJECT` in `block.text`.
- "OVERVIEW" separate from title and prepared-for.
- Phase-column cells are separate blocks (no "DiscoveryBuild" concatenation).
- Page-2 paragraphs still multi-line blocks.

### WP-B (P0) — Ink-model accuracy: union-inflation guard + measured ratios + unanimity (RC-3)
File: `PDFTextAnalysisEngine.swift` (`resolveLineFontSize`, `effectiveFontSize`,
`inkRatio`). Three sub-fixes, in order of impact ON THIS FIXTURE:

1. **Union-inflation guard (fixes the 14.9/13.7 outliers).** The line ink height fed to
   `effectiveFontSize` is currently the union `lineBounds.height`; double-drawn text
   inflates the union past any single glyph's ink. Clamp:
   `inkHeight = min(lineBounds.height, maxIndividualGlyphBoundsHeight + 1.0)` (the per-
   sample `bounds` are already in hand in `resolveLineFontSize`'s `samples`). A vertical
   double-draw offset then cannot inflate the estimate; ordinary lines are unaffected
   (their tallest glyph ≈ the union height by definition).
2. **Measured ink ratios (fixes the ±6% metric drift, benefits every font).** Replace the
   metric-derived extent ratios (`capHeight`/`xHeight`/`ascender` at
   `inkRatio(forFontName:lineText:)`) with EMPIRICALLY MEASURED ink: once per font (cached,
   same cache keying as today), render four calibration strings at 100pt into a tiny
   offscreen CoreText pass and measure actual ink extents — caps `"HODX"`, ascenders
   `"hlkd"`, x-height `"nouma"`, descenders `"pqgy"` — deriving exact per-class top/bottom
   ratios. Deterministic, ~4 CTLine image-bounds calls per font per process. Fall back to
   the current metric-derived ratios when the font can't be instantiated. Expect
   `testPDFTextAnalysisDetectsFontSizeAccuratelyAcrossCommonFonts`'s worst-case error to
   DROP (consider tightening its 8% tolerance after measuring; don't force it).
3. **Unanimity trust (for third-party PDFs with real reported sizes; inert on this
   fixture).** When `validSizes` has ≥ 4 samples and tight spread
   (`max-min ≤ max(0.2, median×0.02)`), trust the reported size unless it contradicts the
   ink estimate catastrophically (`reported > est×1.35 || reported < est/1.35`); the
   existing narrow band applies only to sparse/disagreeing readings. Calibration
   constraint that MUST stay green:
   `testPDFTextAnalysisUsesVisibleFontSizeForScaledContentStreams` (nominal 24 @ 0.5
   scale → est ≈ 12, unanimous reported 24 → 24 > 12×1.35 → rejected, ink wins ✓ — this
   test forbids naive "always trust reported"). Since generated fixtures carry NO reported
   sizes, unit-test the decision as a pure function: refactor the accept/reject choice
   into a static helper (`static func resolvedSize(reported:count:spread:inkEstimate:)`)
   and test it directly; end-to-end coverage comes from editedrun2-adjacent third-party
   files locally (skip-guarded).
Acceptance: page-1 Monaco runs resolve within 6% of 12.0 including `Owner Owner`;
`fontsMatch` clusters the header lines identically; detected-fonts menu shows ONE Monaco
entry; page-2 bullet-line strays (11.3/12.0) tighten toward 10.7; all existing size tests
green.

### WP-C (P0) — Editor no-reflow / size-fidelity pinning (user failure #2)
Files: tests only expected; `ReadingCanvas.swift` only if tests expose real gaps.

With WP-A (1-line blocks) + WP-B (correct size), the reflow/enlarge symptoms should
disappear — the editor already sizes from the block (`documentFontSize = block.fontSize`,
width from block bounds). Pin with tests rather than touching the editor:
- one-line header block → committed op has 1 line's worth of height
  (`editedBounds.height ≤ lineHeight × 1.6`) and font size within 6% of source.
- open → cancel: member bytes hash-identical (reuse v2 non-mutation pattern).
- open → Done-unchanged: no operation appended.
- commit "Demo Client" → "Demo Person" → rendered ink stays within the original line's
  y-band (pixel check: no ink in the band 1.5 lines below).
If the editor DOES still enlarge (e.g. `Self.editingFamilyName` fallback when a font is
missing), fix minimally in `InlineTextEditorOverlay.init`. Monaco exists on macOS →
`NSFont(name:"Monaco")` resolves; no substitution needed for this fixture.

### WP-D (P1) — hitTest line-containment tie-break (RC-4)
File: `PDFTextAnalysisEngine.swift` (`hitTest`).
Among `tightHits`, prefer candidates where ANY `line.bounds` (±tolerance) contains the
point; pick `smallestBlock` within that subset; fall back to current behavior when the
subset is empty. Pure refinement — cannot select something the old code wouldn't.

### WP-E (P1) — Detected-fonts polish + fixture coverage (user item 4)
Files: `ReadingCanvas.swift` (`detectedFontChoices`, `DetectedFontChoice`), L10n ×6.
v2 shipped the menu; add:
1. Monospace tag: `NSFont.isFixedPitch` → append a localized " · Mono" suffix
   (new key `readingCanvas.detectedFont.mono`).
2. Dedup hardening: WP-B collapses size variants; also round to 0.5pt for the dedup key
   so 10.65/10.7 don't double-list.
3. Tests (generated fixtures): monospaced header page surfaces
   `Detected: Monaco 12` (mono-tagged, not substituted); mixed-fonts page surfaces body
   Helvetica ~10 + bold + italic candidates; list stable/deduplicated (≤12, no
   same-family-same-size dupes); selecting the Monaco candidate applies family+size and
   `editorFontTraits` has no bold/italic.

### WP-F (P0) — External-modification preservation + bake-stamp (user items B + F)
Files: `WorkspaceDocument.swift`, `WorkspaceViewModel.swift`, new
`Orifold/Engine/WorkspaceFingerprintStore.swift`, tests.
Implement the v2-deferred design verbatim (see `docs/EDITING_HARDENING_V2_PLAN.md`
status banner for the full TODO):
1. **Bake-stamp first (low risk, additive):** on successful `regenerateEditedPage`,
   attach invisible annotation `/OrifoldBakeStamp = SHA256(canonical ops encoding)` to the
   regenerated page. `reconcileCommittedEditsWithLoadedPages` checks the stamp FIRST
   (missing/mismatch + ops present → regenerate; match → skip); the v1 text-presence check
   stays as the legacy fallback. Fixes style-only stale bakes (F). Ensure the stamp
   annotation is stripped by `dataStrippedOfOrifoldMetadata` (sanitize) and ignored by
   annotation UIs (filter it wherever `/OrifoldWorkspaceComments` is filtered).
2. **Fingerprint sidecar (B):** at `fileWrapper` save, after final bytes exist:
   `store[workspace.id] = SHA256(finalData)` in
   `~/Library/Application Support/Orifold/workspace-fingerprints.json` (LRU ≤ 200
   entries). At load's metadata-restore branch (`importPDFDocument`): fingerprint exists
   and mismatches → **external modification**: import the FLAT file fresh (visible content
   wins), keep comments only, drop `editableWorkspace`/ops/pristine, surface a one-line
   notice (L10n ×6: `notice.externalModification.detected`). No fingerprint → current
   behavior (legacy/other-machine). Match → current behavior.
3. Tests: save→qpdf/PDFKit-tamper→reopen keeps tamper (ops dropped, notice fired);
   save→reopen untouched keeps ops; legacy no-fingerprint file keeps ops; trapped-state
   reconciliation tests stay green; sanitized output contains no `OrifoldBakeStamp`.
   Store path injectable (env var or init param) so tests don't touch the real
   Application Support directory.

### WP-G (P3) — Rotated bakers (user item D; 3 confirmed bugs from the flow audit)
Files: new `Orifold/Engine/RotationNeutralizedPageDrawing.swift`,
`PDFDecorationExportBaker.swift`, `PDFFormSupport.swift`,
`Signing/Appearance/SignatureAppearanceRenderer.swift`.
Extract the proven recipe from `PDFEditedPageRenderer.regeneratedPage` (`:~19-68`): draw a
rotation-zeroed copy into a raw-mediaBox context; re-tag output with original `/Rotate` +
all boxes. Apply to all three bakers (`pageInfo` variants at `PDFDecorationExportBaker:253`,
`PDFFormSupport:202`, `SignatureAppearanceRenderer:376`; `drawPlacement` then needs no
extra transform — placement rects are already raw-space). Tests: 90°/270° generated pages,
pixel/aspect assertions (never text extraction); existing rotated-edit + signature suites
must stay green. **This is the riskiest package (visual-signature save path) — land it as
its own commit, full suite after, and drop it (defer) if anything ambiguous surfaces.**

### WP-H (P3) — Annotation-undo stable handles (user item E)
Files: `WorkspaceViewModel.swift` (~8 closure sites), `ReadingCanvas.swift` (note editor),
tests. Implement the v2 TODO: stamp `/OrifoldAnnID = UUID` at creation; undo/redo closures
capture `(pageRefID, annID, lightweight snapshot {type,bounds,color,contents,inkPaths})`
and resolve the live page+annotation at execution time (`memberPDF(for:)` + localIndex +
annID scan); removal by annID; re-add by reconstruction — never re-parent a captured
object; every closure re-registers its inverse (fixes the dead-redo family too). If
resolution fails → status message, not silent no-op. Test: annotate → commit text edit
(member reload) → undo removes from LIVE page → redo re-adds; repeat across
snapshot-restore.

### WP-I (P3) — Type3/Skia dirty-tracking (user item C)
File: `WorkspaceViewModel.swift`. v2 TODO verbatim: `annotationDirtyMemberIDs: Set<UUID>`
set by every live-annotation mutation; `currentPDFDataForExport`/`currentPDFData` return
`document.memberPDFData[id]` verbatim for clean members instead of
`PDFSerializer.data(from:)`; clear flag when bytes are re-serialized+stored. Test: import
normalizer fixture (or CI-skip): unedited/unannotated member bytes byte-identical across
save. Residual (document): edited or annotated members still pay the PDFKit rewrite.

### Explicit deferral
- **Cross-member pristine lockstep (user item G):** defer again, same TODO as v2. The
  rebase-to-baked behavior is consistent; the fix requires pristine-PDF surgery + a
  scoped OrderSnapshot extension — poor risk/reward while P0s exist.

---

## 3. Priorities → packages

- **P0:** WP-A, WP-B, WP-C, WP-F, RC-5 pinning tests (+ verify sanitize A is green)
- **P1:** WP-D, WP-E
- **P3:** WP-G, WP-H, WP-I (each its own commit; each individually droppable)
- **Deferred:** cross-member pristine (G)

## 4. Fixtures

### 4.1 Generated (CI-safe) — extend `EditingFixturePDFBuilder`
- `monospacedHeaderPage()`: Monaco 12 — `SAMPLE PROJECT PROPOSAL` / `Prepared for: Demo
  Client` / `Date: January 2026` / blank gap / `OVERVIEW` / a 2-line wrapped Monaco
  paragraph (control: MUST still merge) / a rule-less 3×3 text grid (Phase/Duration/Owner
  columns at x≈40/160/275, row pitch ≈ 1.9em).
- `unanimousReportedSizePage()` (only if CoreText-rendered fixtures carry PDFium-readable
  reported sizes — verify with a probe first; if reported comes back nil, WP-B's unanimity
  path is testable only via editedrun2 locally + unit-test the decision function directly
  by refactoring it into a pure static helper).
- Reuse `mixedFonts()` for detected-font and Match assertions.

### 4.2 Local regression (skip-guarded absolute path, established pattern)
`EditedRun2RegressionTests`: the §2 acceptance list run against the real file — header
line isolation, table cell isolation, page-2 paragraph integrity + Match/Copy/Paste, size
fidelity, cancel no-op, detected Monaco candidate. Every test
`throw XCTSkip` when the file is absent.

## 5. Test matrix (new)

| Test file | Pins |
|---|---|
| `HeaderLineSegmentationTests` | WP-A acceptance on generated fixture: 4 header lines separate; ALL-CAPS veto; table cells separate; control paragraph still merges |
| `FontSizeUnanimityTests` | WP-B decision helper unit tests (unanimous-trust, catastrophic-reject, sparse→band) + Monaco end-to-end via local fixture skip-guard |
| `EditorNoReflowTests` | WP-C: 1-line stays 1-line, size within 6%, cancel hash-identical, Done-unchanged no-op |
| `EditedRun2RegressionTests` | §4.2 list (local-only) |
| `DetectedFontMonoTests` | WP-E: mono tag, dedup, selection traits |
| `ExternalModificationReopenTests` | WP-F.2 matrix |
| `StyleOnlyReconciliationTests` | WP-F.1 bake-stamp |
| `RotatedBakerTests` | WP-G pixel/aspect on 90/270 |
| `AnnotationUndoAfterReloadTests` | WP-H |
| extend `PDFImportNormalizerTests` | WP-I byte-identity |

Validation style rules (unchanged from v2, they bit us twice): PDFium reading-order or
pixel checks — never PDFKit `.string`/`.attributedString` token checks on edited pages;
re-fetch pages after commits; whitespace-collapse text compares; subsequence tolerance for
overlapping-run pages.

## 6. Risk register

| Package | Risk | Mitigation |
|---|---|---|
| WP-A | under-merging real prose (ragged-right, centered 2-line headings) | 2.5×lineHeight margin tolerance; column-degenerate fallback; full v1/v2 merge suites after each sub-change; control paragraph in the generated fixture |
| WP-B.1 | clamping a legitimately tall union (inline math/oversized glyph) | clamp is to the tallest GLYPH, not a constant — a genuinely tall glyph keeps its height |
| WP-B.2 | measured ratios shifting every size test by a few % | run the full size-test suite immediately; ratios are strictly more accurate, adjust only test tolerances that were compensating for metric error (document each) |
| WP-B.3 | regressing the scaled-content ink-wins case | the 1.35× catastrophic band is calibrated to that exact test; keep it green before/after |
| WP-F.2 | wrongly dropping ops (false external-mod) | hash only ever set from OUR final bytes; mismatch requires the file to actually differ; untouched-roundtrip test |
| WP-F.2 | fingerprint store pollution in tests | injectable store path |
| WP-G | signature save path visual regression | own commit, pixel tests, full suite, drop-if-ambiguous |
| WP-H | 8 call sites behavioral change | one shared helper, per-site test, own commit |
| WP-I | export byte-reuse staleness | reuse ONLY when member neither annotated nor edited since last serialize; conservative flag-set on every mutation site found by grep `addAnnotation\(|removeAnnotation\(` |

## 7. Executor gotchas (hard-won, repo-specific)

1. **Regenerate the Xcode project** (`xcodegen`) whenever adding Swift files — SPM globs
   but CI's Xcode-build step uses the committed pbxproj (this exact miss turned CI red in
   v2; fixed in `8180b82`).
2. CI Xcode 16.4 PDFKit extraction quirk (§5 rules).
3. L10n: every new UI string ×6 languages or `LocalizationCoverageTests` fails; edit
   `Localizable.xcstrings` via the JSON-script pattern.
4. Codable evolution: new persisted fields = `decodeIfPresent` + default.
5. Shared repo: `git fetch` before push; expect xcstrings conflicts; delete stray
  `* 2.swift` Finder copies (they break SPM).
6. swiftlint: keep new files clean; don't grow per-file counts in touched files.
7. Renderer CGContext work: `saveGState/restoreGState` + reset text mode `.fill`.
8. Keep chat replies terse (user preference); full effort in code/tests.

## 8. Verification loops (two, both green, before merge)

**Loop 1 — focused:** all §5 files + the standing editing suites
(`PageGraphicsIndexTests`, `TableEditPreservationTests`, `TextDeletionLifecycleTests`,
`SanitizedExportLeakTests`, `StyleFidelityMatchTests`, `BulletAndOverlayTests`,
`InspectorTextEditRowTests`, `MatchFormatInferenceTests`, `InlineEditorFormatUXTests`,
`InlineEditReconciliationTests`, `StructuralOpsEditConsistencyTests`,
`InlineTextEditPlacementTests`, `PDFTextEditingRedesignTests`,
`InlineEditStressFixtureAnalysisTests`) + local fixture suites when present. Fix all,
rerun touched.

**Loop 2 — full safety:** sync with `main`; clean `swift build`; **`xcodebuild build`
(CI parity — see gotcha 1)**; full `swift test`; swiftlint per-file delta; changed-file
sweep (broad rewrites, debug logs, probes, absolute paths outside skip-guards,
force-unwraps, silent catches, misleading delete/redaction copy, PDFKit round-trips,
L10n gaps, missing `decodeIfPresent`). Fix → rerun full suite + touched tests.

## 9. Merge + post-merge

Merge only after both loops green + branch synced + no stray fixtures/probes. Ff-merge to
`main`, push, then on `main`: build, full suite, and the highest-risk set — editedrun2
page-1 header tests (local), page-2 style tests, deletion lifecycle, underline reset,
table rules, detected fonts, sanitize scan, external-mod reopen, export/reopen. **Watch
the CI run to completion** (v2 needed two CI-only fixes: PDFium-vs-PDFKit extraction in
tests, stale pbxproj). Test-only CI failure → fix forward; product failure → revert.

## 10. Final report checklist

1 final SHA · 2 branch · 3 files changed · 4 root causes confirmed (vs §1 — note
deviations) · 5 fixes per WP · 6 tests added/updated · 7 editedrun2 p1 results ·
8 editedrun2 p2 results · 9 Loop 1 · 10 Loop 2 · 11 post-merge incl. CI run id ·
12 risks reduced · 13 deferred (cross-member pristine; any dropped P3) · 14 remaining
limitations (visual-only delete; substituted fonts; letter-spacing; per-machine
fingerprint) · 15 merged+pushed confirmation. Do not overclaim.
