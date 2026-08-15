import PDFKit
import XCTest
@testable import Orifold

final class SignatureValidationTests: XCTestCase {
    @MainActor
    func testOpeningSignedPDFAsDocumentKeepsUntouchedValidationEvidence() async throws {
        let signerName = "Wave 6 Opened \(UUID().uuidString)"
        let identity = try SelfSignedSigningIdentityProvider.generate(
            request: SelfSignedIdentityRequest(commonName: signerName)
        )
        let signed = try sign(pdf: try unsignedPDFData(), identity: identity, signerName: signerName)
        let document = try WorkspaceDocument(
            testingFile: FileWrapper(regularFileWithContents: signed),
            contentType: .pdf,
            filename: "signed.pdf"
        )
        let viewModel = WorkspaceViewModel(
            document: document,
            engine: PDFKitEngine(),
            processingEngine: PDFKitProcessingEngineFallback()
        )

        let member = try XCTUnwrap(viewModel.document.workspace.documents.first)
        let hardened = try XCTUnwrap(viewModel.document.memberPDFData[member.id])
        XCTAssertNotEqual(hardened, signed, "document-open rendering must use hardened bytes")
        let validationData = try XCTUnwrap(viewModel.signatureValidationData(for: member.id))
        XCTAssertEqual(validationData, signed, "document-open Inspector must validate the untouched signed source")

        let reports = await PDFSignatureValidationService.validate(pdf: validationData)
        let report = try XCTUnwrap(reports.first)
        XCTAssertEqual(report.signerCommonName, signerName)
        XCTAssertEqual(report.integrity, .valid)
        XCTAssertEqual(report.coverage, .entireDocument)
    }

    @MainActor
    func testImportedSignedPDFKeepsUntouchedValidationEvidenceOutsideHardenedWorkspaceBytes() async throws {
        let signerName = "Wave 6 Imported \(UUID().uuidString)"
        let identity = try SelfSignedSigningIdentityProvider.generate(
            request: SelfSignedIdentityRequest(commonName: signerName)
        )
        let signed = try sign(pdf: try unsignedPDFData(), identity: identity, signerName: signerName)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Orifold-signed-import-\(UUID().uuidString).pdf")
        try signed.write(to: url, options: .atomic)
        defer { try? FileManager.default.removeItem(at: url) }

        let viewModel = WorkspaceViewModel(
            document: WorkspaceDocument(),
            engine: PDFKitEngine(),
            processingEngine: PDFKitProcessingEngineFallback()
        )
        viewModel.importFiles(urls: [url])
        for _ in 0..<200 {
            if viewModel.document.workspace.documents.count == 1, !viewModel.isImporting { break }
            try await Task.sleep(nanoseconds: 25_000_000)
        }

        let member = try XCTUnwrap(viewModel.document.workspace.documents.first)
        let hardened = try XCTUnwrap(viewModel.document.memberPDFData[member.id])
        XCTAssertNotEqual(hardened, signed, "rendering and editing must continue to use hardened bytes")

        let validationData = try XCTUnwrap(viewModel.signatureValidationData(for: member.id))
        XCTAssertEqual(validationData, signed, "Inspector must validate the untouched signed source")
        let reports = await PDFSignatureValidationService.validate(pdf: validationData)
        let report = try XCTUnwrap(reports.first)
        XCTAssertEqual(report.signerCommonName, signerName)
        XCTAssertEqual(report.integrity, .valid)
        XCTAssertEqual(report.coverage, .entireDocument)
        XCTAssertTrue(viewModel.hasThirdPartyCryptographicSignature)

        let undoManager = UndoManager()
        viewModel.undoManager = undoManager
        viewModel.removeDocument(member)
        XCTAssertTrue(viewModel.document.workspace.documents.isEmpty)
        viewModel.performUndoCommand()
        let restoredMember = try XCTUnwrap(viewModel.document.workspace.documents.first)
        XCTAssertEqual(viewModel.signatureValidationData(for: restoredMember.id), signed)
    }

    func testAppSelfSignedPDFReportsValidIntegrityWholeDocumentAndUntrustedIdentity() async throws {
        let signerName = "Wave 6 Signer \(UUID().uuidString)"
        let identity = try SelfSignedSigningIdentityProvider.generate(
            request: SelfSignedIdentityRequest(commonName: signerName)
        )
        let signed = try sign(pdf: try unsignedPDFData(), identity: identity, signerName: signerName)

        let reports = await PDFSignatureValidationService.validate(pdf: signed)

        let report = try XCTUnwrap(reports.first)
        XCTAssertEqual(reports.count, 1)
        XCTAssertEqual(report.signerCommonName, signerName)
        XCTAssertEqual(report.integrity, .valid)
        XCTAssertEqual(report.coverage, .entireDocument)
        XCTAssertEqual(report.trust, .notTrusted)
        XCTAssertNotNil(report.signingTime)
        XCTAssertFalse(report.isTimestamped)
    }

    func testFlippingCoveredByteFailsIntegrity() async throws {
        let signerName = "Wave 6 Integrity \(UUID().uuidString)"
        let identity = try SelfSignedSigningIdentityProvider.generate(
            request: SelfSignedIdentityRequest(commonName: signerName)
        )
        var signed = try sign(pdf: try unsignedPDFData(), identity: identity, signerName: signerName)
        let marker = Data("ORIFOLD-INTEGRITY-A".utf8)
        let markerRange = try XCTUnwrap(signed.range(of: marker))
        signed[markerRange.upperBound - 1] = UInt8(ascii: "B")

        let reports = await PDFSignatureValidationService.validate(pdf: signed)
        let report = try XCTUnwrap(reports.first)

        XCTAssertEqual(report.integrity, .invalid)
        XCTAssertEqual(report.coverage, .entireDocument)
    }

    func testSecondIncrementalSignaturePreservesFirstIntegrityAndMarksItsEarlierCoverage() async throws {
        let firstName = "Wave 6 First \(UUID().uuidString)"
        let secondName = "Wave 6 Second \(UUID().uuidString)"
        let firstIdentity = try SelfSignedSigningIdentityProvider.generate(
            request: SelfSignedIdentityRequest(commonName: firstName)
        )
        let secondIdentity = try SelfSignedSigningIdentityProvider.generate(
            request: SelfSignedIdentityRequest(commonName: secondName)
        )
        let firstSigned = try sign(
            pdf: try unsignedPDFData(),
            identity: firstIdentity,
            signerName: firstName
        )
        let twiceSigned = try sign(
            pdf: firstSigned,
            identity: secondIdentity,
            signerName: secondName
        )

        let reports = await PDFSignatureValidationService.validate(pdf: twiceSigned)
            .sorted { $0.signedFileLength < $1.signedFileLength }

        XCTAssertEqual(reports.count, 2)
        XCTAssertEqual(reports[0].signerCommonName, firstName)
        XCTAssertEqual(reports[0].integrity, .valid)
        XCTAssertEqual(reports[0].coverage, .changedAfterSigning)
        XCTAssertEqual(reports[1].signerCommonName, secondName)
        XCTAssertEqual(reports[1].integrity, .valid)
        XCTAssertEqual(reports[1].coverage, .entireDocument)
    }

    func testCoverageRequiresExactContentsGapAndHandlesOverflow() throws {
        let token = Data("<< /Contents <01020000> >>".utf8)
        let contentsToken = Data("<01020000>".utf8)
        let tokenRange = try XCTUnwrap(token.range(of: contentsToken))
        let open = tokenRange.lowerBound
        let close = tokenRange.upperBound - 1
        let range = SignatureByteRange(
            beforeOffset: 0,
            beforeLength: open,
            afterOffset: close + 1,
            afterLength: token.count - close - 1
        )
        let contents = Data([0x01, 0x02, 0x00, 0x00])

        XCTAssertEqual(
            PDFSignatureValidationService.coverageVerdict(
                for: range,
                contents: contents,
                pdf: token
            ).0,
            .entireDocument
        )
        var appended = token
        appended.append(Data("\n% incremental update".utf8))
        XCTAssertEqual(
            PDFSignatureValidationService.coverageVerdict(
                for: range,
                contents: contents,
                pdf: appended
            ).0,
            .changedAfterSigning
        )
        let oversizedGap = SignatureByteRange(
            beforeOffset: 0,
            beforeLength: open - 1,
            afterOffset: close + 1,
            afterLength: token.count - close - 1
        )
        XCTAssertEqual(
            PDFSignatureValidationService.coverageVerdict(
                for: oversizedGap,
                contents: contents,
                pdf: token
            ).0,
            .invalid
        )
    }

    func testHostileByteRangeOverflowIsRejected() {
        let pdf = Data("<< /Contents <01020000> >>".utf8)
        let contents = Data([0x01, 0x02, 0x00, 0x00])
        let overflowing = SignatureByteRange(
            beforeOffset: 0,
            beforeLength: 0,
            afterOffset: Int.max,
            afterLength: 1
        )
        XCTAssertEqual(
            PDFSignatureValidationService.coverageVerdict(
                for: overflowing,
                contents: contents,
                pdf: pdf
            ).0,
            .invalid
        )
        XCTAssertThrowsError(try PDFByteRangeCalculator.digestInput(pdf: pdf, range: overflowing))
    }

    func testSignedDataV3StillReachesPinnedCMSVerifier() async throws {
        let signerName = "Wave 6 v3 \(UUID().uuidString)"
        let identity = try SelfSignedSigningIdentityProvider.generate(
            request: SelfSignedIdentityRequest(commonName: signerName)
        )
        let signed = try sign(pdf: try unsignedPDFData(), identity: identity, signerName: signerName)
        let dictionary = try XCTUnwrap(QPDFService.signatureDictionaries(in: signed).first)
        let range = try XCTUnwrap(dictionary.byteRange)
        var paddedCMS = try XCTUnwrap(dictionary.contents)
        let versionPattern = Data([0x02, 0x01, 0x01])
        let searchEnd = min(paddedCMS.count, 80)
        let versionRange = try XCTUnwrap(
            paddedCMS.range(of: versionPattern, in: 0..<searchEnd)
        )
        paddedCMS[versionRange.upperBound - 1] = 0x03
        let replacement = Data(
            ("<" + paddedCMS.map { String(format: "%02X", $0) }.joined() + ">").utf8
        )
        XCTAssertEqual(replacement.count, range.afterOffset - range.beforeLength)
        var signedDataV3 = signed
        signedDataV3.replaceSubrange(range.beforeLength..<range.afterOffset, with: replacement)

        let reports = await PDFSignatureValidationService.validate(pdf: signedDataV3)
        let report = try XCTUnwrap(reports.first)

        XCTAssertEqual(report.signerCommonName, signerName)
        XCTAssertEqual(report.integrity, .valid)
        XCTAssertEqual(report.trust, .unavailable)
        XCTAssertEqual(report.coverage, .entireDocument)
    }

    private func unsignedPDFData() throws -> Data {
        let page = PDFPage()
        page.setBounds(CGRect(x: 0, y: 0, width: 612, height: 792), for: .mediaBox)
        let document = PDFDocument()
        document.insert(page, at: 0)
        var data = try XCTUnwrap(document.dataRepresentation())
        data.append(Data("\n% ORIFOLD-INTEGRITY-A\n".utf8))
        return data
    }

    private func sign(pdf: Data,
                      identity: SecuritySigningIdentity,
                      signerName: String) throws -> Data {
        try PDFIncrementalSigner().sign(
            pdf: pdf,
            field: SignatureFieldSpec(
                pageIndex: 0,
                rect: CGRect(x: 40, y: 60, width: 180, height: 50),
                signerName: signerName
            ),
            appearance: nil
        ) { byteRangeBytes in
            try CMSSignatureBuilder.buildCMS(
                byteRangeBytes: byteRangeBytes,
                identity: identity,
                signingTime: Date(timeIntervalSince1970: 1_786_240_000)
            )
        }
    }
}
