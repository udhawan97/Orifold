import PDFKit
import UniformTypeIdentifiers
import XCTest
@testable import Orifold

/// Regression coverage for the import/permission hardening pass: the classifier that
/// turns a raw error into a user-facing `ImportFailureKind`, the pre-flight checks that
/// must catch permission/missing/iCloud-pending files before ever reaching the parser,
/// and `RecentsStore`'s self-healing behavior when a recent file becomes unavailable.
final class ImportPermissionTests: XCTestCase {
    // MARK: - Classification

    func testClassifyMapsCocoaPermissionErrorToPermissionDenied() {
        let error = NSError(domain: NSCocoaErrorDomain, code: CocoaError.fileReadNoPermission.rawValue)
        XCTAssertEqual(ImportFailureClassifier.classify(error: error, url: nil), .permissionDenied)
    }

    func testClassifyMapsCocoaNoSuchFileErrorToFileMissing() {
        let error = NSError(domain: NSCocoaErrorDomain, code: CocoaError.fileReadNoSuchFile.rawValue)
        XCTAssertEqual(ImportFailureClassifier.classify(error: error, url: nil), .fileMissing)
    }

    func testClassifyMapsCorruptFileErrorToCorruptOrEncrypted() {
        let error = NSError(domain: NSCocoaErrorDomain, code: CocoaError.fileReadCorruptFile.rawValue)
        XCTAssertEqual(ImportFailureClassifier.classify(error: error, url: nil), .corruptOrEncrypted)
    }

    func testClassifyMapsConversionErrorsToMatchingKinds() {
        XCTAssertEqual(ImportFailureClassifier.classify(error: DocumentImportConverter.ConversionError.unsupportedType, url: nil), .unsupportedType)
        XCTAssertEqual(ImportFailureClassifier.classify(error: DocumentImportConverter.ConversionError.passwordProtected, url: nil), .corruptOrEncrypted)
        XCTAssertEqual(ImportFailureClassifier.classify(error: DocumentImportConverter.ConversionError.unreadableDocument, url: nil), .corruptOrEncrypted)
        XCTAssertEqual(ImportFailureClassifier.classify(error: DocumentImportConverter.ConversionError.fileTooLarge(1), url: nil), .tooLarge)
    }

    func testClassifyIsPassthroughForAlreadyClassifiedFailure() {
        // The async import path can throw an `ImportFailureKind` directly (from a
        // pre-flight check inside a `Task.detached`), so `classify` must recognize
        // that case instead of falling through to `.unknown`.
        XCTAssertEqual(ImportFailureClassifier.classify(error: ImportFailureKind.iCloudNotDownloaded, url: nil), .iCloudNotDownloaded)
    }

    func testClassifyFallsBackToFileMissingWhenURLDoesNotExist() {
        let missingURL = FileManager.default.temporaryDirectory.appendingPathComponent("does-not-exist-\(UUID().uuidString).pdf")
        let genericError = NSError(domain: "SomeOtherDomain", code: 1)
        XCTAssertEqual(ImportFailureClassifier.classify(error: genericError, url: missingURL), .fileMissing)
    }

    // MARK: - Pre-flight

    func testPreflightReturnsFileMissingForNonexistentURL() {
        let missingURL = FileManager.default.temporaryDirectory.appendingPathComponent("nope-\(UUID().uuidString).pdf")
        XCTAssertEqual(ImportFailureClassifier.preflight(url: missingURL), .fileMissing)
    }

    func testPreflightReturnsNilForAnOrdinaryReadableFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("preflight-ok-\(UUID().uuidString).txt")
        try Data("hello".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertNil(ImportFailureClassifier.preflight(url: url))
    }

    // MARK: - Recovery action mapping

    func testUnsupportedTypeAndTooLargeOfferNoRecoveryActions() {
        XCTAssertFalse(ImportFailureKind.unsupportedType.showsChooseFileAgain)
        XCTAssertFalse(ImportFailureKind.unsupportedType.showsGrantFolderAccess)
        XCTAssertFalse(ImportFailureKind.tooLarge.showsChooseFileAgain)
        XCTAssertFalse(ImportFailureKind.tooLarge.showsGrantFolderAccess)
    }

    func testPermissionDeniedOffersBothChooseFileAgainAndGrantFolderAccess() {
        XCTAssertTrue(ImportFailureKind.permissionDenied.showsChooseFileAgain)
        XCTAssertTrue(ImportFailureKind.permissionDenied.showsGrantFolderAccess)
    }

    func testFileMissingOffersChooseFileAgainButNotGrantFolderAccess() {
        // Granting folder access can't undo a delete/move — reselecting is the only
        // action that makes sense here.
        XCTAssertTrue(ImportFailureKind.fileMissing.showsChooseFileAgain)
        XCTAssertFalse(ImportFailureKind.fileMissing.showsGrantFolderAccess)
    }

    // MARK: - ImportError defaults (back-compat for existing call sites)

    func testImportErrorDefaultsToUnknownClassification() {
        let error = WorkspaceViewModel.ImportError(fileName: "test.pdf", message: "oops")
        XCTAssertEqual(error.kind, .unknown)
        XCTAssertNil(error.recentEntryID)
        XCTAssertNil(error.sourceURL)
    }

    // MARK: - RecentsStore self-healing

    @MainActor
    func testRecentEntryBecomesUnavailableAfterFileIsDeletedAndIsRemovable() throws {
        let store = RecentsStore.shared
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("recent-selfheal-\(UUID().uuidString).pdf")
        try Data("not a real pdf, just needs to exist".utf8).write(to: url)

        store.recordOpen(url: url)
        guard let entry = store.entries.first(where: { $0.path == url.path }) else {
            XCTFail("recordOpen should have inserted an entry for the new URL")
            return
        }
        defer { store.remove(id: entry.id) }

        XCTAssertTrue(store.isAvailable(entry), "a freshly-written, readable file should be available")

        try FileManager.default.removeItem(at: url)

        XCTAssertFalse(store.isAvailable(entry), "isAvailable must reflect actual readability, not just a stale fileExists check")
        XCTAssertNil(store.resolvedURL(for: entry), "resolving a deleted file (no bookmark) must return nil, not a dangling path URL")
    }

    // MARK: - Whitelist parity

    func testFolderScanWhitelistAgreesWithWorkspaceDocumentWhitelistForRepresentativeExtensions() {
        let extensionsExpectedSupported = ["pdf", "html", "docx", "odt", "rtf", "txt", "md", "csv", "json", "png", "jpg"]
        for ext in extensionsExpectedSupported {
            let url = URL(fileURLWithPath: "/tmp/sample.\(ext)")
            XCTAssertTrue(isSupportedImportURL(url), "\(ext) should be supported by the shared whitelist used for folder scans")
        }

        let extensionsExpectedUnsupported = ["exe", "app", "dmg", "zip"]
        for ext in extensionsExpectedUnsupported {
            let url = URL(fileURLWithPath: "/tmp/sample.\(ext)")
            XCTAssertFalse(isSupportedImportURL(url), "\(ext) should not be treated as importable")
        }
    }
}
