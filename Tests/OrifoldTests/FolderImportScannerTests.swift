import XCTest
@testable import Orifold

final class FolderImportScannerTests: XCTestCase {
    private func makeTempDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("FolderImportScannerTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func write(_ name: String, in directory: URL, contents: String = "hello") throws -> URL {
        let url = directory.appendingPathComponent(name)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func testFlatFolderReturnsAllSupportedFiles() async throws {
        let root = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        _ = try write("a.txt", in: root)
        _ = try write("b.txt", in: root)

        let result = await FolderImportScanner.scan(folders: [root])
        XCTAssertEqual(result.supportedURLs.count, 2)
        XCTAssertEqual(result.unsupportedCount, 0)
        XCTAssertFalse(result.wasTruncated)
    }

    func testNestedFoldersAreScannedAndSortedByPath() async throws {
        let root = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        _ = try write("z-top.txt", in: root)
        _ = try write("nested/a-inner.txt", in: root)
        _ = try write("nested/deeper/b-inner.txt", in: root)

        let result = await FolderImportScanner.scan(folders: [root])
        XCTAssertEqual(result.supportedURLs.count, 3)

        let relativeOrder = result.supportedURLs.map { $0.path }
        XCTAssertEqual(relativeOrder, relativeOrder.sorted { $0.localizedStandardCompare($1) == .orderedAscending })
    }

    func testHiddenFilesAreSkipped() async throws {
        let root = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        _ = try write(".hidden.txt", in: root)
        _ = try write("visible.txt", in: root)

        let result = await FolderImportScanner.scan(folders: [root])
        XCTAssertEqual(result.supportedURLs.count, 1)
        XCTAssertEqual(result.supportedURLs.first?.lastPathComponent, "visible.txt")
    }

    func testUnsupportedOnlyFolderReportsZeroSupportedWithUnsupportedCount() async throws {
        let root = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        _ = try write("archive.zip", in: root)
        _ = try write("binary.bin", in: root)

        let result = await FolderImportScanner.scan(folders: [root])
        XCTAssertTrue(result.supportedURLs.isEmpty)
        XCTAssertEqual(result.unsupportedCount, 2)
    }

    func testEmptyFolderReportsNothingFoundAndNothingSkipped() async throws {
        let root = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let result = await FolderImportScanner.scan(folders: [root])
        XCTAssertTrue(result.isEmpty)
        XCTAssertTrue(result.supportedURLs.isEmpty)
        XCTAssertEqual(result.unsupportedCount, 0)
    }

    func testMoreThanFiftySupportedFilesAreAllReturnedByTheScanner() async throws {
        let root = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        for index in 0..<60 {
            _ = try write("file-\(String(format: "%03d", index)).txt", in: root)
        }

        let result = await FolderImportScanner.scan(folders: [root])
        XCTAssertEqual(result.supportedURLs.count, 60, "the scanner itself should not apply the 50-file batch cap")
        XCTAssertFalse(result.wasTruncated)
    }

    func testDuplicateFileAcrossOverlappingRootsIsDedupedByPath() async throws {
        let root = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let subfolder = root.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: subfolder, withIntermediateDirectories: true)
        _ = try write("shared.txt", in: subfolder)

        let result = await FolderImportScanner.scan(folders: [root, subfolder])
        XCTAssertEqual(result.supportedURLs.count, 1, "scanning an outer folder and one of its own subfolders should not double-count files")
    }

    func testEmptyFolderNeverReportsTruncation() async throws {
        let root = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let result = await FolderImportScanner.scan(folders: [root])
        XCTAssertFalse(result.wasTruncated)
    }

    func testScanTruncatesOnceEntryCapIsExceeded() async throws {
        let root = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let overCapCount = FolderImportScanner.maxScannedEntries + 5
        for index in 0..<overCapCount {
            let url = root.appendingPathComponent("file-\(index).txt")
            FileManager.default.createFile(atPath: url.path, contents: Data())
        }

        let result = await FolderImportScanner.scan(folders: [root])
        XCTAssertTrue(result.wasTruncated)
    }
}
