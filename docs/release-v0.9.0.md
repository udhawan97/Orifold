# v0.9.0 Orifold

## GitHub Release Fields

Tag: `v0.9.0`

Target: latest commit tagged by `v0.9.0`

Release title: `v0.9.0 Orifold — Read deeper, inspect more, ship cleaner`

Assets to upload (all produced automatically by `release.yml`):

- `Orifold-0.9.0-macOS-universal.dmg` — drag-to-Applications disk image for Apple Silicon and Intel
- `Orifold-0.9.0-macOS-universal.dmg.sha256` — checksum sidecar used by the in-app updater
- `Orifold.dmg` — byte-identical stable-name alias for `releases/latest/download/Orifold.dmg`
- `Orifold.dmg.sha256`
- `manifest.json` — version, build, date, size, checksum, minimum macOS, and architecture
- `Orifold.zip` — one-line installer, Homebrew cask, and Desktop-helper artifact

Automation: `.github/workflows/release.yml` builds a universal app when a `v*` / `release-v*` tag is pushed, packages and smoke-tests the DMG, publishes the tagged release as GitHub's latest release, and dispatches a docs-site rebuild.

Build the assets locally with:

```zsh
ORIFOLD_UNIVERSAL=1 ./scripts/install-mac.sh --clean --no-open --package-only --package /tmp/Orifold.zip
zsh scripts/make-dmg.sh --from-zip /tmp/Orifold.zip --output /tmp/Orifold-0.9.0-macOS-universal.dmg --version 0.9.0
```

## Release Notes

# v0.9.0 Orifold — Read deeper, inspect more, ship cleaner

**Release:** Latest release

**Tag:** [`v0.9.0`](https://github.com/udhawan97/Orifold/releases/tag/v0.9.0)

---

## What Changed Since v0.8.14

This is Orifold's largest feature release so far. It adds navigation and read-aloud tools, document metadata and attachments, print imposition, hanko and barcode workflows, tagged-structure inspection, and archival-readiness guidance. The release also includes a native installed-app workflow audit and fixes every actionable gap found in that pass.

### Read and navigate

- **Nested Contents.** Orifold reads embedded PDF bookmarks into a navigable hierarchy and generates bookmarks from Markdown headings. Bookmarks survive the normal export pipeline.
- **Read aloud.** Start from **More → Read Aloud** or the View menu. Orifold speaks the document locally, highlights the current passage, follows page changes, and offers speed plus pause/resume/stop controls.
- **Bundled sample document.** The empty workspace now offers a disposable five-page sample so a new user can explore Contents, reading, editing, and markup without finding a file first.

### Understand and manage the file

- **Document metadata editor.** Edit title, author, subject, and keywords in the Inspector. Changes are undoable and written into exported PDF metadata.
- **Embedded attachments.** The Inspector can list, add, extract, and remove embedded files. Attachments are preserved through normal exports and participate in undo.
- **Tagged structure inspection.** A read-only Structure tab shows the current page's reading-order tree and alt-text coverage.
- **Archival readiness.** **More → Archival readiness…** checks six useful signals: encryption, embedded fonts, XMP metadata, output intent, tagged structure, and active content.

### Finish and deliver

- **Booklet and N-up imposition.** PDF export can arrange pages as booklet, 2-up, or 4-up; the File menu also offers 2-up printing. Decorations and annotations are baked before pages are imposed.
- **Hanko studio.** Create a circle or square visual hanko seal from a name, preview it, and place it like the other stamps.
- **Barcode and QR tools.** Generate and place QR, Code 128, Aztec, or PDF417 marks, then scan the current page locally with Vision and copy or open detected values.
- **Safer text substitution and spell-check.** Metric-compatible bundled fonts keep fallback edits closer to the source geometry, while continuous spell-check is enabled by default and configurable in Settings.

### User-flow fixes from the installed-app audit

- **The first action stays visible in short windows.** Compact welcome layouts put Choose Files, Choose Folder, and the sample before feature education, show a scroll affordance, and remove the companion overlap.
- **New documents open on page one.** Initial PDFKit layout now stays on the first page even when import normalization regenerates the combined document more than once.
- **Export works from toolbar overflow.** Export is a direct toolbar action instead of a nested menu that macOS disabled at compact widths; Print remains in File and on ⌘P.
- **Advanced export options are accessible controls.** Protect, Reduce file size, and Sanitize are standalone checkboxes with conditional settings in a scrollable sheet.
- **Recent files are real buttons.** Cards now have native keyboard activation and accurate help text in all six languages.

## Privacy and Compatibility

- All new document processing remains on-device. Read Aloud uses macOS speech, and barcode scanning uses Vision locally.
- Orifold still requires macOS 14 Sonoma or newer and ships as one universal Apple Silicon + Intel build.
- No workspace schema migration is required. Existing PDFs and workspaces continue to open normally.

## Important Boundaries

- Archival readiness is guidance, not PDF/A certification or conversion.
- Structure inspection is read-only in this release.
- Imposition flattens annotations into the arranged pages; original bookmark destinations are not reproduced for N-up/booklet output because page mapping is no longer one-to-one.
- Hanko seals are visual stamps, not cryptographic signatures.
- Attachment editing is unavailable while the source PDF is encrypted; decrypt or export an unlocked copy first.

## Verification

- 959 tests gate the source release, including export-order, attachment, imposition, outline, structure, archival, read-aloud, barcode, font-substitution, sample-document, and initial-viewport regressions.
- The app was clean-built, installed to `~/Applications/Orifold.app`, and driven through compact and normal window flows for first run, sample import, page navigation, search, Contents, toolbar overflow, Export, password options, and Recents accessibility.
- The release workflow produces checksummed DMG and ZIP artifacts and smoke-tests the packaged app before GitHub marks the release latest.

## Install / Upgrade

Existing users on v0.8.14 or newer can choose **Orifold → Check for Updates…**. Or install directly:

```zsh
curl -fsSL https://raw.githubusercontent.com/udhawan97/Orifold/main/install.sh | zsh
```

The same command installs or updates the universal app without requiring Xcode.
