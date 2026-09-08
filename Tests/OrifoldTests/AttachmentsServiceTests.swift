import AppKit
import CoreGraphics
import PDFKit
import XCTest
@testable import Orifold

final class AttachmentsServiceTests: XCTestCase {
    func testListEmptyWhenNoAttachments() throws {
        let bare = PDFDocument()
        bare.insert(PDFPage(), at: 0)
        XCTAssertEqual(try AttachmentsService.list(in: try XCTUnwrap(bare.dataRepresentation())), [])
    }
    func testAddListExtractRoundTrip() throws {
        let base: Data = {
            let document = PDFDocument()
            document.insert(PDFPage(), at: 0)
            return document.dataRepresentation()!
        }()
        let payload = Data("hello-orifold".utf8)

        let withAttachment = try AttachmentsService.add(payload, name: "note.txt", mimeType: "text/plain", to: base)
        let listed = try AttachmentsService.list(in: withAttachment)
        XCTAssertEqual(listed.map(\.name), ["note.txt"])
        XCTAssertEqual(listed.first?.byteCount, payload.count)
        XCTAssertEqual(listed.first?.mimeType, "text/plain")
        XCTAssertEqual(try AttachmentsService.extract("note.txt", from: withAttachment), payload) // byte-identical

        let removed = try AttachmentsService.remove("note.txt", from: withAttachment)
        XCTAssertEqual(try AttachmentsService.list(in: removed), [])
        XCTAssertTrue(QPDFService.isStructurallySound(removed))
    }

    func testAddDisambiguatesDuplicateKey() throws {
        let base: Data = {
            let document = PDFDocument()
            document.insert(PDFPage(), at: 0)
            return document.dataRepresentation()!
        }()
        let first = try AttachmentsService.add(Data("one".utf8), name: "note.txt", mimeType: nil, to: base)
        let second = try AttachmentsService.add(Data("two".utf8), name: "note.txt", mimeType: nil, to: first)
        // qpdf refuses a duplicate name-tree key, so the second add must land under
        // a distinct key rather than silently failing or overwriting the first.
        XCTAssertEqual(Set(try AttachmentsService.list(in: second).map(\.name)), ["note.txt", "note-2.txt"])
        XCTAssertEqual(try AttachmentsService.extract("note.txt", from: second), Data("one".utf8))
        XCTAssertEqual(try AttachmentsService.extract("note-2.txt", from: second), Data("two".utf8))
    }

    func testExtractThrowsNotFoundForMissingAttachment() throws {
        let base: Data = {
            let document = PDFDocument()
            document.insert(PDFPage(), at: 0)
            return document.dataRepresentation()!
        }()
        let withAttachment = try AttachmentsService.add(Data("x".utf8), name: "a.txt", mimeType: nil, to: base)
        XCTAssertThrowsError(try AttachmentsService.extract("missing.txt", from: withAttachment)) { error in
            XCTAssertEqual(error as? AttachmentsError, .notFound)
        }
    }

    // `QPDFService.sanitized` intentionally strips /Names/EmbeddedFiles, so
    // "sanitize for sharing" drops every attachment — the deliberate interaction
    // with this feature.
    func testSanitizeStripsAttachments() throws {
        let base: Data = {
            let document = PDFDocument()
            document.insert(PDFPage(), at: 0)
            return document.dataRepresentation()!
        }()
        let withAttachment = try AttachmentsService.add(Data("secret".utf8), name: "s.txt", mimeType: nil, to: base)
        XCTAssertEqual(try AttachmentsService.list(in: withAttachment).count, 1)
        let sanitized = try XCTUnwrap(QPDFService.sanitized(withAttachment, removingMetadata: false))
        XCTAssertEqual(try AttachmentsService.list(in: sanitized), [])
    }

    // MARK: - Workspace integration (I3)

    func testAddAttachmentToWorkspaceMemberWithUndo() throws {
        let viewModel = try makeViewModel()
        let memberID = try XCTUnwrap(viewModel.document.workspace.documents.first?.id)
        let payloadURL = try writeTempFile(Data("attach-me".utf8), name: "note.txt")
        defer { try? FileManager.default.removeItem(at: payloadURL.deletingLastPathComponent()) }

        XCTAssertTrue(viewModel.addAttachment(payloadURL))
        let liveBytes = try XCTUnwrap(viewModel.document.memberPDFData[memberID])
        XCTAssertEqual(try AttachmentsService.list(in: liveBytes).map(\.name), ["note.txt"])
        XCTAssertTrue(viewModel.undoManager?.canUndo ?? false)

        viewModel.undoManager?.undo()
        let restored = try XCTUnwrap(viewModel.document.memberPDFData[memberID])
        XCTAssertEqual(try AttachmentsService.list(in: restored), [])
    }

    // Regression: attachments live only in the member byte lane, which the PDFKit
    // export assembly drops — they must be re-grafted onto the exported bytes.
    func testAttachmentsSurviveExport() throws {
        let viewModel = try makeViewModel()
        let payloadURL = try writeTempFile(Data("survive-export".utf8), name: "keep.txt")
        defer { try? FileManager.default.removeItem(at: payloadURL.deletingLastPathComponent()) }
        XCTAssertTrue(viewModel.addAttachment(payloadURL))

        let exported = try viewModel.dataForPDFExport()
        XCTAssertEqual(try AttachmentsService.list(in: exported).map(\.name), ["keep.txt"])
        XCTAssertEqual(try AttachmentsService.extract("keep.txt", from: exported), Data("survive-export".utf8))
    }

    func testExportWithSanitizeDropsAttachments() throws {
        let viewModel = try makeViewModel()
        let payloadURL = try writeTempFile(Data("strip-me".utf8), name: "gone.txt")
        defer { try? FileManager.default.removeItem(at: payloadURL.deletingLastPathComponent()) }
        XCTAssertTrue(viewModel.addAttachment(payloadURL))

        let options = WorkspaceExportOptions(sanitization: PDFSanitizationOptions(removesMetadata: false))
        let exported = try viewModel.dataForPDFExport(options: options)
        XCTAssertEqual(try AttachmentsService.list(in: exported), [])
    }

    func testAddedAttachmentSurvivesNormalSaveAndReopenWithLiveAnnotation() throws {
        let viewModel = try makeViewModel()
        let memberID = try XCTUnwrap(viewModel.document.workspace.documents.first?.id)
        let payload = Data("normal-save-payload".utf8)
        let payloadURL = try writeTempFile(payload, name: "saved.txt")
        defer { try? FileManager.default.removeItem(at: payloadURL.deletingLastPathComponent()) }
        XCTAssertTrue(viewModel.addAttachment(payloadURL))
        let page = try XCTUnwrap(viewModel.loadedPDFs.first?.1.page(at: 0))
        let annotation = PDFAnnotation(bounds: CGRect(x: 20, y: 20, width: 120, height: 30),
                                       forType: .freeText, withProperties: nil)
        annotation.contents = "Live note"
        page.addAnnotation(annotation)
        let widget = PDFAnnotation(bounds: CGRect(x: 20, y: 80, width: 150, height: 30),
                                   forType: .widget, withProperties: nil)
        widget.widgetFieldType = .text
        widget.fieldName = "Fictional reference"
        widget.widgetStringValue = "Live answer"
        page.addAnnotation(widget)
        viewModel.markAnnotationsModified()
        // Loader retains unreadable orphan bytes for possible recovery; they are not a
        // workspace member and must not make an otherwise valid snapshot fail.
        viewModel.document.memberPDFData[UUID()] = Data("unreadable orphan".utf8)

        let snapshot = try viewModel.document.snapshot(contentType: .pdf)
        XCTAssertEqual(try AttachmentsService.extract("saved.txt", from: XCTUnwrap(snapshot.memberPDFData[memberID])), payload)
        let saved = try viewModel.document.savedFileWrapper(from: snapshot)
        XCTAssertEqual(try AttachmentsService.extract("saved.txt", from: XCTUnwrap(saved.regularFileContents)), payload)
        let reopened = try WorkspaceDocument(testingFile: saved, contentType: .pdf)
        XCTAssertEqual(try AttachmentsService.extract("saved.txt", from: XCTUnwrap(reopened.memberPDFData[memberID])), payload)
        let reopenedPDF = try XCTUnwrap(PDFDocument(data: XCTUnwrap(reopened.memberPDFData[memberID])))
        XCTAssertTrue(try XCTUnwrap(reopenedPDF.page(at: 0)).annotations.contains { $0.contents == "Live note" })
        XCTAssertEqual(reopenedPDF.page(at: 0)?.annotations.first { $0.isPDFWidget }?.widgetStringValue, "Live answer")

        XCTAssertTrue(viewModel.removeAttachment(named: "saved.txt"))
        let removed = try viewModel.document.savedFileWrapper(from: viewModel.document.snapshot(contentType: .pdf))
        XCTAssertEqual(try AttachmentsService.list(in: XCTUnwrap(removed.regularFileContents)), [])
        let reopenedRemoved = try WorkspaceDocument(testingFile: removed, contentType: .pdf)
        XCTAssertEqual(try AttachmentsService.list(in: XCTUnwrap(reopenedRemoved.memberPDFData[memberID])), [])
    }

    // MARK: - Harness

    // `WorkspaceViewModel.undoManager` is weak (the window owns it in the app), so
    // the test must retain it or it deallocates and every registerUndo no-ops.
    private var retainedUndoManager: UndoManager?

    private func makeViewModel() throws -> WorkspaceViewModel {
        let wrapper = FileWrapper(regularFileWithContents: makeSinglePagePDF())
        wrapper.preferredFilename = "attach.pdf"
        let document = try WorkspaceDocument(testingFile: wrapper, contentType: .pdf, filename: "attach.pdf")
        let viewModel = WorkspaceViewModel(document: document, processingEngine: PDFiumProcessingEngine())
        let undo = UndoManager()
        retainedUndoManager = undo
        viewModel.undoManager = undo
        return viewModel
    }

    private func makeSinglePagePDF() -> Data {
        let data = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        let ctx = CGContext(consumer: CGDataConsumer(data: data as CFMutableData)!, mediaBox: &mediaBox, nil)!
        ctx.beginPDFPage(nil)
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(mediaBox)
        ctx.endPDFPage()
        ctx.closePDF()
        return data as Data
    }

    // Writes into a unique subdirectory so the file's `lastPathComponent` (which
    // `addAttachment` uses as the attachment name) is exactly `name`.
    private func writeTempFile(_ data: Data, name: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Orifold-att-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }
}
