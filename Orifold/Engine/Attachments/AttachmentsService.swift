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
        let result: Data?? = QPDFService.withQPDF(data, description: "attachments-extract", password: password) { qpdf -> Data? in
            guard let node = embeddedFilesNode(qpdf),
                  let filespec = findFilespec(qpdf, node: node, name: name, depth: 0),
                  let stream = embeddedFileStream(qpdf, filespec: filespec) else { return nil }
            return streamData(qpdf, stream)
        }
        guard let inner = result else { throw AttachmentsError.invalidPDF }
        guard let bytes = inner else { throw AttachmentsError.notFound }
        return bytes
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
        var byteCount = 0
        if hasKey(qpdf, stream, "/Params") {
            let params = qpdf_oh_get_key(qpdf, stream, "/Params")
            if qpdf_oh_is_dictionary(qpdf, params) == QPDF_TRUE, hasKey(qpdf, params, "/Size") {
                byteCount = max(0, Int(qpdf_oh_get_int_value_as_int(qpdf, qpdf_oh_get_key(qpdf, params, "/Size"))))
            }
        }
        var mimeType: String? = nil
        if hasKey(qpdf, stream, "/Subtype") {
            mimeType = nameValue(qpdf, qpdf_oh_get_key(qpdf, stream, "/Subtype"))
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
