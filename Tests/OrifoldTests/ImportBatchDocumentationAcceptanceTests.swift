import PDFKit
import XCTest
@testable import Orifold

final class ImportBatchDocumentationAcceptanceTests: XCTestCase {
    @MainActor
    func testCompletedFiftyFileImportCanAddOneMoreFileToTheSameWorkspaceWithoutChangingExistingMembers() async throws {
        let temporaryRoot = ProcessInfo.processInfo.environment["ORIFOLD_TEST_TEMP_ROOT"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.temporaryDirectory
        let directory = temporaryRoot
            .appendingPathComponent("Orifold-import-batch-acceptance-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let bytes = EditingFixturePDFBuilder.makePDF(runs: [
            .init(string: "Synthetic import acceptance", origin: CGPoint(x: 72, y: 720))
        ])
        XCTAssertEqual(try XCTUnwrap(PDFDocument(data: bytes)).pageCount, 1)
        let urls = try (0...50).map { index in
            let url = directory.appendingPathComponent(String(format: "batch-%03d.pdf", index))
            try bytes.write(to: url)
            return url
        }
        let viewModel = WorkspaceViewModel(
            document: WorkspaceDocument(),
            engine: PDFKitEngine(),
            processingEngine: PDFKitProcessingEngineFallback()
        )

        // This is the Add Files entry point, including its per-selection safety bound.
        importFilesWithBatchLimit(urls: Array(urls.prefix(50)), into: viewModel)
        try await waitForImport(in: viewModel)
        XCTAssertNil(viewModel.importError)
        XCTAssertEqual(viewModel.memberDocuments.count, 50)
        XCTAssertEqual(viewModel.pageCount, 50)
        let existingIDs = viewModel.memberDocuments.map(\.id)
        let existingPageOrder = viewModel.document.workspace.pageOrder.map(\.id)
        let existingBytes = viewModel.document.memberPDFData

        importFilesWithBatchLimit(urls: [try XCTUnwrap(urls.last)], into: viewModel)
        try await waitForImport(in: viewModel)

        XCTAssertNil(viewModel.importError)
        XCTAssertEqual(viewModel.memberDocuments.count, 51)
        XCTAssertEqual(viewModel.pageCount, 51)
        XCTAssertEqual(viewModel.memberDocuments.map(\.displayName), urls.map { $0.deletingPathExtension().lastPathComponent })
        XCTAssertEqual(Array(viewModel.memberDocuments.prefix(50)).map(\.id), existingIDs)
        XCTAssertEqual(Array(viewModel.document.workspace.pageOrder.prefix(50)).map(\.id), existingPageOrder)
        for id in existingIDs {
            XCTAssertEqual(viewModel.document.memberPDFData[id], existingBytes[id])
        }
    }

    @MainActor
    private func waitForImport(in viewModel: WorkspaceViewModel) async throws {
        let deadline = Date().addingTimeInterval(45)
        while viewModel.isImporting {
            guard Date() < deadline else {
                viewModel.cancelActiveOperation()
                throw NSError(domain: "ImportBatchDocumentationAcceptanceTests", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "Synthetic import did not finish within 45 seconds."])
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}
