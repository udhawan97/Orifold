import CryptoKit
import Foundation
import XCTest
@testable import PDFold

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
    func testGrantedResponseExtractsTheTimestampToken() throws {
        let imprint = Data(repeating: 0xA5, count: 32)
        let token = makeTimeStampToken(messageImprint: imprint)
        let response = makeTimeStampResponse(status: 0, token: token)

        let parsed = try TimestampResponseParser.parse(response, expectedMessageImprint: imprint)

        XCTAssertEqual(parsed.derEncoded, token)
        XCTAssertEqual(parsed.messageImprint, imprint)
    }

    func testGrantedResponseRejectsMismatchedMessageImprint() throws {
        let token = makeTimeStampToken(messageImprint: Data(repeating: 0xA5, count: 32))
        let response = makeTimeStampResponse(status: 0, token: token)

        XCTAssertThrowsError(
            try TimestampResponseParser.parse(response, expectedMessageImprint: Data(repeating: 0x5A, count: 32))
        ) { error in
            XCTAssertTrue(String(describing: error).contains("messageImprint"))
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
    func testClientPostsTimestampQueryAndParsesReply() async throws {
        let signatureValue = Data("cms-signature-value".utf8)
        let imprint = Data(SHA256.hash(data: signatureValue))
        let responseBody = makeTimeStampResponse(
            status: 0,
            token: makeTimeStampToken(messageImprint: imprint)
        )
        let session = StubTimestampSession(data: responseBody, statusCode: 200)
        let tsaURL = URL(string: "https://tsa.example.test/tsr")!

        let token = try await TimestampClient(session: session).fetchTimestamp(
            for: signatureValue,
            tsaURL: tsaURL
        )

        XCTAssertEqual(token.messageImprint, imprint)
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
