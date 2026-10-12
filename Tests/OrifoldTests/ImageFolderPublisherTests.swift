import Darwin
import Foundation
import XCTest
@testable import Orifold

final class ImageFolderPublisherTests: XCTestCase {
    private var root: URL!
    private var destination: URL { root.appendingPathComponent("Pages", isDirectory: true) }
    private let pages = [
        ImageFolderPublisher.Page(filename: "page-001.png", data: Data("first new page".utf8)),
        ImageFolderPublisher.Page(filename: "page-002.png", data: Data("second new page".utf8))
    ]

    override func setUpWithError() throws {
        let temporary = ProcessInfo.processInfo.environment["ORIFOLD_TEST_TEMP_ROOT"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) } ?? FileManager.default.temporaryDirectory
        root = temporary.appendingPathComponent("orifold-image-publication-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        // Use the filesystem's canonical spelling for sandbox rules. Foundation's
        // resolvingSymlinksInPath may shorten /private/var back to the /var alias.
        let canonicalPath = try XCTUnwrap(Darwin.realpath(root.path, nil))
        defer { free(canonicalPath) }
        root = URL(fileURLWithPath: String(cString: canonicalPath), isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testEveryFailedPublicationStepPreservesExistingTreeExactly() throws {
        try makeOldTree()
        let before = try tree(at: destination)
        for step in [ImageFolderPublisher.Step.createStaging, .writePage(0), .writePage(1), .publish] {
            XCTAssertThrowsError(try ImageFolderPublisher.publish(pages, to: destination) {
                if $0 == step { throw POSIXError(.ENOSPC) }
            })
            XCTAssertEqual(try tree(at: destination), before, "failure at \(step)")
        }
    }

    func testSiblingAccessDeniedNeverDeletesExistingOutput() throws {
        try makeOldTree()
        let before = try tree(at: destination)
        XCTAssertThrowsError(try ImageFolderPublisher.publish(pages, to: destination) {
            if $0 == .createStaging { throw POSIXError(.EACCES) }
        })
        XCTAssertEqual(try tree(at: destination), before)
    }

    func testCancelledStagingPreservesExistingOutputExactly() throws {
        try makeOldTree()
        let before = try tree(at: destination)
        XCTAssertThrowsError(try ImageFolderPublisher.publish(pages, to: destination) {
            if $0 == .writePage(1) { throw CancellationError() }
        })
        XCTAssertEqual(try tree(at: destination), before)
    }

    func testPageWriteAccessDeniedDoesNotEnableDirectFallback() throws {
        try makeOldTree()
        let before = try tree(at: destination)
        var pageWriteAttempts = 0
        XCTAssertThrowsError(try ImageFolderPublisher.publish(pages, to: destination) {
            if $0 == .writePage(1) {
                pageWriteAttempts += 1
                throw POSIXError(.EACCES)
            }
        })
        XCTAssertEqual(pageWriteAttempts, 1)
        XCTAssertEqual(try tree(at: destination), before)
    }

    func testSuccessfulReplacementContainsExactlyNewPages() throws {
        try makeOldTree()
        try ImageFolderPublisher.publish(pages, to: destination)
        XCTAssertEqual(try tree(at: destination), Dictionary(uniqueKeysWithValues: pages.map { ($0.filename, $0.data) }))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["Pages"])
    }

    func testSelectedPathFallbackCreatesNewCompleteFolder() throws {
        try ImageFolderPublisher.publish(pages, to: destination) {
            if $0 == .createStaging { throw POSIXError(.EPERM) }
        }
        XCTAssertEqual(try tree(at: destination), Dictionary(uniqueKeysWithValues: pages.map { ($0.filename, $0.data) }))
    }

    func testUnreadableParentAllowsCreateNewSelectedPathWithoutAncestorReadAccess() throws {
        XCTAssertEqual(Darwin.chmod(root.path, 0o300), 0)
        defer { _ = Darwin.chmod(root.path, 0o700) }
        try ImageFolderPublisher.publish(pages, to: destination)
        XCTAssertEqual(try tree(at: destination), Dictionary(uniqueKeysWithValues: pages.map { ($0.filename, $0.data) }))
    }

    func testUnreadableParentRefusesExistingFolderReplacementAndPreservesBytes() throws {
        try makeOldTree()
        let before = try tree(at: destination)
        XCTAssertEqual(Darwin.chmod(root.path, 0o300), 0)
        defer { _ = Darwin.chmod(root.path, 0o700) }
        XCTAssertThrowsError(try ImageFolderPublisher.publish(pages, to: destination))
        XCTAssertEqual(try tree(at: destination), before)
    }

    func testOSSandboxSelectedPathGrantCreatesNewOutputAndPreservesExistingOutputWhenSiblingsDenied() throws {
        let executable = try buildSandboxHelper()
        let selected = root.appendingPathComponent("sandbox-output", isDirectory: true)
        for denyParentRead in [false, true] {
            let profile = root.appendingPathComponent("selected-path.sb")
            let parentReadRule = denyParentRead ? "(deny file-read-data (literal \"\(root.path)\"))" : ""
            try """
            (version 1)
            (allow default)
            (deny network*)
            (deny file-write*)
            (allow file-write* (literal "/dev/null") (subpath "\(selected.path)"))
            \(parentReadRule)
            (allow file-read* (subpath "\(selected.path)"))
            """.write(to: profile, atomically: true, encoding: .utf8)
            let created = try runProcess("/usr/bin/sandbox-exec", ["-f", profile.path, executable.path, selected.path, "new"])
            if created == 71 {
                throw XCTSkip("OS sandbox policy cannot be applied inside this already contained runner; use the one-tier private helper")
            }
            XCTAssertEqual(created, 0, "selected-only creation; parent read denied=\(denyParentRead)")
            XCTAssertEqual(try Data(contentsOf: selected.appendingPathComponent("page-001.png")), Data("sandbox page".utf8))
            let existing = try runProcess("/usr/bin/sandbox-exec", ["-f", profile.path, executable.path, selected.path, "existing"])
            XCTAssertEqual(existing, 0, "existing output refusal; parent read denied=\(denyParentRead)")
            XCTAssertEqual(try Data(contentsOf: selected.appendingPathComponent("page-001.png")), Data("sandbox page".utf8))
            try FileManager.default.removeItem(at: selected)
        }
    }

    func testSelectedPathFallbackWriteFailureIsNotReportedCompleteAndRemovesPartialOutput() throws {
        XCTAssertThrowsError(try ImageFolderPublisher.publish(pages, to: destination) {
            if $0 == .createStaging { throw POSIXError(.EACCES) }
            if $0 == .writePage(1) { throw POSIXError(.ENOSPC) }
        })
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    func testNewDestinationAppearingBeforePublicationIsPreserved() throws {
        XCTAssertThrowsError(try ImageFolderPublisher.publish(pages, to: destination) {
            if $0 == .publish { try self.makeOldTree() }
        })
        XCTAssertEqual(try tree(at: destination)["private/note.txt"], Data("preserve nested note".utf8))
    }

    func testReplacedParentBeforePublicationRejectsReceiptAndPreservesBothOutputTrees() throws {
        try makeOldTree()
        let before = try tree(at: destination)
        let movedRoot = root.appendingPathExtension("original")
        defer { try? FileManager.default.removeItem(at: movedRoot) }
        XCTAssertThrowsError(try ImageFolderPublisher.publish(pages, to: destination) {
            if $0 == .publish {
                try FileManager.default.moveItem(at: self.root, to: movedRoot)
                try self.makeOldTree()
                try Data("replacement sentinel".utf8).write(to: self.destination.appendingPathComponent("keep.txt"))
            }
        })
        XCTAssertEqual(try tree(at: movedRoot.appendingPathComponent("Pages")), before)
        XCTAssertEqual(try tree(at: destination)["keep.txt"], Data("replacement sentinel".utf8))
    }

    func testReplacedStagingFolderIsNotDeletedDuringFailureCleanup() throws {
        var unrelated: URL?
        XCTAssertThrowsError(try ImageFolderPublisher.publish(pages, to: destination) {
            if $0 == .publish {
                let staging = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: self.root, includingPropertiesForKeys: nil)
                    .first { $0.lastPathComponent.hasPrefix(".Orifold-image-export-") })
                try FileManager.default.moveItem(at: staging, to: self.root.appendingPathComponent("owned-stage"))
                try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
                try Data("unrelated contents".utf8).write(to: staging.appendingPathComponent("keep.txt"))
                unrelated = staging
            }
        })
        let sentinel = try XCTUnwrap(unrelated).appendingPathComponent("keep.txt")
        XCTAssertEqual(try Data(contentsOf: sentinel), Data("unrelated contents".utf8))
    }

    private func makeOldTree() throws {
        let nested = destination.appendingPathComponent("private", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data("old page one".utf8).write(to: destination.appendingPathComponent("page-001.png"))
        try Data("old stale page".utf8).write(to: destination.appendingPathComponent("page-099.png"))
        try Data("preserve nested note".utf8).write(to: nested.appendingPathComponent("note.txt"))
    }

    private func tree(at folder: URL) throws -> [String: Data] {
        var result: [String: Data] = [:]
        // Path enumeration supplies relative names directly, avoiding mismatched
        // /var and /private/var spellings in URL enumeration results.
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(atPath: folder.path))
        for case let relativePath as String in enumerator {
            let file = folder.appendingPathComponent(relativePath)
            if try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
                result[relativePath] = try Data(contentsOf: file)
            }
        }
        return result
    }

    private func buildSandboxHelper() throws -> URL {
        let checkout = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = checkout.appendingPathComponent("Orifold/Engine/ImageFolderPublisher.swift")
        let helperRoot = root.appendingPathComponent("sandbox-helper", isDirectory: true)
        try FileManager.default.createDirectory(at: helperRoot, withIntermediateDirectories: false)
        let main = helperRoot.appendingPathComponent("main.swift")
        try """
        import Foundation
        import Darwin
        let destination = URL(fileURLWithPath: CommandLine.arguments[1])
        let expectedFailure = CommandLine.arguments[2] == "existing"
        let bytes = Data("sandbox page".utf8)
        do {
            try ImageFolderPublisher.publish([.init(filename: "page-001.png", data: bytes)], to: destination)
            if expectedFailure { exit(10) }
            guard try Data(contentsOf: destination.appendingPathComponent("page-001.png")) == bytes else { exit(11) }
        } catch {
            guard expectedFailure,
                  (try? Data(contentsOf: destination.appendingPathComponent("page-001.png"))) == bytes else { exit(12) }
        }
        """.write(to: main, atomically: true, encoding: .utf8)
        let executable = helperRoot.appendingPathComponent("publisher-probe")
        let status = try runProcess(
            "/usr/bin/xcrun",
            ["swiftc", source.path, main.path, "-o", executable.path]
        )
        XCTAssertEqual(status, 0, "standalone production publisher helper compilation")
        return executable
    }

    private func runProcess(_ executable: String, _ arguments: [String]) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }
}
