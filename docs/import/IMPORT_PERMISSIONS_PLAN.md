# Import & Permission Hardening Plan

Status: **Implemented.** Sections 1–10 below were built as specified — see
`Orifold/Engine/SecurityScopedAccess.swift`, `DocumentImportCoordinator.swift`,
`ImportLog.swift`, the `Orifold.entitlements` bookmarks entitlement, the
classified-error recovery dialog in `ContentView.swift`, and
`Tests/OrifoldTests/ImportPermissionTests.swift`. This document is kept as the
design record and rationale, not a pending spec.

Trigger: a user hit a blocking, non-recoverable dialog when reopening a file:

> **Import Error** — The document "edited.pdf" could not be opened. You don't have permission.

---

## 1. Root cause (confirmed by reading the code)

### The exact error path

`edited.pdf` was almost certainly a file **Orifold itself exported** earlier
(workspaces export/save as PDF — `WorkspaceDocument.writableContentTypes == [.pdf]`,
and the save panels default to names like `…-signed.pdf` / `… .pdf`). The user then
tried to reopen it from the **Recently Viewed** list on the empty-state screen.

The reopen goes through this chain:

1. [`RecentFilesSection.open()`](../../Orifold/Views/RecentFilesSection.swift#L288) →
   `store.resolvedURL(for: entry)` → `onOpen(url)`.
2. `onOpen` is [`EmptyStateView.openRecentFile(_:)`](../../Orifold/Views/EmptyStateView.swift#L357),
   which calls `NSDocumentController.shared.openDocument(withContentsOf: url, display: true)`
   and, on failure, wraps the raw Cocoa error **verbatim**:
   ```swift
   viewModel.importError = WorkspaceViewModel.ImportError(
       fileName: url.lastPathComponent,
       message: error.localizedDescription)   // ← "…could not be opened. You don't have permission."
   ```
   The `ImportError` struct is what renders the **"Import Error"** title. So the vague
   message is a Cocoa `NSFileReadNoPermissionError` (error 257) surfaced with no
   classification, no recovery actions, and no cleanup of the offending recent entry.

### Why permission was actually denied

The app is **sandboxed** with a minimal entitlement set
([`Orifold.entitlements`](../../Orifold/Resources/Orifold.entitlements)):

```xml
com.apple.security.app-sandbox                          = true
com.apple.security.files.user-selected.read-write       = true
```

**There is no `com.apple.security.files.bookmarks.app-scope` entitlement** (confirmed
absent from both the entitlements file and `project.yml`). Yet the recents layer is
built entirely on **security-scoped** bookmarks:

- [`RecentsStore.upsert`](../../Orifold/Engine/RecentsStore.swift#L162) creates them with
  `try? url.bookmarkData(options: .withSecurityScope)`.
- [`RecentsStore.resolvedURL`](../../Orifold/Engine/RecentsStore.swift#L119) resolves them with
  `options: [.withSecurityScope]`.

Without the app-scope bookmarks entitlement, **security-scoped bookmark creation
silently fails** — `bookmarkData(options:.withSecurityScope)` throws, the `try?`
swallows it, and `RecentFileEntry.bookmarkData` is stored as `nil`. `resolvedURL`
then falls through to:

```swift
return FileManager.default.fileExists(atPath: entry.path) ? entry.url : nil
```

i.e. a **raw path URL that carries no sandbox permission across launches**. The file
exists on disk, so this returns a URL — but the sandbox has no grant for it, so
`NSDocumentController.openDocument` (and equally `Data(contentsOf:)` on the in-app
import path) fails with error 257.

Even in the same session, `resolvedURL` returns a URL but never calls
`startAccessingSecurityScopedResource()`, and the caller (`openRecentFile`) doesn't
either — so even a *correctly* resolved scoped URL would fail to read.

### Two independent defects, one symptom

1. **Wrong/missing entitlement → bookmarks never persist.** The self-healing recents
   layer is effectively dead code in the shipped sandbox; every relaunch reopen of a
   file that wasn't just user-selected is a permission failure waiting to happen.
2. **No security-scope lifecycle at the recents open call site.** `resolvedURL`
   hands back a URL without starting access; `openRecentFile` reads it without a
   `start/stop` bracket.

The in-app importer path (`WorkspaceViewModel.importDocument`) *does* bracket access
correctly ([WorkspaceViewModel.swift#L816](../../Orifold/ViewModels/WorkspaceViewModel.swift#L816)),
which is why **fresh** Add-Files/drag-drop imports work — those URLs come straight
from `NSOpenPanel`/drop and carry a live grant. The failure is specific to
**reopening across the permission boundary** (relaunch, or a recents/NSDocument reopen
of an exported file).

### Contributing issues found while auditing

- **Two divergent open pipelines.** Recents "open" routes through
  `NSDocumentController` (`EmptyStateView.openRecentFile`), while Add-Files / drag-drop
  / folder import route through `WorkspaceViewModel.importFiles`. They have *different*
  error handling, different (or no) security-scope handling, and different type
  whitelists. Any fix must unify them behind one handler.
- **`RecentsStore.isAvailable`** checks only `fileExists(atPath:)`
  ([L139](../../Orifold/Engine/RecentsStore.swift#L139)) — it reports a file as available
  even when the sandbox can't read it, so the UI never marks the entry as needing
  reselection.
- **Exported files are not bookmarked.** `writeExportData` /`recordOpen` capture no
  durable access token for the user's chosen export destination, so the exported PDF
  can't be reopened later without re-selection.
- **No structured logging exists** anywhere in the target (`grep` for `OSLog`/`Logger`
  returns nothing), so these failures are invisible in diagnostics.

---

## 2. Deliverables (what the implementation pass must produce)

1. Correct entitlements + a **central security-scoped access layer**.
2. A single **`DocumentImportCoordinator`** every entry point funnels through.
3. **Classified errors** with **recovery actions** (not OK-only dead ends).
4. **Self-healing recents** (mark/removable/no retry loop) + durable export bookmarks.
5. **First-run access guidance** (only if scoped access proves insufficient — see §7).
6. **Structured, privacy-safe logging.**
7. The **regression-test matrix**.

---

## 3. Fix the sandbox permission model (foundation — do first)

### 3.1 Entitlements

Add to [`Orifold.entitlements`](../../Orifold/Resources/Orifold.entitlements) **and**
mirror in `project.yml` so `xcodegen` regenerates it:

```xml
<key>com.apple.security.files.bookmarks.app-scope</key>
<true/>
```

This is the entitlement that actually makes `.withSecurityScope` bookmark
create/resolve succeed in the sandbox. **Without it, every other change here is
cosmetic.** Do *not* add Full Disk Access or broad temporary-exception entitlements —
scoped access is sufficient for the file-picker + bookmark model (see §7).

Verify after building: confirm `codesign -d --entitlements :-` on the built `.app`
shows the new key, and that a recent file reopens after a full quit + relaunch.

### 3.2 Central access helper — `SecurityScopedAccess`

New file `Orifold/Engine/SecurityScopedAccess.swift`. One place that owns the
`start`/`stop` lifecycle so no call site can forget the `defer`:

```swift
enum SecurityScopedAccess {
    /// Runs `body` with the URL's security scope active, always balancing stop.
    static func withAccess<T>(to url: URL, _ body: (URL) throws -> T) rethrows -> T
    static func withAccessAsync<T>(to url: URL, _ body: (URL) async throws -> T) async rethrows -> T

    /// Create a durable app-scope bookmark (nil + logged on failure).
    static func makeBookmark(for url: URL) -> Data?

    /// Resolve, reporting staleness; refreshes and returns a new bookmark when stale.
    static func resolve(_ data: Data) -> (url: URL, isStale: Bool, refreshed: Data?)?
}
```

Rules the helper enforces:
- Always `startAccessingSecurityScopedResource()` **before** any read/write and
  `stop…` in `defer`, even on the throwing path.
- Treat a `false` return from `start…` as "not scoped" (a plain in-sandbox path) —
  not an error by itself — but log it.
- Bookmarks are created with `.withSecurityScope` and resolved with
  `[.withSecurityScope]`, detecting `bookmarkDataIsStale` and refreshing.

Migrate existing scope handling to route through this helper:
`WorkspaceViewModel.importDocument`/`addFileSynchronously` (already bracket, but
should share the helper), and everywhere in `RecentsStore`.

### 3.3 Make the recents open path actually hold the scope

`RecentsStore.resolvedURL` must not hand back a bare URL. Options (pick per call
site): return the URL **and** the started access token, or better — expose
`RecentsStore.openResolvedURL(for:) { url in … }` that keeps the scope active for the
duration of the open. `EmptyStateView.openRecentFile` and
`RecentFilesSection.open()` switch to it and route through the coordinator (§4),
not directly to `NSDocumentController`.

---

## 4. Centralized import handler — `DocumentImportCoordinator`

New file `Orifold/Engine/DocumentImportCoordinator.swift`. **Every** entry point calls
this; no button opens/reads a file on its own anymore.

Entry points that must be migrated (audited list):

| Source | Current site | Notes |
|---|---|---|
| Open File (menu) | `AppCommands.AddFilesCommandButton` L52 | `NSOpenPanel` → coordinator |
| Add Files (empty state) | `EmptyStateView` L304 | `NSOpenPanel` → coordinator |
| Add Folder (menu) | `AppCommands.AddFolderCommandButton` L71 | folder scope + bookmark |
| Folder import (empty state) | `EmptyStateView` folder path | shares folder logic |
| Drag & drop | `ContentView.handleDrop` L559 / `ImportDropDelegate` L1598 | already copies temp drops |
| Open Recent | `RecentFilesSection.open` L288 / `EmptyStateView.openRecentFile` L357 | **the failing path** |
| NSDocument open / Finder double-click / reopen last session | `WorkspaceDocument.init(configuration:)` L135 | classify errors here too |
| Export-then-reopen | export sites in `WorkspaceViewModel` (L3758+, L3917+, L4237+) | persist export bookmark |
| Add file (programmatic) | `WorkspaceViewModel.addFile` L676 | route through coordinator |

Coordinator responsibilities (in order):

```
func open(_ request: ImportRequest) async -> ImportOutcome
```
1. **Normalize** the source to a URL (or in-memory data for drops).
2. **Type gate** against the single whitelist (`WorkspaceDocument.importableContentTypes`,
   §6) *before* touching the parser — fail fast with `.unsupportedType`.
3. **Acquire scope** via `SecurityScopedAccess.withAccess`.
4. **Pre-flight validate** (§6): exists, readable, size sane, iCloud-downloaded.
5. **Parse** via `DocumentImportConverter` (unchanged engine).
6. On success: attach + `RecentsStore.recordOpen` with a **freshly created bookmark**.
7. On failure: return a **classified** `ImportFailure` (§5) — never a raw
   `localizedDescription`.
8. **Log** a structured record either way (§8).

The coordinator returns a typed outcome; the *view layer* decides how to present it,
but the classification + recovery actions are computed centrally so every surface is
consistent.

---

## 5. Error classification + recovery UX

Replace `ImportError { fileName, message }` (a bare string) with a classified enum
carrying **suggested actions**. Add to `WorkspaceViewModel` (or a shared model):

```swift
enum ImportFailureKind {
    case permissionDenied        // Cocoa 257 / scope not granted
    case fileMissing             // moved / renamed / deleted (fileExists == false)
    case unsupportedType
    case corruptOrEncrypted      // parser failed / needs password (non-prompt case)
    case iCloudNotDownloaded     // ubiquitous item still downloading
    case exportTempMissing       // edited/exported file vanished
    case staleBookmark           // resolved stale & re-resolve failed
    case tooLarge(Int64)
    case unknown(String)
}
```

Classification rules:
- Map `NSCocoaErrorDomain` **257** (`NSFileReadNoPermissionError`) and a `false`
  `startAccessingSecurityScopedResource()` → `.permissionDenied` or `.staleBookmark`
  (stale if the entry had a bookmark that resolved stale).
- Map **260** (`NSFileNoSuchFileError`) / `!fileExists` → `.fileMissing`.
- Use `URLResourceValues.ubiquitousItemDownloadingStatus` — if not `.current`,
  classify `.iCloudNotDownloaded` **before** attempting the read.
- Existing `DocumentImportConverter.ConversionError` cases already map cleanly
  (`unsupportedType`, `passwordProtected`, `unreadableDocument`, size) — reuse
  `PDFKitEngine.userMessage` for the message text, but wrap in the kind.

User-facing messages (localize via `Localizable.xcstrings`):

| Kind | Message |
|---|---|
| permissionDenied | "Orifold no longer has permission to access this file. Please reselect it." |
| fileMissing | "This file was moved, renamed, or deleted." |
| unsupportedType | "This file type is not supported yet." |
| corruptOrEncrypted | "This PDF may be damaged or password-protected." |
| iCloudNotDownloaded | "This file is stored in iCloud and may need to finish downloading first." |
| exportTempMissing | "The edited file could not be found. Please export again." |
| staleBookmark | "Access expired. Please choose the file again." |

**Recovery actions** (buttons), shown contextually — never OK-only for a recoverable
kind:

- `Choose File Again` — reopens `NSOpenPanel` scoped to that file, re-imports, and
  updates the recent entry's bookmark. (permissionDenied, staleBookmark, fileMissing,
  exportTempMissing)
- `Grant Folder Access` — opens a directory `NSOpenPanel` at the file's parent,
  persists a **folder** bookmark, retries. (permissionDenied when many files in one
  folder are affected)
- `Show in Finder` — only when `fileExists` is true.
- `Remove from Recents` — calls `RecentsStore.remove(id:)`; shown for any
  recents-originated failure.
- `Cancel` — always available; returns to intro/dashboard, never re-triggers.

Implementation: the current `.alert(item: $importError)` in the views must become a
dialog that renders `failure.actions`. No path may loop: after "Choose File Again"
fails again, downgrade to a single non-modal status, don't re-present the same modal.

---

## 6. Unified type whitelist + PDF pre-flight validation

- **Single source of truth:** `WorkspaceDocument.importableContentTypes`
  ([L82](../../Orifold/Document/WorkspaceDocument.swift#L82)) is already used by
  `NSOpenPanel`, drops, and NSDocument. The coordinator must reuse it — do **not**
  introduce a second list. Audit that `AppCommands`/`EmptyStateView` panels all call
  `configureImportOpenPanel` (they do today) and that the coordinator gates on the
  same set before parsing.
- **PDF pre-flight** (before handing to the parser), in order, each producing a
  classified failure:
  1. `fileExists` → `.fileMissing`
  2. iCloud download status current → else `.iCloudNotDownloaded`
  3. security scope acquired → else `.permissionDenied`
  4. `fileSize` within `maxImportBytes` → else `.tooLarge` (reuse existing check in
     `PDFKitEngine.validateByteCount`)
  5. `isReadableFile(atPath:)`
  6. parser loads (with existing qpdf repair fallback) → else `.corruptOrEncrypted`
  7. `isLocked` → existing password-prompt flow (unchanged — keep
     `enqueuePasswordImport`).
- Unsupported types must fail at step 0 with `.unsupportedType`, never reaching a
  parser-level error.

---

## 7. First-run / startup access guidance (conditional)

Prefer **scoped access** — with §3 done, the file-picker + app-scope-bookmark model
covers Open, drag-drop, recents, and export-reopen **without** any broad prompt. So:

- **Do not** add a first-run permission wall by default. The picker grant is enough.
- Add first-run guidance **only** for the folder-import convenience: a lightweight,
  dismissible empty-state affordance — "Choose Folder" / "Continue with File Picker" —
  that, if the user picks a folder, stores a folder bookmark so subsequent scans don't
  re-prompt. No modal on every launch; show once, respect a "don't show again" flag in
  `UserDefaults`.
- Full Disk Access is **not** required for any current feature; do not instruct users
  toward it. If a future feature genuinely needs it, show the
  `System Settings → Privacy & Security → Full Disk Access` steps *at point of use*,
  not at startup.

---

## 8. Structured, privacy-safe logging

No logging exists today. Add `Orifold/Engine/ImportLog.swift` wrapping `OSLog`
(`Logger(subsystem: "com.ud.Orifold", category: "import")`). Log one record per import
attempt:

- `source` — openPanel | dragDrop | recent | folder | sessionRestore | exportReopen
- `fileExtension` (extension only — **never** the full path or filename stem)
- `securityScopeGranted` (Bool)
- `bookmarkStale` (Bool?)
- `fileExists` / `isReadable`
- `parserResult` — ok | repaired | failed
- `errorDomain` + `errorCode` (numbers, not user strings)

Never log file contents. In **user-facing** UI show only `lastPathComponent`, never
full paths.

---

## 9. Export / reimport protection

- Continue writing exports to the user-chosen `NSSavePanel` URL (already atomic-safe
  via `writeExportData`). After a successful write, **create and persist an app-scope
  bookmark** for that destination (via `SecurityScopedAccess.makeBookmark`) so the
  exported file can be reopened later without reselection.
- `recordOpen`/`recordVisit` for exported files must store that bookmark, not just the
  path — this is what closes the `edited.pdf` loop.
- After export, verify the final file `exists && isReadable` before showing
  `ExportSuccess`; the success panel already offers "Show in Finder" — keep it, and it
  must reveal the verified final path.
- Never treat a `/tmp` / temporary edited artifact as a durable recent. If an edited
  file only lives in a temp dir, do not add it to recents; if it's later missing,
  classify `.exportTempMissing`.

---

## 10. Regression test matrix

Add/extend tests under `Tests/OrifoldTests/`. Existing relevant files:
`ImportStressTests.swift`, `FolderImportOrchestratorTests.swift`,
`RecentFileEntryTests.swift`, `SourceDocumentRoundTripTests.swift`.

Because much of the real failure is sandbox/entitlement behavior that unit tests can't
fully exercise, split into **automatable** and **manual** matrices.

Automatable (logic-level, injectable `FileManager`/access shim):
- Open PDF via file picker (happy path through coordinator).
- Drag/drop PDF (provider → temp copy → import).
- Open recent after file moved/deleted → `.fileMissing`, entry marked unavailable,
  "Remove from Recents" removes it.
- Stale bookmark → `.staleBookmark`, re-resolve refreshes and self-heals path.
- Unsupported file type → `.unsupportedType` **before** parser.
- Corrupted PDF → `.corruptOrEncrypted` (with qpdf repair attempted first).
- Password-protected PDF → routes to password prompt, not an error dialog.
- Permission revoked (simulate `start…` returning false) → `.permissionDenied`,
  recovery actions present, **no repeat loop**.
- Export PDF then reopen via stored bookmark → success.
- iCloud-not-downloaded status → `.iCloudNotDownloaded` without attempting read.
- Type-whitelist parity: every entry point gates on the *same*
  `importableContentTypes`.

Manual (checklist in PR description — sandbox required):
- Open from iCloud Drive, Downloads, Desktop, Documents, an external drive, a network
  share.
- Full quit + relaunch, then reopen a recent (the original repro) — must succeed.
- App relaunch restoring last session without a permission loop.
- Entitlement present in the built `.app` (`codesign -d --entitlements`).

---

## 11. UX quality bar (acceptance criteria)

- No generic "Import Error" unless truly unclassifiable.
- No OK-only dead-end dialog for any recoverable permission issue.
- No repeated launch popups; first-run guidance shows at most once.
- No crash when access fails — every failure is a typed outcome.
- User can always Cancel back to the intro/dashboard.
- Recents self-heal: unavailable entries are marked, removable, and not retried
  endlessly (`isAvailable` must reflect *readability*, not just existence).

---

## 12. Implementation order (for the follow-up pass)

1. **§3.1 entitlement** + rebuild + confirm a relaunch reopen works. (Highest-leverage;
   likely fixes the reported bug on its own.)
2. `SecurityScopedAccess` helper (§3.2) + fix recents open scope (§3.3).
3. `DocumentImportCoordinator` (§4) + migrate all entry points.
4. Error classification + recovery dialog (§5), unified whitelist + pre-flight (§6).
5. Export bookmarks (§9), logging (§8), first-run folder guidance (§7).
6. Tests (§10), then the manual matrix before merge.

**Do not merge until every import / recents / export-reopen flow in §10 passes.**
