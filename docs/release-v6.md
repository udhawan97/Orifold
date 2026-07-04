# v6 Orifold

## GitHub Release Fields

Tag: `release-v6`

Target: latest commit tagged by `release-v6`

Release title: `v6 Orifold`

Asset to upload: `Orifold.zip`

Automation: `.github/workflows/sync-release-v6.yml` checks `origin/main` every 30 minutes, moves `release-v6` only when `main` has advanced, and then dispatches the release workflow to rebuild the latest v6 asset.

Build the asset with:

```zsh
./scripts/install-mac.sh --package-only --package /tmp/Orifold.zip
```

## Release Notes

# v6 Orifold

**Release:** Latest release
**Release date:** July 3, 2026
**Tag:** [`release-v6`](https://github.com/udhawan97/Orifold/releases/tag/release-v6)

---

## A More Complete Local PDF Finishing Workspace

Orifold v6 expands the app from document assembly and markup into a fuller PDF finishing workflow: make scans searchable, complete forms, add stamps and page decorations, reduce file size, protect the final PDF, and keep the exported result aligned with what you saw in the workspace.

The local-first document workspace, one-line installer, automatic update flow, clean uninstall command, inline text editing, comments, signatures, PDF-first save path, source-aware export, and multi-format export remain intact. Version 6 adds OCR, form export controls, decoration baking, compression, encryption, stricter export snapshots, and UI polish around the everyday reading and annotation surface.

This is primarily a **searchable scans, forms, stamps, protected export, compression, and PDF export integrity release**.

---

## What's New in v6

### Searchable Scans With Local OCR

Orifold can turn image-only scan pages into searchable PDF pages without sending the document to a remote service.

- Local Vision OCR recognizes scan text and writes it back as invisible selectable/searchable text.
- OCR work is cancellable and reports clear progress.
- The export path validates OCR output before it becomes part of the workspace.
- The final V6 gate re-imports a protected PDF and checks that searchable scan text survives.

### PDF Forms That Can Be Finished

Forms are now part of the normal workspace instead of a fragile edge case.

- Orifold scans imported PDFs for form fields and shows form status in the reader.
- Users can reset form values when they need a clean start.
- Export can lock form answers by flattening widgets into the final PDF.
- Tests cover text fields, checkboxes, malformed radio groups, reset/undo behavior, and unsupported dynamic-form markers.

### Stamps, Watermarks, Page Numbers, And Bates Labels

Version 6 adds document decorations for packet preparation and review workflows.

- Watermarks, page numbers, Bates labels, and movable stamps are stored in workspace state until export.
- Decorations are burned into exported PDFs so the final file matches the prepared packet.
- Page numbers and Bates labels follow the current page order.
- Existing PDF annotations are preserved while decorations are baked.

### Protected PDF Export

Orifold can export password-protected PDFs and verify the result before handing it back to the user.

- User and owner passwords are validated before writing output.
- Printing and copying permissions are checked after encryption.
- Protected output is reopened and unlocked during verification.
- The app blocks password protection when it would conflict with an existing digital-signature flow.

### File-Size Reduction

The compression path reduces image-heavy PDFs while keeping validation strict.

- Image-heavy PDFs can be downsampled and rewritten through the local PDF processing path.
- Compressed output must remain smaller than the source.
- Text integrity and PDF validity are checked after compression.
- If a PDF is already optimized or cannot be safely reduced, Orifold reports that instead of writing a misleading larger copy.

### Stricter Export Integrity

The V6 export path is deliberately conservative.

- Export uses copied snapshots rather than mutating the live document pages.
- Form flattening, decoration baking, compression, encryption, and validation share one stricter pipeline.
- Compressed encrypted output is validated after encryption, not only before it.
- User-facing save/export paths use throwing export code so failures are surfaced instead of silently ignored.

### Everyday UI Polish

The document workspace got several small fixes that make repeated use feel less brittle.

- Empty-state import UI and the annotation toolbar were redesigned.
- Page indicator behavior and sidebar metrics were tightened.
- Search width and submitted-search behavior were fixed.
- Comment controls now update live state more reliably, and the page badge focuses on the current page.

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

After installing v6, double-click `Orifold.command` on the Desktop. It checks the latest release before opening the app.

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

Feature range used for the product-change summary: `release-v5..HEAD`

Summary:

```text
20 commits changed 37 files, with 9020 insertions and 1212 deletions.
```

Commits:

- `cc3a9ba` Fixing comments
- `065f36e` Intro popover edit
- `374457b` More bug fixes
- `646be7a` Prevent sidebar metric truncation
- `1dff4d5` Redesign empty-state background and annotation toolbar
- `bfdf1db` More UI bug fix
- `3c732c1` Polish page indicator control
- `093e096` Fixing animation and broken comment button
- `4daf848` Add V6 final verification gate
- `bbfffee` Working towards new features
- `8c47c65` Audit findings +
- `754506e` Add protected PDF export
- `95fe5c0` Audit loop closed
- `194324f` Audit loop changes
- `db8f03b` Commenting + audit fixes +
- `9889608` Comment text box fix
- `b92e9a6` Search box width change
- `3edf250` Use SwiftPM for CodeQL analysis
- `df38a08` Speed up CodeQL analysis build
- `69b18b4` Intro UI change

Notable files:

- `Orifold/Engine/PDFOCRService.swift`
- `Orifold/Engine/PDFCompressionService.swift`
- `Orifold/Engine/PDFEncryptionService.swift`
- `Orifold/Engine/PDFFormSupport.swift`
- `Orifold/Engine/PDFDecorationExportBaker.swift`
- `Orifold/Models/WorkspaceExportOptions.swift`
- `Orifold/Models/PageDecoration.swift`
- `Orifold/ViewModels/WorkspaceViewModel.swift`
- `Orifold/Views/ReadingCanvas.swift`
- `Orifold/Views/InspectorView.swift`
- `Orifold/Views/StampPalette.swift`
- `Tests/OrifoldTests/PDFOCRTests.swift`
- `Tests/OrifoldTests/OrifoldTests.swift`
- `Tests/OrifoldTests/SourceDocumentRoundTripTests.swift`
- `docs/features/V6_VERIFICATION.md`

### Release Checklist

- Confirm `Orifold/Resources/Info.plist` is `v6` / `6`.
- Confirm `project.yml` is `v6` / `6`.
- Run the verification commands above.
- Confirm the `release-v6` tag points at `origin/main` locally and on `origin`.
- Confirm the GitHub release for `release-v6` is marked latest and contains `Orifold.zip`.

</details>
