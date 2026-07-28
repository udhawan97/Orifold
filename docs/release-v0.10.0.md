# v0.10.0 Orifold

## GitHub Release Fields

Tag: `v0.10.0`

Target: latest commit tagged by `v0.10.0`

Release title: `v0.10.0 Orifold — Open wider, shape deeper, read farther`

Assets to upload (all produced automatically by `release.yml`):

- `Orifold-0.10.0-macOS-universal.dmg` — drag-to-Applications disk image for Apple Silicon and Intel
- `Orifold-0.10.0-macOS-universal.dmg.sha256` — checksum sidecar used by the in-app updater
- `Orifold.dmg` — byte-identical stable-name alias for `releases/latest/download/Orifold.dmg`
- `Orifold.dmg.sha256`
- `manifest.json` — version, build, date, size, checksum, minimum macOS, and architecture
- `Orifold.zip` — one-line installer, Homebrew cask, and Desktop-helper artifact

Automation: `.github/workflows/release.yml` builds a universal app when a `v*` / `release-v*` tag is pushed, packages and smoke-tests the DMG, publishes the tagged release as GitHub's latest release, and dispatches a docs-site rebuild.

Build the assets locally with:

```zsh
ORIFOLD_UNIVERSAL=1 ./scripts/install-mac.sh --clean --no-open --package-only --package /tmp/Orifold.zip
zsh scripts/make-dmg.sh --from-zip /tmp/Orifold.zip --output /tmp/Orifold-0.10.0-macOS-universal.dmg --version 0.10.0
```

## Release Notes

# v0.10.0 Orifold — Open wider, shape deeper, read farther

**Release:** Latest release

**Tag:** [`v0.10.0`](https://github.com/udhawan97/Orifold/releases/tag/v0.10.0)

---

## What Changed Since v0.9.1

This release widens three parts of the everyday workflow: what Orifold can open, what it can safely change inside a page, and how you can read unfamiliar text. Each feature keeps the same local-first boundary and refuses work it cannot perform faithfully.

### Comic archives fold straight into PDF

- **Open CBZ files like any other import.** Orifold reads ZIP-compatible comic archives directly, sorts image filenames in natural order (`page2` before `page10`), and turns each image into a fitted PDF page.
- **No temporary extraction folder.** Archive entries are decoded in memory; macOS metadata and non-image files are ignored.
- **Bounded, specific failure handling.** The importer enforces the 100 MB package limit, a 25 MB per-entry limit, and a 1,000-page ceiling. Empty archives, unreadable images, oversized entries, and over-limit books get a clear error instead of a partial or blank PDF.

### Restyle real vector objects

- **Change the paint that is already there.** Select a compatible path, open **Object Style** in the Markup inspector, and change its existing solid fill, stroke, or 0.25–24 pt line width.
- **The edit is part of the document.** Restyling is undoable and survives save, reopen, export, and later inline-text edits through the same object-replay pipeline.
- **Conservative by design.** Orifold does not invent a missing fill or outline, recolor images, rewrite gradients or reused Form XObjects, or modify object content on rotated pages.

### Translate without changing the PDF

- **Translate a selection or the current page on macOS 15+.** The View menu keeps the action reachable at compact window widths, and the More toolbar menu offers the same reading aid when visible.
- **Apple’s on-device Translation framework does the work.** Before the first translation, Orifold explains that macOS may download the selected language model. After the model is present, the document text is translated on this Mac.
- **Selection first, current page second.** A PDF text selection takes priority; otherwise Orifold reads the current page in detected order, including committed inline text edits. Long passages are split at sentence and word boundaries, translated in order, and reassembled.
- **Read-only means read-only.** The side-by-side result can be copied, but it never replaces text, adds an annotation, or writes anything back to the PDF.

### Documentation and privacy

- Added exact CBZ import, object-restyling, and translation guides.
- Clarified that document contents are never uploaded while update checks, optional signing timestamps, and Apple language-model downloads remain explicit network-capable flows.
- Refreshed source, test, build, installer, and release metadata across the README and public documentation.

## Privacy and Compatibility

- Orifold still requires macOS 14 Sonoma or newer and ships as one universal Apple Silicon + Intel build.
- Translation alone requires macOS 15 or newer; the command is not shown on macOS 14.
- Document import, editing, OCR, translation, and export stay on-device. macOS may contact Apple to obtain a translation language model after the first-use disclosure.
- No workspace schema migration is required. Existing PDFs and workspaces continue to open normally.

## Important Boundaries

- CBZ support covers ZIP-compatible `.cbz` archives, not RAR-based `.cbr` files.
- A workspace still holds up to 50 imported files even when one CBZ becomes many PDF pages.
- Vector restyling changes only compatible existing paint channels on unrotated pages.
- Translation is a reading aid, not a PDF-editing or replacement workflow.

## Verification

- 984 tests gate the source release, including focused CBZ bounds/order/error coverage, object-style persistence and undo coverage, and translation chunking/source-selection/disclosure coverage.
- SwiftPM and Xcode builds, generated-project parity, localization coverage, installer packaging, strict code-sign verification, and the production documentation build are release gates.
- The universal DMG workflow mounts and smoke-tests the exact packaged app before GitHub publishes it.

**Full Changelog**: https://github.com/udhawan97/Orifold/compare/v0.9.1...v0.10.0
