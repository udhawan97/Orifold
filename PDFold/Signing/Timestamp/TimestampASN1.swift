import Foundation

enum TimestampASN1Error: Error, Equatable, LocalizedError {
    case invalidDER(String)

    var errorDescription: String? {
        switch self {
        case .invalidDER(let message):
            return "Invalid DER: \(message)"
        }
    }
}

enum TimestampASN1 {
    static let sha256AlgorithmIdentifier = [2, 16, 840, 1, 101, 3, 4, 2, 1]
    static let signedDataContentType = [1, 2, 840, 113549, 1, 7, 2]
    static let tstInfoContentType = [1, 2, 840, 113549, 1, 9, 16, 1, 4]

    static func encodeSequence(_ values: [Data]) -> Data {
        encode(tag: 0x30, value: values.concatenated())
    }

    static func encodeSet(_ values: [Data]) -> Data {
        encode(tag: 0x31, value: values.concatenated())
    }

    static func encodeExplicitContext0(_ value: Data) -> Data {
        encode(tag: 0xA0, value: value)
    }

    static func encodeInteger(_ value: Int) -> Data {
        precondition(value >= 0)
        if value == 0 {
            return encode(tag: 0x02, value: Data([0]))
        }

        var remaining = value
        var bytes: [UInt8] = []
        while remaining > 0 {
            bytes.insert(UInt8(remaining & 0xFF), at: 0)
            remaining >>= 8
        }

        if let first = bytes.first, first & 0x80 != 0 {
            bytes.insert(0, at: 0)
        }

        return encode(tag: 0x02, value: Data(bytes))
    }

    static func encodePositiveInteger(_ bytes: Data) -> Data {
        let normalized = bytes.drop { $0 == 0 }
        var value = normalized.isEmpty ? Data([0]) : Data(normalized)

        if let first = value.first, first & 0x80 != 0 {
            value.insert(0, at: 0)
        }

        return encode(tag: 0x02, value: value)
    }

    static func encodeBoolean(_ value: Bool) -> Data {
        encode(tag: 0x01, value: Data([value ? 0xFF : 0x00]))
    }

    static func encodeObjectIdentifier(_ arcs: [Int]) -> Data {
        precondition(arcs.count >= 2)
        precondition((0...2).contains(arcs[0]))
        precondition(arcs[1] >= 0)
        precondition(arcs[0] < 2 ? arcs[1] < 40 : true)

        var bytes = Data([UInt8(arcs[0] * 40 + arcs[1])])
        for arc in arcs.dropFirst(2) {
            precondition(arc >= 0)
            bytes.append(contentsOf: base128(arc))
        }

        return encode(tag: 0x06, value: bytes)
    }

    static func encodeOctetString(_ value: Data) -> Data {
        encode(tag: 0x04, value: value)
    }

    static func encodeUTF8String(_ value: String) -> Data {
        encode(tag: 0x0C, value: Data(value.utf8))
    }

    static func encodeGeneralizedTime(_ value: String) -> Data {
        encode(tag: 0x18, value: Data(value.utf8))
    }

    static func encode(tag: UInt8, value: Data) -> Data {
        var data = Data([tag])
        data.append(encodeLength(value.count))
        data.append(value)
        return data
    }

    static func encodeLength(_ length: Int) -> Data {
        precondition(length >= 0)
        if length < 0x80 {
            return Data([UInt8(length)])
        }

        var remaining = length
        var bytes: [UInt8] = []
        while remaining > 0 {
            bytes.insert(UInt8(remaining & 0xFF), at: 0)
            remaining >>= 8
        }

        return Data([0x80 | UInt8(bytes.count)] + bytes)
    }

    static func validateTimeStampToken(_ data: Data, expectedMessageImprint: Data? = nil) throws -> Data {
        var reader = DERReader(data: data)
        let contentInfo = try reader.readElement(expectedTag: 0x30, name: "TimeStampToken ContentInfo")
        try reader.requireEnd()

        var contentInfoReader = DERReader(data: contentInfo.value)
        let contentType = try contentInfoReader.readObjectIdentifier(name: "ContentInfo.contentType")
        guard contentType == signedDataContentType else {
            throw TimestampASN1Error.invalidDER("TimeStampToken contentType is not signedData")
        }

        let explicitSignedData = try contentInfoReader.readElement(expectedTag: 0xA0, name: "ContentInfo.content")
        try contentInfoReader.requireEnd()

        var explicitReader = DERReader(data: explicitSignedData.value)
        let signedData = try explicitReader.readElement(expectedTag: 0x30, name: "SignedData")
        try explicitReader.requireEnd()

        let imprint = try extractMessageImprint(fromSignedData: signedData.value)
        if let expectedMessageImprint, imprint != expectedMessageImprint {
            throw TimestampASN1Error.invalidDER("TimeStampToken messageImprint does not match the request")
        }

        return imprint
    }

    private static func extractMessageImprint(fromSignedData value: Data) throws -> Data {
        var reader = DERReader(data: value)
        _ = try reader.readInteger(name: "SignedData.version")
        _ = try reader.readElement(expectedTag: 0x31, name: "SignedData.digestAlgorithms")

        let encapContentInfo = try reader.readElement(expectedTag: 0x30, name: "SignedData.encapContentInfo")
        var encapReader = DERReader(data: encapContentInfo.value)
        let eContentType = try encapReader.readObjectIdentifier(name: "EncapsulatedContentInfo.eContentType")
        guard eContentType == tstInfoContentType else {
            throw TimestampASN1Error.invalidDER("TimeStampToken eContentType is not id-ct-TSTInfo")
        }

        guard encapReader.peekTag() == 0xA0 else {
            throw TimestampASN1Error.invalidDER("TimeStampToken is missing embedded TSTInfo")
        }

        let explicitContent = try encapReader.readElement(expectedTag: 0xA0, name: "EncapsulatedContentInfo.eContent")
        try encapReader.requireEnd()

        var explicitReader = DERReader(data: explicitContent.value)
        let octets = try explicitReader.readOctetString(name: "TSTInfo eContent")
        try explicitReader.requireEnd()

        return try parseTSTInfoMessageImprint(octets)
    }

    private static func parseTSTInfoMessageImprint(_ data: Data) throws -> Data {
        var reader = DERReader(data: data)
        let sequence = try reader.readElement(expectedTag: 0x30, name: "TSTInfo")
        try reader.requireEnd()

        var tstInfo = DERReader(data: sequence.value)
        let version = try tstInfo.readInteger(name: "TSTInfo.version")
        guard version == 1 else {
            throw TimestampASN1Error.invalidDER("TSTInfo.version is not v1")
        }

        _ = try tstInfo.readObjectIdentifier(name: "TSTInfo.policy")
        let messageImprint = try tstInfo.readElement(expectedTag: 0x30, name: "TSTInfo.messageImprint")
        let hashedMessage = try parseMessageImprint(messageImprint.value)

        _ = try tstInfo.readElement(expectedTag: 0x02, name: "TSTInfo.serialNumber")
        _ = try tstInfo.readElement(expectedTag: 0x18, name: "TSTInfo.genTime")
        return hashedMessage
    }

    static func parseMessageImprint(_ data: Data) throws -> Data {
        var reader = DERReader(data: data)
        let algorithm = try reader.readElement(expectedTag: 0x30, name: "MessageImprint.hashAlgorithm")
        var algorithmReader = DERReader(data: algorithm.value)
        let algorithmOID = try algorithmReader.readObjectIdentifier(name: "MessageImprint.hashAlgorithm.algorithm")
        guard algorithmOID == sha256AlgorithmIdentifier else {
            throw TimestampASN1Error.invalidDER("MessageImprint hash algorithm is not SHA-256")
        }

        if !algorithmReader.isAtEnd {
            let parameters = try algorithmReader.readElement(name: "MessageImprint.hashAlgorithm.parameters")
            guard parameters.tag == 0x05 && parameters.value.isEmpty else {
                throw TimestampASN1Error.invalidDER("Unsupported MessageImprint hash algorithm parameters")
            }
        }
        try algorithmReader.requireEnd()

        let hashedMessage = try reader.readOctetString(name: "MessageImprint.hashedMessage")
        try reader.requireEnd()
        guard hashedMessage.count == 32 else {
            throw TimestampASN1Error.invalidDER("SHA-256 MessageImprint has invalid length")
        }

        return hashedMessage
    }

    private static func base128(_ value: Int) -> [UInt8] {
        var remaining = value
        var encoded = [UInt8(remaining & 0x7F)]
        remaining >>= 7

        while remaining > 0 {
            encoded.insert(UInt8(remaining & 0x7F) | 0x80, at: 0)
            remaining >>= 7
        }

        return encoded
    }
}

struct DERElement: Equatable {
    let tag: UInt8
    let value: Data
    let encoded: Data
}

struct DERReader {
    private let data: Data
    private var offset: Int = 0

    init(data: Data) {
        self.data = data
    }

    var isAtEnd: Bool {
        offset == data.count
    }

    func peekTag() -> UInt8? {
        guard offset < data.count else { return nil }
        return data[offset]
    }

    mutating func readElement(expectedTag: UInt8? = nil, name: String) throws -> DERElement {
        guard offset < data.count else {
            throw TimestampASN1Error.invalidDER("Missing \(name)")
        }

        let start = offset
        let tag = data[offset]
        offset += 1

        let length = try readLength(name: name)
        guard length <= data.count - offset else {
            throw TimestampASN1Error.invalidDER("\(name) length exceeds available bytes")
        }

        let valueStart = offset
        offset += length

        if let expectedTag, tag != expectedTag {
            throw TimestampASN1Error.invalidDER("\(name) has tag 0x\(String(tag, radix: 16)), expected 0x\(String(expectedTag, radix: 16))")
        }

        return DERElement(
            tag: tag,
            value: Data(data[valueStart..<offset]),
            encoded: Data(data[start..<offset])
        )
    }

    mutating func readInteger(name: String) throws -> Int {
        let element = try readElement(expectedTag: 0x02, name: name)
        guard !element.value.isEmpty else {
            throw TimestampASN1Error.invalidDER("\(name) is empty")
        }

        let bytes = [UInt8](element.value)
        if bytes.count > 1 {
            if bytes[0] == 0x00 && bytes[1] & 0x80 == 0 {
                throw TimestampASN1Error.invalidDER("\(name) is not minimally encoded")
            }
            if bytes[0] == 0xFF && bytes[1] & 0x80 != 0 {
                throw TimestampASN1Error.invalidDER("\(name) is not minimally encoded")
            }
        }

        guard bytes[0] & 0x80 == 0 else {
            throw TimestampASN1Error.invalidDER("\(name) must be non-negative")
        }

        var value = 0
        for byte in bytes {
            guard value <= (Int.max - Int(byte)) / 256 else {
                throw TimestampASN1Error.invalidDER("\(name) is too large")
            }
            value = value * 256 + Int(byte)
        }

        return value
    }

    mutating func readObjectIdentifier(name: String) throws -> [Int] {
        let element = try readElement(expectedTag: 0x06, name: name)
        let bytes = [UInt8](element.value)
        guard let first = bytes.first else {
            throw TimestampASN1Error.invalidDER("\(name) is empty")
        }

        var arcs: [Int]
        if first < 40 {
            arcs = [0, Int(first)]
        } else if first < 80 {
            arcs = [1, Int(first) - 40]
        } else {
            arcs = [2, Int(first) - 80]
        }

        var index = 1
        while index < bytes.count {
            var value = 0
            var didTerminate = false
            while index < bytes.count {
                let byte = bytes[index]
                index += 1
                guard value <= (Int.max - Int(byte & 0x7F)) / 128 else {
                    throw TimestampASN1Error.invalidDER("\(name) arc is too large")
                }
                value = value * 128 + Int(byte & 0x7F)
                if byte & 0x80 == 0 {
                    didTerminate = true
                    break
                }
            }

            guard didTerminate else {
                throw TimestampASN1Error.invalidDER("\(name) has truncated base-128 arc")
            }
            arcs.append(value)
        }

        return arcs
    }

    mutating func readOctetString(name: String) throws -> Data {
        let element = try readElement(expectedTag: 0x04, name: name)
        return element.value
    }

    mutating func readUTF8String(name: String) throws -> String {
        let element = try readElement(expectedTag: 0x0C, name: name)
        guard let string = String(data: element.value, encoding: .utf8) else {
            throw TimestampASN1Error.invalidDER("\(name) is not valid UTF-8")
        }
        return string
    }

    mutating func readBitString(name: String) throws -> Data {
        let element = try readElement(expectedTag: 0x03, name: name)
        guard let unusedBits = element.value.first else {
            throw TimestampASN1Error.invalidDER("\(name) is empty")
        }
        guard unusedBits <= 7 else {
            throw TimestampASN1Error.invalidDER("\(name) has invalid unused-bit count")
        }
        return element.value
    }

    mutating func requireEnd() throws {
        guard isAtEnd else {
            throw TimestampASN1Error.invalidDER("Trailing DER data")
        }
    }

    private mutating func readLength(name: String) throws -> Int {
        guard offset < data.count else {
            throw TimestampASN1Error.invalidDER("\(name) is missing a length")
        }

        let first = data[offset]
        offset += 1

        if first & 0x80 == 0 {
            return Int(first)
        }

        let byteCount = Int(first & 0x7F)
        guard byteCount > 0 else {
            throw TimestampASN1Error.invalidDER("\(name) uses indefinite length")
        }
        guard byteCount <= MemoryLayout<Int>.size else {
            throw TimestampASN1Error.invalidDER("\(name) length is too large")
        }
        guard byteCount <= data.count - offset else {
            throw TimestampASN1Error.invalidDER("\(name) has truncated length")
        }
        guard data[offset] != 0 else {
            throw TimestampASN1Error.invalidDER("\(name) length is not minimally encoded")
        }

        var length = 0
        for _ in 0..<byteCount {
            length = length * 256 + Int(data[offset])
            offset += 1
        }

        guard length >= 0x80 else {
            throw TimestampASN1Error.invalidDER("\(name) length should use short form")
        }

        return length
    }
}

private extension Array where Element == Data {
    func concatenated() -> Data {
        reduce(into: Data()) { result, value in
            result.append(value)
        }
    }
}
