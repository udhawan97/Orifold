# pdFold release-v4 Release Notes

## GitHub Release Fields

Tag: `release-v4`

Target: latest commit tagged by `release-v4`

Release title: `pdFold release-v4 - inline editing, digital signatures, and Xcode build parity`

Asset to upload: `pdFold.zip`

Build the asset with:

```zsh
./scripts/install-mac.sh --package-only --package /tmp/pdFold.zip
```

## Release Notes

# Inline PDF Text Editing, Digital Signatures, and Xcode Build Parity

**Release:** Latest release  
**Release date:** July 1, 2026  
**Tag:** [`release-v4`](https://github.com/udhawan97/PDFold/releases/tag/release-v4)

---

## ✦ A More Precise Native PDF Editor

pdFold release-v4 focuses on the editing and signing paths that matter most in dense real-world PDFs: click existing text, edit it in place, sign documents, and export a PDF that keeps the original page stable.

The local-first document workspace, installer, automatic update flow, clean uninstall command, PDFium validation, and multi-format export from v3 remain intact. Version 4 hardens inline PDF text editing, PDF save metadata, authentic PDF signatures, bundled signing guidance, Xcode project parity, release automation, and regression coverage so the app behaves more like a serious Mac PDF workflow tool.

This is primarily a **PDF editing fidelity, signature, export integrity, and release automation release**.

---

## What's New in release-v4

### Bulletproof Inline PDF Text Editing

Inline PDF text editing now keeps document-space and screen-space measurements separate.

- The floating editor previews text at `documentFontSize * PDFView.scaleFactor`, so small 8-10pt resume text remains legible at fit-to-page zoom.
- Commits store document-space font size and a concrete PostScript font name instead of a zoomed display size.
- The editor listens for `PDFViewScaleChanged` while open and refreshes layout/formatting as the user zooms.
- Existing replacement alignment is preserved when reopening a previous edit.

---

### Shared CoreText Measurement and Rendering

Preview geometry, committed bounds, and PDF rendering now use one CoreText-based layout path for replacement text.

- Replacement measurement and drawing are unified through `ReplacementTextLayout`.
- Long replacements and unbreakable words expand predictably instead of clipping.
- The live editor's committed page-space bounds are honored instead of being re-pinned to the original source line.
- Repeated edits update the existing operation instead of stacking patches.

---

### Safer Erase and Page Regeneration

Text replacement now erases less and preserves more.

- The erase patch targets the original source text bounds, not `sourceBounds ∪ editedBounds`.
- The renderer samples the local page background instead of always painting white.
- Regeneration still starts from pristine original page bytes so repeated edits do not accumulate old patches.
- Existing highlight, note, ink, signature, and text-box annotations survive text edit regeneration.

---

### Better Font and Size Fidelity

PDFium-reported font sizes are now checked against actual glyph ink in page space.

- Scaled content streams no longer inflate replacement text by trusting nominal `Tf` sizes blindly.
- Carlito/Calibri-style embedded font names map to closer installed macOS faces when the exact source face is not available.
- Toolbar font, size, bold, italic, color, and alignment choices round-trip through preview, commit, export, save, and reopen.

---

### Undo, Redo, and Save Integrity

Inline PDF text edits now restore both rendered bytes and edit metadata.

- Undo restores prior PDF bytes and page edit state.
- Redo replays the edited PDF bytes and operation state.
- Standard macOS saves now write flat PDF output while keeping the existing export options available.
- PDF export strips stale hidden workspace-comment metadata before writing, so removed comments do not silently survive in later exported PDFs.
- Save and export snapshots continue to export from copied pages, preserving the live page-sharing invariant.
- App metadata is bumped to `CFBundleShortVersionString` `3.0` and `CFBundleVersion` `4`.

---

### Authentic PDF Signatures

release-v4 adds a native signing path for PDF deliverables.

- Signing contracts, identity providers, CMS signature construction, and timestamp request support are included in the app codebase.
- Signature appearances render consistently for placed signatures.
- The signing path has focused regression coverage for CMS packaging, timestamp handling, appearance rendering, and PDF signing behavior.
- Certificate setup and verification guidance is bundled as an app resource and loads in SwiftPM, Xcode, and packaged app layouts.

---

### Signature Input and Placement Polish

The latest release target includes the follow-up signature fixes after the original release-v4 tag.

- Signature placement models preserve the data needed for reliable save, reopen, and export.
- Signature palette and input behavior were tightened after the digital-signature feature landed.
- The current tag target includes the latest signature input fix on `main`.

---

### Release and CI/CD Hardening

release-v4 also tightens the release path.

- The checked-in Xcode project now includes signing sources, signing tests, Swift package products, bundled certificate-guide resources, and a shared `PDFold` scheme for build/test verification.
- Xcode tests use the app debug dylib without launching the full app, while SwiftPM continues to cover the WebKit HTML pagination path.
- `release-v*` tags now trigger the release workflow.
- Tagged releases publish `pdFold.zip` and are marked as the latest GitHub release.
- Rolling `pdFold-latest` builds still refresh from `main`, but no longer steal the latest-release pointer from versioned releases.
- README download links point at `https://github.com/udhawan97/PDFold/releases/latest/download/pdFold.zip`.

---

## Install

```zsh
curl -fsSL https://raw.githubusercontent.com/udhawan97/PDFold/main/install.sh | zsh
```

The installer downloads the latest `pdFold.zip`, installs `pdFold.app` to `~/Applications`, creates Desktop commands for launch/update and uninstall, clears quarantine metadata, and opens pdFold.

Direct download: [`pdFold.zip`](https://github.com/udhawan97/PDFold/releases/latest/download/pdFold.zip)

---

## Update

After installing release-v4, double-click `pdFold.command` on the Desktop. It checks the latest release before opening the app.

---

## Uninstall

Double-click `Uninstall pdFold.command` on the Desktop.

To keep pdFold app support, preferences, caches, and sandbox data:

```zsh
curl -fsSL https://raw.githubusercontent.com/udhawan97/PDFold/main/scripts/uninstall-mac.sh | zsh -s -- --keep-user-data
```

---

## Verification

```zsh
plutil -lint PDFold/Resources/Info.plist
plutil -lint PDFold/Resources/PDFold.entitlements
zsh -n install.sh
zsh -n scripts/install-mac.sh
zsh -n scripts/uninstall-mac.sh
zsh -n scripts/install-mac.command
zsh -n "Install or Update pdFold.command"
zsh -n "Uninstall pdFold.command"
plutil -lint "Install or Update pdFold.app/Contents/Info.plist"
swift build
swift test
xcodebuild build -quiet -project PDFold.xcodeproj -scheme PDFold -destination 'generic/platform=macOS' CODE_SIGNING_ALLOWED=NO
xcodebuild test -quiet -project PDFold.xcodeproj -scheme PDFold -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
./scripts/install-mac.sh --package-only --package /tmp/pdFold.zip
```

---

## Git Summary

Feature range used for the product-change summary: `release-v3..6391579`

Summary:

```text
35 product commits changed 58 files, with 9077 insertions and 809 deletions, before the documentation-only release-note cleanup.
```

Commits:

- `6391579` Fixing signature input issues
- `feb5c45` Add views
- `140e510` Merge digital signature feature (PAdES B-T + cursive visual signatures)
- `87d24c2` Add authentic PDF digital signatures (PAdES B-T) and cursive visual signatures
- `2e4d4aa` Text editing hardening + other fixes
- `6694b91` Bunch of fixes on signature
- `c685d39` Keep inline text edits vertically aligned
- `7f62f36` Fix inline editor toolbar controls
- `5605b2a` Prepare release v4
- `e467b45` Bump app build for PDF save metadata
- `6847e79` Inline text editing overhaul
- `0dbbc21` Remove workspace save format from app bundle
- `f385452` Edit text bug fixes
- `5d8c859` Default saves to PDF
- `fdda0f1` Edit text bug fix
- `551a597` Update README.md
- `78467cc` Install script UI fix
- `1697764` Annotation on install script
- `04f5189` Merge remote-tracking branch 'origin/main'
- `768d6d9` Split same-baseline columns into separate editable blocks
- `1e799c3` Merge pull request #3 from udhawan97/friendly-helper-claude/sharp-margulis-d55d19
- `0fdb103` Fix inline text edit placement and font-size fidelity
- `1a44aad` Merge branch 'claude/optimistic-gauss-ad6e08'
- `b7d4f01` Merge remote-tracking branch 'origin/main' into claude/optimistic-gauss-ad6e08
- `8088ac7` App name changes
- `9a4ec5b` Fix inline text editing: lost edits on export, misplaced/overlapping replacement text, dropped annotations, and font fidelity
- `fd596f7` Adding fixes for notes feature
- `d82cef0` renaming app to pdFold
- `955fe43` Shell script fixes
- `d609234` CI fixes
- `bc5b2e1` Merge branch 'claude/relaxed-tharp-3a55e3'
- `b43c6c7` Fix text edits not appearing live or after export
- `7d48355` Merge branch 'claude/relaxed-tharp-3a55e3'
- `575348a` Fix inline text editing correctness and accumulation bugs
- `a7a2ee8` Editing feature retry

---

## Release Checklist

- Confirm `PDFold/Resources/Info.plist` is `3.0` / `4`.
- Confirm `project.yml` is `3.0` / `4`.
- Confirm `PDFold/Resources/CERTIFICATE_GUIDE.md` is included in SwiftPM resources, Xcode app resources, and installer packaging.
- Confirm the Xcode project includes the signing source files, signing tests, Swift package products, and shared `PDFold` test scheme.
- Run the verification commands above.
- Confirm the `release-v4` tag points at the intended release commit locally and on `origin`.
- Confirm the GitHub release for `release-v4` is marked latest and contains `pdFold.zip`.
