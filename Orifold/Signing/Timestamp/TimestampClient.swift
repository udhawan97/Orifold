import CryptoKit
import Foundation

struct TimeStampToken: Equatable {
    let derEncoded: Data
    let messageImprint: Data

    init(derEncoded: Data) throws {
        self.derEncoded = derEncoded
        self.messageImprint = try TimestampASN1.validateTimeStampToken(derEncoded)
    }

    fileprivate init(validatedDER: Data, messageImprint: Data) {
        self.derEncoded = validatedDER
        self.messageImprint = messageImprint
    }
}

extension TimeStampToken {
    var cmsTimeStampToken: CMSTimeStampToken {
        CMSTimeStampToken(derEncoded: derEncoded)
    }
}

extension CMSTimeStampToken {
    init(_ token: TimeStampToken) {
        self.init(derEncoded: token.derEncoded)
    }
}

enum TimestampClientError: Error, Equatable, LocalizedError {
    case invalidResponse(String)
    case tsaRejected(status: Int, statusString: [String], failureInfo: Data?)
    case missingToken(status: Int)
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse(let message):
            return "Invalid timestamp response: \(message)"
        case .tsaRejected(let status, let statusString, _):
            let detail = statusString.isEmpty ? "" : " (\(statusString.joined(separator: "; ")))"
            return "Timestamp authority rejected the request with status \(status)\(detail)."
        case .missingToken(let status):
            return "Timestamp authority returned granted status \(status) without a TimeStampToken."
        case .httpStatus(let status):
            return "Timestamp authority returned HTTP \(status)."
        }
    }
}

protocol TimestampNetworking {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: TimestampNetworking {}

struct TimestampClient {
    static let defaultTSAURL = URL(string: "https://freetsa.org/tsr")!

    var session: TimestampNetworking

    init(session: TimestampNetworking = URLSession.shared) {
        self.session = session
    }

    func fetchTimestamp(for signatureValue: Data,
                        tsaURL: URL = TimestampClient.defaultTSAURL) async throws -> TimeStampToken {
        let messageImprint = TimestampRequestEncoder.sha256Digest(of: signatureValue)
        let requestBody = TimestampRequestEncoder.requestBody(
            messageImprint: messageImprint,
            nonce: TimestampRequestEncoder.randomNonce(),
            certReq: true
        )

        var request = URLRequest(url: tsaURL)
        request.httpMethod = "POST"
        request.httpBody = requestBody
        request.setValue("application/timestamp-query", forHTTPHeaderField: "Content-Type")
        request.setValue("application/timestamp-reply", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            throw TimestampClientError.httpStatus(httpResponse.statusCode)
        }

        do {
            return try TimestampResponseParser.parse(data, expectedMessageImprint: messageImprint)
        } catch let error as TimestampClientError {
            throw error
        } catch let error as TimestampASN1Error {
            throw TimestampClientError.invalidResponse(error.localizedDescription)
        } catch {
            throw error
        }
    }
}

func fetchTimestamp(for signatureValue: Data, tsaURL: URL) async throws -> TimeStampToken {
    try await TimestampClient().fetchTimestamp(for: signatureValue, tsaURL: tsaURL)
}

enum TimestampRequestEncoder {
    static func sha256Digest(of data: Data) -> Data {
        Data(SHA256.hash(data: data))
    }

    static func requestBody(for signatureValue: Data,
                            nonce: Data? = randomNonce(),
                            certReq: Bool = true) -> Data {
        requestBody(messageImprint: sha256Digest(of: signatureValue), nonce: nonce, certReq: certReq)
    }

    static func requestBody(messageImprint: Data,
                            nonce: Data? = nil,
                            certReq: Bool = true) -> Data {
        precondition(messageImprint.count == 32)

        let algorithmIdentifier = TimestampASN1.encodeSequence([
            TimestampASN1.encodeObjectIdentifier(TimestampASN1.sha256AlgorithmIdentifier)
        ])
        let messageImprint = TimestampASN1.encodeSequence([
            algorithmIdentifier,
            TimestampASN1.encodeOctetString(messageImprint)
        ])

        var fields = [
            TimestampASN1.encodeInteger(1),
            messageImprint
        ]

        if let nonce {
            fields.append(TimestampASN1.encodePositiveInteger(nonce))
        }
        if certReq {
            fields.append(TimestampASN1.encodeBoolean(true))
        }

        return TimestampASN1.encodeSequence(fields)
    }

    static func randomNonce() -> Data {
        var generator = SystemRandomNumberGenerator()
        return Data((0..<16).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
    }
}

struct TimestampStatusInfo: Equatable {
    let status: Int
    let statusString: [String]
    let failureInfo: Data?

    var isGranted: Bool {
        status == 0 || status == 1
    }
}

enum TimestampResponseParser {
    static func parse(_ data: Data, expectedMessageImprint: Data? = nil) throws -> TimeStampToken {
        var reader = DERReader(data: data)
        let response = try reader.readElement(expectedTag: 0x30, name: "TimeStampResp")
        try reader.requireEnd()

        var responseReader = DERReader(data: response.value)
        let statusElement = try responseReader.readElement(expectedTag: 0x30, name: "TimeStampResp.status")
        let statusInfo = try parseStatusInfo(statusElement.value)

        guard statusInfo.isGranted else {
            throw TimestampClientError.tsaRejected(
                status: statusInfo.status,
                statusString: statusInfo.statusString,
                failureInfo: statusInfo.failureInfo
            )
        }

        guard !responseReader.isAtEnd else {
            throw TimestampClientError.missingToken(status: statusInfo.status)
        }

        let tokenElement = try responseReader.readElement(name: "TimeStampResp.timeStampToken")
        try responseReader.requireEnd()

        let imprint = try TimestampASN1.validateTimeStampToken(
            tokenElement.encoded,
            expectedMessageImprint: expectedMessageImprint
        )
        return TimeStampToken(validatedDER: tokenElement.encoded, messageImprint: imprint)
    }

    private static func parseStatusInfo(_ data: Data) throws -> TimestampStatusInfo {
        var reader = DERReader(data: data)
        let status = try reader.readInteger(name: "PKIStatusInfo.status")

        var strings: [String] = []
        if reader.peekTag() == 0x30 {
            let freeText = try reader.readElement(expectedTag: 0x30, name: "PKIStatusInfo.statusString")
            var freeTextReader = DERReader(data: freeText.value)
            while !freeTextReader.isAtEnd {
                strings.append(try freeTextReader.readUTF8String(name: "PKIFreeText"))
            }
        }

        var failureInfo: Data?
        if reader.peekTag() == 0x03 {
            failureInfo = try reader.readBitString(name: "PKIStatusInfo.failInfo")
        }

        try reader.requireEnd()
        return TimestampStatusInfo(status: status, statusString: strings, failureInfo: failureInfo)
    }
}
