# v0.12.0 Orifold

## GitHub Release Fields

Tag: `v0.12.0`

Target: release commit to be tagged `v0.12.0`

Release title: `v0.12.0 Orifold — Trust every fold, compare every draft`

Assets produced automatically by `.github/workflows/release.yml`:

- `Orifold-0.12.0-macOS-universal.dmg` — drag-to-Applications disk image for Apple Silicon and Intel
- `Orifold-0.12.0-macOS-universal.dmg.sha256` — versioned checksum sidecar
- `Orifold.dmg` — byte-identical stable-name alias for `releases/latest/download/Orifold.dmg`
- `Orifold.dmg.sha256` — stable-name checksum sidecar
- `manifest.json` — version, build, date, size, checksum, minimum macOS, and architecture
- `Orifold.zip` — one-line installer, Homebrew cask, and Desktop-helper artifact

Build the assets locally with:

```zsh
ORIFOLD_UNIVERSAL=1 ./scripts/install-mac.sh --clean --no-open --package-only --package /tmp/Orifold.zip
zsh scripts/make-dmg.sh --from-zip /tmp/Orifold.zip --output /tmp/Orifold-0.12.0-macOS-universal.dmg --version 0.12.0
```

## Release Notes

# v0.12.0 Orifold — Trust every fold, compare every draft

**Release:** September 26, 2026

**Tag:** `v0.12.0`

---

## Folder folds tell the whole story

- Folder operations retain a session-only result ledger for every planned input: completed,
  failed, cancelled while processing, or not started.
- Outputs publish through a no-replace path, preserving existing files byte-for-byte when a
  destination appears during the run. Setup, validation, and publication failures stay attached
  to the affected input.
- Searchable copies, Smaller copies, and Review copies are built-in presets, with one saved custom
  configuration for a workflow you repeat.

## Comparisons stay honest under pressure

- Compare With… shows determinate page-pair progress and cooperative cancellation. Dismissing the
  panel or changing the offset cancels obsolete work, and late callbacks cannot replace a newer run.
- Results preserve actual workspace page numbers and source identities, disclose offset exclusions,
  and distinguish changed, one-sided, incomplete, and unavailable analysis.
- Failed visual rendering or text extraction is no longer presented as an unchanged page.

## Redaction removes supported content

True redaction removes supported text, form XObjects, vector paths, images, and annotations from
affected page bytes, then rebuilds and re-reads the result to verify that marked content does not
survive. Unsupported pending edits and ambiguous form-field intersections fail closed. Redaction
remains beta and does not claim to scrub independent metadata, bookmark, structure-tree, comment,
or attachment copies.

## Privacy and compatibility

- Document processing remains local; no document uploads or new cloud paths were added.
- Orifold requires macOS 14 Sonoma or newer and ships as one universal Apple Silicon and Intel build.
- Release builds remain ad-hoc signed and are not Apple-notarized unless release signing secrets are configured.

## Verification contract

- The local Swift release gate executed 1,338 tests, skipped 33 documented environment-gated cases,
  and reported 0 failures in the captured rerun.
- Swift build, universal Xcode Release build, strict packaged-app signature verification, shell
  syntax, localization JSON validation, Graphify refresh, and the 77-page docs build passed.
- Native comparison smoke coverage exercised progress, cancellation UI, changed-page navigation,
  actual page numbers, and offset disclosure on synthetic PDFs.

**Full Changelog**: https://github.com/udhawan97/Orifold/compare/v0.11.1...v0.12.0
