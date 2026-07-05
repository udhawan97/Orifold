import SwiftUI
import AppKit

/// Landing-screen brand moment: a clean sheet of paper folds — beak, tail, then a
/// sweeping wing — into a small origami crane silhouette, then gently dissolves away
/// so the real app icon (`AppIconMark`) can materialize on the same tile.
///
/// The crane is drawn as a single morphing silhouette in a `Canvas`: each of its seven
/// outline points starts exactly on the flat square's perimeter (so frame one reads as
/// a plain sheet of paper) and travels to its final position on its own staggered
/// schedule, choreographed with `KeyframeAnimator`. Crease lines fade in per phase to
/// keep the "folded paper" read even though, under the hood, it's a vertex morph
/// rather than a physical fold simulation.
///
/// The hand-off to the finished logo is sequenced, not crossfaded: the crane fully
/// dissolves first, then the icon materializes on a tile drawn to match the icon's
/// real background, so two different shapes never overlap mid-transition. It settles
/// into a barely perceptible idle breath rather than looping.
///
/// A short beat after the view appears the fold plays automatically; tapping the mark
/// replays it. With Reduce Motion the animation is skipped entirely and the finished
/// logo is shown immediately, so the screen is complete and polished with no motion.
struct OrifoldFoldMark: View {
    var size: CGFloat = 80

    /// Delay before the fold plays on first appearance, so the screen settles first.
    private let autoplayDelay: TimeInterval = 1.0
    /// Total keyframe runtime, used to time the post-resolve idle breath.
    private let animationRuntime: TimeInterval = 2.95

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var playCount = 0
    @State private var breathe = false
    @State private var didResolve = false
    @State private var replayGeneration = 0

    private var shouldReduceMotion: Bool {
        reduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    var body: some View {
        Group {
            if shouldReduceMotion {
                AppIconMark(size: size)
                    .accessibilityLabel("Orifold")
            } else {
                animated
            }
        }
        .frame(width: size, height: size)
    }

    private var animated: some View {
        Button {
            replay()
        } label: {
            KeyframeAnimator(initialValue: FoldState.start, trigger: playCount) { state in
                ZStack {
                    Canvas(opaque: false, rendersAsynchronously: true) { context, canvasSize in
                        FoldMarkRenderer.draw(in: &context, size: canvasSize, state: state)
                    }

                    AppIconMark(size: size)
                        .opacity(state.iconIn)
                }
                .scaleEffect(breathe ? 1.012 : 1.0)
            } keyframes: { _ in
                // Sheet fades and scales into place.
                KeyframeTrack(\.sheet) {
                    CubicKeyframe(1.0, duration: 0.34)
                }
                // Beak & head tuck in first.
                KeyframeTrack(\.foldBeak) {
                    LinearKeyframe(0.0, duration: 0.18)
                    CubicKeyframe(1.0, duration: 0.55)
                }
                // Then the tail point.
                KeyframeTrack(\.foldTail) {
                    LinearKeyframe(0.0, duration: 0.45)
                    CubicKeyframe(1.0, duration: 0.55)
                }
                // The wing sweeps up last — the biggest, most dramatic fold.
                KeyframeTrack(\.foldWing) {
                    LinearKeyframe(0.0, duration: 0.75)
                    CubicKeyframe(1.0, duration: 0.68)
                }
                // The back ridge settles, crisping the silhouette.
                KeyframeTrack(\.foldRidge) {
                    LinearKeyframe(0.0, duration: 1.15)
                    CubicKeyframe(1.0, duration: 0.55)
                }
                // Hold the finished crane for a beat, then dissolve it away…
                KeyframeTrack(\.paperOut) {
                    LinearKeyframe(0.0, duration: 2.05)
                    CubicKeyframe(1.0, duration: 0.38)
                }
                // …and only then materialize the finished logo on the same tile.
                KeyframeTrack(\.iconIn) {
                    LinearKeyframe(0.0, duration: 2.45)
                    CubicKeyframe(1.0, duration: 0.42)
                }
            }
        }
        .buttonStyle(.plain)
        .help("Replay the fold")
        .onAppear {
            guard playCount == 0 else { return }
            // Let the surrounding screen settle, then play the fold.
            let generation = replayGeneration
            DispatchQueue.main.asyncAfter(deadline: .now() + autoplayDelay) {
                guard generation == replayGeneration, playCount == 0 else { return }
                play()
            }
        }
        .accessibilityLabel("Orifold")
        .accessibilityHint("Replays the fold animation.")
    }

    private func replay() {
        play()
    }

    private func play() {
        replayGeneration += 1
        didResolve = false
        breathe = false
        playCount += 1
        scheduleIdleBreath()
    }

    private func scheduleIdleBreath() {
        let generation = replayGeneration
        // Settle into a slow, near-invisible idle breath once the fold resolves.
        DispatchQueue.main.asyncAfter(deadline: .now() + animationRuntime) {
            guard generation == replayGeneration, !didResolve else { return }
            didResolve = true
            withAnimation(.easeInOut(duration: 3.4).repeatForever(autoreverses: true)) {
                breathe = true
            }
        }
    }
}

// MARK: - Animation state

private struct FoldState: Equatable {
    var sheet: Double
    /// TR corner tucks into the beak + head.
    var foldBeak: Double
    /// BL corner draws out into the tail.
    var foldTail: Double
    /// TL corner sweeps up into the wing.
    var foldWing: Double
    /// Back ridge / neck notch settle into their final crease.
    var foldRidge: Double
    /// Crane dissolves away (the tile stays put).
    var paperOut: Double
    /// Finished logo materializes on top.
    var iconIn: Double

    static let start = FoldState(sheet: 0, foldBeak: 0, foldTail: 0, foldWing: 0, foldRidge: 0, paperOut: 0, iconIn: 0)
}

/// The crane's outline, as a single closed 7-point silhouette:
/// beak → head base → back ridge → wing tip → wing notch → tail tip → breast → (close).
private struct CranePoints {
    var beak: CGPoint
    var headBase: CGPoint
    var backRidge: CGPoint
    var wingTip: CGPoint
    var wingNotch: CGPoint
    var tailTip: CGPoint
    var breast: CGPoint
}

// MARK: - Renderer

private enum FoldMarkRenderer {
    static func draw(in context: inout GraphicsContext, size: CGSize, state: FoldState) {
        let side = min(size.width, size.height)
        guard side > 0 else { return }

        // Fade + subtle scale-in of the whole mark.
        context.opacity = state.sheet
        let scale = 0.92 + 0.08 * state.sheet
        let mid = CGPoint(x: size.width / 2, y: size.height / 2)
        context.translateBy(x: mid.x, y: mid.y)
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -mid.x, y: -mid.y)

        let tileRect = CGRect(x: (size.width - side) / 2, y: (size.height - side) / 2, width: side, height: side)
        let tileRadius = side * 0.22
        let tilePath = Path(roundedRect: tileRect, cornerRadius: tileRadius, style: .continuous)

        drawTile(in: &context, path: tilePath, rect: tileRect)

        // Keep the folded paper contained within the rounded tile.
        context.clip(to: tilePath)

        // The paper fades out on its own while the tile stays put, so the incoming
        // logo hands off on a steady ground rather than crossfading two shapes.
        context.opacity = state.sheet * (1 - state.paperOut)

        drawCrane(in: &context, tileRect: tileRect, side: side, state: state)
    }

    private static func drawCrane(in context: inout GraphicsContext, tileRect: CGRect, side: CGFloat, state: FoldState) {
        let inset = side * 0.19
        let paper = tileRect.insetBy(dx: inset, dy: inset)

        let tl = CGPoint(x: paper.minX, y: paper.minY)
        let tr = CGPoint(x: paper.maxX, y: paper.minY)
        let br = CGPoint(x: paper.maxX, y: paper.maxY)
        let bl = CGPoint(x: paper.minX, y: paper.maxY)

        // Start points trace the flat square's perimeter exactly, so at progress 0
        // the silhouette is indistinguishable from a plain unfolded sheet.
        let start = CranePoints(
            beak: tr,
            headBase: CGPoint(x: tr.x - paper.width * 0.12, y: tr.y),
            backRidge: CGPoint(x: tr.x - paper.width * 0.55, y: tr.y),
            wingTip: tl,
            wingNotch: CGPoint(x: tl.x, y: tl.y + paper.height * 0.30),
            tailTip: bl,
            breast: br
        )

        func point(_ fx: Double, _ fy: Double) -> CGPoint {
            CGPoint(x: tileRect.minX + tileRect.width * fx, y: tileRect.minY + tileRect.height * fy)
        }

        // Finished crane silhouette, as fractions of the tile.
        let end = CranePoints(
            beak: point(0.93, 0.26),
            headBase: point(0.64, 0.36),
            backRidge: point(0.50, 0.20),
            wingTip: point(0.13, 0.06),
            wingNotch: point(0.44, 0.48),
            tailTip: point(0.07, 0.68),
            breast: point(0.64, 0.87)
        )

        let pBeak = state.foldBeak
        let pTail = state.foldTail
        let pWing = state.foldWing
        let pRidge = state.foldRidge

        let current = CranePoints(
            beak: lerp(start.beak, end.beak, pBeak),
            headBase: lerp(start.headBase, end.headBase, pBeak),
            backRidge: lerp(start.backRidge, end.backRidge, pRidge),
            wingTip: lerp(start.wingTip, end.wingTip, pWing),
            wingNotch: lerp(start.wingNotch, end.wingNotch, pWing),
            tailTip: lerp(start.tailTip, end.tailTip, pTail),
            breast: lerp(start.breast, end.breast, max(pBeak, pTail) * 0.4 + pRidge * 0.6)
        )

        var body = Path()
        body.move(to: current.beak)
        body.addLine(to: current.headBase)
        body.addLine(to: current.backRidge)
        body.addLine(to: current.wingTip)
        body.addLine(to: current.wingNotch)
        body.addLine(to: current.tailTip)
        body.addLine(to: current.breast)
        body.closeSubpath()

        let foldAmount = max(pBeak, pTail, pWing, pRidge)

        context.drawLayer { layer in
            layer.addFilter(.shadow(color: .black.opacity(0.20), radius: side * 0.05, x: side * 0.01, y: side * 0.03))
            layer.fill(
                body,
                with: .linearGradient(
                    Gradient(colors: [Color(white: 1.0), Color(white: 1.0 - 0.08 * foldAmount)]),
                    startPoint: CGPoint(x: paper.midX, y: paper.minY),
                    endPoint: CGPoint(x: paper.midX, y: paper.maxY)
                )
            )
        }

        // Crease lines fade in per phase, selling the "folded paper" read.
        drawCrease(in: &context, current.beak, current.headBase, pBeak)
        drawCrease(in: &context, current.headBase, current.backRidge, pRidge)
        drawCrease(in: &context, current.backRidge, current.wingTip, pWing)
        drawCrease(in: &context, current.wingNotch, current.tailTip, pTail)
        drawCrease(in: &context, current.backRidge, current.wingNotch, pRidge)
    }

    private static func drawCrease(in context: inout GraphicsContext, _ a: CGPoint, _ b: CGPoint, _ q: Double) {
        guard q > 0.03 else { return }
        var path = Path()
        path.move(to: a)
        path.addLine(to: b)
        context.stroke(path, with: .color(.black.opacity(0.12 * min(1, q * 1.6))), lineWidth: 0.7)
    }

    private static func drawTile(in context: inout GraphicsContext, path: Path, rect: CGRect) {
        // Glacier-blue tile matched to the app icon: dark navy on the left/bottom
        // ramping to bright teal on the right/top (sampled from AppIcon-512).
        let gradient = Gradient(colors: [
            Color(.sRGB, red: 0.17, green: 0.27, blue: 0.40, opacity: 1),
            Color(.sRGB, red: 0.46, green: 0.75, blue: 0.83, opacity: 1)
        ])
        context.fill(
            path,
            with: .linearGradient(
                gradient,
                startPoint: CGPoint(x: rect.minX, y: rect.maxY),   // bottom-left, dark
                endPoint: CGPoint(x: rect.maxX, y: rect.minY)       // top-right, bright
            )
        )

        // Soft teal glow toward the top-right, as in the icon.
        let glowRadius = rect.width * 0.75
        let glowCenter = CGPoint(x: rect.minX + rect.width * 0.82, y: rect.minY + rect.height * 0.20)
        context.fill(
            path,
            with: .radialGradient(
                Gradient(colors: [
                    Color(.sRGB, red: 0.50, green: 0.82, blue: 0.86, opacity: 0.35),
                    Color.clear
                ]),
                center: glowCenter,
                startRadius: 0,
                endRadius: glowRadius
            )
        )

        // Faint nested rim lines, echoing the icon's inset borders.
        for fraction in [0.055, 0.11] {
            let borderInset = rect.width * fraction
            let ring = Path(
                roundedRect: rect.insetBy(dx: borderInset, dy: borderInset),
                cornerRadius: rect.width * 0.22 - borderInset,
                style: .continuous
            )
            context.stroke(ring, with: .color(.white.opacity(0.06)), lineWidth: 1)
        }
    }

    private static func lerp(_ a: CGPoint, _ b: CGPoint, _ t: Double) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }
}
