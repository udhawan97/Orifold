import CQPDF
import Foundation
import PDFKit
import XCTest
@testable import Orifold

// Synthetic decoded pixel signatures test removal independently of visible black covers.
@MainActor
final class InheritedRedactionWorkflowTests: XCTestCase {
    func testInheritedImageRemovalAtEngineWorkflowSaveAndReopenBoundaries() throws {
        let source = try inheritedImageFixture()
        let region = CGRect(x: 90, y: 290, width: 220, height: 220)
        let engine = try RedactionEngine.redact(source, regions: [0: [region]])
        XCTAssertEqual(imageCount(source), 1, "fixture sanity")
        XCTAssertEqual(imageEvidence(source).first?["decodedPrefixHex"], "E71AC30BDA5146EF9213BACE")
        XCTAssertEqual(resourceTopology(source)["pageHasResources"], false)
        XCTAssertEqual(resourceTopology(source)["parentHasResources"], true, "fixture must really inherit resources")
        XCTAssertEqual(imageCount(engine), 0, "engine boundary must remove the source image")
        XCTAssertTrue(PDFTextAnalysisEngine.readingOrderText(data: engine, pageIndex: 0).contains("KEEPME"))

        let wrapper = FileWrapper(regularFileWithContents: source)
        wrapper.preferredFilename = "inherited-image.pdf"
        let root = ProcessInfo.processInfo.environment["ORIFOLD_TEST_TEMP_ROOT"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) } ?? FileManager.default.temporaryDirectory
        let directory = root.appendingPathComponent("Orifold-inherited-redaction-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fingerprintStore = WorkspaceFingerprintStore(directory: directory)
        let document = try WorkspaceDocument(testingFile: wrapper, contentType: .pdf,
                                             filename: "inherited-image.pdf", fingerprintStore: fingerprintStore)
        let vm = WorkspaceViewModel(document: document, processingEngine: PDFiumProcessingEngine())
        let ref = try XCTUnwrap(document.workspace.pageOrder.first)
        let normalized = try XCTUnwrap(document.memberPDFData[ref.memberDocId])
        XCTAssertEqual(resourceTopology(normalized)["parentHasResources"], true)
        XCTAssertTrue(signatures(normalized).contains(secretPixels))
        vm.addRedactionMark(rect: region, pageRefID: ref.id)
        XCTAssertTrue(vm.applyRedactions())
        let live = try XCTUnwrap(document.memberPDFData[ref.memberDocId])
        XCTAssertEqual(imageCount(live), 0, "catalog graft must not resurrect inherited source images")
        XCTAssertTrue(PDFTextAnalysisEngine.readingOrderText(data: live, pageIndex: 0).contains("KEEPME"))

        let snapshot = try document.snapshot(contentType: .pdf)
        for bytes in snapshot.originalMemberPDFData.values {
            XCTAssertEqual(imageCount(bytes), 0, "pristine replay base must not retain the removed source image")
        }
        let saved = try document.savedFileWrapper(from: snapshot)
        let savedData = try XCTUnwrap(saved.regularFileContents)
        XCTAssertEqual(imageCount(savedData), 0, "saved output must not retain the source image")
        let reopened = try WorkspaceDocument(testingFile: saved, contentType: .pdf,
                                             filename: "inherited-image-saved.pdf", fingerprintStore: fingerprintStore)
        for bytes in reopened.memberPDFData.values {
            XCTAssertEqual(imageCount(bytes), 0, "editable metadata must not retain the source image")
        }
        for bytes in reopened.restoredOriginalMemberPDFData.values {
            XCTAssertEqual(imageCount(bytes), 0, "saved editable pristine bases must not retain the source image")
        }
    }

    func testUnusedSharedInheritedImageIsRemovedWhileOtherPageAndCatalogSurvive() throws {
        try assertSharedResourceWorkflow(imageAlsoUsedOnSecondPage: false)
    }

    func testInheritedImageStillUsedOnUnaffectedPageIsPreserved() throws {
        try assertSharedResourceWorkflow(imageAlsoUsedOnSecondPage: true)
    }

    func testInheritedImageRemovalSurvivesObjectReplayAndSavedPristineBaseReopen() throws {
        let source = try sharedResourceFixture(imageAlsoUsedOnSecondPage: false)
        let (document, directory, store) = try documentWithCatalog(source)
        defer { try? FileManager.default.removeItem(at: directory) }
        let vm = WorkspaceViewModel(document: document, processingEngine: PDFiumProcessingEngine())
        let first = document.workspace.pageOrder[0], second = document.workspace.pageOrder[1]
        let object = try XCTUnwrap(vm.objectMap(for: second).objects.first { $0.objectType == .imageXObject })
        XCTAssertTrue(vm.applyObjectEdit([move(object, ref: second)]))
        vm.addRedactionMark(rect: CGRect(x: 90, y: 290, width: 220, height: 220), pageRefID: first.id)
        XCTAssertTrue(vm.applyRedactions())
        let moved = try XCTUnwrap(vm.objectMap(for: second).objects.first { $0.objectType == .imageXObject })
        XCTAssertTrue(vm.applyObjectEdit([move(moved, ref: second)]), "replay exercises the object base after redaction")
        XCTAssertFalse(signatures(try XCTUnwrap(document.memberPDFData[first.memberDocId])).contains(secretPixels))
        let snapshot = try document.snapshot(contentType: .pdf)
        XCTAssertEqual(snapshot.originalMemberPDFData.count, 1, "fixture must exercise persisted pristine bytes")
        for bytes in snapshot.originalMemberPDFData.values { XCTAssertFalse(signatures(bytes).contains(secretPixels)) }
        let saved = try document.savedFileWrapper(from: snapshot)
        let reopened = try WorkspaceDocument(testingFile: saved, contentType: .pdf,
                                             filename: "shared-replay.pdf", fingerprintStore: store)
        XCTAssertEqual(reopened.restoredOriginalMemberPDFData.count, 1)
        for bytes in reopened.memberPDFData.values { XCTAssertFalse(signatures(bytes).contains(secretPixels)) }
        for bytes in reopened.restoredOriginalMemberPDFData.values { XCTAssertFalse(signatures(bytes).contains(secretPixels)) }
    }

    private let secretPixels = "E71AC30BDA5146EF9213BACE"
    private let keptPixels = "152D4982A7C40F631B8E4CD2"

    private func assertSharedResourceWorkflow(imageAlsoUsedOnSecondPage: Bool) throws {
        let source = try sharedResourceFixture(imageAlsoUsedOnSecondPage: imageAlsoUsedOnSecondPage)
        XCTAssertEqual(resourceTopology(source)["parentHasResources"], true)
        XCTAssertTrue(signatures(source).contains(secretPixels))
        XCTAssertTrue(signatures(source).contains(keptPixels))
        let (document, directory, _) = try documentWithCatalog(source)
        defer { try? FileManager.default.removeItem(at: directory) }
        let vm = WorkspaceViewModel(document: document, processingEngine: PDFiumProcessingEngine())
        let first = document.workspace.pageOrder[0]
        let before = try XCTUnwrap(PDFDocument(data: source))
        vm.addRedactionMark(rect: CGRect(x: 90, y: 290, width: 220, height: 220), pageRefID: first.id)
        XCTAssertTrue(vm.applyRedactions())
        let live = try XCTUnwrap(document.memberPDFData[first.memberDocId])
        XCTAssertEqual(signatures(live).contains(secretPixels), imageAlsoUsedOnSecondPage)
        XCTAssertTrue(signatures(live).contains(keptPixels), "unaffected page's image pixels must survive")
        let after = try XCTUnwrap(PDFDocument(data: live))
        XCTAssertEqual(after.pageCount, 2)
        XCTAssertEqual((0..<2).map { after.page(at: $0)?.label }, (0..<2).map { before.page(at: $0)?.label })
        let outlines = PDFOutlineReader.nodes(in: after)
        XCTAssertEqual(outlines.map(\.title), ["First", "Second"])
        XCTAssertEqual(outlines.map(\.localPageIndex), [0, 1])
        XCTAssertTrue(after.page(at: 1)?.annotations.contains { $0.contents == "KEEP NOTE" } ?? false)
        XCTAssertEqual(try AttachmentsService.extract("keep.txt", from: live), Data("fixture attachment".utf8))
        XCTAssertTrue(PDFTextAnalysisEngine.readingOrderText(data: live, pageIndex: 1).contains("SECOND"))
    }

    private func documentWithCatalog(_ source: Data) throws -> (WorkspaceDocument, URL, WorkspaceFingerprintStore) {
        let root = ProcessInfo.processInfo.environment["ORIFOLD_TEST_TEMP_ROOT"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) } ?? FileManager.default.temporaryDirectory
        let directory = root.appendingPathComponent("inherited-workflow-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = WorkspaceFingerprintStore(directory: directory)
        let document = try WorkspaceDocument(testingFile: FileWrapper(regularFileWithContents: source),
                                             contentType: .pdf, filename: "shared.pdf", fingerprintStore: store)
        // Import intentionally sanitizes attachments. Model an existing workspace that has
        // attached a file instead, preserving this synthetic catalog for the workflow test.
        document.memberPDFData[try XCTUnwrap(document.workspace.documents.first).id] = source
        return (document, directory, store)
    }

    private func move(_ object: DetectedObject, ref: PageRef) -> ObjectEditOperation {
        var transform = object.transform
        transform.e += 12
        return ObjectEditOperation(type: .objectTransform, documentID: ref.memberDocId, pageRefID: ref.id,
                                   sourceObjectKey: object.stableKey, objectType: object.objectType,
                                   editability: object.editability, originalBoundsPdf: object.boundsPdf,
                                   newBoundsPdf: object.boundsPdf.offsetBy(dx: 12, dy: 0),
                                   originalTransform: object.transform, newTransform: transform,
                                   pageRotation: Int(object.pageRotation), originalZIndex: object.zOrder,
                                   newZIndex: object.zOrder, replacementStrategy: .pdfiumStructural)
    }

    private func signatures(_ data: Data) -> Set<String> {
        Set(imageEvidence(data).compactMap { $0["decodedPrefixHex"] })
    }

    private func sharedResourceFixture(imageAlsoUsedOnSecondPage: Bool) throws -> Data {
        let first = "q 200 0 0 200 100 300 cm /Secret Do Q\nBT /F1 12 Tf 72 700 Td (KEEPME) Tj ET\n"
        let shared = imageAlsoUsedOnSecondPage ? "q 60 0 0 60 350 300 cm /Secret Do Q\n" : ""
        let second = "\(shared)q 100 0 0 100 100 300 cm /Keep Do Q\nBT /F1 12 Tf 72 700 Td (SECOND) Tj ET\n"
        let attachment = "fixture attachment"
        let raw = """
        %PDF-1.4
        1 0 obj << /Type /Catalog /Pages 2 0 R /PageLabels << /Nums [0 << /P (SEC-) /S /D /St 1 >>] >> \
        /Outlines 10 0 R /Names << /EmbeddedFiles << /Names [(keep.txt) 13 0 R] >> >> >> endobj
        2 0 obj << /Type /Pages /Kids [3 0 R 4 0 R] /Count 2 \
        /Resources << /Font << /F1 5 0 R >> /XObject << /Secret 7 0 R /Keep 9 0 R >> >> >> endobj
        3 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 6 0 R >> endobj
        4 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 8 0 R /Annots [15 0 R] >> endobj
        5 0 obj << /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >> endobj
        6 0 obj << /Length \(first.utf8.count) >> stream
        \(first)endstream endobj
        7 0 obj << /Type /XObject /Subtype /Image /Width 2 /Height 2 /ColorSpace /DeviceRGB \
        /BitsPerComponent 8 /Filter /ASCIIHexDecode /Length 25 >> stream
        \(secretPixels)>
        endstream endobj
        8 0 obj << /Length \(second.utf8.count) >> stream
        \(second)endstream endobj
        9 0 obj << /Type /XObject /Subtype /Image /Width 2 /Height 2 /ColorSpace /DeviceRGB \
        /BitsPerComponent 8 /Filter /ASCIIHexDecode /Length 25 >> stream
        \(keptPixels)>
        endstream endobj
        10 0 obj << /Type /Outlines /Count 2 /First 11 0 R /Last 12 0 R >> endobj
        11 0 obj << /Title (First) /Parent 10 0 R /Next 12 0 R /Dest [3 0 R /Fit] >> endobj
        12 0 obj << /Title (Second) /Parent 10 0 R /Prev 11 0 R /Dest [4 0 R /Fit] >> endobj
        13 0 obj << /Type /Filespec /F (keep.txt) /EF << /F 14 0 R >> >> endobj
        14 0 obj << /Type /EmbeddedFile /Length \(attachment.utf8.count) >> stream
        \(attachment)
        endstream endobj
        15 0 obj << /Type /Annot /Subtype /Text /Rect [400 600 424 624] /Contents (KEEP NOTE) /P 4 0 R >> endobj
        trailer << /Root 1 0 R /Size 16 >>
        %%EOF
        """
        return try XCTUnwrap(QPDFService.repaired(Data(raw.utf8)))
    }

    private func inheritedImageFixture() throws -> Data {
        // Same structure as RedactionEngineTests:186-205; unique fictional RGB pixels.
        let content = "q 200 0 0 200 100 300 cm /Im1 Do Q\nBT /F1 12 Tf 72 700 Td (KEEPME) Tj ET\n"
        let pixels = "E71AC30BDA5146EF9213BACE"
        let raw = """
        %PDF-1.4
        1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj
        2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 \
        /Resources << /Font << /F1 4 0 R >> /XObject << /Im1 6 0 R >> >> >> endobj
        3 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 5 0 R >> endobj
        4 0 obj << /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >> endobj
        5 0 obj << /Length \(content.utf8.count) >> stream
        \(content)endstream endobj
        6 0 obj << /Type /XObject /Subtype /Image /Width 2 /Height 2 /ColorSpace /DeviceRGB \
        /BitsPerComponent 8 /Filter /ASCIIHexDecode /Length \(pixels.count + 1) >> stream
        \(pixels)>
        endstream endobj
        trailer << /Root 1 0 R /Size 7 >>
        %%EOF
        """
        return try XCTUnwrap(QPDFService.repaired(Data(raw.utf8)))
    }

    private func imageEvidence(_ data: Data) -> [[String: String]] {
        XCTAssertTrue(QPDFService.isStructurallySound(data), "invalid PDF cannot count as removed pixels")
        return QPDFService.withQPDF(data, description: "inherited-redaction-image-signatures") { qpdf in
            var images: [[String: String]] = []
            for id in Int32(1)...512 {
                let object = qpdf_get_object_by_id(qpdf, id, 0)
                guard qpdf_oh_is_stream(qpdf, object) != QPDF_FALSE else { continue }
                let dictionary = qpdf_oh_get_dict(qpdf, object)
                guard qpdf_oh_is_name_and_equals(qpdf,
                    qpdf_oh_get_key(qpdf, dictionary, "/Subtype"), "/Image") != QPDF_FALSE else { continue }
                var buffer: UnsafeMutablePointer<UInt8>?
                var length = 0
                var decodedPrefix = "unavailable"
                if !QPDFService.hasErrors(qpdf_oh_get_stream_data(qpdf, object,
                    qpdf_dl_generalized, nil, &buffer, &length)), let pointer = buffer {
                    decodedPrefix = UnsafeBufferPointer(start: pointer, count: min(length, 24))
                        .map { String(format: "%02X", $0) }.joined()
                    free(pointer)
                }
                images.append(["objectID": String(id), "width": String(qpdf_oh_get_int_value(qpdf,
                    qpdf_oh_get_key(qpdf, dictionary, "/Width"))),
                    "decodedLength": String(length), "decodedPrefixHex": decodedPrefix])
            }
            return images
        } ?? []
    }

    private func imageCount(_ data: Data) -> Int { imageEvidence(data).count }


    private func resourceTopology(_ data: Data) -> [String: Bool] {
        QPDFService.withQPDF(data, description: "inherited-resource-topology") { qpdf in
            let page = qpdf_get_page_n(qpdf, 0)
            let parent = qpdf_oh_get_key(qpdf, page, "/Parent")
            return ["pageHasResources": qpdf_oh_has_key(qpdf, page, "/Resources") != QPDF_FALSE,
                    "parentHasResources": qpdf_oh_has_key(qpdf, parent, "/Resources") != QPDF_FALSE]
        } ?? [:]
    }

}
