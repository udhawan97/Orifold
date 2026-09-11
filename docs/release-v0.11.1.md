# v0.11.1 Orifold

## GitHub Release Fields

Tag: `v0.11.1`

Target: release commit to be tagged `v0.11.1`

Release title: `v0.11.1 Orifold — Keep every page, finish every handoff`

Assets produced automatically by `.github/workflows/release.yml`:

- `Orifold-0.11.1-macOS-universal.dmg` — drag-to-Applications disk image for Apple Silicon and Intel
- `Orifold-0.11.1-macOS-universal.dmg.sha256` — versioned checksum sidecar
- `Orifold.dmg` — byte-identical stable-name alias for `releases/latest/download/Orifold.dmg`
- `Orifold.dmg.sha256` — stable-name checksum sidecar
- `manifest.json` — version, build, date, size, checksum, minimum macOS, and architecture
- `Orifold.zip` — one-line installer, Homebrew cask, and Desktop-helper artifact

Build the assets locally with:

```zsh
ORIFOLD_UNIVERSAL=1 ./scripts/install-mac.sh --clean --no-open --package-only --package /tmp/Orifold.zip
zsh scripts/make-dmg.sh --from-zip /tmp/Orifold.zip --output /tmp/Orifold-0.11.1-macOS-universal.dmg --version 0.11.1
```

## Release Notes

# v0.11.1 Orifold — Keep every page, finish every handoff

**Release:** September 10, 2026

**Tag:** `v0.11.1`

---

## Preservation fixes

- Selected-page and split exports now use the complete baked export before selecting their pages,
  so page decorations and other visible workspace content are retained.
- Structural page-operation undo and redo keep authoritative member bytes separate from live
  PDFKit snapshots. Embedded attachments are neither erased nor resurrected by later page edits.
- Newly created annotations use stable workspace and annotation identities for undo and redo, so
  a page rotation or other structural restore cannot leave a detached annotation object behind.

## Import and update fixes

- Folder imports keep their accounting open until every queued password decision resolves.
  Encrypted PDFs unlocked later contribute to the final count and preserve their batch order;
  wrong passwords, skips, malformed inputs, unsupported files, truncation, and cancellation keep
  their established behavior.
- Update and restore helpers now require an app-owned, revocable handoff authorization. If macOS
  quit review is cancelled, the helper exits before changing the app and Orifold returns to an
  explicit retry state.
- Reopen and install-attempt markers are now required prerequisites. A write failure keeps the
  app open, reports a useful preparation failure, preserves the verified download, and cleans
  only records owned by the current attempt.

## Privacy and compatibility

- Document processing remains on the Mac. These fixes do not add document uploads or new network
  paths.
- Orifold requires macOS 14 Sonoma or newer and ships as one universal Apple Silicon and Intel
  build.
- Release builds remain ad-hoc signed and are not Apple-notarized unless release signing secrets
  are configured.

## Verification contract

- The Swift suite contains 1,267 tests; environment-gated fixture tests may skip when their local
  corpora are unavailable.
- Focused regressions cover attachment-preserving page timelines, decorated subset and split
  exports, annotation creation undo after structural restore, mixed encrypted folder imports,
  marker-write failures, owned cleanup, revoked helper authorization, cancelled install and
  restore termination, and explicit retry.
- SwiftPM build and tests, shell syntax, Graphify refresh, universal packaging, hosted CI, exact
  published assets, checksums, bundle resources, code signing, and public download behavior are
  release gates.

**Full Changelog**: https://github.com/udhawan97/Orifold/compare/v0.11.0...v0.11.1
