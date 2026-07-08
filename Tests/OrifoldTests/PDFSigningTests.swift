import AppKit
import PDFKit
import XCTest
@testable import Orifold

// Acceptance tests for the digital-signature feature (see docs/signing/SIGNING_SPEC.md).
//
// These are RED on purpose: every signing primitive currently throws
// `SigningError.notImplemented`. Codex's job is to make each of these pass WITHOUT
// weakening the assertions. They pin the byte-exact behaviour of the incremental-update
// signer (the part most likely to be subtly wrong) and the export-survival fix.

// MARK: - Module D: byte-exact ByteRange / Contents primitives

final class PDFByteRangeCalculatorTests: XCTestCase {

    /// A synthetic "signature-ready" buffer: a fixed-width `/ByteRange` placeholder and a
    /// `/Contents <00…00>` placeholder, exactly as the incremental update must emit them.
    /// We keep it tiny and ASCII so offsets are checkable by hand.
    private func makeSignatureReadyBytes(contentsHexDigits: Int = 32)
        -> (data: Data, openAngleIndex: Int, closeAngleIndex: Int) {
        let head = "%PDF-1.7\n1 0 obj\n<< /Type /Sig /SubFilter /ETSI.CAdES.detached "
        // Fixed-width ByteRange placeholder: four 10-digit right-justified slots.
        let byteRange = "/ByteRange [0000000000 0000000000 0000000000 0000000000] "
        let contentsPrefix = "/Contents <"
        let zeros = String(repeating: "0", count: contentsHexDigits)
        let contentsSuffix = ">"
        let tail = " >>\nendobj\n%%EOF\n"

        let prefixString = head + byteRange + contentsPrefix
        let prefixData = Data(prefixString.utf8)
        let openAngleIndex = prefixData.count - 1                 // index of '<'
        let closeAngleIndex = openAngleIndex + 1 + contentsHexDigits // index of '>'

        let full = prefixString + zeros + contentsSuffix + tail
        return (Data(full.utf8), openAngleIndex, closeAngleIndex)
    }

    func testComputeByteRangeExcludesExactlyTheContentsValueIncludingBrackets() throws {
        let fixture = makeSignatureReadyBytes()
        let range = try PDFByteRangeCalculator.computeByteRange(in: fixture.data)

        // segment 1 = everything up to (not including) '<'
        XCTAssertEqual(range.beforeOffset, 0)
        XCTAssertEqual(range.beforeLength, fixture.openAngleIndex)

        // segment 2 starts at the first byte AFTER '>' and runs to EOF
        XCTAssertEqual(range.afterOffset, fixture.closeAngleIndex + 1)
        XCTAssertEqual(range.afterLength, fixture.data.count - (fixture.closeAngleIndex + 1))

        // The gap that is NOT signed is exactly the `<...>` value.
        let gap = range.afterOffset - (range.beforeOffset + range.beforeLength)
        XCTAssertEqual(gap, fixture.closeAngleIndex - fixture.openAngleIndex + 1)
    }

    func testDigestInputIsTheTwoCoveredSpansConcatenatedAndSkipsTheGap() throws {
        let fixture = makeSignatureReadyBytes()
        let range = try PDFByteRangeCalculator.computeByteRange(in: fixture.data)
        let digestInput = try PDFByteRangeCalculator.digestInput(pdf: fixture.data, range: range)

        let expected = fixture.data[0..<range.beforeLength]
            + fixture.data[range.afterOffset..<(range.afterOffset + range.afterLength)]
        XCTAssertEqual(digestInput, Data(expected))

        // The digested bytes must contain NONE of the placeholder hex bytes.
        XCTAssertEqual(digestInput.count, fixture.data.count - (range.afterOffset - range.beforeLength))
    }

    func testWriteByteRangeOverwritesInPlaceWithoutShiftingDownstreamBytes() throws {
        let fixture = makeSignatureReadyBytes()
        let range = try PDFByteRangeCalculator.computeByteRange(in: fixture.data)
        let written = try PDFByteRangeCalculator.writeByteRange(range, into: fixture.data)

        // Same length — a shift by even one byte invalidates every subsequent offset.
        XCTAssertEqual(written.count, fixture.data.count)
        // The concrete integers must now be present in the ByteRange array.
        let text = String(decoding: written, as: UTF8.self)
        XCTAssertTrue(text.contains("/ByteRange ["))
        for value in range.array {
            XCTAssertTrue(text.contains(String(value)), "ByteRange missing \(value)")
        }
        // '<' and '>' must sit at the same offsets as before the rewrite.
        XCTAssertEqual(written.firstIndex(of: UInt8(ascii: "<")), fixture.data.firstIndex(of: UInt8(ascii: "<")))
    }

    func testFillContentsSplicesHexAndZeroPadsWithoutTouchingAnyOtherByte() throws {
        let fixture = makeSignatureReadyBytes(contentsHexDigits: 32)
        let range = try PDFByteRangeCalculator.computeByteRange(in: fixture.data)
        let der = Data([0xDE, 0xAD, 0xBE, 0xEF])
        let filled = try PDFByteRangeCalculator.fillContents(in: fixture.data, range: range, derSignature: der)

        XCTAssertEqual(filled.count, fixture.data.count, "filling must not change the file length")

        let open = fixture.openAngleIndex
        let close = fixture.closeAngleIndex
        let hex = String(decoding: filled[(open + 1)..<close], as: UTF8.self)
        XCTAssertTrue(hex.lowercased().hasPrefix("deadbeef"), "DER not spliced at the front: \(hex)")
        XCTAssertEqual(hex.count, 32, "placeholder width must be preserved")
        XCTAssertTrue(hex.dropFirst(8).allSatisfy { $0 == "0" }, "remainder must be zero-padded")

        // Everything outside the brackets is byte-identical to the original.
        XCTAssertEqual(filled[0...open], fixture.data[0...open])
        XCTAssertEqual(filled[close...], fixture.data[close...])
    }

    func testFillContentsRejectsSignatureLargerThanPlaceholder() throws {
        let fixture = makeSignatureReadyBytes(contentsHexDigits: 8) // room for only 4 DER bytes
        let range = try PDFByteRangeCalculator.computeByteRange(in: fixture.data)
        let tooBig = Data(repeating: 0xAB, count: 64)
        XCTAssertThrowsError(try PDFByteRangeCalculator.fillContents(in: fixture.data, range: range, derSignature: tooBig)) {
            XCTAssertEqual($0 as? SigningError, .contentsPlaceholderTooSmall)
        }
    }
}

// MARK: - Module D: end-to-end incremental-update structure

final class PDFIncrementalSignerStructureTests: XCTestCase {
    private func onePagePDFData() throws -> Data {
        let bounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        let page = PDFPage()
        page.setBounds(bounds, for: .mediaBox)
        let doc = PDFDocument()
        doc.insert(page, at: 0)
        return try XCTUnwrap(doc.dataRepresentation())
    }

    private func multiPagePDFData(count: Int = 3) throws -> Data {
        let bounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        let doc = PDFDocument()
        for index in 0..<count {
            let page = PDFPage()
            page.setBounds(bounds, for: .mediaBox)
            doc.insert(page, at: index)
        }
        return try XCTUnwrap(doc.dataRepresentation())
    }

    func testSignedOutputIsAnAppendOnlyIncrementalUpdate() throws {
        let original = try onePagePDFData()
        let field = SignatureFieldSpec(
            pageIndex: 0,
            rect: CGRect(x: 360, y: 60, width: 200, height: 60),
            signerName: "Ada Lovelace",
            reason: "Approval",
            location: "London"
        )
        // Trivial CMS callback so we exercise the PDF layout independent of real crypto.
        let signed = try PDFIncrementalSigner().sign(pdf: original, field: field, appearance: nil) { byteRangeBytes in
            XCTAssertFalse(byteRangeBytes.isEmpty, "signer must hand the CMS builder the ByteRange bytes")
            return Data([0x30, 0x03, 0x02, 0x01, 0x00]) // a minimal DER blob
        }

        // Incremental update = original bytes are a strict prefix; new bytes are appended.
        XCTAssertGreaterThan(signed.count, original.count)
        XCTAssertEqual(signed.prefix(original.count), original,
                       "an incremental update must not rewrite any original byte")

        let text = String(decoding: signed, as: UTF8.self)
        XCTAssertTrue(text.contains("/Type /Sig") || text.contains("/Type/Sig"))
        XCTAssertTrue(text.contains("/SubFilter /ETSI.CAdES.detached"))
        XCTAssertTrue(text.contains("/ByteRange"))
        XCTAssertTrue(text.contains("/Contents <"))
        XCTAssertTrue(text.contains("/AcroForm"))
        // Two startxref sections: the original plus the incremental one.
        XCTAssertGreaterThanOrEqual(text.components(separatedBy: "startxref").count - 1, 2)

        // Still a valid, openable PDF.
        XCTAssertNotNil(PDFDocument(data: signed))
    }

    func testSignedWidgetAttachesToRequestedPageObject() throws {
        let original = try multiPagePDFData()
        let field = SignatureFieldSpec(
            pageIndex: 1,
            rect: CGRect(x: 120, y: 80, width: 180, height: 54),
            signerName: "Grace Hopper"
        )
        let signed = try PDFIncrementalSigner().sign(pdf: original, field: field, appearance: nil) { _ in
            Data([0x30, 0x03, 0x02, 0x01, 0x00])
        }

        let text = String(decoding: signed, as: UTF8.self)
        let objects = pdfObjects(in: text)
        let fieldObject = try XCTUnwrap(objects.last { $0.body.contains("/Subtype /Widget") })
        let fieldObjectNumber = fieldObject.number
        let pageObject = try XCTUnwrap(objects.last {
            $0.body.contains("/Type /Page") &&
            !$0.body.contains("/Type /Pages") &&
            $0.body.contains("/Annots") &&
            $0.body.contains("\(fieldObjectNumber) 0 R")
        })
        let pageObjectNumber = pageObject.number

        XCTAssertTrue(text.contains("/P \(pageObjectNumber) 0 R"))
        XCTAssertNotEqual(pageObjectNumber, fieldObjectNumber)
        XCTAssertNotNil(PDFDocument(data: signed))
    }

    func testSignedWidgetIncludesVisibleAppearanceStreamWhenProvided() throws {
        let original = try onePagePDFData()
        let appearance = try SignatureAppearanceRenderer.pdfAppearanceStream(
            for: .typedName("Visible Signer"),
            bounds: CGRect(x: 0, y: 0, width: 180, height: 54)
        )
        let field = SignatureFieldSpec(
            pageIndex: 0,
            rect: CGRect(x: 120, y: 80, width: 180, height: 54),
            signerName: "Visible Signer"
        )

        let signed = try PDFIncrementalSigner().sign(pdf: original, field: field, appearance: appearance) { _ in
            Data([0x30, 0x03, 0x02, 0x01, 0x00])
        }

        let text = String(decoding: signed, as: UTF8.self)
        XCTAssertTrue(text.contains("/AP << /N"))
        XCTAssertTrue(text.contains("/Type /XObject /Subtype /Form"))
        XCTAssertNotNil(PDFDocument(data: signed))
    }

    func testSecondSignaturePreservesTheFirst() throws {
        let original = try onePagePDFData()
        let field1 = SignatureFieldSpec(pageIndex: 0, rect: CGRect(x: 40, y: 60, width: 180, height: 50), signerName: "First")
        let field2 = SignatureFieldSpec(pageIndex: 0, rect: CGRect(x: 360, y: 60, width: 180, height: 50), signerName: "Second")
        let cms: (Data) throws -> Data = { _ in Data([0x30, 0x03, 0x02, 0x01, 0x00]) }

        let once = try PDFIncrementalSigner().sign(pdf: original, field: field1, appearance: nil, cms: cms)
        let twice = try PDFIncrementalSigner().sign(pdf: once, field: field2, appearance: nil, cms: cms)

        // The first signing's bytes survive verbatim under the second incremental update.
        XCTAssertEqual(twice.prefix(once.count), once, "second signature must not disturb the first")
        let text = String(decoding: twice, as: UTF8.self)
        XCTAssertGreaterThanOrEqual(text.components(separatedBy: "/Type /Sig").count
                                    + text.components(separatedBy: "/Type/Sig").count - 2, 2)
    }

    func testSecondSignaturePreservesFirstFieldInAcroFormFieldsArray() throws {
        let original = try onePagePDFData()
        let field1 = SignatureFieldSpec(pageIndex: 0, rect: CGRect(x: 40, y: 60, width: 180, height: 50), signerName: "First")
        let field2 = SignatureFieldSpec(pageIndex: 0, rect: CGRect(x: 360, y: 60, width: 180, height: 50), signerName: "Second")
        let cms: (Data) throws -> Data = { _ in Data([0x30, 0x03, 0x02, 0x01, 0x00]) }

        let once = try PDFIncrementalSigner().sign(pdf: original, field: field1, appearance: nil, cms: cms)
        let twice = try PDFIncrementalSigner().sign(pdf: once, field: field2, appearance: nil, cms: cms)

        let text = String(decoding: twice, as: UTF8.self)
        let objects = pdfObjects(in: text)
        let widgetObjectNumbers = objects.filter { $0.body.contains("/Subtype /Widget") }.map(\.number)
        XCTAssertEqual(widgetObjectNumbers.count, 2, "both signature widgets must exist as objects")

        // The LATEST /AcroForm revision (the one actually in effect after the second signing)
        // must list both widgets — dropping the first would silently orphan its field from
        // the document's field tree even though the field object itself remains byte-intact.
        let acroFormMatches = try NSRegularExpression(pattern: #"/AcroForm\s+(\d+)\s+0\s+R"#)
            .matches(in: text, range: NSRange(text.startIndex..., in: text))
        let lastMatch = try XCTUnwrap(acroFormMatches.last)
        let numberRange = try XCTUnwrap(Range(lastMatch.range(at: 1), in: text))
        let acroFormObjectNumber = try XCTUnwrap(Int(text[numberRange]))
        let acroFormObject = try XCTUnwrap(objects.last { $0.number == acroFormObjectNumber })

        for widgetNumber in widgetObjectNumbers {
            XCTAssertTrue(acroFormObject.body.contains("\(widgetNumber) 0 R"),
                          "/AcroForm /Fields must retain widget \(widgetNumber) from the earlier signature")
        }
    }

    func testManySuccessiveSignaturesAllRemainListedInAcroFormFields() throws {
        // Regression pin for a substring false-match: "1 0 obj" is itself a substring of
        // "21 0 obj", so a naive object-body lookup used while merging /AcroForm /Fields can
        // silently return the WRONG (later, larger-numbered) object once numbering crosses
        // into ambiguous territory. Sign enough times to push object numbers past 21 and
        // verify every earlier widget survives in the final /AcroForm.
        var pdf = try onePagePDFData()
        let cms: (Data) throws -> Data = { _ in Data([0x30, 0x03, 0x02, 0x01, 0x00]) }
        let signingCount = 25

        for index in 0..<signingCount {
            let field = SignatureFieldSpec(
                pageIndex: 0,
                rect: CGRect(x: 20, y: 20, width: 80, height: 30),
                signerName: "Signer \(index)"
            )
            pdf = try PDFIncrementalSigner().sign(pdf: pdf, field: field, appearance: nil, cms: cms)
        }

        let text = String(decoding: pdf, as: UTF8.self)
        let objects = pdfObjects(in: text)
        let widgetObjectNumbers = objects.filter { $0.body.contains("/Subtype /Widget") }.map(\.number)
        XCTAssertEqual(widgetObjectNumbers.count, signingCount, "every widget object must exist")
        XCTAssertGreaterThan(
            widgetObjectNumbers.max() ?? 0, 21,
            "object numbers must grow past the known '1 0 obj' substring-of-'21 0 obj' collision point for this test to be meaningful"
        )

        let acroFormMatches = try NSRegularExpression(pattern: #"/AcroForm\s+(\d+)\s+0\s+R"#)
            .matches(in: text, range: NSRange(text.startIndex..., in: text))
        let lastMatch = try XCTUnwrap(acroFormMatches.last)
        let numberRange = try XCTUnwrap(Range(lastMatch.range(at: 1), in: text))
        let acroFormObjectNumber = try XCTUnwrap(Int(text[numberRange]))
        let acroFormObject = try XCTUnwrap(objects.last { $0.number == acroFormObjectNumber })

        for widgetNumber in widgetObjectNumbers {
            XCTAssertTrue(
                acroFormObject.body.contains("\(widgetNumber) 0 R"),
                "/AcroForm /Fields must retain widget \(widgetNumber) even after many successive signings push object numbers past ambiguous substring boundaries"
            )
        }
    }

    func testNonASCIISignerNameIsEncodedAsUTF16BEWithByteOrderMark() throws {
        let original = try onePagePDFData()
        let signerName = "山田太郎"
        let field = SignatureFieldSpec(pageIndex: 0, rect: CGRect(x: 40, y: 60, width: 180, height: 50), signerName: signerName)
        let signed = try PDFIncrementalSigner().sign(pdf: original, field: field, appearance: nil) { _ in
            Data([0x30, 0x03, 0x02, 0x01, 0x00])
        }

        var expectedBytes = Data([0xFE, 0xFF])
        for unit in signerName.utf16 {
            expectedBytes.append(UInt8(unit >> 8))
            expectedBytes.append(UInt8(unit & 0xFF))
        }

        XCTAssertNotNil(signed.range(of: expectedBytes),
                        "signer name must round-trip as UTF-16BE bytes with a BOM, not corrupted UTF-8-of-UTF-8 bytes")
        XCTAssertNotNil(PDFDocument(data: signed))
    }

    func testEmbeddedNewlineAndCarriageReturnAreEscapedInLiteralStrings() throws {
        let original = try onePagePDFData()
        let field = SignatureFieldSpec(
            pageIndex: 0,
            rect: CGRect(x: 40, y: 60, width: 180, height: 50),
            signerName: "Ada Lovelace",
            reason: "Line one\nLine two\rLine three"
        )
        let signed = try PDFIncrementalSigner().sign(pdf: original, field: field, appearance: nil) { _ in
            Data([0x30, 0x03, 0x02, 0x01, 0x00])
        }

        let text = String(decoding: signed, as: UTF8.self)
        XCTAssertTrue(text.contains(#"Line one\nLine two\rLine three"#),
                      "a literal newline/carriage-return inside a PDF string must be escaped as \\n / \\r, not written as a raw EOL byte")
        // The raw bytes must never appear unescaped inside the /Reason value.
        XCTAssertFalse(signed.range(of: Data("Line one\nLine two".utf8)) != nil,
                       "an unescaped raw newline byte leaked into the signed PDF")
        XCTAssertNotNil(PDFDocument(data: signed))
    }

    func testEstimatedSignatureDERBytesWidensContentsPlaceholderBeyondTheDefaultFloor() throws {
        let original = try onePagePDFData()
        let field = SignatureFieldSpec(
            pageIndex: 0,
            rect: CGRect(x: 40, y: 60, width: 180, height: 50),
            signerName: "Wide Signer",
            estimatedSignatureDERBytes: 20_000
        )
        let signed = try PDFIncrementalSigner().sign(pdf: original, field: field, appearance: nil) { _ in
            Data([0x30, 0x03, 0x02, 0x01, 0x00])
        }

        let text = String(decoding: signed, as: UTF8.self)
        let contentsRange = try XCTUnwrap(text.range(of: #"/Contents <[0-9a-fA-F]+>"#, options: .regularExpression))
        let placeholderHexDigits = text[contentsRange].count - "/Contents <>".count
        XCTAssertGreaterThan(placeholderHexDigits, 32_768,
                             "a large estimated DER size must widen the placeholder beyond the default floor")
    }

    /// Builds a minimal PDF whose most recent cross-reference section is a modern
    /// cross-reference STREAM object (`/Type /XRef`) rather than a classic `xref` table —
    /// what most non-Orifold tools (Ghostscript, mutool, recent Adobe output) now emit.
    /// `startxref` points at an `N 0 obj` header, not the literal `xref` keyword.
    private func xrefStreamPDFData() -> Data {
        var body = "%PDF-1.5\n"
        body += "1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n"
        body += "2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n"
        body += "3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] >>\nendobj\n"
        let xrefStreamOffset = body.utf8.count
        body += "4 0 obj\n<< /Type /XRef /Size 5 /Root 1 0 R /W [1 2 1] /Length 4 >>\nstream\n\u{0}\u{0}\u{0}\u{0}\nendstream\nendobj\n"
        body += "startxref\n\(xrefStreamOffset)\n%%EOF\n"
        return Data(body.utf8)
    }

    func testSigningRefusesAPDFWhoseLastCrossReferenceSectionIsAnXRefStream() throws {
        let field = SignatureFieldSpec(pageIndex: 0, rect: CGRect(x: 40, y: 60, width: 180, height: 50), signerName: "Signer")
        XCTAssertThrowsError(
            try PDFIncrementalSigner().sign(pdf: xrefStreamPDFData(), field: field, appearance: nil) { _ in
                Data([0x30, 0x03, 0x02, 0x01, 0x00])
            }
        ) { error in
            XCTAssertEqual(error as? SigningError, .unsupportedPDFStructure,
                           "an xref-stream-only PDF must be refused, not silently corrupted with a classic-xref incremental update")
        }
    }

    func testSigningStillAcceptsAClassicXrefTablePDF() throws {
        // Sanity companion to the refusal test above: the ordinary PDFKit-produced fixture
        // used throughout this file must still sign successfully (classic xref table).
        let original = try onePagePDFData()
        let field = SignatureFieldSpec(pageIndex: 0, rect: CGRect(x: 40, y: 60, width: 180, height: 50), signerName: "Signer")
        let signed = try PDFIncrementalSigner().sign(pdf: original, field: field, appearance: nil) { _ in
            Data([0x30, 0x03, 0x02, 0x01, 0x00])
        }
        XCTAssertNotNil(PDFDocument(data: signed))
    }
}

final class SignatureSelfCheckTests: XCTestCase {
    private func onePagePDFData() throws -> Data {
        let bounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        let page = PDFPage()
        page.setBounds(bounds, for: .mediaBox)
        let doc = PDFDocument()
        doc.insert(page, at: 0)
        return try XCTUnwrap(doc.dataRepresentation())
    }

    func testSelfCheckPassesForARealSignedDocument() throws {
        let original = try onePagePDFData()
        let field = SignatureFieldSpec(pageIndex: 0, rect: CGRect(x: 40, y: 60, width: 180, height: 50), signerName: "Signer")
        let signed = try PDFIncrementalSigner().sign(pdf: original, field: field, appearance: nil) { _ in
            Data([0x30, 0x03, 0x02, 0x01, 0x00])
        }

        let result = SignatureSelfCheck.verify(signedPDF: signed)
        XCTAssertTrue(result.coversWholeDocument,
                     "a genuine incremental-update signature must cover the whole exported file")
        let byteRange = try XCTUnwrap(result.byteRange)
        XCTAssertEqual(byteRange.count, 4)
        XCTAssertEqual(byteRange[0], 0)
        XCTAssertEqual(byteRange[2] + byteRange[3], signed.count)
    }

    func testSelfCheckFailsWhenTrailingBytesWereAppendedAfterSigning() throws {
        // Simulates a corrupted/appended-to export: the /ByteRange still claims the
        // ORIGINAL file length, but the file on disk is now longer — exactly the case a
        // post-export self-check exists to catch.
        let original = try onePagePDFData()
        let field = SignatureFieldSpec(pageIndex: 0, rect: CGRect(x: 40, y: 60, width: 180, height: 50), signerName: "Signer")
        var signed = try PDFIncrementalSigner().sign(pdf: original, field: field, appearance: nil) { _ in
            Data([0x30, 0x03, 0x02, 0x01, 0x00])
        }
        signed.append(Data("not part of the signed range".utf8))

        let result = SignatureSelfCheck.verify(signedPDF: signed)
        XCTAssertFalse(result.coversWholeDocument,
                       "appending bytes after the signed ByteRange must be detected, not silently accepted")
    }

    func testSelfCheckFailsGracefullyWithNoByteRange() {
        let result = SignatureSelfCheck.verify(signedPDF: Data("%PDF-1.4\nnot a signed document".utf8))
        XCTAssertFalse(result.coversWholeDocument)
        XCTAssertNil(result.byteRange)
    }

    func testSelfCheckIgnoresADecoyByteRangeInsideAnAppendedAppearanceStream() throws {
        // Regression pin: the appearance-stream XObject is appended to the file AFTER the
        // signature object. If its content stream happens to contain the literal bytes
        // "/ByteRange [...]" (e.g. embedded font metadata, or a comment), a naive
        // last-match-in-file search would pick up that decoy instead of the real
        // signature dictionary's ByteRange.
        let original = try onePagePDFData()
        let field = SignatureFieldSpec(pageIndex: 0, rect: CGRect(x: 40, y: 60, width: 180, height: 50), signerName: "Signer")
        let decoyAppearance = PDFAppearanceStream(
            xobject: Data("% /ByteRange [0000000001 0000000002 0000000003 0000000004]\n".utf8),
            bbox: CGRect(x: 0, y: 0, width: 180, height: 50)
        )
        let signed = try PDFIncrementalSigner().sign(pdf: original, field: field, appearance: decoyAppearance) { _ in
            Data([0x30, 0x03, 0x02, 0x01, 0x00])
        }

        let result = SignatureSelfCheck.verify(signedPDF: signed)
        XCTAssertTrue(result.coversWholeDocument,
                     "must find the REAL signature's /ByteRange, not the decoy in the appended appearance stream")
        let byteRange = try XCTUnwrap(result.byteRange)
        XCTAssertNotEqual(byteRange, [1, 2, 3, 4], "must not have matched the decoy ByteRange")
        XCTAssertEqual(byteRange[2] + byteRange[3], signed.count)
    }
}

// MARK: - Module E: the export-survival bug (currently reproduces as data loss)

final class SignatureExportSurvivalTests: XCTestCase {
    /// A solid-black PNG we can detect after rendering.
    private func blackPNG(width: Int, height: Int) throws -> Data {
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.black.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        NSGraphicsContext.restoreGraphicsState()
        return try XCTUnwrap(rep.representation(using: .png, properties: [:]))
    }

    private func blankPageData() throws -> Data {
        let page = PDFPage()
        page.setBounds(CGRect(x: 0, y: 0, width: 612, height: 792), for: .mediaBox)
        let doc = PDFDocument()
        doc.insert(page, at: 0)
        return try XCTUnwrap(doc.dataRepresentation())
    }

    func testBakedVisualSignatureRejectsUnmappedPlacement() throws {
        let pdfData = try blankPageData()
        let placement = SignaturePlacement(
            pageRefId: UUID(),
            imageData: try blackPNG(width: 120, height: 40),
            rect: CGRect(x: 100, y: 100, width: 120, height: 40),
            signerName: "Ada"
        )

        XCTAssertThrowsError(try SignatureExportBaker.bake(placements: [placement], into: pdfData) { _ in nil }) { error in
            XCTAssertEqual(error as? SigningError, .invalidPDF)
        }
    }
}

private func pdfObjects(in text: String) -> [(number: Int, body: String)] {
    var objects: [(number: Int, body: String)] = []
    var currentNumber: Int?
    var currentBody: [Substring] = []

    for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
        let parts = line.split(separator: " ")
        if currentNumber == nil,
           parts.count >= 3,
           let number = Int(parts[0]),
           parts[1] == "0",
           parts[2] == "obj" {
            currentNumber = number
            let remainder = parts.dropFirst(3).joined(separator: " ")
            if !remainder.isEmpty {
                currentBody.append(Substring(remainder))
            }
            continue
        }

        if line == "endobj", let number = currentNumber {
            objects.append((number, currentBody.joined(separator: "\n")))
            currentNumber = nil
            currentBody.removeAll()
            continue
        }

        if currentNumber != nil {
            currentBody.append(line)
        }
    }

    return objects
}
