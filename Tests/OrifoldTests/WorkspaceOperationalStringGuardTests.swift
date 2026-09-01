import XCTest

final class WorkspaceOperationalStringGuardTests: XCTestCase {
    private static let rawOperationalNeedles = [
        "An import is already in progress.",
        "Importing files",
        "Preparing document",
        "Import canceled after adding",
        "Finish importing before making more changes.",
        "Finish reducing file size before making more changes.",
        "Finish making this document searchable before making more changes.",
        "Reducing file size",
        "Preparing PDF",
        "File-size reduction was cancelled.",
        "Orifold could not render page",
    ]

    private func rawOperationalMatches(in source: String) -> [String] {
        let productLines = source.components(separatedBy: "\n").filter {
            !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//")
        }
        return Self.rawOperationalNeedles.filter { needle in
            productLines.contains { $0.contains("\"\(needle)") }
        }
    }

    func testDetectorRejectsRawViewModelSpecimens() {
        let specimen = #"operationProgress.start(title: "Importing files", detail: "Preparing PDF")"#
        XCTAssertEqual(rawOperationalMatches(in: specimen), ["Importing files", "Preparing PDF"])
    }

    func testBoundedWorkspaceOperationalInventoryUsesCatalogKeys() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let viewModel = try String(
            contentsOf: root.appendingPathComponent("Orifold/ViewModels/WorkspaceViewModel.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(
            rawOperationalMatches(in: viewModel).isEmpty,
            "Raw operational copy found in WorkspaceViewModel: \(rawOperationalMatches(in: viewModel))"
        )
    }
}
