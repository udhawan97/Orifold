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
        directoryName: String,
        beforeBindingVerification: (() throws -> Void)? = nil
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
        var ownsOpenedParent = true
        defer {
            if ownsOpenedParent { Darwin.close(openedParent) }
        }

        let createResult = directoryName.withCString {
            Darwin.mkdirat(openedParent, $0, mode_t(0o755))
        }
        if createResult != 0, errno != EEXIST {
            throw currentPOSIXError()
        }

        let openedDirectory = directoryName.withCString {
            Darwin.openat(
                openedParent,
                $0,
                O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
            )
        }
        guard openedDirectory >= 0 else {
            throw currentPOSIXError()
        }
        var ownsOpenedDirectory = true
        defer {
            if ownsOpenedDirectory { Darwin.close(openedDirectory) }
        }

        try beforeBindingVerification?()
        try Self.verifyBinding(
            descriptor: openedDirectory,
            parentDescriptor: openedParent,
            directoryName: directoryName
        )
        parentDescriptor = openedParent
        descriptor = openedDirectory
        self.directoryName = directoryName
        url = parentURL.appendingPathComponent(directoryName, isDirectory: true)
        ownsOpenedDirectory = false
        ownsOpenedParent = false
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
        try Self.verifyBinding(
            descriptor: descriptor,
            parentDescriptor: parentDescriptor,
            directoryName: directoryName
        )
    }

    private static func verifyBinding(
        descriptor: Int32,
        parentDescriptor: Int32,
        directoryName: String
    ) throws {
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
    /// file at the user's real destination. If creating a sibling is denied,
    /// exact NSSavePanel-chosen path grants can still create a new output with
    /// an exclusive open. An existing output is never directly overwritten.
    /// `validate` runs against the written bytes before they're committed to
    /// `targetURL`, so a validation failure never lands at the real destination.
    static func write(_ data: Data, to targetURL: URL, validate: ((Data) throws -> Void)? = nil) throws {
        try write(data, to: targetURL, writeForTesting: nil, validate: validate)
    }

    static func write(
        _ data: Data,
        to targetURL: URL,
        writeForTesting: ((Data, Int32) throws -> Void)?,
        validate: ((Data) throws -> Void)? = nil
    ) throws {
        guard targetURL.isFileURL, targetURL.path.hasPrefix("/"),
              !targetURL.path.utf8.contains(0) else { throw ExportWriteError.fileNotFound }
        let fileManager = FileManager.default
        let directory = targetURL.deletingLastPathComponent()
        let tempURL = directory.appendingPathComponent(".Orifold-export-\(UUID().uuidString)")
        let descriptor = Darwin.open(tempURL.path, O_RDWR | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, mode_t(0o644))
        guard descriptor >= 0 else {
            let stagingError = currentPOSIXError()
            guard stagingError.code == .EACCES || stagingError.code == .EPERM else { throw stagingError }
            // Validate before exposing any bytes at a path with a file-only grant.
            try validate?(data)
            let selectedDescriptor = Darwin.open(targetURL.path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, mode_t(0o644))
            guard selectedDescriptor >= 0 else {
                if errno == EEXIST { throw stagingError }
                throw currentPOSIXError()
            }
            var completed = false
            defer {
                if !completed { removeOwnedFile(at: targetURL, descriptor: selectedDescriptor) }
                Darwin.close(selectedDescriptor)
            }
            try writeAll(data, to: selectedDescriptor)
            guard Darwin.fsync(selectedDescriptor) == 0 else { throw currentPOSIXError() }
            completed = true
            return
        }
        defer {
            removeOwnedFile(at: tempURL, descriptor: descriptor)
            Darwin.close(descriptor)
        }
        if let writeForTesting {
            try writeForTesting(data, descriptor)
        } else {
            try writeAll(data, to: descriptor)
        }
        guard Darwin.fsync(descriptor) == 0 else { throw currentPOSIXError() }
        if let validate {
            guard Darwin.lseek(descriptor, 0, SEEK_SET) == 0 else { throw currentPOSIXError() }
            let stagedData = try readAll(from: descriptor, expectedSize: data.count)
            guard stagedData.count == data.count else { throw ExportWriteError.emptyFile }
            try validate(stagedData)
        }
        guard ownsFile(at: tempURL, descriptor: descriptor) else { throw ExportWriteError.fileNotFound }
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
    }

    private static func ownsFile(at url: URL, descriptor: Int32) -> Bool {
        var opened = stat()
        var named = stat()
        return Darwin.fstat(descriptor, &opened) == 0 && Darwin.lstat(url.path, &named) == 0
            && opened.st_dev == named.st_dev && opened.st_ino == named.st_ino
    }

    private static func removeOwnedFile(at url: URL, descriptor: Int32) {
        guard ownsFile(at: url, descriptor: descriptor) else { return }
        _ = Darwin.unlink(url.path)
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
