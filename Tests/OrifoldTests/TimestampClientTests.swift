import CryptoKit
import Foundation
import XCTest
@testable import Orifold

final class TimestampRequestEncoderTests: XCTestCase {
    func testRequestBodyContainsSHA256MessageImprintNonceAndCertReq() throws {
        let signatureValue = Data("signer-info-signature".utf8)
        let expectedImprint = Data(SHA256.hash(data: signatureValue))
        let body = TimestampRequestEncoder.requestBody(
            for: signatureValue,
            nonce: Data([0x01, 0x02, 0x03, 0x04]),
            certReq: true
        )

        var reader = DERReader(data: body)
        let request = try reader.readElement(expectedTag: 0x30, name: "TimeStampReq")
        try reader.requireEnd()

        var requestReader = DERReader(data: request.value)
        XCTAssertEqual(try requestReader.readInteger(name: "TimeStampReq.version"), 1)

        let messageImprint = try requestReader.readElement(expectedTag: 0x30, name: "TimeStampReq.messageImprint")
        XCTAssertEqual(try TimestampASN1.parseMessageImprint(messageImprint.value), expectedImprint)

        XCTAssertEqual(try requestReader.readInteger(name: "TimeStampReq.nonce"), 0x01020304)
        let certReq = try requestReader.readElement(expectedTag: 0x01, name: "TimeStampReq.certReq")
        XCTAssertEqual(certReq.value, Data([0xFF]))
        try requestReader.requireEnd()
    }
}

final class TimestampResponseParserTests: XCTestCase {
    func testGrantedResponseRejectsStructurallyValidButUnverifiedTimestampToken() throws {
        let imprint = Data(repeating: 0xA5, count: 32)
        let token = makeTimeStampToken(messageImprint: imprint)
        let response = makeTimeStampResponse(status: 0, token: token)

        XCTAssertThrowsError(
            try TimestampResponseParser.parse(response, expectedMessageImprint: imprint)
        ) { error in
            XCTAssertEqual(error as? TimestampASN1Error, .unsupportedTrustValidation)
        }
    }

    func testGrantedResponseRejectsMismatchedMessageImprint() throws {
        let token = makeTimeStampToken(messageImprint: Data(repeating: 0xA5, count: 32))
        let response = makeTimeStampResponse(status: 0, token: token)

        XCTAssertThrowsError(
            try TimestampResponseParser.parse(response, expectedMessageImprint: Data(repeating: 0x5A, count: 32))
        ) { error in
            XCTAssertEqual(
                error as? TimestampASN1Error,
                .invalidDER("TimeStampToken messageImprint does not match the request")
            )
        }
    }

    func testRejectedResponseThrowsStatusDetails() throws {
        let response = makeTimeStampResponse(
            status: 2,
            statusStrings: ["bad request"],
            failureInfo: Data([0x00, 0x80])
        )

        XCTAssertThrowsError(try TimestampResponseParser.parse(response)) { error in
            XCTAssertEqual(
                error as? TimestampClientError,
                .tsaRejected(status: 2, statusString: ["bad request"], failureInfo: Data([0x00, 0x80]))
            )
        }
    }

    func testGrantedResponseWithoutTokenThrows() throws {
        let response = makeTimeStampResponse(status: 0)

        XCTAssertThrowsError(try TimestampResponseParser.parse(response)) { error in
            XCTAssertEqual(error as? TimestampClientError, .missingToken(status: 0))
        }
    }
}

final class TimestampClientTests: XCTestCase {
    func testClientPostsTimestampQueryButRejectsUnverifiedReply() async throws {
        let signatureValue = Data("cms-signature-value".utf8)
        let imprint = Data(SHA256.hash(data: signatureValue))
        let responseBody = makeTimeStampResponse(
            status: 0,
            token: makeTimeStampToken(messageImprint: imprint)
        )
        let session = StubTimestampSession(data: responseBody, statusCode: 200)
        let tsaURL = URL(string: "https://tsa.example.test/tsr")!

        do {
            _ = try await TimestampClient(session: session).fetchTimestamp(
                for: signatureValue,
                tsaURL: tsaURL
            )
            XCTFail("Expected the unverified timestamp token to be rejected")
        } catch {
            XCTAssertEqual(error as? TimestampClientError, .trustValidationUnavailable)
        }
        let request = try XCTUnwrap(session.request)
        XCTAssertEqual(request.url, tsaURL)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/timestamp-query")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/timestamp-reply")
        XCTAssertFalse((request.httpBody ?? Data()).isEmpty)
    }

    func testClientThrowsForHTTPFailure() async {
        let session = StubTimestampSession(data: Data(), statusCode: 503)
        let tsaURL = URL(string: "https://tsa.example.test/tsr")!

        do {
            _ = try await TimestampClient(session: session).fetchTimestamp(for: Data([0x01]), tsaURL: tsaURL)
            XCTFail("Expected HTTP failure")
        } catch {
            XCTAssertEqual(error as? TimestampClientError, .httpStatus(503))
        }
    }
}

final class TimestampAuthorityFallbackChainTests: XCTestCase {
    func testUnverifiedTokensFromEveryTSAAreRejected() async {
        let imprint = Data(SHA256.hash(data: Data("cms-signature-value".utf8)))
        let goodResponse = makeTimeStampResponse(status: 0, token: makeTimeStampToken(messageImprint: imprint))
        let session = RoutingStubTimestampSession(responses: Dictionary(
            uniqueKeysWithValues: TimestampAuthorityOption.allCases.map { ($0.url, .success(data: goodResponse)) }
        ))

        do {
            _ = try await TimestampAuthorityFallbackChain.fetchTimestamp(
                for: Data("cms-signature-value".utf8),
                preferring: .freeTSA,
                client: TimestampClient(session: session)
            )
            XCTFail("Expected every structurally valid but unverified token to fail closed")
        } catch {
            XCTAssertEqual(error as? TimestampClientError, .trustValidationUnavailable)
        }
        XCTAssertEqual(session.requestedURLsInOrder, TimestampAuthorityOption.allCases.map(\.url))
    }

    func testThrowsTheLastErrorWhenEveryTSAFails() async {
        let session = RoutingStubTimestampSession(responses: [:], defaultStatusCode: 503)

        do {
            _ = try await TimestampAuthorityFallbackChain.fetchTimestamp(
                for: Data([0x01]),
                preferring: .sectigo,
                client: TimestampClient(session: session)
            )
            XCTFail("Expected every TSA in the fallback chain to fail")
        } catch {
            XCTAssertEqual(error as? TimestampClientError, .httpStatus(503))
        }
        XCTAssertEqual(session.requestedURLsInOrder.count, TimestampAuthorityOption.allCases.count,
                       "must try every option in the chain before giving up")
    }

    func testOnAttemptFiresForEveryOptionTriedInOrder() async {
        let session = RoutingStubTimestampSession(responses: [:], defaultStatusCode: 503)
        final class AttemptLog: @unchecked Sendable {
            var options: [TimestampAuthorityOption] = []
        }
        let log = AttemptLog()

        _ = try? await TimestampAuthorityFallbackChain.fetchTimestamp(
            for: Data([0x01]),
            preferring: .globalSign,
            client: TimestampClient(session: session),
            onAttempt: { log.options.append($0) }
        )

        // Lets a progress UI show which TSA is currently being contacted instead of
        // freezing on one static message while several endpoints are tried in sequence.
        XCTAssertEqual(log.options, [.globalSign, .freeTSA, .digiCert, .sectigo],
                       "onAttempt must fire once per option, preferred first, in the exact order they're tried")
    }
}

final class TimestampEmbeddingPolicyTests: XCTestCase {
    func testTrustBoundaryFailureProducesWarnedUnstampedDecision() throws {
        let decision = try TimestampEmbeddingPolicy.resolve(requested: true) {
            throw TimestampClientError.trustValidationUnavailable
        }

        XCTAssertEqual(decision.state, .unavailable)
        XCTAssertNil(decision.token)
        XCTAssertFalse(decision.timestampWasApplied)
        XCTAssertEqual(decision.warningLocalizationKey, "status.sign.timestampUnavailable")
    }

    func testSigningCancellationIsNotConvertedToTimestampFallback() {
        XCTAssertThrowsError(
            try TimestampEmbeddingPolicy.resolve(requested: true) {
                throw SigningError.cancelled
            }
        ) { error in
            XCTAssertEqual(error as? SigningError, .cancelled)
        }
    }

    func testTaskCancellationIsNotConvertedToTimestampFallback() {
        XCTAssertThrowsError(
            try TimestampEmbeddingPolicy.resolve(requested: true) {
                throw CancellationError()
            }
        ) { error in
            XCTAssertEqual(error as? SigningError, .cancelled)
        }
    }

    func testURLSessionCancellationIsNotConvertedToTimestampFallback() {
        XCTAssertThrowsError(
            try TimestampEmbeddingPolicy.resolve(requested: true) {
                throw URLError(.cancelled)
            }
        ) { error in
            XCTAssertEqual(error as? SigningError, .cancelled)
        }
    }
}

final class TimestampLocalizationContractTests: XCTestCase {
    func testTimestampTruthCopyShipsInEverySupportedLanguage() throws {
        let catalogURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Orifold/Resources/Localizable.xcstrings")
        let root = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(contentsOf: catalogURL)) as? [String: Any]
        )
        let strings = try XCTUnwrap(root["strings"] as? [String: Any])
        let requiredLanguages: Set<String> = ["en", "es", "fr", "hi", "ja", "zh-Hans"]
        let keys = [
            "error.signing.timestampUnavailable",
            "signProgress.timestamping",
            "signProgress.timestampingWithProvider",
            "signaturePalette.digital.timestamp.help",
            "signaturePalette.digital.tsaProvider.help",
            "status.sign.timestampUnavailable"
        ]

        for key in keys {
            let entry = try XCTUnwrap(strings[key] as? [String: Any], "missing \(key)")
            let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any], "missing locales for \(key)")
            XCTAssertEqual(Set(localizations.keys), requiredLanguages, "\(key) must ship in all six languages")
            for language in requiredLanguages {
                let payload = try XCTUnwrap(localizations[language] as? [String: Any])
                let unit = try XCTUnwrap(payload["stringUnit"] as? [String: Any])
                let value = try XCTUnwrap(unit["value"] as? String)
                XCTAssertFalse(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "\(key) [\(language)]")
            }
        }

        let timestampHelp = try localizedValue(
            key: "signaturePalette.digital.timestamp.help",
            language: "en",
            strings: strings
        )
        XCTAssertTrue(timestampHelp.contains("do not embed or mark"))
        XCTAssertTrue(timestampHelp.contains("never your document"))
        XCTAssertTrue(timestampHelp.contains("PAdES B-B"))
    }

    private func localizedValue(
        key: String,
        language: String,
        strings: [String: Any]
    ) throws -> String {
        let entry = try XCTUnwrap(strings[key] as? [String: Any])
        let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any])
        let payload = try XCTUnwrap(localizations[language] as? [String: Any])
        let unit = try XCTUnwrap(payload["stringUnit"] as? [String: Any])
        return try XCTUnwrap(unit["value"] as? String)
    }
}

private final class RoutingStubTimestampSession: TimestampNetworking {
    enum StubResponse {
        case success(data: Data)
        case failure(statusCode: Int)
    }

    private let responses: [URL: StubResponse]
    private let defaultStatusCode: Int
    private(set) var requestedURLsInOrder: [URL] = []

    init(responses: [URL: StubResponse], defaultStatusCode: Int = 200) {
        self.responses = responses
        self.defaultStatusCode = defaultStatusCode
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let url = request.url!
        requestedURLsInOrder.append(url)
        switch responses[url] {
        case .success(let data):
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (data, response)
        case .failure(let statusCode):
            let response = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (Data(), response)
        case nil:
            let response = HTTPURLResponse(url: url, statusCode: defaultStatusCode, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (Data(), response)
        }
    }
}

private final class StubTimestampSession: TimestampNetworking {
    private let data: Data
    private let statusCode: Int
    private(set) var request: URLRequest?

    init(data: Data, statusCode: Int) {
        self.data = data
        self.statusCode = statusCode
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        self.request = request
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/timestamp-reply"]
        )!
        return (data, response)
    }
}

private func makeTimeStampResponse(status: Int,
                                   statusStrings: [String] = [],
                                   failureInfo: Data? = nil,
                                   token: Data? = nil) -> Data {
    var statusInfoFields = [TimestampASN1.encodeInteger(status)]
    if !statusStrings.isEmpty {
        statusInfoFields.append(TimestampASN1.encodeSequence(statusStrings.map(TimestampASN1.encodeUTF8String)))
    }
    if let failureInfo {
        statusInfoFields.append(TimestampASN1.encode(tag: 0x03, value: failureInfo))
    }

    var responseFields = [TimestampASN1.encodeSequence(statusInfoFields)]
    if let token {
        responseFields.append(token)
    }

    return TimestampASN1.encodeSequence(responseFields)
}

private func makeTimeStampToken(messageImprint: Data) -> Data {
    let sha256Algorithm = TimestampASN1.encodeSequence([
        TimestampASN1.encodeObjectIdentifier(TimestampASN1.sha256AlgorithmIdentifier)
    ])
    let digestAlgorithms = TimestampASN1.encodeSet([sha256Algorithm])
    let tstMessageImprint = TimestampASN1.encodeSequence([
        sha256Algorithm,
        TimestampASN1.encodeOctetString(messageImprint)
    ])
    let tstInfo = TimestampASN1.encodeSequence([
        TimestampASN1.encodeInteger(1),
        TimestampASN1.encodeObjectIdentifier([1, 2, 3, 4]),
        tstMessageImprint,
        TimestampASN1.encodeInteger(1),
        TimestampASN1.encodeGeneralizedTime("20260701000000Z")
    ])
    let encapContentInfo = TimestampASN1.encodeSequence([
        TimestampASN1.encodeObjectIdentifier(TimestampASN1.tstInfoContentType),
        TimestampASN1.encodeExplicitContext0(TimestampASN1.encodeOctetString(tstInfo))
    ])
    let signedData = TimestampASN1.encodeSequence([
        TimestampASN1.encodeInteger(3),
        digestAlgorithms,
        encapContentInfo,
        TimestampASN1.encodeSet([])
    ])

    return TimestampASN1.encodeSequence([
        TimestampASN1.encodeObjectIdentifier(TimestampASN1.signedDataContentType),
        TimestampASN1.encodeExplicitContext0(signedData)
    ])
}
