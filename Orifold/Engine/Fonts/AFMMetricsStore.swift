import Foundation

/// A parsed AFM (Adobe Font Metrics) file: the font's PostScript name plus per-glyph
/// advance widths in 1000-units-per-em text space. Used to check widths for the Core-14
/// base fonts (Helvetica/Times/Courier/Symbol/ZapfDingbats) that a PDF can reference
/// without embedding any glyph program.
struct AFMFont {
    /// The `FontName` from the AFM's global section (e.g. `"Helvetica"`).
    let fontName: String
    /// Glyph name (`"A"`, `"space"`, `"bullet"`) → advance width in 1000ths of an em.
    let glyphWidths: [String: Double]

    /// The advance width for a glyph by its AFM name, or `nil` if the font has no such glyph.
    func advanceWidth(glyphName: String) -> Double? {
        glyphWidths[glyphName]
    }

    /// Best-effort advance width of a run of text: the sum of each character's glyph
    /// advance. Characters with no known glyph name in this font (or outside the mapped
    /// ASCII set) contribute nothing rather than guessing.
    func width(of string: String) -> Double {
        string.reduce(0) { total, character in
            guard let name = Self.glyphName(for: character),
                  let width = glyphWidths[name] else { return total }
            return total + width
        }
    }

    /// Maps a character to its AFM/AdobeStandardEncoding glyph name for `width(of:)`.
    /// ASCII letters name themselves; digits, space, and common punctuation use their
    /// standard names. Anything else returns `nil` (skipped by `width(of:)`).
    private static func glyphName(for character: Character) -> String? {
        if character.isASCII, character.isLetter {
            return String(character)
        }
        return asciiGlyphNames[character]
    }

    private static let asciiGlyphNames: [Character: String] = [
        " ": "space", "0": "zero", "1": "one", "2": "two", "3": "three",
        "4": "four", "5": "five", "6": "six", "7": "seven", "8": "eight",
        "9": "nine", ".": "period", ",": "comma", ":": "colon", ";": "semicolon",
        "!": "exclam", "?": "question", "-": "hyphen", "'": "quoteright",
        "(": "parenleft", ")": "parenright", "/": "slash", "&": "ampersand",
        "@": "at", "#": "numbersign", "$": "dollar", "%": "percent",
        "+": "plus", "=": "equal", "*": "asterisk", "_": "underscore",
    ]
}

/// Parses AFM files and loads the bundled Adobe Core-14 metrics.
enum AFMMetricsStore {
    /// Parses an AFM file's text into an `AFMFont`, or `nil` if the text has no usable
    /// character-metrics section. Reads the `FontName` from the global section and each
    /// `C <code> ; WX <width> ; N <glyph> ;` line between `StartCharMetrics` and
    /// `EndCharMetrics`; extra fields (bounding boxes, ligatures) are ignored.
    static func parse(_ text: String) -> AFMFont? {
        var fontName: String?
        var glyphWidths: [String: Double] = [:]
        var inCharMetrics = false
        var sawCharMetricsSection = false

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("StartCharMetrics") {
                inCharMetrics = true
                sawCharMetricsSection = true
                continue
            }
            if line.hasPrefix("EndCharMetrics") {
                inCharMetrics = false
                continue
            }

            guard inCharMetrics else {
                if line.hasPrefix("FontName") {
                    let value = line.dropFirst("FontName".count).trimmingCharacters(in: .whitespaces)
                    if !value.isEmpty { fontName = value }
                }
                continue
            }

            var glyphName: String?
            var width: Double?
            for field in line.split(separator: ";") {
                let tokens = field.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
                guard let key = tokens.first else { continue }
                switch key {
                case "WX": if tokens.count >= 2 { width = Double(tokens[1]) }
                case "N": if tokens.count >= 2 { glyphName = tokens[1] }
                default: break
                }
            }
            if let glyphName, let width { glyphWidths[glyphName] = width }
        }

        guard sawCharMetricsSection, !glyphWidths.isEmpty else { return nil }
        return AFMFont(fontName: fontName ?? "", glyphWidths: glyphWidths)
    }

    /// Loads a bundled Core-14 AFM by its PostScript resource name (e.g. `"Helvetica"`,
    /// `"Times-Roman"`). Resolves the asset through `FontRegistrar` (the shared bundled-
    /// resource resolver) and returns `nil` — never traps — when the metrics aren't
    /// bundled in this build, so the substitution feature degrades gracefully without them.
    static func core14(_ fontName: String) -> AFMFont? {
        guard let url = FontRegistrar.afmURL(forResource: fontName),
              let text = afmText(at: url) else { return nil }
        return parse(text)
    }

    private static func afmText(at url: URL) -> String? {
        if let utf8 = try? String(contentsOf: url, encoding: .utf8) { return utf8 }
        return try? String(contentsOf: url, encoding: .isoLatin1)
    }
}
