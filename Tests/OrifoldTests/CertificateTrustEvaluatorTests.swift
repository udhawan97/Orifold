import XCTest
@testable import Orifold

final class CertificateTrustEvaluatorTests: XCTestCase {
    private func makeSelfSignedProfile(commonName: String = "Test Signer") throws -> DigitalCertificateProfile {
        let identity = try SelfSignedSigningIdentityProvider.generate(
            request: SelfSignedIdentityRequest(commonName: "\(commonName) \(UUID().uuidString)")
        )
        return try DigitalCertificateProfile(
            identity: identity,
            label: "Test profile",
            source: .selfSignedGenerated,
            keychainPersistentRef: Data()
        )
    }

    func testSelfSignedIdentityEvaluatesAsNotTrustedByTheSystemRoots() async throws {
        // A self-signed certificate has no path to a root your Mac already trusts — this is
        // the EXPECTED, correct result, not an error. The whole point of this check existing
        // is to make that distinction visible and honestly labeled in the UI.
        let profile = try makeSelfSignedProfile()
        let evaluation = try await CertificateTrustEvaluator.evaluate(profile: profile)

        switch evaluation.verdict {
        case .notTrusted:
            break // expected
        case .trusted, .revoked:
            XCTFail("a freshly generated self-signed certificate must not evaluate as trusted or revoked, got \(evaluation.verdict)")
        }
    }

    func testEvaluationThrowsForAProfileWithNoCertificateBytes() async throws {
        // Construct a profile with an empty chain directly via Codable decoding, bypassing
        // the throwing initializer (which always populates at least the leaf certificate for
        // any real identity) — this simulates a corrupted/hand-edited profiles.json entry.
        let json = """
        {
            "id": "\(UUID().uuidString)",
            "label": "Corrupted",
            "source": {"kind": "selfSignedGenerated"},
            "keychainPersistentRef": "",
            "subjectCommonName": "Nobody",
            "issuerCommonName": "Nobody",
            "serialHex": "",
            "notBefore": 0,
            "notAfter": 0,
            "isSelfSigned": true,
            "chainCertificatesDER": [],
            "keyAlgorithm": "ECDSA-P256-SHA256",
            "sha256Fingerprint": "",
            "createdAt": 0
        }
        """
        guard let data = json.data(using: .utf8),
              let profile = try? JSONDecoder().decode(DigitalCertificateProfile.self, from: data) else {
            throw XCTSkip("DigitalCertificateProfile's Codable representation changed shape; update this fixture to match")
        }

        do {
            _ = try await CertificateTrustEvaluator.evaluate(profile: profile)
            XCTFail("expected .noCertificatesInProfile for an empty chain")
        } catch {
            XCTAssertEqual(error as? CertificateTrustEvaluator.EvaluationError, .noCertificatesInProfile)
        }
    }
}
