import Foundation

/// Abstracts the download+verify step so the controller can be driven by a mock in tests
/// without touching the network.
protocol UpdateDownloading {
    func download(_ update: AvailableUpdate, progress: @escaping @Sendable (Double) -> Void) async throws -> URL
}

/// Downloads a release's signed DMG into the updater cache and verifies it before it is
/// ever handed to the installer.
///
/// The verification is the point: the DMG is checked against the release's published
/// `.sha256` sidecar, so a truncated or tampered download is rejected and deleted rather
/// than installed. Nothing here replaces the app bundle — a sandboxed app can't — it only
/// produces a verified local artifact for the install hand-off (opening the DMG).
struct UpdateDownloader: UpdateDownloading {
    enum DownloadError: Error, Equatable {
        case noDownloadURL
        case http(Int)
        case checksumUnavailable
        case checksumMismatch(expected: String, actual: String)
    }

    private let session: URLSession
    private let cacheDirectory: URL

    init(session: URLSession = .shared, cacheDirectory: URL = UpdateStorePaths.updaterCacheDirectory()) {
        self.session = session
        self.cacheDirectory = cacheDirectory
    }

    /// Fetches and verifies the DMG, returning the verified local file URL. `progress` is
    /// called with a fraction in `0...1` as bytes arrive. Throws (and leaves no partial
    /// file) on network failure or checksum mismatch.
    func download(_ update: AvailableUpdate, progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> URL {
        guard let dmgURL = update.dmgDownloadURL else { throw DownloadError.noDownloadURL }

        // Fail fast if integrity can't be established: fetch the tiny checksum sidecar first.
        let expected = try await fetchExpectedChecksum(for: dmgURL)

        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        let downloaded = try await streamToFile(dmgURL, progress: progress)

        // Verify before the file is ever eligible for install; a mismatch is deleted.
        let actual = try RollbackArchiver.sha256(of: downloaded)
        guard actual.caseInsensitiveCompare(expected) == .orderedSame else {
            try? FileManager.default.removeItem(at: downloaded)
            throw DownloadError.checksumMismatch(expected: expected, actual: actual)
        }

        let destination = cacheDirectory.appendingPathComponent("Orifold-\(update.version).dmg")
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: downloaded, to: destination)
        return destination
    }

    // MARK: - Checksum sidecar

    /// The published `<dmg>.sha256` sidecar is `"<hex>  <filename>"`; we take the hex token.
    private func fetchExpectedChecksum(for dmgURL: URL) async throws -> String {
        let sidecarURL = dmgURL.appendingPathExtension("sha256")
        var request = URLRequest(url: sidecarURL)
        request.setValue("Orifold", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw DownloadError.checksumUnavailable
        }
        guard let text = String(data: data, encoding: .utf8),
              let token = text.split(whereSeparator: { $0.isWhitespace }).first,
              token.count == 64,
              token.allSatisfy(\.isHexDigit) else {
            throw DownloadError.checksumUnavailable
        }
        return String(token)
    }

    // MARK: - Download with progress

    private func streamToFile(_ url: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let delegate = DownloadDelegate(progress: progress)
        // A dedicated session carrying the injected configuration (so test URLProtocol stubs
        // still intercept), invalidated as soon as the download finishes.
        let downloadSession = URLSession(configuration: session.configuration, delegate: delegate, delegateQueue: nil)
        defer { downloadSession.finishTasksAndInvalidate() }

        var request = URLRequest(url: url)
        request.setValue("Orifold", forHTTPHeaderField: "User-Agent")
        let task = downloadSession.downloadTask(with: request)
        // Cancelling the enclosing Swift Task (the user hitting Cancel) cancels the transfer;
        // the delegate then resumes the continuation with a URLError.cancelled, which the
        // controller maps back to `.updateAvailable` rather than a failure.
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                delegate.continuation = continuation
                task.resume()
            }
        } onCancel: {
            task.cancel()
        }
    }

    /// Bridges `URLSessionDownloadTask`'s delegate callbacks to async/await and reports
    /// progress. Callbacks are serialized on the session's delegate queue, so the
    /// continuation is resumed exactly once.
    private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
        private let progress: @Sendable (Double) -> Void
        var continuation: CheckedContinuation<URL, Error>?

        init(progress: @escaping @Sendable (Double) -> Void) { self.progress = progress }

        func urlSession(
            _ session: URLSession,
            downloadTask: URLSessionDownloadTask,
            didWriteData bytesWritten: Int64,
            totalBytesWritten: Int64,
            totalBytesExpectedToWrite: Int64
        ) {
            guard totalBytesExpectedToWrite > 0 else { return }
            progress(min(1, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)))
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
            guard let continuation else { return }
            self.continuation = nil
            if let http = downloadTask.response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                continuation.resume(throwing: DownloadError.http(http.statusCode))
                return
            }
            // `location` is deleted once this method returns, so move it out synchronously.
            let staged = FileManager.default.temporaryDirectory
                .appendingPathComponent("orifold-dl-\(UUID().uuidString).dmg")
            do {
                try FileManager.default.moveItem(at: location, to: staged)
                progress(1)
                continuation.resume(returning: staged)
            } catch {
                continuation.resume(throwing: error)
            }
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            // On the happy path `didFinishDownloadingTo` already resumed and nil'd the
            // continuation, so this returns. If the task instead completed WITHOUT ever
            // delivering a file (an error, or the rare "completed with nil error but no
            // finish" case), resume here so `download()` can never hang.
            guard let continuation else { return }
            self.continuation = nil
            continuation.resume(throwing: error ?? URLError(.badServerResponse))
        }
    }
}
