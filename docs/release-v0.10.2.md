# v0.10.2 Orifold

## GitHub Release Fields

Tag: `v0.10.2`

Target: release commit to be tagged `v0.10.2`

Release title: `v0.10.2 Orifold — Your language, a usable window`

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

# v0.10.2 Orifold — Your language, a usable window

**Release:** Upcoming patch release

**Tag:** `v0.10.2` (published after the release gates pass)

---

## What Changed Since v0.10.1

This patch addresses two first-impression risks identified in an isolated packaged-build audit.

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

- These changes affect interface resources and window geometry only; they do not read, upload, rewrite, or export document content.
- Orifold still requires macOS 14 Sonoma or newer and ships as one universal Apple Silicon + Intel build.
- Release builds remain ad-hoc signed and are not Apple-notarized unless the release signing secrets are configured.

## Verification Contract

- Locale-specific bundle-selection regressions cover Japanese, Simplified Chinese, unsupported-language fallback, and SwiftPM raw-catalog behavior.
- Window-sizing regressions cover default/minimum geometry, below-floor repair, and preservation of dimensions meeting the supported minimum.
- SwiftPM, XcodeGen, universal packaging, strict code-sign verification, installed-app workflows, hosted CI, published assets, installer behavior, and production documentation are release gates.

**Full Changelog**: https://github.com/udhawan97/Orifold/compare/v0.10.1...v0.10.2
