import CoreGraphics
import XCTest
@testable import Orifold

/// Feature G3: the Vision barcode scanner, proven by a generate→detect round-trip. Both halves
/// run entirely in-memory on-device (Core Image encode, Vision decode) — no network, no
/// PDFPage.string — so the test is deterministic and CI-safe. A blank page yields nothing.
final class BarcodeScannerTests: XCTestCase {
    func testGenerateThenDetectRoundTripsQR() throws {
        let payload = "https://orifold.app/wave2-scan"
        let image = try BarcodeGenerator.image(for: payload, symbology: .qr, scale: 10)
        let detected = BarcodeScanner.scan(image)
        XCTAssertTrue(
            detected.contains { $0.payload == payload && $0.symbology == .qr },
            "expected to decode the QR payload back, got \(detected)"
        )
    }

    func testGenerateThenDetectRoundTripsCode128() throws {
        let payload = "ORIFOLD-128"
        let image = try BarcodeGenerator.image(for: payload, symbology: .code128, scale: 10)
        let detected = BarcodeScanner.scan(image)
        XCTAssertTrue(
            detected.contains { $0.payload == payload && $0.symbology == .code128 },
            "expected to decode the Code 128 payload back, got \(detected)"
        )
    }

    func testBlankImageDetectsNoBarcodes() throws {
        let blank = try makeWhiteImage(width: 400, height: 400)
        XCTAssertTrue(BarcodeScanner.scan(blank).isEmpty)
    }

    private func makeWhiteImage(width: Int, height: Int) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try XCTUnwrap(context.makeImage())
    }
}
