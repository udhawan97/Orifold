import PDFKit
import XCTest
@testable import Orifold

/// PHASE 0/LOOP 1 VALIDATION — the real user fixture (trapped state: op present,
/// bake missing) must self-heal at load: visible on page 2 immediately, exported,
/// and visible after a fresh reopen with no interaction.
final class Phase0TrappedFixtureValidationTests: XCTestCase {
    private static let fixtureURL = URL(fileURLWithPath: "/Users/umang/Documents/development/test-files-Orifold/test-text-edit-latest.pdf")

    func testTrappedFixtureSelfHealsOnLoadAndExportsVisibly() throws {
        guard FileManager.default.fileExists(atPath: Self.fixtureURL.path) else {
            throw XCTSkip("test-text-edit-latest.pdf not present (expected outside the repo)")
        }
        let data = try Data(contentsOf: Self.fixtureURL)
        let wrapper = FileWrapper(regularFileWithContents: data)
        wrapper.preferredFilename = "test-text-edit-latest.pdf"
        let document = try WorkspaceDocument(testingFile: wrapper, contentType: .pdf, filename: "test-text-edit-latest.pdf")
        let viewModel = WorkspaceViewModel(document: document, processingEngine: PDFiumProcessingEngine())

        // 1. The committed op must be VISIBLE on page 2 right after load, no clicks.
        let livePage = try XCTUnwrap(viewModel.loadedPDFs.first?.1.page(at: 1))
        let liveText = livePage.attributedString?.string ?? ""
        print("VALIDATE liveText contains yolo=\(liveText.contains("maximus ultricies, yolo"))")
        XCTAssertTrue(liveText.contains("maximus ultricies, yolo"),
                      "load-time reconciliation must bake the trapped op into the visible page")

        // 2. Export → fresh reopen must show it with zero app memory.
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("Orifold-trapped-heal-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: outputURL) }
        XCTAssertTrue(viewModel.saveFlattenedPDF(to: outputURL))
        XCTAssertNil(viewModel.exportError)

        let reopenedData = try Data(contentsOf: outputURL)
        let reopenedPDF = try XCTUnwrap(PDFDocument(data: reopenedData))
        var yoloPages: [Int] = []
        for i in 0..<reopenedPDF.pageCount {
            guard let p = reopenedPDF.page(at: i) else { continue }
            if (p.attributedString?.string ?? "").contains("maximus ultricies, yolo") { yoloPages.append(i) }
        }
        print("VALIDATE reopened yolo pages=\(yoloPages)")
        XCTAssertFalse(yoloPages.isEmpty, "exported PDF must visibly contain the healed edit")

        // 3. Round-trip through the workspace-save path (embeds editable state + pristine
        //    base): reopening THAT file must also show the edit immediately AND keep a
        //    pristine base so future re-edits don't stack bakes.
        let saved = try document.exportedPDFDataThrowing(
            from: document.snapshot(contentType: .pdf),
            options: WorkspaceExportOptions(embedsEditableWorkspaceState: true)
        )
        let savedWrapper = FileWrapper(regularFileWithContents: saved)
        savedWrapper.preferredFilename = "healed.pdf"
        let reopenedDocument = try WorkspaceDocument(testingFile: savedWrapper, contentType: .pdf, filename: "healed.pdf")
        XCTAssertFalse(reopenedDocument.restoredOriginalMemberPDFData.isEmpty,
                       "workspace save must persist pristine bytes for members with committed edits")
        let reopenedViewModel = WorkspaceViewModel(document: reopenedDocument, processingEngine: PDFiumProcessingEngine())
        let reopenedLive = try XCTUnwrap(reopenedViewModel.loadedPDFs.first?.1.page(at: 1))
        XCTAssertTrue((reopenedLive.attributedString?.string ?? "").contains("maximus ultricies, yolo"),
                      "reopened workspace must show the committed edit with no interaction")

        // 4. Pristine base sanity: the restored pristine bytes must NOT contain the edit.
        let pristine = try XCTUnwrap(reopenedDocument.restoredOriginalMemberPDFData.values.first)
        let pristinePage = try XCTUnwrap(PDFDocument(data: pristine)?.page(at: 1))
        XCTAssertFalse((pristinePage.attributedString?.string ?? "").contains("yolo"),
                       "pristine base must remain pre-edit")
    }
}
