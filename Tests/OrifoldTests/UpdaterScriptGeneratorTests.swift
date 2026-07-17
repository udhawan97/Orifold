import XCTest
@testable import Orifold

final class UpdaterScriptGeneratorTests: XCTestCase {
    private let generator = UpdaterScriptGenerator()

    private func inputs(
        pid: Int32 = 4321,
        appPath: String = "/Users/x/Applications/Orifold.app",
        dmg: String = "/Users/x/cache/Orifold-0.8.7.dmg",
        sha: String = String(repeating: "a", count: 64),
        version: String = "0.8.7",
        rollback: String? = nil,
        relaunch: String = "/usr/bin/open"
    ) -> UpdaterScriptGenerator.Inputs {
        .init(appPID: pid, appBundlePath: appPath, dmgPath: dmg, dmgSHA256: sha,
              newVersion: version, rollbackZipPath: rollback, relaunchCommand: relaunch)
    }

    // MARK: - Rendering & validation

    func testRenderSubstitutesEveryToken() throws {
        let script = try generator.render(inputs(rollback: "/Users/x/Rollback/Orifold-0.8.6.zip"))
        XCTAssertFalse(script.contains("@@"), "no placeholder token may survive rendering")
        XCTAssertTrue(script.contains("APP_PID='4321'"))
        XCTAssertTrue(script.contains("APP_PATH='/Users/x/Applications/Orifold.app'"))
        XCTAssertTrue(script.contains("EXPECTED_SHA='\(String(repeating: "a", count: 64))'"))
        XCTAssertTrue(script.contains("ROLLBACK_ZIP='/Users/x/Rollback/Orifold-0.8.6.zip'"))
        XCTAssertTrue(script.hasPrefix("#!/bin/zsh"))
    }

    func testRejectsNonHexOrWrongLengthDigest() {
        XCTAssertThrowsError(try generator.render(inputs(sha: "tooshort"))) {
            XCTAssertEqual($0 as? UpdaterScriptGenerator.GeneratorError, .invalidDigest)
        }
        XCTAssertThrowsError(try generator.render(inputs(sha: String(repeating: "z", count: 64)))) {
            XCTAssertEqual($0 as? UpdaterScriptGenerator.GeneratorError, .invalidDigest)
        }
    }

    func testRejectsNonPositivePID() {
        XCTAssertThrowsError(try generator.render(inputs(pid: 0))) {
            XCTAssertEqual($0 as? UpdaterScriptGenerator.GeneratorError, .invalidPID)
        }
    }

    func testRejectsSingleQuoteInPathsToPreventInjection() {
        XCTAssertThrowsError(try generator.render(inputs(appPath: "/Users/x/'; rm -rf ~/'/Orifold.app"))) {
            guard case UpdaterScriptGenerator.GeneratorError.unsafeValue = $0 else { return XCTFail("expected unsafeValue") }
        }
    }

    /// Files written by an App Sandbox process receive a quarantine attribute. LaunchServices
    /// refuses to execute such a generated `.command` with OSStatus -67026 (reported to the
    /// user as "damaged") even though the script is local and its contents are trusted.
    func testPrepareForLaunchRemovesSandboxQuarantine() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("orifold-script-quarantine-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let script = root.appendingPathComponent("orifold-updater.command")
        try "#!/bin/zsh\nexit 0\n".write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        try XCTAssertProcess("/usr/bin/xattr", ["-w", "com.apple.quarantine", "0086;00000000;Orifold;", script.path])
        XCTAssertEqual(try runProcess("/usr/bin/xattr", ["-p", "com.apple.quarantine", script.path]).status, 0)
        XCTAssertThrowsError(
            try runProcess(script.path, []),
            "the fixture must reproduce the sandbox-created executable rejection before the fix"
        )

        try generator.prepareForLaunch(script)

        XCTAssertNotEqual(
            try runProcess("/usr/bin/xattr", ["-p", "com.apple.quarantine", script.path]).status,
            0,
            "the generated executable must be de-quarantined before NSWorkspace opens it"
        )
        XCTAssertEqual(try runProcess(script.path, []).status, 0)
    }

    // MARK: - Restore rendering & validation

    private func restoreInputs(
        pid: Int32 = 4321,
        appPath: String = "/Users/x/Applications/Orifold.app",
        zip: String = "/Users/x/Rollback/Orifold-0.8.5.zip",
        sha: String = String(repeating: "b", count: 64),
        version: String = "0.8.5",
        relaunch: String = "/usr/bin/open"
    ) -> UpdaterScriptGenerator.RestoreInputs {
        .init(appPID: pid, appBundlePath: appPath, archiveZipPath: zip, archiveSHA256: sha,
              restoreVersion: version, relaunchCommand: relaunch)
    }

    func testRenderRestoreSubstitutesEveryToken() throws {
        let script = try generator.renderRestore(restoreInputs())
        XCTAssertFalse(script.contains("@@"), "no placeholder token may survive rendering")
        XCTAssertTrue(script.contains("APP_PID='4321'"))
        XCTAssertTrue(script.contains("ARCHIVE_ZIP='/Users/x/Rollback/Orifold-0.8.5.zip'"))
        XCTAssertTrue(script.contains("EXPECTED_SHA='\(String(repeating: "b", count: 64))'"))
        XCTAssertTrue(script.contains("RESTORE_VERSION='0.8.5'"))
        XCTAssertTrue(script.hasPrefix("#!/bin/zsh"))
    }

    func testRenderRestoreRejectsBadDigestPIDAndInjection() {
        XCTAssertThrowsError(try generator.renderRestore(restoreInputs(sha: "short"))) {
            XCTAssertEqual($0 as? UpdaterScriptGenerator.GeneratorError, .invalidDigest)
        }
        XCTAssertThrowsError(try generator.renderRestore(restoreInputs(pid: 0))) {
            XCTAssertEqual($0 as? UpdaterScriptGenerator.GeneratorError, .invalidPID)
        }
        XCTAssertThrowsError(try generator.renderRestore(restoreInputs(zip: "/x/'; rm -rf ~/'.zip"))) {
            guard case UpdaterScriptGenerator.GeneratorError.unsafeValue = $0 else { return XCTFail("expected unsafeValue") }
        }
    }

    /// Live dry-run of the restore swap: a signed "CURRENT" bundle installed, a signed
    /// "PREVIOUS" bundle zipped exactly as `RollbackArchiver` does (`ditto -c -k --keepParent`),
    /// then the generated restore script runs and must replace CURRENT with PREVIOUS and relaunch.
    func testGeneratedRestoreScriptSwapsBundleAndRelaunches() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("orifold-restore-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let installDir = root.appendingPathComponent("Applications", isDirectory: true)
        let prevDir = root.appendingPathComponent("prev-src", isDirectory: true)
        try FileManager.default.createDirectory(at: installDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: prevDir, withIntermediateDirectories: true)

        let installedApp = installDir.appendingPathComponent("Orifold.app")
        let previousApp = prevDir.appendingPathComponent("Orifold.app")
        try makeSignedApp(at: installedApp, marker: "CURRENT")
        try makeSignedApp(at: previousApp, marker: "PREVIOUS")

        // Archive the previous bundle exactly like RollbackArchiver (keepParent zip of the .app).
        let zip = root.appendingPathComponent("Orifold-0.8.5.zip")
        try XCTAssertProcess("/usr/bin/ditto", ["-c", "-k", "--keepParent", previousApp.path, zip.path])
        let sha = try RollbackArchiver.sha256(of: zip)

        let recorded = root.appendingPathComponent("relaunched.txt")
        let recorder = root.appendingPathComponent("recorder.sh")
        try "#!/bin/zsh\nprintf '%s' \"$1\" > '\(recorded.path)'\n".write(to: recorder, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: recorder.path)

        let script = try UpdaterScriptGenerator().writeRestore(
            .init(appPID: 999_999,                       // no such PID → proceeds at once
                  appBundlePath: installedApp.path, archiveZipPath: zip.path, archiveSHA256: sha,
                  restoreVersion: "0.8.5", relaunchCommand: recorder.path),
            to: root
        )

        let result = try runProcess("/bin/zsh", [script.path])
        XCTAssertEqual(result.status, 0, "restore script failed:\n\(result.output)")

        let installedMarker = try String(contentsOf: installedApp.appendingPathComponent("Contents/Resources/marker.txt"), encoding: .utf8)
        XCTAssertEqual(installedMarker, "PREVIOUS", "current bundle should have been replaced by the archived previous one")
        XCTAssertEqual(try? String(contentsOf: recorded, encoding: .utf8), installedApp.path)
        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: installDir.path)) ?? []
        XCTAssertEqual(leftovers.sorted(), ["Orifold.app"], "no .replaced/.staging debris")
    }

    // MARK: - Live dry-run of the swap (macOS tools)

    /// Builds two ad-hoc-signed fake app bundles + a real DMG, then runs the generated
    /// script (with a stale PID and a recorder in place of `open`) and asserts the old
    /// bundle was replaced by the new one and relaunch was invoked. This exercises the
    /// actual mount → verify → stage → swap → relaunch path, not a simulation.
    func testGeneratedScriptSwapsBundleAndRelaunches() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("orifold-swap-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let installDir = root.appendingPathComponent("Applications", isDirectory: true)
        let srcDir = root.appendingPathComponent("dmg-src", isDirectory: true)
        try FileManager.default.createDirectory(at: installDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: srcDir, withIntermediateDirectories: true)

        let oldApp = installDir.appendingPathComponent("Orifold.app")
        let newApp = srcDir.appendingPathComponent("Orifold.app")
        try makeSignedApp(at: oldApp, marker: "OLD")
        try makeSignedApp(at: newApp, marker: "NEW")

        // Real DMG containing the new app.
        let dmg = root.appendingPathComponent("Orifold-9.9.9.dmg")
        try XCTAssertProcess("/usr/bin/hdiutil", ["create", "-volname", "Orifold", "-srcfolder", srcDir.path,
                                                  "-ov", "-format", "UDZO", "-quiet", dmg.path])
        let sha = try RollbackArchiver.sha256(of: dmg)

        // Recorder in place of `open` — records the path it would relaunch.
        let recorded = root.appendingPathComponent("relaunched.txt")
        let recorder = root.appendingPathComponent("recorder.sh")
        try "#!/bin/zsh\nprintf '%s' \"$1\" > '\(recorded.path)'\n".write(to: recorder, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: recorder.path)

        let script = try UpdaterScriptGenerator().write(
            .init(appPID: 999_999,                       // no such PID → proceeds at once
                  appBundlePath: oldApp.path, dmgPath: dmg.path, dmgSHA256: sha,
                  newVersion: "9.9.9", rollbackZipPath: nil, relaunchCommand: recorder.path),
            to: root
        )

        let result = try runProcess("/bin/zsh", [script.path])
        XCTAssertEqual(result.status, 0, "updater script failed:\n\(result.output)")

        // The installed bundle is now the NEW one.
        let installedMarker = try String(contentsOf: oldApp.appendingPathComponent("Contents/Resources/marker.txt"), encoding: .utf8)
        XCTAssertEqual(installedMarker, "NEW", "old bundle should have been replaced by the new one")
        // Relaunch was invoked with the installed app path.
        XCTAssertEqual(try? String(contentsOf: recorded, encoding: .utf8), oldApp.path)
        // No debris left behind.
        XCTAssertFalse(FileManager.default.fileExists(atPath: dmg.path), "consumed DMG should be removed")
        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: installDir.path)) ?? []
        XCTAssertEqual(leftovers.sorted(), ["Orifold.app"], "no .previous/.staging debris")
    }

    /// Regression guard for the post-swap rollback gap: when the swap already succeeded
    /// (a new bundle sits at `$APP_PATH`) but post-swap verification then fails, the real
    /// `restore_and_fail` helper must remove that bundle and restore the known-good backup —
    /// not leave the possibly-unlaunchable new one in place and orphan the backup.
    ///
    /// A same-directory rename can't be made to fail in the full dry-run (writability is
    /// pre-checked), so this drives the helper extracted verbatim from the shipped template
    /// through exactly that caller-2 state.
    func testRestoreAfterPostSwapVerifyFailurePutsOldBundleBack() throws {
        let restoreFn = try extractedRestoreHelper()

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("orifold-restore-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        // Caller-2 state: the swap succeeded, so a NEW (bad) bundle is at APP_PATH and the
        // known-good OLD bundle is parked at the backup path.
        let appPath = root.appendingPathComponent("Orifold.app", isDirectory: true)
        let backup = root.appendingPathComponent("Orifold.app.previous-1234", isDirectory: true)
        try writeMarkedDir(appPath, marker: "NEW-BAD")
        try writeMarkedDir(backup, marker: "OLD-GOOD")

        // Harness: inject the caller-2 variables, stub the helpers the function calls, then
        // run the real restore_and_fail. `fail` must exit non-zero (the update still fails).
        let harness = root.appendingPathComponent("harness.sh")
        try """
        #!/bin/zsh -f
        set -u
        APP_PATH='\(appPath.path)'
        BACKUP='\(backup.path)'
        ROLLBACK_ZIP=''
        say() { :; }
        cleanup() { :; }
        fail() { exit 3; }
        \(restoreFn)
        restore_and_fail "post-swap verify failed"
        """.write(to: harness, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: harness.path)

        let result = try runProcess("/bin/zsh", [harness.path])
        XCTAssertEqual(result.status, 3, "restore_and_fail must still fail the update:\n\(result.output)")

        // The old bundle is back in place…
        let restored = try String(contentsOf: appPath.appendingPathComponent("marker.txt"), encoding: .utf8)
        XCTAssertEqual(restored, "OLD-GOOD", "post-swap failure must roll back to the previous bundle")
        // …and the backup was consumed, not orphaned.
        XCTAssertFalse(FileManager.default.fileExists(atPath: backup.path), "backup should be moved back, not left behind")
    }

    // MARK: - Helpers

    /// Extracts the `restore_and_fail` shell function verbatim from the shipped template so
    /// the test drives the real code, not a hand-copied approximation.
    private func extractedRestoreHelper(file: StaticString = #filePath, line: UInt = #line) throws -> String {
        // Indentation is normalized by Swift's multiline-literal stripping, so match the
        // opening/closing braces by trimmed content rather than a fixed indent.
        let lines = UpdaterScriptGenerator.template.components(separatedBy: "\n")
        guard let startIdx = lines.firstIndex(where: { $0.contains("restore_and_fail() {") }) else {
            XCTFail("restore_and_fail() not found in template", file: file, line: line)
            throw XCTSkip("restore_and_fail() not found")
        }
        guard let relEnd = lines[(startIdx + 1)...].firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "}" }) else {
            XCTFail("could not find end of restore_and_fail()", file: file, line: line)
            throw XCTSkip("restore_and_fail() end not found")
        }
        return lines[startIdx...relEnd].joined(separator: "\n")
    }

    /// Creates a directory standing in for an app bundle, tagged with a marker file.
    private func writeMarkedDir(_ url: URL, marker: String) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try marker.write(to: url.appendingPathComponent("marker.txt"), atomically: true, encoding: .utf8)
    }

    private func makeSignedApp(at appURL: URL, marker: String) throws {
        let macOS = appURL.appendingPathComponent("Contents/MacOS")
        let resources = appURL.appendingPathComponent("Contents/Resources")
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        // A real Mach-O so codesign is happy; the marker distinguishes the two builds.
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: macOS.appendingPathComponent("Orifold"))
        try marker.write(to: resources.appendingPathComponent("marker.txt"), atomically: true, encoding: .utf8)
        try """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
        <key>CFBundleExecutable</key><string>Orifold</string>
        <key>CFBundleIdentifier</key><string>com.ud.Orifold</string>
        </dict></plist>
        """.write(to: appURL.appendingPathComponent("Contents/Info.plist"), atomically: true, encoding: .utf8)
        try XCTAssertProcess("/usr/bin/codesign", ["--force", "--deep", "-s", "-", appURL.path])
    }

    @discardableResult
    private func runProcess(_ launchPath: String, _ args: [String]) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }

    private func XCTAssertProcess(_ launchPath: String, _ args: [String], file: StaticString = #filePath, line: UInt = #line) throws {
        let result = try runProcess(launchPath, args)
        XCTAssertEqual(result.status, 0, "\(launchPath) \(args.joined(separator: " ")) failed:\n\(result.output)", file: file, line: line)
    }
}
