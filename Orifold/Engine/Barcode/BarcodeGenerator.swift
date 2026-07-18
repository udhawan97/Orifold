import CoreGraphics
import CoreImage
import Foundation

/// The 2-D and 1-D symbologies Orifold can generate, each backed by a Core Image barcode
/// filter. All four ship with the OS — no third-party dependency, fully offline.
enum BarcodeSymbology: String, CaseIterable, Codable, Identifiable {
    case qr
    case aztec
    case code128
    case pdf417

    var id: String { rawValue }

    /// The `CIFilter` name that draws this symbology.
    var ciFilterName: String {
        switch self {
        case .qr: return "CIQRCodeGenerator"
        case .aztec: return "CIAztecCodeGenerator"
        case .code128: return "CICode128BarcodeGenerator"
        case .pdf417: return "CIPDF417BarcodeGenerator"
        }
    }

    /// A conservative per-symbology payload ceiling, in UTF-8 bytes. The 2-D codes use their
    /// documented byte-mode capacities at a middle error-correction level; Code 128 is a 1-D
    /// code that grows unreadably wide long before its theoretical limit, so it is capped at
    /// the practical length `CICode128BarcodeGenerator` handles cleanly. Exceeding the ceiling
    /// throws rather than emitting a barcode no scanner could resolve.
    var maxPayloadBytes: Int {
        switch self {
        case .qr: return 2_953
        case .aztec: return 1_914
        case .pdf417: return 1_108
        case .code128: return 80
        }
    }
}

/// Why a barcode couldn't be produced. Deliberately *not* a `LocalizedError`: the only case a
/// user ever sees is `.payloadTooLong`, which the composer surfaces through the
/// `barcode.error.tooLong` catalog entry (with the limit interpolated) rather than through a
/// raw `errorDescription`. The other two are programmer/edge conditions.
enum BarcodeError: Error, Equatable {
    case emptyPayload
    case payloadTooLong(max: Int)
    case generationFailed
}

/// Renders a payload string into a crisp barcode image using Core Image. The native filter
/// output is one pixel per module, so it is integer-upscaled with nearest-neighbour
/// interpolation — every module stays a hard-edged square block a scanner can resolve, where
/// smoothing would blur the module boundaries the decode relies on.
enum BarcodeGenerator {
    /// - Parameters:
    ///   - payload: The text to encode. Whitespace-only payloads count as empty.
    ///   - symbology: Which barcode family to draw.
    ///   - scale: Integer magnification of the 1-module-per-pixel native output. Clamped to ≥1.
    static func image(for payload: String, symbology: BarcodeSymbology, scale: Int = 12) throws -> CGImage {
        guard !payload.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw BarcodeError.emptyPayload
        }
        let data = Data(payload.utf8)
        guard data.count <= symbology.maxPayloadBytes else {
            throw BarcodeError.payloadTooLong(max: symbology.maxPayloadBytes)
        }
        guard let filter = CIFilter(name: symbology.ciFilterName) else {
            throw BarcodeError.generationFailed
        }
        filter.setValue(data, forKey: "inputMessage")
        // Medium error-correction: recoverable if the printed seal is lightly marked, without
        // inflating a QR into a needlessly dense grid.
        if symbology == .qr {
            filter.setValue("M", forKey: "inputCorrectionLevel")
        }
        guard let output = filter.outputImage else {
            throw BarcodeError.generationFailed
        }

        // Software renderer keeps generation deterministic and headless-safe (no GPU/display
        // dependency), which matters for CI as much as for a background export.
        let context = CIContext(options: [.useSoftwareRenderer: true])
        guard let native = context.createCGImage(output, from: output.extent) else {
            throw BarcodeError.generationFailed
        }

        let factor = max(1, scale)
        guard factor > 1 else { return native }
        return try upscaled(native, by: factor)
    }

    /// Nearest-neighbour integer upscale via a `CGContext` with interpolation disabled.
    private static func upscaled(_ image: CGImage, by factor: Int) throws -> CGImage {
        let width = image.width * factor
        let height = image.height * factor
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            throw BarcodeError.generationFailed
        }
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let result = context.makeImage() else {
            throw BarcodeError.generationFailed
        }
        return result
    }
}
