import Foundation
import CoreGraphics
import AppKit
import PDFKit

// MARK: - Signing walking skeleton
//
// These are the SHARED CONTRACTS for the digital-signature feature. Every module
// (see SIGNING_SPEC.md) codes against the types below so parallel subagents don't
// collide on interfaces. Every implementation currently throws `.notImplemented`;
// the acceptance tests in Tests/PDFoldTests/PDFSigningTests.swift are RED until the
// modules are built out. Do NOT change these signatures without updating the spec
// and the tests together.

enum SigningError: Error, Equatable {
    case notImplemented
    case invalidPDF
    case contentsPlaceholderNotFound
    case contentsPlaceholderTooSmall
    case byteRangePlaceholderNotFound
    case missingIdentity
    case timestampUnavailable
}

// MARK: - Module D contracts (PDF incremental signer)

/// A parsed PDF `/ByteRange [a b c d]`. It describes the two byte spans that the
/// CMS signature covers — i.e. the whole file EXCEPT the hex placeholder (including
/// its enclosing `<` `>`) inside `/Contents`.
///
///   segment 1 = bytes[a ..< a + b]      (a is always 0)
///   gap       = bytes[a + b ..< c]      (the `<...>` /Contents value — NOT signed)
///   segment 2 = bytes[c ..< c + d]
struct SignatureByteRange: Equatable {
    var beforeOffset: Int   // a — always 0
    var beforeLength: Int   // b — number of bytes before the opening '<'
    var afterOffset: Int    // c — index of the first byte after the closing '>'
    var afterLength: Int    // d — number of bytes from c to EOF

    init(beforeOffset: Int, beforeLength: Int, afterOffset: Int, afterLength: Int) {
        self.beforeOffset = beforeOffset
        self.beforeLength = beforeLength
        self.afterOffset = afterOffset
        self.afterLength = afterLength
    }

    /// The four integers exactly as they must be written into the PDF `/ByteRange` array.
    var array: [Int] { [beforeOffset, beforeLength, afterOffset, afterLength] }
}

/// Byte-exact primitives for the incremental-update signer. Implemented in Module D.
/// These are pure functions on `Data` so they can be tested without any real crypto.
enum PDFByteRangeCalculator {
    /// Locate the single `/Contents <00…00>` hex placeholder in `pdf` and compute the
    /// ByteRange that covers every byte except that placeholder's value (brackets included).
    /// Throws `.contentsPlaceholderNotFound` if there is no `/Contents <…>` token.
    static func computeByteRange(in pdf: Data) throws -> SignatureByteRange {
        let contents = try PDFSigningByteSearch.contentsPlaceholder(in: pdf)
        return SignatureByteRange(
            beforeOffset: 0,
            beforeLength: contents.openAngle,
            afterOffset: contents.closeAngle + 1,
            afterLength: pdf.count - (contents.closeAngle + 1)
        )
    }

    /// The exact bytes the signature digests: segment 1 concatenated with segment 2.
    static func digestInput(pdf: Data, range: SignatureByteRange) throws -> Data {
        guard range.beforeOffset == 0,
              range.beforeLength >= 0,
              range.afterOffset >= range.beforeLength,
              range.afterLength >= 0,
              range.beforeLength <= pdf.count,
              range.afterOffset <= pdf.count,
              range.afterOffset + range.afterLength <= pdf.count else {
            throw SigningError.invalidPDF
        }

        var digest = Data()
        digest.reserveCapacity(range.beforeLength + range.afterLength)
        digest.append(pdf[0..<range.beforeLength])
        digest.append(pdf[range.afterOffset..<(range.afterOffset + range.afterLength)])
        return digest
    }

    /// Overwrite the fixed-width `/ByteRange [ … ]` placeholder in place (no length change)
    /// with the concrete `range`. The array must have been emitted wide enough to hold any
    /// value; overwriting must not shift a single downstream byte.
    static func writeByteRange(_ range: SignatureByteRange, into pdf: Data) throws -> Data {
        let placeholder = try PDFSigningByteSearch.byteRangePlaceholder(in: pdf)
        let concrete = String(
            format: "%010d %010d %010d %010d",
            range.beforeOffset,
            range.beforeLength,
            range.afterOffset,
            range.afterLength
        )
        guard concrete.utf8.count <= placeholder.length else {
            throw SigningError.invalidPDF
        }

        var padded = concrete
        if padded.utf8.count < placeholder.length {
            padded += String(repeating: " ", count: placeholder.length - padded.utf8.count)
        }

        var output = pdf
        output.replaceSubrange(placeholder.range, with: Data(padded.utf8))
        return output
    }

    /// Hex-encode `derSignature`, splice it into the `/Contents <…>` placeholder, and
    /// zero-pad the remainder. Throws `.contentsPlaceholderTooSmall` if it does not fit.
    /// The returned data must be byte-identical to the input except inside the brackets.
    static func fillContents(in pdf: Data, range: SignatureByteRange, derSignature: Data) throws -> Data {
        guard range.beforeLength >= 0,
              range.afterOffset > range.beforeLength,
              range.afterOffset <= pdf.count,
              pdf[range.beforeLength] == UInt8(ascii: "<"),
              pdf[range.afterOffset - 1] == UInt8(ascii: ">") else {
            throw SigningError.invalidPDF
        }

        let hexCapacity = range.afterOffset - range.beforeLength - 2
        let signatureHex = derSignature.map { String(format: "%02x", $0) }.joined()
        guard signatureHex.utf8.count <= hexCapacity else {
            throw SigningError.contentsPlaceholderTooSmall
        }

        let paddedHex = signatureHex + String(repeating: "0", count: hexCapacity - signatureHex.utf8.count)
        var output = pdf
        output.replaceSubrange((range.beforeLength + 1)..<(range.afterOffset - 1), with: Data(paddedHex.utf8))
        return output
    }
}

/// Everything needed to place one visible signature field during signing.
struct SignatureFieldSpec {
    var pageIndex: Int
    var rect: CGRect
    var signerName: String
    var reason: String?
    var location: String?
    var contactInfo: String?
    /// `ETSI.CAdES.detached` for PAdES (goal) or `adbe.pkcs7.detached` (fallback).
    var subFilter: String

    init(pageIndex: Int,
         rect: CGRect,
         signerName: String,
         reason: String? = nil,
         location: String? = nil,
         contactInfo: String? = nil,
         subFilter: String = "ETSI.CAdES.detached") {
        self.pageIndex = pageIndex
        self.rect = rect
        self.signerName = signerName
        self.reason = reason
        self.location = location
        self.contactInfo = contactInfo
        self.subFilter = subFilter
    }
}

/// A rendered visible-signature appearance as a PDF Form XObject stream (Module E output).
struct PDFAppearanceStream {
    /// The `/Type /XObject /Subtype /Form` stream body (font subset embedded).
    var xobject: Data
    var bbox: CGRect
}

/// The core incremental-update signer (Module D). `sign` lays out the signature field +
/// placeholders, then calls back into `cms` with the exact ByteRange bytes so the CMS is
/// built over the right content, then splices the DER back in. It must be an append-only
/// incremental update: signing an already-signed PDF must preserve prior signatures.
protocol PDFSigner {
    func sign(pdf: Data,
              field: SignatureFieldSpec,
              appearance: PDFAppearanceStream?,
              cms: (_ byteRangeBytes: Data) throws -> Data) throws -> Data
}

struct PDFIncrementalSigner: PDFSigner {
    init() {}

    func sign(pdf: Data,
              field: SignatureFieldSpec,
              appearance: PDFAppearanceStream?,
              cms: (_ byteRangeBytes: Data) throws -> Data) throws -> Data {
        let plan = try PDFIncrementalUpdatePlan(pdf: pdf, field: field, appearance: appearance)
        var signatureReadyPDF = plan.render()
        let range = try PDFByteRangeCalculator.computeByteRange(in: signatureReadyPDF)
        signatureReadyPDF = try PDFByteRangeCalculator.writeByteRange(range, into: signatureReadyPDF)
        let finalizedRange = try PDFByteRangeCalculator.computeByteRange(in: signatureReadyPDF)
        let byteRangeBytes = try PDFByteRangeCalculator.digestInput(pdf: signatureReadyPDF, range: finalizedRange)
        let derSignature = try cms(byteRangeBytes)
        return try PDFByteRangeCalculator.fillContents(
            in: signatureReadyPDF,
            range: finalizedRange,
            derSignature: derSignature
        )
    }
}

// MARK: - Module D private implementation

private enum PDFSigningByteSearch {
    struct ContentsPlaceholder {
        var openAngle: Int
        var closeAngle: Int
    }

    struct ByteRangePlaceholder {
        var range: Range<Int>
        var length: Int { range.count }
    }

    static func contentsPlaceholder(in pdf: Data) throws -> ContentsPlaceholder {
        let bytes = [UInt8](pdf)
        let token = Array("/Contents".utf8)
        var candidates: [ContentsPlaceholder] = []
        var index = 0

        while let tokenRange = bytes.firstRange(of: token, in: index..<bytes.count) {
            var cursor = tokenRange.upperBound
            while cursor < bytes.count, isPDFWhitespace(bytes[cursor]) {
                cursor += 1
            }
            guard cursor < bytes.count, bytes[cursor] == UInt8(ascii: "<") else {
                index = tokenRange.upperBound
                continue
            }

            var close = cursor + 1
            while close < bytes.count, bytes[close] != UInt8(ascii: ">") {
                close += 1
            }
            guard close < bytes.count else {
                throw SigningError.contentsPlaceholderNotFound
            }

            let hexBytes = bytes[(cursor + 1)..<close]
            if hexBytes.allSatisfy({ $0 == UInt8(ascii: "0") }) {
                candidates.append(ContentsPlaceholder(openAngle: cursor, closeAngle: close))
            }
            index = close + 1
        }

        if let placeholder = candidates.last {
            return placeholder
        }
        throw SigningError.contentsPlaceholderNotFound
    }

    static func byteRangePlaceholder(in pdf: Data) throws -> ByteRangePlaceholder {
        let bytes = [UInt8](pdf)
        let token = Array("/ByteRange".utf8)
        var zeroFilledCandidates: [ByteRangePlaceholder] = []
        var fallback: ByteRangePlaceholder?
        var index = 0

        while let tokenRange = bytes.firstRange(of: token, in: index..<bytes.count) {
            var cursor = tokenRange.upperBound
            while cursor < bytes.count, isPDFWhitespace(bytes[cursor]) {
                cursor += 1
            }
            guard cursor < bytes.count, bytes[cursor] == UInt8(ascii: "[") else {
                index = tokenRange.upperBound
                continue
            }

            var close = cursor + 1
            while close < bytes.count, bytes[close] != UInt8(ascii: "]") {
                close += 1
            }
            guard close < bytes.count else {
                throw SigningError.byteRangePlaceholderNotFound
            }

            let range = (cursor + 1)..<close
            let placeholder = ByteRangePlaceholder(range: range)
            fallback = placeholder
            let body = bytes[range]
            if body.allSatisfy({ $0 == UInt8(ascii: "0") || isPDFWhitespace($0) }) {
                zeroFilledCandidates.append(placeholder)
            }
            index = close + 1
        }

        if let placeholder = zeroFilledCandidates.last ?? fallback {
            return placeholder
        }
        throw SigningError.byteRangePlaceholderNotFound
    }

    private static func isPDFWhitespace(_ byte: UInt8) -> Bool {
        byte == 0x00 || byte == 0x09 || byte == 0x0A || byte == 0x0C || byte == 0x0D || byte == 0x20
    }
}

private extension Array where Element == UInt8 {
    func firstRange(of needle: [UInt8], in searchRange: Range<Int>) -> Range<Int>? {
        guard !needle.isEmpty,
              searchRange.lowerBound >= 0,
              searchRange.upperBound <= count,
              searchRange.count >= needle.count else {
            return nil
        }

        var index = searchRange.lowerBound
        let lastStart = searchRange.upperBound - needle.count
        while index <= lastStart {
            if self[index..<(index + needle.count)].elementsEqual(needle) {
                return index..<(index + needle.count)
            }
            index += 1
        }
        return nil
    }
}

private struct PDFIncrementalUpdatePlan {
    private static let contentsHexDigits = 32_768

    private let original: Data
    private let field: SignatureFieldSpec
    private let appearance: PDFAppearanceStream?
    private let rootObjectNumber: Int
    private let previousStartXref: Int
    private let maxObjectNumber: Int
    private let originalCatalogBody: String
    private let pageObjectNumber: Int?

    private let acroFormObjectNumber: Int
    private let fieldObjectNumber: Int
    private let signatureObjectNumber: Int
    private let appearanceObjectNumber: Int?

    init(pdf: Data, field: SignatureFieldSpec, appearance: PDFAppearanceStream?) throws {
        self.original = pdf
        self.field = field
        self.appearance = appearance

        let text = String(decoding: pdf, as: UTF8.self)
        self.rootObjectNumber = try Self.parseRootObjectNumber(from: text)
        self.previousStartXref = try Self.parsePreviousStartXref(from: text)
        self.maxObjectNumber = max(Self.parseMaxObjectNumber(from: text), try Self.parseTrailerSize(from: text) - 1)
        self.originalCatalogBody = try Self.parseObjectBody(objectNumber: rootObjectNumber, in: text)
        self.pageObjectNumber = nil

        self.acroFormObjectNumber = maxObjectNumber + 1
        self.fieldObjectNumber = maxObjectNumber + 2
        self.signatureObjectNumber = maxObjectNumber + 3
        self.appearanceObjectNumber = appearance == nil ? nil : maxObjectNumber + 4
    }

    func render() -> Data {
        var output = original
        if !output.isEmpty, output.last != UInt8(ascii: "\n") {
            output.append(UInt8(ascii: "\n"))
        }

        var offsets: [(objectNumber: Int, offset: Int)] = []

        appendObject(
            number: rootObjectNumber,
            body: catalogBody(),
            to: &output,
            offsets: &offsets
        )
        appendObject(
            number: acroFormObjectNumber,
            body: "<< /SigFlags 3 /Fields [\(fieldObjectNumber) 0 R] >>",
            to: &output,
            offsets: &offsets
        )
        appendObject(
            number: fieldObjectNumber,
            body: fieldBody(),
            to: &output,
            offsets: &offsets
        )
        appendObject(
            number: signatureObjectNumber,
            body: signatureBody(),
            to: &output,
            offsets: &offsets
        )
        if let appearance, let appearanceObjectNumber {
            appendObject(
                number: appearanceObjectNumber,
                body: appearanceBody(appearance),
                to: &output,
                offsets: &offsets
            )
        }

        let xrefOffset = output.count
        output.append(Data(xrefSection(offsets: offsets, xrefOffset: xrefOffset).utf8))
        return output
    }

    private func appendObject(number: Int,
                              body: String,
                              to output: inout Data,
                              offsets: inout [(objectNumber: Int, offset: Int)]) {
        offsets.append((number, output.count))
        output.append(Data("\(number) 0 obj\n\(body)\nendobj\n".utf8))
    }

    private func catalogBody() -> String {
        let bodyWithoutAcroForm = originalCatalogBody.removingPDFDictionaryEntry(named: "AcroForm")
        guard let insertion = bodyWithoutAcroForm.range(of: ">>", options: .backwards) else {
            return "<< /Type /Catalog /AcroForm \(acroFormObjectNumber) 0 R >>"
        }
        var updated = bodyWithoutAcroForm
        updated.insert(contentsOf: " /AcroForm \(acroFormObjectNumber) 0 R", at: insertion.lowerBound)
        return updated
    }

    private func fieldBody() -> String {
        let rect = pdfArray(field.rect.pdfRectValues)
        var entries = [
            "/Type /Annot",
            "/Subtype /Widget",
            "/FT /Sig",
            "/Rect \(rect)",
            "/T \(pdfLiteralString("Signature \(signatureObjectNumber)"))",
            "/F 132",
            "/V \(signatureObjectNumber) 0 R"
        ]
        if let pageObjectNumber {
            entries.append("/P \(pageObjectNumber) 0 R")
        }
        if let appearanceObjectNumber {
            entries.append("/AP << /N \(appearanceObjectNumber) 0 R >>")
        }
        return "<< \(entries.joined(separator: " ")) >>"
    }

    private func signatureBody() -> String {
        var entries = [
            "/Type /Sig",
            "/Filter /Adobe.PPKLite",
            "/SubFilter /\(field.subFilter)",
            "/ByteRange [0000000000 0000000000 0000000000 0000000000]",
            "/Contents <\(String(repeating: "0", count: Self.contentsHexDigits))>",
            "/M \(pdfLiteralString(pdfDateString(Date())))",
            "/Name \(pdfLiteralString(field.signerName))"
        ]
        if let reason = field.reason, !reason.isEmpty {
            entries.append("/Reason \(pdfLiteralString(reason))")
        }
        if let location = field.location, !location.isEmpty {
            entries.append("/Location \(pdfLiteralString(location))")
        }
        if let contactInfo = field.contactInfo, !contactInfo.isEmpty {
            entries.append("/ContactInfo \(pdfLiteralString(contactInfo))")
        }
        return "<< \(entries.joined(separator: " ")) >>"
    }

    private func appearanceBody(_ appearance: PDFAppearanceStream) -> String {
        let stream = String(decoding: appearance.xobject, as: UTF8.self)
        let bbox = pdfArray(appearance.bbox.pdfRectValues)
        return """
        << /Type /XObject /Subtype /Form /BBox \(bbox) /Length \(appearance.xobject.count) >>
        stream
        \(stream)
        endstream
        """
    }

    private func xrefSection(offsets: [(objectNumber: Int, offset: Int)], xrefOffset: Int) -> String {
        let sorted = offsets.sorted { $0.objectNumber < $1.objectNumber }
        var lines = "xref\n"
        var index = 0
        while index < sorted.count {
            let start = sorted[index].objectNumber
            var group = [sorted[index]]
            index += 1
            while index < sorted.count, sorted[index].objectNumber == group.last!.objectNumber + 1 {
                group.append(sorted[index])
                index += 1
            }

            lines += "\(start) \(group.count)\n"
            for item in group {
                lines += String(format: "%010d 00000 n \n", item.offset)
            }
        }

        let size = max(maxObjectNumber, appearanceObjectNumber ?? signatureObjectNumber) + 1
        lines += """
        trailer
        << /Size \(size) /Root \(rootObjectNumber) 0 R /Prev \(previousStartXref) >>
        startxref
        \(xrefOffset)
        %%EOF
        """
        lines += "\n"
        return lines
    }

    private static func parseRootObjectNumber(from text: String) throws -> Int {
        guard let match = text.lastRegexMatch(#"/Root\s+(\d+)\s+0\s+R"#),
              let value = Int(match[1]) else {
            throw SigningError.invalidPDF
        }
        return value
    }

    private static func parseTrailerSize(from text: String) throws -> Int {
        guard let match = text.lastRegexMatch(#"/Size\s+(\d+)"#),
              let value = Int(match[1]) else {
            throw SigningError.invalidPDF
        }
        return value
    }

    private static func parsePreviousStartXref(from text: String) throws -> Int {
        guard let markerRange = text.range(of: "startxref", options: .backwards) else {
            throw SigningError.invalidPDF
        }
        let suffix = text[markerRange.upperBound...]
        guard let match = String(suffix).firstRegexMatch(#"\s*(\d+)"#),
              let value = Int(match[1]) else {
            throw SigningError.invalidPDF
        }
        return value
    }

    private static func parseMaxObjectNumber(from text: String) -> Int {
        let bytes = Array(text.utf8)
        var index = 0
        var maxObject = 0

        while index < bytes.count {
            guard bytes[index].isASCIIDigit else {
                index += 1
                continue
            }

            let numberStart = index
            guard numberStart == 0 || bytes[numberStart - 1].isPDFWhitespace else {
                index += 1
                continue
            }

            var value = 0
            var digitCount = 0
            while index < bytes.count, bytes[index].isASCIIDigit {
                digitCount += 1
                guard digitCount <= 10 else {
                    while index < bytes.count, bytes[index].isASCIIDigit {
                        index += 1
                    }
                    value = -1
                    break
                }
                value = value * 10 + Int(bytes[index] - UInt8(ascii: "0"))
                index += 1
            }
            guard value >= 0 else { continue }

            var cursor = index
            guard skipPDFWhitespace(in: bytes, cursor: &cursor),
                  cursor < bytes.count,
                  bytes[cursor] == UInt8(ascii: "0") else {
                index = max(numberStart + 1, index)
                continue
            }
            cursor += 1

            guard skipPDFWhitespace(in: bytes, cursor: &cursor),
                  cursor + 3 <= bytes.count,
                  bytes[cursor] == UInt8(ascii: "o"),
                  bytes[cursor + 1] == UInt8(ascii: "b"),
                  bytes[cursor + 2] == UInt8(ascii: "j") else {
                index = max(numberStart + 1, index)
                continue
            }

            maxObject = max(maxObject, value)
            index = cursor + 3
        }

        return maxObject
    }

    private static func parseObjectBody(objectNumber: Int, in text: String) throws -> String {
        let header = "\(objectNumber) 0 obj"
        guard let headerRange = text.range(of: header, options: .backwards),
              let endRange = text.range(of: "endobj", range: headerRange.upperBound..<text.endIndex) else {
            throw SigningError.invalidPDF
        }
        return String(text[headerRange.upperBound..<endRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func skipPDFWhitespace(in bytes: [UInt8], cursor: inout Int) -> Bool {
        let start = cursor
        while cursor < bytes.count {
            switch bytes[cursor] {
            case 0x00, 0x09, 0x0A, 0x0C, 0x0D, 0x20:
                cursor += 1
            default:
                return cursor > start
            }
        }
        return cursor > start
    }
}

private extension UInt8 {
    var isASCIIDigit: Bool {
        self >= UInt8(ascii: "0") && self <= UInt8(ascii: "9")
    }

    var isPDFWhitespace: Bool {
        switch self {
        case 0x00, 0x09, 0x0A, 0x0C, 0x0D, 0x20:
            return true
        default:
            return false
        }
    }
}

private extension String {
    func firstRegexMatch(_ pattern: String) -> [String]? {
        regexMatches(pattern).first
    }

    func lastRegexMatch(_ pattern: String) -> [String]? {
        regexMatches(pattern).last
    }

    func allRegexMatches(_ pattern: String) -> [[String]] {
        regexMatches(pattern)
    }

    private func regexMatches(_ pattern: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        let nsRange = NSRange(startIndex..<endIndex, in: self)
        return regex.matches(in: self, range: nsRange).map { match in
            (0..<match.numberOfRanges).map { index in
                guard let range = Range(match.range(at: index), in: self) else { return "" }
                return String(self[range])
            }
        }
    }

    func removingPDFDictionaryEntry(named name: String) -> String {
        guard let keyRange = range(of: "/\(name)") else { return self }
        var cursor = keyRange.upperBound
        while cursor < endIndex, self[cursor].isWhitespace {
            cursor = index(after: cursor)
        }

        if self[cursor...].hasPrefix("<<") {
            guard let valueEnd = matchingDictionaryEnd(startingAt: cursor) else { return self }
            var updated = self
            updated.removeSubrange(keyRange.lowerBound..<valueEnd)
            return updated
        }

        guard let end = firstPDFTokenBoundary(after: cursor) else { return self }
        var updated = self
        updated.removeSubrange(keyRange.lowerBound..<end)
        return updated
    }

    private func matchingDictionaryEnd(startingAt start: String.Index) -> String.Index? {
        var cursor = start
        var depth = 0
        while cursor < endIndex {
            if self[cursor...].hasPrefix("<<") {
                depth += 1
                cursor = index(cursor, offsetBy: 2)
                continue
            }
            if self[cursor...].hasPrefix(">>") {
                depth -= 1
                cursor = index(cursor, offsetBy: 2)
                if depth == 0 { return cursor }
                continue
            }
            cursor = index(after: cursor)
        }
        return nil
    }

    private func firstPDFTokenBoundary(after start: String.Index) -> String.Index? {
        var cursor = start
        while cursor < endIndex {
            let char = self[cursor]
            if char == "/" || char == ">" || char.isNewline {
                return cursor
            }
            cursor = index(after: cursor)
        }
        return endIndex
    }
}

private extension CGRect {
    var pdfRectValues: [CGFloat] {
        [minX, minY, maxX, maxY]
    }
}

private func pdfArray(_ values: [CGFloat]) -> String {
    "[\(values.map(pdfNumber).joined(separator: " "))]"
}

private func pdfNumber(_ value: CGFloat) -> String {
    let double = Double(value)
    if double.rounded() == double {
        return String(Int(double))
    }
    return String(format: "%.4f", double)
}

private func pdfLiteralString(_ value: String) -> String {
    var escaped = ""
    for byte in value.utf8 {
        switch byte {
        case UInt8(ascii: "("), UInt8(ascii: ")"), UInt8(ascii: "\\"):
            escaped.append("\\")
            escaped.append(Character(UnicodeScalar(byte)))
        case 0x0A:
            escaped.append("\\n")
        case 0x0D:
            escaped.append("\\r")
        default:
            escaped.append(Character(UnicodeScalar(byte)))
        }
    }
    return "(\(escaped))"
}

private func pdfDateString(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyyMMddHHmmss"
    return "D:\(formatter.string(from: date))+00'00'"
}

// MARK: - Module E contract (export-survival baking)

/// Bakes visual (non-cryptographic) signature placements into a PDF's page content so
/// they survive export → reopen. This replaces the current broken path where a placement
/// lives only as an in-memory PDFKit stamp annotation and is lost on export
/// (see WorkspaceDocument.exportedPDFData). Implemented in Module E.
enum SignatureExportBaker {
    /// Draw each placement's image into the page content of the matching page and return
    /// new PDF bytes. `pageIndexForPlacement` maps a placement to a 0-based page index in
    /// `pdf` (the export pipeline already knows the flattened page order).
    static func bake(placements: [SignaturePlacement],
                     into pdf: Data,
                     pageIndexForPlacement: (SignaturePlacement) -> Int?) throws -> Data {
        try SignatureExportBakingSupport.bake(
            placements: placements,
            into: pdf,
            pageIndexForPlacement: pageIndexForPlacement
        )
    }
}
