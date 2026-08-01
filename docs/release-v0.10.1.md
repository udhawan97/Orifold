# v0.10.1 Orifold

## GitHub Release Fields

Tag: `v0.10.1`

Target: latest commit tagged by `v0.10.1`

Release title: `v0.10.1 Orifold — Keep your place, keep your context`

Assets to upload (all produced automatically by `release.yml`):

- `Orifold-0.10.1-macOS-universal.dmg` — drag-to-Applications disk image for Apple Silicon and Intel
- `Orifold-0.10.1-macOS-universal.dmg.sha256` — checksum sidecar used by the in-app updater
- `Orifold.dmg` — byte-identical stable-name alias for `releases/latest/download/Orifold.dmg`
- `Orifold.dmg.sha256`
- `manifest.json` — version, build, date, size, checksum, minimum macOS, and architecture
- `Orifold.zip` — one-line installer, Homebrew cask, and Desktop-helper artifact

Automation: `.github/workflows/release.yml` builds a universal app when a `v*` / `release-v*` tag is pushed, packages and smoke-tests the DMG, publishes the tagged release as GitHub's latest release, and dispatches a docs-site rebuild.

Build the assets locally with:

```zsh
ORIFOLD_UNIVERSAL=1 ./scripts/install-mac.sh --clean --no-open --package-only --package /tmp/Orifold.zip
zsh scripts/make-dmg.sh --from-zip /tmp/Orifold.zip --output /tmp/Orifold-0.10.1-macOS-universal.dmg --version 0.10.1
```

## Release Notes

# v0.10.1 Orifold — Keep your place, keep your context

**Release:** Latest release

**Tag:** [`v0.10.1`](https://github.com/udhawan97/Orifold/releases/tag/v0.10.1)

---

## What Changed Since v0.10.0

This patch release makes page identity, recent-work re-entry, and localized status flows more dependable. It does not change workspace numbering or document bytes to achieve that clarity.

### Source page labels without unstable numbering

- **Workspace position stays primary.** Page 12 remains page 12 in the merged workspace, even when its source PDF calls that page `A-3`, `iv`, or another custom label.
- **Useful source context appears beside it.** The page bar and search results show the source label only when the PDF really contains a `/PageLabels` number tree and the label differs from the workspace position.
- **One shared answer.** Page-bar and search copy now resolve through the same page-reference model, including mixed labeled/unlabeled members, reordered pages, and boundary pages.
- **Read-only by design.** Orifold never writes page labels, changes jump-field input, renumbers sidebar pages, or alters export bytes for this display feature.

### Recents returns to the right place

- **Resume lands where promised.** The Recent card's stored workspace page is applied after the document view is ready instead of being lost during launch-time regeneration.
- **Thumbnails show document content, not separators.** The view model resolves the current workspace position to the actual combined PDF page before Recents renders its preview.
- **Missing files recover instead of dead-ending.** Activating a Not found card now opens the existing classified recovery sheet with Choose File Again, Remove from Recents, and Cancel.
- **Clear all is deliberate.** Clear Recent History states the number of entries, explains that documents are untouched, defaults to Cancel, and only clears after explicit confirmation.

### Localization holds across all six languages

- Fixed a placeholder-order crash in Hindi and Japanese Replace All results.
- Localized comment page references, export status, baked page-number stamps, and the remaining interpolated error/status strings.
- Added format-specifier parity and interpolated-localization-key guards so same-typed placeholders and compiler-derived keys cannot silently regress.
- Added English, Spanish, French, Hindi, Japanese, and Simplified Chinese copy for Recent-history confirmation.

## Privacy and Compatibility

- Orifold still requires macOS 14 Sonoma or newer and ships as one universal Apple Silicon + Intel build.
- Page-label display and Recents recovery are local metadata/UI operations. They do not upload, rewrite, or export document content.
- No workspace schema migration is required. Existing PDFs, workspaces, bookmarks, and Recent entries continue to work.

## Verification

- 1,007 Swift tests gate the source release, with 33 intentionally skipped environment/fixture cases and zero failures in the local release pass.
- Focused regressions prove missing Recent cards still dispatch recovery and Clear History cannot call the store directly from its header action.
- Localization coverage, placeholder parity, raw-key, and interpolated-key guards cover all six shipped languages.
- The clean installed app was verified at `/Users/umang/Applications/Orifold.app`: missing-file recovery surfaced all three actions, Clear History showed count/scope before mutation, and cancelling preserved all 12 existing Recent entries.
- SwiftPM build/tests, XcodeGen parity, shell syntax, universal packaging, strict code-sign verification, hosted CI, published assets, installer behavior, and production documentation remain release gates.

**Full Changelog**: https://github.com/udhawan97/Orifold/compare/v0.10.0...v0.10.1
