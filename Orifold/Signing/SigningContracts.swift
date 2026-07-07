import Foundation
import CoreGraphics
import AppKit
import PDFKit

// MARK: - Signing walking skeleton
//
// These are the SHARED CONTRACTS for the digital-signature feature. Every module
// (see docs/signing/SIGNING_SPEC.md) codes against the types below so parallel subagents don't
// collide on interfaces. Every implementation currently throws `.notImplemented`;
// the acceptance tests in Tests/OrifoldTests/PDFSigningTests.swift are RED until the
// modules are built out. Do NOT change these signatures without updating the spec
// and the tests together.

enum SigningError: Error, Equatable, LocalizedError {
    case notImplemented
    case invalidPDF
    case contentsPlaceholderNotFound
    case contentsPlaceholderTooSmall
    case byteRangePlaceholderNotFound
    case missingIdentity
    case timestampUnavailable
    /// The PDF's most recent cross-reference section is a modern cross-reference STREAM
    /// (`/Type /XRef`), not a classic `xref` table. `PDFIncrementalUpdatePlan` only knows
    /// how to append a classic incremental xref section with `/Prev` pointing at a classic
    /// table — writing one on top of an xref-stream-only file produces a PDF most readers
    /// (and this app's own re-parse) can't traverse. Refuse instead of risking corruption.
    case unsupportedPDFStructure
    case cancelled
    /// The selected identity's certificate `notValidAfter` date has already passed.
    /// Nothing upstream of `signAndExportCryptographicPDF` checked this — a placement
    /// made while a certificate was still valid could otherwise be silently signed and
    /// exported after it expired, producing a PDF that looks successfully signed but
    /// whose certificate no reader will consider currently valid.
    case identityExpired

    /// Every call site that switches on `SigningError` already handles the common cases
    /// (`.cancelled`, `.notImplemented`, `.missingIdentity`, `.unsupportedPDFStructure`)
    /// with their own dedicated message; this covers those PLUS the cases that fall through
    /// to a generic `default:` branch there (`.invalidPDF`, the placeholder-reservation
    /// cases, `.timestampUnavailable`, `.identityExpired`) -- without `LocalizedError`
    /// conformance, that fallback's `error.localizedDescription` produced a useless generic
    /// Cocoa string for exactly the cases most likely to actually happen to a user (an
    /// expired certificate, an unreachable timestamp server).
    var errorDescription: String? {
        switch self {
        case .notImplemented:
            return L10n.string("error.export.signingNotAvailable")
        case .invalidPDF:
            return L10n.string("error.signing.invalidPDF")
        case .contentsPlaceholderNotFound, .contentsPlaceholderTooSmall, .byteRangePlaceholderNotFound:
            return L10n.string("error.signing.placeholderReservationFailed")
        case .missingIdentity:
            return L10n.string("error.export.chooseSigningIdentity")
        case .timestampUnavailable:
            return L10n.string("error.signing.timestampUnavailable")
        case .unsupportedPDFStructure:
            return L10n.string("error.export.unsupportedPDFStructure")
        case .cancelled:
            return L10n.string("status.sign.cancelled")
        case .identityExpired:
            return L10n.string("error.signing.identityExpired")
        }
    }
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
    /// Best-effort estimate (bytes) of the final CMS DER blob, used to size the `/Contents`
    /// hex placeholder wide enough for this identity's certificate chain (+ timestamp token,
    /// if requested) before the real signature exists. Falls back to a proven-sufficient
    /// default when nil (e.g. a trivial CMS callback in tests).
    var estimatedSignatureDERBytes: Int?

    init(pageIndex: Int,
         rect: CGRect,
         signerName: String,
         reason: String? = nil,
         location: String? = nil,
         contactInfo: String? = nil,
         subFilter: String = "ETSI.CAdES.detached",
         estimatedSignatureDERBytes: Int? = nil) {
        self.pageIndex = pageIndex
        self.rect = rect
        self.signerName = signerName
        self.reason = reason
        self.location = location
        self.contactInfo = contactInfo
        self.subFilter = subFilter
        self.estimatedSignatureDERBytes = estimatedSignatureDERBytes
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
    /// Proven-sufficient floor (16 KB DER) for a typical self-signed or single-intermediate
    /// chain plus a timestamp token. Never shrink below this even when an estimate is smaller.
    private static let defaultContentsHexDigits = 32_768

    private let original: Data
    private let field: SignatureFieldSpec
    private let appearance: PDFAppearanceStream?
    private let rootObjectNumber: Int
    private let previousStartXref: Int
    private let maxObjectNumber: Int
    private let originalCatalogBody: String
    private let pageObjectNumber: Int
    private let originalPageBody: String
    /// Indirect refs ("N 0 R") of any signature/form fields already listed in an existing
    /// `/AcroForm /Fields` array — from a prior Orifold signing pass or a pre-existing form.
    /// Carried forward so a second signature (or a form PDF's fields) is never dropped.
    private let existingAcroFormFieldRefs: [String]

    private let acroFormObjectNumber: Int
    private let fieldObjectNumber: Int
    private let signatureObjectNumber: Int
    private let appearanceObjectNumber: Int?

    /// Hex-digit width of the `/Contents` placeholder, sized from the identity's estimated
    /// DER size when supplied, floored at `defaultContentsHexDigits` and rounded up to the
    /// next 1024-digit boundary so a large certificate chain (or TSA token) still fits.
    private var contentsHexDigits: Int {
        guard let estimatedBytes = field.estimatedSignatureDERBytes else {
            return Self.defaultContentsHexDigits
        }
        let requiredHexDigits = estimatedBytes * 2
        guard requiredHexDigits > Self.defaultContentsHexDigits else {
            return Self.defaultContentsHexDigits
        }
        return ((requiredHexDigits + 1023) / 1024) * 1024
    }

    init(pdf: Data, field: SignatureFieldSpec, appearance: PDFAppearanceStream?) throws {
        self.original = pdf
        self.field = field
        self.appearance = appearance

        let text = String(decoding: pdf, as: UTF8.self)
        self.rootObjectNumber = try Self.parseRootObjectNumber(from: text)
        self.previousStartXref = try Self.parsePreviousStartXref(from: text)
        try Self.requireClassicXrefTable(in: pdf, atByteOffset: previousStartXref)
        self.maxObjectNumber = max(Self.parseMaxObjectNumber(from: text), try Self.parseTrailerSize(from: text) - 1)
        self.originalCatalogBody = try Self.parseObjectBody(objectNumber: rootObjectNumber, in: text)
        self.existingAcroFormFieldRefs = Self.parseExistingAcroFormFieldRefs(catalogBody: originalCatalogBody, in: text)
        self.pageObjectNumber = try Self.parsePageObjectNumber(at: field.pageIndex, in: text)
        self.originalPageBody = try Self.parseObjectBody(objectNumber: pageObjectNumber, in: text)

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
            body: Data(catalogBody().utf8),
            to: &output,
            offsets: &offsets
        )
        appendObject(
            number: pageObjectNumber,
            body: Data(pageBody().utf8),
            to: &output,
            offsets: &offsets
        )
        appendObject(
            number: acroFormObjectNumber,
            body: acroFormBody(),
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
                              body: Data,
                              to output: inout Data,
                              offsets: inout [(objectNumber: Int, offset: Int)]) {
        offsets.append((number, output.count))
        output.append(Data("\(number) 0 obj\n".utf8))
        output.append(body)
        output.append(Data("\nendobj\n".utf8))
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

    private func pageBody() -> String {
        let widgetRef = "\(fieldObjectNumber) 0 R"
        if let annotsRange = originalPageBody.range(of: #"/Annots\s*\[[^\]]*\]"#, options: .regularExpression),
           let closingBracket = originalPageBody[annotsRange].range(of: "]", options: .backwards) {
            var updated = originalPageBody
            updated.insert(contentsOf: " \(widgetRef)", at: closingBracket.lowerBound)
            return updated
        }

        guard let insertion = originalPageBody.range(of: ">>", options: .backwards) else {
            return "<< /Type /Page /Annots [\(widgetRef)] >>"
        }
        var updated = originalPageBody
        updated.insert(contentsOf: " /Annots [\(widgetRef)]", at: insertion.lowerBound)
        return updated
    }

    /// Merges the new signature widget's ref into any `/Fields` already present (a prior
    /// Orifold signature, or a pre-existing AcroForm on an imported form PDF) instead of
    /// replacing them — losing them here would silently drop prior signatures/form fields
    /// from the document's field tree even though their objects remain byte-intact.
    private func acroFormBody() -> Data {
        let fieldRefs = existingAcroFormFieldRefs + ["\(fieldObjectNumber) 0 R"]
        return Data("<< /SigFlags 3 /Fields [\(fieldRefs.joined(separator: " "))] >>".utf8)
    }

    private func fieldBody() -> Data {
        let rect = pdfArray(field.rect.pdfRectValues)
        var body = Data("<< /Type /Annot /Subtype /Widget /FT /Sig /Rect \(rect) /T ".utf8)
        body.append(pdfLiteralStringData("Signature \(signatureObjectNumber)"))
        body.append(Data(" /F 132 /V \(signatureObjectNumber) 0 R /P \(pageObjectNumber) 0 R".utf8))
        if let appearanceObjectNumber {
            body.append(Data(" /AP << /N \(appearanceObjectNumber) 0 R >>".utf8))
        }
        body.append(Data(" >>".utf8))
        return body
    }

    private func signatureBody() -> Data {
        var body = Data("<< /Type /Sig /Filter /Adobe.PPKLite /SubFilter /\(field.subFilter)".utf8)
        body.append(Data(" /ByteRange [0000000000 0000000000 0000000000 0000000000]".utf8))
        body.append(Data(" /Contents <\(String(repeating: "0", count: contentsHexDigits))>".utf8))
        body.append(Data(" /M ".utf8))
        body.append(pdfLiteralStringData(pdfDateString(Date())))
        body.append(Data(" /Name ".utf8))
        body.append(pdfLiteralStringData(field.signerName))
        if let reason = field.reason, !reason.isEmpty {
            body.append(Data(" /Reason ".utf8))
            body.append(pdfLiteralStringData(reason))
        }
        if let location = field.location, !location.isEmpty {
            body.append(Data(" /Location ".utf8))
            body.append(pdfLiteralStringData(location))
        }
        if let contactInfo = field.contactInfo, !contactInfo.isEmpty {
            body.append(Data(" /ContactInfo ".utf8))
            body.append(pdfLiteralStringData(contactInfo))
        }
        body.append(Data(" >>".utf8))
        return body
    }

    private func appearanceBody(_ appearance: PDFAppearanceStream) -> Data {
        let bbox = pdfArray(appearance.bbox.pdfRectValues)
        var body = Data("<< /Type /XObject /Subtype /Form /BBox \(bbox) /Length \(appearance.xobject.count) >>\nstream\n".utf8)
        // Append the XObject stream bytes directly rather than decoding them through a
        // Swift String first: any font-subset binary content would round-trip corrupted,
        // since re-encoding via .utf8 does not reproduce arbitrary raw bytes byte-for-byte.
        body.append(appearance.xobject)
        body.append(Data("\nendstream".utf8))
        return body
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

    /// Per the PDF spec, `startxref` gives the exact byte offset of either the literal
    /// `xref` keyword (classic table) or an `N G obj` header whose object is a
    /// cross-reference STREAM (`/Type /XRef`) — the modern form most tools now emit.
    /// This appender only knows how to write a classic incremental `xref` section with
    /// `/Prev`, so refuse up front rather than silently emitting a PDF whose xref chain
    /// most readers can't walk. Checked against the ORIGINAL raw bytes (not the lossy
    /// UTF-8-decoded `text` used for pattern matching elsewhere in this parser), since an
    /// exact byte offset must be verified against exact bytes.
    private static func requireClassicXrefTable(in pdf: Data, atByteOffset offset: Int) throws {
        let bytes = [UInt8](pdf)
        let keyword = Array("xref".utf8)
        guard offset >= 0,
              offset + keyword.count <= bytes.count,
              Array(bytes[offset..<(offset + keyword.count)]) == keyword else {
            throw SigningError.unsupportedPDFStructure
        }
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

    /// Finds the most recent `"N 0 obj" ... "endobj"` revision of `objectNumber`. A plain
    /// substring search is not enough: `"1 0 obj"` is itself a substring of `"21 0 obj"`, so
    /// naively matching the header text can silently return an unrelated, larger object's
    /// body. Guard every candidate match by requiring a non-digit (or start-of-string)
    /// immediately before it, and keep searching earlier in the text past any false match.
    private static func parseObjectBody(objectNumber: Int, in text: String) throws -> String {
        let header = "\(objectNumber) 0 obj"
        var searchRange = text.startIndex..<text.endIndex
        while let headerRange = text.range(of: header, options: .backwards, range: searchRange) {
            let precededByDigit = headerRange.lowerBound > text.startIndex
                && text[text.index(before: headerRange.lowerBound)].isNumber
            if !precededByDigit,
               let endRange = text.range(of: "endobj", range: headerRange.upperBound..<text.endIndex) {
                return String(text[headerRange.upperBound..<endRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            searchRange = text.startIndex..<headerRange.lowerBound
        }
        throw SigningError.invalidPDF
    }

    private static func parseExistingAcroFormFieldRefs(catalogBody: String, in text: String) -> [String] {
        guard let match = catalogBody.firstRegexMatch(#"/AcroForm\s+(\d+)\s+0\s+R"#),
              let acroFormObjectNumber = Int(match[1]),
              let acroFormBody = try? parseObjectBody(objectNumber: acroFormObjectNumber, in: text),
              let fieldsRange = acroFormBody.range(of: #"/Fields\s*\[[^\]]*\]"#, options: .regularExpression) else {
            return []
        }
        let fieldsText = String(acroFormBody[fieldsRange])
        return fieldsText.allRegexMatches(#"(\d+)\s+0\s+R"#).compactMap { fieldMatch in
            fieldMatch.count >= 2 ? "\(fieldMatch[1]) 0 R" : nil
        }
    }

    private static func parsePageObjectNumber(at pageIndex: Int, in text: String) throws -> Int {
        guard pageIndex >= 0 else { throw SigningError.invalidPDF }
        var pageObjects: [Int] = []
        for match in text.allRegexMatches(#"(?s)(\d+)\s+0\s+obj\s*(.*?)\s*endobj"#) {
            guard match.count >= 3,
                  let objectNumber = Int(match[1]) else { continue }
            let body = match[2]
            guard body.firstRegexMatch(#"/Type\s*/Page(?!s)"#) != nil else { continue }
            pageObjects.append(objectNumber)
        }
        guard pageObjects.indices.contains(pageIndex) else {
            throw SigningError.invalidPDF
        }
        return pageObjects[pageIndex]
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

/// Encodes `value` as a PDF literal string (ISO 32000-1 §7.9.2.2), returning the exact bytes
/// to splice into the file — never a `String` destined for `.utf8` re-encoding, which cannot
/// reproduce arbitrary raw byte sequences (any Unicode scalar ≥ U+0080 always re-encodes to
/// 2+ UTF-8 bytes, corrupting a single intended byte). Pure-ASCII text is written as-is
/// (readable, and what every PDF viewer expects for plain names); anything else is written
/// as UTF-16BE with the mandatory byte-order mark, matching how Acrobat itself encodes
/// non-Latin signer names/reasons/locations.
private func pdfLiteralStringData(_ value: String) -> Data {
    // Escape at the CHARACTER level, before any byte encoding. Escaping raw encoded bytes
    // instead would be wrong for UTF-16BE: a `(`/`)`/`\` byte value can appear as one half of
    // an unrelated 2-byte code unit (common in CJK text), and inserting a backslash there
    // splits that unit and corrupts the character. Escaping first means the inserted
    // backslash becomes its own well-formed unit once encoded, leaving neighboring
    // characters untouched.
    var escaped = ""
    for character in value {
        switch character {
        case "(", ")", "\\":
            escaped.append("\\")
            escaped.append(character)
        case "\n":
            escaped.append("\\n")
        case "\r":
            escaped.append("\\r")
        default:
            escaped.append(character)
        }
    }

    var raw = Data()
    if escaped.utf8.allSatisfy({ $0 < 0x80 }) {
        raw = Data(escaped.utf8)
    } else {
        raw.append(contentsOf: [0xFE, 0xFF])
        for unit in escaped.utf16 {
            raw.append(UInt8(unit >> 8))
            raw.append(UInt8(unit & 0xFF))
        }
    }

    var result = Data()
    result.append(UInt8(ascii: "("))
    result.append(raw)
    result.append(UInt8(ascii: ")"))
    return result
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

// MARK: - Post-export self-check

/// A lightweight, purely local self-check run on the app's OWN signing output right after
/// export — not a substitute for opening the file in a real PDF reader (that's what
/// `docs/signing/VERIFICATION.md` is for), but enough to catch the signing/export pipeline
/// itself producing a structurally broken result — e.g. the atomic-write step truncating
/// the file, or a `/ByteRange` that doesn't reach end-of-file — before telling the user
/// "signed successfully."
enum SignatureSelfCheck {
    struct Result: Equatable {
        /// `true` when the most recent `/ByteRange [a b c d]` covers the ENTIRE file
        /// (`a == 0`, `c + d == fileLength`) — i.e. nothing was appended or truncated after
        /// the signature was written, matching what a real validator like `pdfsig` reports
        /// as "Total document signed".
        var coversWholeDocument: Bool
        var byteRange: [Int]?
    }

    static func verify(signedPDF: Data) -> Result {
        let text = String(decoding: signedPDF, as: UTF8.self)
        // Anchor to the actual signature dictionary (`/Type /Sig … /ByteRange […] … >>`),
        // not just "the last /ByteRange found anywhere in the file" — an appearance-stream
        // XObject appended AFTER the signature object (rendered text, font data) could
        // otherwise happen to contain the literal bytes `/ByteRange [...]` and get mistaken
        // for the real one, producing a wrong verdict either direction.
        guard let sigTypeRange = text.range(of: "/Type /Sig", options: .backwards) else {
            return Result(coversWholeDocument: false, byteRange: nil)
        }
        let dictClose = text.range(of: ">>", range: sigTypeRange.upperBound..<text.endIndex)?.lowerBound ?? text.endIndex
        let dictScope = String(text[sigTypeRange.lowerBound..<dictClose])

        guard let match = dictScope.firstRegexMatch(#"/ByteRange\s*\[\s*(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s*\]"#),
              match.count == 5,
              let a = Int(match[1]), let b = Int(match[2]), let c = Int(match[3]), let d = Int(match[4]) else {
            return Result(coversWholeDocument: false, byteRange: nil)
        }
        let coversWhole = a == 0 && (c + d) == signedPDF.count
        return Result(coversWholeDocument: coversWhole, byteRange: [a, b, c, d])
    }
}
