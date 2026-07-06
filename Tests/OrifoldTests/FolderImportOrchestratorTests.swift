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

    @MainActor
    private func makeViewModel() -> WorkspaceViewModel {
        WorkspaceViewModel(
            document: WorkspaceDocument(),
            engine: PDFKitEngine(),
            processingEngine: PDFKitProcessingEngineFallback()
        )
    }

    // MARK: - importPickedOrDropped

    func testFilesOnlyWithNoFoldersReturnsReadyUnchanged() async {
        let files = [URL(fileURLWithPath: "/tmp/a.txt"), URL(fileURLWithPath: "/tmp/b.txt")]

        let outcome = await importPickedOrDropped(files: files, folders: [])

        guard case .ready(let urls, let unsupportedCount, let wasLimited, let wasTruncated) = outcome else {
            return XCTFail("expected .ready, got \(outcome)")
        }
        XCTAssertEqual(urls, files)
        XCTAssertEqual(unsupportedCount, 0)
        XCTAssertFalse(wasLimited)
        XCTAssertFalse(wasTruncated)
    }

    func testFilesOnlyPropagatesWasLimitedFlagWithoutTouchingFolderPath() async {
        let files = [URL(fileURLWithPath: "/tmp/a.txt")]

        let outcome = await importPickedOrDropped(files: files, folders: [], wasLimited: true)

        guard case .ready(_, _, let wasLimited, _) = outcome else {
            return XCTFail("expected .ready, got \(outcome)")
        }
        XCTAssertTrue(wasLimited)
    }

    func testWasLimitedIsPreservedWhenAFolderIsAlsoPresent() async throws {
        // Regression test: importPickedOrDropped used to hardcode wasLimited: false
        // once any folder was involved, silently dropping the "too many loose files
        // were dropped" signal the moment a folder was scanned alongside them.
        let root = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("a.txt", in: root)

        let files = [URL(fileURLWithPath: "/tmp/a.txt")]
        let outcome = await importPickedOrDropped(files: files, folders: [root], wasLimited: true)

        guard case .ready(_, _, let wasLimited, _) = outcome else {
            return XCTFail("expected .ready, got \(outcome)")
        }
        XCTAssertTrue(wasLimited, "wasLimited must survive merging with folder-scanned files, not just the folders-empty path")
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

        guard case .ready(let urls, let unsupportedCount, let wasLimited, _) = outcome else {
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

        guard case .ready(let urls, _, _, _) = outcome else {
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

    // MARK: - applyFolderImportOutcome (regression guards for the swallowed-signal bugs)

    @MainActor
    func testReadyOutcomeSurfacesBothSkippedSummaryAndProviderLimitWarning() {
        // Regression test: applyOutcome used to be an if/else-if that let the
        // unsupported-file summary toast silently swallow the provider-limit error
        // whenever both were true for the same outcome. They're independent UI
        // surfaces (editingStatus toast vs. importError alert) and must both fire.
        let viewModel = makeViewModel()
        let outcome = FolderImportOutcome.ready(
            urls: [URL(fileURLWithPath: "/tmp/a.txt")],
            unsupportedCount: 2,
            wasLimited: true,
            wasTruncated: false
        )

        applyFolderImportOutcome(outcome, into: viewModel) { _ in
            XCTFail("should not need confirmation for a .ready outcome")
        }

        XCTAssertNotNil(viewModel.editingStatus, "skipped-file summary must still be shown")
        XCTAssertNotNil(viewModel.importError, "provider-limit warning must not be swallowed by the summary toast")
    }

    func testReadyStatusMessageSurfacesTruncationEvenWithNoUnsupportedFiles() {
        // Regression test: scan.wasTruncated used to be discarded entirely once the
        // merged file count fit under the batch limit, leaving no signal that the
        // 10,000-entry safety cap cut a scan short.
        let message = folderImportReadyStatusMessage(importedCount: 5, unsupportedCount: 0, wasTruncated: true)
        XCTAssertNotNil(message, "a truncated scan must produce a status message even with zero unsupported files")
    }

    func testReadyStatusMessageIsNilWhenNothingNoteworthyHappened() {
        XCTAssertNil(folderImportReadyStatusMessage(importedCount: 5, unsupportedCount: 0, wasTruncated: false))
    }

    @MainActor
    func testImportFirstFromPendingBatchSurfacesTruncationEvenWithNoUnsupportedFiles() {
        // Regression test: the shared "Import first 50" handler used by both the
        // drop-zone/button confirmation dialog and the File-menu's NSAlert only
        // checked unsupportedCount, silently dropping the truncation signal after
        // the user confirmed the import even though the dialog showed it beforehand.
        let viewModel = makeViewModel()
        let batch = PendingFolderImportBatch(
            urls: (0..<60).map { URL(fileURLWithPath: "/tmp/file-\($0).txt") },
            unsupportedCount: 0,
            wasTruncated: true
        )

        importFirstFromPendingBatch(batch, into: viewModel)

        XCTAssertNotNil(viewModel.editingStatus, "a truncated scan must still be surfaced after confirming the import")
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
