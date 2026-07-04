# v7 Orifold

## GitHub Release Fields

Tag: `release-v7`

Target: latest commit tagged by `release-v7`

Release title: `v7 Orifold`

Asset to upload: `Orifold.zip`

Automation: `.github/workflows/sync-release-v7.yml` checks `origin/main` every 30 minutes, moves `release-v7` only when `main` has advanced, and then dispatches the release workflow to rebuild the latest v7 asset.

Build the asset with:

```zsh
./scripts/install-mac.sh --package-only --package /tmp/Orifold.zip
```

## Release Notes

# v7 Orifold

**Release:** Latest release
**Release date:** July 4, 2026
**Tag:** [`release-v7`](https://github.com/udhawan97/Orifold/releases/tag/release-v7)

---

## A Bulletproof PDF Engine Underneath

Orifold v7 adds a native, dependency-light [qpdf](https://github.com/qpdf/qpdf) engine (Apache-2.0, statically linked, vendored as a universal `arm64`/`x86_64` library — no external process, no network call) alongside PDFKit and PDFium. It powers four things: repairing corrupt PDFs on import, real AES-256 password protection, a lossless structural compression pass, and a "sanitize for sharing" export option — all gated by a qpdf structural check that now runs before every export leaves the app.

Everything from v6 still works: local-first workspace, one-line installer, searchable OCR, forms, stamps, decorations, compression, protected export, and multi-format export. Version 7 is primarily a **durability and trust release** — it doesn't add new document workflows, it makes the existing ones harder to break and safer to share.

---

## What's New in v7

### Corrupt PDFs Get Repaired, Not Rejected

Files with damaged cross-reference tables or malformed object structures used to fail on import. Orifold now falls back to qpdf's recovery path when PDFKit can't open a file.

- qpdf reconstructs the cross-reference table and repairs damaged objects before Orifold retries the import.
- Recovery is silent when it succeeds — the user just sees their file open.
- Covered by import-stress tests that feed deliberately corrupted PDFs through the real import pipeline.

### Real AES-256 Password Protection

Protected export previously used CoreGraphics' 128-bit RC4/AES path. It now goes through qpdf's R6 encryption handler.

- User and owner passwords, plus print/copy permissions, are set through qpdf's AES-256 (PDF 2.0) encryption parameters.
- Post-export verification still reopens and unlocks the result before handing it back, matching v6's guarantee.

### Sanitize for Sharing

A new export option strips content designed to run automatically or leak information you didn't mean to send.

- Removes catalog-level auto-run actions (`/OpenAction`), embedded JavaScript, and embedded files.
- An opt-in sub-toggle also strips document metadata (author, producer, timestamps).
- Sanitize is now applied consistently on every export path, including the compressed-export path — a gap found and fixed during this release's audit (see below).
- If sanitization can't be completed, export now fails loudly with a clear message instead of silently shipping an unsanitized file.

### Lossless Structural Compression

The existing image-downsampling compression pass is now followed by a qpdf object-stream optimization pass.

- Repacks the PDF's internal object structure losslessly — this catches size wins that image downsampling alone can't, especially on text-heavy PDFs.
- Runs after image compression and before sanitize/encryption in the export pipeline, so gains compound instead of being undone.

### Every Export Is Structurally Validated

Previously, plain unencrypted exports had no post-write validation at all. Every PDF Orifold writes — encrypted or not — now passes a qpdf structural check (`qpdf --check`-equivalent) before it's allowed to reach disk.

---

## Hardening That Happened Along the Way

This release went through an explicit audit pass — one reviewer for user-flow/logic bugs, one adversarial pass hunting crashes and memory-safety issues in the new native engine integration — before merging. What it found and fixed:

- **Sanitize was silently skipped on the compressed-export path.** Checking "Reduce file size" and "Sanitize for sharing" together in the export sheet produced a smaller file that was *not* actually sanitized, with no warning. Fixed by threading the sanitize option through the compression pipeline and making sanitize failures throw instead of silently falling back.
- **A missing signature-conflict guard** on the compressed-export path could let sanitize/encryption options through even when the workspace has a placed digital signature. Fixed to match the guard already used on the plain export path.
- **An undo/redo crash** was found and fixed independently during release verification (see `Orifold/App/AppCommands.swift`, `Orifold/ViewModels/WorkspaceViewModel.swift`).
- The new qpdf C API wrapper (`Orifold/Engine/QPDFService.swift`) was reviewed for pointer-lifetime and concurrency safety; no exploitable issues were found, though two low-severity robustness notes were logged for future hardening (an unnecessarily conservative 2 GB import-size guard, and undocumented reliance on Swift `Data`'s retain behavior across a C API boundary).

---

## Install

```zsh
curl -fsSL https://raw.githubusercontent.com/udhawan97/Orifold/main/install.sh | zsh
```

The installer downloads the latest `Orifold.zip`, installs `Orifold.app` to `~/Applications`, creates Desktop commands for launch/update and uninstall, clears quarantine metadata, and opens Orifold.

Direct download: [`Orifold.zip`](https://github.com/udhawan97/Orifold/releases/latest/download/Orifold.zip)

Homebrew users can install the same prebuilt release app:

```zsh
brew tap udhawan97/orifold https://github.com/udhawan97/Orifold
brew install --cask udhawan97/orifold/orifold
```

The cask clears download quarantine after installation, matching the one-line installer. Release builds are fully Gatekeeper-trusted once the release workflow is configured with Apple Developer ID signing and notarization secrets.

---

## Update

After installing v7, double-click `Orifold.command` on the Desktop. It checks the latest release before opening the app.

---

## Uninstall

Double-click `Uninstall Orifold.command` on the Desktop.

To keep Orifold app support, preferences, caches, and sandbox data:

```zsh
curl -fsSL https://raw.githubusercontent.com/udhawan97/Orifold/main/scripts/uninstall-mac.sh | zsh -s -- --keep-user-data
```

---

<details>
<summary>Developer details</summary>

### New Dependency

`Packages/QPDFBinary` vendors a universal (`arm64` + `x86_64`) static build of [qpdf](https://github.com/qpdf/qpdf) 12.3.0 (Apache-2.0) plus [libjpeg-turbo](https://github.com/libjpeg-turbo/libjpeg-turbo) 3.1.0 (BSD/IJG/zlib, a mandatory qpdf build dependency), built with qpdf's native crypto provider so there is no external OpenSSL/GnuTLS dependency. The binary is committed directly to the repo as a local `.xcframework` binary target, following the same SPM pattern as `Packages/PDFiumBinary`. See `Orifold/Resources/THIRD-PARTY-NOTICES.md` for license text.

### Verification

```zsh
plutil -lint Orifold/Resources/Info.plist
plutil -lint Orifold/Resources/Orifold.entitlements
zsh -n install.sh
zsh -n scripts/install-mac.sh
zsh -n scripts/uninstall-mac.sh
zsh -n scripts/install-mac.command
zsh -n "Install or Update Orifold.command"
zsh -n "Uninstall Orifold.command"
zsh -n "Install or Update Orifold.app/Contents/MacOS/OrifoldInstaller"
plutil -lint "Install or Update Orifold.app/Contents/Info.plist"
swift build
swift test
xcodebuild build -quiet -project Orifold.xcodeproj -scheme Orifold -destination 'generic/platform=macOS' CODE_SIGNING_ALLOWED=NO
xcodebuild test -quiet -project Orifold.xcodeproj -scheme Orifold -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
./scripts/install-mac.sh --package-only --package /tmp/Orifold.zip
```

All of the above passed cleanly on this release: 281 tests, 0 failures; the packaged app was unpacked and confirmed to launch, report `CFBundleShortVersionString v7`, and have qpdf symbols statically linked into the executable.

### Git Summary

Feature range used for the product-change summary: `release-v6..HEAD`

Summary:

```text
97 files changed, 13628 insertions(+), 500 deletions(-)
```

Commits:

- `0abbaef` Update README and architecture diagrams for v7 qpdf engine
- `b33a8ff` Fixing undo crash
- `9c301e2` Add qpdf engine: repair, real AES-256 encryption, sanitize, export validation (merge)

Notable files:

- `Orifold/Engine/QPDFService.swift`
- `Orifold/Engine/PDFKitEngine.swift`
- `Orifold/Engine/PDFEncryptionService.swift`
- `Orifold/Engine/PDFCompressionService.swift`
- `Orifold/Models/WorkspaceExportOptions.swift`
- `Orifold/ViewModels/WorkspaceViewModel.swift`
- `Orifold/Views/ContentView.swift`
- `Orifold/App/AppCommands.swift`
- `Packages/QPDFBinary/Package.swift`
- `Tests/OrifoldTests/QPDFServiceTests.swift`
- `Tests/OrifoldTests/ImportStressTests.swift`
- `docs/assets/orifold-v3-architecture-diagram.svg`

### Release Checklist

- Confirm `Orifold/Resources/Info.plist` is `v7` / `7`.
- Confirm `project.yml` is `v7` / `7`.
- Run the verification commands above.
- Confirm the `release-v7` tag points at `origin/main` locally and on `origin`.
- Confirm the GitHub release for `release-v7` is marked latest and contains `Orifold.zip`.

</details>
