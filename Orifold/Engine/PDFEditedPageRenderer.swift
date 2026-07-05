import AppKit
import CoreText
import Foundation
import PDFKit

enum PDFEditedPageRenderer {
    static func regeneratedPage(from page: PDFPage, applying operations: [PDFTextEditOperation]) -> PDFPage? {
        guard !operations.isEmpty else { return page.copy() as? PDFPage }
        let mediaBox = page.bounds(for: .mediaBox)
        guard mediaBox.width > 0, mediaBox.height > 0 else { return nil }

        // `PDFPage.draw(with:to:)` bakes the page's own `/Rotate` value into what it
        // renders (confirmed empirically): drawing a rotated page into a context sized to
        // the RAW (unrotated) mediaBox clips or distorts 90°/270° content entirely, since
        // the visually-rotated content's footprint doesn't match the raw box dimensions.
        // Meanwhile every edit's geometry (`sourceBounds`/`editedBounds`) comes from
        // PDFium/text-analysis, which reports RAW/unrotated content-stream coordinates —
        // drawing the background WITH rotation applied while erase-patches/replacement
        // text use RAW coordinates would place them in two different coordinate spaces.
        // Sidestep this: draw the background from a rotation-neutralized COPY of the page
        // (so it renders in the same raw space the edit geometry already uses), then tag
        // the final output page with the ORIGINAL rotation so viewers rotate the whole
        // thing — background and edits together — for display, exactly as the original
        // page did.
        guard let unrotatedPage = page.copy() as? PDFPage else { return nil }
        unrotatedPage.rotation = 0

        let data = NSMutableData()
        var outputBox = CGRect(origin: .zero, size: mediaBox.size)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &outputBox, nil) else {
            return nil
        }

        context.beginPDFPage([:] as CFDictionary)
        context.saveGState()
        context.translateBy(x: -mediaBox.minX, y: -mediaBox.minY)
        drawRasterizedPageBackground(from: page, mediaBox: mediaBox, in: context)
        drawPageBackground(from: page, unrotatedPage: unrotatedPage, mediaBox: mediaBox, in: context)

        for operation in operations {
            let eraseBounds = eraseBounds(for: operation)
            for sourceBounds in eraseBounds {
                drawErasePatch(for: sourceBounds, on: page, in: context)
            }
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
        for box in [PDFDisplayBox.mediaBox, .cropBox, .bleedBox, .trimBox, .artBox] {
            newPage.setBounds(page.bounds(for: box), for: box)
        }
        newPage.rotation = page.rotation
        return newPage
    }

    private static func drawRasterizedPageBackground(from page: PDFPage, mediaBox: CGRect, in context: CGContext) {
        guard let image = renderedRawPageImage(from: page, mediaBox: mediaBox) else { return }

        context.saveGState()
        context.draw(image, in: mediaBox)
        context.restoreGState()
    }

    private static func renderedRawPageImage(from page: PDFPage, mediaBox: CGRect) -> CGImage? {
        guard mediaBox.width > 0, mediaBox.height > 0 else { return nil }

        let scale: CGFloat = 2
        let pixelWidth = max(1, Int(ceil(mediaBox.width * scale)))
        let pixelHeight = max(1, Int(ceil(mediaBox.height * scale)))
        guard let bitmap = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        bitmap.setFillColor(NSColor.white.cgColor)
        bitmap.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        bitmap.scaleBy(x: scale, y: scale)
        bitmap.translateBy(x: -mediaBox.minX, y: -mediaBox.minY)
        drawPageRef(page, mediaBox: mediaBox, in: bitmap)
        return bitmap.makeImage()
    }

    private static func drawPageBackground(from page: PDFPage, unrotatedPage: PDFPage, mediaBox: CGRect, in context: CGContext) {
        if page.pageRef != nil {
            context.saveGState()
            drawPageRef(page, mediaBox: mediaBox, in: context)
            context.restoreGState()
        } else {
            unrotatedPage.draw(with: .mediaBox, to: context)
        }
    }

    private static func drawPageRef(_ page: PDFPage, mediaBox: CGRect, in context: CGContext) {
        guard let pageRef = page.pageRef else { return }

        let rotation = ((page.rotation % 360) + 360) % 360
        if rotation != 0 {
            context.concatenate(
                pageRef.getDrawingTransform(
                    .mediaBox,
                    rect: mediaBox,
                    rotate: Int32(-rotation),
                    preserveAspectRatio: true
                )
            )
        }
        context.drawPDFPage(pageRef)
    }

    static func eraseBounds(for operation: PDFTextEditOperation) -> [CGRect] {
        // Inserting brand-new text has nothing to erase; patching would stamp an opaque
        // rectangle over whatever background art sits under the insertion point.
        guard !operation.isInsertion else { return [] }
        let sourceBounds = (operation.sourceLineBounds.isEmpty ? [operation.sourceBounds] : operation.sourceLineBounds)
            .map { $0.standardized }
        // Automatic width/height growth is only layout help for the replacement text.
        // It should not stamp a background-colored rectangle over nearby content. Only
        // explicit geometry changes — a manual drag/resize, or Match/Copy/Restore Style
        // adopting a different paragraph's margins/column (`didApplyMatchedGeometry`) —
        // erase the destination box too, so the replacement never bleeds into whatever
        // original content sat at that new location.
        guard operation.didManuallyReposition ||
            operation.didManuallyResizeWidth ||
            operation.didManuallyResizeHeight ||
            operation.didApplyMatchedGeometry else {
            return sourceBounds
        }
        return sourceBounds + [operation.editedBounds]
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

    static func measuredBounds(for operation: PDFTextEditOperation, pageBounds: CGRect? = nil, sourcePage: PDFPage? = nil) -> CGRect {
        let layout = ReplacementTextLayout(operation: operation)

        // Word-wrap can't break every unbreakable run, so an undersized stale box may
        // clip. Auto-growth is allowed only inside the detected column. A manual width
        // choice is already the user's wrap policy, so keep it exactly.
        let unwrapped = layout.suggestedSize(constrainedTo: CGSize(width: 10_000, height: 10_000))
        let pageLimit: CGFloat? = {
            guard let page = pageBounds?.standardized, page.width > 0 else { return nil }
            return max(24, page.maxX - 8 - operation.editedBounds.minX)
        }()
        var maxWidth = maximumTextWidth(for: operation)
        if let pageLimit { maxWidth = min(maxWidth, pageLimit) }
        let trimmedReplacement = operation.replacementText.trimmingCharacters(in: .whitespacesAndNewlines)
        let textUnchanged = !trimmedReplacement.isEmpty &&
            trimmedReplacement == operation.sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        let singleUnbreakableToken = !trimmedReplacement.isEmpty &&
            trimmedReplacement.rangeOfCharacter(from: .whitespaces) == nil
        var width: CGFloat
        if operation.didManuallyResizeWidth {
            width = max(1, operation.editedBounds.width)
        } else {
            let needed = ceil(unwrapped.width) + 8
            var cap = maxWidth
            // Unchanged text always fit the page before — never reflow it onto a second
            // line just because the detected column or a substituted font came out a bit
            // narrow. A single unbreakable token can't wrap meaningfully either; both may
            // grow toward the page's right margin instead of wrapping mid-thought.
            //
            // But `unwrapped`/`needed` is the *single-line* width of the whole replacement,
            // and for an already-wrapped multi-line paragraph that is enormous — applying
            // this growth there would collapse the paragraph onto one page-wide line. So
            // only grow unchanged text when the source itself was a single line.
            let sourceWasSingleLine = operation.sourceLineBounds.count <= 1
            if singleUnbreakableToken || (textUnchanged && sourceWasSingleLine), needed > cap {
                cap = min(needed, pageLimit ?? needed)
            }
            width = min(max(operation.editedBounds.width, min(needed, cap)), cap)
        }

        var measured = layout.suggestedSize(constrainedTo: CGSize(width: width, height: 10_000))
        // A pathologically long paste (tens of thousands of characters) has no other cap on
        // height the way width is capped by the page's right margin — left unchecked, the
        // box (and the erase/replacement geometry baked into the exported PDF) can grow far
        // taller than the page itself, silently drawing the edit off-page instead of failing
        // or visibly wrapping. Cap auto-height to what can actually fit above the box's
        // fixed top edge within the page, the same way width is already capped to what fits
        // before the page's right edge. A manual resize is the user's own explicit choice,
        // so it is never overridden here, matching `didManuallyResizeWidth`'s behavior above.
        let heightPageLimit: CGFloat? = {
            guard let page = pageBounds?.standardized, page.height > 0 else { return nil }
            return max(24, operation.editedBounds.maxY - page.minY - 8)
        }()

        // A paragraph edited near the page's bottom margin has little or no room to grow
        // downward, but the live editor overlay (`InlineTextEditorOverlay.resizeTextViewHeight`)
        // has no such limit and shows the user's full typed text while they're still
        // editing. Capping height alone here — after already settling on the paragraph's
        // established (often narrow) column width — would make `ReplacementTextLayout.draw`
        // silently drop whatever no longer fits inside that shorter box, so the user loses
        // the tail of what they typed with no warning. Before accepting that loss, widen —
        // but only up to `maxWidth`, the SAME column-aware ceiling used above (bounded by a
        // detected right-neighbor column as well as the page edge), never the raw page edge
        // directly: a left-column paragraph must not widen across into a right column's text
        // just to avoid an unrelated height cap. Fewer wrapped lines needs less height, and
        // unused width within the paragraph's own safe column is far less damaging than
        // silently deleting the user's text.
        if !operation.didManuallyResizeHeight, !operation.didManuallyResizeWidth,
           let heightPageLimit, maxWidth > width {
            let neededHeight = ceil(measured.height) + 4
            if neededHeight > heightPageLimit {
                let widened = layout.suggestedSize(constrainedTo: CGSize(width: maxWidth, height: 10_000))
                if ceil(widened.height) + 4 < neededHeight {
                    width = maxWidth
                    measured = widened
                }
            }
        }

        // Column/page-edge growth above only ever looked at OTHER TEXT blocks (via
        // `columnBounds`'s right-neighbor detection) — an adjacent embedded image, figure,
        // or shaded box isn't a text block, so nothing stopped auto-growth from drawing the
        // replacement's extra width directly over it. Auto-growth never erases (only the
        // ORIGINAL source bounds get erased — see `eraseBounds`), so growing into non-blank
        // page content would draw new text on top of it unerased. Before accepting that
        // growth, confirm the strip of page the box is about to expand INTO is actually
        // blank (ordinary paper background); if it isn't, fall back to the original
        // committed width so the text wraps normally instead of overlapping that content.
        if !operation.didManuallyResizeWidth, width > operation.editedBounds.width, let sourcePage {
            let growthStrip = CGRect(
                x: operation.editedBounds.maxX,
                y: operation.editedBounds.minY,
                width: width - operation.editedBounds.maxX,
                height: max(operation.editedBounds.height, ceil(measured.height) + 4)
            )
            if !regionIsBlankBackground(growthStrip, on: sourcePage) {
                width = max(1, operation.editedBounds.width)
                measured = layout.suggestedSize(constrainedTo: CGSize(width: width, height: 10_000))
            }
        }

        let height = operation.didManuallyResizeHeight
            ? max(1, operation.editedBounds.height)
            : min(max(1, ceil(measured.height) + 4), heightPageLimit ?? .greatestFiniteMagnitude)

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

    private static func maximumTextWidth(for operation: PDFTextEditOperation) -> CGFloat {
        guard let columnBounds = operation.columnBounds?.standardized,
              columnBounds.width > 0 else {
            return max(620, operation.sourceBounds.standardized.width, operation.editedBounds.standardized.width)
        }
        return max(24, columnBounds.maxX - operation.editedBounds.minX)
    }

    /// True when `rect` on `page` looks like ordinary paper background — possibly with a
    /// FEW stray/sparse dark pixels from nearby text ink — rather than a densely-painted
    /// embedded image, figure, or shaded block. Used to gate auto-width growth (see
    /// `measuredBounds`) so it never draws replacement text over an image it never erased.
    ///
    /// This deliberately checks the FRACTION of light/paper-colored pixels rather than
    /// requiring one dominant color: text glyphs only ink a small fraction of the pixels
    /// they occupy (a growth strip that happens to graze the tail of an unrelated word, or
    /// a still-to-be-erased sliver of the source text itself, is still mostly white) —
    /// while a real photo/image densely covers nearly every sampled pixel with non-white
    /// color. Requiring "one overwhelming color" instead would also reject ordinary sparse
    /// text ink, which is legitimate to grow over (it gets erased or was never the
    /// target of this check to begin with).
    private static func regionIsBlankBackground(_ rect: CGRect, on page: PDFPage) -> Bool {
        let pageBounds = page.bounds(for: .mediaBox)
        let sampleRect = rect.standardized.intersection(pageBounds)
        guard sampleRect.width > 1, sampleRect.height > 1, !sampleRect.isNull else { return true }

        let maxPixels = 96
        let pixelWidth = min(maxPixels, max(1, Int(ceil(sampleRect.width))))
        let pixelHeight = min(maxPixels, max(1, Int(ceil(sampleRect.height))))
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
            return true
        }

        let scaleX = CGFloat(pixelWidth) / sampleRect.width
        let scaleY = CGFloat(pixelHeight) / sampleRect.height
        bitmapContext.saveGState()
        bitmapContext.setFillColor(NSColor.white.cgColor)
        bitmapContext.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        bitmapContext.scaleBy(x: scaleX, y: scaleY)
        bitmapContext.translateBy(x: -sampleRect.minX, y: -sampleRect.minY)
        drawPageForSampling(page, mediaBox: pageBounds, in: bitmapContext)
        bitmapContext.restoreGState()

        var totalSamples = 0
        var lightSamples = 0
        let sampleStep = max(1, Int(sqrt(Double(pixelWidth * pixelHeight) / 900.0).rounded(.up)))
        for y in stride(from: 0, to: pixelHeight, by: sampleStep) {
            for x in stride(from: 0, to: pixelWidth, by: sampleStep) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                var red: CGFloat = 0
                var green: CGFloat = 0
                var blue: CGFloat = 0
                var alpha: CGFloat = 0
                color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
                guard alpha > 0.5 else { continue }
                totalSamples += 1
                // Paper background (white or a light off-white/tint) has high brightness AND
                // low saturation; sparse black text ink fails brightness, a solid colored
                // image/figure typically fails on saturation even at high brightness.
                let maxComponent = max(red, green, blue)
                let minComponent = min(red, green, blue)
                let saturation = maxComponent > 0 ? (maxComponent - minComponent) / maxComponent : 0
                if maxComponent >= 0.82, saturation <= 0.12 {
                    lightSamples += 1
                }
            }
        }
        guard totalSamples > 0 else { return true }

        // A growth strip that's mostly paper background, with at most a sparse scattering
        // of foreign ink, is safe to grow into. A densely-painted image/figure fails this
        // by a wide margin (most sampled pixels are neither light nor low-saturation).
        return Double(lightSamples) / Double(totalSamples) >= 0.7
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
        drawPageForSampling(page, mediaBox: pageBounds, in: bitmapContext)
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

    private static func drawPageForSampling(_ page: PDFPage, mediaBox: CGRect, in context: CGContext) {
        if let pageRef = page.pageRef {
            let rotation = ((page.rotation % 360) + 360) % 360
            context.saveGState()
            if rotation != 0 {
                context.concatenate(
                    pageRef.getDrawingTransform(
                        .mediaBox,
                        rect: mediaBox,
                        rotate: Int32(-rotation),
                        preserveAspectRatio: true
                    )
                )
            }
            context.drawPDFPage(pageRef)
            context.restoreGState()
        } else {
            page.draw(with: .mediaBox, to: context)
        }
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
        var attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): ctFont,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): operation.textColor.nsColor.cgColor,
            NSAttributedString.Key(kCTParagraphStyleAttributeName as String): paragraph
        ]
        if operation.underline {
            attributes[NSAttributedString.Key(kCTUnderlineStyleAttributeName as String)] = CTUnderlineStyle.single.rawValue
        }
        attributedString = NSAttributedString(string: operation.replacementText, attributes: attributes)
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
