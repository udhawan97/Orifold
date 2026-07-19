# Orifold

Local-first PDF workspace for macOS 14+. SwiftUI + PDFium/qpdf. No network calls for
document processing.

**Read [CONTEXT.md](CONTEXT.md) first** — the domain glossary (workspace, member, page ref,
byte lanes, replay, bake, bake stamp, imposition, sanitize). Its vocabulary is load-bearing
and spans files. This file covers mechanics; CONTEXT.md covers meaning.

## Commands

```bash
swift build && swift test          # what ships; ~900 tests, XCTest only
swift build -c release             # REQUIRED after touching @_silgen_name bindings
swift test --filter PDFSmokeTests  # fast smoke
swiftlint lint --quiet
xcodegen generate                  # after ANY project.yml change; commit the result
npm run dev --prefix docs-site     # Astro docs, port 4321 (see .claude/launch.json)
```

## Two build systems, and CI enforces they agree

- `Package.swift` (SwiftPM) is what **ships** — `scripts/install-mac.sh` runs
  `swift build -c release` and hand-assembles the `.app`. `xcodebuild` never builds a release.
- `project.yml` → `xcodegen generate` → `Orifold.xcodeproj` is for **Xcode and the Xcode test
  target only**.

Both `Orifold.xcodeproj/project.pbxproj` and `Orifold/Resources/Info.plist` are **generated
files committed to git**. CI regenerates and runs `git diff --exit-code` on them.

- **Never hand-edit `Info.plist`** — edit `project.yml`, regenerate, commit.
- **Any new resource or SPM dependency goes in BOTH manifests**, then regenerate. Missing one
  ships the resource dead in the Xcode build.
- `Resources/Fonts` is special: `.copy(...)` in Package.swift, `type: folder` in project.yml.
  A plain Xcode group flattens `Fonts/AFM/` and `FontRegistrar` silently returns nil.
- **Never use `Bundle.module`** — SPM's accessor `fatalError`s and once crash-looped shipped
  builds. Copy the non-trapping resolver in `L10n.swift`, `FontRegistrar.swift`, or
  `SampleDocument.swift`.

## Engine split

| Engine | Owns | Never |
|---|---|---|
| PDFKit | display, selection, search, print, sourcing annotations/forms | rebuilding page content |
| PDFium | text geometry, object edits, compression, imposition, `SaveAsCopy` | — |
| qpdf | repair, AES-256, sanitize, re-serialize the object graph | rendering or editing content |

- Prefer `FPDFText` over PDFKit for text extraction — PDFKit varies across SDK versions.
- `PDFSerializer.data(from:)` is the only sanctioned way to get bytes out of a `PDFDocument`;
  `dataRepresentation()` returns nil for linearized/unlocked-encrypted PDFs.
- Import prefers original bytes over PDFKit re-serialization, which destroys text layers.

### C interop

- Every PDFium call holds the process-wide `pdfiumLock`, then
  `FPDF_InitLibrary()` / `defer { FPDF_DestroyLibrary() }`. Per-call init is safe *only*
  because the lock serializes it.
- **Two `@_silgen_name` bindings of one C symbol must have byte-identical Swift signatures** —
  otherwise whole-module optimization merges them and breaks `swift build -c release`. Reuse
  existing bindings (some are `internal` deliberately). Prefixes: `poe_` object editing,
  `imp_` imposition.
- `FPDFPage_GenerateContent` drops path colors — every caller must first run
  `poeTouchPathColorsForGenerateContent` or paths re-emit black.

## Concurrency

No custom actors. View models are `@MainActor @Observable`; engines are `enum` namespaces with
static methods, called synchronously under the lock.

- `Task { }` inside a `@MainActor` func **inherits MainActor** — use `Task.detached` for
  anything long-running (OCR, signing, Vision).
- `PDFPage`/`PDFDocument` aren't `Sendable`; cross the boundary with a
  `final class …Box: @unchecked Sendable` written on one thread, read after the task joins.

## Localization — test-enforced, will fail your build

~1,180 keys × 6 languages (en, es, fr, hi, ja, zh-Hans) in `Localizable.xcstrings`.

- Every user-facing string goes through `L10n` **and** gets all 6 translations.
  `LocalizationCoverageTests` fails on gaps.
- **Never pass a bare dotted key to `Text`/`Button`/`navigationTitle`/etc.** —
  `RawLocalizationKeyLeakTests` regex-scans for this and fails.
- Use `L10n.format(key, args…)`, not `Text("key \(arg)")` — interpolation produces a
  compiler-derived key that won't match the catalog.
- In `body`, pass the view's own `@Environment(\.locale)` into `L10n.string(_:locale:)`, or the
  view won't re-render on language change. AppKit surfaces observe
  `orifoldLanguageDidChange` instead.
- `Workspace.title` defaults to the literal English `"Untitled Workspace"` on purpose —
  auto-rename string-compares it.

## Hand-sync hazards

- **Keyboard shortcuts** — `ShortcutRegistry.ShortcutChord` is the single source of truth;
  binding sites derive from it. Never hand-type `.keyboardShortcut("b", modifiers: .command)`.
- **New file type** — `project.yml` `CFBundleDocumentTypes` + `UTType` in `WorkspaceDocument` +
  `SourceDocumentPayload` mapping + a `DocumentImportConverter` branch.
- **Version bump** — `project.yml`, `README.md` (3 spots), `docs-site/src/data/stats.json`,
  `docs-site/src/lib/release.ts`.
- **Test/file/line counts** — `README.md` (3 spots) + `docs-site/src/data/stats.json`, which
  feeds the docs site. Regenerate per `docs-site/AGENTS.md`; nothing enforces them and the two
  have silently desynced before. Counts in *this* file stay approximate so they can't rot.
- **Undo/redo menu** — read `viewModel.undoManager` (not `@Environment(\.undoManager)`, nil in
  `.commands`) and touch `structureRevision` to force re-evaluation.

## Invariants that span files

- **Byte lanes** — a document-level change must apply to every present lane independently.
  Go through `mutateMemberBytes`; it's atomic and registers one undo step.
- **Bake stamps** — scan annotations via `BakeStamp.userAnnotations(on:)`, never
  `page.annotations`, or engine bookkeeping counts as user markup.
- **`BakedPDFData` is a type-level precondition** — imposition on unflattened bytes silently
  drops annotations and still produces a valid PDF. No throw catches it.
- **Export order is load-bearing**: capture attachments → reconcile → assemble+flatten →
  compress → impose → write bookmarks → re-inject attachments → sanitize → encrypt.
  Sanitize runs *after* re-injection on purpose, and throws rather than falling back.
- **Bookmarks are written once, late** — `/Outlines` is applied after imposition and
  *before* attachment re-injection. Re-serializing a parsed outline can slip every
  destination forward a page, so one carried down from the assembly arrives pointing at
  the wrong pages; and the write is a PDFKit round-trip, which drops embedded files, so
  it cannot run after re-injection. Capture reads the live member documents, never
  `snapshot.memberPDFData` — those bytes are already shifted. Imposition skips the write:
  N-up merges pages, so no index mapping is faithful.
- **Operations, not bytes, are the source of truth** — never trust stored bytes on open.
- **Sandbox** — all file reads go through `SecurityScopedAccess.withAccess(to:)`.

## Testing

XCTest only (no swift-testing). `final class <Subject>Tests: XCTestCase`, long
behavior-describing method names. Fixtures in `Tests/OrifoldTests/Support/`.

- **Never assert on `PDFPage.string`** — Xcode 16.4 CI quirk. Use `FPDFText` or
  thumbnail-brightness checks.
- `OrifoldTests.swift` (9.2k lines) is a legacy catch-all; new work gets its own file.

## Navigation

`WorkspaceViewModel.swift` (8.5k) and `ReadingCanvas.swift` (5.3k) are the giants — navigate by
`// MARK: -`. Engines are `enum` namespaces under `Orifold/Engine/`.
`docs/*_PLAN.md` are records of **shipped** work, not pending specs.
