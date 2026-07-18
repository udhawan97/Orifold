import CQPDF
import Foundation

/// A single embedded file ("attachment") surfaced from a PDF's document-level
/// `/Root/Names/EmbeddedFiles` name tree.
///
/// `name` is the name-tree *key* qpdf uses to identify the attachment for
/// extraction and removal — our add path sets that key equal to the display
/// filename, so it doubles as the label shown in the UI. `byteCount` is the
/// decoded file size read from the embedded-file stream's `/Params /Size`;
/// `mimeType` is the stream's `/Subtype` when present.
struct PDFAttachment: Equatable {
    let name: String
    let byteCount: Int
    let mimeType: String?
}

enum AttachmentsError: Error, Equatable {
    /// qpdf could not open the source bytes (corrupt, or encrypted without the
    /// supplied password).
    case invalidPDF
    /// No attachment with the requested key exists.
    case notFound
    /// qpdf's add pass did not produce structurally sound bytes.
    case addFailed
    /// qpdf's remove pass did not produce structurally sound bytes.
    case removeFailed
}

/// Lists, extracts, adds, and removes PDF embedded files ("attachments").
///
/// Reads (`list`/`extract`) walk the `/Root/Names/EmbeddedFiles` name tree
/// directly through qpdf's object API — a clean in-memory read with no temp
/// files. Writes (`add`/`remove`) drive qpdf's own `QPDFJob` engine
/// (`qpdfjob_run_from_argv`), which builds and maintains the `/Filespec` +
/// name-tree correctly and serializes through qpdf's structure-preserving
/// writer (the same writer `QPDFService.optimized`/`sanitized` rely on). Both
/// halves reach everything through the existing `CQPDF` module, so the whole
/// feature adds ZERO new `@_silgen_name` bindings.
///
/// Note the deliberate symmetry with `QPDFService.sanitized(_:removingMetadata:)`,
/// which *strips* `/Names/EmbeddedFiles` outright: "sanitize for sharing" and
/// this manager touch the same object graph, so a sanitized export intentionally
/// drops every attachment listed here.
enum AttachmentsService {
    // MARK: - List / extract (qpdf_oh name-tree walk)

    /// Returns every embedded file in `data`, in name-tree order. An absent name
    /// tree (the common case) yields `[]`. Throws `.invalidPDF` when qpdf can't
    /// parse `data` (including an encrypted document whose `password` is missing
    /// or wrong).
    static func list(in data: Data, password: String? = nil) throws -> [PDFAttachment] {
        let result = QPDFService.withQPDF(data, description: "attachments-list", password: password) { qpdf -> [PDFAttachment] in
            guard let node = embeddedFilesNode(qpdf) else { return [] }
            var attachments: [PDFAttachment] = []
            collectAttachments(qpdf, node: node, into: &attachments, depth: 0)
            return attachments
        }
        guard let result else { throw AttachmentsError.invalidPDF }
        return result
    }

    /// Returns the decoded bytes of the attachment whose name-tree key is `name`.
    /// Throws `.invalidPDF` when qpdf can't parse `data`, or `.notFound` when no
    /// such attachment exists.
    static func extract(_ name: String, from data: Data, password: String? = nil) throws -> Data {
        // Capture the bytes in an outer var rather than returning `Data?` from the
        // body: `withQPDF` already overloads its own `nil` return to mean "couldn't
        // open", so a body-returned `nil` (attachment absent) would be
        // indistinguishable from that. A `Bool` "did open" return keeps the two
        // failure modes cleanly separated.
        var extracted: Data? = nil
        let opened = QPDFService.withQPDF(data, description: "attachments-extract", password: password) { qpdf -> Bool in
            guard let node = embeddedFilesNode(qpdf),
                  let filespec = findFilespec(qpdf, node: node, name: name, depth: 0),
                  let stream = embeddedFileStream(qpdf, filespec: filespec) else { return true }
            extracted = streamData(qpdf, stream)
            return true
        }
        guard opened != nil else { throw AttachmentsError.invalidPDF }
        guard let bytes = extracted else { throw AttachmentsError.notFound }
        return bytes
    }

    // MARK: - Add / remove (qpdfjob argv)

    /// Adds `fileData` as an attachment named `name`, returning the rewritten
    /// bytes. Path separators in `name` are stripped, and a colliding key is
    /// disambiguated (`note.txt` → `note-2.txt`) because qpdf refuses a duplicate
    /// key outright. Throws `.addFailed` when qpdf's add pass can't produce
    /// structurally sound bytes.
    static func add(_ fileData: Data, name: String, mimeType: String?, to data: Data, password: String? = nil) throws -> Data {
        let existingKeys = Set(((try? list(in: data, password: password)) ?? []).map(\.name))
        let filename = sanitizedKey(name)
        let key = disambiguated(filename, against: existingKeys)

        let attachmentURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Orifold-attachment-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: attachmentURL) }
        try fileData.write(to: attachmentURL)

        let output = try runJobPreservingSource(data, password: password) { inputURL, outputURL in
            var arguments = ["qpdf"]
            if let password { arguments.append("--password=\(password)") }
            arguments.append(contentsOf: [
                inputURL.path, outputURL.path,
                "--add-attachment", attachmentURL.path,
                "--key=\(key)", "--filename=\(filename)"
            ])
            if let mimeType, !mimeType.isEmpty { arguments.append("--mimetype=\(mimeType)") }
            arguments.append("--") // terminates the --add-attachment sub-options
            return runJob(arguments)
        }
        guard let output else { throw AttachmentsError.addFailed }
        return output
    }

    /// Removes the attachment whose name-tree key is `name`, returning the
    /// rewritten bytes. Throws `.removeFailed` when qpdf's remove pass can't
    /// produce structurally sound bytes (including when no such key exists).
    static func remove(_ name: String, from data: Data, password: String? = nil) throws -> Data {
        let output = try runJobPreservingSource(data, password: password) { inputURL, outputURL in
            var arguments = ["qpdf"]
            if let password { arguments.append("--password=\(password)") }
            arguments.append(contentsOf: [inputURL.path, outputURL.path, "--remove-attachment=\(name)"])
            return runJob(arguments)
        }
        guard let output else { throw AttachmentsError.removeFailed }
        return output
    }

    // MARK: - qpdfjob plumbing

    // qpdf exit codes (Constants.h, qpdf_exit_code_e): 0 = success, 3 = warnings
    // (tolerated — e.g. a recovered xref), 2 = errors.
    private static let jobExitSuccess: Int32 = 0
    private static let jobExitWarnings: Int32 = 3

    /// Writes `source` to a temp input, runs `job` (which must write to the temp
    /// output), then reads the output back and gates it through qpdf's structural
    /// check. Returns `nil` on any non-success/warning exit, empty output, or a
    /// failed structural check. All temp files are cleaned up in `defer`
    /// (precedent: `PDFCompressionService`).
    private static func runJobPreservingSource(
        _ source: Data,
        password: String?,
        _ job: (URL, URL) throws -> Int32
    ) throws -> Data? {
        let directory = FileManager.default.temporaryDirectory
        let inputURL = directory.appendingPathComponent("Orifold-att-in-\(UUID().uuidString).pdf")
        let outputURL = directory.appendingPathComponent("Orifold-att-out-\(UUID().uuidString).pdf")
        defer {
            try? FileManager.default.removeItem(at: inputURL)
            try? FileManager.default.removeItem(at: outputURL)
        }
        try source.write(to: inputURL)
        let code = try job(inputURL, outputURL)
        guard code == jobExitSuccess || code == jobExitWarnings else { return nil }
        guard let output = try? Data(contentsOf: outputURL), !output.isEmpty else { return nil }
        guard QPDFService.isStructurallySound(output, password: password) else { return nil }
        return output
    }

    /// Bridges a Swift `[String]` into the null-terminated C `argv` qpdfjob
    /// expects, `strdup`-ing each argument and freeing every copy after the call.
    private static func runJob(_ arguments: [String]) -> Int32 {
        let copies = arguments.map { strdup($0) }
        defer { copies.forEach { free($0) } }
        var argv: [UnsafePointer<CChar>?] = copies.map { $0.map { UnsafePointer($0) } }
        argv.append(nil)
        return qpdfjob_run_from_argv(argv)
    }

    /// Strips path separators so a crafted `name` can't smuggle a path into the
    /// name tree; keeps the key a flat identifier.
    private static func sanitizedKey(_ name: String) -> String {
        let cleaned = name
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "attachment" : cleaned
    }

    /// Returns `key` unchanged unless it collides with an existing name-tree key,
    /// in which case it inserts a `-N` suffix before the extension.
    private static func disambiguated(_ key: String, against existing: Set<String>) -> String {
        guard existing.contains(key) else { return key }
        let asNSString = key as NSString
        let ext = asNSString.pathExtension
        let base = ext.isEmpty ? key : asNSString.deletingPathExtension
        var index = 2
        while true {
            let candidate = ext.isEmpty ? "\(base)-\(index)" : "\(base)-\(index).\(ext)"
            if !existing.contains(candidate) { return candidate }
            index += 1
        }
    }

    // MARK: - Name-tree walk helpers

    /// The `/Root/Names/EmbeddedFiles` name-tree root node, or `nil` when the
    /// document has no embedded-files tree.
    private static func embeddedFilesNode(_ qpdf: qpdf_data) -> qpdf_oh? {
        let root = qpdf_get_root(qpdf)
        guard hasKey(qpdf, root, "/Names") else { return nil }
        let names = qpdf_oh_get_key(qpdf, root, "/Names")
        guard qpdf_oh_is_dictionary(qpdf, names) == QPDF_TRUE, hasKey(qpdf, names, "/EmbeddedFiles") else { return nil }
        let embeddedFiles = qpdf_oh_get_key(qpdf, names, "/EmbeddedFiles")
        guard qpdf_oh_is_dictionary(qpdf, embeddedFiles) == QPDF_TRUE else { return nil }
        return embeddedFiles
    }

    /// Recursively collects `(key, filespec)` pairs. A name-tree node is either a
    /// leaf holding a `/Names` array of alternating `[key, value, key, value, …]`
    /// or an intermediate holding a `/Kids` array of child nodes — a node may
    /// legally carry both, so both branches are always checked. `depth` guards
    /// against a maliciously cyclic/deep tree.
    private static func collectAttachments(
        _ qpdf: qpdf_data,
        node: qpdf_oh,
        into attachments: inout [PDFAttachment],
        depth: Int
    ) {
        guard depth < 64 else { return }
        if hasKey(qpdf, node, "/Names") {
            let names = qpdf_oh_get_key(qpdf, node, "/Names")
            if qpdf_oh_is_array(qpdf, names) == QPDF_TRUE {
                let count = qpdf_oh_get_array_n_items(qpdf, names)
                var index: Int32 = 0
                while index + 1 < count {
                    let keyObject = qpdf_oh_get_array_item(qpdf, names, index)
                    let filespec = qpdf_oh_get_array_item(qpdf, names, index + 1)
                    if let key = utf8Value(qpdf, keyObject) {
                        let (byteCount, mimeType) = embeddedFileInfo(qpdf, filespec: filespec)
                        attachments.append(PDFAttachment(name: key, byteCount: byteCount, mimeType: mimeType))
                    }
                    index += 2
                }
            }
        }
        if hasKey(qpdf, node, "/Kids") {
            let kids = qpdf_oh_get_key(qpdf, node, "/Kids")
            if qpdf_oh_is_array(qpdf, kids) == QPDF_TRUE {
                for kidIndex in 0..<qpdf_oh_get_array_n_items(qpdf, kids) {
                    collectAttachments(
                        qpdf,
                        node: qpdf_oh_get_array_item(qpdf, kids, kidIndex),
                        into: &attachments,
                        depth: depth + 1
                    )
                }
            }
        }
    }

    /// Finds the filespec dictionary for a given name-tree key, recursing through
    /// `/Kids` exactly like `collectAttachments`.
    private static func findFilespec(
        _ qpdf: qpdf_data,
        node: qpdf_oh,
        name: String,
        depth: Int
    ) -> qpdf_oh? {
        guard depth < 64 else { return nil }
        if hasKey(qpdf, node, "/Names") {
            let names = qpdf_oh_get_key(qpdf, node, "/Names")
            if qpdf_oh_is_array(qpdf, names) == QPDF_TRUE {
                let count = qpdf_oh_get_array_n_items(qpdf, names)
                var index: Int32 = 0
                while index + 1 < count {
                    if utf8Value(qpdf, qpdf_oh_get_array_item(qpdf, names, index)) == name {
                        return qpdf_oh_get_array_item(qpdf, names, index + 1)
                    }
                    index += 2
                }
            }
        }
        if hasKey(qpdf, node, "/Kids") {
            let kids = qpdf_oh_get_key(qpdf, node, "/Kids")
            if qpdf_oh_is_array(qpdf, kids) == QPDF_TRUE {
                for kidIndex in 0..<qpdf_oh_get_array_n_items(qpdf, kids) {
                    if let found = findFilespec(
                        qpdf,
                        node: qpdf_oh_get_array_item(qpdf, kids, kidIndex),
                        name: name,
                        depth: depth + 1
                    ) {
                        return found
                    }
                }
            }
        }
        return nil
    }

    /// Reads `/Params /Size` (decoded byte count) and `/Subtype` (MIME) off a
    /// filespec's embedded-file stream. Both are best-effort: a missing `/Params`
    /// yields a zero count and a missing `/Subtype` yields `nil`.
    private static func embeddedFileInfo(_ qpdf: qpdf_data, filespec: qpdf_oh) -> (Int, String?) {
        guard let stream = embeddedFileStream(qpdf, filespec: filespec) else { return (0, nil) }
        // `/Params` and `/Subtype` live on the stream's *dictionary*; a stream
        // object handle isn't itself a dictionary, so `qpdf_oh_get_dict` is
        // required before any key read (unlike the plain filespec dict above).
        let dictionary = qpdf_oh_get_dict(qpdf, stream)
        var byteCount = 0
        if hasKey(qpdf, dictionary, "/Params") {
            let params = qpdf_oh_get_key(qpdf, dictionary, "/Params")
            if qpdf_oh_is_dictionary(qpdf, params) == QPDF_TRUE, hasKey(qpdf, params, "/Size") {
                byteCount = max(0, Int(qpdf_oh_get_int_value_as_int(qpdf, qpdf_oh_get_key(qpdf, params, "/Size"))))
            }
        }
        var mimeType: String? = nil
        if hasKey(qpdf, dictionary, "/Subtype") {
            mimeType = nameValue(qpdf, qpdf_oh_get_key(qpdf, dictionary, "/Subtype"))
        }
        return (byteCount, mimeType)
    }

    /// The embedded-file stream (`/EF /F` or `/EF /UF`) referenced by a filespec.
    private static func embeddedFileStream(_ qpdf: qpdf_data, filespec: qpdf_oh) -> qpdf_oh? {
        guard qpdf_oh_is_dictionary(qpdf, filespec) == QPDF_TRUE, hasKey(qpdf, filespec, "/EF") else { return nil }
        let embeddedFile = qpdf_oh_get_key(qpdf, filespec, "/EF")
        guard qpdf_oh_is_dictionary(qpdf, embeddedFile) == QPDF_TRUE else { return nil }
        for key in ["/F", "/UF"] where hasKey(qpdf, embeddedFile, key) {
            let stream = qpdf_oh_get_key(qpdf, embeddedFile, key)
            if qpdf_oh_is_stream(qpdf, stream) == QPDF_TRUE { return stream }
        }
        return nil
    }

    /// Copies a stream's fully-decoded (`qpdf_dl_all`) bytes into a Swift `Data`.
    /// qpdf allocates the buffer with `malloc`; the copy must happen immediately
    /// and the buffer must be released with `qpdf_oh_free_buffer` — never a bare
    /// `free`, and never left dangling past this call.
    private static func streamData(_ qpdf: qpdf_data, _ stream: qpdf_oh) -> Data? {
        var filtered: QPDF_BOOL = QPDF_FALSE
        var buffer: UnsafeMutablePointer<UInt8>?
        var length = 0
        let code = qpdf_oh_get_stream_data(qpdf, stream, qpdf_dl_all, &filtered, &buffer, &length)
        guard hasErrors(code) == false else { return nil }
        guard let buffer else { return Data() }
        defer {
            var releasable: UnsafeMutablePointer<UInt8>? = buffer
            qpdf_oh_free_buffer(&releasable)
        }
        return Data(bytes: buffer, count: length)
    }

    // MARK: - qpdf value / key helpers

    private static func hasKey(_ qpdf: qpdf_data, _ oh: qpdf_oh, _ key: String) -> Bool {
        key.withCString { qpdf_oh_has_key(qpdf, oh, $0) != QPDF_FALSE }
    }

    /// Reads a PDF string object as UTF-8, copying the exact bytes immediately
    /// (qpdf owns the returned buffer). Absent, non-string, or empty values map to
    /// `nil`.
    private static func utf8Value(_ qpdf: qpdf_data, _ oh: qpdf_oh) -> String? {
        var raw: UnsafePointer<CChar>?
        var length = 0
        guard qpdf_oh_get_value_as_utf8(qpdf, oh, &raw, &length) == QPDF_TRUE, let raw, length > 0 else { return nil }
        return raw.withMemoryRebound(to: UInt8.self, capacity: length) {
            String(decoding: UnsafeBufferPointer(start: $0, count: length), as: UTF8.self)
        }
    }

    /// Reads a PDF name object as a MIME string: qpdf hands back the canonical
    /// name with a leading `/`, so that's stripped, and any residual `#XX` hex
    /// escapes are decoded (a no-op when qpdf already resolved them).
    private static func nameValue(_ qpdf: qpdf_data, _ oh: qpdf_oh) -> String? {
        var raw: UnsafePointer<CChar>?
        var length = 0
        guard qpdf_oh_get_value_as_name(qpdf, oh, &raw, &length) == QPDF_TRUE, let raw, length > 0 else { return nil }
        var name = raw.withMemoryRebound(to: UInt8.self, capacity: length) {
            String(decoding: UnsafeBufferPointer(start: $0, count: length), as: UTF8.self)
        }
        if name.hasPrefix("/") { name.removeFirst() }
        let decoded = decodedNameEscapes(name)
        return decoded.isEmpty ? nil : decoded
    }

    private static func decodedNameEscapes(_ value: String) -> String {
        guard value.contains("#") else { return value }
        let bytes = Array(value.utf8)
        var out: [UInt8] = []
        out.reserveCapacity(bytes.count)
        var index = 0
        while index < bytes.count {
            if bytes[index] == UInt8(ascii: "#"), index + 2 < bytes.count,
               let high = hexNibble(bytes[index + 1]), let low = hexNibble(bytes[index + 2]) {
                out.append(high << 4 | low)
                index += 3
            } else {
                out.append(bytes[index])
                index += 1
            }
        }
        return String(decoding: out, as: UTF8.self)
    }

    private static func hexNibble(_ byte: UInt8) -> UInt8? {
        switch byte {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): return byte - UInt8(ascii: "0")
        case UInt8(ascii: "a")...UInt8(ascii: "f"): return byte - UInt8(ascii: "a") + 10
        case UInt8(ascii: "A")...UInt8(ascii: "F"): return byte - UInt8(ascii: "A") + 10
        default: return nil
        }
    }

    private static func hasErrors(_ code: QPDF_ERROR_CODE) -> Bool {
        (code & QPDF_ERRORS) != 0
    }
}
