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

struct PDFTextPageAnalysis {
    var pageRefID: UUID?
    var blocks: [EditableTextBlock]
}

final class PDFTextAnalysisEngine {
    private struct CharacterSample {
        var scalar: UnicodeScalar
        var bounds: CGRect?
        var fontSize: CGFloat
        var color: CodableColor
    }

    func analyze(data: Data, pageIndex: Int, pageRefID: UUID? = nil, fallbackPage: PDFPage? = nil) -> PDFTextPageAnalysis {
        if let pdfium = analyzeWithPDFium(data: data, pageIndex: pageIndex, pageRefID: pageRefID),
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

    private func analyzeWithPDFium(data: Data, pageIndex: Int, pageRefID: UUID?) -> PDFTextPageAnalysis? {
        guard !data.isEmpty, data.count <= Int(Int32.max) else { return nil }
        pdfiumLock.lock()
        defer { pdfiumLock.unlock() }
        FPDF_InitLibrary()
        defer { FPDF_DestroyLibrary() }

        let document = data.withUnsafeBytes { rawBuffer -> OpaquePointer? in
            guard let baseAddress = rawBuffer.baseAddress else { return nil }
            return FPDF_LoadMemDocument(baseAddress, Int32(data.count), nil)
        }
        guard let document else { return nil }
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
            let resolvedSize = size.isFinite && size >= 4 ? CGFloat(size) : 12
            samples.append(CharacterSample(
                scalar: scalar,
                bounds: bounds,
                fontSize: resolvedSize,
                color: color
            ))
        }

        let blocks = blocksFromSamples(samples, pageRefID: pageRefID, confidence: .high)
        return PDFTextPageAnalysis(pageRefID: pageRefID, blocks: blocks)
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

    private func blocksFromSamples(_ samples: [CharacterSample], pageRefID: UUID?, confidence: PDFTextEditConfidence) -> [EditableTextBlock] {
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

        return lines.compactMap { rawLine in
            let sorted = rawLine.sorted {
                ($0.bounds?.minX ?? .greatestFiniteMagnitude) < ($1.bounds?.minX ?? .greatestFiniteMagnitude)
            }
            let text = String(String.UnicodeScalarView(sorted.map(\.scalar)))
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty,
                  let bounds = unionBounds(sorted.compactMap(\.bounds)),
                  bounds.width > 2,
                  bounds.height > 2 else { return nil }

            let fontSize = median(sorted.map(\.fontSize))
            let color = sorted.first(where: { $0.scalar.value != 32 })?.color ?? .documentText
            let run = PDFTextRun(
                text: text,
                bounds: bounds,
                fontName: "Helvetica",
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
                fontName: "Helvetica",
                fontSize: fontSize,
                textColor: color,
                rotation: 0,
                baseline: bounds.minY,
                confidence: confidence
            )
        }
        .sorted { $0.bounds.minY > $1.bounds.minY }
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

    private func median(_ values: [CGFloat]) -> CGFloat {
        let sorted = values.filter { $0.isFinite && $0 > 0 }.sorted()
        guard !sorted.isEmpty else { return 12 }
        return sorted[sorted.count / 2]
    }
}
