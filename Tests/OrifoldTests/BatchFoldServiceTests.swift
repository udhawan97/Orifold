import AppKit
import PDFKit
import XCTest
@testable import Orifold

@MainActor
final class BatchFoldServiceTests: XCTestCase {
    // MARK: - Output naming (pure)

    func testOutputNameAppendsFoldedSuffix() {
        let name = BatchFoldService.outputName(
            for: URL(fileURLWithPath: "/tmp/Quarterly Report.pdf"),
            existingNames: []
        )
        XCTAssertEqual(name, "Quarterly Report-folded.pdf")
    }

    func testOutputNameResolvesCollisionsCaseInsensitively() {
        let source = URL(fileURLWithPath: "/tmp/report.pdf")
        XCTAssertEqual(
            BatchFoldService.outputName(for: source, existingNames: ["Report-Folded.pdf"]),
            "report-folded-2.pdf"
        )
        XCTAssertEqual(
            BatchFoldService.outputName(
                for: source,
                existingNames: ["report-folded.pdf", "report-folded-2.pdf"]
            ),
            "report-folded-3.pdf"
        )
    }

    func testPDFURLsKeepsOnlyPDFExtensions() {
        let scan = FolderScanResult(
            supportedURLs: [
                URL(fileURLWithPath: "/tmp/a.pdf"),
                URL(fileURLWithPath: "/tmp/b.PNG"),
                URL(fileURLWithPath: "/tmp/c.PDF"),
                URL(fileURLWithPath: "/tmp/d.docx")
            ],
            unsupportedCount: 0,
            wasTruncated: false
        )
        XCTAssertEqual(
            BatchFoldService.pdfURLs(from: scan).map(\.lastPathComponent),
            ["a.pdf", "c.PDF"]
        )
    }

    // MARK: - Per-file pipeline

    func testEmptyOptionsFoldReturnsInputBytesUnchanged() async throws {
        let input = try whitePDFData(pages: 1)
        let output = try await BatchFoldService.fold(
            input,
            fileName: "blank.pdf",
            options: BatchFoldService.Options()
        )
        XCTAssertEqual(output, input)
    }

    func testWatermarkFoldInksEveryPageAndPreservesPageCount() async throws {
        let input = try whitePDFData(pages: 2)
        var options = BatchFoldService.Options()
        options.watermarkText = "CONFIDENTIAL"

        let output = try await BatchFoldService.fold(input, fileName: "white.pdf", options: options)

        let outputPDF = try XCTUnwrap(PDFDocument(data: output))
        XCTAssertEqual(outputPDF.pageCount, 2)
        for pageIndex in 0..<2 {
            let before = try inkCoverage(of: input, pageIndex: pageIndex)
            let after = try inkCoverage(of: output, pageIndex: pageIndex)
            XCTAssertGreaterThan(after, before, "page \(pageIndex) should carry the baked watermark")
        }
        XCTAssertTrue(QPDFService.isStructurallySound(output))
    }

    func testOCRFoldAddsSearchableTextViaInjectedProvider() async throws {
        let input = try whitePDFData(pages: 1, speckled: true)
        var options = BatchFoldService.Options()
        options.runsOCR = true

        let output = try await BatchFoldService.fold(
            input,
            fileName: "scan.pdf",
            options: options,
            recognitionProvider: { _, _, _ in
                [
                    PDFOCRRecognizedLine(
                        text: "Folded stack phrase",
                        normalizedBounds: CGRect(x: 0.2, y: 0.4, width: 0.5, height: 0.1),
                        confidence: 0.9
                    )
                ]
            }
        )

        let outputPDF = try XCTUnwrap(PDFDocument(data: output))
        XCTAssertEqual(outputPDF.pageCount, 1)
        XCTAssertFalse(outputPDF.findString("Folded stack phrase", withOptions: .caseInsensitive).isEmpty)
        XCTAssertTrue(QPDFService.isStructurallySound(output))
    }

    func testOCRFoldKeepsWorkingWhenNothingIsRecognized() async throws {
        let input = try whitePDFData(pages: 1)
        var options = BatchFoldService.Options()
        options.runsOCR = true

        let output = try await BatchFoldService.fold(
            input,
            fileName: "blank.pdf",
            options: options,
            recognitionProvider: { _, _, _ in [] }
        )

        let outputPDF = try XCTUnwrap(PDFDocument(data: output))
        XCTAssertEqual(outputPDF.pageCount, 1)
        XCTAssertTrue(QPDFService.isStructurallySound(output))
    }

    // MARK: - Batch run

    func testRunWritesFoldedOutputsAndIsolatesFailures() async throws {
        let folder = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let goodA = folder.appendingPathComponent("a.pdf")
        let badB = folder.appendingPathComponent("b.pdf")
        let goodC = folder.appendingPathComponent("c.pdf")
        try whitePDFData(pages: 1).write(to: goodA)
        try Data("not a pdf at all".utf8).write(to: badB)
        try whitePDFData(pages: 1).write(to: goodC)

        var options = BatchFoldService.Options()
        options.watermarkText = "DRAFT"

        let result = await BatchFoldService.run(
            inputFolder: folder,
            files: [goodA, badB, goodC],
            options: options,
            progress: { _, _ in },
            isCancelled: { false }
        )

        XCTAssertEqual(result.foldedCount, 2)
        XCTAssertEqual(result.failedCount, 1)
        XCTAssertFalse(result.wasCancelled)
        let outputDirectory = try XCTUnwrap(result.outputDirectory)
        XCTAssertEqual(outputDirectory.lastPathComponent, BatchFoldService.outputFolderName)
        XCTAssertEqual(outputDirectory.deletingLastPathComponent().path, folder.path)
        let written = try FileManager.default.contentsOfDirectory(atPath: outputDirectory.path).sorted()
        XCTAssertEqual(written, ["a-folded.pdf", "c-folded.pdf"])
        if case .failed = result.outcomes[1].result {} else {
            XCTFail("the unreadable file should be the failed outcome")
        }
    }

    func testRunAvoidsOverwritingEarlierResults() async throws {
        let folder = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("a.pdf")
        try whitePDFData(pages: 1).write(to: source)
        let outputDirectory = folder.appendingPathComponent(BatchFoldService.outputFolderName)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let earlier = outputDirectory.appendingPathComponent("a-folded.pdf")
        try Data("earlier run".utf8).write(to: earlier)

        var options = BatchFoldService.Options()
        options.watermarkText = "DRAFT"

        let result = await BatchFoldService.run(
            inputFolder: folder,
            files: [source],
            options: options,
            progress: { _, _ in },
            isCancelled: { false }
        )

        XCTAssertEqual(result.foldedCount, 1)
        XCTAssertEqual(try Data(contentsOf: earlier), Data("earlier run".utf8))
        let written = try FileManager.default.contentsOfDirectory(atPath: outputDirectory.path).sorted()
        XCTAssertEqual(written, ["a-folded-2.pdf", "a-folded.pdf"])
    }

    func testRunStopsBetweenFilesWhenCancelled() async throws {
        let folder = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        var files: [URL] = []
        for name in ["a.pdf", "b.pdf", "c.pdf"] {
            let url = folder.appendingPathComponent(name)
            try whitePDFData(pages: 1).write(to: url)
            files.append(url)
        }
        let outputDirectory = folder.appendingPathComponent(BatchFoldService.outputFolderName)

        var options = BatchFoldService.Options()
        options.watermarkText = "DRAFT"

        // Cancels as soon as the first result lands, which `run` observes at the next
        // between-files check — deterministic without any timing games.
        let result = await BatchFoldService.run(
            inputFolder: folder,
            files: files,
            options: options,
            progress: { _, _ in },
            isCancelled: {
                let written = (try? FileManager.default.contentsOfDirectory(atPath: outputDirectory.path)) ?? []
                return !written.isEmpty
            }
        )

        XCTAssertTrue(result.wasCancelled)
        XCTAssertEqual(result.foldedCount, 1)
        XCTAssertLessThan(result.outcomes.count, files.count)
    }

    // MARK: - Fixtures

    private func makeTempFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("BatchFoldServiceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func whitePDFData(pages: Int, speckled: Bool = false) throws -> Data {
        let pdf = PDFDocument()
        for index in 0..<pages {
            let size = CGSize(width: 400, height: 400)
            let image = NSImage(size: size)
            image.lockFocus()
            NSColor.white.setFill()
            NSRect(origin: .zero, size: size).fill()
            if speckled {
                NSColor.black.setFill()
                var seed: UInt64 = 42
                for _ in 0..<160 {
                    seed = seed &* 6364136223846793005 &+ 1442695040888963407
                    let x = CGFloat(seed % 380) + 10
                    let y = CGFloat((seed >> 16) % 380) + 10
                    NSRect(x: x, y: y, width: 2, height: 2).fill()
                }
            }
            image.unlockFocus()
            let page = try XCTUnwrap(PDFPage(image: image))
            pdf.insert(page, at: index)
        }
        return try XCTUnwrap(PDFSerializer.data(from: pdf))
    }

    /// Fraction of sampled pixels that are visibly non-white — the sanctioned ink check
    /// (never `PDFPage.string`; see PDFPageStringGuardTests).
    private func inkCoverage(of data: Data, pageIndex: Int) throws -> Double {
        let pdf = try XCTUnwrap(PDFDocument(data: data))
        let page = try XCTUnwrap(pdf.page(at: pageIndex))
        let bounds = page.bounds(for: .mediaBox)
        let thumbnail = page.thumbnail(of: CGSize(width: bounds.width, height: bounds.height), for: .mediaBox)
        let tiff = try XCTUnwrap(thumbnail.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))

        var inked = 0
        var sampled = 0
        for px in stride(from: 0, to: bitmap.pixelsWide, by: 7) {
            for py in stride(from: 0, to: bitmap.pixelsHigh, by: 7) {
                guard let color = bitmap.colorAt(x: px, y: py)?.usingColorSpace(.deviceRGB) else { continue }
                sampled += 1
                if color.brightnessComponent < 0.85 { inked += 1 }
            }
        }
        guard sampled > 0 else { return 0 }
        return Double(inked) / Double(sampled)
    }
}
