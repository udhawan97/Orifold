import Darwin
import Foundation
import XCTest
@testable import Orifold

final class ExportFileWriterTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        let root = ProcessInfo.processInfo.environment["ORIFOLD_TEST_TEMP_ROOT"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) } ?? FileManager.default.temporaryDirectory
        directory = root.appendingPathComponent("orifold-export-writer-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let directory { try FileManager.default.removeItem(at: directory) }
    }

    func testPartialStorageFailurePreservesExistingOutputAndRemovesStaging() throws {
        let target = directory.appendingPathComponent("existing.pdf")
        let original = Data("previous export\0\u{ff}".utf8)
        try original.write(to: target)
        for code in [POSIXErrorCode.EFBIG, .ENOSPC] {
            XCTAssertThrowsError(try ExportFileWriter.write(Data(repeating: 42, count: 16_384), to: target,
                                                          writeForTesting: { data, descriptor in
                let written = data.withUnsafeBytes { Darwin.write(descriptor, $0.baseAddress, 4096) }
                XCTAssertEqual(written, 4096)
                throw POSIXError(code)
            })) { error in
                XCTAssertEqual((error as? POSIXError)?.code, code)
            }
            XCTAssertEqual(try Data(contentsOf: target), original)
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["existing.pdf"])
        }
    }

    func testValidationFailurePreservesExistingOutputAndRemovesStaging() throws {
        let target = directory.appendingPathComponent("existing.pdf")
        let original = Data("previous export".utf8)
        try original.write(to: target)
        XCTAssertThrowsError(try ExportFileWriter.write(Data("invalid export".utf8), to: target) { _ in
            throw ExportWriteError.emptyFile
        })
        XCTAssertEqual(try Data(contentsOf: target), original)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["existing.pdf"])
    }

    func testSuccessfulNewAndReplacementExportsValidateWrittenBytes() throws {
        let target = directory.appendingPathComponent("output.pdf")
        for bytes in [Data("first export".utf8), Data("replacement export".utf8)] {
            var validated = false
            try ExportFileWriter.write(bytes, to: target) { written in
                XCTAssertEqual(written, bytes)
                validated = true
            }
            XCTAssertTrue(validated)
            XCTAssertEqual(try Data(contentsOf: target), bytes)
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["output.pdf"])
        }
    }

    func testCleanupPreservesStagingNameReplacedByAnotherWriter() throws {
        let target = directory.appendingPathComponent("output.pdf")
        let otherBytes = Data("another writer".utf8)
        var tempURL: URL!
        XCTAssertThrowsError(try ExportFileWriter.write(Data("export".utf8), to: target) { _ in
            let name = try XCTUnwrap(FileManager.default.contentsOfDirectory(atPath: self.directory.path).first)
            tempURL = self.directory.appendingPathComponent(name)
            try FileManager.default.removeItem(at: tempURL)
            try otherBytes.write(to: tempURL)
            throw ExportWriteError.emptyFile
        })
        XCTAssertEqual(try Data(contentsOf: tempURL), otherBytes)
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
    }
}
