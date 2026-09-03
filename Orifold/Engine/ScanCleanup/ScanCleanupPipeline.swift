import CoreGraphics
import Foundation
import PDFKit

enum ScanCleanupPipelineError: LocalizedError, Equatable {
    case invalidPDF
    case pageRenderFailed(pageIndex: Int)
    case replacementFailed(pageIndex: Int)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .invalidPDF, .pageRenderFailed, .replacementFailed:
            return L10n.string("status.scanCleanup.applyFailed")
        case .cancelled:
            return L10n.string("status.scanCleanup.cancelled")
        }
    }
}

/// Display-sized images derived from the exact production cleanup raster. The full-resolution
/// intermediates stay inside `previewImages` and are released before this value crosses actors.
struct ScanCleanupPreviewImages: @unchecked Sendable {
    let before: CGImage
    let after: CGImage
}

enum ScanCleanupPipeline {
    /// Roughly preserves the detail of the former 110-DPI letter-page preview while avoiding
    /// retaining the production 300-DPI raster in SwiftUI state.
    static let previewDisplayLongEdgePixels = 1_200

    /// Renders the page's underlying content with its `/Rotate` presentation temporarily
    /// cleared, then applies the selected cleanup operations to that bitmap.
    ///
    /// Both Apply and the sheet's proofing preview come through here. The destination page keeps
    /// its `/Rotate` entry, so rendering without that presentation rotation is what stops the
    /// rotation being applied twice on redisplay — and it is why a rotated scan must never be
    /// cleaned in its presented orientation: Vision's crop, Otsu's threshold, and despeckling
    /// would all run against a differently shaped bitmap than the one that gets written.
    static func contentImages(
        for page: PDFPage,
        options: ScanCleanupOptions,
        isCancelled: @Sendable () -> Bool = { false }
    ) -> (before: CGImage, after: CGImage)? {
        let preservedRotation = page.rotation
        page.rotation = 0
        defer { page.rotation = preservedRotation }
        guard !isCancelled(), let source = PDFOCRService.rasterizedImage(for: page) else { return nil }
        guard !isCancelled() else { return nil }
        return (source, ScanCleanup.clean(source, options: options))
    }

    /// Uses the same 300-DPI, long-edge-capped rendering path as local OCR, then applies the
    /// selected cleanup operations to that bitmap.
    static func cleanedImage(for page: PDFPage, options: ScanCleanupOptions) -> CGImage? {
        contentImages(for: page, options: options)?.after
    }

    /// Builds the proofing images from the same 300-DPI, 4,500-pixel-capped source used by
    /// `cleanedImage`. Cleanup happens before either image is downsampled, so resolution-sensitive
    /// crop detection, Otsu thresholding, and despeckling cannot disagree with Apply.
    static func previewImages(
        for page: PDFPage,
        options: ScanCleanupOptions,
        displayLongEdgePixels: Int = previewDisplayLongEdgePixels,
        isCancelled: @Sendable () -> Bool = { false }
    ) -> ScanCleanupPreviewImages? {
        guard displayLongEdgePixels > 0,
              let production = contentImages(for: page, options: options, isCancelled: isCancelled) else { return nil }
        guard !isCancelled(),
              let before = downsampled(production.before, longEdgePixels: displayLongEdgePixels) else { return nil }
        guard !isCancelled(),
              let after = downsampled(production.after, longEdgePixels: displayLongEdgePixels) else { return nil }
        guard !isCancelled() else { return nil }
        return ScanCleanupPreviewImages(before: before, after: after)
    }

    /// Raster-cleans the requested pages, then swaps only their `/Contents`, `/Resources`, and
    /// transparency group into the original qpdf object graph. Catalog structures and untouched
    /// page objects remain byte-graph members of the original document.
    static func replacingPageContents(
        in data: Data,
        pageIndices: [Int],
        options: ScanCleanupOptions,
        isCancelled: @Sendable () -> Bool = { false }
    ) throws -> Data {
        guard let source = PDFDocument(data: data), source.pageCount > 0 else {
            throw ScanCleanupPipelineError.invalidPDF
        }
        let indices = Array(Set(pageIndices)).sorted()
        guard !indices.isEmpty, indices.allSatisfy({ source.page(at: $0) != nil }) else {
            throw ScanCleanupPipelineError.invalidPDF
        }

        var replacements: [(index: Int, data: Data)] = []
        replacements.reserveCapacity(indices.count)
        for index in indices {
            guard !isCancelled() else { throw ScanCleanupPipelineError.cancelled }
            guard let page = source.page(at: index) else {
                throw ScanCleanupPipelineError.pageRenderFailed(pageIndex: index)
            }
            // `cleanedImage` renders without the page's `/Rotate` presentation, which the
            // destination keeps — so replacing the content cannot apply the rotation twice
            // when PDFKit/PDFium displays it again.
            guard let cleaned = cleanedImage(for: page, options: options),
                  let replacement = replacementPageData(from: cleaned, mediaBox: page.bounds(for: .mediaBox)) else {
                throw ScanCleanupPipelineError.pageRenderFailed(pageIndex: index)
            }
            replacements.append((index, replacement))
        }

        var output = data
        for replacement in replacements {
            guard !isCancelled() else { throw ScanCleanupPipelineError.cancelled }
            guard let updated = QPDFService.replacingPageContent(
                in: output,
                pageIndex: replacement.index,
                with: replacement.data
            ) else {
                throw ScanCleanupPipelineError.replacementFailed(pageIndex: replacement.index)
            }
            output = updated
        }
        guard let reopened = PDFDocument(data: output), reopened.pageCount == source.pageCount,
              QPDFService.isStructurallySound(output) else {
            throw ScanCleanupPipelineError.invalidPDF
        }
        do {
            _ = try PDFiumProcessingEngine().validatePDF(data: output)
        } catch {
            throw ScanCleanupPipelineError.invalidPDF
        }
        return output
    }

    private static func replacementPageData(from image: CGImage, mediaBox: CGRect) -> Data? {
        guard mediaBox.width.isFinite, mediaBox.height.isFinite,
              mediaBox.width > 0, mediaBox.height > 0 else { return nil }
        let output = NSMutableData()
        var box = mediaBox
        guard let consumer = CGDataConsumer(data: output as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &box, nil) else { return nil }
        context.beginPDFPage([kCGPDFContextMediaBox as String: box] as CFDictionary)
        context.interpolationQuality = .high
        context.draw(image, in: box)
        context.endPDFPage()
        context.closePDF()
        return output as Data
    }

    private static func downsampled(_ image: CGImage, longEdgePixels: Int) -> CGImage? {
        let sourceLongEdge = max(image.width, image.height)
        guard sourceLongEdge > 0, longEdgePixels > 0 else { return nil }
        guard sourceLongEdge > longEdgePixels else { return image }

        let scale = CGFloat(longEdgePixels) / CGFloat(sourceLongEdge)
        let width = max(1, Int((CGFloat(image.width) * scale).rounded()))
        let height = max(1, Int((CGFloat(image.height) * scale).rounded()))
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
