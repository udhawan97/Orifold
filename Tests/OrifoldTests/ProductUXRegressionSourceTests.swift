import XCTest
@testable import Orifold

/// Focused integration guards for SwiftUI behavior whose wiring cannot be exercised through
/// the view model alone. The assertions intentionally name the production dependency/action
/// anchors so a future refactor must preserve thumbnail refresh, keyboard selection, and
/// VoiceOver reordering for both document and page rows.
final class ProductUXRegressionSourceTests: XCTestCase {
    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func source(_ path: String) throws -> String {
        try String(contentsOf: repositoryRoot.appendingPathComponent(path), encoding: .utf8)
    }

    func testSidebarThumbnailTasksObserveContentRevision() throws {
        let sidebar = try source("Orifold/Views/SidebarView.swift")

        XCTAssertEqual(sidebar.components(separatedBy: "viewModel.structureRevision").count - 1, 2)
        XCTAssertEqual(sidebar.components(separatedBy: "SidebarThumbnailCacheKey(").count - 1, 2)
        XCTAssertFalse(sidebar.contains(".task(id: member.id)"))
        XCTAssertFalse(sidebar.contains(".task(id: pageNumber)"))
    }

    func testSidebarRowsExposeKeyboardAndVoiceOverSelectionAndReordering() throws {
        let sidebar = try source("Orifold/Views/SidebarView.swift")

        XCTAssertGreaterThanOrEqual(sidebar.components(separatedBy: ".accessibilityAction {").count - 1, 2)
        XCTAssertGreaterThanOrEqual(sidebar.components(separatedBy: ".onKeyPress(.return)").count - 1, 2)
        XCTAssertGreaterThanOrEqual(sidebar.components(separatedBy: "L10n.string(\"toc.moveUp\"").count - 1, 2)
        XCTAssertGreaterThanOrEqual(sidebar.components(separatedBy: "L10n.string(\"toc.moveDown\"").count - 1, 2)
    }

    func testThumbnailCacheKeyChangesWithContentRevision() {
        let id = UUID()

        XCTAssertNotEqual(
            SidebarThumbnailCacheKey(id: id, contentRevision: 3),
            SidebarThumbnailCacheKey(id: id, contentRevision: 4)
        )
    }
}
