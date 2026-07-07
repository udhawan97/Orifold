import Foundation
import Security

#if canImport(X509)
import X509

typealias Certificate = X509.Certificate
#else
/// DER-backed stand-in used until the package wires in swift-certificates.
///
/// Module A exposes the same `Certificate` name promised by docs/signing/SIGNING_SPEC.md so
/// downstream signing code can be written now. When the X509 product is added to
/// Package.swift this becomes `X509.Certificate` through the conditional typealias
/// above.
struct Certificate: Equatable {
    let derRepresentation: Data

    init(derEncoded data: Data) {
        self.derRepresentation = data
    }

    init(derEncoded bytes: [UInt8]) {
        self.derRepresentation = Data(bytes)
    }
}
#endif

enum SignatureAlgorithm: String, Equatable {
    case rsaPKCS1SHA256 = "RSA-PKCS1-SHA256"
    case ecdsaP256SHA256 = "ECDSA-P256-SHA256"

    var secKeyAlgorithm: SecKeyAlgorithm {
        switch self {
        case .rsaPKCS1SHA256:
            return .rsaSignatureMessagePKCS1v15SHA256
        case .ecdsaP256SHA256:
            return .ecdsaSignatureMessageX962SHA256
        }
    }
}

protocol SigningIdentity {
    var certificate: Certificate { get }
    var chain: [Certificate] { get }
    var signatureAlgorithm: SignatureAlgorithm { get }

    /// Signs the provided message bytes with SHA-256 using the private key held by
    /// Security.framework. Private key material is never exported.
    func sign(_ data: Data) throws -> Data
}

extension SigningIdentity {
    /// `nil` only in the (unreachable in practice — swift-certificates is an unconditional
    /// dependency) non-X509 fallback build, where the DER-backed `Certificate` stand-in
    /// carries no parsed validity dates.
    var certificateExpiryDate: Date? {
        #if canImport(X509)
        return certificate.notValidAfter
        #else
        return nil
        #endif
    }

    var isCertificateExpired: Bool {
        guard let certificateExpiryDate else { return false }
        return certificateExpiryDate < Date()
    }
}

enum SigningIdentityError: Error, Equatable, CustomStringConvertible, LocalizedError {
    case securityStatus(operation: String, status: OSStatus)
    case securityFrameworkError(operation: String, message: String)
    case missingCertificate
    case missingPrivateKey
    case invalidCertificateData
    case invalidPKCS12
    case noIdentityInPKCS12
    case unsupportedPrivateKeyAlgorithm(String)
    case unsupportedSigningAlgorithm(SignatureAlgorithm)
    case randomGenerationFailed(OSStatus)
    case selfSignedCertificateCreationFailed

    var description: String {
        switch self {
        case let .securityStatus(operation, status):
            if let plainEnglish = Self.plainEnglishMessage(for: status) {
                return plainEnglish
            }
            return String(localized: "\(operation) failed (code \(status)). Try again, and if it keeps happening, check the certificate in Keychain Access.", locale: L10n.currentLocale)
        case let .securityFrameworkError(operation, message):
            return String(localized: "\(operation) failed: \(message)", locale: L10n.currentLocale)
        case .missingCertificate:
            return L10n.string("error.signingIdentity.missingCertificate")
        case .missingPrivateKey:
            return L10n.string("error.signingIdentity.missingPrivateKey")
        case .invalidCertificateData:
            return L10n.string("error.signingIdentity.invalidCertificateData")
        case .invalidPKCS12:
            return L10n.string("error.signingIdentity.invalidPKCS12")
        case .noIdentityInPKCS12:
            return L10n.string("error.signingIdentity.noIdentityInPKCS12")
        case let .unsupportedPrivateKeyAlgorithm(details):
            return String(localized: "Orifold doesn't support this certificate's private key algorithm (\(details)). Try a different certificate.", locale: L10n.currentLocale)
        case let .unsupportedSigningAlgorithm(algorithm):
            return String(localized: "This certificate's private key can't create \(algorithm.rawValue) signatures. Try a different certificate.", locale: L10n.currentLocale)
        case let .randomGenerationFailed(status):
            return String(localized: "Orifold couldn't generate the secure random data signing requires (code \(status)). Try again.", locale: L10n.currentLocale)
        case .selfSignedCertificateCreationFailed:
            return L10n.string("error.signingIdentity.selfSignedCertificateCreationFailed")
        }
    }

    /// `LocalizedError` conformance so `error.localizedDescription` at generic catch sites
    /// actually surfaces the message above -- without this conformance, Swift/Foundation's
    /// default `Error` -> `NSError` bridging produces a useless generic string ("The
    /// operation couldn't be completed. (Orifold.SigningIdentityError error 0.)") that hides
    /// every case here, including the ones already written to be plain-English.
    var errorDescription: String? { description }

    /// Translates the handful of Security-framework status codes a casual user can actually
    /// act on (wrong password, cancelled, item missing) into plain English. Returns `nil`
    /// for anything else so the caller's generic-but-still-actionable fallback applies —
    /// deliberately not attempting to explain every one of Security's ~100 status codes,
    /// most of which are internal/never-actually-hit in this app's call paths.
    private static func plainEnglishMessage(for status: OSStatus) -> String? {
        switch status {
        case errSecAuthFailed, errSecPkcs12VerifyFailure:
            return L10n.string("error.signingIdentity.wrongPassword")
        case errSecUserCanceled:
            return L10n.string("error.signingIdentity.userCancelled")
        case errSecItemNotFound:
            return L10n.string("error.signingIdentity.itemNotFoundInKeychain")
        case errSecDuplicateItem:
            return L10n.string("error.signingIdentity.alreadyInKeychain")
        case errSecInteractionNotAllowed:
            return L10n.string("error.signingIdentity.keychainLocked")
        default:
            return nil
        }
    }
}

/// A SigningIdentity backed by a macOS SecIdentity/SecKey pair.
struct SecuritySigningIdentity: SigningIdentity {
    let secIdentity: SecIdentity
    let secCertificate: SecCertificate
    let secCertificateChain: [SecCertificate]
    let certificate: Certificate
    let chain: [Certificate]
    let signatureAlgorithm: SignatureAlgorithm

    private let privateKey: SecKey

    init(secIdentity: SecIdentity, secCertificateChain suppliedChain: [SecCertificate] = []) throws {
        var certificateRef: SecCertificate?
        let certificateStatus = SecIdentityCopyCertificate(secIdentity, &certificateRef)
        guard certificateStatus == errSecSuccess else {
            throw SigningIdentityError.securityStatus(
                operation: "SecIdentityCopyCertificate",
                status: certificateStatus
            )
        }
        guard let leafCertificate = certificateRef else {
            throw SigningIdentityError.missingCertificate
        }

        var privateKeyRef: SecKey?
        let privateKeyStatus = SecIdentityCopyPrivateKey(secIdentity, &privateKeyRef)
        guard privateKeyStatus == errSecSuccess else {
            throw SigningIdentityError.securityStatus(
                operation: "SecIdentityCopyPrivateKey",
                status: privateKeyStatus
            )
        }
        guard let privateKey = privateKeyRef else {
            throw SigningIdentityError.missingPrivateKey
        }

        let normalizedChain = Self.normalizedChain(leaf: leafCertificate, suppliedChain: suppliedChain)

        self.secIdentity = secIdentity
        self.secCertificate = leafCertificate
        self.secCertificateChain = normalizedChain
        self.privateKey = privateKey
        self.signatureAlgorithm = try SignatureAlgorithm(privateKey: privateKey)
        self.certificate = try CertificateConverter.certificate(from: leafCertificate)
        self.chain = try normalizedChain.map { try CertificateConverter.certificate(from: $0) }
    }

    func sign(_ data: Data) throws -> Data {
        let algorithm = signatureAlgorithm.secKeyAlgorithm
        guard SecKeyIsAlgorithmSupported(privateKey, .sign, algorithm) else {
            throw SigningIdentityError.unsupportedSigningAlgorithm(signatureAlgorithm)
        }

        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(privateKey, algorithm, data as CFData, &error) else {
            throw SigningIdentityError.cfError(operation: "SecKeyCreateSignature", error: error)
        }

        return signature as Data
    }

    var commonName: String? {
        var name: CFString?
        let status = SecCertificateCopyCommonName(secCertificate, &name)
        guard status == errSecSuccess else { return nil }
        return name as String?
    }

    private static func normalizedChain(
        leaf: SecCertificate,
        suppliedChain: [SecCertificate]
    ) -> [SecCertificate] {
        var chain = suppliedChain
        let leafData = SecCertificateCopyData(leaf) as Data
        if chain.first.map({ SecCertificateCopyData($0) as Data }) != leafData {
            chain.insert(leaf, at: 0)
        }

        var seen = Set<Data>()
        return chain.filter { certificate in
            let data = SecCertificateCopyData(certificate) as Data
            return seen.insert(data).inserted
        }
    }
}

private enum CertificateConverter {
    static func certificate(from secCertificate: SecCertificate) throws -> Certificate {
        let derData = SecCertificateCopyData(secCertificate) as Data

        #if canImport(X509)
        do {
            return try Certificate(derEncoded: Array(derData))
        } catch {
            throw SigningIdentityError.invalidCertificateData
        }
        #else
        return Certificate(derEncoded: derData)
        #endif
    }
}

private extension SignatureAlgorithm {
    init(privateKey: SecKey) throws {
        guard let attributes = SecKeyCopyAttributes(privateKey) as? [String: Any],
              let keyType = attributes[kSecAttrKeyType as String] else {
            throw SigningIdentityError.unsupportedPrivateKeyAlgorithm("missing key attributes")
        }

        let keyTypeString = keyType as? String ?? String(describing: keyType)
        if keyTypeString == kSecAttrKeyTypeRSA as String {
            self = .rsaPKCS1SHA256
            return
        }

        if keyTypeString == kSecAttrKeyTypeECSECPrimeRandom as String {
            let size = (attributes[kSecAttrKeySizeInBits as String] as? NSNumber)?.intValue
            guard size == 256 else {
                throw SigningIdentityError.unsupportedPrivateKeyAlgorithm("EC key size \(size ?? 0); expected P-256")
            }
            self = .ecdsaP256SHA256
            return
        }

        throw SigningIdentityError.unsupportedPrivateKeyAlgorithm(keyTypeString)
    }
}

extension SigningIdentityError {
    static func cfError(operation: String, error: Unmanaged<CFError>?) -> SigningIdentityError {
        guard let error else {
            return .securityFrameworkError(operation: operation, message: "Unknown Security.framework error")
        }

        let retainedError = error.takeRetainedValue()
        let message = CFErrorCopyDescription(retainedError) as String? ?? "Unknown Security.framework error"
        return .securityFrameworkError(operation: operation, message: message)
    }
}
