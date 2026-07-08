# v0.8.4 Orifold

## GitHub Release Fields

Tag: `release-v0.8.4`

Target: latest commit tagged by `release-v0.8.4`

Release title: `v0.8.4 Orifold`

Assets to upload (all produced automatically by `release.yml`):

- `Orifold-0.8.4-macOS-universal.dmg` — the drag-to-Applications disk image (primary download)
- `Orifold-0.8.4-macOS-universal.dmg.sha256` — checksum sidecar
- `Orifold.dmg` — byte-identical stable-name alias, so `releases/latest/download/Orifold.dmg` never breaks
- `Orifold.dmg.sha256`
- `manifest.json` — version, build, date, size, checksum, min macOS, architecture
- `Orifold.zip` — unchanged; still drives the one-line installer, Homebrew cask, and `.command` helpers

Automation: `.github/workflows/release.yml` builds a **universal (Apple Silicon + Intel)** app on push of any `release-v*` tag, packages the DMG via `scripts/make-dmg.sh`, and — new in this release — runs a **packaged-app smoke gate** (verifies the `Orifold_Orifold.bundle` resource bundle is present, `codesign --verify` passes, and the app launches without an early crash) before publishing. It then publishes the tagged release as GitHub's "latest" (`make_latest: true`) and dispatches a docs-site rebuild so the download page reflects the new version.

Build the assets locally with:

```zsh
ORIFOLD_UNIVERSAL=1 ./scripts/install-mac.sh --package-only --package /tmp/Orifold.zip
zsh scripts/make-dmg.sh --from-zip /tmp/Orifold.zip --version 0.8.4
```

## Release Notes

# v0.8.4 Orifold

**Release:** Latest release
**Tag:** [`release-v0.8.4`](https://github.com/udhawan97/Orifold/releases/tag/release-v0.8.4)

---

## What Changed Since v0.8.3

v0.8.4 is a **stability and correctness** release. It fixes a launch crash that affected the packaged build, removes the idle CPU pinning that made the app feel sluggish, and repairs a widespread defect where localized interface text could render as raw translation keys. No document-editing behavior changes.

### Fixed: launch crash on the packaged app

- The v0.8.3 DMG could crash on launch because the installer didn't copy SwiftPM's resource bundle (`Orifold_Orifold.bundle`, which carries the string catalog and asset catalog) into the app. The first localized lookup then hit `Bundle.module`'s `fatalError` and the app crash-looped.
- The installer now copies **every** SwiftPM resource bundle into `Contents/Resources`, and refuses to install or package a bundle that is missing `Orifold_Orifold.bundle` — a build that would crash at launch can no longer ship.
- The string lookup layer no longer traps: it resolves the resource bundle by hand and degrades to untranslated text at worst, never a crash.
- The release workflow gained a **smoke gate** that mounts the built DMG, asserts the resource bundle is present, verifies the code signature, and launches the app to confirm it survives startup — all before the release is published.

### Fixed: idle CPU pinning (sluggishness)

- The empty-state screen ran two always-on `Canvas` animations (the companion's idle "breathing" and the ambient background glow) that redrew every frame forever, pinning a full CPU core even when the app was idle.
- Companions now settle into a still resting pose after a short grace period and wake on hover or interaction; the ambient background runs at a much lower frame rate. Measured idle CPU dropped from ~100% of a core to ~0% with a document open (and a low single-digit percentage on the empty state).

### Fixed: interface text showing raw translation keys

- Because Orifold builds with pure SwiftPM (no Xcode project), SwiftUI's default `LocalizedStringKey` resolution — which reads `Bundle.main` — can't find the string catalog, which lives in a nested resource bundle. Any view that passed a bare key literal to `Text`, `Label`, `Button`, `Link`, `Toggle`, `TextField`, `Picker`, `DisclosureGroup`, `.help(...)`, `.accessibilityLabel(...)`, `.confirmationDialog(...)`, and similar APIs rendered the **raw key** on screen (e.g. a link reading `help.viewDocumentation.button`).
- Every such site across the app now resolves through the app's own localization layer, so all interface text — panels, toolbars, menus, popovers, dialogs, and accessibility labels — displays correctly in all six supported languages, and updates live when the in-app language is switched.
- A new regression test scans the interface source and fails the build if any raw key literal ever reaches a localized-text API again.

### Also hardened

- Snapshotting fixes for two SwiftUI `ForEach` loops (the annotation-tool capsule and the inspector's markup list) that could index a stale, shortened array after a reader-mode toggle or an annotation delete.
- The inspector's Markup tab computes its cross-document annotation walk once per render instead of twice.

## Install / Upgrade

1. Download `Orifold-0.8.4-macOS-universal.dmg` (or the stable-name `Orifold.dmg`).
2. Open it and drag **Orifold** into **Applications**.
3. Launch from Applications. Existing users can also re-run `scripts/install-mac.sh`, which always fetches the latest release.
