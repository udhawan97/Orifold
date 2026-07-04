# v5 Orifold

## GitHub Release Fields

Tag: `release-v5`

Target: latest commit tagged by `release-v5`

Release title: `v5 Orifold`

Asset to upload: `Orifold.zip`

Build the asset with:

```zsh
./scripts/install-mac.sh --package-only --package /tmp/Orifold.zip
```

## Release Notes

# v5 Orifold

**Release:** Latest release  
**Release date:** July 1, 2026  
**Tag:** [`release-v5`](https://github.com/udhawan97/Orifold/releases/tag/release-v5)

---

## A Cleaner Save, Export, and Editing Release

Orifold v5 tightens the everyday workflow around saving, exporting, and small editing details. Normal macOS Save/Save As now stays PDF-first, while the export menu keeps the broader formats users expect when they need DOCX, Markdown, text, HTML, image pages, or print output.

The release also preserves original source data for supported non-PDF imports, adds safer same-format export behavior, covers the source round trip with focused tests, and includes a more organized toolbar plus an optional in-app helper.

## Install

```zsh
curl -fsSL https://raw.githubusercontent.com/udhawan97/Orifold/main/install.sh | zsh
```

Direct download: [`Orifold.zip`](https://github.com/udhawan97/Orifold/releases/latest/download/Orifold.zip)

The installer downloads the latest `Orifold.zip`, installs `Orifold.app` to `~/Applications`, creates Desktop commands for launch/update and uninstall, clears quarantine metadata, and opens Orifold.

Homebrew users can install the same prebuilt release app through the repository cask:

```zsh
brew tap udhawan97/orifold https://github.com/udhawan97/Orifold
brew install --cask udhawan97/orifold/orifold
```

---

## What's New in v5

### PDF-First Save Path

- Standard macOS Save and Save As write flat PDF output by default.
- The previous `.orifoldproj` workspace save type has been removed from app metadata and installer checks.
- Existing export/share choices remain available for users who need another output format.

### Source-Aware Export

- Unchanged same-format exports can return original bytes for supported source documents.
- Source payload metadata is embedded into saved PDFs so reopened documents can recover safe export context.
- `.doc`, `.odt`, and `.rtf` join the export menu.
- Text-like formats can map unique inline edits back into the source export.
- Ambiguous, unmapped, PDF-only, or lossy package-format edits fail clearly instead of quietly producing misleading files.

### Inline Text Editing Polish

- Choosing the same font size no longer counts as a style change.
- Real edits preserve at least the original detected text bounds, reducing collapsed geometry after style-only interactions.
- Regression tests cover no-op Done behavior, same-size style changes, and live inline edits across supported source samples.

### Toolbar and Optional Helper Polish

- Search, contents, signature, edit, annotation, export, guide, and inspector controls are grouped more deliberately in the toolbar.
- Foldy, the optional Orifold helper, reacts to common actions and can be hidden from the app menu or popover.
- Helper bubbles avoid blocking normal canvas input.

### Installation Choices

- The original one-line installer remains available and still creates Desktop launch/update and uninstall commands.
- A tap-compatible Homebrew cask is included for users who prefer `brew install --cask`.
- README install, update, and uninstall sections now document both routes.

---

## Update

After installing v5, double-click `Orifold.command` on the Desktop. It checks the latest release before opening the app.

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

### Git Summary

Feature range used for the product-change summary: `release-v4..HEAD`

Summary:

```text
11 commits changed 22 files, with 2286 insertions and 313 deletions.
```

Commits:

- `HEAD` Extend CodeQL timeout
- `bc17433` Normalize Orifold install links
- `97c175b` Add optional Homebrew cask
- `b92d4f6` Polish release README and CI test
- `f709d96` Stabilize CI plist validation
- `25ee541` Prepare release v5
- `ad00fd9` Inline coverage +
- `cf28ee5` Cleaning up bugs on export
- `0235c02` UI header fixes
- `8908ce2` Adding UI pet
- `bf04db0` UI fixes

Notable files:

- `Orifold/Document/WorkspaceDocument.swift`
- `Orifold/ViewModels/WorkspaceViewModel.swift`
- `Orifold/Engine/PDFKitEngine.swift`
- `Orifold/Models/SourceDocumentPayload.swift`
- `Orifold.xcodeproj/project.pbxproj`
- `Casks/orifold.rb`
- `install.sh`
- `scripts/install-mac.sh`
- `.github/workflows/ci.yml`
- `.github/workflows/codeql.yml`
- `Orifold/Views/ContentView.swift`
- `Orifold/Views/ReadingCanvas.swift`
- `Orifold/Pet/PetBuddy.swift`
- `Tests/OrifoldTests/SourceDocumentRoundTripTests.swift`

### Release Checklist

- Confirm `Orifold/Resources/Info.plist` is `3.0` / `5`.
- Confirm `project.yml` is `3.0` / `5`.
- Run the verification commands above.
- Confirm the `release-v5` tag points at the intended release commit locally and on `origin`.
- Confirm the GitHub release for `release-v5` is marked latest and contains `Orifold.zip`.

</details>
