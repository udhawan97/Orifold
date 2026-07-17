# v0.8.12 Orifold

## GitHub Release Fields

Tag: `v0.8.12`

Target: latest commit tagged by `v0.8.12`

Release title: `v0.8.12 Orifold`

Assets to upload (all produced automatically by `release.yml`):

- `Orifold-0.8.12-macOS-universal.dmg` — the drag-to-Applications disk image (primary download)
- `Orifold-0.8.12-macOS-universal.dmg.sha256` — checksum sidecar used by the in-app updater
- `Orifold.dmg` — byte-identical stable-name alias for `releases/latest/download/Orifold.dmg`
- `Orifold.dmg.sha256`
- `manifest.json` — version, build, date, size, checksum, minimum macOS, and architecture
- `Orifold.zip` — used by the one-line installer, Homebrew cask, and `.command` helpers

Automation: `.github/workflows/release.yml` builds a **universal (Apple Silicon + Intel)** app when a `v*` / `release-v*` tag is pushed, packages the DMG, smoke-tests the packaged app, publishes the tagged release as GitHub's latest release, and dispatches a docs-site rebuild.

Build the assets locally with:

```zsh
ORIFOLD_UNIVERSAL=1 ./scripts/install-mac.sh --clean --no-open --package-only --package /tmp/Orifold.zip
zsh scripts/make-dmg.sh --from-zip /tmp/Orifold.zip --output /tmp/Orifold-0.8.12-macOS-universal.dmg --version 0.8.12
```

## Release Notes

# v0.8.12 Orifold

**Release:** Latest release
**Tag:** [`v0.8.12`](https://github.com/udhawan97/Orifold/releases/tag/v0.8.12)

---

## What Changed Since v0.8.11

This release deepens the editing architecture so text and graphic changes can safely coexist. It also makes complex-page inspection and canvas interactions more predictable. No file-format migration or network behavior changes.

### Improved

- **Edit text and graphics in the same PDF.** Inline text replacement and Select-tool object edits now replay together from one canonical page instead of blocking one another or risking one edit type overwriting the other.
- **Preserve interactive PDF content.** Mixed edits retain live annotations, filled form values, page rotations, and workspace edit metadata through save, reopen, export, and subsequent edits.
- **Fail safely on partial edits.** If Orifold cannot resolve every requested structural object operation, it leaves the live document untouched and explains that the edit could not be completed rather than saving a partial replay.
- **More consistent canvas controls.** Delete, Escape, selection changes, resize, page changes, inline-editor completion, undo alignment, and repaint now follow one ordered interaction state machine.
- **Predictable complex-page performance.** Text and object tools share one versioned PDFium page inspection. Bounded cache limits reject excess work explicitly instead of rescanning indefinitely or silently falling back to a less reliable detector.

### Under the hood

- Structural object edits remain authoritative in PDFium. Transparent text-replacement overlays are imported as PDF form objects without redrawing the destination page, qpdf preserves live annotation and AcroForm state, and a final metadata pass restores rotations and combined edit stamps.
- Page duplication, deletion, reordering, cross-document moves, z-order changes, undo/redo, and persisted legacy object identifiers are covered by new regression tests.
- The release gate now contains 749 tests across 186 Swift app-and-test files, plus the production build, generated-project, documentation, packaging, and installed-app checks.

## Install / Upgrade

1. Download `Orifold-0.8.12-macOS-universal.dmg` or the stable-name `Orifold.dmg`.
2. Open it and drag **Orifold** into Applications.
3. Launch from Applications. Existing users can also use Orifold's consent-based updater or rerun `scripts/install-mac.sh`, which fetches the latest release.
