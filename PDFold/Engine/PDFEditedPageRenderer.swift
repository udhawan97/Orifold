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
            drawErasePatch(for: operation.sourceBounds, on: page, in: context)
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

    private static func drawErasePatch(for sourceBounds: CGRect, on page: PDFPage, in context: CGContext) {
        let patch = sourceBounds.standardized.insetBy(dx: -1, dy: -1)
        guard patch.width > 0, patch.height > 0 else { return }

        context.saveGState()
        context.setFillColor(sampledBackgroundColor(near: sourceBounds, on: page) ?? NSColor.white.cgColor)
        context.fill(patch)
        context.restoreGState()
    }

    private static func drawReplacement(_ operation: PDFTextEditOperation, in context: CGContext) {
        context.saveGState()
        let layout = ReplacementTextLayout(operation: operation)
        context.textMatrix = .identity
        layout.draw(in: context, bounds: operation.editedBounds)
        context.restoreGState()
    }

    static func measuredBounds(for operation: PDFTextEditOperation) -> CGRect {
        let layout = ReplacementTextLayout(operation: operation)

        // Word-wrap can't break a single unbreakable run (e.g. one long word), so a
        // replacement wider than the current box would otherwise get silently clipped by
        // the CTFrame below instead of wrapping. Grow the width to fit one line of the
        // text first (capped so it can't run off an average page), then measure height
        // against that final width. This is a safety net — the live editor already keeps
        // its box wide enough as the user types, so this mainly matters for edits that
        // arrive with a stale/undersized box.
        let unwrapped = layout.suggestedSize(constrainedTo: CGSize(width: 10_000, height: 10_000))
        let maxWidth: CGFloat = 620
        let width = min(max(operation.editedBounds.width, min(ceil(unwrapped.width) + 6, maxWidth)), maxWidth)

        let measured = layout.suggestedSize(constrainedTo: CGSize(width: width, height: 10_000))
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

    private static func sampledBackgroundColor(near sourceBounds: CGRect, on page: PDFPage) -> CGColor? {
        let pageBounds = page.bounds(for: .mediaBox)
        let sampleRect = sourceBounds.standardized.insetBy(dx: -2, dy: -2).intersection(pageBounds)
        guard sampleRect.width > 0, sampleRect.height > 0, !sampleRect.isNull else {
            return nil
        }

        let maxPixels = 160
        let pixelWidth = min(maxPixels, max(1, Int(ceil(sampleRect.width * 2))))
        let pixelHeight = min(maxPixels, max(1, Int(ceil(sampleRect.height * 2))))
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelWidth,
            pixelsHigh: pixelHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ),
        let bitmapContext = NSGraphicsContext(bitmapImageRep: bitmap)?.cgContext else {
            return nil
        }

        let scaleX = CGFloat(pixelWidth) / sampleRect.width
        let scaleY = CGFloat(pixelHeight) / sampleRect.height
        bitmapContext.saveGState()
        bitmapContext.setFillColor(NSColor.white.cgColor)
        bitmapContext.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        bitmapContext.scaleBy(x: scaleX, y: scaleY)
        bitmapContext.translateBy(x: -sampleRect.minX, y: -sampleRect.minY)
        page.draw(with: .mediaBox, to: bitmapContext)
        bitmapContext.restoreGState()

        var buckets: [Int: ColorBucket] = [:]
        let sampleStep = max(1, Int(sqrt(Double(pixelWidth * pixelHeight) / 4096.0).rounded(.up)))
        for y in stride(from: 0, to: pixelHeight, by: sampleStep) {
            for x in stride(from: 0, to: pixelWidth, by: sampleStep) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                var red: CGFloat = 0
                var green: CGFloat = 0
                var blue: CGFloat = 0
                var alpha: CGFloat = 0
                color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
                guard alpha > 0.5 else { continue }

                let key = ColorBucket.key(red: red, green: green, blue: blue)
                buckets[key, default: ColorBucket()].add(red: red, green: green, blue: blue, alpha: alpha)
            }
        }

        return buckets.values.max { lhs, rhs in lhs.count < rhs.count }?.color.cgColor
    }
}

private struct ReplacementTextLayout {
    private let attributedString: NSAttributedString
    private let framesetter: CTFramesetter

    init(operation: PDFTextEditOperation) {
        let font = NSFont(name: operation.fontName, size: operation.fontSize)
            ?? NSFont.systemFont(ofSize: operation.fontSize)
        let ctFont = CTFontCreateWithFontDescriptor(font.fontDescriptor as CTFontDescriptor, font.pointSize, nil)
        let paragraph = Self.paragraphStyle(
            alignment: operation.alignment.ctTextAlignment,
            lineBreakMode: .byWordWrapping
        )
        attributedString = NSAttributedString(
            string: operation.replacementText,
            attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): ctFont,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): operation.textColor.nsColor.cgColor,
                NSAttributedString.Key(kCTParagraphStyleAttributeName as String): paragraph
            ]
        )
        framesetter = CTFramesetterCreateWithAttributedString(attributedString)
    }

    private static func paragraphStyle(alignment: CTTextAlignment, lineBreakMode: CTLineBreakMode) -> CTParagraphStyle {
        var alignment = alignment
        var lineBreakMode = lineBreakMode
        return withUnsafeBytes(of: &alignment) { alignmentBytes in
            withUnsafeBytes(of: &lineBreakMode) { lineBreakBytes in
                let settings = [
                    CTParagraphStyleSetting(
                        spec: .alignment,
                        valueSize: MemoryLayout<CTTextAlignment>.size,
                        value: alignmentBytes.baseAddress!
                    ),
                    CTParagraphStyleSetting(
                        spec: .lineBreakMode,
                        valueSize: MemoryLayout<CTLineBreakMode>.size,
                        value: lineBreakBytes.baseAddress!
                    )
                ]
                return CTParagraphStyleCreate(settings, settings.count)
            }
        }
    }

    func suggestedSize(constrainedTo size: CGSize) -> CGSize {
        guard attributedString.length > 0 else { return .zero }

        return CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            CFRange(location: 0, length: attributedString.length),
            nil,
            size,
            nil
        )
    }

    func draw(in context: CGContext, bounds: CGRect) {
        guard attributedString.length > 0, bounds.width > 0, bounds.height > 0 else { return }

        let path = CGMutablePath()
        path.addRect(bounds)
        let frame = CTFramesetterCreateFrame(
            framesetter,
            CFRange(location: 0, length: attributedString.length),
            path,
            nil
        )
        CTFrameDraw(frame, context)
    }
}

private struct ColorBucket {
    private(set) var count: Int = 0
    private var red: CGFloat = 0
    private var green: CGFloat = 0
    private var blue: CGFloat = 0
    private var alpha: CGFloat = 0

    static func key(red: CGFloat, green: CGFloat, blue: CGFloat) -> Int {
        let r = Int((red * 255).rounded()) / 16
        let g = Int((green * 255).rounded()) / 16
        let b = Int((blue * 255).rounded()) / 16
        return (r << 8) | (g << 4) | b
    }

    mutating func add(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        count += 1
        self.red += red
        self.green += green
        self.blue += blue
        self.alpha += alpha
    }

    var color: NSColor {
        guard count > 0 else { return .white }

        return NSColor(
            srgbRed: red / CGFloat(count),
            green: green / CGFloat(count),
            blue: blue / CGFloat(count),
            alpha: alpha / CGFloat(count)
        )
    }
}

private extension CodableTextAlignment {
    var ctTextAlignment: CTTextAlignment {
        switch self {
        case .left: return .left
        case .center: return .center
        case .right: return .right
        }
    }
}
