# v5 pdFold

## GitHub Release Fields

Tag: `release-v5`

Target: latest commit tagged by `release-v5`

Release title: `v5 pdFold`

Asset to upload: `pdFold.zip`

Build the asset with:

```zsh
./scripts/install-mac.sh --package-only --package /tmp/pdFold.zip
```

## Release Notes

# v5 pdFold

**Release:** Latest release  
**Release date:** July 1, 2026  
**Tag:** [`release-v5`](https://github.com/udhawan97/PDFold/releases/tag/release-v5)

---

## A Cleaner Save, Export, and Editing Release

pdFold v5 tightens the everyday workflow around saving, exporting, and small editing details. Normal macOS Save/Save As now stays PDF-first, while the export menu keeps the broader formats users expect when they need DOCX, Markdown, text, HTML, image pages, or print output.

The release also preserves original source data for supported non-PDF imports, adds safer same-format export behavior, covers the source round trip with focused tests, and includes a more organized toolbar plus an optional in-app helper.

## Install

```zsh
curl -fsSL https://raw.githubusercontent.com/udhawan97/PDFold/main/install.sh | zsh
```

Direct download: [`pdFold.zip`](https://github.com/udhawan97/PDFold/releases/latest/download/pdFold.zip)

The installer downloads the latest `pdFold.zip`, installs `pdFold.app` to `~/Applications`, creates Desktop commands for launch/update and uninstall, clears quarantine metadata, and opens pdFold.

---

## What's New in v5

### PDF-First Save Path

- Standard macOS Save and Save As write flat PDF output by default.
- The previous `.pdfoldproj` workspace save type has been removed from app metadata and installer checks.
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
- Foldy, the optional pdFold helper, reacts to common actions and can be hidden from the app menu or popover.
- Helper bubbles avoid blocking normal canvas input.

---

## Update

After installing v5, double-click `pdFold.command` on the Desktop. It checks the latest release before opening the app.

---

## Uninstall

Double-click `Uninstall pdFold.command` on the Desktop.

To keep pdFold app support, preferences, caches, and sandbox data:

```zsh
curl -fsSL https://raw.githubusercontent.com/udhawan97/PDFold/main/scripts/uninstall-mac.sh | zsh -s -- --keep-user-data
```

---

<details>
<summary>Developer details</summary>

### Verification

```zsh
plutil -lint PDFold/Resources/Info.plist
plutil -lint PDFold/Resources/PDFold.entitlements
zsh -n install.sh
zsh -n scripts/install-mac.sh
zsh -n scripts/uninstall-mac.sh
zsh -n scripts/install-mac.command
zsh -n "Install or Update pdFold.command"
zsh -n "Uninstall pdFold.command"
zsh -n "Install or Update pdFold.app/Contents/MacOS/pdFoldInstaller"
plutil -lint "Install or Update pdFold.app/Contents/Info.plist"
swift build
swift test
xcodebuild build -quiet -project PDFold.xcodeproj -scheme PDFold -destination 'generic/platform=macOS' CODE_SIGNING_ALLOWED=NO
xcodebuild test -quiet -project PDFold.xcodeproj -scheme PDFold -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
./scripts/install-mac.sh --package-only --package /tmp/pdFold.zip
```

### Git Summary

Feature range used for the product-change summary: `release-v4..HEAD`

Summary:

```text
7 commits changed 18 files, with 2141 insertions and 251 deletions.
```

Commits:

- `HEAD` Stabilize CI plist validation
- `25ee541` Prepare release v5
- `ad00fd9` Inline coverage +
- `cf28ee5` Cleaning up bugs on export
- `0235c02` UI header fixes
- `8908ce2` Adding UI pet
- `bf04db0` UI fixes

Notable files:

- `PDFold/Document/WorkspaceDocument.swift`
- `PDFold/ViewModels/WorkspaceViewModel.swift`
- `PDFold/Engine/PDFKitEngine.swift`
- `PDFold/Models/SourceDocumentPayload.swift`
- `PDFold.xcodeproj/project.pbxproj`
- `.github/workflows/ci.yml`
- `PDFold/Views/ContentView.swift`
- `PDFold/Views/ReadingCanvas.swift`
- `PDFold/Pet/PetBuddy.swift`
- `Tests/PDFoldTests/SourceDocumentRoundTripTests.swift`

### Release Checklist

- Confirm `PDFold/Resources/Info.plist` is `3.0` / `5`.
- Confirm `project.yml` is `3.0` / `5`.
- Run the verification commands above.
- Confirm the `release-v5` tag points at the intended release commit locally and on `origin`.
- Confirm the GitHub release for `release-v5` is marked latest and contains `pdFold.zip`.

</details>
