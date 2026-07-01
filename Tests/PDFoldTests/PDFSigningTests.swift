import AppKit
import PDFKit
import XCTest
@testable import PDFold

// Acceptance tests for the digital-signature feature (see SIGNING_SPEC.md).
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

    func testBakedVisualSignatureSurvivesExportAndRendersInThePage() throws {
        let pdfData = try blankPageData()
        let rect = CGRect(x: 200, y: 360, width: 200, height: 80)
        let placement = SignaturePlacement(
            pageRefId: UUID(),
            imageData: try blackPNG(width: 200, height: 80),
            rect: rect,
            signerName: "Ada"
        )

        let baked = try SignatureExportBaker.bake(placements: [placement], into: pdfData) { _ in 0 }

        // Reopen the exported bytes from scratch — the signature must still be there.
        let reopened = try XCTUnwrap(PDFDocument(data: baked))
        let page = try XCTUnwrap(reopened.page(at: 0))

        // Render the page and sample the centre of the signature rect: it must be dark ink,
        // proving the signature was baked into page content, not lost like the annotation path.
        let thumb = page.thumbnail(of: CGSize(width: 612, height: 792), for: .mediaBox)
        let tiff = try XCTUnwrap(thumb.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        let sample = try XCTUnwrap(bitmap.colorAt(x: Int(rect.midX), y: Int(792 - rect.midY))?.usingColorSpace(.deviceRGB))
        XCTAssertLessThan(sample.brightnessComponent, 0.5, "baked signature ink is missing from the exported page")
    }
}
