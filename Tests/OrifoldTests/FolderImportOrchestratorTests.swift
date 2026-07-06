import UniformTypeIdentifiers
import XCTest
@testable import Orifold

final class FolderImportOrchestratorTests: XCTestCase {
    private func makeTempDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("FolderImportOrchestratorTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @discardableResult
    private func write(_ name: String, in directory: URL, contents: String = "hello") throws -> URL {
        let url = directory.appendingPathComponent(name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - importPickedOrDropped

    func testFilesOnlyWithNoFoldersReturnsReadyUnchanged() async {
        let files = [URL(fileURLWithPath: "/tmp/a.txt"), URL(fileURLWithPath: "/tmp/b.txt")]

        let outcome = await importPickedOrDropped(files: files, folders: [])

        guard case .ready(let urls, let unsupportedCount, let wasLimited) = outcome else {
            return XCTFail("expected .ready, got \(outcome)")
        }
        XCTAssertEqual(urls, files)
        XCTAssertEqual(unsupportedCount, 0)
        XCTAssertFalse(wasLimited)
    }

    func testFilesOnlyPropagatesWasLimitedFlagWithoutTouchingFolderPath() async {
        let files = [URL(fileURLWithPath: "/tmp/a.txt")]

        let outcome = await importPickedOrDropped(files: files, folders: [], wasLimited: true)

        guard case .ready(_, _, let wasLimited) = outcome else {
            return XCTFail("expected .ready, got \(outcome)")
        }
        XCTAssertTrue(wasLimited)
    }

    func testNoFilesAndNoFoldersReturnsNothingToImport() async {
        let outcome = await importPickedOrDropped(files: [], folders: [])
        guard case .nothingToImport = outcome else {
            return XCTFail("expected .nothingToImport, got \(outcome)")
        }
    }

    func testFolderWithFewSupportedFilesReturnsReadyWithMergedURLs() async throws {
        let root = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("a.txt", in: root)
        try write("b.txt", in: root)

        let outcome = await importPickedOrDropped(files: [], folders: [root])

        guard case .ready(let urls, let unsupportedCount, let wasLimited) = outcome else {
            return XCTFail("expected .ready, got \(outcome)")
        }
        XCTAssertEqual(urls.count, 2)
        XCTAssertEqual(unsupportedCount, 0)
        XCTAssertFalse(wasLimited)
    }

    func testFolderMergedWithDraggedFilesDedupesBySamePath() async throws {
        let root = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let shared = try write("shared.txt", in: root)
        try write("other.txt", in: root)

        let outcome = await importPickedOrDropped(files: [shared], folders: [root])

        guard case .ready(let urls, _, _) = outcome else {
            return XCTFail("expected .ready, got \(outcome)")
        }
        XCTAssertEqual(urls.count, 2, "the dragged file and its folder-scanned duplicate should not both appear")
    }

    func testFolderWithOnlyUnsupportedFilesReturnsOnlyUnsupported() async throws {
        let root = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("archive.zip", in: root)

        let outcome = await importPickedOrDropped(files: [], folders: [root])

        guard case .onlyUnsupported = outcome else {
            return XCTFail("expected .onlyUnsupported, got \(outcome)")
        }
    }

    func testEmptyFolderReturnsEmpty() async {
        let root = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let outcome = await importPickedOrDropped(files: [], folders: [root])

        guard case .empty = outcome else {
            return XCTFail("expected .empty, got \(outcome)")
        }
    }

    func testFolderWithMoreThanFiftySupportedFilesRequestsConfirmationWithFullSortedList() async throws {
        let root = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        for index in 0..<60 {
            try write("file-\(String(format: "%03d", index)).txt", in: root)
        }

        let outcome = await importPickedOrDropped(files: [], folders: [root])

        guard case .needsConfirmation(let batch) = outcome else {
            return XCTFail("expected .needsConfirmation, got \(outcome)")
        }
        XCTAssertEqual(batch.urls.count, 60)
        XCTAssertEqual(batch.unsupportedCount, 0)

        let firstFifty = Array(batch.urls.prefix(maximumImportBatchSize))
        XCTAssertEqual(firstFifty.count, maximumImportBatchSize)
        XCTAssertEqual(firstFifty, firstFifty.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending })
    }

    // MARK: - resolveImportDrop classification (regression guard for the folder-aware drop path)

    private func fileURLProvider(pointingTo url: URL) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.registerDataRepresentation(
            forTypeIdentifier: UTType.fileURL.identifier,
            visibility: .all
        ) { completion in
            completion(url.dataRepresentation, nil)
            return nil
        }
        return provider
    }

    private func resolvedDrop(from providers: [NSItemProvider]) async -> ResolvedImportDrop {
        await withCheckedContinuation { continuation in
            resolveImportDrop(from: providers) { resolved in
                continuation.resume(returning: resolved)
            }
        }
    }

    func testResolveImportDropClassifiesRealDirectoryAsFolderNotFile() async throws {
        // Drop-provider items pointing into the system temp directory get durably
        // copied before classification (the same treatment every dropped file already
        // gets), so this asserts on classification, not exact path identity.
        let root = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = try write("doc.txt", in: root)

        let provider = fileURLProvider(pointingTo: root)
        let fileProvider = fileURLProvider(pointingTo: file)

        let resolved = await resolvedDrop(from: [provider, fileProvider])

        XCTAssertEqual(resolved.folders.count, 1, "the directory item should be classified as a folder root")
        XCTAssertEqual(resolved.files.count, 1, "the plain file item should be classified as a file")

        let isDirectory = (try? resolved.folders.first?.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        XCTAssertTrue(isDirectory)
    }

    func testResolveImportURLsStillFiltersOutDirectoriesUnchanged() async throws {
        // Regression guard: the original file-picker/drop resolver used by every
        // existing call site must keep treating a dropped directory as unsupported,
        // exactly as it did before folder import existed.
        let root = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let provider = fileURLProvider(pointingTo: root)

        let urls = await withCheckedContinuation { continuation in
            resolveImportURLs(from: [provider]) { urls, _ in
                continuation.resume(returning: urls)
            }
        }

        XCTAssertTrue(urls.isEmpty, "a directory URL must not be treated as a supported document by the original resolver")
    }
}
