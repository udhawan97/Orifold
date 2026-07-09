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

    // MARK: - Helpers

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
