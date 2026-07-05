import SwiftUI
import AppKit

/// Brand/companion fold animation: a sheet of paper folds through three deliberate
/// creases — a diagonal valley fold, a half fold, a petal fold — then blossoms into
/// a detailed origami figure. The **figure** is pluggable (`PaperFigure`): the app's
/// brand mark blooms into a crane (tsuru) and hands off to the real app icon, while
/// the dashboard companion blooms into the user's chosen **dog** or **cat** and
/// settles there.
///
/// The opening folds, tile, paper shading, grain, contact shadow, and crease bevel
/// are all shared across every figure — only the final figure's facet/crease geometry
/// differs. Everything is vector-drawn in a single `Canvas` choreographed by
/// `KeyframeAnimator`. The three opening folds are physically simulated (each flap
/// reflects across its crease and rides a sine "lift" shadow). The figure then emerges
/// as a staggered per-part reveal — each facet unfolding from its nearest point on the
/// folded packet's actual outline rather than an arbitrary point, so the paper visibly
/// continues into the figure. The finished figure is richly rendered like real folded
/// washi: warm-ivory facets shaded against a cool light, soft ambient occlusion pooling
/// in the fold valleys, crisp ridge highlights, a deterministic paper-fiber grain
/// clipped to the silhouette, a contact shadow, and a faint moon disc behind it (a quiet
/// Japanese note). The grain is hashed from vertex indices, not randomized per frame, so
/// it never shimmers. Once the run finishes the animator stops ticking, so the settled
/// mark costs nothing.
///
/// For the brand crane the hand-off to the finished logo is sequenced, not crossfaded:
/// the crane fully dissolves first, then the icon materializes on a tile drawn to match
/// the icon's real background, so two different shapes never overlap mid-transition. The
/// dog/cat companions skip that hand-off entirely and settle on the finished animal.
/// Everything settles into a barely perceptible idle breath rather than looping.
///
/// A short beat after the view appears the fold plays automatically; tapping the mark
/// replays it. With Reduce Motion the animation is skipped entirely and the finished
/// figure (crane → app icon; dog/cat → the settled animal) is shown immediately, so the
/// screen is complete and polished with no motion.
struct OrifoldFoldMark: View {
    var size: CGFloat = 80
    /// When embedded inside a caller's own tap target (e.g. the dashboard pet's
    /// button), disable the mark's own replay button so tap gestures don't nest.
    var interactive: Bool = true
    /// Which paper figure the fold blossoms into. Defaults to the brand crane so the
    /// wordmark and every existing call site are unchanged.
    var figure: PaperFigure = .crane

    /// Delay before the fold plays on first appearance, so the screen settles first.
    private let autoplayDelay: TimeInterval = 1.0
    /// Total keyframe runtime, used to time the post-resolve idle breath.
    private let animationRuntime: TimeInterval = 4.2

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
                reducedMotionMark
            } else {
                animated
            }
        }
        .frame(width: size, height: size)
    }

    /// With Reduce Motion the brand crane shows the finished app icon; companion
    /// figures show their settled animal drawn statically (no ticking animator).
    @ViewBuilder private var reducedMotionMark: some View {
        if figure.resolvesToAppIcon {
            AppIconMark(size: size)
                .accessibilityLabel("Orifold")
        } else {
            Canvas(opaque: false) { context, canvasSize in
                FoldMarkRenderer.draw(in: &context, size: canvasSize, state: .resolved, figure: figure)
            }
            .accessibilityLabel(figure.accessibilityLabel)
        }
    }

    private var animated: some View {
        Group {
            if interactive {
                Button {
                    replay()
                } label: {
                    keyframeContent
                }
                .buttonStyle(.plain)
                .help("orifoldFoldMark.replay.help")
            } else {
                keyframeContent
            }
        }
        .onAppear {
            guard playCount == 0 else { return }
            // Let the surrounding screen settle, then play the fold.
            let generation = replayGeneration
            DispatchQueue.main.asyncAfter(deadline: .now() + autoplayDelay) {
                guard generation == replayGeneration, playCount == 0 else { return }
                play()
            }
        }
        .accessibilityLabel(figure.accessibilityLabel)
        .accessibilityHint("orifoldFoldMark.replay.accessibilityHint")
    }

    private var keyframeContent: some View {
        KeyframeAnimator(initialValue: FoldState.start, trigger: playCount) { state in
            ZStack {
                Canvas(opaque: false, rendersAsynchronously: true) { context, canvasSize in
                    FoldMarkRenderer.draw(in: &context, size: canvasSize, state: state, figure: figure)
                }

                // Only the brand crane hands off to the real app icon; companion
                // figures settle on the finished animal.
                if figure.resolvesToAppIcon {
                    AppIconMark(size: size)
                        .opacity(state.iconIn)
                }
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
            // Fold 3: a petal fold narrows the packet into a slender triangle.
            KeyframeTrack(\.fold3) {
                LinearKeyframe(0.0, duration: 1.30)
                CubicKeyframe(1.0, duration: 0.45)
            }
            // Blossom: the packet opens into the figure, part by part.
            KeyframeTrack(\.bloomBody) {
                LinearKeyframe(0.0, duration: 1.75)
                CubicKeyframe(1.0, duration: 0.50)
            }
            // The biggest, most dramatic reveal (crane wings / animal ears).
            KeyframeTrack(\.bloomWing) {
                LinearKeyframe(0.0, duration: 1.90)
                CubicKeyframe(1.0, duration: 0.62)
            }
            KeyframeTrack(\.bloomTail) {
                LinearKeyframe(0.0, duration: 2.08)
                CubicKeyframe(1.0, duration: 0.48)
            }
            KeyframeTrack(\.bloomNeck) {
                LinearKeyframe(0.0, duration: 2.20)
                CubicKeyframe(1.0, duration: 0.55)
            }
            KeyframeTrack(\.bloomHead) {
                LinearKeyframe(0.0, duration: 2.52)
                CubicKeyframe(1.0, duration: 0.50)
            }
            // Hold the finished figure for a beat, then dissolve it away…
            KeyframeTrack(\.paperOut) {
                LinearKeyframe(0.0, duration: 3.20)
                CubicKeyframe(1.0, duration: 0.40)
            }
            // …and only then materialize the finished logo on the same tile.
            KeyframeTrack(\.iconIn) {
                LinearKeyframe(0.0, duration: 3.65)
                CubicKeyframe(1.0, duration: 0.45)
            }
        }
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
    /// Staggered blossom phases: the figure opens part by part.
    var bloomBody: Double
    var bloomWing: Double
    var bloomTail: Double
    var bloomNeck: Double
    var bloomHead: Double
    /// Figure dissolves away (the tile stays put). Only used when the figure hands
    /// off to the app icon; companion figures ignore it and stay settled.
    var paperOut: Double
    /// Finished logo materializes on top.
    var iconIn: Double

    static let start = FoldState(
        sheet: 0, fold1: 0, fold2: 0, fold3: 0,
        bloomBody: 0, bloomWing: 0, bloomTail: 0, bloomNeck: 0, bloomHead: 0,
        paperOut: 0, iconIn: 0
    )

    /// The fully-unfolded, settled figure (all folds complete, all parts bloomed, no
    /// dissolve). Used to draw the static Reduce-Motion companion.
    static let resolved = FoldState(
        sheet: 1, fold1: 1, fold2: 1, fold3: 1,
        bloomBody: 1, bloomWing: 1, bloomTail: 1, bloomNeck: 1, bloomHead: 1,
        paperOut: 0, iconIn: 0
    )
}

// MARK: - Figure geometry
//
// All coordinates are tile-unit fractions ((0,0) = tile top-left, (1,1) = bottom-right).
// The opening folds are identical for every figure, so every figure unfolds its parts
// from the same folded-packet outline (`packetTriangle`). Only the blossomed facet and
// crease geometry differs per figure. Facets are painted in array order (back to front).

/// The five staggered blossom groups, reused across every figure (the keyframe timings
/// drive these five tracks). Each figure reinterprets them: for the crane they are the
/// literal body/wing/tail/neck/head; for the animals they map to torso/ears/tail/muzzle/head.
private enum BloomGroup {
    case body, wing, tail, neck, head

    func progress(_ state: FoldState) -> Double {
        switch self {
        case .body: return state.bloomBody
        case .wing: return state.bloomWing
        case .tail: return state.bloomTail
        case .neck: return state.bloomNeck
        case .head: return state.bloomHead
        }
    }
}

/// One paper facet. `hi`/`lo` are paper-tone values (0…1, see `paperTone`) for the two
/// ends of the facet's shading gradient, oriented from `gradFrom` to `gradTo`.
private struct PaperFacet {
    let group: BloomGroup
    let pts: [CGPoint]
    let hi: Double
    let lo: Double
    let gradFrom: CGPoint
    let gradTo: CGPoint
}

/// A fold line. `valley` folds pool soft shadow; ridges catch a thin highlight.
private struct PaperCrease {
    let group: BloomGroup
    let a: CGPoint
    let b: CGPoint
    let valley: Bool
    let strength: Double
}

/// Deep valley that pools soft ambient occlusion.
private struct PaperOcclusion {
    let center: CGPoint
    let radius: Double
    let group: BloomGroup
}

/// One quiet specular streak along a lit ridge, clipped to the silhouette.
private struct PaperSpecular {
    let from: CGPoint
    let to: CGPoint
    let group: BloomGroup
}

/// A complete blossomed figure. The brand crane (`.crane`) hands off to the app icon;
/// the companion animals (`.dog`, `.cat`) settle on the finished figure.
struct PaperFigure {
    /// `nil` for the brand crane; the companion species otherwise.
    fileprivate let species: PetSpecies?
    fileprivate let facets: [PaperFacet]
    fileprivate let creases: [PaperCrease]
    fileprivate let occlusion: [PaperOcclusion]
    fileprivate let packetTriangle: [CGPoint]
    fileprivate let groundCenter: CGPoint
    fileprivate let specular: PaperSpecular?

    /// Only the brand crane dissolves and hands off to the real app icon.
    fileprivate var resolvesToAppIcon: Bool { species == nil }

    var accessibilityLabel: String { species?.accessibilityLabel ?? "Orifold" }

    static func forSpecies(_ species: PetSpecies) -> PaperFigure {
        switch species {
        case .dog: return .dog
        case .cat: return .cat
        }
    }

    /// Outline of the folded packet left by fold 3 (matches the triangle drawn in
    /// `drawFoldStages`'s fold3 branch exactly): creaseTop → br → creaseBot. Every
    /// part unfolds from its nearest point on this outline. Shared by all figures
    /// because the opening folds are identical.
    fileprivate static let packet: [CGPoint] = [
        CGPoint(x: 0.5, y: 0.5),
        CGPoint(x: 0.8, y: 0.8),
        CGPoint(x: 0.5, y: 0.8),
    ]
}

// MARK: Crane geometry
//
// A poised 3/4 crane, head/beak facing right to echo the app icon's arrow direction:
// body centered, two wings up (bright near wing up-left, darker far wing up-right),
// neck rising up-right to a beaked head, tail sweeping down-left.

extension PaperFigure {
    static let crane: PaperFigure = {
        let bodyTop = CGPoint(x: 0.505, y: 0.470)
        let bodyR = CGPoint(x: 0.610, y: 0.600)
        let bodyBot = CGPoint(x: 0.520, y: 0.760)
        let bodyL = CGPoint(x: 0.380, y: 0.600)

        // Paint order: back to front (far wing & tail behind, neck/head, body, near wing).
        let facets: [PaperFacet] = [
            // Far wing — behind, up-right, darker (depth).
            PaperFacet(group: .wing,
                       pts: [CGPoint(x: 0.555, y: 0.485), CGPoint(x: 0.668, y: 0.205), CGPoint(x: 0.655, y: 0.515)],
                       hi: 0.54, lo: 0.34, gradFrom: CGPoint(x: 0.668, y: 0.205), gradTo: CGPoint(x: 0.60, y: 0.515)),
            // Tail — two facets, sweeping down-left.
            PaperFacet(group: .tail,
                       pts: [CGPoint(x: 0.430, y: 0.660), CGPoint(x: 0.150, y: 0.775), CGPoint(x: 0.410, y: 0.705)],
                       hi: 0.86, lo: 0.66, gradFrom: CGPoint(x: 0.430, y: 0.660), gradTo: CGPoint(x: 0.150, y: 0.775)),
            PaperFacet(group: .tail,
                       pts: [CGPoint(x: 0.410, y: 0.705), CGPoint(x: 0.150, y: 0.775), CGPoint(x: 0.395, y: 0.745)],
                       hi: 0.60, lo: 0.44, gradFrom: CGPoint(x: 0.410, y: 0.705), gradTo: CGPoint(x: 0.150, y: 0.775)),
            // Body — shadowed back + lit front, split on the keel.
            PaperFacet(group: .body,
                       pts: [bodyTop, bodyBot, bodyL],
                       hi: 0.72, lo: 0.52, gradFrom: bodyTop, gradTo: bodyL),
            PaperFacet(group: .body,
                       pts: [bodyTop, bodyR, bodyBot],
                       hi: 1.00, lo: 0.80, gradFrom: bodyTop, gradTo: bodyBot),
            // Neck — lower + upper, two-tone, rising up-right.
            PaperFacet(group: .neck,
                       pts: [CGPoint(x: 0.560, y: 0.520), CGPoint(x: 0.720, y: 0.300), CGPoint(x: 0.610, y: 0.560)],
                       hi: 0.98, lo: 0.80, gradFrom: CGPoint(x: 0.720, y: 0.300), gradTo: CGPoint(x: 0.60, y: 0.560)),
            PaperFacet(group: .neck,
                       pts: [CGPoint(x: 0.610, y: 0.560), CGPoint(x: 0.720, y: 0.300), CGPoint(x: 0.665, y: 0.575)],
                       hi: 0.80, lo: 0.62, gradFrom: CGPoint(x: 0.720, y: 0.300), gradTo: CGPoint(x: 0.66, y: 0.575)),
            // Head + beak (points right).
            PaperFacet(group: .head,
                       pts: [CGPoint(x: 0.720, y: 0.300), CGPoint(x: 0.762, y: 0.240), CGPoint(x: 0.700, y: 0.345)],
                       hi: 0.94, lo: 0.78, gradFrom: CGPoint(x: 0.762, y: 0.240), gradTo: CGPoint(x: 0.700, y: 0.345)),
            PaperFacet(group: .head,
                       pts: [CGPoint(x: 0.762, y: 0.240), CGPoint(x: 0.850, y: 0.300), CGPoint(x: 0.712, y: 0.320)],
                       hi: 0.90, lo: 0.72, gradFrom: CGPoint(x: 0.850, y: 0.300), gradTo: CGPoint(x: 0.712, y: 0.320)),
            // Near wing — shadowed back + bright front, sweeping up-left.
            PaperFacet(group: .wing,
                       pts: [CGPoint(x: 0.560, y: 0.520), CGPoint(x: 0.235, y: 0.130), CGPoint(x: 0.420, y: 0.545)],
                       hi: 0.78, lo: 0.58, gradFrom: CGPoint(x: 0.235, y: 0.130), gradTo: CGPoint(x: 0.46, y: 0.55)),
            PaperFacet(group: .wing,
                       pts: [CGPoint(x: 0.650, y: 0.520), CGPoint(x: 0.235, y: 0.130), CGPoint(x: 0.560, y: 0.520)],
                       hi: 1.00, lo: 0.82, gradFrom: CGPoint(x: 0.235, y: 0.130), gradTo: CGPoint(x: 0.65, y: 0.52)),
        ]

        let creases: [PaperCrease] = [
            PaperCrease(group: .body, a: bodyTop, b: bodyBot, valley: true, strength: 1.0),                                                  // body keel
            PaperCrease(group: .neck, a: CGPoint(x: 0.560, y: 0.520), b: CGPoint(x: 0.720, y: 0.300), valley: false, strength: 0.8),         // neck ridge
            PaperCrease(group: .wing, a: CGPoint(x: 0.560, y: 0.520), b: CGPoint(x: 0.235, y: 0.130), valley: true, strength: 0.9),          // near-wing keel
            PaperCrease(group: .wing, a: CGPoint(x: 0.420, y: 0.545), b: CGPoint(x: 0.650, y: 0.520), valley: false, strength: 0.6),         // wing root ridge
            PaperCrease(group: .tail, a: CGPoint(x: 0.410, y: 0.705), b: CGPoint(x: 0.150, y: 0.775), valley: true, strength: 0.5),          // tail median
            PaperCrease(group: .head, a: CGPoint(x: 0.762, y: 0.240), b: CGPoint(x: 0.712, y: 0.320), valley: false, strength: 0.5),         // head fold
            PaperCrease(group: .wing, a: CGPoint(x: 0.360, y: 0.360), b: CGPoint(x: 0.520, y: 0.510), valley: false, strength: 0.45),        // near-wing secondary fold
            PaperCrease(group: .wing, a: CGPoint(x: 0.610, y: 0.505), b: CGPoint(x: 0.660, y: 0.300), valley: true, strength: 0.4),          // far-wing base valley
        ]

        let occlusion: [PaperOcclusion] = [
            PaperOcclusion(center: CGPoint(x: 0.52, y: 0.55), radius: 0.16, group: .wing),
            PaperOcclusion(center: CGPoint(x: 0.60, y: 0.53), radius: 0.11, group: .neck),
            PaperOcclusion(center: CGPoint(x: 0.47, y: 0.70), radius: 0.10, group: .body),
        ]

        return PaperFigure(
            species: nil,
            facets: facets,
            creases: creases,
            occlusion: occlusion,
            packetTriangle: PaperFigure.packet,
            groundCenter: CGPoint(x: 0.48, y: 0.79),
            specular: PaperSpecular(from: CGPoint(x: 0.560, y: 0.520), to: CGPoint(x: 0.30, y: 0.235), group: .wing)
        )
    }()
}

// MARK: Dog geometry
//
// A friendly seated shiba-style origami dog, facing right (echoing the icon's arrow
// direction): a broad two-tone head with two upright pricked ears, a short muzzle
// pointing right, a seated haunch below, and a curled tail sweeping up the back.
// Group mapping: head→head, ears→wing, muzzle→neck, torso→body, tail→tail.

extension PaperFigure {
    static let dog: PaperFigure = {
        let headTop = CGPoint(x: 0.500, y: 0.300)
        let headR = CGPoint(x: 0.635, y: 0.440)
        let headBot = CGPoint(x: 0.500, y: 0.575)
        let headL = CGPoint(x: 0.375, y: 0.440)

        let facets: [PaperFacet] = [
            // Far ear — behind, up-right, darker (depth).
            PaperFacet(group: .wing,
                       pts: [CGPoint(x: 0.560, y: 0.320), CGPoint(x: 0.680, y: 0.150), CGPoint(x: 0.610, y: 0.400)],
                       hi: 0.54, lo: 0.34, gradFrom: CGPoint(x: 0.680, y: 0.150), gradTo: CGPoint(x: 0.60, y: 0.400)),
            // Tail — a small curl behind the haunch, kept low and left so it reads
            // separately from the ears above rather than crowding them.
            PaperFacet(group: .tail,
                       pts: [CGPoint(x: 0.345, y: 0.665), CGPoint(x: 0.225, y: 0.600), CGPoint(x: 0.375, y: 0.615)],
                       hi: 0.72, lo: 0.52, gradFrom: CGPoint(x: 0.375, y: 0.615), gradTo: CGPoint(x: 0.225, y: 0.600)),
            PaperFacet(group: .tail,
                       pts: [CGPoint(x: 0.345, y: 0.665), CGPoint(x: 0.375, y: 0.615), CGPoint(x: 0.410, y: 0.675)],
                       hi: 0.60, lo: 0.42, gradFrom: CGPoint(x: 0.410, y: 0.675), gradTo: CGPoint(x: 0.345, y: 0.665)),
            // Torso / seated haunch — shadowed back + lit front.
            PaperFacet(group: .body,
                       pts: [CGPoint(x: 0.455, y: 0.545), CGPoint(x: 0.455, y: 0.810), CGPoint(x: 0.300, y: 0.740)],
                       hi: 0.62, lo: 0.42, gradFrom: CGPoint(x: 0.455, y: 0.545), gradTo: CGPoint(x: 0.300, y: 0.740)),
            PaperFacet(group: .body,
                       pts: [CGPoint(x: 0.455, y: 0.545), CGPoint(x: 0.585, y: 0.795), CGPoint(x: 0.455, y: 0.810)],
                       hi: 0.84, lo: 0.62, gradFrom: CGPoint(x: 0.455, y: 0.545), gradTo: CGPoint(x: 0.585, y: 0.795)),
            // Head — shadowed left + lit right, split on the muzzle keel.
            PaperFacet(group: .head,
                       pts: [headTop, headBot, headL],
                       hi: 0.72, lo: 0.52, gradFrom: headTop, gradTo: headL),
            PaperFacet(group: .head,
                       pts: [headTop, headR, headBot],
                       hi: 1.00, lo: 0.80, gradFrom: headTop, gradTo: headBot),
            // Muzzle — short wedge pointing right, two-tone.
            PaperFacet(group: .neck,
                       pts: [CGPoint(x: 0.585, y: 0.410), CGPoint(x: 0.745, y: 0.500), CGPoint(x: 0.590, y: 0.520)],
                       hi: 0.96, lo: 0.78, gradFrom: CGPoint(x: 0.745, y: 0.500), gradTo: CGPoint(x: 0.59, y: 0.520)),
            PaperFacet(group: .neck,
                       pts: [CGPoint(x: 0.590, y: 0.520), CGPoint(x: 0.745, y: 0.500), CGPoint(x: 0.620, y: 0.555)],
                       hi: 0.78, lo: 0.60, gradFrom: CGPoint(x: 0.745, y: 0.500), gradTo: CGPoint(x: 0.62, y: 0.555)),
            // Near ear — bright, pricked up (slightly out-left), in front of the head.
            PaperFacet(group: .wing,
                       pts: [CGPoint(x: 0.475, y: 0.310), CGPoint(x: 0.395, y: 0.135), CGPoint(x: 0.455, y: 0.420)],
                       hi: 0.86, lo: 0.62, gradFrom: CGPoint(x: 0.395, y: 0.135), gradTo: CGPoint(x: 0.47, y: 0.420)),
        ]

        let creases: [PaperCrease] = [
            PaperCrease(group: .head, a: headTop, b: headBot, valley: true, strength: 1.0),                                          // head keel
            PaperCrease(group: .neck, a: CGPoint(x: 0.585, y: 0.410), b: CGPoint(x: 0.745, y: 0.500), valley: false, strength: 0.6), // muzzle ridge
            PaperCrease(group: .wing, a: CGPoint(x: 0.475, y: 0.310), b: CGPoint(x: 0.395, y: 0.135), valley: true, strength: 0.7),  // near-ear fold
            PaperCrease(group: .wing, a: CGPoint(x: 0.560, y: 0.320), b: CGPoint(x: 0.680, y: 0.150), valley: true, strength: 0.4),  // far-ear fold
            PaperCrease(group: .body, a: CGPoint(x: 0.455, y: 0.545), b: CGPoint(x: 0.455, y: 0.810), valley: true, strength: 0.5),  // chest keel
            PaperCrease(group: .tail, a: CGPoint(x: 0.375, y: 0.615), b: CGPoint(x: 0.225, y: 0.600), valley: false, strength: 0.4), // tail median
        ]

        let occlusion: [PaperOcclusion] = [
            PaperOcclusion(center: CGPoint(x: 0.50, y: 0.44), radius: 0.13, group: .head),
            PaperOcclusion(center: CGPoint(x: 0.45, y: 0.60), radius: 0.10, group: .body),
            PaperOcclusion(center: CGPoint(x: 0.50, y: 0.33), radius: 0.08, group: .wing),
        ]

        return PaperFigure(
            species: .dog,
            facets: facets,
            creases: creases,
            occlusion: occlusion,
            packetTriangle: PaperFigure.packet,
            groundCenter: CGPoint(x: 0.45, y: 0.83),
            specular: PaperSpecular(from: CGPoint(x: 0.500, y: 0.300), to: CGPoint(x: 0.430, y: 0.430), group: .head)
        )
    }()
}

// MARK: Cat geometry
//
// A composed seated origami cat, facing right: a narrow two-tone head crowned by two
// tall pointed ears, a small flat muzzle, a slim upright torso, and a long tail curling
// along the front paws. Group mapping matches the dog (head→head, ears→wing,
// muzzle→neck, torso→body, tail→tail).

extension PaperFigure {
    static let cat: PaperFigure = {
        let headTop = CGPoint(x: 0.500, y: 0.320)
        let headR = CGPoint(x: 0.605, y: 0.450)
        let headBot = CGPoint(x: 0.500, y: 0.560)
        let headL = CGPoint(x: 0.400, y: 0.450)

        let facets: [PaperFacet] = [
            // Far ear — tall pointed triangle behind, darker.
            PaperFacet(group: .wing,
                       pts: [CGPoint(x: 0.560, y: 0.320), CGPoint(x: 0.650, y: 0.130), CGPoint(x: 0.505, y: 0.315)],
                       hi: 0.52, lo: 0.32, gradFrom: CGPoint(x: 0.650, y: 0.130), gradTo: CGPoint(x: 0.55, y: 0.320)),
            // Tail — long curl sweeping along the front, two facets.
            PaperFacet(group: .tail,
                       pts: [CGPoint(x: 0.455, y: 0.775), CGPoint(x: 0.680, y: 0.790), CGPoint(x: 0.500, y: 0.700)],
                       hi: 0.72, lo: 0.52, gradFrom: CGPoint(x: 0.500, y: 0.700), gradTo: CGPoint(x: 0.680, y: 0.790)),
            PaperFacet(group: .tail,
                       pts: [CGPoint(x: 0.500, y: 0.700), CGPoint(x: 0.680, y: 0.790), CGPoint(x: 0.615, y: 0.685)],
                       hi: 0.60, lo: 0.42, gradFrom: CGPoint(x: 0.615, y: 0.685), gradTo: CGPoint(x: 0.680, y: 0.790)),
            // Torso — slim seated body, shadowed back + lit front.
            PaperFacet(group: .body,
                       pts: [CGPoint(x: 0.470, y: 0.540), CGPoint(x: 0.470, y: 0.795), CGPoint(x: 0.360, y: 0.720)],
                       hi: 0.62, lo: 0.42, gradFrom: CGPoint(x: 0.470, y: 0.540), gradTo: CGPoint(x: 0.360, y: 0.720)),
            PaperFacet(group: .body,
                       pts: [CGPoint(x: 0.470, y: 0.540), CGPoint(x: 0.560, y: 0.790), CGPoint(x: 0.470, y: 0.795)],
                       hi: 0.84, lo: 0.62, gradFrom: CGPoint(x: 0.470, y: 0.540), gradTo: CGPoint(x: 0.560, y: 0.790)),
            // Head — shadowed left + lit right, split on the keel.
            PaperFacet(group: .head,
                       pts: [headTop, headBot, headL],
                       hi: 0.72, lo: 0.52, gradFrom: headTop, gradTo: headL),
            PaperFacet(group: .head,
                       pts: [headTop, headR, headBot],
                       hi: 1.00, lo: 0.80, gradFrom: headTop, gradTo: headBot),
            // Muzzle — small flat wedge, two-tone.
            PaperFacet(group: .neck,
                       pts: [CGPoint(x: 0.550, y: 0.455), CGPoint(x: 0.650, y: 0.510), CGPoint(x: 0.545, y: 0.540)],
                       hi: 0.96, lo: 0.78, gradFrom: CGPoint(x: 0.650, y: 0.510), gradTo: CGPoint(x: 0.545, y: 0.540)),
            PaperFacet(group: .neck,
                       pts: [CGPoint(x: 0.545, y: 0.540), CGPoint(x: 0.650, y: 0.510), CGPoint(x: 0.580, y: 0.545)],
                       hi: 0.78, lo: 0.60, gradFrom: CGPoint(x: 0.650, y: 0.510), gradTo: CGPoint(x: 0.58, y: 0.545)),
            // Near ear — bright tall pointed triangle in front.
            PaperFacet(group: .wing,
                       pts: [CGPoint(x: 0.455, y: 0.320), CGPoint(x: 0.360, y: 0.120), CGPoint(x: 0.500, y: 0.320)],
                       hi: 0.88, lo: 0.64, gradFrom: CGPoint(x: 0.360, y: 0.120), gradTo: CGPoint(x: 0.48, y: 0.320)),
        ]

        let creases: [PaperCrease] = [
            PaperCrease(group: .head, a: headTop, b: headBot, valley: true, strength: 1.0),                                          // head keel
            PaperCrease(group: .neck, a: CGPoint(x: 0.550, y: 0.455), b: CGPoint(x: 0.650, y: 0.510), valley: false, strength: 0.5), // muzzle ridge
            PaperCrease(group: .wing, a: CGPoint(x: 0.455, y: 0.320), b: CGPoint(x: 0.360, y: 0.120), valley: true, strength: 0.7),  // near-ear fold
            PaperCrease(group: .wing, a: CGPoint(x: 0.560, y: 0.320), b: CGPoint(x: 0.650, y: 0.130), valley: true, strength: 0.4),  // far-ear fold
            PaperCrease(group: .body, a: CGPoint(x: 0.470, y: 0.540), b: CGPoint(x: 0.470, y: 0.795), valley: true, strength: 0.5),  // chest keel
            PaperCrease(group: .tail, a: CGPoint(x: 0.500, y: 0.700), b: CGPoint(x: 0.680, y: 0.790), valley: false, strength: 0.4), // tail median
        ]

        let occlusion: [PaperOcclusion] = [
            PaperOcclusion(center: CGPoint(x: 0.50, y: 0.46), radius: 0.11, group: .head),
            PaperOcclusion(center: CGPoint(x: 0.46, y: 0.60), radius: 0.09, group: .body),
            PaperOcclusion(center: CGPoint(x: 0.50, y: 0.33), radius: 0.07, group: .wing),
        ]

        return PaperFigure(
            species: .cat,
            facets: facets,
            creases: creases,
            occlusion: occlusion,
            packetTriangle: PaperFigure.packet,
            groundCenter: CGPoint(x: 0.47, y: 0.83),
            specular: PaperSpecular(from: CGPoint(x: 0.500, y: 0.320), to: CGPoint(x: 0.440, y: 0.440), group: .head)
        )
    }()
}

// MARK: - Renderer

private enum FoldMarkRenderer {
    static func draw(in context: inout GraphicsContext, size: CGSize, state: FoldState, figure: PaperFigure) {
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

        drawTile(in: &context, path: tilePath, rect: tileRect, side: side)

        // Keep all paper contained within the rounded tile.
        context.clip(to: tilePath)

        // The paper fades out on its own while the tile stays put, so the incoming
        // logo hands off on a steady ground rather than crossfading two shapes. Only
        // the brand crane fades; companion figures ignore `paperOut` and stay settled.
        let fade = figure.resolvesToAppIcon ? state.paperOut : 0
        let paperOpacity = state.sheet * (1 - fade)
        guard paperOpacity > 0.001 else { return }
        context.opacity = paperOpacity

        // Convenience: tile-unit → canvas points.
        func at(_ p: CGPoint) -> CGPoint {
            CGPoint(x: tileRect.minX + p.x * side, y: tileRect.minY + p.y * side)
        }

        drawFoldStages(in: &context, side: side, state: state, at: at)
        drawFigure(in: &context, tileRect: tileRect, side: side, state: state, figure: figure, at: at)
    }

    // MARK: Opening folds (square → triangle → wide packet → slender triangle)

    private static func drawFoldStages(
        in context: inout GraphicsContext,
        side: CGFloat,
        state: FoldState,
        at: (CGPoint) -> CGPoint
    ) {
        // The folded packet dissolves into the emerging figure body.
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
                // Petal fold: tr folds down across creaseTop–crease3 onto br,
                // collapsing the wide packet into a slender triangle.
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

    // MARK: Figure blossom

    private static func drawFigure(
        in context: inout GraphicsContext,
        tileRect: CGRect,
        side: CGFloat,
        state: FoldState,
        figure: PaperFigure,
        at: (CGPoint) -> CGPoint
    ) {
        let overall = max(state.bloomBody, state.bloomWing, state.bloomTail, state.bloomNeck, state.bloomHead)
        guard overall > 0.001 else { return }

        // Contact shadow beneath the settling figure — a single soft ellipse, darkest
        // at its core and falling off smoothly, so it reads as grounded without
        // looking like a separate dark puddle.
        let groundOpacity = 0.15 * state.bloomBody
        if groundOpacity > 0.005 {
            let center = at(figure.groundCenter)
            let rx = side * 0.22, ry = side * 0.04
            context.fill(
                Path(ellipseIn: CGRect(x: center.x - rx, y: center.y - ry, width: rx * 2, height: ry * 2)),
                with: .radialGradient(
                    Gradient(stops: [
                        .init(color: .black.opacity(groundOpacity), location: 0),
                        .init(color: .black.opacity(groundOpacity * 0.4), location: 0.6),
                        .init(color: .clear, location: 1),
                    ]),
                    center: center, startRadius: 0, endRadius: rx
                )
            )
        }

        // Resolve each visible facet's current (unfolding) path.
        var silhouette = Path()
        var visible: [(facet: PaperFacet, path: Path, opacity: Double)] = []
        for facet in figure.facets {
            let p = facet.group.progress(state)
            guard p > 0.001 else { continue }
            let eased = ease(p)
            let path = unfoldPath(facet.pts, progress: eased, packet: figure.packetTriangle, at: at)
            silhouette.addPath(path)
            visible.append((facet, path, min(1, eased * 1.6)))
        }
        guard !visible.isEmpty else { return }

        // One soft drop shadow for the whole figure, then facets tile over it.
        context.drawLayer { layer in
            layer.addFilter(.shadow(color: .black.opacity(0.22 * overall), radius: side * 0.03, x: side * 0.006, y: side * 0.016))
            layer.fill(silhouette, with: .color(.white))
        }

        // A soft rim glow behind the silhouette lifts the paper off the tile — half
        // of this blurred stroke sits under the facets about to be painted, half
        // bleeds just past the outer edge as a faint halo.
        context.drawLayer { layer in
            layer.opacity = 0.35 * overall
            layer.addFilter(.blur(radius: side * 0.006))
            layer.stroke(silhouette, with: .color(.white.opacity(0.85)), lineWidth: side * 0.010)
        }

        // Facets — warm-ivory paper shaded against cool light, with a crisp hairline
        // at each facet's own edge so adjoining panels read as distinct planes.
        // Opacity is baked into the fill/stroke colors rather than a `drawLayer`
        // wrapper: with up to ten-odd facets animating in the same frame, that
        // many offscreen layer allocations every frame was a real cost sitting
        // right in the busiest part of the animation. A plain fill/stroke with
        // pre-multiplied alpha produces identical pixels without it.
        for entry in visible {
            context.fill(entry.path, with: .linearGradient(
                Gradient(colors: [paperTone(entry.facet.hi).opacity(entry.opacity), paperTone(entry.facet.lo).opacity(entry.opacity)]),
                startPoint: at(entry.facet.gradFrom), endPoint: at(entry.facet.gradTo)
            ))
            context.stroke(entry.path, with: .color(.black.opacity(0.05 * entry.opacity)), lineWidth: max(0.5, side * 0.0022))
        }

        // One quiet specular streak where the light catches the paper most directly,
        // along a lit ridge — clipped tight to the silhouette so it reads as a
        // highlight on the paper, not a glow floating past its edge.
        if let specular = figure.specular {
            let specularP = specular.group.progress(state)
            if specularP > 0.05 {
                context.drawLayer { layer in
                    layer.clip(to: silhouette)
                    var streak = Path()
                    streak.move(to: at(specular.from)); streak.addLine(to: at(specular.to))
                    layer.addFilter(.blur(radius: side * 0.014))
                    layer.stroke(streak, with: .color(.white.opacity(0.32 * ease(specularP))),
                                style: StrokeStyle(lineWidth: side * 0.05, lineCap: .round))
                }
            }
        }

        // Ambient occlusion pooling in the deep fold valleys.
        context.drawLayer { layer in
            layer.clip(to: silhouette)
            for occ in figure.occlusion {
                let p = occ.group.progress(state)
                guard p > 0.05 else { continue }
                let c = at(occ.center)
                let r = side * occ.radius
                layer.fill(
                    Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                    with: .radialGradient(
                        Gradient(colors: [Color(.sRGB, red: 0.24, green: 0.30, blue: 0.42, opacity: 0.16 * ease(p)), .clear]),
                        center: c, startRadius: 0, endRadius: r
                    )
                )
            }
        }

        // Fold creases as a paired bevel — a dark shadow hairline immediately beside
        // a bright ridge hairline, offset to either side of the fold — reads as an
        // embossed, engraved seam rather than a single flat stroke.
        for crease in figure.creases {
            let p = crease.group.progress(state)
            guard p > 0.06 else { continue }
            let a = at(crease.a), b = at(crease.b)
            let fade = min(1, ease(p) * 1.5)
            let n = perpendicular(crease.a, crease.b)
            let offset = max(0.5, side * 0.0028)
            let shadowOffset = CGPoint(x: n.x * offset, y: n.y * offset)
            let liftOffset = CGPoint(x: -n.x * offset, y: -n.y * offset)

            var shadowLine = Path()
            shadowLine.move(to: CGPoint(x: a.x + shadowOffset.x, y: a.y + shadowOffset.y))
            shadowLine.addLine(to: CGPoint(x: b.x + shadowOffset.x, y: b.y + shadowOffset.y))
            context.stroke(shadowLine, with: .color(Color(.sRGB, red: 0.24, green: 0.29, blue: 0.40, opacity: (crease.valley ? 0.30 : 0.16) * crease.strength * fade)),
                           style: StrokeStyle(lineWidth: max(0.7, side * 0.0042), lineCap: .round))

            var liftLine = Path()
            liftLine.move(to: CGPoint(x: a.x + liftOffset.x, y: a.y + liftOffset.y))
            liftLine.addLine(to: CGPoint(x: b.x + liftOffset.x, y: b.y + liftOffset.y))
            context.stroke(liftLine, with: .color(.white.opacity((crease.valley ? 0.35 : 0.60) * crease.strength * fade)),
                           style: StrokeStyle(lineWidth: max(0.5, side * 0.0028), lineCap: .round))
        }

        // Washi paper grain + top-light sheen, clipped to the figure. The grain's
        // fiber positions are hashed from their index and never change once
        // computed, so `grainFibers` builds the two fiber paths (in unit tile
        // space) exactly once and this just maps them into canvas space with a
        // single affine transform per color — not 100+ hash/trig calls and Path
        // allocations every single animation frame.
        context.drawLayer { layer in
            layer.clip(to: silhouette)
            layer.opacity = overall

            let transform = CGAffineTransform(a: side, b: 0, c: 0, d: side, tx: tileRect.minX, ty: tileRect.minY)
            let lineWidth = max(0.5, side * 0.0016)
            layer.stroke(grainFibers.dark.applying(transform), with: .color(.black.opacity(0.05)), lineWidth: lineWidth)
            layer.stroke(grainFibers.light.applying(transform), with: .color(.white.opacity(0.07)), lineWidth: lineWidth)

            layer.fill(
                Path(CGRect(x: at(.zero).x, y: at(.zero).y, width: side, height: side)),
                with: .linearGradient(
                    Gradient(colors: [.white.opacity(0.10), .clear, .black.opacity(0.04)]),
                    startPoint: at(CGPoint(x: 0.78, y: 0.05)),
                    endPoint: at(CGPoint(x: 0.25, y: 0.95))
                )
            )
        }
    }

    /// Grain fiber segments in unit tile space (0...1), split into two combined
    /// paths by tint. Built once on first use and reused for the process's
    /// lifetime — the hash-based positions are deterministic, so recomputing
    /// them (with multiple hash calls and trig per fiber) every frame was pure
    /// waste in the single most frequently redrawn layer of the animation.
    private static let grainFibers: (dark: Path, light: Path) = {
        let fiberCount = 128
        var dark = Path()
        var light = Path()
        for i in 0..<fiberCount {
            let fi = Double(i)
            let hx = abs(hash(fi * 12.9898))
            let hy = abs(hash(fi * 78.233))
            let angle = hash(fi * 3.17) * 0.5   // near-horizontal fibers
            let len = 0.02 * (0.5 + abs(hash(fi * 5.1)))
            let start = CGPoint(x: hx, y: hy)
            let end = CGPoint(x: hx + cos(angle) * len, y: hy + sin(angle) * len)
            if i % 3 == 0 {
                dark.move(to: start); dark.addLine(to: end)
            } else {
                light.move(to: start); light.addLine(to: end)
            }
        }
        return (dark, light)
    }()

    /// Warm-ivory paper tone. `v` in 0…1: 1 = brightest lit paper, 0 = deepest fold
    /// shadow. Highlights lean warm, shadows lean cool, as real paper does under a
    /// cool sky light.
    private static func paperTone(_ v: Double) -> Color {
        let t = max(0, min(1, v))
        let warm = (r: 1.00, g: 0.985, b: 0.96)
        let cool = (r: 0.72, g: 0.76, b: 0.82)
        return Color(.sRGB,
                     red: cool.r + (warm.r - cool.r) * t,
                     green: cool.g + (warm.g - cool.g) * t,
                     blue: cool.b + (warm.b - cool.b) * t,
                     opacity: 1)
    }

    /// Unfolds a facet's points from their nearest anchor on the folded packet's
    /// outline out to their final tile-unit positions, then converts to canvas space.
    private static func unfoldPath(_ pts: [CGPoint], progress: Double, packet: [CGPoint], at: (CGPoint) -> CGPoint) -> Path {
        var path = Path()
        let resolved = pts.map { pt -> CGPoint in
            let anchor = nearestPointOnPolygon(pt, polygon: packet)
            return at(lerp(anchor, pt, t: progress))
        }
        path.move(to: resolved[0])
        for pt in resolved.dropFirst() { path.addLine(to: pt) }
        path.closeSubpath()
        return path
    }

    // MARK: Tile

    private static func drawTile(in context: inout GraphicsContext, path: Path, rect: CGRect, side: CGFloat) {
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
                startPoint: CGPoint(x: rect.minX, y: rect.maxY),
                endPoint: CGPoint(x: rect.maxX, y: rect.minY)
            )
        )

        // Faint moon disc behind the figure — a quiet Japanese note (tsukimi).
        let moonCenter = CGPoint(x: rect.minX + rect.width * 0.71, y: rect.minY + rect.height * 0.30)
        let moonRadius = side * 0.20
        context.fill(
            Path(ellipseIn: CGRect(x: moonCenter.x - moonRadius, y: moonCenter.y - moonRadius, width: moonRadius * 2, height: moonRadius * 2)),
            with: .radialGradient(
                Gradient(colors: [
                    Color(.sRGB, red: 0.86, green: 0.95, blue: 0.97, opacity: 0.26),
                    Color(.sRGB, red: 0.70, green: 0.90, blue: 0.95, opacity: 0.0)
                ]),
                center: moonCenter, startRadius: 0, endRadius: moonRadius
            )
        )

        // Soft teal glow toward the top-right, as in the icon.
        let glowRadius = rect.width * 0.75
        let glowCenter = CGPoint(x: rect.minX + rect.width * 0.82, y: rect.minY + rect.height * 0.20)
        context.fill(
            path,
            with: .radialGradient(
                Gradient(colors: [
                    Color(.sRGB, red: 0.50, green: 0.82, blue: 0.86, opacity: 0.22),
                    Color.clear
                ]),
                center: glowCenter, startRadius: 0, endRadius: glowRadius
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

    /// Deterministic hash in roughly [-1, 1] — a fract(sin(x)*k) style pseudo-random.
    private static func hash(_ x: Double) -> Double {
        let v = sin(x) * 43758.5453
        return (v - v.rounded(.down)) * 2 - 1
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

    /// Unit vector perpendicular to a–b (tile-unit space; direction is arbitrary but
    /// consistent, which is all the crease bevel needs).
    private static func perpendicular(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
        let dx = b.x - a.x, dy = b.y - a.y
        let len = max(0.0001, (dx * dx + dy * dy).squareRoot())
        return CGPoint(x: -dy / len, y: dx / len)
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
