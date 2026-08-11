import Foundation
import Security
import SwiftASN1
@_spi(CMS) import X509

enum PDFSignatureIntegrityVerdict: Equatable {
    case valid
    case invalid
}

enum PDFSignatureTrustVerdict: Equatable {
    case trusted
    case revoked
    case notTrusted
    case unavailable
}

enum PDFSignatureCoverageVerdict: Equatable {
    case entireDocument
    case changedAfterSigning
    case invalid
}

struct PDFSignatureValidation: Identifiable, Equatable {
    var id: String
    var signerCommonName: String
    var signingTime: Date?
    var isTimestamped: Bool
    var integrity: PDFSignatureIntegrityVerdict
    var trust: PDFSignatureTrustVerdict
    var coverage: PDFSignatureCoverageVerdict
    var signedFileLength: Int
}

/// Structure-only data extracted from an AcroForm signature dictionary by qpdf. CMS parsing
/// and all cryptographic decisions remain in swift-certificates.
struct QPDFSignatureDictionary {
    var id: String
    var byteRange: SignatureByteRange?
    var contents: Data?
    var signerName: String?
    var signingTime: Date?
}

enum PDFSignatureValidationService {
    static func validate(pdf: Data) async -> [PDFSignatureValidation] {
        let dictionaries = QPDFService.signatureDictionaries(in: pdf)
        return await dictionaries.asyncMap { dictionary in
            await validate(dictionary: dictionary, pdf: pdf)
        }
    }

    private static func validate(dictionary: QPDFSignatureDictionary,
                                 pdf: Data) async -> PDFSignatureValidation {
        let (coverage, signedFileLength) = coverageVerdict(
            for: dictionary.byteRange,
            contents: dictionary.contents,
            pdf: pdf
        )

        guard let range = dictionary.byteRange,
              let paddedContents = dictionary.contents,
              let cmsData = firstDERObject(in: paddedContents),
              let digestInput = try? PDFByteRangeCalculator.digestInput(pdf: pdf, range: range) else {
            return PDFSignatureValidation(
                id: dictionary.id,
                signerCommonName: dictionary.signerName ?? L10n.string("signature.validation.unknownSigner"),
                signingTime: dictionary.signingTime,
                isTimestamped: false,
                integrity: .invalid,
                trust: .unavailable,
                coverage: coverage,
                signedFileLength: signedFileLength
            )
        }

        // The pinned verifier accepts CMS SignedData v3, while its convenience
        // `CMSSignature` metadata view accepts only v1/v4. Never gate integrity on that
        // narrower view: a valid v3 signature still receives a cryptographic verdict.
        let signature = try? CMSSignature(derEncoded: [UInt8](cmsData))
        let signer = signature.flatMap { ((try? $0.signers) ?? []).first }
        let signerCommonName = signer.flatMap { commonName(from: $0.certificate) }
            ?? dictionary.signerName
            ?? L10n.string("signature.validation.unknownSigner")
        let integrity = await integrityVerdict(of: cmsData, digestInput: digestInput)
        let trust: PDFSignatureTrustVerdict
        if let signature {
            trust = await trustVerdict(of: signature)
        } else {
            trust = .unavailable
        }

        return PDFSignatureValidation(
            id: dictionary.id,
            signerCommonName: signerCommonName,
            signingTime: signer?.signingTime ?? dictionary.signingTime,
            // The pinned CMS metadata API does not expose a structurally parsed and
            // cryptographically verified RFC 3161 token. A raw OID byte match is not proof,
            // so every displayed signing time remains explicitly unverified.
            isTimestamped: false,
            integrity: integrity,
            trust: trust,
            coverage: coverage,
            signedFileLength: signedFileLength
        )
    }

    static func coverageVerdict(for range: SignatureByteRange?,
                                contents: Data?,
                                pdf: Data) -> (PDFSignatureCoverageVerdict, Int) {
        guard let range, range.afterLength >= 0 else { return (.invalid, 0) }
        let (signedFileLength, overflow) = range.afterOffset.addingReportingOverflow(
            range.afterLength
        )
        guard !overflow,
              signedFileLength > 0,
              signedFileLength <= pdf.count,
              contentsGapMatches(pdf: pdf, range: range, contents: contents) else {
            return (.invalid, overflow ? 0 : signedFileLength)
        }
        if signedFileLength == pdf.count {
            return (.entireDocument, signedFileLength)
        }
        return (.changedAfterSigning, signedFileLength)
    }

    /// Proves that the excluded ByteRange gap is precisely this dictionary's hex
    /// `/Contents` value. Merely ending at EOF is not enough: an attacker could otherwise
    /// omit arbitrary bytes inside a larger gap and receive a false full-coverage verdict.
    private static func contentsGapMatches(pdf: Data,
                                           range: SignatureByteRange,
                                           contents: Data?) -> Bool {
        guard range.beforeOffset == 0,
              range.beforeLength >= 0,
              range.afterOffset > range.beforeLength,
              range.afterOffset <= pdf.count,
              let contents else { return false }
        let gap = pdf[range.beforeLength..<range.afterOffset]
        guard gap.first == UInt8(ascii: "<"), gap.last == UInt8(ascii: ">") else {
            return false
        }

        let prefixStart = max(0, range.beforeLength - 64)
        let prefix = pdf[prefixStart..<range.beforeLength]
            .reversed()
            .drop(while: isPDFWhitespace)
            .reversed()
        guard prefix.suffix(Data("/Contents".utf8).count)
            .elementsEqual(Data("/Contents".utf8)) else { return false }

        var decoded = Data()
        var highNibble: UInt8?
        for byte in gap.dropFirst().dropLast() where !isPDFWhitespace(byte) {
            guard let nibble = hexNibble(byte) else { return false }
            if let high = highNibble {
                decoded.append((high << 4) | nibble)
                highNibble = nil
            } else {
                highNibble = nibble
            }
        }
        guard highNibble == nil else { return false }
        return decoded == contents
    }

    private static func isPDFWhitespace(_ byte: UInt8) -> Bool {
        byte == 0 || byte == 9 || byte == 10 || byte == 12 || byte == 13 || byte == 32
    }

    private static func hexNibble(_ byte: UInt8) -> UInt8? {
        switch byte {
        case 48...57: return byte - 48
        case 65...70: return byte - 55
        case 97...102: return byte - 87
        default: return nil
        }
    }

    private static func integrityVerdict(of cmsData: Data,
                                         digestInput: Data) async -> PDFSignatureIntegrityVerdict {
        let verification = await CMS.isValidSignature(
            dataBytes: digestInput,
            signatureBytes: cmsData,
            trustRoots: CertificateStore(),
            microsoftCompatible: true
        ) {
            RFC5280Policy()
        }
        switch verification {
        case .success, .failure(.unableToValidateSigner):
            // swift-certificates checks the digest and public-key signature before its chain
            // search. This failure therefore still proves integrity; trust is separate below.
            return .valid
        case .failure(.invalidCMSBlock):
            return .invalid
        }
    }

    private static func trustVerdict(of signature: CMSSignature) async -> PDFSignatureTrustVerdict {
        let certificateDER = signature.certificates.compactMap(derEncoded)
        guard !certificateDER.isEmpty else { return .unavailable }

        let signer = ((try? signature.signers) ?? []).first
        let chain = signer.map { signerCertificate in
            let leaf = derEncoded(signerCertificate.certificate)
            return ([leaf].compactMap { $0 } + certificateDER).uniqued()
        } ?? certificateDER
        guard let evaluation = try? await CertificateTrustEvaluator.evaluate(
            certificateChainDER: chain,
            checksRevocation: false
        ) else {
            return .unavailable
        }
        switch evaluation.verdict {
        case .trusted:
            return .trusted
        case .revoked:
            return .revoked
        case .notTrusted:
            return .notTrusted
        }
    }

    /// `/Contents` is a fixed-capacity PDF string, so the CMS DER is followed by zero
    /// padding. Read only the first DER object's declared length before handing it to the
    /// pinned library; no CMS fields or signatures are interpreted here.
    private static func firstDERObject(in data: Data) -> Data? {
        guard data.count >= 2 else { return nil }
        let bytes = [UInt8](data)
        let lengthByte = bytes[1]
        let headerLength: Int
        let contentLength: Int
        if lengthByte & 0x80 == 0 {
            headerLength = 2
            contentLength = Int(lengthByte)
        } else {
            let lengthBytes = Int(lengthByte & 0x7F)
            guard lengthBytes > 0, lengthBytes <= MemoryLayout<Int>.size,
                  bytes.count >= 2 + lengthBytes else { return nil }
            headerLength = 2 + lengthBytes
            var parsedLength = 0
            for byte in bytes[2..<(2 + lengthBytes)] {
                let (shifted, shiftOverflow) = parsedLength.multipliedReportingOverflow(by: 256)
                let (next, addOverflow) = shifted.addingReportingOverflow(Int(byte))
                guard !shiftOverflow, !addOverflow else { return nil }
                parsedLength = next
            }
            contentLength = parsedLength
        }
        guard contentLength >= 0,
              headerLength <= data.count,
              contentLength <= data.count - headerLength else { return nil }
        return data.prefix(headerLength + contentLength)
    }

    private static func derEncoded(_ certificate: Certificate) -> Data? {
        var serializer = DER.Serializer()
        guard (try? serializer.serialize(certificate)) != nil else { return nil }
        return Data(serializer.serializedBytes)
    }

    private static func commonName(from certificate: Certificate) -> String? {
        guard let der = derEncoded(certificate),
              let securityCertificate = SecCertificateCreateWithData(nil, der as CFData) else {
            return nil
        }
        var commonName: CFString?
        guard SecCertificateCopyCommonName(securityCertificate, &commonName) == errSecSuccess else {
            return nil
        }
        return commonName as String?
    }
}

private extension Array where Element == Data {
    func uniqued() -> [Data] {
        var seen = Set<Data>()
        return filter { seen.insert($0).inserted }
    }
}

private extension Array {
    func asyncMap<T>(_ transform: (Element) async -> T) async -> [T] {
        var results: [T] = []
        results.reserveCapacity(count)
        for element in self {
            results.append(await transform(element))
        }
        return results
    }
}
