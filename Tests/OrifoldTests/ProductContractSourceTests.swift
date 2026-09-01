import XCTest

final class ProductContractSourceTests: XCTestCase {
    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func source(_ path: String) throws -> String {
        try String(
            contentsOf: repositoryRoot.appendingPathComponent(path),
            encoding: .utf8
        )
    }

    func testPublicTextEditCopyDescribesVisualReplacementAndDiscoveryRisk() throws {
        let readme = try source("README.md")
        let guide = try source("docs-site/src/content/docs/edit/edit-text.mdx")
        let combined = (readme + "\n" + guide).lowercased()

        XCTAssertFalse(readme.contains("edit real PDF text in place"))
        XCTAssertFalse(guide.contains("rather than on top of an invisible copy"))
        XCTAssertTrue(combined.contains("visual replacement") || combined.contains("visually replace"))
        for disclosure in ["search", "copy/paste", "extraction", "assistive technology"] {
            XCTAssertTrue(combined.contains(disclosure), "Missing text-edit disclosure: \(disclosure)")
        }
    }

    func testUpdateGuideDoesNotPromiseUndistributedRollbackHelper() throws {
        let guide = try source("docs-site/src/content/docs/get-started/update-uninstall.mdx")

        XCTAssertFalse(guide.contains("scripts/install-mac.sh --restore"))
        XCTAssertFalse(guide.contains("~/Library/Application Support/Orifold/Rollback/"))
        XCTAssertTrue(guide.contains("no installed Terminal helper"))
        XCTAssertTrue(guide.contains("Orifold's GitHub Releases"))
        XCTAssertTrue(guide.contains("reinstall it manually"))
        XCTAssertTrue(guide.contains("installs the verified app, relaunches"))
    }

    func testCombineGuidesKeepPageReorderingWithinOneMember() throws {
        let combine = try source("docs-site/src/content/docs/import/combine.mdx")
        let firstWorkspace = try source("docs-site/src/content/docs/get-started/first-workspace.mdx")

        XCTAssertFalse(combine.contains("reorder across documents"))
        XCTAssertFalse(combine.contains("drag any thumbnail into another document"))
        XCTAssertFalse(firstWorkspace.contains("drag pages into the order you want across all the files"))
        XCTAssertTrue(combine.contains("within that same document"))
        XCTAssertTrue(firstWorkspace.contains("inside that document"))
        XCTAssertTrue(combine.contains("drag whole documents up or down"))
    }

    func testReadyInstallButtonUsesTheRelaunchDisclosureKey() throws {
        let view = try source("Orifold/Views/UpdateStatusView.swift")
        XCTAssertTrue(
            view.contains("Button(L10n.string(\"settings.updates.action.install\", locale: locale))")
        )
    }
}
