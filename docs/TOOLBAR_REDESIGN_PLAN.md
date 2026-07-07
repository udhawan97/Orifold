# Toolbar redesign — calm three-zone bar with progressive disclosure

**Target implementer:** Sonnet
**Primary file:** `Orifold/Views/ContentView.swift` (`mainToolbar`, `ToolbarIconButton`, `ToolbarMenuGlyph`, `AnnotationToolPicker`)
**New file:** `Orifold/Views/ToolbarMoreMenu.swift`
**Design owner sign-off:** derived from the before/after mockup shown in-session on 2026-07-07.

---

## 1. Problem

The nav bar carries ~25 affordances and reads as cluttered and cramped:

- **Leading** (2, OS-grouped into one tight pill): Add files `plus.circle`, Contents `list.bullet.rectangle.portrait` — the two icons crowd each other and the title.
- **Center** (`.principal`): the `AnnotationToolPicker` capsule (7–11 tools + color) — this is the core editing surface and stays.
- **Trailing** (11): Undo, Redo, │, Reader mode, Search, Inspector, Document comfort, Share menu, More menu, Shortcuts, Guide.

Two separate menus (Share + More) and nine loose trailing buttons give no visual hierarchy — everything shouts equally. World-class PDF editors (Preview, PDF Expert, Acrobat) keep a *small, curated persistent set* and push everything else behind one well-designed overflow.

## 2. Design principles

1. **Calm** — persistent controls are the few actions used on almost every document. Everything else is one click away, not zero.
2. **Native + progressive disclosure** — a single trailing overflow, not two menus and a loose row.
3. **Discoverability preserved** — the overflow is a *designed popover* with labels, live toggle state, and one-line descriptions, so hidden tools still teach themselves. (This is the "keep the popover to let the user know what it does" requirement.)
4. **No layout shift** — toggling a tool's active state, or opening the popover, must not reflow the center capsule. Fixed hit sizes, opacity-animated fills (already the pattern in `ToolButtonStyle`).
5. **State survives collapse** — the More button itself shows an active tint when any tool it contains is on (reader mode, non-default comfort), so collapsing doesn't hide state.

## 3. Iterations considered

1. **Inventory + tiering** — cataloged all affordances, assigned Tier 1 (persistent) / 2 (secondary) / 3 (rare). Finding: the trailing 11 is the clutter; the leading crowding is a count + spacing issue.
2. **Dump Tier 2/3 into the existing native "More" menu** — cheapest, but a plain `Menu` loses toggle-state visibility ("is reader mode on?") and the "what does it do" explanation. Rejected as not "world-class."
3. **Mode switcher (PDF-Expert style Read / Annotate / Edit segmented control)** — over-engineers Orifold, which isn't strongly moded; fights the existing `AnnotationToolPicker` + its `ViewThatFits` fallback. Rejected as too invasive.
4. **Retractable inline strip** (ellipsis expands a row of icons in place) — sleek but causes horizontal reflow of the center capsule and hidden icons still lack labels. Partial.
5. **Curated persistent set + designed "More" popover (chosen)** — leading collapses to a single primary `+`; trailing becomes `Undo · Redo │ Search · Share · Inspector · More`; "More" opens a custom animated popover with sectioned, labeled, stateful rows. Consolidates both menus, preserves discoverability, reads calm. **This is the spec below.**

## 4. Final design

### Zones

| Zone | Contents |
|------|----------|
| **Leading** (`.navigation`) | **Add files `+`** only. Primary action; give it a subtle accent tint and clear spacing from the title. |
| **Center** (`.principal`) | `AnnotationToolPicker` capsule — unchanged. |
| **Trailing** (`.primaryAction`) | `Undo` · `Redo` │ `Search` · `Share` · `Inspector` · `More(⌄)` |

### What moves where

| Current item | New home |
|---|---|
| Add files `+` | Leading (kept, restyled primary) |
| Contents / Outline | **More popover → View** |
| Undo / Redo | Trailing (kept) |
| Reader mode | **More popover → View** (toggle row w/ state) |
| Search | Trailing (kept) |
| Inspector (sidebar) | Trailing (kept) |
| Document comfort | **More popover → View** (row → comfort controls) |
| Share / Export | Trailing (kept, keep the two menu items) |
| More menu (pages/print/settings/about) | absorbed into the new **More popover** |
| Shortcuts cheat sheet | **More popover → Help** |
| Guide (Gami) | **More popover → Help** |

### The "More" popover (`ToolbarMoreMenu`)

Trigger: a `ToolbarIconButton`-styled button, `systemImage: "ellipsis"`, `isActive` = `viewModel.isReaderMode || !viewModel.documentComfortSettings.isAtDefault` (so collapsed state is visible). On tap → `.popover(arrowEdge: .top)` presenting `ToolbarMoreMenu`, `.frame(width: 300)`.

Sections (each row: leading SF Symbol, title, optional one-line subtitle, trailing state/shortcut/chevron):

- **View**
  - Reader mode — toggle row, shows `On`/`Off` pill, ⌘⇧R. Subtitle: "Distraction-free reading".
  - Document comfort — row, chevron. Subtitle: "Warm tint, spacing, contrast". Opens the comfort controls (see §5 popover-chaining).
  - Outline — row, chevron. Subtitle: "Jump to sections". Opens the TOC (see §5).
- **Pages** (reuse the existing overflow submenu logic)
  - Rotate left / Rotate right / Duplicate / Delete selected (respect empty-selection state as the current More menu does).
- **Document**
  - Print — ⌘P.
- **Help**
  - Keyboard shortcuts — opens `ShortcutsCheatSheetButton`'s sheet.
  - Orifold guide — opens `GuideButton`'s popover.
- Footer
  - Settings — ⌘, · About.

Provide one reusable row view `MoreToolsRow` (icon, title, subtitle?, trailing enum: `.toggle(Bool)` / `.chevron` / `.shortcut(String)` / `.none`, action). Section headers: 11px, `Color.dsTextSecondary`, sentence case.

## 5. Implementation steps

1. **New `ToolbarMoreMenu.swift`.** Build `ToolbarMoreMenu(viewModel:)` + `MoreToolsRow`. Match the app's design tokens (`Color.dsAccent`, `dsSurface`, `dsTextPrimary/Secondary`, `dsSeparator`, `ToolbarIconMetrics.cornerRadius`). Rows are bordered/hover-highlighted list rows, **not** rounded cards (dense-list rule). Respect `accessibilityReduceMotion`.
2. **Wire the trigger** in `mainToolbar`'s `.primaryAction` group: add the `More` `ToolbarIconButton` after `Inspector`; delete the old `ellipsis.circle` `Menu` and fold its items into `ToolbarMoreMenu`.
3. **Move Reader mode, Document comfort, Contents** out of their current toolbar slots into `ToolbarMoreMenu`. Keep their existing `@State`/`viewModel` bindings and keyboard shortcuts (attach the shortcuts to the popover rows via `.keyboardShortcut` on hidden buttons, or keep the shortcuts on the still-present actions — verify ⌘⇧R, ⌥⌘1 still fire).
4. **Leading zone:** remove the Contents `ToolbarItem`; keep only Add files. Restyle Add files as primary — accent-tinted glyph (or a soft accent background like the mockup) and ensure spacing from the title. On macOS 26 the OS groups adjacent `.navigation` items into a liquid-glass pill; with one item the crowding is gone by construction. Verify no residual tight grouping.
5. **Popover chaining (Document comfort / Outline).** Presenting a popover from inside a popover is janky. Use a coordinator: an enum `enum PendingToolbarPopover { case comfort, outline }`, a `@State var pendingPopover`. The row sets `pendingPopover` and dismisses the More popover; on the More popover's dismiss, `DispatchQueue.main.async` presents the target popover from the same trailing anchor. **Fallback if flaky:** make Document comfort and Outline plain rows that toggle their existing `@State` popover bools directly (accept a one-frame flash), or render the comfort controls *inline* inside the More popover via an in-popover page enum (`@State var page: .root | .comfort`) with a back chevron — cleaner, preferred if time allows.
6. **Keep Share visible** as its own `ToolbarMenuGlyph` `Menu` (already refactored). Do not fold Share into More — it's Tier 1.
7. **Delete** the now-unused `ShortcutsCheatSheetButton`/`GuideButton` trailing placements from the toolbar; invoke their presentation from More rows instead (keep the underlying sheet/popover state).

## 6. Risks / edge cases

- **Localization (blocking):** every new user-facing string (section headers, subtitles, `On`/`Off`) must be added to `Localizable.xcstrings` for **all 6 languages** or the L10n coverage test fails (see prior CI incidents). Minimize new strings — reuse existing `toolbar.*` / `more.*` keys for the actions; only the subtitles + section headers are genuinely new. List every new key and translate all 6.
- **macOS 26 toolbar grouping** — verify the single leading item isn't still wrapped in a crowding OS pill; if so, use explicit padding or a `ToolbarItemGroup`.
- **`ViewThatFits` capsule** — the center picker must be unaffected; test the narrow-window compact fallback still appears.
- **Reduce-motion** — popover open + row highlights must honor `accessibilityReduceMotion` (no spring).
- **Accessibility** — each row needs a proper `accessibilityLabel`; the More button needs an `accessibilityValue` reflecting active state; keyboard traversal into the popover must work.
- **Active-state parity** — confirm the More button's `isActive` tint tracks reader mode + comfort so state is never hidden.

## 7. Acceptance criteria

- [ ] Leading shows a single, uncramped, accent-tinted Add files button with clear spacing from the title.
- [ ] Trailing shows exactly: Undo, Redo, divider, Search, Share, Inspector, More.
- [ ] More opens a labeled popover with View / Pages / Document / Help sections; reader-mode + comfort show live state.
- [ ] The More button is tinted when reader mode is on or comfort is non-default.
- [ ] Contents, Reader mode, Comfort, Shortcuts, Guide, page ops, print, settings, about are all reachable from More; their keyboard shortcuts still work.
- [ ] No layout shift when toggling any tool's active state or opening the popover.
- [ ] Center annotation capsule and its compact fallback unchanged.
- [ ] All new strings present in all 6 languages; L10n coverage test passes.
- [ ] `xcodebuild -scheme Orifold -destination 'platform=macOS' build` succeeds; visual verify in a running window.

## 8. Out of scope (note for a possible phase 2)

- Thinning the annotation capsule itself (e.g. grouping eraser/strikeout under the highlight cluster). The user asked to *keep* the core editing features visible, so the capsule stays as-is for now.
