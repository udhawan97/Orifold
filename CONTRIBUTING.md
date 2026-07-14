# Contributing to Orifold

Thanks for your interest in improving Orifold — a calm, local-first PDF workspace for macOS. Contributions of all kinds are welcome: bug reports, feature ideas, documentation, translations, and code.

By participating, you agree to abide by our [Code of Conduct](CODE_OF_CONDUCT.md).

## Ways to contribute

- **Report a bug** — open an issue using the [bug report template](.github/ISSUE_TEMPLATE/bug_report.md).
- **Request a feature** — open an issue using the [feature request template](.github/ISSUE_TEMPLATE/feature_request.md).
- **Improve docs** — fixes to the README, `docs/`, or the docs-site are always appreciated.
- **Add a translation** — Orifold ships in 6 languages via `Localizable.xcstrings`.
- **Fix or build something** — see the workflow below.

## Development setup

Orifold is a native macOS app (macOS 14+) built with SwiftUI and PDFium.

```bash
# Clone
git clone https://github.com/udhawan97/Orifold
cd Orifold

# Generate the Xcode project (requires XcodeGen)
xcodegen generate

# Open in Xcode, or build from the command line
swift build
swift test
```

Requirements:

- macOS 14 or later
- Xcode 16+
- [XcodeGen](https://github.com/yonsson/XcodeGen) — `brew install xcodegen`

## Pull request workflow

1. **Fork** the repo and create a branch from `main`.
2. **Make focused changes** — keep each PR to a single logical unit.
3. **Add tests** where it makes sense, and make sure `swift test` passes.
4. **Run a release build** after touching any native/C-interop bindings: `swift build -c release` (some binding issues only surface under whole-module optimization).
5. **Keep it local-first** — Orifold makes no network calls for document processing. Nothing about a user's files should leave their Mac.
6. **Open a PR** against `main` with a clear description of what changed and why.

## Coding guidelines

- Match the style of the surrounding code — naming, structure, and idiom.
- Keep the UI calm and uncluttered; new surface area should earn its place.
- Prefer PDFium (`FPDFText`) over PDFKit for text extraction — PDFKit behaves inconsistently across SDK versions.
- User-facing strings must go through `L10n` and be added to all supported languages.

## Reporting security issues

Please do **not** open public issues for security vulnerabilities. See [SECURITY.md](SECURITY.md) for how to report them privately.

## Questions

Open a [discussion or issue](https://github.com/udhawan97/Orifold/issues) — happy to help.
