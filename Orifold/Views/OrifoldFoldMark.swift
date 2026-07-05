import SwiftUI
import AppKit

/// Landing-screen brand moment: a sheet of paper folds through three deliberate
/// creases — a diagonal valley fold, a half fold, a petal fold — then blossoms into a
/// slender origami swan (a two-tone keeled body, a segmented neck that cascades into
/// a graceful curve, a single swept wing, a small tail, and a reverse-folded head with
/// the beak pointing right), holds, and dissolves so the real app icon (`AppIconMark`)
/// can materialize on the same tile.
///
/// Everything is vector-drawn in a single `Canvas` choreographed by `KeyframeAnimator`:
/// the three opening folds are physically simulated (each flap reflects across its
/// crease and rides a sine "lift" shadow), and the swan then emerges as a staggered
/// per-part reveal — body, wing, a segment-by-segment neck cascade, tail, head — with
/// every part unfolding from its nearest point on the folded packet's actual outline
/// rather than an arbitrary interior point, so the paper visibly continues into the
/// bird instead of popping in. A soft ground shadow and a single top-light sheen give
/// it quiet depth without busywork. Once the run finishes the animator stops ticking,
/// so the settled mark costs nothing.
///
/// The hand-off to the finished logo is sequenced, not crossfaded: the swan fully
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
    private let animationRuntime: TimeInterval = 4.55

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
                    CubicKeyframe(1.0, duration: 0.30)
                }
                // Fold 1: diagonal valley fold — the top-left half lifts and lays
                // over the bottom-right, leaving a two-layer triangle.
                KeyframeTrack(\.fold1) {
                    LinearKeyframe(0.0, duration: 0.30)
                    CubicKeyframe(1.0, duration: 0.55)
                }
                // Fold 2: the triangle folds in half, left point to right.
                KeyframeTrack(\.fold2) {
                    LinearKeyframe(0.0, duration: 0.85)
                    CubicKeyframe(1.0, duration: 0.45)
                }
                // Fold 3: a petal fold narrows the packet further — the last
                // deliberate crease before the paper opens into the bird.
                KeyframeTrack(\.fold3) {
                    LinearKeyframe(0.0, duration: 1.30)
                    CubicKeyframe(1.0, duration: 0.45)
                }
                // Blossom: the packet opens into the swan, part by part.
                KeyframeTrack(\.bloomBody) {
                    LinearKeyframe(0.0, duration: 1.75)
                    CubicKeyframe(1.0, duration: 0.50)
                }
                KeyframeTrack(\.bloomTail) {
                    LinearKeyframe(0.0, duration: 2.00)
                    CubicKeyframe(1.0, duration: 0.45)
                }
                KeyframeTrack(\.bloomWing) {
                    LinearKeyframe(0.0, duration: 1.90)
                    CubicKeyframe(1.0, duration: 0.55)
                }
                // The neck cascades in segment by segment (see the per-segment
                // stagger in `drawSwan`), so it
                // gets the longest span of any part.
                KeyframeTrack(\.bloomNeck) {
                    LinearKeyframe(0.0, duration: 2.05)
                    CubicKeyframe(1.0, duration: 0.85)
                }
                KeyframeTrack(\.bloomHead) {
                    LinearKeyframe(0.0, duration: 2.75)
                    CubicKeyframe(1.0, duration: 0.50)
                }
                // Hold the finished swan for a beat, then dissolve it away…
                KeyframeTrack(\.paperOut) {
                    LinearKeyframe(0.0, duration: 3.55)
                    CubicKeyframe(1.0, duration: 0.40)
                }
                // …and only then materialize the finished logo on the same tile.
                KeyframeTrack(\.iconIn) {
                    LinearKeyframe(0.0, duration: 4.00)
                    CubicKeyframe(1.0, duration: 0.45)
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
    /// Diagonal valley fold (square → triangle).
    var fold1: Double
    /// Half fold (triangle → wide packet).
    var fold2: Double
    /// Petal fold (wide packet → slender triangle).
    var fold3: Double
    /// Staggered blossom phases: the swan opens part by part.
    var bloomBody: Double
    var bloomTail: Double
    var bloomWing: Double
    var bloomNeck: Double
    var bloomHead: Double
    /// Swan dissolves away (the tile stays put).
    var paperOut: Double
    /// Finished logo materializes on top.
    var iconIn: Double

    static let start = FoldState(
        sheet: 0, fold1: 0, fold2: 0, fold3: 0,
        bloomBody: 0, bloomTail: 0, bloomWing: 0, bloomNeck: 0, bloomHead: 0,
        paperOut: 0, iconIn: 0
    )
}

// MARK: - Swan geometry
//
// All coordinates are tile-unit fractions ((0,0) = tile top-left, (1,1) = bottom-right).
// The silhouette is centered and faces right, echoing the app icon's arrow direction.

private enum SwanGeometry {
    // Body: a two-tone keeled teardrop. bodyFront is a quad (an extra vertex over a
    // plain triangle) for a rounder, less angular profile.
    static let bodyTopL = CGPoint(x: 0.49, y: 0.49)
    static let bodyTopR = CGPoint(x: 0.635, y: 0.525)
    static let bodyMid = CGPoint(x: 0.60, y: 0.72)
    static let bodyBottom = CGPoint(x: 0.545, y: 0.855)
    static let bodyLeft = CGPoint(x: 0.345, y: 0.635)

    static let bodyBack: [CGPoint] = [bodyTopL, bodyBottom, bodyLeft]
    static let bodyFront: [CGPoint] = [bodyTopL, bodyTopR, bodyMid, bodyBottom]

    // Neck: a ribbon along a curved centerline from the body up to the head, split
    // into segments so it can cascade into place rather than unfold as one piece.
    static let neckLine: [CGPoint] = [
        bodyTopR,
        CGPoint(x: 0.68, y: 0.42),
        CGPoint(x: 0.735, y: 0.31),
        CGPoint(x: 0.775, y: 0.205),
        CGPoint(x: 0.80, y: 0.145),
    ]
    static let neckWidths: [Double] = [0.028, 0.026, 0.022, 0.017, 0.012]
    static let neckShades: [Double] = [0.97, 0.945, 0.92, 0.895, 0.87]

    // Head + beak, continuing from the neck's last point.
    static let headBase = neckLine[4]
    static let headTip = CGPoint(x: 0.850, y: 0.118)
    static let headThroat = CGPoint(x: 0.822, y: 0.168)
    static let beakTip = CGPoint(x: 0.935, y: 0.148)
    static let head: [CGPoint] = [headBase, headTip, headThroat]
    static let beak: [CGPoint] = [headTip, beakTip, headThroat]

    // Wing: swept up and back, two facets sharing the root and an interior fold point.
    static let wingRoot = bodyLeft
    static let wingTip = CGPoint(x: 0.13, y: 0.11)
    static let wingFold = CGPoint(x: 0.30, y: 0.30)
    static let wingOuterEdge = CGPoint(x: 0.42, y: 0.50)
    static let wingBack: [CGPoint] = [wingRoot, wingTip, wingFold]
    static let wingFront: [CGPoint] = [wingRoot, wingFold, wingOuterEdge]

    // Tail: small and tucked, echoing the body's proportions.
    static let tailRoot = CGPoint(x: 0.475, y: 0.775)
    static let tailTip = CGPoint(x: 0.205, y: 0.895)
    static let tailFold = CGPoint(x: 0.375, y: 0.845)
    static let tail: [CGPoint] = [tailRoot, tailTip, tailFold]

    /// Outline of the folded packet left by fold 3 (matches the triangle drawn in
    /// `drawFoldStages`'s fold3 branch exactly): creaseTop → br → creaseBot. Every
    /// part unfolds from its nearest point on this outline, so the swan visibly
    /// emerges from the paper's actual folded edges instead of popping in.
    static let packetTriangle: [CGPoint] = [
        CGPoint(x: 0.5, y: 0.5),
        CGPoint(x: 0.8, y: 0.8),
        CGPoint(x: 0.5, y: 0.8),
    ]
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
        let tilePath = Path(roundedRect: tileRect, cornerRadius: side * 0.22, style: .continuous)

        drawTile(in: &context, path: tilePath, rect: tileRect)

        // Keep all paper contained within the rounded tile.
        context.clip(to: tilePath)

        // The paper fades out on its own while the tile stays put, so the incoming
        // logo hands off on a steady ground rather than crossfading two shapes.
        let paperOpacity = state.sheet * (1 - state.paperOut)
        guard paperOpacity > 0.001 else { return }
        context.opacity = paperOpacity

        // Convenience: tile-unit → canvas points.
        func at(_ p: CGPoint) -> CGPoint {
            CGPoint(x: tileRect.minX + p.x * side, y: tileRect.minY + p.y * side)
        }

        drawFoldStages(in: &context, side: side, state: state, at: at)
        drawSwan(in: &context, side: side, state: state, at: at)
    }

    // MARK: Opening folds (square → triangle → wide packet → slender triangle)

    private static func drawFoldStages(
        in context: inout GraphicsContext,
        side: CGFloat,
        state: FoldState,
        at: (CGPoint) -> CGPoint
    ) {
        // The folded packet dissolves into the emerging swan body.
        let stageOpacity = 1 - min(1, state.bloomBody * 1.55)
        guard stageOpacity > 0.001 else { return }

        // Paper square in tile-unit coordinates.
        let tl = CGPoint(x: 0.2, y: 0.2), tr = CGPoint(x: 0.8, y: 0.2)
        let br = CGPoint(x: 0.8, y: 0.8), bl = CGPoint(x: 0.2, y: 0.8)
        let creaseTop = CGPoint(x: 0.5, y: 0.5), creaseBot = CGPoint(x: 0.5, y: 0.8)
        let crease3 = CGPoint(x: 0.8, y: 0.5)

        context.drawLayer { layer in
            layer.opacity = stageOpacity

            if state.fold3 > 0 {
                // Petal fold: tr folds down across creaseTop–crease3 (a horizontal
                // line), landing exactly on br — collapsing the wide packet into a
                // slender triangle: creaseTop, br, creaseBot.
                var settled = Path()
                settled.move(to: at(creaseTop)); settled.addLine(to: at(br)); settled.addLine(to: at(creaseBot))
                settled.closeSubpath()
                layer.drawLayer { l in
                    l.addFilter(.shadow(color: .black.opacity(0.16), radius: side * 0.035, x: 0, y: side * 0.018))
                    l.fill(settled, with: .linearGradient(
                        Gradient(colors: [Color(white: 0.95), Color(white: 0.88)]),
                        startPoint: at(creaseTop), endPoint: at(creaseBot)))
                }

                let movingTR = lerp(at(tr), reflect(at(tr), across: at(creaseTop), at(crease3)), t: state.fold3)
                var flap = Path()
                flap.move(to: at(creaseTop)); flap.addLine(to: movingTR); flap.addLine(to: at(crease3))
                flap.closeSubpath()
                let lift = sin(state.fold3 * .pi)
                layer.drawLayer { l in
                    if lift > 0.02 {
                        l.addFilter(.shadow(color: .black.opacity(0.18 * lift), radius: side * 0.04 * lift, x: 0, y: side * 0.025 * lift))
                    }
                    l.fill(flap, with: .linearGradient(
                        Gradient(colors: [Color(white: 1.0), Color(white: 0.93)]),
                        startPoint: lerp(at(creaseTop), at(crease3), t: 0.5), endPoint: movingTR))
                }
                var crease = Path()
                crease.move(to: at(creaseTop)); crease.addLine(to: at(crease3))
                layer.stroke(crease, with: .color(.black.opacity(0.09 * state.fold3)), lineWidth: 0.7)
            } else if state.fold2 > 0 {
                // Half fold: right half stays, left point folds across x = 0.5.
                var rightHalf = Path()
                rightHalf.move(to: at(creaseTop)); rightHalf.addLine(to: at(tr))
                rightHalf.addLine(to: at(br)); rightHalf.addLine(to: at(creaseBot))
                rightHalf.closeSubpath()
                layer.drawLayer { l in
                    l.addFilter(.shadow(color: .black.opacity(0.18), radius: side * 0.035, x: 0, y: side * 0.018))
                    l.fill(rightHalf, with: .linearGradient(
                        Gradient(colors: [Color(white: 0.96), Color(white: 0.89)]),
                        startPoint: at(creaseTop), endPoint: at(br)))
                }

                let movingBL = lerp(at(bl), reflect(at(bl), across: at(creaseTop), at(creaseBot)), t: state.fold2)
                var flap = Path()
                flap.move(to: at(creaseTop)); flap.addLine(to: movingBL); flap.addLine(to: at(creaseBot))
                flap.closeSubpath()
                let lift = sin(state.fold2 * .pi)
                layer.drawLayer { l in
                    if lift > 0.02 {
                        l.addFilter(.shadow(color: .black.opacity(0.20 * lift), radius: side * 0.045 * lift, x: 0, y: side * 0.028 * lift))
                    }
                    l.fill(flap, with: .linearGradient(
                        Gradient(colors: [Color(white: 1.0), Color(white: 0.93)]),
                        startPoint: at(creaseTop), endPoint: movingBL))
                }
                var crease = Path()
                crease.move(to: at(creaseTop)); crease.addLine(to: at(creaseBot))
                layer.stroke(crease, with: .color(.black.opacity(0.11)), lineWidth: 0.7)
            } else if state.fold1 > 0 {
                // Diagonal fold: base triangle + flap reflecting across bl–tr.
                var baseTri = Path()
                baseTri.move(to: at(bl)); baseTri.addLine(to: at(tr)); baseTri.addLine(to: at(br))
                baseTri.closeSubpath()
                layer.drawLayer { l in
                    l.addFilter(.shadow(color: .black.opacity(0.18), radius: side * 0.035, x: 0, y: side * 0.018))
                    l.fill(baseTri, with: .linearGradient(
                        Gradient(colors: [Color(white: 0.97), Color(white: 0.90)]),
                        startPoint: at(tr), endPoint: at(bl)))
                }

                let movingTL = lerp(at(tl), reflect(at(tl), across: at(bl), at(tr)), t: state.fold1)
                var flap = Path()
                flap.move(to: at(bl)); flap.addLine(to: movingTL); flap.addLine(to: at(tr))
                flap.closeSubpath()
                let lift = sin(state.fold1 * .pi)
                layer.drawLayer { l in
                    if lift > 0.02 {
                        l.addFilter(.shadow(color: .black.opacity(0.20 * lift), radius: side * 0.045 * lift, x: 0, y: side * 0.028 * lift))
                    }
                    l.fill(flap, with: .linearGradient(
                        Gradient(colors: [Color(white: 1.0), Color(white: 0.95 - 0.06 * state.fold1)]),
                        startPoint: lerp(at(bl), at(tr), t: 0.5), endPoint: movingTL))
                }
                var crease = Path()
                crease.move(to: at(bl)); crease.addLine(to: at(tr))
                layer.stroke(crease, with: .color(.black.opacity(0.09 * state.fold1)), lineWidth: 0.7)
            } else {
                // Flat sheet.
                var square = Path()
                square.move(to: at(tl)); square.addLine(to: at(tr))
                square.addLine(to: at(br)); square.addLine(to: at(bl))
                square.closeSubpath()
                layer.drawLayer { l in
                    l.addFilter(.shadow(color: .black.opacity(0.16), radius: side * 0.03, x: 0, y: side * 0.015))
                    l.fill(square, with: .linearGradient(
                        Gradient(colors: [Color(white: 1.0), Color(white: 0.93)]),
                        startPoint: at(tl), endPoint: at(br)))
                }
            }
        }
    }

    // MARK: Swan blossom

    private static func drawSwan(
        in context: inout GraphicsContext,
        side: CGFloat,
        state: FoldState,
        at: (CGPoint) -> CGPoint
    ) {
        let overall = max(state.bloomBody, state.bloomTail, state.bloomWing, state.bloomNeck, state.bloomHead)
        guard overall > 0.001 else { return }

        // Soft ground shadow beneath the settling swan.
        let groundOpacity = 0.12 * state.bloomBody
        if groundOpacity > 0.005 {
            let center = at(CGPoint(x: 0.52, y: 0.83))
            let rx = side * 0.24, ry = side * 0.04
            let shadowRect = CGRect(x: center.x - rx, y: center.y - ry, width: rx * 2, height: ry * 2)
            context.fill(
                Path(ellipseIn: shadowRect),
                with: .radialGradient(
                    Gradient(colors: [.black.opacity(groundOpacity), .clear]),
                    center: center, startRadius: 0, endRadius: rx
                )
            )
        }

        var silhouette = Path()
        var opaqueFacets: [(Path, Double, Double, Double, CGPoint, CGPoint)] = []  // path, opacity, shadeTop, shadeBottom, from, to

        func addFacet(_ pts: [CGPoint], progress: Double, shadeTop: Double, shadeBottom: Double, from: CGPoint, to: CGPoint) {
            guard progress > 0.001 else { return }
            let eased = ease(progress)
            let path = unfoldPath(pts, progress: eased, at: at)
            silhouette.addPath(path)
            opaqueFacets.append((path, min(1, eased * 1.6), shadeTop, shadeBottom, at(from), at(to)))
        }

        // Body.
        addFacet(SwanGeometry.bodyBack, progress: state.bloomBody, shadeTop: 0.84, shadeBottom: 0.76,
                 from: SwanGeometry.bodyTopL, to: SwanGeometry.bodyLeft)
        addFacet(SwanGeometry.bodyFront, progress: state.bloomBody, shadeTop: 0.99, shadeBottom: 0.92,
                 from: SwanGeometry.bodyTopL, to: SwanGeometry.bodyBottom)

        // Tail.
        addFacet(SwanGeometry.tail, progress: state.bloomTail, shadeTop: 0.90, shadeBottom: 0.84,
                 from: SwanGeometry.tailRoot, to: SwanGeometry.tailTip)

        // Wing.
        addFacet(SwanGeometry.wingBack, progress: state.bloomWing, shadeTop: 0.80, shadeBottom: 0.73,
                 from: SwanGeometry.wingRoot, to: SwanGeometry.wingTip)
        addFacet(SwanGeometry.wingFront, progress: state.bloomWing, shadeTop: 0.99, shadeBottom: 0.91,
                 from: SwanGeometry.wingFold, to: SwanGeometry.wingRoot)

        // Neck: segments cascade in one after another rather than revealing together.
        let segmentCount = SwanGeometry.neckLine.count - 1
        let stagger = 0.16
        let span = 1 - stagger * Double(segmentCount - 1)
        for i in 0..<segmentCount {
            let localRaw = (state.bloomNeck - stagger * Double(i)) / span
            let local = max(0, min(1, localRaw))
            guard local > 0.001 else { continue }
            let quad = ribbonSegment(
                a: SwanGeometry.neckLine[i], b: SwanGeometry.neckLine[i + 1],
                widthA: SwanGeometry.neckWidths[i], widthB: SwanGeometry.neckWidths[i + 1]
            )
            addFacet(quad, progress: local, shadeTop: SwanGeometry.neckShades[i], shadeBottom: SwanGeometry.neckShades[i] - 0.05,
                      from: SwanGeometry.neckLine[i], to: SwanGeometry.neckLine[i + 1])
        }

        // Head + beak.
        addFacet(SwanGeometry.head, progress: state.bloomHead, shadeTop: 0.94, shadeBottom: 0.87,
                 from: SwanGeometry.headBase, to: SwanGeometry.headTip)
        addFacet(SwanGeometry.beak, progress: state.bloomHead, shadeTop: 0.90, shadeBottom: 0.82,
                 from: SwanGeometry.headTip, to: SwanGeometry.beakTip)

        guard !opaqueFacets.isEmpty else { return }

        // One clean drop shadow for the whole silhouette, then facets tile over it.
        context.drawLayer { layer in
            layer.addFilter(.shadow(color: .black.opacity(0.16 * overall), radius: side * 0.035, x: side * 0.006, y: side * 0.020))
            layer.fill(silhouette, with: .color(.white))
        }

        for (path, opacity, shadeTop, shadeBottom, from, to) in opaqueFacets {
            context.drawLayer { layer in
                layer.opacity = opacity
                layer.fill(path, with: .linearGradient(
                    Gradient(colors: [Color(white: shadeTop), Color(white: shadeBottom)]),
                    startPoint: from, endPoint: to
                ))
            }
        }

        // A single soft top-light sheen, clipped to the swan — quiet depth, no texture.
        context.drawLayer { layer in
            layer.clip(to: silhouette)
            layer.opacity = overall
            layer.fill(
                Path(CGRect(x: at(.zero).x, y: at(.zero).y, width: side, height: side)),
                with: .linearGradient(
                    Gradient(colors: [.white.opacity(0.06), .clear, .black.opacity(0.025)]),
                    startPoint: at(CGPoint(x: 0.75, y: 0.05)),
                    endPoint: at(CGPoint(x: 0.25, y: 0.95))
                )
            )
        }

        // A few tasteful crease lines — body median and wing root only.
        func crease(_ a: CGPoint, _ b: CGPoint, _ progress: Double, opacity: Double) {
            guard progress > 0.05 else { return }
            var line = Path()
            line.move(to: at(a)); line.addLine(to: at(b))
            context.stroke(line, with: .color(.black.opacity(opacity * min(1, progress * 1.6))), lineWidth: 0.7)
        }
        crease(SwanGeometry.bodyTopL, SwanGeometry.bodyBottom, state.bloomBody, opacity: 0.10)
        crease(SwanGeometry.wingRoot, SwanGeometry.wingFold, state.bloomWing, opacity: 0.08)
    }

    /// Unfolds a facet's points from their nearest anchor on the folded packet's
    /// outline out to their final tile-unit positions, then converts to canvas space.
    private static func unfoldPath(_ pts: [CGPoint], progress: Double, at: (CGPoint) -> CGPoint) -> Path {
        var path = Path()
        let resolved = pts.map { pt -> CGPoint in
            let anchor = nearestPointOnPolygon(pt, polygon: SwanGeometry.packetTriangle)
            return at(lerp(anchor, pt, t: progress))
        }
        path.move(to: resolved[0])
        for pt in resolved.dropFirst() { path.addLine(to: pt) }
        path.closeSubpath()
        return path
    }

    /// One quad of a ribbon between two centerline points, offset by their half-widths.
    private static func ribbonSegment(a: CGPoint, b: CGPoint, widthA: Double, widthB: Double) -> [CGPoint] {
        let n = perpendicular(a, b)
        let a1 = CGPoint(x: a.x + n.x * widthA, y: a.y + n.y * widthA)
        let a2 = CGPoint(x: a.x - n.x * widthA, y: a.y - n.y * widthA)
        let b1 = CGPoint(x: b.x + n.x * widthB, y: b.y + n.y * widthB)
        let b2 = CGPoint(x: b.x - n.x * widthB, y: b.y - n.y * widthB)
        return [a2, a1, b1, b2]
    }

    private static func perpendicular(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
        let dx = b.x - a.x, dy = b.y - a.y
        let len = max(0.0001, (dx * dx + dy * dy).squareRoot())
        return CGPoint(x: -dy / len, y: dx / len)
    }

    // MARK: Tile

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
                    Color(.sRGB, red: 0.50, green: 0.82, blue: 0.86, opacity: 0.30),
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

    // MARK: Geometry helpers

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

    private static func ease(_ t: Double) -> Double {
        let x = max(0, min(1, t))
        return x * x * (3 - 2 * x)
    }

    /// Nearest point to `p` on the closed polygon's boundary (checks every edge).
    private static func nearestPointOnPolygon(_ p: CGPoint, polygon: [CGPoint]) -> CGPoint {
        var best = polygon[0]
        var bestDist = CGFloat.greatestFiniteMagnitude
        for i in 0..<polygon.count {
            let a = polygon[i]
            let b = polygon[(i + 1) % polygon.count]
            let candidate = nearestPointOnSegment(p, a: a, b: b)
            let dx = candidate.x - p.x, dy = candidate.y - p.y
            let dist = dx * dx + dy * dy
            if dist < bestDist {
                bestDist = dist
                best = candidate
            }
        }
        return best
    }

    private static func nearestPointOnSegment(_ p: CGPoint, a: CGPoint, b: CGPoint) -> CGPoint {
        let dx = b.x - a.x, dy = b.y - a.y
        let denom = dx * dx + dy * dy
        guard denom > 0 else { return a }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / denom))
        return CGPoint(x: a.x + t * dx, y: a.y + t * dy)
    }
}
