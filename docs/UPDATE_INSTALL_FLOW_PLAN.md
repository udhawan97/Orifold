# Update Install Flow Plan — quit → replace → relaunch → restore

**Status: PLANNING ONLY — approved for later implementation ("implement" not yet given).**
Written 2026-07-10 against `main` after v0.8.6. Companion to
[UPDATE_SYSTEM_PLAN.md](UPDATE_SYSTEM_PLAN.md) (the A–K architecture plan); this document
covers only the missing last mile: install, relaunch, and state preservation.

---

## 1. Current flow summary (verified against code, not memory)

What v0.8.6 actually does today:

1. **Check** — `UpdateController.checkForUpdates` → `GitHubReleaseTransport` asks
   `releases/latest` (ETag + cached-body 304 handling), compares tags via `UpdateVersion`.
   Prereleases and downgrades are never offered.
2. **Download + verify** — `UpdateController.downloadUpdate()` → `UpdateDownloader`
   streams the versioned universal DMG into `Application Support/Orifold/UpdaterCache/`
   with live progress, fetches the published `.sha256` sidecar first, verifies the digest,
   deletes on mismatch. Re-uses an already-verified download when present.
3. **Hand-off (the incomplete part)** — "Install and Relaunch" runs
   `UpdateInstallPreflight` (blocks while any document has unsaved changes), then
   `revealDownloadedUpdateForInstall()` = `NSWorkspace.open(dmg)`. **The user finishes
   manually in Finder** (drag to Applications), manually quits, manually relaunches.
   Nothing programmatically lands in Applications today — the task prompt's "moves the
   new app into /Applications" overstates current behavior.
4. **Menu flow** — `CheckForUpdatesCommandButton` → one-shot check →
   `UpdateAlertPresenter` (static `NSAlert`s: available/up-to-date/failed). The
   "available" alert's actions are View Release / Skip / Later — **no download or install
   from the menu**, and `NSAlert.runModal` cannot show live progress.
5. **Dormant, already-shipped primitives** (all unit-tested, none wired into install):
   `RollbackArchiver` (zip + sha256 of current bundle, one-archive retention),
   `RecoveryStore` (pre-update snapshot payloads + sidecars), `UpdateHistoryStore`
   (install ledger with `launchVerified`), `LaunchSentinel` (crash-loop detection),
   `UpdateArtifactCleaner` (allowlisted cache pruning), `UpdateLaunchCoordinator`
   (sentinel + 30 s healthy-grace + auto-check at launch).

### Relevant files/classes

| Area | File |
|---|---|
| Phase machine + actions | `Orifold/Engine/Updates/UpdateController.swift`, `UpdateModels.swift` |
| Discovery | `Orifold/Engine/Updates/GitHubReleaseTransport.swift`, `UpdateVersion.swift` |
| Download + verify | `Orifold/Engine/Updates/UpdateDownloader.swift` |
| Install safety | `UpdateInstallPreflight.swift`, `RollbackArchive.swift`, `RecoveryStore.swift`, `UpdateArtifactCleaner.swift`, `UpdateStorePaths.swift` |
| Launch lifecycle | `UpdateLaunchCoordinator.swift`, `LaunchSentinel.swift`, `UpdateHistoryStore.swift`, `Orifold/App/OrifoldApp.swift` |
| Menu UI | `Orifold/App/UpdateCommands.swift` (+ `AppCommands.swift` insertion) |
| Settings UI | `Orifold/Views/SettingsView.swift` (`updatesSection`, `updateStatusView`, `attemptInstall`) |
| Reopen state source | `Orifold/Engine/RecentsStore.swift`, `Orifold/Models/RecentFileEntry.swift` (`bookmarkData`, `lastPageOpened`) |
| Unsandboxed machinery to reuse | `scripts/install-mac.sh` (quit/replace/verify/relaunch pieces), `Install or Update Orifold.command` (Terminal wrapper pattern) |
| Strings | `Orifold/Resources/Localizable.xcstrings` — every new string ×6 languages via `L10n.string` (leak + coverage tests enforce) |

## 2. Gaps: current vs desired

| # | Desired | Today | Gap |
|---|---|---|---|
| 1 | Preserve on-screen state across update | Preflight blocks unsaved docs; recents remember last page; no reopen-after-update | No "what was open" contract; nothing reopens automatically |
| 2 | Replace old app cleanly | Finder drag by hand | No programmatic replace (sandbox forbids in-process; child processes inherit the sandbox) |
| 3 | Auto-quit old, auto-launch new | User does both | No orchestrated quit → swap → relaunch |
| 4 | Menu flow can download+install with staged UI | Static NSAlerts, check-only | NSAlert can't render progress; no download/install actions |
| 5 | Informative failure states | download/verify failures surfaced in Settings; install failures invisible (happen in Finder) | No install-attempt outcome detection, no retry surface |

## 3. Recommended design (smallest robust, sandbox-honest)

**Transport of the swap: a generated, self-contained updater `.command` opened via
`NSWorkspace.open` (runs unsandboxed in Terminal).** This is the path the repo's verified
plans already endorse (WEBSITE_PLAN §8b / UPDATE_SYSTEM_PLAN §F): LaunchServices-legal, no
privileged helper, no new entitlements, and visibly honest — the user watches the swap
happen instead of the app silently vanishing. Sparkle 2 remains the silent-install endgame
(gated on EdDSA key custody + GUI rehearsal, out of scope here); everything below stays
behind the existing `UpdateController` surface so Sparkle can replace the transport later
without UI changes.

### 3.1 Install orchestration (happy path)

On **Install and Relaunch** (Settings or the new update window):

1. **Preflight** — `documentsBlockingInstall()`; if non-empty, show the save-first prompt
   (existing behavior) and stop.
2. **Preserve state** (new `UpdateReopenManifest`):
   - Write `reopen-manifest.json` (support root, atomic, additive-schema): for every open
     document with a `fileURL`: security-scoped bookmark + path + current page index
     (from the live view model; fall back to `RecentsStore.lastPageOpened`), plus
     `{fromVersion, toVersion, savedAt}`.
   - Belt-and-suspenders: `RecoveryStore.saveCheckpoint(reason: .preUpdate)` with
     `WorkspaceDocument.snapshot()` bytes per open doc — crash-during-update insurance.
   - **Contract (answers "what's missing"):** documents that have never been saved
     (no `fileURL`) cannot be reopened by reference. The preflight already forces
     save-or-close of anything unsaved, so by install time every open doc has a URL and
     clean state. An open-but-clean untitled window is empty by definition → nothing to
     preserve. This contract is what makes restore possible without a new persistence
     layer.
3. **Rollback archive** — `RollbackArchiver.archive(bundleURL: Bundle.main.bundleURL, …)`
   (already implemented + tested; ditto zip into `Rollback/`, prunes to one). This is the
   only sanctioned "old copy left behind".
4. **Write `install-attempt.json`** (updater cache): `{fromVersion, toVersion, dmgPath,
   dmgSHA256, startedAt}` — how the next launch knows whether the install worked.
5. **Record history** — `UpdateHistoryStore.record(from:to:…, launchVerified: false)`.
6. **Generate the updater script** from a bundled template resource into
   `UpdaterCache/orifold-updater.command` (chmod +x), with these values baked in: app PID,
   absolute current bundle path, verified DMG path, expected SHA-256, new version string.
7. **Hand off + quit**: `NSWorkspace.open(script)` → phase `.installing(update)` (brief
   "Installing — Orifold will relaunch itself…" state) → `NSApp.terminate(nil)` (normal
   termination path → sentinel `markCleanExit`, NSDocument review flow as final backstop).

### 3.2 The updater script (template resource, ~80 lines of zsh)

Runs unsandboxed in Terminal; strictly sequential, fails loudly, never deletes user data:

1. Wait for the passed PID to exit (`kill -0` poll, 60 s timeout → abort with message
   "Orifold didn't quit; nothing was changed").
2. **Re-verify** the DMG's SHA-256 against the baked-in digest (closes the
   verify-then-install TOCTOU gap).
3. Refuse unsafe targets: baked bundle path must end in `Orifold.app`, must not be under
   `/Volumes/`, `/private/var/folders/` (app translocation), or the updater cache. If
   refused → fall back message + `open` the DMG for manual drag.
4. `hdiutil attach -nobrowse -readonly`, locate `Orifold.app` in the mount,
   `codesign --verify --deep --strict` on the *new* app.
5. Replace **in place at the running app's location** (`~/Applications` or
   `/Applications` — wherever it actually ran from, per WEBSITE_PLAN §8b reconciliation):
   `rm -rf` old bundle → `ditto` new bundle → `xattr -cr` (quarantine strip) →
   `codesign --verify` the installed copy.
6. `hdiutil detach`; delete the consumed DMG from the cache.
7. `open <installed app>` → relaunch. Print a one-line success message; window closes.
8. Any failure after the old bundle is removed → restore from the rollback zip written in
   3.1(3) (unzip via `ditto -x -k`), then report. The user is never left app-less.

### 3.3 Relaunch: verification + state restore (in `UpdateLaunchCoordinator`)

On `applicationDidFinishLaunching`:

1. If `install-attempt.json` exists:
   - current version == `toVersion` → **success**: flip the history record's
     `launchVerified` (after the existing 30 s healthy grace), delete the marker, run
     `UpdateArtifactCleaner.clean()` (already allowlisted to UpdaterCache/Rollback only).
   - current version == `fromVersion` → **install failed/abandoned**: delete the marker,
     set a pending-failure flag the UI surfaces once ("The update didn't complete. Your
     current version is untouched." + Retry / Reveal Download / Later). Retry re-enters
     3.1 with the still-cached DMG.
2. If `reopen-manifest.json` exists (consume + delete, one-shot): resolve each bookmark
   (`SecurityScopedAccess`), `NSDocumentController.openDocument` each, navigate to the
   saved page index via the existing resume path (`RecentsStore` / `WorkspaceViewModel`
   page-jump). Unresolvable entries (file moved/deleted) are skipped silently — recents
   already shows them as unavailable; never an error dialog on first launch after update.
3. Crash-loop detection (existing sentinel) now has a real rollback artifact + restore
   path to offer — wire the *offer* only if `Rollback/` has a verified archive; restore
   itself reuses the same script mechanism with the archive as source (stretch, step 7).

### 3.4 Menu-driven UI: one Software Update window

`NSAlert.runModal` cannot update mid-flight, so the menu flow gets a small dedicated
**Software Update window** (single-instance SwiftUI `Window` scene, ~considered the calm
Sparkle-style surface). "Check for Updates…" opens it and starts a check. It renders
`UpdateController.phase` directly — the same states Settings shows, via a shared extracted
`UpdateStatusView` component so the two surfaces can't drift:

| Phase | Window shows | Actions |
|---|---|---|
| `.checking` | spinner (Reduce Motion: text only) | — |
| `.upToDate` | "You're up to date — Orifold X" | OK |
| `.updateAvailable` | version, date, size, release-notes link | **Download Update** (default) · Skip This Version · Later |
| `.downloading(_, fraction)` | determinate bar + percent | Cancel *(new: cancellable download)* |
| `.readyToInstall` | "Ready to install. Orifold will save its window list, quit, and relaunch as X.Y.Z." | **Install and Relaunch** (default) · Later |
| `.installing` *(new phase)* | "Installing — Orifold will quit now and reopen itself when finished." | — (auto-quit ~1 s later) |
| `.failed(kind)` | calm headline per kind (download / verification / install / network) + disclosure detail | **Retry** · Open Download Page · OK |

Settings keeps its inline section (unchanged behavior, now delegating to the shared
component). `UpdateAlertPresenter` shrinks to nothing / is deleted — the menu button just
opens the window. Existing keys reused; new keys (~8: installing status, retry, cancel,
install-failed headline, reopen-failure-free copy, window title) ×6 languages.

## 4. Edge cases & failure handling

- **User cancels quit** (NSDocument review dialog appears despite preflight — e.g. a doc
  dirtied in the gap): termination cancelled → script's PID-wait times out → aborts with
  "nothing was changed"; app still running, phase reset to `.readyToInstall`. No damage.
- **Terminal unavailable / .command handler remapped**: `NSWorkspace.open` failure →
  fall back to today's behavior (reveal DMG) + explanatory copy. Never a dead end.
- **Download cancelled / app quits mid-download**: partial file lives in
  `temporaryDirectory` then cache; cleaner's 24 h retention sweeps strays. Cancel action
  invalidates the URLSession task and returns to `.updateAvailable`.
- **Disk full**: archive/ditto failures abort *before* the old bundle is touched (script
  order: verify → mount → replace last). App-side archive failure downgrades to a warning
  (install proceeds, rollback unavailable — recorded in history).
- **Running from a translocated / DMG / non-standard path**: script refuses (3.2 §3) and
  falls back to manual drag — replacing a translocated path is meaningless.
- **Both `~/Applications` and `/Applications` copies exist**: replace only the running
  one; never sweep the other from the updater (that stays an installer-script behavior).
- **Sequential updates** (0.8.6 → 0.8.7 while 0.8.6's DMG still cached): cache is keyed
  `Orifold-<version>.dmg`; a newer available version re-downloads; cleaner prunes the old.
- **Relaunch fails** (`open` errors): script prints the path + "open it from Applications";
  next manual launch still consumes the reopen manifest — restore isn't lost.
- **Reopen-manifest bookmark fails to resolve**: skip silently (file gone/moved) — recents
  UI already communicates unavailability; never block launch.
- **Crash during install after old bundle removed**: script's own rollback restore
  (3.2 §8). Crash *of the script* between rm and ditto is the worst case → next manual
  launch of… nothing. Mitigation: `ditto` the new bundle to a staging dir *beside* the
  target first, then `rm` old + `mv` staged — swap window shrinks to a rename. (Do it this
  way in the script; listed here so Opus implements the stage-then-swap order.)

## 5. Security / verification (before anything is installed)

Already enforced: newer-version-only offers (transport), SHA-256 of DMG vs published
sidecar (downloader, mismatch deleted). Added by this plan:

1. Script **re-verifies** the digest immediately before mounting (TOCTOU close).
2. `codesign --verify --deep --strict` on the new app pre-swap and on the installed copy
   post-swap (ad-hoc era: verifies integrity, not identity — identity pinning
   (Team ID) is explicitly deferred until Developer ID signing lands; note it in the
   script header so it's added at the signing flip, per WEBSITE_PLAN §6 pre-flip work).
3. Quarantine strip only on the freshly-installed bundle, nothing else.
4. The updater script is generated from a **bundled template resource** (code-signed with
   the app) into the updater-owned cache; values are baked via safe substitution (no shell
   interpolation of user-controlled strings; paths single-quoted, digest hex-validated).
5. No `sudo` anywhere; if the target dir isn't writable, fail with a clear message.
6. Downgrades remain impossible via the update path; rollback stays an explicit,
   hash-verified user action.

## 6. Implementation sequence for Opus

Each step compiles + tests green independently; stop at any red.

1. **`UpdatePhase.installing` + cancellable download.** Add the phase case (update
   `availableUpdate`/`isBusy` switches + tests), add `cancelDownload()` (session task
   invalidation) and Cancel wiring. *Accept:* controller tests cover cancel → back to
   `.updateAvailable`, and `.installing` classification.
2. **`UpdateReopenManifest` store** (new file, pattern-copy of `UpdateHistoryStore`):
   write/consume-once/delete, additive schema, atomic; + `install-attempt.json`
   read/write in the same file or sibling. *Accept:* round-trip, consume-once, and
   minimal-JSON-decodes tests (fixture style, matches existing store tests).
3. **Updater script template + generator.** Template as a bundled resource
   (`Resources/orifold-updater.command.template`); generator substitutes PID/paths/digest,
   writes executable script into `UpdaterCache/`. Stage-then-swap order (§4 last bullet),
   rollback-restore branch, PID-wait, refusal guards. *Accept:* unit tests on the
   generator (substitution, quoting, digest validation, refusal of `/Volumes` paths —
   assert on generated text); a bash-level dry-run test executing the script against a
   fake .app tree + fake DMG in a temp dir (`hdiutil` create in test — same pattern as
   RollbackArchive's ditto tests).
4. **Orchestrate install in `UpdateController.installAndRelaunch()`** replacing
   `revealDownloadedUpdateForInstall` (keep the reveal as the fallback path): preflight →
   reopen manifest + recovery checkpoints → rollback archive → attempt marker → history
   record → generate script → open → `.installing` → terminate. *Accept:* controller test
   with mocks driving the full sequence order (spy on a protocol-injected
   "InstallHandOff") without actually terminating.
5. **Launch-side: attempt-outcome detection + reopen.** Extend `UpdateLaunchCoordinator`
   per §3.3 (success → verify+clean; failure → pending-failure flag; manifest → reopen via
   bookmarks + page jump). *Accept:* coordinator logic factored into a pure,
   version-in/decision-out function with tests for success/failed/absent marker; reopen
   resolution logic tested with dead bookmarks (skip, never throw).
6. **Software Update window + shared `UpdateStatusView`.** Extract from SettingsView; new
   `Window` scene + menu button opens it; delete `UpdateAlertPresenter`; add L10n keys ×6.
   *Accept:* RawLocalizationKeyLeak + LocalizationCoverage green; all seven states render
   (state-driven previews/unit-viewable); Settings behavior unchanged.
7. **(Stretch, only if all green)** Wire crash-loop rollback *offer* → same script
   mechanism with the rollback zip as source. Separately committed, separately revertible.

Ship as **v0.8.7** with the usual release ritual (bump ×9 locations, release notes doc,
releases.mdx, README, stats/fallbacks — the v0.8.6 commit is the template).

## 7. Acceptance criteria & verification

Automated (all must pass with the existing 650+ suite):
- Version compare, 304/ETag, checksum, cleanup-safety, preflight suites stay green.
- New: cancel-download, reopen-manifest round-trip/consume-once, script-generator
  substitution + refusal guards, script dry-run swap in temp dir, install-orchestration
  order, launch-outcome decision function, dead-bookmark reopen skip.

Manual (GUI session, the same 0.8.4-reporting trick used for v0.8.5/0.8.6 verification):
1. Install a local build reporting an older version → menu Check for Updates → window
   walks checking → available → Download (live %) → Ready.
2. Open two saved documents on distinct pages + one dirty document → Install and
   Relaunch → save-first prompt lists the dirty doc → save it → install proceeds:
   Terminal shows the swap, app quits, **new version relaunches itself**, both documents
   reopen on their pages. `update-history.json` gains a verified record; `Rollback/`
   holds exactly one zip; consumed DMG gone from cache.
3. Corrupt the cached DMG before Install → script refuses (digest mismatch), old app
   untouched and relaunchable, failure surfaced on next launch with Retry.
4. Kill the app mid-download → relaunch → no partial-file weirdness; check again → clean.
5. Reduce Motion on: no spinner/cross-fade; all states legible as text.
6. All six languages: window + alerts show translated strings (spot-check 2 languages).

---

*Non-goals (unchanged from UPDATE_SYSTEM_PLAN):* Sparkle 2 silent in-place updates (needs
EdDSA custody + GUI rehearsal), delta updates, background auto-download without consent,
privileged helpers. The consent posture stays: nothing downloads or installs without an
explicit user action.
