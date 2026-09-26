import Darwin
import Foundation

enum ExportWriteError: Error, LocalizedError {
    case fileNotFound
    case emptyFile
    case destinationExists
    case outputDirectoryChanged

    var errorDescription: String? { userMessage }

    var userMessage: String {
        switch self {
        case .fileNotFound:
            return L10n.string("error.export.writeFileNotFound")
        case .emptyFile:
            return L10n.string("error.export.writeEmptyFile")
        case .destinationExists:
            return L10n.string("error.batchFold.outputCollision")
        case .outputDirectoryChanged:
            return L10n.string("error.batchFold.outputDirectoryChanged")
        }
    }
}

/// A retained, no-symlink descriptor for a batch output folder and its selected parent.
/// Publication uses these descriptors rather than resolving either directory by pathname again.
final class ExportOutputDirectory {
    let url: URL

    fileprivate let descriptor: Int32
    private let parentDescriptor: Int32
    private let directoryName: String

    convenience init(parentURL: URL, directoryName: String) throws {
        guard let parentDirectory = BoundedLocalFileDirectory(authorizedRoot: parentURL) else {
            throw ExportWriteError.outputDirectoryChanged
        }
        try self.init(
            parentURL: parentURL,
            parentDirectory: parentDirectory,
            directoryName: directoryName
        )
    }

    init(
        parentURL: URL,
        parentDirectory: BoundedLocalFileDirectory,
        directoryName: String
    ) throws {
        guard parentURL.isFileURL,
              parentURL.path.hasPrefix("/"),
              !directoryName.isEmpty,
              directoryName != ".",
              directoryName != "..",
              !directoryName.contains("/") else {
            throw ExportWriteError.outputDirectoryChanged
        }

        let openedParent = try parentDirectory.duplicateDescriptor()

        let createResult = directoryName.withCString {
            Darwin.mkdirat(openedParent, $0, mode_t(0o755))
        }
        if createResult != 0, errno != EEXIST {
            let error = currentPOSIXError()
            Darwin.close(openedParent)
            throw error
        }

        let openedDirectory = directoryName.withCString {
            Darwin.openat(
                openedParent,
                $0,
                O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
            )
        }
        guard openedDirectory >= 0 else {
            let error = currentPOSIXError()
            Darwin.close(openedParent)
            throw error
        }

        parentDescriptor = openedParent
        descriptor = openedDirectory
        self.directoryName = directoryName
        url = parentURL.appendingPathComponent(directoryName, isDirectory: true)

        do {
            try verifyBinding()
        } catch {
            Darwin.close(openedDirectory)
            Darwin.close(openedParent)
            throw error
        }
    }

    deinit {
        Darwin.close(descriptor)
        Darwin.close(parentDescriptor)
    }

    func existingNames() throws -> Set<String> {
        let duplicate = Darwin.dup(descriptor)
        guard duplicate >= 0 else { throw currentPOSIXError() }
        guard let stream = Darwin.fdopendir(duplicate) else {
            let error = currentPOSIXError()
            Darwin.close(duplicate)
            throw error
        }
        defer { Darwin.closedir(stream) }

        var names = Set<String>()
        while let entry = Darwin.readdir(stream) {
            let name = withUnsafePointer(to: &entry.pointee.d_name) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) {
                    String(cString: $0)
                }
            }
            if name != ".", name != ".." { names.insert(name) }
        }
        return names
    }

    var currentURL: URL {
        var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let result = Darwin.fcntl(descriptor, F_GETPATH, &path)
        guard result == 0 else { return url }
        return URL(fileURLWithPath: String(cString: path), isDirectory: true)
    }

    fileprivate func verifyBinding() throws {
        var openedMetadata = stat()
        var namedMetadata = stat()
        guard Darwin.fstat(descriptor, &openedMetadata) == 0 else { throw currentPOSIXError() }
        let result = directoryName.withCString {
            Darwin.fstatat(parentDescriptor, $0, &namedMetadata, AT_SYMLINK_NOFOLLOW)
        }
        guard result == 0,
              (namedMetadata.st_mode & S_IFMT) == S_IFDIR,
              openedMetadata.st_dev == namedMetadata.st_dev,
              openedMetadata.st_ino == namedMetadata.st_ino else {
            throw ExportWriteError.outputDirectoryChanged
        }
    }

    fileprivate func identity(of name: String) -> (device: dev_t, inode: ino_t)? {
        var metadata = stat()
        let result = name.withCString {
            Darwin.fstatat(descriptor, $0, &metadata, AT_SYMLINK_NOFOLLOW)
        }
        guard result == 0 else { return nil }
        return (metadata.st_dev, metadata.st_ino)
    }

    fileprivate func removeEntry(
        named name: String,
        matching identity: (device: dev_t, inode: ino_t)
    ) {
        guard let currentIdentity = self.identity(of: name),
              currentIdentity.device == identity.device,
              currentIdentity.inode == identity.inode else { return }
        _ = name.withCString { Darwin.unlinkat(descriptor, $0, 0) }
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

    /// Publishes validated bytes in a retained directory only if the name does not exist.
    ///
    /// Batch output names are selected from a directory snapshot, so another process can create
    /// the same name before publication. A hard link gives us an atomic no-replace commit on the
    /// destination's own file system: descriptor-relative `linkat(2)` either creates the final
    /// directory entry or fails with `EEXIST`. Temporary-file cleanup compares inode identity
    /// before unlinking, so it never removes a path another writer replaced. There is deliberately
    /// no direct-write fallback, because it could truncate a destination that appeared later.
    static func createNew(
        _ data: Data,
        named targetName: String,
        in directory: ExportOutputDirectory,
        validate: ((Data) throws -> Void)? = nil,
        beforeCommit: (() throws -> Void)? = nil,
        commitForTesting: (() throws -> Void)? = nil,
        afterCommitForTesting: (() throws -> Void)? = nil
    ) throws {
        guard !targetName.isEmpty,
              targetName != ".",
              targetName != "..",
              !targetName.contains("/") else {
            throw ExportWriteError.fileNotFound
        }

        let tempName = ".Orifold-export-\(UUID().uuidString)"
        let stagedDescriptor = tempName.withCString {
            Darwin.openat(
                directory.descriptor,
                $0,
                O_RDWR | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW,
                mode_t(0o644)
            )
        }
        guard stagedDescriptor >= 0 else { throw currentPOSIXError() }

        var stagedMetadata = stat()
        guard Darwin.fstat(stagedDescriptor, &stagedMetadata) == 0 else {
            let error = currentPOSIXError()
            Darwin.close(stagedDescriptor)
            throw error
        }
        let stagedIdentity = (device: stagedMetadata.st_dev, inode: stagedMetadata.st_ino)
        defer {
            Darwin.close(stagedDescriptor)
            directory.removeEntry(named: tempName, matching: stagedIdentity)
        }

        try writeAll(data, to: stagedDescriptor)
        guard Darwin.fsync(stagedDescriptor) == 0 else { throw currentPOSIXError() }
        guard Darwin.lseek(stagedDescriptor, 0, SEEK_SET) == 0 else { throw currentPOSIXError() }
        let stagedData = try readAll(from: stagedDescriptor, expectedSize: data.count)
        if let validate {
            try validate(stagedData)
        }
        try beforeCommit?()
        try directory.verifyBinding()
        guard let currentStagedIdentity = directory.identity(of: tempName),
              currentStagedIdentity.device == stagedIdentity.device,
              currentStagedIdentity.inode == stagedIdentity.inode else {
            throw ExportWriteError.fileNotFound
        }

        if let commitForTesting {
            try commitForTesting()
        } else {
            let result = tempName.withCString { sourceName in
                targetName.withCString { targetName in
                    Darwin.linkat(directory.descriptor, sourceName, directory.descriptor, targetName, 0)
                }
            }
            guard result == 0 else {
                if errno == EEXIST { throw ExportWriteError.destinationExists }
                throw currentPOSIXError()
            }
        }
        try afterCommitForTesting?()

        guard let targetIdentity = directory.identity(of: targetName) else {
            throw ExportWriteError.fileNotFound
        }
        guard targetIdentity.device == stagedIdentity.device,
              targetIdentity.inode == stagedIdentity.inode else {
            throw ExportWriteError.fileNotFound
        }
        do {
            try directory.verifyBinding()
        } catch {
            directory.removeEntry(named: targetName, matching: stagedIdentity)
            throw error
        }
    }

    private static func writeAll(_ data: Data, to descriptor: Int32) throws {
        try data.withUnsafeBytes { bytes in
            var written = 0
            while written < bytes.count {
                let result = Darwin.write(
                    descriptor,
                    bytes.baseAddress?.advanced(by: written),
                    bytes.count - written
                )
                if result < 0, errno == EINTR { continue }
                guard result > 0 else { throw currentPOSIXError() }
                written += result
            }
        }
    }

    private static func readAll(from descriptor: Int32, expectedSize: Int) throws -> Data {
        var data = Data()
        data.reserveCapacity(expectedSize)
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = buffer.withUnsafeMutableBytes {
                Darwin.read(descriptor, $0.baseAddress, $0.count)
            }
            if count == 0 { return data }
            if count < 0, errno == EINTR { continue }
            guard count > 0, count <= expectedSize - data.count else {
                throw ExportWriteError.emptyFile
            }
            data.append(buffer, count: count)
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

private func currentPOSIXError() -> POSIXError {
    POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
}
