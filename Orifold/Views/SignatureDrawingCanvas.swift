import SwiftUI
import AppKit

/// A minimal freehand signature canvas: captures mouse-drag strokes as vector paths and
/// renders them to a transparent PNG on demand — the same "ink on transparent" convention
/// `SignatureImageRenderer` uses for typed/initials signatures, so a drawn signature
/// composites onto a page the same way.
struct SignatureDrawingCanvas: NSViewRepresentable {
    @Binding var clearTrigger: Int
    /// The rendered PNG (nil when there are no completed strokes yet). Callers derive
    /// "has strokes" from `!= nil` instead of tracking a second, always-redundant flag —
    /// this and stroke-emptiness always change together, since both are only ever reported
    /// from the same `mouseUp`/`clear` call sites below.
    var onImageRendered: (Data?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onImageRendered: onImageRendered)
    }

    func makeNSView(context: Context) -> DrawingCanvasView {
        let view = DrawingCanvasView()
        view.coordinator = context.coordinator
        context.coordinator.lastClearTrigger = clearTrigger
        return view
    }

    func updateNSView(_ nsView: DrawingCanvasView, context: Context) {
        guard context.coordinator.lastClearTrigger != clearTrigger else { return }
        context.coordinator.lastClearTrigger = clearTrigger
        nsView.clear()
    }

    @MainActor
    final class Coordinator {
        let onImageRendered: (Data?) -> Void
        var lastClearTrigger = 0

        init(onImageRendered: @escaping (Data?) -> Void) {
            self.onImageRendered = onImageRendered
        }
    }
}

final class DrawingCanvasView: NSView {
    var coordinator: SignatureDrawingCanvas.Coordinator?
    private var strokes: [NSBezierPath] = []
    private var currentStroke: NSBezierPath?

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        bounds.fill()
        NSColor.black.setStroke()
        for stroke in strokes {
            stroke.lineWidth = 2.6
            stroke.lineCapStyle = .round
            stroke.lineJoinStyle = .round
            stroke.stroke()
        }
        currentStroke?.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        let path = NSBezierPath()
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.move(to: convert(event.locationInWindow, from: nil))
        currentStroke = path
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let currentStroke else { return }
        currentStroke.line(to: convert(event.locationInWindow, from: nil))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let currentStroke else { return }
        strokes.append(currentStroke)
        self.currentStroke = nil
        coordinator?.onImageRendered(renderPNG())
    }

    func clear() {
        strokes.removeAll()
        currentStroke = nil
        needsDisplay = true
        coordinator?.onImageRendered(nil)
    }

    /// Renders the captured strokes into a fresh transparent-background bitmap — never by
    /// re-decoding a lossy on-screen snapshot — matching `SignatureImageRenderer`'s own
    /// manual `NSBitmapImageRep` + `NSGraphicsContext` approach (an `NSImage(size:).lockFocus()`
    /// + `tiffRepresentation` path can silently fail to finalize a transparent TIFF here).
    func renderPNG() -> Data? {
        guard !strokes.isEmpty, bounds.width > 0, bounds.height > 0 else { return nil }
        let size = bounds.size
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width),
            pixelsHigh: Int(size.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        NSGraphicsContext.current = context

        NSColor.clear.setFill()
        NSRect(origin: .zero, size: size).fill()
        NSColor.black.setStroke()
        for stroke in strokes {
            stroke.lineWidth = 2.6
            stroke.stroke()
        }

        return bitmap.representation(using: .png, properties: [:])
    }
}
