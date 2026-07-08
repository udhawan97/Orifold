# Orifold macOS Download Experience — Implementation Plan & Spec

**Status:** Planning only. Not implemented.
**Date:** 2026-07-08 · **Baseline audited:** v0.8.2 (build 9) on main — the shipped Folding Studio landing (`docs-site/src/pages/index.astro`, 650 lines), `release.yml` (zip-only), `scripts/install-mac.sh` (sign/notarize/staple wiring exists, secrets-gated), `Casks/orifold.rb` (`version :latest`, `sha256 :no_check`), and `docs/WEBSITE_PLAN.md` §5–§8 (the accepted download-system architecture; this plan extends it, it does not replace it).
**Relationship to WEBSITE_PLAN.md:** §5 (asset convention, `make-dmg.sh`, atomic publish, fallback ladder), §6 (Gatekeeper facts), §7 (version truth), §8 (update phases) remain binding. This document adds: **universal binaries, versioned DMG filenames, the notarization enablement track, the CTA redesign to the user-specified spec, install-instructions UX, the analytics decision, and the full QA/launch checklists.** Where the two documents conflict, this one wins (conflicts are called out inline).

---

## 0. Current state vs. target — the honest delta

| Dimension | Today (audited) | Target |
|---|---|---|
| Artifact | `Orifold.zip` only | `Orifold-X.Y.Z-macOS-universal.dmg` (+ stable-name `Orifold.dmg` alias, + zip kept for installer/cask) |
| Architecture | arm64-only (`swift build`, native arch) | **Universal 2** — both `PDFium.xcframework` and `QPDF.xcframework` ship `macos-arm64_x86_64` slices (verified via `lipo -archs`: `x86_64 arm64`), so this is a build-flag change, not a dependency hunt |
| Signing | Ad-hoc (`ORIFOLD_SIGNING_IDENTITY: '-'`); Developer ID path fully coded in `install-mac.sh` + `release.yml` but secrets unset | Developer ID Application + hardened runtime + notarized + stapled (app **and** dmg) |
| Min macOS | **14 (Sonoma)** — `Package.swift` `platforms: [.macOS(.v14)]`, cask `depends_on macos: :sonoma` | Unchanged. ⚠️ The requested copy "macOS 12+" is **wrong for this app** — all user-facing copy says **macOS 14+** |
| Landing CTA | "Download for Mac" stacked button, href falls back to zip while `dmgMissing` | "Download for macOS" + icon + microcopy per §3 below |
| Trust line | "Not notarized yet — first launch takes one extra step." (true) | "Signed and notarized for macOS." — **gated on `site.json.signedBuilds`; may not ship a day earlier** |
| Analytics | Page ships "No analytics · No accounts · No uploads" as a trust stat | See §5.6 — client-side tracking conflicts with the shipped brand promise; default is server-side GitHub download counts |

**Three decision points for Umang (defaults chosen, all reversible):**

1. **Universal vs Apple-Silicon-only.** Default: **ship universal.** Deps are ready; Intel Macs (2019–2020) run Sonoma. Cost: ~2× binary size for the app executable (frameworks are already fat), one Rosetta QA pass. Fallback if the fat build misbehaves: stay arm64-only and the filename/copy drop "universal"/"Intel".
2. **Analytics.** Default: **no client-side event tracking** (keeps "No analytics" true); measure downloads via the GitHub Releases API `download_count` (per-asset, exact, zero JS). The requested `download_macos_clicked` event is fully specced in §5.6 and can be wired to a cookieless provider later behind one flag.
3. **Apple Developer Program enrollment ($99/yr).** Required for the "Signed and notarized" trust line and for silencing Gatekeeper. Everything else in this plan ships without it; the notarization track (§5.4) starts the day the membership exists.

---

## 1. Product plan

**Goal.** A visitor on the Orifold landing page clicks one obvious button, gets a versioned universal DMG, opens it, drags Orifold to Applications, and launches it — with zero scary dialogs (notarized era) or one honestly-coached dialog (interim). The browser never "silently installs" anything; the flow is the standard macOS DMG ritual, made premium.

**Phasing (4 PRs + 1 ops track):**

| Phase | Ships | Depends on |
|---|---|---|
| **PR-1 — DMG pipeline** | `scripts/make-dmg.sh` (universal build, branded DMG, checksum), `release.yml` atomic publish of versioned dmg + stable alias + zip + manifest, cask version/sha pin, docs-site rebuild dispatch | nothing |
| **PR-2 — CTA & install UX** | Button rename + icon + microcopy + file-details line, "Starting download…" feedback, "Install Orifold on macOS" 3-step section, "Need another version?" fallback block, `release.ts` versioned-asset support | PR-1 merged (so the button has a real dmg by the time copy says ".dmg") |
| **OPS — Apple Developer enrollment** | ADP membership, Developer ID Application cert, 5 GitHub secrets (`release.yml` already consumes them by name) | Umang |
| **PR-3 — Notarization enablement** | `sign_staged_app` inside-out rewrite (nested frameworks first, hardened runtime, no `--deep` signing), dmg signing+stapling in `make-dmg.sh`, one real dry run, flip `site.json.signedBuilds`, trust-line copy + collapsed coaching card, cask `caveats`/`postflight` cleanup | OPS |
| **PR-4 — QA + launch** | Full §7 test matrix on clean machines, §8 launch checklist, throwaway-tag end-to-end rehearsal | PR-1..3 |

PR-1 and PR-2 deliver a complete, honest, unsigned-era experience. PR-3 flips it to the fully trusted flow without touching layout — every signed-era string is pre-written behind `site.json.signedBuilds` (pattern already established in WEBSITE_PLAN §3.7).

**Success metrics** (from GitHub API, no client JS): dmg `download_count` per release; ratio of dmg vs zip downloads (validates the DMG flow); GitHub issue rate mentioning "damaged"/"can't open" (Gatekeeper friction signal — should drop to ~0 post-notarization).

---

## 2. UX/UI design spec

All visual work happens inside the shipped Folding Studio design system: tokens only (`tokens.css` + the `--of-paper` family), zero raw colors in `landing.css`, transform/opacity-only animation, `crease-reveal` as the only entrance grammar. No new fonts, no animation libraries.

### 2.1 Hero (Fold 0) — CTA cluster

Desktop (two-column hero, unchanged grid):

```
[icon] Download for macOS          ← .btn-main, 1rem/650
       Apple Silicon + Intel       ← .btn-sub, 0.72rem
—————————————————————————————
macOS 14+ · Universal DMG · v0.8.3 · 15 MB    ← file-details line, gray-2, tabular-nums
View install instructions →                    ← secondary link → #install
Signed and notarized for macOS.                ← trust line (signedBuilds era)
```

- The CTA stays aligned with the H1 block (existing `.btn-row` position); the file-details line replaces the current meta chips' version/date row content (version + released-date chips remain, per shipped layout).
- **Trust line gating:** `signedBuilds: true` → "Signed and notarized for macOS." (gray-2, same size as the inoculation line it replaces). `false` → keep the shipped honest line "Not notarized yet — first launch takes one extra step. Here's how →". Never both.
- "View install instructions" anchors to `#install` (§2.3). Instant jump (`scroll-behavior` never smooth — shipped rule).

Mobile (≤720px): button full-width, icon left, text block centered in remaining space, file details wrap beneath the button, trust line below that. The shipped non-Mac UA gate stands: non-macOS visitors get "View on GitHub" primary + "Send this page to your Mac", and the dmg link demotes to small text with the new note **"For macOS only."**

### 2.2 Final fold (download band)

Same button spec as hero (`#cta-final`). Around it, in order:

1. Button + file-details line (identical component, one Astro partial — build once, render twice).
2. **Architecture line replaces the shipped M-series-only paragraph:** "One download works for Apple Silicon and Intel Macs." (the requested universal clarity line — replaces "Intel Macs aren't supported yet" and its issue link).
3. Install steps (§2.3) — replaces the current position of the coaching card; the Gatekeeper coaching card becomes step 3's note (unsigned era) or collapses to one line (signed era).
4. SHA-256 verify block (shipped `chip-cmd` pattern): `shasum -a 256 ~/Downloads/Orifold-0.8.3-macOS-universal.dmg` + copy button; expected hash baked at build from the `.sha256` release asset.
5. **"Need another version?"** — `.details` collapsed block (replaces "Other ways to install", absorbing its contents):
   - Universal DMG (the same primary link, restated)
   - Direct .zip (for the installer/cask path)
   - Homebrew chip `brew install --cask orifold`
   - Release notes → `/releases/` docs page · All releases → GitHub
   - Support link: **"Having trouble installing?"** → `help/troubleshooting` docs anchor for Gatekeeper/quarantine issues.

### 2.3 "Install Orifold on macOS" — 3-step section (`#install`)

New compact band inside the final fold (not a modal — modals fight the one-sheet scroll narrative and break no-JS). Three numbered paper tiles (reuse the V2 step-tile pattern: 40px cream `--of-paper` tile, fold-shade edge, plain numerals):

1. **Open the downloaded `Orifold-[VERSION]-macOS-universal.dmg`.** — "It mounts like a tiny disk."
2. **Drag Orifold into the Applications folder.** — "The window shows you exactly where."
3. **Open Orifold from Applications.** — "Eject the disk image after; you don't need it again."

Note beneath (signed era): *"If macOS asks for confirmation, choose Open. Orifold appears as a signed and notarized app."*
Note beneath (unsigned era): the shipped per-OS coaching card verbatim (macOS 14 right-click→Open; macOS 15 Settings → Privacy & Security → Open Anyway), introduced by Gami's existing bubble.

Small static illustration allowed: a stylized DMG-window vignette (cream sheet + app tile + arrow + folder glyph, illustration register, "Illustration" caption) — 0 bytes of media, DOM+CSS only, consistent with V1–V4. No animation beyond `crease-reveal`.

### 2.4 States (both CTA instances)

| State | Treatment |
|---|---|
| Default | Dark premium fill (§3), icon + two-line label |
| Hover | `translateY(-1px)` + pre-rendered shadow opacity crossfade (shipped `card-lift` rules apply — no box-shadow animation) |
| Pressed (`:active`) | `translateY(0)` + `filter: brightness(0.92)` |
| Focus | `:focus-visible` ring: 2px `var(--of-accent)` offset 3px (existing token treatment) |
| Downloading | Sub-label swaps to **"Starting download…"** for 4s (JS click handler; `aria-live="polite"` via the existing `role="status"` node) |
| Post-click helper | After the 4s window, a small line fades in under the file details: **"Download didn't start? [Try again](same href) or [get it from GitHub](releaseUrl)."** — persists for the session |
| Degraded (no dmg on latest release) | Shipped `dmgMissing` ladder unchanged: button falls back to zip with `.zip` label; enhancer confirm-or-upgrade only |
| Non-Mac UA | Shipped gate + "For macOS only." note |
| Reduced motion / no-JS | Button is a plain `<a href>` — download works with zero JS; the feedback states are additive |

---

## 3. Button copy and visual spec

### 3.1 Copy (final, verbatim)

- Primary: **Download for macOS** *(rename from the shipped "Download for Mac" — one string, two instances + the View-menu of copy greps)*
- Sub-label: **Apple Silicon + Intel**
- File details: **macOS 14+ · Universal DMG · v{version} · {size}** — every value from `release.ts`, never hardcoded (shipped rule); `min-width` in `ch` + `tabular-nums` so enhancer upgrades can't shift layout. ⚠️ Not "macOS 12+" — the app requires 14.
- Secondary link: **View install instructions**
- Trust line: **Signed and notarized for macOS.** *(signedBuilds-gated, §2.1)*

### 3.2 Icon — decision + spec

**Do not use the Apple logo ().** Apple's *Guidelines for Using Apple Trademarks* restrict the logo to licensed contexts (App Store badges, MFi); a web download button does not qualify. **SF Symbols are also out for web use** — the SF license permits use only in apps for Apple platforms, not as exported web assets. Both flagged as legal blockers; neither is needed.

**Chosen icon: a hand-drawn "arrow into tray" download glyph** (the universal desktop-download symbol), drawn in the Folding Studio line style:

- Inline SVG, 20×20 viewBox, `stroke: currentColor`, `stroke-width: 1.8`, round caps — a down arrow descending into an open tray/dock line, with the tray's left corner given the page's dog-ear fold token (one 45° notch) so it reads as *Orifold's* download glyph, not clipart.
- `aria-hidden="true"` (button text carries the semantics), ~0.4KB raw, sits left of the two-line label with `0.65rem` gap, optically aligned to the `.btn-main` cap height.
- Alternative considered and rejected: the crane mark (already does hero/footer duty; a download affordance should say "download," not "brand").

### 3.3 Visual (tokens of the shipped system)

- Container: `display: inline-flex; align-items: center; gap: 0.65rem; padding: 0.72rem 1.35rem; border-radius: 10px` (radius token L).
- Fill: keep `var(--of-accent)` text-on-`var(--of-canvas)` inversion in dark theme (the shipped premium-dark treatment); light theme unchanged from shipped `.btn-primary`. **No new colors.** If a darker "SaaS-black" reads better in light theme, the sanctioned route is `color-mix(in srgb, var(--of-text-1) 92%, var(--of-canvas))` — still zero raw values.
- Shadow: resting `0 1px 2px` + hover-deepen via pre-rendered pseudo-element (shipped `card-lift` rule).
- Two-line label: `.btn-main` 1rem/weight 650; `.btn-sub` 0.72rem/500/85% opacity, `min-width: 18ch` (shipped).
- Contrast gates: button text ≥4.5:1 on fill in both themes; focus ring ≥3:1 against adjacent colors. Added as named rows to the manual contrast pass (WEBSITE_PLAN §4.1).

---

## 4. Download/install user flow

```
Visitor (macOS, Safari/Chrome/Arc)
  │ 1. Clicks "Download for macOS"          ← plain <a href>, works no-JS
  │      href = versioned asset URL baked at build
  │      sub-label → "Starting download…" (4s), then helper line arms
  │ 2. Browser saves Orifold-0.8.3-macOS-universal.dmg  (~15 MB, seconds)
  │ 3. Opens the .dmg → window shows Orifold.app, an arrow, /Applications alias
  │      (branded background: canvas-dark washi + fold-arrow; layout via committed .DS_Store)
  │ 4. Drags Orifold.app → Applications
  │ 5. Ejects the image, launches Orifold from Applications / Spotlight
  │ 6a. Signed era: Gatekeeper one-time "downloaded from the internet — Open?" → Open. Done.
  │ 6b. Unsigned era: per-OS coached path (14: right-click→Open · 15: Open Anyway) — card in step 3's note
  └─ Failure branches:
       download blocked → helper line: "Try again / get it from GitHub"
       latest release missing dmg → build/enhancer ladder serves zip + note (shipped)
       "damaged / can't be opened" → troubleshooting doc (quarantine + ad-hoc explainer, `xattr` stays doc-only)
       Intel Mac on macOS ≤13 → app won't launch; About-This-Mac + macOS 14 requirement in troubleshooting
```

The browser never auto-installs; no `Launch Services` tricks, no pkg. The DMG *is* the product handshake — its interior is the one screen we fully control, so it must look designed (§6).

---

## 5. Engineering checklist

### 5.1 Universal build (`scripts/install-mac.sh`)

- [ ] `swift build -c release --arch arm64 --arch x86_64` behind a new `ORIFOLD_UNIVERSAL=1` env (default on in CI release path; local dev builds stay native-arch for speed).
- [ ] Post-build assert: `lipo -archs` on the app executable == `x86_64 arm64`; fail loudly otherwise.
- [ ] Verify SwiftPM emits the fat binary path correctly (`--show-bin-path` changes to `apple/Products/Release` for multi-arch — the `built_binary=` line at `scripts/install-mac.sh:447` must handle both layouts).
- [ ] Frameworks: PDFium + QPDF slices are already fat (verified) — `ditto` them as today; no lipo work.
- [ ] Remove the `uname -m` arm64-refusal guard from the prebuilt path once universal ships (WEBSITE_PLAN §5.3 added it; universal obsoletes it); cask drops any `depends_on arch:` plan.

### 5.2 `scripts/make-dmg.sh` (per WEBSITE_PLAN §5.2, plus deltas)

Everything in §5.2 stands (hdiutil UDZO, committed `.DS_Store`, no AppleScript, 3-attempt retry). Deltas:

- [ ] Output name: `Orifold-${VERSION}-macOS-universal.dmg` (version from the tag, CI-enforced).
- [ ] Also emit `${name}.sha256` (`shasum -a 256`, filename-relative format so `shasum -c` works).
- [ ] Volume name: `Orifold ${VERSION}`; volume icon: app icon as `.VolumeIcon.icns`.
- [ ] Internet-enable is obsolete (deprecated by Apple) — skip.
- [ ] Signed era: `codesign --sign "Developer ID Application: …" --timestamp` the dmg → `notarytool submit` → `stapler staple` the dmg (the app inside is already stapled first — order per WEBSITE_PLAN §5.2). Ad-hoc era: skip gracefully (same conditional pattern as `install-mac.sh`).

### 5.3 `release.yml` (extends WEBSITE_PLAN §5.3)

- [ ] Tag-derived version (PlistBuddy override of the copied Info.plist — §5.3.1 verbatim; the committed plist already says 0.8.2/9, CI must still override from tag).
- [ ] Tagged path uploads **four assets, atomically (draft → upload all → publish+latest):**
  1. `Orifold-X.Y.Z-macOS-universal.dmg` — canonical, what the CTA links and browsers save
  2. `Orifold.dmg` — byte-identical copy, stable name, so `releases/latest/download/Orifold.dmg` never breaks (fallback ladder, docs deep-links, LAST_KNOWN_GOOD path)
  3. `Orifold-X.Y.Z-macOS-universal.dmg.sha256`
  4. `Orifold.zip` — unchanged (installer, cask, `.command` helpers)
- [ ] `manifest.json` uploaded as a fifth asset: `{ version, build, releaseDate, minMacOS: "14", arch: "universal2", files: [{name, size, sha256, url}] }` — the requested releases manifest; later doubles as the Sparkle-adjacent metadata source (WEBSITE_PLAN §8 Phase 2 unchanged).
- [ ] Cask pin step (§5.3.4 verbatim: real `version`, real `sha256`, versioned URL) — kills `version :latest, sha256 :no_check`.
- [ ] `gh workflow run docs.yml --ref main` dispatch after publish (§5.3.5 verbatim — not `workflow_run`).
- [ ] Rolling `Orifold-latest`: gains `prerelease: true`; builds the dmg too (canary — §5.3 rationale stands).
- [ ] `paths-ignore: [docs-site/**, docs/**]` on the main-push trigger (§5.3 carry-over; still unimplemented).

### 5.4 Signing & notarization (PR-3 / OPS)

- [ ] Enroll Apple Developer Program; create **Developer ID Application** certificate; export `.p12`.
- [ ] Set the five secrets `release.yml` **already consumes by name**: `ORIFOLD_DEVELOPER_ID_CERTIFICATE_BASE64`, `ORIFOLD_DEVELOPER_ID_CERTIFICATE_PASSWORD`, `ORIFOLD_SIGNING_IDENTITY`, `ORIFOLD_APPLE_ID`, `ORIFOLD_APPLE_TEAM_ID`, `ORIFOLD_APPLE_APP_SPECIFIC_PASSWORD` (keychain-import and notarytool steps are already written — audited lines 53–79 of `release.yml`, 220–249 of `install-mac.sh`).
- [ ] **Rewrite `sign_staged_app` inside-out** (WEBSITE_PLAN §6 pre-flip work item, still open): sign nested `PDFium.framework`/`QPDF.framework` and any nested executables first (no entitlements on them), then the app with entitlements + `--options runtime` (hardened runtime) + `--timestamp`; drop any `--deep` from *signing* (verify-only `--deep` is fine).
- [ ] Hardened-runtime exception audit: app is sandboxed with narrow entitlements; confirm no JIT/dylib-env exceptions needed (pure Swift + prebuilt frameworks — none expected).
- [ ] Dry run before flipping any copy: notarize app → staple app → build dmg → sign dmg → notarize dmg → staple dmg → `spctl -a -t open --context context:primary-signature` on the dmg + `spctl -a -vv` on the app → fresh-VM download test.
- [ ] Flip `site.json.signedBuilds: true` (new key) — collapses the coaching card, arms the trust line, and simplifies the cask (`caveats` + `xattr` postflight removed in the same PR).
- [ ] Update `Uninstall/Install .command` helpers and one-line installer copy that mention ad-hoc signing.

### 5.5 Site (`docs-site/`) — PR-2

- [ ] `release.ts`: match dmg asset by pattern `^Orifold-\d+\.\d+\.\d+-macOS-universal\.dmg$` (prefer versioned; fall back to stable `Orifold.dmg` name), expose `dmgVersionedUrl`, `sha256` (fetch the `.sha256` asset body at build), and bump `LAST_KNOWN_GOOD` (currently stale at 0.8.1).
- [ ] Button partial: rename label, add icon SVG, sub-label "Apple Silicon + Intel", file-details line, trust-line gating, `#install` section, "Need another version?" block, "Starting download…" + helper-line handler (≤0.4KB added to the inline IIFE — budget per WEBSITE_PLAN §4.8 still holds).
- [ ] `site.json`: `arch: "Universal"`, add `signedBuilds: false`.
- [ ] Update `get-started/install.mdx` docs for the DMG-first flow (installer/brew demoted to alternatives), and `help/troubleshooting` gains the "Download didn't start" + "damaged app" entries.
- [ ] README download section: dmg-first, versioned badge already planned (WEBSITE_PLAN §7).
- [ ] Enhancer: no change to the state machine; it must recognize the versioned asset pattern (same regex, shared via a `data-` attribute).

### 5.6 Analytics — conflict called out, both paths specced

**Conflict:** the shipped landing's Fold 4 stat row says **"0 — telemetry, analytics, accounts"** about the app, and the page itself promises "This page asks GitHub for the latest version number… The app never does." Client-side click tracking on the page would not break the *app's* promise but visibly erodes the *brand's*. 

**Default (recommended): zero client JS.**
- Metric source: `GET /repos/udhawan97/Orifold/releases` → per-asset `download_count`, snapshotted weekly by a tiny scheduled workflow into `docs/metrics/downloads.csv` (append-only). Exact, free, retroactive, invisible.
- This measures *completed downloads* (better than clicks) per asset per version — dmg vs zip vs brew-driven zip is directly readable.

**If click-level analytics is later wanted** (one flag: `site.json.analytics: "plausible" | null`), the event is pre-specced exactly as requested:
- Provider must be cookieless + IP-anonymizing (self-hosted Plausible or GoatCounter); disclose in the page footer ("Cookieless page analytics; the app has none.") — the Fold-4 honesty clause must be amended in the same PR, or this ships never.
- Event: `download_macos_clicked` · props: `{ platform: "macOS", version: rel.version, source_section: "hero" | "final_fold" }` — fired from the existing click handler, fire-and-forget, never blocking navigation.

### 5.7 Hosting, MIME, caching — facts, not wishes

- Host: **GitHub Releases** (HTTPS, Fastly-backed CDN, free, already the release home). No new infra.
- **MIME:** GitHub serves release assets as `application/octet-stream`, and this cannot be configured. Every macOS browser downloads `.dmg` correctly on extension + `Content-Disposition`; Safari/Chrome/Arc verified in QA (§7). The literal `application/x-apple-diskimage` requirement is achievable only by fronting with our own CDN (Cloudflare R2) — **not needed; requirement satisfied by behavior, flagged here as a conscious deviation.**
- **Caching/staleness:** versioned filenames make stale downloads structurally impossible (each release = new URL). The stable `Orifold.dmg` URL is a 302 through `releases/latest/download/…`, re-resolved per request — no long-lived cache to poison. The known trap (WEBSITE_PLAN §5.1, re-affirmed): the first hop 302s even for missing assets; all smoke tests must follow the chain to a final 200.

---

## 6. DMG packaging checklist

- [ ] Contents: `Orifold.app` (signed→notarized→stapled first) + `/Applications` symlink. Nothing else visible.
- [ ] Window: ~600×400, icon view, 104px icons; app at left-third, Applications alias at right-third; toolbar/sidebar/statusbar hidden; layout via **committed `scripts/assets/dmg-layout.DS_Store`** (generated once locally in Finder, `ditto`'d into staging — deterministic, no CI AppleScript).
- [ ] Background: `scripts/assets/dmg-background@2x.png` — canvas-dark washi texture, one crease hairline, a fold-styled arrow from app to folder. **No text baked into pixels** beyond the arrow (no OS instructions — they age; WEBSITE_PLAN §5.2 rule) except optionally the wordmark. Provide 1x+2x (`.background` folder, `dmg-background.tiff` combining both via `tiffutil -cathidpicheck`).
- [ ] Volume name `Orifold X.Y.Z`; `.VolumeIcon.icns` set (`SetFile -a C` on the mount / `fileicon` equivalent).
- [ ] Format: UDZO (zlib) — default compression is fine at ~15MB; UDBZ only if it saves >15%.
- [ ] `hdiutil create`/`attach`/`detach` wrapped in 3-attempt retry with detach+cleanup between attempts (CI "Resource busy" mitigation).
- [ ] Signed era: dmg codesigned (Developer ID, `--timestamp`) + notarized + stapled; `spctl -a -t open --context context:primary-signature` passes.
- [ ] `shasum -a 256` sidecar emitted; value also lands in `manifest.json` and the site verify block.
- [ ] Local verification target: `zsh scripts/make-dmg.sh --verify` mounts the image, asserts app signature (`codesign --verify --deep --strict`), asserts symlink, unmounts.

---

## 7. QA test plan

**Machines:** Apple Silicon (primary dev machine + one clean macOS 15 VM), Intel or Rosetta (`arch -x86_64` for the x86_64 slice; a real Intel Mac on macOS 14 if reachable — flag as best-effort), fresh user account on each (Gatekeeper state is per-user).

**Download UX (per browser: Safari, Chrome, Arc):**
- [ ] Click hero CTA → download begins immediately; saved filename is `Orifold-X.Y.Z-macOS-universal.dmg`.
- [ ] "Starting download…" appears and reverts; helper line appears after 4s and links work.
- [ ] Final-fold CTA identical. No-JS (Safari develop-menu off): plain link still downloads.
- [ ] Non-Mac UA (iPhone + Windows UA spoof): GitHub CTA + "For macOS only." note; no dmg button flash (synchronous gate).
- [ ] `dmgMissing` simulation (point `site.json` repo at a zip-only release in a test build): button degrades to zip with correct labels.

**Install flow:**
- [ ] Open dmg → branded window renders (background, layout, icon positions survive UDZO + fresh mount on a clean machine — `.DS_Store` regressions are the classic failure).
- [ ] Drag to `/Applications`, eject, launch from Applications and Spotlight.
- [ ] **Quarantine preserved:** verify `com.apple.quarantine` xattr present post-download (`xattr -p`), then: signed-era → single "Open?" dialog, opens clean, `spctl -a -vv` = accepted, notarized; unsigned-era → per-OS coached path works exactly as the card says on macOS 14 **and** 15 (re-run the WEBSITE_PLAN §2.2 machine test on the *dmg* artifact — prior test was zip).
- [ ] Clean install (no prior Orifold) and upgrade install (drag-replace over existing `/Applications/Orifold.app` while old version present; settings/recent-docs survive; running-app case shows Finder's "in use" correctly).
- [ ] Install-location reconciliation: existing `~/Applications` installer-era copy + new `/Applications` dmg copy — confirm the app's own update path (WEBSITE_PLAN §8b) and the installer's in-place-replace behave; no dual-Dock-icon confusion in docs.
- [ ] Universal: `lipo -archs` on shipped binary = both; launch under Rosetta (`arch -x86_64 /Applications/Orifold.app/Contents/MacOS/Orifold`) — app boots, opens a PDF, exports (PDFium/QPDF x86_64 slices actually exercised).
- [ ] First-launch experience after drag: onboarding/empty-state renders, no sandbox permission surprises.

**Release plumbing:**
- [ ] Throwaway tag end-to-end (WEBSITE_PLAN §5.4 acceptance test, extended): tag → release publishes with all 5 assets atomically → cask pinned → docs.yml auto-runs → live page shows new version + versioned href → stable URL redirect chain ends 200 → `shasum -c` passes against the sidecar → delete tag/release.
- [ ] Site: Lighthouse ≥95 perf+a11y both themes (existing gate); keyboard-only pass over CTA → install steps → details blocks; VoiceOver reads button as "Download for macOS, Apple Silicon + Intel, link".

---

## 8. Launch checklist

1. [ ] PR-1 merged; `Orifold-latest` canary has built dmg green ≥3 consecutive pushes.
2. [ ] PR-2 merged behind reality: copy shows zip-era truthfully until first dmg release tags.
3. [ ] Tag `v0.8.3` (or next) — first dmg release; verify §7 plumbing checklist live.
4. [ ] Docs (`install.mdx`, `troubleshooting`, README) flipped dmg-first in the same release window.
5. [ ] OPS: ADP enrolled → secrets set → PR-3 dry run on a throwaway tag → real signed release → **only then** flip `signedBuilds` + trust line + cask cleanup.
6. [ ] Post-launch watch (first 48h): GitHub issues for "damaged/can't open"; download counts snapshot job running; docs smoke step green.
7. [ ] Update `docs/WEBSITE_PLAN.md` cross-references (§5 "extended by MACOS_DOWNLOAD_EXPERIENCE_PLAN") and memory/release notes.

---

## 9. Risks and mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| **Apple logo / SF Symbols in the button** | — | Pre-empted: neutral custom glyph specced (§3.2); both Apple assets flagged as license violations for web use. Revisit only with legal review. |
| **"Signed and notarized" copy ships before it's true** | Medium (copy is written, temptation exists) | Hard gate on `site.json.signedBuilds`; PR-2 review checklist item; the flag flips only in PR-3 after the spctl-verified dry run. |
| **Universal build breaks x86_64 at runtime** (untested slice) | Medium | Rosetta QA gate (§7); PDFium/QPDF slices verified fat; fallback pre-decided: ship arm64-only, drop "Intel/Universal" strings (they're all `release.ts`/`site.json`-driven, one-file change). |
| **Analytics quietly added later, contradicting Fold 4** | Low | §5.6 makes the amendment rule explicit: provider + footer disclosure + stat-row copy change in one PR, or never. |
| **DMG layout regressions on CI** (`.DS_Store` fragility, hdiutil "Resource busy") | Medium | Committed `.DS_Store` (no Finder scripting), 3-retry wrapper, canary dmg on every push so release day is never the first run, `--verify` target in QA. |
| **Stale downloads / publish-window 404** | Low | Versioned filenames + atomic draft-publish (WEBSITE_PLAN §5.3) + redirect-chain smoke test. |
| **macOS 15.x "damaged" dead-end on unsigned dmg** | Known real | §2.2-style machine test re-run on the dmg before PR-2 copy freezes; coaching card leads with installer path if observed; notarization (PR-3) is the actual fix. |
| **GitHub MIME type ≠ `application/x-apple-diskimage`** | Certain | Accepted deviation (§5.7): behavior verified per-browser in QA; own-CDN escape hatch documented if ever needed. |
| **Cask pin commit races concurrent sessions** (shared repo, frequent branch flips) | Medium | `git pull --rebase` ×3 retry around the cask commit (WEBSITE_PLAN §5.3.4); cask change is one self-contained file. |
| **Notarization dry run surfaces hardened-runtime breakage** (PDFium JIT-less assumption wrong) | Low | Dry run happens on a throwaway tag before any public copy changes; entitlement exceptions documented if needed. |

---

## 10. Final acceptance criteria

- [ ] Landing hero + final fold show **"Download for macOS"** with the custom download glyph, "Apple Silicon + Intel" sub-label, and the file-details line `macOS 14+ · Universal DMG · v{X.Y.Z} · {size}` — all values baked from release metadata, correct with JS disabled.
- [ ] Clicking the CTA immediately downloads `Orifold-{X.Y.Z}-macOS-universal.dmg` over HTTPS from GitHub Releases; `https://github.com/udhawan97/Orifold/releases/latest/download/Orifold.dmg` resolves to the same bytes.
- [ ] The DMG opens to a branded drag-to-Applications window; the drag→launch flow verified on clean macOS 14 and 15 accounts, Apple Silicon and x86_64 (Rosetta minimum).
- [ ] Button has hover, pressed, focus-visible, downloading, failure-helper, degraded (zip), and non-Mac states; desktop/tablet/mobile responsive per §2; WCAG contrast rows pass both themes.
- [ ] "Install Orifold on macOS" 3-step section live and anchor-linked from the hero; unsigned-era Gatekeeper coaching accurate per real-machine test; "Having trouble installing?" support link present.
- [ ] "Need another version?" block present with universal-clarity line, zip, brew, release notes, all-releases links.
- [ ] Download measurement running (GitHub `download_count` snapshots); the `download_macos_clicked` client event ships **only** with a cookieless provider + on-page disclosure + Fold-4 copy amendment (§5.6), else not at all.
- [ ] Release pipeline: tag → universal build → sign (→ notarize+staple when secrets exist) → dmg + sha256 + manifest + stable alias + zip, published atomically → cask pinned → site rebuilt, hands-off; throwaway-tag rehearsal documented as passed.
- [ ] Apple trademark risk resolved: no  logo, no SF Symbols on the web; noted in this doc and the PR description.
- [ ] "Signed and notarized for macOS." renders **iff** `signedBuilds: true`, which flips only after the spctl-verified signed dry run — the page can never claim trust it doesn't have.
