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
}
