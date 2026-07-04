import AppKit
import PDFKit
import XCTest
@testable import Orifold

@MainActor
final class PDFOCRTests: XCTestCase {
    func testSearchableDataAddsInvisibleTextLayer() async throws {
        let sourcePDF = try imageOnlyPDF()
        let sourceData = try XCTUnwrap(PDFSerializer.data(from: sourcePDF))
        let beforePage = try XCTUnwrap(sourcePDF.page(at: 0))
        let beforeBitmap = try renderedOCRBitmap(for: beforePage)
        var member = MemberDocument(displayName: "Scan", sourcePDFRef: "scan.pdf")
        let pageRef = PageRef(memberDocId: member.id, sourcePageIndex: 0)
        member.pageRefs = [pageRef.id]

        let result = try await PDFOCRService.searchableData(
            documents: [(member, sourceData)],
            recognitionProvider: { _, _, _ in
                [
                    PDFOCRRecognizedLine(
                        text: "Searchable invoice phrase",
                        normalizedBounds: CGRect(x: 0.18, y: 0.55, width: 0.55, height: 0.08),
                        confidence: 0.91
                    )
                ]
            }
        )

        let outputData = try XCTUnwrap(result.dataByMemberID[member.id])
        let outputPDF = try XCTUnwrap(PDFDocument(data: outputData))
        let outputPage = try XCTUnwrap(outputPDF.page(at: 0))
        XCTAssertEqual(result.recognizedPageCount, 1)
        XCTAssertTrue(outputPage.string?.contains("Searchable invoice phrase") == true)
        XCTAssertFalse(outputPDF.findString("invoice phrase", withOptions: .caseInsensitive).isEmpty)
        XCTAssertNoThrow(try PDFiumProcessingEngine().validatePDF(data: outputData))

        let afterBitmap = try renderedOCRBitmap(for: outputPage)
        XCTAssertLessThan(pixelDifference(beforeBitmap, afterBitmap), 0.01)
    }

    func testSearchableDataPlacesRotatedPageSelectionBoundsOnRecognizedLine() async throws {
        let sourcePDF = try imageOnlyPDF()
        let sourcePage = try XCTUnwrap(sourcePDF.page(at: 0))
        sourcePage.rotation = 90
        let sourceData = try XCTUnwrap(PDFSerializer.data(from: sourcePDF))
        var member = MemberDocument(displayName: "Rotated scan", sourcePDFRef: "rotated.pdf")
        member.pageRefs = [PageRef(memberDocId: member.id, sourcePageIndex: 0).id]

        let result = try await PDFOCRService.searchableData(
            documents: [(member, sourceData)],
            recognitionProvider: { _, _, _ in
                [
                    PDFOCRRecognizedLine(
                        text: "Rotated scan phrase",
                        normalizedBounds: CGRect(x: 0.20, y: 0.30, width: 0.25, height: 0.10),
                        confidence: 0.92
                    )
                ]
            }
        )

        let outputData = try XCTUnwrap(result.dataByMemberID[member.id])
        let outputPDF = try XCTUnwrap(PDFDocument(data: outputData))
        let outputPage = try XCTUnwrap(outputPDF.page(at: 0))
        let selection = try XCTUnwrap(outputPDF.findString("Rotated scan phrase", withOptions: .caseInsensitive).first)
        let bounds = selection.bounds(for: outputPage)

        XCTAssertEqual(outputPage.rotation, 90)
        XCTAssertGreaterThan(bounds.minX, 170)
        XCTAssertLessThan(bounds.minX, 200)
        XCTAssertGreaterThan(bounds.minY, 430)
        XCTAssertLessThan(bounds.minY, 460)
        XCTAssertGreaterThan(bounds.width, bounds.height)
    }

    func testSearchableDataSkipsAlreadySearchablePages() async throws {
        let sourcePDF = try textPDF("Already searchable")
        let sourceData = try XCTUnwrap(PDFSerializer.data(from: sourcePDF))
        var member = MemberDocument(displayName: "Text", sourcePDFRef: "text.pdf")
        let pageRef = PageRef(memberDocId: member.id, sourcePageIndex: 0)
        member.pageRefs = [pageRef.id]
        var providerWasCalled = false

        do {
            _ = try await PDFOCRService.searchableData(
                documents: [(member, sourceData)],
                recognitionProvider: { _, _, _ in
                    providerWasCalled = true
                    return []
                }
            )
            XCTFail("Expected already-searchable input to take the no-scanned-pages path.")
        } catch PDFOCRError.noScannedPages {
            XCTAssertFalse(providerWasCalled)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testSearchableDataCanRepairPageWithExistingTextLayer() async throws {
        let sourcePDF = try textPDF("Existing bad text layer")
        let sourceData = try XCTUnwrap(PDFSerializer.data(from: sourcePDF))
        var member = MemberDocument(displayName: "Text", sourcePDFRef: "text.pdf")
        member.pageRefs = [PageRef(memberDocId: member.id, sourcePageIndex: 0).id]
        var requestedPages: [Int] = []

        let result = try await PDFOCRService.searchableData(
            documents: [(member, sourceData)],
            includePagesWithText: true,
            recognitionProvider: { _, pageNumber, _ in
                requestedPages.append(pageNumber)
                return [
                    PDFOCRRecognizedLine(
                        text: "Repaired searchable phrase",
                        normalizedBounds: CGRect(x: 0.14, y: 0.70, width: 0.55, height: 0.08),
                        confidence: 0.92
                    )
                ]
            }
        )

        let outputData = try XCTUnwrap(result.dataByMemberID[member.id])
        let outputPDF = try XCTUnwrap(PDFDocument(data: outputData))
        XCTAssertEqual(requestedPages, [1])
        XCTAssertEqual(result.recognizedPageCount, 1)
        XCTAssertFalse(outputPDF.findString("Repaired searchable phrase", withOptions: .caseInsensitive).isEmpty)
        XCTAssertNoThrow(try PDFiumProcessingEngine().validatePDF(data: outputData))
    }

    @MainActor
    func testBlankPageDoesNotShowScanBanner() throws {
        let document = WorkspaceDocument()
        try document.importPDFDocumentForTesting(try blankPDF(), filename: "blank.pdf")
        let viewModel = WorkspaceViewModel(document: document)
        XCTAssertFalse(viewModel.hasScannedPages)
        XCTAssertEqual(viewModel.scannedPageCount, 0)
        XCTAssertEqual(viewModel.ocrCandidatePageCount, 0)
        XCTAssertFalse(viewModel.canRepairSearchableText)
    }

    @MainActor
    func testViewModelOffersRepairWhenVisiblePageAlreadyHasTextLayer() throws {
        let document = WorkspaceDocument()
        try document.importPDFDocumentForTesting(try textPDF("Existing searchable-looking text"), filename: "text.pdf")
        let viewModel = WorkspaceViewModel(document: document)

        XCTAssertFalse(viewModel.hasScannedPages)
        XCTAssertEqual(viewModel.scannedPageCount, 0)
        XCTAssertEqual(viewModel.ocrCandidatePageCount, 1)
        XCTAssertFalse(viewModel.canStartSearchable)
        XCTAssertTrue(viewModel.canRepairSearchableText)
    }

    func testSearchableDataDropsLowConfidenceLines() async throws {
        let sourcePDF = try imageOnlyPDF()
        let sourceData = try XCTUnwrap(PDFSerializer.data(from: sourcePDF))
        var member = MemberDocument(displayName: "Scan", sourcePDFRef: "scan.pdf")
        let pageRef = PageRef(memberDocId: member.id, sourcePageIndex: 0)
        member.pageRefs = [pageRef.id]

        let result = try await PDFOCRService.searchableData(
            documents: [(member, sourceData)],
            recognitionProvider: { _, _, _ in
                [
                    PDFOCRRecognizedLine(
                        text: "Reliable text",
                        normalizedBounds: CGRect(x: 0.18, y: 0.55, width: 0.40, height: 0.08),
                        confidence: 0.88
                    ),
                    PDFOCRRecognizedLine(
                        text: "Unreliable text",
                        normalizedBounds: CGRect(x: 0.18, y: 0.45, width: 0.40, height: 0.08),
                        confidence: 0.12
                    )
                ]
            }
        )

        let outputData = try XCTUnwrap(result.dataByMemberID[member.id])
        let outputPDF = try XCTUnwrap(PDFDocument(data: outputData))
        let outputString = try XCTUnwrap(outputPDF.page(at: 0)?.string)
        XCTAssertTrue(outputString.contains("Reliable text"))
        XCTAssertFalse(outputString.contains("Unreliable text"))
    }

    func testSearchableDataUpdatesMixedDocumentAndKeepsTextPageSearchable() async throws {
        let sourcePDF = PDFDocument()
        let scannedPage = try XCTUnwrap(try imageOnlyPDF().page(at: 0))
        let textPage = try XCTUnwrap(try textPDF("Existing searchable text").page(at: 0))
        sourcePDF.insert(scannedPage, at: 0)
        sourcePDF.insert(textPage, at: 1)
        let sourceData = try XCTUnwrap(PDFSerializer.data(from: sourcePDF))
        var member = MemberDocument(displayName: "Mixed", sourcePDFRef: "mixed.pdf")
        member.pageRefs = [
            PageRef(memberDocId: member.id, sourcePageIndex: 0).id,
            PageRef(memberDocId: member.id, sourcePageIndex: 1).id
        ]
        var requestedPages: [Int] = []

        let result = try await PDFOCRService.searchableData(
            documents: [(member, sourceData)],
            recognitionProvider: { _, pageNumber, _ in
                requestedPages.append(pageNumber)
                return [
                    PDFOCRRecognizedLine(
                        text: "New scan text",
                        normalizedBounds: CGRect(x: 0.18, y: 0.55, width: 0.40, height: 0.08),
                        confidence: 0.88
                    )
                ]
            }
        )

        let outputData = try XCTUnwrap(result.dataByMemberID[member.id])
        let outputPDF = try XCTUnwrap(PDFDocument(data: outputData))
        XCTAssertEqual(outputPDF.pageCount, 2)
        XCTAssertEqual(requestedPages, [1])
        XCTAssertTrue(outputPDF.page(at: 0)?.string?.contains("New scan text") == true)
        XCTAssertTrue(outputPDF.page(at: 1)?.string?.contains("Existing searchable text") == true)
        XCTAssertNoThrow(try PDFiumProcessingEngine().validatePDF(data: outputData))
    }

    func testSearchableDataFailsWholeResultWhenOneScannedPageFails() async throws {
        let sourcePDF = PDFDocument()
        let firstPage = try XCTUnwrap(try imageOnlyPDF().page(at: 0))
        let secondPage = try XCTUnwrap(try imageOnlyPDF().page(at: 0))
        sourcePDF.insert(firstPage, at: 0)
        sourcePDF.insert(secondPage, at: 1)
        let sourceData = try XCTUnwrap(PDFSerializer.data(from: sourcePDF))
        var member = MemberDocument(displayName: "Two scans", sourcePDFRef: "scans.pdf")
        member.pageRefs = [
            PageRef(memberDocId: member.id, sourcePageIndex: 0).id,
            PageRef(memberDocId: member.id, sourcePageIndex: 1).id
        ]

        do {
            _ = try await PDFOCRService.searchableData(
                documents: [(member, sourceData)],
                recognitionProvider: { _, pageNumber, _ in
                    if pageNumber == 2 {
                        throw PDFOCRError.recognitionFailed(pageNumber: pageNumber)
                    }
                    return [
                        PDFOCRRecognizedLine(
                            text: "First page text",
                            normalizedBounds: CGRect(x: 0.18, y: 0.55, width: 0.40, height: 0.08),
                            confidence: 0.88
                        )
                    ]
                }
            )
            XCTFail("Expected one bad page to fail the searchable update.")
        } catch PDFOCRError.recognitionFailed(let pageNumber) {
            XCTAssertEqual(pageNumber, 2)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testSearchableDataFailsWhenScannedPageHasNoUsableText() async throws {
        let sourcePDF = try imageOnlyPDF()
        let sourceData = try XCTUnwrap(PDFSerializer.data(from: sourcePDF))
        var member = MemberDocument(displayName: "Scan", sourcePDFRef: "scan.pdf")
        member.pageRefs = [PageRef(memberDocId: member.id, sourcePageIndex: 0).id]

        do {
            _ = try await PDFOCRService.searchableData(
                documents: [(member, sourceData)],
                recognitionProvider: { _, _, _ in
                    [
                        PDFOCRRecognizedLine(
                            text: "Too uncertain",
                            normalizedBounds: CGRect(x: 0.20, y: 0.50, width: 0.45, height: 0.08),
                            confidence: 0.2
                        )
                    ]
                }
            )
            XCTFail("Expected low-confidence scan recognition to fail.")
        } catch PDFOCRError.recognitionFailed(let pageNumber) {
            XCTAssertEqual(pageNumber, 1)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testSearchableDataReportsInvalidPDFInsteadOfAlreadySearchable() async throws {
        var member = MemberDocument(displayName: "Broken", sourcePDFRef: "broken.pdf")
        member.pageRefs = [UUID()]

        do {
            _ = try await PDFOCRService.searchableData(
                documents: [(member, Data([0x00, 0x01, 0x02]))],
                recognitionProvider: { _, _, _ in [] }
            )
            XCTFail("Expected invalid PDF error.")
        } catch PDFOCRError.invalidPDF(let memberName) {
            XCTAssertEqual(memberName, "Broken")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testSearchableDataCancellationLeavesNoResult() async throws {
        let sourcePDF = try imageOnlyPDF()
        let sourceData = try XCTUnwrap(PDFSerializer.data(from: sourcePDF))
        var member = MemberDocument(displayName: "Scan", sourcePDFRef: "scan.pdf")
        let pageRef = PageRef(memberDocId: member.id, sourcePageIndex: 0)
        member.pageRefs = [pageRef.id]

        do {
            _ = try await PDFOCRService.searchableData(
                documents: [(member, sourceData)],
                recognitionProvider: { _, _, isCancelled in
                    XCTAssertTrue(isCancelled())
                    return []
                },
                isCancelled: { true }
            )
            XCTFail("Expected cancellation.")
        } catch PDFOCRError.cancelled {
            XCTAssertTrue(true)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    @MainActor
    func testViewModelDetectsScannedPagesAndClearsBannerAfterSearchableUpdate() async throws {
        let document = WorkspaceDocument()
        try document.importPDFDocumentForTesting(try imageOnlyPDF(), filename: "scan.pdf")
        let viewModel = WorkspaceViewModel(document: document)
        XCTAssertTrue(viewModel.hasScannedPages)
        XCTAssertEqual(viewModel.scannedPageCount, 1)
        XCTAssertTrue(viewModel.canStartSearchable)

        let member = try XCTUnwrap(viewModel.loadedPDFs.first?.0)
        let sourceData = try XCTUnwrap(document.memberPDFData[member.id])
        let result = try await PDFOCRService.searchableData(
            documents: [(member, sourceData)],
            recognitionProvider: { _, _, _ in
                [
                    PDFOCRRecognizedLine(
                        text: "Detected scan text",
                        normalizedBounds: CGRect(x: 0.20, y: 0.50, width: 0.45, height: 0.08),
                        confidence: 0.9
                    )
                ]
            }
        )

        let updatedData = try XCTUnwrap(result.dataByMemberID[member.id])
        document.memberPDFData[member.id] = updatedData
        let updated = try XCTUnwrap(PDFDocument(data: updatedData))
        viewModel.loadedPDFs = [(member, updated)]
        viewModel.rebuild()
        XCTAssertFalse(viewModel.hasScannedPages)

        let exportedText = try XCTUnwrap(String(data: try viewModel.dataForWorkspaceExport(as: .text), encoding: .utf8))
        XCTAssertTrue(exportedText.contains("Detected scan text"))
    }

    @MainActor
    func testViewModelBlocksStartingSearchableWhileBusy() throws {
        let document = WorkspaceDocument()
        try document.importPDFDocumentForTesting(try imageOnlyPDF(), filename: "scan.pdf")
        let viewModel = WorkspaceViewModel(document: document)
        XCTAssertTrue(viewModel.canStartSearchable)

        viewModel.setProcessingStateForTesting(compressionActive: true)
        XCTAssertFalse(viewModel.canStartSearchable)

        viewModel.setProcessingStateForTesting(compressionActive: false, ocrActive: true)
        XCTAssertFalse(viewModel.canStartSearchable)
        XCTAssertTrue(viewModel.isMakingSearchable)

        viewModel.setProcessingStateForTesting()
        viewModel.isImporting = true
        XCTAssertFalse(viewModel.canStartSearchable)
    }
}

private func imageOnlyPDF() throws -> PDFDocument {
    let view = OCRImageFixtureView(frame: CGRect(x: 0, y: 0, width: 612, height: 792))
    return try XCTUnwrap(PDFDocument(data: view.dataWithPDF(inside: view.bounds)))
}

private func textPDF(_ text: String) throws -> PDFDocument {
    let view = OCRTextFixtureView(frame: CGRect(x: 0, y: 0, width: 612, height: 792), text: text)
    return try XCTUnwrap(PDFDocument(data: view.dataWithPDF(inside: view.bounds)))
}

private func blankPDF() throws -> PDFDocument {
    let view = OCRBlankFixtureView(frame: CGRect(x: 0, y: 0, width: 612, height: 792))
    return try XCTUnwrap(PDFDocument(data: view.dataWithPDF(inside: view.bounds)))
}

private func renderedOCRBitmap(for page: PDFPage) throws -> NSBitmapImageRep {
    let thumbnail = page.thumbnail(of: CGSize(width: 306, height: 396), for: .mediaBox)
    let data = try XCTUnwrap(thumbnail.tiffRepresentation)
    return try XCTUnwrap(NSBitmapImageRep(data: data))
}

private func pixelDifference(_ lhs: NSBitmapImageRep, _ rhs: NSBitmapImageRep) -> Double {
    guard lhs.pixelsWide == rhs.pixelsWide, lhs.pixelsHigh == rhs.pixelsHigh else { return 1 }
    var changed = 0
    let total = max(1, lhs.pixelsWide * lhs.pixelsHigh)
    for y in 0..<lhs.pixelsHigh {
        for x in 0..<lhs.pixelsWide {
            guard let left = lhs.colorAt(x: x, y: y),
                  let right = rhs.colorAt(x: x, y: y) else {
                changed += 1
                continue
            }
            let delta = abs(left.redComponent - right.redComponent) +
                abs(left.greenComponent - right.greenComponent) +
                abs(left.blueComponent - right.blueComponent)
            if delta > 0.08 {
                changed += 1
            }
        }
    }
    return Double(changed) / Double(total)
}

private final class OCRImageFixtureView: NSView {
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        bounds.fill()
        NSColor(calibratedWhite: 0.86, alpha: 1).setFill()
        NSBezierPath(rect: CGRect(x: 120, y: 180, width: 360, height: 260)).fill()
        NSColor(calibratedWhite: 0.35, alpha: 1).setFill()
        NSBezierPath(ovalIn: CGRect(x: 250, y: 270, width: 90, height: 90)).fill()
    }
}

private final class OCRBlankFixtureView: NSView {
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        bounds.fill()
    }
}

private final class OCRTextFixtureView: NSView {
    private let text: String

    init(frame frameRect: NSRect, text: String) {
        self.text = text
        super.init(frame: frameRect)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        bounds.fill()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 24),
            .foregroundColor: NSColor.black
        ]
        text.draw(in: CGRect(x: 72, y: 120, width: 460, height: 60), withAttributes: attributes)
    }
}
