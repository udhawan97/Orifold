# Toolbar redesign — calm three-zone bar with progressive disclosure (v2, modern polish)

**Target implementer:** Sonnet
**Primary file:** `Orifold/Views/ContentView.swift` (`mainToolbar`, `ToolbarIconButton`, `ToolbarMenuGlyph`, `AnnotationToolPicker`)
**New file:** `Orifold/Views/ToolbarMoreMenu.swift`
**Design owner sign-off:** before/after + modern-polish mockups shown in-session 2026-07-07.

> **v2 note.** v1 established the three-zone layout. v2 adds a coherent motion + material system, per-symbol micro-interactions, and turns the "More" popover into a two-level drill-in surface — all under strict performance guardrails (§5). Nothing here trades frame rate or correctness for polish: every effect animates transform/opacity only, is scoped with `.animation(value:)`, and has a reduce-motion path.

---

## 1. Problem

The nav bar carries ~25 affordances and reads cluttered and cramped:

- **Leading** (2, OS-grouped into one tight pill): Add files `plus.circle`, Contents `list.bullet.rectangle.portrait` — crowd each other and the title.
- **Center** (`.principal`): the `AnnotationToolPicker` capsule — the core editing surface, stays.
- **Trailing** (11): Undo, Redo, │, Reader mode, Search, Inspector, Document comfort, Share menu, More menu, Shortcuts, Guide.

Two separate menus + nine loose buttons give no hierarchy. World-class PDF editors keep a small curated persistent set and push the rest behind one well-designed overflow.

## 2. Design principles

1. **Calm** — persistent controls are the few used on almost every document; everything else is one click away, not zero.
2. **Native + progressive disclosure** — one trailing overflow, not two menus and a loose row.
3. **Discoverability preserved** — the overflow is a *designed* popover with labels, live toggle state, and one-line descriptions, so hidden tools teach themselves.
4. **Modern but quiet** — glass, depth, and spring motion in service of clarity, never decoration. One accent, one elevation on screen, sentence case, no shouting.
5. **No layout shift, no dropped frames** — toggling state or opening the popover never reflows the center capsule; polish is transform/opacity only.
6. **State survives collapse** — the More button tints (+ a small accent dot) when any contained tool is on.

## 3. Iterations

**Layout (v1):** inventory→tier; rejected native-menu dump (loses state/labels), mode-switcher (over-engineers), retractable inline strip (reflows center). Chose curated persistent set + designed More popover.

**Polish (v2), three passes:**
1. **Motion + material system (§4.1)** — pull all durations, easings, materials, and elevation into named tokens so every surface animates identically. Without this, polish drifts into ad-hoc springs that fight each other.
2. **Micro-interactions + symbol life (§4.2)** — SF Symbol state transitions (`book`→`book.fill`), bounce on add, a cursor-following row highlight, an active-state dot that springs in. Small, GPU-cheap, high perceived quality.
3. **Popover as a mini surface (§4.4)** — two-level drill-in (root → Comfort / Outline) with a horizontal push + animated height, a back header, and a real switch. Kills popover-in-popover jank *and* feels like Control Center. Reduce-motion collapses it to an instant swap.

## 4. Final design

### Zones

| Zone | Contents |
|------|----------|
| **Leading** (`.navigation`) | **Add files `+`** only — accent-tinted glass tile, spaced from the title. |
| **Center** (`.principal`) | `AnnotationToolPicker` capsule — unchanged. |
| **Trailing** (`.primaryAction`) | `Undo` · `Redo` │ `Search` · `Share` · `Inspector` · `More(⌄)` |

### 4.1 Motion & material system (build first)

Add a `ToolbarMotion` / `ToolbarSurface` enum next to `ToolbarIconMetrics`. Everything below references these — no inline magic numbers.

```
enum ToolbarMotion {
    static let snappy  = Animation.spring(response: 0.28, dampingFraction: 0.86) // selection, drill-in, dot
    static let gentle  = Animation.easeOut(duration: 0.16)                       // popover height, page slide
    static let micro   = Animation.easeOut(duration: 0.12)                       // hover/press fills
    // Every caller wraps these as `reduce ? nil : ToolbarMotion.snappy`.
}
```

Material / elevation:
- **More popover:** `.regularMaterial` background in `RoundedRectangle(cornerRadius: 16, style: .continuous)`, hairline `.strokeBorder(Color.dsSeparator.opacity(0.6), lineWidth: 1)`, one soft shadow (`color .black.opacity(0.28), radius 24, y 12`; calibrate for light mode). **Exactly one material layer** — never nest a second `.regularMaterial` inside (overdraw + blur cost).
- **Elevation rule:** at most one floating material at a time. If a row opens a sheet (shortcuts) or a separate popover, the More popover dismisses first.
- **Icon tile (rows + Add-files):** 28pt `RoundedRectangle(8, .continuous)`; fill `Color.dsAccentSoft` when the row/action is active, else `Color.primary.opacity(0.06)`; glyph `Color.dsAccent` when active else `Color.dsTextSecondary`.

### 4.2 Micro-interactions (per control)

- **SF Symbol state transitions** — replace hard icon swaps with `.contentTransition(.symbolEffect(.replace))`:
  - Reader mode `book` ↔ `book.fill`, Inspector `sidebar.right` (fill on active). Toggling animates the glyph, not a cross-fade of two views.
- **Add files** — `.symbolEffect(.bounce, value: addTrigger)` (bump an Int on tap) so the `+` gives a tactile confirmation.
- **More button active state** — when `isActive` (reader on OR comfort non-default): tint via the existing pill fill *and* a 6pt accent dot in the top-trailing corner that springs in with `ToolbarMotion.snappy` via `.transition(.scale.combined(with: .opacity))`.
- **Cursor-following row highlight** (popover) — a single capsule/rounded-rect that slides behind the hovered row using `@Namespace` + `matchedGeometryEffect` (the same technique the annotation capsule's selection pill and tooltip already use). One moving layer, not per-row background inserts.
- **Press** — `scale 0.97` on press with `ToolbarMotion.snappy` (already in `ToolButtonStyle`; align the constant).
- **Shared vocabulary** — reuse `AnnotationToolPicker`'s selection `@Namespace` language so the whole toolbar reads as one motion system.

### 4.3 What moves where

| Current item | New home |
|---|---|
| Add files `+` | Leading (restyled primary) |
| Contents / Outline | More → View |
| Undo / Redo | Trailing (kept) |
| Reader mode | More → View (switch row, live state) |
| Search | Trailing (kept) |
| Inspector | Trailing (kept) |
| Document comfort | More → View (drill-in detail page) |
| Share / Export | Trailing (kept) |
| More menu (pages/print/settings/about) | absorbed into More popover |
| Shortcuts cheat sheet | More → Help |
| Guide (Gami) | More → Help |

### 4.4 The "More" popover (`ToolbarMoreMenu`) — two-level drill-in

Trigger: a `ToolbarIconButton`, `systemImage: "ellipsis"`, `isActive` = `viewModel.isReaderMode || !viewModel.documentComfortSettings.isAtDefault`. Tap → `.popover(arrowEdge: .top)`, content `.frame(width: 300)`.

**Navigation model — one popover, internal pages (no popover-in-popover):**

```
enum MorePage: Equatable { case root, comfort, outline }
@State private var page: MorePage = .root
```

- Root and detail pages live in a `ZStack`/switch; transition between them with an asymmetric horizontal push:
  `.transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)).combined(with: .opacity))`, driven by `.animation(reduce ? nil : ToolbarMotion.gentle, value: page)`.
- The popover **height animates** to the current page's content: apply `.animation(reduce ? nil : ToolbarMotion.gentle, value: page)` on the container so `.fixedSize(horizontal:false, vertical:true)` content resizes smoothly.
- Detail pages start with a **back header**: a chevron-left button (`Color.dsAccent`) + page title + optional trailing action (Comfort shows "Reset", enabled only when non-default). Back returns to `.root`; `Esc` also backs out one level before dismissing.
- **Reduce-motion:** transitions become `.identity`; height/page swap instantly. Everything still fully functional.

**Root content** (reusable `MoreToolsRow`: leading tinted icon tile, title, optional subtitle, trailing `.switch(Bool)` / `.chevron` / `.shortcut(String)` / `.none`, action):

- **View**
  - Reader mode — `.switch`, ⌘⇧R, subtitle "Distraction-free reading". Flip springs (`snappy`).
  - Document comfort — `.chevron` → `page = .comfort`, subtitle "Warm tint, spacing, contrast".
  - Outline — `.chevron` → `page = .outline`, subtitle "Jump to sections".
- **Pages** — Rotate left/right, Duplicate, Delete selected (reuse existing overflow logic; keep the empty-selection handling).
- **Document** — Print (⌘P).
- **Help** — Keyboard shortcuts (opens the sheet — dismiss popover first), Orifold guide (opens Guide popover).
- **Footer** — Settings (⌘,), About.

**Comfort detail page:** embed the existing `DocumentComfortPopover` controls inline (reuse, don't rebuild) under the back header. **Outline detail page:** embed the TOC list (from the current `showTOC` popover) inline.

## 5. Performance guardrails (non-negotiable)

- **Transform/opacity/material only** in animation hot paths — never animate layout-affecting geometry per-frame except the deliberate popover-height ease (cheap, one-shot).
- **Single material layer** for the popover; no nested `.regularMaterial`; no `.shadow` stacking.
- **Scoped animation** — always `.animation(_, value:)`, never a blanket `.animation(_)`.
- **No `AnyView`** in rows or pages; use `@ViewBuilder` and the `MoreToolsRow` value type.
- **One moving highlight** via `matchedGeometryEffect`, not N conditional row backgrounds.
- **Reuse namespaces** — don't spin up a new `@Namespace` per row.
- **Symbol effects are GPU-cheap** — fine to use, but gate `.symbolEffect` value bumps so they fire on real state changes only.
- **No `drawingGroup()`** unless profiling proves a win (it forces offscreen rasterization and usually hurts here).
- **Reduce-motion = zero springs**, instant page swaps — verified as a first-class path, not an afterthought.
- Target: no dropped frames opening/closing the popover or toggling any state on the reference machine; the center capsule must not repaint when the popover animates.

## 6. Implementation steps

1. Add `ToolbarMotion` + material/tile constants next to `ToolbarIconMetrics`; refactor existing `ToolbarIconButton`/`ToolButtonStyle` to reference them (align the press-scale + hover constants).
2. New `ToolbarMoreMenu.swift`: `ToolbarMoreMenu(viewModel:…, page binding or internal)`, `MoreToolsRow`, `MorePage`, the drill-in `ZStack`, back header, and inline Comfort/Outline pages (reuse existing views).
3. In `mainToolbar` `.primaryAction`: add the `More` `ToolbarIconButton` after Inspector; delete the old `ellipsis.circle` `Menu`, folding its items into `ToolbarMoreMenu`; remove the Reader-mode, Document-comfort, Shortcuts, Guide trailing placements (their state/sheets stay, invoked from rows).
4. Leading: delete the Contents `ToolbarItem`; restyle Add files as the accent glass tile + `.symbolEffect(.bounce)`; verify spacing from the title and no residual OS pill crowding on macOS 26.
5. Apply the SF Symbol `.contentTransition(.symbolEffect(.replace))` to Reader/Inspector glyphs.
6. Wire keyboard shortcuts so ⌘⇧R, ⌥⌘1, ⌘P still fire even though the controls now live in the popover (attach to hidden `Button`s in the toolbar or keep command definitions).
7. Keep Share visible as its own `ToolbarMenuGlyph` `Menu`.

## 7. Risks / edge cases

- **Localization (blocking):** every new user-facing string (section headers, subtitles, `On`/`Off`, "Reset", "Warmth", "Contrast", "Page tint", "Night mode") must be in `Localizable.xcstrings` for **all 6 languages** or the L10n coverage test fails (prior CI incidents). Reuse existing `toolbar.*`/`more.*` keys for actions; only subtitles + section headers are new. List and translate every key.
- **macOS 26 toolbar grouping** — confirm the single leading item isn't still wrapped in a crowding liquid-glass pill; add explicit padding or a `ToolbarItemGroup` if so.
- **`ViewThatFits` capsule** — center picker unaffected; test the narrow-window compact fallback still appears and the material popover doesn't clip.
- **Reduce-motion parity** — the drill-in, height ease, symbol effects, and the active-dot must all no-op under `accessibilityReduceMotion`.
- **Accessibility** — each row needs an `accessibilityLabel`; switch rows expose `.isToggle`/value; the More button exposes an `accessibilityValue` reflecting active state; keyboard traversal into and within the popover (incl. back on `Esc`) must work; VoiceOver announces page changes.
- **Material contrast** — verify row text and tinted tiles meet contrast over `.regularMaterial` in both light and dark; fall back to a solid `Color.dsSurface` if a translucent popover ever reads muddy over bright PDF pages.

## 8. Acceptance criteria

- [ ] Leading = one uncramped accent glass Add-files tile, bounces on add, clear title spacing.
- [ ] Trailing = Undo, Redo, divider, Search, Share, Inspector, More — nothing else.
- [ ] More opens a `.regularMaterial` popover; Reader/Comfort/Outline/Pages/Print/Help/Settings/About all reachable; shortcuts still fire.
- [ ] More button tints + shows the accent dot when reader mode on or comfort non-default.
- [ ] Comfort and Outline are **drill-in pages** inside the same popover (no second popover), with an animated push + back header; `Esc` backs out one level.
- [ ] Reader/Inspector glyphs use symbol replace transitions; one cursor-following row highlight.
- [ ] Reduce-motion: every spring/slide/symbol effect no-ops; all functions still reachable.
- [ ] No layout shift on any toggle; center capsule doesn't repaint while the popover animates; no dropped frames.
- [ ] Center annotation capsule + compact fallback unchanged.
- [ ] All new strings in all 6 languages; L10n coverage test passes.
- [ ] `xcodebuild -scheme Orifold -destination 'platform=macOS' build` succeeds; visual verify in a running window.

## 9. Out of scope (possible phase 2)

- Thinning the annotation capsule (grouping eraser/strikeout under highlight). The user asked to keep core editing visible, so the capsule stays as-is.
