# Orifold Documentation Makeover — Redesign Plan

**Status:** Planning only. Not implemented. Hand to Sonnet for execution.
**Baseline:** Astro Starlight site already shipped in `docs-site/` (v1), deployed to `udhawan97.github.io/Orifold` via `.github/workflows/docs.yml`.
**This document supersedes** `docs/DOCS_SITE_PLAN.md` as the active spec. That file described building v1; this describes the makeover from v1 → v2. Keep the old plan for history; do not follow it where the two disagree.
**Quality bar:** Apple / Anthropic / Linear / Vercel / SpaceX — minimal, calm, intentional, credible.
**Non‑negotiable constraints:** free/open‑source tooling only, no framework runtime on content pages, Lighthouse ≥ 95 perf & a11y, `prefers-reduced-motion` honored everywhere, no fabricated screenshots.

---

## 0. What Already Exists (so we don't rebuild what's fine)

The makeover is **evolution, not rebuild.** v1 is genuinely good. What ships today:

- **Framework:** Astro Starlight, dark‑default, tokens mapped 1:1 from `DesignSystem.swift` (`tokens.css`), folded‑corner origami motif (`theme.css`). Keep all of this.
- **Components:** `Card`, `CardGrid`, `Callout` (tip/note/warning/danger/whentouse), `Figure`, `Badge`, `Kbd`, `TrustStrip`, `HeroReducedMotion`, plus overrides `Footer`, `Hero`, `MarkdownContent`, `PageTitle`.
- **Content:** ~50 pages across Get Started · Import · Edit · Annotate · Fill & Sign · Export · Reading · Settings · Help · Releases · Developers. Task pages are consistent and well‑scoped.
- **Homepage:** splash hero (animated crane‑fold SVG) + trust strip + three card grids (Start here / Popular workflows / Explore).
- **Data:** `stats.json`, `popular.json`.

**The five real problems this makeover fixes** (everything below elaborates these):

1. **Every visual is a synthetic SVG mockup.** `public/assets/screenshots/*.svg` are hand‑drawn app illustrations; `public/assets/gifs/*.svg` are *static SVG stills named like GIFs* — nothing animates, nothing shows the real app. This is the single biggest credibility gap versus the Apple/Linear bar.
2. **The pet system is built but unused.** `gami-mark.svg`, `ori-mark.svg`, `orifold-dog-wag.svg`, `orifold-cat-twitch.svg` exist; they appear in exactly one `<Figure>` on the companion page. There is no pet‑guide component, no pet callouts, no pet presence in the docs body. The brief's "friendly page guides" don't exist yet.
3. **Stat drift.** "354 tests", "61 files", "~29,000 lines" are hardcoded in `developers/architecture.mdx` and `developers/release-gate.mdx` despite `stats.json` existing — violating the original plan's single‑source rule. These rot on every release.
4. **Developer wing is thin and flat.** Dev pages are 27–52 lines each, no developer FAQ, no collapsible deep‑dives, no "why this matters" framing. Recruiters/senior engineers get a shallow read.
5. **Homepage is card‑heavy, not story‑driven.** Three stacked card grids (15 cards) read as a link farm, not a narrative. No scroll moments, no hierarchy beyond "grid, grid, grid."

---

## 1. Current Documentation Audit (Iteration 1 — Structure)

### 1.1 What feels cluttered / repetitive / wordy

| Issue | Where | Verdict |
|---|---|---|
| Three consecutive card grids | `index.mdx` | **Too much.** 15 cards in a row flattens hierarchy. Collapse to one hero‑story + one curated "popular" row + one slim developer/help footer. |
| "Explore" grid duplicates sidebar | `index.mdx` bottom grid | **Cut or fold in.** Troubleshooting/FAQ/Releases/Developers already live in the sidebar; a fourth grid is redundant. |
| Companion page prose is dense | `get-started/companion.mdx` | **Simplify.** Two ~5‑line paragraphs describe fold geometry ("layered tails, folded ears, a ruff you can see the layers of") — lovely but wordy for a user page. Move fold‑craft detail into a collapsible "The origami detail" `<details>`; keep the top scannable. |
| Long single paragraphs on concept pages | `developers/architecture.mdx`, `settings/privacy.mdx` | Break into short sections + tables (architecture already does this well; privacy needs it). |
| Duplicated stats in prose | architecture + release‑gate | **Bug.** Must read from `stats.json` via a `<Stat>` component. |

### 1.2 What should move into collapsible `<details>` blocks

Starlight ships `<details>`/`<summary>` and an `<Aside>`; we'll add a styled `<Details>` wrapper. Collapse:

- **Developer deep‑dives:** qpdf flag lists, CMS/signing internals, PDFium build notes, the SPM `Bundle.module` xcstrings gotcha — visible on demand, not in the default scroll.
- **Honest‑scope caveats** on Edit Text / Signatures / Compress ("what 'detected text' means", "why text‑only PDFs barely shrink") — keep the happy path clean, tuck the nuance.
- **Full format/shortcut tables** where a page only needs the common rows inline.
- **Companion fold‑craft detail** (above).
- **FAQ answers** longer than ~2 sentences.

Rule: **collapse depth, never collapse the answer.** The first sentence of every dropdown summary must state the takeaway so a non‑opener still learns something.

### 1.3 Stale / misleading visual assets

**All of them, in the same way:** every `screenshots/*.svg` and `gifs/*.svg` is a synthetic mockup, not the real app. They're competent illustrations but they (a) can drift from real UI silently, (b) read as "placeholder" to a discerning viewer, and (c) the `gifs/` ones don't move despite the name. Full asset‑by‑asset disposition in §8.

### 1.4 Missing pages

| Missing page | Section | Why it matters |
|---|---|---|
| **Developer FAQ** | Developers | Brief explicitly requires it; senior‑engineer credibility. |
| **Project overview / "Start here for developers"** | Developers | A single orientation page: what to read first, riskiest modules, module map. |
| **Build & release** (release engineering) | Developers | Current `build.mdx` is source‑build only; nothing covers how releases are cut, CI gates, notarization reality. |
| **Roadmap / non‑goals** | Developers or top‑level | Recruiters/contributors want to know direction and what's intentionally out of scope. |
| **Keyboard shortcuts cheat‑sheet visual** | Settings | Exists as text; a printable/scannable card is a nice‑to‑have. |
| **Accessibility statement** | Settings or Help | The app has Reduced Motion, Reader/Night modes, eye‑care — a short a11y page is on‑brand and recruiter‑positive. |

### 1.5 User flows not clearly explained end‑to‑end

The pages exist but the *connective tissue* is weak. Add explicit, visual, numbered flows for:

- **Import → arrange → export one PDF** (the core value loop; today it's split across three pages with no single "watch it happen" moment).
- **Sign a document** (draw → place → export).
- **Fill → lock → share** a form.
- **Scan → OCR → search** (three conflated pages: OCR ↔ Search ↔ Edit Text).

These are exactly the GIF candidates (§7).

### 1.6 Pages needing stronger visual hierarchy

- **Homepage** (§5) — story, not grids.
- **Developer landing** — needs a hero, a module map, and "read these first" ordering.
- **Privacy page** — the most‑linked trust page should be the most visually confident (big promise, then proof), not a wall of prose.

---

## 2. Missing Elements & Improvement Opportunities (summary)

1. **Real media pipeline** (screenshots + GIFs) with a capture harness, optimization budget, and static fallbacks. §7.
2. **Pet guide system** — a real `PetTip` component with Gami/Ori variants, keyboard‑accessible, reduced‑motion aware, translatable. §6.
3. **`<Stat>` component** reading `stats.json` — kill stat drift. §11.
4. **`<Details>` deep‑dive component** — styled, origami‑consistent. §1.2.
5. **Developer FAQ + deepened dev wing.** §9.
6. **Homepage storytelling + tasteful scroll motion.** §5.
7. **A11y statement + formalized reduced‑motion coverage.** §10.
8. **Video/GIF `<Media>` component** with `<video>`‑preferred, GIF‑fallback, poster image, lazy load, captions. §7.

---

## 3. Three Iterations of the Plan

### Iteration 1 — Audit & Structure ✔ (see §1, §4)

Outcome: keep the framework and IA; fix stat drift; add missing dev pages + developer FAQ; introduce `<Details>` for deep dives; de‑clutter the homepage; identify the four core flows that need motion.

### Iteration 2 — Visual & Interaction Design

**Layout system (minimal, calm):**

- **One content column, 72ch**, generous `ma` (間) whitespace. Already set — enforce it on concept pages too.
- **Section rhythm:** vertical spacing scale `1.5 / 2.5 / 4rem`; the skewed `.of-crease` divider only between *major* homepage sections (not inside body pages — it's a signature, not a workhorse).
- **Cards:** keep folded‑corner cards but **reduce their density.** Cards are for navigation moments (homepage, section landings), not for every list. Body pages use prose + callouts + steps, not card soup.
- **Typography:** keep system stack (zero web‑font download = perf + CJK/Devanagari coverage). Add a *slightly* tighter heading tracking and a display‑size hero H1 clamp. No decorative display font — restraint is the Japanese‑modern move.

**Motion (premium, not distracting) — total budget: tiny.**

- **Allowed:** hover transitions (120ms), theme cross‑fade, `<details>` expand, and **scroll‑reveal fade‑up** (8–12px translate, 300ms, `once`) on homepage sections and figures only. Nothing loops in the body. Nothing parallaxes.
- **Scroll‑triggered moments (homepage only, ≤ 3):**
  1. Hero crane‑fold plays once on load (already exists; keep).
  2. The **"chaos → order" value moment**: as the "many files → one PDF" band scrolls into view, a small SVG/Lottie shows scattered file rectangles folding into one document. One play, `IntersectionObserver`, reduced‑motion → static final frame.
  3. A pet does **one** subtle entrance (Gami wag or Ori tail‑twitch) when the "Meet your guides" band appears. One play, then rest.
- **Implementation:** pure CSS + a ~1KB `IntersectionObserver` snippet, no animation library. If Lottie is ever needed for #2, gate it behind reduced‑motion and lazy‑load it; otherwise animate the existing SVG via CSS/SMIL as the crane already does. **No GSAP/Framer/AOS** — unjustified weight.

**Visual assets:** real screenshots (framed in `<Figure>`) and short GIFs/video for the four core flows (§7). SVG diagrams stay *only* for architecture/workspace concepts (§8).

**Navigation / IA:** keep the sidebar tree; add a **"For developers" top‑level entry point** and a persistent, quiet **"Docs home"** via logo. Add breadcrumbs + prev/next (Starlight defaults — verify enabled). Add a **developer landing hero** so the dev wing has a front door.

### Iteration 3 — Recruiter / Developer Polish (see §9)

Outcome: developer FAQ, architecture depth via collapsible deep‑dives, explicit "read these first / don't break these" guidance, build‑and‑release page, "why this matters" notes on flagship features, final polish checklist, exact Sonnet task list.

---

## 4. Final Recommended Documentation Structure

Keep v1's IA (it's good and task‑first). **Changes only**, marked ✚ new / ✎ changed / ✂ remove:

```
GET STARTED            (unchanged; simplify companion page copy ✎)
IMPORT & ORGANIZE      (unchanged)
EDIT                   (unchanged; add collapsible honest-scope on edit-text ✎)
ANNOTATE & REVIEW      (unchanged)
FILL & SIGN            (unchanged)
EXPORT & PROTECT       (unchanged)
READ COMFORTABLY       (unchanged)
SETTINGS & BASICS
  ├── Change the app language
  ├── Keyboard shortcuts
  ├── Privacy & local-first design       (visual-hierarchy pass ✎)
  └── Accessibility                       ✚ new (Reduced Motion, Reader/Night, comfort presets)
HELP
  ├── Troubleshooting (+3 subpages)
  └── FAQ                                  (user-facing; unchanged)
RELEASE NOTES          (unchanged; ensure latest reflects shipped version)
DEVELOPERS             (front door + depth)
  ├── Start here (dev overview)           ✚ new — module map, read-first order, risk map
  ├── Why Orifold?
  ├── Architecture overview               (add collapsible deep-dives ✎, <Stat> ✎)
  ├── The engines
  ├── Build from source
  ├── Build & release (CI/CD, notarization)✚ new
  ├── Localization guide
  ├── Testing & the release gate          (<Stat> ✎)
  ├── Developer FAQ                        ✚ new
  ├── Roadmap & non-goals                  ✚ new
  └── Contributing
```

**Homepage** is redesigned in place (§5), not restructured in the tree.

**IA rules unchanged from v1:** task‑first sidebar labels; max 2 levels deep; one task = one page; `Pro workflow` badges for advanced flows; user pages never mention Swift/internals except in a "How it works" footer link.

---

## 5. Homepage Redesign Plan

**Principle:** minimal but not empty. Replace three card grids with a **calm vertical story** that answers What / Who / Why / How‑different / Get‑started / Developers — in that order — with at most **one** card grid and at most **three** motion moments.

### Section order (top → bottom)

1. **Hero.** Keep the animated crane‑fold (left/right split as today). Tighten copy:
   - H1: **"Fold chaos into one clean PDF."**
   - Sub: "A free, open‑source PDF workspace for macOS. Drop in up to 50 messy files — edit, sign, and export one polished document. Nothing ever leaves your Mac."
   - Buttons: `Get started →` (primary) · `Install in 30 seconds` (ghost).
   - **Pet touch:** a small resting Gami *or* Ori mark tucked near the hero art (static; not animated on load — the crane owns the hero motion).

2. **Trust strip** (keep). Three facts: `🔒 100% local` · `🆓 Free · MIT` · `🧪 <Stat tests/> tests gate every release`. Stats via `<Stat>`.

3. **The value moment — "Many files in. One PDF out."** The one *scroll‑reveal* animation (§ Iteration 2, moment #2): scattered file cards fold into a single document. One short line each side ("before: 7 files, 2 screenshots, a Word doc" → "after: one searchable, signed, protected PDF"). Reduced‑motion → static before/after.

4. **Who it's for** — three short columns, no cards, just an icon + label + one line:
   - *Everyday Mac users* — "Merge, sign, and clean up PDFs without a subscription."
   - *Privacy‑minded people* — "Legal, medical, financial docs that must never touch a server."
   - *Developers* — "A native, MIT‑licensed, four‑engine PDF app you can read end to end."

5. **What makes it different** — a tight 4‑item feature strip (not the old 8‑card grid): **Local‑only** · **One‑document workspace (merge is not a step)** · **Real AES‑256 + sanitize** · **On‑device OCR**. Each with a one‑line "why it matters."

6. **Popular workflows** — **one** curated card grid (6 cards max), from `popular.json`: Combine · Edit text · Sign · Fill a form · Compress · Protect. (Drop OCR/Language from the homepage grid — they live in the sidebar.)

7. **Meet your guides — Gami & Ori.** A single calm band introducing the two companions (the pet‑system front door, §6), with the *one* pet entrance animation. Links to the companion page. This is where the personality lives on the homepage — contained, not sprinkled chaotically.

8. **For developers** — a slim two‑line band + one button to the developer landing. Not a card grid.

9. **Footer** (keep): "Free · Open source (MIT) · 100% local · No account, ever" + GitHub + release link.

**Cut from homepage:** the "Explore" grid (redundant with sidebar), OCR + Language homepage cards, and any second/third card grid. Net: **one** card grid on the homepage, down from three.

**Performance:** homepage must still transfer ≤ 100KB excluding search index; the value‑moment animation is a single optimized SVG (or ≤ 20KB lazy Lottie gated behind reduced‑motion), pets are inline SVG.

---

## 6. Pet Guide System — Gami & Ori

**The bar:** premium documentation companions (think a tasteful margin mascot), **never** Clippy. Contained, optional‑feeling, accessible. Reuse existing assets (`gami-mark.svg`, `ori-mark.svg`, `orifold-dog-wag.svg`, `orifold-cat-twitch.svg`) — do **not** commission new art.

### 6.1 Roles (strict, so they don't blur)

| | **Gami** (Dog) | **Ori** (Cat) |
|---|---|---|
| Voice | Energetic, loyal, encouraging | Curious, clever, charmingly bossy |
| Appears in | User‑facing pages, Quick Start, beginner tips | Developer pages, edge cases, advanced/technical notes |
| Example | "Need a quick start? Gami's got your back." | "Ori says: read the architecture notes before you touch the renderer." |
| Mark color | uses `--of-accent` (currentColor) | uses `--of-accent` (currentColor) |

**Discipline rule:** Gami never gives deep technical notes; Ori never appears on a Get‑Started page. If a tip doesn't clearly belong to one voice, it's a plain `<Callout>`, not a pet. **Density cap: at most one pet tip per screenful, ideally one per page.** Pets punctuate; they don't narrate.

### 6.2 New component: `<PetTip who="gami|ori">`

A specialized callout: small pet mark (28–32px, inline SVG, `currentColor`) at left, one‑ or two‑line message, folded‑corner motif to match cards. Built on the existing callout styling so it's visually native.

- **Structure:** `role="note"`, `aria-label="Gami's tip"` / `"Ori's note"`. Pet mark is decorative (`aria-hidden`) since the label carries the identity.
- **Reduced motion:** the mark is static by default. A *subtle* one‑time idle (wag/twitch) may play on scroll‑into‑view **only** if `prefers-reduced-motion: no-preference`; otherwise fully static.
- **Keyboard/AT:** it's inline flowing content, not a popover — nothing to trap. If a variant ever uses a hover popover, it must be `<details>`‑based or button‑triggered, focusable, `Esc`‑dismissible, and must not obscure body text.
- **Translatable:** message is slot content (real page text, localized like everything else). The `aria-label` prefix ("Gami's tip") comes from Starlight UI strings, never hardcoded.
- **Never blocks content:** it's in the normal flow. No fixed/floating pet that overlaps text. (A floating corner mascot is explicitly rejected — it fights the calm brief and is an a11y/mobile hazard.)

### 6.3 Where pets appear

| Surface | Pet | Usage |
|---|---|---|
| Homepage "Meet your guides" band | Both | The front door; one entrance animation. |
| Quick Start / first‑workspace | Gami | 1 encouraging tip at the start. |
| Each user section landing (optional) | Gami | At most one beginner tip. |
| Edit Text / Signatures honest‑scope | Ori | 1 precise "watch out" note. |
| Developer landing + architecture | Ori | "Read these first" / "don't break these" notes. |
| Developer FAQ | Ori | Framing the riskiest‑parts answer. |
| 404 page | One (rotate) | A single charming line. |
| End of "Your first workspace" | Gami | "You now know 80% of Orifold." |

**Do NOT** put pets in: troubleshooting steps, tables, warnings/danger callouts (safety must read straight), or more than once per page in body content.

### 6.4 Accessibility (hard requirements)

- Respects `prefers-reduced-motion` — no idle animation when reduced.
- Pet marks are `aria-hidden`; identity conveyed by text label.
- Text contrast ≥ 4.5:1 in both themes (uses existing token pairs — verified).
- No pet element is keyboard‑focusable unless it's an interactive popover, in which case full keyboard operation + `Esc` + focus‑visible ring.
- Everything translatable; no identity encoded only in an image.

---

## 7. GIF / Animation Strategy

**Reality check first:** today's `gifs/*.svg` are static SVGs — they don't move and they aren't the real app. **They must be replaced with real captures** for the four core flows. Everything else stays static.

### 7.1 Format decision (challenge the brief's "GIF")

The brief says "GIF." **GIF is the wrong container** for screen recordings at this quality bar: huge files, 256‑color banding, no pause. **Use `<video>` (H.264/HEVC MP4 + WebM/AV1), `autoplay muted loop playsinline`, with a poster image and a static PNG fallback.** Deliver a real `.gif` only as a last‑resort fallback where `<video>` can't be used (it essentially always can). This is what Apple/Stripe/Linear actually do; calling them "GIFs" in the brief is fine, but ship video.

Build a `<Media>` component: `<video>` with `poster`, `loading="lazy"` behavior (IntersectionObserver play/pause so off‑screen clips don't decode), reduced‑motion → shows poster only (no autoplay), optional `<track>` captions, mandatory `aria-label`/caption.

### 7.2 The clips to produce (short, looping, silent, app‑only)

| Clip | Flow shown | Page | Length | Loop | Captions | Static fallback |
|---|---|---|---|---|---|---|
| **combine** | Sidebar drag: reorder pages across two demo docs, then one Export | `import/combine` | 4–6s | Yes | On‑frame text labels | Yes (poster) |
| **edit‑text** | Click detected text, type a change, click away to commit | `edit/edit-text` | 3–5s | Yes | Yes | Yes |
| **sign** | Draw signature → place on demo line → export | `fill-sign/signatures` | 4–6s | Yes | Yes | Yes |
| **export/save** | ⇧⌘E → format picker → save panel → confirmation | `export/export-save` | 3–5s | Yes | Yes | Yes |

**Second‑tier (add only if capture is cheap; otherwise keep as screenshots):**

| Clip | Flow | Page |
|---|---|---|
| ocr | Scan → OCR → ⌘F finds text | `edit/ocr` |
| forms | Detect fields → fill → lock | `fill-sign/forms` |
| night‑mode | Toggle Gentle/Paper/Amber | `reading/night-mode` |
| companion‑switch | Switch Gami ↔ Ori in the popover | `get-started/companion` |
| recently‑viewed | Empty‑state shelf reopening a file | `import/recently-viewed` |

For each clip, the spec is: **purpose** (teach the flow faster than prose), **placement** (directly under the page's Steps, one clip per page max), **exact flow** (above), **length** (3–6s), **loop** (yes), **captions** (on‑frame labels for the key action + `aria-label`), **fallback** (poster PNG always).

### 7.3 Capture standards (inherit `MEDIA_MANIFEST.md`, tighten)

- App UI only. Dark mode (brand default). 1600×1000 window, fixed zoom, one companion chosen and kept constant.
- Obviously‑fake demo docs (`Sample Agreement.pdf`, etc.). **No real files, paths, usernames, desktop, or menu bar clutter.**
- Optimize hard: target < 1.5MB per clip (video), poster < 60KB. Trim dead frames; ~24fps is plenty.
- Loop cleanly (first == last frame). No cursor teleporting.

### 7.4 What should NOT be a GIF/video

- Anything static works better as a screenshot (toolbars, empty states, comparisons) — see §8.
- Concept/architecture — stays an SVG diagram.
- Homepage value moment — a single lightweight SVG animation, not a screen recording.

---

## 8. SVG / Image Audit — asset‑by‑asset disposition

Decision per asset: **Keep · Refresh · → Screenshot · → Video · Collapse (move to `<details>`) · Remove.**

| Asset | Today | Decision | Notes |
|---|---|---|---|
| `orifold-crane-fold.svg` (155KB) | Hero animation | **Keep** | Signature; already reduced‑motion aware. Verify it's not shipped on non‑hero pages (155KB is heavy). |
| `hero-banner-{dark,light}.svg` | README only | **Keep** (README) | Not used in site; fine. |
| `value-props-{dark,light}.svg` | README only | **Keep** (README) | Same. |
| `orifold-v3-architecture-diagram.svg` | `developers/architecture` | **Keep, refresh** | Verify labels match current layers; this is a legitimate diagram use of SVG. |
| `orifold-v3-workspace-diagram.svg` | `what-is-orifold` | **Keep, refresh** | Concept diagram — good SVG use. Confirm it's actually placed on the page. |
| `gami-mark.svg`, `ori-mark.svg` | 1 figure | **Keep, promote** | Become the `<PetTip>` marks (§6). Finally used properly. |
| `orifold-dog-wag.svg`, `orifold-cat-twitch.svg` | unused | **Keep, wire in** | The homepage "Meet your guides" entrance + optional PetTip idle. |
| `screenshots/*.svg` (all 10) | Synthetic mockups | **→ Screenshot** | Replace with real captures. Until captured, keep the SVG mockup **but** label the page's Figure caption honestly (or keep placeholder). Do not present a synthetic mockup as a real screenshot without noting it. |
| `gifs/*.svg` (all 4) | Static SVG "gifs" | **→ Video** | Replace with real `<Media>` clips (§7). These are the most misleading assets on the site. |
| `companion-gami-ori.svg` | companion page | **→ Screenshot** or **Refresh** | Prefer a real capture of the two companions in‑app. |
| `favicon.svg`, app‑icon PNGs | chrome | **Keep** | Fine. |

**SVG philosophy going forward:** SVG for **diagrams and marks** (crisp, translatable `<text>`, tiny). **Real captures** (screenshot/video) for **UI**. Never a synthetic SVG pretending to be a screenshot — that's the one pattern we're eliminating.

**Interim honesty policy:** if real captures aren't ready when v2 ships, the `<Figure>`/`<Media>` placeholder state (dashed box with capture spec) is the correct shippable state — **not** a synthetic mockup dressed as the real thing. Match the existing `MEDIA_MANIFEST.md` stance.

---

## 9. Developer FAQ & Developer‑Wing Polish

### 9.1 New page: `developers/faq.mdx` (Developer FAQ)

Q&A format, first sentence answers, `<details>` for depth. Questions (from the brief + gaps):

1. **How does Orifold render PDFs?** → PDFKit for display/composition; PDFium for image ops; short. Deep dive collapsible.
2. **How does text editing work?** → detected‑text model, in‑place edit, font handling, why scans need OCR. Deep dive: the "edit lands on top" history (PDFKit re‑serialization) if worth surfacing.
3. **How are annotations & signatures handled?** → visual layer vs. burned‑in at export; drawn signature vs. cryptographic signing distinction.
4. **How does import/export work?** → import normalizer, 50‑file workspace, staged export pipeline + qpdf validation gate.
5. **How are keyboard shortcuts structured?** → the real set only; where they're defined.
6. **How does localization work?** → xcstrings, 6 languages, coverage test, `Bundle.module`/JSON‑fallback gotcha (collapsible).
7. **How should contributors test changes?** → `swift test`; the release gate; manual pass.
8. **What are the riskiest parts of the app?** → export/re‑serialization path, encryption/sanitize, OCR, signing. *(Ori note.)*
9. **What files/modules should I understand first?** → module map with a "read‑order."
10. **What should I avoid breaking?** → the export validation gate, the local‑only boundary (never add network), localization coverage, the two sandbox entitlements.
11. **How are releases created?** → CI, tagging, notarization reality, GitHub Actions asset. Link to Build & release.
12. **What CI/CD checks are required?** → tests, SwiftLint, CodeQL, dependency‑review, docs build. From `.github/workflows/`.
13. **What is the architecture at a high level?** → one paragraph + link to architecture.

### 9.2 New page: `developers/start-here.mdx`

The dev front door: a **module map** (from the `Orifold/` tree), a **read‑first order** (What is it → Why → Architecture → Engines → Build → FAQ), a **risk map** ("touch these carefully"), and a "if `swift test` passes you're set up" onboarding promise. One Ori PetTip.

### 9.3 New page: `developers/build-release.mdx`

How releases are actually cut: version bump, tag, `release.yml`, ad‑hoc signing vs. notarization honesty, the installer/prebuilt path, log locations. Complements the source‑build page.

### 9.4 New page: `developers/roadmap.mdx`

**Now / Next / Later / Non‑goals.** Non‑goals are the trust move: no cloud sync, no Windows/iPad (state kindly), no telemetry, no collaborative review. Recruiters read decisiveness here.

### 9.5 Depth via collapsibles (not longer prose)

Architecture, engines, localization, and testing pages each gain 1–3 `<details>` deep‑dives so the **default read stays scannable** but the depth exists for the senior engineer who opens them.

### 9.6 "Why this matters" notes on flagship features

Add a one‑line **Why it matters** to: Local‑only, AES‑256, Sanitize, OCR, One‑document workspace, Export validation gate. On user pages it's plain language; on dev pages it's the engineering rationale.

### 9.7 `<Stat>` component — fix stat drift (blocking)

Create `<Stat name="tests|files|loc|languages|version|maxFilesPerWorkspace|entitlements" />` reading `stats.json`. Replace every hardcoded "354 / 61 / 29,000 / 6 languages" in `architecture.mdx` and `release-gate.mdx`. **Acceptance:** `grep -R "354" src/content` returns nothing.

---

## 10. Accessibility & Performance Requirements

**Performance:**

- Homepage ≤ 100KB transferred (excl. search index). Content pages ship **no** framework JS runtime.
- Media: `<video>` lazy (IntersectionObserver play/pause), poster < 60KB, clip < 1.5MB, `preload="none"`.
- Images: `loading="lazy"`, explicit `width`/`height` (no layout shift), AVIF/WebP where raster.
- No animation library (no GSAP/Framer/AOS). Scroll reveal = ~1KB IntersectionObserver + CSS.
- The 155KB crane SVG loads **only** on the homepage hero — verify it's not pulled onto other pages.
- Lighthouse mobile ≥ 95 Performance and ≥ 95 Accessibility on homepage + one task page + one dev page.

**Accessibility:**

- `prefers-reduced-motion`: crane static frame, no scroll‑reveal translate, no pet idle, video shows poster only (no autoplay). One code path, tested via emulation.
- Alt text on every image; `aria-label` + optional caption on every `<Media>`; captions/on‑frame labels on demo clips.
- Keyboard: skip‑link, sidebar, `⌘K`/`/` search, theme toggle, ToC, every `<details>`, any pet popover — all reachable and operable; visible focus rings (already `--of-accent` 2px).
- Contrast: all token pairs pass WCAG AA both themes (verify accent‑on‑canvas ≥ 4.5:1 at build).
- Screen reader: pet marks `aria-hidden`; identity in text. Video not announced as decorative if it teaches (label it).
- Translatable: all UI chrome from Starlight strings; no identity/meaning locked in images; layouts survive +40% string length and CJK line‑breaking (pseudo‑locale test).
- Mobile: no horizontal scroll at 360px; ToC collapses; cards reflow; pets don't overlap text.

---

## 11. Exact Implementation Checklist for Sonnet

> Do not redesign the app. Do not invent features or shortcuts. When unsure what the app does, check `README.md` + source and write honest scope. Keep everything free/open‑source. Preserve v1's IA and tokens.

**Phase A — Components & data plumbing (no content churn yet)**
- [ ] `Stat.astro` — reads `src/data/stats.json`; props select a field; renders text only.
- [ ] Replace hardcoded stats in `developers/architecture.mdx` + `developers/release-gate.mdx` with `<Stat>`. Grep‑verify no "354"/"29,000"/"61 source" remain in `src/content`.
- [ ] `Details.astro` — styled `<details>/<summary>` deep‑dive with folded‑corner motif; summary shows takeaway.
- [ ] `PetTip.astro` — `who="gami|ori"`, inline `currentColor` mark, callout‑native styling, `role="note"`, translatable `aria-label`, reduced‑motion‑safe, `aria-hidden` mark.
- [ ] `Media.astro` — `<video muted loop playsinline>` + `poster` + IntersectionObserver play/pause + reduced‑motion (poster only) + `aria-label`/caption + optional `<track>`; degrades to poster `<img>` if no source.
- [ ] `Stat`, `Details`, `PetTip`, `Media` styles added to `theme.css` (reuse existing tokens/motifs).

**Phase B — Homepage rebuild (`index.mdx`)**
- [ ] Implement §5 section order; reduce to **one** card grid; remove the "Explore" grid + OCR/Language homepage cards.
- [ ] Add "Who it's for" (3 columns), "What makes it different" (4‑item strip), "Meet your guides" pet band, slim "For developers" band.
- [ ] Add the single scroll‑reveal value‑moment animation (SVG/CSS + IntersectionObserver), reduced‑motion → static.
- [ ] Wire `<Stat>` into the trust strip.

**Phase C — New pages**
- [ ] `developers/start-here.mdx` (module map, read‑order, risk map, one Ori PetTip).
- [ ] `developers/faq.mdx` (§9.1, `<Details>` for depth, one Ori PetTip).
- [ ] `developers/build-release.mdx` (§9.3).
- [ ] `developers/roadmap.mdx` (Now/Next/Later/Non‑goals).
- [ ] `settings/accessibility.mdx` (Reduced Motion, Reader/Night, comfort presets).
- [ ] Add all five to `astro.config.mjs` sidebar in the positions in §4.

**Phase D — Content polish**
- [ ] Simplify `get-started/companion.mdx` top; move fold‑craft detail into `<Details>`.
- [ ] Add collapsible honest‑scope `<Details>` to `edit/edit-text.mdx` and `fill-sign/signatures.mdx`.
- [ ] Add "Why it matters" one‑liners to flagship features (§9.6).
- [ ] Visual‑hierarchy pass on `settings/privacy.mdx` (promise → proof; tables/sections not prose wall).
- [ ] Insert `<PetTip>` per §6.3 map — **one per page max**, correct voice per page type.
- [ ] Deep‑dive `<Details>` on architecture/engines/localization/testing.

**Phase E — Media**
- [ ] Capture 4 core clips (§7.2) to real `<video>` + posters; place one per page under Steps.
- [ ] Replace `gifs/*.svg` usages with `<Media>`; if not yet captured, use `<Media>` placeholder state (dashed spec box) — never ship the static SVG as a "GIF."
- [ ] Replace `screenshots/*.svg` with real PNGs where captured; keep honest placeholders otherwise.
- [ ] Refresh architecture/workspace diagrams if labels drifted.
- [ ] Verify the 155KB crane SVG loads only on the homepage.

**Phase F — QA & ship** (see §12).

---

## 12. Testing & Verification Checklist

- [ ] `npm run build` clean; deploys via `docs.yml` to Pages.
- [ ] Zero broken internal links (Starlight validator or `lychee` in CI).
- [ ] `grep -R "354\|29,000\|61 source" docs-site/src/content` → empty (stats via `<Stat>` only).
- [ ] Four canonical searches still return the right page #1: "edit text", "combine PDFs", "where did my export go", "change language".
- [ ] Sidebar: all §4 entries present + ordered; new dev pages appear; current‑page highlight works.
- [ ] Keyboard‑only pass: skip‑link, sidebar, `⌘K`/`/`, theme toggle, ToC, every `<details>`, any pet popover.
- [ ] VoiceOver spot‑check: homepage, one task page, one PetTip, one `<Media>`, one troubleshooting accordion.
- [ ] `prefers-reduced-motion` emulation: crane static, no scroll‑reveal, no pet idle, video shows poster only — verify on homepage + a page with a clip.
- [ ] Responsive 360/768/1280/1600: no horizontal scroll; ToC collapses; cards reflow; pets don't overlap text; video posters fit.
- [ ] Pseudo‑locale (+40%, CJK): nav/cards/badges/PetTip don't truncate or overflow.
- [ ] Lighthouse mobile ≥ 95 Perf & A11y on homepage + one task page + one dev page; zero contrast failures.
- [ ] Homepage transfer ≤ 100KB excl. search index; content pages ship no framework JS runtime; crane not on other pages.
- [ ] Each `<Media>`: lazy, poster present, off‑screen doesn't autoplay, `aria-label` set, loops cleanly, < 1.5MB.
- [ ] Pet density: ≤ 1 pet tip per page in body content; Gami absent from dev pages; Ori absent from Get‑Started.
- [ ] Both themes screenshot‑diffed on homepage + one page per template.
- [ ] No user page mentions Swift/internals outside a "How it works" footer link.
- [ ] `stats.json` values match the real current release before ship.

---

## 13. Risks & Edge Cases

| Risk | Mitigation |
|---|---|
| **Pets become Clippy / childish.** | Hard density cap (≤1/page), strict voice split, no floating mascot, contained bands only, always optional‑feeling. If in doubt, use a plain callout. |
| **Real captures never get made** → site stalls or ships fake media. | Placeholder state is the shippable honest state; components render capture specs. Ship v2 structure without waiting on media; drop clips in later with no code change. |
| **Scroll animations tank Lighthouse / annoy.** | ≤3 moments, homepage only, one play each, IntersectionObserver, reduced‑motion kills them, no animation lib. Budget‑test before merge. |
| **Video autoplay policy / battery on mobile.** | `muted playsinline`, `preload="none"`, pause when off‑screen, poster‑only under reduced‑motion. |
| **Stat drift returns.** | `<Stat>` + grep guard in CI. |
| **155KB crane leaking onto every page.** | Verify hero‑only import; it already lives in the Hero override — confirm no other page imports it. |
| **Homepage de‑carding hurts navigation.** | Sidebar + search remain the real nav; homepage is a story, not the index. Keep one popular‑workflows grid + clear buttons. |
| **Localization: pet labels / captions hardcoded.** | All pet `aria-label` prefixes from Starlight UI strings; messages are page content; captions translatable. |
| **Adding Node/media assets bloats the repo.** | Optimize every asset; keep clips < 1.5MB; consider Git LFS if total media grows large. |
| **Diagrams drift from real architecture.** | Refresh diagrams this pass; note in Contributing that architecture changes update the diagram. |
| **Two competing plan docs.** | This doc supersedes `DOCS_SITE_PLAN.md`; state that at top (done) and in the PR. |

---

## 14. Definition of Done

The makeover is done when **all** of these hold:

1. **Credible visuals:** the four core flows show the *real app* via `<Media>` (or honest placeholders), and no synthetic SVG is presented as a screenshot/GIF.
2. **Pets are guides, not decoration:** `<PetTip>` exists, wired per §6.3, ≤1/page, correct voice split, fully accessible and reduced‑motion‑safe.
3. **Homepage tells a story:** What/Who/Why/Different/Start/Developers, one card grid, ≤3 tasteful motion moments, ≤100KB.
4. **Developer wing is deep and confident:** Developer FAQ, Start‑here, Build & release, Roadmap/Non‑goals all live; architecture/engines carry collapsible deep‑dives; "why this matters" notes present.
5. **No stat drift:** all stats via `<Stat>`; grep guard passes.
6. **Fast & accessible:** Lighthouse ≥95/≥95, keyboard + VoiceOver pass, reduced‑motion path verified, pseudo‑locale survives +40%/CJK, no horizontal scroll at 360px.
7. **Calm and consistent:** folded‑corner motif and tokens unchanged; no new fonts; no animation library; the site feels like the app's sibling.
8. **Honest:** every claim matches the shipped app (formats, 50‑file limit, real shortcuts, 6 languages, 2 entitlements); non‑goals stated plainly; no invented features.
9. **Ships green:** `npm run build` clean, links valid, deploys via `docs.yml`, README links to the docs site.

---

### Appendix — Weak ideas explicitly rejected

- **Real animated GIFs** for screen recordings → use `<video>` (smaller, pausable, higher quality). "GIF" kept as colloquial label only.
- **Floating/persistent corner mascot** → rejected (a11y hazard, mobile overlap, fights the calm brief). Pets live in contained flow bands.
- **Three homepage card grids** → collapsed to one; story sections replace link farms.
- **Animation library (GSAP/Framer/AOS)** → rejected as unjustified weight; CSS + IntersectionObserver suffices.
- **Synthetic SVG "screenshots"** as the permanent visual strategy → replaced by real captures; SVG reserved for diagrams/marks.
- **Hardcoded stats in prose** → `<Stat>` + `stats.json` single source.
- **Longer dev prose for "depth"** → depth via collapsible deep‑dives so the default read stays scannable.
