import Foundation
import PDFKit

/// "Fold the whole stack": run OCR, watermarking, and/or compression over every PDF in a
/// folder in one pass, writing results into a `Folded` subfolder and never touching the
/// originals. Each file is processed independently, so one unreadable PDF becomes one
/// failed outcome rather than aborting the batch.
enum BatchFoldService {
    /// Name of the subfolder created inside the chosen folder to hold the results.
    /// Deliberately not localized: a stable name means repeat runs reuse one folder
    /// instead of scattering results across per-language siblings.
    static let outputFolderName = "Folded"

    struct Options: Equatable, Sendable {
        var compressionPreset: PDFCompressionPreset?
        var runsOCR = false
        var watermarkText: String?

        /// Whether no operation is selected at all — the sheet disables Run on this.
        var isEmpty: Bool {
            compressionPreset == nil && !runsOCR && trimmedWatermarkText == nil
        }

        var trimmedWatermarkText: String? {
            guard let text = watermarkText?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else { return nil }
            return text
        }
    }

    enum FileResult: Equatable, Sendable {
        case folded(outputURL: URL)
        case failed(message: String)
        case cancelled
        case notStarted
    }

    struct FileOutcome: Equatable, Sendable {
        var sourceURL: URL
        var result: FileResult
    }

    struct RunResult: Sendable {
        var inputFolder: URL
        var outcomes: [FileOutcome]
        var outputDirectory: URL?
        var setupFailureMessage: String?
        var wasCancelled = false
        var scanWasTruncated: Bool
        var scanFailureCount: Int

        init(
            inputFolder: URL,
            files: [URL],
            scanWasTruncated: Bool = false,
            scanFailureCount: Int = 0
        ) {
            self.inputFolder = inputFolder
            outcomes = files.map { FileOutcome(sourceURL: $0, result: .notStarted) }
            self.scanWasTruncated = scanWasTruncated
            self.scanFailureCount = scanFailureCount
        }

        var foldedCount: Int {
            outcomes.filter { if case .folded = $0.result { return true } else { return false } }.count
        }

        var failedCount: Int {
            outcomes.filter { if case .failed = $0.result { return true } else { return false } }.count
        }

        var cancelledCount: Int {
            outcomes.filter { if case .cancelled = $0.result { return true } else { return false } }.count
        }

        var notStartedCount: Int {
            outcomes.filter { if case .notStarted = $0.result { return true } else { return false } }.count
        }

        var notProcessedCount: Int { cancelledCount + notStartedCount }

        var firstFailureMessage: String? {
            for outcome in outcomes {
                if case .failed(let message) = outcome.result { return message }
            }
            return nil
        }
    }

    enum BatchFoldError: LocalizedError, Equatable {
        case unreadablePDF
        case lockedPDF
        case outputUnsound

        var errorDescription: String? {
            switch self {
            case .unreadablePDF:
                return L10n.string("error.batchFold.unreadable")
            case .lockedPDF:
                return L10n.string("error.batchFold.locked")
            case .outputUnsound:
                return L10n.string("error.batchFold.outputUnsound")
            }
        }
    }

    // MARK: - Planning (pure)

    /// The PDFs a folder scan contributes to a batch. The scanner accepts every importable
    /// type; folding only transforms PDFs, so everything else is left untouched.
    static func pdfURLs(from scan: FolderScanResult, inputFolder: URL) -> [URL] {
        let outputDirectory = inputFolder
            .appendingPathComponent(outputFolderName, isDirectory: true)
            .standardizedFileURL
        let outputPathPrefix = outputDirectory.path + "/"

        return scan.supportedURLs.filter { url in
            guard url.pathExtension.lowercased() == "pdf" else { return false }
            let standardizedPath = url.standardizedFileURL.path
            return standardizedPath != outputDirectory.path
                && !standardizedPath.hasPrefix(outputPathPrefix)
        }
    }

    /// Collision-proof output file name for one source, against the names already present in
    /// the output folder (case-insensitive, as on default macOS volumes).
    static func outputName(for source: URL, existingNames: Set<String>) -> String {
        let base = source.deletingPathExtension().lastPathComponent
        let lowered = Set(existingNames.map { $0.lowercased() })
        var candidate = "\(base)-folded.pdf"
        var counter = 2
        while lowered.contains(candidate.lowercased()) {
            candidate = "\(base)-folded-\(counter).pdf"
            counter += 1
        }
        return candidate
    }

    // MARK: - Per-file pipeline

    /// Transforms one PDF's bytes: OCR first (so scans gain the text layer the later stages
    /// and the user's search both want), then the watermark bake, then compression last so
    /// it shrinks the final content. Throws for a failure that should mark this file failed;
    /// benign per-file conditions (nothing scanned, compression would grow the file) keep
    /// the prior bytes and continue.
    static func fold(
        _ data: Data,
        fileName: String,
        options: Options,
        progress: @escaping @Sendable (Double) -> Void = { _ in },
        isCancelled: @escaping @Sendable () -> Bool = { false },
        recognitionProvider: PDFOCRService.RecognitionProvider? = nil
    ) async throws -> Data {
        if let sourceDocument = PDFDocument(data: data), sourceDocument.isLocked {
            throw BatchFoldError.lockedPDF
        }
        var current = data
        let stageCount = Double(max(enabledStageCount(options), 1))
        // Immutable per-stage base offsets, because the engines' progress callbacks are
        // `@Sendable` and therefore cannot capture a mutated counter.
        var completedStages = 0.0

        if options.runsOCR {
            try checkCancellation(isCancelled)
            let member = MemberDocument(displayName: fileName, sourcePDFRef: fileName)
            let base = completedStages
            do {
                let result: PDFOCRResult
                if let recognitionProvider {
                    result = try await PDFOCRService.searchableData(
                        documents: [(member, current)],
                        recognitionProvider: recognitionProvider,
                        progress: { progress(min((base + $0) / stageCount, 1)) },
                        isCancelled: isCancelled
                    )
                } else {
                    result = try await PDFOCRService.makeSearchable(
                        documents: [(member, current)],
                        progress: { progress(min((base + $0) / stageCount, 1)) },
                        isCancelled: isCancelled
                    )
                }
                if let searchable = result.dataByMemberID[member.id] {
                    current = searchable
                }
            } catch let error as PDFOCRError where error == .noScannedPages {
                // A text-native PDF has nothing to recognize; folding it is still fine.
            }
            completedStages += 1
            progress(min(completedStages / stageCount, 1))
        }

        if let watermarkText = options.trimmedWatermarkText {
            try checkCancellation(isCancelled)
            guard let document = PDFDocument(data: current), document.pageCount > 0 else {
                throw BatchFoldError.unreadablePDF
            }
            let memberID = UUID()
            let pageOrder = (0..<document.pageCount).map {
                PageRef(memberDocId: memberID, sourcePageIndex: $0)
            }
            let watermark = PageDecoration(
                kind: .watermark,
                text: watermarkText,
                fontSize: 64,
                opacity: 0.16,
                swatch: .tertiary
            )
            current = try PDFDecorationExportBaker.bake(
                decorations: [watermark],
                pageOrder: pageOrder,
                into: current
            )
            completedStages += 1
            progress(min(completedStages / stageCount, 1))
        }

        if let preset = options.compressionPreset {
            try checkCancellation(isCancelled)
            let base = completedStages
            do {
                let result = try PDFCompressionService.reduceFileSize(
                    of: current,
                    preset: preset,
                    progress: { progress(min((base + $0) / stageCount, 1)) },
                    isCancelled: isCancelled
                )
                current = result.data
            } catch let error as PDFCompressionError where error == .grewLarger {
                // Already compact; keeping the pre-compression bytes is the success path.
            }
            completedStages += 1
            progress(min(completedStages / stageCount, 1))
        }

        guard QPDFService.isStructurallySound(current) else {
            throw BatchFoldError.outputUnsound
        }
        progress(1)
        return current
    }

    // MARK: - Batch run

    /// Runs the whole batch off the main actor: brackets the folder's security scope (the
    /// same raw start/stop shape as `FolderImportScanner`, because the scope must span the
    /// loop), creates the output folder, then folds and writes each file independently.
    static func run(
        inputFolder: URL,
        files: [URL],
        options: Options,
        scanWasTruncated: Bool = false,
        scanFailureCount: Int = 0,
        progress: @escaping @Sendable (Double, String) -> Void,
        isCancelled: @escaping @Sendable () -> Bool,
        recognitionProvider: PDFOCRService.RecognitionProvider? = nil,
        beforeOutputCommit: (@Sendable (URL) throws -> Void)? = nil
    ) async -> RunResult {
        await Task.detached(priority: .userInitiated) {
            var result = RunResult(
                inputFolder: inputFolder,
                files: files,
                scanWasTruncated: scanWasTruncated,
                scanFailureCount: scanFailureCount
            )
            let isSecurityScoped = inputFolder.startAccessingSecurityScopedResource()
            defer { if isSecurityScoped { inputFolder.stopAccessingSecurityScopedResource() } }

            guard let authorizedDirectory = BoundedLocalFileDirectory(authorizedRoot: inputFolder) else {
                result.setupFailureMessage = L10n.string("batchFold.error.outputFolder")
                return result
            }
            let outputDirectory: ExportOutputDirectory
            do {
                outputDirectory = try ExportOutputDirectory(
                    parentURL: inputFolder,
                    parentDirectory: authorizedDirectory,
                    directoryName: outputFolderName
                )
                result.outputDirectory = outputDirectory.url
            } catch {
                result.setupFailureMessage = error.localizedDescription
                return result
            }

            let initialNames: Set<String>
            do {
                initialNames = try outputDirectory.existingNames()
            } catch {
                result.setupFailureMessage = error.localizedDescription
                return result
            }
            var existingNames = initialNames
            let totalCount = Double(max(files.count, 1))

            for (index, sourceURL) in files.enumerated() {
                if isCancelled() {
                    result.wasCancelled = true
                    break
                }
                progress(Double(index) / totalCount, sourceURL.lastPathComponent)
                do {
                    let data = try BoundedLocalFileReader.readFileReportingFailure(
                        at: sourceURL,
                        within: inputFolder,
                        using: authorizedDirectory,
                        maxBytes: Int(DocumentImportConverter.maxImportBytes)
                    )
                    guard !data.isEmpty else {
                        throw BatchFoldError.unreadablePDF
                    }
                    let folded = try await fold(
                        data,
                        fileName: sourceURL.lastPathComponent,
                        options: options,
                        progress: { fileFraction in
                            progress(
                                (Double(index) + fileFraction) / totalCount,
                                sourceURL.lastPathComponent
                            )
                        },
                        isCancelled: isCancelled,
                        recognitionProvider: recognitionProvider
                    )
                    try checkCancellation(isCancelled)
                    let outputURL = try publish(
                        folded,
                        from: sourceURL,
                        into: outputDirectory,
                        existingNames: &existingNames,
                        beforeOutputCommit: beforeOutputCommit
                    )
                    result.outcomes[index].result = .folded(outputURL: outputURL)
                    if isCancelled() {
                        result.wasCancelled = true
                        break
                    }
                } catch is CancellationError {
                    result.outcomes[index].result = .cancelled
                    result.wasCancelled = true
                    break
                } catch {
                    result.outcomes[index].result = .failed(message: error.localizedDescription)
                }
            }
            result.outputDirectory = outputDirectory.currentURL
            progress(1, "")
            return result
        }.value
    }

    // MARK: - Helpers

    private static let maximumPublicationAttempts = 100

    private static func publish(
        _ data: Data,
        from sourceURL: URL,
        into outputDirectory: ExportOutputDirectory,
        existingNames: inout Set<String>,
        beforeOutputCommit: (@Sendable (URL) throws -> Void)?
    ) throws -> URL {
        for _ in 0..<maximumPublicationAttempts {
            let name = outputName(for: sourceURL, existingNames: existingNames)
            let outputURL = outputDirectory.url.appendingPathComponent(name)
            do {
                try ExportFileWriter.createNew(
                    data,
                    named: name,
                    in: outputDirectory,
                    validate: { bytes in
                        guard QPDFService.isStructurallySound(bytes) else {
                            throw BatchFoldError.outputUnsound
                        }
                    },
                    beforeCommit: { try beforeOutputCommit?(outputURL) }
                )
                existingNames.insert(name)
                return outputDirectory.currentURL.appendingPathComponent(name)
            } catch ExportWriteError.destinationExists {
                existingNames.insert(name)
            }
        }
        throw ExportWriteError.destinationExists
    }

    private static func enabledStageCount(_ options: Options) -> Int {
        var count = 0
        if options.runsOCR { count += 1 }
        if options.trimmedWatermarkText != nil { count += 1 }
        if options.compressionPreset != nil { count += 1 }
        return count
    }

    private static func checkCancellation(_ isCancelled: () -> Bool) throws {
        if isCancelled() { throw CancellationError() }
    }
}
