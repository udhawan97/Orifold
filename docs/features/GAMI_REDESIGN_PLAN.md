# Gami Redesign Plan — Companion + Speech Bubble System

**Status:** Implemented — shipped in v0.8.1. Kept here as the design rationale; see `Orifold/Pet/` and `Orifold/Views/OrifoldFoldMark.swift` for the shipped code.
**Date:** 2026-07-06
**Scope:** `Orifold/Pet/PetBuddy.swift`, `Orifold/Pet/PetSpecies.swift`, `Orifold/Views/OrifoldFoldMark.swift` (dog figure), `Orifold/Views/ContentView.swift:289` (overlay mount), `Orifold/Resources/Localizable.xcstrings` (`pet.*` keys), `Orifold/DesignSystem/DesignSystem.swift` (tokens).

Gami is the dog companion. Ori (cat) is untouched by this plan except where shared infrastructure (bubble, positioning, copy system) improves both. `PetSpecies.dog` / `.cat` rawValues must **not** change (persisted identity).

---

## 1. Diagnosis of Current Issues

Grounded in the current code:

1. **Gami is not distinctive.** `PaperFigure.dog` (OrifoldFoldMark.swift:527) is a shiba-style 3/4 profile in uniform warm kraft paper. At the 72 pt workspace chip it reads as "generic origami animal," not a character. There are no markings, no color identity, and the pointed shiba ears + long wedge snout skew sharp/foxy rather than warm.
2. **The companion card is heavy.** `PetView` wraps the figure in an opaque-ish rounded card (`dsSurface` at 0.78–0.94 opacity) with a 1 px border and a large shadow. On a white PDF page the dark-mode card is a hard block; the chip announces itself instead of receding.
3. **The bubble sits on top of document content.** `PetOverlay` is a `VStack` anchored `.bottomTrailing` with `.padding(18)` over the whole workspace (ContentView.swift:289). The bubble grows *upward from the chip*, directly over the bottom-right of the PDF page — exactly where page text, resize handles, and scroll position live. There is **zero** awareness of selection, edit boxes, or toolbar geometry.
4. **Too close to content.** 18 pt from the window edge and only `.dsSM` (8 pt) between bubble and chip; no guaranteed clearance from the PDF page bounds at all.
5. **Layout feels accidental.** Bubble width (`maxWidth: 300`) plus hover-growth spacing hacks (`hoverGrowthDelta + popoverGap` offsets, comments admitting the VStack "has to be told" about scale growth) produce a stack that shifts and jumps. Two different bubbles (event bubble in `PetOverlay`, hover tip in `PetView.overlay`) use the same component but different anchoring math — they can visually land in different spots.
6. **Copy is jokey, not polished.** Lines like the "emotionally support the export button" register as a gag. Fun once; in a professional PDF editor it reads as a debug toy. Random selection from flat arrays also means tone is inconsistent between consecutive messages.
7. **Distraction risk.** Messages fire on *every* throttle-passing feature event (highlight, comment, tag, sign, note, edit, ink, rotate, delete…, 15 event types), plus feedback/inspiration interjections every 7th/15th trigger. During focused editing this is noise. There is no suppression during text editing or selection, no per-message cooldown beyond a global 6 s, and no "don't show tips" (only full hide).

---

## 2. Gami Visual Redesign — Origami Bernedoodle

Replace `PaperFigure.dog` geometry and palette. Same rendering pipeline (facets + creases + occlusion + wags in `FoldMarkRenderer`), so cost stays identical: one `Canvas`, no images.

### Character direction
A seated, front-3/4 **Bernedoodle** in folded paper: rounded forms, floppy ears, black/white patchwork. Warm but composed — a studio origami piece, not a cartoon.

### Geometry spec (for the new `PaperFigure.dog`)
- **Head:** rounder than current — a soft hexagonal fold (wider than tall) replacing the current diamond. Keel crease stays center for the origami read.
- **Ears:** two **large floppy trapezoids** folding *down and outward* past the jawline (current ears are short triangles). Near ear drapes over the cheek with a visible inner fold. Ears are **black** facets — the strongest Bernedoodle signal.
- **Face patches:** head split into black top/side panels and a **white blaze** running down the center of the face into the muzzle — 3–4 facets with the crease lines doing the patch boundaries (origami-authentic: color change at a fold, not painted-on).
- **Muzzle:** short, slightly rounded two-facet wedge (drop the long shiba snout), white paper, small dark rounded nose facet with the existing moist highlight treatment.
- **Eyes:** keep the dark-facet + catchlight approach, but rounder and set slightly wider/lower for a soft, friendly gaze. Optional tiny brow crease for warmth.
- **Body:** compact seated bell (reuse cat's silhouette *family* is fine here since pose differs — 3/4 vs front): **white chest tuft**, black back/saddle facets, one white front paw visible.
- **Tail:** shorter, rounder plume than current, white-tipped black. Keep the existing `PaperWag(group: .tail, …, excitable: true)` — retune pivot to the new tail base, amplitude ~0.22 (calmer than current 0.30), speed ~7.
- **Texture:** existing crease/occlusion/specular system already gives paper shading. Add one extra low-strength crease across each ear so the floppy fold reads.

### New palettes (in `PaperPalette` extension)
- `.berneInk` — soft black (not #000; a warm near-black like `hsl(24, 12%, 16%)` warm / slightly lifted in dark mode) for ears/saddle/patches.
- `.berneCream` — warm white/cream for blaze, chest, muzzle, paw. Must stay visible against `dsSurface` in light mode → rely on crease strokes + occlusion for edge definition, and keep `hi/lo` spread wide enough.
- Reuse `.noseDog`, `.catchlight`.
- Verify both palettes in light + dark schemes (the palette system already takes colorScheme).

### Constraints
- Same facet-count order of magnitude as today (~16 facets, ~8 creases) — no perf change.
- Must read as a dog at 56 pt (new compact size, §3) — test by rendering at 56/72/112 pt.
- The blossom/unfold intro animation must still work: keep group mapping head→`.head`, ears→`.wing`, muzzle/nose→`.neck`, torso→`.body`, tail→`.tail` so `FoldState` staggering needs no changes.
- Update `EmptyStateView` picker card + welcome presentation automatically (they render the same figure).

---

## 3. Container / Label Redesign

### Chip (workspace presentation)
- **Smaller at rest:** compact container 72 → **56 pt**; hover 112 → **88 pt** (still clearly interactive, less looming). Keep `.bottomTrailing` scale anchor.
- **Lighter surface:** replace the current double-background with a single frosted treatment: `.ultraThinMaterial` + `dsSurface` wash at ~0.35 light / ~0.5 dark, 1 px `dsSeparator` hairline at reduced opacity, corner radius `.dsRadiusMd` continuous. Shadow: radius 8, y 3, black 8% light / 20% dark — a paper card resting on the page, not a floating slab.
- Keep at-rest opacity dimming (0.88) and hover glow — they're good.
- **No visible text label on the chip.** The label lives in tooltip + popover header. A resting text label adds permanent visual weight for information the user learns once.

### Label decision
| Option | Verdict |
|---|---|
| “Gami” | Name alone doesn't explain function to new users. Use as the short a11y name. |
| **“Gami · Orifold Guide”** | **Recommended.** Names the character *and* the role; scales across popover header, tooltip, and settings. |
| “Ask Gami” | Verb implies a chat/Q&A feature that doesn't exist — over-promises. Reserve for a future interactive help entry point. |
| “Gami Assistant” | Generic, corporate; "assistant" also implies AI chat. |

Usage:
- Chip tooltip (`.help`): **"Gami · Orifold Guide"** → key `gami.avatar.help`.
- Popover header: title **"Gami"**, subtitle **"Orifold Guide"** (two-line header replaces the plain species-picker title) with a small figure thumbnail.
- Accessibility label on chip: "Gami, Orifold guide". Hint: "Shows tips for editing and exporting."
- Settings/menu strings: "Hide Gami tips", "Show Gami".

### Popover
Keep `PetControlPopover` structure; restyle to the same frosted card recipe, add the header above the species switcher, and add a **"Hide tips"** toggle distinct from "Hide Gami" (§6).

---

## 4. Speech Bubble Redesign

Replace `PetBubble` with `GamiHintBubble`, a single component used by both event messages and hover tips (removes today's dual-anchoring duplication).

**Visual spec:**
- Surface: `.ultraThinMaterial` + `dsSurface` wash (match chip recipe), radius `.dsRadiusMd` continuous, hairline border `dsSeparator` @ 0.6, shadow radius 10 / y 4 / black 10% light, 24% dark. Noticeably lighter than today's `regularMaterial` + heavy shadow.
- **Anchor notch:** a small (10×5 pt) folded-paper triangle pointing at the chip — drawn as a `Path`, same fill as the card. Include it *only* when the bubble is adjacent to the chip (default placement); omit in chip-collapsed or repositioned states where it would point at nothing.
- Optional 14 pt Gami monochrome glyph or "Gami" caption row above the message in `dsTextSecondary` at 10 pt — gives attribution without a heavy header. (Pick one: glyph *or* caption, not both.)

**Typography & metrics:**
- Text: `.dsCaption()` → bump to 12 pt regular, `lineSpacing(3.5)`, `dsTextPrimary`.
- Padding: 12 pt horizontal / 10 pt vertical (`.dsMD`/`.dsSM`-derived tokens).
- **Max width 280 pt**, min width 120 pt; `fixedSize(horizontal: false, vertical: true)` for wrapping. No max line count — long localized strings wrap, never truncate (§8).
- Contrast: verify `dsTextPrimary` on the washed material ≥ 4.5:1 both schemes (add to QA).

**Behavior:**
- `allowsHitTesting(false)` stays for the passive hint; add a small **dismiss affordance** only when a hint is sticky (§6) — in that mode the bubble becomes hit-testable with an ⌫-style close button (24 pt hit target).
- Entrance/exit: opacity + 4 pt rise, spring(response 0.3, damping 0.85). Reduced motion → opacity only (pattern already in place, keep it).
- Auto-dismiss stays timer-based (`displayDuration`), but scale duration with text length: `4.0 + min(3.0, wordCount × 0.12)` seconds so translated longer strings get read time.
- z-order: bubble renders inside the companion overlay layer, above PDF content but **below** popovers/menus/sheets (SwiftUI overlay order already guarantees this; document it and verify with the popover open).

**Spacing guarantees (tokens, add to DesignSystem):**
- `gamiBubbleGap` = 12 pt bubble↔chip.
- `gamiContentClearance` = 24 pt minimum between bubble edge and the visible PDF page rect (§5).
- `gamiEdgeInset` = 16 pt from window edges.

---

## 5. Smart Positioning Rules

Today: none. Plan a lightweight geometry-based resolver — no per-frame work, evaluated only when a hint is about to show (and on resize/scroll while visible, debounced).

### Inputs (exclusion zones), collected as `[CGRect]` in overlay coordinate space
`WorkspaceViewModel`/PDF layer publishes a small struct, `GamiExclusionContext`:
1. **Selection rects** — `PDFView.currentSelection` page-space rects converted via `pdfView.convert(_:from:)`. Updated on `PDFViewSelectionChanged` (already observed for other features), debounced 150 ms.
2. **Active text-edit box** — the inline text-edit overlay's frame + its handle margin (the Smart Text Edit views already know their frame; expose it).
3. **Drag/resize handles** — included in (2)'s inflated rect (+12 pt).
4. **Search highlights** — current search result rect when `SearchView` is active.
5. **Static chrome** — toolbar strip, bottom progress bar (`WorkspaceOperationProgressView`), page-nav controls: constant rects from `GeometryReader` at the overlay level, cheap.
6. **Open menus/popovers** — not tracked geometrically; instead, *suppress* new hints while `isPopoverPresented` or a sheet/menu is open (state check, not geometry).

Only (1)–(4) are dynamic; capture them lazily at show-time — no continuous observation cost when no bubble is visible.

### Resolver algorithm (`GamiPlacementResolver`, pure function → testable)
```
candidates (in order):
  A. above chip, trailing-aligned      (default, notch down)
  B. leading of chip, vertically centered (notch right)
  C. above chip, shifted left up to 96pt
  D. chip-collapsed "hint chip" mode   (no bubble; see below)

score(candidate) = fails if bubble rect (inflated by gamiContentClearance)
                   intersects any exclusion rect or exits window minus gamiEdgeInset
pick first passing candidate; else D.
```
- Chip itself never moves during a session (predictability beats cleverness); only the bubble repositions. Exception: **cramped-window mode** (§6) may dock the chip tighter into the corner.
- **Hint-chip fallback (D):** instead of a bubble, the chip shows a 6 pt accent dot badge + the pulse animation; hovering or clicking the chip then shows the message in the popover. Nothing is ever forced over content.
- **Editing/selection gate:** if the user has an active text selection or an open edit box, *non-critical* hints (everything except `.warning`) are deferred: queue the latest one for up to 20 s; deliver when the gate clears, else drop it. `.warning` uses the resolver like everything else but is allowed to pick candidate D immediately rather than being deferred.
- Re-evaluate placement on window resize and on scroll (NSScrollView bounds-change notification, debounced 200 ms) while a bubble is visible; if the current spot now collides, animate to the next candidate or collapse to D.

This is deliberately rect-math only — no hit-testing, no per-frame observation, O(candidates × zones) at show time.

---

## 6. Interaction Behavior & States

**Default (rest):** chip at 56 pt, 0.88 opacity, idle breath + occasional tail sway (existing idle system). No bubble.

**Hover:** grow to 88 pt (spring 0.28/0.78, existing), tail wag excitement ramps (existing `excitement` param), accent hairline glow. Hover tip appears after the existing 0.35 s dwell **only if** no event bubble is live *and* the resolver finds a valid spot; otherwise nothing. Cursor: pointing hand (existing).

**Active hint (event):** triggered from the existing `PetEvent` hooks, but tightened:
- **Hero moments only by default:** export, save, sign, first-run greeting, warnings, and first-use of a feature (per-feature "seen" flag in `UserDefaults`, e.g. `gami.seen.edit`). The long tail (highlight/comment/tag/note/ink/rotate/delete/addFile/search repeat-events) no longer produces bubbles after first use — the chip does its pulse instead, keeping acknowledgment without words.
- Global throttle: raise `minInterval` 6 s → **45 s** between bubbles; pulse remains un-throttled feedback.
- **Per-line cooldown:** remember last 5 shown line keys (not strings) in memory; never repeat within a session. Drop the current "reroll once" hack.
- Feedback/inspiration interjections: cap at 1 per session each, never during editing.

**Dismissed:**
- Clicking a visible bubble region is currently impossible (`allowsHitTesting(false)`) — keep passive bubbles passive; **Esc-free dismissal happens via timeout**. Sticky hints (warnings) get the close button (§4).
- Popover gains **"Hide Gami tips"** toggle (`gamiTipsEnabled`, default on): tips off = no bubbles ever, chip + popover remain. Existing "Hide Gami" (`petEnabled`) removes everything. Menu-bar command in `AppCommands` mirrors both.
- Dismissing a specific tip category is out of scope; the seen-flags system already prevents repetition.

**Reduced motion:** no wag, no pulse, no scale (already mostly handled via `shouldReduceMotion`); ensure the new notch/rise entrance degrades to opacity-only; hover growth becomes a border-emphasis change instead of scale.

**Cramped window (workspace width < 700 pt or height < 500 pt):** chip drops to 44 pt, hover growth disabled (popover only), bubbles always use hint-chip mode (D). Evaluate via `GeometryReader` size at the overlay.

## 7. Copywriting Guidelines

**Voice:** a calm studio assistant who likes paper. Warm, brief (≤ 12 words English), concrete, at most one light fold/paper metaphor — never a joke *about* the app's buttons. No exclamation stacking, no self-deprecation, no "emotionally support" gags. Every line should either (a) tell the user something useful or (b) mark a real moment (greeting, completed export) with one quiet sentence.

Replacement samples (English source; all localized):

| Key context | Line |
|---|---|
| greeting.1 | “Hi, I’m Gami. I’ll share tips as you work.” |
| greeting.2 | “Welcome back. Your documents stay on this Mac.” |
| export.1 | “Exporting? I can walk you through the options.” |
| export.2 | “Tip: Compact export shrinks file size before sharing.” |
| save.1 | “Saved. Your work stays private, on this device.” |
| save.2 | “Tip: Autosave keeps edits safe between sessions.” |
| edit.first | “Editing text? Zoom in for finer control of handles.” |
| edit.2 | “Tip: press Escape to finish editing a text box.” |
| search.first | “Use ⌘F to jump between matches on any page.” |
| sign.first | “Signatures are created and stored only on your Mac.” |
| onboarding.hint | “I’m here if you need a hand. Click me anytime.” |
| warning.unsaved | “Heads up — this document has unsaved changes.” |

Hover tips shrink to 6 rotating micro-lines of the same voice (e.g. “Need a tip? Click me.”, “Everything stays on your Mac.”). Retire all current `pet.dog.*` gag lines. Ori’s cat lines get a matching tone pass in a later, separate task.

**Review rule for new lines:** must survive the test “would this look fine in Preview.app?” If it winks too hard, cut it.

---

## 8. Localization

Languages: en, es, fr, hi, zh-Hans, ja (all already in `Localizable.xcstrings`; the L10n coverage test requires all six — see `spm-localizable-xcstrings-ci-fix` constraints: tests read via `Bundle.module` + JSON fallback).

- **Key scheme:** migrate user-facing companion strings to a `gami.*` namespace: `gami.greeting.1`, `gami.tip.export.1`, `gami.hover.1`, `gami.menu.hideTips`, `gami.avatar.help`, `gami.a11y.label`, `gami.a11y.hint`, `gami.warning.unsaved`. Shared species-neutral infrastructure keys stay `pet.*` where reused by Ori, or move to `companion.*` if touched anyway. Old orphaned `pet.dog.*` keys are deleted (xcstrings tooling will flag stale keys; the coverage test must be updated in the same commit).
- Keys stay **string literals** at call sites (documented `L10n.string` interpolation pitfall in PetBuddy.swift:24 — preserve that pattern).
- **Expansion budget:** design bubble at max-width 280 pt against the *longest* translation; German isn't shipped but hi/es/fr run ~30–40% longer than en. Rule: no line may exceed 3 wrapped lines at 280 pt / 12 pt text in any language — enforce with a unit test that renders `NSAttributedString` measurement per locale (pure text measurement, no UI test needed).
- CJK (zh-Hans, ja): shorter glyph counts but taller line boxes — `lineSpacing` uses points not em, already safe; verify no mid-word breaks look wrong (CJK wraps anywhere, fine).
- Hindi: taller ascenders/descenders — confirm vertical padding at 10 pt doesn't clip matras; bump to 11 pt if needed.
- No hardcoded strings anywhere new; `PetSpeciesSwitcher` labels, popover header, tooltip, toggle all keyed.
- Buddy name **"Gami" is not translated** (brand name, same in all locales — matches existing treatment of "Orifold"); "Orifold Guide" subtitle *is* translated.

---

## 9. Accessibility

- **Chip:** `accessibilityLabel("Gami, Orifold guide")` (localized), `accessibilityHint` "Shows tips for editing and exporting", traits `.isButton`. Reachable via full keyboard access (it's a `Button`, verify focus ring isn't clipped by `scaleEffect` — test hover-scale + focus together).
- **Bubble announcements:** post new hint text via `AccessibilityNotification.Announcement` (polite — do not move VoiceOver focus). Never announce hover tips (hover is a pointer concept; VO users get the popover instead). Never announce the same line twice per session (per-line cooldown covers this).
- **No focus trap:** bubbles are non-focusable decorations; the popover is the only focusable surface and uses standard `NSPopover` focus-return behavior (already the case).
- **Sticky/warning bubble:** its close button is focusable, labeled "Dismiss tip", Esc also closes.
- **Reduced motion:** covered in §6; additionally the *fold intro replay* on events (`replayToken`) must skip under reduce-motion (verify — `OrifoldFoldMark` already has a static path).
- **Reduce transparency:** material backgrounds must fall back to opaque `dsSurface` (`accessibilityReduceTransparency` environment) — new check, applies to chip, bubble, popover.
- **Contrast:** `dsTextPrimary` on washed material ≥ 4.5:1, secondary caption ≥ 3:1, both schemes, verified with increased-contrast mode on.
- Tips are always non-blocking: they never intercept clicks destined for the PDF (passive bubbles keep `allowsHitTesting(false)`).

---

## 10. Performance / Quality Constraints

- **Rendering:** stay on the existing single `Canvas` + `TimelineView` figure; no images, no Lottie, no layers. New geometry keeps facet count comparable → no cost delta. Idle `TimelineView` already pauses logic when the figure has no wags/motion; verify the timeline is `.animation(paused:)`-gated when the window is occluded/inactive (add if missing).
- **No per-frame positioning:** resolver runs at show-time + debounced resize/scroll only (§5).
- **Timers:** all `DispatchWorkItem`s already cancel in `onDisappear`; the new deferred-hint queue and per-line cooldown must live in `PetBuddy` (single `@MainActor` singleton) with the same cancel-on-hush discipline. Audit: `dismissWorkItem`, hover show/hide items, pulse reset, new deferral item — each cancelled in `hush()`/`disable()`/`onDisappear`.
- **Observation:** selection/scroll notifications subscribed **only while** a hint is visible or pending; unsubscribe on dismiss. Zero steady-state observers beyond what exists today.
- **No layout feedback loops:** bubble placement is computed, then applied as `.position`/offset in the overlay — it must not read its own rendered geometry to reposition (single-pass resolver, `onGeometryChange` only for window/chrome rects).
- Never intercept events over: selection, text editing, drag/resize handles, search nav, export/save, zoom, rotate, page/section navigation — guaranteed structurally because the only hit-testable companion surfaces are the chip and (when sticky) the close button, both in the corner exclusion-safe zone.

---

## 11. Implementation Architecture

Keep the `Orifold/Pet/` module; introduce Gami-branded components incrementally. No storage-key renames (`petEnabled`, `petSpecies`, rawValues `dog`/`cat` all persist).

**Files & components:**
- `Orifold/Pet/PetSpecies.swift` — unchanged enum; `displayName` for `.dog` becomes "Gami" (key `gami.name`), `.cat` stays "Ori".
- `Orifold/Pet/PetBuddy.swift` → state additions:
  - `gamiTipsEnabled` (`@AppStorage "gamiTipsEnabled"`, default true)
  - `seenEvents: Set<String>` (persisted, `gami.seenEvents` JSON)
  - `recentLineKeys: [String]` (in-memory, cap 5)
  - `pendingDeferredHint: (event, expiry)` + gate flags `isUserEditing`, `isUserSelecting` (set by workspace layer)
  - `minInterval` 6 → 45; `displayDuration` becomes computed from line length.
- **New** `Orifold/Pet/GamiHintBubble.swift` — the restyled bubble (replaces `PetBubble`), with `notchEdge: Edge?`, `isSticky: Bool`, `onDismiss: (() -> Void)?`.
- **New** `Orifold/Pet/GamiPlacementResolver.swift` — pure struct: `resolve(bubbleSize:chipFrame:exclusions:container:) -> Placement` where `Placement` is `.aboveChip(CGPoint) | .leadingChip(CGPoint) | .shifted(CGPoint) | .hintChip`. 100% unit-testable, no SwiftUI imports.
- **New** `Orifold/Pet/GamiExclusionContext.swift` — struct + a small collector protocol the workspace layer implements (`selectionRects`, `activeEditRect`, `searchHighlightRect`, `chromeRects`).
- `PetOverlay` (in PetBuddy.swift) → rename `GamiCompanionOverlay` in place; consumes resolver output; hosts chip + bubble via `.overlay` with explicit positions instead of the VStack (kills the hover-spacing hack — `hoverGrowthDelta` bookkeeping goes away because placement is computed from the *hover-scaled* chip frame directly).
- `PetView` → `CompanionChipView` (both species render through it); sizes per §3; keep `HoverSensor`, popover, pulse.
- `OrifoldFoldMark.swift` → replace `PaperFigure.dog` facets/creases/palette; add `.berneInk`/`.berneCream` palettes. No renderer changes.
- `ContentView.swift:289` — mount unchanged except padding token `gamiEdgeInset` and passing the exclusion collector.
- **Tokens** in `DesignSystem.swift`: `gamiBubbleGap`, `gamiContentClearance`, `gamiEdgeInset`, chip size constants.
- **Feature safety valve:** everything ships behind the existing `petEnabled` + new `gamiTipsEnabled`; no separate feature flag needed (redesign replaces, doesn't fork).

**State flow:** workspace layer → sets gate flags + provides exclusion rects → `PetBuddy.trigger(event)` → eligibility (enabled, tips on, seen-flags, throttle, gates) → line selection (cooldown-aware) → resolver → publish `(message, placement)` → overlay renders.

---

## 12. QA Checklist

Layout / collision:
- [ ] Bubble never overlaps selected PDF text (select text near bottom-right corner, trigger export tip).
- [ ] Bubble never overlaps an open inline text-edit box or its handles.
- [ ] Bubble never overlaps drag/resize handles of annotations.
- [ ] Bubble/chip never cover export/save toolbar controls or the operation progress bar.
- [ ] Bubble never covers the active search highlight or search navigation.
- [ ] Hint-chip fallback engages when no candidate placement fits.
- [ ] Chip stays clear of scrollbars at `gamiEdgeInset`.

Workflows:
- [ ] Zoom in/out while a bubble is visible → repositions or collapses, no overlap.
- [ ] Rotate page; navigate pages; navigate sections — no stale bubble placement.
- [ ] During active text editing: non-critical hints deferred; warning hints use hint-chip.
- [ ] Text selection, copy, drag — pointer events never captured by companion layer.
- [ ] Export and save flows end-to-end with tips on and off.

Appearance / a11y / l10n:
- [ ] Light + dark mode: contrast ≥ 4.5:1 body text, chip legible on white PDF page.
- [ ] Reduce Motion: no wag/pulse/scale; opacity-only transitions; fold replay skipped.
- [ ] Reduce Transparency: opaque fallbacks.
- [ ] VoiceOver: chip label/hint correct; hints announced once, politely; no focus trap; sticky close button focusable; Esc dismisses.
- [ ] All 6 languages: no truncation, ≤ 3 wrapped lines, Hindi glyphs not clipped; L10n coverage test green (Bundle.module JSON fallback path).
- [ ] Window at 700×500 and smaller: cramped mode, 44 pt chip, popover-only hints.

Engineering:
- [ ] No timer/work-item leaks (open/close documents ×20, Instruments leaks run).
- [ ] No steady-state observers while idle (no bubble pending).
- [ ] z-order: popover/menus/sheets render above bubble; bubble above PDF.
- [ ] No CPU regression at idle (TimelineView paused when inactive) — compare Activity Monitor before/after.
- [ ] SwiftLint + full test suite green; PDF export smoke test green.

---

## 13. Sonnet Execution Plan (phased)

Each phase compiles, tests green, and is merge-safe on its own. Run `swift build && swift test` + SwiftLint after every phase.

**Phase 0 — Audit (read-only).** Read `PetBuddy.swift`, `PetSpecies.swift`, `OrifoldFoldMark.swift` (dog + renderer), `ContentView.swift` overlay mount, all `pet.*` keys in `Localizable.xcstrings`, the L10n coverage test, and how Smart Text Edit / search expose their frames. Confirm the exclusion-rect sources listed in §5 exist; note gaps.

**Phase 1 — Gami figure.** Replace `PaperFigure.dog` geometry + add `.berneInk`/`.berneCream` palettes per §2. Verify at 44/56/88 pt, light/dark, blossom intro, tail wag, reduce-motion static path. No behavior changes.

**Phase 2 — Container + tokens.** Add design tokens (§4 spacing, §3 sizes). Restyle chip (`PetView` → `CompanionChipView`) and popover; add popover header "Gami / Orifold Guide"; update tooltip + a11y strings (new `gami.*` keys, all 6 languages, coverage test updated).

**Phase 3 — Bubble component.** Build `GamiHintBubble` (notch, sticky variant, length-scaled duration, reduce-motion/transparency fallbacks). Swap both usages (event + hover tip). Still corner-anchored — no resolver yet.

**Phase 4 — Positioning.** Add `GamiPlacementResolver` + `GamiExclusionContext` + workspace collectors; convert `PetOverlay` → `GamiCompanionOverlay` with computed placement; delete the hover-growth spacing hacks; add resize/scroll re-evaluation + hint-chip fallback + cramped-window mode. **Unit-test the resolver** (pure function: overlap cases, edge insets, fallback order).

**Phase 5 — Behavior.** Seen-flags, 45 s throttle, per-line cooldown, editing/selection deferral gates, session caps for feedback/inspiration, `gamiTipsEnabled` toggle (popover + `AppCommands` menu item).

**Phase 6 — Copy + localization.** Replace all Gami lines per §7 in all 6 languages; delete orphaned `pet.dog.*` keys; add the max-3-lines measurement test; keep Ori keys untouched.

**Phase 7 — Accessibility polish.** Announcements, focus ring under scale, sticky-dismiss button, Esc handling, reduce-transparency audit across chip/bubble/popover.

**Phase 8 — QA loop 1.** Run §12 checklist end-to-end; fix findings.

**Phase 9 — QA loop 2 (regression).** Re-run the *workflow* half of §12 after fixes, plus Instruments leaks pass, plus full test suite + lint + PDF smoke test. Then merge to main and push (standing instruction).

**Guardrails for Sonnet:** never rename `PetSpecies` rawValues or `petEnabled`/`petSpecies` storage keys; keep L10n keys as string literals at call sites; keep Ori (cat) visuals/lines untouched; keep every new string in all six languages or the coverage test fails.
