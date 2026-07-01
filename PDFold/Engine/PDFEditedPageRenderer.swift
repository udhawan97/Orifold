import AppKit
import CoreText
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
            // Erase the union of where the text used to be and where it ends up — a
            // replacement that measures taller/wider than the original can extend beyond
            // sourceBounds, and anything outside the erased patch shows through underneath
            // the new glyphs instead of being covered by it.
            drawErasePatch(for: operation.sourceBounds.union(operation.editedBounds), in: context)
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
        // Expand by 2.5pt on each side to ensure ascenders/descenders outside the
        // measured text bounds are fully covered before drawing replacement text.
        let patch = sourceBounds.insetBy(dx: -2.5, dy: -2.5)
        context.saveGState()
        context.setFillColor(NSColor.white.cgColor)
        context.fill(patch)
        context.restoreGState()
    }

    private static func drawReplacement(_ operation: PDFTextEditOperation, in context: CGContext) {
        context.saveGState()

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = operation.alignment.nsTextAlignment
        paragraph.lineBreakMode = .byWordWrapping
        let font = NSFont(name: operation.fontName, size: operation.fontSize)
            ?? NSFont.systemFont(ofSize: operation.fontSize)
        let framesetter = CTFramesetterCreateWithAttributedString(NSAttributedString(
            string: operation.replacementText,
            attributes: [
                .font: font,
                .foregroundColor: operation.textColor.nsColor.cgColor,
                .paragraphStyle: paragraph
            ]
        ))
        let path = CGMutablePath()
        path.addRect(operation.editedBounds)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
        context.textMatrix = .identity
        CTFrameDraw(frame, context)

        context.restoreGState()
    }

    static func measuredBounds(for operation: PDFTextEditOperation) -> CGRect {
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

        // Word-wrap can't break a single unbreakable run (e.g. one long word), so a
        // replacement wider than the current box would otherwise get silently clipped by
        // the CTFrame below instead of wrapping. Grow the width to fit one line of the
        // text first (capped so it can't run off an average page), then measure height
        // against that final width. This is a safety net — the live editor already keeps
        // its box wide enough as the user types, so this mainly matters for edits that
        // arrive with a stale/undersized box.
        let unwrapped = text.boundingRect(
            with: CGSize(width: .greatestFiniteMagnitude, height: font.pointSize * 2),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes
        )
        let maxWidth: CGFloat = 620
        let width = min(max(operation.editedBounds.width, min(ceil(unwrapped.width) + 6, maxWidth)), maxWidth)

        let measured = text.boundingRect(
            with: CGSize(width: width, height: CGFloat.infinity),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes
        )
        let height = max(operation.editedBounds.height, ceil(measured.height) + 4)

        // Anchor to the box's TOP edge, matching the live inline editor — which grows
        // downward from a fixed top as text wraps (InlineTextEditorOverlay.resizeTextViewHeight).
        // PDF page space is y-up, so leaving origin.y untouched while growing height would
        // instead push the box (and the text drawn inside it) upward past where the user
        // saw it while typing, into whatever content sits above.
        let topY = operation.editedBounds.maxY
        var bounds = operation.editedBounds
        bounds.size.width = width
        bounds.size.height = height
        bounds.origin.y = topY - height
        return bounds
    }
}
