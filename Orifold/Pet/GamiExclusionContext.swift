import CoreGraphics

/// Rects (in the companion overlay's coordinate space) that a Gami hint bubble must
/// never cover: selected PDF text, an active edit box and its handles, search
/// highlights, and static chrome like the toolbar or the export progress bar.
///
/// Deliberately a plain value type with no SwiftUI/AppKit dependency, so
/// `GamiPlacementResolver` stays pure and unit-testable. Callers collect these
/// lazily, only when a hint is about to show — there is no continuous observation.
struct GamiExclusionContext {
    var selectionRects: [CGRect] = []
    var activeEditRect: CGRect?
    var searchHighlightRect: CGRect?
    var chromeRects: [CGRect] = []

    /// All zones flattened into one array for the resolver.
    var allRects: [CGRect] {
        var rects = selectionRects
        if let activeEditRect { rects.append(activeEditRect) }
        if let searchHighlightRect { rects.append(searchHighlightRect) }
        rects.append(contentsOf: chromeRects)
        return rects
    }

    static let empty = GamiExclusionContext()
}
