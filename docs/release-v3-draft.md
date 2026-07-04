# Orifold v3.0 Release Draft

## GitHub Release Fields

Tag: `v3.0`

Target: `main`

Release title: `Orifold v3.0 - automatic updates and clean uninstall`

Asset to upload: `Orifold.zip`

Build the asset with:

```zsh
./scripts/install-mac.sh --package-only --package /tmp/Orifold.zip
```

## Release Notes

Orifold v3.0 keeps the local-first document workspace from v2, adds a supplemental local PDF processing backend, and improves the install lifecycle: normal launches now check for updates automatically, and users get a dedicated clean uninstall command.

### What's Changed

- Automatic update check on launch: the Desktop `Orifold.command` launcher runs the installer/updater every time it opens Orifold, so users do not need a separate update command.
- Clean uninstall command: installs now create `Uninstall Orifold.command` on the Desktop.
- Local PDF processing backend: PDF imports now flow through an injectable `PDFProcessingEngine`, with PDFium-backed validation and a PDFKit fallback path.
- Uninstaller script: `scripts/uninstall-mac.sh` removes `~/Applications/Orifold.app`, generated Desktop commands, the `~/.orifold` installer cache, Orifold app support data, preferences, caches, saved state, and sandbox container data.
- User files are preserved: files created outside Orifold's app support directories are not removed by uninstall.
- Legacy cleanup: install/update/uninstall flows remove the old `Update Orifold.command` artifact.
- Release metadata bumped to `CFBundleShortVersionString` `3.0` and `CFBundleVersion` `3`.
- README setup, update, uninstall, quality, and troubleshooting sections now match the v3 flow.

### Install

```zsh
curl -fsSL https://raw.githubusercontent.com/udhawan97/Orifold/main/install.sh | zsh
```

The installer downloads the latest `Orifold.zip`, installs `Orifold.app` to `~/Applications`, creates Desktop commands for launch/update and uninstall, clears quarantine metadata, and opens Orifold. The release workflow also publishes a rolling `Orifold Latest` release from `main` so the one-line installer does not require Xcode or Apple's Command Line Tools.

### Update

After installing v3, double-click `Orifold.command` on the Desktop. It checks the latest release before opening the app.

### Uninstall

Double-click `Uninstall Orifold.command` on the Desktop.

To keep Orifold app support, preferences, caches, and sandbox data:

```zsh
curl -fsSL https://raw.githubusercontent.com/udhawan97/Orifold/main/scripts/uninstall-mac.sh | zsh -s -- --keep-user-data
```

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
plutil -lint "Install or Update Orifold.app/Contents/Info.plist"
swift build
./scripts/install-mac.sh --package-only --package /tmp/Orifold.zip
```

### Release Checklist

- Confirm `Orifold/Resources/Info.plist` is `3.0` / `3`.
- Confirm `project.yml` is `3.0` / `3`.
- Run the verification commands above.
- Confirm the rolling `Orifold Latest` release contains `Orifold.zip`.
- Publish the versioned release with tag `v3.0`; the workflow uploads `Orifold.zip`.
