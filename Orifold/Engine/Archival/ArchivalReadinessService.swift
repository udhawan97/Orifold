import CQPDF
import Foundation

/// Cheap introspection signals about how well a document would survive long-term
/// archiving.
///
/// Every field is a *hint*. This is emphatically not PDF/A validation — that is hundreds
/// of clauses — and no consumer may present it as one. False positives are acceptable
/// here precisely because the output is advisory; a flagged document is worth a look, not
/// condemned.
struct ArchivalReadiness: Equatable {
    /// PDF/A forbids encryption outright, so any encryption is a hint against archiving.
    var isEncrypted: Bool
    /// `/OpenAction`, `/AA`, or `/Names/JavaScript` — the same keys the sanitizer strips.
    var hasActiveContent: Bool
    /// False as soon as one font is referenced without an embedded file.
    var allFontsEmbedded: Bool
    /// `/Root/OutputIntents` with at least one entry — colour is reproducible later.
    var hasOutputIntent: Bool
    var hasXMPMetadata: Bool
    var isTagged: Bool
}

/// Read-only. Opens the bytes, reads a handful of catalog and page signals, mutates
/// nothing.
enum ArchivalReadinessService {

    /// Bounds the page-tree descent, matching the field-walk cap in `QPDFService`.
    private static let maximumDepth = 64

    /// Returns nil when the bytes cannot be read at all.
    ///
    /// Deliberately nil rather than a default-constructed value: an all-green checklist
    /// for a document that could not even be parsed would be the worst failure mode this
    /// panel has.
    static func evaluate(_ data: Data, password: String? = nil) -> ArchivalReadiness? {
        QPDFService.withQPDF(data, description: "archival-readiness", password: password) { qpdf in
            let root = qpdf_get_root(qpdf)

            return ArchivalReadiness(
                isEncrypted: qpdf_is_encrypted(qpdf) != QPDF_FALSE,
                hasActiveContent: hasActiveContent(qpdf, root: root),
                allFontsEmbedded: allFontsEmbedded(qpdf, root: root),
                hasOutputIntent: hasOutputIntent(qpdf, root: root),
                hasXMPMetadata: QPDFService.hasKey(qpdf, root, "/Metadata"),
                isTagged: isTagged(data, qpdf: qpdf, root: root)
            )
        }
    }

    // MARK: - Signals

    private static func hasActiveContent(_ qpdf: qpdf_data, root: qpdf_oh) -> Bool {
        if QPDFService.hasKey(qpdf, root, "/OpenAction") { return true }
        if QPDFService.hasKey(qpdf, root, "/AA") { return true }
        guard QPDFService.hasKey(qpdf, root, "/Names") else { return false }
        let names = qpdf_oh_get_key(qpdf, root, "/Names")
        return QPDFService.hasKey(qpdf, names, "/JavaScript")
    }

    private static func hasOutputIntent(_ qpdf: qpdf_data, root: qpdf_oh) -> Bool {
        guard QPDFService.hasKey(qpdf, root, "/OutputIntents") else { return false }
        let intents = qpdf_oh_get_key(qpdf, root, "/OutputIntents")
        guard qpdf_oh_is_array(qpdf, intents) != QPDF_FALSE else { return false }
        return qpdf_oh_get_array_n_items(qpdf, intents) > 0
    }

    /// Prefers PDFium's catalog flag and falls back to the raw `/MarkInfo /Marked` entry
    /// when the document will not load through PDFium — the two disagree rarely, but a
    /// document qpdf can read and PDFium cannot should still report its tagging honestly.
    private static func isTagged(_ data: Data, qpdf: qpdf_data, root: qpdf_oh) -> Bool {
        if StructureInspectionService.documentIsTagged(data) { return true }
        guard QPDFService.hasKey(qpdf, root, "/MarkInfo") else { return false }
        let markInfo = qpdf_oh_get_key(qpdf, root, "/MarkInfo")
        guard QPDFService.hasKey(qpdf, markInfo, "/Marked") else { return false }
        return qpdf_oh_get_bool_value(qpdf, qpdf_oh_get_key(qpdf, markInfo, "/Marked")) != QPDF_FALSE
    }

    // MARK: - Font walk

    /// Walks every page's `/Resources /Font` and returns false on the first font with no
    /// embedded file.
    ///
    /// Standard-14 fonts legitimately carry no FontDescriptor, and PDF/A still requires
    /// them to be embedded — so reporting Helvetica as unembedded is the correct hint,
    /// not a false positive.
    private static func allFontsEmbedded(_ qpdf: qpdf_data, root: qpdf_oh) -> Bool {
        guard QPDFService.hasKey(qpdf, root, "/Pages") else { return true }
        var allEmbedded = true
        walkPages(qpdf, node: qpdf_oh_get_key(qpdf, root, "/Pages"), depth: 0) { page in
            if !pageFontsEmbedded(qpdf, page: page) { allEmbedded = false }
        }
        return allEmbedded
    }

    /// `/Resources` may be inherited from an ancestor `/Pages` node rather than sitting on
    /// the leaf, so a walk that only reads the page's own dictionary silently reports
    /// "no fonts" for a large class of real documents. Inherited resources are resolved by
    /// passing the nearest ancestor's down.
    private static func walkPages(
        _ qpdf: qpdf_data,
        node: qpdf_oh,
        depth: Int,
        inherited: qpdf_oh? = nil,
        visit: (qpdf_oh) -> Void
    ) {
        guard depth < maximumDepth else { return }

        let resources = QPDFService.hasKey(qpdf, node, "/Resources")
            ? qpdf_oh_get_key(qpdf, node, "/Resources")
            : inherited

        guard QPDFService.hasKey(qpdf, node, "/Kids") else {
            visit(resources ?? node)
            return
        }

        let kids = qpdf_oh_get_key(qpdf, node, "/Kids")
        guard qpdf_oh_is_array(qpdf, kids) != QPDF_FALSE else { return }
        for index in 0..<qpdf_oh_get_array_n_items(qpdf, kids) {
            walkPages(
                qpdf,
                node: qpdf_oh_get_array_item(qpdf, kids, index),
                depth: depth + 1,
                inherited: resources,
                visit: visit
            )
        }
    }

    private static func pageFontsEmbedded(_ qpdf: qpdf_data, page resources: qpdf_oh) -> Bool {
        guard QPDFService.hasKey(qpdf, resources, "/Font") else { return true }
        let fonts = qpdf_oh_get_key(qpdf, resources, "/Font")
        guard qpdf_oh_is_dictionary(qpdf, fonts) != QPDF_FALSE else { return true }

        var embedded = true
        qpdf_oh_begin_dict_key_iter(qpdf, fonts)
        while qpdf_oh_dict_more_keys(qpdf) != QPDF_FALSE {
            guard let name = qpdf_oh_dict_next_key(qpdf) else { continue }
            let font = qpdf_oh_get_key(qpdf, fonts, name)
            if !fontIsEmbedded(qpdf, font: font, depth: 0) { embedded = false }
        }
        return embedded
    }

    private static func fontIsEmbedded(_ qpdf: qpdf_data, font: qpdf_oh, depth: Int) -> Bool {
        guard depth < maximumDepth else { return true }

        // Type0 fonts keep their descriptor on the descendant CIDFont, not on themselves.
        if QPDFService.hasKey(qpdf, font, "/DescendantFonts") {
            let descendants = qpdf_oh_get_key(qpdf, font, "/DescendantFonts")
            guard qpdf_oh_is_array(qpdf, descendants) != QPDF_FALSE else { return false }
            for index in 0..<qpdf_oh_get_array_n_items(qpdf, descendants)
            where !fontIsEmbedded(qpdf, font: qpdf_oh_get_array_item(qpdf, descendants, index), depth: depth + 1) {
                return false
            }
            return true
        }

        guard QPDFService.hasKey(qpdf, font, "/FontDescriptor") else { return false }
        let descriptor = qpdf_oh_get_key(qpdf, font, "/FontDescriptor")
        return QPDFService.hasKey(qpdf, descriptor, "/FontFile")
            || QPDFService.hasKey(qpdf, descriptor, "/FontFile2")
            || QPDFService.hasKey(qpdf, descriptor, "/FontFile3")
    }
}
