import AppKit

/// The primary document-window contract. Keep these values centralized so the
/// SwiftUI scene, AppKit restoration repair, and regression tests cannot drift.
enum PrimaryWindowSizing {
    static let defaultContentSize = NSSize(width: 980, height: 720)
    static let minimumContentSize = NSSize(width: 641, height: 500)

    static func clampedContentSize(_ size: NSSize) -> NSSize {
        NSSize(
            width: max(size.width, minimumContentSize.width),
            height: max(size.height, minimumContentSize.height)
        )
    }

    /// SwiftUI applies the minimum during normal resizing. This AppKit guard also
    /// repairs an invalid tiny frame restored by macOS or inherited from an older
    /// build, without changing any already-usable user-selected size.
    @MainActor
    static func configure(_ window: NSWindow?) {
        guard let window else { return }
        window.contentMinSize = minimumContentSize

        let currentSize = window.contentLayoutRect.size
        let clampedSize = clampedContentSize(currentSize)
        guard clampedSize != currentSize else { return }
        window.setContentSize(clampedSize)
    }
}
