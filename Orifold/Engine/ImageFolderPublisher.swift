import Darwin
import Foundation

/// Publishes a complete page set in one rename. Existing exports are never removed before
/// fallible writes. A selected-path-only sandbox grant can create a new output directly,
/// but cannot safely replace an existing output without sibling staging access.
enum ImageFolderPublisher {
    struct Page {
        let filename: String
        let data: Data
    }

    enum Step: Equatable {
        case createStaging
        case writePage(Int)
        case publish
    }

    private struct Identity: Equatable {
        let device: dev_t
        let inode: ino_t

        init(_ metadata: stat) {
            device = metadata.st_dev
            inode = metadata.st_ino
        }
    }

    static func publish(
        _ pages: [Page],
        to destination: URL,
        beforeStep: (Step) throws -> Void = { _ in }
    ) throws {
        guard destination.isFileURL, !destination.path.utf8.contains(0),
              validFilename(destination.lastPathComponent), !pages.isEmpty,
              Set(pages.map(\.filename)).count == pages.count,
              pages.allSatisfy({ validFilename($0.filename) }) else { throw POSIXError(.EINVAL) }
        let parent = destination.deletingLastPathComponent()
        let parentDescriptor = Darwin.open(parent.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        if parentDescriptor < 0 {
            guard errno == EACCES || errno == EPERM else { throw posixError() }
            try createNewSelectedFolder(pages, at: destination, beforeStep: beforeStep)
            return
        }
        defer { Darwin.close(parentDescriptor) }
        let parentIdentity = try identity(of: parentDescriptor)
        let existing = try directoryIdentity(at: destination.lastPathComponent, in: parentDescriptor)
        let stagingName = ".Orifold-image-export-\(UUID().uuidString)"
        let staging = parent.appendingPathComponent(stagingName, isDirectory: true)
        do {
            try beforeStep(.createStaging)
            guard Darwin.mkdirat(parentDescriptor, stagingName, 0o700) == 0 else { throw posixError() }
        } catch {
            // Only an access-denied *creation* may use the create-new fallback. Disk-full,
            // write, sync and rename failures never trigger a destructive second attempt.
            guard existing == nil, isAccessDenied(error),
                  matchesDirectoryIdentity(parent, identity: parentIdentity) else { throw error }
            try createNewSelectedFolder(pages, at: destination, beforeStep: beforeStep)
            return
        }
        let stagingDescriptor = Darwin.openat(parentDescriptor, stagingName, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard stagingDescriptor >= 0 else { throw posixError() }
        defer { Darwin.close(stagingDescriptor) }
        let stagingIdentity = try identity(of: stagingDescriptor)
        var cleanupIdentity = stagingIdentity
        defer {
            // Cleanup is best effort and never changes a successful publication into an
            // error. Skip cleanup if the parent or the unique staging entry was replaced.
            removeIfStillOwned(staging, identity: cleanupIdentity, parent: parent, parentIdentity: parentIdentity)
        }
        try write(pages, into: stagingDescriptor, beforeStep: beforeStep)
        try beforeStep(.publish)
        guard matchesDirectoryIdentity(parent, identity: parentIdentity),
              try directoryIdentity(at: stagingName, in: parentDescriptor) == stagingIdentity,
              try directoryIdentity(at: destination.lastPathComponent, in: parentDescriptor) == existing else {
            throw POSIXError(.ESTALE)
        }
        let flags = existing == nil ? UInt32(RENAME_EXCL) : UInt32(RENAME_SWAP)
        guard Darwin.renameatx_np(parentDescriptor, stagingName, parentDescriptor, destination.lastPathComponent, flags) == 0 else {
            throw posixError()
        }
        if let existing { cleanupIdentity = existing }
    }

    private static func createNewSelectedFolder(
        _ pages: [Page], at destination: URL, beforeStep: (Step) throws -> Void
    ) throws {
        // mkdir is exclusive: an existing directory/file/symlink is left untouched.
        guard Darwin.mkdir(destination.path, 0o700) == 0 else { throw posixError() }
        let descriptor = Darwin.open(destination.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw posixError() }
        defer { Darwin.close(descriptor) }
        let ownedIdentity = try identity(of: descriptor)
        var completed = false
        defer {
            if !completed { removeIfStillOwned(destination, identity: ownedIdentity) }
        }
        try write(pages, into: descriptor, beforeStep: beforeStep)
        try beforeStep(.publish)
        var metadata = stat()
        guard Darwin.lstat(destination.path, &metadata) == 0,
              (metadata.st_mode & S_IFMT) == S_IFDIR, Identity(metadata) == ownedIdentity else {
            throw POSIXError(.ESTALE)
        }
        completed = true
    }

    private static func write(_ pages: [Page], into directory: Int32, beforeStep: (Step) throws -> Void) throws {
        for (index, page) in pages.enumerated() {
            try beforeStep(.writePage(index))
            let descriptor = Darwin.openat(directory, page.filename, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
            guard descriptor >= 0 else { throw posixError() }
            defer { Darwin.close(descriptor) }
            try page.data.withUnsafeBytes { bytes in
                var offset = 0
                while offset < bytes.count {
                    let count = Darwin.write(descriptor, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                    if count < 0 && errno == EINTR { continue }
                    guard count > 0 else { throw count < 0 ? posixError() : POSIXError(.EIO) }
                    offset += count
                }
            }
            guard Darwin.fsync(descriptor) == 0 else { throw posixError() }
        }
    }

    private static func directoryIdentity(at name: String, in parent: Int32) throws -> Identity? {
        var metadata = stat()
        if Darwin.fstatat(parent, name, &metadata, AT_SYMLINK_NOFOLLOW) != 0 {
            if errno == ENOENT { return nil }
            throw posixError()
        }
        guard (metadata.st_mode & S_IFMT) == S_IFDIR else { throw POSIXError(.ENOTDIR) }
        return Identity(metadata)
    }

    private static func identity(of descriptor: Int32) throws -> Identity {
        var metadata = stat()
        guard Darwin.fstat(descriptor, &metadata) == 0 else { throw posixError() }
        return Identity(metadata)
    }

    private static func removeIfStillOwned(
        _ url: URL, identity: Identity, parent: URL? = nil, parentIdentity: Identity? = nil
    ) {
        var metadata = stat()
        if let parent, let parentIdentity {
            guard matchesDirectoryIdentity(parent, identity: parentIdentity) else { return }
        }
        guard Darwin.lstat(url.path, &metadata) == 0,
              (metadata.st_mode & S_IFMT) == S_IFDIR, Identity(metadata) == identity else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private static func matchesDirectoryIdentity(_ url: URL, identity: Identity) -> Bool {
        var metadata = stat()
        return Darwin.fstatat(AT_FDCWD, url.path, &metadata, 0) == 0
            && (metadata.st_mode & S_IFMT) == S_IFDIR && Identity(metadata) == identity
    }

    private static func validFilename(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.contains("/") && !name.utf8.contains(0)
    }

    private static func isAccessDenied(_ error: Error) -> Bool {
        let error = error as NSError
        return error.domain == NSPOSIXErrorDomain && (error.code == Int(EACCES) || error.code == Int(EPERM))
    }

    private static func posixError() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}
