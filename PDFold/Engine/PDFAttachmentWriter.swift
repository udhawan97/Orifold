import Foundation

/// Embeds a file attachment in a PDF using an ISO 32000-1 §7.5.6
/// incremental update. Requires only Foundation — no third-party deps.
///
/// Works on traditional xref-table PDFs (PDF 1.0–1.4), which is what
/// PDFKit emits by default on macOS.
enum PDFAttachmentWriter {

    // MARK: - Public

    /// Embeds `attachmentData` as a named file in `pdfData`.
    /// Returns the augmented PDF bytes, or nil if the PDF can't be parsed.
    static func embed(
        attachmentData: Data,
        filename: String,
        mimeType: String = "application/json",
        in pdfData: Data
    ) -> Data? {
        guard let info = PDFParser.parse(pdfData) else { return nil }
        let safeFilename = sanitizedFilename(filename)
        return buildIncrementalUpdate(
            pdfData: pdfData,
            info: info,
            attachmentData: attachmentData,
            filename: safeFilename,
            mimeType: mimeType
        )
    }

    // MARK: - Incremental update builder

    private static func buildIncrementalUpdate(
        pdfData: Data,
        info: PDFParser.Info,
        attachmentData: Data,
        filename: String,
        mimeType: String
    ) -> Data {
        var body = Data()
        var xrefEntries: [(objNum: Int, offset: Int)] = []
        var nextObjNum = info.highestObjNum + 1

        func currentOffset() -> Int { pdfData.count + body.count }

        func appendObject(_ num: Int, dict: String, stream: Data? = nil) {
            xrefEntries.append((num, currentOffset()))
            if let s = stream {
                body += enc("\(num) 0 obj\n\(dict)\nstream\n")
                body += s
                body += enc("\nendstream\nendobj\n")
            } else {
                body += enc("\(num) 0 obj\n\(dict)\nendobj\n")
            }
        }

        // ── Object 1: EmbeddedFile stream ───────────────────────────────
        let fileObjNum = nextObjNum; nextObjNum += 1
        appendObject(fileObjNum,
            dict: "<<\n/Type /EmbeddedFile\n/Subtype /\(pdfSubtype(mimeType))\n/Length \(attachmentData.count)\n>>",
            stream: attachmentData
        )

        // ── Object 2: Filespec ───────────────────────────────────────────
        let filespecObjNum = nextObjNum; nextObjNum += 1
        let fname = pdfStr(filename)
        appendObject(filespecObjNum,
            dict: "<<\n/Type /Filespec\n/F \(fname)\n/UF \(fname)\n/EF << /F \(fileObjNum) 0 R >>\n>>"
        )

        // ── Object 3: EmbeddedFiles name tree (flat array form) ──────────
        let nameTreeObjNum = nextObjNum; nextObjNum += 1
        appendObject(nameTreeObjNum,
            dict: "<< /Names [\(fname) \(filespecObjNum) 0 R] >>"
        )

        // ── Object 4: Updated Catalog ────────────────────────────────────
        // Same object number as the original catalog — the incremental
        // update's xref entry overrides the old one.
        let catObjNum = info.catalogObjNum
        xrefEntries.append((catObjNum, currentOffset()))
        // Preserve the /Pages reference; add /Names.
        // Optional catalog keys from the original are NOT preserved here;
        // this is acceptable for freshly-exported PDFs where PDFKit only
        // writes /Type + /Pages.
        body += enc("""
            \(catObjNum) 0 obj
            <<
            /Type /Catalog
            /Pages \(info.pagesObjNum) 0 R
            /Names << /EmbeddedFiles \(nameTreeObjNum) 0 R >>
            >>
            endobj\n
            """)

        // ── xref section ─────────────────────────────────────────────────
        let xrefStart = currentOffset()
        body += enc(buildXref(entries: xrefEntries))

        // ── trailer ──────────────────────────────────────────────────────
        let newSize = max(info.pdfSize, nextObjNum, info.highestObjNum + 1)
        body += enc("""
            trailer
            <<
            /Size \(newSize)
            /Root \(catObjNum) 0 R
            /Prev \(info.startxref)
            >>
            startxref
            \(xrefStart)
            %%EOF\n
            """)

        var result = pdfData
        result.append(body)
        return result
    }

    // MARK: - xref builder

    private static func buildXref(entries: [(objNum: Int, offset: Int)]) -> String {
        // Group into contiguous runs for compact xref subsections
        let sorted = entries.sorted { $0.objNum < $1.objNum }
        var sections: [[(Int, Int)]] = []
        var run: [(Int, Int)] = []
        for (i, e) in sorted.enumerated() {
            if i > 0, e.objNum != sorted[i - 1].objNum + 1 {
                sections.append(run); run = []
            }
            run.append((e.objNum, e.offset))
        }
        if !run.isEmpty { sections.append(run) }

        var out = "xref\n"
        for section in sections {
            out += "\(section[0].0) \(section.count)\n"
            for (_, off) in section {
                // Each entry must be exactly 20 bytes: 10+1+5+1+1+1+\r\n = 20
                out += "\(String(format: "%010d", off)) 00000 n \r\n"
            }
        }
        return out
    }

    // MARK: - Helpers

    private static func enc(_ s: String) -> Data { Data(s.utf8) }

    /// Converts a MIME type to a PDF name (replaces / with #2F)
    private static func pdfSubtype(_ mimeType: String) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._+-")
        return mimeType.unicodeScalars.map { scalar in
            if scalar == "/" { return "#2F" }
            return allowed.contains(scalar) ? String(scalar) : "#\(String(format: "%02X", scalar.value))"
        }.joined()
    }

    /// Wraps a string as a PDF literal string, escaping parens and backslash
    private static func pdfStr(_ s: String) -> String {
        "(" + s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "(", with: "\\(")
            .replacingOccurrences(of: ")", with: "\\)")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r") + ")"
    }

    private static func sanitizedFilename(_ filename: String) -> String {
        let basename = URL(fileURLWithPath: filename).lastPathComponent
        let filtered = basename.unicodeScalars.filter {
            !CharacterSet.controlCharacters.contains($0) && $0 != "/" && $0 != "\\"
        }
        let safe = String(String.UnicodeScalarView(filtered)).trimmingCharacters(in: .whitespacesAndNewlines)
        return safe.isEmpty ? "attachment" : safe
    }
}

// MARK: - Minimal PDF structure parser

struct PDFParser {
    struct Info {
        var startxref: Int
        var catalogObjNum: Int
        var pagesObjNum: Int
        var highestObjNum: Int
        var pdfSize: Int
    }

    static func parse(_ data: Data) -> Info? {
        // ── 1. Find startxref (last occurrence, scan tail) ───────────────
        let tailLen = min(4096, data.count)
        guard let tail = String(data: data.suffix(tailLen), encoding: .isoLatin1),
              let sxRange = tail.range(of: "startxref", options: .backwards) else { return nil }
        let afterSX = tail[sxRange.upperBound...].drop(while: \.isWhitespace)
        guard let startxref = Int(afterSX.prefix(while: \.isNumber)) else { return nil }

        // ── 2. Read from startxref offset ────────────────────────────────
        guard startxref < data.count,
              let fromXref = String(data: data[startxref...], encoding: .isoLatin1) else { return nil }

        // ── 3. Locate trailer ────────────────────────────────────────────
        guard let trailerRange = fromXref.range(of: "trailer") else { return nil }
        let trailerStr = String(fromXref[trailerRange.upperBound...])

        guard let rootObjNum = extractRef(trailerStr, key: "Root"),
              let pdfSize    = extractInt(trailerStr, key: "Size") else { return nil }

        // ── 4. Parse xref table → offset map ────────────────────────────
        let xrefBody = String(fromXref[fromXref.startIndex..<trailerRange.lowerBound])
        let offsetMap = parseXref(xrefBody)
        guard let catalogOffset = offsetMap[rootObjNum], catalogOffset < data.count else { return nil }

        // ── 5. Read catalog object → /Pages ref ──────────────────────────
        guard let catalogStr = String(data: data[catalogOffset...].prefix(2048), encoding: .isoLatin1),
              let pagesObjNum = extractRef(catalogStr, key: "Pages") else { return nil }

        let highestObjNum = offsetMap.keys.max() ?? (pdfSize - 1)

        return Info(
            startxref: startxref,
            catalogObjNum: rootObjNum,
            pagesObjNum: pagesObjNum,
            highestObjNum: highestObjNum,
            pdfSize: pdfSize
        )
    }

    // MARK: - xref table parser

    private static func parseXref(_ s: String) -> [Int: Int] {
        var map: [Int: Int] = [:]
        let lines = s.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0 != "xref" }
        var i = 0
        while i < lines.count {
            let parts = lines[i].split(separator: " ")
            guard parts.count == 2,
                  let first = Int(parts[0]),
                  let count = Int(parts[1]) else { i += 1; continue }
            i += 1
            for j in 0..<count {
                guard i < lines.count else { break }
                let ep = lines[i].split(separator: " "); i += 1
                guard ep.count >= 3, let off = Int(ep[0]), ep[2] == "n" else { continue }
                map[first + j] = off
            }
        }
        return map
    }

    // MARK: - Value extractors

    /// Extracts object number from `/Key N M R`
    static func extractRef(_ s: String, key: String) -> Int? {
        guard let re = try? NSRegularExpression(pattern: "/\(key)\\s+(\\d+)\\s+\\d+\\s+R"),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              let r = Range(m.range(at: 1), in: s) else { return nil }
        return Int(s[r])
    }

    /// Extracts integer from `/Key N`
    static func extractInt(_ s: String, key: String) -> Int? {
        guard let re = try? NSRegularExpression(pattern: "/\(key)\\s+(\\d+)"),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              let r = Range(m.range(at: 1), in: s) else { return nil }
        return Int(s[r])
    }
}
