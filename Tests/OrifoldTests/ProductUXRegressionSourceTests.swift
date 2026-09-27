import XCTest

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
}
