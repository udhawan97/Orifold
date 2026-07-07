import Crypto
import PDFKit
import UniformTypeIdentifiers
import X509
import XCTest

@testable import Orifold

/// Round 2 of the end-to-end flow pass: deliberately different territory from round 1
/// (which covered weird-input import, a full edit/export/reopen round trip, comment
/// undo/redo, no-certificate signing, and empty-owner-password export). This round covers
/// an expired-certificate signing flow, a multi-document workspace mutation sequence, and
/// dangling-reference safety after removing a document mid-session.
final class UserFlowRegressionRound2Tests: XCTestCase {
    /// A minimal but genuinely valid 1x1 PNG -- `placeSignature` requires `NSImage(data:)`
    /// to succeed, so arbitrary placeholder bytes silently fail placement (returning nil)
    /// well before the expiry/identity logic these tests actually target.
    private static let tinySignatureImageData: Data = {
        let image = NSImage(size: NSSize(width: 1, height: 1))
        image.lockFocus()
        NSColor.black.setFill()
        NSRect(x: 0, y: 0, width: 1, height: 1).fill()
        image.unlockFocus()
        let tiff = image.tiffRepresentation!
        let rep = NSBitmapImageRep(data: tiff)!
        return rep.representation(using: .png, properties: [:])!
    }()

    private func makeFlowMemberWithPDF(
        name: String,
        pageTexts: [String]
    ) throws -> (member: MemberDocument, refs: [PageRef], pdfData: Data) {
        let pdf = PDFDocument()
        for (index, text) in pageTexts.enumerated() {
            let view = Round2FixturePageView(frame: CGRect(x: 0, y: 0, width: 612, height: 792), text: text)
            let pageData = view.dataWithPDF(inside: view.bounds)
            guard let pageDocument = PDFDocument(data: pageData), let page = pageDocument.page(at: 0) else {
                throw XCTSkip("fixture page rendering failed")
            }
            pdf.insert(page, at: index)
        }
        var member = MemberDocument(displayName: name, sourcePDFRef: "\(name).pdf")
        let refs = (0..<pdf.pageCount).map { PageRef(memberDocId: member.id, sourcePageIndex: $0) }
        member.pageRefs = refs.map(\.id)
        let pdfData = try XCTUnwrap(pdf.dataRepresentation())
        return (member, refs, pdfData)
    }

    // MARK: - Expired certificate signing must fail clearly, never crash or silently sign

    private struct FakeExpiredSigningIdentity: SigningIdentity {
        var certificate: Certificate
        var chain: [Certificate] = []
        var signatureAlgorithm: SignatureAlgorithm = .ecdsaP256SHA256
        func sign(_ data: Data) throws -> Data { Data() }
    }

    private func makeExpiredCertificate() throws -> Certificate {
        let privateKey = Certificate.PrivateKey(P256.Signing.PrivateKey())
        let subject = try DistinguishedName { CommonName("Round2 Expired Test") }
        return try Certificate(
            version: .v3,
            serialNumber: .init(),
            publicKey: privateKey.publicKey,
            notValidBefore: Date().addingTimeInterval(-3 * 24 * 60 * 60),
            notValidAfter: Date().addingTimeInterval(-1 * 24 * 60 * 60),
            issuer: subject,
            subject: subject,
            signatureAlgorithm: .ecdsaWithSHA256,
            extensions: Certificate.Extensions {
                Critical(BasicConstraints.notCertificateAuthority)
                Critical(KeyUsage(digitalSignature: true, nonRepudiation: true))
            },
            issuerPrivateKey: privateKey
        )
    }

    @MainActor
    func testSigningWithExpiredCertificateShowsClearMessageNotCrashAndDoesNotSign() throws {
        let fixture = try makeFlowMemberWithPDF(name: "ExpiredSign", pageTexts: ["Please sign here"])
        let document = WorkspaceDocument()
        document.workspace.documents = [fixture.member]
        document.workspace.pageOrder = fixture.refs
        document.memberPDFData[fixture.member.id] = fixture.pdfData
        let viewModel = WorkspaceViewModel(document: document, processingEngine: PDFKitProcessingEngineFallback())

        let expiredIdentity = FakeExpiredSigningIdentity(certificate: try makeExpiredCertificate())
        XCTAssertTrue(expiredIdentity.isCertificateExpired)

        viewModel.beginCryptographicSignaturePlacement(
            imageData: Self.tinySignatureImageData,
            signerName: "Round2 Tester",
            signerIdentityRef: nil,
            reason: nil,
            location: nil,
            contactInfo: nil,
            timestampRequested: false,
            identity: expiredIdentity,
            certificateProfileID: nil
        )
        let page = try XCTUnwrap(viewModel.loadedPDFs.first?.1.page(at: 0))
        let placedAnnotation = viewModel.placeSignature(imageData: Self.tinySignatureImageData, at: CGPoint(x: 150, y: 700), on: page)
        XCTAssertNotNil(placedAnnotation, "placement itself should succeed -- the expiry check belongs to the signing step, not placement")
        XCTAssertTrue(document.workspace.signatures.contains { $0.isCryptographic })

        let originalBytesBeforeSigning = document.memberPDFData[fixture.member.id]

        viewModel.signAndExportCryptographicPDF(timestampRequested: false)

        // The certificate's expiry must stop the sign before it ever produces a
        // "successfully signed" PDF -- a document that LOOKS validly signed with an
        // expired certificate is worse than an outright failure.
        XCTAssertNotNil(viewModel.exportError, "an expired certificate must produce a visible error, not fail silently")
        let message = try XCTUnwrap(viewModel.exportError?.message)
        XCTAssertFalse(message.isEmpty)
        XCTAssertFalse(message.contains("couldn’t be completed") || message.contains("couldn't be completed"), "must not leak the generic Cocoa fallback: '\(message)'")
        XCTAssertTrue(message.localizedCaseInsensitiveContains("expired"), "message should tell the user the certificate expired: '\(message)'")
        XCTAssertEqual(document.memberPDFData[fixture.member.id], originalBytesBeforeSigning, "member PDF bytes must be unchanged after a rejected signing attempt")
    }

    // MARK: - Multi-document workspace: add, remove, export must stay consistent

    func testMultiDocumentWorkspaceAddRemoveExportStaysConsistent() throws {
        let first = try makeFlowMemberWithPDF(name: "First", pageTexts: ["First doc page"])
        let second = try makeFlowMemberWithPDF(name: "Second", pageTexts: ["Second doc page one", "Second doc page two"])
        let document = WorkspaceDocument()
        document.workspace.documents = [first.member, second.member]
        document.workspace.pageOrder = first.refs + second.refs
        document.memberPDFData[first.member.id] = first.pdfData
        document.memberPDFData[second.member.id] = second.pdfData
        let viewModel = WorkspaceViewModel(document: document, processingEngine: PDFKitProcessingEngineFallback())

        XCTAssertEqual(viewModel.pageCount, 3)
        XCTAssertEqual(viewModel.memberDocuments.count, 2)

        viewModel.removeDocument(first.member)

        XCTAssertEqual(viewModel.memberDocuments.count, 1, "removing one member must leave exactly the other")
        XCTAssertEqual(viewModel.pageCount, 2, "page count must reflect only the remaining member's pages")
        XCTAssertFalse(document.workspace.pageOrder.contains { first.refs.map(\.id).contains($0.id) }, "removed member's page refs must not linger in pageOrder")

        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("Orifold-multidoc-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: outputURL) }
        XCTAssertTrue(viewModel.saveFlattenedPDF(to: outputURL), "export after removing a document should still succeed")
        XCTAssertNil(viewModel.exportError)

        let exportedPDF = try XCTUnwrap(PDFDocument(data: try Data(contentsOf: outputURL)))
        XCTAssertEqual(exportedPDF.pageCount, 2, "exported file must contain only the surviving member's pages")
        XCTAssertFalse(exportedPDF.page(at: 0)?.string?.contains("First doc") ?? false, "the removed document's content must not appear in the export")
    }

    // MARK: - Dangling reference safety: acting on a just-removed document must not crash

    func testEditableTextBlockLookupOnRemovedDocumentPageReturnsNilNotCrash() throws {
        let fixture = try makeFlowMemberWithPDF(name: "ToRemove", pageTexts: ["Will be removed"])
        let document = WorkspaceDocument()
        document.workspace.documents = [fixture.member]
        document.workspace.pageOrder = fixture.refs
        document.memberPDFData[fixture.member.id] = fixture.pdfData
        let viewModel = WorkspaceViewModel(document: document, processingEngine: PDFKitProcessingEngineFallback())

        let page = try XCTUnwrap(viewModel.loadedPDFs.first?.1.page(at: 0))
        // Retain the PDFPage object itself (as a UI layer holding a stale reference across
        // an async gap plausibly would) after removing its owning document.
        viewModel.removeDocument(fixture.member)
        XCTAssertTrue(viewModel.isWorkspaceEmpty)

        // Must not crash: neither hit-testing nor attempting an edit on a page whose
        // document no longer exists in the workspace.
        let result = viewModel.editableTextBlock(at: CGPoint(x: 150, y: 700), on: page, in: viewModel.combinedPDF)
        XCTAssertNil(result, "a page from a removed document should resolve to nothing, not crash or resurrect stale state")
    }

    // MARK: - Cancelling signature placement mid-flow must fully clear pending state

    @MainActor
    func testCancellingSignaturePlacementThenStartingFreshDoesNotLeakPriorIdentity() throws {
        let fixture = try makeFlowMemberWithPDF(name: "CancelSign", pageTexts: ["Sign area"])
        let document = WorkspaceDocument()
        document.workspace.documents = [fixture.member]
        document.workspace.pageOrder = fixture.refs
        document.memberPDFData[fixture.member.id] = fixture.pdfData
        let viewModel = WorkspaceViewModel(document: document, processingEngine: PDFKitProcessingEngineFallback())

        let expiredIdentity = FakeExpiredSigningIdentity(certificate: try makeExpiredCertificate())
        viewModel.beginCryptographicSignaturePlacement(
            imageData: Self.tinySignatureImageData,
            signerName: "First Attempt",
            signerIdentityRef: nil,
            reason: nil,
            location: nil,
            contactInfo: nil,
            timestampRequested: false,
            identity: expiredIdentity,
            certificateProfileID: nil
        )
        viewModel.cancelSignaturePlacement()

        // Starting a plain (non-cryptographic) visual signature placement next must not
        // carry over the previously-selected identity or force cryptographic mode.
        viewModel.beginVisualSignaturePlacement(imageData: Self.tinySignatureImageData, kind: .visualTyped, signerName: "Second Attempt")
        let page = try XCTUnwrap(viewModel.loadedPDFs.first?.1.page(at: 0))
        _ = viewModel.placeSignature(imageData: Self.tinySignatureImageData, at: CGPoint(x: 150, y: 700), on: page)

        let placed = try XCTUnwrap(document.workspace.signatures.last)
        XCTAssertFalse(placed.isCryptographic, "cancelling a cryptographic placement must not leak into the next, unrelated visual placement")
    }
}

private final class Round2FixturePageView: NSView {
    private let text: String

    init(frame: CGRect, text: String) {
        self.text = text
        super.init(frame: frame)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("unavailable") }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        bounds.fill()
        NSString(string: text).draw(
            in: CGRect(x: 72, y: 72, width: 468, height: 648),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 16),
                .foregroundColor: NSColor.black
            ]
        )
    }
}
