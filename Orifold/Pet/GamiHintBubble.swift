import SwiftUI

/// The Gami hint bubble: a light, professional contextual hint — not a modal, not a
/// debug tooltip. Used for both feature-event hints and the hover tip, replacing the
/// two previously-duplicated bubble call sites so they share one visual and one set
/// of accessibility/motion/contrast rules.
struct GamiHintBubble: View {
    let message: String
    /// Which edge the anchor notch points from, toward the chip. `nil` omits the
    /// notch entirely (e.g. the collapsed/repositioned states where it wouldn't
    /// point at anything meaningful).
    var notchEdge: GamiNotchEdge?
    /// Sticky hints (e.g. warnings) get an explicit close affordance instead of
    /// relying purely on the auto-dismiss timer, and become hit-testable.
    var isSticky: Bool = false
    var onDismiss: (() -> Void)?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var feedbackURL: URL? {
        guard message.contains("umangdhawan97@gmail.com") else { return nil }
        return URL(string: "mailto:umangdhawan97@gmail.com")
    }

    static let maxWidth: CGFloat = 280
    static let minWidth: CGFloat = 120
    private static let notchSize = CGSize(width: 10, height: 5)

    var body: some View {
        HStack(alignment: .top, spacing: .dsSM) {
            Group {
                if let feedbackURL {
                    Link(destination: feedbackURL) { bubbleText }
                } else {
                    bubbleText
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isSticky, let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.dsTextSecondary)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("gami.bubble.dismiss")
            }
        }
        .padding(.horizontal, .dsMD)
        .padding(.vertical, 10)
        .frame(minWidth: Self.minWidth, maxWidth: Self.maxWidth, alignment: .leading)
        .background(alignment: .center) {
            surface.clipShape(RoundedRectangle(cornerRadius: .dsRadiusMd, style: .continuous))
        }
        .overlay {
            RoundedRectangle(cornerRadius: .dsRadiusMd, style: .continuous)
                .strokeBorder(Color.dsSeparator.opacity(colorScheme == .dark ? 0.7 : 0.9), lineWidth: 1)
        }
        .overlay(alignment: notchAlignment) {
            if let notchEdge {
                notch(for: notchEdge)
            }
        }
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.24 : 0.10), radius: 10, x: 0, y: 4)
        .allowsHitTesting(isSticky)
    }

    private var bubbleText: some View {
        Text(message)
            .font(.system(size: 12, weight: .regular))
            .lineSpacing(3.5)
            .foregroundStyle(Color.dsTextPrimary)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var surface: some View {
        if reduceTransparency {
            Color.dsSurface.opacity(colorScheme == .dark ? 0.98 : 0.99)
        } else {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Color.dsSurface.opacity(colorScheme == .dark ? 0.55 : 0.42)
            }
        }
    }

    private var notchAlignment: Alignment {
        switch notchEdge {
        case .bottom: return .bottom
        case .trailing: return .trailing
        case nil: return .center
        }
    }

    @ViewBuilder
    private func notch(for edge: GamiNotchEdge) -> some View {
        let fill = reduceTransparency
            ? Color.dsSurface.opacity(colorScheme == .dark ? 0.98 : 0.99)
            : Color.dsSurface.opacity(colorScheme == .dark ? 0.65 : 0.55)
        switch edge {
        case .bottom:
            NotchTriangle(pointing: .down)
                .fill(fill)
                .frame(width: Self.notchSize.width, height: Self.notchSize.height)
                .offset(x: -.dsLG, y: Self.notchSize.height)
        case .trailing:
            NotchTriangle(pointing: .right)
                .fill(fill)
                .frame(width: Self.notchSize.height, height: Self.notchSize.width)
                .offset(x: Self.notchSize.height, y: 0)
        }
    }

    /// Auto-dismiss duration scaled to message length, so longer translated strings
    /// get enough time to read: a floor of 4s plus ~0.12s per word, capped at +3s.
    static func displayDuration(for message: String) -> TimeInterval {
        let wordCount = message.split(separator: " ").count
        return 4.0 + min(3.0, Double(wordCount) * 0.12)
    }
}

/// A tiny folded-paper triangle used as the bubble's anchor notch.
private struct NotchTriangle: Shape {
    enum Direction { case down, right }
    var pointing: Direction

    func path(in rect: CGRect) -> Path {
        var path = Path()
        switch pointing {
        case .down:
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        case .right:
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        }
        path.closeSubpath()
        return path
    }
}
