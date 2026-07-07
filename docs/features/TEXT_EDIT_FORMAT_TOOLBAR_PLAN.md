# Text Editing, Format Painter & Toolbar — Redesign Plan

**Status:** Plan only (no code yet). Hand-off document for Sonnet execution.
**Date:** 2026-07-07
**Builds on:** [SMART_TEXT_EDIT_PLAN.md](SMART_TEXT_EDIT_PLAN.md) (2026-07-06). That plan's Phase 1
(hittable fallback + editability classification) **has shipped**; its Phase 2 "transparent edit
mode", §3.3 coordinate normalization, §3.6 region OCR, and §3.7 content-stream removal have **not**.
This document supersedes its remaining phases and extends scope to the Format Painter and the top
toolbar.

Every file:line below was verified against the current tree (branch
`friendly-helper-claude/gracious-hypatia-030c8d`) by a 14-agent audit + adversarial verification
pass. Line numbers will drift during implementation — treat them as anchors, re-grep the cited
symbol names.

---

## 1. Executive diagnosis

### 1.1 White box behind edited text (while editing)

The live editor overlay **is** a white box, by construction. `InlineTextEditorOverlay` stamps two
opaque white layers over the page:

- `patchView.layer?.backgroundColor = NSColor.white.cgColor` — hardcoded pure white, never sampled
  from the page (`ReadingCanvas.swift:2586`), framed to the detected block bounds + 2px on every
  side (`ReadingCanvas.swift:3032`), on top of the analysis engine's own −2pt bounds inset — so it
  bleeds ~4pt past the glyph ink in all directions, including down into the next line.
- The text view itself: `textView.drawsBackground = true; backgroundColor =
  NSColor.white.withAlphaComponent(0.98)` (`ReadingCanvas.swift:2595-2596`).

The editor's minimum geometry then inflates the box far past the original line:

- Minimum width **156pt** (180pt for empty text) regardless of the text's real width
  (`ReadingCanvas.swift:3007`) — a short heading like "AI & Data" gets a white slab much wider
  than its ink.
- Height `max(sourceRect.height + 6, displayFontSize * 1.5)`, **top-anchored** so all extra height
  hangs *below* the original line (`ReadingCanvas.swift:3021-3024`), directly over the content
  beneath — exactly the reported symptom. Live re-measure keeps a ≥1.55× font-size floor and grows
  downward (`resizeTextViewHeight`, `ReadingCanvas.swift:3060-3066`); `autoFitWidthIfNeeded`
  (`ReadingCanvas.swift:3116`) widens it rightward while typing.

### 1.2 White box baked into the page (after commit / in export)

On commit, `PDFEditedPageRenderer.regeneratedPage` redraws the pristine page, then paints opaque
"erase patches", then the replacement text — and the regenerated page replaces the live page and is
re-serialized into the member PDF (`WorkspaceViewModel.swift:2612, 2653-2676`), so screen and
export show identical patches. Export just concatenates the already-baked members
(`WorkspaceViewModel.swift:1270-1280` → `WorkspaceDocument.snapshot`). Three compounding causes:

1. **Destination-box erase over-triggers.** `eraseBounds()` erases the *full committed box*
   (`editedBounds`) — not just the original text — whenever any of four **sticky** flags is set:
   `didManuallyReposition` (set by a 1px handle drag, `ReadingCanvas.swift:3193`),
   `didManuallyResizeWidth`/`Height` (both set by any resize drag, `ReadingCanvas.swift:3208`), or
   `didApplyMatchedGeometry` — set by **Match Style, Copy/Paste Style, and the armed format
   painter** (`applyParagraphGeometry`, `ReadingCanvas.swift:3407-3416`;
   `PDFEditedPageRenderer.swift:110-116`). The committed box is systematically taller than the
   original line (CoreText line height of the substitute font + 4pt, top-anchored downward —
   `measuredBounds`, `PDFEditedPageRenderer.swift:254-276`), so this patch covers the line below.
   **This is the user's exact repro: using copy-format flipped `didApplyMatchedGeometry`, which
   stamped an `editedBounds`-sized patch over the content under "AI & Data".**
2. **Patch color falls back to pure white** and is otherwise a single flat dominant-bucket color:
   `sampledBackgroundColor(...) ?? NSColor.white.cgColor` (`PDFEditedPageRenderer.swift:124`),
   dominant 16-level RGB bucket average (`:366-420`). Gradients, tinted bands, two-tone resume
   sidebars → one flat rectangle. There is no "background too complex, don't patch" branch.
3. **Block-level erase for fallback blocks.** PDFKit-fallback (`.replace`) blocks and reopened-edit
   synthetic blocks carry `lines: []`, so erase falls back to the whole `sourceBounds`
   (`PDFEditedPageRenderer.swift:102`) — line-selection rects taller than glyph ink, ~3pt bleed.
   Worst case: `wholePageFallbackBlock` (`PDFTextAnalysisEngine.swift:607-628`) has non-empty text
   and `bounds = cropBox.insetBy(dx: 48, dy: 48)`, so it fails the `isInsertion` check
   (`WorkspaceViewModel.swift:2568`) and a committed edit **erases nearly the entire page**.

Additionally the original glyphs are never removed — the whole original page is redrawn underneath
(`context.drawPDFPage(pageRef)`, `PDFEditedPageRenderer.swift:95`) and merely painted over, so the
patch is the *only* thing hiding the old text (old text remains searchable/extractable in exports).

### 1.3 Format Painter copies the wrong/partial style

Five verified defects, in descending impact:

1. **Style is coupled to geometry.** `apply(format:)` always calls `applyParagraphGeometry`, which
   adopts the *source paragraph's* `bounds`/`columnBounds` and sets `didApplyMatchedGeometry`
   (`ReadingCanvas.swift:3390-3416`). Pasting "Cloud & DevOps" onto "AI & Data" moves/re-wraps the
   target box to the source's column footprint *and* triggers the destination-erase patch (§1.2.1).
2. **Alignment and underline are never extracted from the PDF.** The analysis engine's block
   builder omits both; `PDFTextEditFormat(block:)` coerces nil alignment to `.left`
   (`PDFTextEditingModels.swift:265-273`). Centered/underlined headings paste as left/plain.
3. **Weight transfer is lossy end-to-end.** PDFium's 100–900 weight is collapsed to a bold/regular
   PostScript-name substitution (`PDFTextAnalysisEngine.swift:212-215`); `apply()` re-derives
   traits from `NSFont(name:)` with a `.systemFont` fallback that silently drops bold/italic when
   the name doesn't instantiate (`ReadingCanvas.swift:3392-3394`). Semibold → regular.
4. **Copy captures the original analysis-derived style, not what the user sees.** `copyNearbyFormat`
   stores the immutable `sourceFormat` captured at editor open (`ReadingCanvas.swift:3341-3346`);
   for previously-edited blocks the "original" is resolved by nearest-block-within-80pt (block IDs
   are re-minted every analysis pass), so it can be read from the **wrong paragraph** — e.g. the
   body text under the heading.
5. **No painter UX.** Armed state (`isInlineTextFormatPainterArmed`,
   `WorkspaceViewModel.swift:310`) has no cursor, no toolbar state, no Escape disarm (cancel leaves
   it armed — `ReadingCanvas.swift:2514-2527`), auto-fires on the next editor open possibly minutes
   later (`applyArmedFormatPainterIfNeeded` in init, `ReadingCanvas.swift:2495`), and paste is not
   undoable in-editor (undo registration suppressed, `ReadingCanvas.swift:3467-3475`).

### 1.4 Toolbar crowding and the "-" control

- **Structural crowding:** 14 toolbar items — 2 leading buttons, a `.principal` capsule that alone
  is ~480–530pt (12 fixed 28pt tool buttons + 5–6 dividers, `.fixedSize()` so it never compresses;
  `ContentView.swift:1638-1691`), and a trailing `ToolbarItemGroup` of **11** items with zero
  adaptive collapse. Below it sits a *second* full-width bar (`ZoomPageBar`,
  `ReadingCanvas.swift:241-330`, first child of the canvas VStack at `:18`) with zoom −/fit/+,
  brand, and page field — two stacked chrome bars reading as one bloated "top toolbar".
- **The "-" control:** most likely the bare `Divider().padding(.horizontal, 2)` placed directly in
  `ToolbarItemGroup(.primaryAction)` between Redo and Reader-mode (`ContentView.swift:455-456`).
  Outside a stack, a toolbar `Divider` resolves horizontally — a short gray **dash that reads as a
  minus sign** and consumes a full toolbar-item slot plus inter-item spacing. (The zoom-out `minus`
  at `ReadingCanvas.swift:249-255` is the secondary candidate; the plan removes/compacts both.)
- **Icon inconsistency:** 8 trailing buttons go through `ToolbarIconButton` (14pt semibold,
  28×28, r7); the Export/More `Menu`s only match glyph size but keep system menu chrome + chevron;
  `GuideButton` is patched ad hoc at the call site (`ContentView.swift:592-596`);
  `ShortcutsCheatSheetButton` has no styling at all and renders at native toolbar size.

### 1.5 Active-state fill bleeding outside button borders

The blue active fill on `isActive` buttons (inspector `sidebar.right`, eyeglasses
`documentComfort`, reader-mode) is a conditional, **unclipped** `RoundedRectangle(cornerRadius: 7)
.fill(Color.dsAccent)` ZStack layer constrained only by `.frame(28×28)`
(`ContentView.swift:1944-1956`). `.contentShape` is hit-testing-only — there is **no `clipShape`**.
The app builds against the macOS 26 SDK with no Liquid Glass opt-out, so the *visible* button
border users perceive is the system's glass toolbar-item chrome, whose capsule geometry differs
from the custom r7 square — the flat opaque fill renders outside that perceived border. The bleed
is amplified by animation: the eyeglasses `isActive` flips inside `withTransaction(.easeInOut
0.15)` (comfort presets), animating insertion of the unclipped fill with a default transition,
while `ToolButtonStyle` layers hover/press `.animation` + `scaleEffect`
(`ContentView.swift:1891-1909`), and `acceptsImportDrops` overrides the rounded `contentShape`
with a full `Rectangle`.

---

## 2. Current-state audit checklist (for Sonnet, Phase 1)

Work through this list before changing behavior; check each box by reproducing the cited mechanism.

**Text edit pipeline**
- [ ] `Orifold/Views/ReadingCanvas.swift` — `InlineTextEditorOverlay`: `patchView` white layer
  (2586, 3032), textView white background (2595-2596), min geometry (3007, 3021-3024, 3060-3066),
  `autoFitWidthIfNeeded` (3116), move/resize flag setting (3193, 3208), cancel path leaving
  painter armed (2514-2527), `applyArmedFormatPainterIfNeeded` in init (2495), format-toolbar undo
  suppression (3467-3475), scroll/zoom re-layout via notifications (2658-2664).
- [ ] `Orifold/Engine/PDFEditedPageRenderer.swift` — `eraseBounds` flag logic (98-117),
  `drawErasePatch` white fallback (119-127), `measuredBounds` top-anchored growth (137-277),
  `sampledBackgroundColor` dominant bucket (366-420), `regionIsBlankBackground` (300-364, gates
  only width growth, never the patch), whole-page redraw keeping old glyphs (95),
  `ReplacementTextLayout` (444-565): CTFrameDraw top-fill, `originalLinePitch` needs ≥2 lines
  (476-494), captured `baseline` never consumed.
- [ ] `Orifold/Engine/PDFTextAnalysisEngine.swift` — tiered hitTest filters only `.insertion`
  (106-118), line-level PDFKit fallback (561-604), `wholePageFallbackBlock` `.overlayOnly` with
  non-empty text + cropBox-inset-48 bounds (607-628 — **giant-erase hazard**), majority-vote
  single-style blocks (462-470), font resolution → Helvetica fallback (212-258), per-page PDFium
  init/teardown under global lock (127-137), unstable block UUIDs per pass.
- [ ] `Orifold/Models/PDFTextEditingModels.swift` — `PDFTextEditFormat` carries `bounds`/
  `columnBounds` (238-274); `PDFTextEditability` lacks `.ocr`; `EditableTextBlock` lacks
  letter-spacing/line-height/strikethrough/weight fields.
- [ ] `Orifold/ViewModels/WorkspaceViewModel.swift` — `applyInlineTextEdit` re-runs
  `measuredBounds` after Done (WYSIWYG divergence), `isInsertion` requires empty text AND lines
  (2568), `regenerateEditedPage` page swap + full member re-serialize (2612, 2653-2676),
  `textAnalysisCache`, export provider (1270-1280), `copiedInlineTextFormat` (309-310),
  painter disarm only on undo/redo (1826, 1837, 1845), OCR never refreshes
  `originalMemberPDFData` (2073-2077 vs 6198), legacy dead FreeText overlay path (4932-4934).
- [ ] Undo — environment `NSUndoManager`, `InlineTextEditSnapshot` full-byte member snapshots per
  edit (O(doc size) per step); editor-local NSTextView stack invisible to workspace undo;
  annotation undo closures invalidated by page swap; redo chord split (⌘Y app vs ⇧⌘Z editor).

**Toolbar / design system**
- [ ] `Orifold/Views/ContentView.swift` — `mainToolbar` (400-601), bare `Divider` (455-456),
  `AnnotationToolPicker` capsule + `ViewThatFits` single-menu fallback (1655-1753),
  `ToolbarIconMetrics` (1915-1920), `ToolbarIconButton` unclipped active fill (1927-1963),
  `ToolButtonStyle` animations (1891-1909), `ToolbarMenuIconLabelStyle` (1968-1975),
  ad-hoc `GuideButton` styling (592-596).
- [ ] `Orifold/Views/ReadingCanvas.swift` — `ZoomPageBar` at top of canvas (17-18, 241-330).
- [ ] `Orifold/DesignSystem/DesignSystem.swift` — tokens (colors/spacing/radii/type); missing:
  motion tokens, on-accent foreground, icon/control-size scale; r7 off the 6/10/16 radius scale.
- [ ] Build settings — macOS 26 SDK, deployment target 14.0, no Liquid Glass opt-out/adoption.

**Cross-cutting**
- [ ] `Orifold/Resources/Localizable.xcstrings` — 965 keys × 6 languages (en/es/fr/hi/ja/zh-Hans),
  gated by `LocalizationCoverageTests` (every new key must exist in all 6 or CI fails).
- [ ] `Orifold/App/ShortcutRegistry.swift` — descriptive-only cheat sheet, hand-synced; ⌘B/⌘I/⌘U
  advertised in editor tooltips but unwired (plain-text NSTextView).
- [ ] Accessibility — SwiftUI toolbar has labels/hints; AppKit inline editor has almost none
  (only the move handle, `ReadingCanvas.swift:4106`); ~10 views copy-paste
  `reduceMotion || NSWorkspace... || comfort.reduceAnimations`; AppKit editor CATransactions
  ignore it (4004-4020).
- [ ] `DocumentComfortSettings` — viewer-only page modes incl. high-contrast; chrome never
  observes `accessibilityDisplayShouldIncreaseContrast`.

---

## 3. Desired UX behavior

### A. Editing existing text (`.direct` / `.replace`)

- **Enter:** Edit Text tool active → hover shows a faint accent outline on the hit block
  (pre-click affordance; today feedback is post-click only). Click → editor opens **in place**,
  prefilled, sized to the text's real ink bounds + 4pt padding — never a 156pt slab.
- **Edit state:** transparent. The original line is hidden by a *live erase preview* painted with
  the same sampled background the renderer will bake (WYSIWYG), clipped to the source line rects —
  not a white sheet over the block. Chrome = 1px accent rounded outline + small corner/edge
  handles rendered *outside* the content box; the mini format bar floats above (or below when near
  the top), never covering neighboring lines.
- **Selection bounds:** the outline hugs the committed geometry exactly; if commit would auto-grow
  the box (column cap, height cap), the outline previews that final geometry *before* Done — what
  you see is what gets baked.
- **Commit:** Done (⌘⏎) bakes exactly the previewed geometry. No-op guard: unchanged text + style
  + geometry ⇒ zero operation, zero layout shift.
- **Cancel:** Esc discards; no artifacts, painter state untouched (see E).
- **Export:** patches only under the actual replaced line rects; never pure-white on non-white
  paper; complex background ⇒ explicit warning chip before commit (see C).

### B. Adding overlay text (`.insertion`)

Click on blank space → "New text" chip, transparent box with placeholder caret, no erase ever
(already guaranteed by `isInsertion`). Visually identical editor chrome, different chip label so
users know nothing is being replaced.

### C. Replacing text visually (controlled mask)

When the region's background is non-uniform (reuse the `regionIsBlankBackground` heuristic on the
erase rects, which today is only consulted for width growth), the app must *say so instead of
silently stamping a flat rectangle*: a warning chip on the editor — "Background here isn't plain
paper. Orifold will cover it with a sampled patch." Commit proceeds only with that explicit state
visible. `.overlayOnly` blocks always show the existing cover-and-replace banner; the
**whole-page fallback block must never erase the whole page** (fix in §4.5).

### D. OCR / image-only PDFs

Unchanged near-term behavior (scanned page → `.overlayOnly` chip + make-searchable flow), plus the
two shipped-gap fixes: refresh `originalMemberPDFData` after OCR so PDFium can analyze the OCR
layer, and add `.ocr` to `PDFTextSource` so future region-OCR (SMART plan §3.6) has plumbing.
Region-OCR itself stays deferred — it is not required to fix this brief.

### E. Copying formatting (Format Painter)

Word mental model, adapted:

- **Capture:** inside the editor, "Copy Style" captures the *currently visible* style
  (`currentFormat`), not the stale analysis original. Confirmation toast + the painter button
  enters an armed (filled) state.
- **Apply:** with the painter armed, the next text block clicked gets the style applied
  **style-only** (no geometry adoption) and the painter disarms (single-use). ⌥-click the painter
  button (or double-click, Word-style) pins it: applies to every subsequent clicked block until
  Esc/tool-switch/click on empty space.
- **Cursor:** armed state swaps the canvas cursor to a paintbrush (custom `NSCursor`), plus a thin
  persistent status chip "Style copied — click text to apply (Esc to cancel)".
- **Cancel:** Esc, tool change, or editor cancel disarms. Never silently auto-applies minutes
  later.
- **Undo:** every apply is one undo step; ⌘Z reverts the style application only.
- **Shortcuts (Mac, Word-compatible):** ⇧⌘C = Copy Style, ⇧⌘V = Paste Style (check collisions:
  neither is bound today; ⌘C/⌘V untouched). Registered in `ShortcutRegistry` + cheat sheet.

### F. Toolbar use

- **One chrome row.** Zoom/page controls fold into the main toolbar as one compact pill; the
  `ZoomPageBar` row disappears (brand moves to the empty-state / About, page field into the pill).
- **Tiered visibility:** Tier 1 always visible (select, edit-text, markup cluster, comment, undo/
  redo, search, zoom/page pill, export/share, inspector, More). Tier 2 contextual (signature/stamp
  palettes, form bar, editing format bar — appear with their tool/mode). Tier 3 in More (settings,
  about, guide, shortcuts cheat sheet, page ops, print, comfort presets beyond the eyeglasses
  toggle).
- **Responsive:** the capsule already has `ViewThatFits`; extend the same discipline to the
  trailing cluster with a defined collapse order (see §6).

---

## 4. Text editing technical plan

### 4.0 Editing model decision

**Recommendation: keep the hybrid replacement model (regenerate page = redraw + erase + redraw
text) and fix its geometry, color, and preview honesty.** Do not switch to content-stream editing
now, and do not regress to annotation overlays. Rationale in §13; the model is already
rotation-safe, undo-integrated, persistence-integrated, and its failures are all *parameter*
failures (patch color, patch size, flag triggers, preview chrome), not architecture failures.
True content-stream text removal (PDFium `FPDFPageObj` deletion / qpdf surgery) stays a Phase-5+
investigation for `.direct` blocks only.

### 4.1 Transparent edit overlay

- Delete the white `patchView` fill; repaint it as a **live erase preview**: fill with
  `sampledBackgroundColor(near:on:)` (same function the renderer uses — extract it from
  `PDFEditedPageRenderer` into a shared helper so preview and bake can never disagree), clipped to
  the union of `block.lines[].bounds` (fall back to `block.bounds` only when lines are empty).
- `textView.drawsBackground = false`; text draws over the preview patch. Caret color stays
  `dsAccentNS`.
- Editor chrome: 1px `dsAccent` rounded (r 4) outline via a border layer, handles outside the
  content rect, format bar detached above/below. No shadow sheets.
- Remove min-width 156/180 and the 1.5×-font-height floor. Editor content size = measured text
  size + `textContainerInset` (3×2) + 2pt; the *hit area* for grabbing can stay large without
  painting anything.

### 4.2 Bounds, line-height, baseline

- **Commit geometry = preview geometry.** Run `measuredBounds` on the draft *live* (debounced) and
  drive the editor outline from it; `applyInlineTextEdit` then commits that exact rect instead of
  re-deriving post-hoc.
- **Baseline anchoring:** consume the captured `block.baseline` (today dead data). For single-line
  edits, draw the first CTLine at the original baseline (compute frame origin = baseline −
  substitute-font ascent) instead of top-filling the frame; extend `originalLinePitch` to
  single-line sources by deriving pitch from the source font size when only one line exists.
- **Height:** for unchanged/similar-length text, prefer source ink height (already partially done
  via `unchangedTextHasKnownHeight`); when CoreText needs more, grow but *show it* in the preview.

### 4.3 Erase-patch discipline (the core fix)

1. **Per-line always.** Populate `sourceLineBounds` for PDFKit-fallback blocks (each fallback block
   is one line — set `sourceLineBounds = [bounds]` tightened by the selection's glyph run) and for
   reopened synthetic blocks (persist original line bounds on the operation — they already are;
   stop dropping them on reopen).
2. **Decouple the four flags.**
   - `didApplyMatchedGeometry`: **stop setting it from style paste** (§5). Match Style keeps it
     only when the user explicitly chooses "match geometry too" (new secondary action).
   - `didManuallyReposition`: require a real move (≥3pt accumulated delta) before latching.
   - Resize drag sets only the axis actually dragged, not both.
   - Make flags **clearable**: if the user drags the box back within 1pt of origin, unlatch.
3. **Destination erase = only what's needed.** When destination erase is legitimately required
   (real move/resize), erase `editedBounds ∩ page`, but first check `regionIsBlankBackground` on
   the *newly covered* area (destination minus source): if blank ⇒ skip the destination patch
   entirely (drawing text on blank paper needs no patch); if not blank ⇒ patch + surface the §3.C
   warning chip.
4. **Never a silent pure-white fallback.** If `sampledBackgroundColor` returns nil, sample the page
   corners for the paper color; only if that also fails use white — and log via `ImportLog`.
5. **Whole-page fallback block must not erase.** In `applyInlineTextEdit`, treat
   `.overlayOnly` + empty `lines` + bounds ≥ ~50% of the page as insertion-like for erase purposes
   (erase nothing; the replacement draws as overlay text), or clamp erase to the typed-text rect.
   Add a regression test: committing an edit on `wholePageFallbackBlock` must not produce a patch
   larger than the edited text bounds.

### 4.4 Layering, drag/resize, collision

- Keep the overlay an `NSView` child of the PDFView for now, but move re-layout from
  notification-driven manual frames to `PDFPageOverlayViewProvider` (the coordinator already
  implements it for ink/signature overlays) in Phase 5 — lower-risk, removes scroll/zoom glue.
- Z-order: erase-preview patch < text view < outline < handles < format bar.
- Collision awareness: while dragging/resizing, if the live outline intersects other detected
  blocks' bounds (from the cached analysis), tint the outline amber — no hard blocking, just
  honesty. Cheap: analysis is already cached per page.

### 4.5 Fonts

- Keep `resolveFontPostScriptName` substitution; **stop the silent `.systemFont` drop**: when
  `NSFont(name:)` fails at apply/render time, re-run the resolver against the requested family +
  numeric weight instead of falling to system, and record the substitution on the operation so the
  UI can show "shown in <substitute>" in the editor chip. Embedded-font extraction/reuse stays out
  of scope (heavy; note as future work).

### 4.6 Export, persistence, undo

- Export path needs no structural change (patches are baked pre-export); the fixes above flow
  through automatically. Add golden-image tests (§10).
- Persistence: unchanged this round, but note the audit finding — pristine originals are not
  preserved across save/reopen (baked members become the new "original"), so re-edits after reopen
  re-patch baked pages. Acceptable for now; document it in code and add a fixture test so the
  behavior is at least pinned. Full pristine-bytes store = future work.
- Undo: all changes funnel through `applyInlineTextEdit` + `InlineTextEditSnapshot`, so undo keeps
  working; add tests for painter-apply undo (§5) and geometry-flag changes. Do not touch the
  snapshot model this round (memory cost is a known, separate issue).

---

## 5. Format Painter technical plan

### 5.1 Style schema

Extend, don't replace, the Codable `PDFTextEditFormat` — split style from geometry:

```swift
/// Pure visual style — safe to apply anywhere. Codable.
struct TextStyleSnapshot: Codable, Equatable {
    // Typography
    var fontFamily: String          // family, not resolved PostScript name
    var fontPostScriptName: String  // best resolved face, for exact reuse when available
    var fontSize: CGFloat
    var weight: Int                 // 100–900 numeric (PDFium already reports it)
    var isItalic: Bool
    // Color
    var textColor: CodableColor
    var opacity: CGFloat            // 1.0 default; applied to textColor alpha
    // Decoration
    var underline: Bool
    var strikethrough: Bool         // capture-ready; render support may lag (see 5.5)
    // Paragraph
    var alignment: CodableTextAlignment
    var lineHeightMultiple: CGFloat?   // nil = derive from source pitch
    var letterSpacing: CGFloat?        // nil = normal (kCTKernAttributeName when set)
    // Metadata
    var sourceKind: StyleSourceKind    // .pdfNativeText | .editedOperation | .overlayText
    var capturedAt: Date
}

/// Geometry lives separately and is opt-in.
struct TextGeometrySnapshot: Codable, Equatable {
    var bounds: CGRect?
    var columnBounds: CGRect?
}
```

`PDFTextEditFormat` becomes a thin composition (`style` + `geometry`) with a migration decoder for
old saved workspaces (decode legacy flat keys → snapshot pair). `copiedInlineTextFormat:
PDFTextEditFormat?` on the view model becomes `copiedTextStyle: TextStyleSnapshot?` (+ optional
`copiedTextGeometry` for the explicit "match geometry" action).

### 5.2 Capture behavior

| Source | How |
|---|---|
| Block being edited (button in editor) | Capture `currentFormat`-equivalent **live** editor state — family/size/traits/color/alignment/underline as currently visible, not the stale `sourceFormat`. |
| Un-edited PDF text (eyedropper, no editor) | New armed "pick source" micro-mode: with painter shortcut pressed while no editor open, click any text → run cached analysis hitTest, build snapshot from block (plus new engine extraction below). One extra click, no editor spawn. Phase 3 stretch; MVP = capture from editor only. |
| Heading / mixed-format selection | Blocks are single-style today (majority vote, `PDFTextAnalysisEngine.swift:462-470`). MVP: capture the block's dominant style and say so ("Copied dominant style"). Per-run capture = future work; the schema (per-run list) is ready for it. |
| Previously edited block | Capture the operation's *replacement* style (what's visible), never the nearest-block-80pt guess. Match by operation identity (the editor already knows its operation on reopen), not by re-analysis UUIDs. |
| Overlay/insertion text | Same snapshot; `sourceKind = .overlayText`. |

**Engine extensions (needed for honest capture):**
- Alignment inference: compare line x-extents to `columnBounds` (left-flush / centered /
  right-flush within tolerance) in `buildBlock`; store on `EditableTextBlock.alignment` (field
  exists, never set).
- Underline/strikethrough detection: scan page vector segments for horizontal rules within
  [baseline−0.15em, baseline+0.05em] (underline) / mid-x-height (strikethrough) spanning ≥80% of a
  run's width. Heuristic, flag-gated; when unsure, capture `false` (never guess `true`).
- Numeric weight: thread PDFium's weight through `PDFTextRun`/`EditableTextBlock` instead of
  collapsing to bold/regular at name-resolution time.

### 5.3 Apply behavior

- To the open editor (Paste Style button / ⇧⌘V): set family+weight+italic (resolved via the
  §4.5 non-lossy path), size, color, underline, alignment, letter-spacing. **Never touch geometry,
  never set `didApplyMatchedGeometry`.** One workspace-undo step; also push a proper editor-local
  undo entry (stop suppressing registration for *explicit* style actions — keep suppression only
  for the per-keystroke attribute reapply).
- To a clicked block while armed (no editor open): open the editor prefilled (existing path),
  apply the snapshot, keep the editor open for inspection — Done commits, Esc cancels cleanly and
  disarms.
- To new-text defaults: pinned painter + click on empty space seeds the insertion editor's
  starting style.
- Mixed-format targets: single-style blocks today — the snapshot simply replaces the block's
  style; document this in the tooltip ("applies to the whole text box").
- "Match geometry too": separate menu item on the Match Style button retains today's
  bounds/column adoption for the users who want column re-flow — this is the *only* path that may
  set `didApplyMatchedGeometry`.

### 5.4 Safety: not copied by default

Position, width/height, rotation, background masks/patches, redaction fills, `columnBounds`,
locked-object properties, and `sourceBounds` metadata. Highlight/background fill only if a future
explicit "include background" toggle is added (no silent transfer). Rotation transfer only with the
geometry opt-in.

### 5.5 Interaction spec

- Toolbar (editor format bar): paintbrush icon button with three states — idle / armed (filled
  `dsAccent`, matching §7 active-state rules) / pinned (filled + small pin glyph). Single click =
  copy+arm single-use; ⌥-click or double-click = pinned; click while armed = disarm.
- Cursor: custom paintbrush `NSCursor` over the canvas while armed (fallback: crosshair +
  status chip if asset work is deferred).
- Status chip (existing `EditingStatusBanner`): "Style copied — click text to apply · Esc cancels"
  (persistent while armed, not a 3s toast).
- Esc / tool switch / document switch ⇒ disarm (fix `cancel()` leaving armed state).
- Toasts on apply: "Style applied" success (existing message plumbing).
- Shortcuts: ⇧⌘C / ⇧⌘V; add to `ShortcutRegistry` + cheat sheet; also wire the advertised-but-dead
  ⌘B/⌘I/⌘U in the editor's keyDown while at it (audit found them unwired).
- Strikethrough: schema + capture now; if `ReplacementTextLayout` render support (CT attribute +
  manual line draw) doesn't fit the phase budget, hide the control and keep the field dormant —
  never a control that silently no-ops.
- All new strings ×6 languages (`LocalizationCoverageTests` gate).

---

## 6. Toolbar redesign plan

### 6.1 Chosen architecture

**Adaptive priority-tiered toolbar with a single More overflow + existing contextual surfaces.**
Not a command palette (wrong for a direct-manipulation canvas app's primary chrome; fine as a
future ⌘K addition), not a floating mini-toolbar for primary tools (already exists contextually as
the editor format bar — keep that pattern for contextual, not global, tools). Rationale in §13.

### 6.2 Information architecture

| Cluster | Contents | Placement |
|---|---|---|
| Navigation/view | Contents (TOC), zoom/page pill, reader mode | leading + trailing |
| Selection/editing | select, edit text | center capsule |
| Text/markup | comment, comment-region, highlight, underline, strikeout, eraser, note, ink, color | center capsule (grouped) |
| Insert/sign | signature, stamp | center capsule |
| Search | search | trailing |
| Export/share | export menu (export/print) | trailing |
| Panels | inspector toggle | trailing |
| Comfort | eyeglasses popover | trailing |
| Settings/more | More menu: page ops, print, guide, shortcuts, settings, about | trailing (last) |

Changes from today:
- **Delete the bare `Divider()` toolbar item** (`ContentView.swift:455`) — the "-". Use
  `ToolbarItemGroup` spacing / a `ToolbarSpacer`-style gap instead of a drawn dash.
- **Fold `ZoomPageBar` into the toolbar** as one compact pill: `− / % readout (menu: fit, 50–400%)
  / +` plus `page n / N` field. Remove the second chrome row entirely (form bar stays contextual;
  `BottomBarBrand` moves out of daily chrome). Frees ~28px of vertical space for the document.
- **Move `ShortcutsCheatSheetButton` and `GuideButton` into More** (keep their auto-show-once
  behavior by presenting from the toolbar anchor). Trailing cluster drops from 11 items to 7:
  undo, redo, search, export, inspector, eyeglasses, More.
- **Capsule stays** (it's the app's signature element) but tighten: dividers only between logical
  clusters (3 max), `groupDivider` horizontal padding 6→4, and give `.none` (select) the leading
  slot rather than a lone divided island.

### 6.3 Responsive behavior (collapse order)

Window width tiers (measured at the toolbar, accounting for open panels — inspector 280pt +
sidebar both reduce available width):

1. **Full ≥ ~1200pt effective:** everything above.
2. **Medium:** capsule keeps all tools; trailing cluster merges export+inspector+eyeglasses
   candidates never merge — instead undo/redo collapse first (they remain in the app menu/⌘Z);
   defined order: undo/redo → eyeglasses (into More) → export (into More).
3. **Small:** capsule falls back to its existing `compactToolMenu` single button (already built);
   trailing = search, zoom pill (page field hidden, just −/+), More.
4. **Reader/presentation mode:** capsule filtered (existing `isReaderModeAllowed`), zoom pill +
   search + More only.

Implement with `ViewThatFits` variants of the trailing group (same pattern as the capsule) —
no custom width math, no NSToolbar `>>` overflow reliance.

### 6.4 Visual system standards

| Token | Value |
|---|---|
| Toolbar button hit size | 28×28 (unchanged; document as `ToolbarIconMetrics.hitSize`) |
| Icon glyph | SF Symbol 14pt semibold, monochrome (13pt only for optically-heavy glyphs — keep a per-symbol optical table, not ad-hoc) |
| Corner radius | 7 continuous — **add `dsRadiusControl = 7` to DesignSystem** so it's on-scale |
| Group spacing | 8pt between items, 12pt between clusters, dividers only inside the capsule |
| Active fill | `dsAccent`, icon `dsOnAccent` (new token; today reuses `dsSurface`) |
| Hover fill | `dsAccentSoft` (or tool-specific soft tints) |
| Pressed | scale 0.96, 0.12s ease-out |
| Disabled | 35% opacity (unchanged) |
| Focus ring | `.focusable()` + `dsAccent` 2pt ring on keyboard focus (missing today) |
| Tooltip delay | 400ms (unchanged), bubble 190pt fixed, localized |
| Menus/popovers | anchored to button frame, same r7, `dsSurface` bg, `dsSeparator` hairline |
| Motion | new DS tokens: `dsMotionFast=0.12s easeOut`, `dsMotionMedium=0.18s easeOut`, `dsMotionSpring=(0.31, 0.79)`; all gated by one shared `\.dsReduceMotion` environment value (see §8) |

### 6.5 Targeted bug fixes

1. **"-" control:** delete the bare `Divider()` item (`ContentView.swift:455-456`). If visual
   separation is still wanted, rely on cluster spacing. Also compact the zoom "−/fit/+" into the
   pill (§6.2) so no lone dash-like control remains in top chrome.
2. **Active-fill bleed (inspector + eyeglasses + reader):**
   - Add `.clipShape(RoundedRectangle(cornerRadius: ToolbarIconMetrics.cornerRadius,
     style: .continuous))` on `ToolbarIconButton`'s ZStack so no fill can render past the r7 shape.
   - Stop animating the fill's insertion: drive it as an always-present layer with animated
     *opacity* (`.opacity(isActive ? 1 : 0)`) instead of conditional insertion — kills the
     transition-driven bleed under `withTransaction`.
   - Neutralize the system chrome mismatch: on the macOS 26 SDK give these items
     `.sharedBackgroundVisibility(.hidden)` / `.buttonStyle(.plain)` treatment so the *only*
     visible active shape is ours (verify per-OS with screenshots; if glass chrome cannot be
     hidden, invert: adopt the system toggle on-state and drop the custom fill on 26+).
   - Restore the rounded `contentShape` after `acceptsImportDrops` (it currently overwrites with
     `Rectangle`).
3. **Icon normalization:** route Export/More `Menu`s and `ShortcutsCheatSheetButton`/`GuideButton`
   (until they move to More) through one shared component set — extract `ToolbarIconButton`,
   `ToolbarIconMenu` (menu wrapper with hidden indicator + identical hover/active treatment),
   `ToolbarIconMetrics`, `ToolButtonStyle` from `ContentView.swift` into
   `Orifold/DesignSystem/ToolbarControls.swift`. `AppToolbar.swift` stub gets deleted or becomes
   the home of `mainToolbar`.

---

## 7. Design system rules (permanent, add to DesignSystem.swift doc header + review checklist)

1. No button/control animation may render outside its container; every active/hover fill is
   `clipShape`d to the control's shape.
2. Active states animate opacity/scale of persistent layers — never view insertion/removal — so
   transitions can't escape bounds.
3. Icon visual weight is normalized via a per-symbol optical-size table, not raw point sizes.
4. Toolbar groups use 8/12pt spacing tokens; drawn dividers only inside grouped capsules.
5. Text-edit surfaces are transparent by default; any opaque fill under document content is
   opt-in, sampled from the page, and visible in preview before commit (WYSIWYG).
6. Background/erase fills never silently fall back to pure white.
7. Selection = outline + handles outside the content box; selection chrome never occludes
   neighboring document content.
8. Dropdowns/popovers align to the toolbar grid (anchor = button frame, radius = control radius).
9. Every tooltip/label/chip string goes through `L10n` (6-language gate).
10. Keyboard focus ring visible on all toolbar controls; focus order follows visual order.
11. On-accent foreground uses `dsOnAccent`; contrast ≥ 4.5:1 in both appearances.
12. One `\.dsReduceMotion` environment value (system ∥ NSWorkspace ∥ comfort setting) consumed by
    every animation, including AppKit CATransactions.

---

## 8. Accessibility & localization plan

- **Keyboard-only editing:** editor reachable/dismissable by keyboard (Esc cancel, ⌘⏎ done —
  exists; verify), Tab traverses format bar controls in visual order via an
  `NSAccessibilityElement` container (today: none), resize/move handles get accessibility
  labels + `AXValue` adjustments (only the move handle has a label today,
  `ReadingCanvas.swift:4106`).
- **Screen reader:** editor open announces detected text + editability chip; painter arm/disarm
  and apply post `NSAccessibility.post(.announcementRequested)`; toolbar buttons keep
  label+hint+`isSelected` traits (exists on SwiftUI side).
- **Format painter states:** armed/pinned exposed as accessibilityValue on the painter button;
  cursor change is never the only signal (chip + button state).
- **Reduced motion:** consolidate the ~10 copy-pasted checks into one environment value; route the
  AppKit editor's CATransaction animations (`ReadingCanvas.swift:4004-4020`) through it.
- **High contrast:** chrome observes `accessibilityDisplayShouldIncreaseContrast` (bump separator
  + fill alphas); active toolbar fill/icon pair verified ≥4.5:1 in light/dark/high-contrast; the
  high-contrast *page mode* stays as-is.
- **Localization:** every new key ×6 languages (CI-gated); dropdown/menu widths fit longest
  translation (test de-facto longest: hi/ja labels); tooltips localized (already routed through
  L10n).
- **RTL:** app UI languages are LTR today; keep leading/trailing (not left/right) layout in all
  new SwiftUI so future RTL is cheap. Text *content* alignment handling in the editor is
  script-agnostic already.
- **Undo menu titles:** action names resolve at registration; keep (known limitation), but new
  actions must use L10n keys so at least fresh registrations localize.

---

## 9. Performance guardrails

- No new dependencies. Everything above uses PDFKit/PDFium/CoreText/Vision already vendored.
- **No full-page regeneration while typing.** Live preview = AppKit layers only; `regeneratedPage`
  runs exactly once per commit (unchanged). The no-op guard prevents commit work when nothing
  changed.
- Debounce live `measuredBounds` preview at ~80ms; it's CoreText-only (no page raster).
- `sampledBackgroundColor` runs at most twice per edit session (preview open + commit verify) per
  erase rect — cache per (pageRef, rect) in the editor session.
- Painter capture/apply is O(1) struct copy; engine alignment/underline extraction runs inside the
  existing per-page analysis pass and is cached in `textAnalysisCache`.
- Toolbar: `ViewThatFits` variants are cheap; keep animations transform/opacity-only
  (GPU-composited), no layout-driven animation on hover.
- Overlay teardown: editor removes notification observers in `deinit` (exists) — add a leak test
  (open/close editor 100×, assert deallocation via weak ref).
- Export stays deterministic: same ops in, same bytes out (golden tests tolerate metadata dates
  only).
- Known-but-deferred perf debt (do not touch this round, do not regress): per-edit full-member
  re-serialize; full-byte undo snapshots; per-page PDFium re-init under global lock.

---

## 10. Testing plan

New targets: `PDFEditedPageRendererTests`, `InlineTextEditorGeometryTests`,
`TextStyleSnapshotTests`, plus fixture corpus `Tests/OrifoldTests/Fixtures/textedit/`
(resume-like two-column PDF, tinted-band PDF, rotated-90, scanned, multi-line paragraph).

**Text editing**
- Edit a line with a neighbor 4pt below → committed page: no patch pixel outside source line rects
  (golden-image diff).
- Edit a heading; commit; reopen; re-edit — geometry stable, no patch growth.
- Multi-line paragraph edit → line pitch preserved (existing `testOriginalLinePitch` hook).
- Single-line edit → baseline within 0.5pt of original (new baseline test).
- Cancel edit → zero operations, zero visual delta, painter state unchanged.
- Commit unchanged text → zero operations (no-op guard).
- Undo/redo after edit, after move, after style paste.
- Export → reopen in PDFKit: no rect fill objects outside expected patch areas; text extractable.
- Tinted-background fixture: patch color == sampled band color, never `1,1,1` white
  (assert on content stream fill color).
- `wholePageFallbackBlock` commit: patch area ≤ edited text bounds (giant-erase regression).
- Move box 1px and release at origin → no destination erase (flag unlatch test).
- Selection handles visible and outside content box (view hierarchy assertions).

**Format Painter**
- Copy heading style (bold, colored, centered — synthetic fixture) → apply to body line: family,
  numeric weight, size, color, alignment, underline all match; target `bounds` unchanged;
  `didApplyMatchedGeometry == false`.
- Copy from an *edited* block → captures the visible replacement style, not the pre-edit original.
- Apply once → disarmed; pinned mode → stays armed across 3 applies; Esc disarms; tool switch
  disarms; cancel disarms (regression on `cancel()` leaving armed).
- Undo after apply reverts style only.
- Mixed-format source → captures dominant style, status message says so.
- Apply across pages (copy page 1, apply page 3).
- ⇧⌘C/⇧⌘V wired; no collisions (run through `ShortcutsCheatSheet` + menu audit).
- Legacy `PDFTextEditFormat` JSON decodes into split style/geometry (migration test).

**Toolbar**
- Snapshot tests at 1440/1100/900/700pt widths, sidebar open/closed, inspector open/closed:
  correct tier collapse, no clipped items, no `>>` system overflow.
- Active inspector/eyeglasses/reader states: snapshot inside 28×28 r7 — zero fill pixels outside
  the clip shape (pixel-diff on the button region), light + dark + increased-contrast.
- No bare Divider item present (view-tree assertion).
- Hover/pressed/focus states render; focus ring visible via keyboard Tab.
- Longest-locale labels (hi/ja) in menus — no truncation.
- Reduced-motion (all three sources) → no animated transitions.
- More menu open/close: no layout shift of neighboring items.

**Regression sweep (existing flows)**
Import → add text → draw → highlight → comment → search → export → reopen → undo/redo → language
switch (6) → light/dark/high-contrast page modes → signature placement → form bar →
`LocalizationCoverageTests` green.

---

## 11. Acceptance criteria

1. Editing text never shows an opaque white rectangle: live editor background is the sampled page
   background clipped to source line rects; editor chrome is outline+handles only.
2. Edited text never covers neighboring content unless the user explicitly moved/resized onto it —
   and then only with the warning chip shown.
3. Exported PDF contains no patch outside source line rects (+1pt) and destination rects that
   genuinely required cover; never pure white on non-white paper.
4. Copying "Cloud & DevOps" style onto "AI & Data" transfers family, weight, size, color,
   alignment, underline — and does not move, re-wrap, or erase around the target.
5. Painter supports single-use and pinned; Esc/tool-switch/cancel disarm; armed state has visible
   button state + persistent chip + cursor.
6. Undo/redo covers edits, moves, resizes, and every style application.
7. Toolbar is one chrome row (ZoomPageBar folded in); trailing cluster ≤7 items; the bare Divider
   "-" is gone.
8. Inspector/eyeglasses/reader active fills are pixel-clipped to the r7 button shape in all
   appearances; no animation renders outside it.
9. All toolbar glyphs render at the normalized metric via the shared components (including Menus).
10. Secondary tools live in More/contextual surfaces; nothing is unreachable at any window width.
11. No measurable regression: commit latency ≤ current, no per-keystroke page regeneration,
    launch/import unchanged.
12. All 6 languages complete (CI gate), VoiceOver labels on editor toolbar + handles, reduce-motion
    respected everywhere including AppKit editor animations.

---

## 12. Implementation sequencing for Sonnet

Commit small units per step (shared repo, concurrent sessions — expect xcstrings merge conflicts;
rebase early). Each phase independently shippable; run the regression sweep at every phase end.

### Phase 1 — Root-cause verification & test scaffold (no behavior change)
- **Objective:** pin current behavior in tests before touching it; re-verify every §1 mechanism.
- **Touches:** `Tests/OrifoldTests/` (new fixtures + renderer/geometry tests asserting *current*
  behavior where correct, `XCTExpectFailure` where broken), no app code.
- **Risks:** none (test-only). Fixture PDFs must be deterministic (generate via CoreGraphics in
  test setup, don't check in binaries where avoidable).
- **Tests:** the §10 scaffold, giant-erase and white-fallback marked expected-fail.
- **Rollback:** delete tests.

### Phase 2 — Text editing fix
- **Objective:** §4.1–4.5: transparent editor, sampled live patch, real content sizing, per-line
  erase, flag decoupling, no silent white, whole-page-block guard, baseline anchoring, WYSIWYG
  commit geometry.
- **Touches:** `ReadingCanvas.swift` (InlineTextEditorOverlay), `PDFEditedPageRenderer.swift`,
  `PDFTextAnalysisEngine.swift` (line bounds for fallback blocks), `WorkspaceViewModel.swift`
  (`applyInlineTextEdit` no-op/commit geometry), shared background-sampler helper, xcstrings
  (warning-chip strings ×6).
- **Risks:** WYSIWYG geometry change can shift existing saved edits' rendering — gate with the
  migration rule "existing operations keep legacy measuredBounds path; only new/re-committed ops
  use preview geometry". Sampled live patch on huge pages — cache per session. Flag unlatching
  must not break legitimate destination erases (covered by tests).
- **Tests:** flip Phase-1 expected-fails to passes; golden diffs; export/reopen.
- **Rollback:** feature-flag `TransparentInlineEditor` (compile-time bool) reverting to white
  patch path; renderer changes are pure functions — revert by commit.

### Phase 3 — Format Painter
- **Objective:** §5 in full (MVP: capture from editor, style-only apply, single-use + pinned,
  Esc/cursor/chip, shortcuts, undo; stretch: eyedropper pick-source, underline/alignment engine
  extraction if not landed in Phase 2).
- **Touches:** `PDFTextEditingModels.swift` (schema split + migration), `ReadingCanvas.swift`
  (painter interactions, keyDown), `WorkspaceViewModel.swift` (armed state lifecycle),
  `PDFTextAnalysisEngine.swift` (alignment/weight extraction), `ShortcutRegistry.swift`,
  `ShortcutsCheatSheet`, xcstrings ×6.
- **Risks:** decoder migration of saved workspaces (test with a pre-change saved file); armed-state
  lifecycle regressions (auto-apply-on-open is *removed* — verify no user-visible flow depended on
  it beyond the painter itself); undo idiom mismatch (use the `InlineTextEditSnapshot` idiom).
- **Tests:** §10 painter block.
- **Rollback:** painter is additive; disable buttons + shortcuts, schema migration is
  forward-compatible (old fields still decoded).

### Phase 4 — Toolbar compaction & active-state fix
- **Objective:** §6: extract shared toolbar components, delete Divider item, clip active fills,
  opacity-driven active layers, fold ZoomPageBar into the zoom/page pill, move
  shortcuts/guide into More, responsive trailing tiers, `dsOnAccent`/motion tokens.
- **Touches:** `ContentView.swift`, new `DesignSystem/ToolbarControls.swift`,
  `ReadingCanvas.swift` (remove ZoomPageBar row), `DesignSystem.swift` (tokens),
  `ShortcutsCheatSheet`/`GuidePopover` (presentation anchor), xcstrings (zoom pill strings).
- **Risks:** macOS 26 glass chrome interaction — verify on 26 *and* on macOS 14/15 (deployment
  target 14) with per-OS conditionals; ZoomPageBar removal must keep zoom notifications and page
  jump working (they're NotificationCenter-driven, placement-independent); auto-show behaviors of
  guide/cheat-sheet must still fire from More.
- **Tests:** §10 toolbar block (snapshots per width/appearance/OS where CI allows).
- **Rollback:** ZoomPageBar fold is one commit — revertable; component extraction is
  behavior-neutral refactor first, visual changes second (two separate commits).

### Phase 5 — Polish & regression pass
- **Objective:** §7 rules audit across the app, §8 a11y (editor accessibility container, shared
  reduce-motion environment, contrast checks), `PDFPageOverlayViewProvider` migration for the
  editor overlay (optional, only if Phase 2 landed clean), dead-code removal
  (`addEditableTextOverlay` FreeText path, `AppToolbar.swift` stub), full regression sweep +
  performance measurement (commit latency, memory across 50 edits).
- **Risks:** overlay-provider migration is the riskiest item here — keep it last, separate commit,
  behind the same feature flag.
- **Rollback:** each item is an independent commit.

---

## 13. Trade-off analysis

### Text editing model

| Option | Pros | Cons | Effort | Recommendation |
|---|---|---|---|---|
| True content-stream editing | Real replacement; old text actually gone; smallest exports; perfect fidelity potential | Very high complexity (CID/subset fonts, Tj/TJ splitting, kerning arrays); corruption risk; months of hardening; PDFium/qpdf write APIs are the sharpest knives in the repo | Very high | Later (investigate for `.direct` only, Phase 5+) |
| Annotation overlay editing | Simple; annotations are portable | Doesn't *edit* — original text still visible unless masked (that mask is the white-box problem again, now viewer-dependent); FreeText appearance varies across viewers; repo already abandoned this path (dead code at `WorkspaceViewModel.swift:4932`) | Low | No |
| **Hybrid replacement (current: redraw + erase + redraw)** | Already built, rotation-safe, undo/persistence integrated; failures are parametric not architectural; deterministic vector output; WYSIWYG achievable | Old glyphs remain under patch (pseudo-redaction, honesty issue); patch visible on complex backgrounds (mitigated by §4.3, warned by §3.C); page-level rebake cost per commit | **Medium (fix-in-place)** | **Yes — fix, don't replace** |
| OCR-assisted overlay | Only option for scanned docs | Wrong tool for text-layer PDFs; Vision cost; already partially served by make-searchable flow | Medium | Only as the existing scanned-page fallback; region-OCR deferred |

### Toolbar design

| Option | Pros | Cons | Effort | Recommendation |
|---|---|---|---|---|
| Static compact toolbar | Simple, predictable | Breaks at small widths/panels open — today's exact failure | Low | No |
| **Adaptive priority-tier toolbar + More overflow** | Everything reachable at every width; deterministic collapse; matches macOS conventions; capsule's ViewThatFits pattern already proven in-repo | Needs defined collapse order + snapshot tests | **Medium** | **Yes** |
| Contextual toolbar (tool-dependent chrome swap) | Minimal chrome | Hides mode entry points; disorienting for a doc editor's primary bar | Medium | Only for secondary surfaces (already have: editor format bar, form bar — keep) |
| Floating mini-toolbar | Great near content | Wrong for global tools; occlusion management cost | Medium | Keep only as the existing editor-attached format bar |
| Command palette (⌘K) | Power-user speed | Doesn't reduce visible chrome; discoverability-only layer | Medium | Future addition, out of scope |

---

## 14. Final recommendation

- **Text editing model:** keep the **hybrid replacement** engine; make the *editing state*
  transparent and the *erase patch* honest (per-line, sampled color, no silent white, flags
  decoupled, WYSIWYG commit). This converts the white-box bug class into a designed, warned,
  minimal-footprint mask — without a rewrite.
- **Format Painter:** Word-style **capture-visible-style / apply-style-only** painter with
  single-use + pinned modes, armed cursor + persistent chip, Esc disarm, ⇧⌘C/⇧⌘V. The one-line
  load-bearing change: **style paste must never adopt source geometry or set
  `didApplyMatchedGeometry`.**
- **Toolbar:** **adaptive priority-tiered single-row toolbar** — Divider item deleted, ZoomPageBar
  folded into a zoom/page pill, shortcuts/guide into More, all controls through shared clipped
  components with `dsOnAccent` + motion tokens.
- **Order:** exactly Phases 1→5 above; Phase 2 (text editing) before Phase 3 (painter) because the
  painter fix depends on the flag decoupling; toolbar (Phase 4) is independent and can parallelize
  with 3 if two sessions run.
- **Highest-risk parts:** (1) commit-geometry WYSIWYG change interacting with previously saved
  edits — gate by op age; (2) macOS 26 glass chrome vs custom active fills — verify on both OS
  generations with pixel tests; (3) `PDFTextEditFormat` schema migration — decode-legacy test
  mandatory; (4) removing auto-apply-on-open painter behavior — confirm no flow depends on it.
- **Quality bar for Sonnet:** no phase merges without its §10 test block green + the regression
  sweep + `LocalizationCoverageTests` (all 6 languages) + zero new pixels outside clip shapes in
  the button snapshot tests + golden-image export diffs. When a cited line number has drifted,
  re-locate by symbol name and update this doc's checklist in the same PR. Never ship a control
  that silently no-ops, and never let any fill — patch or button — render where the user hasn't
  been shown it will.
