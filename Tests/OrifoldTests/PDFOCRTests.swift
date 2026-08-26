import AppKit
import PDFKit
import Vision
import XCTest
@testable import Orifold

@MainActor
final class PDFOCRTests: XCTestCase {
    private func installDeterministicOCR(on viewModel: WorkspaceViewModel, text: String) {
        viewModel.ocrRecognitionProviderForTesting = { _, _, _ in
            [
                PDFOCRRecognizedLine(
                    text: text,
                    normalizedBounds: CGRect(x: 0.15, y: 0.62, width: 0.62, height: 0.08),
                    confidence: 0.95
                )
            ]
        }
    }

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

    func testSearchableDataKeepsEveryRecognizedLineInsidePageBounds() async throws {
        let sourcePDF = try imageOnlyPDF()
        let sourceData = try XCTUnwrap(PDFSerializer.data(from: sourcePDF))
        var member = MemberDocument(displayName: "Multi-line scan", sourcePDFRef: "scan.pdf")
        member.pageRefs = [PageRef(memberDocId: member.id, sourcePageIndex: 0).id]
        let recognizedLines = [
            PDFOCRRecognizedLine(
                text: "ORIFOLD OCR LIVE CHECK",
                normalizedBounds: CGRect(x: 0.12, y: 0.70, width: 0.58, height: 0.06),
                confidence: 0.96
            ),
            PDFOCRRecognizedLine(
                text: "Preserve the original page.",
                normalizedBounds: CGRect(x: 0.12, y: 0.56, width: 0.52, height: 0.05),
                confidence: 0.95
            ),
            PDFOCRRecognizedLine(
                text: "Recognize locally. Verify before applying.",
                normalizedBounds: CGRect(x: 0.12, y: 0.48, width: 0.68, height: 0.05),
                confidence: 0.94
            ),
            PDFOCRRecognizedLine(
                text: "SEARCH TOKEN FOLD 7429",
                normalizedBounds: CGRect(x: 0.16, y: 0.20, width: 0.62, height: 0.07),
                confidence: 0.97
            )
        ]

        let result = try await PDFOCRService.searchableData(
            documents: [(member, sourceData)],
            recognitionProvider: { _, _, _ in recognizedLines }
        )

        let outputData = try XCTUnwrap(result.dataByMemberID[member.id])
        let outputPDF = try XCTUnwrap(PDFDocument(data: outputData))
        let outputPage = try XCTUnwrap(outputPDF.page(at: 0))
        let mediaBox = outputPage.bounds(for: .mediaBox)

        for line in recognizedLines {
            let selection = try XCTUnwrap(
                outputPDF.findString(line.text, withOptions: .caseInsensitive).first,
                "Missing OCR line: \(line.text)"
            )
            let bounds = selection.bounds(for: outputPage)
            XCTAssertGreaterThan(bounds.width, 0, line.text)
            XCTAssertGreaterThan(bounds.height, 0, line.text)
            XCTAssertGreaterThanOrEqual(bounds.minX, mediaBox.minX - 1, line.text)
            XCTAssertGreaterThanOrEqual(bounds.minY, mediaBox.minY - 1, line.text)
            XCTAssertLessThanOrEqual(bounds.maxX, mediaBox.maxX + 1, line.text)
            XCTAssertLessThanOrEqual(bounds.maxY, mediaBox.maxY + 1, line.text)
        }
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

    func testSearchableDataCanAddAnotherLayerToPageWithExistingText() async throws {
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
        XCTAssertFalse(viewModel.canAddOCRLayerToSearchablePages)
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
        XCTAssertTrue(viewModel.canAddOCRLayerToSearchablePages)
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
        XCTAssertEqual(result.qualityReport.recognizedLineCount, 1)
        XCTAssertEqual(result.qualityReport.lowConfidenceLineCount, 1)
        XCTAssertTrue(result.qualityReport.needsReview)
    }

    func testSearchableDataReportsPartialSuccessWithoutDiscardingReadablePages() async throws {
        let sourcePDF = PDFDocument()
        sourcePDF.insert(try XCTUnwrap(try imageOnlyPDF().page(at: 0)), at: 0)
        sourcePDF.insert(try XCTUnwrap(try imageOnlyPDF().page(at: 0)), at: 1)
        let sourceData = try XCTUnwrap(PDFSerializer.data(from: sourcePDF))
        var member = MemberDocument(displayName: "Two scans", sourcePDFRef: "scans.pdf")
        member.pageRefs = [
            PageRef(memberDocId: member.id, sourcePageIndex: 0).id,
            PageRef(memberDocId: member.id, sourcePageIndex: 1).id
        ]

        let result = try await PDFOCRService.searchableData(
            documents: [(member, sourceData)],
            options: PDFOCROptions(continuesAfterPageFailure: true),
            recognitionProvider: { _, pageNumber, _ in
                guard pageNumber == 1 else {
                    throw PDFOCRError.recognitionFailed(pageNumber: pageNumber)
                }
                return [
                    PDFOCRRecognizedLine(
                        text: "Readable first page",
                        normalizedBounds: CGRect(x: 0.18, y: 0.55, width: 0.40, height: 0.08),
                        confidence: 0.91
                    )
                ]
            }
        )

        let outputData = try XCTUnwrap(result.dataByMemberID[member.id])
        let outputPDF = try XCTUnwrap(PDFDocument(data: outputData))
        XCTAssertEqual(result.recognizedPageCount, 1)
        XCTAssertFalse(outputPDF.findString("Readable first page", withOptions: .caseInsensitive).isEmpty)
        XCTAssertEqual(result.qualityReport.requestedPageCount, 2)
        XCTAssertEqual(result.qualityReport.skippedPageNumbers, [2])
        XCTAssertEqual(result.qualityReport.recognizedLineCount, 1)
        XCTAssertEqual(result.qualityReport.averageConfidence, 0.91, accuracy: 0.001)
        XCTAssertEqual(result.qualityReport.changedMemberCount, 1)
        XCTAssertEqual(result.qualityReport.validatedMemberCount, 1)
        XCTAssertTrue(result.qualityReport.integrityChecksPassed)
        XCTAssertTrue(result.qualityReport.needsReview)
        XCTAssertNoThrow(try PDFiumProcessingEngine().validatePDF(data: outputData))
    }

    func testSearchableDataReportsSkippedPagesInVisibleWorkspaceOrder() async throws {
        let twoPagePDF = PDFDocument()
        twoPagePDF.insert(try XCTUnwrap(try imageOnlyPDF().page(at: 0)), at: 0)
        twoPagePDF.insert(try XCTUnwrap(try imageOnlyPDF().page(at: 0)), at: 1)
        let twoPageData = try XCTUnwrap(PDFSerializer.data(from: twoPagePDF))
        var first = MemberDocument(displayName: "First", sourcePDFRef: "first.pdf")
        first.pageRefs = (0..<2).map { PageRef(memberDocId: first.id, sourcePageIndex: $0).id }
        var second = MemberDocument(displayName: "Second", sourcePDFRef: "second.pdf")
        second.pageRefs = (0..<2).map { PageRef(memberDocId: second.id, sourcePageIndex: $0).id }

        let result = try await PDFOCRService.searchableData(
            documents: [(first, twoPageData), (second, twoPageData)],
            displayPageNumbersByMemberID: [first.id: [2, 4], second.id: [1, 3]],
            options: PDFOCROptions(continuesAfterPageFailure: true),
            recognitionProvider: { _, visiblePageNumber, _ in
                guard visiblePageNumber != 1 else {
                    throw PDFOCRError.recognitionFailed(pageNumber: visiblePageNumber)
                }
                return [
                    PDFOCRRecognizedLine(
                        text: "Visible page \(visiblePageNumber)",
                        normalizedBounds: CGRect(x: 0.15, y: 0.65, width: 0.4, height: 0.08),
                        confidence: 0.9
                    )
                ]
            }
        )

        XCTAssertEqual(result.qualityReport.skippedPageNumbers, [1])
        XCTAssertEqual(result.qualityReport.recognizedPageCount, 3)
    }

    func testSearchableDataReturnsOnlyMembersWhosePagesChanged() async throws {
        let scannedData = try XCTUnwrap(PDFSerializer.data(from: try imageOnlyPDF()))
        let textData = try XCTUnwrap(PDFSerializer.data(from: try textPDF("Already searchable")))
        var scannedMember = MemberDocument(displayName: "Scan", sourcePDFRef: "scan.pdf")
        scannedMember.pageRefs = [PageRef(memberDocId: scannedMember.id, sourcePageIndex: 0).id]
        var textMember = MemberDocument(displayName: "Text", sourcePDFRef: "text.pdf")
        textMember.pageRefs = [PageRef(memberDocId: textMember.id, sourcePageIndex: 0).id]

        let result = try await PDFOCRService.searchableData(
            documents: [(scannedMember, scannedData), (textMember, textData)],
            recognitionProvider: { _, pageNumber, _ in
                XCTAssertEqual(pageNumber, 1)
                return [
                    PDFOCRRecognizedLine(
                        text: "Only the scan changes",
                        normalizedBounds: CGRect(x: 0.18, y: 0.55, width: 0.45, height: 0.08),
                        confidence: 0.93
                    )
                ]
            }
        )

        XCTAssertEqual(Set(result.dataByMemberID.keys), [scannedMember.id])
        XCTAssertNil(result.dataByMemberID[textMember.id])
        XCTAssertEqual(result.qualityReport.changedMemberCount, 1)
        XCTAssertEqual(result.qualityReport.validatedMemberCount, 1)
        XCTAssertTrue(result.qualityReport.integrityChecksPassed)
    }

    func testSearchableDataPreservesPageGeometryAndAnnotationsWhileAddingTextOverlay() async throws {
        let sourcePDF = try imageOnlyPDF()
        let sourcePage = try XCTUnwrap(sourcePDF.page(at: 0))
        let cropBox = CGRect(x: 24, y: 36, width: 540, height: 700)
        sourcePage.setBounds(cropBox, for: .cropBox)
        sourcePage.rotation = 270
        let note = PDFAnnotation(
            bounds: CGRect(x: 72, y: 96, width: 24, height: 24),
            forType: .text,
            withProperties: nil
        )
        note.contents = "Keep this note"
        sourcePage.addAnnotation(note)

        let field = PDFAnnotation(
            bounds: CGRect(x: 120, y: 96, width: 180, height: 28),
            forType: .widget,
            withProperties: nil
        )
        field.widgetFieldType = .text
        field.fieldName = "Reference number"
        field.widgetStringValue = "FORM-2048"
        sourcePage.addAnnotation(field)

        let outlineRoot = PDFOutline()
        let outlineItem = PDFOutline()
        outlineItem.label = "Scanned page"
        outlineItem.destination = PDFDestination(page: sourcePage, at: CGPoint(x: 0, y: 792))
        outlineRoot.insertChild(outlineItem, at: 0)
        sourcePDF.outlineRoot = outlineRoot
        sourcePDF.documentAttributes = [PDFDocumentAttribute.titleAttribute: "OCR preservation fixture"]
        let sourceData = try XCTUnwrap(PDFSerializer.data(from: sourcePDF))
        let persistedSourcePDF = try XCTUnwrap(PDFDocument(data: sourceData))
        let persistedSourcePage = try XCTUnwrap(persistedSourcePDF.page(at: 0))
        var member = MemberDocument(displayName: "Annotated scan", sourcePDFRef: "annotated.pdf")
        member.pageRefs = [PageRef(memberDocId: member.id, sourcePageIndex: 0).id]

        let result = try await PDFOCRService.searchableData(
            documents: [(member, sourceData)],
            recognitionProvider: { _, _, _ in
                [
                    PDFOCRRecognizedLine(
                        text: "Preserved scan text",
                        normalizedBounds: CGRect(x: 0.20, y: 0.52, width: 0.40, height: 0.08),
                        confidence: 0.95
                    )
                ]
            }
        )

        let outputData = try XCTUnwrap(result.dataByMemberID[member.id])
        let outputPDF = try XCTUnwrap(PDFDocument(data: outputData))
        let outputPage = try XCTUnwrap(outputPDF.page(at: 0))
        XCTAssertEqual(outputPage.rotation, 270)
        assertEqual(outputPage.bounds(for: .mediaBox), persistedSourcePage.bounds(for: .mediaBox))
        assertEqual(outputPage.bounds(for: .cropBox), cropBox)
        XCTAssertEqual(outputPage.annotations.count, persistedSourcePage.annotations.count)
        XCTAssertEqual(
            outputPage.annotations.filter { $0.contents == "Keep this note" }.count,
            persistedSourcePage.annotations.filter { $0.contents == "Keep this note" }.count
        )
        XCTAssertEqual(
            outputPage.annotations.first(where: { $0.fieldName == "Reference number" })?.widgetStringValue,
            "FORM-2048"
        )
        XCTAssertEqual(outputPDF.outlineRoot?.child(at: 0)?.label, "Scanned page")
        XCTAssertEqual(
            outputPDF.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String,
            "OCR preservation fixture"
        )
        XCTAssertFalse(outputPDF.findString("Preserved scan text", withOptions: .caseInsensitive).isEmpty)
        XCTAssertTrue(QPDFService.isStructurallySound(outputData))
        XCTAssertTrue(result.qualityReport.integrityChecksPassed)
    }

    func testSearchableDataReportsLowConfidenceLinesForReview() async throws {
        let sourcePDF = try imageOnlyPDF()
        let sourceData = try XCTUnwrap(PDFSerializer.data(from: sourcePDF))
        var member = MemberDocument(displayName: "Scan", sourcePDFRef: "scan.pdf")
        member.pageRefs = [PageRef(memberDocId: member.id, sourcePageIndex: 0).id]

        let result = try await PDFOCRService.searchableData(
            documents: [(member, sourceData)],
            recognitionProvider: { _, _, _ in
                [
                    PDFOCRRecognizedLine(
                        text: "Certain heading",
                        normalizedBounds: CGRect(x: 0.15, y: 0.72, width: 0.45, height: 0.08),
                        confidence: 0.94
                    ),
                    PDFOCRRecognizedLine(
                        text: "Review this line",
                        normalizedBounds: CGRect(x: 0.15, y: 0.58, width: 0.45, height: 0.08),
                        confidence: 0.45
                    )
                ]
            }
        )

        XCTAssertEqual(result.qualityReport.recognizedLineCount, 2)
        XCTAssertEqual(result.qualityReport.lowConfidenceLineCount, 1)
        XCTAssertEqual(result.qualityReport.averageConfidence, 0.695, accuracy: 0.001)
        XCTAssertTrue(result.qualityReport.needsReview)
    }

    func testOCRLanguageChoiceConfiguresVisionWithoutAutomaticDetection() throws {
        let request = VNRecognizeTextRequest()
        let options = PDFOCROptions(recognitionLanguage: "fr-FR")

        PDFOCRService.configureRecognitionRequest(request, options: options)

        XCTAssertEqual(request.recognitionLanguages, ["fr-FR"])
        XCTAssertFalse(request.automaticallyDetectsLanguage)
        XCTAssertTrue(request.usesLanguageCorrection)
        XCTAssertEqual(request.recognitionLevel, .accurate)
    }

    func testAutomaticOCRLanguageLeavesVisionInDetectionMode() throws {
        let request = VNRecognizeTextRequest()

        PDFOCRService.configureRecognitionRequest(request, options: PDFOCROptions())

        XCTAssertTrue(request.recognitionLanguages.isEmpty)
        XCTAssertTrue(request.automaticallyDetectsLanguage)
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
                options: PDFOCROptions(continuesAfterPageFailure: false),
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

    func testOCRPreservesPageLabelsAndEmbeddedAttachmentsThroughOutput() async throws {
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/page-labels.pdf")
        let attachment = Data("OCR structural lane proof".utf8)
        let labeledAttachmentData = try AttachmentsService.add(
            attachment,
            name: "ocr-proof.txt",
            mimeType: "text/plain",
            to: Data(contentsOf: fixtureURL)
        )
        let rasterOverlay = try XCTUnwrap(PDFSerializer.data(from: try rasterTextPDF("STRUCTURE PROOF")))
        let sourceData = try XCTUnwrap(PDFPageOverlayMergeEngine.merge(
            overlays: (0..<4).map {
                PDFPageOverlayMergeEngine.Overlay(pageIndex: $0, data: rasterOverlay, originX: 0, originY: 0)
            },
            into: labeledAttachmentData
        ))
        let sourcePDF = try XCTUnwrap(PDFDocument(data: sourceData))
        let document = WorkspaceDocument()
        var member = MemberDocument(displayName: "Labeled fixture", sourcePDFRef: "labels.pdf")
        let refs = (0..<sourcePDF.pageCount).map {
            PageRef(memberDocId: member.id, sourcePageIndex: $0)
        }
        member.pageRefs = refs.map(\.id)
        document.workspace.documents = [member]
        document.workspace.pageOrder = refs
        document.memberPDFData[member.id] = sourceData
        let viewModel = WorkspaceViewModel(document: document)

        let prepared = try XCTUnwrap(viewModel.currentPDFDataForOCR()[member.id])
        let result = try await PDFOCRService.searchableData(
            documents: [(member, prepared)],
            options: PDFOCROptions(pageSelection: .allVisiblePages),
            recognitionProvider: { _, pageNumber, _ in
                [
                    PDFOCRRecognizedLine(
                        text: "OCR overlay page \(pageNumber)",
                        normalizedBounds: CGRect(x: 0.15, y: 0.65, width: 0.45, height: 0.08),
                        confidence: 0.95
                    )
                ]
            }
        )
        let output = try XCTUnwrap(result.dataByMemberID[member.id])
        let outputPDF = try XCTUnwrap(PDFDocument(data: output))

        XCTAssertTrue(QPDFService.hasPageLabels(output))
        XCTAssertEqual(outputPDF.page(at: 0)?.label, "i")
        XCTAssertEqual(outputPDF.page(at: 1)?.label, "ii")
        XCTAssertEqual(outputPDF.page(at: 2)?.label, "1")
        XCTAssertEqual(outputPDF.page(at: 3)?.label, "A-7")
        XCTAssertEqual(try AttachmentsService.extract("ocr-proof.txt", from: output), attachment)
        XCTAssertFalse(outputPDF.findString("OCR overlay page 4", withOptions: .caseInsensitive).isEmpty)
        XCTAssertTrue(QPDFService.isStructurallySound(output))
        XCTAssertTrue(result.qualityReport.integrityChecksPassed)
    }

    func testViewModelBlocksOCRWhenCommittedTextEditsWouldBeReplayed() throws {
        let document = WorkspaceDocument()
        try document.importPDFDocumentForTesting(try imageOnlyPDF(), filename: "edited-scan.pdf")
        let viewModel = WorkspaceViewModel(document: document)
        let pageRefID = try XCTUnwrap(viewModel.loadedPDFs.first?.0.pageRefs.first)
        document.workspace.pageEditStates = [
            PageEditState(pageRefID: pageRefID, operations: [
                PDFTextEditOperation(
                    pageRefID: pageRefID,
                    sourceBlockID: UUID(),
                    sourceBounds: .zero,
                    sourceText: "Original",
                    editedBounds: .zero,
                    replacementText: "Edited",
                    fontName: "Helvetica",
                    fontSize: 12,
                    textColor: .documentText,
                    alignment: .left
                )
            ])
        ]

        XCTAssertTrue(viewModel.hasCommittedEditsBlockingOCR)
        XCTAssertFalse(viewModel.canStartConfiguredOCR)
        viewModel.makeSearchable()
        XCTAssertFalse(viewModel.isMakingSearchable)
        XCTAssertNil(viewModel.lastOCRQualityReport)
        XCTAssertEqual(viewModel.editingStatus?.severity, .warning)
        XCTAssertEqual(viewModel.editingStatus?.message, L10n.string("status.ocr.finishEditsBeforeOCR"))
    }

    func testScanBannerRouteStaysScannedOnlyWhenInspectorIsSetToAllVisible() throws {
        let document = WorkspaceDocument()
        try document.importPDFDocumentForTesting(try textPDF("Existing searchable text"), filename: "text.pdf")
        let viewModel = WorkspaceViewModel(document: document)
        viewModel.ocrPageSelection = .allVisiblePages

        XCTAssertEqual(viewModel.scannedPageCount, 0)
        XCTAssertGreaterThan(viewModel.ocrCandidatePageCount, 0)
        viewModel.makeScannedPagesSearchable()

        XCTAssertFalse(viewModel.isMakingSearchable)
        XCTAssertNil(viewModel.lastOCRQualityReport)
    }

    func testCancellationAtApplyBoundaryKeepsBytesAndPreviousReceipt() async throws {
        let document = WorkspaceDocument()
        try document.importPDFDocumentForTesting(try rasterTextPDF("FOLD TOKEN 8146"), filename: "cancel.pdf")
        let viewModel = WorkspaceViewModel(document: document)
        installDeterministicOCR(on: viewModel, text: "FOLD TOKEN 8146")

        viewModel.makeSearchable()
        for _ in 0..<240 where viewModel.isMakingSearchable {
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        let priorReport = try XCTUnwrap(viewModel.lastOCRQualityReport)
        let member = try XCTUnwrap(viewModel.loadedPDFs.first?.0)
        let priorData = try XCTUnwrap(document.memberPDFData[member.id])

        viewModel.ocrPageSelection = .allVisiblePages
        viewModel.ocrResultReadyHandlerForTesting = { [weak viewModel] in
            viewModel?.cancelActiveOperation()
        }
        viewModel.makeSearchable()
        for _ in 0..<240 where viewModel.isMakingSearchable {
            try await Task.sleep(nanoseconds: 25_000_000)
        }

        XCTAssertFalse(viewModel.isMakingSearchable)
        XCTAssertEqual(document.memberPDFData[member.id], priorData)
        XCTAssertEqual(viewModel.lastOCRQualityReport, priorReport)
        XCTAssertEqual(viewModel.editingStatus?.severity, .warning)
    }

    func testLaterPageMutationInvalidatesReceiptAndUndoRestoresIt() async throws {
        let document = WorkspaceDocument()
        try document.importPDFDocumentForTesting(try rasterTextPDF("FOLD TOKEN 9631"), filename: "receipt.pdf")
        let viewModel = WorkspaceViewModel(document: document)
        installDeterministicOCR(on: viewModel, text: "FOLD TOKEN 9631")
        let undoManager = UndoManager()
        viewModel.undoManager = undoManager

        viewModel.makeSearchable()
        for _ in 0..<240 where viewModel.isMakingSearchable {
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        let report = try XCTUnwrap(viewModel.lastOCRQualityReport)
        let pageRef = try XCTUnwrap(document.workspace.pageOrder.first)

        viewModel.rotatePage(pageRef, by: 90)
        XCTAssertNil(viewModel.lastOCRQualityReport)

        undoManager.undo()
        XCTAssertEqual(viewModel.lastOCRQualityReport, report)
    }

    func testOCRUndoRedoPreservesPageLabelsAndEmbeddedAttachment() async throws {
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/page-labels.pdf")
        let attachment = Data("OCR undo structural proof".utf8)
        let labeledAttachmentData = try AttachmentsService.add(
            attachment,
            name: "ocr-undo-proof.txt",
            mimeType: "text/plain",
            to: Data(contentsOf: fixtureURL)
        )
        let rasterOverlay = try XCTUnwrap(PDFSerializer.data(from: try rasterTextPDF("STRUCTURE TOKEN 6428")))
        let sourceData = try XCTUnwrap(PDFPageOverlayMergeEngine.merge(
            overlays: (0..<4).map {
                PDFPageOverlayMergeEngine.Overlay(pageIndex: $0, data: rasterOverlay, originX: 0, originY: 0)
            },
            into: labeledAttachmentData
        ))
        let sourcePDF = try XCTUnwrap(PDFDocument(data: sourceData))
        let document = WorkspaceDocument()
        var member = MemberDocument(displayName: "Undo structure", sourcePDFRef: "undo-structure.pdf")
        let refs = (0..<sourcePDF.pageCount).map { PageRef(memberDocId: member.id, sourcePageIndex: $0) }
        member.pageRefs = refs.map(\.id)
        document.workspace.documents = [member]
        document.workspace.pageOrder = refs
        document.memberPDFData[member.id] = sourceData
        let viewModel = WorkspaceViewModel(document: document)
        installDeterministicOCR(on: viewModel, text: "STRUCTURE TOKEN 6428")
        let undoManager = UndoManager()
        viewModel.undoManager = undoManager
        viewModel.ocrPageSelection = .allVisiblePages

        viewModel.makeSearchable()
        for _ in 0..<480 where viewModel.isMakingSearchable {
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        let recognizedData = try XCTUnwrap(document.memberPDFData[member.id])
        XCTAssertTrue(QPDFService.hasPageLabels(recognizedData))
        XCTAssertEqual(try AttachmentsService.extract("ocr-undo-proof.txt", from: recognizedData), attachment)
        XCTAssertTrue(stableOCRText(in: recognizedData).contains("STRUCTURE TOKEN 6428"))

        undoManager.undo()
        let undoneData = try XCTUnwrap(document.memberPDFData[member.id])
        XCTAssertTrue(QPDFService.hasPageLabels(undoneData))
        XCTAssertEqual(try AttachmentsService.extract("ocr-undo-proof.txt", from: undoneData), attachment)
        XCTAssertFalse(stableOCRText(in: undoneData).contains("STRUCTURE TOKEN 6428"))

        undoManager.redo()
        let redoneData = try XCTUnwrap(document.memberPDFData[member.id])
        XCTAssertTrue(QPDFService.hasPageLabels(redoneData))
        XCTAssertEqual(try AttachmentsService.extract("ocr-undo-proof.txt", from: redoneData), attachment)
        XCTAssertTrue(stableOCRText(in: redoneData).contains("STRUCTURE TOKEN 6428"))
    }

    func testOCRUndoRedoRestoresChangedBytesExactlyAndNeverRewritesUntouchedMember() async throws {
        let scannedData = try XCTUnwrap(PDFSerializer.data(from: try rasterTextPDF("FOLD TOKEN 5194")))
        let untouchedAttachment = Data("untouched member proof".utf8)
        let searchableData = try AttachmentsService.add(
            untouchedAttachment,
            name: "untouched.txt",
            mimeType: "text/plain",
            to: try XCTUnwrap(PDFSerializer.data(from: try textPDF("Already searchable")))
        )
        var scannedMember = MemberDocument(displayName: "Scan", sourcePDFRef: "scan.pdf")
        let scannedRef = PageRef(memberDocId: scannedMember.id, sourcePageIndex: 0)
        scannedMember.pageRefs = [scannedRef.id]
        var untouchedMember = MemberDocument(displayName: "Searchable", sourcePDFRef: "searchable.pdf")
        let untouchedRef = PageRef(memberDocId: untouchedMember.id, sourcePageIndex: 0)
        untouchedMember.pageRefs = [untouchedRef.id]
        let document = WorkspaceDocument()
        document.workspace.documents = [scannedMember, untouchedMember]
        document.workspace.pageOrder = [scannedRef, untouchedRef]
        document.memberPDFData = [scannedMember.id: scannedData, untouchedMember.id: searchableData]
        let viewModel = WorkspaceViewModel(document: document)
        installDeterministicOCR(on: viewModel, text: "FOLD TOKEN 5194")
        let undoManager = UndoManager()
        viewModel.undoManager = undoManager

        viewModel.makeScannedPagesSearchable()
        for _ in 0..<240 where viewModel.isMakingSearchable {
            try await Task.sleep(nanoseconds: 25_000_000)
        }

        XCTAssertNotEqual(document.memberPDFData[scannedMember.id], scannedData)
        XCTAssertEqual(document.memberPDFData[untouchedMember.id], searchableData)
        XCTAssertEqual(
            try AttachmentsService.extract(
                "untouched.txt",
                from: try XCTUnwrap(document.memberPDFData[untouchedMember.id])
            ),
            untouchedAttachment
        )

        undoManager.undo()
        XCTAssertEqual(document.memberPDFData[scannedMember.id], scannedData)
        XCTAssertEqual(document.memberPDFData[untouchedMember.id], searchableData)

        undoManager.redo()
        XCTAssertTrue(
            stableOCRText(in: try XCTUnwrap(document.memberPDFData[scannedMember.id]))
                .contains("FOLD TOKEN 5194")
        )
        XCTAssertEqual(document.memberPDFData[untouchedMember.id], searchableData)
    }

    func testProductionVisionOCRIsSearchableAfterSaveReopenAndReceiptFollowsUndoRedo() async throws {
        let phrase = "FOLD TOKEN 7429"
        let document = WorkspaceDocument()
        let sourcePDF = try rasterTextPDF(phrase)
        try XCTUnwrap(sourcePDF.page(at: 0)).rotation = 90
        try document.importPDFDocumentForTesting(sourcePDF, filename: "vision-scan.pdf")
        let viewModel = WorkspaceViewModel(document: document)
        let undoManager = UndoManager()
        viewModel.undoManager = undoManager

        XCTAssertTrue(viewModel.hasScannedPages)
        viewModel.makeSearchable()
        for _ in 0..<200 where viewModel.isMakingSearchable {
            try await Task.sleep(nanoseconds: 25_000_000)
        }

        XCTAssertFalse(viewModel.isMakingSearchable)
        let report = try XCTUnwrap(viewModel.lastOCRQualityReport)
        XCTAssertTrue(report.integrityChecksPassed)
        let member = try XCTUnwrap(viewModel.loadedPDFs.first?.0)
        let searchableData = try XCTUnwrap(document.memberPDFData[member.id])
        let reopened = try XCTUnwrap(PDFDocument(data: searchableData))
        XCTAssertEqual(reopened.page(at: 0)?.rotation, 90)
        XCTAssertFalse(reopened.findString(phrase, withOptions: .caseInsensitive).isEmpty)

        undoManager.undo()
        XCTAssertNil(viewModel.lastOCRQualityReport)
        let undoneData = try XCTUnwrap(document.memberPDFData[member.id])
        XCTAssertTrue(stableOCRText(in: undoneData).isEmpty)

        undoManager.redo()
        XCTAssertEqual(viewModel.lastOCRQualityReport, report)
        let redonePDF = try XCTUnwrap(viewModel.loadedPDFs.first?.1)
        XCTAssertFalse(redonePDF.findString(phrase, withOptions: .caseInsensitive).isEmpty)
    }

    func testProductionVisionOCRRecognizesCounterclockwiseQuarterTurn() async throws {
        let phrase = "FOLD TOKEN 2753"
        let document = WorkspaceDocument()
        let sourcePDF = try rasterTextPDF(phrase)
        try XCTUnwrap(sourcePDF.page(at: 0)).rotation = 270
        try document.importPDFDocumentForTesting(sourcePDF, filename: "vision-scan-270.pdf")
        let viewModel = WorkspaceViewModel(document: document)

        viewModel.makeSearchable()
        for _ in 0..<200 where viewModel.isMakingSearchable {
            try await Task.sleep(nanoseconds: 25_000_000)
        }

        XCTAssertFalse(viewModel.isMakingSearchable)
        XCTAssertTrue(try XCTUnwrap(viewModel.lastOCRQualityReport).integrityChecksPassed)
        let member = try XCTUnwrap(viewModel.loadedPDFs.first?.0)
        let searchableData = try XCTUnwrap(document.memberPDFData[member.id])
        let reopened = try XCTUnwrap(PDFDocument(data: searchableData))
        XCTAssertEqual(reopened.page(at: 0)?.rotation, 270)
        XCTAssertFalse(reopened.findString(phrase, withOptions: .caseInsensitive).isEmpty)
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

private func rasterTextPDF(_ text: String) throws -> PDFDocument {
    let pixelWidth = 1_224
    let pixelHeight = 1_584
    let bitmap = try XCTUnwrap(NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelWidth,
        pixelsHigh: pixelHeight,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ))
    let graphicsContext = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphicsContext
    NSColor.white.setFill()
    CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight).fill()
    text.draw(
        at: CGPoint(x: 150, y: 800),
        withAttributes: [
            .font: NSFont.systemFont(ofSize: 72, weight: .bold),
            .foregroundColor: NSColor.black
        ]
    )
    graphicsContext.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    let image = NSImage(size: CGSize(width: pixelWidth, height: pixelHeight))
    image.addRepresentation(bitmap)
    let view = OCRRasterTextFixtureView(
        frame: CGRect(x: 0, y: 0, width: 612, height: 792),
        image: image
    )
    let data = view.dataWithPDF(inside: view.bounds)
    let document = try XCTUnwrap(PDFDocument(data: data))
    XCTAssertTrue(stableOCRText(in: data).isEmpty)
    return document
}

private func stableOCRText(in data: Data, pageIndex: Int = 0) -> String {
    PDFTextAnalysisEngine()
        .analyze(data: data, pageIndex: pageIndex, pageRefID: UUID(), fallbackPage: nil)
        .blocks
        .map(\.text)
        .joined(separator: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
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

private func assertEqual(
    _ lhs: CGRect,
    _ rhs: CGRect,
    accuracy: CGFloat = 0.01,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertEqual(lhs.minX, rhs.minX, accuracy: accuracy, file: file, line: line)
    XCTAssertEqual(lhs.minY, rhs.minY, accuracy: accuracy, file: file, line: line)
    XCTAssertEqual(lhs.width, rhs.width, accuracy: accuracy, file: file, line: line)
    XCTAssertEqual(lhs.height, rhs.height, accuracy: accuracy, file: file, line: line)
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

private final class OCRRasterTextFixtureView: NSView {
    private let image: NSImage

    init(frame frameRect: NSRect, image: NSImage) {
        self.image = image
        super.init(frame: frameRect)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        bounds.fill()
        image.draw(in: bounds)
    }
}
