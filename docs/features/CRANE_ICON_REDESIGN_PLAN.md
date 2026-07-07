# Orifold Crane Icon Redesign — Plan & Design Review

**Date:** 2026-07-07 · **Status:** PLAN — awaiting review, no app code changed
**Design assets staged in:** `docs/assets/icon-redesign/` (5 candidates + final + contact sheet)

---

## 1. Audit of the current icon & animation

### What ships today

| Surface | Asset | Problem |
|---|---|---|
| macOS Dock / Finder / installer | `Orifold/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-{16…1024}.png` + `AppIcon.icns` in the installer app | **Raster folded-paper *arrow*, not the crane.** Dates from the rename commit (`c812da4`). The brand mark and the app icon are two different objects. |
| In-app wordmark & About | `Orifold/Views/OrifoldFoldMark.swift` (86 KB, ~1500 lines) — Canvas/TimelineView fold animation; `AppIconMark` (GuidePopover.swift) shows `NSApp.applicationIconImage` | Excellent architecture (replayable clock, reduce-motion, stops ticking at rest) but the **brand run is 1.0 s delay + 4.3 s runtime** — far beyond a premium 700–1200 ms — and it **ends by dissolving the crane into the arrow icon**, a brand discontinuity at the emotional peak of the animation. |
| README hero (×2) | `docs/assets/orifold-crane-fold.svg` | **155 KB** SMIL SVG, **7.6 s infinite loop** (battery-draining, violates our own motion rules), heavy `feDropShadow` + 2×`feGaussianBlur` filters, 30+ gradients. |
| Docs-site hero | `docs-site/src/assets/orifold-crane-fold.svg` inlined raw in `Hero.astro` (+ `HeroReducedMotion.astro` pauses it) | Duplicate copy #2 of the same 155 KB file. |
| Docs-site favicon | `docs-site/public/favicon.svg` | Duplicate copy #3 — and **useless as a favicon**: at t=0 the animation shows a nearly blank tile. In practice `astro.config.mjs` points the favicon at `orifold-app-icon-32.png` — the *arrow* — so the browser tab doesn't match the brand either. |

### Summary of defects
1. **Brand mismatch:** dock icon = arrow; brand mark = crane; fold animation hands off crane → arrow.
2. **Asset duplication:** the 155 KB animated SVG exists 3× with no single source of truth.
3. **Performance:** infinite 7.6 s SMIL loop with blur filters on the README and docs hero; 155 KB favicon.
4. **Static-context failure:** the animated SVG renders near-blank when SMIL doesn't run (favicon, some previews).
5. **Speed:** in-app brand animation is ~5.3 s wall-clock to resolution.

---

## 2. Five design iterations

Produced by a 5-designer → 3-judge (brand / small-size legibility / engineering) → refine → verify pipeline (14 agents). Every candidate: static SVG, 1024 viewBox, ≤ 3.6 KB, 0 filters, tile stays in the Orifold indigo→teal family, crane faces right. See `contact-sheet.png` for all six side by side at 260/64/32/16 px.

| # | Direction | Pros | Cons | Judge total |
|---|---|---|---|---|
| 1 | **Kessho — sculpted facets** (`candidate-a.svg`) evolution of the current brand crane: faceted washi, ridge highlights, red tancho crown, ink eye | Best-modeled paper crane; crisp at 32 px; tiny file (3.5 KB) | Eye + crown read as an *illustrated bird* (swan/woodpecker), not a fold; facets fragment into "mottled lace" at 16 px; stock-illustration pose | 133 |
| 2 | **Hinomaru — sun + silhouette** (`candidate-b.svg`) red sun disc + crisp ivory tsuru overlapping it, facets as tonal cuts only | Only candidate with a real composition *idea*; unmistakable two-shape gestalt at 32 AND 16 px; lightest file (2.0 KB, 6 paths); maximal brand punch | Bottom-right feels empty; head stylized; grey facets recede on red | **152 — winner** |
| 3 | **Kasane — kirigami layers** (`candidate-c.svg`) crane as 4 stacked flat paper planes with occlusion bands | Distinctive shadowbox depth; clean | "Dead in render": reads as mountains/sailboat, not a crane; hanko dot floats detached; worst small-size read | 95 |
| 4 | **Senbazuru — crease constellation** (`candidate-d.svg`) blueprint line-art crane with fold-vertex nodes + red tancho | Most fluent origami vocabulary; elegant; 2.4 KB / 3 gradients | Line art is the wrong tool at 16–32 px (no mass); too quiet next to solid dock icons | 120 |
| 5 | **Origata — folded from the page** (`candidate-e.svg`) document sheet whose corner folds up into a crane | Best brand *story* for a PDF editor | Two competing objects; at 32 px it's "white rectangle + noise" — the crane (the brand subject) loses | 110 |

**Verdict pattern across judges:** composition ideas beat rendering detail at icon sizes. The Hinomaru's two-element gestalt (red sun + white bird) is the only design that survives 16 px while also being the most distinctive at 1024.

---

## 3. Final selected direction — "Hinomaru Tsuru" (refined)

`docs/assets/icon-redesign/orifold-crane-icon.svg` — **2.4 KB, 5 gradients, 0 filters, 10 paths.**

The machine-refined winner failed fresh-eyes verification twice (head/beak facets in light grey dissolved into the red sun at ≤ 32 px; goose-like drooping tail). Final hand-finishing pass rebuilt the silhouette:

- **Classic three-spike tsuru silhouette** — tail spikes up-left, twin wing peaks with a deep notch, slender neck rising up-right into the folded head. This is the geometry people recognize as "origami crane" instantly.
- **All paper crossing the red disc is near-white** (warm ivory `#fffdf9 → #f1ecdf`); shadow facets are *warm* greys (`#dcd6c9…#ece8dd`) so paper never sinks into the teal tile or the red sun.
- **Beak pierces the sun's rim** onto indigo — the most identifying spike lands on the highest-contrast boundary.
- **One red element** (the hinomaru sun, vermilion radial `#ea4b3c → #cb322e` with a subtle dark rim + faint halo) — replaces the tancho dot; red-circle motif kept, maximal restraint.
- Deepened tile (`#192c48 → #2a4a6e → #5da9c2`), hairline inner keyline, soft radial seat shadow (a gradient shape, not a filter).

**Companion asset:** `orifold-crane-icon-small.svg` (629 B, flat colors, thickened neck, no keyline/halo) — the rasterization source for 16/32/64 px so small sizes are drawn *for* small sizes, exactly how Apple ships size-specific icon art.

Evaluation of the final against the six criteria: silhouette ✅ instant at 512→32, gestalt holds at 16; origami identity ✅ (pure fold geometry, no eye, no cartoon anatomy); premium polish ✅ (restraint, one idea, disciplined palette); scalability ✅ (dedicated small variant); brand fit ✅ (tile family, red-circle motif, faces right like today's mark); performance ✅ (2.4 KB static, zero filters).

---

## 4. Implementation plan (safest path, phased — each phase shippable alone)

### Phase 1 — Brand source of truth + generator
- Add `docs/assets/brand/orifold-crane-icon.svg` (master) and `orifold-crane-icon-small.svg` (move from `icon-redesign/` once approved).
- Add `scripts/generate-icons.sh`: rsvg-convert pipeline →
  - AppIcon PNGs: **small variant** for 16/32/64, **master** for 128/256/512/1024;
  - `docs-site/public/assets/orifold-app-icon-{32,128}.png`;
  - installer `AppIcon.icns` via `iconutil`;
  - static `favicon.svg` (= small variant, ~630 B).

### Phase 2 — macOS app icon
- Replace the 7 PNGs in `AppIcon.appiconset` + regenerate installer `AppIcon.icns`. `AppIconMark`/About/dock/cmd-tab follow automatically via `NSApp.applicationIconImage`. No code change.

### Phase 3 — In-app animation retune (`OrifoldFoldMark.swift`)
Keep the architecture (TimelineView + Canvas, replay trigger, reduce-motion skip, clock pause at rest). Change only crane data + brand timing:
- **Retarget crane geometry**: new `PaperFigure.crane` facets/creases derived from the final SVG (normalized 0–1), three-spike pose; drop the ink eye.
- **Add the sun**: the hinomaru disc fades/scales in behind the crane during the bloom (~200 ms), replacing the current "moon disc" note — the red seal moment.
- **Retime the brand run 4.3 s → ~1.05 s**: opening folds 0–500 ms (same three creases, faster, staggered), figure bloom 500–850 ms, sun + highlight sweep 850–1000 ms, sequenced hand-off to the *new crane app icon* completing ~1.05 s. Autoplay delay 1.0 s → 0.3 s.
- Hand-off is now crane → crane-icon: continuity instead of the arrow switcheroo.
- Companions (Gami/Ori) and their idle wags untouched.

### Phase 4 — Web / README / favicon
- **New animated `orifold-crane-fold.svg` v2** (target ≤ 15 KB): one-shot SMIL (`repeatCount="1"`, `fill="freeze"`), ~1.1 s — tile+sun ease in (0–250 ms), crane facets unfold staggered (150–800 ms), ridge highlight sweep (800–1000 ms), frozen end-state pixel-identical to the static master (so t=0-broken previews are gone and it never loops).
- README `<img>` paths unchanged; alt text updated.
- Docs hero: keep raw-inline + existing `HeroReducedMotion.astro` `pauseAnimations()`; add optional 200 ms CSS highlight-sweep hover gated by `prefers-reduced-motion: no-preference`.
- Favicon: `favicon.svg` = static small variant; `astro.config.mjs` favicon → the SVG with regenerated 32 px PNG fallback.

### Phase 5 — Cleanup
- Delete the three 155 KB copies; docs-site copies become generated artifacts of `scripts/generate-icons.sh`.
- Update `docs/assets/MEDIA_MANIFEST.md`; refresh README brand-row caption ("quiet red tancho" → hinomaru sun).

## 5. Exact files that change

| File | Change |
|---|---|
| `docs/assets/brand/orifold-crane-icon{,-small}.svg` | new — single source of truth |
| `scripts/generate-icons.sh` | new — all raster/derived assets |
| `Orifold/Resources/Assets.xcassets/AppIcon.appiconset/*.png` | regenerated (7 files) |
| `Install or Update Orifold.app/Contents/Resources/AppIcon.icns` | regenerated |
| `Orifold/Views/OrifoldFoldMark.swift` | crane geometry + brand timeline retime (crane section + `FoldState.state` brand track constants only) |
| `docs/assets/orifold-crane-fold.svg` | replaced by ≤15 KB one-shot v2 |
| `docs-site/src/assets/orifold-crane-fold.svg` | replaced (generated copy) |
| `docs-site/public/favicon.svg` | replaced by 629 B static small variant |
| `docs-site/astro.config.mjs` | favicon path → SVG |
| `docs-site/public/assets/orifold-app-icon-{32,128}.png` | regenerated from crane |
| `docs-site/src/components/overrides/Hero.astro` | optional hover sweep CSS |
| `README.md` | alt text + brand-row caption |
| `docs/assets/MEDIA_MANIFEST.md` | manifest update |

## 6. Performance & accessibility

- **Static master:** 2.4 KB, 5 gradients, 0 filters, 0 clip-heavy tricks → trivially cheap to rasterize everywhere (rsvg, browsers, Xcode).
- **No infinite loops anywhere** after this plan: README/docs SMIL plays once and freezes; in-app crane stops its clock at rest (already true, kept).
- **Animation budget:** in-app brand run ~1.05 s (within 700–1200 ms), hover micro 200 ms, transform/opacity-only SMIL (no filter animation).
- **Reduced motion:** app — existing `accessibilityReduceMotion` skip stays; docs — `pauseAnimations()` + CSS media query for hover; README — GitHub can't detect it, but a one-shot 1.1 s animation that freezes is the respectful ceiling.
- **Contrast:** ivory-on-indigo ≈ 9:1; ivory-on-vermilion ≈ 3.1:1 (decorative mark, and the highest-value spike — the beak — sits on the indigo boundary by design).
- **Alt labels:** "Orifold — an origami crane crossing a red sun" for README/docs `<img>`/inline `role="img"`; `AppIconMark` gets `.accessibilityLabel("Orifold app icon")`.

## 7. QA checklist

**macOS app**
- [ ] Dock at default + max size; Finder list/gallery; cmd-tab; Spotlight; About popover; Get Info — crane crisp at every size, no arrow anywhere
- [ ] 16/32/64 renders come from the small variant (neck visible, no mush)
- [ ] Empty-state fold animation: resolves ≤ 1.1 s, hands off to crane icon, replay works, Reduce Motion shows static mark instantly
- [ ] Activity Monitor: 0% CPU after mark settles; no jank during fold on Intel + Apple Silicon
- [ ] Installer app icon (icns) matches

**README (GitHub)**
- [ ] Light + dark themes; animation plays once, freezes on the exact static mark; no blank first frame
- [ ] Alt text updated in both hero and brand-row usages

**Docs site**
- [ ] Hero light/dark; `prefers-reduced-motion` shows frozen mark; hover sweep 200 ms only when motion allowed
- [ ] Favicon: browser tab, pinned tab, hard-refresh cache; matches dock icon family
- [ ] Lighthouse: no perf regression from hero asset (155 KB → ≤ 15 KB)

**Brand consistency**
- [ ] App icon, README, docs hero, favicon, in-app mark all resolve to the same final artwork
- [ ] Old arrow icon gone from all surfaces; MEDIA_MANIFEST accurate

## 8. Status

Plan + design assets only. **No app code, icon assets, README, or docs-site files changed.** Implementation starts on approval of the final mark (`docs/assets/icon-redesign/orifold-crane-icon.svg`).
