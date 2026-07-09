# v0.8.5 Orifold

## GitHub Release Fields

Tag: `v0.8.5`

Target: latest commit tagged by `v0.8.5`

Release title: `v0.8.5 Orifold`

Assets to upload (all produced automatically by `release.yml`):

- `Orifold-0.8.5-macOS-universal.dmg` — the drag-to-Applications disk image (primary download)
- `Orifold-0.8.5-macOS-universal.dmg.sha256` — checksum sidecar
- `Orifold.dmg` — byte-identical stable-name alias, so `releases/latest/download/Orifold.dmg` never breaks
- `Orifold.dmg.sha256`
- `manifest.json` — version, build, date, size, checksum, min macOS, architecture
- `Orifold.zip` — unchanged; still drives the one-line installer, Homebrew cask, and `.command` helpers

Automation: `.github/workflows/release.yml` builds a **universal (Apple Silicon + Intel)** app on push of any `v*` / `release-v*` tag, packages the DMG via `scripts/make-dmg.sh`, runs the packaged-app smoke gate (resource bundle present, `codesign --verify` passes, app launches without an early crash), then publishes the tagged release as GitHub's "latest" (`make_latest: true`) and dispatches a docs-site rebuild so the download page reflects the new version. Standardizing on `v0.8.5`-style tags going forward; the `release-v*` trigger is retained for backward compatibility.

Build the assets locally with:

```zsh
ORIFOLD_UNIVERSAL=1 ./scripts/install-mac.sh --package-only --package /tmp/Orifold.zip
zsh scripts/make-dmg.sh --from-zip /tmp/Orifold.zip --version 0.8.5
```

## Release Notes

# v0.8.5 Orifold

**Release:** Latest release
**Tag:** [`v0.8.5`](https://github.com/udhawan97/Orifold/releases/tag/v0.8.5)

---

## What Changed Since v0.8.4

v0.8.5 gives Orifold the ability to **tell you when it's out of date** — a native, consent-first in-app update check — plus a calmer website. No document-editing behavior changes this cycle.

### Added: in-app update checking

- **"Check for Updates…" in the app menu**, placed directly under About Orifold (the canonical macOS location). It asks the GitHub Releases API for the latest stable version number, compares it to the running build, and reports "you're up to date" or "an update is available" — fully localized in all six languages, and shown as a calm native dialog, never a raw error code.
- **A Settings toggle, "Check for updates automatically", off by default.** Only turning it on lets Orifold check on its own (roughly once a day). The check is a single outbound version request — nothing about you or your documents is ever sent. A **Check Now** button and a plain-language status line sit alongside it.
- **Consent-first by construction.** This release is check-only: Orifold never downloads, installs, restarts, or closes your work on its own. When a newer version exists it points you to the download and you take every step yourself. The engine underneath (version comparison, an update-history ledger, a launch-health sentinel, and rollback/recovery stores) is in place for a future permission-gated auto-updater, but nothing user-facing acts without your say-so.

### Fixed

- **Update checks could go stale after the first one.** The GitHub check caches an ETag so unchanged releases don't burn API quota, but a "304 Not Modified" response was treated as "you're up to date" without re-comparing against your version — which could mask a genuinely newer release indefinitely. A 304 now re-evaluates the cached release against the running version, so a real update is always surfaced. Covered by new regression tests for the transport (previously untested).
- **Four broken "Under the Hood" anchor links in the README** now resolve to the correct GitHub-generated slug.

### Website

- **Light/dark theme toggle** — light by default (paper metaphor), your choice remembered across visits.
- **An honest "what's folding next" roadmap** — only genuinely-upcoming work, no shipped features masquerading as "coming soon".
- **Redesigned macOS download button** with an Apple-logo affordance and clearer release/size metadata.

## Install / Upgrade

1. Download `Orifold-0.8.5-macOS-universal.dmg` (or the stable-name `Orifold.dmg`).
2. Open it and drag **Orifold** into **Applications**.
3. Launch from Applications. Existing users can also re-run `scripts/install-mac.sh`, which always fetches the latest release.
