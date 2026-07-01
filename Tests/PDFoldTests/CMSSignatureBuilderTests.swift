import CryptoKit
import Foundation
import XCTest
@testable import PDFold

final class CMSSignatureBuilderTests: XCTestCase {
    func testBuildCMSIncludesRequiredPAdESSignedAttributesBeforeSigning() throws {
        let certificate = TestCertificate.makeDER(serial: Data([0x01, 0x23]))
        let identity = RecordingCMSIdentity(
            certificateDER: certificate,
            certificateChainDER: [certificate],
            signatureAlgorithm: .rsaPKCS1SHA256,
            signatureValue: Data([0xAA, 0xBB, 0xCC])
        )
        let byteRangeBytes = Data("signed byte range bytes".utf8)
        let signingTime = Date(timeIntervalSince1970: 1_704_067_200) // 2024-01-01T00:00:00Z

        let cms = try CMSSignatureBuilder.buildCMS(
            byteRangeBytes: byteRangeBytes,
            identity: identity,
            signingTime: signingTime
        )

        XCTAssertTrue(cms.derContainsObjectIdentifier("1.2.840.113549.1.7.2"), "CMS must be SignedData")
        XCTAssertTrue(cms.derContainsObjectIdentifier("1.2.840.113549.1.9.3"), "missing content-type")
        XCTAssertTrue(cms.derContainsObjectIdentifier("1.2.840.113549.1.9.4"), "missing message-digest")
        XCTAssertTrue(cms.derContainsObjectIdentifier("1.2.840.113549.1.9.5"), "missing signing-time")
        XCTAssertTrue(cms.derContainsObjectIdentifier("1.2.840.113549.1.9.16.2.47"), "missing ESS signing-certificate-v2")
        XCTAssertTrue(cms.containsSubdata(Data(SHA256.hash(data: byteRangeBytes))), "missing SHA-256 message digest")
        XCTAssertTrue(cms.containsSubdata(Data(SHA256.hash(data: certificate))), "missing ESS certificate hash")
        XCTAssertTrue(cms.containsSubdata(Data([0xAA, 0xBB, 0xCC])), "missing signer signature value")

        let signedAttributes = try XCTUnwrap(identity.signedInputs.first)
        XCTAssertEqual(signedAttributes.first, 0x31, "signer must receive the DER SET OF signed attributes")
        XCTAssertTrue(signedAttributes.derContainsObjectIdentifier("1.2.840.113549.1.9.3"))
        XCTAssertTrue(signedAttributes.derContainsObjectIdentifier("1.2.840.113549.1.9.4"))
        XCTAssertTrue(signedAttributes.derContainsObjectIdentifier("1.2.840.113549.1.9.5"))
        XCTAssertTrue(signedAttributes.derContainsObjectIdentifier("1.2.840.113549.1.9.16.2.47"))
    }

    func testBuildCMSAttachesTimestampTokenAsUnsignedAttribute() throws {
        let certificate = TestCertificate.makeDER(serial: Data([0x45, 0x67]))
        let identity = RecordingCMSIdentity(
            certificateDER: certificate,
            certificateChainDER: [certificate],
            signatureAlgorithm: .ecdsaP256SHA256,
            signatureValue: Data([0x11, 0x22])
        )
        let timestampToken = CMSTimeStampToken(derEncoded: TestDER.sequence([
            try TestDER.objectIdentifier("1.2.840.113549.1.7.2"),
            TestDER.explicitContextSpecific(tag: 0, value: TestDER.sequence([]))
        ]))

        let cms = try CMSSignatureBuilder.buildCMS(
            byteRangeBytes: Data("timestamped".utf8),
            identity: identity,
            timestamp: timestampToken,
            signingTime: Date(timeIntervalSince1970: 1_704_067_200)
        )

        XCTAssertTrue(cms.derContainsObjectIdentifier("1.2.840.113549.1.9.16.2.14"), "missing timestamp unsigned attribute")
        XCTAssertTrue(cms.containsSubdata(timestampToken.derEncoded), "timestamp token must be embedded verbatim")
        XCTAssertEqual(identity.signedInputs.count, 1)
    }

    func testBuildCMSRequestsTimestampOverSignatureValue() throws {
        let certificate = TestCertificate.makeDER(serial: Data([0x89, 0xAB]))
        let signatureValue = Data([0xA1, 0xB2, 0xC3])
        let identity = RecordingCMSIdentity(
            certificateDER: certificate,
            certificateChainDER: [certificate],
            signatureAlgorithm: .rsaPKCS1SHA256,
            signatureValue: signatureValue
        )
        let timestampToken = CMSTimeStampToken(derEncoded: TestDER.sequence([
            try TestDER.objectIdentifier("1.2.840.113549.1.7.2"),
            TestDER.explicitContextSpecific(tag: 0, value: TestDER.sequence([
                TestDER.integer(Data([0x01]))
            ]))
        ]))
        var observedSignatureValue: Data?

        let cms = try CMSSignatureBuilder.buildCMS(
            byteRangeBytes: Data("timestamp provider".utf8),
            identity: identity,
            signingTime: Date(timeIntervalSince1970: 1_704_067_200)
        ) { value in
            observedSignatureValue = value
            return timestampToken
        }

        XCTAssertEqual(observedSignatureValue, signatureValue)
        XCTAssertTrue(cms.derContainsObjectIdentifier("1.2.840.113549.1.9.16.2.14"), "missing timestamp unsigned attribute")
        XCTAssertTrue(cms.containsSubdata(timestampToken.derEncoded), "timestamp token must be embedded verbatim")
    }
}

private final class RecordingCMSIdentity: CMSSigningIdentity {
    let certificateDER: Data
    let certificateChainDER: [Data]
    let signatureAlgorithm: CMSSignatureAlgorithm
    let signatureValue: Data
    private(set) var signedInputs: [Data] = []

    init(certificateDER: Data,
         certificateChainDER: [Data],
         signatureAlgorithm: CMSSignatureAlgorithm,
         signatureValue: Data) {
        self.certificateDER = certificateDER
        self.certificateChainDER = certificateChainDER
        self.signatureAlgorithm = signatureAlgorithm
        self.signatureValue = signatureValue
    }

    func sign(_ data: Data) throws -> Data {
        signedInputs.append(data)
        return signatureValue
    }
}

private enum TestCertificate {
    static func makeDER(serial: Data) -> Data {
        let signatureAlgorithm = TestDER.sequence([
            try! TestDER.objectIdentifier("1.2.840.113549.1.1.11"),
            TestDER.null()
        ])
        let name = TestDER.sequence([
            TestDER.set([
                TestDER.sequence([
                    try! TestDER.objectIdentifier("2.5.4.3"),
                    TestDER.utf8String("pdFold Test")
                ])
            ])
        ])
        let validity = TestDER.sequence([
            TestDER.utcTime("240101000000Z"),
            TestDER.utcTime("260101000000Z")
        ])
        let subjectPublicKeyInfo = TestDER.sequence([
            TestDER.sequence([
                try! TestDER.objectIdentifier("1.2.840.113549.1.1.1"),
                TestDER.null()
            ]),
            TestDER.bitString(Data([0x00]))
        ])
        let tbsCertificate = TestDER.sequence([
            TestDER.explicitContextSpecific(tag: 0, value: TestDER.integer(Data([0x02]))),
            TestDER.integer(serial),
            signatureAlgorithm,
            name,
            validity,
            name,
            subjectPublicKeyInfo
        ])

        return TestDER.sequence([
            tbsCertificate,
            signatureAlgorithm,
            TestDER.bitString(Data([0x00]))
        ])
    }
}

private enum TestDER {
    static func sequence(_ values: [Data]) -> Data {
        tagged(0x30, values.concatenatedForTest())
    }

    static func set(_ values: [Data]) -> Data {
        tagged(0x31, values.sorted { $0.lexicographicallyPrecedesForTest($1) }.concatenatedForTest())
    }

    static func integer(_ value: Data) -> Data {
        tagged(0x02, value)
    }

    static func bitString(_ value: Data) -> Data {
        tagged(0x03, value)
    }

    static func null() -> Data {
        tagged(0x05, Data())
    }

    static func objectIdentifier(_ oid: String) throws -> Data {
        let components = oid.split(separator: ".").compactMap { UInt64($0) }
        guard components.count >= 2 else {
            throw CMSSignatureBuilderError.invalidObjectIdentifier(oid)
        }
        var body = Data(base128(components[0] * 40 + components[1]))
        for component in components.dropFirst(2) {
            body.append(contentsOf: base128(component))
        }
        return tagged(0x06, body)
    }

    static func utf8String(_ value: String) -> Data {
        tagged(0x0C, Data(value.utf8))
    }

    static func utcTime(_ value: String) -> Data {
        tagged(0x17, Data(value.utf8))
    }

    static func explicitContextSpecific(tag: UInt8, value: Data) -> Data {
        tagged(0xA0 | tag, value)
    }

    private static func tagged(_ tag: UInt8, _ contents: Data) -> Data {
        var result = Data([tag])
        result.append(length(contents.count))
        result.append(contents)
        return result
    }

    private static func length(_ count: Int) -> Data {
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

private extension Data {
    func derContainsObjectIdentifier(_ oid: String) -> Bool {
        (try? containsSubdata(TestDER.objectIdentifier(oid))) ?? false
    }

    func containsSubdata(_ needle: Data) -> Bool {
        guard !needle.isEmpty else {
            return true
        }
        return range(of: needle) != nil
    }

    func lexicographicallyPrecedesForTest(_ other: Data) -> Bool {
        for (lhs, rhs) in zip(self, other) {
            if lhs != rhs {
                return lhs < rhs
            }
        }
        return count < other.count
    }
}

private extension Array where Element == Data {
    func concatenatedForTest() -> Data {
        var result = Data()
        forEach { result.append($0) }
        return result
    }
}
