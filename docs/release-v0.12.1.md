# v0.12.1 Orifold

## GitHub Release Fields

Tag: `v0.12.1`

Target: release commit to be tagged `v0.12.1`

Release title: `v0.12.1 Orifold — Trust what you see`

Assets produced automatically by `.github/workflows/release.yml`:

- `Orifold-0.12.1-macOS-universal.dmg` — drag-to-Applications disk image for Apple Silicon and Intel
- `Orifold-0.12.1-macOS-universal.dmg.sha256` — versioned checksum sidecar
- `Orifold.dmg` — byte-identical stable-name alias for `releases/latest/download/Orifold.dmg`
- `Orifold.dmg.sha256` — stable-name checksum sidecar
- `manifest.json` — version, build, date, size, checksum, minimum macOS, and architecture
- `Orifold.zip` — one-line installer, Homebrew cask, and Desktop-helper artifact

Build the assets locally with:

```zsh
ORIFOLD_UNIVERSAL=1 ./scripts/install-mac.sh --clean --no-open --package-only --package /tmp/Orifold.zip
zsh scripts/make-dmg.sh --from-zip /tmp/Orifold.zip --output /tmp/Orifold-0.12.1-macOS-universal.dmg --version 0.12.1
```

## Release Notes

# v0.12.1 Orifold — Trust what you see

**Release:** September 26, 2026

**Tag:** `v0.12.1`

---

## Comparisons include the working draft

- Compare With… now includes enabled watermarks, page numbers, Bates labels, stamps, hanko,
  images, and under/over PDF overlays in the workspace's visual evidence.
- Text counts still read the original member PDF bytes, so a visual decoration cannot invent a
  wording change. Decoration-preparation failure is reported as unavailable visual evidence.
- Rotated and cropped pages retain their page geometry while the comparison visual is prepared.

## Redaction fails closed around ambiguous content

- A mark that overlaps a placed signature or stored positioned decoration is refused before
  serialization or byte mutation. A stored page-wide decoration without reliable bounds blocks
  redaction anywhere on that page. Move or remove the editable item, then apply redaction.
- Complex page-scale vector paths and shadings that cannot be safely split are refused before
  mutation. Simple page-wide backgrounds can remain under the black box without rasterizing the
  whole page, and the confirmation and result copy disclose that boundary in all six languages.
- Redacted pages keep page labels, embedded attachments, and unaffected annotations through
  apply, undo, and redo.

## Sidebar and import flows keep their place

- Document and page thumbnails refresh when document bytes change while row identity and
  selection stay stable.
- Cancelling one encrypted-file prompt advances to the next queued file instead of dismissing the
  shared prompt.
- Sidebar document and page rows accept Return for selection and expose VoiceOver Select, Move Up,
  and Move Down actions. Pointer drag and drop remains unchanged.

## Output publication cleanup

An early output-directory binding failure now has one descriptor owner. The failure still closes
both descriptors, publishes nothing, and keeps descriptor-relative validation for successful
folder folds.

## Compatibility and privacy

Document processing remains local. Orifold requires macOS 14 Sonoma or newer and ships as a
universal Apple Silicon + Intel app. Public builds remain ad-hoc signed and are not Apple-notarized
unless the release signing secrets are configured.

## Verification contract

- The local Swift release gate executed 1,352 tests, with environment-gated skips reported
  separately, and the release workflow repeats the full suite on the tagged commit.
- Focused redaction, comparison, decoration, localization, password-queue, sidebar-reorder, and
  output-publication regressions passed before integration.
- Swift build, universal Xcode Release build, packaged-app signature verification, shell syntax,
  localization JSON validation, Graphify refresh, docs build, and public-surface checks are release
  gates rather than release-note assumptions.

**Full Changelog**: https://github.com/udhawan97/Orifold/compare/v0.12.0...v0.12.1
