import Darwin
import Foundation
import XCTest
@testable import Orifold

final class BoundedLocalFileReaderTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("orifold-bounded-reader-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let directory {
            try? FileManager.default.removeItem(at: directory)
        }
        try super.tearDownWithError()
    }

    func testReadsRegularFileWithinLimit() throws {
        let url = directory.appendingPathComponent("small.pdf")
        let expected = Data("bounded input".utf8)
        XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: expected))

        XCTAssertEqual(BoundedLocalFileReader.readFile(at: url, maxBytes: expected.count), expected)
    }

    func testReadsNestedFileThroughAuthorizedRoot() throws {
        let nested = directory.appendingPathComponent("Nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let url = nested.appendingPathComponent("small.pdf")
        let expected = Data("authorized descendant".utf8)
        XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: expected))

        XCTAssertEqual(
            BoundedLocalFileReader.readFile(
                at: url,
                within: directory,
                maxBytes: expected.count
            ),
            expected
        )
    }

    func testAuthorizedRootRejectsSiblingFile() throws {
        let sibling = directory.deletingLastPathComponent().appendingPathComponent("outside.pdf")
        defer { try? FileManager.default.removeItem(at: sibling) }
        XCTAssertTrue(FileManager.default.createFile(atPath: sibling.path, contents: Data("outside".utf8)))

        XCTAssertNil(
            BoundedLocalFileReader.readFile(at: sibling, within: directory, maxBytes: 1_024)
        )
    }

    func testRejectsSparseFileOverLimitBeforeAllocation() throws {
        let url = directory.appendingPathComponent("oversized.pdf")
        XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: Data([0])))
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: 512 * 1024 + 1)
        try handle.close()

        XCTAssertNil(BoundedLocalFileReader.readFile(at: url, maxBytes: 512 * 1024))
    }

    func testRejectsNonRegularFile() throws {
        let url = directory.appendingPathComponent("fifo")
        XCTAssertEqual(mkfifo(url.path, 0o600), 0)
        XCTAssertNil(BoundedLocalFileReader.readFile(at: url, maxBytes: 1_024))
    }

    func testBindFileFallsBackToSelectedDescriptorWhenParentCannotBeRetained() throws {
        let protected = directory.appendingPathComponent("file-only", isDirectory: true)
        try FileManager.default.createDirectory(at: protected, withIntermediateDirectories: true)
        let url = protected.appendingPathComponent("selected.pdf")
        let expected = Data("sandbox-selected bytes".utf8)
        XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: expected))
        XCTAssertEqual(chmod(protected.path, mode_t(S_IXUSR)), 0)
        defer { _ = chmod(protected.path, mode_t(S_IRWXU)) }

        let source = try XCTUnwrap(BoundedLocalFileReader.bindFile(
            at: url,
            maxBytes: expected.count
        ))

        XCTAssertEqual(source.data, expected)
        XCTAssertNil(source.directory, "a file-only capability must not grant relative asset access")
    }

    func testRetainedDirectoryRejectsAChildWhoseIdentityDoesNotMatchSelection() throws {
        let selected = directory.appendingPathComponent("selected.pdf")
        let replacement = directory.appendingPathComponent("replacement.pdf")
        try Data("selected".utf8).write(to: selected)
        try Data("replacement".utf8).write(to: replacement)
        let descriptor = Darwin.open(selected.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        XCTAssertGreaterThanOrEqual(descriptor, 0)
        defer { Darwin.close(descriptor) }
        var metadata = stat()
        XCTAssertEqual(Darwin.fstat(descriptor, &metadata), 0)
        let identity = BoundedLocalFileIdentity(device: metadata.st_dev, inode: metadata.st_ino)
        let retained = try XCTUnwrap(BoundedLocalFileDirectory(authorizedRoot: directory))

        XCTAssertNil(retained.readAsset(
            pathComponents: [replacement.lastPathComponent],
            maxBytes: 1_024,
            matching: identity
        ))
    }
}
