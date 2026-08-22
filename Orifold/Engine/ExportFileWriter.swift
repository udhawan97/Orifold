import Foundation

enum ExportWriteError: Error, LocalizedError {
    case fileNotFound
    case emptyFile

    var errorDescription: String? { userMessage }

    var userMessage: String {
        switch self {
        case .fileNotFound:
            return L10n.string("error.export.writeFileNotFound")
        case .emptyFile:
            return L10n.string("error.export.writeEmptyFile")
        }
    }
}

/// The one crash-safe way Orifold puts export bytes on disk, extracted from
/// `WorkspaceViewModel` so batch operations share it instead of duplicating it.
enum ExportFileWriter {
    /// Writes export bytes to `targetURL`, preferring a crash-safe temp-file +
    /// atomic swap so a crash or force-quit mid-write can't leave a truncated
    /// file at the user's real destination. Falls back to a direct,
    /// non-atomic write only if the temp-sibling-file write itself can't even
    /// start -- some sandboxed destinations only grant write access to the
    /// exact NSSavePanel-chosen path, not sibling paths in the same folder
    /// (which is also why neither write uses `.atomic`: that option creates
    /// its own hidden sibling temp file, which would hit the same problem).
    /// `validate` runs against the written bytes before they're committed to
    /// `targetURL`, so a validation failure never lands at the real destination.
    static func write(_ data: Data, to targetURL: URL, validate: ((Data) throws -> Void)? = nil) throws {
        let fileManager = FileManager.default
        let directory = targetURL.deletingLastPathComponent()
        let tempURL = directory.appendingPathComponent(".Orifold-export-\(UUID().uuidString)")

        let wroteTemp: Bool
        do {
            try data.write(to: tempURL)
            wroteTemp = true
        } catch {
            wroteTemp = false
        }

        if wroteTemp {
            defer { try? fileManager.removeItem(at: tempURL) }
            if let validate {
                try validate(try Data(contentsOf: tempURL))
            }
            if fileManager.fileExists(atPath: targetURL.path) {
                guard try fileManager.replaceItemAt(
                    targetURL,
                    withItemAt: tempURL,
                    backupItemName: nil,
                    options: [.usingNewMetadataOnly]
                ) != nil else {
                    throw ExportWriteError.fileNotFound
                }
            } else {
                try fileManager.moveItem(at: tempURL, to: targetURL)
            }
        } else {
            if let validate {
                try validate(data)
            }
            try data.write(to: targetURL)
        }
    }

    /// The only source of truth for "did the export actually land on disk" --
    /// callers must not report success from a Task/panel return value alone.
    static func verify(at url: URL) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw ExportWriteError.fileNotFound
        }
        if isDirectory.boolValue {
            let contents = try FileManager.default.contentsOfDirectory(atPath: url.path)
            guard !contents.isEmpty else { throw ExportWriteError.emptyFile }
        } else {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
            guard size > 0 else { throw ExportWriteError.emptyFile }
        }
    }
}
