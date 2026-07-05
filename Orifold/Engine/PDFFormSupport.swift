import AppKit
import Foundation
import PDFKit

struct PDFFormField: Identifiable, Equatable {
    var id: String
    var pageRefID: UUID
    var fieldName: String
    var fieldType: String
    var value: String
    var bounds: CGRect
}

struct PDFFormSummary: Equatable {
    var fields: [PDFFormField] = []
    var hasUnsupportedDynamicFeatures: Bool = false

    var fieldCount: Int { fields.count }
    var containsForm: Bool { !fields.isEmpty }
}

struct PDFFormFieldNavigationTarget {
    var pageIndex: Int
    var bounds: CGRect
    var fieldType: String
}

enum PDFFormSupport {
    enum FormError: LocalizedError, Equatable {
        case invalidPDF
        case pageOrderMismatch

        var errorDescription: String? {
            switch self {
            case .invalidPDF:
                return L10n.string("error.form.invalidPDF")
            case .pageOrderMismatch:
                return L10n.string("error.form.pageOrderMismatch")
            }
        }
    }

    static func scan(documents: [(MemberDocument, PDFDocument)], pageOrder: [PageRef]) -> PDFFormSummary {
        var fields: [PDFFormField] = []
        var hasUnsupportedDynamicFeatures = false
        for (member, pdf) in documents {
            hasUnsupportedDynamicFeatures = hasUnsupportedDynamicFeatures || containsUnsupportedDynamicFeatures(in: pdf)
            for pageIndex in 0..<pdf.pageCount {
                guard member.pageRefs.indices.contains(pageIndex),
                      let page = pdf.page(at: pageIndex),
                      let pageRef = pageOrder.first(where: { $0.id == member.pageRefs[pageIndex] }) else {
                    continue
                }
                for (annotationIndex, annotation) in page.annotations.enumerated() where annotation.isPDFWidget {
                    fields.append(PDFFormField(
                        id: "\(pageRef.id.uuidString)-\(annotation.fieldName ?? "\(annotationIndex)")",
                        pageRefID: pageRef.id,
                        fieldName: annotation.fieldName ?? "Field \(fields.count + 1)",
                        fieldType: annotation.widgetFieldType.rawValue,
                        value: displayValue(for: annotation),
                        bounds: annotation.bounds
                    ))
                }
            }
        }
        return PDFFormSummary(fields: fields, hasUnsupportedDynamicFeatures: hasUnsupportedDynamicFeatures)
    }

    static func containsUnsupportedDynamicFeatures(in data: Data) -> Bool {
        unsupportedDynamicFormMarkers.contains { marker in
            data.range(of: marker) != nil
        }
    }

    static func flattenedData(from pdfData: Data, pageOrder: [PageRef]) throws -> Data {
        guard let document = PDFDocument(data: pdfData), document.pageCount > 0 else {
            throw FormError.invalidPDF
        }
        guard document.pageCount == pageOrder.count else {
            throw FormError.pageOrderMismatch
        }

        let output = NSMutableData()
        guard let consumer = CGDataConsumer(data: output as CFMutableData),
              var defaultMediaBox = document.page(at: 0)?.bounds(for: .mediaBox),
              let context = CGContext(consumer: consumer, mediaBox: &defaultMediaBox, nil) else {
            throw FormError.invalidPDF
        }

        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else {
                throw FormError.invalidPDF
            }
            let mediaBox = page.bounds(for: .mediaBox)
            context.beginPDFPage(pageInfo(mediaBox: mediaBox))
            context.saveGState()
            page.draw(with: .mediaBox, to: context)
            context.restoreGState()

            var drawnRadioGroups = Set<String>()
            for annotation in page.annotations where annotation.isPDFWidget {
                guard shouldDraw(annotation, drawnRadioGroups: &drawnRadioGroups) else { continue }
                drawFlattenedValue(for: annotation, in: context)
            }
            context.endPDFPage()
        }
        context.closePDF()

        guard output.length > 0,
              let flattenedDocument = PDFDocument(data: output as Data),
              flattenedDocument.pageCount == document.pageCount else {
            throw FormError.invalidPDF
        }
        try copyNonWidgetAnnotations(from: document, to: flattenedDocument)
        guard let flattenedData = PDFSerializer.data(from: flattenedDocument) else {
            throw FormError.invalidPDF
        }
        return flattenedData
    }

    static func displayValue(for annotation: PDFAnnotation) -> String {
        if annotation.widgetFieldType == .button {
            return annotation.buttonWidgetState == .onState ? "On" : "Off"
        }
        return annotation.widgetStringValue ?? annotation.contents ?? ""
    }

    private static func drawFlattenedValue(for annotation: PDFAnnotation, in context: CGContext) {
        let rect = annotation.bounds.standardized
        guard rect.width > 2, rect.height > 2 else { return }
        if annotation.widgetFieldType == .button {
            drawButtonValue(annotation, in: rect, context: context)
            return
        }
        let value = displayValue(for: annotation).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        let fontSize = min(max(rect.height * 0.45, 9), 14)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize),
            .foregroundColor: NSColor.black
        ]
        let textRect = rect.insetBy(dx: 4, dy: max(2, (rect.height - fontSize) / 3))
        drawString(value, in: textRect, attributes: attributes, context: context)
    }

    private static func shouldDraw(_ annotation: PDFAnnotation, drawnRadioGroups: inout Set<String>) -> Bool {
        guard annotation.widgetFieldType == .button,
              annotation.widgetControlType == .radioButtonControl,
              annotation.buttonWidgetState == .onState else {
            return true
        }
        let group = annotation.fieldName ?? UUID().uuidString
        guard !drawnRadioGroups.contains(group) else { return false }
        drawnRadioGroups.insert(group)
        return true
    }

    private static func drawButtonValue(_ annotation: PDFAnnotation, in rect: CGRect, context: CGContext) {
        context.saveGState()
        context.setStrokeColor(NSColor.black.cgColor)
        context.setLineWidth(1)
        context.stroke(rect.insetBy(dx: 1, dy: 1))
        if annotation.buttonWidgetState == .onState {
            let mark = "✓"
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.boldSystemFont(ofSize: min(rect.height * 0.72, 18)),
                .foregroundColor: NSColor.black
            ]
            drawString(mark, in: rect.insetBy(dx: 2, dy: 1), attributes: attributes, context: context)
        }
        context.restoreGState()
    }

    private static func copyNonWidgetAnnotations(from source: PDFDocument, to destination: PDFDocument) throws {
        guard source.pageCount == destination.pageCount else {
            throw FormError.invalidPDF
        }
        for pageIndex in 0..<source.pageCount {
            guard let sourcePage = source.page(at: pageIndex),
                  let destinationPage = destination.page(at: pageIndex) else {
                throw FormError.invalidPDF
            }
            for annotation in sourcePage.annotations where !annotation.isPDFWidget {
                guard let copied = annotation.copy() as? PDFAnnotation else {
                    throw FormError.invalidPDF
                }
                destinationPage.addAnnotation(copied)
            }
        }
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

    private static func containsUnsupportedDynamicFeatures(in document: PDFDocument) -> Bool {
        guard let data = document.dataRepresentation() else { return false }
        return containsUnsupportedDynamicFeatures(in: data)
    }

    private static let unsupportedDynamicFormMarkers = [
        Data("/XFA".utf8),
        Data("/JavaScript".utf8),
        Data("/JS".utf8)
    ]
}

extension PDFAnnotation {
    var isPDFWidget: Bool {
        type == "Widget" || !widgetFieldType.rawValue.isEmpty
    }
}
