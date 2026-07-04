<br>

<p align="center">
  <img src="docs/assets/orifold-icon.png" alt="Orifold app icon" width="180">
</p>

<h1 align="center">Orifold</h1>

<p align="center">
  <em>The PDF workspace that never phones home.</em>
</p>

<p align="center">
  <strong>From six scattered files to one polished, searchable, password-protected PDF.<br>No account. No upload. No subscription.</strong>
</p>

<p align="center">
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-111111?style=for-the-badge&logo=apple&logoColor=white">
  &nbsp;&nbsp;
  <img alt="Release v6" src="https://img.shields.io/badge/release-v6-2563EB?style=for-the-badge&logo=github&logoColor=white">
  &nbsp;&nbsp;
  <img alt="Local first" src="https://img.shields.io/badge/privacy-local%20first-10B981?style=for-the-badge&logo=icloud&logoColor=white">
  &nbsp;&nbsp;
  <img alt="MIT License" src="https://img.shields.io/badge/license-MIT-6B7280?style=for-the-badge&logo=opensourceinitiative&logoColor=white">
</p>

<p align="center">
  <img alt="SwiftUI" src="https://img.shields.io/badge/interface-SwiftUI-0A84FF?style=for-the-badge&logo=swift&logoColor=white">
  &nbsp;&nbsp;
  <img alt="PDFKit plus PDFium" src="https://img.shields.io/badge/engine-PDFKit%20%2B%20PDFium-10B981?style=for-the-badge">
</p>

<p align="center">
  <a href="#-quick-start"><strong>Quick Start</strong></a>
  &nbsp;&nbsp;&nbsp;
  <a href="#-features"><strong>Features</strong></a>
  &nbsp;&nbsp;&nbsp;
  <a href="#product-flow"><strong>Product Flow</strong></a>
  &nbsp;&nbsp;&nbsp;
  <a href="#architecture"><strong>Architecture</strong></a>
  &nbsp;&nbsp;&nbsp;
  <a href="#-privacy-and-security"><strong>Privacy</strong></a>
  &nbsp;&nbsp;&nbsp;
  <a href="#developer-notes"><strong>Developers</strong></a>
</p>

---

## Why Orifold

Orifold is for the moment when a simple PDF task becomes six PDFs, two screenshots, a Word document, a scanned form, and one file named `final_final_revised_ACTUAL.pdf`.

It gives that pile a single local workspace. Import files, reorder pages, annotate, edit detected text, fill and lock forms, add stamps, make scans searchable, compress the output, protect it with a password, and export the result. Orifold can't stop you from naming the export `final_final_revised_ACTUAL_v2.pdf` — but it can make sure that file is the one that's actually final.

Preview is great — right up until the job involves more than one file. Acrobat does everything, for a subscription, with a cloud attached. Orifold sits in the gap: merge, OCR, forms, stamps, compression, and password protection — native, local, and free.

## Product Flow

<p align="center">
  <img src="docs/assets/orifold-v3-workspace-diagram.svg" alt="Orifold product flow: import mixed files, edit and finish them in one local workspace, then export one clean file — everything runs on your Mac">
</p>

<p align="center">
  <em>Bring in mixed files, work locally, then export a clean, searchable, protected, or smaller result.</em>
</p>

## ⚡ Quick Start

Paste this into Terminal:

```zsh
curl -fsSL https://raw.githubusercontent.com/udhawan97/Orifold/main/install.sh | zsh
```

The installer downloads the latest prebuilt app, places it in `~/Applications/Orifold.app`, and creates Desktop commands for launch/update and uninstall.

Direct download: [`Orifold.zip`](https://github.com/udhawan97/Orifold/releases/latest/download/Orifold.zip)

No Xcode. No GitHub account. No compile step. No account creation ceremony, either.

Requires macOS 14 Sonoma or newer. That's the whole list.

<details>
<summary>Homebrew install</summary>

```zsh
brew tap udhawan97/orifold https://github.com/udhawan97/Orifold
brew install --cask udhawan97/orifold/orifold
```

Homebrew installs the same prebuilt app and clears the download quarantine after installation. The one-line installer remains the friendliest path because it also creates Desktop launch/update and uninstall commands.
</details>

<details>
<summary>How to open Terminal</summary>

Open **Applications** → **Utilities** → **Terminal**, paste the command above, and press Return.
</details>

<details>
<summary>Building from source instead?</summary>

Developer source builds need Apple Command Line Tools with Swift 5.9+. The normal installer downloads a prebuilt `.app` and does not need Command Line Tools — they only appear when building from source. See <a href="#developer-notes">Developer Notes</a>.
</details>

## ✨ Features

Everything below runs on your Mac. The cloud was not consulted.

| Area | What you can do | Built for |
| --- | --- | --- |
| Import | Open PDFs, Word documents, HTML, Markdown, text, CSV, JSON, XML, and common image formats | Turning mixed inputs into one workspace |
| Organize | Reorder documents and pages, rotate pages, delete pages, use section banners, and navigate from the sidebar | Assembling a clean packet from messy source files |
| Read and search | Use a native PDF canvas, page indicator, sidebar navigation, inspector, workspace search, and password unlock prompts | Finding the right page without losing context |
| Annotate | Highlight, add notes, draw ink, underline, strike out, place text boxes, and edit detected PDF text | Reviewing and correcting documents in place |
| Comments and metadata | Add workspace comments, tags, document details, and inspector-visible annotation lists | Keeping review context attached to the file |
| Signatures | Draw and place signatures, then export signed PDF output locally | Handling lightweight signature workflows without leaving the app |
| Forms | Detect PDF form fields, edit answers, reset forms, and lock answers during export | Finishing forms before sending the final copy |
| Scans and OCR | Make scanned pages searchable with local Vision OCR and preserve recognized text in export | Making ⌘F work on that thing your printer emailed you |
| Stamps and decorations | Add watermarks, page numbers, Bates labels, and movable stamps that burn into exported PDFs | Preparing packets, exhibits, and reviewed drafts |
| Compression | Downsample oversized PDF images and validate the compressed result | Helping your "quick attachment" stop bouncing off email size limits |
| Protection | Export password-protected PDFs with permission checks and post-export verification | Sharing sensitive documents more deliberately |
| Export | Save normal PDFs or export PDF, DOCX, Markdown, plain text, HTML, PNG pages, JPEG pages, or print output | Sending the format the next person actually needs |
| Install and update | Install with one command, use Desktop launch/update helpers, uninstall cleanly, or install through Homebrew | Making the app usable by people who do not build software |

## Architecture

<p align="center">
  <img src="docs/assets/orifold-v3-architecture-diagram.svg" alt="Orifold architecture: SwiftUI views send intents to one observable view model, local PDF engines behind protocol seams do the work, and a staged export pipeline writes validated artifacts inside a local-only boundary, guarded by a release gate">
</p>

<p align="center">
  <em>Unidirectional flow inside a local-only boundary — and a release gate standing outside it.</em>
</p>

<details>
<summary>Layer-by-layer responsibilities</summary>

| Layer | Responsibility |
| --- | --- |
| SwiftUI app | Document window, sidebar, canvas, annotation toolbar, search, inspector, password prompts, and export controls |
| Workspace state | Imported documents, page order, undo snapshots, comments, tags, signatures, form summaries, and decorations |
| PDF services | PDFKit composition, PDFium validation and compression support, Vision OCR, encryption, form flattening, decoration baking, and signing helpers |
| Local storage | Saved PDF data, workspace metadata, source payloads, comments, signatures, and page edit state |
| Release tooling | One-line installer, package builder, Desktop update launcher, uninstaller, GitHub Actions release asset, and validation tests |
</details>

<details>
<summary>Same picture, as a Mermaid graph</summary>

```mermaid
flowchart LR
    Files["Source files<br/>PDF, Word, HTML, Markdown, text, data, images"]
    UI["SwiftUI views<br/>sidebar, canvas, toolbar, inspector"]
    State["Workspace state<br/>WorkspaceViewModel — pages, comments, forms, decorations"]
    Services["Local engines<br/>PDFKit, PDFium, Vision OCR, signing"]
    Export["Export pipeline<br/>flatten forms, bake stamps, compress, encrypt, validate"]
    Artifacts["Artifacts<br/>PDF, DOCX, MD, TXT, HTML, PNG, JPEG"]

    Files --> UI
    UI --> State
    State --> Services
    Services --> Export
    Export --> Artifacts
```
</details>

## 📦 Release Status

Orifold v6 is the current release. It expands the app from document assembly and markup into a fuller PDF finishing workflow: searchable scans, form export, stamps and decorations, compression, protected output, and a cleaner everyday UI.

| Detail | Status |
| --- | --- |
| Release tag | [`release-v6`](https://github.com/udhawan97/Orifold/releases/tag/release-v6) |
| Release asset | [`Orifold.zip`](https://github.com/udhawan97/Orifold/releases/latest/download/Orifold.zip) |
| Recommended install | `curl -fsSL https://raw.githubusercontent.com/udhawan97/Orifold/main/install.sh \| zsh` |
| Distribution | Prebuilt macOS app zip, with source builds available for developers |
| Privacy model | Local document processing; no upload pipeline |

## 🔄 Updating and Uninstalling

**To update:** double-click **Orifold.command** on the Desktop. The launcher checks the latest release before opening the app. That's the entire update procedure — you may cancel the calendar reminder.

You can also paste the installer command again:

```zsh
curl -fsSL https://raw.githubusercontent.com/udhawan97/Orifold/main/install.sh | zsh
```

**To uninstall:** double-click **Uninstall Orifold.command** on the Desktop. It removes the installed app, generated Desktop commands, installer cache, and Orifold app data — a cleaner exit than most software manages.

<details>
<summary>Homebrew and advanced options</summary>

Update via Homebrew:

```zsh
brew update
brew upgrade --cask udhawan97/orifold/orifold
```

Uninstall via Homebrew:

```zsh
brew uninstall --cask udhawan97/orifold/orifold
```

Uninstall but keep app support, preferences, caches, and sandbox data:

```zsh
curl -fsSL https://raw.githubusercontent.com/udhawan97/Orifold/main/scripts/uninstall-mac.sh | zsh -s -- --keep-user-data
```
</details>

## A Typical Session

1. Launch Orifold.
2. Drag in PDFs, Word documents, text files, web exports, data files, scans, or images.
3. Reorder documents and pages until the workspace matches the story you need to tell.
4. Annotate, edit text, fill forms, add comments, add stamps, or place a signature.
5. Search across the combined document set.
6. Make scans searchable, compress the PDF, or protect the output when needed.
7. Save a normal PDF or export another format.

## 🔒 Privacy and Security

Orifold is local-first by design. Documents are opened, edited, saved, OCRed, compressed, protected, and exported on your machine.

The app uses macOS sandboxing and user-selected file access. PDFium validation, Vision OCR, PDFKit composition, compression, encryption, and export verification run locally.

Practical guardrails include:

- Password prompts for protected PDFs.
- Import size limits for accidental giant files.
- Local validation before and after compression or encryption.
- Form flattening before decoration burn-in when requested.
- Export error reporting for failed writes, image rendering, malformed PDFs, or unsafe source round trips.
- Hidden Orifold comment metadata stripped before flat PDF export.
- Installer, uninstaller, packaging, build, and test checks in the release gate.

<details>
<summary>Sandbox details</summary>

The app enables:

- `com.apple.security.app-sandbox`
- `com.apple.security.files.user-selected.read-write`

These entitlements allow sandboxed read/write access to files selected by the user.
</details>

## Developer Notes

The whole thing is 59 Swift files, roughly 21,000 lines, with 202 tests standing guard in the release gate.

```text
Orifold/
  App/             App entry point and command wiring
  Document/        macOS document package read/write support
  Engine/          PDF loading, conversion, OCR, compression, encryption, forms, export helpers
  Models/          Workspace, page, annotation, comment, export option, and decoration models
  Resources/       App metadata, entitlements, assets, and certificate guide
  Signing/         Signing identities, CMS construction, timestamping, and verification helpers
  ViewModels/      Workspace state, document operations, search, export, undo
  Views/           SwiftUI interface components
scripts/
  install-mac.sh       Release-first installer, source builder, and release packager
  uninstall-mac.sh     Clean uninstaller for installed app artifacts and Orifold app data
install.sh             Hosted one-line bootstrap
```

<details>
<summary>Build, test, package, and source-install commands</summary>

Open the project in Xcode:

```zsh
open Orifold.xcodeproj
```

Build and test:

```zsh
swift build
swift test
xcodebuild build -quiet -project Orifold.xcodeproj -scheme Orifold -destination 'generic/platform=macOS' CODE_SIGNING_ALLOWED=NO
xcodebuild test -quiet -project Orifold.xcodeproj -scheme Orifold -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

Create the same release zip used by GitHub Releases:

```zsh
./scripts/install-mac.sh --package-only --package /tmp/Orifold.zip
```

Create a Developer ID signed and notarized release zip:

```zsh
ORIFOLD_SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
ORIFOLD_NOTARIZE=1 \
ORIFOLD_APPLE_ID="apple-id@example.com" \
ORIFOLD_APPLE_TEAM_ID="TEAMID" \
ORIFOLD_APPLE_APP_SPECIFIC_PASSWORD="app-specific-password" \
./scripts/install-mac.sh --package-only --package /tmp/Orifold.zip
```

GitHub Actions uses the same path when these secrets are configured: `ORIFOLD_DEVELOPER_ID_CERTIFICATE_BASE64`, `ORIFOLD_DEVELOPER_ID_CERTIFICATE_PASSWORD`, `ORIFOLD_SIGNING_IDENTITY`, `ORIFOLD_APPLE_ID`, `ORIFOLD_APPLE_TEAM_ID`, and `ORIFOLD_APPLE_APP_SPECIFIC_PASSWORD`.

Install from the current source checkout without opening the app:

```zsh
./scripts/install-mac.sh --no-open
```

App metadata: `CFBundleShortVersionString` `v6`, `CFBundleVersion` `6`.
</details>

<details>
<summary>Quality checks and release gate</summary>

| Check | What to verify |
| --- | --- |
| Build | `swift build` completes |
| Tests | `swift test` and Xcode tests pass |
| Metadata | App plists and entitlements lint cleanly |
| Installer | Shell scripts parse with `zsh -n` |
| Package | `./scripts/install-mac.sh --package-only --package /tmp/Orifold.zip` creates the release artifact |
| User workflow | Import, search, annotate, forms, OCR, stamps, compression, protected export, update, and uninstall work on a local Mac |

Release gate commands:

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
</details>

## 🗺️ Roadmap

- More export presets.
- Faster large-document navigation.
- Automated UI smoke tests.

## 🔧 Troubleshooting

<details>
<summary>Clicking the installer opens a GitHub page instead of installing</summary>

That is expected on GitHub. README links open files in the browser; they do not execute Mac installer scripts.

Use the Quick Start command from Terminal, or download the repository first and run the installer from Finder.
</details>

<details>
<summary>Double-clicking the installer says it cannot be opened</summary>

Open Terminal in the project folder and run:

```zsh
chmod +x "Install or Update Orifold.command" "Uninstall Orifold.command" "Install or Update Orifold.app/Contents/MacOS/OrifoldInstaller" scripts/install-mac.sh scripts/install-mac.command scripts/uninstall-mac.sh
```

Then double-click `Install or Update Orifold.app` again from Finder.
</details>

<details>
<summary>The installer says no prebuilt release is available</summary>

The normal installer uses a prebuilt app and does not need developer tools. This message means the GitHub release asset `Orifold.zip` has not been published yet or could not be downloaded.

Wait for the release workflow to publish `Orifold.zip`, then run the installer again. Developer source builds can opt in with:

```zsh
curl -fsSL https://raw.githubusercontent.com/udhawan97/Orifold/main/install.sh | ORIFOLD_ALLOW_SOURCE_BUILD=1 zsh
```
</details>

<details>
<summary>macOS warns the app is from an unidentified developer</summary>

Orifold release builds are ad-hoc signed but not notarized. The one-line installer and Homebrew cask remove download quarantine from the installed app. If macOS still warns, open it from Finder, then use **Open** from the security prompt.

Fully quiet Gatekeeper behavior requires a release zip built with Apple Developer ID signing and notarization secrets configured in GitHub Actions.
</details>

<details>
<summary>The build fails and the terminal window closes too fast</summary>

Open `.build/install.log` in the project folder. It contains the latest installer/build output.

When using the README install command, the prebuilt release attempt is also logged at `~/.orifold/prebuilt-install.log`.
</details>

## Contributing

Bug reports and feature requests are welcome in [Issues](https://github.com/udhawan97/Orifold/issues). If you're building from source, the <a href="#developer-notes">Developer Notes</a> and release gate commands are the whole onboarding doc — if `swift test` passes, you're set up.

## License

Orifold is available under the [MIT License](LICENSE).

---

<p align="center">
  If Orifold rescued you from <code>final_final_revised_ACTUAL_v3.pdf</code>, consider
  <a href="https://github.com/udhawan97/Orifold/stargazers">starring the repo</a>.<br>
  Since nothing you do in Orifold ever leaves your Mac, stars are the only telemetry we get.
</p>

<p align="center">
  Built with SwiftUI, PDFKit, PDFium, and Vision — all running on your machine.
</p>

<p align="center">
  <a href="#orifold">Back to top ↑</a>
</p>
