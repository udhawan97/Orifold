import XCTest
@testable import Orifold

final class RecentFilesFlowTests: XCTestCase {
    func testMissingRecentStillDispatchesOpenForRecovery() {
        let entry = makeEntry()
        var openedEntry: RecentFileEntry?

        let isAvailable = activateRecentFileCard(
            entry: entry,
            resolveURL: { _ in nil },
            onOpen: { openedEntry = $0 }
        )

        XCTAssertFalse(isAvailable)
        XCTAssertEqual(
            openedEntry,
            entry,
            "an unavailable card must reach the recovery flow instead of failing silently"
        )
    }

    func testAvailableRecentDispatchesOpenAndStaysAvailable() {
        let entry = makeEntry()
        var openedEntry: RecentFileEntry?

        let isAvailable = activateRecentFileCard(
            entry: entry,
            resolveURL: { _ in URL(fileURLWithPath: "/tmp/available.orifold") },
            onOpen: { openedEntry = $0 }
        )

        XCTAssertTrue(isAvailable)
        XCTAssertEqual(openedEntry, entry)
    }

    func testClearHistoryRequiresConfirmationBeforeCallingStoreClear() throws {
        let source = try recentFilesSectionSource()
        let headerStart = try XCTUnwrap(source.range(of: "private var header: some View"))
        let cardsStart = try XCTUnwrap(
            source.range(
                of: "@ViewBuilder\n    private var cards",
                range: headerStart.upperBound..<source.endIndex
            )
        )
        let header = String(source[headerStart.lowerBound..<cardsStart.lowerBound])

        XCTAssertTrue(header.contains("isConfirmingClear = true"))
        XCTAssertFalse(
            header.contains("store.clear()"),
            "the header action must request confirmation, not erase history directly"
        )
        XCTAssertTrue(source.contains(".confirmationDialog("))
        XCTAssertTrue(source.contains("recentFiles.clearConfirmation.title"))
        XCTAssertTrue(source.contains("recentFiles.clearConfirmation.message"))
        XCTAssertTrue(source.contains("recentFiles.clearConfirmation.confirm"))
        XCTAssertTrue(
            source.contains("store.clear()"),
            "the destructive confirmation must remain wired to the store operation"
        )
    }

    private func makeEntry() -> RecentFileEntry {
        RecentFileEntry(
            id: UUID(),
            bookmarkData: nil,
            path: "/tmp/missing.orifold",
            displayName: "Missing",
            lastOpened: Date(),
            pageCount: 4,
            lastPageOpened: 1,
            thumbnailCacheKey: nil
        )
    }

    private func recentFilesSectionSource() throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Tests/OrifoldTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // repository root
        let sourceURL = repositoryRoot.appendingPathComponent("Orifold/Views/RecentFilesSection.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
