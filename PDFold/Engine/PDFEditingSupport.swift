import AppKit
import PDFKit

enum PDFTextEditWarning: Equatable {
    case emptySelection
    case invalidSelectionBounds
    case invalidAnnotationBounds
    case annotationCreationFailed
    case unsupportedReplacement
    case serializationFailed
    case colorConversionFailed
    case fontConversionFailed

    var message: String {
        switch self {
        case .emptySelection:
            return "pdFold could not find editable text at that location."
        case .invalidSelectionBounds:
            return "That PDF text selection has invalid bounds, so pdFold added a normal text box instead."
        case .invalidAnnotationBounds:
            return "That annotation has invalid geometry and could not be edited safely."
        case .annotationCreationFailed:
            return "pdFold could not create an annotation on that page."
        case .unsupportedReplacement:
            return "pdFold could not safely replace that PDF text. A normal text box was added instead."
        case .serializationFailed:
            return "pdFold could not serialize the edited PDF. Your workspace remains open."
        case .colorConversionFailed:
            return "pdFold could not preserve the original text color, so it used the default document text color."
        case .fontConversionFailed:
            return "pdFold could not preserve the original font, so it used a system font."
        }
    }
}

struct PDFTextEditStyle: Equatable {
    var font: NSFont
    var textColor: NSColor
    var alignment: NSTextAlignment
    var backgroundColor: NSColor

    static let fallback = PDFTextEditStyle(
        font: .systemFont(ofSize: 13),
        textColor: .dsTextPrimaryNS,
        alignment: .left,
        backgroundColor: .clear
    )
}

struct PDFTextReplacementPlan: Equatable {
    var text: String
    var bounds: CGRect
    var style: PDFTextEditStyle
    var shouldUseReplacementBackground: Bool
    var warnings: [PDFTextEditWarning]
}

enum PDFEmptyEditAction: Equatable {
    case allow
    case removeDraft
    case rejectReplacement
}

enum PDFEditingSupport {
    static let minimumFontSize: CGFloat = 8
    static let defaultTextBoxSize = CGSize(width: 180, height: 54)

    static func normalizedEditableText(_ rawText: String?) -> String {
        (rawText ?? "")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func replacementPlan(
        text rawText: String?,
        selectionBounds: CGRect,
        attributedString: NSAttributedString?,
        pageBounds: CGRect? = nil
    ) -> PDFTextReplacementPlan? {
        let text = normalizedEditableText(rawText)
        guard !text.isEmpty else { return nil }
        guard isValidPDFBounds(selectionBounds), selectionBounds.width >= 4, selectionBounds.height >= 4 else {
            return PDFTextReplacementPlan(
                text: text,
                bounds: .zero,
                style: .fallback,
                shouldUseReplacementBackground: false,
                warnings: [.invalidSelectionBounds]
            )
        }

        var warnings: [PDFTextEditWarning] = []
        let extractedStyle = style(from: attributedString, warnings: &warnings)
        let font = extractedStyle.font
        let height = max(selectionBounds.height + 4, font.pointSize * 1.35)
        let proposedBounds = CGRect(
            x: floor(selectionBounds.minX - 2),
            y: floor(selectionBounds.midY - height / 2),
            width: ceil(max(selectionBounds.width + 8, 36)),
            height: ceil(height)
        )
        guard let bounds = boundsContainedInPage(proposedBounds, pageBounds: pageBounds) else {
            return PDFTextReplacementPlan(
                text: text,
                bounds: .zero,
                style: extractedStyle,
                shouldUseReplacementBackground: false,
                warnings: warnings + [.invalidAnnotationBounds]
            )
        }
        guard isValidPDFBounds(bounds) else {
            return PDFTextReplacementPlan(
                text: text,
                bounds: .zero,
                style: extractedStyle,
                shouldUseReplacementBackground: false,
                warnings: warnings + [.invalidAnnotationBounds]
            )
        }

        return PDFTextReplacementPlan(
            text: text,
            bounds: bounds,
            style: extractedStyle,
            shouldUseReplacementBackground: canUseReplacementBackground(for: selectionBounds, text: text, font: font),
            warnings: warnings
        )
    }

    static func textBoxBounds(centeredAt pagePoint: CGPoint, pageBounds: CGRect?) -> CGRect {
        guard pagePoint.x.isFinite, pagePoint.y.isFinite else {
            return CGRect(x: CGFloat.infinity, y: CGFloat.infinity, width: 0, height: 0)
        }
        var bounds = CGRect(
            x: pagePoint.x - defaultTextBoxSize.width / 2,
            y: pagePoint.y - defaultTextBoxSize.height / 2,
            width: defaultTextBoxSize.width,
            height: defaultTextBoxSize.height
        )
        guard let pageBounds, isValidPDFBounds(pageBounds) else { return bounds }
        if bounds.minX < pageBounds.minX { bounds.origin.x = pageBounds.minX + 8 }
        if bounds.maxX > pageBounds.maxX { bounds.origin.x = pageBounds.maxX - bounds.width - 8 }
        if bounds.minY < pageBounds.minY { bounds.origin.y = pageBounds.minY + 8 }
        if bounds.maxY > pageBounds.maxY { bounds.origin.y = pageBounds.maxY - bounds.height - 8 }
        return bounds
    }

    static func resizedFreeTextBounds(
        currentBounds: CGRect,
        text: String,
        font: NSFont,
        preserveWidth: Bool
    ) -> CGRect? {
        guard isValidPDFBounds(currentBounds), font.pointSize.isFinite, font.pointSize > 0 else {
            return nil
        }
        let measured = (text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? " " : text) as NSString
        let measurementWidth = preserveWidth ? max(currentBounds.width - 10, 1) : 520
        let size = measured.boundingRect(
            with: CGSize(width: measurementWidth, height: CGFloat.infinity),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        ).size
        var bounds = currentBounds
        if !preserveWidth {
            bounds.size.width = max(36, min(620, ceil(size.width) + 14))
        }
        bounds.size.height = max(font.pointSize * 1.45, ceil(size.height) + 10)
        return isValidPDFBounds(bounds) ? bounds : nil
    }

    static func editorFieldColors(for textColor: NSColor) -> (background: NSColor, foreground: NSColor) {
        let converted = textColor.usingColorSpace(.sRGB) ?? .labelColor
        let brightness = converted.perceivedBrightness
        if brightness > 0.78 {
            return (NSColor(srgbRed: 0.071, green: 0.082, blue: 0.098, alpha: 1), textColor)
        }
        let foreground: NSColor = (brightness < 0.18 && NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
            ? .labelColor
            : textColor
        return (.textBackgroundColor, foreground)
    }

    static func replacementBackgroundColor(isReplacement: Bool, originalBackground: NSColor?) -> NSColor {
        guard isReplacement else { return originalBackground ?? .clear }
        return originalBackground ?? .pdfPageEraseBackground
    }

    static func isValidPDFBounds(_ bounds: CGRect) -> Bool {
        bounds.origin.x.isFinite &&
        bounds.origin.y.isFinite &&
        bounds.size.width.isFinite &&
        bounds.size.height.isFinite &&
        bounds.width > 0 &&
        bounds.height > 0 &&
        bounds.width < 100_000 &&
        bounds.height < 100_000
    }

    static func emptyEditAction(text: String, isDraft: Bool, isReplacement: Bool) -> PDFEmptyEditAction {
        guard text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .allow
        }
        if isDraft { return .removeDraft }
        if isReplacement { return .rejectReplacement }
        return .allow
    }

    private static func style(from attributedString: NSAttributedString?, warnings: inout [PDFTextEditWarning]) -> PDFTextEditStyle {
        guard let attributedString, attributedString.length > 0 else {
            return .fallback
        }

        let font: NSFont
        if let extractedFont = attributedString.attribute(.font, at: 0, effectiveRange: nil) as? NSFont,
           extractedFont.pointSize.isFinite,
           extractedFont.pointSize >= minimumFontSize {
            font = extractedFont
        } else {
            font = PDFTextEditStyle.fallback.font
            warnings.append(.fontConversionFailed)
        }

        let color: NSColor
        if let extractedColor = attributedString.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor,
           extractedColor.usingColorSpace(.sRGB) != nil || extractedColor.usingColorSpace(.deviceRGB) != nil {
            color = extractedColor
        } else {
            color = PDFTextEditStyle.fallback.textColor
            warnings.append(.colorConversionFailed)
        }

        return PDFTextEditStyle(
            font: font,
            textColor: color,
            alignment: .left,
            backgroundColor: .clear
        )
    }

    private static func canUseReplacementBackground(for bounds: CGRect, text: String, font: NSFont) -> Bool {
        let estimatedWidth = ceil((text as NSString).size(withAttributes: [.font: font]).width)
        return bounds.width >= max(estimatedWidth * 0.45, 4)
    }

    private static func boundsContainedInPage(_ bounds: CGRect, pageBounds: CGRect?) -> CGRect? {
        guard isValidPDFBounds(bounds) else { return nil }
        guard let pageBounds, isValidPDFBounds(pageBounds) else { return bounds }
        guard bounds.width <= pageBounds.width, bounds.height <= pageBounds.height else { return nil }

        var contained = bounds
        if contained.minX < pageBounds.minX {
            contained.origin.x = pageBounds.minX
        }
        if contained.maxX > pageBounds.maxX {
            contained.origin.x = pageBounds.maxX - contained.width
        }
        if contained.minY < pageBounds.minY {
            contained.origin.y = pageBounds.minY
        }
        if contained.maxY > pageBounds.maxY {
            contained.origin.y = pageBounds.maxY - contained.height
        }
        return isValidPDFBounds(contained) && pageBounds.contains(contained) ? contained : nil
    }
}

struct PDFAnnotationEditSnapshot {
    var contents: String?
    var font: NSFont?
    var fontColor: NSColor?
    var color: NSColor?
    var alignment: NSTextAlignment
    var bounds: CGRect

    init(annotation: PDFAnnotation) {
        contents = annotation.contents
        font = annotation.font
        fontColor = annotation.fontColor
        color = annotation.color
        alignment = annotation.alignment
        bounds = annotation.bounds
    }

    func restore(to annotation: PDFAnnotation) {
        annotation.contents = contents
        annotation.font = font
        annotation.fontColor = fontColor
        annotation.color = color ?? .clear
        annotation.alignment = alignment
        annotation.bounds = bounds
    }
}

private extension NSColor {
    static let pdfPageEraseBackground = NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.98)

    var perceivedBrightness: CGFloat {
        let color = usingColorSpace(.sRGB) ?? self
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: nil)
        return (0.2126 * red) + (0.7152 * green) + (0.0722 * blue)
    }
}
