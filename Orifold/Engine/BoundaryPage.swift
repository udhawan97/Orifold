import PDFKit
import AppKit

final class BoundaryPage: PDFPage {
    private let docName: String
    private let docPageCount: Int

    init(documentName: String, pageCount: Int, width: CGFloat = 612) {
        self.docName = documentName
        self.docPageCount = pageCount
        super.init()
        setBounds(CGRect(x: 0, y: 0, width: width, height: 80), for: .mediaBox)
    }

    required init?(coder: NSCoder) { nil }

    override func draw(with box: PDFDisplayBox, to context: CGContext) {
        let rect = bounds(for: box)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)

        // Background — warm canvas tone
        NSColor(srgbRed: 0.945, green: 0.937, blue: 0.914, alpha: 1).setFill()
        rect.fill()

        // Top hairline
        NSColor(white: 0, alpha: 0.08).setFill()
        NSRect(x: 0, y: rect.height - 0.5, width: rect.width, height: 0.5).fill()

        // Left accent bar — clay
        NSColor(srgbRed: 0.788, green: 0.392, blue: 0.259, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: 4, height: rect.height).fill()

        // Title
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
            .foregroundColor: NSColor(srgbRed: 0.102, green: 0.098, blue: 0.082, alpha: 1)
        ]
        let subtitleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor(srgbRed: 0.549, green: 0.533, blue: 0.486, alpha: 1)
        ]
        let subtitle = "\(docPageCount) page\(docPageCount == 1 ? "" : "s")" as NSString
        let title = docName as NSString

        // Vertically centre the two-line block in the 80pt banner
        let titleH: CGFloat = 20
        let subH: CGFloat = 14
        let gap: CGFloat = 4
        let blockH = titleH + gap + subH
        let baseY = (rect.height - blockH) / 2

        title.draw(in: CGRect(x: 16, y: baseY + subH + gap, width: rect.width - 24, height: titleH),
                   withAttributes: titleAttrs)
        subtitle.draw(in: CGRect(x: 16, y: baseY, width: rect.width - 24, height: subH),
                      withAttributes: subtitleAttrs)

        NSGraphicsContext.restoreGraphicsState()
    }
}
