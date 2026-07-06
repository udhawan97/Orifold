import Foundation
import UniformTypeIdentifiers

/// Classification of why an import/reopen attempt failed, computed once centrally so
/// every import entry point (Open File, drag/drop, Open Recent, folder import,
/// export-then-reopen) shows the same message and the same recovery actions instead of
/// each surfacing a raw, unclassified `error.localizedDescription`.
///
/// This is what actually distinguishes "you don't have permission" (recoverable by
/// reselecting the file) from "the file is gone" (recoverable only by removing the
/// recent) from "unsupported type" (not recoverable at all) — three cases a bare
/// Cocoa error message collapses into the same unhelpful sentence.
enum ImportFailureKind: Equatable, Error {
    case permissionDenied
    case staleBookmark
    case fileMissing
    case unsupportedType
    case corruptOrEncrypted
    case iCloudNotDownloaded
    case exportTempMissing
    case tooLarge
    case unknown

    /// Reselecting the exact file both re-grants access and re-locates it, so this
    /// covers every recoverable kind except a folder-wide permission problem (where
    /// granting the containing folder is the more useful action).
    var showsChooseFileAgain: Bool {
        switch self {
        case .permissionDenied, .staleBookmark, .fileMissing, .exportTempMissing, .corruptOrEncrypted:
            return true
        case .unsupportedType, .tooLarge, .unknown, .iCloudNotDownloaded:
            return false
        }
    }

    /// Only meaningful when the file itself still exists but the sandbox can't reach
    /// it — granting the parent folder resolves that without the user needing to
    /// pick the exact file again.
    var showsGrantFolderAccess: Bool {
        self == .permissionDenied || self == .staleBookmark
    }
}

enum ImportFailureClassifier {
    /// Maps a thrown error (Cocoa I/O error, `DocumentImportConverter.ConversionError`,
    /// or an unrecognized error) plus the URL it was attempting to reach into a single
    /// `ImportFailureKind`. `fileExistsOverride` lets a caller that already checked
    /// existence (e.g. via a held security scope) skip a redundant disk hit.
    static func classify(error: Error, url: URL?, fileExistsOverride: Bool? = nil) -> ImportFailureKind {
        if let alreadyClassified = error as? ImportFailureKind {
            return alreadyClassified
        }
        if let conversionError = error as? DocumentImportConverter.ConversionError {
            switch conversionError {
            case .unsupportedType:
                return .unsupportedType
            case .passwordProtected, .unreadableDocument, .emptyDocument, .binaryDataMislabelledAsText:
                return .corruptOrEncrypted
            case .renderingFailed, .renderTimedOut:
                return .corruptOrEncrypted
            case .fileTooLarge, .fileTypeTooLarge, .htmlRenderedTooLarge, .documentRenderedTooLarge:
                return .tooLarge
            }
        }

        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain {
            switch nsError.code {
            case CocoaError.fileReadNoPermission.rawValue, CocoaError.fileWriteNoPermission.rawValue:
                return .permissionDenied
            case CocoaError.fileNoSuchFile.rawValue, CocoaError.fileReadNoSuchFile.rawValue:
                return .fileMissing
            case CocoaError.fileReadCorruptFile.rawValue:
                return .corruptOrEncrypted
            default:
                break
            }
        }

        if let url {
            let exists = fileExistsOverride ?? FileManager.default.fileExists(atPath: url.path)
            if !exists { return .fileMissing }
        }
        if let url, isPendingiCloudDownload(url) {
            return .iCloudNotDownloaded
        }
        return .unknown
    }

    /// Pre-flight classification performed BEFORE attempting to read/parse — catches
    /// permission, existence, and iCloud-download-pending cases without ever handing an
    /// unreadable file to the PDF/document parser.
    static func preflight(url: URL) -> ImportFailureKind? {
        if isPendingiCloudDownload(url) {
            return .iCloudNotDownloaded
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .fileMissing
        }
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            return .permissionDenied
        }
        return nil
    }

    private static func isPendingiCloudDownload(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]),
              let status = values.ubiquitousItemDownloadingStatus else {
            return false
        }
        return status != .current
    }
}
