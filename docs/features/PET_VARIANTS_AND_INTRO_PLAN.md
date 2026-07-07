# Pet Variants + Intro-Icon Experience — Implementation Plan

**Status:** Plan only. No code written. Hand to Sonnet for execution.
**Date:** 2026-07-07
**Author model:** Opus (planning)
**Related plans:** `docs/features/GAMI_REDESIGN_PLAN.md`, `docs/features/ORI_REDESIGN_PLAN.md` (both shipped).

---

## 0. The one thing that changes this whole plan

The prompt asks for two variants per pet:

- Gami: **"Original Gami"** and **"Bernedoodle Gami"**
- Ori: **"Original Ori"** and **"Siberian Cat Ori"**

**Critical reality check from the codebase audit:** the "Bernedoodle Gami" and "Siberian Cat Ori" are *already the shipping defaults*. They were built by **replacing the originals in place**, so the "Original" figures **no longer exist in the current source** — they live only in git history:

| Variant the user calls… | Actually is… | Exists today? | Source to restore from |
|---|---|---|---|
| "Bernedoodle Gami" | current default `PaperFigure.dog` | ✅ shipping | — |
| "Original Gami" | pre-redesign **shiba** in kraft paper | ❌ git only | `git show a29821e^:Orifold/Views/OrifoldFoldMark.swift` (the `static let dog` block) |
| "Siberian Cat Ori" | current default `PaperFigure.cat` | ✅ shipping | — |
| "Original Ori" | pre-redesign **flat-slate front-facing cat** | ❌ git only | `git show c74703a^:Orifold/Views/OrifoldFoldMark.swift` (the `static let cat` block) |

**Good news that de-risks the whole feature:** the palettes those originals used — `PaperPalette.kraft` (shiba) and `PaperPalette.slate` (flat cat) — are **still present in the current file** (lines ~303–304), just unused. So restoring the originals is mostly a copy-geometry-from-git operation with zero palette work.

**Therefore this feature is fundamentally an "offer the classic look back as an alternate skin" feature, not a "design two brand-new pets" feature.** That is much cheaper and lower-risk than the prompt implies, and the plan is scoped accordingly. If the user actually wants *four freshly-designed* figures, that is a different, much larger effort — flagged in §9 Risks.

**Naming recommendation:** internally use a neutral `classic` / `modern` axis (not "original/Bernedoodle"), because "original" is ambiguous (the current default is what most users will have seen "first") and because a shared two-value enum keeps the code clean. User-facing labels can still say "Classic" / "Bernedoodle" and "Classic" / "Siberian" via localization. **Keep the modern redesigns as the default** — they're the polished, on-brand ones this project just invested two full cycles in.

---

## 1. Current-State Audit

### 1a. How pets are modeled today
- **Identity** = `PetSpecies` enum (`Orifold/Pet/PetSpecies.swift`): `case dog` / `case cat`, `String` raw values, persisted via `@AppStorage("petSpecies")` in `PetBuddy`, parsed leniently through `PetSpecies.resolved(from:)` (garbage → `.fallback` = dog). This is deliberately kept separate from transient animation state.
- **Appearance** = `PaperFigure` struct (`Orifold/Views/OrifoldFoldMark.swift`): pure vector geometry (facets/creases/occlusion/wags) drawn in a single SwiftUI `Canvas`. Three static figures exist: `.crane` (brand mark), `.dog`, `.cat`. Resolved via `PaperFigure.forSpecies(_ species: PetSpecies) -> PaperFigure`.
- **Rendering** = `OrifoldFoldMark(size:interactive:figure:replayTrigger:excitement:)`. Every surface (workspace chip, intro, picker cards, popover header) renders through this one view. **No raster assets exist** — pets are 100% Canvas-drawn vectors. This means "pet asset fails to load" is essentially impossible for the figures themselves; the only failure mode is a corrupt *persisted variant string*, which the lenient-parse pattern already handles.

### 1b. Intro-page pet behavior today
- Lives in `EmptyStatePetIntro` → `chosenIntro` → `PetView(presentation: .welcome)` (`Orifold/Views/EmptyStateView.swift:568–631`).
- Welcome pet **compact size = 64 pt**, hover size = 64 × 1.15 = **73.6 pt** (`PetView` sizing, `Orifold/Pet/PetBuddy.swift:984–996`).
- **BUG/GAP:** `supportsHoverExpansion` is `presentation == .workspace && !isCramped` (`PetBuddy.swift:709`). The welcome pet is `.welcome`, so **it never actually hover-expands** — the 1.15× welcome hover size is dead code. The intro pet is effectively a static 64 pt figure with only the ambient breath/idle wag.
- **No launch-showcase behavior at all** — nothing makes it start large and settle. It fades/slides in via `chosenIntro`'s `hasAppeared` spring, at its normal 64 pt.

### 1c. Customization surfaces today
- **First-run picker**: `PetPicker` / `PetPickerCard` on the empty state — dog vs cat only, 76 pt live folding preview, tap-to-replay, a "Choose" button. No variant concept.
- **Popover switcher**: `PetSpeciesSwitcher` inside `PetControlPopover` (workspace chip popover) — dog/cat segmented control.
- **Menu bar**: `AppCommands` has a species `Picker`.
- **Settings window** (`Orifold/Views/SettingsView.swift`): a deliberately-minimal 39-line `Form` with just Language + Appearance pickers. Its doc comment explicitly says it only hosts controls "that already have a real, working implementation" — a pet-variant picker **qualifies** (it has real backing behavior), so it fits the existing philosophy.
- All species changes route through `PetBuddy.selectSpecies(_:)`, which also fires the greeting/sibling-switch line.

### 1d. Limitations this plan removes
1. Only one look per pet; no way to get the classic figures back.
2. Intro pet is visually inert (no launch showcase, no working hover).
3. No settings-level pet control at all — customization is scattered across picker/popover/menu.
4. Welcome hover sizing is dead code.

---

## 2. Proposed UX / Design Plan

### 2a. Intro-page icon hover + launch showcase
Target behavior (from prompt): launch large → hold ~5 s → smoothly shrink to normal → hover re-enlarges smoothly, premium and cheap.

**Design:**
- **Welcome sizes (retuned):** rest **64 pt**, showcase/hover **88 pt** (matches the workspace hover ceiling for visual consistency; enough to reveal ruff/blaze/lynx-tip detail). Anchor the scale at `.center` for the intro (unlike the corner-anchored workspace chip) so it grows symmetrically in the intro's open layout.
- **Launch showcase state machine** (three phases): `.showcasing` (starts at 88 pt on appear) → after **5.0 s** animate to `.resting` (64 pt) with a gentle spring → `.resting` is the steady state. Hovering at any point enters a transient hover-enlarge to 88 pt; un-hovering returns to whatever the base phase dictates (still `.resting`).
- **Motion feel:** one spring for the shrink (`response ≈ 0.5, damping ≈ 0.82`), a snappier spring for hover (`response ≈ 0.3, damping ≈ 0.78`). No continuous animation loops beyond the existing idle breath. The 5 s timer is a single `DispatchWorkItem` (cancellable in `onDisappear`), **not** a `Timer` or animation keyframe — negligible cost.
- **Reduced motion:** skip the scale entirely. Show the pet at rest size 64 pt immediately, no showcase, no hover growth — or, if we want *some* affordance, cross-fade a subtle accent ring on hover instead of scaling. Recommendation: no scale, opacity-only, matching the rest of the app's reduce-motion contract.
- **Detail visibility:** because these are vector Canvas figures, enlarging costs nothing and stays crisp at any size — no bitmap blur. The 88 pt showcase is purely a redraw at a larger `size:`.

### 2b. Variant customization control — where it lives
**Evaluated locations:**

| Location | Verdict |
|---|---|
| **Settings window (⌘,)** | **Recommended primary home.** It's the conventional place for persistent personalization, it already exists and is philosophically scoped to "real controls," and variants are a set-and-forget preference, not an in-the-moment action. |
| Pet popover (workspace chip) | **Recommended secondary.** Add a compact variant row *under* the existing species switcher — power users already open this to switch species; offering the skin here is natural and discoverable. Keep it small (two thumbnails). |
| First-run picker | **Do not add variants here.** First-run should stay a simple dog-vs-cat decision; adding a 2×2 variant matrix on first launch is choice-overload at the worst moment. Users can re-skin later. |
| Menu bar | Leave as species-only. A nested variant submenu is clutter for a cosmetic setting. |

**So: Settings = the canonical picker (with thumbnails); popover = a quick secondary toggle.** Both write the same persisted state.

### 2c. Settings picker design
A new **"Companion"** section in `SettingsView`'s form:
- Two rows, one per species (Gami, Ori), each showing the species name + a horizontal pair of **live `OrifoldFoldMark` thumbnails** (~44 pt each, `interactive: false`) — one per variant — rendered as selectable cards with a selected-state ring in `dsAccent`. Because thumbnails are the real vector figure, they're always in sync with what ships and cost nothing to render.
- Selecting a thumbnail sets that species' variant immediately (live-applies to any visible pet, same `@AppStorage`/observation wiring appearance/language already use).
- Labels: "Gami — Classic / Bernedoodle", "Ori — Classic / Siberian", all localized.

### 2d. Design direction for the figures
- **No new design work required for the shipping defaults** — Bernedoodle Gami and Siberian Ori already meet the "cuddly/playful/warm" and "elegant/curious/fluffy" bars (that was the whole point of the two prior redesign cycles).
- **The "classic" variants** are restorations of the shiba (kraft paper) and flat-slate cat. They already match the origami system (same facet/crease/palette vocabulary). The plan is to restore them faithfully, not redesign them — they're the "vintage" option.
- Keep all four figures within the existing `PaperFigure` vocabulary so the fold-in intro animation, idle wags, and hover excitement all work uniformly with zero renderer changes.

---

## 3. Technical Implementation Plan

### 3a. Variant model (the safe approach)
**Do NOT expand `PetSpecies`.** It's the identity axis (dog vs cat) and is load-bearing across switches, persistence, tests, and copy. Adding `dogClassic`/`dogModern` cases would explode every `switch` and break the `petSpecies` rawValue contract.

**Instead add a parallel `PetVariant` axis:**
```
enum PetVariant: String, CaseIterable, Sendable {
    case modern   // the shipping redesign (default)
    case classic  // the restored pre-redesign figure
    static let fallback: PetVariant = .modern
    static func resolved(from raw: String?) -> PetVariant { ... }  // lenient, mirrors PetSpecies
}
```
- One shared enum, applied per species. `modern` = default so existing users see no change.
- Persist **per species** so each pet remembers its own skin independently:
  - `@AppStorage("gamiVariant")` (dog) and `@AppStorage("oriVariant")` (cat) in `PetBuddy`, each defaulting to `modern`.
  - Expose on `PetBuddy`: `variant(for species: PetSpecies) -> PetVariant` and `setVariant(_:for:)`, mirroring the `species`/`selectSpecies` pattern (observable, `didSet`-persisted, lenient-parsed in `init`).

### 3b. Figure resolution
- Rename/extend the resolver: `PaperFigure.forSpecies(_ species: PetSpecies, variant: PetVariant) -> PaperFigure`.
  ```
  switch (species, variant) {
  case (.dog, .modern):  return .dog          // current Bernedoodle
  case (.dog, .classic): return .dogClassic   // restored shiba
  case (.cat, .modern):  return .cat          // current Siberian
  case (.cat, .classic): return .catClassic   // restored flat-slate
  }
  ```
- Keep the old single-arg `forSpecies(_:)` as a thin wrapper defaulting to `.modern` **only if** it simplifies migration; otherwise update all call sites (there are only a handful: `PetPickerCard`, `PetView.petIcon`, `PetControlPopover` header, `CompanionSwitchHintCard`). Prefer updating call sites so the variant is always explicit.
- **Add two new `PaperFigure` static lets**: `.dogClassic` (paste the shiba geometry from `a29821e^`, palette `.kraft`) and `.catClassic` (paste the flat-slate cat from `c74703a^`, palette `.slate`). Both palettes already exist. Verify the pasted geometry compiles against the *current* `PaperFacet`/`PaperCrease`/`PaperWag` signatures (they've been stable, but the classic Ori predates a couple of wag fields — reconcile `hoverOnly`/`excitable` defaults).

### 3c. Wiring the variant into every render site
Every `OrifoldFoldMark(... figure: .forSpecies(species) ...)` becomes `figure: PaperFigure.forSpecies(species, variant: buddy.variant(for: species))`. Sites:
- `PetView.petIcon` (workspace chip)
- `EmptyStatePetIntro` welcome pet (via `PetView(presentation:.welcome)` — pass variant down or read from `buddy`)
- `PetPickerCard` (first-run preview — shows the **current** variant per species)
- `PetControlPopover` header thumbnail
- `CompanionSwitchHintCard` thumbnails
- new Settings thumbnails (renders **both** variants regardless of selection)

### 3d. Intro showcase implementation
- Add a `.welcome` branch to `supportsHoverExpansion` (currently workspace-only) **or** introduce a dedicated `welcomeShowcase` sizing path in `PetView` gated by a new `@State private var showcasePhase`.
- On `PetView.onAppear` (welcome only): set showcase scale, schedule a 5.0 s `DispatchWorkItem` to drop to rest; cancel in `onDisappear`. Compose with hover the same multiplicative way `currentScale` already composes hover × pulse.
- Reuse the existing `hoverGrowthDelta` bookkeeping only if the intro pet coexists with a floating bubble (it doesn't in the intro layout — the intro greeting is a sibling `HStack`, not an overlay), so no collision math needed here.

### 3e. Asset naming conventions
- **In-app figures:** no files — new static lets `PaperFigure.dogClassic`, `PaperFigure.catClassic`. Keep the `MARK:` section comments describing each ("Classic Gami — the original shiba in kraft paper").
- **Marketing/docs SVGs (optional, only if we surface variants in docs):** follow the existing `orifold-<pet>-<pose>.svg` convention → `orifold-dog-classic.svg`, `orifold-cat-classic.svg`, keeping `orifold-dog-wag.svg`/`orifold-cat-twitch.svg` as the modern defaults. Head marks: `gami-classic-mark.svg` etc. **Docs assets are out of scope for the first implementation pass** unless the user asks — the in-app feature stands alone.

### 3f. State management & persistence summary
- `petSpecies` (existing) — which pet.
- `gamiVariant`, `oriVariant` (new) — which skin per pet, default `modern`, lenient-parsed.
- All via `@AppStorage`, all observable through `PetBuddy`, all live-applying (no relaunch needed), matching the appearance/language precedent.

### 3g. Performance safeguards
- Figures are vector; larger previews = larger `Canvas` draw, still cheap and crisp. No bitmaps, no Lottie.
- The 5 s showcase is one cancellable `DispatchWorkItem`, not a render loop.
- Settings renders 4 static (`interactive:false`, no idle timeline) thumbnails — confirm `OrifoldFoldMark` with a settled figure and no wags doesn't spin a `TimelineView` needlessly (the crane/settled path already guards this; verify for the classic figures whose `idle` arrays differ).
- No new observers in steady state; variant reads are plain property reads.

---

## 4. Files / Components Likely Affected

| File | Change |
|---|---|
| `Orifold/Pet/PetSpecies.swift` | Add `PetVariant` enum (or a new `Orifold/Pet/PetVariant.swift`). |
| `Orifold/Pet/PetBuddy.swift` | `gamiVariant`/`oriVariant` `@AppStorage` + `variant(for:)`/`setVariant(_:for:)`; welcome showcase state in `PetView`; fix `supportsHoverExpansion` for welcome; pass variant into `petIcon`. |
| `Orifold/Views/OrifoldFoldMark.swift` | Add `PaperFigure.dogClassic` + `.catClassic` (restored from git); extend `forSpecies(_:variant:)`. |
| `Orifold/Views/SettingsView.swift` | New "Companion" section with per-species variant thumbnails. |
| `Orifold/Views/EmptyStateView.swift` | `PetPickerCard` + welcome intro render the current variant; welcome pet gets showcase behavior. |
| `Orifold/Resources/Localizable.xcstrings` | New keys (6 languages): `settings.companion.label`, `pet.variant.classic.name`, `pet.variant.modern.name` (or per-pet: `gami.variant.classic/modern`, `ori.variant.classic/siberian`), `pet.variant.accessibility.*`. |
| `Tests/OrifoldTests/OrifoldTests.swift` | Variant persistence + resolution tests; L10n coverage auto-covers new keys. |
| `Orifold/App/AppCommands.swift` | (Optional) leave species-only; no change recommended. |

---

## 5. Edge Cases & Risks

- **Naming inversion (highest-impact):** "Original" = the *classic* restored figure, but the current default is the redesign. Mislabeling will confuse users into thinking the redesign is "new/experimental." Mitigate with clear localized labels ("Classic" vs "Bernedoodle"/"Siberian") and keeping `modern` as default.
- **Classic geometry drift:** the classic Ori predates some `PaperWag` fields; pasted geometry must compile against current structs. Build immediately after paste.
- **Dead-code trap:** the existing welcome 1.15× hover size is unused; don't "preserve" it — replace with the real showcase sizing.
- **Variant × switch-hint / sibling-line interactions:** changing a *skin* must NOT fire the species sibling-switch line (that's for dog↔cat identity changes only). `setVariant` must be a separate path from `selectSpecies`.
- **First-run:** picker previews should show each species' *current* (default `modern`) variant; a fresh install has no stored variant → lenient parse → `modern`. Verify no nil/blank pet.
- **Corrupt persisted variant:** `resolved(from:)` → `modern`. Test with a garbage `gamiVariant` value.
- **Scope risk:** if the user truly wants four *newly designed* figures (not restorations), that's a multi-day design effort, not this plan. Confirm before building.
- **Reduced-motion + showcase:** ensure the 5 s shrink is fully skipped, not just faster, under reduce-motion.

---

## 6. Accessibility & Localization Checklist

- [ ] Settings variant cards are `Button`s: keyboard-focusable, `.isSelected` trait on the active one, focus ring not clipped by any scale.
- [ ] Each thumbnail has a localized `accessibilityLabel` ("Gami, Bernedoodle style, selected") and the group is `accessibilityElement(children: .contain)`.
- [ ] VoiceOver announces variant change politely (no focus stealing).
- [ ] Reduced motion: no intro showcase scale, no hover scale; opacity/ring only.
- [ ] Reduced transparency: thumbnail card backgrounds fall back to opaque `dsSurface` (mirror `GamiHintBubble`).
- [ ] Contrast: selected ring + label meet 4.5:1 in light, dark, and increased-contrast modes; classic kraft/slate figures legible on the settings surface in all three.
- [ ] All labels/tooltips via `L10n.string` string-literal keys; **no hardcoded strings**; 6 languages complete or `LocalizationCoverageTests` fails.
- [ ] Pet name "Gami"/"Ori" not translated (brand); variant words ("Classic", "Bernedoodle", "Siberian") localized.

---

## 7. Testing & Validation Checklist

**Unit (extend `PetBuddyTests` / new `PetVariantTests`):**
- [ ] `PetVariant.resolved(from:)` maps nil/garbage → `.modern`.
- [ ] `variant(for:)` / `setVariant(_:for:)` persist per species independently (setting Gami's skin doesn't touch Ori's).
- [ ] `PaperFigure.forSpecies(_:variant:)` returns the correct figure for all 4 combinations and never the wrong species.
- [ ] Changing a variant does **not** fire the sibling-switch line or greeting.
- [ ] L10n coverage green for all new keys.

**Manual QA:**
- [ ] Intro: pet launches at 88 pt, holds ~5 s, springs down to 64 pt smoothly.
- [ ] Intro: hovering after settle re-enlarges smoothly; un-hover returns to 64 pt; rapid hover in/out doesn't jitter or strand a size.
- [ ] Settings: picking a variant live-updates the workspace chip and intro pet without relaunch.
- [ ] Variant persists across quit/relaunch (both pets independently).
- [ ] Classic Gami (shiba/kraft) and Classic Ori (flat slate) render correctly at 44/64/76/88 pt, light + dark.
- [ ] Popover secondary variant toggle matches Settings and stays in sync.
- [ ] Reduced motion + reduced transparency + increased contrast all clean.
- [ ] No launch-time regression (compare cold-launch to empty state before/after; the 5 s timer must not delay interactivity).
- [ ] Full suite + SwiftLint (0 errors) + PDF smoke test green.
- [ ] Visual regression: default users (no stored variant) still see Bernedoodle/Siberian — no silent skin change.

---

## 8. Step-by-Step Execution Plan (for Sonnet)

Each phase compiles + `swift build && swift test` + SwiftLint green before the next.

1. **Restore classic figures.** Add `PaperFigure.dogClassic` (from `a29821e^`, palette `.kraft`) and `PaperFigure.catClassic` (from `c74703a^`, palette `.slate`) to `OrifoldFoldMark.swift`. Reconcile against current `PaperFacet`/`PaperCrease`/`PaperWag` signatures. Verify all 4 figures render at 44/64/88 pt, light/dark, with working fold-in + idle.
2. **Variant model.** Add `PetVariant` enum (lenient parse, `modern` default). Add `gamiVariant`/`oriVariant` `@AppStorage` + `variant(for:)`/`setVariant(_:for:)` to `PetBuddy`. Extend `PaperFigure.forSpecies(_:variant:)` and update all call sites.
3. **Settings picker.** Add the "Companion" section to `SettingsView` with per-species variant thumbnails, live-applying, fully a11y + localized (new xcstrings keys, 6 languages).
4. **Popover secondary toggle.** Add a compact variant row under the species switcher in `PetControlPopover`, sharing the same state.
5. **Intro showcase + hover.** Fix `supportsHoverExpansion` for `.welcome`; add the launch-large → 5 s → shrink state machine and hover re-enlarge; reduce-motion path. Retune welcome sizes to 64/88.
6. **Tests.** Add variant persistence/resolution tests; verify variant change doesn't fire sibling line; confirm L10n coverage.
7. **QA loop 1 → fix → QA loop 2** (run the §7 manual checklist twice), then commit and merge to main and push (standing instruction), resolving any `Localizable.xcstrings` conflict via the order-preserving JSON-merge approach used in prior cycles.

**Do NOT touch:** `PetSpecies` raw values or the `petSpecies`/`petEnabled` storage keys; the renderer internals (`FoldMarkRenderer`, `FoldState`); `GamiPlacementResolver`/`GamiHintBubble`/`GamiExclusionContext`; the sibling-switch / switch-hint logic; the modern default figures' geometry.

---

## 9. Open Questions to Confirm Before Building
1. **Restore vs. redesign:** does "Original Gami/Ori" mean *restore the pre-redesign figures* (this plan, ~1 day) or *design two brand-new alternate figures* (much larger)? This plan assumes restore.
2. **Default:** keep the modern redesigns as default (recommended) — confirm you don't want "Classic" to be the out-of-box look.
3. **Docs/marketing:** should the variant feature be reflected in README/docs-site + new SVGs, or is the in-app feature enough for now? (This plan treats docs as an optional follow-on.)
