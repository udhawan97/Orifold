import Foundation
import Darwin

/// Generates the unsandboxed `.command` that performs the actual app swap and relaunch.
///
/// A sandboxed app cannot replace its own bundle, so on install the app writes this script
/// into the updater cache and opens it (`NSWorkspace.open` → Terminal, outside the sandbox).
/// The script waits for the app to quit, re-verifies the DMG, then does a **stage-then-swap**
/// (copy new bundle beside the target, then two fast renames) so the window where no app
/// exists on disk is a rename, not a multi-second copy — and restores the old bundle if any
/// step fails.
///
/// The template is embedded (compiled into, and code-signed with, the app) rather than a
/// loose resource — one less thing that can go missing at runtime. Injected values are
/// single-quoted and pre-validated (digest = 64 hex, PID = positive integer, no single
/// quotes in any path), so there is no shell-injection surface.
struct UpdaterScriptGenerator {
    enum GeneratorError: Error, Equatable {
        case invalidPID
        case invalidDigest
        case unsafeValue(String)
        case writeFailed
        case quarantineRemovalFailed
    }

    struct Inputs {
        var appPID: Int32
        var appBundlePath: String
        var dmgPath: String
        var dmgSHA256: String
        var newVersion: String
        var rollbackZipPath: String?
        /// Command used to relaunch the installed app. `open` in production; overridden in
        /// tests so the swap can be verified without actually launching anything.
        var relaunchCommand: String = "/usr/bin/open"
    }

    /// Inputs for restoring the archived previous version (a zip of the `.app`) rather than
    /// installing a downloaded DMG. Same stage-then-swap contract; the source is a zip that is
    /// extracted instead of a disk image that is mounted.
    struct RestoreInputs {
        var appPID: Int32
        var appBundlePath: String
        var archiveZipPath: String
        var archiveSHA256: String
        var restoreVersion: String
        var relaunchCommand: String = "/usr/bin/open"
    }

    func render(_ inputs: Inputs) throws -> String {
        guard inputs.appPID > 0 else { throw GeneratorError.invalidPID }

        let digest = inputs.dmgSHA256.lowercased()
        guard digest.count == 64, digest.allSatisfy(\.isHexDigit) else { throw GeneratorError.invalidDigest }

        // A single quote in any injected value would break out of the single-quoted shell
        // assignment; reject rather than try to escape. Required values must be non-empty.
        let required = [inputs.appBundlePath, inputs.dmgPath, inputs.newVersion, inputs.relaunchCommand]
        for value in required where value.isEmpty || value.contains("'") {
            throw GeneratorError.unsafeValue(value)
        }
        let rollback = inputs.rollbackZipPath ?? ""
        if rollback.contains("'") { throw GeneratorError.unsafeValue(rollback) }

        return Self.template
            .replacingOccurrences(of: "@@APP_PID@@", with: String(inputs.appPID))
            .replacingOccurrences(of: "@@APP_PATH@@", with: inputs.appBundlePath)
            .replacingOccurrences(of: "@@DMG_PATH@@", with: inputs.dmgPath)
            .replacingOccurrences(of: "@@EXPECTED_SHA@@", with: digest)
            .replacingOccurrences(of: "@@NEW_VERSION@@", with: inputs.newVersion)
            .replacingOccurrences(of: "@@ROLLBACK_ZIP@@", with: rollback)
            .replacingOccurrences(of: "@@RELAUNCH_CMD@@", with: inputs.relaunchCommand)
    }

    /// Renders and writes the script into `directory` as an executable `.command`, returning
    /// its URL for `NSWorkspace.open`.
    func write(_ inputs: Inputs, to directory: URL = UpdateStorePaths.updaterCacheDirectory()) throws -> URL {
        let script = try render(inputs)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("orifold-updater.command")
        guard let data = script.data(using: .utf8) else { throw GeneratorError.writeFailed }
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        try prepareForLaunch(url)
        return url
    }

    /// Renders the restore `.command`, which extracts the archived previous-version zip and
    /// swaps it into place using the same stage-then-swap + verify contract as an update.
    func renderRestore(_ inputs: RestoreInputs) throws -> String {
        guard inputs.appPID > 0 else { throw GeneratorError.invalidPID }

        let digest = inputs.archiveSHA256.lowercased()
        guard digest.count == 64, digest.allSatisfy(\.isHexDigit) else { throw GeneratorError.invalidDigest }

        let required = [inputs.appBundlePath, inputs.archiveZipPath, inputs.restoreVersion, inputs.relaunchCommand]
        for value in required where value.isEmpty || value.contains("'") {
            throw GeneratorError.unsafeValue(value)
        }

        return Self.restoreTemplate
            .replacingOccurrences(of: "@@APP_PID@@", with: String(inputs.appPID))
            .replacingOccurrences(of: "@@APP_PATH@@", with: inputs.appBundlePath)
            .replacingOccurrences(of: "@@ARCHIVE_ZIP@@", with: inputs.archiveZipPath)
            .replacingOccurrences(of: "@@EXPECTED_SHA@@", with: digest)
            .replacingOccurrences(of: "@@RESTORE_VERSION@@", with: inputs.restoreVersion)
            .replacingOccurrences(of: "@@RELAUNCH_CMD@@", with: inputs.relaunchCommand)
    }

    /// Renders and writes the restore script as an executable `.command`.
    func writeRestore(_ inputs: RestoreInputs, to directory: URL = UpdateStorePaths.updaterCacheDirectory()) throws -> URL {
        let script = try renderRestore(inputs)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("orifold-restore.command")
        guard let data = script.data(using: .utf8) else { throw GeneratorError.writeFailed }
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        try prepareForLaunch(url)
        return url
    }

    /// Makes a generated executable eligible for LaunchServices hand-off.
    ///
    /// macOS quarantines files created by an App Sandbox process. Opening a quarantined
    /// `.command` asks Gatekeeper to execute that newly-created file and is rejected with
    /// OSStatus -67026 ("File created by an AppSandbox, exec/open not allowed"), surfaced to
    /// users as a misleading damaged-file alert. The script is generated from a template
    /// embedded in Orifold's signed bundle, so remove only that launch-blocking attribute
    /// immediately after writing it. Sandbox provenance remains intact.
    func prepareForLaunch(_ url: URL) throws {
        let result = url.path.withCString { path in
            "com.apple.quarantine".withCString { attribute in
                removexattr(path, attribute, 0)
            }
        }
        guard result == 0 || errno == ENOATTR else {
            throw GeneratorError.quarantineRemovalFailed
        }
    }

    // MARK: - Template

    static let template = ##"""
    #!/bin/zsh -f
    set -u

    # Generated by Orifold to install a verified update. Every value below is injected by
    # the app, single-quoted and pre-validated (digest = 64 hex, pid = integer, no quotes).
    APP_PID='@@APP_PID@@'
    APP_PATH='@@APP_PATH@@'
    DMG_PATH='@@DMG_PATH@@'
    EXPECTED_SHA='@@EXPECTED_SHA@@'
    NEW_VERSION='@@NEW_VERSION@@'
    ROLLBACK_ZIP='@@ROLLBACK_ZIP@@'
    RELAUNCH_CMD='@@RELAUNCH_CMD@@'

    PATH="/usr/bin:/bin:/usr/sbin:/sbin"
    MOUNT="${TMPDIR:-/tmp}/orifold-update-mount-$$"
    STAGING="${APP_PATH}.update-staging-$$"
    BACKUP="${APP_PATH}.previous-$$"

    say() { printf "%s\n" "$1"; }

    cleanup() {
        [[ -d "$MOUNT" ]] && hdiutil detach "$MOUNT" -quiet 2>/dev/null
        [[ -d "$STAGING" ]] && rm -rf "$STAGING" 2>/dev/null
    }

    fail() {
        cleanup
        say ""
        say "The update did not complete. Your current version was not changed."
        say "$1"
        say ""
        say "Press Return to close this window."
        read -r _
        exit 1
    }

    # After the old bundle has been moved aside, a failure must put it back — even if the
    # swap already succeeded and a (possibly-unlaunchable) new bundle now sits at APP_PATH
    # (e.g. post-swap verification failed). Remove whatever is at the target first, then
    # restore the known-good backup (or the rollback archive); never leave the new one.
    restore_and_fail() {
        if [[ -d "$BACKUP" ]]; then
            rm -rf "$APP_PATH" 2>/dev/null
            mv "$BACKUP" "$APP_PATH" 2>/dev/null
        elif [[ -n "$ROLLBACK_ZIP" && -f "$ROLLBACK_ZIP" ]]; then
            rm -rf "$APP_PATH" 2>/dev/null
            ditto -x -k "$ROLLBACK_ZIP" "$(dirname "$APP_PATH")" 2>/dev/null
        fi
        fail "$1"
    }

    printf "\033]0;Orifold Updater\007"
    say "Installing Orifold $NEW_VERSION…"

    # 1. Wait (max 60s) for the old app to quit. A stale/gone PID proceeds immediately.
    if [[ "$APP_PID" == <-> ]]; then
        i=0
        while kill -0 "$APP_PID" 2>/dev/null; do
            sleep 0.5
            i=$((i + 1))
            [[ $i -ge 120 ]] && fail "Orifold is still running, so nothing was changed."
        done
    fi

    # 2. Re-verify the download immediately before installing (closes the verify→install gap).
    [[ -f "$DMG_PATH" ]] || fail "The downloaded update could not be found."
    ACTUAL_SHA="$(shasum -a 256 "$DMG_PATH" 2>/dev/null | awk '{print $1}')"
    [[ "$ACTUAL_SHA" == "$EXPECTED_SHA" ]] || fail "The downloaded update failed its integrity check."

    # 3. Refuse unsafe / meaningless install targets.
    case "$APP_PATH" in
        */Orifold.app) : ;;
        *) fail "Unexpected app location; nothing was changed." ;;
    esac
    case "$APP_PATH" in
        /Volumes/*|/private/var/folders/*)
            fail "Orifold is running from a temporary location. Move it to Applications, then update." ;;
    esac
    [[ -d "$APP_PATH" ]] || fail "The current app was not found where expected."
    [[ -w "$(dirname "$APP_PATH")" ]] || fail "No permission to update Orifold in $(dirname "$APP_PATH")."

    # 4. Mount the verified image.
    mkdir -p "$MOUNT"
    hdiutil attach "$DMG_PATH" -nobrowse -readonly -mountpoint "$MOUNT" -quiet \
        || fail "Could not open the update disk image."
    NEW_APP="$(find "$MOUNT" -maxdepth 2 -name 'Orifold.app' -type d -print -quit)"
    [[ -n "$NEW_APP" ]] || fail "The update image did not contain Orifold."

    # 5. Verify the new app's signature before trusting it.
    codesign --verify --deep --strict "$NEW_APP" 2>/dev/null \
        || fail "The update's signature could not be verified."

    # 6. Stage beside the target so the swap is two renames, not a slow copy.
    rm -rf "$STAGING"
    ditto "$NEW_APP" "$STAGING" || fail "Could not copy the new version into place."

    # 7. Swap. From here on, any failure restores the previous version.
    rm -rf "$BACKUP"
    mv "$APP_PATH" "$BACKUP" || fail "Could not move the current version aside."
    mv "$STAGING" "$APP_PATH" || restore_and_fail "Could not move the new version into place."

    # 8. Strip quarantine and verify the installed copy.
    xattr -cr "$APP_PATH" 2>/dev/null
    codesign --verify --deep --strict "$APP_PATH" 2>/dev/null \
        || restore_and_fail "The installed app failed verification."

    # 9. Success: clean up and relaunch the new version.
    rm -rf "$BACKUP"
    [[ -d "$MOUNT" ]] && hdiutil detach "$MOUNT" -quiet 2>/dev/null
    rm -f "$DMG_PATH" 2>/dev/null

    if ! "$RELAUNCH_CMD" "$APP_PATH"; then
        say "Installed, but could not relaunch automatically. Open Orifold from Applications."
    fi
    say "Orifold $NEW_VERSION is installed."
    exit 0
    """##

    // Restore template: same stage-then-swap + verify + relaunch contract as `template`, but the
    // source is the archived previous-version zip (extracted) instead of a downloaded DMG
    // (mounted). Kept as a separate template so the shipped, dry-run-tested update path stays
    // byte-for-byte untouched.
    static let restoreTemplate = ##"""
    #!/bin/zsh -f
    set -u

    # Generated by Orifold to restore the previous version. Every value below is injected by
    # the app, single-quoted and pre-validated (digest = 64 hex, pid = integer, no quotes).
    APP_PID='@@APP_PID@@'
    APP_PATH='@@APP_PATH@@'
    ARCHIVE_ZIP='@@ARCHIVE_ZIP@@'
    EXPECTED_SHA='@@EXPECTED_SHA@@'
    RESTORE_VERSION='@@RESTORE_VERSION@@'
    RELAUNCH_CMD='@@RELAUNCH_CMD@@'

    PATH="/usr/bin:/bin:/usr/sbin:/sbin"
    EXTRACT="${TMPDIR:-/tmp}/orifold-restore-extract-$$"
    STAGING="${APP_PATH}.restore-staging-$$"
    BACKUP="${APP_PATH}.replaced-$$"

    say() { printf "%s\n" "$1"; }

    cleanup() {
        [[ -d "$EXTRACT" ]] && rm -rf "$EXTRACT" 2>/dev/null
        [[ -d "$STAGING" ]] && rm -rf "$STAGING" 2>/dev/null
    }

    fail() {
        cleanup
        say ""
        say "Restore did not complete. Your current version was not changed."
        say "$1"
        say ""
        say "Press Return to close this window."
        read -r _
        exit 1
    }

    # After the current bundle has been moved aside, a failure must put it back — whether the
    # target slot is empty (a failed swap) OR now holds a restored bundle that failed its
    # post-swap verification (remove it first, then restore the known-good backup).
    restore_and_fail() {
        if [[ -d "$BACKUP" ]]; then
            rm -rf "$APP_PATH" 2>/dev/null
            mv "$BACKUP" "$APP_PATH" 2>/dev/null
        fi
        fail "$1"
    }

    printf "\033]0;Orifold Restore\007"
    say "Restoring Orifold $RESTORE_VERSION…"

    # 1. Wait (max 60s) for the running app to quit. A stale/gone PID proceeds immediately.
    if [[ "$APP_PID" == <-> ]]; then
        i=0
        while kill -0 "$APP_PID" 2>/dev/null; do
            sleep 0.5
            i=$((i + 1))
            [[ $i -ge 120 ]] && fail "Orifold is still running, so nothing was changed."
        done
    fi

    # 2. Re-verify the archive immediately before restoring.
    [[ -f "$ARCHIVE_ZIP" ]] || fail "The saved previous version could not be found."
    ACTUAL_SHA="$(shasum -a 256 "$ARCHIVE_ZIP" 2>/dev/null | awk '{print $1}')"
    [[ "$ACTUAL_SHA" == "$EXPECTED_SHA" ]] || fail "The saved previous version failed its integrity check."

    # 3. Refuse unsafe / meaningless targets (mirrors the updater).
    case "$APP_PATH" in
        */Orifold.app) : ;;
        *) fail "Unexpected app location; nothing was changed." ;;
    esac
    case "$APP_PATH" in
        /Volumes/*|/private/var/folders/*)
            fail "Orifold is running from a temporary location. Move it to Applications, then restore." ;;
    esac
    [[ -d "$APP_PATH" ]] || fail "The current app was not found where expected."
    [[ -w "$(dirname "$APP_PATH")" ]] || fail "No permission to restore Orifold in $(dirname "$APP_PATH")."

    # 4. Extract the verified archive and locate the restored bundle.
    rm -rf "$EXTRACT"; mkdir -p "$EXTRACT"
    ditto -x -k "$ARCHIVE_ZIP" "$EXTRACT" || fail "Could not read the saved previous version."
    OLD_APP="$(find "$EXTRACT" -maxdepth 2 -name 'Orifold.app' -type d -print -quit)"
    [[ -n "$OLD_APP" ]] || fail "The saved archive did not contain Orifold."

    # 5. Verify the restored bundle's signature before trusting it.
    codesign --verify --deep --strict "$OLD_APP" 2>/dev/null \
        || fail "The saved version's signature could not be verified."

    # 6. Stage beside the target so the swap is two renames, not a slow copy.
    rm -rf "$STAGING"
    ditto "$OLD_APP" "$STAGING" || fail "Could not copy the previous version into place."

    # 7. Swap. From here on, any failure restores the current version.
    rm -rf "$BACKUP"
    mv "$APP_PATH" "$BACKUP" || fail "Could not move the current version aside."
    mv "$STAGING" "$APP_PATH" || restore_and_fail "Could not move the previous version into place."

    # 8. Strip quarantine and verify the restored copy.
    xattr -cr "$APP_PATH" 2>/dev/null
    codesign --verify --deep --strict "$APP_PATH" 2>/dev/null \
        || restore_and_fail "The restored app failed verification."

    # 9. Success: clean up and relaunch the restored version.
    rm -rf "$BACKUP"
    cleanup

    if ! "$RELAUNCH_CMD" "$APP_PATH"; then
        say "Restored, but could not relaunch automatically. Open Orifold from Applications."
    fi
    say "Orifold $RESTORE_VERSION is restored."
    exit 0
    """##
}
