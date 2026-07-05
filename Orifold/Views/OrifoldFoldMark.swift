import SwiftUI
import AppKit

/// Landing-screen brand moment: a sheet of paper folds — a diagonal valley fold, a
/// half fold — then blossoms into a detailed origami crane (ten shaded facets: twin
/// raised wings, keeled body, reverse-folded head with the beak pointing right, tail),
/// holds, and dissolves so the real app icon (`AppIconMark`) can materialize on the
/// same tile.
///
/// Everything is vector-drawn in a single `Canvas` choreographed by `KeyframeAnimator`:
/// the two opening folds are physically simulated (the flap reflects across the crease
/// and rides a sine "lift" shadow), and the crane then emerges as a staggered per-facet
/// expansion — body first, wings, neck and tail, head last — with crease lines and a
/// soft ground shadow fading in per phase. A subtle top-light sheen and diagonal paper
/// grain are clipped to the crane's silhouette for texture. Once the run finishes the
/// animator stops ticking, so the settled mark costs nothing.
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
    private let animationRuntime: TimeInterval = 3.9

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
                    CubicKeyframe(1.0, duration: 0.60)
                }
                // Fold 2: the triangle folds in half, left point to right.
                KeyframeTrack(\.fold2) {
                    LinearKeyframe(0.0, duration: 0.95)
                    CubicKeyframe(1.0, duration: 0.50)
                }
                // Blossom: the folded packet opens into the crane, part by part.
                KeyframeTrack(\.bloomBody) {
                    LinearKeyframe(0.0, duration: 1.50)
                    CubicKeyframe(1.0, duration: 0.55)
                }
                KeyframeTrack(\.bloomWings) {
                    LinearKeyframe(0.0, duration: 1.65)
                    CubicKeyframe(1.0, duration: 0.60)
                }
                KeyframeTrack(\.bloomNeckTail) {
                    LinearKeyframe(0.0, duration: 1.80)
                    CubicKeyframe(1.0, duration: 0.60)
                }
                KeyframeTrack(\.bloomHead) {
                    LinearKeyframe(0.0, duration: 2.05)
                    CubicKeyframe(1.0, duration: 0.55)
                }
                // Hold the finished crane for a beat, then dissolve it away…
                KeyframeTrack(\.paperOut) {
                    LinearKeyframe(0.0, duration: 2.95)
                    CubicKeyframe(1.0, duration: 0.40)
                }
                // …and only then materialize the finished logo on the same tile.
                KeyframeTrack(\.iconIn) {
                    LinearKeyframe(0.0, duration: 3.40)
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
    /// Half fold (triangle → packet).
    var fold2: Double
    /// Staggered blossom phases: the crane opens part by part.
    var bloomBody: Double
    var bloomWings: Double
    var bloomNeckTail: Double
    var bloomHead: Double
    /// Crane dissolves away (the tile stays put).
    var paperOut: Double
    /// Finished logo materializes on top.
    var iconIn: Double

    static let start = FoldState(
        sheet: 0, fold1: 0, fold2: 0,
        bloomBody: 0, bloomWings: 0, bloomNeckTail: 0, bloomHead: 0,
        paperOut: 0, iconIn: 0
    )
}

// MARK: - Crane geometry
//
// The crane is ten paper facets in tile-unit coordinates ((0,0) = tile top-left,
// (1,1) = tile bottom-right), designed so shared edges share exact vertices.
// Array order is paint order: far wing and tail behind, neck/head/beak next (the
// body covers the neck root), body, then the near wing on top.

private enum BloomGroup {
    case body, wings, neckTail, head

    func progress(_ state: FoldState) -> Double {
        switch self {
        case .body:     return state.bloomBody
        case .wings:    return state.bloomWings
        case .neckTail: return state.bloomNeckTail
        case .head:     return state.bloomHead
        }
    }
}

private struct CraneFacet {
    let group: BloomGroup
    let pts: [CGPoint]
    let shadeTop: Double
    let shadeBottom: Double
    let gradFrom: CGPoint
    let gradTo: CGPoint
}

private struct CraneCrease {
    let group: BloomGroup
    let from: CGPoint
    let to: CGPoint
    let opacity: Double
}

private enum CraneGeometry {
    /// Outline of the folded packet left by fold 2 (matches `rightHalf` in
    /// `drawFoldStages` exactly): creaseTop → tr → br → creaseBot. Every facet vertex
    /// collapses to its nearest point on this outline before the blossom, so the
    /// crane visibly unfolds from the paper's actual folded edges instead of popping
    /// in from an arbitrary interior point.
    static let packetQuad: [CGPoint] = [
        CGPoint(x: 0.5, y: 0.5),
        CGPoint(x: 0.8, y: 0.2),
        CGPoint(x: 0.8, y: 0.8),
        CGPoint(x: 0.5, y: 0.8),
    ]

    static let facets: [CraneFacet] = [
        CraneFacet(group: .wings,
                   pts: [CGPoint(x: 0.48, y: 0.48), CGPoint(x: 0.465, y: 0.095), CGPoint(x: 0.6, y: 0.5)],
                   shadeTop: 0.76, shadeBottom: 0.70,
                   gradFrom: CGPoint(x: 0.465, y: 0.095), gradTo: CGPoint(x: 0.6, y: 0.5)),        // far wing
        CraneFacet(group: .neckTail,
                   pts: [CGPoint(x: 0.38, y: 0.545), CGPoint(x: 0.125, y: 0.685), CGPoint(x: 0.39, y: 0.6)],
                   shadeTop: 0.90, shadeBottom: 0.85,
                   gradFrom: CGPoint(x: 0.38, y: 0.545), gradTo: CGPoint(x: 0.125, y: 0.685)),     // tail, lit half
        CraneFacet(group: .neckTail,
                   pts: [CGPoint(x: 0.39, y: 0.6), CGPoint(x: 0.125, y: 0.685), CGPoint(x: 0.4, y: 0.655)],
                   shadeTop: 0.79, shadeBottom: 0.74,
                   gradFrom: CGPoint(x: 0.4, y: 0.655), gradTo: CGPoint(x: 0.125, y: 0.685)),      // tail, shaded half
        CraneFacet(group: .neckTail,
                   pts: [CGPoint(x: 0.665, y: 0.515), CGPoint(x: 0.84, y: 0.235), CGPoint(x: 0.808, y: 0.295), CGPoint(x: 0.74, y: 0.56)],
                   shadeTop: 0.96, shadeBottom: 0.89,
                   gradFrom: CGPoint(x: 0.84, y: 0.235), gradTo: CGPoint(x: 0.74, y: 0.56)),       // neck
        CraneFacet(group: .head,
                   pts: [CGPoint(x: 0.84, y: 0.235), CGPoint(x: 0.887, y: 0.3), CGPoint(x: 0.8715, y: 0.329), CGPoint(x: 0.808, y: 0.295)],
                   shadeTop: 0.90, shadeBottom: 0.84,
                   gradFrom: CGPoint(x: 0.84, y: 0.235), gradTo: CGPoint(x: 0.808, y: 0.295)),     // head
        CraneFacet(group: .head,
                   pts: [CGPoint(x: 0.887, y: 0.3), CGPoint(x: 0.93, y: 0.36), CGPoint(x: 0.8715, y: 0.329)],
                   shadeTop: 0.99, shadeBottom: 0.92,
                   gradFrom: CGPoint(x: 0.887, y: 0.3), gradTo: CGPoint(x: 0.93, y: 0.36)),        // beak
        CraneFacet(group: .body,
                   pts: [CGPoint(x: 0.54, y: 0.44), CGPoint(x: 0.52, y: 0.78), CGPoint(x: 0.28, y: 0.58)],
                   shadeTop: 0.86, shadeBottom: 0.78,
                   gradFrom: CGPoint(x: 0.54, y: 0.44), gradTo: CGPoint(x: 0.28, y: 0.58)),        // body, shaded half
        CraneFacet(group: .body,
                   pts: [CGPoint(x: 0.54, y: 0.44), CGPoint(x: 0.74, y: 0.56), CGPoint(x: 0.52, y: 0.78)],
                   shadeTop: 0.98, shadeBottom: 0.91,
                   gradFrom: CGPoint(x: 0.54, y: 0.44), gradTo: CGPoint(x: 0.52, y: 0.78)),        // body, lit half
        CraneFacet(group: .wings,
                   pts: [CGPoint(x: 0.52, y: 0.515), CGPoint(x: 0.295, y: 0.14), CGPoint(x: 0.42, y: 0.52)],
                   shadeTop: 0.85, shadeBottom: 0.80,
                   gradFrom: CGPoint(x: 0.295, y: 0.14), gradTo: CGPoint(x: 0.42, y: 0.52)),       // near wing, back half
        CraneFacet(group: .wings,
                   pts: [CGPoint(x: 0.62, y: 0.52), CGPoint(x: 0.295, y: 0.14), CGPoint(x: 0.52, y: 0.515)],
                   shadeTop: 1.00, shadeBottom: 0.93,
                   gradFrom: CGPoint(x: 0.295, y: 0.14), gradTo: CGPoint(x: 0.62, y: 0.52)),       // near wing, lit half
    ]

    static let creases: [CraneCrease] = [
        CraneCrease(group: .body,     from: CGPoint(x: 0.54, y: 0.44),     to: CGPoint(x: 0.52, y: 0.78),     opacity: 0.11),  // body median
        CraneCrease(group: .wings,    from: CGPoint(x: 0.52, y: 0.515),    to: CGPoint(x: 0.295, y: 0.14),    opacity: 0.10),  // wing median
        CraneCrease(group: .wings,    from: CGPoint(x: 0.42, y: 0.52),     to: CGPoint(x: 0.62, y: 0.52),     opacity: 0.08),  // wing root
        CraneCrease(group: .neckTail, from: CGPoint(x: 0.39, y: 0.6),      to: CGPoint(x: 0.125, y: 0.685),   opacity: 0.08),  // tail median
        CraneCrease(group: .neckTail, from: CGPoint(x: 0.7025, y: 0.5375), to: CGPoint(x: 0.8225, y: 0.2675), opacity: 0.07),  // neck median
        CraneCrease(group: .head,     from: CGPoint(x: 0.887, y: 0.3),     to: CGPoint(x: 0.8715, y: 0.329),  opacity: 0.09),  // beak fold
        CraneCrease(group: .head,     from: CGPoint(x: 0.84, y: 0.235),    to: CGPoint(x: 0.808, y: 0.295),   opacity: 0.08),  // head fold
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

        drawFoldStages(in: &context, tileRect: tileRect, side: side, state: state, at: at)
        drawCrane(in: &context, side: side, state: state, at: at)
    }

    // MARK: Opening folds (square → triangle → packet)

    private static func drawFoldStages(
        in context: inout GraphicsContext,
        tileRect: CGRect,
        side: CGFloat,
        state: FoldState,
        at: (CGPoint) -> CGPoint
    ) {
        // The folded packet dissolves into the emerging crane body.
        let stageOpacity = 1 - min(1, state.bloomBody * 1.55)
        guard stageOpacity > 0.001 else { return }

        // Paper square in tile-unit coordinates.
        let tl = CGPoint(x: 0.2, y: 0.2), tr = CGPoint(x: 0.8, y: 0.2)
        let br = CGPoint(x: 0.8, y: 0.8), bl = CGPoint(x: 0.2, y: 0.8)

        context.drawLayer { layer in
            layer.opacity = stageOpacity

            if state.fold2 <= 0 {
                if state.fold1 <= 0 {
                    // Flat sheet.
                    var square = Path()
                    square.move(to: at(tl)); square.addLine(to: at(tr))
                    square.addLine(to: at(br)); square.addLine(to: at(bl))
                    square.closeSubpath()
                    layer.drawLayer { l in
                        l.addFilter(.shadow(color: .black.opacity(0.20), radius: side * 0.04, x: 0, y: side * 0.02))
                        l.fill(square, with: .linearGradient(
                            Gradient(colors: [Color(white: 1.0), Color(white: 0.93)]),
                            startPoint: at(tl), endPoint: at(br)))
                    }
                } else {
                    // Diagonal fold: base triangle + flap reflecting across bl–tr.
                    var baseTri = Path()
                    baseTri.move(to: at(bl)); baseTri.addLine(to: at(tr)); baseTri.addLine(to: at(br))
                    baseTri.closeSubpath()
                    layer.drawLayer { l in
                        l.addFilter(.shadow(color: .black.opacity(0.20), radius: side * 0.04, x: 0, y: side * 0.02))
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
                            l.addFilter(.shadow(color: .black.opacity(0.22 * lift), radius: side * 0.05 * lift, x: 0, y: side * 0.03 * lift))
                        }
                        l.fill(flap, with: .linearGradient(
                            Gradient(colors: [Color(white: 1.0), Color(white: 0.95 - 0.06 * state.fold1)]),
                            startPoint: lerp(at(bl), at(tr), t: 0.5), endPoint: movingTL))
                    }
                    var crease = Path()
                    crease.move(to: at(bl)); crease.addLine(to: at(tr))
                    layer.stroke(crease, with: .color(.black.opacity(0.10 * state.fold1)), lineWidth: 0.8)
                }
            } else {
                // Half fold: right half stays, left point folds across x = 0.5.
                let creaseTop = CGPoint(x: 0.5, y: 0.5), creaseBot = CGPoint(x: 0.5, y: 0.8)
                var rightHalf = Path()
                rightHalf.move(to: at(creaseTop)); rightHalf.addLine(to: at(tr))
                rightHalf.addLine(to: at(br)); rightHalf.addLine(to: at(creaseBot))
                rightHalf.closeSubpath()
                layer.drawLayer { l in
                    l.addFilter(.shadow(color: .black.opacity(0.20), radius: side * 0.04, x: 0, y: side * 0.02))
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
                        l.addFilter(.shadow(color: .black.opacity(0.22 * lift), radius: side * 0.05 * lift, x: 0, y: side * 0.03 * lift))
                    }
                    l.fill(flap, with: .linearGradient(
                        Gradient(colors: [Color(white: 1.0), Color(white: 0.93)]),
                        startPoint: at(creaseTop), endPoint: movingBL))
                }
                var crease = Path()
                crease.move(to: at(creaseTop)); crease.addLine(to: at(creaseBot))
                layer.stroke(crease, with: .color(.black.opacity(0.12)), lineWidth: 0.8)
            }
        }
    }

    // MARK: Crane blossom

    private static func drawCrane(
        in context: inout GraphicsContext,
        side: CGFloat,
        state: FoldState,
        at: (CGPoint) -> CGPoint
    ) {
        let overall = max(state.bloomBody, state.bloomWings, state.bloomNeckTail, state.bloomHead)
        guard overall > 0.001 else { return }

        // Current vertex positions: each facet unfolds from its nearest point on the
        // folded packet's outline out to its final position, on its group's schedule.
        // `p` is already eased once by its CubicKeyframe track; applying `ease()`
        // again here (and to opacity below) is deliberate — it flattens the very
        // start and end of each facet's reveal for a softer settle, verified against
        // rendered filmstrips. The README SVG mirrors this exact double-ease so the
        // two match.
        func facetPath(_ facet: CraneFacet) -> (path: Path, progress: Double)? {
            let p = facet.group.progress(state)
            guard p > 0.001 else { return nil }
            var path = Path()
            let pts = facet.pts.map { pt -> CGPoint in
                let anchor = nearestPointOnPolygon(pt, polygon: CraneGeometry.packetQuad)
                return at(lerp(anchor, pt, t: ease(p)))
            }
            path.move(to: pts[0])
            for pt in pts.dropFirst() { path.addLine(to: pt) }
            path.closeSubpath()
            return (path, p)
        }

        // Soft ground shadow beneath the settling crane.
        let groundOpacity = 0.14 * state.bloomBody
        if groundOpacity > 0.005 {
            let center = at(CGPoint(x: 0.50, y: 0.82))
            let rx = side * 0.26, ry = side * 0.045
            let shadowRect = CGRect(x: center.x - rx, y: center.y - ry, width: rx * 2, height: ry * 2)
            context.fill(
                Path(ellipseIn: shadowRect),
                with: .radialGradient(
                    Gradient(colors: [.black.opacity(groundOpacity), .clear]),
                    center: center, startRadius: 0, endRadius: rx
                )
            )
        }

        // One clean drop shadow for the whole silhouette (cheaper and tidier than
        // per-facet shadows), then the facets tile exactly over it.
        var silhouette = Path()
        var visible: [(CraneFacet, Path, Double)] = []
        for facet in CraneGeometry.facets {
            if let (path, p) = facetPath(facet) {
                silhouette.addPath(path)
                visible.append((facet, path, p))
            }
        }
        guard !visible.isEmpty else { return }

        context.drawLayer { layer in
            layer.addFilter(.shadow(color: .black.opacity(0.20 * overall), radius: side * 0.045, x: side * 0.008, y: side * 0.025))
            layer.fill(silhouette, with: .color(.white))
        }

        for (facet, path, p) in visible {
            context.drawLayer { layer in
                // Facets start as slivers hugging the packet's edge (near-zero area),
                // so opacity only needs a gentle ramp to avoid a flat, papery look
                // lingering too long — no fast "pop to solid" required.
                layer.opacity = min(1, ease(p) * 1.6)
                layer.fill(path, with: .linearGradient(
                    Gradient(colors: [Color(white: facet.shadeTop), Color(white: facet.shadeBottom)]),
                    startPoint: at(facet.gradFrom), endPoint: at(facet.gradTo)
                ))
            }
        }

        // Paper texture, clipped to the crane: a soft top-light sheen and a whisper
        // of diagonal grain.
        context.drawLayer { layer in
            layer.clip(to: silhouette)
            layer.opacity = overall
            layer.fill(
                Path(CGRect(x: at(.zero).x, y: at(.zero).y, width: side, height: side)),
                with: .linearGradient(
                    Gradient(colors: [.white.opacity(0.07), .clear, .black.opacity(0.03)]),
                    startPoint: at(CGPoint(x: 0.7, y: 0.1)),
                    endPoint: at(CGPoint(x: 0.3, y: 0.9))
                )
            )
            var grain = Path()
            var offset = -0.9
            while offset < 0.9 {
                grain.move(to: at(CGPoint(x: offset, y: 1.05)))
                grain.addLine(to: at(CGPoint(x: offset + 1.0, y: -0.05)))
                offset += 0.09
            }
            layer.stroke(grain, with: .color(.black.opacity(0.016)), lineWidth: 0.7)
        }

        // Crease lines fade in with their part of the fold.
        for crease in CraneGeometry.creases {
            let p = crease.group.progress(state)
            guard p > 0.05 else { continue }
            var line = Path()
            line.move(to: at(crease.from))
            line.addLine(to: at(crease.to))
            context.stroke(line, with: .color(.black.opacity(crease.opacity * min(1, p * 1.4))), lineWidth: 0.8)
        }
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
