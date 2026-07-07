# Sidebar Redesign Plan — "Tatami Rail"

**Scope:** the left navigation/sidebar panel only (`Orifold/Views/SidebarView.swift`).
**Goal:** a premium, organized, Japanese-modern / origami-themed workspace rail that makes
file drop-in obvious, communicates document state, and adds professional controls without
clutter — while staying fast, native, and easy to maintain.

**Status:** design plan, not implemented. The final section is a copy-paste execution
prompt for the implementing agent.

---

## 1. Diagnosis of the current sidebar

Grounded in `SidebarView.swift` (505 lines), `ContentView.swift:219-229` (hosting), and
`DesignSystem.swift` (tokens).

| # | Issue | Root cause in code |
|---|-------|--------------------|
| 1 | Brand masthead consumes ~35% of visible height but offers **zero actions** | `SidebarBrandMasthead` is icon + tagline + 3 stat pills; no buttons, no affordances |
| 2 | "0 comments" pill is permanent noise | Metrics always render, even at zero |
| 3 | Disclosure chevron floats detached in the List gutter | `DisclosureGroup` inside `listStyle(.sidebar)` puts its indicator outside the row card |
| 4 | File drop-in is invisible until a drag is already in flight | Drop overlay only appears when `isImportDropTargeted`; no persistent affordance |
| 5 | Document row is minimal: extension badge + name + page count | `MemberDocRow` has no thumbnail, no comment count, no status |
| 6 | Only action on a document is hover-trash (+ same in context menu) | No rename, no per-document export, no insert-after at document level |
| 7 | Dead space below the list when few documents | List fills the panel; nothing anchors the bottom |
| 8 | No hierarchy between identity, documents, and actions | Everything is List rows with identical insets |
| 9 | Double padding: rows pad internally *and* via `listRowInsets` | `MemberDocRow` pads `.dsSM`/5 on top of `EdgeInsets(3,10,3,10)` |

What already works and must be preserved:

- Whole-sidebar drop target + per-row insert-after drop (`onImportDrop(providers, targetPageRefID)`).
- `ForEach.onMove` / `.onDelete` document reorder via the view model.
- `ThumbnailStrip` / `ThumbnailCell`: page thumbnails, multi-select, drag-reorder pages,
  rich page context menu (rotate / duplicate / export / insert files after / delete with
  confirmation), comment badges.
- Reduce-motion gating pattern (`reduceMotion || NSWorkspace…accessibilityDisplayShouldReduceMotion`).
- Focus-mode dim overlay applied by ContentView on top of the sidebar.

Also relevant: when the last document is removed, `ContentView` swaps the whole window to
`EmptyStateView` — **the sidebar never renders in an empty workspace**, so it needs no
zero-document empty state of its own.

---

## 2. Research: what belongs in a PDF-editor sidebar

Patterns from Acrobat, Preview, PDF Expert, Foxit, and Notion/Obsidian/Things-class macOS
sidebars:

- **Acrobat / Foxit** — left rail hosts *navigation panels*: page thumbnails, bookmarks,
  attachments, layers. Editing tools never live there; they live in toolbars/ribbons.
- **Preview** — the purest model: sidebar is just thumbnails with drag-to-reorder and
  drag-in-to-insert. Zero chrome. Its weakness: no file-level metadata at all.
- **PDF Expert** — thumbnails + outline + annotations as sidebar *tabs*; per-item actions
  are contextual (right-click), never persistent buttons.
- **Notion / Obsidian / Things** — uppercase tracked section labels, hover-reveal row
  actions, a single quiet "+ New" affordance pinned where the eye ends, overflow "…" menus
  for everything secondary.

Distilled rules applied below:

1. The sidebar answers "**what is in this workspace and where am I**" — structure and
   navigation. Content tools (annotate, search text, reader mode, export) stay in the top
   toolbar, which Orifold already has (`ContentView.mainToolbar`).
2. **One** visible primary action (Add Files). Everything else is hover- or context-menu.
3. Document-level operations (rename, export, remove) are contextual, mirrored between a
   hover "…" menu and right-click, and exposed to VoiceOver as accessibility actions.
4. A persistent, quiet import affordance beats a hidden drag-only target.

---

## 3. Information architecture

```
┌─────────────────────────────────┐
│ A. Workspace card               │  identity + live stats + Add Files + overflow
├─────────────────────────────────┤
│ B. DOCUMENTS ────────── (fold)  │  section label w/ crease rule + expand/collapse-all
│   ▸ Document card               │  mini-thumb, name, meta, hover actions
│     └ page thumbnail strip      │  (existing ThumbnailStrip, kept)
│   ▸ Document card               │
│   …                             │  (scrolls)
├─────────────────────────────────┤
│ C. Drop zone footer (pinned)    │  dashed fold-card: "Drop PDFs or click to add"
└─────────────────────────────────┘
```

- **A** and **C** are fixed; only **B** scrolls. Structure: `VStack(spacing: 0) { WorkspaceHeaderCard; List { … }; SidebarDropZone }` over `Color.dsSurface`.
- The full-sidebar drag-over overlay (accent stroke + message) stays exactly as today.

### Decisions on the candidate feature list

| Feature | Verdict | Rationale |
|---|---|---|
| Add/import PDFs | **Visible** — button in Zone A + drop zone C | The one primary action |
| Drag-and-drop zone | **Visible** — pinned footer (Zone C) | Fixes discoverability |
| Document list + thumbnails | **Visible** — Zone B | Core |
| File/page/comment counts | **Visible, compressed** — one metadata line in A; per-doc line in cards; zeros omitted | Kills pill noise |
| Rename / delete / per-doc export / insert-after | **Contextual** — "…" hover menu + right-click | Rule 3 |
| Duplicate document | **Rejected** | No VM support; per-doc export via `exportPages(member.pageRefs)` covers the real need |
| Search within documents | **Stays in toolbar** (⌘F, `viewModel.isShowingSearch`) | Content tool, not navigation |
| Sort/filter documents | **Rejected for v1** | Manual reorder exists; typical workspaces are <10 docs. Revisit if >8 docs becomes common |
| Group documents into sections | **Rejected for v1** | Same; the DOCUMENTS section + reorder is enough organization at this scale |
| Recently viewed files | **Stays on EmptyStateView** + File ▸ Open Recent | Sidebar lists members of the *open* workspace; mixing external recents muddies the local-first model |
| Reveal in Finder | **Rejected for members** | Imported sources are embedded in the workspace document, not filesystem files. Recents cards already have it where it makes sense |
| Export/share workspace | **Stays in toolbar** (⇧⌘E menu exists) | Duplication = clutter |
| Comments entry point | **Indirect only** — comment counts on cards/pages navigate on click; the Inspector owns the panel | |
| Document health indicators | **Deferred (v2)** | VM tracks `scannedPageCount`/OCR only workspace-wide today; per-doc status needs engine work |
| Unsaved changes indicator | **Rejected** | Document-based app: the window titlebar already shows the native edited state |
| Collapsed icon rail | **Rejected** | `NavigationSplitView` gives native full-collapse via the toolbar toggle; a custom rail fights AppKit behavior for near-zero benefit |
| Settings/overflow menu | **Minimal** — "…" on the workspace card: Expand All / Collapse All, Rename Workspace (only if trivially wired), nothing else | |

---

## 4. Visual layout plan (top to bottom)

### Zone A — Workspace card (`WorkspaceHeaderCard`, replaces `SidebarBrandMasthead`)

- Container: `dsCard` fill at 0.72 opacity, `dsRadiusMd` continuous corners, `dsSeparator`
  hairline, **origami corner fold** at top-trailing (see §7). Padding `.dsMD`.
- Row 1: static fold-mark glyph 22 pt (reuse `OrifoldFoldMark` in its final folded frame, or
  the app icon asset at small size) + workspace title from
  `viewModel.document.workspace.title` — `13 pt semibold serif` (`.dsDisplay(size: 13)`),
  `dsWordmarkTracking`, `lineLimit(1)`, middle truncation. The tagline ("Fold messy
  documents…") moves out of the sidebar entirely — it stays in the Guide popover.
- Row 2: one quiet metadata line, `11 pt`, `dsTextTertiary`, monospaced digits:
  `"2 files · 34 pages · 3 comments"` — zero-valued segments omitted (a workspace always
  has ≥1 file/page, so the line never goes empty).
- Row 3: actions —
  - `[＋ Add Files]` — capsule button, `dsAccentSoft` fill, `dsAccent` label, 12 pt
    semibold; calls the same open-panel path as the toolbar button
    (`configureImportOpenPanel` + `importFilesWithBatchLimit`). Also an
    `.acceptsImportDrops` target like the toolbar buttons.
  - Spacer, then `…` overflow (borderless `Menu`, `menuIndicator(.hidden)`): *Expand All*,
    *Collapse All*. Nothing destructive lives here.
- At min width 200 pt: Row 2 truncates tail; Row 3 keeps the button (it fits; no
  `ViewThatFits` needed anywhere in the new design).

### Zone B — Documents section

- **Section header** (plain row, not a card): `DOCUMENTS` — 11 pt semibold, uppercase,
  `dsLabelTracking`, `dsTextTertiary`, with trailing count (`· 3`). To its right edge, a
  **crease rule**: 1 px horizontal line filled with a `LinearGradient(dsSeparator → clear)`
  — reads as a fold shadow, not a divider.
- **Document card** (`MemberDocRow`, rebuilt — see §6) with the page `ThumbnailStrip`
  nested under it when expanded (kept as-is, indented 12 pt with a 1 px `dsSeparator`
  "spine" line on the left so pages visibly hang off their parent).
- Reorder/delete stay on the `ForEach` (`.onMove`/`.onDelete` — these must remain direct
  children of the `List`).

### Zone C — Drop zone footer (`SidebarDropZone`, new)

Pinned below the List (inside `SidebarView`, so focus-mode dimming still covers it).
See §5.

---

## 5. Drag-and-drop design

Three layers, two of which already exist:

1. **Persistent affordance (new):** the pinned footer card. ~64 pt tall, `dsRadiusMd`
   dashed `dsSeparator` border (`StrokeStyle(lineWidth: 1, dash: [5, 4])`), transparent
   fill, one top-trailing **cut corner** (fold notch — see §7). Content: `plus.rectangle.on.folder` (hierarchical, 15 pt, `dsTextTertiary`) + two lines:
   "Drop files to add" (12 pt medium `dsTextSecondary`) / "PDF, Word, images, more" (10.5 pt
   `dsTextTertiary`). Entire card is a `Button` opening the import panel, and an `onDrop`
   target appending at the end (`onImportDrop(providers, nil)`).
   - Hover: border → `dsAccent.opacity(0.45)`, icon → `dsAccent`. No scale.
   - Drag-targeted: border solid `dsAccent`, fill `dsAccentSoft`.
   - While `viewModel.isImporting`: swap icon for a small `ProgressView` (`.controlSize(.small)`) and the label for "Adding files…" — button disabled.
2. **In-flight overlay (existing, keep):** full-sidebar accent stroke + centered
   material chip ("Drop to import") when `isImportDropTargeted`. Keep the 0.15 s fade,
   reduce-motion gated.
3. **Precision targets (existing, keep):** per-document-row drop inserts after that
   document; page-cell drop reorders pages.

Error path: a failed/unsupported drop already surfaces `viewModel.importError` as an
alert — keep. Additionally flash the drop-zone border `dsErrorAccent` for 1.5 s when an
import error fires while the sidebar is visible (simple `onChange(of: viewModel.importError)`
+ `Task.sleep`; skip the flash under reduce-motion, the alert carries the information).

---

## 6. Document card design

Replace `DisclosureGroup` with a manually managed card (fixes the detached gutter chevron
and the tap/expand gesture conflict):

```
┌──────────────────────────────────────────┐
│ ▸  [mini-thumb]  Invoice-March.pdf     … │   ← "…" and chevron affordances
│    [PDF chip]    12 pages · 3 comments   │
└──────────────────────────────────────────┘
     │ ┌────┐ Page 1
     │ └────┘            ← existing ThumbnailStrip, spine-indented
```

- **Chevron:** 11 pt `chevron.right` in a 20×20 tappable button at the card's leading
  edge, rotating 90° when expanded (`rotationEffect`, 0.15 s, reduce-motion gated).
  Toggles `expandedDocs` only.
- **Mini-thumbnail:** first page of the member's PDF at 32×42 pt, 3 pt radius,
  `dsSeparator` hairline. Generated once via `page.thumbnail(of:)` into `@State`, keyed by
  `member.id`; falls back to the current `FileTypeBadge` glyph box while nil. A **type
  chip** (existing `SidebarFileType` colors, text only, 5 pt font, 2 pt padding, 3 pt
  radius) overlaps the thumbnail's bottom-leading corner — type stays visible since
  imported HTML/DOCX/images all become PDF pages.
- **Title:** 13 pt semibold `dsTextPrimary`, `lineLimit(1)`, middle truncation.
- **Metadata line:** 11 pt `dsTextTertiary`, monospaced digits: `"12 pages · 3 comments"`,
  comments omitted at zero. Needs a small VM helper `commentCount(for member:)`
  (sum of `commentCount(for: pageRefID)` over `member.pageRefs`).
- **Hover actions** (trailing, fade in on hover, `allowsHitTesting(isHovered)`):
  - `…` menu: **Rename**, **Export Document…** (`exportPages(member.pageRefs.compactMap …)`),
    **Insert Files After…** (existing open-panel + `importFilesWithBatchLimit(insertingAfter:
    member.pageRefs.last)`), divider, **Remove** (destructive, disabled when
    `!viewModel.canRemoveDocuments`).
  - The standalone hover-trash button is removed; Remove lives in the menu and context
    menu (one affordance fewer, same reachability).
- **Context menu:** mirrors the "…" menu exactly.
- **Rename:** menu action swaps the title `Text` for a focused `TextField` (submit on
  Return, cancel on Escape via `.onExitCommand`); commits through a new
  `viewModel.renameDocument(_:to:)` that trims whitespace, ignores no-ops/empties, and
  registers undo with the existing snapshot pattern (`registerUndo` at
  `WorkspaceViewModel.swift:1141` — extend the snapshot to carry display names, or
  register a targeted inverse rename; targeted inverse is simpler and sufficient).
- **Selection:** whole-card tap calls `viewModel.selectDocument(member)` (replaces the
  current `simultaneousGesture` workaround). Card is selected when any of its pageRefs is
  the current selection (existing `isSelected` logic).

---

## 7. Japanese / origami visual treatment

Principles: **ma** (negative space does the organizing), **shibui** (quiet, precise
details), paper as the metaphor — folds, creases, spines. All static vector `Path`s and
existing tokens; no new colors, no materials in rows, no shadows in rows.

1. **Corner fold** (Zone A card, and the selected document card): top-trailing 10 pt
   right-triangle notch. Two `Path`s: the "removed" corner filled with `dsSurface`
   (reads as the card being cut), and the fold-back flap filled with
   `dsSeparator`-over-`dsCard` (slightly lighter triangle) — a classic dog-ear at 1× cost.
   Encapsulate as `FoldedCorner(size: 10)` view + `.foldedCorner()` modifier so it's one
   implementation.
2. **Spine accent** (selected document card): 2 pt vertical rounded bar in `dsAccent`
   hugging the leading edge — the folded edge of a sheet. Replaces a heavier full-border
   selection treatment; combined with the existing `dsAccentSoft` fill.
3. **Crease rules** (section header, and between zones A/B and B/C): 1 px
   `LinearGradient(dsSeparator → .clear)` lines instead of uniform dividers.
4. **Wordmark discipline:** serif (`dsDisplay`) appears exactly once — the workspace title
   in Zone A. Everything else is the system sans stack.
5. **Drop zone notch:** the dashed footer card clips one corner at 45° (custom
   `UnevenRoundedRectangle`-like `Shape`, ~8 pt cut) — echoes the fold motif without any
   illustration. **No crane silhouettes, no mascots** in the sidebar; the pet overlay and
   fold-mark animation already carry personality elsewhere. This keeps it professional.
6. **Paper depth** comes only from fills-over-fills (`dsCard` on `dsSurface`) plus
   hairlines — consistent with the "layered paper" feel at zero GPU cost.

---

## 8. Interaction states

| State | Treatment |
|---|---|
| **Card hover** | Fill `dsCard` 0.72 → 1.0, hairline `dsSeparator` → 0.18 opacity variant, hover actions fade in. 0.12 s easeInOut, reduce-motion gated |
| **Card selected** | `dsAccentSoft` fill + 2 pt accent spine + corner fold; title stays `dsTextPrimary` (color alone never encodes selection — spine is the redundant cue) |
| **Page cell hover/selected** | Keep existing `ThumbnailCell` treatments unchanged |
| **Dragging (import)** | Zone C targeted state + existing full-sidebar overlay; row-level insert-after unchanged |
| **Dragging (reorder)** | Native List reorder for documents; existing custom pageRef drag for pages |
| **Empty workspace** | Not a sidebar state — `EmptyStateView` owns the window (documented invariant; do not build one) |
| **Loading** | Thumb placeholders (existing rounded rects); import in flight → Zone C progress state; long operations → existing `WorkspaceOperationProgressView` overlay (unchanged) |
| **Error** | `importError` alert (existing) + optional 1.5 s `dsErrorAccent` border flash on Zone C |
| **Collapsed** | Native `NavigationSplitView` full collapse; no custom rail |
| **Narrow (200 pt)** | Metadata lines truncate tail; title truncates middle; nothing wraps or overlaps |
| **Focus mode** | ContentView's dim overlay covers header + list + footer automatically (all inside `SidebarView`) |

---

## 9. Accessibility & localization

- **Every** new string goes through `L10n` keys in `Orifold/Resources/Localizable.xcstrings`
  with translations for all six languages (`en, es, fr, hi, ja, zh-Hans`) —
  `LocalizationCoverageTests` fails otherwise. Reuse existing keys where they fit
  (`sidebar.pageCount.*`, `sidebar.metric.*` values, remove-document strings).
  New keys (prefix `sidebar.`): `addFiles`, `overflow.expandAll`, `overflow.collapseAll`,
  `section.documents`, `dropZone.title`, `dropZone.subtitle`, `dropZone.importing`,
  `doc.menu.rename`, `doc.menu.exportDocument`, `doc.menu.insertAfter`, `doc.menu.remove`,
  `doc.rename.placeholder`, plus accessibility-label variants and `undo.renameDocument`.
- Plural-sensitive counts use the existing singular/plural key-pair pattern.
- **VoiceOver:** each document card is one combined element — label
  "«name», «n» pages, «m» comments, selected"; `accessibilityAction`s for Expand/Collapse,
  Rename, Export, Remove. Chevron and "…" get explicit labels. Drop zone: label
  "Add files" + hint "Opens a file browser. You can also drag files here." Metadata is
  never conveyed by color alone.
- **Keyboard:** Add Files button is focusable; rename field gets `@FocusState` focus on
  entry, commits on Return, cancels on Escape. Existing List keyboard navigation is
  untouched.
- **Hover-only affordances** always have non-hover equivalents (context menu + a11y
  actions) — maintain the existing pattern.
- **Reduce motion:** every new animation gated by the existing `shouldReduceMotion`
  computed (`reduceMotion || NSWorkspace…` — and mirror ContentView by also honoring
  `viewModel.documentComfortSettings.reduceAnimations`).
- RTL: none of the six languages is RTL; still use leading/trailing (never left/right) so
  the layout stays direction-correct.

---

## 10. Performance guardrails

- Keep `List` + `.listStyle(.sidebar)` (native reorder, recycling). Header and footer live
  **outside** the List — zero scroll cost.
- No `ViewThatFits` anywhere in the new layout (the current masthead's double-layout
  measurement goes away). No `GeometryReader` in rows.
- No `.shadow` in rows, no materials in rows (the transient drag overlay's
  `.regularMaterial` chip is the only material, unchanged).
- Thumbnails: mini-thumb generated once per member at exact display size ×2 for Retina
  (64×84 px request), cached in row `@State`; page thumbs keep the existing
  `task(id:)`-guarded generation. Invalidate on rotate exactly as today (`thumbnail = nil`).
- Animations: only opacity/fill/rotation, ≤ 0.2 s, all reduce-motion gated. Corner folds,
  crease rules, and spines are static Paths.
- `commentCount(for member:)` is O(pages of that member) against an existing dictionary
  lookup — fine at realistic sizes; do not add caching until profiling says otherwise.
- State: no new sources of truth. Document mutations keep flowing through
  `WorkspaceViewModel` (which already handles undo + persistence); the only additions are
  `renameDocument` (VM) and view-local `@State` (`expandedDocs`, hover flags, thumbnails,
  rename buffer). `expandedDocs` staying per-window `@State` is accepted (resets on window
  close — matches current behavior).

---

## 11. Implementation plan (phased, each phase builds & ships)

**Files touched:** `Orifold/Views/SidebarView.swift` (main), `Orifold/ViewModels/WorkspaceViewModel.swift` (rename + comment-count helper), `Orifold/DesignSystem/DesignSystem.swift` (FoldedCorner shape + crease-rule helper only), `Orifold/Resources/Localizable.xcstrings`, `Tests/OrifoldTests/` (new rename tests; L10n coverage picks up new keys automatically).

**Phase 1 — Structure** (biggest diff, no new features):
`SidebarView` becomes `VStack(spacing: 0) { WorkspaceHeaderCard; List(documents); SidebarDropZone }`.
Move masthead out of the List; delete `SidebarBrandMasthead`/`SidebarMetric`; add the
DOCUMENTS section header; rebuild `MemberDocRow` without `DisclosureGroup` (manual
chevron + `if isExpanded { ThumbnailStrip }`), whole-card tap = select. Keep
`.onMove`/`.onDelete`/row `onDrop` wiring identical. Add all new L10n keys (×6 langs) in
this phase so coverage tests pass from the first commit.

**Phase 2 — Document card content:** mini-thumbnail + type chip, metadata line
(`commentCount(for member:)` VM helper), "…" hover menu + mirrored context menu
(Export Document / Insert Files After reuse existing VM/import functions), remove the
standalone trash button.

**Phase 3 — Rename:** `renameDocument(_:to:)` in the VM with targeted inverse undo
(`undo.renameDocument` action name), inline `TextField` swap with `@FocusState`,
Return/Escape handling. Unit tests: rename persists, trims, rejects empty, undo/redo
round-trips.

**Phase 4 — Origami polish:** `FoldedCorner` shape + modifier, crease-rule gradient lines,
selected-card spine, drop-zone corner notch + hover/targeted/importing/error states,
final spacing pass (single source of padding per row — kill the double-padding).

**Phase 5 — A11y + verification:** combined a11y elements + actions, reduce-motion audit
of every `withAnimation`/`.animation` added, `swift build` + full `swift test` (354+
tests; note the Bundle.module/JSON-fallback quirk for xcstrings in SPM test runs), manual
checklist: drop onto header/rows/footer/canvas, reorder docs and pages, rename+undo,
narrow-width (200 pt) truncation, light *and* dark appearance, focus mode dimming,
VoiceOver walk of one card.

**Explicit non-goals (do not build):** icon rail, document groups/sections, sort/filter,
sidebar search field, recents in sidebar, per-document health badges, unsaved-changes dot,
crane illustrations, new colors, any timer-driven animation.

**Known traps for the implementer:**
- `.onMove`/`.onDelete` must stay on the direct `ForEach` child of `List`.
- Row-level `onDrop` (insert-after) must survive the card rebuild.
- Don't reintroduce `simultaneousGesture` — chevron is its own button, card tap selects.
- xcstrings edits must set `"state": "translated"` for every language on every new key.
- The sidebar renders only when ≥1 document exists — never add empty-state UI to it.
- `navigationSplitViewColumnWidth(min: 200, ideal: 260, max: 320)` is unchanged; test at 200.

---

## 12. Copy-paste execution prompt for Sonnet

```
Implement the sidebar redesign specified in docs/features/SIDEBAR_REDESIGN_PLAN.md
("Tatami Rail"). Read that file fully first — it is the source of truth. Summary of the
job:

Rebuild Orifold/Views/SidebarView.swift into three zones over Color.dsSurface:
(A) WorkspaceHeaderCard — replaces SidebarBrandMasthead: fold-mark glyph + workspace
    title (serif 13pt, dsWordmarkTracking), one metadata line "N files · N pages · N
    comments" (11pt tertiary, monospaced digits, zero segments omitted), an "＋ Add Files"
    capsule button (dsAccentSoft/dsAccent) that opens the existing import open-panel
    (configureImportOpenPanel + importFilesWithBatchLimit) and accepts import drops, and a
    "…" menu with Expand All / Collapse All. Card: dsCard 0.72 fill, dsRadiusMd,
    dsSeparator hairline, folded-corner motif.
(B) The document List (listStyle .sidebar) under a "DOCUMENTS · n" section label
    (11pt semibold uppercase, dsLabelTracking, dsTextTertiary, gradient crease rule).
    Rebuild MemberDocRow WITHOUT DisclosureGroup: explicit 20×20 chevron button
    (rotates 90° when expanded, gated by reduce motion) toggling expandedDocs; whole-card
    tap calls viewModel.selectDocument. Card contents: 32×42 first-page mini-thumbnail
    (page.thumbnail, cached in @State, FileTypeBadge-colored type chip overlapping its
    bottom-left; badge glyph as fallback while loading), 13pt semibold title (middle
    truncation), metadata "N pages · N comments" via a new
    WorkspaceViewModel.commentCount(for member:) helper. Hover-revealed "…" menu and
    identical right-click menu: Rename, Export Document… (exportPages over the member's
    pageRefs), Insert Files After…, divider, Remove (destructive, respects
    canRemoveDocuments). Delete the standalone hover trash button. Selected state:
    dsAccentSoft fill + 2pt dsAccent leading spine + folded corner. Keep ThumbnailStrip
    and ThumbnailCell unchanged, indented under the card with a 1px dsSeparator spine.
    CRITICAL: keep ForEach.onMove/.onDelete and the per-row onDrop insert-after wiring
    exactly as they are today.
(C) SidebarDropZone pinned below the List (inside SidebarView): ~64pt dashed
    dsSeparator card (dash [5,4]) with one 8pt cut corner, plus.rectangle.on.folder icon,
    "Drop files to add" / "PDF, Word, images, more" labels. Whole card is a Button
    opening the import panel AND an onDrop target calling onImportDrop(providers, nil).
    States: hover (accent border/icon), drag-targeted (solid dsAccent border +
    dsAccentSoft fill), importing (small ProgressView + "Adding files…", disabled),
    error flash (dsErrorAccent border 1.5s on importError change, skipped under reduce
    motion). Keep the existing full-sidebar drag-over overlay untouched.

Also implement viewModel.renameDocument(_:to:) with trimming, empty/no-op rejection, and
undo via a targeted inverse rename (action name key undo.renameDocument), triggered from
the Rename menu item via an inline focused TextField (Return commits, Escape cancels).

Add FoldedCorner shape + crease-rule helper to DesignSystem.swift. No new colors, no
shadows or materials in rows, no GeometryReader/ViewThatFits in rows, all animations
≤0.2s opacity/fill/rotation and gated by the existing shouldReduceMotion pattern
(also honor viewModel.documentComfortSettings.reduceAnimations).

Every new user-facing string must be an L10n key added to
Orifold/Resources/Localizable.xcstrings with "state": "translated" entries for ALL SIX
languages (en, es, fr, hi, ja, zh-Hans) — LocalizationCoverageTests enforces this. Use
the key list in plan §9. Plural counts follow the existing singular/plural key-pair
pattern.

Accessibility: each document card is one combined VoiceOver element with
accessibilityActions (Expand/Collapse, Rename, Export, Remove); label the chevron, "…",
and drop zone; nothing hover-only may lack a context-menu/a11y-action equivalent.

Work in the 5 phases from plan §11, keeping the build green after each phase. Do not
build any item on the plan's non-goals list. Finish with: swift build, full swift test
suite passing, plus the manual checklist in §11 (drops on header/rows/footer, doc+page
reorder, rename+undo/redo, 200pt width, light+dark, focus mode, VoiceOver spot check).
```
