import Foundation
import PDFKit

/// Finds pages that are visually blank, so the review sheet can offer them for removal.
/// Detection is by *ink fraction* — the share of clearly dark pixels in a small
/// thumbnail — not mean brightness, which scanner noise and JPEG artifacts defeat.
/// Never deletes anything itself: it only proposes candidate indices.
enum BlankPageDetector {

    /// Thumbnail long edge. Small enough that a 300-page sweep stays cheap; large
    /// enough that a single text line still lands multiple dark pixels.
    private static let thumbnailLongEdge: CGFloat = 128

    /// A pixel this far below full luminance counts as ink.
    private static let inkLuminanceCutoff: Double = 0.5

    /// Pages with less than this fraction of ink pixels are considered blank.
    /// ponytail: fixed heuristic; expose as a sensitivity slider if reports disagree.
    private static let blankInkFraction: Double = 0.005

    /// Indices (0-based, in `document` order) of pages that look blank.
    static func candidateIndices(in document: PDFDocument) -> [Int] {
        (0..<document.pageCount).compactMap { index in
            guard let page = document.page(at: index) else { return nil }
            return isBlank(page) ? index : nil
        }
    }

    static func isBlank(_ page: PDFPage) -> Bool {
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else { return true }
        let scale = thumbnailLongEdge / max(bounds.width, bounds.height)
        let size = CGSize(width: max(bounds.width * scale, 1), height: max(bounds.height * scale, 1))
        let thumbnail = page.thumbnail(of: size, for: .mediaBox)
        guard let cgImage = thumbnail.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            // Unrenderable page: never propose deleting what we couldn't look at.
            return false
        }
        return inkFraction(of: cgImage) < blankInkFraction
    }

    /// Fraction of pixels darker than the luminance cutoff.
    static func inkFraction(of image: CGImage) -> Double {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0,
              let colorSpace = CGColorSpace(name: CGColorSpace.linearGray),
              let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.none.rawValue
              ) else { return 1 }
        // White background first: transparent source pixels must read as paper, not ink.
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let pixels = context.data else { return 1 }
        let buffer = pixels.bindMemory(to: UInt8.self, capacity: width * height)
        let cutoff = UInt8(inkLuminanceCutoff * 255)
        var dark = 0
        for index in 0..<(width * height) where buffer[index] < cutoff {
            dark += 1
        }
        return Double(dark) / Double(width * height)
    }
}
