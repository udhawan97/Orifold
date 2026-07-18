import CryptoKit
import Foundation
import PDFKit

/// Deterministic hash of a page's committed inline-text-edit operations, written onto the
/// regenerated page bytes as an invisible `/OrifoldBakeStamp` annotation. It records *which
/// exact operations the current bytes were baked from*, so a later session can tell whether
/// a page's bytes are in sync with its operations without re-rendering:
///
/// - stamp on the page == hash of the page's operations  → bytes are current, skip.
/// - stamp missing, or != hash of the operations          → operations changed (or a bake
///   went missing) since these bytes were written → regenerate.
///
/// Because the stamp lives with the *bytes* and the hash is recomputed from the *operations*,
/// it detects style-only stale bakes that the text-presence fallback cannot (a restyle that
/// never re-baked leaves identical visible text but a different operation set).
enum BakeStamp {
    /// The annotation key as PDFium takes it: raw, no leading slash.
    static let pdfiumAnnotationKey = "OrifoldBakeStamp"

    /// The same key as PDFKit spells it — PDFKit prefixes annotation keys with a slash,
    /// PDFium does not. DERIVED rather than written out again: the stamp is written through
    /// PDFium and read back through PDFKit, so two independently-spelled constants would be
    /// linked only by an unwritten "minus the slash" rule, and renaming one would leave
    /// stamps written but never detected — every reconcile silently falling back to
    /// text-presence, or re-baking every page.
    static let annotationKey = "/" + pdfiumAnnotationKey

    /// FreeText, in PDFium's annotation-subtype numbering. The stamp must be a FreeText
    /// annotation because it is the only subtype that reliably round-trips a custom key.
    static let pdfiumFreeTextSubtype: Int32 = 3

    /// Off-page and sub-point, so the stamp is never visible, clickable, or printable.
    /// Shared by both writers so the convention is defined once.
    static let bounds = CGRect(x: -10, y: -10, width: 1, height: 1)

    /// True for the invisible bake-stamp annotation. The stamp is a FreeText annotation (the
    /// only reliably round-tripping way to carry a custom key), so every markup check that
    /// keys off `type == "FreeText"` must exclude it — it is engine bookkeeping, not user
    /// markup, and must never count as an edit, list row, or reason to drop a source payload.
    static func isStamp(_ annotation: PDFAnnotation) -> Bool {
        annotation.value(forAnnotationKey: PDFAnnotationKey(rawValue: annotationKey)) != nil
    }

    /// Every annotation on `page` that is genuine user markup — the stamp excluded.
    /// Prefer this over walking `page.annotations` directly: the exclusion is the kind of
    /// step a new scan forgets, and forgetting it counts engine bookkeeping as a user edit.
    static func userAnnotations(on page: PDFPage) -> [PDFAnnotation] {
        page.annotations.filter { !isStamp($0) }
    }

    /// SHA-256 hex of a canonical, order-independent encoding of `operations`. Sorted by id
    /// so array ordering never affects the result; encoded with sorted JSON keys so the
    /// encoding is stable across runs. Every persisted field participates, INCLUDING `id`,
    /// `createdAt`, and `modifiedAt` — those three get fresh values on every re-edit rather
    /// than being carried over from an existing op (see `applyInlineTextEdit`'s merge block
    /// in `WorkspaceViewModel`), so in isolation this is not a hash of "meaningful content
    /// changed," it also reflects "an edit was (re-)committed at all."
    ///
    /// That distinction is harmless in practice: the stamp is always recomputed from, and
    /// attached to, this SAME `operations` value in the SAME commit that changes it
    /// (`regenerateEditedPage` calls this immediately before writing the stamp), so
    /// bake-time and every later reconcile-time read of `operations` — same session, saved
    /// and reloaded, or restored from undo — always see identical id/timestamp fields for a
    /// given edit state. There is no code path where the identity fields differ between
    /// when the stamp was written and when it's later compared, so their churn never causes
    /// a stale-trusted or wrongly-invalidated bake (see
    /// `testReEditingTheSameBlockChurnsIdentityFieldsButReconcilesCleanly`).
    static func hash(for operations: [PDFTextEditOperation]) -> String {
        let sorted = operations.sorted { $0.id.uuidString < $1.id.uuidString }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(sorted) else {
            // Encoding a Codable array of value types does not realistically fail; if it
            // ever did, fall back to a value that never matches a real stamp so reconcile
            // errs toward regenerating rather than trusting a stale bake.
            return "unencodable-\(operations.count)"
        }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Hashes both committed editing lanes for a page. Text-only stamps retain their
    /// historical value so existing workspaces do not need a gratuitous one-time rebake.
    static func hash(textOperations: [PDFTextEditOperation], objectOperations: [ObjectEditOperation]) -> String {
        guard !objectOperations.isEmpty else { return hash(for: textOperations) }
        let text = textOperations.sorted { $0.id.uuidString < $1.id.uuidString }
        let objects = objectOperations.sorted { $0.id.uuidString < $1.id.uuidString }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let textData = try? encoder.encode(text),
              let objectData = try? encoder.encode(objects) else {
            return "unencodable-\(textOperations.count)-\(objectOperations.count)"
        }
        var canonical = Data("orifold-combined-edit-v1\n".utf8)
        canonical.append(textData)
        canonical.append(0)
        canonical.append(objectData)
        return SHA256.hash(data: canonical).map { String(format: "%02x", $0) }.joined()
    }

    /// Writes an invisible stamp annotation for the exact operation set baked into a page,
    /// through the PDFKit lane. Production bakes go through PDFium
    /// (`PDFReplayMetadataEngine.finalize`), which is the writer that runs on real edits;
    /// this is the PDFKit-side counterpart, and both take their key, subtype and bounds from
    /// the constants above so the two lanes cannot encode the convention differently.
    static func attach(_ hash: String, to page: PDFPage) {
        let annotation = PDFAnnotation(
            bounds: bounds,
            forType: .freeText,
            withProperties: nil
        )
        annotation.color = .clear
        annotation.fontColor = .clear
        annotation.contents = nil
        annotation.setValue(hash, forAnnotationKey: PDFAnnotationKey(rawValue: annotationKey))
        page.addAnnotation(annotation)
    }

    /// Returns the first Orifold bake stamp carried by `page`.
    static func value(on page: PDFPage) -> String? {
        page.annotations.lazy.compactMap { annotation -> String? in
            guard isStamp(annotation) else { return nil }
            return annotation.value(forAnnotationKey: PDFAnnotationKey(rawValue: annotationKey)) as? String
        }.first
    }
}
