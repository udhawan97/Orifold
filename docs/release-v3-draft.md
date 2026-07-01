# PDFold v3.0 Release Draft

## GitHub Release Fields

Tag: `v3.0`

Target: `main`

Release title: `PDFold v3.0 - automatic updates and clean uninstall`

Asset to upload: `pdFold.zip`

Build the asset with:

```zsh
./scripts/install-mac.sh --package-only --package /tmp/pdFold.zip
```

## Release Notes

PDFold v3.0 keeps the local-first document workspace from v2, adds a supplemental local PDF processing backend, and improves the install lifecycle: normal launches now check for updates automatically, and users get a dedicated clean uninstall command.

### What's Changed

- Automatic update check on launch: the Desktop `pdFold.command` launcher runs the installer/updater every time it opens pdFold, so users do not need a separate update command.
- Clean uninstall command: installs now create `Uninstall pdFold.command` on the Desktop.
- Local PDF processing backend: PDF imports now flow through an injectable `PDFProcessingEngine`, with PDFium-backed validation and a PDFKit fallback path.
- Uninstaller script: `scripts/uninstall-mac.sh` removes `~/Applications/pdFold.app`, generated Desktop commands, the `~/.pdfold` installer cache, PDFold app support data, preferences, caches, saved state, and sandbox container data.
- User files are preserved: saved `.pdfoldproj` workspace documents are not removed by uninstall.
- Legacy cleanup: install/update/uninstall flows remove the old `Update pdFold.command` artifact.
- Release metadata bumped to `CFBundleShortVersionString` `3.0` and `CFBundleVersion` `3`.
- README setup, update, uninstall, quality, and troubleshooting sections now match the v3 flow.

### Install

```zsh
curl -fsSL https://raw.githubusercontent.com/udhawan97/PDFold/main/install.sh | zsh
```

The installer downloads the latest `pdFold.zip`, installs `pdFold.app` to `~/Applications`, creates Desktop commands for launch/update and uninstall, clears quarantine metadata, and opens pdFold.

### Update

After installing v3, double-click `pdFold.command` on the Desktop. It checks the latest release before opening the app.

### Uninstall

Double-click `Uninstall pdFold.command` on the Desktop.

To keep PDFold app support, preferences, caches, and sandbox data:

```zsh
curl -fsSL https://raw.githubusercontent.com/udhawan97/PDFold/main/scripts/uninstall-mac.sh | zsh -s -- --keep-user-data
```

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
plutil -lint "Install or Update pdFold.app/Contents/Info.plist"
swift build
./scripts/install-mac.sh --package-only --package /tmp/pdFold.zip
```

### Release Checklist

- Confirm `PDFold/Resources/Info.plist` is `3.0` / `3`.
- Confirm `project.yml` is `3.0` / `3`.
- Run the verification commands above.
- Upload `/tmp/pdFold.zip` as `pdFold.zip`.
- Publish the release with tag `v3.0`.
