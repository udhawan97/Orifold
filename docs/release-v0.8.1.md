# v0.8.1 Orifold

## GitHub Release Fields

Tag: `release-v0.8.1`

Target: latest commit tagged by `release-v0.8.1`

Release title: `v0.8.1 Orifold`

Asset to upload: `Orifold.zip`

Automation: `.github/workflows/release.yml` builds and publishes automatically on push of any `release-v*` tag, and marks the tagged release as GitHub's "latest" (`make_latest: true`). The `Orifold-latest` rolling release (built on every `main` push) never claims "latest" itself, so the one-line installer always resolves to whichever is actually newest. The previous `sync-release-v7.yml` workflow — which force-moved the `release-v7` tag to `main` every 30 minutes — has been removed; tags are immutable again from this release forward.

Build the asset with:

```zsh
./scripts/install-mac.sh --package-only --package /tmp/Orifold.zip
```

## Release Notes

# v0.8.1 Orifold

**Release:** Latest release
**Tag:** [`release-v0.8.1`](https://github.com/udhawan97/Orifold/releases/tag/release-v0.8.1)

---

## Why v0.8.1 After v7?

Orifold is adopting semantic versioning. The v1–v7 line was seven sequential build releases; `v0.8.1` says plainly where the project actually stands — a polished beta, actively validated and hardened on the way to 1.0. Nothing was removed and no numbering games were played; the version scheme just grew up alongside the app. Orifold remains in beta, and that beta status is now stated up front rather than implied.

---

## What Changed Since v7

v0.8.1 is a hardening and documentation release: no headline feature, dozens of fixes that make the v7 feature set (the qpdf engine, signing, companions, localization) trustworthy under real use, plus a full documentation overhaul.

### Signing

- Async signing with a real progress indicator and a cancel button that actually interrupts — including a fix for cancel not stopping a hung TSA (timestamp authority) request.
- A TSA provider fallback chain, with a provider picker and typed-signature font choice wired into the signing palette.
- Certificate trust and revocation checking (on-demand, via `SecTrust`) surfaced in Manage Certificates.
- Persistent certificate profiles and a 4-mode signature palette (draw, type, image, certificate-backed).
- xref-stream detection with a post-export structural self-check, so a malformed export is caught before it reaches disk rather than after.
- Five rounds of internal review fixes across the signing subsystem (stale progress text, hidden TSA retries, lost font selections, and more).

### Toolbar, Sidebar, and Editing

- Toolbar redesign across four phases: consolidation, Find & Replace, a responsive capsule layout, and Settings moved from an inline panel into its own window.
- Sidebar redesign ("Tatami Rail"): undo grouping, performance, and visual polish.
- Redesigned drag handles for editable PDF text boxes.
- Keyboard shortcuts overhauled to match macOS conventions, with a new cheat sheet and in-app discovery.
- Fixed Replace All overcounting a match when the replacement would empty a comment.
- Folder import added to the intro screen and the Add Files menu, alongside two rounds of review fixes for folder-import edge cases.
- Fixed import/reopen permission errors with classified recovery UX, and dropped dead code from the import hardening pass.

### Text Editing and Redaction Safety

- Preserve original PDF bytes on import so previously-edited text stays editable.
- Extract real rotation/transform/stroke data instead of conflating page and text rotation.
- Classify invisible or low-visibility text (the common OCR-layer-under-a-scan pattern) instead of treating it as ordinary text, and fixed a bug where that invisible-text drawing mode could leak forward and silently make unrelated replacements on the same page render invisible too.
- Orifold now warns, once, that inline text edits are not true redaction — the original content isn't cryptographically removed from the file.
- Fixed a Format Painter geometry bug and general toolbar polish.
- Added a stress-test PDF fixture and analysis test coverage for the inline-edit pipeline.

### Reading and Comfort

- Night Mode and the standalone brightness slider were replaced by a single **Document Comfort** popover: four reading presets (Default, Night, Eye Care, Focus), Warm Tone/Page Brightness/Text Contrast sliders, and dedicated Eye Care toggles (Reduce Glare, Soften White Pages, Reduce Animations) under a "Fine-tune" disclosure.
- Reader Mode remains an independent, one-tap toolbar toggle for a distraction-free view.

### Companions and Localization

- Gami redesigned as an origami Bernedoodle; Ori redesigned as her own character — an origami Siberian with a distinct curious, clever, quietly-in-charge personality — each with a lighter hint bubble that stays clear of the document and a **Hide Tips** toggle.
- Both companions are bigger and more detailed (three rounds of SVG refinement for structure, texture, and character), and now show off at full size for a few seconds on first launch before settling into their corner — hover anytime to see that detail again. Reduce Motion skips the showcase.
- Fixed first-use tips being silently swallowed by the hint-bubble throttle.
- Two rounds of bug-audit fixes for locale staleness across the companions, toolbar status messages, and popovers.
- Fixed a language-selector bug where a click-blocking z-order issue, stale translations, and a popover locale reset could all mask each other.
- Fixed menu bar commands not updating immediately when the app language changes.
- Localized hardcoded toolbar status/tooltip strings that had been slipping through in English regardless of locale.

### Bug Fixes

- Fixed a hero-logo rendering bug (an inlined SVG replaces an `<object>` embed that could render as a white box).
- Fixed the pet mascot's speech bubble overlapping an enlarged pet on hover.
- Improved long-filename readability in sidebar cards and rows.
- Fixed several broken/missing Xcode project file references surfaced by merges.
- Fixed silent error-message and exception-handling gaps across signing and import, with new regression tests covering both flows.

---

## Engineering

- Added a lean CI quality gate: SwiftLint plus a headless PDF processing smoke test, running on every PR.
- Test suite grew from 354 to **503** tests (0 failures, 9 intentionally skipped, verified on this release).
- Source grew from 61 to 79 Swift files (~29,000 → ~36,000 lines), primarily from the signature experience, sidebar redesign, folder import, inline-edit export hardening, and the new documentation site.

---

## Documentation

- Built a full documentation site (`docs-site/`, Astro/Starlight) covering get-started, import, edit, annotate, fill & sign, export, reading, settings, developer, and release-notes pages — with in-app links to it from the Help menu and Quick Guide.
- Replaced 6 of the documentation's illustrated SVG placeholders with real screenshots of the running app (empty state, main window, annotation markup, Document Comfort, Reader Mode, language switcher); the remaining 8 GIF/screenshot slots stay as hand-illustrated, app-faithful SVGs pending capture (tracked in `docs/assets/MEDIA_MANIFEST.md`).
- Rewrote the reading-comfort docs pages to match the shipped Document Comfort UI (they previously described an earlier, since-replaced preset scheme).
- Corrected several design/plan documents (`docs/features/`, `docs/signing/`, `docs/DOCS_SITE_PLAN.md`) that still read "plan only, not implemented" for features that have since shipped.
- README refreshed: version badge, a beta-status note explaining the v7 → v0.8.1 jump, and regenerated test/file/line counts.

---

## Known Limitations

- Automated end-to-end UI smoke testing (beyond the headless PDF smoke test added this cycle) remains on the roadmap.
- The `ci.yml` full test-suite job is currently red on its pinned Xcode 16.4 toolchain: 3 of 503 tests fail, all at `PDFPage.string` (PDFKit text-extraction) assertions on pages built via `CGContext.drawPDFPage`, while the corresponding visual/save assertions in the same tests pass. This does not affect this release's build (`release.yml` doesn't run the suite) and is tracked as a follow-up rather than fixed blind without an Xcode 16.4 environment to verify against.

---

## Upgrade Notes

Existing installs update automatically via the **Orifold.command** Desktop launcher. New installs use the one-line installer:

```zsh
curl -fsSL https://raw.githubusercontent.com/udhawan97/Orifold/main/install.sh | zsh
```

No data migration is required; no settings or documents are affected by this release.

---

Orifold folds a thousand messy pages so you never have to. The crane stays; the chaos doesn't.
