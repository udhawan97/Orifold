import PDFKit
import UniformTypeIdentifiers
import XCTest
@testable import Orifold

/// Hardening sweep for the PDF import path: feeds a battery of malformed,
/// truncated, and structurally-adversarial byte sequences through the same
/// entry point real imports use, and asserts the pipeline never crashes --
/// only ever succeeds cleanly or fails with a typed `ConversionError`. This
/// is the local, always-run equivalent of fuzzing against public malformed-
/// PDF corpora (pdf.js's and qpdf's test suites take the same approach):
/// import must be bulletproof against garbage input, not just clean ones.
final class ImportStressTests: XCTestCase {
    private var localFixtureDirectory: URL {
        URL(fileURLWithPath: "/Users/umang/Documents/development/test-files", isDirectory: true)
    }

    private var localPDFImportFixtureURLs: [URL] {
        [
            "01-searchable-text-long-multipage 2.pdf",
            "01-searchable-text-long-multipage.pdf",
            "02-mixed-page-sizes-orientations 2.pdf",
            "02-mixed-page-sizes-orientations.pdf",
            "03-image-vector-transparency-stress 2.pdf",
            "03-image-vector-transparency-stress.pdf",
            "04-acroform-fields.pdf",
            "05-dense-table-and-edge-content.pdf",
            "06-links-comments-annotations.pdf",
            "07-password-protected-password-pdfold.pdf",
            "08-large-canvas-blueprint-page.pdf",
        ].map { localFixtureDirectory.appendingPathComponent($0) }
    }

    private var localUnlockedPDFImportFixtureURLs: [URL] {
        localPDFImportFixtureURLs.filter { !$0.lastPathComponent.hasPrefix("07-password-protected") }
    }

    private func assertNeverCrashes(_ data: Data, file: StaticString = #filePath, line: UInt = #line) {
        do {
            let imported = try DocumentImportConverter.importedDocument(
                from: data,
                contentType: .pdf,
                filename: "stress.pdf",
                baseURL: nil
            )
            XCTAssertGreaterThan(imported.pdfDocument.pageCount, 0, "a document reported as imported must have pages", file: file, line: line)
        } catch is DocumentImportConverter.ConversionError {
            // Expected outcome for genuinely unrecoverable input.
        } catch {
            XCTFail("unexpected error type: \(error)", file: file, line: line)
        }
    }

    func testTruncationSweepOfAValidMultiPageDocumentNeverCrashes() throws {
        let pdf = PDFDocument()
        for index in 0..<6 {
            let view = NSView(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
            let page = try XCTUnwrap(PDFDocument(data: view.dataWithPDF(inside: view.bounds))?.page(at: 0))
            pdf.insert(page, at: index)
        }
        let full = try XCTUnwrap(pdf.dataRepresentation())

        // Truncate at every 5% boundary -- covers cutting mid-header, mid-object,
        // mid-stream, mid-xref, and mid-trailer without a 6600-byte-by-byte sweep.
        for percent in stride(from: 5, through: 95, by: 5) {
            let cutoff = full.count * percent / 100
            assertNeverCrashes(full.prefix(cutoff))
        }
    }

    func testByteFlipSweepOfAValidDocumentNeverCrashes() throws {
        let pdf = PDFDocument()
        pdf.insert(try XCTUnwrap(makeSinglePagePDF()), at: 0)
        let original = try XCTUnwrap(pdf.dataRepresentation())

        // Flip one byte at a time across evenly spaced offsets. A single bit
        // flip in the xref table, an object header, or the trailer is exactly
        // the class of corruption real-world "the download got interrupted"
        // or "the disk had a bad sector" bugs produce.
        let stride = max(1, original.count / 40)
        for offset in Swift.stride(from: 0, to: original.count, by: stride) {
            var mutated = original
            mutated[offset] = mutated[offset] ^ 0xFF
            assertNeverCrashes(mutated)
        }
    }

    func testStructurallyAdversarialFixturesNeverCrash() {
        let fixtures: [Data] = [
            Data(), // empty
            Data("%PDF-1.4".utf8), // header only
            Data("%PDF-1.4\n%%EOF".utf8), // header + EOF, no objects
            Data("not a pdf at all, just text".utf8),
            Data(repeating: 0, count: 4096), // all zero bytes
            Data((0..<4096).map { UInt8($0 % 256) }), // pseudo-random binary
            // Trailer references a Root object that doesn't exist.
            Data("""
            %PDF-1.4
            1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj
            trailer<</Root 99 0 R/Size 100>>
            %%EOF
            """.utf8),
            // Circular Pages reference (Pages points to itself as a Kid).
            Data("""
            %PDF-1.4
            1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj
            2 0 obj<</Type/Pages/Kids[2 0 R]/Count 1>>endobj
            trailer<</Root 1 0 R/Size 3>>
            %%EOF
            """.utf8),
            // Page claims a stream /Length far larger than the actual data.
            Data("""
            %PDF-1.4
            1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj
            2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj
            3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 200 200]/Contents 4 0 R>>endobj
            4 0 obj<</Length 999999999>>stream
            short
            endstream endobj
            trailer<</Root 1 0 R/Size 5>>
            %%EOF
            """.utf8),
            // Negative and absurdly large object/generation numbers in xref-like text.
            Data("""
            %PDF-1.4
            1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj
            2 0 obj<</Type/Pages/Kids[3 0 R]/Count -1>>endobj
            3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 -100 999999999]>>endobj
            trailer<</Root 1 0 R/Size 4>>
            %%EOF
            """.utf8),
            // Deeply nested arrays, a classic stack-overflow-by-parser probe.
            Data("%PDF-1.4\n1 0 obj\(String(repeating: "[", count: 5000))1\(String(repeating: "]", count: 5000))endobj\ntrailer<</Root 1 0 R/Size 2>>\n%%EOF".utf8),
        ]

        for fixture in fixtures {
            assertNeverCrashes(fixture)
        }
    }

    func testQPDFServiceNeverCrashesOnTheSameAdversarialFixtures() {
        let fixtures: [Data] = [
            Data(),
            Data("%PDF-1.4".utf8),
            Data(repeating: 0, count: 4096),
            Data((0..<4096).map { UInt8($0 % 256) }),
            Data("%PDF-1.4\n1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj\ntrailer<</Root 99 0 R/Size 100>>\n%%EOF".utf8),
        ]
        for fixture in fixtures {
            _ = QPDFService.repaired(fixture)
            _ = QPDFService.isStructurallySound(fixture)
            _ = QPDFService.optimized(fixture, linearize: false)
            _ = QPDFService.sanitized(fixture, removingMetadata: true)
            // Reaching this line without a crash is the assertion.
        }
    }

    func testLocalImportFixturesOpenThroughConverter() throws {
        try XCTSkipUnless(FileManager.default.fileExists(atPath: localFixtureDirectory.path), "Local import fixtures are not present.")

        for url in localPDFImportFixtureURLs {
            let imported = try DocumentImportConverter.importedDocument(from: url)
            if url.lastPathComponent.hasPrefix("07-password-protected") {
                XCTAssertTrue(imported.pdfDocument.isLocked, url.lastPathComponent)
            } else {
                XCTAssertFalse(imported.pdfDocument.isLocked, url.lastPathComponent)
                XCTAssertGreaterThan(imported.pdfDocument.pageCount, 0, url.lastPathComponent)
            }
        }
    }

    func testLocalPasswordProtectedFixtureDirectOpenReturnsPasswordSpecificError() throws {
        try XCTSkipUnless(FileManager.default.fileExists(atPath: localFixtureDirectory.path), "Local import fixtures are not present.")
        let protectedURL = localFixtureDirectory.appendingPathComponent("07-password-protected-password-pdfold.pdf")
        let file = FileWrapper(regularFileWithContents: try Data(contentsOf: protectedURL))

        XCTAssertThrowsError(try WorkspaceDocument(testingFile: file, contentType: .pdf, filename: protectedURL.lastPathComponent)) { error in
            guard case DocumentImportConverter.ConversionError.passwordProtected = error else {
                return XCTFail("Expected passwordProtected, got \(error)")
            }
        }
    }

    @MainActor
    func testLocalImportFixturesImportAsOneBatchAndPromptForPasswordProtectedPDF() async throws {
        try XCTSkipUnless(FileManager.default.fileExists(atPath: localFixtureDirectory.path), "Local import fixtures are not present.")
        let viewModel = WorkspaceViewModel(document: WorkspaceDocument(), processingEngine: PDFKitProcessingEngineFallback())

        viewModel.importFiles(urls: localPDFImportFixtureURLs)
        try await waitForLocalImportToFinish(in: viewModel)

        let expectedUnlockedPageCount = try localUnlockedPDFImportFixtureURLs.reduce(0) { total, url in
            try total + DocumentImportConverter.importedDocument(from: url).pdfDocument.pageCount
        }
        XCTAssertNil(viewModel.importError)
        XCTAssertEqual(viewModel.memberDocuments.map(\.displayName), localUnlockedPDFImportFixtureURLs.map { $0.deletingPathExtension().lastPathComponent })
        XCTAssertEqual(viewModel.pageCount, expectedUnlockedPageCount)
        XCTAssertTrue(viewModel.isShowingPasswordPrompt)
        XCTAssertEqual(viewModel.pendingPasswordURL?.lastPathComponent, "07-password-protected-password-pdfold.pdf")

        let pendingPDF = try XCTUnwrap(viewModel.pendingPasswordPDF)
        XCTAssertTrue(viewModel.unlock(pdf: pendingPDF, password: "pdfold", url: localPDFImportFixtureURLs[9]))
        XCTAssertNil(viewModel.pendingPasswordPDF)
        XCTAssertEqual(viewModel.memberDocuments.map(\.displayName), localPDFImportFixtureURLs.map { $0.deletingPathExtension().lastPathComponent })
    }

    @MainActor
    func testMultiplePasswordProtectedImportsUnlockSequentiallyWithoutLosingBatchOrder() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Orifold-locked-batch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let plainA = try writeSinglePagePDF(named: "plain-a.pdf", in: tempDirectory)
        let lockedA = try writeEncryptedSinglePagePDF(named: "locked-a.pdf", password: "first", in: tempDirectory)
        let plainB = try writeSinglePagePDF(named: "plain-b.pdf", in: tempDirectory)
        let lockedB = try writeEncryptedSinglePagePDF(named: "locked-b.pdf", password: "second", in: tempDirectory)
        let viewModel = WorkspaceViewModel(document: WorkspaceDocument(), processingEngine: PDFKitProcessingEngineFallback())

        viewModel.importFiles(urls: [plainA, lockedA, plainB, lockedB])
        try await waitForLocalImportToFinish(in: viewModel)

        XCTAssertEqual(viewModel.memberDocuments.map(\.displayName), ["plain-a", "plain-b"])
        XCTAssertEqual(viewModel.pendingPasswordURL?.lastPathComponent, "locked-a.pdf")
        XCTAssertTrue(viewModel.unlock(pdf: try XCTUnwrap(viewModel.pendingPasswordPDF), password: "first", url: lockedA))
        XCTAssertEqual(viewModel.pendingPasswordURL?.lastPathComponent, "locked-b.pdf")
        XCTAssertTrue(viewModel.unlock(pdf: try XCTUnwrap(viewModel.pendingPasswordPDF), password: "second", url: lockedB))
        XCTAssertNil(viewModel.pendingPasswordPDF)
        XCTAssertEqual(viewModel.memberDocuments.map(\.displayName), ["plain-a", "locked-a", "plain-b", "locked-b"])
    }

    @MainActor
    func testPasswordProtectedImportPreservesTargetedInsertionAfterUnlock() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Orifold-locked-target-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let document = WorkspaceDocument()
        let first = try makeSinglePageMember(named: "Existing A")
        let second = try makeSinglePageMember(named: "Existing B")
        document.workspace.documents = [first.member, second.member]
        document.workspace.pageOrder = first.refs + second.refs
        document.memberPDFData[first.member.id] = first.data
        document.memberPDFData[second.member.id] = second.data
        let locked = try writeEncryptedSinglePagePDF(named: "locked-target.pdf", password: "target", in: tempDirectory)
        let viewModel = WorkspaceViewModel(document: document, processingEngine: PDFKitProcessingEngineFallback())

        viewModel.importFiles(urls: [locked], insertingAfter: first.refs[0].id)
        try await waitForLocalImportToFinish(in: viewModel)
        XCTAssertEqual(viewModel.pendingPasswordURL?.lastPathComponent, "locked-target.pdf")
        XCTAssertTrue(viewModel.unlock(pdf: try XCTUnwrap(viewModel.pendingPasswordPDF), password: "target", url: locked))

        XCTAssertEqual(viewModel.memberDocuments.map(\.displayName), ["Existing A", "locked-target", "Existing B"])
    }

    @MainActor
    func testLocalUnlockedFixturesImportAfterExistingDocumentInBatchOrder() async throws {
        try XCTSkipUnless(FileManager.default.fileExists(atPath: localFixtureDirectory.path), "Local import fixtures are not present.")
        let document = WorkspaceDocument()
        let existingPDF = PDFDocument()
        existingPDF.insert(try XCTUnwrap(makeSinglePagePDF()), at: 0)
        let existingData = try XCTUnwrap(existingPDF.dataRepresentation())
        var existingMember = MemberDocument(displayName: "Existing", sourcePDFRef: "existing.pdf")
        let existingRef = PageRef(memberDocId: existingMember.id, sourcePageIndex: 0)
        existingMember.pageRefs = [existingRef.id]
        document.workspace.documents = [existingMember]
        document.workspace.pageOrder = [existingRef]
        document.memberPDFData[existingMember.id] = existingData
        let viewModel = WorkspaceViewModel(document: document, processingEngine: PDFKitProcessingEngineFallback())

        viewModel.importFiles(urls: localUnlockedPDFImportFixtureURLs, insertingAfter: existingRef.id)
        try await waitForLocalImportToFinish(in: viewModel)

        XCTAssertNil(viewModel.importError)
        XCTAssertEqual(viewModel.memberDocuments.first?.displayName, "Existing")
        XCTAssertEqual(Array(viewModel.memberDocuments.dropFirst()).map(\.displayName), localUnlockedPDFImportFixtureURLs.map { $0.deletingPathExtension().lastPathComponent })
    }

    @MainActor
    func testLocalFixturesResolveFromFileURLDropProvidersAndImport() async throws {
        try XCTSkipUnless(FileManager.default.fileExists(atPath: localFixtureDirectory.path), "Local import fixtures are not present.")
        let providers = localUnlockedPDFImportFixtureURLs.compactMap { NSItemProvider(contentsOf: $0) }
        let resolvedURLs = try await resolvedLocalImportURLs(from: providers)
        let viewModel = WorkspaceViewModel(document: WorkspaceDocument(), processingEngine: PDFKitProcessingEngineFallback())

        viewModel.importFiles(urls: resolvedURLs)
        try await waitForLocalImportToFinish(in: viewModel)

        XCTAssertEqual(resolvedURLs.map(\.lastPathComponent), localUnlockedPDFImportFixtureURLs.map(\.lastPathComponent))
        XCTAssertNil(viewModel.importError)
        XCTAssertEqual(viewModel.memberDocuments.count, localUnlockedPDFImportFixtureURLs.count)
    }

    @MainActor
    func testLocalFixturesResolveFromFileRepresentationDropProvidersAndImport() async throws {
        try XCTSkipUnless(FileManager.default.fileExists(atPath: localFixtureDirectory.path), "Local import fixtures are not present.")
        let providers = localUnlockedPDFImportFixtureURLs.map { url in
            let provider = NSItemProvider()
            provider.registerFileRepresentation(forTypeIdentifier: UTType.pdf.identifier, fileOptions: [], visibility: .all) { completion in
                completion(url, false, nil)
                return nil
            }
            return provider
        }
        let resolvedURLs = try await resolvedLocalImportURLs(from: providers)
        let viewModel = WorkspaceViewModel(document: WorkspaceDocument(), processingEngine: PDFKitProcessingEngineFallback())

        viewModel.importFiles(urls: resolvedURLs)
        try await waitForLocalImportToFinish(in: viewModel)

        XCTAssertEqual(resolvedURLs.count, localUnlockedPDFImportFixtureURLs.count)
        XCTAssertTrue(resolvedURLs.allSatisfy { $0.path.contains("OrifoldDrops") })
        XCTAssertNil(viewModel.importError)
        XCTAssertEqual(viewModel.memberDocuments.count, localUnlockedPDFImportFixtureURLs.count)
    }

    @MainActor
    func testLocalFixtureImportCanRunTwiceAfterPreviousBatchFinishes() async throws {
        try XCTSkipUnless(FileManager.default.fileExists(atPath: localFixtureDirectory.path), "Local import fixtures are not present.")
        let viewModel = WorkspaceViewModel(document: WorkspaceDocument(), processingEngine: PDFKitProcessingEngineFallback())

        viewModel.importFiles(urls: localUnlockedPDFImportFixtureURLs)
        try await waitForLocalImportToFinish(in: viewModel)
        viewModel.importFiles(urls: localUnlockedPDFImportFixtureURLs.reversed())
        try await waitForLocalImportToFinish(in: viewModel)

        XCTAssertNil(viewModel.importError)
        XCTAssertEqual(viewModel.memberDocuments.count, localUnlockedPDFImportFixtureURLs.count * 2)
        XCTAssertEqual(viewModel.memberDocuments.prefix(localUnlockedPDFImportFixtureURLs.count).map(\.displayName), localUnlockedPDFImportFixtureURLs.map { $0.deletingPathExtension().lastPathComponent })
        XCTAssertEqual(viewModel.memberDocuments.suffix(localUnlockedPDFImportFixtureURLs.count).map(\.displayName), localUnlockedPDFImportFixtureURLs.reversed().map { $0.deletingPathExtension().lastPathComponent })
    }

    private func makeSinglePagePDF() -> PDFPage? {
        let view = NSView(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
        return PDFDocument(data: view.dataWithPDF(inside: view.bounds))?.page(at: 0)
    }

    private func writeSinglePagePDF(named filename: String, in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(filename)
        let pdf = PDFDocument()
        pdf.insert(try XCTUnwrap(makeSinglePagePDF()), at: 0)
        try XCTUnwrap(pdf.dataRepresentation()).write(to: url)
        return url
    }

    private func writeEncryptedSinglePagePDF(named filename: String, password: String, in directory: URL) throws -> URL {
        let source = PDFDocument()
        source.insert(try XCTUnwrap(makeSinglePagePDF()), at: 0)
        let encrypted = try PDFEncryptionService.encryptedData(
            from: try XCTUnwrap(source.dataRepresentation()),
            options: PDFEncryptionOptions(userPassword: password, ownerPassword: "\(password)-owner")
        )
        let url = directory.appendingPathComponent(filename)
        try encrypted.write(to: url)
        return url
    }

    private func makeSinglePageMember(named name: String) throws -> (member: MemberDocument, refs: [PageRef], data: Data) {
        let pdf = PDFDocument()
        pdf.insert(try XCTUnwrap(makeSinglePagePDF()), at: 0)
        let data = try XCTUnwrap(pdf.dataRepresentation())
        var member = MemberDocument(displayName: name, sourcePDFRef: "\(name).pdf")
        let refs = [PageRef(memberDocId: member.id, sourcePageIndex: 0)]
        member.pageRefs = refs.map(\.id)
        return (member, refs, data)
    }

    @MainActor
    private func waitForLocalImportToFinish(in viewModel: WorkspaceViewModel) async throws {
        let deadline = Date().addingTimeInterval(10)
        while viewModel.isImporting {
            if Date() > deadline {
                XCTFail("Timed out waiting for import to finish")
                return
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    private func resolvedLocalImportURLs(from providers: [NSItemProvider]) async throws -> [URL] {
        try await withCheckedThrowingContinuation { continuation in
            resolveImportURLs(from: providers) { urls, wasLimited in
                if wasLimited {
                    continuation.resume(throwing: NSError(domain: "ImportStressTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Drop provider resolution was unexpectedly limited."]))
                } else {
                    continuation.resume(returning: urls)
                }
            }
        }
    }
}
