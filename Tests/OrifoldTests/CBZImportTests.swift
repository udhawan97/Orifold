import AppKit
import PDFKit
import UniformTypeIdentifiers
import XCTest
@testable import Orifold

final class CBZImportTests: XCTestCase {
    private func littleEndian16(_ value: UInt16) -> [UInt8] {
        [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF)]
    }

    private func littleEndian32(_ value: UInt32) -> [UInt8] {
        (0..<4).map { UInt8((value >> (8 * $0)) & 0xFF) }
    }

    private func makeStoredZIP(_ entries: [(name: String, data: Data)]) -> Data {
        var localBytes: [UInt8] = []
        var centralBytes: [UInt8] = []

        for entry in entries {
            let name = Array(entry.name.utf8)
            let offset = UInt32(localBytes.count)
            localBytes += littleEndian32(0x04034b50)
            localBytes += littleEndian16(20)
            localBytes += littleEndian16(0)
            localBytes += littleEndian16(0)
            localBytes += littleEndian16(0)
            localBytes += littleEndian16(0)
            localBytes += littleEndian32(0)
            localBytes += littleEndian32(UInt32(entry.data.count))
            localBytes += littleEndian32(UInt32(entry.data.count))
            localBytes += littleEndian16(UInt16(name.count))
            localBytes += littleEndian16(0)
            localBytes += name
            localBytes += entry.data

            centralBytes += littleEndian32(0x02014b50)
            centralBytes += littleEndian16(20)
            centralBytes += littleEndian16(20)
            centralBytes += littleEndian16(0)
            centralBytes += littleEndian16(0)
            centralBytes += littleEndian16(0)
            centralBytes += littleEndian16(0)
            centralBytes += littleEndian32(0)
            centralBytes += littleEndian32(UInt32(entry.data.count))
            centralBytes += littleEndian32(UInt32(entry.data.count))
            centralBytes += littleEndian16(UInt16(name.count))
            centralBytes += littleEndian16(0)
            centralBytes += littleEndian16(0)
            centralBytes += littleEndian16(0)
            centralBytes += littleEndian16(0)
            centralBytes += littleEndian32(0)
            centralBytes += littleEndian32(offset)
            centralBytes += name
        }

        let centralOffset = UInt32(localBytes.count)
        var end: [UInt8] = []
        end += littleEndian32(0x06054b50)
        end += littleEndian16(0)
        end += littleEndian16(0)
        end += littleEndian16(UInt16(entries.count))
        end += littleEndian16(UInt16(entries.count))
        end += littleEndian32(UInt32(centralBytes.count))
        end += littleEndian32(centralOffset)
        end += littleEndian16(0)
        return Data(localBytes + centralBytes + end)
    }

    private func png(red: UInt8, green: UInt8, blue: UInt8) throws -> Data {
        let width = 32
        let height = 32
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try XCTUnwrap(
            CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.setFillColor(
            CGColor(
                red: CGFloat(red) / 255,
                green: CGFloat(green) / 255,
                blue: CGFloat(blue) / 255,
                alpha: 1
            )
        )
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let representation = NSBitmapImageRep(cgImage: try XCTUnwrap(context.makeImage()))
        return try XCTUnwrap(representation.representation(using: .png, properties: [:]))
    }

    private func centerColor(of page: PDFPage) throws -> NSColor {
        let image = page.thumbnail(of: CGSize(width: 80, height: 104), for: .mediaBox)
        let representation = try XCTUnwrap(
            NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: Int(image.size.width),
                pixelsHigh: Int(image.size.height),
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            )
        )
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: representation)
        image.draw(in: CGRect(origin: .zero, size: image.size))
        NSGraphicsContext.restoreGraphicsState()
        return try XCTUnwrap(
            representation.colorAt(
                x: representation.pixelsWide / 2,
                y: representation.pixelsHigh / 2
            )?.usingColorSpace(.sRGB)
        )
    }

    func testCBZImportsSupportedImagesInNaturalFilenameOrder() throws {
        let archive = makeStoredZIP([
            ("10.png", try png(red: 230, green: 30, blue: 30)),
            ("notes.txt", Data("ignored".utf8)),
            ("2.png", try png(red: 30, green: 220, blue: 30)),
            ("1.png", try png(red: 30, green: 30, blue: 230))
        ])

        let imported = try DocumentImportConverter.importedDocument(
            from: archive,
            contentType: .data,
            filename: "Natural Order.cbz",
            baseURL: nil
        )
        XCTAssertEqual(imported.pdfDocument.pageCount, 3)
        XCTAssertNil(imported.sourcePayload)
        XCTAssertNil(imported.originalPDFData)

        let first = try centerColor(of: XCTUnwrap(imported.pdfDocument.page(at: 0)))
        let second = try centerColor(of: XCTUnwrap(imported.pdfDocument.page(at: 1)))
        let third = try centerColor(of: XCTUnwrap(imported.pdfDocument.page(at: 2)))
        XCTAssertGreaterThan(first.blueComponent, first.redComponent)
        XCTAssertGreaterThan(second.greenComponent, second.blueComponent)
        XCTAssertGreaterThan(third.redComponent, third.greenComponent)
    }

    func testCBZWithoutImagesReportsAComicArchiveSpecificError() {
        let archive = makeStoredZIP([("README.txt", Data("no pages".utf8))])

        XCTAssertThrowsError(
            try DocumentImportConverter.importedDocument(
                from: archive,
                contentType: .orifoldCBZ,
                filename: "empty.cbz",
                baseURL: nil
            )
        ) { error in
            guard case DocumentImportConverter.ConversionError.comicArchiveNoImages = error else {
                return XCTFail("expected comicArchiveNoImages, got \(error)")
            }
        }
    }

    func testCBZWithUnreadableImageReportsTheEntryName() {
        let archive = makeStoredZIP([("001.png", Data("not an image".utf8))])

        XCTAssertThrowsError(
            try DocumentImportConverter.importedDocument(
                from: archive,
                contentType: .orifoldCBZ,
                filename: "broken.cbz",
                baseURL: nil
            )
        ) { error in
            guard case DocumentImportConverter.ConversionError.comicArchiveUnreadableImage(let name) = error else {
                return XCTFail("expected comicArchiveUnreadableImage, got \(error)")
            }
            XCTAssertEqual(name, "001.png")
        }
    }
}
