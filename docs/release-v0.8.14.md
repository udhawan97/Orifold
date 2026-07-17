# v0.8.14 Orifold

## GitHub Release Fields

Tag: `v0.8.14`

Target: latest commit tagged by `v0.8.14`

Release title: `v0.8.14 Orifold`

Assets to upload (all produced automatically by `release.yml`):

- `Orifold-0.8.14-macOS-universal.dmg` — the drag-to-Applications disk image (primary download)
- `Orifold-0.8.14-macOS-universal.dmg.sha256` — checksum sidecar used by the in-app updater
- `Orifold.dmg` — byte-identical stable-name alias for `releases/latest/download/Orifold.dmg`
- `Orifold.dmg.sha256`
- `manifest.json` — version, build, date, size, checksum, minimum macOS, and architecture
- `Orifold.zip` — used by the one-line installer, Homebrew cask, and `.command` helpers

Automation: `.github/workflows/release.yml` builds a **universal (Apple Silicon + Intel)** app when a `v*` / `release-v*` tag is pushed, packages the DMG, smoke-tests the packaged app, publishes the tagged release as GitHub's latest release, and dispatches a docs-site rebuild.

Build the assets locally with:

```zsh
ORIFOLD_UNIVERSAL=1 ./scripts/install-mac.sh --clean --no-open --package-only --package /tmp/Orifold.zip
zsh scripts/make-dmg.sh --from-zip /tmp/Orifold.zip --output /tmp/Orifold-0.8.14-macOS-universal.dmg --version 0.8.14
```

## Release Notes

# v0.8.14 Orifold

**Release:** Latest release
**Tag:** [`v0.8.14`](https://github.com/udhawan97/Orifold/releases/tag/v0.8.14)

---

## What Changed Since v0.8.13

This hotfix repairs the in-app updater on current macOS releases. It does not change document formats, editing behavior, privacy, or network access.

### Fixed

- **Install and Restart no longer opens a “damaged” updater file.** Orifold now removes the sandbox-applied quarantine attribute from its own trusted, generated updater command before LaunchServices opens it.
- **Restore Previous Version uses the same repaired handoff.** Rollback commands receive the same preparation before launch.
- **Existing safety gates remain intact.** The updater still checks the downloaded DMG's SHA-256, validates the app's code signature before and after the swap, blocks installs with unsaved documents, keeps a rollback bundle, and reopens saved documents after relaunch.

### Verified

- Reproduced macOS error `-67026` with a quarantined sandbox-generated executable, then added a red-to-green regression that proves it executes only after the targeted attribute is removed.
- Re-ran the real DMG mount, signature verification, stage, swap, rollback, relaunch, install-orchestration, unsaved-document preflight, and launch-outcome suites.

## Install / Upgrade

Users on v0.8.13 or earlier must use the one-line installer once, because the broken updater handoff is part of the older app:

```zsh
curl -fsSL https://raw.githubusercontent.com/udhawan97/Orifold/main/install.sh | zsh
```

From v0.8.14 onward, use **Orifold → Check for Updates… → Install and Restart** normally.
