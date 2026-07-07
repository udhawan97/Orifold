# Pet Polish — Sonnet Implementation Handoff

**Status:** Active spec, ready to implement. SVG asset work is ALREADY DONE — this covers only the remaining in-app code.
**Date:** 2026-07-07
**Supersedes:** `PET_VARIANTS_AND_INTRO_PLAN.md` (variants/restorations dropped by owner decision).

## What's already done (do not redo)

The marketing SVGs (`docs/assets/orifold-dog-wag.svg`, `docs/assets/orifold-cat-twitch.svg`, mirrored in `docs-site/public/assets/`) were refined through three committed loops and finalized:

- **Loop 1 — structure & depth** (`c67d053`): layered tails (underside folds, two-facet cream tips), Gami's hind haunch + rear paw + ear-tip fold-back, Ori's hip folds + layered/serrated ruff, occlusion shadows where parts overlap, fold creases, toe creases.
- **Loop 2 — texture & material** (`899ba20`): washi paper-grain overlays (feTurbulence at ~5% alpha, clipped to *non-animated* parts only), three-stop gradient ramps, edge lighting on lit fold edges, specular sheen on the heads.
- **Loop 3 — polish & character** (`0cf5563`): reworked eyes (Gami: warm iris glint; Ori: slate-blue Siberian irises with pupil slivers), doubled catchlights, lid/brow creases, gradient noses with highlights, rim lights, extra whiskers with dark under-lines, lynx-tuft inner folds, tighter grounding shadows.

Sonnet's job: **(A)** enlarge the in-app pets so this motion/detail is visible, and **(B)** echo a bounded set of these details into the in-app Canvas figures.

---

## Task A — Enlarge the in-app pets (+ intro showcase)

### A1. Size tokens (`Orifold/DesignSystem/DesignSystem.swift`)
- `.gamiChipCompact`: **56 → 64**
- `.gamiChipHover`: **88 → 96**
- `.gamiChipCramped`: **44 — unchanged**

These feed `PetView.compactContainerSize/hoverContainerSize` automatically. The hint bubble spacing already derives from `hoverGrowthDelta` + `popoverGap`, so no bubble math changes — but re-verify the resolver QA items below.

### A2. Welcome (intro page) sizing — and fix the dead hover code
In `PetView` (`Orifold/Pet/PetBuddy.swift`, MARK: Sizing):
- `compactContainerSize(for: .welcome)`: **64 → 80**
- `hoverContainerSize(for: .welcome)`: replace the `* 1.15` with **96**.
- **Known dead code to fix:** `supportsHoverExpansion` is `presentation == .workspace && !isCramped` (PetBuddy.swift ~line 709), so the welcome pet **never actually hover-expands** today. Change to `!isCramped && (presentation == .workspace || presentation == .welcome)` — but give the welcome pet a **`.center` scale anchor** (the workspace chip uses `.bottomTrailing` because it's docked in a corner; the intro pet sits in an open HStack and should grow symmetrically). The anchor is currently hardcoded in the `scaleEffect(currentScale, anchor: .bottomTrailing)` modifier — make it presentation-dependent.
- The welcome pet shows no hover *tip* (guarded by `presentation == .workspace` in `handleHover`) — keep it that way; only the scale applies.

### A3. Launch showcase (welcome only)
On the intro page, the pet should launch enlarged so its detail/motion is seen, then settle:
1. On `PetView.onAppear` when `presentation == .welcome`: start at the hover size (96) — a `@State private var isShowcasing = true`.
2. Schedule a single cancellable `DispatchWorkItem` at **+5.0 s** that sets `isShowcasing = false` inside `withAnimation(.spring(response: 0.5, dampingFraction: 0.82))`.
3. `currentScale` composes multiplicatively already (hover × pulse); add the showcase factor the same way: `showcase = isShowcasing ? hoverScale : 1`, and take `max(hover, showcase)` rather than multiplying them (hovering during the showcase must not exceed 96).
4. Cancel the work item in `onDisappear` (follow the existing `hoverShowWorkItem` pattern).
5. **Reduced motion** (`shouldReduceMotion`, which already includes the NSWorkspace check): skip the showcase entirely — start at rest size, no scale animation; hover falls back to no-scale as it does elsewhere.
6. The layout must not jump: `scaleEffect` doesn't change layout size (established pattern in this file), so the greeting card next to it stays put. Verify the enlarged pet doesn't clip against the empty-state edges at 96 pt — if it does, bias the anchor toward the side with room.

## Task B — Echo the SVG detail into the in-app Canvas figures

Bounded additions to `Orifold/Views/OrifoldFoldMark.swift` — **geometry data only; zero renderer changes**. Match the SVG loops, translated to each figure's 0–1 unit space. Budget: ≤ 6 new facets, ≤ 4 new creases, ≤ 1 new occlusion **per figure**.

### B1. `PaperFigure.dog` (Gami)
1. **Tail cream tip, two facets:** split the existing single cream tip facet into a lit face + a turned-under `berneCream`-shaded facet (mirror the SVG's 68,188/86,196/74,205 + 74,205/86,196/80,213 construction at the unit-space tail tip ~(0.22, 0.51)).
2. **Ear-tip fold-back:** one small warm-brown facet (`overridePalette: .innerEarDog`) at the near ear's lower tip (~0.28–0.31, 0.47–0.50), suggesting the paper flipping to show its underside.
3. **Rear paw tab:** one small `berneCream` quad peeking from under the haunch at (~0.30–0.38, 0.82–0.85).
4. **Creases:** one extra floppy-ear crease on the near ear; one blaze-edge crease pair is already implied by facet edges — add a single low-strength (≤0.3) crease along the blaze's right edge.
5. **Occlusion:** one new `PaperOcclusion` under the chin/chest junction (center ~(0.50, 0.55), radius ~0.08, group `.body`).

### B2. `PaperFigure.cat` (Ori)
1. **Ruff inner layer:** two small `berneCream`-based facets with lower `hi/lo` (shaded cream) tucked under the jaw between the existing ruff quads and the chest (mirror the SVG's inner-ruff quads), painted before the bright ruff quads.
2. **Serrated ruff points:** two small hanging triangles below the ruff quads (one per side).
3. **Tail underside sliver:** one darker facet (`siberianSmoke` override or low `hi/lo`) along the tail root's lower edge.
4. **Creases:** one per ruff side (the fold between inner and outer layer), strength ~0.4.
5. **Occlusion:** one under the ruff onto the chest (center ~(0.50, 0.58), radius ~0.07, group `.body`).

**Do not** attempt grain/texture in Canvas (the renderer has no noise primitive and adding one is out of scope), and do not touch eye geometry — the in-app eyes already read correctly at chip size, and iris detail would vanish below 96 pt.

Verify both figures at **44 / 64 / 80 / 96 pt**, light + dark, blossom intro replay, idle wags, reduce-motion static path. Anti-lookalike checks still hold at 44 pt.

## Constraints & do-not-touch

- No changes to: `FoldMarkRenderer` / `FoldState` / wag system internals, `GamiPlacementResolver` / `GamiExclusionContext` / `GamiHintBubble`, `PetSpecies` (raw values, storage keys), copy/L10n (no new strings needed — this is purely visual), the switch-hint/sibling-line logic, the finalized SVGs.
- No new timers beyond the one showcase work item; no steady-state observers; no raster assets.
- All existing tests must stay green; SwiftLint 0 errors; `LocalizationCoverageTests` unaffected.

## QA checklist (run the full loop TWICE, fixing between)

1. `swift build && swift test` + `swiftlint lint --quiet` (0 errors).
2. Chip at 64 pt rest / 96 pt hover: hint bubble + hover tip still clear the enlarged chip (the `hoverGrowthDelta` offsets are derived — verify visually, and confirm `GamiPlacementResolverTests` still pass since chip frames feed the resolver).
3. Cramped mode still 44 pt, no hover growth.
4. Intro: launches at 96 pt, holds 5 s, springs to 80 pt; hover re-enlarges to 96 pt; rapid hover in/out doesn't strand a size; greeting card doesn't shift.
5. Reduce Motion: no showcase, no scale anywhere, fold intro replaced by static settled figure.
6. Both figures at all four sizes, light + dark: new facets render, z-order correct (ruff inner under outer; tail tip facets in order), no stray polygons.
7. No performance regression at idle (TimelineView behavior unchanged).
8. Existing PDF workflows untouched (spot-check select/edit/export with the chip enlarged — corner clearance especially at 96 pt hover in a small-but-not-cramped window).

Then commit, merge `origin/main` (resolve any `Localizable.xcstrings` conflict via the order-preserving JSON approach — though this change should touch no strings), and push to main.
