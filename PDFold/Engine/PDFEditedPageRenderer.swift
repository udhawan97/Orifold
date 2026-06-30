import AppKit
import Foundation
import PDFKit

enum PDFEditedPageRenderer {
    static func regeneratedPage(from page: PDFPage, applying operations: [PDFTextEditOperation]) -> PDFPage? {
        guard !operations.isEmpty else { return page.copy() as? PDFPage }
        let mediaBox = page.bounds(for: .mediaBox)
        guard mediaBox.width > 0, mediaBox.height > 0 else { return nil }

        let data = NSMutableData()
        var outputBox = CGRect(origin: .zero, size: mediaBox.size)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &outputBox, nil) else {
            return nil
        }

        context.beginPDFPage([:] as CFDictionary)
        context.saveGState()
        context.translateBy(x: -mediaBox.minX, y: -mediaBox.minY)
        page.draw(with: .mediaBox, to: context)

        for operation in operations {
            drawErasePatch(for: operation.sourceBounds, in: context)
        }
        for operation in operations {
            drawReplacement(operation, in: context)
        }
        context.restoreGState()
        context.endPDFPage()
        context.closePDF()

        guard let doc = PDFDocument(data: data as Data),
              let newPage = doc.page(at: 0) else {
            return nil
        }
        newPage.rotation = page.rotation
        return newPage
    }

    private static func drawErasePatch(for sourceBounds: CGRect, in context: CGContext) {
        let patch = sourceBounds.insetBy(dx: -1.5, dy: -1.5)
        context.saveGState()
        context.setFillColor(NSColor.white.withAlphaComponent(0.985).cgColor)
        context.fill(patch)
        context.restoreGState()
    }

    private static func drawReplacement(_ operation: PDFTextEditOperation, in context: CGContext) {
        context.saveGState()
        let graphics = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = operation.alignment.nsTextAlignment
        paragraph.lineBreakMode = .byWordWrapping
        let font = NSFont(name: operation.fontName, size: operation.fontSize)
            ?? NSFont.systemFont(ofSize: operation.fontSize)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: operation.textColor.nsColor,
            .paragraphStyle: paragraph
        ]
        let text = operation.replacementText as NSString
        text.draw(with: operation.editedBounds, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes)

        NSGraphicsContext.restoreGraphicsState()
        context.restoreGState()
    }
}
