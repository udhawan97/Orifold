import AppKit
import Foundation
import PDFKit

enum PDFDecorationExportBaker {
    enum BakeError: LocalizedError {
        case invalidPDF
        case pageOrderMismatch
        case invalidDecoration
        case invalidStampDecoration
        case documentTooLargeForDecorationExport

        var errorDescription: String? {
            switch self {
            case .invalidPDF:
                return "pdFold could not apply decorations to this PDF. Reopen the document and try exporting again."
            case .pageOrderMismatch:
                return "pdFold could not match decorations to the current page order. Reopen the document and try exporting again."
            case .invalidDecoration:
                return "pdFold could not apply a decoration to this PDF. Add text or turn the decoration off."
            case .invalidStampDecoration:
                return "pdFold could not apply a stamp to this PDF. Remove the stamp and place it again."
            case .documentTooLargeForDecorationExport:
                return "pdFold could not decorate this PDF because it is too large to process safely. Export without decorations, or split the PDF into smaller files."
            }
        }
    }

    private static let maxDecorationInputBytes = 256 * 1024 * 1024
    private static let maxDecorationPageCount = 500

    static func bake(decorations: [PageDecoration],
                     pageOrder: [PageRef],
                     into pdfData: Data) throws -> Data {
        let active = decorations.filter(\.isEnabled)
        guard !active.isEmpty else { return pdfData }
        guard pdfData.count <= maxDecorationInputBytes else {
            throw BakeError.documentTooLargeForDecorationExport
        }
        guard let document = PDFDocument(data: pdfData), document.pageCount > 0 else {
            throw BakeError.invalidPDF
        }
        guard document.pageCount <= maxDecorationPageCount else {
            throw BakeError.documentTooLargeForDecorationExport
        }
        guard pageOrder.count == document.pageCount else {
            throw BakeError.pageOrderMismatch
        }
        try validate(active, pageOrder: pageOrder)

        let output = NSMutableData()
        guard let consumer = CGDataConsumer(data: output as CFMutableData),
              var defaultMediaBox = document.page(at: 0)?.bounds(for: .mediaBox),
              let context = CGContext(consumer: consumer, mediaBox: &defaultMediaBox, nil) else {
            throw BakeError.invalidPDF
        }

        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else {
                throw BakeError.invalidPDF
            }
            let mediaBox = page.bounds(for: .mediaBox)
            context.beginPDFPage(pageInfo(mediaBox: mediaBox))
            context.saveGState()
            page.draw(with: .mediaBox, to: context)
            context.restoreGState()

            drawDecorations(active, pageIndex: pageIndex, pageOrder: pageOrder, pageBounds: mediaBox, in: context)
            context.endPDFPage()
        }
        context.closePDF()

        guard output.length > 0,
              let bakedDocument = PDFDocument(data: output as Data),
              bakedDocument.pageCount == document.pageCount else {
            throw BakeError.invalidPDF
        }
        try copyAnnotations(from: document, to: bakedDocument)
        guard let bakedData = PDFSerializer.data(from: bakedDocument) else {
            throw BakeError.invalidPDF
        }
        return bakedData
    }

    private static func validate(_ active: [PageDecoration], pageOrder: [PageRef]) throws {
        let pageRefIDs = Set(pageOrder.map(\.id))
        for decoration in active {
            switch decoration.kind {
            case .watermark:
                guard !decoration.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw BakeError.invalidDecoration
                }
            case .stamp:
                guard let pageRefID = decoration.pageRefID,
                      pageRefIDs.contains(pageRefID),
                      let rect = decoration.rect?.standardized,
                      rect.width > 4,
                      rect.height > 4,
                      !decoration.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw BakeError.invalidStampDecoration
                }
            case .pageNumber, .bates:
                break
            }
        }
    }

    private static func copyAnnotations(from source: PDFDocument, to destination: PDFDocument) throws {
        guard source.pageCount == destination.pageCount else {
            throw BakeError.invalidPDF
        }
        for pageIndex in 0..<source.pageCount {
            guard let sourcePage = source.page(at: pageIndex),
                  let destinationPage = destination.page(at: pageIndex) else {
                throw BakeError.invalidPDF
            }
            for annotation in sourcePage.annotations {
                guard let copied = annotation.copy() as? PDFAnnotation else {
                    throw BakeError.invalidPDF
                }
                destinationPage.addAnnotation(copied)
            }
        }
    }

    static func text(for decoration: PageDecoration, pageIndex: Int, pageCount: Int) -> String {
        switch decoration.kind {
        case .watermark, .stamp:
            return decoration.text
        case .pageNumber:
            return "Page \(pageIndex + 1) of \(pageCount)"
        case .bates:
            return "\(decoration.prefix)-\(String(format: "%06d", decoration.startNumber + pageIndex))"
        }
    }

    private static func drawDecorations(_ decorations: [PageDecoration],
                                        pageIndex: Int,
                                        pageOrder: [PageRef],
                                        pageBounds: CGRect,
                                        in context: CGContext) {
        guard pageOrder.indices.contains(pageIndex) else { return }
        let pageRefID = pageOrder[pageIndex].id
        let pageCount = pageOrder.count
        for decoration in decorations {
            switch decoration.kind {
            case .watermark:
                drawWatermark(decoration, pageIndex: pageIndex, pageCount: pageCount, pageBounds: pageBounds, in: context)
            case .pageNumber:
                drawFooterText(decoration, text: text(for: decoration, pageIndex: pageIndex, pageCount: pageCount), pageBounds: pageBounds, in: context)
            case .bates:
                drawBates(decoration, text: text(for: decoration, pageIndex: pageIndex, pageCount: pageCount), pageBounds: pageBounds, in: context)
            case .stamp:
                guard decoration.pageRefID == pageRefID else { continue }
                drawStamp(decoration, pageIndex: pageIndex, pageCount: pageCount, in: context)
            }
        }
    }

    private static func drawWatermark(_ decoration: PageDecoration,
                                      pageIndex: Int,
                                      pageCount: Int,
                                      pageBounds: CGRect,
                                      in context: CGContext) {
        let value = text(for: decoration, pageIndex: pageIndex, pageCount: pageCount)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        let font = NSFont.boldSystemFont(ofSize: decoration.fontSize)
        let attributes = attributes(for: decoration, font: font)
        let size = NSString(string: value).size(withAttributes: attributes)
        context.saveGState()
        context.translateBy(x: pageBounds.midX, y: pageBounds.midY)
        context.rotate(by: -.pi / 5)
        drawString(value, in: CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height), attributes: attributes, context: context)
        context.restoreGState()
    }

    private static func drawFooterText(_ decoration: PageDecoration,
                                       text: String,
                                       pageBounds: CGRect,
                                       in context: CGContext) {
        let attributes = attributes(for: decoration, font: NSFont.systemFont(ofSize: decoration.fontSize))
        let size = NSString(string: text).size(withAttributes: attributes)
        let rect = CGRect(
            x: pageBounds.midX - size.width / 2,
            y: pageBounds.minY + 24,
            width: size.width + 2,
            height: size.height + 2
        )
        context.saveGState()
        drawString(text, in: rect, attributes: attributes, context: context)
        context.restoreGState()
    }

    private static func drawBates(_ decoration: PageDecoration,
                                  text: String,
                                  pageBounds: CGRect,
                                  in context: CGContext) {
        let attributes = attributes(for: decoration, font: NSFont.monospacedDigitSystemFont(ofSize: decoration.fontSize, weight: .regular))
        let size = NSString(string: text).size(withAttributes: attributes)
        let rect = CGRect(x: pageBounds.minX + 36, y: pageBounds.minY + 24, width: size.width + 2, height: size.height + 2)
        context.saveGState()
        drawString(text, in: rect, attributes: attributes, context: context)
        context.restoreGState()
    }

    private static func drawStamp(_ decoration: PageDecoration,
                                  pageIndex: Int,
                                  pageCount: Int,
                                  in context: CGContext) {
        guard let rect = decoration.rect?.standardized,
              rect.width > 4,
              rect.height > 4 else { return }
        let value = text(for: decoration, pageIndex: pageIndex, pageCount: pageCount)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        let color = decoration.swatch.pdfColor.withAlphaComponent(CGFloat(decoration.opacity))
        context.saveGState()
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(2)
        context.stroke(rect)

        let font = NSFont.boldSystemFont(ofSize: min(decoration.fontSize, max(10, rect.height * 0.34)))
        let attributes = attributes(for: decoration, font: font)
        let size = NSString(string: value).size(withAttributes: attributes)
        let textRect = CGRect(
            x: rect.midX - size.width / 2,
            y: rect.midY - size.height / 2,
            width: size.width + 2,
            height: size.height + 2
        )
        drawString(value, in: textRect, attributes: attributes, context: context)
        context.restoreGState()
    }

    private static func attributes(for decoration: PageDecoration, font: NSFont) -> [NSAttributedString.Key: Any] {
        [
            .font: font,
            .foregroundColor: decoration.swatch.pdfColor.withAlphaComponent(CGFloat(decoration.opacity))
        ]
    }

    private static func drawString(_ value: String,
                                   in rect: CGRect,
                                   attributes: [NSAttributedString.Key: Any],
                                   context: CGContext) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        NSString(string: value).draw(in: rect, withAttributes: attributes)
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func pageInfo(mediaBox: CGRect) -> CFDictionary {
        var box = mediaBox
        let boxData = Data(bytes: &box, count: MemoryLayout<CGRect>.size) as CFData
        return [kCGPDFContextMediaBox as String: boxData] as CFDictionary
    }
}

private extension PageDecorationSwatch {
    var pdfColor: NSColor {
        switch self {
        case .accent: return .dsAccentNS
        case .sage: return .dsAnnotationSageNS
        case .coral: return .dsAnnotationCoralNS
        case .tertiary: return .dsTextTertiaryNS
        case .lavender: return .dsAnnotationLavNS
        }
    }
}
