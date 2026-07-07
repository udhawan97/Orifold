<div align="center">

<img src="docs/assets/orifold-crane-fold.svg" alt="Animated Orifold logo: a sheet of paper folds into an origami crane, then becomes the app icon" width="168">

# Orifold

### Drop in up to 50 messy files.<br>Walk away with one polished, searchable, password-protected PDF.

<em>Designed from necessity &nbsp;·&nbsp; Built for privacy &nbsp;·&nbsp; Refined for focus</em>

<br>
<br>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/assets/hero-banner-dark.svg">
  <img src="docs/assets/hero-banner-light.svg" alt="50 messy files go in, one polished, searchable, password-protected PDF comes out — up to 50 files per workspace, 0 files ever uploaded, 12+ PDF tools in one app, $0 forever" width="880">
</picture>

<br>
<br>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/assets/value-props-dark.svg">
  <img src="docs/assets/value-props-light.svg" alt="No account: nothing to sign up for, ever. No upload: your files never leave your Mac. No subscription: free and open source, MIT licensed." width="880">
</picture>

<br>
<br>

<img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-111111?style=for-the-badge&logo=apple&logoColor=white">&nbsp;&nbsp;<img alt="Release v0.8.1" src="https://img.shields.io/badge/release-v0.8.1-2563EB?style=for-the-badge&logo=github&logoColor=white">&nbsp;&nbsp;<img alt="Beta" src="https://img.shields.io/badge/status-beta-F59E0B?style=for-the-badge">&nbsp;&nbsp;<img alt="100% local" src="https://img.shields.io/badge/privacy-100%25%20local-10B981?style=for-the-badge">&nbsp;&nbsp;<img alt="6 languages" src="https://img.shields.io/badge/i18n-6%20languages-8B5CF6?style=for-the-badge">&nbsp;&nbsp;<img alt="MIT License" src="https://img.shields.io/badge/license-MIT-6B7280?style=for-the-badge">

<br>

<sub>Orifold is in beta. <strong>v0.8.1</strong> marks the move to semantic versioning — the v1–v7 line continues here as focused polish, validation, and user-flow hardening on the road to 1.0.</sub>

<br>
<br>

<sub>&nbsp;B&nbsp;U&nbsp;I&nbsp;L&nbsp;T&nbsp;&nbsp;W&nbsp;I&nbsp;T&nbsp;H&nbsp;</sub>

<br>
<br>

<img alt="Swift" src="https://img.shields.io/badge/Swift_5.9-F05138?style=flat-square&logo=swift&logoColor=white">&nbsp;
<img alt="SwiftUI" src="https://img.shields.io/badge/SwiftUI-0A84FF?style=flat-square&logo=swift&logoColor=white">&nbsp;
<img alt="PDFKit" src="https://img.shields.io/badge/PDFKit-111111?style=flat-square&logo=apple&logoColor=white">&nbsp;
<img alt="PDFium" src="https://img.shields.io/badge/PDFium-4285F4?style=flat-square&logo=googlechrome&logoColor=white">&nbsp;
<img alt="qpdf" src="https://img.shields.io/badge/qpdf-6E56CF?style=flat-square&logoColor=white">&nbsp;
<img alt="Vision OCR" src="https://img.shields.io/badge/Vision_OCR-111111?style=flat-square&logo=apple&logoColor=white">&nbsp;
<img alt="App Sandbox" src="https://img.shields.io/badge/App_Sandbox-10B981?style=flat-square&logo=apple&logoColor=white">

<br>
<br>

<a href="#-install-in-30-seconds"><kbd> &nbsp;⚡ Install&nbsp; </kbd></a>&ensp;
<a href="#-what-it-does"><kbd> &nbsp;✨ Features&nbsp; </kbd></a>&ensp;
<a href="#-meet-your-paper-companion"><kbd> &nbsp;🐾 Companion&nbsp; </kbd></a>&ensp;
<a href="#-privacy"><kbd> &nbsp;🔒 Privacy&nbsp; </kbd></a>&ensp;
<a href="#%EF%B8%8F-under-the-hood"><kbd> &nbsp;⚙️ Under the Hood&nbsp; </kbd></a>&ensp;
<a href="#-troubleshooting"><kbd> &nbsp;🆘 Help&nbsp; </kbd></a>&ensp;
<a href="https://udhawan97.github.io/Orifold/"><kbd> &nbsp;📖 Docs&nbsp; </kbd></a>

</div>

---

## 📄 The Problem

A "simple PDF task" is rarely simple. It is six PDFs, two screenshots, a Word document, a scanned form, and one determined file named `final_final_revised_ACTUAL.pdf`.

I built Orifold because basic file work on a Mac should not require a subscription, an upload, or a small ceremony. Preview is excellent until the job gets complicated; the more capable tools often put everyday workflows behind paywalls. **Orifold is my work-in-progress answer**: merge, annotate, OCR, forms, stamps, compression, and password protection — native, local, and free.

It is not perfect yet, but it is being built in public with care, curiosity, and a friendly AI collaborator. The goal is simple: give every Mac user a practical PDF workspace without making them rent their own files back.

<p align="center">
  <img src="docs/assets/orifold-v3-workspace-diagram.svg" alt="Orifold product flow: import mixed files, edit and finish them in one local workspace, then export one clean file — everything runs on your Mac">
</p>

## 🐾 Meet Your Paper Companion

The same fold that opens Orifold's logo blossoms into a small companion that lives in your workspace — pick **Gami · Orifold Guide** (an origami Bernedoodle, all floppy black ears and a cream blaze) or **Ori** (an origami Siberian, plush cream ruff and a composed, wrap-around tail) on first launch, or switch anytime. They're siblings folded from the same sheet of paper — different mothers' patterns, same origami — and it shows: same cream paper, same quiet manners, very different personalities. On first launch your companion shows off at full size for a few seconds — layered fur, folded ears, a wagging tail or a slow tail-curl — before settling into the corner; hover it anytime to see that detail again. Once docked, it sits quietly in the corner, keeps its hints out of your document's way, and speaks up — briefly and usefully — for moments that matter: exporting, saving, and anything that needs your attention.

<table align="center">
  <tr>
    <td align="center" width="240"><img src="docs/assets/orifold-crane-fold.svg" alt="Animated: a sheet of paper folds into an origami crane, then becomes the app icon" width="200"></td>
    <td align="center" width="240"><img src="docs/assets/orifold-dog-wag.svg" alt="Animated: Gami the origami Bernedoodle, tail wagging" width="200"></td>
    <td align="center" width="240"><img src="docs/assets/orifold-cat-twitch.svg" alt="Animated: Ori the origami Siberian, front-facing with a cream ruff, tufted ears that twitch, and a long tail that wraps around her paws and sways" width="200"></td>
  </tr>
  <tr>
    <td align="center"><strong>The Fold</strong><br><sub>The brand mark folds into a crane — a quiet red tancho crown its only splash of color.</sub></td>
    <td align="center"><strong>Gami</strong> &nbsp;<sub>· the Bernedoodle</sub><br><sub>Floppy black ears, a cream blaze, a calm wag. A quiet guide, not a mascot — tips stay brief and out of your document's way.</sub></td>
    <td align="center"><strong>Ori</strong> &nbsp;<sub>· the Siberian</sub><br><sub>Curious, clever, elegant, charmingly bossy. She notices first, speaks second — a wrapped tail instead of a wag.</sub></td>
  </tr>
</table>

## ⚡ Install in 30 Seconds

Paste this into Terminal and press Return:

```zsh
curl -fsSL https://raw.githubusercontent.com/udhawan97/Orifold/main/install.sh | zsh
```

That's it. The installer downloads the prebuilt app to `~/Applications/Orifold.app` and puts two helpers on your Desktop: **Orifold.command** (launch + auto-update) and **Uninstall Orifold.command** (a clean exit).

No Xcode. No GitHub account. No compile step. Requires macOS 14 Sonoma or newer — that's the whole list.

> [!TIP]
> Never used Terminal? Open **Applications → Utilities → Terminal**, paste the line above, press Return. You're now a power user.

<details>
<summary>🍺 &nbsp;Prefer Homebrew?</summary>

<br>

```zsh
brew tap udhawan97/orifold https://github.com/udhawan97/Orifold
brew install --cask udhawan97/orifold/orifold
```

Installs the same prebuilt app and clears the download quarantine. The one-line installer is still the friendliest path — it also creates the Desktop launch/update and uninstall helpers.
</details>

<details>
<summary>📥 &nbsp;Prefer a direct download?</summary>

<br>

Grab [`Orifold.zip`](https://github.com/udhawan97/Orifold/releases/latest/download/Orifold.zip) from the latest release, unzip, and drag `Orifold.app` into Applications. If macOS complains about an unidentified developer, right-click the app and choose **Open**.
</details>

<details>
<summary>🛠️ &nbsp;Building from source?</summary>

<br>

Source builds need Apple Command Line Tools with Swift 5.9+. The normal installer never needs them — it downloads a prebuilt app. See [Under the Hood](#%EF%B8%8F-under-the-hood).
</details>

## ✨ What It Does

Everything below runs on your Mac. The cloud was not consulted.

| | Do this | Get this |
| :---: | --- | --- |
| 📥 | **Import anything** — PDFs, Word, images, scans, Markdown, HTML, CSV — even corrupt files | One workspace instead of a folder of chaos; broken PDFs repaired on the way in |
| 🗂️ | **Organize** — reorder, rotate, delete pages across documents | A clean packet from messy source files |
| ✏️ | **Annotate & edit** — highlight, notes, ink, text boxes, edit PDF text in place | Reviewed documents without a print-sign-scan loop |
| 🖋️ | **Sign & fill forms** — draw signatures, complete form fields, lock answers | Finished paperwork, no third-party e-sign service |
| 🔍 | **OCR scans** — local Vision OCR makes scanned pages searchable | ⌘F finally works on that thing your printer emailed you |
| 🏷️ | **Stamp & label** — watermarks, page numbers, Bates labels | Packets and exhibits that look intentional |
| 🗜️ | **Compress** — downsample oversized images, then losslessly re-pack the structure | Attachments that stop bouncing off email size limits |
| 🧼 | **Sanitize for sharing** — strip auto-run actions, embedded JavaScript, hidden metadata | A file that carries nothing you didn't intend to send |
| 🔒 | **Protect & export** — real AES-256 password, or export DOCX, Markdown, HTML, PNG, JPEG | The format the next person actually needs, locked when it matters |
| 📖 | **Read comfortably** — distraction-free Reader Mode, plus Night Mode with Gentle/Paper/Amber warmth presets | Long documents that don't fight your eyes or your focus |
| 🕘 | **Pick up where you left off** — a Recently Viewed shelf on the empty-state screen, with local thumbnails | One click back into the file you had open yesterday |
| 🌐 | **Work in your language** — full UI in English, Spanish, French, Hindi, Simplified Chinese, and Japanese | An app that speaks your language, switchable from the landing screen |

> [!TIP]
> **Meet Gami & Ori 🤝** — Orifold ships with a small built-in companion that offers short, useful hints for moments that matter (Gami: "Exporting? I can walk you through the options." · Ori: "Gami would chase the cursor. I prefer strategy."). Hints keep clear of your document and collapse to a quiet corner badge rather than sit on top of your page. Helpful when you're new, easy to quiet when you're not: toggle **Hide Gami Tips** from the companion's own popover, or **Show Orifold Buddy** from the app's menu to hide it entirely.

<details>
<summary>📋 &nbsp;Full capability list, feature by feature</summary>

<br>

| Area | What you can do |
| --- | --- |
| **Import** | Open PDFs, Word documents, HTML, Markdown, text, CSV, JSON, XML, and common image formats — up to 50 files per workspace; corrupt PDFs are repaired via qpdf recovery when the native reader gives up |
| **Organize** | Reorder documents and pages, rotate, delete, add section banners, navigate from the sidebar |
| **Read & search** | Native PDF canvas, page indicator, inspector, workspace-wide search, password unlock prompts, distraction-free Reader Mode, Night Mode with Gentle/Paper/Amber warmth-and-dimming presets |
| **Recently viewed** | An empty-state shelf of the last files you opened, with locally cached page thumbnails — nothing about it ever leaves the machine |
| **Annotate** | Highlight, notes, ink, underline, strikeout, text boxes, and in-place editing of detected PDF text |
| **Comments & metadata** | Workspace comments, tags, document details, inspector-visible annotation lists |
| **Signatures** | Draw and place signatures, export signed PDFs locally |
| **Forms** | Detect PDF form fields, edit answers, reset forms, lock answers during export |
| **Scans & OCR** | Local Vision OCR makes scans searchable; recognized text survives export |
| **Stamps & decorations** | Watermarks, page numbers, Bates labels, movable stamps burned into exported PDFs |
| **Compression** | Downsample oversized PDF images, then a lossless qpdf object-stream pass repacks the structure; post-compression validation confirms the result |
| **Sanitize** | Optional export pass strips catalog auto-run actions, embedded JavaScript, embedded files, and (opt-in) document metadata |
| **Protection** | Real AES-256 (PDF 2.0 / R6) password protection with permission checks and post-export verification |
| **Export integrity** | Every exported PDF passes a qpdf structural check before it reaches disk |
| **Export** | PDF, DOCX, Markdown, plain text, HTML, PNG pages, JPEG pages, or print |
| **Languages** | Full interface localization in English, Spanish, French, Hindi, Simplified Chinese, and Japanese, switchable from the landing screen and persisted across launches |
| **Companion** | Gami · Orifold Guide (an origami Bernedoodle) or Ori (an origami Siberian) — an optional companion, each with its own personality and voice, that offers brief hints for exporting, saving, and warnings, with positioning that keeps clear of your document; switch between them anytime, toggle tips from the popover, or hide it entirely from the app menu |
| **Install & update** | One-line installer, Desktop launch/update helpers, clean uninstaller, Homebrew cask |
</details>

## 💡 Three Tips Worth Knowing

1. **Merging isn't a separate step.** Drop files in, rearrange pages in the sidebar until the workspace tells the story you need, export once.
2. **Flatten before sharing.** Locking form answers and baking stamps at export means nobody "accidentally" edits your final copy.
3. **⌘Z is fearless.** Page deletes, rotations, and edits all live in undo history, so experiment freely.

## 🔒 Privacy

Orifold is local-first by design — not as a setting, as an architecture.

- 🖥️ **Everything runs on your Mac.** Import, OCR, compression, encryption, and export never touch a network.
- 🛡️ **Sandboxed.** The app uses macOS App Sandbox with user-selected file access only.
- 📡 **Zero telemetry.** There is no analytics pipeline. There isn't even a server to send it to.

<details>
<summary>🔍 &nbsp;The fine print (sandbox entitlements & guardrails)</summary>

<br>

The app enables exactly two entitlements:

- `com.apple.security.app-sandbox`
- `com.apple.security.files.user-selected.read-write`

Practical guardrails include password prompts for protected PDFs, import size limits, local validation before and after compression or encryption, a qpdf structural check gating every export, an optional sanitize pass that strips auto-run actions and embedded JavaScript, form flattening before decoration burn-in, export error reporting for malformed PDFs or failed writes, and hidden Orifold comment metadata stripped before flat PDF export.
</details>

## 🔄 Updating & Uninstalling

**Update:** double-click **Orifold.command** on your Desktop. It checks the latest release before launching and sweeps up any stray `Orifold.app` copies (e.g. one dragged straight into `/Applications`) so only one install remains. That's the entire procedure — you may cancel the calendar reminder.

**Uninstall:** double-click **Uninstall Orifold.command**. It removes the app, the Desktop helpers, the installer cache, and app data — a cleaner exit than most software manages.

<details>
<summary>⚙️ &nbsp;Homebrew and advanced options</summary>

<br>

Update via Homebrew:

```zsh
brew update
brew upgrade --cask udhawan97/orifold/orifold
```

Uninstall via Homebrew:

```zsh
brew uninstall --cask udhawan97/orifold/orifold
```

Uninstall but keep preferences, caches, and sandbox data:

```zsh
curl -fsSL https://raw.githubusercontent.com/udhawan97/Orifold/main/scripts/uninstall-mac.sh | zsh -s -- --keep-user-data
```
</details>

## 🏗️ Under the Hood

*For developers, contributors, and anyone evaluating how this is built.*

| | |
| --- | --- |
| **Language** | Swift 5.9+, 100% SwiftUI interface |
| **Codebase** | 78 Swift source files, ~35,000 lines |
| **Tests** | 449 tests gating every release |
| **Languages** | English, Spanish, French, Hindi, Simplified Chinese, Japanese — coverage enforced by a test |
| **PDF engines** | PDFKit (composition) + PDFium (image compression) + qpdf (repair, AES-256, sanitize, structural validation) + Vision (OCR) |
| **Architecture** | Unidirectional flow: views → one observable view model → protocol-seamed local engines → staged export pipeline |
| **Distribution** | GitHub Actions builds the release zip; installer, Homebrew cask, and uninstaller ship from this repo |

<p align="center">
  <img src="docs/assets/orifold-v3-architecture-diagram.svg" alt="Orifold architecture: SwiftUI views send intents to one observable view model, local PDF engines behind protocol seams do the work, and a staged export pipeline writes validated artifacts inside a local-only boundary, guarded by a release gate">
</p>

<details>
<summary>🧱 &nbsp;Layer-by-layer responsibilities</summary>

<br>

| Layer | Responsibility |
| --- | --- |
| SwiftUI app | Document window, sidebar, canvas, annotation toolbar, search, inspector, password prompts, export controls, empty-state Recently Viewed shelf, language switcher |
| Workspace state | Imported documents, page order, undo snapshots, comments, tags, signatures, form summaries, decorations, recent-file history |
| PDF services | PDFKit composition, PDFium image compression, qpdf repair/AES-256/sanitize/structural validation, Vision OCR, form flattening, decoration baking, signing helpers |
| Local storage | Saved PDF data, workspace metadata, source payloads, comments, signatures, page edit state |
| Release tooling | One-line installer, package builder, Desktop update launcher, uninstaller, GitHub Actions release asset, validation tests |

```mermaid
flowchart LR
    Files["📁 Source files<br/>PDF, Word, HTML, Markdown, text, data, images"]
    UI["🖼️ SwiftUI views<br/>sidebar, canvas, toolbar, inspector"]
    State["🧠 Workspace state<br/>pages, comments, forms, decorations"]
    Services["⚙️ Local engines<br/>PDFKit, PDFium, qpdf, Vision OCR, signing"]
    Export["📤 Export pipeline<br/>flatten, bake, compress, sanitize, encrypt, validate"]
    Artifacts["✅ Artifacts<br/>PDF, DOCX, MD, TXT, HTML, PNG, JPEG"]

    Files --> UI --> State --> Services --> Export --> Artifacts
```
</details>

<details>
<summary>📁 &nbsp;Project layout</summary>

<br>

```text
Orifold/
  App/             App entry point and command wiring
  DesignSystem/    Shared visual tokens and styling
  Document/        macOS document package read/write support
  Engine/          PDF loading, repair, conversion, OCR, compression, encryption, sanitize, forms, export, Recently Viewed store
  Models/          Workspace, page, annotation, comment, export, decoration, and recent-file models
  Pet/             Gami & Ori, the in-app companions, plus hint bubble/placement logic
  Resources/       App metadata, entitlements, assets, Localizable.xcstrings (6 languages)
  Signing/         Signing identities, CMS construction, timestamping, verification
  ViewModels/      Workspace state, document operations, search, export, undo
  Views/           SwiftUI interface components
Packages/          Vendored binary engines — PDFiumBinary, QPDFBinary (universal static libs)
Tests/             Test suites run in the release gate
scripts/
  install-mac.sh   Release-first installer, source builder, release packager
  uninstall-mac.sh Clean uninstaller
install.sh         Hosted one-line bootstrap
Casks/orifold.rb   Homebrew cask
```
</details>

<details>
<summary>🔨 &nbsp;Build, test, and package</summary>

<br>

Open in Xcode:

```zsh
open Orifold.xcodeproj
```

Build and test:

```zsh
swift build
swiftlint lint --quiet
swift test --filter PDFSmokeTests  # fast PDF load/export sanity check
swift test
xcodebuild build -quiet -project Orifold.xcodeproj -scheme Orifold -destination 'generic/platform=macOS' CODE_SIGNING_ALLOWED=NO
xcodebuild test -quiet -project Orifold.xcodeproj -scheme Orifold -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

Create the same release zip GitHub Releases ships:

```zsh
./scripts/install-mac.sh --package-only --package /tmp/Orifold.zip
```

Install from the current source checkout without opening the app:

```zsh
./scripts/install-mac.sh --no-open
```

App metadata: `CFBundleShortVersionString` `0.8.1`, `CFBundleVersion` `8`.
</details>

<details>
<summary>✍️ &nbsp;Signed & notarized release builds</summary>

<br>

```zsh
ORIFOLD_SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
ORIFOLD_NOTARIZE=1 \
ORIFOLD_APPLE_ID="apple-id@example.com" \
ORIFOLD_APPLE_TEAM_ID="TEAMID" \
ORIFOLD_APPLE_APP_SPECIFIC_PASSWORD="app-specific-password" \
./scripts/install-mac.sh --package-only --package /tmp/Orifold.zip
```

GitHub Actions uses the same path when these secrets are configured: `ORIFOLD_DEVELOPER_ID_CERTIFICATE_BASE64`, `ORIFOLD_DEVELOPER_ID_CERTIFICATE_PASSWORD`, `ORIFOLD_SIGNING_IDENTITY`, `ORIFOLD_APPLE_ID`, `ORIFOLD_APPLE_TEAM_ID`, `ORIFOLD_APPLE_APP_SPECIFIC_PASSWORD`.
</details>

<details>
<summary>✅ &nbsp;Release gate — every command that must pass before shipping</summary>

<br>

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
swiftlint lint --quiet
swift test
xcodebuild build -quiet -project Orifold.xcodeproj -scheme Orifold -destination 'generic/platform=macOS' CODE_SIGNING_ALLOWED=NO
xcodebuild test -quiet -project Orifold.xcodeproj -scheme Orifold -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
./scripts/install-mac.sh --package-only --package /tmp/Orifold.zip
```

Plus a manual pass on the user workflow: import, search, annotate, forms, OCR, stamps, compression, protected export, update, uninstall.
</details>

## 🔧 Troubleshooting

<details>
<summary>Clicking the installer link opens a GitHub page instead of installing</summary>

<br>

That's expected — README links open files in the browser; they don't execute installer scripts. Copy the [install command](#-install-in-30-seconds) into Terminal instead.
</details>

<details>
<summary>macOS warns the app is from an unidentified developer</summary>

<br>

Release builds are ad-hoc signed but not notarized. The one-line installer and Homebrew cask clear the download quarantine automatically. If macOS still warns, right-click the app in Finder and choose **Open** from the security prompt.
</details>

<details>
<summary>Double-clicking a <code>.command</code> file says it cannot be opened</summary>

<br>

Open Terminal in the project folder and run:

```zsh
chmod +x "Install or Update Orifold.command" "Uninstall Orifold.command" "Install or Update Orifold.app/Contents/MacOS/OrifoldInstaller" scripts/install-mac.sh scripts/install-mac.command scripts/uninstall-mac.sh
```

Then double-click `Install or Update Orifold.app` again from Finder.
</details>

<details>
<summary>The installer says no prebuilt release is available</summary>

<br>

The GitHub release asset `Orifold.zip` hasn't been published yet or couldn't be downloaded. Wait for the release workflow, then rerun the installer. Developers can opt into a source build:

```zsh
curl -fsSL https://raw.githubusercontent.com/udhawan97/Orifold/main/install.sh | ORIFOLD_ALLOW_SOURCE_BUILD=1 zsh
```
</details>

<details>
<summary>Something failed and the Terminal window closed too fast</summary>

<br>

Check `.build/install.log` in the project folder for build output, and `~/.orifold/prebuilt-install.log` for the prebuilt install attempt.
</details>

## 🗺️ Roadmap

- True content redaction (remove text/images, not just cover them)
- Side-by-side document compare
- Faster large-document navigation
- Automated UI smoke tests

## 🤝 Contributing

Bug reports and feature requests are welcome in [Issues](https://github.com/udhawan97/Orifold/issues). Building from source? [Under the Hood](#%EF%B8%8F-under-the-hood) is the whole onboarding doc — if `swift test` passes, you're set up.

## 📜 License

Orifold is available under the [MIT License](LICENSE).

---

<p align="center">
  If Orifold rescued you from <code>final_final_revised_ACTUAL_v3.pdf</code>, consider
  <a href="https://github.com/udhawan97/Orifold/stargazers">starring the repo</a>.<br>
  Since nothing you do in Orifold ever leaves your Mac, stars are the only telemetry we get.
</p>

<p align="center">
 Built as a local-first PDF workspace. I used Claude/Codex to accelerate implementation, then manually reviewed, tested, refactored, and documented the system
</p>
