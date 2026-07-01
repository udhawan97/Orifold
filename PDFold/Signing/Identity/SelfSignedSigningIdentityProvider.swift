import Foundation
import Security

#if canImport(X509) && canImport(SwiftASN1)
import SwiftASN1
import X509
#endif

struct SelfSignedIdentityRequest {
    var commonName: String
    var emailAddress: String?
    var validityDays: Int
    var keychainLabel: String

    init(
        commonName: String,
        emailAddress: String? = nil,
        validityDays: Int = 365,
        keychainLabel: String? = nil
    ) {
        self.commonName = commonName
        self.emailAddress = emailAddress
        self.validityDays = max(validityDays, 1)
        self.keychainLabel = keychainLabel
            ?? "\(commonName) - \(SelfSignedSigningIdentityProvider.trustDisclosureLabel)"
    }
}

enum SelfSignedSigningIdentityProvider {
    static let trustDisclosureLabel = "self-signed (identity not independently trusted)"

    static func generate(request: SelfSignedIdentityRequest) throws -> SecuritySigningIdentity {
        let applicationTag = "com.pdfold.signing.self-signed.\(UUID().uuidString)"
        let tagData = Data(applicationTag.utf8)
        let privateKey = try generatePrivateKey(tag: tagData, label: request.keychainLabel)

        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            deletePrivateKey(tag: tagData)
            throw SigningIdentityError.unsupportedPrivateKeyAlgorithm("missing public key")
        }

        let certificate: SecCertificate
        do {
            certificate = try SelfSignedCertificateBuilder.makeCertificate(
                commonName: request.commonName,
                emailAddress: request.emailAddress,
                validityDays: request.validityDays,
                privateKey: privateKey,
                publicKey: publicKey
            )
        } catch {
            deletePrivateKey(tag: tagData)
            throw error
        }

        do {
            try addCertificateToKeychain(certificate, label: request.keychainLabel)
        } catch {
            deletePrivateKey(tag: tagData)
            throw error
        }

        var secIdentity: SecIdentity?
        let identityStatus = SecIdentityCreateWithCertificate(nil, certificate, &secIdentity)
        guard identityStatus == errSecSuccess, let secIdentity else {
            deletePrivateKey(tag: tagData)
            throw SigningIdentityError.securityStatus(
                operation: "SecIdentityCreateWithCertificate",
                status: identityStatus
            )
        }

        return try SecuritySigningIdentity(secIdentity: secIdentity, secCertificateChain: [certificate])
    }

    private static func generatePrivateKey(tag: Data, label: String) throws -> SecKey {
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: tag,
                kSecAttrLabel as String: label
            ]
        ]

        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            throw SigningIdentityError.cfError(operation: "SecKeyCreateRandomKey", error: error)
        }

        return privateKey
    }

    private static func addCertificateToKeychain(_ certificate: SecCertificate, label: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecValueRef as String: certificate,
            kSecAttrLabel as String: label
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess || status == errSecDuplicateItem else {
            throw SigningIdentityError.securityStatus(operation: "SecItemAdd certificate", status: status)
        }
    }

    private static func deletePrivateKey(tag: Data) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: tag,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom
        ]
        SecItemDelete(query as CFDictionary)
    }
}

private enum SelfSignedCertificateBuilder {
    static func makeCertificate(
        commonName: String,
        emailAddress: String?,
        validityDays: Int,
        privateKey: SecKey,
        publicKey: SecKey
    ) throws -> SecCertificate {
        #if canImport(X509) && canImport(SwiftASN1)
        return try makeCertificateWithSwiftCertificates(
            commonName: commonName,
            emailAddress: emailAddress,
            validityDays: validityDays,
            privateKey: privateKey
        )
        #else
        let certificateData = try makeCertificateDERFallback(
            commonName: commonName,
            emailAddress: emailAddress,
            validityDays: validityDays,
            privateKey: privateKey,
            publicKey: publicKey
        )

        guard let certificate = SecCertificateCreateWithData(nil, certificateData as CFData) else {
            throw SigningIdentityError.selfSignedCertificateCreationFailed
        }
        return certificate
        #endif
    }

    #if canImport(X509) && canImport(SwiftASN1)
    private static func makeCertificateWithSwiftCertificates(
        commonName: String,
        emailAddress: String?,
        validityDays: Int,
        privateKey secPrivateKey: SecKey
    ) throws -> SecCertificate {
        let privateKey = try Certificate.PrivateKey(secPrivateKey)
        let publicKey = privateKey.publicKey
        let subject = try DistinguishedName {
            CommonName(commonName)
            if let emailAddress, !emailAddress.isEmpty {
                EmailAddress(emailAddress)
            }
        }

        let now = Date()
        let notBefore = now.addingTimeInterval(-300)
        let notAfter = now.addingTimeInterval(TimeInterval(validityDays) * 24 * 60 * 60)
        let certificate = try Certificate(
            version: .v3,
            serialNumber: .init(),
            publicKey: publicKey,
            notValidBefore: notBefore,
            notValidAfter: notAfter,
            issuer: subject,
            subject: subject,
            signatureAlgorithm: .ecdsaWithSHA256,
            extensions: Certificate.Extensions {
                Critical(BasicConstraints.notCertificateAuthority)
                Critical(KeyUsage(digitalSignature: true, nonRepudiation: true))
                SubjectKeyIdentifier(hash: publicKey)
            },
            issuerPrivateKey: privateKey
        )

        return try SecCertificate.makeWithCertificate(certificate)
    }
    #endif

    private static func makeCertificateDERFallback(
        commonName: String,
        emailAddress: String?,
        validityDays: Int,
        privateKey: SecKey,
        publicKey: SecKey
    ) throws -> Data {
        let publicKeyData = try externalRepresentation(of: publicKey, operation: "SecKeyCopyExternalRepresentation public key")
        let subject = distinguishedName(commonName: commonName, emailAddress: emailAddress)
        let signatureAlgorithm = DER.sequence(
            DER.objectIdentifier("1.2.840.10045.4.3.2")
        )

        let now = Date()
        let notBefore = now.addingTimeInterval(-300)
        let notAfter = now.addingTimeInterval(TimeInterval(validityDays) * 24 * 60 * 60)

        let tbsCertificate = DER.sequence([
            DER.explicit(tag: 0, DER.integer(2)),
            DER.integer(try randomSerialNumber()),
            signatureAlgorithm,
            subject,
            DER.sequence([
                DER.generalizedTime(notBefore),
                DER.generalizedTime(notAfter)
            ]),
            subject,
            subjectPublicKeyInfo(publicKeyData: publicKeyData),
            DER.explicit(tag: 3, extensions())
        ])

        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(
            privateKey,
            .ecdsaSignatureMessageX962SHA256,
            tbsCertificate as CFData,
            &error
        ) else {
            throw SigningIdentityError.cfError(operation: "SecKeyCreateSignature self-signed certificate", error: error)
        }

        return DER.sequence([
            tbsCertificate,
            signatureAlgorithm,
            DER.bitString(signature as Data)
        ])
    }

    private static func externalRepresentation(of key: SecKey, operation: String) throws -> Data {
        var error: Unmanaged<CFError>?
        guard let data = SecKeyCopyExternalRepresentation(key, &error) else {
            throw SigningIdentityError.cfError(operation: operation, error: error)
        }
        return data as Data
    }

    private static func randomSerialNumber() throws -> Data {
        var bytes = [UInt8](repeating: 0, count: 16)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw SigningIdentityError.randomGenerationFailed(status)
        }

        bytes[0] &= 0x7F
        if bytes.allSatisfy({ $0 == 0 }) {
            bytes[bytes.count - 1] = 1
        }
        return Data(bytes)
    }

    private static func distinguishedName(commonName: String, emailAddress: String?) -> Data {
        var relativeDistinguishedNames = [
            attribute(oid: "2.5.4.3", value: DER.utf8String(commonName))
        ]

        if let emailAddress, !emailAddress.isEmpty {
            relativeDistinguishedNames.append(
                attribute(oid: "1.2.840.113549.1.9.1", value: DER.ia5String(emailAddress))
            )
        }

        return DER.sequence(relativeDistinguishedNames)
    }

    private static func attribute(oid: String, value: Data) -> Data {
        DER.set([
            DER.sequence([
                DER.objectIdentifier(oid),
                value
            ])
        ])
    }

    private static func subjectPublicKeyInfo(publicKeyData: Data) -> Data {
        DER.sequence([
            DER.sequence([
                DER.objectIdentifier("1.2.840.10045.2.1"),
                DER.objectIdentifier("1.2.840.10045.3.1.7")
            ]),
            DER.bitString(publicKeyData)
        ])
    }

    private static func extensions() -> Data {
        DER.sequence([
            x509Extension(
                oid: "2.5.29.19",
                critical: true,
                value: DER.sequence([])
            ),
            x509Extension(
                oid: "2.5.29.15",
                critical: true,
                value: DER.bitString(Data([0xC0]), unusedBits: 6)
            )
        ])
    }

    private static func x509Extension(oid: String, critical: Bool, value: Data) -> Data {
        var fields = [DER.objectIdentifier(oid)]
        if critical {
            fields.append(DER.boolean(true))
        }
        fields.append(DER.octetString(value))
        return DER.sequence(fields)
    }
}

private enum DER {
    static func sequence(_ children: [Data]) -> Data {
        tagged(0x30, content: children.reduce(into: Data()) { $0.append($1) })
    }

    static func sequence(_ children: Data...) -> Data {
        sequence(children)
    }

    static func set(_ children: [Data]) -> Data {
        tagged(0x31, content: children.reduce(into: Data()) { $0.append($1) })
    }

    static func explicit(tag: UInt8, _ child: Data) -> Data {
        tagged(0xA0 + tag, content: child)
    }

    static func integer(_ value: Int) -> Data {
        precondition(value >= 0)
        if value == 0 {
            return integer(Data([0]))
        }

        var bytes: [UInt8] = []
        var remaining = value
        while remaining > 0 {
            bytes.insert(UInt8(remaining & 0xFF), at: 0)
            remaining >>= 8
        }
        return integer(Data(bytes))
    }

    static func integer(_ bytes: Data) -> Data {
        var normalized = Array(bytes)
        while normalized.count > 1, normalized[0] == 0, normalized[1] < 0x80 {
            normalized.removeFirst()
        }
        if normalized.isEmpty {
            normalized = [0]
        }
        if normalized[0] >= 0x80 {
            normalized.insert(0, at: 0)
        }
        return tagged(0x02, content: Data(normalized))
    }

    static func boolean(_ value: Bool) -> Data {
        tagged(0x01, content: Data([value ? 0xFF : 0x00]))
    }

    static func objectIdentifier(_ dotted: String) -> Data {
        let components = dotted.split(separator: ".").compactMap { Int($0) }
        precondition(components.count >= 2)

        var encoded = Data([UInt8(components[0] * 40 + components[1])])
        for component in components.dropFirst(2) {
            encoded.append(contentsOf: base128(component))
        }
        return tagged(0x06, content: encoded)
    }

    static func utf8String(_ string: String) -> Data {
        tagged(0x0C, content: Data(string.utf8))
    }

    static func ia5String(_ string: String) -> Data {
        tagged(0x16, content: Data(string.utf8))
    }

    static func generalizedTime(_ date: Date) -> Data {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMddHHmmss'Z'"
        return tagged(0x18, content: Data(formatter.string(from: date).utf8))
    }

    static func octetString(_ data: Data) -> Data {
        tagged(0x04, content: data)
    }

    static func bitString(_ data: Data, unusedBits: UInt8 = 0) -> Data {
        var content = Data([unusedBits])
        content.append(data)
        return tagged(0x03, content: content)
    }

    private static func tagged(_ tag: UInt8, content: Data) -> Data {
        var encoded = Data([tag])
        encoded.append(length(content.count))
        encoded.append(content)
        return encoded
    }

    private static func length(_ length: Int) -> Data {
        if length < 128 {
            return Data([UInt8(length)])
        }

        var bytes: [UInt8] = []
        var remaining = length
        while remaining > 0 {
            bytes.insert(UInt8(remaining & 0xFF), at: 0)
            remaining >>= 8
        }

        return Data([0x80 | UInt8(bytes.count)] + bytes)
    }

    private static func base128(_ value: Int) -> [UInt8] {
        precondition(value >= 0)
        var remaining = value
        var bytes = [UInt8(remaining & 0x7F)]
        remaining >>= 7

        while remaining > 0 {
            bytes.insert(UInt8(remaining & 0x7F) | 0x80, at: 0)
            remaining >>= 7
        }

        return bytes
    }
}
