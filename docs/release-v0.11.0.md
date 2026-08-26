# v0.11.0 Orifold

## GitHub Release Fields

Tag: `v0.11.0`

Target: release commit to be tagged `v0.11.0`

Release title: `v0.11.0 Orifold — Fold the whole stack, compare the drafts`

Assets produced automatically by `.github/workflows/release.yml`:

- `Orifold-0.11.0-macOS-universal.dmg` — drag-to-Applications disk image for Apple Silicon and Intel
- `Orifold-0.11.0-macOS-universal.dmg.sha256` — versioned checksum sidecar
- `Orifold.dmg` — byte-identical stable-name alias for `releases/latest/download/Orifold.dmg`
- `Orifold.dmg.sha256` — stable-name checksum sidecar
- `manifest.json` — version, build, date, size, checksum, minimum macOS, and architecture
- `Orifold.zip` — one-line installer, Homebrew cask, and Desktop-helper artifact

Build the assets locally with:

```zsh
ORIFOLD_UNIVERSAL=1 ./scripts/install-mac.sh --clean --no-open --package-only --package /tmp/Orifold.zip
zsh scripts/make-dmg.sh --from-zip /tmp/Orifold.zip --output /tmp/Orifold-0.11.0-macOS-universal.dmg --version 0.11.0
```

## Release Notes

# v0.11.0 Orifold — Fold the whole stack, compare the drafts

**Release:** August 22, 2026

**Tag:** `v0.11.0`

---

## What Changed Since v0.10.2

This release delivers two long-promised roadmap items — batch folder operations and
side-by-side compare — plus a smaller reading-aid refinement, all local-first.

### Fold the whole stack

- File → **Fold a Folder…** applies the selected steps to every PDF found under a chosen
  folder in one pass: make scanned pages searchable (OCR), add a watermark, and/or reduce
  file size with the existing compression presets.
- Results are written to a `Folded` subfolder with collision-proof names; the original files
  are never modified.
- The run shows per-file progress with Cancel, and one unreadable PDF becomes one failed
  outcome instead of aborting the batch. A PDF that is already compact, or has nothing to
  recognize, keeps its prior bytes and still folds.
- Every output passes qpdf structural validation before it lands on disk, through the same
  crash-safe write-and-verify path as every export.

### Side-by-side compare

- File → **Compare With…** (also in the More menu) pairs the current workspace's pages with
  a picked PDF and shows them side by side.
- Changed regions are highlighted on both pages via a resolution- and anti-aliasing-tolerant
  visual diff; text changes are summarized as word-level added/removed counts.
- A changed-pages strip jumps straight to differences, and a manual page offset re-aligns
  drafts whose pages shifted.
- Visual comparison reads exactly what is displayed (page rotations and crop boxes applied);
  text comparison reads the members' preserved bytes, so re-serialization can't manufacture
  phantom differences. Encrypted PDFs are declined with a clear message.

### Read aloud, from here

- A new View-menu command starts read-aloud at the sentence containing the current text
  selection instead of the top of the page, keeping the follow-along highlight in sync.
- With no selection — or a selection that can't be located in the page's speakable text —
  it falls back to the existing start-of-page behavior.

## Privacy and Compatibility

- All three features are local: batch folding reads and writes only the folder the user
  picks, comparison renders and diffs entirely on the Mac, and nothing is uploaded.
- Orifold still requires macOS 14 Sonoma or newer and ships as one universal Apple Silicon +
  Intel build.
- Release builds remain ad-hoc signed and are not Apple-notarized unless the release signing
  secrets are configured.

## Verification Contract

- The integrated Swift suite contains 1,159 tests: 33 are skipped by their documented
  environment gates and 0 failed in the final local integration gate.
- Focused regressions cover batch output naming and collision avoidance, the per-file
  OCR → watermark → compress pipeline (watermarks asserted via ink coverage, OCR via an
  injected recognition provider), per-file failure isolation and between-file cancellation,
  the visual tile diff's placement and thresholds, word-level LCS counts with the coarse
  long-page fallback, page pairing with offsets and one-sided pages, and the
  offset-aware read-aloud start.
- SwiftPM, XcodeGen, universal packaging, strict code-sign verification, installed-app
  workflows, hosted CI, published assets, installer behavior, and production documentation
  are release gates.

**Full Changelog**: https://github.com/udhawan97/Orifold/compare/v0.10.2...v0.11.0
