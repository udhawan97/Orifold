import Foundation
import CryptoKit
#if canImport(X509)
import X509
import SwiftASN1
#endif

/// Persistent metadata for a signing identity the user has created or imported. The private
/// key itself is never stored here — only Security.framework's Keychain does, addressed by
/// `keychainPersistentRef`. Persisting this is what lets a self-signed identity be created
/// ONCE and reused for every future signing, instead of regenerating (and thus changing) the
/// certificate on every "self-signed" signature — a certificate a recipient can never learn
/// to trust if it's different each time.
struct DigitalCertificateProfile: Codable, Identifiable, Equatable {
    enum Source: Equatable {
        case selfSignedGenerated
        case importedP12(originalFilename: String?)
        case keychainReference
    }

    let id: UUID
    var label: String
    var source: Source
    var keychainPersistentRef: Data
    var subjectCommonName: String
    var issuerCommonName: String
    var serialHex: String
    var notBefore: Date
    var notAfter: Date
    var isSelfSigned: Bool
    var chainCertificatesDER: [Data]
    var keyAlgorithm: String
    var sha256Fingerprint: String
    var createdAt: Date

    var isExpired: Bool { notAfter < Date() }
    var expiresWithinDays: Int { max(0, Int(notAfter.timeIntervalSinceNow / 86_400)) }
    var expiresSoon: Bool { !isExpired && expiresWithinDays <= 30 }

    init(id: UUID = UUID(),
         identity: SecuritySigningIdentity,
         label: String,
         source: Source,
         keychainPersistentRef: Data,
         createdAt: Date = Date()) throws {
        self.id = id
        self.label = label
        self.source = source
        self.keychainPersistentRef = keychainPersistentRef
        self.createdAt = createdAt

        self.sha256Fingerprint = try Self.fingerprint(for: identity)
        self.chainCertificatesDER = identity.chain.compactMap { try? Self.derEncoded($0) }
        self.keyAlgorithm = identity.signatureAlgorithm.rawValue

        #if canImport(X509)
        let certificate = identity.certificate
        self.subjectCommonName = identity.commonName ?? Self.commonName(fromDistinguishedNameDescription: certificate.subject.description) ?? label
        self.issuerCommonName = Self.commonName(fromDistinguishedNameDescription: certificate.issuer.description) ?? certificate.issuer.description
        self.serialHex = certificate.serialNumber.bytes.map { String(format: "%02x", $0) }.joined()
        self.notBefore = certificate.notValidBefore
        self.notAfter = certificate.notValidAfter
        self.isSelfSigned = certificate.issuer.description == certificate.subject.description
        #else
        self.subjectCommonName = identity.commonName ?? label
        self.issuerCommonName = identity.commonName ?? label
        self.serialHex = ""
        self.notBefore = Date()
        self.notAfter = Date().addingTimeInterval(365 * 24 * 3_600)
        self.isSelfSigned = true
        #endif
    }

    /// SHA-256 of the leaf certificate's DER encoding — computable without constructing a
    /// full profile, so callers deciding "is this identity already registered?" don't have to
    /// build (and discard) a throwaway `DigitalCertificateProfile` just to read one field.
    static func fingerprint(for identity: SecuritySigningIdentity) throws -> String {
        let leafDER = try derEncoded(identity.certificate)
        return Data(SHA256.hash(data: leafDER)).map { String(format: "%02x", $0) }.joined()
    }

    private static func commonName(fromDistinguishedNameDescription description: String) -> String? {
        guard let range = description.range(of: #"CN=([^,]+)"#, options: .regularExpression) else {
            return nil
        }
        return String(description[range]).replacingOccurrences(of: "CN=", with: "")
    }

    #if canImport(X509)
    private static func derEncoded(_ certificate: Certificate) throws -> Data {
        var serializer = SwiftASN1.DER.Serializer()
        try serializer.serialize(certificate)
        return Data(serializer.serializedBytes)
    }
    #else
    private static func derEncoded(_ certificate: Certificate) throws -> Data {
        certificate.derRepresentation
    }
    #endif
}

extension DigitalCertificateProfile.Source: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind, originalFilename
    }

    private enum Kind: String, Codable {
        case selfSignedGenerated, importedP12, keychainReference
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .selfSignedGenerated:
            self = .selfSignedGenerated
        case .importedP12:
            self = .importedP12(originalFilename: try container.decodeIfPresent(String.self, forKey: .originalFilename))
        case .keychainReference:
            self = .keychainReference
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .selfSignedGenerated:
            try container.encode(Kind.selfSignedGenerated, forKey: .kind)
        case .importedP12(let originalFilename):
            try container.encode(Kind.importedP12, forKey: .kind)
            try container.encodeIfPresent(originalFilename, forKey: .originalFilename)
        case .keychainReference:
            try container.encode(Kind.keychainReference, forKey: .kind)
        }
    }
}
