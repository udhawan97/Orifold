# Orifold Website Plan — Landing Page + Download & Release Automation

**Status:** Planning only. Not implemented. Hand this document to Sonnet for execution.
**Date:** 2026-07-07 · **Baseline audited:** v0.8.1 — the shipped Astro Starlight docs site in `docs-site/` (deployed to `https://udhawan97.github.io/Orifold/`), `release.yml` (zip-only), the live GitHub releases (`release-v0.8.1` with a single `Orifold.zip` asset; rolling `Orifold-latest`), the one-line installer, and the Homebrew cask.
**Revision 2 (same day):** re-audited against main after the toolbar redesign (`37ae9b6`) and the docs Media wiring (`aed19d2`) landed. Corrections: **every existing app screenshot now shows the removed pre-redesign toolbar** — the §2.1 capture session recaptures all of them, and §10 gains a post-toolbar docs pass; the "0 network calls" privacy stat was wrong (the shipped trusted-timestamp feature makes opt-in TSA requests — §3.5/§8b copy rescoped); the shipped artifact's version actually comes from the committed `Orifold/Resources/Info.plist`, not `project.yml` (§5.3.1/§7 corrected); `docs.yml` already has `workflow_dispatch` (§5.4); the "Translate" guides-row item had no docs page to link (§3.3); "verifiable in Adobe" overclaimed for the self-signed default (§3.4).
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

## 3. Page structure — 8 bands, one background

One continuous `--of-canvas` ground. **No alternating band backgrounds.** Separation = 5–7rem `padding-block` + exactly **three** `.of-crease` skewed hairlines (after §3.2, after §3.5, before §3.7). Content max-width ~1080px. Heading map: **one H1 (§3.1 headline); every band heading is H2; card titles are H3.** `html { scroll-padding-top: 72px }` so anchor jumps clear the sticky nav.

### 3.1 Nav + Hero + proof shot (one act, fold-budgeted)

**Nav (sticky, 56px):** left — 28px crane app icon + "Orifold" wordmark (a `<span>`, not a heading). Right — `Features · Download · Docs · GitHub`. Mobile — `Features · GitHub` (orientation, not a download nobody can use there). Backdrop: `color-mix(canvas 80%, transparent)` + `backdrop-filter: blur(12px)`, bottom hairline `--of-separator`. Skip-link first in DOM.

**Hero — exactly five elements:**

1. **Eyebrow** (small, gray-2): "Orifold — free, open source, for macOS"
2. **H1:** "Fold chaos into one clean PDF." — `clamp(2.6rem, …, 4.5rem)`, weight 600, `--of-text-1`.
3. **Sub (canonical line, verbatim):** "A free, open-source PDF workspace for macOS. Drop in up to 50 messy files — edit, sign, and export one polished document. Nothing ever leaves your Mac."
4. **Button row:** primary **`Download for Mac`** (solid `--of-accent`, 44px min-height, standard 120ms token hover — no glow ring; down-arrow icon; href = stable dmg URL, §5.1) · secondary ghost **`Read the docs`**. No GitHub button here — it's in the nav.
5. **Metadata rows (gray-2, tabular-nums):**
   - `v0.8.2 · macOS 14+ · Apple Silicon · 14 MB · Free & MIT · beta, built in public` — every value baked from release metadata (§7), never hardcoded in copy. The "Apple Silicon" chip carries a `title` tooltip: "Any Mac with an M-series chip — 2020 or later.  → About This Mac to check."
   - `Not notarized yet — first launch takes one extra step. Details ↓` — anchors to `#download`; this is the inoculation line, same visual weight as the chip.

**Crane mark:** ≤96px, beside the H1 at wide viewports (above on narrow), **after the CTA in DOM order** (positioned via grid `order`) so the pitch streams first. Plays its fold once, freezes on the crane.

**Fold budget (acceptance-gated):** `padding-block-start: clamp(3rem, 8vh, 6rem)`. At 1280×700 and 1440×780, the primary CTA **and the top edge of the proof shot** must be visible — the proof shot overlaps slightly up into the hero (negative margin, Apple product-page style) so the app is present in the first paint.

**Proof shot:** the §2.1 recaptured 2× workspace in a minimal window frame (10px radius, hairline border, soft shadow, folded-corner motif). `loading="eager"`, `fetchpriority="high"`, `<link rel="preload">`, explicit `width`/`height` (no CLS), `astro:assets` `<Picture>` AVIF/WebP, **≤150KB served**. `<figcaption>`: "The whole app in one window. Real capture, v0.8.2, dark mode."

### 3.2 "Many files in. One PDF out." — the fold moment (the page's one scripted animation)

- H2 verbatim. Sub: "A 'simple PDF task' is rarely simple. It is six PDFs, two screenshots, a Word document, a scanned form, and one determined file named `final_final_revised_ACTUAL.pdf`."
- **The animation (in scope, built now):** a hand-built inline SVG (~8KB — *not* the crane) of 7 scattered paper sheets with tiny filename labels. One `IntersectionObserver` (threshold .3, fires once, ~30 lines) adds `.is-folded`; CSS transitions (600ms ease-out, 60ms stagger) translate/rotate the sheets inward, each visually "folding" (two-half `scaleX` with a crease highlight via `--of-fold-shade`) into a single clean document that gains the folded-corner motif. Total ~1.2s.
  - **No-JS guard:** the scattered pre-state applies only under `html.js` (set by a 1-line inline script); no JS ⇒ final folded state renders statically.
  - **Reduced-motion:** final state pre-applied; observer never registered.
- Closer: "Merging isn't a separate step. Broken PDFs are repaired on the way in."

### 3.3 Feature highlights — the one card grid (6 cards)

`.of-card` grid, inline SVG glyphs (one icon language site-wide — no emoji), H3 title + one quip, each card links to its docs page:

1. **Edit PDF text in place** — "Click the text, fix the typo. Real glyph geometry, not a sticky note."
2. **Real AES-256 protection** — "Real AES-256, not a 'protected' flag a reader can ignore."
3. **On-device OCR** — "⌘F finally works on that thing your printer emailed you."
4. **Compress** — "Attachments that stop bouncing off email size limits."
5. **Sanitize** — "A file that carries nothing you didn't intend to send."
6. **Fill & flatten forms** — "Finished paperwork, no third-party e-sign service."

Signatures are deliberately **not** a card (next band). Stamps/Bates/find-replace live in a slim `popular.json`-driven guides row beneath the grid: "More jobs: Combine · Stamps & Bates · Protect · Sign →". Note: today's `popular.json` has no Stamps & Bates entry — add one pointing at `annotate/stamps/` during the PR-2 rewrite. (An earlier draft listed "Translate" here; no such docs page exists — the app switches its own UI language, it doesn't translate documents. Dropped.) Card hover: existing 120ms token behavior only.

### 3.4 Signatures — full-width single-feature band (the undersold flagship)

- H2: "A drawn mark is a picture. A digital signature is math."
- Two short columns: what it does (PAdES cryptographic signatures, Keychain and .p12 identities, optional trusted timestamps) and why it matters (one honest line on the difference between an image of a signature and a tamper-evident seal). Verification claim uses the docs' own wording — "verifies as intact in Adobe and any PAdES-aware viewer" — **not** a flat "verifiable in Adobe": with the zero-setup self-signed default, Acrobat reports the signer's identity as unknown until manually trusted (`fill-sign/signatures.mdx:62`); the trusted-identity indicator needs a CA-issued ID. One real capture or the signing-flow illustration with the honest-caption pattern.
- CTA link: "How signing works →" (docs).

### 3.5 Privacy & trust — one consolidated statement (say it once, well)

- H2: "Everything happens on your Mac. The cloud was not consulted."
- Stat-styled facts, inline SVG glyphs, **app-scoped wording**. ⚠️ Corrected in Revision 2: a flat "0 network calls" is **false** — the shipped signing flow contains a real TSA client (`Orifold/Signing/Timestamp/TimestampClient.swift`) that makes opt-in RFC-3161 requests when the user asks for a trusted timestamp, and §3.4 advertises exactly that feature. Copy scopes the claim to telemetry:
  - **0** — "telemetry, analytics, accounts. There isn't even a server to send them to. The only thing Orifold ever asks the network for: a trusted timestamp, when you request one while signing." *(flips via `site.json.appNetworkCheck` when the Phase-1 update check ships: adds "…and the latest version number — only if you turn that on.")*
  - ~~**Blocking verification before this copy is final**~~ **RESOLVED 2026-07-07:** verified with a sandboxed harness (Orifold's exact entitlements + Info.plist ATS state) — the sandbox WAS blocking all TSA requests (DNS resolution denied, `NSURLErrorDomain -1003`), and ATS was independently blocking the three `http://` fallback TSAs (`-1022`). Fixed in the app repo the same day: `network.client` entitlement added, Sectigo switched to `https://`, per-host ATS exceptions for DigiCert + GlobalSign (which don't serve TLS on their TSA hosts), `settings/privacy.mdx` + `fill-sign/signatures.mdx` copy flipped in the same commit. Re-verified sandboxed: all 4 TSAs return valid tokens. §3.4 may promise timestamps.
  - **4** sandbox entitlements — "app-sandbox, the files you pick, remembering the access you gave, and an outbound-only network line used solely for the trusted timestamp you ask for. That's the whole list." *(Was 3 until 2026-07-07 — the count is already 4 before PR-4; `appNetworkCheck` now flips only the update-check clause in the 0-telemetry stat, not the entitlement count.)*
  - **503** tests gate every release · **Free forever, MIT** — the old TrustStrip content lands here; `TrustStrip.astro` itself stays docs-only, untouched.
- One honest clause, small text: "This page asks GitHub for the latest version number so the button below is always current. The app never does."
- "Verify it yourself" → entitlements file + `settings/privacy` docs page.

### 3.6 Why it exists / who it's for (short, warm)

- Builder voice, ≤3 sentences: "I built Orifold because basic file work on a Mac should not require a subscription, an upload, or a small ceremony. Preview is excellent until the job gets complicated; the more capable tools rent your own files back to you."
- Three compact columns (reuse shipped `.of-columns` copy): Everyday Mac users / Privacy-minded people / Developers.
- **Pet moment:** Gami wag + Ori tail-twitch figures — converted to **finite** SMIL loops (3 cycles, freeze) with static reduced-motion variants (same treatment as the crane). Copy: "Meet Gami and Ori — a guide, not a mascot. Optional, dockable, hideable."

### 3.7 Download band (`id="download"`)

- Repeats `Download for Mac` + metadata row (size baked from the **dmg** asset's `size` field).
- **Apple Silicon explainer, plain language:** "Needs a Mac with an Apple M-series chip — that's any Mac from 2020 on ( → About This Mac to check). Intel Macs aren't supported **yet**." — "yet" links a GitHub issue so Intel demand becomes measurable data. This is copy, not detection: browser JS cannot reliably distinguish arm64 from Intel Macs (Safari reports `MacIntel` on both).
- **First-launch box (`.of-callout-note`, always visible), per-OS, final copy pending the §2.2 machine test:**
  - "Orifold is free and open source, so builds aren't notarized by Apple yet. One-time first launch:"
  - "**macOS 14:** right-click Orifold → Open → Open."
  - "**macOS 15:** open Orifold once (it will be blocked), then System Settings → Privacy & Security → **Open Anyway** → enter your password."
  - "Prefer zero dialogs? The one-line installer below clears quarantine for you." + link to the install-troubleshooting doc.
  - Signed-era copy pre-written behind `site.json.signedBuilds`: collapses to "Signed and notarized by Apple."
- **Other ways to install** (`.of-details`, collapsed): curl one-liner (verbatim, labeled "no dialogs — curl downloads aren't quarantined"), Homebrew cask, direct zip.
- Small: "All releases →".

### 3.8 Footer

- Crane mark + "Orifold · Free, open source, MIT." · Docs · What's New · Privacy · GitHub · License · `v0.8.2 · released 2026-07-XX` (baked, links the release).
- Signature line: "Since nothing you do in Orifold ever leaves your Mac, stars are the only telemetry we get. ⭐"

**Mobile CTA behavior (both download surfaces):** the runtime enhancement script UA-gates: on non-Mac platforms (`userAgentData.platform` / `navigator.platform` ≠ Mac, **plus** `maxTouchPoints > 1` to catch iPadOS masquerading as MacIntel) the primary CTA becomes "Orifold runs on macOS — send this page to your Mac" backed by `navigator.share` with copy-link fallback; the dmg link demotes to small text. The build-time (no-JS) state stays the dmg button, so desktop-no-JS remains correct.

---

## 4. Visual, a11y & performance rules

- **Tokens frozen.** `landing.css` (~300 lines): band layout, hero scale, window frame, nav. Zero raw color values (review-enforced); radii 10/8/5; transitions 120ms ease. No new fonts — system stack only. No new colors, no textures, no animation libraries.
- **One red:** `--of-tancho` only on the crane's crown. Fold motif expressed structurally (folded corners, creases, fold verbs in copy) — no origami clip-art.
- **Contrast rule:** gray-3 (`--of-text-3`) is **decorative-only** (hairlines, disabled states). All informational small text — chips, captions, hero note, footer meta — uses gray-2 (6.59:1 light / 10.43:1 dark). Light-mode gray-3 measures 3.54:1 = AA fail; this rule is why.
- **Semantics:** real alt text everywhere, `<figcaption>` captions, `<nav>` + skip-link, `:focus-visible` tokens kept, `aria-hidden="true"` on decorative glyphs.
- **Acceptance gate:** Lighthouse ≥95 performance & accessibility **in both themes**, plus a manual both-theme contrast pass.
- **Budgets (measured, binding):**
  - HTML+CSS+JS ≤ **120KB gzipped total, crane included** (crane sub-budget ≤25KB gz post-diet, else static mark).
  - Hero proof image ≤150KB served (AVIF/WebP 2×, preloaded, eager). Everything below §3.2 lazy-loads.
  - Below-fold capture trio through `<Picture>`: the current ~1.1MB of raw PNG must serve ≤250KB combined.
  - Complete JS inventory: `html.js` one-liner · theme-sync (~10 lines) · crane/pets freeze handler · fold-moment observer (~30 lines) · release-metadata + UA-gate enhancer (~1KB). **Total ≤4KB. Zero framework JS.**

### Animation spec — complete and closed (4 moments; nothing else moves)

| # | Moment | Mechanism | Reduced-motion |
|---|---|---|---|
| 1 | Hero load stagger (eyebrow→H1→sub→CTAs; 12px rise + fade, 400ms ease-out, 60ms stagger, once). Hero & proof shot **excluded from any scroll reveal** — they paint immediately (LCP-safe). | Pure CSS keyframes | `animation: none`, fully visible |
| 2 | Crane fold: plays **once**, freezes on the finished crane (`fill="freeze"`). | Inlined dieted SVG, SMIL | Static final-frame SVG swapped via media query (JS-free); reduced-motion users see the **finished crane**, never the flat sheet |
| 3 | §3.2 fold moment — the only scripted scroll animation on the page. | One IntersectionObserver, once; CSS transitions 600ms; hidden state gated behind `html.js` | Final state pre-applied |
| 4 | Button/card hover. | Existing 120ms token transitions | Kept (non-motion) |
| — | Gami/Ori figures | SMIL, finite (3 cycles → freeze) | Static variants |

**Banned:** blanket scroll reveals, parallax, marquee, count-up numbers, hover glows, nav micro-interactions, screenshot lifts, cursor followers, autoplay video, any animation library.

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
