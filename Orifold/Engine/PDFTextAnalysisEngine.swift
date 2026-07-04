import AppKit
import Foundation
import PDFKit

@_silgen_name("FPDF_LoadPage")
private func FPDF_LoadPage(_ document: OpaquePointer?, _ pageIndex: Int32) -> OpaquePointer?

@_silgen_name("FPDF_ClosePage")
private func FPDF_ClosePage(_ page: OpaquePointer?)

@_silgen_name("FPDFText_LoadPage")
private func FPDFText_LoadPage(_ page: OpaquePointer?) -> OpaquePointer?

@_silgen_name("FPDFText_ClosePage")
private func FPDFText_ClosePage(_ textPage: OpaquePointer?)

@_silgen_name("FPDFText_CountChars")
private func FPDFText_CountChars(_ textPage: OpaquePointer?) -> Int32

@_silgen_name("FPDFText_GetUnicode")
private func FPDFText_GetUnicode(_ textPage: OpaquePointer?, _ index: Int32) -> UInt32

@_silgen_name("FPDFText_GetCharBox")
private func FPDFText_GetCharBox(
    _ textPage: OpaquePointer?,
    _ index: Int32,
    _ left: UnsafeMutablePointer<Double>?,
    _ right: UnsafeMutablePointer<Double>?,
    _ bottom: UnsafeMutablePointer<Double>?,
    _ top: UnsafeMutablePointer<Double>?
) -> Int32

@_silgen_name("FPDFText_GetFontSize")
private func FPDFText_GetFontSize(_ textPage: OpaquePointer?, _ index: Int32) -> Double

@_silgen_name("FPDFText_GetFillColor")
private func FPDFText_GetFillColor(
    _ textPage: OpaquePointer?,
    _ index: Int32,
    _ r: UnsafeMutablePointer<UInt32>?,
    _ g: UnsafeMutablePointer<UInt32>?,
    _ b: UnsafeMutablePointer<UInt32>?,
    _ a: UnsafeMutablePointer<UInt32>?
) -> Int32

@_silgen_name("FPDFText_GetFontInfo")
private func FPDFText_GetFontInfo(
    _ textPage: OpaquePointer?,
    _ index: Int32,
    _ buffer: UnsafeMutableRawPointer?,
    _ buflen: UInt,
    _ flags: UnsafeMutablePointer<Int32>?
) -> UInt

struct PDFTextPageAnalysis {
    var pageRefID: UUID?
    var blocks: [EditableTextBlock]
}

final class PDFTextAnalysisEngine {
    private struct CharacterSample {
        var scalar: UnicodeScalar
        var bounds: CGRect?
        /// nil when FPDFText_GetFontSize reported an implausible value for this glyph
        /// (common for CoreText-drawn replacement text, and for some glyphs even in the
        /// original PDF's own embedded font). Resolved per-line in blocksFromSamples,
        /// preferring other glyphs' valid readings from the same line over guessing from
        /// this one glyph's own bounding box, since sizes are uniform within a run/line.
        var reportedFontSize: CGFloat?
        var color: CodableColor
        var rawFontName: String?
    }

    func analyze(data: Data, pageIndex: Int, pageRefID: UUID? = nil, fallbackPage: PDFPage? = nil) -> PDFTextPageAnalysis {
        if let pdfium = analyzeWithPDFium(data: data, pageIndex: pageIndex, pageRefID: pageRefID, sourcePage: fallbackPage),
           !pdfium.blocks.isEmpty {
            return pdfium
        }
        return analyzeWithPDFKit(page: fallbackPage, pageRefID: pageRefID)
    }

    func hitTest(_ point: CGPoint, in analysis: PDFTextPageAnalysis, tolerance: CGFloat = 5) -> EditableTextBlock? {
        analysis.blocks
            .filter { $0.confidence != .low }
            .first { $0.bounds.insetBy(dx: -tolerance, dy: -tolerance).contains(point) }
    }

    private func analyzeWithPDFium(data: Data, pageIndex: Int, pageRefID: UUID?, sourcePage: PDFPage?) -> PDFTextPageAnalysis? {
        guard !data.isEmpty, data.count <= Int(Int32.max) else { return nil }
        pdfiumLock.lock()
        defer { pdfiumLock.unlock() }
        FPDF_InitLibrary()
        defer { FPDF_DestroyLibrary() }

        return data.withUnsafeBytes { rawBuffer -> PDFTextPageAnalysis? in
            guard let baseAddress = rawBuffer.baseAddress else { return nil }
            guard let document = FPDF_LoadMemDocument(baseAddress, Int32(data.count), nil) else { return nil }
            defer { FPDF_CloseDocument(document) }

            guard let page = FPDF_LoadPage(document, Int32(pageIndex)) else { return nil }
            defer { FPDF_ClosePage(page) }
            guard let textPage = FPDFText_LoadPage(page) else { return nil }
            defer { FPDFText_ClosePage(textPage) }

            let count = Int(FPDFText_CountChars(textPage))
            guard count > 0 else { return PDFTextPageAnalysis(pageRefID: pageRefID, blocks: []) }

            var samples: [CharacterSample] = []
            samples.reserveCapacity(count)
            for index in 0..<count {
                let unicode = FPDFText_GetUnicode(textPage, Int32(index))
                guard let scalar = UnicodeScalar(unicode), scalar.value != 0 else { continue }
                var left = 0.0
                var right = 0.0
                var bottom = 0.0
                var top = 0.0
                let hasBox = FPDFText_GetCharBox(textPage, Int32(index), &left, &right, &bottom, &top) != 0
                let bounds = hasBox && right > left && top > bottom
                    ? CGRect(x: left, y: bottom, width: right - left, height: top - bottom)
                    : nil
                let size = FPDFText_GetFontSize(textPage, Int32(index))
                let color = fillColor(textPage: textPage, index: index)
                let reportedFontSize: CGFloat? = size.isFinite && size >= 4 ? CGFloat(size) : nil
                samples.append(CharacterSample(
                    scalar: scalar,
                    bounds: bounds,
                    reportedFontSize: reportedFontSize,
                    color: color,
                    rawFontName: fontName(textPage: textPage, index: index)
                ))
            }

            let blocks = blocksFromSamples(samples, pageRefID: pageRefID, confidence: .high, sourcePage: sourcePage)
            return PDFTextPageAnalysis(pageRefID: pageRefID, blocks: blocks)
        }
    }

    private func fontName(textPage: OpaquePointer?, index: Int) -> String? {
        var buffer = [UInt8](repeating: 0, count: 256)
        var flags: Int32 = 0
        let needed = buffer.withUnsafeMutableBytes { rawBuffer -> UInt in
            FPDFText_GetFontInfo(textPage, Int32(index), rawBuffer.baseAddress, UInt(rawBuffer.count), &flags)
        }
        guard needed > 1, needed <= buffer.count else { return nil }
        let byteCount = Int(needed) - 1 // FPDFText_GetFontInfo includes a trailing NUL
        return String(bytes: buffer[0..<byteCount], encoding: .utf8)
    }

    /// Maps a font name recovered from the PDF's embedded font descriptor to a PostScript
    /// name Orifold can actually draw with (`NSFont(name:)`), so replacement text matches
    /// the surrounding document's typography instead of always falling back to Helvetica.
    private static func resolveFontPostScriptName(from pdfFontName: String) -> String {
        var name = pdfFontName
        // Subsetted fonts are prefixed with a 6-letter tag + "+", e.g. "ABCDEF+Georgia-Bold".
        if let plusIndex = name.firstIndex(of: "+"),
           name.distance(from: name.startIndex, to: plusIndex) == 6,
           name[..<plusIndex].allSatisfy({ $0.isUppercase || $0.isNumber }) {
            name = String(name[name.index(after: plusIndex)...])
        }
        let lower = name.lowercased()
        if lower.hasPrefix(".") ||
            lower.contains("sfns") ||
            lower.contains("apple") && lower.contains("system") {
            return stableSansSerifPostScriptName()
        }
        if NSFont(name: name, size: 12) != nil {
            return name
        }

        let isBold = lower.contains("bold") || lower.contains("black") || lower.contains("heavy") || lower.contains("semibold")
        let isItalic = lower.contains("italic") || lower.contains("oblique")
        let family: String
        if lower.contains("georgia") {
            family = "Georgia"
        } else if lower.contains("carlito") || lower.contains("calibri") {
            family = "Arial"
        } else if lower.contains("times") || lower.contains("garamond") || lower.contains("cambria") || lower.contains("minion") || lower.contains("serif") {
            family = "Times New Roman"
        } else if lower.contains("courier") || lower.contains("consolas") || lower.contains("mono") {
            family = "Courier New"
        } else if lower.contains("menlo") {
            family = "Menlo"
        } else if lower.contains("avenir") {
            family = "Avenir"
        } else {
            family = "Helvetica"
        }

        var traits: NSFontTraitMask = []
        if isBold { traits.insert(.boldFontMask) }
        if isItalic { traits.insert(.italicFontMask) }
        if let matched = NSFontManager.shared.font(withFamily: family, traits: traits, weight: isBold ? 9 : 5, size: 12) {
            return matched.fontName
        }
        return family == "Helvetica" ? "Helvetica" : (NSFont(name: family, size: 12)?.fontName ?? "Helvetica")
    }

    private static func stableSansSerifPostScriptName() -> String {
        if NSFont(name: "HelveticaNeue", size: 12) != nil {
            return "HelveticaNeue"
        }
        return "Helvetica"
    }

    /// PDFium occasionally mis-decodes a ligature glyph (e.g. the "ti"/"tf" letter pair
    /// rendered as one glyph) into an unrelated character — "Generative" reads back as
    /// "Genera+ve" — when a PDF's ToUnicode table doesn't cover ligature glyphs, even
    /// though the glyphs themselves draw correctly on screen. PDFKit's own text-selection
    /// API tends to resolve this correctly, so prefer it when it plausibly describes the
    /// same span (similar length) rather than trusting PDFium's transcription blindly.
    static func reconcileLigatures(_ pdfiumText: String, bounds: CGRect, sourcePage: PDFPage?) -> String {
        guard let sourcePage,
              let rawPDFKitText = sourcePage.selection(for: bounds)?.string else {
            return pdfiumText
        }
        let pdfKitText = rawPDFKitText
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pdfKitText.isEmpty else { return pdfiumText }
        let ratio = Double(pdfKitText.count) / Double(max(pdfiumText.count, 1))
        guard ratio >= 0.6, ratio <= 1.6 else { return pdfiumText }
        return pdfKitText
    }

    private func fillColor(textPage: OpaquePointer?, index: Int) -> CodableColor {
        var r: UInt32 = 0
        var g: UInt32 = 0
        var b: UInt32 = 0
        var a: UInt32 = 255
        guard FPDFText_GetFillColor(textPage, Int32(index), &r, &g, &b, &a) != 0 else {
            return .documentText
        }
        return CodableColor(
            red: CGFloat(r) / 255,
            green: CGFloat(g) / 255,
            blue: CGFloat(b) / 255,
            alpha: CGFloat(a) / 255
        )
    }

    private func blocksFromSamples(_ samples: [CharacterSample], pageRefID: UUID?, confidence: PDFTextEditConfidence, sourcePage: PDFPage?) -> [EditableTextBlock] {
        var lines: [[CharacterSample]] = []
        for sample in samples {
            if CharacterSet.newlines.contains(sample.scalar) {
                continue
            }
            guard let bounds = sample.bounds else {
                if sample.scalar.value == 32, var last = lines.popLast() {
                    last.append(sample)
                    lines.append(last)
                }
                continue
            }
            let midY = bounds.midY
            if let lineIndex = lines.firstIndex(where: { existing in
                guard let existingBounds = unionBounds(existing.compactMap(\.bounds)) else { return false }
                return abs(existingBounds.midY - midY) <= max(existingBounds.height, bounds.height) * 0.6
            }) {
                lines[lineIndex].append(sample)
            } else {
                lines.append([sample])
            }
        }

        let lineBlocks = lines.flatMap { rawLine -> [EditableTextBlock] in
            let sorted = rawLine.sorted {
                ($0.bounds?.minX ?? .greatestFiniteMagnitude) < ($1.bounds?.minX ?? .greatestFiniteMagnitude)
            }
            // Glyphs are grouped into a "line" by vertical position only, so visually
            // separate columns that share a baseline (e.g. a row of metric numbers, or a
            // heading and its right-aligned date) collapse into one line. Split on large
            // horizontal gaps so each column becomes its own editable block — otherwise
            // editing one cell reflows the whole row left-aligned and destroys the spacing.
            return splitIntoColumns(sorted).compactMap { segment in
                buildBlock(from: segment, pageRefID: pageRefID, confidence: confidence, sourcePage: sourcePage)
            }
        }
        let pageBounds = sourcePage?.bounds(for: .cropBox)
            ?? unionBounds(lineBlocks.map(\.bounds))?.insetBy(dx: -24, dy: -24)
            ?? .zero
        return mergeWrappedLines(assignColumnBounds(to: lineBlocks, pageBounds: pageBounds))
            .sorted { $0.bounds.minY > $1.bounds.minY }
    }

    /// Splits a single vertically-grouped line into separate column segments wherever the
    /// horizontal gap between consecutive glyphs is far wider than a normal inter-word
    /// space. Normal prose (word gaps ≈ 0.2–0.4× the text height) stays intact; real
    /// column gutters (several × the text height) break into their own segments.
    private func splitIntoColumns(_ sortedLine: [CharacterSample]) -> [[CharacterSample]] {
        let heights = sortedLine.compactMap { $0.bounds?.height }.sorted()
        guard heights.count > 1 else { return [sortedLine] }
        let medianHeight = heights[heights.count / 2]
        let gapThreshold = max(medianHeight * 1.5, 6)
        var segments: [[CharacterSample]] = []
        var current: [CharacterSample] = []
        var prevMaxX: CGFloat?
        for sample in sortedLine {
            if let bounds = sample.bounds {
                if let prev = prevMaxX, bounds.minX - prev > gapThreshold, !current.isEmpty {
                    segments.append(current)
                    current = []
                }
                current.append(sample)
                prevMaxX = max(prevMaxX ?? bounds.maxX, bounds.maxX)
            } else {
                // Whitespace/no-bounds glyph: keep it with the current segment.
                current.append(sample)
            }
        }
        if !current.isEmpty { segments.append(current) }
        return segments
    }

    private func buildBlock(from segment: [CharacterSample], pageRefID: UUID?, confidence: PDFTextEditConfidence, sourcePage: PDFPage?) -> EditableTextBlock? {
        let sorted = segment.sorted {
            ($0.bounds?.minX ?? .greatestFiniteMagnitude) < ($1.bounds?.minX ?? .greatestFiniteMagnitude)
        }
        let rawText = String(String.UnicodeScalarView(sorted.map(\.scalar)))
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawText.isEmpty,
              let bounds = unionBounds(sorted.compactMap(\.bounds)),
              bounds.width > 2,
              bounds.height > 2 else { return nil }
        let text = Self.reconcileLigatures(rawText, bounds: bounds, sourcePage: sourcePage)

        let fontSize = resolveLineFontSize(sorted, lineBounds: bounds)
        let color = sorted.first(where: { $0.scalar.value != 32 })?.color ?? .documentText
        let rawFontName = sorted.first(where: { $0.scalar.value != 32 })?.rawFontName
        let fontName = rawFontName.map(Self.resolveFontPostScriptName) ?? "Helvetica"
        let run = PDFTextRun(
            text: text,
            bounds: bounds,
            fontName: fontName,
            fontSize: fontSize,
            textColor: color,
            rotation: 0,
            baseline: bounds.minY,
            confidence: confidence
        )
        let line = PDFTextLine(text: text, bounds: bounds, runs: [run], confidence: confidence)
        return EditableTextBlock(
            pageRefID: pageRefID,
            text: text,
            bounds: bounds.insetBy(dx: -2, dy: -2),
            lines: [line],
            columnBounds: nil,
            fontName: fontName,
            fontSize: fontSize,
            textColor: color,
            rotation: 0,
            baseline: bounds.minY,
            confidence: confidence
        )
    }

    private func analyzeWithPDFKit(page: PDFPage?, pageRefID: UUID?) -> PDFTextPageAnalysis {
        guard let page,
              let pageText = page.string,
              !pageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return PDFTextPageAnalysis(pageRefID: pageRefID, blocks: [])
        }
        let bounds = page.bounds(for: .cropBox)
        let block = EditableTextBlock(
            pageRefID: pageRefID,
            text: pageText,
            bounds: bounds.insetBy(dx: 48, dy: 48),
            lines: [],
            columnBounds: bounds.insetBy(dx: 48, dy: 48),
            fontName: "Helvetica",
            fontSize: 12,
            textColor: .documentText,
            rotation: CGFloat(page.rotation),
            baseline: bounds.maxY - 48,
            confidence: .low
        )
        return PDFTextPageAnalysis(pageRefID: pageRefID, blocks: [block])
    }

    private func unionBounds(_ rects: [CGRect]) -> CGRect? {
        guard var result = rects.first else { return nil }
        rects.dropFirst().forEach { result = result.union($0) }
        return result
    }

    private func assignColumnBounds(to blocks: [EditableTextBlock], pageBounds: CGRect) -> [EditableTextBlock] {
        guard !blocks.isEmpty, pageBounds.width > 0 else { return blocks }
        return blocks.map { block in
            var updated = block
            // Only a block on the SAME visual row may clamp this block's column right edge.
            // Judging "same column" by a loose vertical distance (previously up to 3× the
            // font size) let an indented block one line below shrink the column, which
            // forced measuredBounds to wrap even unchanged text onto a second line.
            let rightNeighborMinX = blocks
                .filter { candidate in
                    candidate.id != block.id &&
                    candidate.bounds.minX > block.bounds.maxX &&
                    rowsOverlap(block.bounds, candidate.bounds)
                }
                .map(\.bounds.minX)
                .min()

            let rightEdge: CGFloat
            if let rightNeighborMinX {
                rightEdge = min(pageBounds.maxX - 8, rightNeighborMinX - max(6, block.fontSize))
            } else {
                rightEdge = pageBounds.maxX - 12
            }
            let leftEdge = max(pageBounds.minX + 8, block.bounds.minX)
            let width = max(block.bounds.width, rightEdge - leftEdge)
            updated.columnBounds = CGRect(
                x: leftEdge,
                y: pageBounds.minY,
                width: width,
                height: pageBounds.height
            )
            return updated
        }
    }

    private func mergeWrappedLines(_ blocks: [EditableTextBlock]) -> [EditableTextBlock] {
        let sorted = blocks.sorted {
            if abs($0.bounds.midY - $1.bounds.midY) > max($0.fontSize, $1.fontSize) {
                return $0.bounds.midY > $1.bounds.midY
            }
            return $0.bounds.minX < $1.bounds.minX
        }
        var merged: [EditableTextBlock] = []
        for block in sorted {
            guard let mergeIndex = merged.indices.reversed().first(where: { shouldMergeWrappedLine(previous: merged[$0], next: block) }) else {
                merged.append(block)
                continue
            }
            var last = merged[mergeIndex]
            last.text = [last.text, block.text]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            last.lines.append(contentsOf: block.lines)
            last.bounds = last.bounds.union(block.bounds)
            if let existingColumn = last.columnBounds, let nextColumn = block.columnBounds {
                let minX = min(existingColumn.minX, nextColumn.minX)
                let maxX = min(existingColumn.maxX, nextColumn.maxX)
                last.columnBounds = CGRect(
                    x: minX,
                    y: min(existingColumn.minY, nextColumn.minY),
                    width: max(last.bounds.width, maxX - minX),
                    height: max(existingColumn.maxY, nextColumn.maxY) - min(existingColumn.minY, nextColumn.minY)
                )
            } else {
                last.columnBounds = last.columnBounds ?? block.columnBounds
            }
            last.confidence = last.confidence == .high && block.confidence == .high ? .high : .medium
            merged[mergeIndex] = last
        }
        return merged
    }

    private func shouldMergeWrappedLine(previous: EditableTextBlock, next: EditableTextBlock) -> Bool {
        guard previous.confidence != .low, next.confidence != .low else { return false }
        guard fontsMatch(previous, next), colorsMatch(previous.textColor, next.textColor) else { return false }
        let verticalGap = previous.bounds.minY - next.bounds.maxY
        let lineHeight = max(previous.bounds.height, next.bounds.height, previous.fontSize, next.fontSize)
        let sameBaseline = abs(previous.bounds.midY - next.bounds.midY) <= lineHeight * 0.45
        let horizontalGap = next.bounds.minX - previous.bounds.maxX
        if sameBaseline,
           horizontalGap >= 0,
           horizontalGap <= max(30, lineHeight * 3),
           previous.text.trimmingCharacters(in: .whitespacesAndNewlines).isLikelyStandaloneListMarker {
            return true
        }
        // Rows separated by more than typical single-spaced leading (chip rows, padded
        // labels, loose layouts) are standalone elements, not a wrapped continuation.
        guard verticalGap >= -lineHeight * 0.35, verticalGap <= lineHeight * 0.9 else { return false }
        guard columnBoundsCompatible(previous.columnBounds, next.columnBounds, tolerance: max(12, lineHeight)) else { return false }
        guard lineLooksWrapped(previous: previous, next: next, lineHeight: lineHeight) else { return false }

        let indentDelta = next.bounds.minX - previous.bounds.minX
        let sameLeft = abs(indentDelta) <= max(8, lineHeight * 0.8)
        let hangingContinuation = indentDelta > 0 && indentDelta <= max(48, lineHeight * 4)
        let trimmedNext = next.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let veryShortContinuation = trimmedNext.count <= 3
        let trimmedPrevious = previous.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let previousLooksOpen = trimmedPrevious.range(of: #"[.!?;:]$"#, options: .regularExpression) == nil
        guard veryShortContinuation || !trimmedNext.isLikelyListItemStart else { return false }

        return (sameLeft || hangingContinuation || veryShortContinuation) &&
            (previousLooksOpen || veryShortContinuation)
    }

    /// True when the upper line plausibly word-wrapped into the lower one. A wrapped
    /// line is never conspicuously shorter than its continuation — if the upper line had
    /// that much free room, the continuation's leading words would have moved up into it.
    /// A short label sitting above a longer unrelated line (stacked chips, sidebar rows)
    /// fails this, so the two stay separately editable instead of fusing into one block.
    private func lineLooksWrapped(previous: EditableTextBlock, next: EditableTextBlock, lineHeight: CGFloat) -> Bool {
        let shortfall = next.bounds.maxX - previous.bounds.maxX
        return shortfall <= max(24, lineHeight * 2)
    }

    private func fontsMatch(_ lhs: EditableTextBlock, _ rhs: EditableTextBlock) -> Bool {
        lhs.fontName == rhs.fontName && abs(lhs.fontSize - rhs.fontSize) <= max(0.75, lhs.fontSize * 0.08)
    }

    private func colorsMatch(_ lhs: CodableColor, _ rhs: CodableColor) -> Bool {
        abs(lhs.red - rhs.red) <= 0.02 &&
            abs(lhs.green - rhs.green) <= 0.02 &&
            abs(lhs.blue - rhs.blue) <= 0.02 &&
            abs(lhs.alpha - rhs.alpha) <= 0.02
    }

    private func columnBoundsCompatible(_ lhs: CGRect?, _ rhs: CGRect?, tolerance: CGFloat) -> Bool {
        guard let lhs, let rhs else { return true }
        return abs(lhs.maxX - rhs.maxX) <= tolerance * 2.5
    }

    private func verticalDistance(between lhs: CGRect, and rhs: CGRect) -> CGFloat {
        if lhs.intersects(rhs) { return 0 }
        if lhs.maxY < rhs.minY { return rhs.minY - lhs.maxY }
        return lhs.minY - rhs.maxY
    }

    /// True when the two rects share enough vertical extent to sit on the same text row.
    private func rowsOverlap(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        let overlap = min(lhs.maxY, rhs.maxY) - max(lhs.minY, rhs.minY)
        return overlap >= min(lhs.height, rhs.height) * 0.4
    }

    private func median(_ values: [CGFloat]) -> CGFloat {
        let sorted = values.filter { $0.isFinite && $0 > 0 }.sorted()
        guard !sorted.isEmpty else { return 12 }
        return sorted[sorted.count / 2]
    }

    /// FPDFText_GetFontSize is unreliable for some glyphs and for pages that apply a text
    /// scale through the content stream CTM: PDFium can report the nominal `Tf` size while
    /// the glyph boxes are visibly smaller in page space. Prefer reported sizes only when
    /// they agree with the actual ink height; otherwise use an ink-derived effective size.
    private func resolveLineFontSize(_ samples: [CharacterSample], lineBounds: CGRect) -> CGFloat {
        let validSizes = samples.compactMap(\.reportedFontSize).filter { $0.isFinite && $0 > 0 }
        let inkEstimatedSize = effectiveFontSize(fromInkHeight: lineBounds.height)
        if !validSizes.isEmpty {
            let reported = median(validSizes)
            guard inkEstimatedSize > 0 else { return reported }
            let upperPlausible = inkEstimatedSize * 1.08
            let lowerPlausible = inkEstimatedSize * 0.85
            if reported > upperPlausible || reported < lowerPlausible {
                return inkEstimatedSize
            }
            return reported
        }
        return inkEstimatedSize > 0 ? inkEstimatedSize : 12
    }

    private func effectiveFontSize(fromInkHeight inkHeight: CGFloat) -> CGFloat {
        guard inkHeight.isFinite, inkHeight > 0 else { return 0 }
        // For common PDF fonts, the union of visible glyph boxes in a line is usually a bit
        // shorter than the nominal point size. 1.15 keeps replacement glyphs visually close
        // to the source ink without accepting unscaled nominal sizes from CTM-scaled pages.
        return max(4, inkHeight * 1.15)
    }
}

private extension String {
    var isLikelyListItemStart: Bool {
        range(of: #"^\s*([•\-–—*]|\(?[0-9A-Za-z]+\)|[0-9A-Za-z]+[.)])\s+"#, options: .regularExpression) != nil
    }

    var isLikelyStandaloneListMarker: Bool {
        range(of: #"^\s*([•\-–—*]|\(?[0-9A-Za-z]+\)|[0-9A-Za-z]+[.)])\s*$"#, options: .regularExpression) != nil
    }
}
