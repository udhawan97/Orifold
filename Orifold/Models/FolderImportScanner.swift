import Foundation

/// Result of recursively scanning one or more folders for documents Orifold can import.
struct FolderScanResult {
    var supportedURLs: [URL]
    var unsupportedCount: Int
    var wasTruncated: Bool

    var isEmpty: Bool { supportedURLs.isEmpty && unsupportedCount == 0 }
}

/// Recursively finds importable documents under one or more folder roots, off the main actor.
enum FolderImportScanner {
    /// Backstop against pathological trees (e.g. symlink cycles into huge directories) — not a
    /// product-facing limit, just a guarantee the scan itself terminates promptly.
    static let maxScannedEntries = 10_000

    static func scan(folders: [URL]) async -> FolderScanResult {
        await Task.detached(priority: .userInitiated) {
            scanSynchronously(folders: folders)
        }.value
    }

    private static func scanSynchronously(folders: [URL]) -> FolderScanResult {
        let fileManager = FileManager.default
        let resourceKeys: [URLResourceKey] = [.isRegularFileKey, .contentTypeKey]
        let resourceKeySet = Set(resourceKeys)

        var supported: [URL] = []
        var seenPaths: Set<String> = []
        var unsupportedCount = 0
        var scannedCount = 0
        var wasTruncated = false

        rootLoop: for root in folders {
            let isSecurityScoped = root.startAccessingSecurityScopedResource()
            defer { if isSecurityScoped { root.stopAccessingSecurityScopedResource() } }

            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: resourceKeys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            for case let url as URL in enumerator {
                scannedCount += 1
                if scannedCount > maxScannedEntries {
                    wasTruncated = true
                    break rootLoop
                }

                let values = try? url.resourceValues(forKeys: resourceKeySet)
                guard values?.isRegularFile == true else { continue }

                if isSupportedImportURL(url) {
                    let key = url.standardizedFileURL.path
                    if seenPaths.insert(key).inserted {
                        supported.append(url)
                    }
                } else {
                    unsupportedCount += 1
                }
            }
        }

        supported.sort { $0.path.localizedStandardCompare($1.path) == .orderedAscending }

        return FolderScanResult(
            supportedURLs: supported,
            unsupportedCount: unsupportedCount,
            wasTruncated: wasTruncated
        )
    }
}
