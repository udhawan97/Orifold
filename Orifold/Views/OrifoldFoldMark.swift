import SwiftUI
import AppKit

/// Landing-screen brand moment: a clean sheet of paper folds through a few
/// deliberate creases and resolves into the finished Orifold logo.
///
/// The fold is drawn as vector paper panels in a `Canvas` — layered flaps with
/// soft cast shadows and a gentle scale-in — choreographed with `KeyframeAnimator`.
/// The paper folds, then gently dissolves away and the real app icon (`AppIconMark`)
/// materializes on the same tile — a sequenced hand-off (paper out, then icon in)
/// rather than a crossfade, so two different shapes never overlap. The tile is drawn
/// to match the icon's background, keeping the ground steady through the hand-off.
/// It settles into a barely perceptible idle breath rather than looping.
///
/// A short beat after the view appears the fold plays automatically; tapping the mark
/// replays it. With Reduce Motion the animation is skipped entirely and the finished
/// logo is shown immediately, so the screen is complete and polished with no motion.
struct OrifoldFoldMark: View {
    var size: CGFloat = 80

    /// Delay before the fold plays on first appearance, so the screen settles first.
    private let autoplayDelay: TimeInterval = 1.0

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
                // Three deliberate corner folds, gently staggered.
                KeyframeTrack(\.fold1) {
                    LinearKeyframe(0.0, duration: 0.30)
                    CubicKeyframe(1.0, duration: 0.60)
                }
                KeyframeTrack(\.fold2) {
                    LinearKeyframe(0.0, duration: 0.62)
                    CubicKeyframe(1.0, duration: 0.58)
                }
                KeyframeTrack(\.fold3) {
                    LinearKeyframe(0.0, duration: 1.00)
                    CubicKeyframe(1.0, duration: 0.48)
                }
                // Hold the folded paper for a beat, then dissolve it away…
                KeyframeTrack(\.paperOut) {
                    LinearKeyframe(0.0, duration: 1.60)
                    CubicKeyframe(1.0, duration: 0.35)
                }
                // …and only then materialize the finished logo on the same tile.
                KeyframeTrack(\.iconIn) {
                    LinearKeyframe(0.0, duration: 1.98)
                    CubicKeyframe(1.0, duration: 0.40)
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
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
    var fold1: Double
    var fold2: Double
    var fold3: Double
    /// Paper dissolves away (the tile stays put).
    var paperOut: Double
    /// Finished logo materializes on top.
    var iconIn: Double

    static let start = FoldState(sheet: 0, fold1: 0, fold2: 0, fold3: 0, paperOut: 0, iconIn: 0)
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

        // Keep folded paper contained within the rounded tile.
        context.clip(to: tilePath)

        // The paper fades out on its own while the tile stays put, so the incoming
        // logo hands off on a steady ground rather than crossfading two shapes.
        context.opacity = state.sheet * (1 - state.paperOut)

        // Paper region, inset within the tile.
        let inset = side * 0.17
        let paper = tileRect.insetBy(dx: inset, dy: inset)
        let s = paper.width

        let tl = CGPoint(x: paper.minX, y: paper.minY)
        let tr = CGPoint(x: paper.maxX, y: paper.minY)
        let br = CGPoint(x: paper.maxX, y: paper.maxY)
        let bl = CGPoint(x: paper.minX, y: paper.maxY)

        // Crease depths for each folded corner (BR is left sharp → arrow feel).
        let dTR = s * 0.66
        let dBL = s * 0.60
        let dTL = s * 0.30

        // Crease chord endpoints on the two edges meeting at each folded corner.
        let trTop = CGPoint(x: tr.x - dTR, y: tr.y)
        let trRight = CGPoint(x: tr.x, y: tr.y + dTR)
        let blBottom = CGPoint(x: bl.x + dBL, y: bl.y)
        let blLeft = CGPoint(x: bl.x, y: bl.y - dBL)
        let tlTop = CGPoint(x: tl.x + dTL, y: tl.y)
        let tlLeft = CGPoint(x: tl.x, y: tl.y + dTL)

        // Base sheet = square with the three folded corners chamfered away.
        var base = Path()
        base.move(to: tlTop)
        base.addLine(to: trTop)
        base.addLine(to: trRight)
        base.addLine(to: br)
        base.addLine(to: blBottom)
        base.addLine(to: blLeft)
        base.addLine(to: tlLeft)
        base.closeSubpath()

        let paperTop = Color(white: 1.0)
        let paperBottom = Color(white: 0.95)

        // Base sheet with a soft drop shadow and faint top-to-bottom shading.
        context.drawLayer { layer in
            layer.addFilter(.shadow(color: .black.opacity(0.18), radius: side * 0.05, x: 0, y: side * 0.028))
            layer.fill(
                base,
                with: .linearGradient(
                    Gradient(colors: [paperTop, paperBottom]),
                    startPoint: CGPoint(x: paper.midX, y: paper.minY),
                    endPoint: CGPoint(x: paper.midX, y: paper.maxY)
                )
            )
        }

        // Folded flaps, drawn in fold order so later folds layer over earlier ones.
        drawFlap(in: &context, corner: tr, e1: trTop, e2: trRight, q: state.fold1, side: side)
        drawFlap(in: &context, corner: bl, e1: blBottom, e2: blLeft, q: state.fold2, side: side)
        drawFlap(in: &context, corner: tl, e1: tlTop, e2: tlLeft, q: state.fold3, side: side)
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

    /// Draws one folded corner. At `q == 0` the flap fills its chamfer exactly (clean
    /// square); as `q → 1` it lifts and reflects across the crease onto the sheet.
    private static func drawFlap(
        in context: inout GraphicsContext,
        corner: CGPoint,
        e1: CGPoint,
        e2: CGPoint,
        q: Double,
        side: CGFloat
    ) {
        let moving = lerp(corner, reflect(corner, across: e1, e2), t: q)

        var flap = Path()
        flap.move(to: e1)
        flap.addLine(to: moving)
        flap.addLine(to: e2)
        flap.closeSubpath()

        // Paper darkens slightly as it folds over onto itself (the shadowed underside).
        let creaseMid = CGPoint(x: (e1.x + e2.x) / 2, y: (e1.y + e2.y) / 2)
        let shade = Gradient(colors: [
            Color(white: 1.0 - 0.05 * q),
            Color(white: 1.0 - 0.16 * q)
        ])

        let lift = sin(q * .pi) // paper rides highest mid-fold

        context.drawLayer { layer in
            if lift > 0.02 {
                layer.addFilter(.shadow(
                    color: .black.opacity(0.15 * lift),
                    radius: side * 0.038 * lift,
                    x: side * 0.012 * lift,
                    y: side * 0.024 * lift
                ))
            }
            layer.fill(
                flap,
                with: .linearGradient(shade, startPoint: creaseMid, endPoint: moving)
            )
        }

        // Faint crease seam along the hinge once the fold is underway.
        if q > 0.02 {
            var crease = Path()
            crease.move(to: e1)
            crease.addLine(to: e2)
            context.stroke(crease, with: .color(.black.opacity(0.10 * min(1, q * 2))), lineWidth: 0.75)
        }
    }

    private static func reflect(_ p: CGPoint, across a: CGPoint, _ b: CGPoint) -> CGPoint {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let denom = dx * dx + dy * dy
        guard denom > 0 else { return p }
        let t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / denom
        let proj = CGPoint(x: a.x + t * dx, y: a.y + t * dy)
        return CGPoint(x: 2 * proj.x - p.x, y: 2 * proj.y - p.y)
    }

    private static func lerp(_ a: CGPoint, _ b: CGPoint, t: Double) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }
}
