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
    static let annotationKey = "/OrifoldBakeStamp"

    /// True for the invisible bake-stamp annotation. The stamp is a FreeText annotation (the
    /// only reliably round-tripping way to carry a custom key), so every markup check that
    /// keys off `type == "FreeText"` must exclude it — it is engine bookkeeping, not user
    /// markup, and must never count as an edit, list row, or reason to drop a source payload.
    static func isStamp(_ annotation: PDFAnnotation) -> Bool {
        annotation.value(forAnnotationKey: PDFAnnotationKey(rawValue: annotationKey)) != nil
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
}
