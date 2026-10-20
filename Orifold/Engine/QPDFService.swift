import CQPDF
import Darwin
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

    /// Workspace consumers operate on readable bytes without retaining an import password.
    static func decrypted(_ data: Data, password: String) -> Data? {
        withQPDF(data, description: "unlock-workspace", password: password) { qpdf in
            guard !hasErrors(qpdf_check_pdf(qpdf)) else { return nil }
            return write(qpdf) { qpdf_set_preserve_encryption($0, QPDF_FALSE) }
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

    /// True when the document catalog carries an XMP metadata stream
    /// (`/Metadata`). The Info-dict editor edits only `/Info`, so the UI uses
    /// this to warn that a separate XMP packet may still repeat old values.
    static func hasXMPMetadata(_ data: Data, password: String? = nil) -> Bool {
        withQPDF(data, description: "xmp-probe", password: password) { qpdf in
            qpdf_oh_has_key(qpdf, qpdf_get_root(qpdf), "/Metadata") == QPDF_TRUE
        } ?? false
    }

    /// True when the document catalog carries a `/PageLabels` number tree --
    /// the numbering a document prints on its own pages (roman front matter,
    /// an offprint starting at 247, an exhibit reading "A-7").
    ///
    /// This exists because `PDFPage.label` cannot be asked the question: for a
    /// document with no `/PageLabels` it *synthesizes* "1", "2", "3" rather
    /// than returning nil. A UI that shows "the label when it differs from the
    /// position" would therefore invent labels for every unlabeled member of a
    /// merged workspace. The catalog key is the only honest signal.
    static func hasPageLabels(_ data: Data) -> Bool {
        withQPDF(data, description: "page-labels-probe") { qpdf in
            qpdf_oh_has_key(qpdf, qpdf_get_root(qpdf), "/PageLabels") == QPDF_TRUE
        } ?? false
    }

    /// Carries the canonical Info dictionary and embedded-file tree across page realignment.
    /// Other catalog state and every destination page remain untouched.
    static func preservingCanonicalMetadataAndAttachments(in destinationData: Data, from sourceData: Data) -> Data? {
        withQPDF(destinationData, description: "canonical-catalog-destination") { destination in
            withQPDF(sourceData, description: "canonical-catalog-source") { source in
                guard !hasErrors(qpdf_check_pdf(destination)), !hasErrors(qpdf_check_pdf(source)) else { return nil }
                let sourceTrailer = qpdf_get_trailer(source)
                let destinationTrailer = qpdf_get_trailer(destination)
                if hasKey(source, sourceTrailer, "/Info") {
                    let info = indirectObject(qpdf_oh_get_key(source, sourceTrailer, "/Info"), in: source)
                    let copied = qpdf_oh_copy_foreign_object(destination, source, info)
                    replaceKey(destination, in: destinationTrailer, key: "/Info", value: copied)
                } else {
                    removeKey(destination, from: destinationTrailer, key: "/Info")
                }
                let sourceRoot = qpdf_get_root(source)
                let destinationRoot = qpdf_get_root(destination)
                let sourceNames = qpdf_oh_get_key(source, sourceRoot, "/Names")
                var destinationNames = qpdf_oh_get_key(destination, destinationRoot, "/Names")
                if qpdf_oh_is_dictionary(source, sourceNames) == QPDF_TRUE,
                   hasKey(source, sourceNames, "/EmbeddedFiles") {
                    if qpdf_oh_is_dictionary(destination, destinationNames) != QPDF_TRUE {
                        destinationNames = qpdf_oh_new_dictionary(destination)
                        replaceKey(destination, in: destinationRoot, key: "/Names", value: destinationNames)
                    }
                    let files = indirectObject(qpdf_oh_get_key(source, sourceNames, "/EmbeddedFiles"), in: source)
                    let copied = qpdf_oh_copy_foreign_object(destination, source, files)
                    replaceKey(destination, in: destinationNames, key: "/EmbeddedFiles", value: copied)
                } else if qpdf_oh_is_dictionary(destination, destinationNames) == QPDF_TRUE {
                    removeKey(destination, from: destinationNames, key: "/EmbeddedFiles")
                }
                guard !hasErrors(qpdf_check_pdf(destination)) else { return nil }
                return write(destination) { _ in }
            }
        }
    }

    /// Replaces only page annotations and the document AcroForm in `destinationData` with
    /// their live counterparts from `sourceData`. Page contents/resources remain those of the
    /// destination. This is the preserving bridge used after canonical edit replay: PDFKit bytes
    /// may provide live notes, signatures, and form values, but never become the destination's
    /// page-content base.
    static func replacingInteractiveState(in destinationData: Data, from sourceData: Data) -> Data? {
        withQPDF(destinationData, description: "interactive-state-destination") { destination in
            withQPDF(sourceData, description: "interactive-state-source") { source in
                guard hasErrors(qpdf_check_pdf(destination)) == false,
                      hasErrors(qpdf_check_pdf(source)) == false else { return nil }
                let destinationPageCount = qpdf_get_num_pages(destination)
                guard destinationPageCount >= 0,
                      destinationPageCount == qpdf_get_num_pages(source) else { return nil }

                for pageIndex in 0..<destinationPageCount {
                    let sourcePage = qpdf_get_page_n(source, numericCast(pageIndex))
                    let destinationPage = qpdf_get_page_n(destination, numericCast(pageIndex))
                    if hasKey(source, sourcePage, "/Annots") {
                        let sourceAnnotations = indirectObject(
                            qpdf_oh_get_key(source, sourcePage, "/Annots"),
                            in: source
                        )
                        let copiedAnnotations = qpdf_oh_copy_foreign_object(
                            destination,
                            source,
                            sourceAnnotations
                        )
                        replaceKey(destination, in: destinationPage, key: "/Annots", value: copiedAnnotations)

                        // Annotation `/P` entries must reference the destination page rather
                        // than a recursively copied source page.
                        let count = qpdf_oh_get_array_n_items(destination, copiedAnnotations)
                        if count > 0 {
                            for annotationIndex in 0..<count {
                                let annotation = qpdf_oh_get_array_item(
                                    destination,
                                    copiedAnnotations,
                                    annotationIndex
                                )
                                replaceKey(destination, in: annotation, key: "/P", value: destinationPage)
                            }
                        }
                    } else {
                        removeKey(destination, from: destinationPage, key: "/Annots")
                    }
                }

                let sourceRoot = qpdf_get_root(source)
                let destinationRoot = qpdf_get_root(destination)
                if hasKey(source, sourceRoot, "/AcroForm") {
                    let sourceForm = indirectObject(
                        qpdf_oh_get_key(source, sourceRoot, "/AcroForm"),
                        in: source
                    )
                    let copiedForm = qpdf_oh_copy_foreign_object(
                        destination,
                        source,
                        sourceForm
                    )
                    replaceKey(destination, in: destinationRoot, key: "/AcroForm", value: copiedForm)
                } else {
                    removeKey(destination, from: destinationRoot, key: "/AcroForm")
                }

                return write(destination) { _ in }
            }
        }
    }

    /// Replaces a page's drawing operators and resources while retaining the destination page
    /// object itself. Keeping that indirect object is what preserves page labels, outlines,
    /// annotations, form references, and every catalog-level feature that points at the page.
    /// The replacement PDF must contain exactly one page.
    static func replacingPageContent(
        in destinationData: Data,
        pageIndex: Int,
        with replacementPageData: Data
    ) -> Data? {
        withQPDF(destinationData, description: "page-content-destination") { destination in
            withQPDF(replacementPageData, description: "page-content-source") { source in
                guard hasErrors(qpdf_check_pdf(destination)) == false,
                      hasErrors(qpdf_check_pdf(source)) == false,
                      pageIndex >= 0,
                      pageIndex < qpdf_get_num_pages(destination),
                      qpdf_get_num_pages(source) == 1,
                      !hasErrors(qpdf_push_inherited_attributes_to_page(destination)),
                      !hasErrors(qpdf_push_inherited_attributes_to_page(source)) else { return nil }

                let destinationPage = qpdf_get_page_n(destination, numericCast(pageIndex))
                let sourcePage = qpdf_get_page_n(source, 0)
                for key in ["/Contents", "/Resources", "/Group"] {
                    if hasKey(source, sourcePage, key) {
                        let sourceValue = indirectObject(
                            qpdf_oh_get_key(source, sourcePage, key),
                            in: source
                        )
                        let copied = qpdf_oh_copy_foreign_object(destination, source, sourceValue)
                        replaceKey(destination, in: destinationPage, key: key, value: copied)
                    } else {
                        removeKey(destination, from: destinationPage, key: key)
                    }
                }
                return writeRemovingUnreferencedPageResources(destination)
            }
        }
    }

    /// Materializing inheritance removes ancestor resource dictionaries. The job's page
    /// content analysis then removes unused entries from each page's effective resources,
    /// including shared dictionaries and nested forms, while retaining resources used by
    /// unaffected pages. Otherwise a catalog graft can retain pixels removed from content.
    /// Preserve the existing catalog/page objects. The job applies this option while
    /// reading its input, so the split-stage memory writer alone cannot perform the prune.
    private static func writeRemovingUnreferencedPageResources(_ qpdf: qpdf_data) -> Data? {
        guard let source = write(qpdf, configure: { _ in }) else { return nil }
        let root = ProcessInfo.processInfo.environment["TMPDIR"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) } ?? FileManager.default.temporaryDirectory
        var template = root.appendingPathComponent("Orifold-resource-cleanup-XXXXXX").path.utf8CString
        guard let path = template.withUnsafeMutableBufferPointer({ buffer -> String? in
            guard let base = buffer.baseAddress, let created = mkdtemp(base) else { return nil }
            return String(cString: created)
        }) else { return nil }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("input.pdf")
        let output = directory.appendingPathComponent("output.pdf")
        let configuration: [String: Any] = [
            "inputFile": input.path, "outputFile": output.path,
            "removeUnreferencedResources": "yes",
            // Resource pruning is a page-selection operation. Select every original page
            // exactly once, in order, from the main input so catalog destinations stay bound.
            "pages": [["file": ".", "range": "1-z"]]
        ]
        guard FileManager.default.createFile(atPath: input.path, contents: source, attributes: [.posixPermissions: 0o600]),
              FileManager.default.createFile(atPath: output.path, contents: Data(), attributes: [.posixPermissions: 0o600]),
              let json = try? JSONSerialization.data(withJSONObject: configuration),
              let config = String(data: json, encoding: .utf8) else { return nil }
        var ownedJob = qpdfjob_init()
        var ownedLogger = qpdflogger_create()
        defer { qpdfjob_cleanup(&ownedJob); qpdflogger_cleanup(&ownedLogger) }
        guard let job = ownedJob, let logger = ownedLogger else { return nil }
        qpdflogger_set_info(logger, qpdf_log_dest_discard, nil, nil)
        qpdflogger_set_warn(logger, qpdf_log_dest_discard, nil, nil)
        qpdflogger_set_error(logger, qpdf_log_dest_discard, nil, nil)
        qpdfjob_set_logger(job, logger)
        guard config.withCString({ qpdfjob_initialize_from_json(job, $0) }) == 0,
              qpdfjob_run(job) == 0, let result = try? Data(contentsOf: output),
              !result.isEmpty, isStructurallySound(result) else { return nil }
        return result
    }

    /// Structural diagnostic for the annotation/form graft: every terminal field in
    /// `/AcroForm/Fields` must be the same indirect object reachable from a destination page's
    /// `/Annots` array. Kept internal so replay regression tests can verify identity, not merely
    /// that PDFKit happens to display a copied value.
    static func formFieldsReferencePageAnnotations(_ data: Data) -> Bool {
        withQPDF(data, description: "form-annotation-identity") { qpdf in
            let root = qpdf_get_root(qpdf)
            guard hasKey(qpdf, root, "/AcroForm") else { return true }
            let form = qpdf_oh_get_key(qpdf, root, "/AcroForm")
            guard hasKey(qpdf, form, "/Fields") else { return true }

            var pageAnnotationIDs = Set<String>()
            let pageCount = qpdf_get_num_pages(qpdf)
            guard pageCount >= 0 else { return false }
            for pageIndex in 0..<pageCount {
                let page = qpdf_get_page_n(qpdf, numericCast(pageIndex))
                guard hasKey(qpdf, page, "/Annots") else { continue }
                let annotations = qpdf_oh_get_key(qpdf, page, "/Annots")
                for annotationIndex in 0..<qpdf_oh_get_array_n_items(qpdf, annotations) {
                    let annotation = qpdf_oh_get_array_item(qpdf, annotations, annotationIndex)
                    if let identity = indirectIdentity(annotation, in: qpdf) {
                        pageAnnotationIDs.insert(identity)
                    }
                }
            }

            var fieldIDs = Set<String>()
            var visitedFieldIDs = Set<String>()
            collectTerminalFieldIDs(
                from: qpdf_oh_get_key(qpdf, form, "/Fields"),
                in: qpdf,
                into: &fieldIDs,
                visited: &visitedFieldIDs,
                depth: 0
            )
            return !fieldIDs.isEmpty && fieldIDs.isSubset(of: pageAnnotationIDs)
        } ?? false
    }

    // MARK: - Private helpers

    /// `internal` for the same reason `withQPDF` is: sibling engine services in this
    /// module — `ArchivalReadinessService` — need the identical key probe, and a second
    /// copy would be one more place for the `QPDF_FALSE` comparison to drift.
    static func hasKey(_ qpdf: qpdf_data, _ oh: qpdf_oh, _ key: String) -> Bool {
        key.withCString { qpdf_oh_has_key(qpdf, oh, $0) != QPDF_FALSE }
    }

    private static func removeKey(_ qpdf: qpdf_data, from oh: qpdf_oh, key: String) {
        key.withCString { qpdf_oh_remove_key(qpdf, oh, $0) }
    }

    static func replaceKey(_ qpdf: qpdf_data, in oh: qpdf_oh, key: String, value: qpdf_oh) {
        key.withCString { qpdf_oh_replace_key(qpdf, oh, $0, value) }
    }

    /// qpdf can copy only indirect objects across documents. PDF permits `/Annots` arrays and
    /// `/AcroForm` dictionaries to be direct, so promote those legal containers in the temporary
    /// source instance before asking qpdf to copy them.
    private static func indirectObject(_ object: qpdf_oh, in qpdf: qpdf_data) -> qpdf_oh {
        qpdf_oh_is_indirect(qpdf, object) != QPDF_FALSE
            ? object
            : qpdf_make_indirect_object(qpdf, object)
    }

    private static func collectTerminalFieldIDs(
        from fields: qpdf_oh,
        in qpdf: qpdf_data,
        into identities: inout Set<String>,
        visited: inout Set<String>,
        depth: Int
    ) {
        guard depth < 64, qpdf_oh_is_array(qpdf, fields) != QPDF_FALSE else { return }
        for index in 0..<qpdf_oh_get_array_n_items(qpdf, fields) {
            let field = qpdf_oh_get_array_item(qpdf, fields, index)
            if let identity = indirectIdentity(field, in: qpdf),
               !visited.insert(identity).inserted {
                continue
            }
            if hasKey(qpdf, field, "/Kids") {
                collectTerminalFieldIDs(
                    from: qpdf_oh_get_key(qpdf, field, "/Kids"),
                    in: qpdf,
                    into: &identities,
                    visited: &visited,
                    depth: depth + 1
                )
            } else if let identity = indirectIdentity(field, in: qpdf) {
                identities.insert(identity)
            }
        }
    }

    private static func indirectIdentity(_ object: qpdf_oh, in qpdf: qpdf_data) -> String? {
        let objectID = qpdf_oh_get_object_id(qpdf, object)
        guard objectID > 0 else { return nil }
        return "\(objectID):\(qpdf_oh_get_generation(qpdf, object))"
    }

    static func hasErrors(_ code: QPDF_ERROR_CODE) -> Bool {
        (code & QPDF_ERRORS) != 0
    }

    /// Opens `data` as a qpdf instance (with automatic recovery attempted),
    /// runs `body`, and guarantees cleanup. `body` returns `nil` to signal
    /// the operation could not be completed; the qpdf handle is always freed.
    ///
    /// `internal` (not `private`) so sibling engine services in this module --
    /// e.g. `PDFMetadataService` -- can reuse the exact open/recover/cleanup
    /// lifecycle instead of writing a second one.
    static func withQPDF<T>(
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
    ///
    /// `internal` (not `private`) so sibling engine services in this module --
    /// e.g. `PDFMetadataService` -- can reuse the exact serialization sequence
    /// instead of writing a second one.
    static func write(_ qpdf: qpdf_data, configure: (qpdf_data) -> Void) -> Data? {
        guard hasErrors(qpdf_init_write_memory(qpdf)) == false else { return nil }
        configure(qpdf)
        guard hasErrors(qpdf_write(qpdf)) == false else { return nil }

        let length = qpdf_get_buffer_length(qpdf)
        guard length > 0, let buffer = qpdf_get_buffer(qpdf) else { return nil }
        return Data(bytes: buffer, count: length)
    }
}
