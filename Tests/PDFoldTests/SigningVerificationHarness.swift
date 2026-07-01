import PDFKit
import XCTest
@testable import PDFold

/// Module G verification harness. Not part of the normal suite — it only runs when the
/// environment variables below are set, so `swift test` stays hermetic. It drives the SAME
/// component pipeline that `WorkspaceViewModel.signAndExportCryptographicPDF` must call
/// (identity → CMSSignatureBuilder → PDFIncrementalSigner) using a self-signed `.p12`, so a
/// real signed PDF can be validated externally with `pdfsig` / `openssl`.
///
///   PDFOLD_P12_PATH  path to a PKCS#12 (.p12) file
///   PDFOLD_P12_PASS  its passphrase (default "")
///   PDFOLD_SIGN_OUT  where to write the signed PDF
///   PDFOLD_SIGN_TIMESTAMP  set to 1 to request a RFC-3161 timestamp over the CMS signature value
///   PDFOLD_TSA_URL  optional timestamp authority URL (defaults to TimestampClient.defaultTSAURL)
final class SigningVerificationHarness: XCTestCase {
    func testProduceSignedPDFForExternalValidation() throws {
        let env = ProcessInfo.processInfo.environment
        guard let p12Path = env["PDFOLD_P12_PATH"], let outPath = env["PDFOLD_SIGN_OUT"] else {
            throw XCTSkip("set PDFOLD_P12_PATH, PDFOLD_P12_PASS, PDFOLD_SIGN_OUT to run")
        }
        let passphrase = env["PDFOLD_P12_PASS"] ?? ""
        let timestampRequested = env["PDFOLD_SIGN_TIMESTAMP"] == "1"
        let tsaURL = env["PDFOLD_TSA_URL"].flatMap(URL.init(string:)) ?? TimestampClient.defaultTSAURL

        let p12 = try Data(contentsOf: URL(fileURLWithPath: p12Path))
        let identity = try PKCS12SigningIdentityProvider.importIdentity(from: p12, passphrase: passphrase)

        // A minimal one-page PDF to sign.
        let page = PDFPage()
        page.setBounds(CGRect(x: 0, y: 0, width: 612, height: 792), for: .mediaBox)
        let doc = PDFDocument()
        doc.insert(page, at: 0)
        let pdfData = try XCTUnwrap(doc.dataRepresentation())

        let field = SignatureFieldSpec(
            pageIndex: 0,
            rect: CGRect(x: 360, y: 60, width: 200, height: 60),
            signerName: identity.commonName ?? "pdFold Signer",
            reason: "Module G verification",
            location: "Local"
        )

        // This closure is exactly what the app's Sign & Export must do instead of throwing.
        let signed = try PDFIncrementalSigner().sign(pdf: pdfData, field: field, appearance: nil) { byteRangeBytes in
            if timestampRequested {
                return try CMSSignatureBuilder.buildCMS(byteRangeBytes: byteRangeBytes, identity: identity) { signatureValue in
                    try Self.fetchTimestampSynchronously(for: signatureValue, tsaURL: tsaURL).cmsTimeStampToken
                }
            }
            return try CMSSignatureBuilder.buildCMS(byteRangeBytes: byteRangeBytes, identity: identity)
        }

        try signed.write(to: URL(fileURLWithPath: outPath), options: .atomic)
        print("PDFOLD_HARNESS wrote signed PDF: \(outPath) (\(signed.count) bytes)")
    }

    private static func fetchTimestampSynchronously(for signatureValue: Data, tsaURL: URL) throws -> TimeStampToken {
        let semaphore = DispatchSemaphore(value: 0)
        final class TimestampBox {
            var result: Result<TimeStampToken, Error>?
        }
        let box = TimestampBox()

        Task.detached {
            do {
                box.result = .success(try await TimestampClient().fetchTimestamp(for: signatureValue, tsaURL: tsaURL))
            } catch {
                box.result = .failure(error)
            }
            semaphore.signal()
        }

        semaphore.wait()
        switch box.result {
        case .success(let token):
            return token
        case .failure(let error):
            throw error
        case nil:
            throw SigningError.timestampUnavailable
        }
    }
}
