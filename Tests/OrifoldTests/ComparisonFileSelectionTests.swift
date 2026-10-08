import AppKit
import Darwin
import PDFKit
import XCTest
@testable import Orifold

@MainActor
final class ComparisonFileSelectionTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        let temporary = ProcessInfo.processInfo.environment["ORIFOLD_TEST_TEMP_ROOT"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) } ?? FileManager.default.temporaryDirectory
        root = temporary.appendingPathComponent("orifold-compare-selection-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testSparseOversizedPDFRejectsBeforeCreatingComparisonRequest() throws {
        let url = root.appendingPathComponent("oversized.pdf")
        XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: Data()))
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(DocumentImportConverter.maxImportBytes + 1))
        try handle.close()
        let viewModel = WorkspaceViewModel(document: WorkspaceDocument())
        viewModel.prepareCompare(withOtherFileAt: url)
        XCTAssertNil(viewModel.compareRequest)
        XCTAssertEqual(viewModel.exportError?.message, DocumentImportConverter.userMessage(
            for: DocumentImportConverter.ConversionError.fileTooLarge(DocumentImportConverter.maxImportBytes + 1)
        ))
    }

    func testSelectedFileReportingReaderDoesNotRequireReadableParent() throws {
        let selected = root.appendingPathComponent("file-only.pdf")
        let expected = Data("selected bytes".utf8)
        try expected.write(to: selected)
        XCTAssertEqual(Darwin.chmod(root.path, 0o100), 0)
        defer { _ = Darwin.chmod(root.path, 0o700) }
        XCTAssertEqual(try BoundedLocalFileReader.readSelectedFileReportingFailure(at: selected, maxBytes: expected.count), expected)
    }

    func testSpecialSymlinkCorruptAndMissingFilesRetainUnreadableError() throws {
        let fifo = root.appendingPathComponent("special.pdf")
        XCTAssertEqual(Darwin.mkfifo(fifo.path, 0o600), 0)
        let corrupt = root.appendingPathComponent("corrupt.pdf")
        try Data("not a PDF".utf8).write(to: corrupt)
        let symlink = root.appendingPathComponent("link.pdf")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: corrupt)
        for file in [fifo, corrupt, symlink, root.appendingPathComponent("missing.pdf")] {
            let viewModel = WorkspaceViewModel(document: WorkspaceDocument())
            viewModel.prepareCompare(withOtherFileAt: file)
            XCTAssertNil(viewModel.compareRequest)
            XCTAssertEqual(viewModel.exportError?.message, L10n.string("compare.error.unreadable"))
        }
    }

    func testRegularComparisonUsesExactSelectedBytesAndLockedPDFKeepsItsError() throws {
        let pdf = PDFDocument()
        let image = NSImage(size: NSSize(width: 72, height: 72))
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 72, height: 72).fill()
        image.unlockFocus()
        pdf.insert(try XCTUnwrap(PDFPage(image: image)), at: 0)
        let bytes = try XCTUnwrap(PDFSerializer.data(from: pdf))
        let selected = root.appendingPathComponent("selected.pdf")
        try bytes.write(to: selected)
        let member = MemberDocument(displayName: "Synthetic left", sourcePDFRef: "synthetic.pdf")
        let ref = PageRef(memberDocId: member.id, sourcePageIndex: 0)
        let document = WorkspaceDocument()
        var storedMember = member
        storedMember.pageRefs = [ref.id]
        document.workspace.documents = [storedMember]
        document.workspace.pageOrder = [ref]
        document.memberPDFData[member.id] = bytes
        let viewModel = WorkspaceViewModel(document: document)
        viewModel.prepareCompare(withOtherFileAt: selected)
        XCTAssertEqual(try XCTUnwrap(viewModel.compareRequest).engineRequest.rightData, bytes)
        XCTAssertNil(viewModel.exportError)

        let locked = root.appendingPathComponent("locked.pdf")
        XCTAssertTrue(pdf.write(to: locked, withOptions: [.ownerPasswordOption: "fictional-owner", .userPasswordOption: "fictional-user"]))
        let lockedViewModel = WorkspaceViewModel(document: document)
        lockedViewModel.prepareCompare(withOtherFileAt: locked)
        XCTAssertNil(lockedViewModel.compareRequest)
        XCTAssertEqual(lockedViewModel.exportError?.message, L10n.string("compare.error.locked"))
    }

    func testUnreadableSavedMemberRemainsNamedInUserErrorAndKeepsOriginalBytes() {
        let member = MemberDocument(displayName: "Fictional-sentinel-private-name", sourcePDFRef: "synthetic.pdf")
        let document = WorkspaceDocument()
        document.workspace.documents = [member]
        let bytes = Data("fictional corrupt member bytes".utf8)
        document.memberPDFData[member.id] = bytes
        let viewModel = WorkspaceViewModel(document: document)
        XCTAssertEqual(viewModel.importError?.fileName, member.displayName)
        XCTAssertEqual(document.memberPDFData[member.id], bytes)
        XCTAssertTrue(document.workspace.documents.isEmpty)
    }
}
