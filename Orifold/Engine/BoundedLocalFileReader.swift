import Darwin
import Foundation
import UniformTypeIdentifiers

struct BoundedLocalFileAsset {
    let data: Data
    let mimeType: String?
}

struct BoundedLocalFileSource {
    let data: Data
    let directory: BoundedLocalFileDirectory
}

/// Reads one regular local file through a descriptor anchored to its canonical parent.
///
/// The size check and read operate on the same descriptor, and the streaming loop enforces
/// `maxBytes` again. Callers therefore cannot race a pathname metadata check with a later,
/// unbounded `Data(contentsOf:)` allocation.
enum BoundedLocalFileReader {
    static func readFile(at fileURL: URL, maxBytes: Int) -> Data? {
        bindFile(at: fileURL, maxBytes: maxBytes)?.data
    }

    static func bindFile(at fileURL: URL, maxBytes: Int) -> BoundedLocalFileSource? {
        guard fileURL.isFileURL, fileURL.path.hasPrefix("/"), maxBytes >= 0 else { return nil }
        var canonicalBuffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        guard fileURL.path.withCString({ Darwin.realpath($0, &canonicalBuffer) }) != nil else {
            return nil
        }
        let canonicalPath = String(cString: canonicalBuffer)
        let path = canonicalPath as NSString
        let filename = path.lastPathComponent
        let parentPath = path.deletingLastPathComponent
        guard !filename.isEmpty,
              filename != ".",
              filename != "..",
              !filename.utf8.contains(0),
              let directory = BoundedLocalFileDirectory(canonicalRootPath: parentPath),
              let source = directory.readAsset(pathComponents: [filename], maxBytes: maxBytes) else {
            return nil
        }
        return BoundedLocalFileSource(data: source.data, directory: directory)
    }
}

/// Anchors all traversal to one retained directory descriptor. Root acquisition starts from
/// `/` and opens every canonical path component with `openat` + `O_NOFOLLOW`; child traversal
/// repeats the same discipline. `fstat` and read then operate on the exact same final descriptor.
final class BoundedLocalFileDirectory {
    private let rootDescriptor: Int32

    convenience init?(sourceRoot: URL) {
        guard sourceRoot.isFileURL, sourceRoot.path.hasPrefix("/") else { return nil }
        var canonicalBuffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        guard sourceRoot.path.withCString({ Darwin.realpath($0, &canonicalBuffer) }) != nil else {
            return nil
        }
        self.init(canonicalRootPath: String(cString: canonicalBuffer))
    }

    init?(canonicalRootPath: String) {
        guard canonicalRootPath.hasPrefix("/") else { return nil }
        var currentDescriptor = Darwin.open(
            "/",
            O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
        )
        guard currentDescriptor >= 0 else { return nil }

        // `standardizedFileURL` rewrites the already-canonical `/private/var/...` back to the
        // `/var` compatibility symlink. Split the realpath result directly so descriptor
        // traversal never reintroduces a symlink.
        let components = canonicalRootPath.split(separator: "/", omittingEmptySubsequences: true)
        for component in components {
            guard !component.isEmpty, component != ".", component != ".." else {
                Darwin.close(currentDescriptor)
                return nil
            }
            let nextDescriptor = component.withCString {
                Darwin.openat(
                    currentDescriptor,
                    $0,
                    O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
                )
            }
            guard nextDescriptor >= 0 else {
                Darwin.close(currentDescriptor)
                return nil
            }
            Darwin.close(currentDescriptor)
            currentDescriptor = nextDescriptor
        }
        rootDescriptor = currentDescriptor
    }

    deinit {
        Darwin.close(rootDescriptor)
    }

    func readAsset(pathComponents: [String], maxBytes: Int) -> BoundedLocalFileAsset? {
        guard !pathComponents.isEmpty, maxBytes >= 0 else { return nil }
        var currentDescriptor = Darwin.dup(rootDescriptor)
        guard currentDescriptor >= 0 else { return nil }
        _ = Darwin.fcntl(currentDescriptor, F_SETFD, FD_CLOEXEC)
        defer { Darwin.close(currentDescriptor) }

        for (index, component) in pathComponents.enumerated() {
            guard !component.isEmpty,
                  component != ".",
                  component != "..",
                  !component.utf8.contains(0) else { return nil }
            let isFinal = index == pathComponents.count - 1
            // Opening the final component nonblocking prevents a hostile FIFO from blocking
            // before the same-descriptor regular-file check gets a chance to reject it.
            let flags = O_RDONLY | O_CLOEXEC | O_NOFOLLOW | (isFinal ? O_NONBLOCK : O_DIRECTORY)
            let nextDescriptor = component.withCString {
                Darwin.openat(currentDescriptor, $0, flags)
            }
            guard nextDescriptor >= 0 else { return nil }
            Darwin.close(currentDescriptor)
            currentDescriptor = nextDescriptor
        }

        var metadata = stat()
        guard Darwin.fstat(currentDescriptor, &metadata) == 0,
              (metadata.st_mode & S_IFMT) == S_IFREG,
              metadata.st_size >= 0,
              metadata.st_size <= maxBytes,
              let data = readAll(
                  from: currentDescriptor,
                  expectedSize: Int(metadata.st_size),
                  maxBytes: maxBytes
              ) else {
            return nil
        }
        let pathExtension = URL(fileURLWithPath: pathComponents.last!).pathExtension
        return BoundedLocalFileAsset(
            data: data,
            mimeType: UTType(filenameExtension: pathExtension)?.preferredMIMEType
        )
    }

    private func readAll(from descriptor: Int32, expectedSize: Int, maxBytes: Int) -> Data? {
        var data = Data()
        data.reserveCapacity(expectedSize)
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let bytesRead = buffer.withUnsafeMutableBytes { bytes in
                Darwin.read(descriptor, bytes.baseAddress, bytes.count)
            }
            if bytesRead == 0 { return data }
            if bytesRead < 0 {
                if errno == EINTR { continue }
                return nil
            }
            guard bytesRead <= maxBytes - data.count else { return nil }
            data.append(buffer, count: bytesRead)
        }
    }
}
