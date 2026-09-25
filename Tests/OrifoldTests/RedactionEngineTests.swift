import AppKit
import PDFKit
import CQPDF
import XCTest
@testable import Orifold

/// True redaction: content under a region must leave the object graph, not just be covered.
/// Text is read back through PDFium (`readingOrderText`) — never `PDFPage.string`.
final class RedactionEngineTests: XCTestCase {

    private let secretRegion = CGRect(x: 60, y: 690, width: 200, height: 30)

    // MARK: - Text

    func testTextUnderRegionIsRemovedAndTextElsewhereSurvives() throws {
        let source = twoLineFixture()
        XCTAssertTrue(text(source).contains("SECRET"), "fixture sanity")

        let redacted = try RedactionEngine.redact(source, regions: [0: [secretRegion]])

        XCTAssertFalse(text(redacted).contains("SECRET"))
        XCTAssertTrue(text(redacted).contains("KEEPME"), "text outside the region must stay text")
    }

    func testRegionIsBurnedInBlack() throws {
        let redacted = try RedactionEngine.redact(twoLineFixture(), regions: [0: [secretRegion]])

        XCTAssertLessThan(try luminance(of: redacted, at: CGPoint(x: secretRegion.midX, y: secretRegion.midY)), 0.2)
        XCTAssertGreaterThan(try luminance(of: redacted, at: CGPoint(x: 500, y: 100)), 0.8)
    }

    func testPartiallyCoveredLineKeepsItsVisibleNeighboursAsPixels() throws {
        let source = EditingFixturePDFBuilder.makePDF(runs: [
            .init(string: "Alpha SECRET Omega", origin: CGPoint(x: 72, y: 700), fontSize: 28)
        ])
        let secretStart = 72 + width(of: "Alpha ", fontSize: 28)
        let region = CGRect(x: secretStart, y: 690, width: width(of: "SECRET", fontSize: 28), height: 36)

        let redacted = try RedactionEngine.redact(source, regions: [0: [region]])

        XCTAssertFalse(text(redacted).contains("SECRET"))
        let alphaInk = try minimumLuminance(of: redacted, in: CGRect(x: 72, y: 700, width: 60, height: 20))
        XCTAssertLessThan(alphaInk, 0.5, "words beside the region must still render")
    }

    func testRotatedPageIsRedactedInUserSpace() throws {
        let source = EditingFixturePDFBuilder.makePDF(runs: [
            .init(string: "SECRET", origin: CGPoint(x: 72, y: 700)),
            .init(string: "KEEPME", origin: CGPoint(x: 72, y: 400))
        ], rotation: 90)

        let redacted = try RedactionEngine.redact(source, regions: [0: [secretRegion]])

        XCTAssertFalse(text(redacted).contains("SECRET"))
        XCTAssertTrue(text(redacted).contains("KEEPME"))
    }

    func testEmptyRegionsReturnInputUnchanged() throws {
        let source = twoLineFixture()
        XCTAssertEqual(try RedactionEngine.redact(source, regions: [:]), source)
        XCTAssertEqual(try RedactionEngine.redact(source, regions: [0: []]), source)
    }

    // MARK: - Annotations

    func testIntersectingAnnotationIsRemovedAndOthersSurvive() throws {
        let source = try withAnnotations(twoLineFixture()) { page in
            page.addAnnotation(PDFAnnotation(bounds: CGRect(x: 80, y: 695, width: 40, height: 20), forType: .square, withProperties: nil))
            page.addAnnotation(PDFAnnotation(bounds: CGRect(x: 300, y: 100, width: 40, height: 20), forType: .square, withProperties: nil))
        }

        let redacted = try RedactionEngine.redact(source, regions: [0: [secretRegion]])

        let annotations = try XCTUnwrap(PDFDocument(data: redacted)?.page(at: 0)).annotations
        XCTAssertEqual(annotations.count, 1)
        XCTAssertEqual(annotations.first?.bounds.minX ?? 0, 300, accuracy: 1)
    }

    func testFormFieldInRegionIsRefused() throws {
        let source = try withAnnotations(twoLineFixture()) { page in
            let field = PDFAnnotation(bounds: CGRect(x: 80, y: 695, width: 120, height: 20), forType: .widget, withProperties: nil)
            field.widgetFieldType = .text
            field.fieldName = "ssn"
            page.addAnnotation(field)
        }

        XCTAssertThrowsError(try RedactionEngine.redact(source, regions: [0: [secretRegion]])) { error in
            XCTAssertEqual(error as? RedactionEngine.Failure, .formFieldInRegion(pageIndex: 0))
        }
    }

    func testNoStreamInTheFileStillCarriesTheRedactedText() throws {
        // Standard-14 Helvetica + WinAnsi keeps the text as literal ASCII in the content
        // stream, so a byte search over every decoded stream is a real leak detector.
        let source = try plainTextFixture()
        XCTAssertTrue(try streamsCarry("SECRET", in: source), "fixture sanity")

        let redacted = try RedactionEngine.redact(source, regions: [0: [secretRegion]])

        XCTAssertFalse(try streamsCarry("SECRET", in: redacted))
        XCTAssertTrue(try streamsCarry("KEEPME", in: redacted), "detector sanity: surviving text is found")
    }

    // MARK: - Images

    private let imageRect = CGRect(x: 100, y: 300, width: 200, height: 200)

    func testPartiallyCoveredImageIsBlackedOnlyUnderTheRegion() throws {
        let region = CGRect(x: 90, y: 290, width: 110, height: 220)   // left half of the image

        let redacted = try RedactionEngine.redact(try redSquareFixture(), regions: [0: [region]])

        XCTAssertEqual(try imageStreamCount(redacted), 1, "the original pixels must not survive as an orphan stream")
        XCTAssertEqual(try imageWidths(redacted), [64], "pixels are edited in place at native resolution, not re-rasterized")
        XCTAssertLessThan(try luminance(of: redacted, at: CGPoint(x: 150, y: 400)), 0.2)
        let right = try XCTUnwrap(bitmap(redacted).colorAt(x: 260, y: 792 - 400)?.usingColorSpace(.deviceRGB))
        XCTAssertGreaterThan(right.redComponent, 0.8)
        XCTAssertLessThan(right.greenComponent, 0.2)
    }

    func testFullyCoveredImageLeavesNoXObjectBehind() throws {
        let source = try redSquareFixture()
        XCTAssertEqual(try imageStreamCount(source), 1, "fixture sanity")

        let redacted = try RedactionEngine.redact(source, regions: [0: [imageRect.insetBy(dx: -10, dy: -10)]])

        XCTAssertEqual(try imageStreamCount(redacted), 0, "a removed image must not stay anywhere in the file")
        XCTAssertTrue(text(redacted).contains("KEEPME"))
    }

    func testImageFromInheritedResourcesLeavesNoStreamBehind() throws {
        // /Resources on the /Pages node: PDFium regenerates only the page's own dictionary,
        // so without the qpdf prune the image stays reachable — and in the file.
        let source = try inheritedImageFixture()
        XCTAssertEqual(try imageStreamCount(source), 1, "fixture sanity")

        let redacted = try RedactionEngine.redact(source, regions: [0: [imageRect.insetBy(dx: -10, dy: -10)]])

        XCTAssertEqual(try imageStreamCount(redacted), 0)
        XCTAssertTrue(try streamsCarry("KEEPME", in: redacted))
    }

    // MARK: - Fixtures & probes

    private func inheritedImageFixture() throws -> Data {
        let content = "q 200 0 0 200 100 300 cm /Im1 Do Q\nBT /F1 12 Tf 72 700 Td (KEEPME) Tj ET\n"
        let pixels = String(repeating: "FF0000", count: 4)
        let raw = """
        %PDF-1.4
        1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj
        2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 \
        /Resources << /Font << /F1 4 0 R >> /XObject << /Im1 6 0 R >> >> >> endobj
        3 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 5 0 R >> endobj
        4 0 obj << /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >> endobj
        5 0 obj << /Length \(content.utf8.count) >> stream
        \(content)endstream endobj
        6 0 obj << /Type /XObject /Subtype /Image /Width 2 /Height 2 /ColorSpace /DeviceRGB \
        /BitsPerComponent 8 /Filter /ASCIIHexDecode /Length \(pixels.count + 1) >> stream
        \(pixels)>
        endstream endobj
        trailer << /Root 1 0 R >>
        %%EOF
        """
        return try XCTUnwrap(QPDFService.repaired(Data(raw.utf8)))
    }

    /// A 200×200pt solid red image XObject plus a line of text elsewhere.
    private func redSquareFixture() throws -> Data {
        let data = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        let consumer = try XCTUnwrap(CGDataConsumer(data: data as CFMutableData))
        let context = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &mediaBox, nil))
        let pixels = try XCTUnwrap(CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        pixels.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        pixels.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        let image = try XCTUnwrap(pixels.makeImage())

        context.beginPDFPage(nil)
        context.draw(image, in: imageRect)
        let font = CTFontCreateWithName("Helvetica" as CFString, 12, nil)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: "KEEPME", attributes: [.font: font]))
        context.textPosition = CGPoint(x: 72, y: 700)
        CTLineDraw(line, context)
        context.endPDFPage()
        context.closePDF()
        return data as Data
    }

    private func plainTextFixture() throws -> Data {
        let content = "BT /F1 12 Tf 72 700 Td (SECRET) Tj ET\nBT /F1 12 Tf 72 400 Td (KEEPME) Tj ET\n"
        let raw = """
        %PDF-1.4
        1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj
        2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 >> endobj
        3 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] \
        /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >> endobj
        4 0 obj << /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >> endobj
        5 0 obj << /Length \(content.utf8.count) >> stream
        \(content)endstream endobj
        trailer << /Root 1 0 R >>
        %%EOF
        """
        return try XCTUnwrap(QPDFService.repaired(Data(raw.utf8)))
    }

    /// Every indirect object in the file — referenced or orphaned — as qpdf sees it.
    private func eachObject(in data: Data, _ body: (qpdf_data, qpdf_oh) -> Void) throws {
        let visited: Bool? = QPDFService.withQPDF(data, description: "test-objects") { qpdf in
            // Written trailers may omit /Size; fixtures are tiny, so scan a fixed id range.
            for id in Int32(1)...512 {
                let object = qpdf_get_object_by_id(qpdf, id, 0)
                if qpdf_oh_is_null(qpdf, object) == QPDF_FALSE { body(qpdf, object) }
            }
            return true
        }
        XCTAssertEqual(visited, true)
    }

    private func decodedStreams(_ data: Data) throws -> [String] {
        var streams: [String] = []
        try eachObject(in: data) { qpdf, object in
            guard qpdf_oh_is_stream(qpdf, object) != QPDF_FALSE else { return }
            var buffer: UnsafeMutablePointer<UInt8>?
            var length = 0
            guard !QPDFService.hasErrors(qpdf_oh_get_stream_data(qpdf, object, qpdf_dl_generalized, nil, &buffer, &length)),
                  let buffer else { return }
            streams.append(String(decoding: UnsafeBufferPointer(start: buffer, count: length), as: UTF8.self))
            free(buffer)
        }
        return streams
    }

    /// WinAnsi text as either a literal string or the hex string PDFium re-emits it as.
    private func streamsCarry(_ text: String, in data: Data) throws -> Bool {
        let hex = text.utf8.map { String(format: "%02X", $0) }.joined()
        return try decodedStreams(data).contains {
            $0.contains(text) || $0.uppercased().replacingOccurrences(of: " ", with: "").contains(hex)
        }
    }

    private func imageStreamCount(_ data: Data) throws -> Int {
        try imageWidths(data).count
    }

    /// /Width of every image stream in the file, orphans included.
    private func imageWidths(_ data: Data) throws -> [Int] {
        var widths: [Int] = []
        try eachObject(in: data) { qpdf, object in
            guard qpdf_oh_is_stream(qpdf, object) != QPDF_FALSE else { return }
            let dictionary = qpdf_oh_get_dict(qpdf, object)
            if qpdf_oh_is_name_and_equals(qpdf, qpdf_oh_get_key(qpdf, dictionary, "/Subtype"), "/Image") != QPDF_FALSE {
                widths.append(Int(qpdf_oh_get_int_value(qpdf, qpdf_oh_get_key(qpdf, dictionary, "/Width"))))
            }
        }
        return widths
    }

    private func twoLineFixture() -> Data {
        EditingFixturePDFBuilder.makePDF(runs: [
            .init(string: "SECRET", origin: CGPoint(x: 72, y: 700)),
            .init(string: "KEEPME", origin: CGPoint(x: 72, y: 400))
        ])
    }

    private func text(_ data: Data, page: Int = 0) -> String {
        PDFTextAnalysisEngine.readingOrderText(data: data, pageIndex: page)
    }

    private func width(of string: String, fontSize: CGFloat) -> CGFloat {
        let font = CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: [.font: font]))
        return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }

    private func withAnnotations(_ data: Data, _ add: (PDFPage) -> Void) throws -> Data {
        let document = try XCTUnwrap(PDFDocument(data: data))
        add(try XCTUnwrap(document.page(at: 0)))
        return try XCTUnwrap(PDFSerializer.data(from: document))
    }

    /// Renders page 0 at 1pt = 1px (unrotated fixtures only) and samples PDF user space.
    private func bitmap(_ data: Data) throws -> NSBitmapImageRep {
        let page = try XCTUnwrap(PDFDocument(data: data)?.page(at: 0))
        let size = page.bounds(for: .mediaBox).size
        let image = page.thumbnail(of: size, for: .mediaBox)
        return try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation)))
    }

    private func luminance(of data: Data, at point: CGPoint) throws -> Double {
        let rep = try bitmap(data)
        return luminance(rep, point)
    }

    private func minimumLuminance(of data: Data, in rect: CGRect) throws -> Double {
        let rep = try bitmap(data)
        var darkest = 1.0
        for x in stride(from: rect.minX, to: rect.maxX, by: 2) {
            for y in stride(from: rect.minY, to: rect.maxY, by: 2) {
                darkest = min(darkest, luminance(rep, CGPoint(x: x, y: y)))
            }
        }
        return darkest
    }

    private func luminance(_ rep: NSBitmapImageRep, _ point: CGPoint) -> Double {
        let scaleX = Double(rep.pixelsWide) / 612, scaleY = Double(rep.pixelsHigh) / 792
        let px = Int(Double(point.x) * scaleX), py = rep.pixelsHigh - 1 - Int(Double(point.y) * scaleY)
        guard let color = rep.colorAt(x: px, y: py)?.usingColorSpace(.deviceRGB) else { return 1 }
        return 0.299 * color.redComponent + 0.587 * color.greenComponent + 0.114 * color.blueComponent
    }
}
