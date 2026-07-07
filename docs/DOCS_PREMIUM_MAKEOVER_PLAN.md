# Orifold Documentation — Premium Makeover Plan (v3)

**Status:** Planning only. Not implemented. Hand this document to Sonnet for execution.
**Supersedes:** `docs/DOCS_MAKEOVER_PLAN.md` (the v1→v2 plan) and `docs/DOCS_SITE_PLAN.md` (the original v1 build spec). Both stay in the repo as history; where they disagree with this document, this document wins.
**Baseline audited:** Orifold **v0.8.1** — the shipped Astro Starlight site in `docs-site/` (56 pages, 11 sidebar sections), the 476-line `README.md`, `docs/assets/`, and `docs/assets/MEDIA_MANIFEST.md` (6 of 14 media slots are now real captures).
**Quality bar:** Apple / Anthropic / Linear / Vercel / SpaceX — minimal, calm, intentional, credible, lightly playful.
**Hard constraints:** free/open-source tooling only · no framework JS runtime on content pages · Lighthouse ≥ 95 perf & a11y · `prefers-reduced-motion` honored everywhere · no synthetic asset presented as a real capture · every claim must match the shipped app.

---

## 1. Executive Summary

Orifold's documentation is already far above average: a task-first Starlight site with a coherent origami design system, honest copy, and (since v0.8.1) six real screenshots. The makeover is therefore **surgical, not structural**. Five things stand between the current site and the premium bar:

1. **The docs now lie about the app's best feature.** v0.8.1 shipped real cryptographic signing (PKCS#12 identities, certificate trust/revocation checks, TSA timestamping, post-export self-check — `Orifold/Signing/` is an entire module), yet `fill-sign/signatures.mdx` and the FAQ still say a signature is "a visual mark, not a cryptographic digital signature." This is the single most damaging accuracy gap *and* the single biggest undersell for recruiters and senior engineers.
2. **Stat drift and stale labels.** `developers/architecture.mdx` and `developers/release-gate.mdx` hardcode "354 tests / 61 files / ~29,000 lines" while `stats.json` (and reality) say 503 / 79 / ~36,000. The sidebar still says "Night Mode & Document Comfort" for a page renamed "Document Comfort"; `releases/v7.mdx` exists but is missing from the sidebar; the README still describes the retired Gentle/Paper/Amber presets; `stats.json` says 3 entitlements while the README says "exactly two."
3. **Half the visuals are still illustrations.** 8 of 14 media slots are hand-drawn SVGs, and the 4 files in `gifs/` are *static SVGs named like GIFs*. Nothing on the site shows the app in motion.
4. **The pet system is built but absent.** Gami and Ori have polished marks and idle animations in `docs/assets/`, appear in exactly one figure, and have no voice anywhere in the docs body.
5. **The developer wing is thin and the homepage is a link farm.** Dev pages run 27–52 lines with no FAQ, no front door, no risk map; the homepage stacks three card grids (15 cards) with no story.

The plan below fixes these with **one new component family (PetTip, Stat, Details, Media), five new pages, one homepage rebuild, eight media captures, and a repo-wide staleness sweep** — no framework change, no new fonts, no animation library, no paid tooling.

---

## 2. Current Documentation Audit (Iteration 1)

### 2.1 Inventory

| Surface | State |
|---|---|
| `README.md` | 476 lines. Strong voice, animated crane hero, badges, collapsibles. Some staleness (below). |
| `docs-site/` | Astro Starlight, dark-default, tokens mapped from `DesignSystem.swift` (`tokens.css`, 313-line `theme.css`), folded-corner motif. 56 `.mdx` pages, 11 sidebar sections. Deploys via `.github/workflows/docs.yml` to `udhawan97.github.io/Orifold`. |
| Components | `Card`, `CardGrid`, `Callout` (tip/note/warning/danger/whentouse), `Figure`, `Badge`, `Kbd`, `TrustStrip`, `HeroReducedMotion` + overrides `Hero`, `Footer`, `MarkdownContent`, `PageTitle`. |
| Data | `stats.json` (current, correct: v0.8.1 / 503 tests / 79 files / ~36k LOC / 6 languages / 50 files / 3 entitlements) and `popular.json`. **Neither is consumed by any page.** |
| Media | 14 slots tracked in `docs/assets/MEDIA_MANIFEST.md`: **6 real PNG captures** (empty state, annotated window, markup tools, Document Comfort popover, Reader Mode, language switcher), **8 illustrated SVGs** (4 in `screenshots/`, 4 static "gifs"). |
| Brand assets | `orifold-crane-fold.svg` (hero, animated, reduced-motion aware, ~155KB), hero banners + value props (README), `gami-mark.svg`, `ori-mark.svg`, `orifold-dog-wag.svg`, `orifold-cat-twitch.svg`, two v3 concept diagrams. |
| `docs/` folder | Release notes v3–v0.8.1 mixed with internal plan docs (signing specs, feature plans, two superseded docs plans). |

### 2.2 Outdated / wrong (root problems, ranked)

| # | Problem | Where | Severity |
|---|---|---|---|
| 1 | **Signing docs contradict the shipped app.** Drawn-signature page + FAQ say "not a cryptographic digital signature"; v0.8.1 shipped PKCS#12 identities, self-signed profiles, trust/revocation evaluation, TSA fallback chain, async signing with cancel, post-export structural self-check (`Orifold/Signing/`, verified with pdfsig). | `fill-sign/signatures.mdx:28`, `help/faq.mdx:20` | **Blocking** — factually wrong + undersells the most technically impressive subsystem |
| 2 | **Stat drift.** "354 tests, 61 files, ~29,000 lines" hardcoded despite `stats.json` existing with 503/79/~36k. | `developers/architecture.mdx:43`, `developers/release-gate.mdx:7` | High — rots every release |
| 3 | **Entitlement count conflict.** README: "exactly two entitlements." `stats.json`: 3. One is wrong — verify against `Orifold/Resources/Orifold.entitlements` and fix both to match. | README §Privacy, `stats.json` | High — this is the trust page's core claim |
| 4 | **README feature staleness.** Still describes "Night Mode with Gentle/Paper/Amber warmth presets"; v0.8.1 replaced this with Document Comfort (Default / Night / Eye Care / Focus + warmth/brightness/contrast). Also no mention of Find & Replace, folder import, the Settings window, or cryptographic signing — all v0.8.1 features. | `README.md` What-it-does tables | High |
| 5 | **Sidebar staleness.** Label "Night Mode & Document Comfort" vs. page title "Document Comfort"; Release Notes section lists v6–v3 but omits `releases/v7.mdx` (orphaned page) and has no v0.8.1 entry beyond "What's new". | `astro.config.mjs` | Medium |
| 6 | **Static SVGs posing as GIFs.** `public/assets/gifs/*.svg` don't move. A discerning viewer reads them as placeholders; nothing shows the app in motion. | 4 pages | High for credibility |
| 7 | **Pets built, not used.** No PetTip component; marks appear once. The "companion" brand promise stops at the app boundary. | site-wide | Medium |
| 8 | **Dev wing shallow.** 7 pages, 27–52 lines each; no dev FAQ, no start-here/risk map, no release-engineering page, no roadmap/non-goals. | `developers/*` | High for recruiter/contributor audience |
| 9 | **Homepage is grids, not a story.** 15 cards in three stacked grids; the "Explore" grid duplicates the sidebar. | `index.mdx` | Medium |
| 10 | **No accessibility page** despite the app shipping Reduce Motion support, Reader Mode, Document Comfort/eye-care — an easy, on-brand credibility win left on the table. | site | Medium |
| 11 | **`docs/` housekeeping.** Superseded plan docs and implemented feature plans sit beside release notes, confusing "what is current." | `docs/` | Low |

### 2.3 Cluttered / repetitive / underselling

- **Homepage**: three card grids flatten hierarchy; no "why Orifold" narrative, no visual proof (the six real screenshots aren't shown anywhere above the fold of anything).
- **Companion page** (`get-started/companion.mdx`, 44 lines): fold-craft prose is charming but dense; the tuck-into-`<details>` treatment from the v2 plan is still right.
- **README**: the double hero (banner SVG + value-props SVG + 6 large badges + letter-spaced "BUILT WITH" + 7 more badges) is the one place the repo over-decorates. Recruiters see badge soup before they see the product. Consolidate to one badge row + one hero visual.
- **Undersell list**: cryptographic signing (worst), export integrity gate (qpdf structural check on *every* export — quietly world-class), corrupt-PDF repair on import, the 6-language localization with test-enforced coverage, and the release gate itself. Each deserves a "why it matters" line where users see it and an engineering paragraph where developers do.

### 2.4 Hard to navigate / understand

- Casual users: fine — task-first IA works. Weakest point is connective tissue: the core loop (import → arrange → export) is split across three pages with no single "watch it happen" moment.
- Developers: no entry order. Seven flat pages with no "read these first," no module risk map, no FAQ. A senior engineer has to reconstruct the mental model themselves.

---

## 3. Root Problems (one paragraph each)

1. **Truth debt.** The app moved faster than the docs (crypto signing, Document Comfort, toolbar redesign). A premium doc site's first property is that it never contradicts the product. Fixing accuracy outranks every visual improvement in this plan.
2. **Single-source discipline exists but isn't wired.** `stats.json` was created for exactly this and then never consumed. The fix is a component, not a policy.
3. **Credibility media gap.** Real product > illustration. Six real captures proved the pipeline works; the remaining eight slots (especially the four motion slots) are the difference between "nice student project" and "shipped product."
4. **Personality is trapped in the app.** The pets are the brand's warmth. Docs currently have the origami geometry but not the companionship. A restrained PetTip system transfers it without Clippy risk.
5. **The developer story is untold.** The engineering (four engines behind protocol seams, staged validated export, real crypto, 503-test gate) is the project's recruiter case — and it's currently seven thin pages with stale numbers.

---

## 4. Missing Elements & Stale Content (checklist form)

**Missing pages:** Developer FAQ · Developers start-here (module map + risk map) · Build & release (CI/CD, notarization reality) · Roadmap & non-goals · Accessibility statement.
**Missing components:** `Stat`, `PetTip`, `Details` (styled), `Media` (video-with-poster).
**Missing content:** cryptographic-signing user docs + dev docs · Find & Replace · folder import · Settings window · initials (verify in-app: if the signature tool supports initials, document; if not, do not invent) · pet showcase/hover behavior (partially documented) · "why it matters" notes on flagship features.
**Stale content to fix:** signature "visual mark only" claims (rewrite, don't delete — the *drawn* signature is still visual; the page must now cover both drawn marks and certificate-based digital signing) · 354/61/29k stats · README Night Mode presets · entitlement count (verify, then align README + stats.json + privacy page) · sidebar labels/releases list · `MEDIA_MANIFEST.md` rows for the 6 captured slots (manifest says remove rows once real — verify done) · README roadmap (compare/side-by-side/redaction still open — keep; confirm none shipped).
**Stale assets:** the 8 illustrated SVGs (disposition in §12) · verify the two "v3" concept diagrams still match the v0.8.1 layer names (they predate the Signing module — the architecture diagram likely omits it: refresh).

---

## 5. The Five Planning Iterations

Each iteration critiques the previous state and records what changed. The remainder of this document is the *output* of iteration 5.

### Iteration 1 — Audit (§2–§4)
Produced the ranked problem list. **Key correction to the inherited v2 plan:** it claimed "every visual is a synthetic SVG mockup" and "stat drift: 354 tests… violating the single-source rule." Both were half-stale: 6 captures are now real, and `stats.json` is now *correct* but *unconsumed*. This plan re-audits against v0.8.1 instead of inheriting v7-era claims. New findings the v2 plan missed entirely: the signing-docs contradiction (its worst miss), the entitlement-count conflict, the orphaned v7 release page, and the renamed Document Comfort page.

### Iteration 2 — Information Architecture (§6–§8)
First draft added six new sections; critique: the existing 11-section task-first IA is a strength — adding top-level weight makes scanning slower, not faster. Final: **keep the IA, add 5 pages, rename 2 labels, restructure 0 sections.** Also rejected: splitting "Fill & Sign" into "Sign (visual)" and "Sign (digital)" pages — one signing page with a clear two-mode structure beats two pages users must choose between. The 60-second-scan test drove above-the-fold rules per page (§8).

### Iteration 3 — Visual Design System (§14)
First draft proposed a custom display typeface and paper-texture backgrounds; critique: both violate the perf budget and the "restraint is the Japanese-modern move" principle — the system font stack also covers CJK/Devanagari for free, which matters for a 6-language app. Final: zero new fonts, zero textures; refine spacing rhythm, cap card usage to navigation moments, promote the `.of-crease` divider to a homepage-only signature, and let the six real dark-mode screenshots *be* the visual richness.

### Iteration 4 — Motion, Media & Pets (§11–§12)
First draft used GIFs as the brief literally asks; critique: GIF is the wrong container at this bar (256 colors, huge, unpausable). Final: **MP4/WebM `<video>` via a `Media` component with poster + reduced-motion poster-only fallback**; the word "GIF" survives only as a colloquial label. Pet critique round: a floating corner mascot and per-section pet narration were both cut — pets punctuate (≤1 per page), never narrate. Scroll-reveal capped at 3 moments, homepage only, IntersectionObserver + CSS, no library.

### Iteration 5 — Recruiter / Contributor / Casual-User Polish (§9–§10, §13, §15–§19)
Re-read the whole plan through four sets of eyes. Changes made in this pass: (a) elevated the signing-docs fix to blocking priority #1 and made "digital signing" a homepage-visible differentiator — no other free Mac PDF tool leads with verified local crypto signing; (b) added the honest-limitations pattern everywhere (beta status, ad-hoc signing/notarization reality, erase-is-visual-only disclosure, self-signed certificate caveat) because senior engineers trust docs that state limits; (c) added the README de-badging pass for recruiter first impression; (d) tightened the Sonnet checklist to file-level instructions with grep-verifiable acceptance criteria; (e) added the four-persona verification loop (§17).

---

## 6. Final Recommended Documentation Structure

Keep the shipped 11-section IA. Changes only — ✚ new, ✎ changed, ✂ removed:

```
GET STARTED             (✎ companion page copy simplified; ✎ first-workspace gets the core-loop video)
IMPORT & ORGANIZE       (✎ import-files adds folder import; unchanged otherwise)
EDIT                    (✎ edit-text honest-scope Details; ✚ Find & Replace covered in search or shortcuts — see note)
ANNOTATE & REVIEW       (unchanged)
FILL & SIGN             (✎ signatures.mdx rebuilt: drawn marks + certificate-based digital signing)
EXPORT & PROTECT        (✎ integrity page gets "why it matters" framing)
READ COMFORTABLY        (✎ sidebar label → "Document Comfort"; page content verified against v0.8.1 presets)
SETTINGS & BASICS
  ├── Change the app language
  ├── Keyboard shortcuts               (✎ verify against v0.8.1 overhaul + cheat sheet)
  ├── Privacy & local-first design     (✎ hierarchy pass: promise → proof; entitlement count fixed)
  └── Accessibility                    ✚ new
HELP                    (unchanged: Troubleshooting ×4 + FAQ; ✎ FAQ signing answer rewritten)
RELEASE NOTES           (✎ sidebar: What's new (v0.8.1) · v7 · v6 · v5 · v4 · v3 — add the missing v7)
DEVELOPERS
  ├── Start here                       ✚ new — module map, read-first order, risk map
  ├── Why Orifold?
  ├── Architecture overview            (✎ <Stat>, Signing layer added, Details deep-dives)
  ├── The engines                      (✎ add Signing/CMS alongside PDFKit/PDFium/qpdf/Vision)
  ├── Build from source
  ├── Build & release                  ✚ new — CI/CD, tagging, notarization honesty
  ├── Localization guide               (✎ Bundle.module/xcstrings gotcha as Details)
  ├── Testing & the release gate       (✎ <Stat>)
  ├── Developer FAQ                    ✚ new
  ├── Roadmap & non-goals              ✚ new
  └── Contributing
```

*Find & Replace note:* it's a v0.8.1 toolbar feature. Do not add a page; add a subsection to `reading/search.mdx` ("Search & replace across your workspace") and a row in shortcuts. One task = one page cuts both ways — don't fragment.

**IA rules (unchanged from v1, restated as law):** task-first verb labels · max 2 levels · one task = one page, split at ~7 steps · `Pro workflow` badge instead of an "Advanced" ghetto · user pages never mention Swift/qpdf/internals outside a single "How it works" footer link.

---

## 7. Homepage Redesign Plan (`docs-site/src/content/docs/index.mdx`)

**Principle:** a calm vertical story — What → Proof → Who → Different → Start → Guides → Developers — with exactly **one** card grid and ≤ 3 motion moments. Scannable in 60 seconds; every section earns its scroll.

| # | Section | Content | Media / motion |
|---|---|---|---|
| 1 | **Hero** | Keep crane-fold animation + "Fold chaos into one clean PDF." Sub: "A free, open-source PDF workspace for macOS. Drop in up to 50 messy files — edit, sign, and export one polished document. Nothing ever leaves your Mac." Buttons: `Get started →` / `Install in 30 seconds`. | Motion #1: existing crane fold (plays once; reduced-motion → final frame — already built). |
| 2 | **Trust strip** | `🔒 100% local` · `🆓 Free · MIT` · `🧪 <Stat tests/> tests gate every release`. | None. Stats via `<Stat>`. |
| 3 | **Proof** | One real screenshot: `the-orifold-window-annotated.png`, full-width, captioned "The whole app in one window: sidebar, canvas, toolbar, inspector." This is new vs. the v2 plan — we now *have* real captures; show one immediately. | Static, lazy, sized. |
| 4 | **The value moment** | "Many files in. One PDF out." Scattered file cards fold into one document (small SVG animated with CSS, IntersectionObserver-triggered, plays once). | Motion #2. Reduced-motion → static before/after frame. |
| 5 | **Who it's for** | Three columns, no cards: Everyday Mac users / Privacy-minded people ("legal, medical, financial docs that must never touch a server") / Developers ("a native, MIT-licensed, four-engine PDF app you can read end to end"). | None. |
| 6 | **What makes it different** | Tight 4-item strip: **Local-only** · **One-workspace merging (merge isn't a step)** · **Real protection — AES-256, sanitize, verified digital signatures** · **On-device OCR**. One "why it matters" line each. | None. |
| 7 | **Popular workflows** | The **one** card grid — 6 cards from `popular.json`: Combine · Edit text · Sign · Fill a form · Compress · Protect. | Hover lift only. |
| 8 | **Meet your guides** | Gami + Ori band: two marks, two one-line personality intros, link to companion page. | Motion #3: one pet entrance (wag *or* tail-curl) on scroll-into-view, plays once. |
| 9 | **For developers** | Two lines + one button → `developers/start-here/`. "503 tests, four engines, one honest architecture page." | None. |
| 10 | **Footer** (keep) | Free · MIT · 100% local · GitHub · latest release. | None. |

**Cut:** the "Explore" grid (duplicates sidebar), OCR + Language homepage cards, grids #2 and #3.
**Budget:** ≤ 100KB transferred excluding search index and the hero screenshot; screenshot served as optimized WebP ≤ 120KB with explicit dimensions; crane SVG loads on this page only.

---

## 8. User-Facing Documentation Plan

Template every user page already follows (keep): frontmatter keywords → `whentouse` callout → **Steps** → one Figure/Media → tips/notes → "What you should see" → Related. Per-page rules:

- **Above the fold:** the whentouse line + the first 3 steps. Nothing else.
- **Collapsible (`<Details>`):** honest-scope caveats, full format/shortcut tables, edge cases, "How it works" internals.
- **Pets:** per the §11 placement map — never more than one per page.

Feature-by-feature plan (major features; columns = summary / media / common mistakes / a11y note / dev link):

| Feature (page) | Plain-English summary to lead with | Media | Common mistakes to document | Accessibility note | Dev cross-link |
|---|---|---|---|---|---|
| Import & open (`import/import-files`) | Drop up to 50 files — PDFs, Word, images, scans — even broken ones; Orifold repairs what it can. ✎ add folder import. | Replace illustrated SVG with real capture of mid-drag empty state | Trying to import file #51; expecting cloud formats (Pages, Google Docs) | Keyboard path: Add Files menu | engines (qpdf repair) |
| Combine (`import/combine`) | Merging isn't a step — arrange, export once. | **Video #1** (drag pages across docs → export) | Looking for a "Merge" button | Drag alternatives via menu | — |
| Organize pages (`import/organize-pages`) | Reorder, rotate, delete from the sidebar; ⌘Z is fearless. | Video (2nd tier) or real screenshot | Fear of destructive delete (undo covers it) | Context-menu = keyboard reachable | — |
| Edit text (`edit/edit-text`) | Click detected text, type, click away. | **Video #2** | Editing scans without OCR first; expecting reflow | High-contrast edit box | Dev FAQ: text-layer preservation |
| Text boxes & drag (`edit/text-boxes`) | Add new text anywhere; drag to position. | Real screenshot | Confusing new-text-box vs. editing detected text | — | — |
| Formatting / Format Painter (`edit/formatting`) | Match, copy, paste, reset formatting between text. | Short video (2nd tier) | Expecting it to work across apps | — | — |
| OCR (`edit/ocr`) | Local Vision OCR makes scans searchable; ⌘F finally works. | Screenshot of ⌘F hit on a scan | Running OCR on born-digital PDFs | OCR output honors VoiceOver reading | engines (Vision) |
| Signatures (`fill-sign/signatures`) | **Rebuild.** Two modes, one page: *Draw & place* (quick visual mark) and *Digitally sign* (certificate-based, verifiable, timestamped). Steps for both; comparison table "Which do I need?"; honest notes: self-signed certs will show as untrusted in other viewers, ad-hoc app signing reality. | **Video #3** (draw → place → export); screenshot of certificate picker | Sending a drawn mark where a verifiable signature is required (now answerable: use digital signing) | Signature drawing has a keyboard/image alternative — verify in app | Dev FAQ + engines (CMS, TSA, trust) |
| Forms (`fill-sign/forms`, `lock-forms`) | Detect fields, type answers, lock before sharing. | Video (2nd tier) | Forgetting to lock; expecting XFA support (verify) | Field navigation via Tab | — |
| Toolbar (`get-started/the-window`) | ✎ verify against v0.8.1 consolidated toolbar + Settings window; re-annotate screenshot if drifted. | Real capture (exists — verify current) | — | Pointer-free operation | — |
| Keyboard shortcuts (`settings/shortcuts`) | ✎ audit table against the v0.8.1 overhaul; add Find & Replace. | None (tables) | — | This *is* the a11y feature | — |
| Recently viewed (`import/recently-viewed`) | The shelf remembers; thumbnails are local. | Real capture (needs persisted history to shoot) | Privacy worry → answer inline: cached locally only | — | — |
| Document Comfort (`reading/night-mode`) | Four presets + warmth/brightness/contrast. ✎ verify preset names in-app. | Real capture (exists) | Confusing app dark mode vs. page rendering | Link from new Accessibility page | — |
| Language (`settings/language`) | 6 languages, switchable on the landing screen. | Real capture (exists) | — | — | localization guide |
| Export & save (`export/export-save`) | ⇧⌘E → pick format → done. "Where did my file go?" answered inline. | **Video #4** | Expecting live sync to source files | — | Dev FAQ: export pipeline |
| Companion (`get-started/companion`) | ✎ simplify top; fold-craft prose into `<Details>`; document switching, hover showcase, Hide Tips, Reduce Motion behavior. | Real capture of both pets (needs companion-switch reset) | Thinking the pet is mandatory (it's optional — lead with that) | Showcase respects Reduce Motion — say so | — |
| Accessibility (`settings/accessibility`) ✚ | What the app offers: Reduce Motion support, Reader Mode, Document Comfort, keyboard coverage, VoiceOver status (be honest about gaps). | None or 1 screenshot | — | This page is the note | — |

---

## 9. Developer Documentation Plan

**Goal:** a senior engineer forms a correct mental model in 10 minutes and knows what not to break; a recruiter sees evidence of engineering judgment in 2.

- **`developers/start-here.mdx`** ✚ — module map from the real tree (`App/ DesignSystem/ Document/ Engine/ Models/ Pet/ Resources/ Signing/ ViewModels/ Views/` + `Packages/` vendored PDFiumBinary/QPDFBinary), a read-first order (Why → Architecture → Engines → Build → FAQ), a **risk map** ("touch carefully: export pipeline, encryption/sanitize, Signing, text-layer preservation"), and the onboarding promise: "if `swift test` passes, you're set up." One Ori note.
- **`developers/architecture.mdx`** ✎ — wire `<Stat>`; **add the Signing layer** (the current page and diagram predate it); add 2–3 `<Details>` deep-dives (staged export pipeline stage list; the PDFKit re-serialization/text-layer story and why import goes through a qpdf-preserving normalizer; protocol seams + why engines are swappable).
- **`developers/engines.mdx`** ✎ — currently four engines; make it five responsibilities: PDFKit (composition/display), PDFium (image ops), qpdf (repair/AES-256/sanitize/structural validation), Vision (OCR), **Signing (CMS construction, PKCS#12 + self-signed identities, TSA timestamping, trust evaluation)**. One table + one `<Details>` per engine.
- **`developers/build.mdx`** — keep; verify commands still match README's release gate.
- **`developers/build-release.mdx`** ✚ — how a release is actually cut: version bump, tag, `release.yml`, the ad-hoc-signed/not-notarized reality and the quarantine-clearing installer, asset naming, where logs land. Distill from `ci.yml`, `release.yml`, `codeql.yml`, `dependency-review.yml`, `docs.yml` — list what each gate checks.
- **`developers/localization.mdx`** ✎ — keep top-level; add the SPM `Bundle.module` xcstrings gotcha (swift test never compiles xcstrings; JSON fallback) as a `<Details>` — it's a genuinely useful war story.
- **`developers/release-gate.mdx`** ✎ — `<Stat>`; link the README's exact command list rather than duplicating it.
- **`developers/roadmap.mdx`** ✚ — Now / Next / Later / **Non-goals** (no cloud sync, no telemetry, no Windows/iPad, no collaborative review — stated kindly). Sync the "Now" list with the README roadmap (redaction, compare, large-doc perf, UI smoke tests).
- **`developers/contributing.mdx`** ✎ — add "how to document a new feature" (docs-site page template + MEDIA_MANIFEST row + stats.json regeneration), and "architecture changes must update the diagram."

---

## 10. Developer FAQ Plan (`developers/faq.mdx` ✚)

Format: question → first-sentence answer → optional `<Details>` deep dive. One Ori note at the riskiest-parts answer. Questions to ship (16):

1. **How does Orifold render PDFs?** PDFKit displays and composes; PDFium handles image-level work. *Details:* why two engines.
2. **How does text editing work?** Detected text is edited in place against real PDFium geometry (rotation/transforms), then re-exported. *Details:* the "edit lands on top" history — PDFKit re-serialization destroys Type3/Skia text layers, so import runs through a qpdf-preserving normalizer; hidden/low-visibility text classification and the invisible-text export-leak fix.
3. **How are text boxes positioned and updated?** Anchored in page coordinates, live-dragged, committed to workspace state with undo snapshots.
4. **How does format matching/copying work?** Captured attributes applied to the target selection; reset restores detected formatting.
5. **How are annotations handled?** Visual annotation layer during editing; burned in ("flattened") during export so they can't be silently edited afterward.
6. **How are signatures handled?** Two distinct systems: drawn marks (annotation layer) and cryptographic signing (CMS signature with certificate identity, optional TSA timestamp, trust/revocation evaluation, post-export self-check). *Details:* the Signing module layout; known limitation of self-signed profiles.
7. **How does import/export work?** Import: repair-normalize (qpdf) → workspace. Export: staged pipeline — flatten → bake decorations → compress → sanitize → encrypt → **structural validation gates the write**. *Details:* stage list, failure behavior.
8. **How are keyboard shortcuts structured?** Single command wiring in `App/`; overhauled in v0.8.1 to macOS conventions.
9. **How does localization work?** `Localizable.xcstrings`, 6 languages, coverage enforced by a test. *Details:* the SPM/CI gotcha.
10. **How is state managed?** One observable view model; views send intents; engines behind protocol seams; unidirectional.
11. **How should I test changes?** `swift test` locally (smoke filter for speed), then the full release gate. *Details:* CI-only PDFKit `.string` extraction quirk on older SDKs — use `.attributedString` in tests.
12. **What should I read first?** Link start-here.
13. **What are the riskiest parts?** Export pipeline, encryption/sanitize, signing, text-layer preservation, the sandbox boundary. *(Ori: "Understand the export pipeline before touching anything that feeds it.")*
14. **What must I never break?** The export validation gate, the local-only boundary (never add networking beyond TSA requests the user initiates), localization coverage, entitlement minimalism.
15. **How are releases created / what CI runs?** Link build-release.
16. **How should new features be documented?** Link contributing §docs.

---

## 11. Gami & Ori Pet Guide System

Reuse existing assets only (`gami-mark.svg`, `ori-mark.svg`, wag/twitch SVGs). No new art.

**Component: `PetTip.astro`** — `who="gami|ori"`, built on Callout styling with the folded-corner motif. 28–32px inline `currentColor` mark (aria-hidden), text label carries identity (`role="note"`, `aria-label="Gami's tip"` / `"Ori's note"` from translatable UI strings). In normal document flow — **never floating, never fixed, never overlapping text**. Motion: static by default; one-time subtle wag/twitch on scroll-into-view only under `prefers-reduced-motion: no-preference`. On mobile it renders identically (full-width callout); nothing to reposition.

**Voice split (strict):**

| | Gami (dog) | Ori (cat) |
|---|---|---|
| Tone | Energetic, loyal, encouraging, beginner-first | Curious, precise, charmingly bossy, technical |
| Territory | Get Started, user workflow pages, "try this first" | Developer pages, edge cases, honest-scope warnings |
| Sample | "First time? Gami recommends starting with one small PDF — you'll know 80% of Orifold in five minutes." | "Ori's note: the export pipeline validates every write. Break the validator and nothing ships — including your feature." |

**Placement map (the complete list — nothing else gets a pet):**

| Page | Pet | One line about |
|---|---|---|
| Homepage guides band | Both | Introductions (the front door) |
| get-started/first-workspace | Gami | Encouragement at the start |
| get-started/companion | Gami | "You can hide me anytime" |
| edit/edit-text | Ori | Scans need OCR first |
| fill-sign/signatures | Ori | Drawn vs. digital — pick deliberately |
| export/export-save | Gami | Flatten-before-sharing nudge |
| developers/start-here | Ori | Read order |
| developers/faq (riskiest parts) | Ori | Don't break the gate |
| 404 page | Either | One charming line |

**Rules:** ≤ 1 pet tip per page · Gami never on developer pages, Ori never on Get-Started (exception: the two shared front doors) · never inside warnings/danger callouts, troubleshooting steps, or tables · if a tip fits neither voice it's a plain Callout · all pet copy is real page content (translatable) · density audit is a QA gate (§17).

**Anti-childish guardrails:** no speech bubbles, no exclamation stacking, no pet reactions to scrolling, no sound, no persistent presence. The pets are margin notes with a face, not a character system.

---

## 12. GIF / Screenshot / SVG / Animation Strategy

### 12.1 Format ruling
"GIF" in the brief = **short silent `<video>`** (H.264 MP4 + WebM, `autoplay muted loop playsinline preload="none"`, poster PNG/WebP, IntersectionObserver play/pause, reduced-motion → poster only, `aria-label` + visible caption). Real .gif files: never committed. Component: `Media.astro`.

### 12.2 The four first-tier clips

| Clip | Page | Exact flow | Length | Loop | Caption | Fallback |
|---|---|---|---|---|---|---|
| combine | import/combine | Two demo docs in sidebar → drag a page across → Export → one file | 4–6s | Yes | "Arrange, then export once." | Poster |
| edit-text | edit/edit-text | Click detected line → type change → click away → text commits | 3–5s | Yes | "Click, type, done." | Poster |
| sign | fill-sign/signatures | Draw signature → place on demo line → export | 4–6s | Yes | "Drawn and placed locally." | Poster |
| export-save | export/export-save | ⇧⌘E → format picker → save panel → confirmation | 3–5s | Yes | "One shortcut to a finished file." | Poster |

Second tier (only if capture is cheap): ocr, forms-lock, document-comfort presets, companion-switch, recently-viewed. Everything else stays static.

**Capture standards** (inherit `MEDIA_MANIFEST.md`, keep): app UI only, dark mode, 1600×1000, obviously-fake demo docs (`Sample Agreement.pdf`…), one companion constant across all captures, no desktop/menu-bar/personal anything. Video ≤ 1.5MB, poster ≤ 60KB, ~24fps, clean loop (first frame == last). Free tooling: macOS screen recording + ffmpeg.

### 12.3 Asset-by-asset disposition

| Asset | Decision |
|---|---|
| `orifold-crane-fold.svg` | **Keep** — signature hero; verify homepage-only (155KB). |
| Hero banners / value-props SVGs | **Keep, README-only**; refresh text if claims change (e.g., "12+ tools"). |
| `orifold-v3-architecture-diagram.svg` | **Refresh** — add Signing layer, verify labels vs. v0.8.1; rename file without "v3". |
| `orifold-v3-workspace-diagram.svg` | **Keep, verify** labels; rename without "v3". |
| `gami-mark.svg`, `ori-mark.svg` | **Promote** → PetTip marks. |
| `orifold-dog-wag.svg`, `orifold-cat-twitch.svg` | **Wire in** → homepage guides band entrance. |
| 6 real PNGs (empty state, window, markup, comfort, reader, language) | **Keep**; verify against v0.8.1 toolbar redesign — the annotated-window shot is highest drift risk. |
| `screenshots/*.svg` ×4 (import overview, edit-text workflow, recently-viewed shelf, companion pair) | **→ real capture.** Until captured: honest dashed-placeholder Figure state, never an illustration presented as a screenshot. |
| `gifs/*.svg` ×4 | **→ `Media` video** (the four clips above). Delete the static SVGs once replaced. |
| Favicon/app icons | **Keep.** |

### 12.4 Animation standards
Allowed: 120ms hover transitions · theme cross-fade · smooth `<details>` expand · scroll-reveal fade-up (8–12px, 300ms, once) on homepage sections only · the three homepage motion moments (§7) · one-time PetTip idle. Forbidden: animation libraries (GSAP/Framer/AOS), parallax, looping body-content animation, motion that blocks reading, anything that costs a Lighthouse point. Implementation: CSS + ~1KB IntersectionObserver.

---

## 13. Accessibility & Performance Requirements

**Accessibility (WCAG 2.1 AA):** alt text on every image; caption + `aria-label` on every Media; on-frame text labels inside demo clips; reduced-motion path for *everything* (crane final frame, no scroll-reveal, no pet idle, video → poster); full keyboard operability (skip-link, sidebar, `/`+`⌘K` search, theme toggle, ToC, every `<details>`, PetTips are non-interactive flow content); pet marks `aria-hidden` with text identity; contrast ≥ 4.5:1 both themes for all token pairs; screen-reader spot-checks with VoiceOver; layouts survive +40% string length and CJK line-breaking; no horizontal scroll at 360px.

**Performance:** content pages ship zero framework JS; homepage ≤ 100KB transfer excluding search index + hero screenshot; images lazy with explicit dimensions (no CLS); WebP/AVIF for raster; videos `preload="none"` + off-screen pause; crane SVG homepage-only; Lighthouse mobile ≥ 95 Performance and ≥ 95 Accessibility on homepage + one task page + one dev page; minimal dependency policy (Starlight + nothing else new).

---

## 14. Visual Design System Recommendations

Keep the shipped system — it's the right one. Refinements only:

- **Typography:** system stack stays (perf + 6-language coverage). Add heading letter-spacing −0.01em to −0.02em at display sizes; hero H1 `clamp(2rem, 5vw, 3.25rem)`. No new fonts, ever.
- **Spacing:** enforce a 1.5 / 2.5 / 4rem vertical rhythm; 72ch content column; generous 間 (ma) — whitespace is the origami statement.
- **Layout grid:** single column content; homepage sections full-width bands alternating on the canvas token, no background color stripes.
- **Cards:** folded-corner cards reserved for navigation moments (homepage grid, section landings). Body pages use prose + Callouts + Steps. Card hover: 1px lift + shadow token, 120ms.
- **Callouts:** existing five variants + PetTip. Danger/warning stay visually sober (no pets, no motif).
- **Code blocks:** Starlight/Expressive Code defaults; ensure both-theme contrast; `Kbd` for shortcuts.
- **Tables:** short enumerable facts only; zebra off; align with token borders.
- **Screenshots:** always inside `Figure` with caption; consistent dark-mode chrome; subtle 1px border + radius token so dark captures don't bleed into dark theme.
- **Dividers:** `.of-crease` skewed divider = homepage signature only, never in body pages.
- **Navigation:** keep sidebar; verify breadcrumb/prev-next defaults enabled; developer wing gets its front door via start-here.
- **Footer:** keep; add "Docs follow the app — spot drift? Open an issue" line.
- **Dark/light:** dark is brand-default; every new component verified in both.
- **README (GitHub face):** consolidate to **one** badge row (macOS · release · license · privacy), keep crane + one hero banner, drop the letter-spaced BUILT-WITH block in favor of a single-line tech list, keep the collapsible structure. GitHub README ≠ docs site: it keeps its animated SVGs (GitHub can't do video/JS) and links hard to the site.

---

## 15. Content Tone & Copy Direction

**Voice:** calm, confident, precise, lightly witty — the existing "⌘F finally works on that thing your printer emailed you" register is exactly right; keep that frequency (≈ one wry line per page, max).
**Rules:** short sections · headings state outcomes ("Combine files into one PDF", never "Merging functionality") · "Why it matters" one-liners on flagship features · first sentence of every `<Details>` summary states the takeaway · honest limitations stated plainly (beta, ad-hoc signing, self-signed trust warnings, erase-is-visual-only) · no marketing superlatives, no "blazingly", no vague claims, no repetition between README and site (README = pitch + install + pointers; site = the manual).
**Japanese origami identity:** expressed through geometry, restraint, and naming (fold/crease/paper motifs) — not through decoration, not through Japanese words sprinkled in copy. One allowed exception: the 間 whitespace principle may appear once, on the developers/why-orifold page.

---

## 16. Exact Implementation Checklist for Sonnet

> Ground rules: do not invent features — when unsure what the app does, check the source (`Orifold/`) and write honest scope. Free/open-source tooling only. Preserve the IA and tokens. Media capture requires the running app: implement placeholder-honest states wherever a capture isn't available, and never present an illustration as a capture. Work in phases; each phase ends green (`npm run build` in `docs-site/`).

**Phase 0 — Truth sweep (blocking, do first)**
- [ ] Verify entitlement count: read `Orifold/Resources/Orifold.entitlements`; align `stats.json`, README §Privacy, and `settings/privacy.mdx` to the real number.
- [ ] Rebuild `fill-sign/signatures.mdx`: two modes (draw & place / certificate-based digital signing). Source facts from `Orifold/Signing/` (PKCS12 + self-signed providers, `CertificateTrustEvaluator`, TSA chain) and `docs/release-v0.8.1.md`. Include "Which do I need?" table + honest self-signed-trust caveat. Fix `help/faq.mdx:20` to match.
- [ ] README staleness pass: Document Comfort presets (replace Gentle/Paper/Amber — verify real preset names in `Orifold/` source), add Find & Replace + folder import + Settings window + digital signing to feature tables, verify roadmap items still open.
- [ ] `astro.config.mjs`: sidebar label → "Document Comfort"; Release Notes → What's new · v7 · v6 · v5 · v4 · v3.
- [ ] Verify `settings/shortcuts.mdx` table against v0.8.1 shortcut overhaul (source: `Orifold/App/` command wiring).
- [ ] Verify `get-started/the-window.mdx` + its screenshot against the v0.8.1 toolbar/sidebar redesign; flag the screenshot for recapture if drifted.

**Phase A — Components & plumbing**
- [ ] `src/components/Stat.astro` — renders a field from `src/data/stats.json` as text.
- [ ] Replace hardcoded stats in `developers/architecture.mdx` + `developers/release-gate.mdx`. Acceptance: `grep -rn "354\|29,000\|61 source" docs-site/src/content` → empty.
- [ ] `src/components/Details.astro` — styled `<details>/<summary>`, folded-corner motif, takeaway-first summary.
- [ ] `src/components/PetTip.astro` — per §11 (who prop, aria pattern, reduced-motion-safe one-time idle, normal flow).
- [ ] `src/components/Media.astro` — per §12.1, with an honest dashed-placeholder state showing the capture spec when no `src`.
- [ ] Styles for all four in `theme.css` using existing tokens.

**Phase B — Homepage (`index.mdx`)**
- [ ] Implement §7 section order exactly; one card grid; delete Explore grid + OCR/Language cards.
- [ ] Add proof screenshot band, value-moment SVG animation (IntersectionObserver + CSS, reduced-motion static), guides band with one pet entrance, dev band, `<Stat>` in trust strip.
- [ ] Verify homepage weight budget and crane-only-here.

**Phase C — New pages (add each to sidebar per §6)**
- [ ] `developers/start-here.mdx` (module map from real tree, read order, risk map, 1 Ori note).
- [ ] `developers/faq.mdx` (§10, 16 questions, Details for depth, 1 Ori note).
- [ ] `developers/build-release.mdx` (distill `.github/workflows/*.yml` + `scripts/install-mac.sh` honestly).
- [ ] `developers/roadmap.mdx` (Now/Next/Later/Non-goals; sync with README roadmap).
- [ ] `settings/accessibility.mdx` (what the app actually offers; be honest about gaps).

**Phase D — Content polish**
- [ ] `developers/architecture.mdx`: add Signing layer + 2–3 Details deep-dives (§9).
- [ ] `developers/engines.mdx`: five engines incl. Signing.
- [ ] `developers/localization.mdx`: xcstrings/CI gotcha as Details.
- [ ] `reading/search.mdx`: add Find & Replace subsection; `import/import-files.mdx`: add folder import.
- [ ] `get-started/companion.mdx`: simplify top, fold-craft into Details.
- [ ] Honest-scope Details on `edit/edit-text.mdx` (+ text-layer story link) and signatures.
- [ ] "Why it matters" one-liners: local-only, AES-256, sanitize, OCR, one-workspace merge, export gate, digital signing.
- [ ] Hierarchy pass on `settings/privacy.mdx` (promise → proof).
- [ ] Insert PetTips exactly per the §11 placement map — nowhere else.
- [ ] `docs/` housekeeping: move superseded plans (`DOCS_SITE_PLAN.md`, `DOCS_MAKEOVER_PLAN.md`) and implemented feature plans into `docs/archive/`; leave release notes + this plan + `MEDIA_MANIFEST.md` + signing specs at top level.

**Phase E — Media (requires running app; do what's capturable, placeholder the rest)**
- [ ] Capture the 4 first-tier clips (§12.2) per capture standards; encode MP4+WebM+poster; wire via `Media`.
- [ ] Delete `public/assets/gifs/*.svg` once each is replaced (never before).
- [ ] Recapture the 4 remaining illustrated screenshots as real PNGs where feasible (recently-viewed needs persisted history; companion pair needs a switch reset — see MEDIA_MANIFEST notes); otherwise honest placeholders.
- [ ] Refresh + rename the two "v3" diagrams (add Signing layer to architecture).
- [ ] Update `MEDIA_MANIFEST.md` to reflect every disposition.
- [ ] README: single badge row, drop BUILT-WITH block, keep crane + one banner (§14).

**Phase F — QA (run §17 in full).**

---

## 17. Testing & Verification Checklist

**Build & links**
- [ ] `npm run build` clean; deploy via `docs.yml`.
- [ ] Zero broken internal links (Starlight link validation or `lychee`); README ↔ site cross-links resolve.
- [ ] `grep -rn "354\|29,000\|61 source" docs-site/src/content` → empty.
- [ ] `grep -rin "not a cryptographic" docs-site/src/content` → only in the drawn-signature *mode* context, never as a page-level claim.
- [ ] Search sanity: "edit text", "combine PDFs", "sign", "change language" each return the right page first.

**Accessibility & performance**
- [ ] Lighthouse mobile ≥ 95 Perf & ≥ 95 A11y on homepage, one task page, one dev page.
- [ ] Reduced-motion emulation: crane static, no scroll-reveal, no pet idle, videos show posters.
- [ ] Keyboard-only pass: skip-link → sidebar → search → ToC → every Details → theme toggle.
- [ ] VoiceOver spot-check: homepage, one PetTip, one Media, one troubleshooting accordion.
- [ ] Responsive 360/768/1280/1600: no horizontal scroll, ToC collapses, pets never overlap text.
- [ ] Every Media: lazy, poster present, ≤ 1.5MB, loops cleanly, labeled.
- [ ] Both themes checked on homepage + one page per template.

**Content integrity**
- [ ] Pet density audit: ≤ 1 per page; voice split holds (Gami ∉ dev pages, Ori ∉ Get Started).
- [ ] No user page mentions Swift/qpdf/internals outside a "How it works" footer link.
- [ ] `stats.json` regenerated against the actual release before ship; entitlement number matches the entitlements file everywhere.
- [ ] No illustrated SVG is presented as a screenshot or GIF anywhere.

**The four-persona review loop (final gate — do all five passes)**
1. **Casual user:** land on homepage cold → can you say what Orifold is in 10s, install in 60s, and find "how do I sign a PDF" in 3 clicks?
2. **Developer/contributor:** start at developers/start-here → do you know the module map, the risk map, and how to run tests within 10 minutes? Does anything contradict the source?
3. **Recruiter/hiring manager:** skim README + homepage + architecture for 2 minutes → do you see real product screenshots, real numbers, stated non-goals, and honest limitations (the credibility markers)?
4. **Accessibility & performance pass:** the checklist above, executed, with numbers recorded.
5. **Staleness sweep:** every screenshot vs. current app build, every stat vs. `stats.json`, every link, zero placeholder assets presented as final.

---

## 18. Risks & Edge Cases

| Risk | Mitigation |
|---|---|
| **Signing docs overshoot** — describing crypto features beyond what shipped, or hiding the self-signed-cert limitation. | Every signing claim sourced from `Orifold/Signing/` + release notes; the self-signed trust caveat and per-signing cert regeneration defect (if still unfixed at implementation time — check) stated plainly. |
| Pets drift toward Clippy. | Hard placement map (§11), ≤1/page, QA density audit, no floating elements. When in doubt: plain Callout. |
| Captures never get made → site stalls. | Placeholder-honest Media/Figure states are shippable; structure lands first, clips drop in with zero code change. |
| Screenshot drift after v0.8.1 toolbar redesign. | Phase 0 verifies the six existing captures; MEDIA_MANIFEST tracks recapture debt; Contributing says UI changes flag affected captures. |
| Stat drift returns. | `<Stat>` everywhere + grep guard in the QA list (consider adding to CI as a docs.yml step). |
| Homepage rebuild hurts nav. | Sidebar + search remain the real navigation; one curated grid stays. |
| Motion tanks Lighthouse or annoys. | ≤3 moments, homepage-only, play-once, no library, reduced-motion kills all; budget-tested pre-merge. |
| Repo bloat from media. | ≤1.5MB/clip, ≤120KB/screenshot budgets; consider Git LFS only if total media exceeds ~25MB. |
| Concurrent sessions touch docs-site (shared repo). | Small commits per phase; rebase before push; `Localizable.xcstrings` untouched by this work. |
| Three plan docs confuse future sessions. | Phase D archives the two superseded plans; this file's header states supersession. |
| Video autoplay on mobile/battery. | `muted playsinline preload="none"`, off-screen pause, poster under reduced-motion. |

---

## 19. Definition of Done

The makeover is complete when all of these hold:

1. **Nothing contradicts the app.** Signing docs cover both modes truthfully; presets, shortcuts, toolbar, entitlements, and stats all match v0.8.1 (or the then-current release); grep guards pass.
2. **The four core flows show the real app in motion** via `Media` (or honest placeholders), and no synthetic asset poses as a capture anywhere.
3. **Homepage tells the story** — What/Proof/Who/Different/Start/Guides/Developers, one card grid, ≤3 motion moments, within budget.
4. **The developer wing has a front door and depth** — start-here, FAQ, build-release, roadmap/non-goals live and linked; architecture includes Signing; deep-dives are collapsible.
5. **Pets are working guides** — PetTip shipped, placed exactly per map, accessible, reduced-motion-safe, ≤1/page.
6. **Accessibility page exists** and the a11y/perf checklist passes with Lighthouse ≥95/≥95.
7. **The site stays calm** — no new fonts, no animation library, no new runtime deps, tokens unchanged, `.of-crease` homepage-only.
8. **README makes a recruiter-grade first impression** — one badge row, current features, hard link to the docs site.
9. **All five verification passes (§17) executed and green**, `docs/` housekeeping done, `MEDIA_MANIFEST.md` current.
