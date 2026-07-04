import CryptoKit
import Foundation
#if canImport(SwiftASN1)
import SwiftASN1
#endif

enum CMSSignatureAlgorithm: Equatable {
    case rsaPKCS1SHA256
    case ecdsaP256SHA256
}

/// Minimal identity surface needed by the CMS layer.
///
/// Module A owns concrete identity loading/generation. Keeping this protocol DER-based lets
/// Module B build and test strict CMS without reaching into Keychain or certificate storage.
protocol CMSSigningIdentity {
    /// Leaf signer certificate, DER-encoded X.509 Certificate.
    var certificateDER: Data { get }
    /// Certificate chain as DER-encoded X.509 certificates, preferably leaf -> issuers.
    var certificateChainDER: [Data] { get }
    var signatureAlgorithm: CMSSignatureAlgorithm { get }

    /// Signs the DER SET OF signed attributes. Implementations should apply the digest/signature
    /// algorithm represented by `signatureAlgorithm` (for example RSA-PKCS1-SHA256).
    func sign(_ data: Data) throws -> Data
}

struct CMSTimeStampToken: Equatable {
    var derEncoded: Data

    init(derEncoded: Data) {
        self.derEncoded = derEncoded
    }
}

enum CMSSignatureBuilder {
    typealias TimestampProvider = (_ signatureValue: Data) throws -> CMSTimeStampToken?

    static func buildCMS(byteRangeBytes: Data,
                         identity: SigningIdentity,
                         timestamp: CMSTimeStampToken? = nil,
                         signingTime: Date = Date()) throws -> Data {
        let adapter = try SigningIdentityCMSAdapter(identity: identity)
        return try buildCMS(
            byteRangeBytes: byteRangeBytes,
            identity: adapter,
            timestamp: timestamp,
            signingTime: signingTime
        )
    }

    static func buildCMS(byteRangeBytes: Data,
                         identity: SigningIdentity,
                         signingTime: Date = Date(),
                         timestampProvider: TimestampProvider) throws -> Data {
        let adapter = try SigningIdentityCMSAdapter(identity: identity)
        return try buildCMS(
            byteRangeBytes: byteRangeBytes,
            identity: adapter,
            signingTime: signingTime,
            timestampProvider: timestampProvider
        )
    }

    static func buildCMS(byteRangeBytes: Data,
                         identity: CMSSigningIdentity,
                         timestamp: CMSTimeStampToken? = nil,
                         signingTime: Date = Date()) throws -> Data {
        try buildCMS(
            byteRangeBytes: byteRangeBytes,
            identity: identity,
            signingTime: signingTime,
            timestampProvider: { _ in timestamp }
        )
    }

    static func buildCMS(byteRangeBytes: Data,
                         identity: CMSSigningIdentity,
                         signingTime: Date = Date(),
                         timestampProvider: TimestampProvider) throws -> Data {
        guard !identity.certificateDER.isEmpty else {
            throw CMSSignatureBuilderError.emptyCertificate
        }

        let certificates = normalizedCertificateChain(
            leaf: identity.certificateDER,
            chain: identity.certificateChainDER
        )
        let signerCertificate = try CMSCertificateIdentifier(certificateDER: identity.certificateDER)
        let messageDigest = Data(SHA256.hash(data: byteRangeBytes))
        let certificateHash = Data(SHA256.hash(data: identity.certificateDER))

        let signedAttributes = try [
            DER.attribute(oid: OID.contentType, values: [DER.objectIdentifier(OID.data)]),
            DER.attribute(oid: OID.messageDigest, values: [DER.octetString(messageDigest)]),
            DER.attribute(oid: OID.signingTime, values: [DER.time(signingTime)]),
            DER.attribute(
                oid: OID.signingCertificateV2,
                values: [
                    DER.signingCertificateV2(
                        certificateHash: certificateHash,
                        certificateIdentifier: signerCertificate
                    )
                ]
            )
        ].derSetSorted()

        let signedAttributesSet = DER.set(signedAttributes, alreadySorted: true)
        let signatureValue = try identity.sign(signedAttributesSet)
        let timestamp = try timestampProvider(signatureValue)

        let signerInfo = try DER.signerInfo(
            certificateIdentifier: signerCertificate,
            signatureAlgorithm: identity.signatureAlgorithm,
            signedAttributes: signedAttributes,
            signatureValue: signatureValue,
            timestamp: timestamp
        )

        let signedData = DER.sequence([
            DER.integer(1),
            DER.set([try DER.algorithmIdentifier(OID.sha256)], alreadySorted: false),
            DER.sequence([try DER.objectIdentifier(OID.data)]),
            DER.implicitContextSpecificSet(tag: 0, values: certificates.derSetSorted()),
            DER.set([signerInfo], alreadySorted: false)
        ])

        return DER.sequence([
            try DER.objectIdentifier(OID.signedData),
            DER.explicitContextSpecific(tag: 0, value: signedData)
        ])
    }

    private static func normalizedCertificateChain(leaf: Data, chain: [Data]) -> [Data] {
        var certificates = chain.isEmpty ? [leaf] : chain
        if certificates.first != leaf {
            certificates.insert(leaf, at: 0)
        }
        var seen = Set<Data>()
        return certificates.filter { seen.insert($0).inserted }
    }
}

enum CMSSignatureBuilderError: Error, Equatable {
    case emptyCertificate
    case malformedDER
    case malformedCertificate
    case invalidObjectIdentifier(String)
    case unsupportedSigningAlgorithm(SignatureAlgorithm)
}

private struct SigningIdentityCMSAdapter: CMSSigningIdentity {
    let certificateDER: Data
    let certificateChainDER: [Data]
    let signatureAlgorithm: CMSSignatureAlgorithm

    private let signer: (Data) throws -> Data

    init(identity: SigningIdentity) throws {
        certificateDER = try Self.derEncoded(identity.certificate)
        certificateChainDER = try identity.chain.map { try Self.derEncoded($0) }
        signatureAlgorithm = try CMSSignatureAlgorithm(identity.signatureAlgorithm)
        signer = identity.sign
    }

    func sign(_ data: Data) throws -> Data {
        try signer(data)
    }

    private static func derEncoded(_ certificate: Certificate) throws -> Data {
        #if canImport(X509) && canImport(SwiftASN1)
        var serializer = SwiftASN1.DER.Serializer()
        try serializer.serialize(certificate)
        return Data(serializer.serializedBytes)
        #else
        return certificate.derRepresentation
        #endif
    }
}

private extension CMSSignatureAlgorithm {
    init(_ algorithm: SignatureAlgorithm) throws {
        switch algorithm {
        case .rsaPKCS1SHA256:
            self = .rsaPKCS1SHA256
        case .ecdsaP256SHA256:
            self = .ecdsaP256SHA256
        }
    }
}

private enum OID {
    static let data = "1.2.840.113549.1.7.1"
    static let signedData = "1.2.840.113549.1.7.2"
    static let contentType = "1.2.840.113549.1.9.3"
    static let messageDigest = "1.2.840.113549.1.9.4"
    static let signingTime = "1.2.840.113549.1.9.5"
    static let sha256 = "2.16.840.1.101.3.4.2.1"
    static let rsaPKCS1SHA256 = "1.2.840.113549.1.1.11"
    static let ecdsaWithSHA256 = "1.2.840.10045.4.3.2"
    static let signingCertificateV2 = "1.2.840.113549.1.9.16.2.47"
    static let timeStampToken = "1.2.840.113549.1.9.16.2.14"
}

private struct CMSCertificateIdentifier {
    var issuerNameDER: Data
    var serialNumberDER: Data

    init(certificateDER: Data) throws {
        var certificateReader = CMSDERReader(certificateDER)
        let certificate = try certificateReader.readExpected(tag: 0x30)
        guard certificateReader.isAtEnd else {
            throw CMSSignatureBuilderError.malformedCertificate
        }

        var certificateSequence = CMSDERReader(certificate.contents)
        let tbsCertificate = try certificateSequence.readExpected(tag: 0x30)
        var tbsReader = CMSDERReader(tbsCertificate.contents)

        if try tbsReader.peekTag() == 0xA0 {
            _ = try tbsReader.readNode()
        }

        let serialNumber = try tbsReader.readExpected(tag: 0x02)
        _ = try tbsReader.readNode()
        let issuerName = try tbsReader.readExpected(tag: 0x30)

        issuerNameDER = issuerName.encoded
        serialNumberDER = serialNumber.encoded
    }
}

private enum DER {
    static func sequence(_ values: [Data]) -> Data {
        tagged(0x30, values.concatenated())
    }

    static func set(_ values: [Data], alreadySorted: Bool) -> Data {
        tagged(0x31, (alreadySorted ? values : values.derSetSorted()).concatenated())
    }

    static func integer(_ value: Int) -> Data {
        precondition(value >= 0)
        var remaining = value
        var bytes: [UInt8] = []
        repeat {
            bytes.insert(UInt8(remaining & 0xFF), at: 0)
            remaining >>= 8
        } while remaining > 0
        if let first = bytes.first, first & 0x80 != 0 {
            bytes.insert(0x00, at: 0)
        }
        return tagged(0x02, Data(bytes))
    }

    static func octetString(_ value: Data) -> Data {
        tagged(0x04, value)
    }

    static func null() -> Data {
        tagged(0x05, Data())
    }

    static func objectIdentifier(_ oid: String) throws -> Data {
        let components = oid.split(separator: ".").compactMap { UInt64($0) }
        guard components.count >= 2,
              components[0] <= 2,
              components[0] == 2 || components[1] <= 39 else {
            throw CMSSignatureBuilderError.invalidObjectIdentifier(oid)
        }

        var body = Data()
        body.append(contentsOf: base128(components[0] * 40 + components[1]))
        for component in components.dropFirst(2) {
            body.append(contentsOf: base128(component))
        }
        return tagged(0x06, body)
    }

    static func time(_ date: Date) -> Data {
        let calendar = Calendar(identifier: .gregorian)
        let year = calendar.dateComponents(in: TimeZone(secondsFromGMT: 0)!, from: date).year ?? 2000
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)

        if (1950...2049).contains(year) {
            formatter.dateFormat = "yyMMddHHmmss'Z'"
            return tagged(0x17, Data(formatter.string(from: date).utf8))
        }

        formatter.dateFormat = "yyyyMMddHHmmss'Z'"
        return tagged(0x18, Data(formatter.string(from: date).utf8))
    }

    static func algorithmIdentifier(_ oid: String) throws -> Data {
        if oid == OID.rsaPKCS1SHA256 {
            return sequence([try objectIdentifier(oid), null()])
        }
        return sequence([try objectIdentifier(oid)])
    }

    static func attribute(oid: String, values: [Data]) throws -> Data {
        sequence([
            try objectIdentifier(oid),
            set(values, alreadySorted: false)
        ])
    }

    static func signingCertificateV2(certificateHash: Data,
                                     certificateIdentifier: CMSCertificateIdentifier) -> Data {
        let issuerSerial = sequence([
            sequence([
                explicitContextSpecific(tag: 4, value: certificateIdentifier.issuerNameDER)
            ]),
            certificateIdentifier.serialNumberDER
        ])
        let essCertIDv2 = sequence([
            octetString(certificateHash),
            issuerSerial
        ])
        return sequence([
            sequence([essCertIDv2])
        ])
    }

    static func signerInfo(certificateIdentifier: CMSCertificateIdentifier,
                           signatureAlgorithm: CMSSignatureAlgorithm,
                           signedAttributes: [Data],
                           signatureValue: Data,
                           timestamp: CMSTimeStampToken?) throws -> Data {
        var values = [
            integer(1),
            sequence([
                certificateIdentifier.issuerNameDER,
                certificateIdentifier.serialNumberDER
            ]),
            try algorithmIdentifier(OID.sha256),
            implicitContextSpecificSet(tag: 0, values: signedAttributes),
            try algorithmIdentifier(signatureAlgorithm.oid),
            octetString(signatureValue)
        ]

        if let timestamp {
            let timestampAttribute = try attribute(
                oid: OID.timeStampToken,
                values: [timestamp.derEncoded]
            )
            values.append(implicitContextSpecificSet(tag: 1, values: [timestampAttribute].derSetSorted()))
        }

        return sequence(values)
    }

    static func explicitContextSpecific(tag: UInt8, value: Data) -> Data {
        tagged(0xA0 | tag, value)
    }

    static func implicitContextSpecificSet(tag: UInt8, values: [Data]) -> Data {
        tagged(0xA0 | tag, values.concatenated())
    }

    private static func tagged(_ tag: UInt8, _ contents: Data) -> Data {
        var result = Data([tag])
        result.append(length(contents.count))
        result.append(contents)
        return result
    }

    private static func length(_ count: Int) -> Data {
        precondition(count >= 0)
        if count < 128 {
            return Data([UInt8(count)])
        }

        var remaining = count
        var bytes: [UInt8] = []
        while remaining > 0 {
            bytes.insert(UInt8(remaining & 0xFF), at: 0)
            remaining >>= 8
        }
        return Data([0x80 | UInt8(bytes.count)] + bytes)
    }

    private static func base128(_ value: UInt64) -> [UInt8] {
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

private extension CMSSignatureAlgorithm {
    var oid: String {
        switch self {
        case .rsaPKCS1SHA256:
            return OID.rsaPKCS1SHA256
        case .ecdsaP256SHA256:
            return OID.ecdsaWithSHA256
        }
    }
}

private struct CMSDERNode {
    var tag: UInt8
    var encoded: Data
    var contents: Data
}

private struct CMSDERReader {
    private var data: Data
    private var offset = 0

    init(_ data: Data) {
        self.data = Data(data)
    }

    var isAtEnd: Bool {
        offset == data.count
    }

    func peekTag() throws -> UInt8? {
        guard offset < data.count else {
            return nil
        }
        return data[offset]
    }

    mutating func readExpected(tag expectedTag: UInt8) throws -> CMSDERNode {
        let node = try readNode()
        guard node.tag == expectedTag else {
            throw CMSSignatureBuilderError.malformedDER
        }
        return node
    }

    mutating func readNode() throws -> CMSDERNode {
        guard offset + 2 <= data.count else {
            throw CMSSignatureBuilderError.malformedDER
        }

        let start = offset
        let tag = data[offset]
        offset += 1

        let firstLengthByte = data[offset]
        offset += 1

        let contentLength: Int
        if firstLengthByte & 0x80 == 0 {
            contentLength = Int(firstLengthByte)
        } else {
            let byteCount = Int(firstLengthByte & 0x7F)
            guard byteCount > 0, byteCount <= MemoryLayout<Int>.size, offset + byteCount <= data.count else {
                throw CMSSignatureBuilderError.malformedDER
            }
            var length = 0
            for _ in 0..<byteCount {
                length = (length << 8) | Int(data[offset])
                offset += 1
            }
            contentLength = length
        }

        guard contentLength >= 0, offset + contentLength <= data.count else {
            throw CMSSignatureBuilderError.malformedDER
        }

        let contentStart = offset
        offset += contentLength

        return CMSDERNode(
            tag: tag,
            encoded: Data(data[start..<offset]),
            contents: Data(data[contentStart..<offset])
        )
    }
}

private extension Array where Element == Data {
    func concatenated() -> Data {
        var result = Data()
        forEach { result.append($0) }
        return result
    }

    func derSetSorted() -> [Data] {
        sorted { lhs, rhs in
            lhs.lexicographicallyPrecedes(rhs)
        }
    }
}

private extension Data {
    func lexicographicallyPrecedes(_ other: Data) -> Bool {
        for (lhs, rhs) in zip(self, other) {
            if lhs != rhs {
                return lhs < rhs
            }
        }
        return count < other.count
    }
}
