import Foundation

/// Export bytes whose live annotations — signatures, stamps, markup, form fields — have
/// already been flattened into page content by the export assembly.
///
/// This exists to make one precondition unforgettable. Imposition MUST run on flattened
/// bytes: `FPDF_ImportNPagesToOne` rebuilds pages as form XObjects and drops any annotation
/// still live. The result is a structurally valid PDF, so nothing throws and nothing warns —
/// the stamps and signatures are simply gone. A structural-soundness check cannot catch it,
/// because the output IS sound.
///
/// Stated as a comment, that rule was restated in four places and enforced in none. Stated as
/// a type, a caller cannot hand `impose` live document bytes by accident: they have to write
/// `alreadyFlattened:` and mean it.
struct BakedPDFData {
    let bytes: Data

    /// Asserts that the export bake has already run over `bytes`.
    ///
    /// The export assembly (`WorkspaceDocument.exportedPDFDataThrowing`) is the normal
    /// source. Tests exercising imposition in isolation construct one directly, over
    /// fixtures that carry no annotations and so have nothing to lose.
    init(alreadyFlattened bytes: Data) {
        self.bytes = bytes
    }

    /// Applies a page-content pass that preserves flattening — compression, attachment
    /// re-injection — so the bytes stay imposable by construction rather than by the
    /// caller remembering to re-wrap them.
    func mapping(_ transform: (Data) throws -> Data) rethrows -> BakedPDFData {
        BakedPDFData(alreadyFlattened: try transform(bytes))
    }
}
