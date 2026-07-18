import CoreGraphics
import XCTest
@testable import Orifold

/// Feature G1: the Core Image barcode/QR generator. Every symbology must yield a real,
/// non-empty raster; an empty payload and an over-capacity payload must both throw. All
/// assertions are on the produced `CGImage`'s dimensions (CI-safe — no display or decode
/// dependency here; the round-trip decode lives in `BarcodeScannerTests`).
final class BarcodeGeneratorTests: XCTestCase {
    func testEachSymbologyProducesANonEmptyImage() throws {
        for symbology in BarcodeSymbology.allCases {
            let image = try BarcodeGenerator.image(for: "ORIFOLD-2026", symbology: symbology)
            XCTAssertGreaterThan(image.width, 0, "\(symbology) produced a zero-width image")
            XCTAssertGreaterThan(image.height, 0, "\(symbology) produced a zero-height image")
        }
    }

    func testIntegerScaleUpscalesTheModuleGrid() throws {
        // A larger scale factor must yield a proportionally larger raster (nearest-neighbour
        // integer upscale), never the same native 1px-per-module size.
        let small = try BarcodeGenerator.image(for: "SCALE", symbology: .qr, scale: 4)
        let large = try BarcodeGenerator.image(for: "SCALE", symbology: .qr, scale: 12)
        XCTAssertGreaterThan(large.width, small.width)
        XCTAssertGreaterThan(large.height, small.height)
    }

    func testEmptyPayloadThrows() {
        XCTAssertThrowsError(try BarcodeGenerator.image(for: "", symbology: .qr)) { error in
            XCTAssertEqual(error as? BarcodeError, .emptyPayload)
        }
        // Whitespace-only is empty too.
        XCTAssertThrowsError(try BarcodeGenerator.image(for: "   ", symbology: .code128)) { error in
            XCTAssertEqual(error as? BarcodeError, .emptyPayload)
        }
    }

    func testOversizePayloadThrows() {
        let overLimit = String(repeating: "A", count: BarcodeSymbology.code128.maxPayloadBytes + 1)
        XCTAssertThrowsError(try BarcodeGenerator.image(for: overLimit, symbology: .code128)) { error in
            XCTAssertEqual(error as? BarcodeError, .payloadTooLong(max: BarcodeSymbology.code128.maxPayloadBytes))
        }
    }
}
