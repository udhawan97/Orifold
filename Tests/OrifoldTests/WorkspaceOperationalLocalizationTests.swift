import XCTest
@testable import Orifold

final class WorkspaceOperationalLocalizationTests: XCTestCase {
    private static let locales: [(identifier: String, relaunchToken: String)] = [
        ("en", "Relaunch"),
        ("es", "reiniciar"),
        ("fr", "relancer"),
        ("hi", "फिर लॉन्च"),
        ("ja", "再起動"),
        ("zh-Hans", "重新启动"),
    ]

    func testImportProgressPreservesCountsAndFilenameInEveryLocale() {
        let fileName = "résumé-例.pdf"

        for item in Self.locales {
            let locale = Locale(identifier: item.identifier)
            let preparingOne = WorkspaceOperationalCopy.importProgressDetail(
                currentIndex: 0,
                totalCount: 1,
                locale: locale
            )
            let namedOne = WorkspaceOperationalCopy.importProgressDetail(
                currentIndex: 1,
                totalCount: 1,
                fileName: fileName,
                locale: locale
            )
            let preparingMany = WorkspaceOperationalCopy.importProgressDetail(
                currentIndex: 0,
                totalCount: 3,
                locale: locale
            )
            let namedMany = WorkspaceOperationalCopy.importProgressDetail(
                currentIndex: 2,
                totalCount: 3,
                fileName: fileName,
                locale: locale
            )

            XCTAssertNotEqual(preparingOne, "progress.import.preparingDocument", item.identifier)
            XCTAssertEqual(namedOne, fileName, item.identifier)
            XCTAssertTrue(preparingMany.contains("3"), item.identifier)
            XCTAssertTrue(namedMany.contains("2"), item.identifier)
            XCTAssertTrue(namedMany.contains("3"), item.identifier)
            XCTAssertTrue(namedMany.contains(fileName), item.identifier)
        }
    }

    func testCancellationOpenFailureCompressionAndImageFailurePreserveValuesInEveryLocale() {
        let fileName = "Q3 “final”-例.pdf"
        let detail = "DETAIL-409"

        for item in Self.locales {
            let locale = Locale(identifier: item.identifier)
            let one = WorkspaceOperationalCopy.importCanceled(afterAdding: 1, locale: locale)
            let many = WorkspaceOperationalCopy.importCanceled(afterAdding: 4, locale: locale)
            let openFailure = WorkspaceOperationalCopy.couldNotOpen(
                fileName: fileName,
                detail: detail,
                locale: locale
            )
            let compression = WorkspaceOperationalCopy.compressionProgress(percent: 37, locale: locale)
            let imageFailure = WorkspaceOperationalCopy.imageExportRenderFailure(pageNumber: 7, locale: locale)

            XCTAssertTrue(one.contains("1"), item.identifier)
            XCTAssertTrue(many.contains("4"), item.identifier)
            XCTAssertNotEqual(one, many, item.identifier)
            XCTAssertTrue(openFailure.contains(fileName), item.identifier)
            XCTAssertTrue(openFailure.contains(detail), item.identifier)
            XCTAssertTrue(compression.contains("37"), item.identifier)
            XCTAssertTrue(imageFailure.contains("7"), item.identifier)
        }
    }

    func testBusyRecoveryScanConflictAndInstallActionResolveInEveryLocale() {
        let staticKeys = [
            "status.import.alreadyInProgress",
            "status.import.finishBeforeMoreChanges",
            "status.compression.finishBeforeMoreChanges",
            "status.ocr.finishBeforeMoreChanges",
            "progress.import.title",
            "progress.compression.title",
            "progress.compression.preparing",
        ]

        for item in Self.locales {
            let locale = Locale(identifier: item.identifier)
            for key in staticKeys {
                XCTAssertNotEqual(L10n.string(forKey: key, locale: locale), key, "\(item.identifier): \(key)")
            }

            let conflict = L10n.format("status.scanCleanup.semanticConflict", 6, locale: locale)
            XCTAssertTrue(conflict.contains("6"), item.identifier)
            XCTAssertFalse(conflict.contains("status.scanCleanup.semanticConflict"), item.identifier)

            let install = L10n.string("settings.updates.action.install", locale: locale)
            XCTAssertTrue(install.contains(item.relaunchToken), "\(item.identifier): \(install)")
        }
    }
}
