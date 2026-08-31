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

enum ScanCleanupPipeline {
    /// Uses the same 300-DPI, long-edge-capped rendering path as local OCR, then applies the
    /// selected cleanup operations to that bitmap.
    static func cleanedImage(for page: PDFPage, options: ScanCleanupOptions) -> CGImage? {
        guard let source = PDFOCRService.rasterizedImage(for: page) else { return nil }
        return ScanCleanup.clean(source, options: options)
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
            // The destination keeps its `/Rotate` entry. Render the underlying page content
            // without that presentation rotation so replacing the content cannot apply the
            // rotation twice when PDFKit/PDFium displays it again.
            let preservedRotation = page.rotation
            page.rotation = 0
            let cleaned = cleanedImage(for: page, options: options)
            page.rotation = preservedRotation
            guard let cleaned,
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
}
