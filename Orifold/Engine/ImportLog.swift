import Foundation
import OSLog

/// Structured, privacy-safe diagnostics for the import/permission pipeline. Never logs
/// full file paths, filenames, or file contents — only the file extension and outcome
/// flags, so these records are safe to include in sysdiagnose/Console without exposing
/// what the user has open.
enum ImportSource: String {
    case openPanel
    case dragDrop
    case recent
    case folder
    case sessionRestore
    case exportReopen
}

enum ParserResult: String {
    case ok
    case repaired
    case failed
}

enum ImportLogEvent: String {
    case bookmarkCreateFailed
    case bookmarkResolveFailed
    case importAttempt
}

enum ImportLog {
    private static let logger = Logger(subsystem: "com.ud.Orifold", category: "import")

    /// One record per import attempt (success or failure). `fileExtension` only —
    /// never the filename stem or directory path.
    static func recordAttempt(
        source: ImportSource,
        fileExtension: String,
        securityScopeGranted: Bool,
        bookmarkStale: Bool? = nil,
        fileExists: Bool,
        isReadable: Bool,
        parserResult: ParserResult,
        errorDomain: String? = nil,
        errorCode: Int? = nil
    ) {
        logger.log(
            """
            import source=\(source.rawValue, privacy: .public) \
            ext=\(fileExtension, privacy: .public) \
            scope=\(securityScopeGranted, privacy: .public) \
            stale=\(bookmarkStale.map(String.init) ?? "n/a", privacy: .public) \
            exists=\(fileExists, privacy: .public) \
            readable=\(isReadable, privacy: .public) \
            parser=\(parserResult.rawValue, privacy: .public) \
            errorDomain=\(errorDomain ?? "none", privacy: .public) \
            errorCode=\(errorCode.map(String.init) ?? "none", privacy: .public)
            """
        )
    }

    static func log(event: ImportLogEvent, error: Error? = nil) {
        let nsError = error as NSError?
        logger.log(
            "\(event.rawValue, privacy: .public) errorDomain=\(nsError?.domain ?? "none", privacy: .public) errorCode=\(nsError?.code ?? 0, privacy: .public)"
        )
    }
}
