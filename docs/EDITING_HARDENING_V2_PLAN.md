# Editing Hardening V2 — Implementation Plan

> **IMPLEMENTATION STATUS (2026-07-07, shipped):** WP-0,1,2,3,4,5,6,7,8 IMPLEMENTED,
> tested, two green verification loops (547 tests, 0 failures). **Deferred with precise
> TODOs below:** WP-9 (bake-stamp + external-mod fingerprint), WP-11 (rotated
> decoration/form/signature bakers), WP-12 (annotation-undo stable handles), WP-13
> (cross-member pristine lockstep). These four are the higher-risk items that touch the
> save/reconcile/signature paths; deferred to keep this pass's merge safe. WP-13 was
> always flagged first-to-defer.
>
> **Deferred-item TODOs (least-risk designs, ready to pick up):**
> - **WP-9 external-mod discard (P1, user-flagged data safety):** at save, write
>   `SHA256(finalBytes)` keyed by `workspace.id` to a local sidecar
>   (`~/Library/Application Support/Orifold/workspace-fingerprints.json`, LRU-capped). At
>   load's metadata-restore branch (`WorkspaceDocument.importPDFDocument`), if a fingerprint
>   exists and the file hash differs → import the FLAT file fresh (external content wins),
>   keep only comments, drop `editableWorkspace`/ops/pristine, show a one-line notice. No
>   fingerprint (other machine / legacy) → keep current behavior. Same hash → current.
>   Risk: sidecar is per-machine (documented). Bake-stamp half (`/OrifoldBakeStamp` =
>   SHA256 of a page's ops, checked first in `reconcileCommittedEditsWithLoadedPages`) makes
>   style-only stale bakes detectable — additive, low risk, do this half first.
> - **WP-11 rotated bakers (P4, 3 confirmed bugs):** extract the proven recipe from
>   `PDFEditedPageRenderer.regeneratedPage` (lines ~19-68: draw a rotation-zeroed page copy
>   into a raw-mediaBox context, re-tag the output page with the original `/Rotate`) into a
>   shared helper; apply to `PDFDecorationExportBaker.bake`, `PDFFormSupport.flattenedData`,
>   `SignatureAppearanceRenderer` (which then needs no per-placement transform). Fixes
>   background clipping/distortion on 90°/270° pages. NOTE residual: decoration *position*
>   on rotated pages (page-number at raw-bottom → visual-left) is a separate follow-up.
>   Higher risk because the signature baker runs on the visual-signature save path.
> - **WP-12 annotation-undo stale capture (P4):** stamp `/OrifoldAnnID = UUID` on each
>   Orifold-made annotation; rewrite the ~8 undo closures to capture
>   `(pageRefID, annID, lightweight snapshot)` and resolve the live page+annotation at undo
>   time (never retain a `PDFPage`/annotation object). Also re-register the inverse to fix
>   the dead-redo family.
> - **WP-13 cross-member pristine lockstep (P4, first-to-defer):** physically move the
>   pristine page between `originalMemberPDFData` blobs on cross-member `movePage`; snapshot
>   the two touched pristine blobs in OrderSnapshot. Current rebase-to-baked behavior is
>   already consistent, just loses the true pristine for the moved page.

**Status:** Planning doc; core packages now implemented (see status banner). Written 2026-07-07 for execution by Opus.
**Baseline:** `main` @ `3292399` (post editing-hardening-v1: ops↔bytes reconciliation, pristine-base persistence, char-aware font sizing, Match-infers-body-style, editor-isolated undo — see `memory/editing-experience-hardening-2026-07-07.md`).
**Branch:** create `edit-hardening-v2/<slug>` off latest `main`. Commit in the work-package units below. Merge only after the two verification loops in §9 pass, then run §10 post-merge validation.

Line numbers below were verified against `3292399`. They will drift — anchor by symbol name.

---

## 0. Scope discipline

- No broad rewrites. Every fix below is a targeted patch into the existing architecture (which is working: commit → regenerate-from-pristine → reconcile-on-load/export is the settled model — do not redesign it).
- The ONE new architectural piece is the `PageGraphicsIndex` (§2). It is additive (a second pass over PDFium page objects the engine already opens) and powers P0-B, P0-C, P1-A, and P2-D simultaneously. Build it once, first.
- Known adjacent bugs that are explicitly **NOT in this pass** (from the 5-round audit, already reported to the user; do not scope-creep into them): ink-stroke wrong-page targeting, crypto re-sign ByteRange corruption, signature-invalidation warnings for structural ops, duplicatePages not cloning signatures/decorations/comments, exportPages dropping bakers, form radio-group field counting, locked-PDF File>Open path, HTML sync/async renderer split, owner-password permission enforcement, Delete-key removing Widget/Link annotations. Leave them alone unless a P0 fix requires touching the same lines.

---

## 1. Confirmed root causes (audit results)

All verified by direct code read at `3292399`.

### F — Delete text does not delete (P0, verified, one-line root cause)
`ReadingCanvas.swift:4182` in `shouldCancelWithoutCommit`:
```swift
let trimmed = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
if trimmed.isEmpty { return true }   // ← empty text == CANCEL
```
Emptying a block and pressing Done is silently treated as Cancel — the app "keeps restoring" the text. Both `commitButton()` (~4030) and `finishForHandoff()` (~4054) consult this. Everything downstream already supports an empty replacement:
- `PDFEditedPageRenderer`: erase patch is drawn from `sourceLineBounds` regardless; `ReplacementTextLayout.draw` guards `attributedString.length > 0` → draws nothing. Verify `measuredBounds` doesn't produce a degenerate box for empty text (unwrapped size = .zero → falls back to `editedBounds` width; add a guard if needed).
- Rich export loops (`WorkspaceViewModel.swift:5249`, `:5359`) iterate `where !edit.replacementText.isEmpty || !edit.sourceText.isEmpty` → a deletion (empty replacement, non-empty source) is already included.
- The trash button in the editor toolbar (`ReadingCanvas.swift:2993`, `revertButton` at `:4204`) is **revert-this-edit**, only shown for `isExistingEdit`. There is no "delete this text" affordance at all.

### C — Opening the editor destroys underline (P0, three stacked causes)
1. **Underline is never detected.** `grep -c underline PDFTextAnalysisEngine.swift` → **0**. PDF underlines are vector path objects (thin rects/lines under the baseline), not text attributes; the engine only reads glyphs. So every `EditableTextBlock.underline` is `false` for real PDFs.
2. **Any commit erases the underline stroke and redraws without it.** The erase patch covers `sourceLineBounds.insetBy(-1)` (which usually includes the underline stroke, or worse, half of it), and the replacement is drawn from `op.underline == false`. The renderer DOES support underline (`kCTUnderlineStyleAttributeName` in `ReplacementTextLayout`) — it just never receives `true`.
3. **Opening can silently arm a commit.** `InlineTextEditorOverlay.init` calls `applyArmedFormatPainterIfNeeded()` (`ReadingCanvas.swift:2590`) which sets `didChangeStyle = true` — so with a pinned/armed Format Painter, merely opening + Done (or click-away handoff) commits a restyle the user never asked for on THIS block.
4. Perception component: while the editor is open, `patchView` covers the original ink (including the underline). That part is non-mutating (Cancel restores), but combined with (2) the user experience is "opening removed my underline and Reset can't bring it back" — Reset re-applies `sourceFormat`, whose `underline` is false per (1).

### B — Table editing merges headings and covers rules (P0, two causes + one v1 regression suspect)
1. **Merge heuristics are graphics-blind.** `shouldMergeWrappedLine` (~`PDFTextAnalysisEngine.swift:1030-1060`) merges vertically adjacent lines with compatible fonts; nothing stops a merge across a horizontal table rule, so a heading directly above a cell (same font size after v1's char-aware sizing) can merge into the editable block.
2. **v1 regression suspect:** the column-split `gapThreshold` was raised from `1.5×` to `2.2×` median ink height (`PDFTextAnalysisEngine.swift:660`) to stop justified-prose shattering. Narrow table gutters (< ~1.2em) that previously split cells may now MERGE adjacent cells/headers. Rule-aware splitting (below) must restore cell separation without re-shattering prose.
3. **Erase patch covers rules.** `drawErasePatch` paints `sourceLineBounds.insetBy(dx:-1,dy:-1)` as an opaque rect — in a table cell this overlaps the vertical rules abutting the text, wiping them from the regenerated page.

### D — Bullet misalignment (P2, cause identified)
`shouldMergeWrappedLine` deliberately merges a standalone list-marker line into the following text (`:1043` `isLikelyStandaloneListMarker`), and inline markers pass `isLikelyListItemStart` (`:1221-1226`). Once the marker glyph is inside the block, the replacement re-layout (CoreText, plain paragraph) loses the hanging indent: the bullet re-renders as the first character at the paragraph x-origin — visually "bullet moved / too close / became part of the text". Nothing models a marker as a separate non-edited region.

### A — Style fidelity + no detected-fonts menu (P1)
- Detected **colors** already work: `TextColorChoice` with `isDetected`, harvested per block/document (`ReadingCanvas.swift:2504-2516`, `textColorChoices(for:document:)` at `:2579`, cap 24). There is **no analog for fonts**: `fontFamilyMenuItems(originalFamily:)` (`:3975`) is a static family list seeded only with the clicked block's family.
- Subset-tag stripping ALREADY exists and is correct (`resolveFontPostScriptName`, `PDFTextAnalysisEngine.swift:336-370`: strips `ABCDEF+`, promotes weight/italic to a matching installed face, falls back to a stable sans). The detected-fonts menu builds directly on this.
- `sourceFormat`/`PDFTextEditFormat` carries no underline (see C-1), no line-spacing (per-op `originalLinePitch` exists only inside the renderer), no letter/word spacing. Copy/Paste/Match fidelity is capped by what the format struct carries.
- Match Format (v1's `inferredNearbyMatchFormat`, `WorkspaceViewModel.swift` near `editableTextBlock`) excludes headings by size-cluster but has no notion of "inside a table grid" or "is a bullet marker" — table cells and markers can still win as the nearest same-column candidate.

### E — Opaque white backing while dragging (P2)
`patchView` (`ReadingCanvas.swift:2423`, configured `:2680-2689`) is filled with `livePatchColor` (sampled page background — usually opaque white) whenever the block is not an insertion, at full alpha, for the entire editing session including drag/resize. Nothing dims it during interaction, so the user can't see surrounding layout to align.

### G — Inspector Text Edits rows (P3)
`InspectorTextEditsSection` / row view (`InspectorView.swift:1228-1310`) renders `InlineTextEditListItem` (id, pageRefID, pageNumber, memberName, originalText, replacementText, isInsertion — `WorkspaceViewModel.swift` ~2860). No text truncation/wrapping discipline (long strings push past the panel margin), no edit-kind labels, no ordering/timestamps (ops DO carry `createdAt`/`modifiedAt`), no baked/pending status.

### Deferred-item audits (from prior passes, re-verified)
1. **Sanitize leak (CONFIRMED):** `QPDFService.sanitized` (`QPDFService.swift:98-118`) removes `/OpenAction`, `/AA`, `/Names/JavaScript`, `/Names/EmbeddedFiles`, and (with `removingMetadata`) trailer `/Info` + root `/Metadata`. It never touches **annotations**, so the invisible FreeText annotation carrying `/OrifoldWorkspaceComments` (the full workspace JSON: comments, source payloads, editable workspace + member bytes) survives sanitized export. `Self.sanitized` runs AFTER `exportedPDFDataThrowing` embedded it (`WorkspaceViewModel.swift:4427`).
2. **Third-party edits discarded (CONFIRMED, v1 known risk):** `WorkspaceDocument.importPDFDocument` metadata path restores `editableWorkspace` + `editableMemberPDFData` unconditionally — the flat file's actual (possibly externally edited) pages are never consulted.
3. **Type3/Skia (CONFIRMED mechanism):** `currentPDFDataForExport` (`WorkspaceViewModel.swift:~1363`) re-serializes EVERY member via `PDFSerializer.data(from:)` (PDFKit rewrite) on every save to capture live annotations — destroying the qpdf-preserved text layer even for members with zero annotations and zero edits.
4. **Rotated bakers (CONFIRMED ×3):** `PDFDecorationExportBaker.bake` (`:62`), `PDFFormSupport.flattenedData` (`:97`), and `SignatureAppearanceRenderer` (`pageInfo` `:376` drops `/Rotate`; `drawPlacement` `:367` draws `placement.rect` with no rotation transform) all use the raw-mediaBox anti-pattern that `PDFEditedPageRenderer.swift:19-33` documents and solves.
5. **Annotation undo stale captures (CONFIRMED, ~8 sites):** `applyHighlight`, `addNote`, `addTextBox`, `addInkStroke`, `deleteSelectedAnnotation`, `eraseMarkupAnnotation`, `placeSignature`, `removeNoteComment` capture live `PDFPage`/`PDFAnnotation` objects; every `regenerateEditedPage`/snapshot-restore/OCR replaces the member `PDFDocument`, making later undo/redo a silent no-op. Several also never re-register inside the undo closure → redo dead.
6. **Style-only reconciliation gap (CONFIRMED by design):** v1's `reconcileCommittedEditsWithLoadedPages` is text-presence-based; a style-only op with unchanged text is undetectable.
7. **Cross-member pristine (v1 trade-off):** `movePage(after:)` rebases both members' pristine to their *baked* live bytes — consistent but the moved page loses its true pristine.

---

## 2. New shared primitive: `PageGraphicsIndex`

**File:** `Orifold/Engine/PageGraphicsIndex.swift` (new) + small extension hooks in `PDFTextAnalysisEngine`.

The PDFium page-object API is **already declared and linked** (`FPDFPage_CountObjects`, `FPDFPage_GetObject`, `FPDFPageObj_GetType`, `FPDFPageObj_GetBounds` at `PDFTextAnalysisEngine.swift:88-105`; the binary exports the full object API per `docs/OBJECT_EDITING_PLAN.md`). Add one pass during `analyzeWithPDFium` that enumerates PATH objects (type 2) and classifies, in raw page space:

```swift
struct PageGraphicsIndex: Codable, Equatable {
    struct RuleLine: Codable, Equatable {
        var bounds: CGRect      // thin: min(w,h) <= ~2.5pt
        var isHorizontal: Bool  // width >= 4× height
    }
    var horizontalRules: [RuleLine]  // table rules, underlines, separators
    var verticalRules: [RuleLine]
    // Optional later: filled rects (cell shading) — not needed for this pass.
}
```

Classification: a PATH object whose bounds are "thin" (short side ≤ ~2.5pt, long side ≥ ~6pt). No path-segment introspection needed — bounds are enough for rules/underlines. Cap the scan (e.g. first 4,000 objects) so pathological vector art can't stall analysis; log when capped.

Store it on `PDFTextPageAnalysis` (add `var graphics: PageGraphicsIndex = .init(...)` with a Codable-default so the analysis cache and any persisted uses stay compatible).

Consumers:
- **Underline detection (C):** a horizontal rule whose x-range overlaps a run's bounds ≥ 60% and whose y sits in `[baseline − 0.25×fontSize, baseline + 0.06×fontSize]` → `run.underline = true`, propagate to line/block and into `PDFTextEditFormat`. Also record the matched rule's rect on the block (new field `underlineRules: [CGRect]` or fold into lines) so the erase patch can be extended to cover the WHOLE stroke (no half-erased underlines).
- **Merge separators (B):** `shouldMergeWrappedLine` must refuse to merge two lines when a horizontal rule lies strictly between their y-bands and spans ≥ 50% of their union x-range. Exempt rules already classified as underlines of the upper line.
- **Cell-aware column splitting (B):** in `splitIntoColumns`, if a vertical rule falls inside an inter-glyph gap, split there regardless of `gapThreshold`. This restores narrow-gutter table splitting without re-lowering the 2.2× prose threshold.
- **Erase-patch clipping (B):** see §3-B.
- **Match exclusion (A):** a candidate block whose bounds intersect ≥ 2 vertical rules (i.e. sits inside a ruled grid) is excluded from body-style inference when the target is outside any grid.

Testing: generated fixtures draw rules with CGContext strokes — PDFium reports them as path objects. Unit-test the classifier directly on a synthetic page.

Risk: PDFium object enumeration on the pristine bytes is already done per page for text; one more pass is cheap. The silgen declarations for any additional needed calls follow the existing pattern. **This package lands first; everything in P0-B/C depends on it.**

---

## 3. Work packages

Execute in this order. Each package = one or more commits with its tests.

### WP-0 — `PageGraphicsIndex` (§2). Prereq for WP-1/2/4.

### WP-1 (P0) — Non-destructive editor lifecycle + underline survival (failure C)

Files: `PDFTextAnalysisEngine.swift`, `PDFTextEditingModels.swift`, `ReadingCanvas.swift`, `PDFEditedPageRenderer.swift`, `WorkspaceViewModel.swift`.

1. Underline detection per §2 → `EditableTextBlock.underline` / `PDFTextRun.underline` real values; `PDFTextEditFormat(block:)` already copies `underline` ✓.
2. Erase geometry: when a line has a detected underline rule, extend that line's erase rect to include the rule's full bounds (+0.5pt) so commits never leave half a stroke. Store the rule rects on the op (extend `sourceLineBounds` or add `sourceUnderlineRules: [CGRect]` with `decodeIfPresent` default for old workspaces).
3. Replacement drawing already honors `op.underline` → verify thickness/offset looks sane vs original (CoreText default is acceptable; do NOT try to replicate exact stroke width this pass).
4. **Kill the open-time mutation:** `applyArmedFormatPainterIfNeeded()` must not set `didChangeStyle` unless the applied style actually differs (reuse v1's `styleActuallyChanged` logic in `apply(format:...)` — verify it's on this path), AND auto-apply-on-open should mark the session so that Done-with-no-text-change and painter-style == block-style commits nothing.
5. **Cancel/open invariants:** add assertions/tests that opening + Cancel and opening + Done-unchanged leave `pageEditStates`, `memberPDFData`, and the rendered page bit-identical (hash the member bytes before/after).
6. **Reset semantics for committed edits (exactness):** in-editor Reset today re-applies `sourceFormat` (analysis approximation — cannot restore what detection can't see). Change Reset for `isExistingEdit` sessions to route through `revertInlineTextEdit` (pixel-perfect: regenerate from pristine with the op removed) and then reopen the editor on the freshly re-detected original block. Keep current behavior for never-committed sessions (restore session-start state). Update the Reset tooltip copy accordingly (L10n, 6 languages).

### WP-2 (P0) — Table-safe editing (failure B)

Files: `PDFTextAnalysisEngine.swift`, `PDFEditedPageRenderer.swift`, tests.

1. Rule-aware merge veto + rule-aware column split (§2 consumers).
2. **Erase-patch minimization:** change `drawErasePatch` input from raw line bounds to per-line **glyph-ink bounds** (union of glyph boxes, which the engine already has) padded ~1pt — not the padded line box. Then **clip against rules**: subtract from each patch any intersection with a detected rule rect expanded by 0.35pt (draw the patch as a path with even-odd holes, or split the rect into up to 4 sub-rects around the rule). Keep the old full-rect behavior when the page has no `PageGraphicsIndex` rules (fallback = current behavior; zero risk to non-table PDFs).
3. Manual/matched-geometry destination erases (`didApplyMatchedGeometry` path) keep current behavior — only the source-line patches get rule-clipping.
4. Guard: if rule-clipping would leave original glyph ink exposed (rule passes THROUGH the text ink, rare), prefer covering text over preserving the rule — correctness of the edit wins.

### WP-3 (P0) — Deletion as a first-class commit (failure F)

Files: `ReadingCanvas.swift`, `WorkspaceViewModel.swift`, `PDFEditedPageRenderer.swift`, `InspectorView.swift`, L10n.

1. `shouldCancelWithoutCommit`: empty text is a cancel **only for insertions and unchanged-empty sources**. For a block with non-empty `originalText`, empty text = **deletion commit**:
   - remove the `if trimmed.isEmpty { return true }` early-out; replace with `if trimmed.isEmpty { return block-was-also-empty-and-nothing-else-changed }`.
2. `applyInlineTextEdit` accepts empty `replacementText` for non-insertion blocks (audit for hidden guards); the op with empty replacement = erase-only bake. Verify `measuredBounds` handles empty layout (keep `editedBounds`, no growth) and `reconcileCommittedEditsWithLoadedPages` treats empty-replacement ops correctly (its text-presence check skips `replacement.isEmpty` — fine; the op still reconciles via the WP-9 bake-stamp if implemented, otherwise document).
3. **Explicit Delete affordance:** add a "Delete text" action in the editor toolbar (and/or Cmd+Delete): sets text empty + commits immediately. Keep the existing trash = "Remove edit (revert)" for committed edits but retitle for clarity: trash icon tooltip "Revert this edit"; new delete icon (e.g. `text.badge.minus`) "Delete text". L10n ×6.
4. Undo/redo: deletion is a normal op → v1's snapshot undo already covers it; add the test anyway.
5. **Honesty:** deletion is visual (original text remains in the content stream under the patch — same as all edits, per the existing one-time disclosure `textEditPrivacyNotice`). Name everything "Delete text (visual)"-honest in code and DO NOT add any "redact" wording. Extend the existing privacy-notice string to mention deletion if it doesn't already. True redaction stays out of scope (documented deferral — qpdf content-stream surgery, see `docs/OBJECT_EDITING_PLAN.md` for the eventual path).
6. Inspector: deletion rows show "Deleted" badge (WP-7).

### WP-4 (P1) — Style fidelity: detected fonts, richer format, better Match (failure A)

Files: `PDFTextAnalysisEngine.swift`, `PDFTextEditingModels.swift`, `ReadingCanvas.swift`, `WorkspaceViewModel.swift`, L10n.

1. **DetectedFontChoice model** (mirror of `TextColorChoice`): harvest per-page (and clicked-block-first) clusters `(resolvedPostScriptName, family, size, bold, italic, inkShare)` from analysis blocks; expose top N (cap ~12) as menu entries:
   - `Detected: Helvetica 10.2`
   - `Detected: Helvetica Bold 13`
   - `Detected: Times Italic 11 (substituted)` — "(substituted)" suffix when `NSFont(name:)` resolved via fallback rather than the exact face.
   - Selecting one applies family + traits + size in one step (unlike the family-only popup today). Keep the existing family popup beneath a separator.
2. **Format payload upgrades** (all optional/Codable-defaulted for old workspaces):
   - `PDFTextEditFormat.lineHeight: CGFloat?` — captured from the block's measured line pitch (reuse the renderer's `originalLinePitch` logic at analysis time); Paste/Match apply it via the existing `CTParagraphStyle` min/max line height path.
   - underline now real (WP-1).
   - Explicitly OUT: letter/word spacing, horizontal scale (PDFium per-char spacing exists but replicating in CoreText is a rabbit hole — document as limitation).
3. **Copy Format** captures the live editor style INCLUDING underline + lineHeight. **Paste** applies style-only (geometry exclusion from v1 stands).
4. **Match Format** ranking upgrades in `inferredNearbyMatchFormat`:
   - exclude blocks inside ruled grids when target is outside (via `PageGraphicsIndex`),
   - exclude standalone list markers and blocks whose text is a bare marker,
   - exclude blocks with ≥1.5× or ≤0.6× the candidate-pool median size *even when the pool is small* (hardens the existing 25% band),
   - prefer candidates sharing the target's font family when the target is a committed re-edit.
5. Keep expectations honest in UI copy: detected entries are "closest available face", not embedded-font reuse.

### WP-5 (P2) — Bullet/list marker stability (failure D)

Files: `PDFTextAnalysisEngine.swift`, `PDFTextEditingModels.swift`, `ReadingCanvas.swift`, `PDFEditedPageRenderer.swift`.

1. During block assembly, when a line starts with a standalone marker run (existing `isLikelyStandaloneListMarker` / leading `isLikelyListItemStart` glyph group followed by a gap ≥ 0.5em), record on the block: `listMarker: { text, bounds, gapToText }` and set the block's editable text/bounds to START AT THE TEXT, excluding the marker.
2. Editor: marker is not in the textView; `patchView`/erase never cover the marker bounds; the committed op's `sourceBounds`/`editedBounds` anchor at the text x (bullet untouched → cannot move).
3. Multi-line bullet paragraphs: preserve hanging indent by keeping `editedBounds.minX` at text-start and letting wrap happen inside it (this is already how boxes work — the fix is purely "marker excluded").
4. Match/Copy/Paste ignore marker-only blocks (WP-4.4).
5. Fallback: if marker detection is ambiguous (marker not separated by a clear gap), keep current whole-line behavior — never split mid-word.

### WP-6 (P2) — Interactive overlay transparency + alignment (failure E)

Files: `ReadingCanvas.swift` only.

1. During active move/resize drags (the `onMoveDrag` / resize-handle callbacks already bracket begin/end): animate `patchView` alpha → 0.25 and textView background stays clear; restore alpha 1.0 on drag end. One-line state + two CATransaction blocks.
2. Add a temporary-peek modifier: holding Option while dragging keeps full transparency (alpha 0.1). Cheap, discoverable via tooltip.
3. Alignment aids (small, optional if time): while dragging, draw 1px guide lines at the block's original `minX` and the detected `columnBounds.minX`, snap within 3pt. Skip snap entirely if it fights the existing `preferredPageOriginX` logic — verify interaction.
4. Ensure the move handle never overlaps the first text line (offset it above/below the box based on available space — check `moveHandleGap` layout).

### WP-7 (P3) — Inspector Text Edits UX (failure G)

Files: `InspectorView.swift`, `WorkspaceViewModel.swift` (`InlineTextEditListItem`), L10n.

1. Extend `InlineTextEditListItem`: `kind: enum {edit, styleOnly, deletion, insertion}` (derived: empty replacement→deletion; replacement==source && didManuallyChangeStyle→styleOnly; isInsertion→insertion), `modifiedAt: Date`, `orderIndex: Int` (stable sort by createdAt).
2. Row layout: fixed insets, `lineLimit(2)` + middle-truncation on before/after, monospaced-digit page badge, kind badge (color-coded), relative order ("edit 3 of 5 on p.2") when a page has >1 op, member name only in multi-member workspaces.
3. Status: "applied" for all committed ops (they're synchronously baked); if WP-9 lands, show "stale" when the bake-stamp mismatches.
4. Revert button per row targets `operationID` (already does — `revertInlineTextEdit(pageRefID:operationID:)`); add a confirmation-free undo-able action + keep Revert All.
5. No version-control system. Sorting + badges + clean layout only.

### WP-8 (P0, deferred-item #1) — Sanitize strips Orifold metadata

Files: `WorkspaceDocument.swift`, `WorkspaceViewModel.swift`, tests.

1. Expose `WorkspaceDocument.strippedOrifoldMetadata(from data: Data) -> Data?` (internal static): loads PDFDocument, runs the existing `removeMetadataAnnotations` + baked-comment-annotation removal + **comments summary marker page removal if tagged**, re-serializes.
2. In `WorkspaceViewModel.sanitized(_:options:)` (`:4427`): when `options.removesMetadata`, strip Orifold metadata FIRST, then hand to `QPDFService.sanitized`. (qpdf also gets `/Info`+XMP as today.)
3. Byte-level tests: sanitized output contains none of: `OrifoldWorkspaceComments`, `editableWorkspace`, `editableMemberPDFData`, `OrifoldBakedWorkspaceComment`, any comment body string, any source-payload text marker. Non-sanitized export unchanged (round-trip test still green).

### WP-9 (P1, deferred-items #2 + #6 combined) — External-modification detection + style-only reconciliation via bake-stamp

These two share one mechanism. Files: `WorkspaceDocument.swift`, `WorkspaceViewModel.swift`, new `Orifold/Engine/WorkspaceFingerprint.swift`, tests.

1. **Bake-stamp (fixes #6):** when `regenerateEditedPage` succeeds, attach an invisible annotation `/OrifoldBakeStamp = SHA256(canonical-encoding of that page's ops)` to the regenerated page (same invisible-annotation pattern as the metadata blob). `reconcileCommittedEditsWithLoadedPages` gains a primary check: page has ops but stamp missing/mismatched → regenerate (catches style-only staleness); the v1 text-presence check stays as fallback for legacy files. No-op guard: matching stamp → skip (kills the dirty-on-open concern definitively).
2. **External-modification fingerprint (fixes #2, conservative v1):**
   - At save (`fileWrapper`, after final bytes exist): compute `SHA256(finalData)` + page count; store in a small local sidecar store (`~/Library/Application Support/Orifold/workspace-fingerprints.json`, keyed by `workspace.id`, LRU-capped). This sidesteps the can't-hash-yourself problem cleanly.
   - At load (metadata-restore path in `importPDFDocument`): if a fingerprint exists for the embedded `workspace.id` and the file's hash ≠ stored hash → **externally modified** → conservative path: import the FLAT file fresh (current third-party-visible content wins), keep only comments from metadata, drop `editableWorkspace`/ops/pristine, and surface a one-line notice ("This PDF was changed by another app; Orifold kept the visible content. Edit history from the previous session was set aside."). L10n ×6.
   - No fingerprint (other machine / pre-feature file): keep current behavior (embedded state wins) — do NOT guess from structural heuristics in this pass; document the gap.
   - Same-hash → current behavior. Trapped-state reconciliation (v1) unaffected.
3. Tests: save→byte-tamper (append annotation via qpdf or PDFKit)→reopen keeps the tamper; save→reopen untouched keeps ops; legacy file without fingerprint keeps ops.

### WP-10 (P4, deferred-item #3) — Type3/Skia preservation via dirty-tracking

Files: `WorkspaceViewModel.swift`.

1. Add `annotationDirtyMemberIDs: Set<UUID>`; set from every live-annotation mutation site (addNote/addTextBox/addInkStroke/applyHighlight/applyMarkup/place*/delete*/erase*/note edits — enumerate via grep `addAnnotation(|removeAnnotation(`).
2. `currentPDFDataForExport`/`currentPDFData`: for members NOT in the dirty set and whose `memberPDFData` entry is current (regeneration already refreshes it), return `document.memberPDFData[id]` verbatim instead of `PDFSerializer.data(from:)`. Clear a member's dirty flag whenever its bytes are re-serialized-and-stored.
3. Result: an imported Chrome/Skia PDF that is edited (regeneration path preserves? — no: regeneration re-serializes that member; text-layer for the EDITED member still degrades) but never annotated keeps its qpdf-normalized bytes across saves; annotated members still pay the PDFKit cost. Honest residual: document that annotating or editing a member still re-serializes it. Fixture: reuse/import-normalizer Type3 fixture if present (`PDFImportNormalizerTests`), else CI-safe skip.

### WP-11 (P4, deferred-item #4) — Rotated bakers

Files: new `Orifold/Engine/RotationNeutralizedPageDrawing.swift` (shared helper extracted from `PDFEditedPageRenderer`'s proven pattern), `PDFDecorationExportBaker.swift`, `PDFFormSupport.swift`, `SignatureAppearanceRenderer.swift`.

1. Helper: `withRotationNeutralizedPage(page) { rawSpaceDraw }` — draws background from a rotation-zeroed copy into a raw-mediaBox context, returns output page re-tagged with original `/Rotate` + all boxes (exact `PDFEditedPageRenderer.regeneratedPage` recipe, lines 19-68).
2. Apply to all three bakers; `SignatureAppearanceRenderer.drawPlacement` then needs no transform (placement.rect is already raw-space — consistent once background is raw-space) and `pageInfo` gets the rotation re-tag.
3. Tests: 90° and 270° generated pages; pixel-based assertions (aspect + ink-presence in expected raw-space rect), NOT text extraction. Existing rotated inline-edit tests must stay green.

### WP-12 (P4, deferred-item #5) — Annotation undo/redo stable handles

Files: `WorkspaceViewModel.swift`, `ReadingCanvas.swift` (note editor), tests.

1. On creation of any Orifold-made annotation, set a custom key `/OrifoldAnnID = UUID` (same pattern as existing `/Orifold*` keys).
2. New helpers: `resolveLivePage(pageRefID:)` (memberPDF + localIndex — exists) and `findAnnotation(annID:on:)`.
3. Rewrite the ~8 undo closures to capture `(pageRefID, annID, lightweight snapshot: type/bounds/color/contents/inkPaths)` instead of object refs; undo/redo resolves live page + annotation at execution; removal by annID; re-add by reconstructing from snapshot (never re-parent a detached object). Each closure re-registers its inverse (fixes the dead-redo family from the audit in the same stroke).
4. If resolution fails (annotation gone, page deleted): show the existing "nothing to undo"-style status rather than silent no-op.
5. Tests: create → commit text edit (forces member reload) → undo annotation → assert removed from LIVE page; redo → re-added; repeat across snapshot-restore.

### WP-13 (P4, deferred-item #7) — Cross-member pristine lockstep

1. In `movePage(_:after:)`: instead of rebasing both members to baked bytes, physically move the PRISTINE page: load both pristine PDFs (`originalMemberPDFData`), extract source-pristine page at old `sourcePageIndex`, insert into target pristine at the insert index, delete from source pristine, re-serialize both pristine blobs, renormalize `sourcePageIndex` for both members, migrate the moved ref's `pageEditStates` unchanged (sourceBounds are page-local — still valid).
2. Undo path: OrderSnapshot must also capture/restore `originalMemberPDFData` for the two touched members (add a scoped field; do NOT snapshot all pristine data for every order op — memory).
3. Fallback: any step fails → current rebase-to-baked behavior (strictly no worse).
4. Tests: move edited page cross-member → re-edit → no ghost of first bake (`FIRSTREPLACEMENT`-style assertion from v1's pristine tests); undo/redo of the move preserves editability.
5. **If this exceeds budget/risk mid-implementation: defer with TODO** — it is the lowest-priority package; the v1 rebase behavior is already consistent.

---

## 4. Fixtures (all generated in-test; zero new absolute paths)

Add `Tests/OrifoldTests/Support/EditingFixturePDFBuilder.swift`:
- `underlinedParagraph()` — text + CGContext-stroked 1pt line under a run (PDFium sees a path object).
- `tableWithRules()` — heading above a 2×3 grid with 0.75pt h/v rules, distinct header vs body fonts, narrow (~10pt) gutters.
- `bulletList()` — "• " markers (drawn as separate text run at smaller x) + hanging-indent body lines, resume-like.
- `mixedFonts()` — Helvetica 10.2 body, Helvetica-Bold 13 heading, Times-Italic 11 caption, gray + black colors.
- `rotated(_ deg:, content:)` — wraps any of the above with `/Rotate 90/270`.
The two real user fixtures (`test-text-edit-latest.pdf`, `inline-edit-stress-test.pdf`) stay as local-only skip-guarded validation (pattern already established).

---

## 5. Test matrix (new/updated, deterministic)

| Area | Test file (new unless noted) | Key assertions |
|---|---|---|
| Editor non-mutating | `EditorLifecycleNonMutationTests` | open→cancel: member bytes hash-identical; open→Done-unchanged: no op, bytes identical; armed-painter + identical style: no commit; underline visible after cancel (pixel band under baseline) |
| Underline | same + `PageGraphicsIndexTests` | detection true on fixture; commit preserves underline (pixel row present in regenerated page under new text); Reset(committed) restores exact original (bytes regenerated from pristine) |
| Deletion | `TextDeletionLifecycleTests` | empty+Done commits erase-op; live page ink gone in source rect (pixel); export+reopen gone; undo restores; redo removes; revert restores original |
| Table | `TableEditPreservationTests` | heading NOT merged into cell block; v-rule pixels intact post-edit at rule x (pixel column sample); export/reopen intact; Reset restores |
| Copy/Paste/Match | extend `MatchFormatInferenceTests` + `InlineEditorFormatUXTests` | paste carries underline+lineHeight; match excludes grid cells + markers on generated fixtures; gray/black color cases |
| Detected fonts | `DetectedFontChoicesTests` | mixedFonts page yields ≥3 candidates with correct family/size/traits; substituted flag when face missing; applying candidate sets family+size+traits |
| Bullets | `BulletEditStabilityTests` | marker bounds unchanged after text edit (geometry); text minX stable; export/reopen stable |
| Overlay backing | `InlineEditorFormatUXTests` (extend) | patch alpha drops during simulated drag state and restores; state-level (no snapshot infra) |
| Inspector | `InspectorTextEditRowTests` | item kind derivation (deletion/styleOnly/insertion/edit); ordering; truncation model (string prep helpers) |
| Sanitize | `SanitizedExportLeakTests` | byte-scan: no `OrifoldWorkspaceComments`/JSON markers; comments absent; plain export still round-trips |
| External mod | `ExternalModificationReopenTests` | tampered file wins; untouched file keeps ops; no-fingerprint legacy keeps ops |
| Bake-stamp | `StyleOnlyReconciliationTests` | style-only stale bytes regenerate; matching stamp = no rewrite (bytes untouched on load) |
| Type3 | extend `PDFImportNormalizerTests` | unannotated member bytes byte-identical across save; CI-skip if no fixture |
| Rotated bakers | `RotatedBakerTests` | 90°/270° decoration/form/signature output: page aspect preserved + ink in expected region (pixel), `/Rotate` preserved |
| Annotation undo | `AnnotationUndoAfterReloadTests` | undo/redo across member reload affects live page; no silent no-op |

**Validation style rules (hard-won, follow them):** never assert via `PDFPage.string`/`.attributedString` on edited/rotated/dense pages (CI Xcode 16.4 scrambles — use `PDFTextAnalysisEngine` reading-order join, subsequence-tolerant, or pixel sampling; see `ci-xcode164-pdfkit-string-extraction-quirk`). Pixel checks must render rotation-aware. Re-fetch pages after any commit (combinedPDF is rebuilt).

---

## 6. Priorities → packages map

- **P0:** WP-0, WP-1 (C), WP-2 (B), WP-3 (F), WP-8 (sanitize), WP-9.2 (external mods)
- **P1:** WP-4 (A), WP-9.1 (bake-stamp)
- **P2:** WP-5 (D), WP-6 (E)
- **P3:** WP-7 (G)
- **P4:** WP-10, WP-11, WP-12, WP-13 (defer-with-TODO allowed, WP-13 first to drop)

## 7. Risk register

| Package | Risk | Mitigation |
|---|---|---|
| WP-0 | pathological vector pages slow scan | object cap + time budget, log when capped |
| WP-1.6 Reset-as-revert | UX change; reopened block re-detected imperfectly | only for `isExistingEdit`; keep old path behind the non-committed branch |
| WP-2 patch clipping | exposed original ink through rule holes | §3-B-4 guard: text coverage wins over rule preservation |
| WP-2 rule-split | over-splitting prose with decorative lines | only split when rule crosses the gap band vertically (rule y-range overlaps line y-band) |
| WP-3 | empty-op edge cases in measured/reconcile paths | explicit empty-layout guards + dedicated tests |
| WP-4 lineHeight | CoreText min/max line height clipping tall glyphs | reuse existing `originalLinePitch` plausibility band (0.9–3× font size) |
| WP-9 fingerprint | hash store is per-machine | documented; legacy behavior when absent |
| WP-9 stamp | annotation stripped by third-party tools | that ALSO changes the file hash → external-mod path handles it |
| WP-11 signature baker | most-used save path | pixel tests on 0/90/270 + full-suite; land behind small helper reused from proven renderer code |
| WP-12 | 8 call sites, behavioral undo change | one shared helper, mechanical rewrites, per-site tests |
| WP-13 | pristine surgery complexity | fallback to current behavior on any failure; first to defer |

## 8. Executor gotchas (repo-specific, all learned the hard way)

1. **Shared repo, concurrent sessions:** `git fetch` before every push; expect `Localizable.xcstrings` merge conflicts (regenerate by re-running the key-add script rather than hand-merging). Watch for stray `* 2.swift` Finder-conflict copies breaking SPM builds — delete them.
2. **L10n:** every new UI string needs all 6 languages (en/es/fr/hi/ja/zh-Hans) in `Localizable.xcstrings` or `LocalizationCoverageTests` fails. SPM tests read via Bundle.module JSON fallback.
3. **CI toolchain:** Xcode 16.4. The extraction quirk (§5). Also `swift test` locally ≠ CI — push early in the branch, watch the first CI run.
4. **Codable evolution:** every new field on persisted models (`PDFTextEditOperation`, `PDFTextEditFormat`, `Workspace`, analysis types if cached) must use `decodeIfPresent` + default — old workspace payloads must keep loading (test with a fixture from the v1 tests).
5. **xcodegen/project.yml:** new Swift files under `Orifold/` are glob-picked; if CI's Xcode-build step fails on a missing file, regenerate the project (`xcodegen`) and commit.
6. **rtk:** shell commands are auto-proxied; nothing to do.
7. **swiftlint:** don't add new violations in touched files (baseline is warning-heavy; compare per-file counts before/after, pattern in v1 session).
8. **Renderer state leaks:** any new CGContext drawing must `saveGState/restoreGState` AND reset text drawing mode (`.fill`) — see the invisible-text contamination comment in `PDFEditedPageRenderer.drawReplacement`.

## 9. Verification loops (two, both green, before merge)

**Loop 1 — focused:** run every test file in §5 + the v1 editing suites (`InlineEditReconciliationTests`, `StructuralOpsEditConsistencyTests`, `MatchFormatInferenceTests`, `InlineEditorFormatUXTests`, `StressFixtureLifecycleTests`, `DocumentTypeEditHardeningTests`, `PDFTextEditingRedesignTests`, `UserFlowRegressionTests`, `InlineEditExportHardeningTests`). Fix all failures, rerun everything touched.

**Loop 2 — full safety:** sync branch with `main`, then: clean `swift build`; full `swift test`; `swiftlint` per-file delta check; the local-only real-fixture tests (trapped fixture + stress PDF) if present on the machine; then a manual changed-file sweep for: broad rewrites, debug logs/probes, absolute paths, force-unwraps, silent `catch {}`, misleading deletion/redaction copy, unnecessary PDFKit round-trips, missing L10n keys, missing `decodeIfPresent` defaults. Fix, then rerun full suite + affected targeted tests again. Both loops must complete green — a fix during Loop 2 requires rerunning Loop 2's suite.

## 10. Merge + post-merge

Merge requirements: branch synced with `main`, conflicts resolved, clean build, full suite green, new tests green, no new lint violations, no local-only fixture deps (skip-guards verified by grep for the fixture dir path), no debug logging.

Then ff-merge to `main`, push, and post-merge validate on `main`: build, full suite, plus the highest-risk targeted set: deletion lifecycle, underline reset, table rule preservation, copy/match/paste, sanitize leak scan, external-mod reopen, export/reopen round-trip. CI must go green on the push (watch the run — do not walk away; the v1 pass shipped a local-green/CI-red state twice).

If post-merge fails: test-only failure → fix forward on `main`; product-code failure → revert the merge commit immediately, fix on branch, re-run both loops.

## 11. Final report checklist (fill all 13 items)

1. final commit SHA · 2. branch name · 3. files changed · 4. root causes confirmed (vs §1 — note any that turned out different) · 5. fixes implemented per WP · 6. tests added/updated · 7. Loop 1 results · 8. Loop 2 results · 9. post-merge validation incl. CI run id/status · 10. risks reduced · 11. risks deferred (esp. WP-13, any WP-10/11/12 partials, letter-spacing fidelity, true redaction, cross-machine fingerprints) · 12. remaining limitations (visual-only deletion; embedded-font substitution; style fidelity caps) · 13. merged+pushed confirmation.

Do not overclaim: deletion is visual, fonts are best-available substitutes, external-mod detection is same-machine-only in this pass.
