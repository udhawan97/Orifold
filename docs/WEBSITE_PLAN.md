# Orifold Website Plan — Landing Page + Download & Release Automation

**Status:** Planning only. Not implemented. Hand this document to Sonnet for execution.
**Date:** 2026-07-07 · **Baseline audited:** v0.8.1 — the shipped Astro Starlight docs site in `docs-site/` (deployed to `https://udhawan97.github.io/Orifold/`), `release.yml` (zip-only), the live GitHub releases (`release-v0.8.1` with a single `Orifold.zip` asset; rolling `Orifold-latest`), the one-line installer, and the Homebrew cask.
**Revision 2 (same day):** re-audited against main after the toolbar redesign (`37ae9b6`) and the docs Media wiring (`aed19d2`) landed. Corrections: **every existing app screenshot now shows the removed pre-redesign toolbar** — the §2.1 capture session recaptures all of them, and §10 gains a post-toolbar docs pass; the "0 network calls" privacy stat was wrong (the shipped trusted-timestamp feature makes opt-in TSA requests — §3.5/§8b copy rescoped); the shipped artifact's version actually comes from the committed `Orifold/Resources/Info.plist`, not `project.yml` (§5.3.1/§7 corrected); `docs.yml` already has `workflow_dispatch` (§5.4); the "Translate" guides-row item had no docs page to link (§3.3); "verifiable in Adobe" overclaimed for the self-signed default (§3.4).
**Revision 3 (same day) — THE FOLDING STUDIO redesign:** on new direction from Umang (make it fancy/animated like the FolioSenseAI site, keep the origami theme, use the pets Gami & Ori to guide the plot, Apple-grade type). §3 (page structure) and §4 (motion system) below are **fully replaced** with a 7-fold animated scroll narrative — a sheet of washi folded act by act into the crane, Gami guiding the user arc and Ori the developer/trust arc, one red (hanko seal + crane crown), every animation transform/opacity-only and finite (WCAG 2.2.2-clean). Produced via a judge-panel workflow (3 concepts → 3-lens judging → spec → taste + perf/a11y critique). Chosen concept: "The Folding Studio." Locked sections §1, §5–§8 are untouched. See the "Revision 3 deltas" block at the end for §2 pre-work additions and §9/§12 changes. **Also surfaced: a critical app regression — commit `8180b82` silently reverted the TSA timestamp fix (project.yml never declared the network entitlement/ATS, so xcodegen overwrote them); tracked separately, and all page-wide timestamp copy is gated on it (§2.7).**
**Quality bar:** Apple-like restraint — typography-led, spacious, high-contrast, one message per band. Simple but not basic; intentional, refined, trustworthy.
**End-state contract:** `git tag vX.Y.Z && git push --tags` → **zero further manual steps** → the site shows the new version with a working Apple Silicon `.dmg` download, honest Gatekeeper UX, and a clear phased auto-update path.

---

## How this plan was made (iteration record)

This plan went through two full iterations plus adversarial review, per the brief.

### Iteration 1 — base plan (summary)

- **Architecture:** custom non-Starlight Astro landing page inside the existing `docs-site/` build, replacing the Starlight splash at the site root. (Survived review — see §1.)
- **Layout:** 11 alternating-background bands; hero led with a 5.5rem "Orifold" H1, animated crane above it, three CTAs, and `the-orifold-window-annotated.png` as the proof shot.
- **Download:** stable-name asset trick (`releases/latest/download/Orifold.dmg`); dmg built in CI; `workflow_run` trigger to rebuild the site after releases; runtime script that swapped the button to the releases page on any fetch failure.
- **Auto-update:** Phase-1 in-app updater that downloads the zip, strips quarantine, and swaps the bundle in `~/Applications`; Sparkle 2 deferred until Apple notarization.
- **Gatekeeper copy:** "right-click → Open" advice for all macOS versions.

### Adversarial review — 4 critics + 3 web-fact verifiers (what broke)

Four specialist critics (design, macOS release engineering, automation/staleness, web perf/a11y/conversion) and three verification agents (GitHub release/API semantics, Sparkle 2, dmg-in-CI + Gatekeeper) attacked Iteration 1. Highest-impact findings, all evidence-checked:

1. **The chosen hero screenshot self-sabotages.** `the-orifold-window-annotated.png` shows a one-file workspace titled "Untitled" rendering literal *"This is placeholder text…"* copy — directly under a "50 messy files" promise. (Verified by opening the asset.)
2. **The Gatekeeper copy was wrong.** macOS 15 Sequoia **removed** the right-click→Open bypass for unnotarized apps; the only path is System Settings → Privacy & Security → Open Anyway. macOS 14 keeps the right-click path. Some ad-hoc-signed binaries on 15.1+ instead get a dead-end "damaged" verdict. (Web-verified; final copy gated on a real-machine test, §2.)
3. **The Phase-1 updater was impossible.** The app's sandbox entitlements are exactly `app-sandbox` + user-selected read-write + bookmarks — no `network.client`; sandboxed apps can't strip quarantine or replace their own running bundle. (Verified against `Orifold/Resources/Orifold.entitlements`.)
4. **The `workflow_run` trigger silently never fires for tags.** Its `branches:` filter matches the triggering run's head branch, which for a tag push is the *tag name*, not `main` — the site would never rebuild for the one event that matters. (Web-verified; replaced with an explicit dispatch, which GitHub exempts from the `GITHUB_TOKEN` no-retrigger rule.)
5. **Sparkle's deferral rationale was factually wrong.** Sparkle 2's EdDSA verification explicitly supports ad-hoc-signed apps, works sandboxed via bundled XPC services, and strips quarantine on updates it installs. Notarization is not the gate. (Web-verified against Sparkle docs.)
6. **The runtime fallback could downgrade a working button** on a rate-limited shared IP (60 unauthenticated API req/hr/IP), and the publish window (release becomes `latest` before assets finish uploading) could 404 the stable URL.
7. **Measured payload reality:** the crane SVG gzips to **83KB** (not the assumed ~30KB) with 65 infinite SMIL loops + blur filters; the proof shot was specced "lazy-loaded but high fetchpriority" — a contradiction that lazy-loads the LCP element; all captures are 1× on an all-Retina audience.
8. **Light-mode contrast failure:** gray-3 on light canvas measures 3.54:1 — WCAG AA fail on the most conversion-critical small text (version chip, captions).
9. **No mobile story** for a Mac-only app: phone visitors (recruiters clicking a résumé link) would download a 14MB dmg they can't open.
10. **Hero was 9 stacked elements** with the brand name as the largest type on the page — the name already sits in the nav 40px above. Apple spends the headline on the *message*, not the name.

### Iteration 2 — what changed and why

- **Hero rebuilt around the message.** H1 is now "Fold chaos into one clean PDF."; "Orifold" lives in the nav + a small eyebrow. GitHub ghost button cut (it's in the nav). Hero is 5 elements, was 9.
- **Hero screenshot is a specified, blocking deliverable** — capture-content requirements (6–8 mixed files, real title, no self-referential text, 2× resolution) gate the site PR.
- **Gatekeeper UX corrected to verified per-OS behavior**, with a one-line inoculation note directly under the hero CTA and a blocking real-machine dialog test on macOS 14 + 15 before copy is finalized.
- **Phase-1 updater redesigned as check-only** (add `network.client` entitlement, GET `releases/latest`, offer the download page or launch the existing installer `.command`). Privacy copy flips in the same tag.
- **Sparkle 2 re-gated** on EdDSA key custody + appcast CI work — not on the $99 Apple membership.
- **`workflow_run` replaced with an explicit `gh workflow run docs.yml` dispatch** from the release workflow, *after* assets upload — kills the trigger bug and the asset race in one move.
- **Tag ↔ app-version binding CI-enforced:** tagged builds derive `CFBundleShortVersionString` from the tag at package time; a forgotten bump script can no longer ship a v0.9.0 release containing a 0.8.1 app.
- **Atomic release publish:** draft → upload both assets → flip to published+latest → dispatch site rebuild. No publish-window 404.
- **Runtime fallback rewritten confirm-or-upgrade-only** with a 5-state machine, publish-window guard, and ETag caching — it can never downgrade a working button on ambiguity.
- **Crane SVG budgeted:** svgo/precision diet with a **≤25KB-gz hard sub-budget** (else static mark), plays **once** and freezes on the finished crane; reduced-motion users get the finished crane, not the unfolded sheet.
- **LCP fixed:** proof shot eager + `fetchpriority="high"` + preload + explicit dimensions; all captures through `astro:assets` `<Picture>` (AVIF/WebP).
- **Mobile visitors get a real path:** UA-gated CTA swap to "Send this page to your Mac" (share/copy-link).
- **Structure tightened 11 bands → 8, one background** (whitespace + max-3 crease hairlines, no zebra stripes); trust claims said once; **cryptographic signatures promoted to a full-width band** — the undersold flagship.
- **Animation inventory cut 7 → 4 moments**; the one scripted scroll moment is the "fold" animation (the product thesis), now in scope.
- **Docs keep a front door:** the homepage "Popular workflows" grid moves to a proper docs hub page; the landing gets a slim guides row.
- **Light-mode contrast rule:** gray-3 demoted to decorative-only; informational small text uses gray-2. Both-theme Lighthouse gate.
- **Cask upgrade hole closed:** CI pins `version` + `sha256` + versioned URL into `Casks/orifold.rb` per release (today it's `version :latest, sha256 :no_check` — brew users never upgrade); `depends_on arch: :arm64` added.
- **Staleness self-healing:** daily cron rebuild + post-deploy smoke test (grep live HTML for the baked tag; follow the dmg redirect chain to a final 200 — the first hop 302s even for missing assets, so hop-1 proves nothing).

Two review recommendations were **consciously amended rather than adopted**:

- *"Build the dmg only on tagged releases."* Declined: the dmg step stays on every-push `Orifold-latest` (retry-wrapped) so its first real execution is never release day. Demote to tagged-only is the documented fallback if flakiness persists.
- *"Make the hero button scroll to a #download section instead of direct-downloading."* Declined: a primary button that scrolls instead of downloads reads as bait. Direct dmg link + the inoculation line directly beneath it.

Everything below is the final, implementation-ready plan.

---

## 1. Architectural decision

**A custom, non-Starlight Astro landing page inside the existing `docs-site/` build**, replacing the current Starlight splash `index.mdx` at `https://udhawan97.github.io/Orifold/`.

Concretely: delete `docs-site/src/content/docs/index.mdx` from the Starlight content collection and add `docs-site/src/pages/index.astro` — a fully custom page importing `tokens.css` + a new `landing.css`, zero Starlight chrome (no search bar, no docs nav), linking into the docs at their existing slugs. Astro's static routes in `src/pages/` take precedence over Starlight's injected catch-all route.

| Option | Verdict | Why |
|---|---|---|
| **Custom Astro route, same build** | ✅ Chosen | One repo, one deploy (`docs.yml`), shared `tokens.css` so landing and docs are provably one design system, docs URLs untouched, root URL becomes a real product page. |
| Separate site | ❌ | One Pages deployment per repo; a second site means a second repo/pipeline and token drift. Nothing needs it. |
| Upgraded Starlight splash | ❌ | The splash template is why the homepage reads as a manual: "Orifold Docs" H1, search bar, ~72ch column. No full-bleed hero or product nav without fighting the shell. |

**Docs keep a front door.** The current homepage's "Popular workflows" grid (hand-authored `Card` components in `index.mdx`; note `src/data/popular.json` exists but is currently **unused** by anything) does not die with `index.mdx`:

- New docs page `docs-site/src/content/docs/get-started/workflows.mdx` — "Popular workflows" hub. Sidebar entry under Get Started.
- Refactor the grid to read from `popular.json`, and drive the landing's slim guides row (§3.3) from the same file — **one curation source, two surfaces**.
- `astro.config.mjs` redirect: `/docs` → `/get-started/workflows/` (task-first target for the landing nav's "Docs" link).
- Pagefind check: verify "install" / "download" / "combine" still surface after `index.mdx` is deleted; add front-matter keywords to `workflows.mdx` if not.

**Theme handoff (binding):** the landing `<head>` gets a ~10-line inline script that reads Starlight's persisted theme key from localStorage, sets `data-theme` to match, falls back to `prefers-color-scheme`. No theme toggle on the landing. `landing.css` contains **zero raw color values** (review-enforced); e.g. the nav backdrop is `color-mix(in srgb, var(--of-canvas) 80%, transparent)`.

**Alignment note:** `docs/DOCS_PREMIUM_MAKEOVER_PLAN.md` still carries a "Planning only. Not implemented." header, but its substance shipped in commit `91491d8` ("Premium docs makeover: accuracy fixes, pet guides, dev wing, homepage story") — signing docs now describe real cryptographic signatures, stat drift is fixed, the homepage story order exists. Correct that header to "Substantially shipped," and note that the homepage story + the fold-animation deliverable now live on the landing page.

---

## 2. Blocking pre-work (before any landing code)

1. **Capture session** (decides whether the page looks premium at all). **Every existing app capture is content-stale, not just resolution-stale:** all six real PNGs predate the toolbar redesign (`37ae9b6`) and show the removed dense toolbar. The new toolbar is: leading single Add-files button · thinned highlight-led markup capsule (underline/strikeout/eraser behind a disclosure) · trailing Undo·Redo│Search·Share·Inspector·**More** popover (reader mode, comfort, outline, page ops, …); Reader Mode also moved to the View menu (⌘⇧R). Capture on a post-`37ae9b6` build:
   - **Hero proof shot (new):** dark mode, current version, **2× resolution (2400×1504 minimum)**. Content requirements: 6–8 mixed files visible in the sidebar (several PDFs, a PNG screenshot, a scanned form, and one file named `final_final_revised_ACTUAL.pdf` — the brand joke, in pixels), a believable document body with **no self-referential or placeholder text**, a real document title (e.g. "Lease packet — 12 Maple St"). Caption stays honest: "Real capture, v0.8.2, dark mode."
   - **Below-fold trio (recapture, redefine content):** `annotate-markup-tools` (new thinned capsule + its disclosure popover), `night-mode-comparison` (Document Comfort now lives inside the More popover — capture the popover open or the split comparison without the retired toolbar button), `reader-mode-toggle` (the toolbar toggle no longer exists — capture the More-popover switch or the View-menu path instead). Capture at 2× while at it.
   - **`the-orifold-window-annotated.png` (recapture):** used by `get-started/the-window.mdx`; shows the old toolbar and the placeholder-text document.
   - `first-workspace-empty-state.png` shows no toolbar and stays valid.
   - Update `docs/assets/MEDIA_MANIFEST.md` with the new assets and the 2×-for-hero rule, **building on the Media/MP4 wiring that landed in `aed19d2`**; while in there, reconcile its "1600×1000 recommended" window-size spec with the actual capture standard chosen for this session, and fix the reader-mode-toggle row description ("toolbar tucked away" doesn't match the asset).
2. **Gatekeeper dialog verification (blocking for all download copy).** Download the real ad-hoc-signed asset in Safari on clean macOS 14 and macOS 15 machines/VMs; record exact dialogs and escape paths. Expected: macOS 14 = right-click → Open works; macOS 15 = "Apple could not verify…" then Settings → Privacy & Security → Open Anyway → password. If the observed verdict is instead **"damaged and can't be opened"** (seen on some 15.1+ non-validly-signed binaries), the coaching copy must lead with the installer as the primary path and keep `xattr -cr` in troubleshooting only. **Decide from evidence, not hope.**
3. **Crane SVG diet.** `docs-site/src/assets/orifold-crane-fold.svg` is 155KB raw / **83KB gzipped** with 65 `repeatCount="indefinite"` SMIL animations + blur filters. svgo + coordinate-precision pass targeted at ≤96px render; convert to a single finite play-through ending `fill="freeze"` on the completed crane. **Hard sub-budget: ≤25KB gzipped** — if unreachable, ship a static crane mark on the landing and keep the animation docs-only (pre-decided; no renegotiation at build time). Produce a companion static final-frame SVG for reduced-motion.
4. **Starlight route prototype.** Verify custom `index.astro` + deleted splash coexist cleanly: route precedence, 404 page, sitemap, canonical URLs, and the `/docs` redirect under the `/Orifold` base path.

---

## 3. Page structure — The Folding Studio (7 folds + footer, one sheet)

One page = one sheet of washi folded, act by act, into the crane. One continuous ground: dark-indigo `--of-canvas` studio-at-dusk atmosphere in dark theme; the same layout renders correctly under light tokens (theme handoff from §1 is unchanged and binding). Cream paper objects (the sanctioned `--of-paper` family, §4.1), one disciplined red: `--of-tancho` appears **only** on the hanko seal (Fold 3) and the crane's crown (final fold). Arc: promise → gather → shape → seal → keep → breath → take home. Total ≈ 7–8 viewport-heights.

**Global band rules.** Content max-width ~1080px. Acts separated by `padding-block: clamp(5rem, 12vh, 8rem)`. Each act header is a **crease**: kicker (uppercase, `.14em` tracking, `.76rem`, colored `var(--act-accent)`) → H2 (clamp-sized, −0.02em tracking, weight ~640) → the `crease-reveal` entrance (§4) draws a 1px fold-line across the band top as content unfolds. Heading map unchanged: **one H1 (hero); every act heading is H2; card titles are H3.** `html { scroll-padding-top: 72px }`. Kickers are English with a "FIRST FOLD ·" prefix (`第一の折り` style is banned). The **間 act kicker is the page's single CJK glyph** — it earns it because the band embodies the concept. It ships wrapped `<span lang="ja" aria-hidden="true">間</span>` with an sr-only English equivalent ("ma — the margin"). No other CJK anywhere (the former `二·1/2/3` step tiles are re-specified in §3.3 with plain numerals).

**Honesty register (binding, inverted-chrome rule):** traffic-light macOS window chrome appears **only** on real screenshots, never on stylized vignettes. Every real screenshot carries a visible `<figcaption>` "Real capture — Orifold v{captured-on version}" — the version is **pinned per capture in the captures manifest** (§2.1: `docs-site/src/data/landing-captures.json`, one entry per capture: filename → `{ capturedOnVersion, capturedDate }`). Captions render from the manifest pin, **never from live `release.ts` and never hardcoded** — a caption must state the version the pixels were actually shot on, so shipping v0.9 without recapturing cannot silently falsify seven captions. A build check warns when any pin trails the current release by more than one minor. Every stylized vignette carries a small "Illustration" caption. The two visual registers must be distinguishable at a glance.

**Nav (sticky, 56px, unchanged from Revision 2):** left — 28px crane app icon + "Orifold" wordmark (`<span>`, not a heading). Right — `Features · Download · Docs · GitHub`; mobile — `Features · GitHub`. The **Features anchor targets the crease-pattern grid** (`#features`, below the V2 stage) — skimmers bypass the theater entirely. Backdrop `color-mix(in srgb, var(--of-canvas) 80%, transparent)` + `backdrop-filter: blur(12px)`, bottom hairline `--of-separator`. Skip-link first in DOM.

### 3.0 Act map

| # | `id` | Kicker | H2 (verbatim) | Job | Real captures | Vignette | Pet |
|---|------|--------|----------------|-----|---------------|----------|-----|
| 0 | `#sheet` | ORIFOLD · FREE FOR MACOS | **Fold chaos into one clean PDF.** | Promise + CTA | none | V5 (crane, static hero frame) | none |
| 1 | `#fold-1` | FIRST FOLD · GATHER | **Fifty messy files. One sheet.** | Journey begins | `import-files-overview.png`, `language-switcher.png` | V1 Gathering | Gami arrives |
| 2 | `#fold-2` | SECOND FOLD · SHAPE | **Edit the page, not a copy of it.** | Feature proof | `combine-reorder-pages.png`, `edit-text-workflow.png`, `export-save-confirmation.png` | V2 Crease Stage | Gami handoff (band end) |
| 3 | `#fold-3` | THIRD FOLD · SEAL | **A signature that holds up.** | Flagship | `sign-document-digital.png` | V3 Seal | Ori arrives |
| 4 | `#fold-4` | FOURTH FOLD · KEEP | **The studio has no windows.** | Trust | none | V4 No Exit | Ori speaks |
| 5 | `#ma` | 間 · THE MARGIN | **Why this exists.** | Breath | none | none (zero motion) | both, silent |
| 6 | `#final-fold` | FINAL FOLD · TAKE IT HOME | **The crane finishes here.** | Conversion | none | V5 completes (the one animated crane) | Gami coaches, Ori converts devs — both static here |
| — | footer | — | colophon | — | — | — | static marks only |

### 3.1 Fold 0 — `#sheet` (hero)

Two-column grid; mobile stacks crane (~160px) above type. **DOM order is binding: the entire left column precedes the crane markup in the parse stream** — the H1 (the LCP element) must never sit behind kilobytes of SVG.

**Left column, in DOM order:**
1. Kicker: `ORIFOLD · FREE FOR MACOS`.
2. H1: **"Fold chaos into one clean PDF."** — `clamp(2.6rem, 6vw, 4.4rem)`, variable weight ~720, −0.03em, text-fill gradient + `background-clip: text`; `&nbsp;` guard on "clean&nbsp;PDF." **Gradient endpoint is theme-scoped:** dark theme `linear-gradient(120deg, var(--of-text-1) 40%, var(--of-accent-bright))`; light theme ends at `var(--of-accent)` instead (`--of-accent-bright` measures 2.6:1 on the light canvas — below the 3:1 large-text floor, and invisible to Lighthouse because the text is gradient-clipped). Gradient text endpoints, both themes, are named rows in the §4.1 manual contrast pass.
3. Sub (canonical line, **verbatim**, source `docs-site/src/content/docs/index.mdx:23` — copy out before §10 deletes the file): "A free, open-source PDF workspace for macOS. Drop in up to 50 messy files — edit, sign, and export one polished document. Nothing ever leaves your Mac."
4. CTA row: primary stacked-label button **"Download for Mac"** with sub-label `macOS 14+ · v0.8.2 · 14 MB` (all three values baked from `release.ts` at build; refreshed by the §5.5 enhancer; **never hardcoded**; href = stable dmg URL per §5.1). Sub-label gets `min-width` in `ch` + `tabular-nums` so an enhancer version upgrade (`v0.8.2 → v0.10.0`) cannot shift layout. Secondary: mono chip `brew install --cask orifold` with copy button (`copy-flash`; `aria-label="Copy install command"`, confirmation in `role="status"`). Tertiary text links: GitHub · Release notes · Docs.
5. Gatekeeper inoculation line (gray-2, same weight as chips): *"Not notarized yet — first launch takes one extra step. [Here's how →](#final-fold)"* — the anchor jumps to the coaching card (final wording of the coaching itself gates on the §2.2 machine test). `scroll-behavior` is never set to `smooth` (and is forced `auto` under reduced motion, §4.7).
6. Metadata chips (tabular-nums, gray-2): `version` · `released <date>` — baked from `release.ts`, always visible (no-JS-correct). **The runtime SHA chip is cut** — the GitHub refs deref, its sessionStorage cache, the `chip-in` animation, and its failure mode all go with it. Nobody verifies a short hash from a marketing page; the final-fold SHA256 checksum block does the real provenance job. Saves ~0.3KB JS, one animation, one network dance beside the primary CTA.

**Right column:** the crane, large (~38% of the grid), **no container, no chrome, no screenshot** — the mark is the product shot. **The hero crane is the static one-fold-short frame** (§2.3): a designed, first-class composition — a composed pose chosen by eye to read as intentional sculpture, expectant, not crumpled — shipped as a small inline SVG or `<img>` (~2–3KB), crownless (the hero crane never shows red), identical in every mode (JS, no-JS, reduced-motion). The single animated crane instance lives at `#final-fold` (§3.7). *Upgrade path only:* if the §2.3 rebuild lands under ~28KB raw, a second inline animated instance paused at `data-pause-t` may replace the hero static — gated on the §2.3 go/no-go, never assumed. (The old "two instances gzip-dedupe" premise is deleted: gzip's 32KB window cannot back-reference a second copy of an asset this size — measured 0% dedup.)

**Ambient background (entire hero ambient system, nothing else):**
- Static washi grain: inline `<svg>` `feTurbulence` tile, ~3% opacity, CSS-masked to fade below the fold. **Zero animation, ≤1.5KB raw.**
- Two fold-shadows: full-bleed `--of-fold-shade` linear-gradient wedges (light raking across a creased backdrop), each its own composited layer, `will-change: transform`, drifting ±30px via `shade-drift-a` (26s) / `shade-drift-b` (34s), transform-only, `.in-view`-gated — and **finite: `animation-iteration-count: 2`, ending at the rest position** (keyframes authored to return home). WCAG 2.2.2 requires a mechanism for >5s auto-motion; a finite drift that settles needs none, and the dusk mood survives — the light rakes twice, then the studio is still.

**No pet in the hero** (decided; rejects the hero-Gami graft). The hero keeps *ma*; Gami is one scroll away and the inoculation line + chips already do the hero's coaching work. Do not re-add — see §4 mascot-drift rule.

**Fold budget (acceptance-gated):** at 1280×700 and 1440×780 the primary CTA and the crane must both be fully visible. Hero and crane are **excluded from `crease-reveal`** — they paint immediately. With no hero raster and a static crane, **LCP is the H1 text block** (inline `<svg>` is not an LCP candidate in Chromium), fetch-free. One tall-viewport spot-check (1200×1920) is added to §12: if Fold 1's capture enters that initial viewport, that one image drops `loading=lazy`.

### 3.2 Fold 1 — `#fold-1` GATHER

- H2: **"Fifty messy files. One sheet."** Sub: "A 'simple PDF task' is rarely simple. It is six PDFs, two screenshots, a Word document, a scanned form, and one determined file named `final_final_revised_ACTUAL.pdf`."
- **V1 — The Gathering** (stylized, pure CSS, "Illustration" caption):
  - DOM: `<figure class="gather"><div class="scrap" data-kind="pdf|img|docx|scan">×7</div><div class="stack"><div class="stack-sheet">×3</div></div></figure>`. Scraps = skewed cream rects (`--of-paper` fills, `--of-paper-edge` borders, `--of-fold-shade` diagonal gradients) with tiny type-glyph labels; scattered via per-scrap custom props `--tx/--ty/--rot`. The top scrap carries the **dog-eared corner token** (`.sheet-token`, a folded-corner pseudo-element) — this exact motif recurs in V2/V3/V4 as the "one sheet" traveling the page.
  - On reveal (entrance-once): `scrap-settle` — each scrap translates/rotates to the stack and fades as the three stack sheets rise; 0.5s each, staggered 80ms, `cubic-bezier(.22,1,.36,1)`.
  - Ambient: `corner-lift` on the top stack sheet **only** (one node, 7s, ±2px rotateX corner curl) — **finite: `animation-iteration-count: 2`, re-armed on each `.in-view` re-entry** via class toggle (2.2.2-compliant without a control), and **suspended whenever any pet is idling** (§4.4 single-idler extension).
  - No window chrome (illustration register).
- Real proof beside it: `import-files-overview.png` (mid-drag "Release to import" capture) through `astro:assets` `<Picture>`, lazy (except under the §3.1 tall-viewport rule), explicit dims. Caption (manifest-pinned version): "Real capture — Orifold v0.8.2. Drag anything in; broken PDFs are repaired on the way."
- Copy row beneath: merge up to 50 files · drag-in import · sidebar page-thumbnail drag reordering (new, `6285b4d` — say it plainly: "Drag pages around in the sidebar until the story reads right.").
- **Gami enters** (margin, `pet-arrive` + `bubble-pop`, §3.9 roster line 1). Directly beneath Gami's figure, small: `language-switcher.png`, captioned **"Real capture — Gami greets you in the app, in six languages."** — the honesty anchor proving the guides live in the product, placed at the exact moment a visitor could suspect mascot-ware. This is the page's **only** Gami mention outside roster bubbles (see §3.3 card 6).

### 3.3 Fold 2 — `#fold-2` SHAPE

- H2: **"Edit the page, not a copy of it."** Sub (shipping default): "Click the text, fix the typo. Real glyph geometry — not a sticky note floating over a picture of one." **Copy gate (§2.10):** the stronger "…on the real page" clause is restored only if the export path is verified to preserve original text layers post-`PDFImportNormalizer`. The import-side fix shipped; the export side is documented as unresolved — until verified, the sub claims the edit (which IS in-place), not whole-page byte-fidelity. The H2 stands either way.
- **V2 — The Crease Stage** (sticky stage; real captures inside, so each scene keeps window chrome + its own "Real capture" caption; the fold *framing* is obviously theatrical):
  - DOM: `<section class="stage-wrap"><div class="stage" data-step="1"><div class="scene" data-scene="1|2|3">×3</div></div><div class="step" data-step-for="1|2|3">×3</div></section>`. `.stage` is `position: sticky; top: 16vh; height: 62vh`; **total stage travel is bounded: `stage-wrap` height ≤ ~220vh (~70vh per step)** — acceptance-checked in §12; an unbounded pinned section between hero and features is the classic skim-killer. Scenes absolutely stacked, active scene = `[data-step]` attribute match; cross-fade = opacity + `translateY(12px) scale(.985)` transition, 0.5s, **with `visibility` toggled alongside opacity** (visibility transitions cleanly with the crossfade) so inactive scenes leave the accessibility tree and can never be read or focused while invisible. Step text blocks each open with a **numbered tile — plain `1`, `2`, `3`** — 40px cream tile (`--of-paper`), fold-shade edge; the "SECOND FOLD" kicker already numbers the act, and 間 stays the page's single CJK moment. Steps are observed at viewport center (`rootMargin: -45% 0px -45%`) to flip `data-step`.
  - Scene 1 — *open*: `combine-reorder-pages.png` (3-document sidebar) slides onto a paper "workbench" mat (cream rounded rect, fold-shade edge), `translateY(16px)` settle.
  - Scene 2 — *shape*: `edit-text-workflow.png` (selection + floating format toolbar); `crease-sweep` draws a 1px light line across the selection area once per step-activation (entrance-per-step; re-fires on revisit because the animation is gated on the attribute selector). Implementation pinned: `transform: scaleX(0→1)`, `transform-origin: left` — never width/left.
  - Scene 3 — *export*: **`sheet-close`, register-safe by construction:** `export-save-confirmation.png` renders **untouched, readable, at rest first**, carrying its own "Real capture" figcaption while visible. Then two **cream ILLUSTRATION halves** (top half `rotateX(0→-178deg)`, `transform-origin: bottom`, a `--of-fold-shade` gradient overlay darkening keyed to the fold, `backface-visibility: hidden`) fold closed **over** it — the capture is never itself warped, skewed, or folded (a chrome-bearing screenshot 3D-folding into origami is exactly the register blur the inverted-chrome rule exists to prevent). The resulting packet carries **no window chrome**, sits in illustration register with the `.sheet-token` corner, and "one clean PDF" is the *packet's* label. 3D transforms enabled only under `@media (pointer: fine)` **and** motion-OK; otherwise a flat opacity/translate settle. **Kill-switch is pre-decided (§4): if the fold doesn't read as paper in the first build, ship the flat settle. No renegotiation.**
  - Reduced-motion / mobile ≤720px / no-JS: stage un-stickied into a static column — three captioned figures in order. No content is JS-injected.
- **Crease-pattern grid** (`id="features"` — the nav anchor target) below the stage: six `.of-card`s (H3 + one-line quip + docs link, inline SVG glyphs, `card-lift` hover only):
  1. **On-device OCR** — "⌘F finally works on that thing your printer emailed you."
  2. **Compress** — "Attachments that stop bouncing off email size limits."
  3. **Fill & flatten forms** — "Finished paperwork, no third-party e-sign service."
  4. **Stamps & Bates** — "Numbered, stamped, and ready for the file room."
  5. **Reader mode** — "The toolbar folds away. The page stays."
  6. **Six languages** — "The whole workspace, menus to tooltips, in six languages." → links `settings/language` docs. *(Gami cut from this quip — a third mascot mention in two folds was cuteness doing no coaching where the feature proof should carry the band; the §3.2 honesty caption keeps its Gami because it proves the guides live in the app.)*
- Guides row beneath the grid, driven from `popular.json` (one curation source, §1 contract unchanged): "More jobs: Combine · Stamps & Bates · Protect · Sign →". Add the missing Stamps & Bates entry to `popular.json` during PR-2 (carried over).
- **Handoff beat (band end):** a sentinel element at the fold-2/fold-3 boundary. As it crosses viewport center, Gami's second bubble appears in Fold 2's margin (roster line 2) and `body[data-guide]` flips `gami → ori` — the page's single mood shift (§4.5) fires **on the handoff itself**, warming the fold-shadows and `--act-accent` toward tancho over 1.2s. **One mover only:** Gami's SMIL is already paused at this point (static figure — the single-idler rule §4.4 is not suspended for the showcase beat); the tint shift plus **Ori's lynx-tip twitch as Fold 3 scrolls in** *is* the handoff. (The former "Gami's ears settle" beat is deleted — it choreographed two pets animating in one beat, failing the spec's own §4.4 audit.) Reversal hysteresis per §4.5.

### 3.4 Fold 3 — `#fold-3` SEAL (flagship)

- H2: **"A signature that holds up."** Lede: "A drawn mark is a picture. A digital signature is math — a tamper-evident seal over the exact bytes you signed."
- **V3 — The Seal** (stylized, no chrome, "Illustration" caption):
  - DOM: `<figure class="seal"><div class="sheet"> <span class="sig-line"/> <span class="hanko"/> <span class="tsa-tag"/> <ol class="chain"><li>×3</li></ol> <ul class="verify"><li>×3</li></ul> </div></figure>`. The `.sheet` carries the `.sheet-token` corner.
  - Entrance sequence (chained delays, entrance-once): `hanko-stamp` — round `--of-tancho` seal scales 1.3→1 with a 2px settle "thud" (0.35s, ease-out) — the page's first red; then `tag-thread` — a paper tag reading "RFC 3161 · FreeTSA" swings in on a hairline thread from the corner, exactly 1 damped oscillation (0.9s), rests; then the **chain row** — three small linked nodes `document hash → certificate → trusted timestamp` unfold left-to-right (`verify-unfold`, staggered 120ms) — this teaches what PAdES actually is; then the verify list — "Document unchanged · Signer verified · Time attested" — same `verify-unfold`, staggered 120ms.
  - **No ambient loop. A seal sits still.**
- Real proof beside it: `sign-document-digital.png` (Digital palette with the FreeTSA / DigiCert / Sectigo / GlobalSign timestamp-provider picker — exists as of `dacf430`). Caption (manifest-pinned version) carries the honest caveat verbatim from the docs' wording: "Real capture — Orifold v0.8.2. Verifies as intact in Adobe and any PAdES-aware viewer; the zero-setup self-signed identity shows as 'unknown signer' until trusted." (Not a flat "verifiable in Adobe" — Revision 2 ruling stands; caveat source is the Callout in `fill-sign/signatures.mdx` ~lines 64–65.)
- Copy columns: what it does (PAdES signatures, Keychain and .p12 identities, optional RFC 3161 trusted timestamps) / why it matters (one honest line on image-of-ink vs. seal). CTA link: "How signing works →".
- **⚠️ Copy gate (page-wide — see the §12 gate list):** every timestamp mention on the page is **blocked on the §2.7 project.yml durable TSA fix** — this act's lede/copy, the `tag-thread` tag text, this capture's caption, **and Fold 4's "0" stat sub-line** (§3.5). Main regressed the entitlement/ATS layer in `8180b82`; until `project.yml` itself carries `network.client` + the ATS exceptions, any timestamp sentence describes a feature the shipped app cannot perform. PR-2 does not merge with timestamp copy anywhere unless that commit is on main; the §12 list enumerates every gated string so the gate is grep-able, not a per-band footnote.
- **Ori arrives** (roster line 3): "Real cryptography. Not a picture of ink." — the flagship's whole argument in eight words, doubling as her half of the handoff exchange.

### 3.5 Fold 4 — `#fold-4` KEEP

- H2: **"The studio has no windows."** Lede: "Everything happens on your Mac. The cloud was not consulted."
- **V4 — No Exit** (stylized diagram, no chrome, "Illustration" caption):
  - DOM: `<figure class="studio"><div class="mac-outline"><div class="sheet"/></div><span class="egress">×3</span><span class="slip">×3</span></figure>` — a thin-line Mac silhouette.
  - On reveal (entrance-once): the sheet (with `.sheet-token`) folds *into* the silhouette (reuse `sheet-close`, flat-settle fallback identical to V2's); three faint dotted egress arrows toward the band edges draw and then **retract** (`egress-retract` — implementation pinned in §4.2: `scaleX` grow-then-shrink from the sheet edge + opacity arrowhead, transform/opacity only; the anti-"converging signals": attempted exits get pulled back); then the **sanitize slip**: three small chips labeled `metadata · edit history · comments` slide out of the sheet's edge and fade (`slip-out`, staggered 100ms) — the WP-8 claim made visible instead of merely stated (honest as of `e320866`: qpdf sanitize now strips the Orifold workspace blob too).
  - Static line beneath (plain text, tabular, no marquee): "No analytics · No accounts · No uploads".
  - Ambient: **none.**
- Stat row (`Stat.astro` pattern, values from `stats.json`/`release.ts`, never hardcoded in copy):
  - **0** — telemetry, analytics, accounts. Sub-line **gated on §2.7 like all timestamp copy**: post-fix it reads "The only thing Orifold ever asks the network for: a trusted timestamp, when you request one while signing." Pre-fix stub (must ship instead if §2.7 slips): "The app asks the network for nothing." *(flips via `site.json.appNetworkCheck` when PR-4 ships — unchanged §3.5/§8b machinery)*
  - **AES-256** — "Real encryption, not a 'protected' flag a reader can ignore."
  - **Sanitize** — "A file that carries nothing you didn't intend to send." (Now strictly true post-WP-8.)
  - **555 tests** gate every release — **only after the §2.6 `stats.json` fix lands** (currently 503, stale by 52); the number renders from `stats.json`, never from copy.
  - **Entitlements** — copy reads **"a handful of narrow entitlements, listed in the docs"** with a link to the entitlements file + `settings/privacy` docs. **Do not print a count** until the §2.7 project.yml fix is durably on main (main currently has 3 keys, `stats.json` says 4, `privacy.mdx` says "exactly four" — three surfaces, three answers; a printed number here would be the fourth). After the fix: may flip to the real count, sourced from `stats.json`.
  - **Free forever, MIT** · **6 languages**.
- One honest clause, small text (carried over verbatim): "This page asks GitHub for the latest version number so the button below is always current. The app never does."
- **Ori speaks once** (roster line 4): "Don't trust me. Read the source. I did." — bubble links to the GitHub repo.

### 3.6 `#ma` — 間 · THE MARGIN

- H2: **"Why this exists."** Body ≈120 words, builder voice, starting from the shipped copy: "I built Orifold because basic file work on a Mac should not require a subscription, an upload, or a small ceremony. Preview is excellent until the job gets complicated; the more capable tools rent your own files back to you. …" (Extend to ~120 words in the same voice: honest, lightly playful, no superlatives.)
- **Zero animation. Zero vignette. Maximum negative space** — `padding-block: clamp(8rem, 20vh, 12rem)`, content max-width 56ch, centered.
- Both pets at rest in the far margin: static `gami-figure.svg` + `ori-figure.svg` (the real PaperFigure-geometry versions), no bubbles, no SMIL, no entrance beyond the standard `crease-reveal` of the band. The one purely ornamental pet moment on the page.

### 3.7 `#final-fold` — TAKE IT HOME (download band; absorbs old §3.7 in full)

- H2: **"The crane finishes here."**
- **V5 completes — the band's ONLY motion:** the final-fold crane (the page's **single animated inline instance**, §2.3), initialized at `data-pause-t`, resumes on a one-shot IO (threshold 0.5) and plays its last fold (~1.2s); on SMIL end, `tancho-set` pops the red crown dot (scale .6→1, 0.3s, once per session — a `sessionStorage` flag prevents replay on back-navigation). **The only red-on-crane on the page.** Zero ambient cost after completion. **Both pets render pre-arrived here:** static figures, bubbles pre-shown as styled captions (the reduced-motion treatment, promoted to default in this band) — no `pet-arrive`, no `bubble-pop`. Four entrance systems firing around the primary Download button would make the pets compete with both the crane payoff and the CTA; the eye path is crane → CTA, nothing else moves. Added to the §4.6 audit table.
- **Download column (machinery unchanged from Revision 2 §3.7/§5):**
  - Primary `Download for Mac` + metadata row (size baked from the **dmg** asset's `size` field; stable URL §5.1; build-time state canonical; §5.5 enhancer confirm-or-upgrade only).
  - Apple Silicon explainer, plain language, verbatim from Revision 2: "Needs a Mac with an Apple M-series chip — that's any Mac from 2020 on ( → About This Mac to check). Intel Macs aren't supported **yet**." — "yet" links the Intel-demand GitHub issue. Copy, not detection (Safari reports `MacIntel` on both).
  - **First-launch coaching card** (`.of-callout-note`, always visible), per-OS, **final copy pending the §2.2 machine test** — spoken by **Gami** (roster line 5): the bubble is the card's intro ("One-time thing. Two seconds. Here's how —"), the card body carries the verified per-OS steps: macOS 14 right-click→Open path; macOS 15 Settings → Privacy & Security → Open Anyway path; "Prefer zero dialogs? The one-line installer clears quarantine for you." Signed-era copy pre-written behind `site.json.signedBuilds` ("Signed and notarized by Apple."), collapsing the card.
  - SHA256 verify block: mono chip with the checksum command + copy button (`copy-flash`; labeled per §4.1 a11y rules).
  - **Other ways to install** (`.of-details`, collapsed): curl one-liner (verbatim, "no dialogs — curl downloads aren't quarantined"), Homebrew cask, direct zip. Small: "All releases →".
- **Developer column** — "Build it yourself": a paper-styled terminal card (**no traffic lights** — it's stylized, and chrome is reserved for real captures; a plain mono card with a `❯` prompt) containing the clone/build lines with a copy button, plus the Homebrew chip repeated. Anchored by **Ori** (roster line 6): "Doubt me? Build it yourself." Both pets thus bow the visitor out — Gami closes the user arc, Ori closes the dev arc.
- **Non-Mac UA gate** (unchanged detection: `userAgentData.platform`/`navigator.platform` ≠ Mac **plus** `maxTouchPoints > 1` for iPadOS): **the detection branch runs synchronously in the inline IIFE, before first paint** — it needs no network, so non-Mac visitors never see a flash-and-shift CTA swap; only the release-version fetch stays async in the §5.5 enhancer. Primary CTA swaps to **"View on GitHub"** with sub "Orifold is a Mac app."; a secondary link "Send this page to your Mac" backed by `navigator.share` with copy-link fallback; the dmg link demotes to small text. Build-time (no-JS) state stays the dmg button, so desktop-no-JS remains correct. Applies to hero + final fold identically.

### 3.8 Footer (colophon)

- "**Folded by hand. MIT licensed.**" · crane mark (static) · Docs · What's New · Privacy · GitHub · License · `v0.8.2 · released 2026-07-XX` (baked, links the release).
- Tiny static `gami-mark.svg` + `ori-mark.svg` (24px) as maker's marks beside the colophon — decorative, `aria-hidden="true"`, no bubbles, no animation.
- Signature line kept: "Since nothing you do in Orifold ever leaves your Mac, stars are the only telemetry we get. ⭐"
- **No easter-egg quip cycler.** (Reference skip; enforced.)

### 3.9 Pet-guide roster — complete and closed (6 bubbles; the ceiling)

Principle: **residents, not tour guides.** Figures sit at band outer margins, never overlapping content. Every line must **coach or prove**; a line that is merely charming gets cut in review — this is a binding editorial rule, and the mitigation for mascot-drift (the design's self-identified weakest point). Gami speaks to users, Ori to the technically-minded — same convention as the docs. **Adding a seventh bubble requires deleting one of these six.**

| # | Where | Who | Line (final copy) | Job |
|---|-------|-----|-------------------|-----|
| 1 | Fold 1, on arrive | Gami | "Bring the whole messy pile. I'll keep it straight." | Orients the import act *(recast: the old "Drop everything on me" invited a drag-drop affordance the page can't honor and cast Gami as a drop target)* |
| 2 | Fold 2→3 handoff sentinel | Gami | "Signatures are Ori's craft. Over to her." | Handoff beat, half 1 — **provisional**: by the roster's own rule this is the merely-charming line (the tint + line 3 already carry the handoff); it must argue for its life in PR-2 review or the roster drops to five |
| 3 | Fold 3, on arrive | Ori | "Real cryptography. Not a picture of ink." | Handoff half 2 + the flagship argument |
| 4 | Fold 4 | Ori | "Don't trust me. Read the source. I did." | Credibility → GitHub link |
| 5 | Final fold, coaching card | Gami | "One-time thing. Two seconds. Here's how —" *(final wording gated on §2.2)* | Gatekeeper coaching as care |
| 6 | Final fold, dev column | Ori | "Doubt me? Build it yourself." | Converts the developer persona |

Rejected placements, do not re-add: hero pet (hero keeps *ma*), scroll-following rail, footer quips, `#ma` bubbles.

**Markup contract (no-JS-safe, AT-quiet):** each pet is plain HTML in document flow — inline SMIL SVG (animated) + `<img>` static figure sibling, plus a `<p class="bubble">` containing the line. **Default visibility is inverted for compliance: the static `<img>` figure shows by default; the inline SMIL SVG is revealed only under `html.js`** (no-JS therefore serves compliant static pets — the shipped SMIL assets loop indefinitely, which fails 2.2.2 ungated). Nothing is JS-injected; JS only adds classes/gating. **The bubble is the accessible content, encountered once in natural reading order — the former `aria-live` mirror is deleted** (it double-announced every line and interrupted mid-read based on scroll position). The inline SVG root gets `aria-hidden="true"` applied at inline time, overriding the assets' shipped `role="img"`/`aria-label` (§2.5); the bubble sits outside the hidden wrapper.

### 3.10 Mobile (≤720px)

Pet figures collapse to the 24px `gami-mark.svg`/`ori-mark.svg` inline beside the bubble text, rendered as a quiet caption row **above** the band content — no absolute positioning, no overlap risk. V2 un-stickies (static column). Fold-shadows drop to one static wedge. Crane hero ~160px (static frame). Nav per §3.0. CTA UA-gate per §3.7.

---

## 4. Visual, a11y & performance rules — motion system, budgets, fallbacks

### 4.1 Design rules (carried over, binding — with one recorded exception)

- **Tokens frozen, one sanctioned amendment.** The design's core material — cream paper — is currently unspecifiable: tokens.css has no paper token, and light theme has no cream that survives the #eef0f2 canvas. One tokens.css amendment ships with PR-2 and is the **only** token change: `--of-paper`, `--of-paper-ink` (text on paper), `--of-paper-edge` (border/fold-shade edge), each defined per theme. **Light-theme paper must carry a visible edge (1px `--of-paper-edge` border or baked fold-shade) measuring ≥3:1 against the canvas** — V1 scraps, the V2 workbench mat and step tiles, V3/V4 sheets, the dev terminal card, and every `.sheet-token` are captioned informational illustrations, so WCAG 1.4.11 applies to their essential edges. Beyond that amendment: `landing.css` contains **zero raw color values** (review-enforced); every color is a `tokens.css` variable or a `color-mix()` of one. Radii 10/8/5; system font stack only, fractional variable weights allowed (640/720), `font-variant-numeric: tabular-nums` on all numeric surfaces. No new fonts, no other new colors, no textures, no animation libraries.
- **One red:** `--of-tancho` exactly twice — the V3 hanko and the final-fold crown. The Fold-3 accent warm-shift uses `color-mix`, never raw tancho on text.
- **Contrast rule (extended):** gray-3 decorative-only; all informational small text (chips, captions, footer meta) uses gray-2 **on canvas-family surfaces only**. **Bubble surfaces are pinned:** either canvas-family background + gray-2 text, or `--of-paper` background + `--of-paper-ink` text — **never gray-2 on paper** (dark-theme gray-2 on cream measures ~1.5:1). The both-theme manual contrast pass gains named rows: every cream surface + its edge (both themes), every bubble pairing (both themes), and the H1 gradient text endpoints (both themes — Lighthouse cannot evaluate gradient-clipped text).
- **Chrome-honesty rule:** window chrome on real captures only (§3.0). Capture captions render from the captures manifest pin (§2.1), never live `release.ts`.
- **Semantics:** real alt text, `<figcaption>` everywhere, `<nav>` + skip-link, `:focus-visible` tokens, `aria-hidden` on decorative glyphs and pet figures (bubble text is the accessible content, single-channel — no live-region mirror), copy buttons carry `aria-label` ("Copy install command" etc.) and their "✓ Copied" confirmation lives in a `role="status"` element, CJK glyphs wrapped `<span lang="ja" aria-hidden="true">` with sr-only English equivalents, `prefers-reduced-motion` honored everywhere per §4.7, `scroll-behavior: auto` forced under PRM (smooth is never set anyway).
- **Acceptance gate:** Lighthouse ≥95 performance & accessibility **in both themes**; fold-budget check at 1280×700 and 1440×780 plus the 1200×1920 LCP spot-check; §4.6 ambient audit (boundaries included); §4.7 matrix walked manually; the manual contrast pass above.

### 4.2 Keyframe inventory — complete and closed (nothing else moves)

Universal ease: `--ease-fold: cubic-bezier(.22,1,.36,1)`. Durations are tokens, not magic numbers. **Every implementation is pinned to transform/opacity — the four former holes (egress-retract, card-lift shade, crease-sweep, pet-arrive sweep) are now specified, not implied.**

| Keyframe | Type | Duration / details |
|---|---|---|
| `crease-reveal` | entrance | 0.5s; 1px fold-line `scaleX(0→1)` along block top + content `rotateX(-6deg)→0` + fade; the **only** block-entrance grammar. (Deliberately not blur-resolve: blur is repaint-expensive and reads "lens," not "paper.") |
| `crane-fold` (SMIL) | entrance | **final fold only** (single animated instance): initialized at `data-pause-t`, resumes on IO, ~1.2s remainder, `fill="freeze"`. Hero uses the static frame — no hero SMIL in any mode |
| `tancho-set` | entrance | 0.3s crown pop, once per session; crown is a non-SMIL node, transparent by default (§2.3); no-JS fallback via scoped CSS (§4.7) |
| `scrap-settle` | entrance | V1; 0.5s each, 80ms stagger |
| `sheet-close` | entrance | V2 scene 3 + V4; two cream illustration halves, rotateX with shade gradient keyed to fold angle; the real capture beneath is never transformed (§3.3); `pointer:fine` + motion-OK only; **kill-switch: flat settle** |
| `crease-sweep` | entrance-per-step | V2 scene 2; 0.6s; **`transform: scaleX(0→1)`, `transform-origin: left`** — width/left banned |
| `hanko-stamp` / `tag-thread` / `verify-unfold` | entrance | V3 chain: 0.35s / 0.9s (1 damped oscillation) / staggered 120ms |
| `egress-retract` / `slip-out` | entrance | V4; **rebuilt composited: dotted line = `scaleX` grow-then-shrink from the sheet edge, arrowhead = opacity** (stroke-dashoffset is paint-level, banned) / 100ms-staggered chip slide (transform/opacity) |
| `pet-arrive` / `bubble-pop` | entrance | 0.5s slide-in 24px + 6° rotateZ settle + fold-shade sweep — **sweep = a translating gradient overlay (`transform`); `background-position` explicitly banned**; bubble 300ms later, scale .92→1. Not used in `#final-fold` (pets pre-arrived, §3.7) |
| `corner-lift` | ambient (finite) | V1 top sheet, 7s, **`animation-iteration-count: 2`**, one node, re-armed per `.in-view` re-entry, suspended while any pet idles (§4.4) |
| `shade-drift-a` / `shade-drift-b` | ambient (finite) | hero wedges, 26s/34s, **iteration-count 2, keyframes end at rest position**, transform-only, IO-gated |
| pet SMIL idle (wag/twitch) | ambient (gated) | JS-gated, **≤4.5s window per entry** (3 wag cycles = 3.9s — same feel, under the WCAG 2.2.2 5s line with no pause mechanism needed), §4.4 |
| `card-lift` | interaction | hover translateY(−2px) 0.15s; **shade deepen = pre-rendered shadow on a pseudo-element, opacity crossfade only** (box-shadow animation is banned by this table's own rules) |
| `copy-flash` | interaction | "✓ Copied" 1.4s revert, mirrored to `role="status"` |

*(Removed: `chip-in` — the SHA chip is cut, §3.1.)*

**Banned (unchanged in spirit, updated in letter):** blanket scroll reveals *other than* `crease-reveal`, parallax, marquee/ticker, count-up numbers, hover glows, cursor followers, scroll-linked/scroll-jacked elements, autoplay video, mousemove parallax, hotspot tours, animation libraries, blur-based reveals, `box-shadow`/layout-property animation, `stroke-dashoffset` animation, `background-position` animation. Everything animated is `transform`/`opacity` only — with zero undeclared exceptions (SMIL crane/pets excepted as finite/gated SMIL, not CSS).

### 4.3 Reveal observer

One `IntersectionObserver`, threshold 0.15, one-shot: adds `.is-revealed`, then `unobserve`. Elements opt in via `.crease`. Hidden pre-state (`opacity:0; transform:rotateX(-6deg) …`) applies **only under `html.js`** — and the `html.js` classlist snippet (plus the synchronous UA-gate branch, §3.7) is **the first element of `<head>`, executing before first paint**; otherwise every `.crease` paints visible then hides — a flash plus a shift. No JS ⇒ everything visible statically. Reduced-motion ⇒ observer never registered **and** the CSS `@media` nuke applies (triple defense: JS branch + CSS media + no-IO fallback). Hero and the final-fold crane are never observed by it.

### 4.4 Pet controller

One shared `.in-view` IO (threshold 0.35) over pet-band wrappers + ambient-vignette wrappers.

- **Arrival:** first intersection adds `.pet-arrived` → `pet-arrive` fires, `bubble-pop` follows at +300ms. **No live-region announcement** — the bubble is in-flow accessible text encountered once in reading order (the mirror double-announced and interrupted mid-read; deleted).
- **Idle gating (SMIL; on-disk assets untouched, inline copies restructured — §2.5):** on load, JS calls `svg.pauseAnimations()` on both inline pet SVGs (they're inline, so this works; it's also why they must be inline). On band entry: `setCurrentTime(0)`, `unpauseAnimations()`, and a **≤4.5s** `setTimeout` re-pauses — 3 full wag cycles (3.9s), under the WCAG 2.2.2 5s line by construction. **Paint-cost rule:** SMIL is main-thread and both pets animate inside filter subtrees (feDropShadow / feTurbulence) as shipped; the **build-time inline copies** hoist animated groups out of the filter subtree (bake the drop shadow as a static path or filter only non-animated siblings) and keep grain rects out of the animated invalidation region. Acceptance: DevTools paint-flashing during the idle window shows tail/ear-sized invalidations only, never full-figure repaints.
- **Single-idler rule (extended):** a module-level ref holds the currently idling pet; a new band entry pauses the previous immediately. **≤1 pet animating at any scroll position** — acceptance-checked (the cat's two concurrent animateTransforms count as that one pet, but the paint audit covers them). While any pet idles, the controller also **suspends `corner-lift`** — this is what keeps the hero/fold-1 boundary under the §4.6 cap.
- **Handoff sentinel, with hysteresis:** the primary sentinel at the fold-2/3 boundary (rootMargin `-45% 0px -45%`) toggles Gami's bubble 2 and flips `body[data-guide]` to `ori`. **The reverse flip fires only when a second sentinel, placed ~one viewport-height above the first, re-enters** (equivalently: reversals debounced ~2s) — a reader dwelling at the boundary must not strobe the 1.2s page tint. At the handoff, Gami is already paused (static); only Ori moves (§3.3). No exit animations — pets never chase the scroll.
- **Reduced-motion:** static `*-figure.svg` `<img>` shown (it's the default); inline SMIL stays hidden; bubbles render pre-shown as styled captions; controller never unpauses SMIL.
- **No-JS:** **static figures show by default** (the inline SMIL SVG is revealed only under `html.js` — §3.9 markup contract) — no-JS serves compliant static pets instead of indefinite SMIL loops; bubbles visible; nothing missing. The JS gate is purely additive.

### 4.5 Act tint — two states, bound to the narrative

`body[data-guide="gami"]` (default) / `body[data-guide="ori"]` (set at the handoff sentinel; reverted via the §4.4 hysteresis sentinel). Under `ori`: `--act-accent: color-mix(in srgb, var(--of-tancho) 22%, var(--of-accent))`.

**Implementation is pinned composited:** background gradients do not interpolate, and unregistered custom properties transition discretely — so the fold-shadow warming is **not** a transition on the gradient. Each wedge carries **both tint states pre-painted as two stacked gradient layers**, and the flip crossfades their `opacity` over 1.2s (composited; no full-bleed repaint mid-scroll — the sentinel fires exactly while the user is scrolling, the worst paint timing). Kicker/text consumers transition `color` only (tiny paint areas), optionally via an `@property`-registered `--act-accent` with `syntax: '<color>'` — **an animating custom property must never feed the full-bleed gradients.** That's the entire per-act tint system — the single mood shift **is** the Gami→Ori handoff beat. No other act recolors anything.

### 4.6 Ambient-motion cap — ≤3 concurrent **at any scroll offset, band boundaries included**, composited-only (audited)

| Scroll position | Ambient nodes running | Count |
|---|---|---|
| Hero | shade-drift ×2 (finite, 2 cycles, freeze at rest) | ≤2 |
| **Hero/Fold-1 boundary** | shade-drift (if still cycling) ×2 + Gami idle window; `corner-lift` suspended while Gami idles (§4.4) | ≤3 |
| Fold 1 | corner-lift (finite ×2) **or** Gami idle — never both (single-idler suspension) | ≤1 |
| Folds 2–4 (and their boundaries) | ≤1 (pet idle only, only while its band is in view) | ≤1 |
| `#ma` | none, by design | 0 |
| Final fold | crane finite play (~1.2s) + crown pop; **pets static, pre-arrived — zero pet motion** (§3.7) | ≤1 |

Every ambient is `.in-view`-gated (CSS `animation-play-state: paused` until the class lands; SMIL via the controller) **and finite** (iteration counts above) — the page has no infinite auto-motion anywhere, which is what makes it WCAG 2.2.2-clean without an on-page pause control. The §12 acceptance audit samples **the four band boundaries explicitly**, not just band centers, with DevTools paint flashing.

### 4.7 Reduced-motion / no-JS matrix — every moving part, its fallback

| Moment | Reduced-motion | No-JS |
|---|---|---|
| `crease-reveal` | fully visible, no transition | fully visible (pre-state gated on `html.js`) |
| Hero crane | static one-fold-short frame (same as default — it's static in every mode, crownless) | same static frame |
| Final-fold crane | static final-frame companion (crown set) via `@media` swap, JS-free — the companion is inline for this one instance and **counted in §4.8** | SMIL plays once to completion at load (finite, retimed **≤5s total** per §2.3 so the one-shot clears WCAG 2.2.2), freezes finished via `fill="freeze"` |
| `tancho-set` | crown pre-set on the static companion | crown shown via `html:not(.js) #final-fold .crane-crown { opacity: 1 }` — **scoped to the final-fold instance only**; the crown node itself stays non-SMIL and transparent-by-default (§2.3), so no other crane rendering can ever show red |
| V1 scraps / corner-lift | settled final stack, no curl | settled final stack (pre-state behind `html.js`) |
| V2 sticky stage | un-stickied static column, three captioned figures | same static column (`data-step` never flips; CSS default shows all scenes stacked as figures, `visibility: visible`) |
| `sheet-close` | flat final state | flat final state |
| V3 sequence | seal/tag/chain/checks pre-rendered at rest | same |
| V4 arrows/slips | diagram at final state, arrows absent, slips faded | same |
| Pets | static figure `<img>` (the default) + bubbles as styled captions | **static figure `<img>` (the default — SMIL is `html.js`-revealed, so no-JS never loops)**; bubbles visible |
| Fold-shadows / washi | static wedges / static grain (grain is always static) | drift runs but is **finite (2 cycles, freezes at rest)** — 2.2.2-clean by construction; grain static |
| Act tint | still fires (color/opacity crossfade, not motion) with `transition: none` | stays `gami` state; Fold 3 keeps base accent — content unaffected |
| `card-lift` | **translate dropped; pseudo-element shadow/color affordance kept** (hover translate is motion — user-initiated and permissible, but PRM users get the stateless affordance) | n/a (hover is CSS; fine) |
| Anchor jumps (inoculation → `#final-fold`) | `scroll-behavior: auto` forced (smooth is never set anyway) | instant jump |
| Chips / CTA / UA gate | unaffected (non-motion) | build-time baked state: correct version/size/date, dmg button |
| Hover/copy interactions | kept (non-motion beyond card-lift row above) | copy buttons hidden (`html.js`-gated); commands remain selectable text |

### 4.8 Budgets — revised, honest, binding

This design is heavier than Revision 2's: JS doubles, CSS roughly triples. New hard numbers, **measured minified** at PR-2 review (terser/esbuild-minified inline output is mandated in §12 — Astro does not minify `is:inline` scripts by default, and the raw itemization only closes minified):

- **JS: one inline IIFE, ≤8KB raw / ≤3KB gzipped (minified). Zero framework** (the only external JS remains Astro's prefetch module). Itemized inventory — anything not on this list doesn't ship:
  1. `html.js` flag + single `reduce` matchMedia read + **synchronous UA-gate branch** (first element of `<head>`, pre-paint — §3.7/§4.3) (~0.3KB)
  2. Theme-sync (§1, unchanged, ~0.3KB)
  3. Reveal IO (~0.4KB)
  4. V2 stage-step IO (~0.4KB)
  5. Shared `.in-view` IO + pet controller (SMIL gate, ≤4.5s idle timer, single-idler incl. corner-lift suspension) (~1.4KB — live-region mirror deleted)
  6. Crane controller (final-fold `data-pause-t` init, resume IO, session flag) (~0.5KB)
  7. §5.5 release enhancer (async version confirm-or-upgrade) + share/copy-link fallback (~1.4KB; **SHA deref chain deleted**; state machine otherwise verbatim from §5.5 — untouched)
  8. Copy buttons + `role="status"` confirm (~0.35KB)
  9. `data-guide` handoff IO + hysteresis sentinel (~0.4KB)
  ≈5.5KB raw pre-minify; the caps hold with ~1KB headroom as measured-minified numbers. **No scroll listeners anywhere** (everything is IO/timer-based).
- **CSS:** `landing.css` ≤30KB raw / ≤7KB gz (was ~300 lines; now ~1,000 incl. vignettes + keyframes + the dual-layer tint wedges).
- **Inline SVG (single-animated-crane architecture — §2.3):**
  - washi grain ≤1.5KB raw;
  - pet SMIL inlines measured at 3.7KB + 4.6KB gz (the §2.5 filter-subtree restructure must not grow them materially);
  - **one animated crane, `#final-fold` only: ≤25KB gz post-§2.3 rebuild (hard sub-budget)**;
  - **hero static one-fold-short frame: ≤3KB raw**;
  - **final-fold static PRM companion (crowned final frame): ≤3KB raw** — previously uncounted, now on the books.
  - *(Deleted: the dual-inline "gzip-dedupe to ≤30KB combined" clause — gzip's 32KB window cannot dedupe a second copy of an asset this size; measured 2× cost, 0% dedup. If an animated hero is ever wanted post-rebuild, serve the crane as a same-origin external SVG via `<object>` so one cached fetch serves both — a §2.3-gated upgrade, not the plan.)*
- **Total HTML+CSS+JS ≤65KB gzipped, the animated crane + both static frames included.** (Old cap was 120KB but assumed a hero raster; the new page has none.)
- **Images:** hero = zero raster (LCP is the H1 text — fetch-free; inline SVG is not an LCP candidate). All 7 landing captures (`import-files-overview`, `language-switcher`, `combine-reorder-pages`, `edit-text-workflow`, `export-save-confirmation`, `sign-document-digital`, plus one spare) via `astro:assets` `<Picture>` AVIF/WebP, lazy (per-image exception under the §3.1 tall-viewport rule), explicit dimensions: **≤110KB served each, ≤650KB combined.** **The static `gami-figure.svg`/`ori-figure.svg` `<img>`s (~19KB raw combined) are counted here** — they are the default-visible pets and fetch regardless. Source PNGs are the shipped 1600px/135–200KB standard — no recapture required (audit-verified); the manifest's 1600px standard is accepted for the landing since no capture is above the fold on the gated viewports. **Path correction (verified on main):** `combine-reorder-pages.png`, `export-save-confirmation.png`, and `sign-document-digital.png` currently live in `docs-site/public/assets/gifs/` (PNGs in a gifs folder), not `screenshots/` — see §2.1; PR-2's first commit moves them.
- **V1–V4 vignettes: 0 bytes of media** (DOM + CSS only).
- **Crane sub-rule (re-anchored):** the single-animated-instance layout **is** the baseline, decided now — not a fallback discovered at build time. If even that one instance can't reach ≤25KB gz at the §2.3 go/no-go, the landing ships fully static cranes and V5's payoff is cut to static crane + `tancho-set` only. Pre-decided; no renegotiation.

---


## 5. Download system

### 5.1 Asset convention

Two stable names per release, forever:

- **`Orifold.dmg`** — website + humans. Button href: `https://github.com/udhawan97/Orifold/releases/latest/download/Orifold.dmg`.
- **`Orifold.zip`** — the one-line installer, cask, and `.command` helpers, all untouched.

Version lives in the tag; the URL never changes. `Orifold-latest` gains `prerelease: true`, which **guarantees** it can never hijack `releases/latest` (verified: latest = newest non-prerelease, non-draft release).

**Verified caveat, encoded in every check:** the `/releases/latest/download/…` first hop **302s even for nonexistent assets** — existence checks must use the API or follow the redirect chain to a final 200; hop-1 status proves nothing. Also: `github.com` download objects are CORS-blocked for browser fetches; only `api.github.com` is CORS-open.

### 5.2 `scripts/make-dmg.sh` (decided now)

- Raw `hdiutil` UDZO with `/Applications` symlink + background PNG (`scripts/assets/dmg-background@2x.png`: canvas-dark, fold motif, arrow — **no OS-specific launch instructions baked into pixels**; they'd be wrong for one OS or stale after notarization).
- **Layout via a committed pre-baked `.DS_Store`** (generated once locally, `ditto`'d into the staging dir). **No AppleScript/Finder scripting on CI** — that's the flaky part of the popular `create-dmg` shell script; a committed `.DS_Store` makes the pretty layout deterministic. (`create-dmg` was evaluated and rejected for this reason; sindresorhus/create-dmg can't do custom layout at all.)
- **`hdiutil create`/`detach` wrapped in a 3-attempt retry** with detach+cleanup between attempts — "Resource busy" on GitHub runners is real, known, and unfixed at the runner-image level; retries are the standard mitigation.
- Signing order: app signed (→ notarized+stapled when secrets exist) → dmg built → dmg codesigned same identity → (dmg notarized+stapled). Ad-hoc identity ⇒ skip dmg signing gracefully, same conditional pattern as today. In the signed era, **both** the app (pre-dmg) and the dmg get stapled.

### 5.3 Release workflow changes (`.github/workflows/release.yml` — outline, no YAML)

Tagged-release path, in order:

1. **Derive version from tag (CI-enforced):** normalize the tag (strip `release-`/`v`), export `ORIFOLD_MARKETING_VERSION`; the packaging step extends `install-mac.sh`'s existing `write_info_plist()` (`scripts/install-mac.sh:416`) to `Set` `CFBundleShortVersionString` from it and `CFBundleVersion` from the run number. **Important (Revision 2):** the shipped zip's version does **not** come from `project.yml` — `write_info_plist()` copies the committed `Orifold/Resources/Info.plist` verbatim (which carries `0.8.1`/`8`); `project.yml` only feeds xcodegen/Xcode builds. The PlistBuddy step must therefore override the copied plist's version keys. **The tag is the single source of truth for shipped artifacts.** `scripts/bump-version.sh` is a **new** courtesy script for dev/source builds — it must update **both** `project.yml` and `Orifold/Resources/Info.plist` (two committed version sources today), and prints the tag command.
2. Build + test as today → package zip → **make dmg** (`scripts/make-dmg.sh`).
3. **Atomic publish:** create the release `draft: true` → upload `Orifold.zip` + `Orifold.dmg` → `gh release edit <tag> --draft=false --latest`. The release only becomes `latest` with assets attached — no publish-window 404 for the button, the installer, or the site build.
4. **Pin the cask (~15 lines):** `shasum -a 256 Orifold.zip`; sed `Casks/orifold.rb` to `version 'X.Y.Z'`, real `sha256`, versioned `releases/download/vX.Y.Z/Orifold.zip` URL; commit+push to main with the default token, wrapped in a `git pull --rebase` retry ×3 (this repo has concurrent sessions). Brew users get real upgrades and checksums for the first time.
5. **Dispatch the site rebuild:** `gh workflow run docs.yml --ref main` (grant `permissions: actions: write` to the release job). This works with the default `GITHUB_TOKEN` — GitHub exempts `workflow_dispatch`/`repository_dispatch` from the no-retrigger rule; no PAT needed. Running **after** step 3 kills the asset race by construction. *(Do NOT use `workflow_run` — its branch filter matches the tag name for tag-triggered runs and silently never fires.)*

Rolling `Orifold-latest` path: gains `prerelease: true`, retitled "Development build from latest `main` — not the release channel," keeps zip **and** dmg (retry-wrapped; every-push execution is the canary that keeps release day boring; demote dmg to tagged-only if flakiness persists — documented fallback).

Also in this PR: `depends_on arch: :arm64` in `Casks/orifold.rb`; `uname -m` guard in `install-mac.sh`'s prebuilt path (non-arm64 → refuse with a clear message); add `paths-ignore: [docs-site/**, docs/**]` to the release workflow's `main`-push trigger (today every docs-only push burns a full ~15-min macOS app build for an unchanged `Orifold-latest`; tag triggers unaffected). **No backfill `workflow_dispatch` for old tags** — dispatching an old tag checks out a commit that predates `make-dmg.sh`; the only way `releases/latest` gets a dmg is shipping `v0.8.2` from post-PR-1 main.

### 5.4 Docs workflow changes (`.github/workflows/docs.yml` — outline)

- Keep the existing push-path trigger; `workflow_dispatch` **already exists** in `docs.yml` (Revision 2 correction — the step-5 dispatch works against today's file with no trigger change). Add only a **daily `schedule:` cron** — belt-and-braces that re-bakes truth at most 24h late no matter which event misfired.
- Build env gets `GITHUB_TOKEN` so the build-time release fetch is never rate-limited.
- **Post-deploy smoke step:** curl the live page and grep for the tag fetched from `releases/latest`; `curl -sIL …/releases/latest/download/Orifold.dmg` and assert the **final** response is 200 (whole redirect chain, per §5.1). Failure = red X + notification instead of silent drift.

**Acceptance test for the whole contract (run once, literally):** push a throwaway tag → watch the release publish with both assets → watch docs.yml auto-start with zero clicks → live page shows the new tag → dmg link resolves 200 → delete the tag/release.

### 5.5 Fallback layers

1. **Build-time (canonical, no-JS truth):** `docs-site/src/lib/release.ts` fetches `releases/latest` during `astro build` — tag, `published_at`, the **dmg** asset's `browser_download_url` + `size` (one call covers everything). dmg asset absent → button degrades to zip with an inline note + a build warning. API call fails → last-known-good state (optimistic stable URL).
2. **Runtime enhancer (~1KB) — confirm-or-upgrade only; never downgrade on ambiguity.** Complete state machine:
   - `200 + dmg asset present` → refresh version/size/date in the chips.
   - `200, no dmg, published_at < 10 min ago` → publish-window guard: **do nothing** (near-impossible with atomic publish; guard kept anyway).
   - `200, no dmg, older than 10 min` → authoritative: swap button to the releases page, "Get the latest release →".
   - `403` (rate-limited — shared office/university IPs are real) → **do nothing**; build-time state stands.
   - Network error / timeout → do nothing.
   - Cache the response in `sessionStorage` + send `If-None-Match` (304s don't count against the 60/hr unauthenticated budget).
   - The same script performs the mobile UA gate (§3.8).
3. **Human:** "All releases →" always present.

---

## 6. Gatekeeper reality — honest UX, verified facts

- Builds are ad-hoc signed, not notarized (confirmed on the live asset). **macOS 15 removed the right-click→Open bypass** for unnotarized apps; the only path is Settings → Privacy & Security → Open Anyway → password. macOS 14 keeps the one-dialog right-click path. curl downloads carry **no** quarantine xattr — the one-line installer genuinely is the zero-dialog path, and the copy may say so.
- Per-OS coaching in §3.7; the one-line inoculation note under the hero CTA; installer promoted as the no-dialogs alternative in the same band. `xattr -cr` appears **only** in the troubleshooting doc as an escape hatch (it still works on 15/26, but public install docs shouldn't train users to defeat Gatekeeper).
- **Signed-era flip is not turnkey — pre-flip work item:** rewrite `sign_staged_app` inside-out (sign `PDFium.framework` and nested executables first, **no entitlements** on them; then the app with entitlements + hardened runtime; drop the deprecated `--deep`), then one full dry run with real credentials: `notarytool submit` → staple app → build dmg → sign+staple dmg → `spctl -a -t open --context context:primary-signature` on the dmg. Only then flip `site.json.signedBuilds`. The $99/yr Apple Developer membership remains the single highest-leverage trust upgrade; **the site does not wait for it**.
- Sparkle-era note: do **not** enable Library Validation on ad-hoc builds (it can block loading the Sparkle framework).

---

## 7. Version display — one source of truth

- **Canonical source: GitHub release metadata at build time** (`release.ts`) → hero chip, download chip (size from the dmg asset specifically), footer version/date/link, and a **build-time "Latest release" banner at the top of `releases.mdx`** ("Latest: v0.9.0 — 2026-07-XX · full notes on GitHub") so the hand-written release essays become historical entries that can never make "What's New" lie.
- **`stats.json` loses its `version` key.** `Stat.astro` resolves `version` from `release.ts` (offline fallback: last-known value).
- Version normalization (strip `release-`/`v`, dotted-numeric compare) lives once in `scripts/lib/version.sh` and once in the app's `UpdateChecker`, with a shared test-vector list.
- README: replace the static `release-v0.8.1` badge (`README.md:30`) with the self-updating `img.shields.io/github/v/release/udhawan97/Orifold` endpoint; de-version the prose at `README.md:34` and `README.md:337`; add a release-workflow grep guard that fails if the previous version string survives outside changelog history.
- The committed `Orifold/Resources/Info.plist` is the second hand-maintained version source (see §5.3.1) — `bump-version.sh` owns it; CI overrides it from the tag either way.
- The hero sub-line's verbatim source is `docs-site/src/content/docs/index.mdx:23` — copy it into the landing **before** §10 deletes that file. README deliberately keeps its own two-line variant; don't "sync" it.

---

## 8. Auto-update — three cleanly separated concerns

### (a) Website download automation

Fully covered by §5. Zero manual steps by construction; daily cron + post-deploy smoke as the safety net.

### (b) In-app updates

**Phase 1 — now (ad-hoc era): check-only, consent-first.** *(The sandbox forbids in-process download-and-swap: sandboxed apps can't strip quarantine or replace their own running bundle. The `network.client` entitlement exists as of 2026-07-07 — outbound requests work; self-replacement still doesn't.)*

- ~~Add `com.apple.security.network.client`~~ **Already shipped 2026-07-07, ahead of PR-4:** the entitlement was added to fix trusted timestamps, which sandboxed builds were silently degrading (verified per §3.5 — sandbox blocked TSA DNS; ATS blocked the http fallbacks; both fixed, privacy docs flipped in the same commit). PR-4 no longer touches entitlements — it only adds the UpdateChecker, Settings toggle, and menu item, and flips `site.json.appNetworkCheck` for the update-check clause in the §3.5 copy.
- `UpdateChecker`: GET `releases/latest` with ETag caching, normalize tag, compare to `CFBundleShortVersionString`. Surfaces: menu **"Check for Updates…"** (always explicit) + Settings toggle **"Check automatically (weekly)" — default OFF**. Copy: "Asks GitHub for the latest version number. Your files are never involved." (Not "the only network request Orifold can make" — trusted-timestamp signing also uses the network, opt-in.)
- Update available → sheet: release-notes link + **"Open download page"** (website `#download`) + **"Run the installer"** (NSWorkspace-opens the existing `Install or Update Orifold.command` in Terminal — LaunchServices-legal; the script runs unsandboxed and already solved quit/replace/verify).
- **Install-location reconciliation** (dmg introduces `/Applications`; installer prefers `~/Applications`): small `install-mac.sh` change — if an existing `Orifold.app` is found in `/Applications`, replace it **in place** instead of sweeping it into `~/Applications`, so dmg users' Dock icons and Open-With bindings survive updates. The sweep remains only when no prior install exists.

**Phase 2 — Sparkle 2 (recommended endgame), decoupled from notarization.** *(Verified: Sparkle's EdDSA verification explicitly supports ad-hoc-signed apps — its own test app ships that way; sandboxed operation is supported via bundled XPC services + `SUEnableInstallerLauncherService`; Sparkle strips quarantine on updates it installs, so post-first-install updates are seamless even unsigned. SPM integration is small: package + `SUPublicEDKey` + `SUFeedURL` + `SPUStandardUpdaterController`.)*

- Honest reasons it's Phase 2, not Phase 1: **EdDSA key custody** (generate once, GitHub secret + offline copy; once shipped it can never be removed — losing it kills the update chain), the `generate_appcast` CI step (`--ed-key-file -` from a secret, `--download-url-prefix` at the versioned release URL, appcast committed to the repo or Pages — the proven Maccy pattern), dependency weight vs a 50-line checker, and shipping the consent UX first so automatic checks are already opt-in when the transport gets powerful.
- Trigger: after Phase 1 ships and the dmg pipeline has two clean releases — **not** gated on the Apple membership.

### (c) Tagging & release ritual

- **Standardize on `v0.9.0`-style tags**; keep the `release-v*` trigger for compat. Ritual: `bump-version.sh 0.9.0` (courtesy) → commit → `git tag v0.9.0` → `git push --tags`. CI derives the artifact version from the tag, publishes atomically, pins the cask, dispatches the site.
- Channels: `v*` = stable (`releases/latest`); `Orifold-latest` = dev, `prerelease: true`.
- Guard the release `workflow_dispatch` path: refuse `--latest` for a tag older than the current latest (prevents an accidental re-run flipping `releases/latest` backwards).

---

## 9. File / folder change list

```
NEW
docs-site/src/pages/index.astro
docs-site/src/components/landing/{Nav,Hero,ProofShot,FoldMoment,FeatureGrid,
  SignatureBand,PrivacyBand,DownloadBand,LandingFooter}.astro
docs-site/src/styles/landing.css                     # zero raw colors, review-enforced
docs-site/src/lib/release.ts                         # build-time metadata + fallback states
docs-site/src/data/site.json                         # signedBuilds, appNetworkCheck, repo coords
docs-site/src/content/docs/get-started/workflows.mdx # popular-workflows hub (docs front door)
docs-site/src/assets/landing/fold-moment.svg         # ~8KB hand-built, §3.2
scripts/make-dmg.sh                                  # hdiutil + retry, committed .DS_Store, no AppleScript
scripts/bump-version.sh + scripts/lib/version.sh     # normalizer + shared test vectors
scripts/assets/{dmg-background@2x.png, dmg-layout.DS_Store}

MODIFIED
docs-site/src/content/docs/index.mdx                 # DELETED (workflows → hub page; story → landing)
docs-site/astro.config.mjs                           # redirect /docs → /get-started/workflows/; sidebar entry
docs-site/src/components/Stat.astro                  # version resolves from release.ts
docs-site/src/data/stats.json                        # version key removed
docs-site/src/data/popular.json                      # becomes the single curation source (hub + landing row)
docs-site/src/content/docs/releases.mdx              # build-time latest-release banner
.github/workflows/release.yml                        # tag-derived version, dmg, atomic publish,
                                                     # cask pin+commit, docs dispatch, prerelease flag
.github/workflows/docs.yml                           # workflow_dispatch + daily cron + smoke step
scripts/install-mac.sh                               # arch guard; in-place /Applications replace
Casks/orifold.rb                                     # arch guard now; version/sha pinned by CI per release
docs/DOCS_PREMIUM_MAKEOVER_PLAN.md                   # status header corrected; fold-anim ownership → landing
assets: hero capture @2x + MEDIA_MANIFEST.md update; crane SVG dieted + static variant;
  Gami/Ori finite-loop + static variants
Orifold app (PR-4): UpdateChecker + Settings toggle + menu item
                                                     # (network.client entitlement already shipped 2026-07-07
                                                     #  with the trusted-timestamp fix; privacy docs flipped then)

UNTOUCHED, DELIBERATELY
install.sh entry point, zip layout/name, Desktop .command helpers, all docs slugs,
tokens.css, theme.css, TrustStrip.astro (docs-only), Hero/Footer overrides (docs-only)
```

---

## 10. README / docs update checklist

- [ ] README: website link near the top + dynamic shields release badge; dmg above zip in direct-download options; de-versioned prose; installer stays prominent.
- [ ] `get-started/install.mdx`: dmg first (with the per-OS first-launch steps from §3.7), installer as "the no-dialogs path," zip third; Apple Silicon requirement + plain-language explainer.
- [ ] `get-started/update-uninstall.mdx`: rewritten when PR-4 ships (menu check + toggle primary; `.command` fallback).
- [ ] `developers/build-release.mdx`: two-asset convention, `make-dmg.sh`, tag-derived versioning, `v*` standard, dev channel, cask auto-pin, site dispatch.
- [ ] `developers/release-gate.mdx`: dmg smoke (`hdiutil attach` → launch → verify), throwaway-tag acceptance test, signed-era pre-flip checklist.
- [ ] `settings/privacy.mdx` + §3.5 stats: flip with PR-4, same tag.
- [ ] `releases.mdx`: banner wiring; note in the ritual that the essays are curated history.
- [ ] **Post-toolbar docs pass (new in Revision 2):** the toolbar redesign (`37ae9b6`) made four docs pages the landing links into factually wrong — `reading/reader-mode.mdx` ("Click Reader Mode in the toolbar" → now View menu ⌘⇧R / More popover), `reading/night-mode.mdx` ("Click Document Comfort in the toolbar" → now inside More), `get-started/the-window.mdx` (describes retired toolbar layout + uses the stale annotated capture), `annotate/markup.mdx` (underline/strikeout now behind the capsule's disclosure popover). Rewrite alongside the §2.1 recaptures.
- [ ] `docs/DOCS_PREMIUM_MAKEOVER_PLAN.md`: status → "Substantially shipped (91491d8)"; homepage story + fold-animation deliverable now owned by the landing page.
- [ ] `docs/TOOLBAR_REDESIGN_PLAN.md`: shipped in `37ae9b6` (note: `ToolbarMoreMenu` landed inside `ContentView.swift`, not as the planned new file) — add a shipped header or delete per the Smart-Text-Edit precedent.
- [ ] `docs/assets/MEDIA_MANIFEST.md`: new hero capture, 2×-for-hero rule, dieted crane + static variants, fold-moment SVG, pet finite-loop variants; build on the `aed19d2` Media/MP4 sections; reconcile the 1600×1000 spec with the chosen capture standard.
- [ ] Pagefind check: "install" / "download" / "combine" surface post-`index.mdx`-deletion; keywords on `workflows.mdx` if not.

---

## 11. Risks & edge cases

1. **macOS 15 Open-Anyway drop-off** — mitigated by the hero inoculation line, per-OS coaching, installer promotion; the real fix is notarization (the $99 membership decision stays with Umang; §6 pre-flip work is scoped either way).
2. **Observed Gatekeeper dialogs differ from documented ones** ("damaged" dead-end verdict on some 15.1+ builds) — §2.2 machine test is blocking; copy is written from evidence, not documentation.
3. **Starlight route collision** (custom `index.astro` + deleted splash) — §2.4 prototype gates PR-2; verify 404, sitemap, canonical, and the `/docs` redirect under the `/Orifold` base.
4. **CI cask commit races concurrent sessions** — `pull --rebase` retry ×3; the cask file is touched by nothing else.
5. **hdiutil flakiness** — 3-attempt retry + no AppleScript; documented fallback = tagged-only dmg if retries prove insufficient.
6. **Crane can't reach ≤25KB gz** — pre-decided fallback: static mark on the landing, animation stays docs-only. No renegotiation at build time.
7. **First network call vs. the "0 network calls" brand** — moot for the entitlement itself: `network.client` + the privacy.mdx rescope shipped together 2026-07-07 with the trusted-timestamp fix. PR-4 still ships consent UX + the `appNetworkCheck` stat flip (update-check clause only) in one tag.
8. **EdDSA key loss (Phase 2)** — generate once, GitHub secret + offline copy; documented in `build-release.mdx` before Sparkle ships; keys are rotatable but never removable.
9. **Rate limits on shared IPs** — the enhancer is confirm-or-upgrade-only with ETag caching; the build-time state is canonical; the no-JS path is fully correct by construction.
10. **Publish-window 404 on the stable URL** — closed by atomic draft→upload→publish; the runtime guard covers the residual case.
11. ~~**TSA timestamps possibly broken in shipped sandboxed builds**~~ **Confirmed and fixed 2026-07-07** (§3.5): sandbox blocked all TSA DNS, ATS blocked the three `http://` fallbacks. Entitlement + ATS exceptions + Sectigo-https shipped with the privacy-copy flip; re-verified sandboxed with all 4 TSAs returning tokens. §3.4 may promise timestamps.
12. **Screenshots must be captured on a post-toolbar-redesign build** — any capture showing the pre-`37ae9b6` toolbar is an instant credibility bug on a page whose caption says "real capture."

---

## 12. Sequencing & instructions for Sonnet

Ship as four small PRs (shared-repo rule: small units, commit often, expect concurrent sessions):

1. **PR-1 — Pipeline** (isolated, no site changes): `make-dmg.sh` + dmg assets, `release.yml` (tag-derived version, dmg step, atomic publish, cask pin, docs dispatch, `prerelease: true` on Orifold-latest), cask + installer arch guards, `bump-version.sh` + `version.sh`. **Then ship `v0.8.2`** — the only way `releases/latest` gets a dmg. Run the §5.4 throwaway-tag acceptance test.
2. **Pre-PR-2 gates (blocking):** capture session (§2.1), Gatekeeper machine test (§2.2), crane diet (§2.3), Starlight route prototype (§2.4).
3. **PR-2 — Site:** landing page + components + `release.ts` + `site.json` + `docs.yml` changes (dispatch/cron/smoke) + workflows hub + `/docs` redirect + `index.mdx` deletion + `popular.json` wiring.
4. **PR-3 — Docs/README:** §10 items independent of the app.
5. **PR-4 — App:** check-only `UpdateChecker` + Settings toggle + menu item + `appNetworkCheck` stat flip, riding the next `v*` tag. (`network.client` entitlement + privacy.mdx rescope already shipped 2026-07-07 with the timestamp fix.)
6. **Later:** two clean releases → Sparkle 2 (Phase 2); membership purchased → §6 pre-flip signing work → flip `signedBuilds`.

**Implementation rules for Sonnet:**

- Read this document top to bottom before writing code; §5.1's redirect caveat, §5.3.5's dispatch choice, and §8(b)'s sandbox constraints are verified facts — do not re-litigate or "simplify" them back to the refuted Iteration-1 designs (no `workflow_run`, no in-process update install, no right-click advice for macOS 15).
- The copy in §3 is direction with example lines, not lorem ipsum — use it verbatim where quoted; keep the voice (honest, lightly playful, fold metaphors, no superlatives).
- Never hardcode a version string in landing copy; everything flows from `release.ts`.
- `landing.css` must contain zero raw color values; every color is a `tokens.css` variable or `color-mix` of one.
- Verify with the preview server + Lighthouse in **both themes** before merging PR-2; check the fold budget at 1280×700 and 1440×780; test reduced-motion and no-JS states explicitly.
- Anything ambiguous: prefer the more restrained option. When in doubt, cut motion, cut copy, keep contrast.


---

## Revision 3 deltas — Folding Studio (§2 additions, §9/§12 changes)

*The §3/§4 above are the Folding-Studio replacement. Below: the pre-work, file-list, and sequencing changes that come with it. Everything in §1 and §5–§8 stays exactly as written.*

### §2 pre-work — additions & amendments (append to the main §2)

§2.2 (Gatekeeper machine test) and §2.4 (route prototype) are unchanged and still blocking. §2.1 and §2.3 are amended; §2.5–§2.10 are new. **§2.3 is now the first task in the sequence** (see its go/no-go).

- **§2.1 amended — capture session mostly discharged; paths corrected; manifest added.** Post-toolbar recaptures shipped in `bef7f0e` + `a186efa`. **Corrected inventory (verified):** `import-files-overview.png`, `language-switcher.png`, `edit-text-workflow.png` live in `docs-site/public/assets/screenshots/`; **`combine-reorder-pages.png`, `export-save-confirmation.png`, and `sign-document-digital.png` live in `docs-site/public/assets/gifs/`** (PNGs misfiled in the gifs folder), and `docs/assets/screenshots/` holds only 5 files — the old "all seven byte-identical across both screenshots dirs" claim was false, and `astro:assets` imports written from it would 404. **PR-2 housekeeping (first commit): move the three PNGs into `screenshots/` and update the two docs pages that reference them.** No recapture needed — the assets exist. **Do not re-demand them.** New deliverable: **`docs-site/src/data/landing-captures.json`** — the captures manifest pinning, per capture, the version it was actually shot on + capture date; §3.0 captions render from these pins; a build check warns when any pin trails `release.ts` by more than one minor. Remaining, re-scoped:
  - The 2× hero proof shot is **no longer landing-blocking** — the hero ships crane-only. `the-orifold-window-annotated.png` still fails hero grade (1 file, "Untitled", self-referential body, 1600px) but is now a docs asset; recapture to §2.1 content rules is deferred, optional, non-gating.
  - Still stale, **docs-only** (§10 residual, not landing-blocking): `annotate-markup-tools.png`, `night-mode-comparison.png` + the `annotate/markup.mdx` copy fix.
- **§2.3 amended — crane rebuild (not diet), FIRST pre-work task, go/no-go gate.** Honest scope: the current asset is 155KB raw / ~83KB gz with 65 `repeatCount="indefinite"` animate nodes. Reaching ≤25KB gz is a 70% cut **plus** a full re-authoring — a finite, sequenced timeline ending `fill="freeze"`, retimed so the **full single play runs ≤5s** (clearing WCAG 2.2.2 for the no-JS one-shot; the final-fold remainder stays ~1.2s). This is a sub-project, not an svgo pass, so it runs **first, with a go/no-go checkpoint before any PR-2 build starts**: pass ⇒ single-animated-instance architecture (§4.8); fail ⇒ the pre-decided all-static cut. Deliverables from the same session: (a) `data-pause-t` on the root `<svg>` — **chosen by eye, not computed**: the paused frame must read as intentional sculpture, a composed expectant pose, never crumpled — and **"pause frame approved as a standalone still" is a named PR-2 acceptance check**, because that frame is also the hero's static composition; (b) the hero static frame designed as a **first-class composition** (crownless), exported ≤3KB, plus the crowned static final-frame companion for the PRM swap (≤3KB); (c) the crown/tancho dot as a separately-addressable **non-SMIL** node, transparent by default (CSS-set via `tancho-set` under JS, via the §4.7 scoped `html:not(.js)` rule under no-JS — resolving the old §2.3(b)/§4.7 contradiction where the crown was simultaneously JS-only and "reached via SMIL freeze"); (d) all internal ids namespaced (`crane-`); (e) *upgrade check only:* if the rebuilt asset lands <~28KB raw, a second inline hero instance may be considered — otherwise never revisited.
- **§2.5 (new) — inline-SVG id + AT + paint audit.** The crane, `orifold-dog-wag.svg`, `orifold-cat-twitch.svg`, and the washi-grain filter are inlined into one document. Audit every `id`/`url(#…)` reference for uniqueness; prefix per-asset (`crane-`, `gami-`, `ori-`, `washi-`). **On-disk pet assets are never edited** (README-shared; the finite-3-cycle asset conversion stays cancelled — replaced by the §4.4 JS gate) — but the **build-time inline copies** are restructured: (a) animated groups hoisted out of filter subtrees per §4.4's paint-cost rule; (b) `aria-hidden="true"` applied to the inline SVG roots, overriding the shipped `role="img"`/`aria-label` (the bubble outside the wrapper is the accessible content); (c) default visibility inverted per §3.9 (static `<img>` default, SMIL under `html.js`).
- **§2.6 (new) — `stats.json` truth fix.** `docs-site/src/data/stats.json` `tests: 503` → the real count (grep `func test` under `Tests/` at fix time; 555 as of this audit). Blocking for the Fold 4 stat row.
- **§2.7 (new, highest priority after §2.3) — durable TSA re-fix in `project.yml`; gate is page-wide.** Commit `8180b82` (xcodegen regeneration) silently reverted `5f85f9a`: `com.apple.security.network.client` is gone from `Orifold/Resources/Orifold.entitlements` and the `NSAppTransportSecurity` per-host exceptions (timestamp.digicert.com, timestamp.globalsign.com) are gone from Info.plist, because both were hand-edits that `project.yml` doesn't declare. Durable fix = add the entitlement to `project.yml:109-114` and the ATS dictionary to `project.yml:58-63` `info.properties`, regenerate, re-verify sandboxed TSA tokens (all 4 providers). Cascading corrections in the same change: `stats.json` entitlements key, `settings/privacy.mdx` "exactly four entitlements" wording, and the plan's own §3.5/§8(b)/§11.11 RESOLVED notes gain a "regressed `8180b82`, re-fixed durably in `<commit>`" annotation. **Blocking for every timestamp mention page-wide** — the grep-able list lives in §12 and covers Fold 3 copy, Fold 3's capture caption, and Fold 4's "0" stat sub-line (the old Fold-3-only gate left Fold 4 advertising the same broken feature).
- **§2.8 (new) — washi-grain tile.** Hand-build the inline `feTurbulence` grain SVG (≤1.5KB raw, static, maskable). Zero animation by construction.
- **§2.9 (new) — pet figure & bubble QA.** Verify `gami-figure.svg`/`ori-figure.svg` render crisply at margin size and at the 24px mobile mark fallback; confirm the figures carry no ids colliding with §2.5; verify both bubble surface pairings (§4.1) in both themes; write the six roster lines into a single source constant so a future copy pass edits one place. (No new pet art is required — figures are real PaperFigure geometry, marks exist, SMIL assets exist; speech bubbles are HTML/CSS, not assets.)
- **§2.10 (new) — export text-layer fidelity copy gate.** Fold 2's sub sits next to a known engine caveat: the import-side fix shipped (`PDFImportNormalizer`), but the export path is documented as still able to re-serialize and rebuild original text layers. Before locking Fold 2 copy: verify whether current export preserves original text layers post-normalizer. Verified ⇒ the sub may restore "…on the real page." Caveat stands ⇒ ship the softened sub in §3.3 (claims the edit, which IS in-place — not whole-page byte-fidelity a byte-differ could contest).
- **Superseded pre-work:** the old §3.2 `fold-moment.svg` (~8KB hand-built) is **cancelled** — V1 replaces it with DOM+CSS at 0 bytes of media.

---


### What stays untouched (binding)

**§1 (architecture, theme handoff, docs front door, `popular.json` single-source contract), §5 (download system: asset convention, make-dmg, release workflow, docs workflow, fallback layers/state machine), §6 (Gatekeeper facts & signed-era flip), §7 (version single-source-of-truth), and §8 (auto-update phases) are unchanged, verbatim, and not to be re-litigated.** §10 and §11 stand except for the §2.7 annotations noted above. Deltas to §9 and §12 only:

**§9 file-list deltas:**
- NEW components become `docs-site/src/components/landing/{Nav,Hero,GatherFold,CreaseStage,SealFold,KeepFold,MaBand,FinalFold,PetGuide,LandingFooter}.astro` (replaces the old `{ProofShot,FoldMoment,FeatureGrid,SignatureBand,PrivacyBand,DownloadBand}` set).
- REMOVE `docs-site/src/assets/landing/fold-moment.svg` from NEW (cancelled, §2 note).
- ADD to NEW: washi-grain inline SVG partial; **rebuilt** namespaced crane with `data-pause-t` + hero static frame + crowned static companion (§2.3 control contract); **`docs-site/src/data/landing-captures.json` (captures manifest, §2.1) + its build check**.
- ADD to MODIFIED: **`tokens.css` (the one sanctioned amendment: `--of-paper` / `--of-paper-ink` / `--of-paper-edge`, per theme — §4.1)**, `project.yml` (§2.7 entitlement + ATS, app repo), `docs-site/src/data/stats.json` (tests count — the `version`-key removal already listed stands), `settings/privacy.mdx` (entitlement wording), **the two docs pages referencing the three PNGs moved out of `gifs/` (§2.1 housekeeping)**.
- REMOVE from MODIFIED assets line: "Gami/Ori finite-loop + static variants" → pets ship as-is on disk, JS-gated with restructured inline copies (§2.5/§4.4); static variants already exist (`*-figure.svg`).
- UNTOUCHED-DELIBERATELY list unchanged, plus: `orifold-dog-wag.svg` / `orifold-cat-twitch.svg` **on-disk asset bytes** (README-shared; never edited for the landing — build-time inline copies may be restructured per §2.5).

**§12 sequencing/acceptance deltas:**
- Pre-PR-2 gates are now, in order: **§2.3 crane rebuild + control contract + go/no-go (FIRST — the page's two headline moments rest on it)** · §2.2 Gatekeeper machine test · §2.4 route prototype · §2.5 id/AT/paint audit · §2.6 stats fix · §2.7 durable TSA fix · §2.10 export-fidelity check.
- **Timestamp copy gate — grep-able list (all gated on §2.7; PR-2 may ship with these stubbed to non-timestamp signing claims if §2.7 slips, never with timestamp claims):** (1) §3.4 lede/copy-column timestamp mentions + the `tag-thread` "RFC 3161 · FreeTSA" tag text + the chain node "trusted timestamp" + "Time attested"; (2) §3.4 `sign-document-digital.png` caption (provider picker); (3) §3.5 "0" stat sub-line (stub: "The app asks the network for nothing.").
- PR-2 acceptance adds: §4.6 ambient audit (≤3 concurrent **at any offset — the four band boundaries sampled explicitly**, ≤1 pet idling) with paint-flashing evidence (incl. the §4.4 tail/ear-sized-invalidation check) · §4.7 matrix walked manually (reduced-motion **and** no-JS, both themes) · §4.8 budgets measured **on terser/esbuild-minified inline output** (JS ≤3KB gz itemized, total ≤65KB gz, captures + pet figures ≤650KB served) · fold budget at 1280×700 + 1440×780 **+ the 1200×1920 tall-viewport LCP spot-check (§3.1)** · **V2 stage travel ≤220vh** · **`sheet-close` paper-quality checkpoint with the pre-decided flat-settle kill-switch** · **crane pause-frame approved as a standalone still (§2.3)** · the §4.1 manual contrast pass (cream surfaces + edges, bubble pairings, H1 gradient endpoints — both themes) · pet roster frozen at ≤6 bubbles (a 7th requires deleting one; **bubble 2 must argue for its life or the roster is five**) · Lighthouse ≥95 both themes.
- Implementation rules gain one line: *the pet-copy rule is binding — every bubble coaches or proves; if a proposed line is merely charming, cut it. When in doubt, cut motion, cut copy, keep contrast — unchanged.*

### Revision 3 critique fixes applied (record)


- **Captions no longer drift:** per-capture version pinned in a new captures manifest (`landing-captures.json`); captions render from the pin, never live `release.ts`; build check warns when a pin trails the release by >1 minor (§2.1, §3.0).
- **TSA gate is page-wide:** §2.7 now blocks every timestamp mention — Fold 3 copy, Fold 3 caption, Fold 4 "0" stat sub-line — with one grep-able gate list in §12; stub copy pre-written.
- **Crane premise rebuilt:** gzip-dedupe clause deleted (32KB window makes it impossible — measured 0% dedup); ONE animated inline crane at `#final-fold` is now the architecture, hero is a designed static one-fold-short frame (first-class composition, approved as a standalone still); §2.3 escalated to first pre-work task with a go/no-go before PR-2; full play retimed ≤5s so the no-JS one-shot clears WCAG 2.2.2; dual-inline only as an upgrade if the rebuild lands <~28KB raw.
- **Crown contradiction resolved:** crown stays a non-SMIL transparent node; `html:not(.js) #final-fold .crane-crown{opacity:1}` scoped to final-fold only; hero is static in every mode; §4.7 rows rewritten.
- **WCAG 2.2.2 pause/stop/hide:** pet idle window trimmed to ≤4.5s; corner-lift finite (×2, re-armed per re-entry); shade-drift finite (2 cycles, freeze at rest) — no pause-control JS needed; no-JS pets inverted to static-by-default, SMIL revealed under `html.js`.
- **Paper tokens sanctioned:** one tokens.css amendment (`--of-paper`, `--of-paper-ink`, `--of-paper-edge`, per theme); light-theme paper gets a ≥3:1 edge; bubble surfaces explicitly specified (never gray-2 on paper); §4.1 wording amended; named contrast-pass rows added.
- **H1 gradient theme-scoped:** light theme ends at `var(--of-accent)` (5.24:1); gradient endpoints added to the manual contrast checklist.
- **Act tint made composited:** both tint states pre-painted as stacked gradient layers, opacity crossfade; text consumers transition `color` only; hysteresis added (second upper sentinel) so slow scrubbing can't strobe the shift.
- **Register blur fixed:** V2 scene 3 spec'd — capture readable untouched first, two cream ILLUSTRATION halves fold over it, packet is chrome-free illustration register with its own label.
- **Handoff obeys single-idler:** Gami is already paused/static at the sentinel; only Ori twitches; "ears settle" deleted.
- **Final-fold motion pileup cut:** pets render pre-arrived (static figures, bubbles as styled captions); crane completion + crown is the band's only motion; added to §4.6 audit.
- **Cute-density trimmed:** card 6 quip is now product-fact ("The whole workspace, menus to tooltips, in six languages."); Gami mentions capped at roster + the one honesty caption.
- **CJK reduced to one moment:** step tiles use plain 1/2/3; 間 is the page's single CJK glyph, wrapped `lang="ja" aria-hidden` with an sr-only English equivalent.
- **SHA chip cut entirely** (deref chain, sessionStorage cache, `chip-in` keyframe, CLS risk all removed); hero metadata = version · released date, baked.
- **Sticky stage bounded:** total travel ≤220vh (~70vh/step); nav "Features" anchor lands at the crease-pattern grid below the stage; cap added to §12.
- **Fold 2 claim gated:** new §2.10 export text-layer fidelity check; shipping sub softened (drops "on the real page") until export-side preservation is verified; H2 stands (editing IS in-place).
- **Capture paths corrected (verified):** three of seven captures live in `docs-site/public/assets/gifs/`, `docs/assets/screenshots/` holds only 5; §2.1 fixed; PR-2 first commit moves the three PNGs into `screenshots/` and updates the two docs references.
- **Pet SMIL paint cost:** build-time inline copies may hoist animated groups out of filter subtrees (assets on disk untouched); acceptance = paint-flashing shows tail/ear-sized invalidations only.
- **Ambient cap restated:** ≤3 at any scroll offset, band boundaries included; §12 audit samples the four boundaries; single-idler also suspends corner-lift.
- **Keyframe holes pinned:** egress-retract rebuilt as scaleX + opacity arrowhead; card-lift shade = pre-rendered pseudo-element shadow, opacity crossfade; crease-sweep = `scaleX` origin-left; pet-arrive sweep = translating gradient overlay (`background-position` banned).
- **CLS pinned:** UA gate runs synchronously in the inline IIFE before first paint; CTA sub-label gets `min-width` in ch + tabular-nums; `html.js` snippet is the first element of `<head>`.
- **PRM matrix completed:** card-lift row corrected (drops translate under PRM); `scroll-behavior: auto` under PRM; static crane companion + both figure SVGs counted in §4.8.
- **AT fixes:** aria-live bubble mirror deleted (bubbles are flow content — no double announcement); V2 scenes toggle `visibility` with opacity; copy buttons get `aria-label` + `role="status"` confirmation; pet SVG `role="img"`/`aria-label` overridden with `aria-hidden` at inline time (rule added to §2.5).
- **JS budget honest:** terser/esbuild-minified inline output mandated in §12; enhancer re-itemized at 1.4KB (SHA deref gone, UA gate sync); caps kept as measured-minified numbers.
- **LCP pinned:** left-column-first DOM order binding in §3.1; tall-viewport (1200×1920) LCP spot-check added; Fold 1 capture drops `loading=lazy` if it enters that initial viewport.
- **Roster polish:** line 1 recast ("Bring the whole messy pile. I'll keep it straight."); bubble 2 kept but flagged provisional — must survive the coach-or-prove review or the roster drops to five.
