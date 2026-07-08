import AppKit
import CoreGraphics
import Foundation
import PDFKit

/// Generates small, deterministic PDF fixtures for the editing-hardening tests. Text is
/// drawn with CoreText and rules/underlines are drawn as real CGContext strokes, so PDFium
/// reports them as genuine PATH page objects (which `PageGraphicsIndex` classifies) — the
/// only way to exercise underline detection and table-rule awareness against the real
/// analysis engine rather than a mock.
///
/// Coordinates are PDF-native (y-up, origin bottom-left). Page size defaults to US Letter.
enum EditingFixturePDFBuilder {
    static let pageSize = CGSize(width: 612, height: 792)

    struct TextRun {
        var string: String
        var origin: CGPoint          // baseline origin, PDF space
        var fontName: String = "Helvetica"
        var fontSize: CGFloat = 12
        var color: NSColor = .black
        var underline: Bool = false  // draws a stroked rule ~1.2pt below the baseline
    }

    struct Rule {
        var rect: CGRect             // thin rect; short side is the stroke thickness
        var color: NSColor = .black
    }

    /// Renders one page with the given runs + rules into a single-page PDF, optionally
    /// tagged with a `/Rotate` value.
    static func makePDF(runs: [TextRun], rules: [Rule] = [], rotation: Int = 0) -> Data {
        let data = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            return Data()
        }
        ctx.beginPDFPage(nil)
        // White background so sampling/erase logic sees paper.
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(mediaBox)

        for rule in rules {
            ctx.setFillColor(rule.color.cgColor)
            ctx.fill(rule.rect)
        }

        for run in runs {
            let font = CTFontCreateWithName(run.fontName as CFString, run.fontSize, nil)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: run.color.cgColor
            ]
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: run.string, attributes: attrs))
            ctx.textPosition = run.origin
            CTLineDraw(line, ctx)
            if run.underline {
                let width = CTLineGetTypographicBounds(line, nil, nil, nil)
                ctx.setFillColor(run.color.cgColor)
                // ~1.2pt below the baseline, 1pt thick — a typical PDF underline.
                ctx.fill(CGRect(x: run.origin.x, y: run.origin.y - 1.6, width: CGFloat(width), height: 1.0))
            }
        }

        ctx.endPDFPage()
        ctx.closePDF()

        guard rotation != 0, let pdf = PDFDocument(data: data as Data), let page = pdf.page(at: 0) else {
            return data as Data
        }
        page.rotation = rotation
        return pdf.dataRepresentation() ?? (data as Data)
    }

    // MARK: - Canned fixtures

    /// A single underlined line of body text.
    static func underlinedParagraph(text: String = "Jane Q Public") -> Data {
        makePDF(runs: [
            TextRun(string: "Contact information below", origin: CGPoint(x: 72, y: 720), fontSize: 11),
            TextRun(string: text, origin: CGPoint(x: 72, y: 690), fontName: "Helvetica", fontSize: 12, underline: true)
        ])
    }

    /// Heading above a 2-column × 3-row table with horizontal + vertical rules and
    /// distinct header vs body fonts. Narrow (~10pt) gutter between columns.
    static func tableWithRules() -> Data {
        let left: CGFloat = 72, right: CGFloat = 540
        let col1X: CGFloat = 80, col2X: CGFloat = 320
        let rowYs: [CGFloat] = [640, 610, 580]   // baselines
        let ruleYs: [CGFloat] = [660, 630, 600, 570] // rules between/around rows
        var runs: [TextRun] = [
            TextRun(string: "Quarterly Summary", origin: CGPoint(x: left, y: 700), fontName: "Helvetica-Bold", fontSize: 16),
            // header row
            TextRun(string: "Region", origin: CGPoint(x: col1X, y: rowYs[0]), fontName: "Helvetica-Bold", fontSize: 11),
            TextRun(string: "Revenue", origin: CGPoint(x: col2X, y: rowYs[0]), fontName: "Helvetica-Bold", fontSize: 11),
            // body rows
            TextRun(string: "North", origin: CGPoint(x: col1X, y: rowYs[1]), fontSize: 11),
            TextRun(string: "12400", origin: CGPoint(x: col2X, y: rowYs[1]), fontSize: 11),
            TextRun(string: "South", origin: CGPoint(x: col1X, y: rowYs[2]), fontSize: 11),
            TextRun(string: "9800", origin: CGPoint(x: col2X, y: rowYs[2]), fontSize: 11)
        ]
        _ = runs // silence if unused warnings during edits
        var rules: [Rule] = ruleYs.map { Rule(rect: CGRect(x: left, y: $0, width: right - left, height: 0.75)) }
        // vertical rules: table left edge, column divider (~310, in the gutter), right edge
        for x in [left, CGFloat(310), right] {
            rules.append(Rule(rect: CGRect(x: x, y: ruleYs.last!, width: 0.75, height: ruleYs.first! - ruleYs.last!)))
        }
        return makePDF(runs: runs, rules: rules)
    }

    /// A resume-style bullet list: "• " markers drawn as a separate run at a smaller x than
    /// the hanging-indent body text.
    static func bulletList() -> Data {
        var runs: [TextRun] = [TextRun(string: "Experience", origin: CGPoint(x: 72, y: 720), fontName: "Helvetica-Bold", fontSize: 13)]
        let items = ["Led the migration to a new build system", "Reduced page load time by forty percent", "Mentored three junior engineers"]
        var y: CGFloat = 690
        for item in items {
            runs.append(TextRun(string: "\u{2022}", origin: CGPoint(x: 72, y: y), fontSize: 12))
            runs.append(TextRun(string: item, origin: CGPoint(x: 92, y: y), fontSize: 12))
            y -= 24
        }
        return makePDF(runs: runs)
    }

    /// A monospaced (Monaco) header page mirroring editedrun2.pdf page 1: a title, a
    /// "Prepared for:" line, a date line, an OVERVIEW section header, a genuinely-wrapped
    /// two-line control paragraph (MUST still merge), and a rule-less 3-column text grid
    /// whose column cells are stacked with normal single-spacing (MUST stay separate).
    static func monospacedHeaderPage() -> Data {
        var runs: [TextRun] = [
            TextRun(string: "SAMPLE PROJECT PROPOSAL", origin: CGPoint(x: 54, y: 730), fontName: "Monaco", fontSize: 12),
            TextRun(string: "Prepared for: Demo Client", origin: CGPoint(x: 54, y: 710), fontName: "Monaco", fontSize: 12),
            TextRun(string: "Date: January 2026", origin: CGPoint(x: 54, y: 690), fontName: "Monaco", fontSize: 12),
            TextRun(string: "OVERVIEW", origin: CGPoint(x: 54, y: 660), fontName: "Monaco", fontSize: 12),
            // Control paragraph: two lines that genuinely wrap (line 1 fills to the right
            // margin), so the merge logic must still fuse them.
            TextRun(string: "This is a short sample document used only to demonstrate that a real wrapped", origin: CGPoint(x: 54, y: 636), fontName: "Monaco", fontSize: 12),
            TextRun(string: "paragraph continues onto its second line and stays one editable block.", origin: CGPoint(x: 54, y: 620), fontName: "Monaco", fontSize: 12)
        ]
        // Rule-less table: 3 columns (Phase / Duration / Owner), cells stacked with normal
        // single-spacing. These must remain separate cells, not merge into one column block.
        let colX: [CGFloat] = [54, 200, 340]
        let headers = ["Phase", "Duration", "Owner"]
        for (idx, header) in headers.enumerated() {
            runs.append(TextRun(string: header, origin: CGPoint(x: colX[idx], y: 580), fontName: "Monaco", fontSize: 12))
        }
        let cells = [["Discovery", "Build", "Review"], ["2 weeks", "4 weeks", "1 week"], ["Demo Team", "Demo Team", "Demo Client"]]
        for (col, columnCells) in cells.enumerated() {
            var y: CGFloat = 560
            for cell in columnCells {
                runs.append(TextRun(string: cell, origin: CGPoint(x: colX[col], y: y), fontName: "Monaco", fontSize: 12))
                y -= 18   // ~1.5em pitch — normal single-spacing, not a big gap
            }
        }
        return makePDF(runs: runs)
    }

    /// Mixed fonts/sizes/colors for detected-font and Match tests.
    static func mixedFonts() -> Data {
        makePDF(runs: [
            TextRun(string: "Project Overview", origin: CGPoint(x: 72, y: 720), fontName: "Helvetica-Bold", fontSize: 13, color: .black),
            TextRun(string: "The body paragraph describes the work in plain language for the reader.", origin: CGPoint(x: 72, y: 690), fontName: "Helvetica", fontSize: 10, color: NSColor(white: 0.1, alpha: 1)),
            TextRun(string: "A caption in italic for the figure above", origin: CGPoint(x: 72, y: 660), fontName: "Times-Italic", fontSize: 11, color: NSColor(white: 0.4, alpha: 1)),
            TextRun(string: "More body text continues the paragraph naturally here.", origin: CGPoint(x: 72, y: 630), fontName: "Helvetica", fontSize: 10, color: NSColor(white: 0.1, alpha: 1))
        ])
    }
}
