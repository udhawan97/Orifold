# Ori Redesign Plan — A Distinct Companion, Not "the Cat Version of Gami"

**Status:** Plan only. No implementation yet. Hand to Sonnet for execution (§9).
**Date:** 2026-07-06
**Prereq reading:** `docs/features/GAMI_REDESIGN_PLAN.md` (shipped 2026-07-06) — Ori inherits all of the bubble/positioning/behavior infrastructure built there. This plan changes *who Ori is*, not how bubbles work.

**Scope:** `Orifold/Views/OrifoldFoldMark.swift` (cat figure + palettes), `Orifold/Pet/PetBuddy.swift` (hover-tilt parity for Gami, launch hint state), `Orifold/Pet/PetSpecies.swift` (tagline key only), `Orifold/Views/EmptyStateView.swift` (picker copy), `Orifold/Resources/Localizable.xcstrings` (`ori.*` namespace, all 6 languages), `docs/assets/orifold-cat-twitch.svg` + `docs-site/public/assets/` copies (marketing art), README + docs-site (final phase).

**Hard invariants (unchanged from the Gami plan):**
- `PetSpecies` rawValues stay `dog`/`cat`; storage keys `petSpecies`, `petEnabled`, `petSpeciesChosen`, `gamiTipsEnabled` never change.
- L10n keys are string literals at call sites (`L10n.string` interpolation pitfall, documented in PetBuddy.swift).
- Every new string ships in all 6 languages or `LocalizationCoverageTests` fails.
- No new rendering tech: the figure stays a `PaperFigure` (facets + creases + occlusion + wags) drawn in the existing single `Canvas`. No raster images, no Lottie, no per-frame layout.

**A translation note for anyone reading the brief:** the request mentions "SVG/CSS" and "z-index" — this is a native SwiftUI macOS app. The in-app Ori is Canvas-drawn vector geometry (cheaper than SVG parsing); the only actual SVGs are the marketing/docs images. "z-index" concerns map to SwiftUI overlay order, which the Gami redesign already settled (bubble above PDF, below popovers). Sonnet should not introduce webview/SVG rendering in-app.

---

## 1. Character Direction

**Ori is a female Siberian cat, folded from paper.** Where Gami is a warm, chunky, floppy-eared Bernedoodle in near-black + cream, Ori is composed and plush: a dense ruff, a luxurious tail, a calm face that watches rather than waits.

**Archetype split (the one-line brief for every future copy/design decision):**
- **Gami** — golden-hearted apprentice: playful, loyal, excited, encouraging. Moves *toward* you.
- **Ori** — resident studio master: curious, clever, elegant, calm, independent, softly affectionate, charmingly bossy. Lets you come to *her*.

**Related but never confusable.** They share the same paper (both use the cream detail palette — visibly "cut from the same sheet"), the same fold-in intro, the same chip/bubble system. They differ in everything a silhouette carries:

| Axis | Gami | Ori |
|---|---|---|
| Pose | 3/4 profile, leaning in | Front-facing, upright, symmetric |
| Ear | Big floppy trapezoids, down | Tall tufted triangles, up |
| Tail | Short plume, wags side-to-side | Long layered plume, slow curl |
| Face | Round, blaze down the middle | Wide ruffed wedge, masked |
| Motion | Wag, pulse, bounce | Twitch, blink, tilt, sway |
| Voice | "I can help with that." | "I already looked at it." |

Anti-lookalike checks (must pass at 44/56/88 pt): not a rabbit (ears must be *wide-based* triangles with inner-fold detail, never long parallel lobes), not a fox (no long snout — the muzzle stays a short bright wedge), not a rat (ruff keeps the head wide; tail thick, never a line), not a small dog (front-facing symmetry + almond eyes + whisker creases are the instant cat tells).

The current cat (front-facing slate, shipped earlier) is a solid *pose* baseline — the redesign keeps the front-facing family and upgrades it to a Siberian: plusher, marked, more feminine, more premium.

## 2. Visual Redesign

Replace `PaperFigure.cat` geometry (OrifoldFoldMark.swift:677) in place. Same group mapping (head+eyes→`.head`, ears→`.wing`, muzzle/nose/whiskers→`.neck`, torso→`.body`, tail→`.tail`) so the blossom intro animation needs zero renderer changes.

### New palettes (extend `PaperPalette`)
- `.siberianSlate` — a slightly warm, silvery blue-grey (richer than current `.slate`, which reads flat): warm ≈ (0.88, 0.89, 0.95), cool ≈ (0.42, 0.46, 0.60). Becomes the figure's base palette.
- `.siberianSmoke` — a deeper slate for the mask/mantle markings: warm ≈ (0.55, 0.58, 0.70), cool ≈ (0.26, 0.29, 0.40).
- Reuse **`.berneCream`** for ruff/chest/muzzle/paws/tail-tip — the shared cream is the deliberate "siblings from the same paper stock" cue with Gami.
- Keep `.noseCat` (pink), `.innerEarCat` (pink), `.catchlight`, `.craneInk` (eyes).

### Geometry spec (the Siberian upgrades, ~20 facets, ~12 creases — same cost class as today)
- **Ruff (new, the defining Siberian feature):** a wide cream collar of 2–3 kite facets framing the lower face, making the head read wider and plusher than the body — the classic Siberian proportion. This is the single highest-value change.
- **Head:** keep the wide rounded diamond, soften the cheek corners outward slightly (the ruff carries the width). Add a **smoke mask**: two `.siberianSmoke` facets over the crown/outer cheeks with the color change on crease lines (origami-authentic, same technique as Gami's blaze), leaving a cream inverted-V between the eyes.
- **Ears:** keep tall wide-based triangles with pink inner folds; add a tiny cream **lynx-tip tuft facet** at each apex (2 small triangles) — Siberian signature, and one more anti-rabbit cue.
- **Eyes:** keep dark almonds + catchlights, but tilt the outer corners up ~10% and set them a touch wider — calm, knowing, feminine. Optional single-crease "lash" accent on the outer corner of each eye at low strength.
- **Muzzle/nose/whiskers:** keep current (short bright wedge, pink nose triangle, four whisker ridge-creases) — already correct.
- **Body:** keep the seated bell but slim it ~6% at the shoulders so the ruff/head dominates; chest kite becomes cream (continuous with the ruff). Front paws stay, near paw cream ("white mittens").
- **Tail (major upgrade):** replace the 3-facet hook with a **5-facet layered plume** curling around the front of the paws (classic composed-cat pose — tail wrapped, not raised): thick at the root, two overlapping mid-facets suggesting fur layers, a bright cream tip. Wrapped-around-front also further separates her silhouette from Gami's up-swept tail.
- **Shading:** existing crease/occlusion/specular systems suffice. Add one occlusion under the ruff (chin shadow) and one at the tail wrap. Specular stays on the head.

### Readability & modes
- Verify at 44 (cramped) / 56 (rest) / 88 (hover) pt, light + dark scheme. The `PaperPalette` tone ramp already renders scheme-agnostically against the chip's frosted card; the slate/cream split must hold ≥ 3:1 facet-boundary contrast in both modes at 56 pt (manual check + screenshot pass).
- The picker card (EmptyStateView) and popover thumbnail render the same figure automatically — re-verify the welcome (64 pt) size.

### Marketing/docs assets (the actual SVGs)
- Redraw `docs/assets/orifold-cat-twitch.svg` (and the identical `docs-site/public/assets/` copy) to match: front-facing Siberian, ruff, mask, lynx tips, wrapped plume tail, slow tail-sway + ear-twitch animation (keep the existing SMIL animation approach and tile framing from the dog SVG).
- Update `docs-site/public/assets/screenshots/companion-gami-ori.svg` caption ("the origami cat" → "the origami Siberian") and its inline cat drawing to echo the new look (ruff + mask at minimum).

## 3. Personality System

### Voice definition
Ori speaks in short declaratives with impeccable posture. She observes first, then comments. Warmth shows as *approval*, not enthusiasm. Bossiness is affection wearing a monocle. She is never mean, never needy, never random.

**Voice rules (for every Ori line, all 6 languages):**
- ≤ 12 words English. Declarative or a short imperative. Period, not exclamation.
- She *notices* things ("I saw that.") rather than *cheers* things ("Great job!").
- At most one dry flourish per line; usefulness or a real observation underneath it.
- "Human" as an address is allowed at most once across the shipped set (it's her catchphrase, not her tic).
- Same professionalism bar as Gami's redesign: every line survives the "would this look fine in Preview.app?" test — Ori's version of passing that test is wit, Gami's is warmth.

### When Ori speaks vs. stays quiet
Ori uses the **same eligibility engine** Gami got (hero events + first-use only, 45 s throttle, per-line cooldown, editing/selection deferral, tips toggle) — it's species-neutral in `PetBuddy` already. The *character* difference is in distribution, not machinery:
- Ori's hover tip delay is longer (0.35 s → **0.6 s** for `.cat`) — she doesn't leap to attention.
- Ori gets one extra quiet behavior: after the pulse-only acknowledgment of a non-hero event, no copy ever. (Same as Gami — stated here so Sonnet doesn't "add personality" by increasing chatter.)

### Sample lines (English source; localize all)
Hero + hover sets, replacing/refreshing the current `pet.cat.*` copy under a new `ori.*` namespace:

| Context | Line |
|---|---|
| greeting.1 | "You're back. I kept everything exactly where you left it." |
| greeting.2 | "Proceed. I've already reviewed the room." |
| export.1 | "Exporting? I found a cleaner path through this. Follow me." |
| export.2 | "Export approved. Naturally, I checked it first." |
| save.1 | "Saved. Your work stays here, under my supervision." |
| save.2 | "Noted and kept. Elegant edits only, please." |
| warning.1 | "Something needs your attention. I noticed it first, obviously." |
| warning.2 | "A small problem. Handle it; I'll observe." |
| hoverTip.1 | "Yes? I was already watching." |
| hoverTip.2 | "Click me if you require guidance. Or company." |
| hoverTip.3 | "Everything stays on this Mac. I insist on it." |
| hoverTip.4 | "Gami would chase the cursor. I prefer strategy." |
| hoverTip.5 | "Your margins are acceptable. Barely." |
| hoverTip.6 | "Proceed, human. You may." |
| intro.greeting | "I'm Ori. I'll be supervising. You'll do wonderfully." |
| intro.message | "Everything stays on this Mac. I'll offer a clever tip when one is warranted — your files stay yours." |

### The Origami sibling bit (shared, used sparingly)
Ori + Gami = **Origami** — siblings folded from the same sheet, different mothers' patterns. This is a *brand joke*, so it lives in exactly three places and nowhere else (repetition would kill it):
1. **Picker subtitle** (`petPicker.subtitle` refresh): "Two companions, one sheet of paper — together, they make Origami. You can switch anytime."
2. **One switch-confirmation line each** (shown once when the user switches species, via the existing `selectSpecies` greeting path): Ori→ "You've met my brother Gami. Different fold, same paper." / Gami→ "Ori's my sister — same sheet, fancier creases!"
3. **The launch hint body copy** (§6).
Keep it out of the rotating hover/event pools so it never repeats at random.

## 4. Animation & Interaction

The idle-wag system already supports everything needed (`.twitch`, `.sway`, `hoverOnly`, `excitable`). Current cat motion is directionally right; retune for the new geometry:

- **Tail:** slow curl-sway at the wrap (speed ~1.4, amplitude ~0.14, pivot at the tail root by the paws) — visibly half Gami's tempo.
- **Ears:** keep the sharp twitch (speed ~9, amplitude ~0.10), pivot between ear bases; lynx tufts ride along free.
- **Hover:** keep the signature head-tilt (`hoverOnly` sway on head/neck/wing at the shared pivot) — this is Ori's "curious lean-in." Slightly deepen on hover via existing `excitable` ramp.
- **Blink:** approximate with the existing crease/facet system only if trivial (an eye facet's `hi/lo` cannot animate today). **Do not extend the renderer for blinking** — the twitch/tilt/sway trio already reads alive; a blink system is new renderer surface for marginal gain. Explicitly out of scope.
- **Paw stretch / paper shimmer:** out of scope for the same reason. The specular pass already gives a subtle sheen.
- **Reduced motion:** all idle wags and hover tilt are already gated by the reduce-motion path (static settled figure); confirm, don't rebuild.
- No layout shift (wags are draw-time rotations, not layout), no interaction blocking (chip hit-testing unchanged), no bubble overlap (resolver from the Gami plan handles both species identically).

### Parity gift to Gami (things Ori has that Gami lacks)
Per the brief — where Ori's system is richer, lift Gami to match:
1. **Hover head-tilt:** Gami currently only scales + wags on hover. Add one `hoverOnly` sway wag to Gami's head/neck groups (pivot at his head keel, amplitude ~0.06) — an attentive ear-cock. Cheap, uses existing machinery.
2. **Hover-tip delay by species:** implementing Ori's 0.6 s delay makes the delay species-configurable; Gami keeps 0.35 s. (No change in feel for Gami, but the mechanism lands cleanly.)
3. **Switch-confirmation sibling line** (§3) ships for both simultaneously.

## 5. Ori Logo / Mark

Four directions considered:

| Direction | Verdict |
|---|---|
| Minimal origami cat-head mark (folded face, ears, mask) | **Recommended.** Reads at 16 pt, pairs 1:1 with a matching Gami head mark, trivially derived from the figure's own head geometry — near-zero new design surface. |
| Full-body curled-tail silhouette | Beautiful at large sizes, muddy below 24 pt. Use as the *marketing* pose (the redrawn `orifold-cat-twitch.svg` is exactly this) — not the mark. |
| Folded-paper Siberian face with moon motif | Elegant but introduces a new symbol (moon) with no brand anchor; risks "mystical" drift from the clean studio aesthetic. Rejected. |
| Abstract geometric cat (triangles only) | Generic; fails the "instantly Ori" test. Rejected. |

**Plan:** derive a **head-only mark** from the new figure's head/ear/mask facets (crown + ears + mask + eyes, ~8 facets), exported two ways:
- In-app: no new asset needed — the popover header and picker card already render the live figure; the "mark" is only needed for docs/marketing.
- Docs/marketing: a small static SVG (`docs/assets/ori-mark.svg`) + a matching Gami head mark (`docs/assets/gami-mark.svg`) so the docs-site companion page can show the pair as equals. Both monochrome-capable (single-color variant via `currentColor`) for future favicon/badge use.

## 6. Companion-Switch Launch Hint

**Reality check:** first launch already has a full-screen picker (`PetPicker` on the empty state) — users *choose* on day one. The actual gap: after choosing, nothing ever reminds users the other companion exists, or that the chip's popover can switch. So this is a **"you can switch" hint**, not a "choose your companion" onboarding.

**Options evaluated:**

| Pattern | Verdict |
|---|---|
| **Anchored popover from the companion chip** | **Recommended.** It points at the exact control it teaches (the chip → popover → switcher path), reuses the existing `PetControlPopover` styling, needs no new placement logic (NSPopover anchors itself), and is naturally dismissible (click anywhere). |
| Toast/banner | Floats unanchored — teaches a location without pointing at it; adds a new UI pattern to the app for one message. Rejected. |
| Dashboard micro-card | The empty state already hosts the full picker; duplicating there teaches nothing new. Rejected. |
| Pulsing toolbar hint | The companion isn't in the toolbar; misdirects. Rejected. |

**Behavior spec:**
- **Trigger:** on the **third** app session (`gamiSessionCount` counter, `@AppStorage`), if the user has never opened the companion popover (`gamiPopoverOpened` flag) and never switched species. Not first launch (they just chose), not second (still settling in).
- **Content:** compact card anchored to the chip — both figures at 28 pt side by side, title "Two companions, one sheet" + one line each: **"Gami keeps things playful. Ori supervises with taste."** + a "Switch anytime" affordance opening the real popover + an explicit close button.
- **Dismissal & persistence:** any interaction (close, click-away, opening the popover, switching) sets `companionSwitchHintShown = true` — never shows again. Opening the popover organically before session 3 also pre-marks it shown.
- **Suppression:** never while a document import/drop is in progress, never while a hint bubble is visible (and vice versa — `PetBuddy` suppresses bubbles while the hint is up), never in cramped-window mode, never when `petEnabled == false`.
- **Accessibility:** the popover is focusable, Esc closes, VoiceOver reads title → both descriptions → actions; focus returns to the chip on close.
- **Localization:** keys `companionHint.title`, `companionHint.gami`, `companionHint.ori`, `companionHint.switch`, `companionHint.dismiss` — all 6 languages.

## 7. UX Integration Map

Where Ori appears (all existing surfaces — no new mounts):
- **Empty state / intro:** `PetPicker` card (redesigned figure auto-renders); refreshed `petPicker.subtitle` (§3); intro greeting bubble beside the welcome figure.
- **Workspace:** the companion chip (bottom-trailing), hint bubbles, hint-chip badge, hover tip — all via the shared system.
- **Popover:** header shows "Ori / Orifold Guide" (the existing `gami.popover.subtitle` key is species-neutral "Orifold Guide" — verify the header uses `species.displayName`, which it does), species switcher, tips toggle.
- **Menu bar:** `AppCommands` species picker + Show Orifold Buddy toggle (existing).
- **Settings:** none needed; the popover is the control surface.

Guarantees (all inherited from the Gami redesign, re-verified for Ori in QA): never covers document text/toolbar/handles (resolver + exclusion zones), never too small (56 pt chip floor, 44 pt cramped), hover growth anchored bottom-trailing (grows into empty corner), no clipping (hover scale is draw-time), overlay order fixed (bubble < popovers), and — new bar — **Ori must look no less finished than Gami at every size**, which the shared cream palette and equal facet budget are designed to guarantee.

## 8. Technical & Quality Plan

**Files to inspect first (read-only audit):** `OrifoldFoldMark.swift` (cat figure + wag system), `PetBuddy.swift` (hover-tip timing, popover, state), `PetSpecies.swift`, `EmptyStateView.swift` (picker), `Localizable.xcstrings` (`pet.cat.*` inventory), `AppCommands.swift`, `Tests/OrifoldTests/` (PetBuddy + LocalizationCoverage + GamiPlacementResolver tests).

**Files to change:**
- `OrifoldFoldMark.swift` — replace `PaperFigure.cat`, add `.siberianSlate`/`.siberianSmoke` palettes, add Gami's `hoverOnly` head-tilt wag.
- `PetBuddy.swift` — species-configurable hover-tip delay; switch-hint state (`gamiSessionCount`, `companionSwitchHintShown`, `gamiPopoverOpened`); new `CompanionSwitchHintCard` view presented as a popover from the chip; suppress hint bubbles while it's shown; switch-confirmation sibling lines in `selectSpecies`.
- `PetSpecies.swift` — tagline key refresh only (`pet.species.cat.tagline` → new Siberian wording; key name unchanged).
- `EmptyStateView.swift` — no structural change; `petPicker.subtitle` copy refresh flows through L10n.
- `Localizable.xcstrings` — new `ori.*` namespace (migrate the 16 `pet.cat.*` hero/hover/intro keys, matching Gami's `gami.*` precedent; delete the orphaned old keys in the same commit), `companionHint.*`, refreshed `petPicker.subtitle` + `pet.species.cat.tagline`, sibling switch lines (`ori.sibling.switch`, `gami.sibling.switch`). Use the order-preserving in-place JSON update approach (no key re-sorting — keeps the diff reviewable; this bit us once already).
- Marketing SVGs per §2/§5.

**State & persistence:** all via `@AppStorage` (existing pattern); pet choice persistence unchanged (`petSpecies`). Hint state is three small keys, all read-once-per-launch — no observers.

**Performance guardrails:** facet count parity with Gami (~20); no new timers beyond the hint's one-shot presentation; no renderer API changes; startup untouched (figure builds lazily as a `static let`); zero effect on PDF rendering paths (Pet module is UI-overlay only).

**Testing plan:**
- Unit: extend `PetBuddyTests` — hover-delay per species, switch-hint trigger logic (session 3 + not-shown + popover-never-opened), sibling line fires once on switch, hint state persistence. `LocalizationCoverageTests` covers the new keys automatically.
- Existing `GamiPlacementResolverTests` must stay green (no resolver changes expected).
- Manual QA (§9 checklist).

**Regression risks & mitigations:** breaking Gami while touching shared wag/hover code (mitigate: species-parameterized additions only, never edits to Gami's values except the additive head-tilt; run visual pass on both); xcstrings merge conflicts with concurrent sessions (mitigate: in-place JSON script, small commits, re-run coverage test after any merge); the hint colliding with the greeting bubble on session 3 (mitigate: hint waits until no bubble is visible and defers 5 s after launch).

## 9. Sonnet Execution Handoff

Phases; each compiles, `swift build && swift test` + SwiftLint green, before the next.

1. **Audit (read-only).** Read the files in §8. Confirm current cat facet/crease counts, wag params, hover-tip delay call site, picker structure, `pet.cat.*` key inventory. Note deltas vs. this plan.
2. **Palettes + Ori figure.** `.siberianSlate`, `.siberianSmoke`; replace `PaperFigure.cat` per §2. Verify at 44/56/64/88 pt, light+dark, blossom intro, reduce-motion static path. Anti-lookalike check (§1) at 44 pt.
3. **Motion.** Retune Ori's wags (§4); add Gami's `hoverOnly` head-tilt; make hover-tip delay species-configurable (dog 0.35 s / cat 0.6 s).
4. **Copy + L10n.** `ori.*` migration (16 keys), delete orphaned `pet.cat.*` hero/hover/intro keys, sibling switch lines, tagline + picker subtitle refresh — all 6 languages, order-preserving JSON edit, coverage test updated in the same commit.
5. **Switch hint.** State keys, `CompanionSwitchHintCard`, trigger/suppression/dismissal per §6, a11y pass, `companionHint.*` keys ×6.
6. **Marketing assets.** Redraw `orifold-cat-twitch.svg` (+ docs-site copy), update `companion-gami-ori.svg`, add `ori-mark.svg`/`gami-mark.svg`. Validate XML; check alt/desc text says "Siberian".
7. **Docs.** README companion section + capability table; docs-site `companion.mdx` (Ori personality, switch hint), `first-workspace.mdx`, `faq.mdx`, `releases.mdx` bullet. Same voice rules as the app copy.
8. **QA loop 1**, fix, **QA loop 2** (validation loop below), then merge to main and push (standing instruction).

**Acceptance criteria:**
- Ori reads instantly as a fluffy female cat at 44 pt; never rabbit/fox/rat/dog (§1 checks).
- Gami visually unchanged except the additive hover head-tilt; all Gami tests green.
- Switching species round-trips, persists across relaunch, fires each sibling line exactly once.
- Switch hint appears on session 3 only under §6 conditions; never again after any dismissal path; absent under every suppression condition.
- All 6 languages render without truncation in bubble, picker, hint card.
- Reduce Motion: both figures static-settled; hint card opacity-only.
- No new steady-state timers/observers; no PDF-workflow interference (spot-check select/edit/export with Ori active).

**Edge cases to test:** switch species while a bubble is visible (bubble hushes, sibling line shows); switch hint session counter across crash/relaunch; hint + cramped window; hint + `petEnabled` toggled off mid-session; VoiceOver focus return from hint card; RTL-agnostic layout (all 6 shipped languages are LTR, but don't hardcode leading/trailing flips).

**Do not touch:** `PetSpecies` rawValues/storage keys, the renderer (`FoldMarkRenderer`, `FoldState`), `GamiPlacementResolver`/`GamiExclusionContext`, `GamiHintBubble` visuals, Gami's figure geometry (except the additive head-tilt wag entry), qpdf/engine/export code, `gami.*` copy.

**Required validation loop (run twice):**
1. Implement the phase. 2. `swift build && swift test` + `swiftlint lint --quiet` (0 errors). 3. Manually verify: Ori figure at all sizes/modes, Gami unchanged, species switching, launch hint trigger + dismissal, hover states (tilt/twitch/tail), reduce-motion. 4. Fix findings. 5. Repeat 2–3 once more before the final response.
