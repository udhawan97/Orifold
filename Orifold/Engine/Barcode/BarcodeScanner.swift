import CoreGraphics
import Foundation
import PDFKit
import Vision

/// A barcode Vision found on a page or image: its decoded text and, when it is one of the
/// four symbologies Orifold itself generates, the matching `BarcodeSymbology` (nil for any
/// other symbology Vision can also read, e.g. EAN-13 — the payload is still reported).
struct DetectedBarcode: Equatable {
    var payload: String
    var symbology: BarcodeSymbology?
}

/// Detects barcodes/QR codes with Vision. Fully on-device and offline — `VNDetectBarcodesRequest`
/// needs no network and no model download — so a generate→detect round-trip is deterministic in
/// tests and CI.
enum BarcodeScanner {
    /// Detects every barcode Vision can read in `image`, in no guaranteed order. Empty on failure.
    static func scan(_ image: CGImage) -> [DetectedBarcode] {
        let request = VNDetectBarcodesRequest()
        do {
            try VNImageRequestHandler(cgImage: image, orientation: .up, options: [:]).perform([request])
        } catch {
            return []
        }
        return (request.results ?? []).compactMap { observation in
            guard let payload = observation.payloadStringValue,
                  !payload.isEmpty else { return nil }
            return DetectedBarcode(payload: payload, symbology: BarcodeSymbology(observation.symbology))
        }
    }

    /// Rasterizes `page` (via the shared OCR renderer) and detects barcodes in it.
    static func scan(page: PDFPage) -> [DetectedBarcode] {
        guard let image = PDFOCRService.rasterizedImage(for: page) else { return [] }
        return scan(image)
    }
}

private extension BarcodeSymbology {
    /// Maps a Vision symbology onto the four Orifold models, or nil for anything else.
    init?(_ vnSymbology: VNBarcodeSymbology) {
        switch vnSymbology {
        case .qr: self = .qr
        case .aztec: self = .aztec
        case .code128: self = .code128
        case .pdf417: self = .pdf417
        default: return nil
        }
    }
}
