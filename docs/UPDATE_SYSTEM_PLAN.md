# Orifold Update System — Plan & Implementation Status

> Approved 2026-07-08. This document is both the approved plan (Fable) and the running
> status of what has actually shipped versus what remains. The remaining work is gated on
> things this environment can't do safely: a **GUI self-update rehearsal** and **EdDSA/CI
> secret custody**, which are the user's to hold.

---

## Implementation status (2026-07-08)

**Shipped and tested** (`swift test`: full suite 624 passing, 34 of them new update tests):

| Area | Files | State |
|---|---|---|
| Version normalization (shared w/ `version.sh` semantics; `0.10 > 0.9`) | `Engine/Updates/UpdateVersion.swift` | ✅ + tests |
| Observable phase machine + pluggable transport | `Engine/Updates/UpdateController.swift`, `UpdateModels.swift` | ✅ + tests |
| Check-only transport (GitHub `releases/latest`, ETag, no downgrades/prereleases) | `Engine/Updates/GitHubReleaseTransport.swift` | ✅ + tests |
| Install ledger (ring buffer, additive schema) | `Engine/Updates/UpdateHistoryStore.swift` | ✅ + tests |
| Launch sentinel + crash-loop detection | `Engine/Updates/LaunchSentinel.swift` | ✅ + tests |
| Rollback archive: previous-version zip + sha256 manifest + verify/prune | `Engine/Updates/RollbackArchive.swift` | ✅ + tests |
| Recovery store: pre-update/crash snapshots, torn-write safe | `Engine/Updates/RecoveryStore.swift` | ✅ + tests |
| Shared store paths under Application Support | `Engine/Updates/UpdateStorePaths.swift` | ✅ |
| "Check for Updates…" menu item (under About) + native result alert | `App/UpdateCommands.swift`, `App/AppCommands.swift` | ✅ |
| Settings: automatic-check toggle (consent) + Check Now + live status | `Views/SettingsView.swift` | ✅ |
| Launch wiring: sentinel stamp, verify-healthy grace, clean-exit, background check | `Engine/Updates/UpdateLaunchCoordinator.swift`, `App/OrifoldApp.swift` | ✅ |
| L10n: 20 keys × 6 languages, coverage + raw-key-leak guards green | `Resources/Localizable.xcstrings` | ✅ |

Design choices honored: automatic checks **default OFF** (the Settings toggle is the
consent moment); manual check always available; the check-only transport **cannot install
anything**, so nothing is ever installed without a later, explicit, consented Sparkle path;
`releases/latest` structurally excludes prereleases and older tags, so a downgrade is never
offered; all stores live beside `recents.json` and survive a bundle swap untouched.

**Pending — needs a GUI/interactive session and/or user-held secrets** (do not attempt headless):

1. **Phase 0 — Sparkle spike (go/no-go).** Prove sandboxed ad-hoc self-update end-to-end on
   a real Mac with two app versions + a local appcast. Everything below is gated on this.
2. **Phase 1 — EdDSA keys + signed `appcast.xml` in CI.** The private key is generate-once,
   never-removable; store as a GitHub secret + offline copy *before* the first signed
   release. Wire `make-appcast.sh` into `release.yml`/`docs.yml`, published via Pages.
3. **Phase 2/3 — Sparkle transport behind the existing `UpdateTransport` protocol** +
   download/staged/install sheet states + the second-launch inline consent card. The
   controller, phase machine, and entry points are already shaped for this drop-in.
4. **Phase 4 — pre-install checkpoint hook** (`willInstallUpdate` → `RecoveryStore` +
   `UpdateHistoryStore` record). Stores are ready; only the Sparkle delegate call is missing.
5. **Phase 6 — rollback restore**: `install-mac.sh --restore <zip>` (verify sha256, in-place
   swap honoring `/Applications` vs `~/Applications`, strip quarantine, relaunch, codesign
   verify) + Help-menu "Restore Previous Version…". The archive/manifest half is done;
   `UpdateController.canRestorePreviousVersion` already reflects an existing manifest.
6. **Phase 7 — "Recovered work" cards** on `EmptyStateView` (Open / Save As… / Discard) +
   recents fixture regression tests both version directions.
7. **About-popover status line** ("up to date" / "X available").

The crash-loop detector is already live but intentionally does **not** surface a rollback
offer yet — offering restore before restore works would be dishonest. It detects and
remembers (`UpdateLaunchCoordinator.lastAssessment`) so the offer drops in with Phase 6.

---

## A. Executive summary

Adopt **Sparkle 2 as the update transport** — verified in `WEBSITE_PLAN.md` §8 to work
ad-hoc-signed and sandboxed via its XPC installer services, the only sanctioned way a
sandboxed app can replace itself — and wrap it in Orifold-native consent-first UX: a "Check
for Updates…" item under the app menu, an Updates section in Settings, calm non-modal
status, and explicit permission before any install or restart. Around that transport we
build what Sparkle does not: a pre-install autosave checkpoint into a recovery store, an
update-history ledger with launch verification and crash-loop detection, a one-version
rollback archive with a "Restore Previous Version" flow routed through the existing
unsandboxed installer script, and a quiet recovery card on the empty-state screen. CI grows
an EdDSA-signed `appcast.xml` via the existing docs-site pipeline; all user data lives in
Application Support and survives bundle swaps, protected by tests.

## B. Current-state audit (repo-verified 2026-07-08)

- Pure SwiftPM executable, macOS 14+, script-assembled `.app` (`Package.swift`,
  `scripts/install-mac.sh`). SwiftUI `DocumentGroup` + `ReferenceFileDocument`
  (`OrifoldApp.swift`, `WorkspaceDocument.swift:42`).
- App Sandbox ON with `network.client` already granted (`Orifold.entitlements`) — so the
  check-only transport works today; **self-replacement does not** (WEBSITE_PLAN §8).
- Ad-hoc signed (`-`) unless Developer ID secrets exist; notarization pending (`release.yml`).
- Release pipeline already ships versioned DMG + zip + sha256 + `manifest.json` + stable
  `Orifold.dmg`, rolling `Orifold-latest` prerelease, and re-dispatches `docs.yml` on tags.
- Framework-embed pattern exists (PDFium via `ditto` + rpath, `install-mac.sh:496`) — Sparkle
  follows it. Menu insertion point: `CommandGroup(replacing: .appInfo)`.
- Recents = custom `RecentsStore` JSON + bookmarks in App Support, atomic writes, plus
  NSDocumentController "Open Recent". 6-language L10n via `L10n.string` with leak/coverage guards.
- Two clean releases already exist (v0.8.3, v0.8.4) → Sparkle's "two clean releases" gate is met.

**Unknowns to resolve before Phase 2:** does the DocumentGroup bridge autosave-in-place and
show the native unsaved-changes review on quit? · current Sparkle 2.x sandbox Info.plist keys
and re-signing of its XPC services under ad-hoc · `generate_appcast` pinning · installed bundle
size (rollback budget) · appcast hosting URL on Pages · Xcode wrapper parity for the Sparkle dep.

## C. Proposed UX

Calm, quiet, non-modal unless user-initiated. State lives in the app menu, About popover,
and Settings — never an interrupting window.

- **Automatic:** second-launch inline consent (empty-state footer, not a dialog). If accepted,
  background checks are silent unless an update exists (badge + one quiet banner). Background
  *download* only if separately enabled; **install always waits for explicit consent**.
- **Manual:** Orifold menu → "Check for Updates…" directly under About. States: Checking →
  Up to date / Update available (sheet). *(Shipped today via NSAlert + Settings status.)*
- **Update sheet:** icon, "Orifold X is ready to download", "You have Y · Released … · N MB",
  release notes, [Remind Me Later] [Skip This Version] [Download] → progress → "Ready to
  install. Orifold will restart to finish — your open documents will be saved first."
  [Install Later] [Install and Restart].
- **Install/restart:** consent → pre-update checkpoint → Sparkle relaunch via normal
  termination, so unsaved docs get the native review-changes dialog; cancelling there cancels
  the install cleanly (stays staged). Never force-close.
- **Failure:** sheet, not raw error — "The update couldn't be installed. Your current version
  is untouched and your documents are safe." + [Try Again] [Open Download Page] + disclosure.
- **Rollback:** calm launch dialog after a verified-bad update; Help → "Restore Previous
  Version…" otherwise. Restore explains it will close, reinstall the previous version, and
  leave documents untouched.
- **Recovery:** next launch after abrupt exit shows a "Recovered work" card row above Recents,
  each labeled "Autosaved Recovery" + time, actions Open / Save As… / Discard. Originals untouched.

## D. Update state machine

`idle → checking → upToDate | updateAvailable → downloading → downloaded/staged →
(consent) preflightCheckpoint → awaitingTermination → installing → launchVerification →
verified | rollbackOffered → rollingBack → rollbackComplete`. `staged` persists across
launches; `Skip` is per-version; **downgrade only via the rollback path, never the appcast**.
See `UpdatePhase` for the shipped subset (`idle/checking/upToDate/updateAvailable/
downloading/readyToInstall/failed`).

## E. Data model (all under `Application Support/Orifold/`, additive JSON, atomic writes)

- `update-history.json` — ring buffer ≤10 of `{from/to version+build, channel, installedAt,
  launchVerified, verifiedAt, rolledBack, rollbackReason}`. *(Shipped: `UpdateHistoryStore`.)*
- `launch-sentinel.json` — `{version, build, launchStartedAt, cleanExit, consecutiveUncleanCount}`.
  *(Shipped: `LaunchSentinel`.)*
- `Rollback/Orifold-<version>.zip` + `rollback-manifest.json` `{version, build, sha256,
  archivedAt, archiveFileName}`. *(Shipped: `RollbackArchiver`.)*
- `Recovery/<uuid>.orifold-recovery` + sidecar `{sourceURL?, sourceBookmark?, displayName,
  capturedAt, reason, appVersion, dirtyAtCapture}`. *(Shipped: `RecoveryStore`.)*
- Recents: `recents.json` **unchanged and untouched**; add decode-fixture regression tests.

## F. Rollback architecture

Sparkle has no rollback. In the `willInstall` hook, zip the running bundle into `Rollback/`
(reading self is sandbox-legal), record sha256, prune to one. **Failed update** = Sparkle
install error, or ≥2 consecutive unclean launches of an unverified version, or a store-migration
decode failure at startup, or user choice. Restore routes through the unsandboxed installer
(`install-mac.sh --restore <zip>`): verify sha256, in-place swap (honor `/Applications` vs
`~/Applications`), strip quarantine, relaunch, codesign-verify — launched via `NSWorkspace.open`
on the `.command` wrapper. Appcast never offers downgrades; additive-only schema keeps rollback
reads safe. Falls back to re-downloading the permanent versioned release asset if the archive
is missing.

## G. Autosave & document recovery

First verify the base: the ReferenceFileDocument/NSDocument bridge should already autosave in
place and show the native unsaved-changes review on quit — everything here *adds* to that.
Pre-update checkpoint writes `WorkspaceDocument.snapshot()` bytes (already pure/testable,
`WorkspaceDocument.swift:300`) to `Recovery/` atomically. Abrupt closure → sentinel detects
unclean exit → recovery scan → "Recovered work" cards. Edge cases: cloud-offline, missing
volume (grayed card, no crash), read-only (Save As… to a writable location), moved/renamed
(bookmark resolution; sidecar display name is the fallback).

## H. Test plan

Unit: version vectors (shared w/ `version.sh`), history encode/decode + prune, sentinel
transitions, crash-loop threshold, recovery round-trip, rollback sha256, additive-schema
downgrade decodes, L10n coverage + leak. *(All shipped and green.)* Integration: real appcast
parse + signature verify, checkpoint bytes re-open, recents fixture both directions. UI: menu
state, Settings toggles, sheet states, recovery cards. Crash-sim: kill -9 during checkpoint /
download / install → recovery surfaces, no torn stores. Updater failure: bad EdDSA sig / wrong
sha256 / network-down / disk-full. Rollback rehearsal on a local install. CI: appcast entry +
signed zip in a dry-run; smoke-test extended to verify Sparkle embedded + codesign-clean.

## I. Risk register

| Risk | Sev | Lik | Mitigation |
|---|---|---|---|
| EdDSA key lost → update chain dead | Crit | Low | Generate once; secret + offline copy; custody runbook before first signed release; CI fails if signing secret absent |
| Sparkle XPC install fails on ad-hoc+sandbox | High | Med | Phase-0 spike is the gate; fallback = the shipped check-only + installer-script updates |
| Script bundle breaks Sparkle embed/sign | High | Med | Follow PDFium pattern; no Library Validation on ad-hoc; extend CI smoke-test |
| Update interrupts unsaved work | Crit | Low | Native review flow + pre-install checkpoint + recovery store; install cancellable |
| Rollback zip corrupt/missing | Med | Low | sha256 at archive + restore; fallback re-download of versioned asset |
| Crash-loop false positive | Med | Med | Only unclean (non-clean-exit) launches count; require ≥2; offer, never auto-act |
| Bad migration blocks safe downgrade | Med | Low | Additive-only schema + fixture tests both directions |
| Chatty/naggy UX | Med | Med | One consent moment; badges over banners; sheets only on user action |

## J. Implementation sequence

Phase 0 spike (throwaway) → 1 keys+appcast CI → 2 Sparkle in-app + entry points → 3 consent +
lifecycle UX → 4 checkpoint + ledger → 5 launch verification + failure detection → 6 rollback →
7 recovery UI + recents hardening → 8 docs + QA. Each phase is `git revert`-able; none touches
document-editing paths. **Phases' data/logic layer (1-of-4, 5, 6-archive, 7-store) is already
implemented and tested**; the Sparkle-transport, CI-key, and GUI-surface halves remain.

## K. Opus handoff prompt

The original paste-ready Opus prompt is retained in the chat that produced this plan. It
still applies for the pending phases, with one adjustment: **the framework-independent
foundation (this doc's "Shipped" table) already exists and is tested — extend it, don't
rebuild it.** Start at Phase 0 (Sparkle spike); when wiring Sparkle, conform it to the
existing `UpdateTransport` protocol and drive the existing `UpdatePhase`/`UpdateController`;
attach the `willInstall` checkpoint to `RecoveryStore` + `UpdateHistoryStore` + the
`RollbackArchiver`; add `install-mac.sh --restore`; and surface recovery cards on
`EmptyStateView`. Re-verify the DocumentGroup autosave/review-on-quit behavior before Phase 2.
