import CQPDF
import Foundation

/// Thin Swift wrapper around qpdf's C API (`Packages/QPDFBinary`), used as a
/// structure-level hardening pass alongside PDFKit/PDFium. qpdf never renders
/// or edits page content -- it only repairs, re-encrypts, and re-serializes
/// the underlying PDF object graph, which is why it composes cleanly with the
/// rest of the engine stack instead of replacing any of it.
enum QPDFService {
    enum QPDFServiceError: Error, Equatable {
        case cannotOpenSourcePDF
        case writeFailed
    }

    /// Attempts to recover a damaged PDF (broken xref table, missing trailer,
    /// malformed object) and rewrite it as a clean, valid file. Returns `nil`
    /// if qpdf cannot produce a readable document, in which case the caller
    /// should fall back to its existing "unreadable" error path.
    static func repaired(_ data: Data) -> Data? {
        withQPDF(data, description: "import") { qpdf in
            guard hasErrors(qpdf_check_pdf(qpdf)) == false else { return nil }
            return write(qpdf) { _ in }
        }
    }

    /// Runs qpdf's structural checker (equivalent to `qpdf --check`) without
    /// modifying the data. Used as a post-export validation gate. `password`
    /// must be supplied for encrypted data -- qpdf cannot parse (and will
    /// report as unsound) an encrypted PDF it can't decrypt.
    static func isStructurallySound(_ data: Data, password: String? = nil) -> Bool {
        withQPDF(data, description: "validate", password: password) { qpdf in
            hasErrors(qpdf_check_pdf(qpdf)) == false
        } ?? false
    }

    /// Lossless-only optimization: regenerates object streams and,
    /// optionally, linearizes ("fast web view") the output. Never touches
    /// image or content-stream bytes, so it composes with image downsampling
    /// in `PDFCompressionService` rather than competing with it.
    static func optimized(_ data: Data, linearize: Bool) -> Data? {
        withQPDF(data, description: "optimize") { qpdf in
            guard hasErrors(qpdf_check_pdf(qpdf)) == false else { return nil }
            return write(qpdf) { qpdf in
                qpdf_set_object_stream_mode(qpdf, qpdf_o_generate)
                qpdf_set_linearization(qpdf, linearize ? QPDF_TRUE : QPDF_FALSE)
            }
        }
    }

    /// True AES-256 (PDF 2.0 /R6) encryption with granular permissions.
    /// Replaces the AES-128 that Core Graphics' `kCGPDFContextEncryptionKeyLength`
    /// caps out at.
    static func encryptedAES256(
        _ data: Data,
        userPassword: String,
        ownerPassword: String,
        allowsPrinting: Bool,
        allowsCopying: Bool
    ) throws -> Data {
        let result: Data? = withQPDF(data, description: "encrypt") { qpdf in
            guard hasErrors(qpdf_check_pdf(qpdf)) == false else { return nil }
            return write(qpdf) { qpdf in
                userPassword.withCString { userPtr in
                    ownerPassword.withCString { ownerPtr in
                        qpdf_set_r6_encryption_parameters2(
                            qpdf,
                            userPtr,
                            ownerPtr,
                            QPDF_TRUE, // allow_accessibility
                            allowsCopying ? QPDF_TRUE : QPDF_FALSE, // allow_extract
                            QPDF_TRUE, // allow_assemble
                            QPDF_TRUE, // allow_annotate_and_form
                            QPDF_TRUE, // allow_form_filling
                            QPDF_TRUE, // allow_modify_other
                            allowsPrinting ? qpdf_r3p_full : qpdf_r3p_none,
                            QPDF_TRUE // encrypt_metadata
                        )
                    }
                }
            }
        }
        guard let encrypted = result else {
            throw QPDFServiceError.cannotOpenSourcePDF
        }
        return encrypted
    }

    /// Strips catalog-level auto-run actions (`/OpenAction`, `/AA`) and the
    /// document-wide JavaScript and embedded-file name trees (`/Names
    /// /JavaScript`, `/Names/EmbeddedFiles`) that make a PDF "active" rather
    /// than an inert document. Optionally also strips the `/Info` dictionary
    /// and XMP metadata stream (`/Metadata`) so the exported file carries no
    /// author/producer/history trail.
    ///
    /// This only removes catalog-level actions and name trees, not per-page
    /// or per-annotation actions (e.g. a link annotation's own `/A` entry) --
    /// good enough for "make this safe to share" but not a forensic sanitizer.
    static func sanitized(_ data: Data, removingMetadata: Bool) -> Data? {
        withQPDF(data, description: "sanitize") { qpdf in
            guard hasErrors(qpdf_check_pdf(qpdf)) == false else { return nil }

            let root = qpdf_get_root(qpdf)
            removeKey(qpdf, from: root, key: "/OpenAction")
            removeKey(qpdf, from: root, key: "/AA")
            if hasKey(qpdf, root, "/Names") {
                let names = qpdf_oh_get_key(qpdf, root, "/Names")
                removeKey(qpdf, from: names, key: "/JavaScript")
                removeKey(qpdf, from: names, key: "/EmbeddedFiles")
            }
            if removingMetadata {
                removeKey(qpdf, from: qpdf_get_trailer(qpdf), key: "/Info")
                removeKey(qpdf, from: root, key: "/Metadata")
            }

            return write(qpdf) { _ in }
        }
    }

    // MARK: - Private helpers

    private static func hasKey(_ qpdf: qpdf_data, _ oh: qpdf_oh, _ key: String) -> Bool {
        key.withCString { qpdf_oh_has_key(qpdf, oh, $0) != QPDF_FALSE }
    }

    private static func removeKey(_ qpdf: qpdf_data, from oh: qpdf_oh, key: String) {
        key.withCString { qpdf_oh_remove_key(qpdf, oh, $0) }
    }

    private static func hasErrors(_ code: QPDF_ERROR_CODE) -> Bool {
        (code & QPDF_ERRORS) != 0
    }

    /// Opens `data` as a qpdf instance (with automatic recovery attempted),
    /// runs `body`, and guarantees cleanup. `body` returns `nil` to signal
    /// the operation could not be completed; the qpdf handle is always freed.
    private static func withQPDF<T>(
        _ data: Data,
        description: String,
        password: String? = nil,
        _ body: (qpdf_data) -> T?
    ) -> T? {
        guard !data.isEmpty, data.count <= Int(Int32.max) else { return nil }
        var qpdf = qpdf_init()
        defer { qpdf_cleanup(&qpdf) }
        guard let qpdf else { return nil }

        qpdf_set_suppress_warnings(qpdf, QPDF_TRUE)
        qpdf_set_attempt_recovery(qpdf, QPDF_TRUE)

        let readErrors: Bool = data.withUnsafeBytes { rawBuffer -> Bool in
            guard let baseAddress = rawBuffer.bindMemory(to: CChar.self).baseAddress else { return true }
            let code = description.withCString { descriptionPtr in
                if let password {
                    return password.withCString { passwordPtr in
                        qpdf_read_memory(qpdf, descriptionPtr, baseAddress, UInt64(data.count), passwordPtr)
                    }
                }
                return qpdf_read_memory(qpdf, descriptionPtr, baseAddress, UInt64(data.count), nil)
            }
            return hasErrors(code)
        }
        guard !readErrors else { return nil }

        return body(qpdf)
    }

    /// Configures write parameters via `configure`, writes to an in-memory
    /// buffer, and returns the resulting bytes, or `nil` on failure.
    ///
    /// `qpdf_init_write_memory` must be called *before* any write-parameter
    /// function (encryption, linearization, object-stream mode) -- it resets
    /// whatever was set earlier, so setting parameters first is a silent
    /// no-op at best and an unspecified-behavior crash at worst.
    private static func write(_ qpdf: qpdf_data, configure: (qpdf_data) -> Void) -> Data? {
        guard hasErrors(qpdf_init_write_memory(qpdf)) == false else { return nil }
        configure(qpdf)
        guard hasErrors(qpdf_write(qpdf)) == false else { return nil }

        let length = qpdf_get_buffer_length(qpdf)
        guard length > 0, let buffer = qpdf_get_buffer(qpdf) else { return nil }
        return Data(bytes: buffer, count: length)
    }
}
