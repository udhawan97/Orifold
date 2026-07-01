import AppKit
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import PDFKit

enum SignatureAppearanceError: Error, Equatable {
    case emptyText
    case invalidSize
    case imageEncodingFailed
    case invalidImageData
}

struct SignatureAppearanceDescriptor {
    enum Kind {
        case typedName(String)
        case initials(String)
    }

    var kind: Kind
    var inkColor: CGColor

    init(kind: Kind, inkColor: CGColor = CGColor(gray: 0, alpha: 1)) {
        self.kind = kind
        self.inkColor = inkColor
    }

    static func typedName(_ name: String, inkColor: CGColor = CGColor(gray: 0, alpha: 1)) -> SignatureAppearanceDescriptor {
        SignatureAppearanceDescriptor(kind: .typedName(name), inkColor: inkColor)
    }

    static func initials(_ value: String, inkColor: CGColor = CGColor(gray: 0, alpha: 1)) -> SignatureAppearanceDescriptor {
        SignatureAppearanceDescriptor(kind: .initials(value), inkColor: inkColor)
    }

    static func initials(fromName name: String, inkColor: CGColor = CGColor(gray: 0, alpha: 1)) -> SignatureAppearanceDescriptor {
        let initials = name
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .compactMap(\.first)
            .prefix(3)
            .map { String($0).uppercased() }
            .joined()
        return SignatureAppearanceDescriptor(kind: .initials(initials), inkColor: inkColor)
    }

    var displayText: String {
        switch kind {
        case .typedName(let value), .initials(let value):
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    var isInitials: Bool {
        if case .initials = kind { return true }
        return false
    }
}

enum SignatureAppearanceRenderer {
    static func pngData(for descriptor: SignatureAppearanceDescriptor,
                        size: CGSize,
                        scale: CGFloat = 2) throws -> Data {
        guard size.width > 0, size.height > 0, scale > 0 else {
            throw SignatureAppearanceError.invalidSize
        }

        let pixelWidth = max(1, Int(ceil(size.width * scale)))
        let pixelHeight = max(1, Int(ceil(size.height * scale)))
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            throw SignatureAppearanceError.imageEncodingFailed
        }

        context.clear(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        context.scaleBy(x: scale, y: scale)
        try draw(descriptor, in: CGRect(origin: .zero, size: size), context: context)

        guard let cgImage = context.makeImage() else {
            throw SignatureAppearanceError.imageEncodingFailed
        }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw SignatureAppearanceError.imageEncodingFailed
        }
        return data
    }

    static func pdfAppearanceStream(for descriptor: SignatureAppearanceDescriptor,
                                    bounds: CGRect) throws -> PDFAppearanceStream {
        guard bounds.width > 0, bounds.height > 0 else {
            throw SignatureAppearanceError.invalidSize
        }
        let path = try outlinePath(for: descriptor, in: CGRect(origin: .zero, size: bounds.size))
        let color = descriptor.inkColor.pdfRGBComponents
        let stream = """
        q
        \(color.red.pdfNumber) \(color.green.pdfNumber) \(color.blue.pdfNumber) rg
        \(path.pdfFillCommands)
        Q
        """
        return PDFAppearanceStream(xobject: Data(stream.utf8), bbox: CGRect(origin: .zero, size: bounds.size))
    }

    static func draw(_ descriptor: SignatureAppearanceDescriptor,
                     in rect: CGRect,
                     context: CGContext) throws {
        guard rect.width > 0, rect.height > 0 else {
            throw SignatureAppearanceError.invalidSize
        }
        let path = try outlinePath(for: descriptor, in: rect)
        context.saveGState()
        context.setFillColor(descriptor.inkColor)
        context.addPath(path)
        context.fillPath()
        context.restoreGState()
    }

    private static func outlinePath(for descriptor: SignatureAppearanceDescriptor,
                                    in rect: CGRect) throws -> CGPath {
        let text = descriptor.displayText
        guard !text.isEmpty else { throw SignatureAppearanceError.emptyText }

        let baseFontSize: CGFloat = descriptor.isInitials ? 120 : 96
        let font = makeFont(isInitials: descriptor.isInitials, size: baseFontSize)
        let sourcePath = textOutlinePath(text, font: font)
        let sourceBounds = sourcePath.boundingBoxOfPath
        guard !sourceBounds.isNull, sourceBounds.width > 0, sourceBounds.height > 0 else {
            throw SignatureAppearanceError.emptyText
        }

        let xInset = max(4, rect.width * (descriptor.isInitials ? 0.12 : 0.05))
        let yInset = max(3, rect.height * (descriptor.isInitials ? 0.12 : 0.08))
        let target = rect.insetBy(dx: min(xInset, rect.width / 3), dy: min(yInset, rect.height / 3))
        let scale = min(target.width / sourceBounds.width, target.height / sourceBounds.height)

        var transform = CGAffineTransform.identity
            .translatedBy(
                x: target.midX - sourceBounds.midX * scale,
                y: target.midY - sourceBounds.midY * scale
            )
            .scaledBy(x: scale, y: scale)

        guard let fitted = sourcePath.copy(using: &transform) else {
            throw SignatureAppearanceError.emptyText
        }
        return fitted
    }

    private static func makeFont(isInitials: Bool, size: CGFloat) -> CTFont {
        let candidates = isInitials
            ? ["AvenirNext-DemiBold", "HelveticaNeue-Bold", "Helvetica-Bold"]
            : ["SnellRoundhand", "AppleChancery", "Noteworthy-Light", "HelveticaNeue-Italic"]

        for name in candidates {
            let font = CTFontCreateWithName(name as CFString, size, nil)
            let resolvedName = CTFontCopyPostScriptName(font) as String
            if resolvedName.caseInsensitiveCompare(name) == .orderedSame {
                return font
            }
        }

        return CTFontCreateWithName(
            (isInitials ? "Helvetica-Bold" : "Helvetica-Oblique") as CFString,
            size,
            nil
        )
    }

    private static func textOutlinePath(_ text: String, font: CTFont) -> CGPath {
        let attributed = NSAttributedString(string: text, attributes: [
            kCTFontAttributeName as NSAttributedString.Key: font
        ])
        let line = CTLineCreateWithAttributedString(attributed)
        let runs = CTLineGetGlyphRuns(line) as! [CTRun]
        let outline = CGMutablePath()

        for run in runs {
            let glyphCount = CTRunGetGlyphCount(run)
            guard glyphCount > 0 else { continue }

            let attributes = CTRunGetAttributes(run) as NSDictionary
            let runFont = attributes[kCTFontAttributeName] as! CTFont
            var glyphs = [CGGlyph](repeating: 0, count: glyphCount)
            var positions = [CGPoint](repeating: .zero, count: glyphCount)
            CTRunGetGlyphs(run, CFRange(location: 0, length: glyphCount), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: glyphCount), &positions)

            for index in 0..<glyphCount {
                guard let glyphPath = CTFontCreatePathForGlyph(runFont, glyphs[index], nil) else { continue }
                let transform = CGAffineTransform(translationX: positions[index].x, y: positions[index].y)
                outline.addPath(glyphPath, transform: transform)
            }
        }

        return outline
    }
}

private extension CGColor {
    var pdfRGBComponents: (red: CGFloat, green: CGFloat, blue: CGFloat) {
        let converted = converted(
            to: CGColorSpaceCreateDeviceRGB(),
            intent: .defaultIntent,
            options: nil
        ) ?? self
        let components = converted.components ?? [0, 0, 0, alpha]
        if components.count >= 3 {
            return (components[0], components[1], components[2])
        }
        let gray = components.first ?? 0
        return (gray, gray, gray)
    }
}

private extension CGFloat {
    var pdfNumber: String {
        let value = abs(self) < 0.000_001 ? 0 : self
        return String(format: "%.4f", Double(value))
    }
}

private extension CGPoint {
    var pdfPoint: String {
        "\(x.pdfNumber) \(y.pdfNumber)"
    }
}

private extension CGPath {
    var pdfFillCommands: String {
        var commands: [String] = []
        applyWithBlock { elementPointer in
            let element = elementPointer.pointee
            switch element.type {
            case .moveToPoint:
                commands.append("\(element.points[0].pdfPoint) m")
            case .addLineToPoint:
                commands.append("\(element.points[0].pdfPoint) l")
            case .addQuadCurveToPoint:
                let current = commands.lastPoint ?? .zero
                let control = element.points[0]
                let end = element.points[1]
                let control1 = CGPoint(
                    x: current.x + (2.0 / 3.0) * (control.x - current.x),
                    y: current.y + (2.0 / 3.0) * (control.y - current.y)
                )
                let control2 = CGPoint(
                    x: end.x + (2.0 / 3.0) * (control.x - end.x),
                    y: end.y + (2.0 / 3.0) * (control.y - end.y)
                )
                commands.append("\(control1.pdfPoint) \(control2.pdfPoint) \(end.pdfPoint) c")
            case .addCurveToPoint:
                commands.append("\(element.points[0].pdfPoint) \(element.points[1].pdfPoint) \(element.points[2].pdfPoint) c")
            case .closeSubpath:
                commands.append("h")
            @unknown default:
                break
            }
        }
        commands.append("f")
        return commands.joined(separator: "\n")
    }
}

private extension Array where Element == String {
    var lastPoint: CGPoint? {
        for command in reversed() {
            let parts = command.split(separator: " ")
            guard parts.count >= 3,
                  ["m", "l", "c"].contains(String(parts.last ?? "")) else { continue }
            let xIndex = parts.count - 3
            let yIndex = parts.count - 2
            guard xIndex >= 0,
                  yIndex >= 0,
                  let x = Double(parts[xIndex]),
                  let y = Double(parts[yIndex]) else { continue }
            return CGPoint(x: x, y: y)
        }
        return nil
    }
}

enum SignatureExportBakingSupport {
    static func bake(placements: [SignaturePlacement],
                     into pdf: Data,
                     pageIndexForPlacement: (SignaturePlacement) -> Int?) throws -> Data {
        guard let document = PDFDocument(data: pdf), document.pageCount > 0 else {
            throw SigningError.invalidPDF
        }

        var placementsByPage: [Int: [SignaturePlacement]] = [:]
        for placement in placements {
            guard let pageIndex = pageIndexForPlacement(placement),
                  pageIndex >= 0,
                  pageIndex < document.pageCount else { continue }
            placementsByPage[pageIndex, default: []].append(placement)
        }

        let output = NSMutableData()
        guard let consumer = CGDataConsumer(data: output as CFMutableData),
              var defaultMediaBox = document.page(at: 0)?.bounds(for: .mediaBox),
              let context = CGContext(consumer: consumer, mediaBox: &defaultMediaBox, nil) else {
            throw SigningError.invalidPDF
        }

        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            let mediaBox = page.bounds(for: .mediaBox)
            context.beginPDFPage(pageInfo(mediaBox: mediaBox))
            context.saveGState()
            page.draw(with: .mediaBox, to: context)
            context.restoreGState()

            for placement in placementsByPage[pageIndex] ?? [] {
                try drawPlacement(placement, in: context)
            }

            context.endPDFPage()
        }
        context.closePDF()

        guard output.length > 0 else {
            throw SigningError.invalidPDF
        }
        return output as Data
    }

    private static func drawPlacement(_ placement: SignaturePlacement,
                                      in context: CGContext) throws {
        guard placement.rect.width > 0,
              placement.rect.height > 0,
              let image = cgImage(from: placement.imageData) else {
            throw SignatureAppearanceError.invalidImageData
        }

        context.saveGState()
        context.interpolationQuality = .high
        context.draw(image, in: placement.rect)
        context.restoreGState()
    }

    private static func cgImage(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private static func pageInfo(mediaBox: CGRect) -> CFDictionary {
        var box = mediaBox
        let boxData = Data(bytes: &box, count: MemoryLayout<CGRect>.size) as CFData
        return [kCGPDFContextMediaBox as String: boxData] as CFDictionary
    }
}
