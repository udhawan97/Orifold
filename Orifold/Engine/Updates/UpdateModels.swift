import Foundation

/// A newer release the app discovered, in display-ready form.
struct AvailableUpdate: Equatable {
    var version: String
    var currentVersion: String
    var releaseNotesURL: URL?
    var downloadPageURL: URL?
    var publishedAt: Date?
    var assetSizeBytes: Int?
    /// Direct download URL of the versioned universal DMG asset, used by the in-app
    /// downloader. Its SHA-256 sidecar is the same URL with `.sha256` appended.
    var dmgDownloadURL: URL?
}

/// Why an update attempt could not complete, in a form the UI turns into calm copy plus
/// an expandable technical detail — never a raw error code as the headline.
struct UpdateFailure: Equatable {
    enum Kind: Equatable {
        case network
        case parsing
        case download
        case verification
        case install
    }
    var kind: Kind
    /// Technical detail for the disclosure triangle, not the headline.
    var detail: String
}

/// The user-visible lifecycle of an update. The check-only transport shipping today drives
/// `idle → checking → upToDate | updateAvailable | failed`; `downloading`/`readyToInstall`
/// exist for the Sparkle transport that lands once the Phase-0 spike confirms sandboxed
/// self-update, and `rollbackAvailable` is surfaced independently after a bad install.
enum UpdatePhase: Equatable {
    case idle
    case checking
    case upToDate
    case updateAvailable(AvailableUpdate)
    case downloading(AvailableUpdate, fractionCompleted: Double)
    case readyToInstall(AvailableUpdate)
    /// The verified update is being handed to the updater: the app is about to quit and
    /// relaunch itself as the new version. Terminal window state — no user actions.
    case installing(AvailableUpdate)
    case failed(UpdateFailure)

    var availableUpdate: AvailableUpdate? {
        switch self {
        case let .updateAvailable(update), let .downloading(update, _), let .readyToInstall(update), let .installing(update):
            return update
        case .idle, .checking, .upToDate, .failed:
            return nil
        }
    }

    var isBusy: Bool {
        switch self {
        case .checking, .downloading, .installing: return true
        case .idle, .upToDate, .updateAvailable, .readyToInstall, .failed: return false
        }
    }
}

/// The result of asking a transport "is there something newer than `currentVersion`?".
enum UpdateCheckOutcome: Equatable {
    case upToDate
    case available(AvailableUpdate)
}

/// Abstracts *how* an update is discovered so the controller doesn't depend on Sparkle or
/// GitHub directly. Today's implementation is `GitHubReleaseTransport` (check-only); the
/// Sparkle transport conforms to the same surface later, which is why the controller and
/// its tests never mention either backend.
protocol UpdateTransport {
    func checkForUpdate(currentVersion: UpdateVersion) async throws -> UpdateCheckOutcome
}
