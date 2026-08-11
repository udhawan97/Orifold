# v0.10.2 Orifold

## GitHub Release Fields

Tag: `v0.10.2`

Target: release commit to be tagged `v0.10.2`

Release title: `v0.10.2 Orifold — Split, shape, and verify`

Assets produced automatically by `.github/workflows/release.yml`:

- `Orifold-0.10.2-macOS-universal.dmg` — drag-to-Applications disk image for Apple Silicon and Intel
- `Orifold-0.10.2-macOS-universal.dmg.sha256` — versioned checksum sidecar
- `Orifold.dmg` — byte-identical stable-name alias for `releases/latest/download/Orifold.dmg`
- `Orifold.dmg.sha256` — stable-name checksum sidecar
- `manifest.json` — version, build, date, size, checksum, minimum macOS, and architecture
- `Orifold.zip` — one-line installer, Homebrew cask, and Desktop-helper artifact

Build the assets locally with:

```zsh
ORIFOLD_UNIVERSAL=1 ./scripts/install-mac.sh --clean --no-open --package-only --package /tmp/Orifold.zip
zsh scripts/make-dmg.sh --from-zip /tmp/Orifold.zip --output /tmp/Orifold-0.10.2-macOS-universal.dmg --version 0.10.2
```

## Release Notes

# v0.10.2 Orifold — Split, shape, and verify

**Release:** August 11, 2026

**Tag:** `v0.10.2`

---

## What Changed Since v0.10.1

This release makes large PDF cleanups easier to finish without leaving the local workspace. It adds reviewed page cleanup, structured splitting, outline editing, vector-safe page treatments, and conservative incoming-signature inspection, then closes two packaged-app first-impression gaps.

### Split and finish large documents

- Split one workspace into separate PDFs every N pages, by explicit page ranges, or at top-level bookmarks.
- Detect likely blank pages with a noise-tolerant visual heuristic, review every candidate, and choose exactly which pages to remove.
- Edit the exported outline: add, rename, reorder, indent, outdent, delete, or restore bookmarks while keeping destinations tied to stable workspace pages.
- Export comments, highlights, underlines, and strikeouts as a localized Markdown summary.
- Scale PDF output onto A4 or US Letter while preserving one-to-one page mapping and bookmarks.

### Shape pages without flattening them

- Set visible crop margins for one page or all pages, with atomic undo across workspace members.
- Place another PDF above or below the current content on one page or every page.
- Overlay content stays vector PDF content during export instead of becoming a raster screenshot.
- Crop and overlay paths preserve Orifold's existing attachment, byte-lane, page-target, and undo contracts.

### Inspect signatures already in a PDF

- Incoming PDF signatures now report cryptographic integrity, whether the signature covers the whole document or predates later changes, system certificate trust, and signing-time metadata labeled unverified.
- Trust, revocation, and time claims stay conservative: unavailable evidence is labeled unavailable or unverified rather than being treated as proof. Incoming RFC 3161 timestamp and LTV evidence are not verified in this release.
- Signature inspection is local and read-only; it does not modify or upload the document.

### The in-app language choice now wins

- Japanese and Simplified Chinese now resolve through their matching locale-aware packaged resources even when macOS prefers a different language.
- Region-qualified locales such as `ja_JP` and `zh_CN` resolve to Japanese and Simplified Chinese instead of silently falling back to English.
- Unsupported languages retain a deliberate English fallback.
- Localized format strings use the selected locale for formatting as well as translation lookup.

### The main window cannot restore into an unusable sliver

- New workspaces start at a practical 980 × 720 pt content size.
- The primary document window has an audited 641 × 500 pt minimum content size.
- Restored frames below that floor are clamped when the AppKit window reconnects.
- Restored sizes meeting the supported minimum are preserved instead of being reset on every launch.

## Privacy and Compatibility

- Document processing and signature inspection remain local to the Mac. Orifold changes PDF bytes only when the user applies an edit or exports; it does not upload document content.
- Orifold still requires macOS 14 Sonoma or newer and ships as one universal Apple Silicon + Intel build.
- Release builds remain ad-hoc signed and are not Apple-notarized unless the release signing secrets are configured.

## Verification Contract

- The integrated Swift suite contains 1,086 tests: 33 are skipped by their documented environment gates and 0 fail locally.
- Focused regressions cover split planning and PDF output, blank-page proposal/removal, outline persistence, comment summaries, scale mapping, CropBox mutation/undo, vector overlay placement, signature extraction/validation, locale selection, and window sizing.
- SwiftPM, XcodeGen, universal packaging, strict code-sign verification, installed-app workflows, hosted CI, published assets, installer behavior, and production documentation are release gates.

**Full Changelog**: https://github.com/udhawan97/Orifold/compare/v0.10.1...v0.10.2
