import Foundation
import Security

/// The result of checking a certificate profile's chain trust and revocation status
/// against macOS's own trust infrastructure — entirely local computation plus, for
/// revocation, an OCSP/CRL query to the issuing CA's own (free) responder. Orifold does
/// not implement OCSP/CRL parsing itself: `SecPolicyCreateRevocation` + `SecTrustEvaluateWithError`
/// are Apple's own, already-tested implementation of both checks, combined into one verdict
/// (Security.framework does not cleanly separate "untrusted chain" from "revocation
/// unreachable" below the surface of a single pass/fail + error).
struct CertificateTrustEvaluation: Equatable {
    enum Verdict: Equatable {
        /// The chain resolves to a root your Mac already trusts, and revocation checking
        /// (where reachable) found nothing wrong.
        case trusted
        /// Apple's Security framework specifically reported this certificate as revoked.
        case revoked
        /// Anything else — most commonly a self-signed or otherwise untrusted root. This is
        /// the EXPECTED result for a self-signed identity; it is not an error.
        case notTrusted(reason: String)
    }

    var verdict: Verdict
    /// `false` when Orifold could not even ask the question (e.g. the profile has no
    /// certificate bytes) — distinct from `.notTrusted`, which means the question WAS
    /// asked and answered "no."
    var checkedAt: Date
}

enum CertificateTrustEvaluator {
    enum EvaluationError: Error, Equatable, LocalizedError {
        case noCertificatesInProfile
        case invalidCertificateData
        case couldNotCreateTrustObject(OSStatus)

        var errorDescription: String? {
            switch self {
            case .noCertificatesInProfile:
                return L10n.string("certificateTrust.error.noCertificates")
            case .invalidCertificateData:
                return L10n.string("certificateTrust.error.invalidData")
            case .couldNotCreateTrustObject:
                return L10n.string("certificateTrust.error.couldNotEvaluate")
            }
        }
    }

    /// `errSecCertificateRevoked`, per Apple's Security framework error codes
    /// (SecBase.h) — the one specific, documented signal that distinguishes "revoked"
    /// from every other reason a trust evaluation can fail.
    private static let revokedStatus: OSStatus = -67635

    /// Evaluates chain trust + revocation for `profile`. Runs the actual (possibly
    /// network-touching, for OCSP/CRL) evaluation off the calling thread. This is
    /// deliberately ON-DEMAND ONLY — nothing in Orifold calls this automatically, so it
    /// never fires a network request the user didn't explicitly ask for.
    static func evaluate(profile: DigitalCertificateProfile) async throws -> CertificateTrustEvaluation {
        guard !profile.chainCertificatesDER.isEmpty else {
            throw EvaluationError.noCertificatesInProfile
        }
        let certificates = try profile.chainCertificatesDER.map { der -> SecCertificate in
            guard let certificate = SecCertificateCreateWithData(nil, der as CFData) else {
                throw EvaluationError.invalidCertificateData
            }
            return certificate
        }

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do {
                    continuation.resume(returning: try evaluateSynchronously(certificates: certificates))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func evaluateSynchronously(certificates: [SecCertificate]) throws -> CertificateTrustEvaluation {
        let basicPolicy = SecPolicyCreateBasicX509()
        let revocationPolicy = SecPolicyCreateRevocation(
            CFOptionFlags(kSecRevocationOCSPMethod | kSecRevocationCRLMethod)
        )

        var trust: SecTrust?
        let creationStatus = SecTrustCreateWithCertificates(
            certificates as CFArray,
            [basicPolicy, revocationPolicy] as CFArray,
            &trust
        )
        guard creationStatus == errSecSuccess, let trust else {
            throw EvaluationError.couldNotCreateTrustObject(creationStatus)
        }

        var error: CFError?
        let isTrusted = SecTrustEvaluateWithError(trust, &error)
        let now = Date()

        if isTrusted {
            return CertificateTrustEvaluation(verdict: .trusted, checkedAt: now)
        }

        if let error, CFErrorGetCode(error) == Int(revokedStatus) {
            return CertificateTrustEvaluation(verdict: .revoked, checkedAt: now)
        }

        let reason = error.map { CFErrorCopyDescription($0) as String } ?? "unknown"
        return CertificateTrustEvaluation(verdict: .notTrusted(reason: reason), checkedAt: now)
    }
}
