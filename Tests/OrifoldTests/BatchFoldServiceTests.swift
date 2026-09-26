import AppKit
import PDFKit
import XCTest
@testable import Orifold

@MainActor
final class BatchFoldServiceTests: XCTestCase {
    // MARK: - Output naming (pure)

    func testOutputNameAppendsFoldedSuffix() {
        let name = BatchFoldService.outputName(
            for: URL(fileURLWithPath: "/tmp/Quarterly Report.pdf"),
            existingNames: []
        )
        XCTAssertEqual(name, "Quarterly Report-folded.pdf")
    }

    func testOutputNameResolvesCollisionsCaseInsensitively() {
        let source = URL(fileURLWithPath: "/tmp/report.pdf")
        XCTAssertEqual(
            BatchFoldService.outputName(for: source, existingNames: ["Report-Folded.pdf"]),
            "report-folded-2.pdf"
        )
        XCTAssertEqual(
            BatchFoldService.outputName(
                for: source,
                existingNames: ["report-folded.pdf", "report-folded-2.pdf"]
            ),
            "report-folded-3.pdf"
        )
    }

    func testPDFURLsKeepsOnlyPDFExtensions() {
        let inputFolder = URL(fileURLWithPath: "/tmp", isDirectory: true)
        let scan = FolderScanResult(
            supportedURLs: [
                URL(fileURLWithPath: "/tmp/a.pdf"),
                URL(fileURLWithPath: "/tmp/b.PNG"),
                URL(fileURLWithPath: "/tmp/c.PDF"),
                URL(fileURLWithPath: "/tmp/d.docx")
            ],
            unsupportedCount: 0,
            wasTruncated: false
        )
        XCTAssertEqual(
            BatchFoldService.pdfURLs(from: scan, inputFolder: inputFolder).map(\.lastPathComponent),
            ["a.pdf", "c.PDF"]
        )
    }

    func testPDFURLsExcludesExistingFoldedOutputSubtree() {
        let inputFolder = URL(fileURLWithPath: "/tmp/Batch", isDirectory: true)
        let scan = FolderScanResult(
            supportedURLs: [
                inputFolder.appendingPathComponent("source.pdf"),
                inputFolder.appendingPathComponent("Nested/keep.pdf"),
                inputFolder.appendingPathComponent("Folded/earlier-folded.pdf"),
                inputFolder.appendingPathComponent("Folded/Nested/earlier-nested-folded.pdf"),
                inputFolder.appendingPathComponent("Folded Backup/not-an-output.pdf")
            ],
            unsupportedCount: 0,
            wasTruncated: false
        )

        XCTAssertEqual(
            BatchFoldService.pdfURLs(from: scan, inputFolder: inputFolder).map(\.lastPathComponent),
            ["source.pdf", "keep.pdf", "not-an-output.pdf"]
        )
    }

    // MARK: - Per-file pipeline

    func testEmptyOptionsFoldReturnsInputBytesUnchanged() async throws {
        let input = try whitePDFData(pages: 1)
        let output = try await BatchFoldService.fold(
            input,
            fileName: "blank.pdf",
            options: BatchFoldService.Options()
        )
        XCTAssertEqual(output, input)
    }

    func testWatermarkFoldInksEveryPageAndPreservesPageCount() async throws {
        let input = try whitePDFData(pages: 2)
        var options = BatchFoldService.Options()
        options.watermarkText = "CONFIDENTIAL"

        let output = try await BatchFoldService.fold(input, fileName: "white.pdf", options: options)

        let outputPDF = try XCTUnwrap(PDFDocument(data: output))
        XCTAssertEqual(outputPDF.pageCount, 2)
        for pageIndex in 0..<2 {
            let before = try inkCoverage(of: input, pageIndex: pageIndex)
            let after = try inkCoverage(of: output, pageIndex: pageIndex)
            XCTAssertGreaterThan(after, before, "page \(pageIndex) should carry the baked watermark")
        }
        XCTAssertTrue(QPDFService.isStructurallySound(output))
    }

    func testOCRFoldAddsSearchableTextViaInjectedProvider() async throws {
        let input = try whitePDFData(pages: 1, speckled: true)
        var options = BatchFoldService.Options()
        options.runsOCR = true

        let output = try await BatchFoldService.fold(
            input,
            fileName: "scan.pdf",
            options: options,
            recognitionProvider: { _, _, _ in
                [
                    PDFOCRRecognizedLine(
                        text: "Folded stack phrase",
                        normalizedBounds: CGRect(x: 0.2, y: 0.4, width: 0.5, height: 0.1),
                        confidence: 0.9
                    )
                ]
            }
        )

        let outputPDF = try XCTUnwrap(PDFDocument(data: output))
        XCTAssertEqual(outputPDF.pageCount, 1)
        XCTAssertFalse(outputPDF.findString("Folded stack phrase", withOptions: .caseInsensitive).isEmpty)
        XCTAssertTrue(QPDFService.isStructurallySound(output))
    }

    func testOCRFoldKeepsWorkingWhenNothingIsRecognized() async throws {
        let input = try whitePDFData(pages: 1)
        var options = BatchFoldService.Options()
        options.runsOCR = true

        let output = try await BatchFoldService.fold(
            input,
            fileName: "blank.pdf",
            options: options,
            recognitionProvider: { _, _, _ in [] }
        )

        let outputPDF = try XCTUnwrap(PDFDocument(data: output))
        XCTAssertEqual(outputPDF.pageCount, 1)
        XCTAssertTrue(QPDFService.isStructurallySound(output))
    }

    // MARK: - Batch run

    func testRunWritesFoldedOutputsAndIsolatesFailures() async throws {
        let folder = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let goodA = folder.appendingPathComponent("a.pdf")
        let badB = folder.appendingPathComponent("b.pdf")
        let goodC = folder.appendingPathComponent("c.pdf")
        try whitePDFData(pages: 1).write(to: goodA)
        try Data("not a pdf at all".utf8).write(to: badB)
        try whitePDFData(pages: 1).write(to: goodC)

        var options = BatchFoldService.Options()
        options.watermarkText = "DRAFT"

        let result = await BatchFoldService.run(
            inputFolder: folder,
            files: [goodA, badB, goodC],
            options: options,
            progress: { _, _ in },
            isCancelled: { false }
        )

        XCTAssertEqual(result.foldedCount, 2)
        XCTAssertEqual(result.failedCount, 1)
        XCTAssertFalse(result.wasCancelled)
        let outputDirectory = try XCTUnwrap(result.outputDirectory)
        XCTAssertEqual(outputDirectory.lastPathComponent, BatchFoldService.outputFolderName)
        XCTAssertEqual(
            outputDirectory.deletingLastPathComponent().resolvingSymlinksInPath(),
            folder.resolvingSymlinksInPath()
        )
        let written = try FileManager.default.contentsOfDirectory(atPath: outputDirectory.path).sorted()
        XCTAssertEqual(written, ["a-folded.pdf", "c-folded.pdf"])
        if case .failed = result.outcomes[1].result {} else {
            XCTFail("the unreadable file should be the failed outcome")
        }
    }

    func testRunAvoidsOverwritingEarlierResults() async throws {
        let folder = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("a.pdf")
        try whitePDFData(pages: 1).write(to: source)
        let outputDirectory = folder.appendingPathComponent(BatchFoldService.outputFolderName)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let earlier = outputDirectory.appendingPathComponent("a-folded.pdf")
        try Data("earlier run".utf8).write(to: earlier)

        var options = BatchFoldService.Options()
        options.watermarkText = "DRAFT"

        let result = await BatchFoldService.run(
            inputFolder: folder,
            files: [source],
            options: options,
            progress: { _, _ in },
            isCancelled: { false }
        )

        XCTAssertEqual(result.foldedCount, 1)
        XCTAssertEqual(try Data(contentsOf: earlier), Data("earlier run".utf8))
        let written = try FileManager.default.contentsOfDirectory(atPath: outputDirectory.path).sorted()
        XCTAssertEqual(written, ["a-folded-2.pdf", "a-folded.pdf"])
    }

    func testRunDisambiguatesAnExistingNameThatDiffersOnlyByCase() async throws {
        let folder = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("a.pdf")
        try whitePDFData(pages: 1).write(to: source)
        let outputDirectory = folder.appendingPathComponent(BatchFoldService.outputFolderName)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let earlier = outputDirectory.appendingPathComponent("A-FOLDED.PDF")
        try Data("earlier run".utf8).write(to: earlier)

        let result = await BatchFoldService.run(
            inputFolder: folder,
            files: [source],
            options: BatchFoldService.Options(watermarkText: "DRAFT"),
            progress: { _, _ in },
            isCancelled: { false }
        )

        XCTAssertEqual(result.foldedCount, 1)
        XCTAssertEqual(try Data(contentsOf: earlier), Data("earlier run".utf8))
        XCTAssertEqual(result.outcomes[0].outputURL?.lastPathComponent, "a-folded-2.pdf")
    }

    func testCreateNewRefusesDestinationCreatedAtCommitWithoutChangingItsBytes() throws {
        let folder = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let outputDirectory = try ExportOutputDirectory(parentURL: folder, directoryName: "Output")
        let target = outputDirectory.url.appendingPathComponent("result.pdf")
        let existing = Data("another writer got here first".utf8)

        XCTAssertThrowsError(try ExportFileWriter.createNew(
            Data("new bytes".utf8),
            named: target.lastPathComponent,
            in: outputDirectory,
            beforeCommit: { try existing.write(to: target, options: .withoutOverwriting) }
        )) { error in
            XCTAssertEqual(error as? ExportWriteError, .destinationExists)
        }

        XCTAssertEqual(try Data(contentsOf: target), existing)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: outputDirectory.url.path)
        XCTAssertEqual(leftovers, ["result.pdf"])
    }

    func testCreateNewValidationFailurePublishesNothingAndCleansTheStagedFile() throws {
        let folder = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let outputDirectory = try ExportOutputDirectory(parentURL: folder, directoryName: "Output")
        let target = outputDirectory.url.appendingPathComponent("rejected.pdf")

        XCTAssertThrowsError(try ExportFileWriter.createNew(
            Data("invalid bytes".utf8),
            named: target.lastPathComponent,
            in: outputDirectory,
            validate: { _ in throw FixtureFailure.rejected }
        ))

        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: outputDirectory.url.path).isEmpty)
    }

    func testCreateNewPublicationFailureCleansOnlyItsStagedFile() throws {
        let folder = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let outputDirectory = try ExportOutputDirectory(parentURL: folder, directoryName: "Output")

        XCTAssertThrowsError(try ExportFileWriter.createNew(
            Data("valid staged bytes".utf8),
            named: "result.pdf",
            in: outputDirectory,
            commitForTesting: { throw POSIXError(.EACCES) }
        )) { error in
            XCTAssertEqual((error as? POSIXError)?.code, .EACCES)
        }

        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: outputDirectory.url.path).isEmpty)
    }

    func testCreateNewDoesNotDeleteAStagedPathReplacedByAnotherWriter() throws {
        let folder = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let outputDirectory = try ExportOutputDirectory(parentURL: folder, directoryName: "Output")
        let replacement = Data("replacement owned by another writer".utf8)

        XCTAssertThrowsError(try ExportFileWriter.createNew(
            Data("our staged bytes".utf8),
            named: "result.pdf",
            in: outputDirectory,
            beforeCommit: {
                let names = try FileManager.default.contentsOfDirectory(
                    atPath: outputDirectory.url.path
                )
                let stagedName = try XCTUnwrap(names.first { $0.hasPrefix(".Orifold-export-") })
                let stagedURL = outputDirectory.url.appendingPathComponent(stagedName)
                try FileManager.default.removeItem(at: stagedURL)
                try replacement.write(to: stagedURL, options: .withoutOverwriting)
            }
        )) { error in
            XCTAssertEqual(error as? ExportWriteError, .fileNotFound)
        }

        let remainingName = try XCTUnwrap(
            FileManager.default.contentsOfDirectory(atPath: outputDirectory.url.path).first
        )
        XCTAssertTrue(remainingName.hasPrefix(".Orifold-export-"))
        XCTAssertEqual(
            try Data(contentsOf: outputDirectory.url.appendingPathComponent(remainingName)),
            replacement
        )
    }

    func testCreateNewDoesNotDeleteATargetReplacedAfterCommit() throws {
        let folder = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let outputDirectory = try ExportOutputDirectory(parentURL: folder, directoryName: "Output")
        let target = outputDirectory.url.appendingPathComponent("result.pdf")
        let replacement = Data("replacement after commit".utf8)

        XCTAssertThrowsError(try ExportFileWriter.createNew(
            Data("our published bytes".utf8),
            named: target.lastPathComponent,
            in: outputDirectory,
            afterCommitForTesting: {
                try FileManager.default.removeItem(at: target)
                try replacement.write(to: target, options: .withoutOverwriting)
            }
        )) { error in
            XCTAssertEqual(error as? ExportWriteError, .fileNotFound)
        }

        XCTAssertEqual(try Data(contentsOf: target), replacement)
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: outputDirectory.url.path),
            [target.lastPathComponent]
        )
    }

    func testRunRejectsPreexistingFoldedSymlinkWithoutWritingItsTarget() async throws {
        let folder = try makeTempFolder()
        let outside = try makeTempFolder()
        defer {
            try? FileManager.default.removeItem(at: folder)
            try? FileManager.default.removeItem(at: outside)
        }
        let source = folder.appendingPathComponent("a.pdf")
        try whitePDFData(pages: 1).write(to: source)
        try FileManager.default.createSymbolicLink(
            at: folder.appendingPathComponent(BatchFoldService.outputFolderName),
            withDestinationURL: outside
        )

        let result = await BatchFoldService.run(
            inputFolder: folder,
            files: [source],
            options: BatchFoldService.Options(watermarkText: "DRAFT"),
            progress: { _, _ in },
            isCancelled: { false }
        )

        XCTAssertNil(result.outputDirectory)
        XCTAssertNotNil(result.setupFailureMessage)
        XCTAssertEqual(result.notStartedCount, 1)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: outside.path).isEmpty)
    }

    func testRunFailsClosedWhenFoldedDirectoryIsReplacedBeforeCommit() async throws {
        let folder = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("a.pdf")
        try whitePDFData(pages: 1).write(to: source)
        let swap = OneShotDirectorySwap()

        let result = await BatchFoldService.run(
            inputFolder: folder,
            files: [source],
            options: BatchFoldService.Options(watermarkText: "DRAFT"),
            progress: { _, _ in },
            isCancelled: { false },
            beforeOutputCommit: { try swap.replaceDirectory(containing: $0) }
        )

        XCTAssertEqual(result.failedCount, 1)
        guard case .failed(let message) = result.outcomes[0].result else {
            return XCTFail("the directory replacement should fail the current input")
        }
        XCTAssertEqual(message, ExportWriteError.outputDirectoryChanged.localizedDescription)
        for name in [BatchFoldService.outputFolderName, OneShotDirectorySwap.movedName] {
            let directory = folder.appendingPathComponent(name)
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
        }
    }

    func testRunKeepsReadingTheOriginalRootWhenItsPathIsReplacedBetweenInputs() async throws {
        let folder = try makeTempFolder()
        let movedFolder = folder.deletingLastPathComponent()
            .appendingPathComponent("\(folder.lastPathComponent)-moved", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: folder)
            try? FileManager.default.removeItem(at: movedFolder)
        }
        let files = try ["a.pdf", "b.pdf"].map { name in
            let url = folder.appendingPathComponent(name)
            try whitePDFData(pages: 1).write(to: url)
            return url
        }
        let swap = OneShotRootSwap(movedFolder: movedFolder)

        let result = await BatchFoldService.run(
            inputFolder: folder,
            files: files,
            options: BatchFoldService.Options(watermarkText: "DRAFT"),
            progress: { _, _ in },
            isCancelled: { false },
            beforeOutputCommit: { try swap.replaceRoot(containing: $0) }
        )

        XCTAssertEqual(result.foldedCount, 2)
        XCTAssertEqual(result.failedCount, 0)
        let actualOutputDirectory = try XCTUnwrap(result.outputDirectory).resolvingSymlinksInPath()
        XCTAssertEqual(
            actualOutputDirectory,
            movedFolder.appendingPathComponent(BatchFoldService.outputFolderName).resolvingSymlinksInPath()
        )
        XCTAssertTrue(result.outcomes.compactMap(\.outputURL).allSatisfy {
            FileManager.default.fileExists(atPath: $0.path)
        })
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: folder.appendingPathComponent(BatchFoldService.outputFolderName).path
            )
        )
        XCTAssertEqual(
            try Data(contentsOf: folder.appendingPathComponent("b.pdf")),
            OneShotRootSwap.redirectedBytes
        )
    }

    func testRunRetriesANameCreatedAtCommitAndPreservesTheCompetingFile() async throws {
        let folder = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("a.pdf")
        try whitePDFData(pages: 1).write(to: source)
        let collision = OneShotCommitCollision()

        var options = BatchFoldService.Options()
        options.watermarkText = "DRAFT"
        let result = await BatchFoldService.run(
            inputFolder: folder,
            files: [source],
            options: options,
            progress: { _, _ in },
            isCancelled: { false },
            beforeOutputCommit: { try collision.createFile(at: $0) }
        )

        XCTAssertEqual(result.foldedCount, 1)
        let outputDirectory = try XCTUnwrap(result.outputDirectory)
        let firstName = outputDirectory.appendingPathComponent("a-folded.pdf")
        XCTAssertEqual(try Data(contentsOf: firstName), OneShotCommitCollision.marker)
        let outputURL = try XCTUnwrap(result.outcomes.first?.outputURL)
        XCTAssertEqual(outputURL.lastPathComponent, "a-folded-2.pdf")
        XCTAssertTrue(QPDFService.isStructurallySound(try Data(contentsOf: outputURL)))
    }

    func testRunStopsBetweenFilesWhenCancelled() async throws {
        let folder = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        var files: [URL] = []
        for name in ["a.pdf", "b.pdf", "c.pdf"] {
            let url = folder.appendingPathComponent(name)
            try whitePDFData(pages: 1).write(to: url)
            files.append(url)
        }
        let outputDirectory = folder.appendingPathComponent(BatchFoldService.outputFolderName)

        var options = BatchFoldService.Options()
        options.watermarkText = "DRAFT"

        // Cancels as soon as the first result lands, which `run` observes at the next
        // between-files check — deterministic without any timing games.
        let result = await BatchFoldService.run(
            inputFolder: folder,
            files: files,
            options: options,
            progress: { _, _ in },
            isCancelled: {
                let written = (try? FileManager.default.contentsOfDirectory(atPath: outputDirectory.path)) ?? []
                return !written.isEmpty
            }
        )

        XCTAssertTrue(result.wasCancelled)
        XCTAssertEqual(result.foldedCount, 1)
        XCTAssertEqual(result.outcomes.count, files.count)
        XCTAssertEqual(result.failedCount, 0)
        XCTAssertEqual(result.cancelledCount, 0)
        XCTAssertEqual(result.notStartedCount, 2)
    }

    func testRunCancelledBeforeFirstInputLeavesTheCompleteLedgerNotStarted() async throws {
        let folder = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let files = try ["a.pdf", "b.pdf"].map { name in
            let url = folder.appendingPathComponent(name)
            try whitePDFData(pages: 1).write(to: url)
            return url
        }

        let result = await BatchFoldService.run(
            inputFolder: folder,
            files: files,
            options: BatchFoldService.Options(watermarkText: "DRAFT"),
            progress: { _, _ in },
            isCancelled: { true }
        )

        XCTAssertTrue(result.wasCancelled)
        XCTAssertEqual(result.foldedCount, 0)
        XCTAssertEqual(result.cancelledCount, 0)
        XCTAssertEqual(result.notStartedCount, 2)
    }

    func testRunMarksTheInterruptedFileAndLeavesLaterFilesNotStarted() async throws {
        let folder = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let files = try ["a.pdf", "b.pdf"].map { name in
            let url = folder.appendingPathComponent(name)
            try whitePDFData(pages: 1).write(to: url)
            return url
        }
        var options = BatchFoldService.Options()
        options.watermarkText = "DRAFT"
        let cancellation = CancelOnSecondCheck()

        let result = await BatchFoldService.run(
            inputFolder: folder,
            files: files,
            options: options,
            progress: { _, _ in },
            isCancelled: { cancellation.isCancelled }
        )

        XCTAssertTrue(result.wasCancelled)
        XCTAssertEqual(result.foldedCount, 0)
        XCTAssertEqual(result.cancelledCount, 1)
        XCTAssertEqual(result.notStartedCount, 1)
        if case .cancelled = result.outcomes[0].result {} else {
            XCTFail("the interrupted input should be distinct from inputs never started")
        }
        if case .notStarted = result.outcomes[1].result {} else {
            XCTFail("later inputs should remain not started")
        }
    }

    func testRunReportsLockedPDFAsFailedWithoutCreatingAnOutput() async throws {
        let folder = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("locked.pdf")
        let encrypted = try PDFEncryptionService.encryptedData(
            from: whitePDFData(pages: 1),
            options: PDFEncryptionOptions(
                userPassword: "reader-pass",
                ownerPassword: "owner-pass",
                allowsPrinting: true,
                allowsCopying: false
            )
        )
        try encrypted.write(to: source)

        let result = await BatchFoldService.run(
            inputFolder: folder,
            files: [source],
            options: BatchFoldService.Options(watermarkText: "DRAFT"),
            progress: { _, _ in },
            isCancelled: { false }
        )

        XCTAssertEqual(result.failedCount, 1)
        XCTAssertEqual(result.notStartedCount, 0)
        guard case .failed(let message) = result.outcomes[0].result else {
            return XCTFail("the locked input should be reported as a failure")
        }
        XCTAssertEqual(message, BatchFoldService.BatchFoldError.lockedPDF.localizedDescription)
        let outputDirectory = try XCTUnwrap(result.outputDirectory)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: outputDirectory.path).isEmpty)
    }

    func testRunRejectsOversizedInputWithoutReadingOrPublishingIt() async throws {
        let folder = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("oversized.pdf")
        XCTAssertTrue(FileManager.default.createFile(atPath: source.path, contents: Data()))
        let handle = try FileHandle(forWritingTo: source)
        try handle.truncate(atOffset: UInt64(DocumentImportConverter.maxImportBytes + 1))
        try handle.close()

        let result = await BatchFoldService.run(
            inputFolder: folder,
            files: [source],
            options: BatchFoldService.Options(watermarkText: "DRAFT"),
            progress: { _, _ in },
            isCancelled: { false }
        )

        XCTAssertEqual(result.failedCount, 1)
        XCTAssertEqual(result.notStartedCount, 0)
        guard case .failed(let message) = result.outcomes[0].result else {
            return XCTFail("the oversized input should be reported as a failure")
        }
        XCTAssertEqual(
            message,
            DocumentImportConverter.userMessage(
                for: DocumentImportConverter.ConversionError.fileTooLarge(
                    DocumentImportConverter.maxImportBytes + 1
                )
            )
        )
        let outputDirectory = try XCTUnwrap(result.outputDirectory)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: outputDirectory.path).isEmpty)
    }

    func testRunKeepsEveryInputNotStartedWhenOutputFolderSetupFails() async throws {
        let root = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let inputFolder = root.appendingPathComponent("not-a-folder")
        try Data("plain file".utf8).write(to: inputFolder)
        let sources = [
            inputFolder.appendingPathComponent("a.pdf"),
            inputFolder.appendingPathComponent("b.pdf")
        ]

        let result = await BatchFoldService.run(
            inputFolder: inputFolder,
            files: sources,
            options: BatchFoldService.Options(watermarkText: "DRAFT"),
            scanWasTruncated: true,
            scanFailureCount: 1,
            progress: { _, _ in },
            isCancelled: { false }
        )

        XCTAssertNil(result.outputDirectory)
        XCTAssertNotNil(result.setupFailureMessage)
        XCTAssertEqual(result.notStartedCount, 2)
        XCTAssertEqual(result.failedCount, 0)
        XCTAssertTrue(result.scanWasTruncated)
        XCTAssertEqual(result.scanFailureCount, 1)
    }

    // MARK: - Fixtures

    private func makeTempFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("BatchFoldServiceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func whitePDFData(pages: Int, speckled: Bool = false) throws -> Data {
        let pdf = PDFDocument()
        for index in 0..<pages {
            let size = CGSize(width: 400, height: 400)
            let image = NSImage(size: size)
            image.lockFocus()
            NSColor.white.setFill()
            NSRect(origin: .zero, size: size).fill()
            if speckled {
                NSColor.black.setFill()
                var seed: UInt64 = 42
                for _ in 0..<160 {
                    seed = seed &* 6364136223846793005 &+ 1442695040888963407
                    let x = CGFloat(seed % 380) + 10
                    let y = CGFloat((seed >> 16) % 380) + 10
                    NSRect(x: x, y: y, width: 2, height: 2).fill()
                }
            }
            image.unlockFocus()
            let page = try XCTUnwrap(PDFPage(image: image))
            pdf.insert(page, at: index)
        }
        return try XCTUnwrap(PDFSerializer.data(from: pdf))
    }

    /// Fraction of sampled pixels that are non-white — the sanctioned ink check (never
    /// `PDFPage.string`; see PDFPageStringGuardTests). The cutoff sits at 0.97, not the
    /// 0.85 other ink checks use, because the baked watermark is *deliberately* pale
    /// (0.16 opacity): its pixels land around 0.9 brightness, while the untouched fixture
    /// pages are pure white, so anything below the cutoff is real watermark ink.
    private func inkCoverage(of data: Data, pageIndex: Int) throws -> Double {
        let pdf = try XCTUnwrap(PDFDocument(data: data))
        let page = try XCTUnwrap(pdf.page(at: pageIndex))
        let bounds = page.bounds(for: .mediaBox)
        let thumbnail = page.thumbnail(of: CGSize(width: bounds.width, height: bounds.height), for: .mediaBox)
        let tiff = try XCTUnwrap(thumbnail.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))

        var inked = 0
        var sampled = 0
        for px in stride(from: 0, to: bitmap.pixelsWide, by: 7) {
            for py in stride(from: 0, to: bitmap.pixelsHigh, by: 7) {
                guard let color = bitmap.colorAt(x: px, y: py)?.usingColorSpace(.deviceRGB) else { continue }
                sampled += 1
                if color.brightnessComponent < 0.97 { inked += 1 }
            }
        }
        guard sampled > 0 else { return 0 }
        return Double(inked) / Double(sampled)
    }
}

private extension BatchFoldService.FileOutcome {
    var outputURL: URL? {
        if case .folded(let outputURL) = result { return outputURL }
        return nil
    }
}

private final class OneShotCommitCollision: @unchecked Sendable {
    static let marker = Data("competing output".utf8)
    private let lock = NSLock()
    private var hasCreatedFile = false

    func createFile(at url: URL) throws {
        lock.lock()
        defer { lock.unlock() }
        guard !hasCreatedFile else { return }
        hasCreatedFile = true
        try Self.marker.write(to: url, options: .withoutOverwriting)
    }
}

private final class OneShotDirectorySwap: @unchecked Sendable {
    static let movedName = "Folded-before-swap"
    private let lock = NSLock()
    private var hasReplacedDirectory = false

    func replaceDirectory(containing outputURL: URL) throws {
        lock.lock()
        defer { lock.unlock() }
        guard !hasReplacedDirectory else { return }
        hasReplacedDirectory = true

        let directory = outputURL.deletingLastPathComponent()
        let movedDirectory = directory.deletingLastPathComponent()
            .appendingPathComponent(Self.movedName, isDirectory: true)
        try FileManager.default.moveItem(at: directory, to: movedDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    }
}

private final class OneShotRootSwap: @unchecked Sendable {
    static let redirectedBytes = Data("redirected replacement input".utf8)
    private let lock = NSLock()
    private let movedFolder: URL
    private var hasReplacedRoot = false

    init(movedFolder: URL) {
        self.movedFolder = movedFolder
    }

    func replaceRoot(containing outputURL: URL) throws {
        lock.lock()
        defer { lock.unlock() }
        guard !hasReplacedRoot else { return }
        hasReplacedRoot = true

        let root = outputURL.deletingLastPathComponent().deletingLastPathComponent()
        try FileManager.default.moveItem(at: root, to: movedFolder)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        try Self.redirectedBytes.write(
            to: root.appendingPathComponent("b.pdf"),
            options: .withoutOverwriting
        )
    }
}

private final class CancelOnSecondCheck: @unchecked Sendable {
    private let lock = NSLock()
    private var checkCount = 0

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        checkCount += 1
        return checkCount >= 2
    }
}

private enum FixtureFailure: Error {
    case rejected
}
