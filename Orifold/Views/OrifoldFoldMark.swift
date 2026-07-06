import SwiftUI
import AppKit

/// Brand/companion fold animation: a sheet of paper folds through three deliberate
/// creases — a diagonal valley fold, a half fold, a petal fold — then blossoms into a
/// detailed origami figure that stays **alive**. The **figure** is pluggable
/// (`PaperFigure`): the app's brand mark blooms into a crane (tsuru) and hands off to
/// the real app icon, while the dashboard companion blooms into the user's chosen
/// **dog** or **cat**, settles, and then keeps breathing and moving — the dog wags its
/// tail, the cat twitches its ears.
///
/// The whole run is driven by a single continuous clock (`TimelineView`), so the fold
/// can be **replayed on demand** (a tap, or every time a feature fires) and the settled
/// figure can animate forever without re-instantiating anything. The opening folds,
/// tile, paper shading, grain, contact shadow, and crease bevel are shared across every
/// figure; each figure supplies its own facet/crease geometry, a paper **palette**
/// (warm kraft for the dog, cool slate for the cat, warm ivory for the crane), and an
/// optional **idle wag** (which body group sways, around which pivot, how far, how fast).
///
/// Everything is vector-drawn in a `Canvas`. The three opening folds are physically
/// simulated (each flap reflects across its crease and rides a sine "lift" shadow). The
/// figure then emerges as a staggered per-part reveal — each facet unfolding from its
/// nearest point on the folded packet's actual outline — and is richly rendered like
/// real folded washi: two-tone facets shaded against a cool light, ambient occlusion
/// pooling in the fold valleys, crisp ridge highlights, tiny dark eye/nose facets, a
/// deterministic paper-fiber grain clipped to the silhouette, a contact shadow, and a
/// faint moon disc behind it (a quiet Japanese note).
///
/// For the brand crane the hand-off to the finished logo is sequenced, not crossfaded;
/// the dog/cat companions skip the hand-off and settle on the finished animal, then idle.
/// The crane stops ticking once it resolves (it has no idle wag), so the wordmark costs
/// nothing at rest; the companions keep a lightweight ~30fps idle. With Reduce Motion the
/// animation is skipped entirely and the finished figure is shown immediately.
struct OrifoldFoldMark: View {
    var size: CGFloat = 80
    /// When embedded inside a caller's own tap target (e.g. the dashboard pet's
    /// button), disable the mark's own replay button so tap gestures don't nest.
    var interactive: Bool = true
    /// Which paper figure the fold blossoms into. Defaults to the brand crane so the
    /// wordmark and every existing call site are unchanged.
    var figure: PaperFigure = .crane
    /// Bumping this replays the fold from the start — used to re-fold the companion
    /// each time a feature fires.
    var replayTrigger: Int = 0
    /// 0…1: how "excited" the companion should be right now — driven by the caller's
    /// own hover/proximity state (e.g. the workspace chip while the cursor is near).
    /// Only wags marked `excitable` (the dog's tail) respond to it; everything else
    /// ignores it. Smoothed internally so callers can just flip it on `onHover`.
    var excitement: Double = 0

    /// Delay before the fold plays on first appearance, so the screen settles first.
    private let autoplayDelay: TimeInterval = 1.0
    /// Total fold runtime (through the icon hand-off), used to time idle hand-off.
    private let animationRuntime: TimeInterval = 4.3
    /// How long the excitement ramp takes to catch up to a new target — fast enough
    /// to feel responsive, slow enough not to look like a frequency snap.
    private let excitementRampDuration: TimeInterval = 0.35

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var foldStart: Date?
    @State private var isFoldRunning = false
    @State private var hasScheduledFirstPlay = false
    @State private var playGeneration = 0
    @State private var excitementRampStart = Date.distantPast
    @State private var excitementRampFrom: Double = 0
    @State private var excitementTarget: Double = 0

    private var shouldReduceMotion: Bool {
        reduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// Pause the clock when there's nothing to animate: the crane has no idle wag, so
    /// once its fold resolves it stops ticking. Companions always have an idle wag, so
    /// they keep breathing/wagging.
    private var isPaused: Bool {
        figure.idle.isEmpty && !isFoldRunning
    }

    var body: some View {
        Group {
            if shouldReduceMotion {
                reducedMotionMark
            } else if interactive {
                Button {
                    replay()
                } label: {
                    animatedMark
                }
                .buttonStyle(.plain)
                .help("orifoldFoldMark.replay.help")
            } else {
                animatedMark
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(figure.accessibilityLabel)
        .accessibilityHint(interactive && !shouldReduceMotion ? "orifoldFoldMark.replay.accessibilityHint" : "")
        .onAppear(perform: scheduleFirstPlay)
        .onChange(of: replayTrigger) { _, _ in replay() }
        .onChange(of: excitement) { _, newValue in
            excitementRampFrom = currentExcitement(at: Date())
            excitementRampStart = Date()
            excitementTarget = newValue
        }
    }

    /// The smoothed excitement value at a given moment, ramping from wherever the
    /// last ramp started toward its target — avoids an abrupt frequency jump when a
    /// hover flips the caller's `excitement` on or off.
    private func currentExcitement(at date: Date) -> Double {
        let t = FoldMarkRenderer.smoothstep(date.timeIntervalSince(excitementRampStart) / excitementRampDuration)
        return excitementRampFrom + (excitementTarget - excitementRampFrom) * t
    }

    private var animatedMark: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: isPaused)) { timeline in
            let elapsed = foldStart.map { max(0, timeline.date.timeIntervalSince($0)) }
            let state = elapsed.map {
                FoldState.state(atElapsed: $0, resolvesToAppIcon: figure.resolvesToAppIcon)
            } ?? .start
            let intensity = elapsed.map(idleIntensity(atElapsed:)) ?? 1
            let idle = IdlePhase(phase: timeline.date.timeIntervalSinceReferenceDate, intensity: intensity,
                                 excitement: currentExcitement(at: timeline.date))

            ZStack {
                Canvas(opaque: false, rendersAsynchronously: true) { context, canvasSize in
                    FoldMarkRenderer.draw(in: &context, size: canvasSize, state: state, figure: figure, idle: idle)
                }
                // Only the brand crane hands off to the real app icon.
                if figure.resolvesToAppIcon {
                    AppIconMark(size: size)
                        .opacity(state.iconIn)
                }
            }
        }
    }

    /// With Reduce Motion the brand crane shows the finished app icon; companion
    /// figures show their settled animal drawn statically (no wag, no ticking).
    @ViewBuilder private var reducedMotionMark: some View {
        if figure.resolvesToAppIcon {
            AppIconMark(size: size)
                .accessibilityLabel("Orifold")
        } else {
            Canvas(opaque: false) { context, canvasSize in
                FoldMarkRenderer.draw(in: &context, size: canvasSize, state: .resolved,
                                      figure: figure, idle: IdlePhase(phase: 0, intensity: 0))
            }
        }
    }

    /// The idle wag/breath ramps in only once the figure has finished blossoming, and
    /// is suppressed while a (re)fold is underway.
    private func idleIntensity(atElapsed t: TimeInterval) -> Double {
        FoldMarkRenderer.smoothstep((t - 3.0) / 0.8)
    }

    private func scheduleFirstPlay() {
        guard !hasScheduledFirstPlay, !shouldReduceMotion else { return }
        hasScheduledFirstPlay = true
        let generation = playGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + autoplayDelay) {
            guard generation == playGeneration, foldStart == nil else { return }
            play()
        }
    }

    private func replay() {
        guard !shouldReduceMotion else { return }
        play()
    }

    private func play() {
        playGeneration += 1
        foldStart = Date()
        isFoldRunning = true
        let generation = playGeneration
        // Let the clock idle-tick only while the crane is folding; once the fold
        // resolves, `isPaused` can stop it (companions keep ticking via their wag).
        DispatchQueue.main.asyncAfter(deadline: .now() + animationRuntime) {
            guard generation == playGeneration else { return }
            isFoldRunning = false
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

    /// Reproduce the staged fold as a function of elapsed seconds, so the whole
    /// animation can be driven by a continuous clock (enabling replay + idle).
    static func state(atElapsed t: TimeInterval, resolvesToAppIcon: Bool) -> FoldState {
        func track(_ start: Double, _ duration: Double) -> Double {
            FoldMarkRenderer.smoothstep((t - start) / duration)
        }
        return FoldState(
            sheet: track(0.0, 0.30),
            fold1: track(0.30, 0.55),
            fold2: track(0.85, 0.45),
            fold3: track(1.30, 0.45),
            bloomBody: track(1.75, 0.50),
            bloomWing: track(1.90, 0.62),
            bloomTail: track(2.08, 0.48),
            bloomNeck: track(2.20, 0.55),
            bloomHead: track(2.52, 0.50),
            // The dissolve and the icon overlap by a beat so the hand-off crossfades
            // gracefully rather than cutting between two shapes.
            paperOut: resolvesToAppIcon ? track(3.15, 0.55) : 0,
            iconIn: resolvesToAppIcon ? track(3.45, 0.60) : 0
        )
    }
}

/// The continuous idle clock: `phase` (seconds, absolute) drives the wag/breath;
/// `intensity` (0…1) ramps the motion in once the figure has settled; `excitement`
/// (0…1, smoothed) boosts any `excitable` wag — currently just the dog's tail
/// picking up when the cursor is close.
private struct IdlePhase {
    var phase: Double
    var intensity: Double
    var excitement: Double = 0
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

/// Warm/cool endpoints of a figure's paper. Highlights lean toward `warm`, shadows
/// toward `cool`, as real paper does under a cool sky light. Distinct per species so
/// the companions read differently at a glance (kraft dog vs slate cat).
private struct PaperPalette {
    let warm: (r: Double, g: Double, b: Double)
    let cool: (r: Double, g: Double, b: Double)

    /// `v` in 0…1: 1 = brightest lit paper, 0 = deepest fold shadow.
    func tone(_ v: Double) -> Color {
        let t = max(0, min(1, v))
        return Color(.sRGB,
                     red: cool.r + (warm.r - cool.r) * t,
                     green: cool.g + (warm.g - cool.g) * t,
                     blue: cool.b + (warm.b - cool.b) * t,
                     opacity: 1)
    }

    static let ivory = PaperPalette(warm: (1.00, 0.985, 0.96), cool: (0.72, 0.76, 0.82))
    static let kraft = PaperPalette(warm: (1.00, 0.90, 0.73), cool: (0.66, 0.50, 0.36))
    static let slate = PaperPalette(warm: (0.95, 0.96, 1.00), cool: (0.56, 0.60, 0.74))

    // Detail materials used via a facet's `overridePalette` — noses, inner ears, and
    // eye catchlights, so a few small facets can read as their own material.
    static let noseDog = PaperPalette(warm: (0.36, 0.27, 0.24), cool: (0.13, 0.10, 0.10))
    static let noseCat = PaperPalette(warm: (0.98, 0.68, 0.72), cool: (0.60, 0.32, 0.40))
    static let innerEarDog = PaperPalette(warm: (0.80, 0.58, 0.42), cool: (0.44, 0.30, 0.22))
    static let innerEarCat = PaperPalette(warm: (0.99, 0.82, 0.84), cool: (0.72, 0.48, 0.55))
    static let catchlight = PaperPalette(warm: (1.00, 1.00, 1.00), cool: (0.88, 0.92, 0.98))

    // The red-crowned crane's (tancho) scarlet crown patch and dark eye.
    static let craneCrown = PaperPalette(warm: (0.90, 0.24, 0.22), cool: (0.52, 0.09, 0.11))
    static let craneInk = PaperPalette(warm: (0.26, 0.28, 0.34), cool: (0.09, 0.10, 0.14))
}

/// One paper facet. `hi`/`lo` are paper-tone values (0…1) for the two ends of the
/// facet's shading gradient, oriented from `gradFrom` to `gradTo`.
private struct PaperFacet {
    let group: BloomGroup
    let pts: [CGPoint]
    let hi: Double
    let lo: Double
    let gradFrom: CGPoint
    let gradTo: CGPoint
    /// When set, this facet paints in its own material (nose, inner ear, catchlight)
    /// instead of the figure's paper palette. Declared last so existing call sites
    /// (which don't pass it) keep compiling via the synthesized default.
    var overridePalette: PaperPalette? = nil
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

/// A living-idle wag: the named `group` rotates around `pivot` by ±`amplitude`
/// (radians) at `speed` (radians/second). Dogs wag the tail; cats twitch their ears
/// and sway their tail — a figure can carry more than one independent wag.
private struct PaperWag {
    /// `sway` is a smooth continuous sine (a wag or a slow wavy drift); `twitch` stays
    /// near rest most of the cycle and snaps through a brief, sharp flick — reads as
    /// alert/reflexive rather than rhythmic.
    enum Motion {
        case sway
        case twitch
    }

    let group: BloomGroup
    let pivot: CGPoint
    let amplitude: Double
    let speed: Double
    var motion: Motion = .sway
    /// When true, this wag speeds up and widens while `IdlePhase.excitement` is
    /// elevated (the dog's tail, picking up when the cursor is close).
    var excitable: Bool = false
    /// When true, this wag is silent at rest and only appears while
    /// `IdlePhase.excitement` is elevated — the cat's hover head-tilt.
    var hoverOnly: Bool = false
}

/// A complete blossomed figure. The brand crane (`.crane`) hands off to the app icon;
/// the companion animals (`.dog`, `.cat`) settle on the finished figure and idle.
struct PaperFigure {
    /// `nil` for the brand crane; the companion species otherwise.
    fileprivate let species: PetSpecies?
    fileprivate let facets: [PaperFacet]
    fileprivate let creases: [PaperCrease]
    fileprivate let occlusion: [PaperOcclusion]
    fileprivate let packetTriangle: [CGPoint]
    fileprivate let groundCenter: CGPoint
    fileprivate let specular: PaperSpecular?
    fileprivate let palette: PaperPalette
    /// The figure's idle wags — empty for a figure that rests completely still (the
    /// crane), one entry for a single wagging part, or several for independent
    /// motion (the cat twitches its ears and sways its tail at the same time).
    fileprivate let idle: [PaperWag]

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
            // Tancho crown — the crane's scarlet cap, a quiet pop of color.
            PaperFacet(group: .head,
                       pts: [CGPoint(x: 0.726, y: 0.298), CGPoint(x: 0.762, y: 0.246), CGPoint(x: 0.782, y: 0.288)],
                       hi: 0.92, lo: 0.52, gradFrom: CGPoint(x: 0.762, y: 0.246), gradTo: CGPoint(x: 0.726, y: 0.298),
                       overridePalette: .craneCrown),
            // Eye — a dark bead with a bright catchlight.
            PaperFacet(group: .head,
                       pts: [CGPoint(x: 0.788, y: 0.281), CGPoint(x: 0.803, y: 0.286), CGPoint(x: 0.792, y: 0.298)],
                       hi: 0.80, lo: 0.30, gradFrom: CGPoint(x: 0.803, y: 0.286), gradTo: CGPoint(x: 0.792, y: 0.298),
                       overridePalette: .craneInk),
            PaperFacet(group: .head,
                       pts: [CGPoint(x: 0.790, y: 0.283), CGPoint(x: 0.797, y: 0.285), CGPoint(x: 0.791, y: 0.290)],
                       hi: 1.0, lo: 0.9, gradFrom: CGPoint(x: 0.790, y: 0.283), gradTo: CGPoint(x: 0.791, y: 0.290),
                       overridePalette: .catchlight),
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
            specular: PaperSpecular(from: CGPoint(x: 0.560, y: 0.520), to: CGPoint(x: 0.30, y: 0.235), group: .wing),
            palette: .ivory,
            idle: []
        )
    }()
}

// MARK: Dog geometry
//
// A friendly seated shiba-ish origami dog in warm kraft paper, facing right: a rounded
// two-tone head, a long snout with a dark nose, two soft down-folded ears, a seated
// haunch, a dark eye, and a big plume tail that WAGS. Group mapping: head→head,
// ears→wing, snout+nose→neck, torso→body, tail→tail.

extension PaperFigure {
    static let dog: PaperFigure = {
        let headTop = CGPoint(x: 0.455, y: 0.240)
        let headR = CGPoint(x: 0.585, y: 0.380)
        let headBot = CGPoint(x: 0.460, y: 0.520)
        let headL = CGPoint(x: 0.335, y: 0.375)

        let facets: [PaperFacet] = [
            // Far ear — down-folded behind the head on the right, darker.
            PaperFacet(group: .wing,
                       pts: [CGPoint(x: 0.520, y: 0.270), CGPoint(x: 0.600, y: 0.300), CGPoint(x: 0.545, y: 0.470)],
                       hi: 0.50, lo: 0.30, gradFrom: CGPoint(x: 0.600, y: 0.300), gradTo: CGPoint(x: 0.545, y: 0.470)),
            // Tail — a big plume sweeping up the back-left (the wag element), three facets.
            PaperFacet(group: .tail,
                       pts: [CGPoint(x: 0.340, y: 0.700), CGPoint(x: 0.185, y: 0.470), CGPoint(x: 0.375, y: 0.620)],
                       hi: 0.80, lo: 0.55, gradFrom: CGPoint(x: 0.375, y: 0.620), gradTo: CGPoint(x: 0.185, y: 0.470)),
            PaperFacet(group: .tail,
                       pts: [CGPoint(x: 0.340, y: 0.700), CGPoint(x: 0.375, y: 0.620), CGPoint(x: 0.420, y: 0.700)],
                       hi: 0.62, lo: 0.44, gradFrom: CGPoint(x: 0.420, y: 0.700), gradTo: CGPoint(x: 0.340, y: 0.700)),
            // Plush dark tip on the tail.
            PaperFacet(group: .tail,
                       pts: [CGPoint(x: 0.185, y: 0.470), CGPoint(x: 0.250, y: 0.500), CGPoint(x: 0.232, y: 0.566)],
                       hi: 0.44, lo: 0.26, gradFrom: CGPoint(x: 0.250, y: 0.500), gradTo: CGPoint(x: 0.185, y: 0.470)),
            // Torso / seated haunch — shadowed back + lit front.
            PaperFacet(group: .body,
                       pts: [CGPoint(x: 0.445, y: 0.500), CGPoint(x: 0.445, y: 0.840), CGPoint(x: 0.280, y: 0.740)],
                       hi: 0.60, lo: 0.40, gradFrom: CGPoint(x: 0.445, y: 0.500), gradTo: CGPoint(x: 0.280, y: 0.740)),
            PaperFacet(group: .body,
                       pts: [CGPoint(x: 0.445, y: 0.500), CGPoint(x: 0.560, y: 0.820), CGPoint(x: 0.445, y: 0.840)],
                       hi: 0.86, lo: 0.62, gradFrom: CGPoint(x: 0.445, y: 0.500), gradTo: CGPoint(x: 0.560, y: 0.820)),
            // Chest tuft — a soft bright wedge down the front.
            PaperFacet(group: .body,
                       pts: [CGPoint(x: 0.470, y: 0.520), CGPoint(x: 0.522, y: 0.700), CGPoint(x: 0.456, y: 0.762)],
                       hi: 0.99, lo: 0.74, gradFrom: CGPoint(x: 0.470, y: 0.520), gradTo: CGPoint(x: 0.456, y: 0.762)),
            // Front paw — a small lit tab at the base.
            PaperFacet(group: .body,
                       pts: [CGPoint(x: 0.470, y: 0.800), CGPoint(x: 0.575, y: 0.812), CGPoint(x: 0.560, y: 0.848), CGPoint(x: 0.470, y: 0.848)],
                       hi: 0.94, lo: 0.72, gradFrom: CGPoint(x: 0.470, y: 0.800), gradTo: CGPoint(x: 0.470, y: 0.848)),
            // Head — shadowed back-left + lit front-right, split on the keel.
            PaperFacet(group: .head,
                       pts: [headTop, headBot, headL],
                       hi: 0.66, lo: 0.46, gradFrom: headTop, gradTo: headL),
            PaperFacet(group: .head,
                       pts: [headTop, headR, headBot],
                       hi: 1.00, lo: 0.80, gradFrom: headTop, gradTo: headBot),
            // Eye — dark facet on the lit cheek, lifted by a tiny catchlight.
            PaperFacet(group: .head,
                       pts: [CGPoint(x: 0.518, y: 0.356), CGPoint(x: 0.556, y: 0.370), CGPoint(x: 0.520, y: 0.396)],
                       hi: 0.22, lo: 0.10, gradFrom: CGPoint(x: 0.518, y: 0.356), gradTo: CGPoint(x: 0.520, y: 0.396)),
            PaperFacet(group: .head,
                       pts: [CGPoint(x: 0.524, y: 0.362), CGPoint(x: 0.537, y: 0.366), CGPoint(x: 0.527, y: 0.376)],
                       hi: 1.0, lo: 0.9, gradFrom: CGPoint(x: 0.524, y: 0.362), gradTo: CGPoint(x: 0.527, y: 0.376),
                       overridePalette: .catchlight),
            // Snout — long wedge pointing right, lit top + shadowed underside.
            PaperFacet(group: .neck,
                       pts: [CGPoint(x: 0.545, y: 0.350), CGPoint(x: 0.720, y: 0.470), CGPoint(x: 0.548, y: 0.450)],
                       hi: 0.98, lo: 0.80, gradFrom: CGPoint(x: 0.720, y: 0.470), gradTo: CGPoint(x: 0.55, y: 0.450)),
            PaperFacet(group: .neck,
                       pts: [CGPoint(x: 0.548, y: 0.450), CGPoint(x: 0.720, y: 0.470), CGPoint(x: 0.560, y: 0.520)],
                       hi: 0.74, lo: 0.56, gradFrom: CGPoint(x: 0.720, y: 0.470), gradTo: CGPoint(x: 0.56, y: 0.520)),
            // Nose — a rounded dark button with a moist top highlight.
            PaperFacet(group: .neck,
                       pts: [CGPoint(x: 0.702, y: 0.452), CGPoint(x: 0.741, y: 0.462), CGPoint(x: 0.751, y: 0.482), CGPoint(x: 0.710, y: 0.500)],
                       hi: 0.82, lo: 0.30, gradFrom: CGPoint(x: 0.720, y: 0.454), gradTo: CGPoint(x: 0.714, y: 0.498),
                       overridePalette: .noseDog),
            // Near ear — bright, soft down-fold in front on the left.
            PaperFacet(group: .wing,
                       pts: [CGPoint(x: 0.400, y: 0.250), CGPoint(x: 0.300, y: 0.470), CGPoint(x: 0.440, y: 0.400)],
                       hi: 0.82, lo: 0.56, gradFrom: CGPoint(x: 0.400, y: 0.250), gradTo: CGPoint(x: 0.300, y: 0.470)),
            // Inner near-ear — a warmer, darker fold nested inside for depth.
            PaperFacet(group: .wing,
                       pts: [CGPoint(x: 0.399, y: 0.294), CGPoint(x: 0.338, y: 0.444), CGPoint(x: 0.430, y: 0.398)],
                       hi: 0.72, lo: 0.42, gradFrom: CGPoint(x: 0.399, y: 0.294), gradTo: CGPoint(x: 0.338, y: 0.444),
                       overridePalette: .innerEarDog),
        ]

        let creases: [PaperCrease] = [
            PaperCrease(group: .head, a: headTop, b: headBot, valley: true, strength: 1.0),                                          // head keel
            PaperCrease(group: .neck, a: CGPoint(x: 0.545, y: 0.350), b: CGPoint(x: 0.720, y: 0.470), valley: false, strength: 0.7), // snout ridge
            PaperCrease(group: .wing, a: CGPoint(x: 0.400, y: 0.250), b: CGPoint(x: 0.300, y: 0.470), valley: true, strength: 0.6),  // near-ear fold
            PaperCrease(group: .wing, a: CGPoint(x: 0.520, y: 0.270), b: CGPoint(x: 0.545, y: 0.470), valley: true, strength: 0.35), // far-ear fold
            PaperCrease(group: .body, a: CGPoint(x: 0.445, y: 0.500), b: CGPoint(x: 0.445, y: 0.840), valley: true, strength: 0.5),  // chest keel
            PaperCrease(group: .tail, a: CGPoint(x: 0.340, y: 0.700), b: CGPoint(x: 0.185, y: 0.470), valley: false, strength: 0.5), // tail median
        ]

        let occlusion: [PaperOcclusion] = [
            PaperOcclusion(center: CGPoint(x: 0.47, y: 0.42), radius: 0.12, group: .head),
            PaperOcclusion(center: CGPoint(x: 0.44, y: 0.60), radius: 0.11, group: .body),
            PaperOcclusion(center: CGPoint(x: 0.37, y: 0.66), radius: 0.08, group: .tail),
        ]

        return PaperFigure(
            species: .dog,
            facets: facets,
            creases: creases,
            occlusion: occlusion,
            packetTriangle: PaperFigure.packet,
            groundCenter: CGPoint(x: 0.44, y: 0.87),
            specular: PaperSpecular(from: CGPoint(x: 0.470, y: 0.260), to: CGPoint(x: 0.560, y: 0.360), group: .head),
            palette: .kraft,
            // Big, lively tail wag around the tail base — picks up further when the
            // cursor is close (`excitable`), since a dog's tail is the one part of it
            // that visibly reacts to attention.
            idle: [
                PaperWag(group: .tail, pivot: CGPoint(x: 0.360, y: 0.720), amplitude: 0.30, speed: 8.2,
                         motion: .sway, excitable: true)
            ]
        )
    }()
}

// MARK: Cat geometry
//
// Ori: a FRONT-FACING seated origami cat in cool slate paper — deliberately a different
// pose family from the dog's 3/4 profile so the two never read as reskinned silhouettes.
// A wide, rounded diamond face split on a center keel, two broad triangular ears with
// pink inner folds, two dark almond eyes with catchlights, a tiny pink nose over a
// bright muzzle wedge, whisker crease lines on both cheeks, a compact seated bell of a
// body with chest tuft and two front paws, and a tail that hooks around the right side
// with a raised dark tip. Group mapping: head+eyes→head, ears→wing, muzzle/nose/whiskers
// →neck, torso→body, tail→tail. The front-facing symmetry is what makes it read as a
// cat instantly, even at the 72 pt workspace-chip size.

extension PaperFigure {
    static let cat: PaperFigure = {
        let headTop = CGPoint(x: 0.500, y: 0.288)
        let headBot = CGPoint(x: 0.500, y: 0.548)

        let facets: [PaperFacet] = [
            // Tail — a bold hook curling around the right side from behind, dark tip
            // raised: the classic curled cat tail, nothing like the dog's plume.
            PaperFacet(group: .tail,
                       pts: [CGPoint(x: 0.565, y: 0.805), CGPoint(x: 0.750, y: 0.780), CGPoint(x: 0.618, y: 0.726)],
                       hi: 0.74, lo: 0.56, gradFrom: CGPoint(x: 0.618, y: 0.726), gradTo: CGPoint(x: 0.750, y: 0.780)),
            PaperFacet(group: .tail,
                       pts: [CGPoint(x: 0.618, y: 0.726), CGPoint(x: 0.750, y: 0.780), CGPoint(x: 0.734, y: 0.630)],
                       hi: 0.56, lo: 0.40, gradFrom: CGPoint(x: 0.734, y: 0.630), gradTo: CGPoint(x: 0.750, y: 0.780)),
            PaperFacet(group: .tail,
                       pts: [CGPoint(x: 0.716, y: 0.652), CGPoint(x: 0.766, y: 0.622), CGPoint(x: 0.720, y: 0.560)],
                       hi: 0.38, lo: 0.22, gradFrom: CGPoint(x: 0.766, y: 0.622), gradTo: CGPoint(x: 0.720, y: 0.560)),
            // Torso — a compact seated bell, shadowed left + lit right.
            PaperFacet(group: .body,
                       pts: [CGPoint(x: 0.500, y: 0.545), CGPoint(x: 0.500, y: 0.815), CGPoint(x: 0.372, y: 0.795), CGPoint(x: 0.428, y: 0.560)],
                       hi: 0.56, lo: 0.40, gradFrom: CGPoint(x: 0.500, y: 0.545), gradTo: CGPoint(x: 0.372, y: 0.795)),
            PaperFacet(group: .body,
                       pts: [CGPoint(x: 0.500, y: 0.545), CGPoint(x: 0.572, y: 0.560), CGPoint(x: 0.628, y: 0.795), CGPoint(x: 0.500, y: 0.815)],
                       hi: 0.82, lo: 0.62, gradFrom: CGPoint(x: 0.500, y: 0.545), gradTo: CGPoint(x: 0.628, y: 0.795)),
            // Chest tuft — a soft bright kite down the front.
            PaperFacet(group: .body,
                       pts: [CGPoint(x: 0.500, y: 0.560), CGPoint(x: 0.542, y: 0.720), CGPoint(x: 0.500, y: 0.790), CGPoint(x: 0.458, y: 0.720)],
                       hi: 0.96, lo: 0.76, gradFrom: CGPoint(x: 0.500, y: 0.560), gradTo: CGPoint(x: 0.500, y: 0.790)),
            // Front paws — two small tabs, the near one brighter.
            PaperFacet(group: .body,
                       pts: [CGPoint(x: 0.442, y: 0.775), CGPoint(x: 0.498, y: 0.772), CGPoint(x: 0.498, y: 0.818), CGPoint(x: 0.436, y: 0.818)],
                       hi: 0.86, lo: 0.70, gradFrom: CGPoint(x: 0.442, y: 0.775), gradTo: CGPoint(x: 0.436, y: 0.818)),
            PaperFacet(group: .body,
                       pts: [CGPoint(x: 0.502, y: 0.772), CGPoint(x: 0.558, y: 0.775), CGPoint(x: 0.564, y: 0.818), CGPoint(x: 0.502, y: 0.818)],
                       hi: 0.98, lo: 0.80, gradFrom: CGPoint(x: 0.502, y: 0.772), gradTo: CGPoint(x: 0.502, y: 0.818)),
            // Ears — wide symmetric triangles rooted ON the crown edges, tips splayed
            // slightly outward. Painted before the head so their bases tuck under it.
            PaperFacet(group: .wing,
                       pts: [CGPoint(x: 0.402, y: 0.372), CGPoint(x: 0.386, y: 0.184), CGPoint(x: 0.478, y: 0.306)],
                       hi: 0.86, lo: 0.62, gradFrom: CGPoint(x: 0.386, y: 0.184), gradTo: CGPoint(x: 0.402, y: 0.372)),
            PaperFacet(group: .wing,
                       pts: [CGPoint(x: 0.414, y: 0.352), CGPoint(x: 0.398, y: 0.230), CGPoint(x: 0.460, y: 0.306)],
                       hi: 0.86, lo: 0.55, gradFrom: CGPoint(x: 0.398, y: 0.230), gradTo: CGPoint(x: 0.414, y: 0.352),
                       overridePalette: .innerEarCat),
            PaperFacet(group: .wing,
                       pts: [CGPoint(x: 0.522, y: 0.306), CGPoint(x: 0.614, y: 0.184), CGPoint(x: 0.598, y: 0.372)],
                       hi: 0.60, lo: 0.40, gradFrom: CGPoint(x: 0.614, y: 0.184), gradTo: CGPoint(x: 0.598, y: 0.372)),
            PaperFacet(group: .wing,
                       pts: [CGPoint(x: 0.540, y: 0.306), CGPoint(x: 0.602, y: 0.230), CGPoint(x: 0.586, y: 0.352)],
                       hi: 0.62, lo: 0.38, gradFrom: CGPoint(x: 0.602, y: 0.230), gradTo: CGPoint(x: 0.586, y: 0.352),
                       overridePalette: .innerEarCat),
            // Head — a wide, rounded diamond with cheek corners, split on a center
            // keel: shadowed left half + lit right half under the cool top-right light.
            PaperFacet(group: .head,
                       pts: [headTop, headBot, CGPoint(x: 0.408, y: 0.502), CGPoint(x: 0.362, y: 0.408)],
                       hi: 0.68, lo: 0.50, gradFrom: headTop, gradTo: CGPoint(x: 0.395, y: 0.480)),
            PaperFacet(group: .head,
                       pts: [headTop, CGPoint(x: 0.638, y: 0.408), CGPoint(x: 0.592, y: 0.502), headBot],
                       hi: 1.00, lo: 0.82, gradFrom: headTop, gradTo: CGPoint(x: 0.605, y: 0.480)),
            // Eyes — two dark ink almonds, each lifted by a tiny catchlight.
            PaperFacet(group: .head,
                       pts: [CGPoint(x: 0.415, y: 0.408), CGPoint(x: 0.468, y: 0.398), CGPoint(x: 0.462, y: 0.432)],
                       hi: 0.60, lo: 0.20, gradFrom: CGPoint(x: 0.468, y: 0.398), gradTo: CGPoint(x: 0.462, y: 0.432),
                       overridePalette: .craneInk),
            PaperFacet(group: .head,
                       pts: [CGPoint(x: 0.532, y: 0.398), CGPoint(x: 0.585, y: 0.408), CGPoint(x: 0.538, y: 0.432)],
                       hi: 0.60, lo: 0.20, gradFrom: CGPoint(x: 0.532, y: 0.398), gradTo: CGPoint(x: 0.538, y: 0.432),
                       overridePalette: .craneInk),
            PaperFacet(group: .head,
                       pts: [CGPoint(x: 0.432, y: 0.407), CGPoint(x: 0.447, y: 0.404), CGPoint(x: 0.443, y: 0.415)],
                       hi: 1.0, lo: 0.9, gradFrom: CGPoint(x: 0.432, y: 0.407), gradTo: CGPoint(x: 0.443, y: 0.415),
                       overridePalette: .catchlight),
            PaperFacet(group: .head,
                       pts: [CGPoint(x: 0.549, y: 0.404), CGPoint(x: 0.564, y: 0.407), CGPoint(x: 0.553, y: 0.415)],
                       hi: 1.0, lo: 0.9, gradFrom: CGPoint(x: 0.549, y: 0.404), gradTo: CGPoint(x: 0.553, y: 0.415),
                       overridePalette: .catchlight),
            // Muzzle — a short bright wedge; the chin ends well above the head's
            // bottom point so the face stays round and cute, never long.
            PaperFacet(group: .neck,
                       pts: [CGPoint(x: 0.464, y: 0.460), CGPoint(x: 0.536, y: 0.460), CGPoint(x: 0.500, y: 0.512)],
                       hi: 1.00, lo: 0.86, gradFrom: CGPoint(x: 0.500, y: 0.460), gradTo: CGPoint(x: 0.500, y: 0.512)),
            // Nose — a tiny pink downward triangle centered under the eyes.
            PaperFacet(group: .neck,
                       pts: [CGPoint(x: 0.482, y: 0.460), CGPoint(x: 0.518, y: 0.460), CGPoint(x: 0.500, y: 0.485)],
                       hi: 0.85, lo: 0.50, gradFrom: CGPoint(x: 0.500, y: 0.460), gradTo: CGPoint(x: 0.500, y: 0.485),
                       overridePalette: .noseCat),
        ]

        let creases: [PaperCrease] = [
            PaperCrease(group: .head, a: headTop, b: headBot, valley: true, strength: 0.9),                                          // center face keel
            PaperCrease(group: .wing, a: CGPoint(x: 0.462, y: 0.318), b: CGPoint(x: 0.392, y: 0.196), valley: true, strength: 0.5),  // left-ear fold
            PaperCrease(group: .wing, a: CGPoint(x: 0.538, y: 0.318), b: CGPoint(x: 0.608, y: 0.196), valley: true, strength: 0.35), // right-ear fold
            PaperCrease(group: .body, a: CGPoint(x: 0.500, y: 0.560), b: CGPoint(x: 0.500, y: 0.790), valley: true, strength: 0.45), // chest keel
            PaperCrease(group: .tail, a: CGPoint(x: 0.600, y: 0.780), b: CGPoint(x: 0.734, y: 0.640), valley: false, strength: 0.4), // tail median
            // Whiskers — four thin bright crease lines fanning off the muzzle. Ridge
            // hairlines at low strength read as fold accents, not drawn-on whiskers.
            PaperCrease(group: .neck, a: CGPoint(x: 0.452, y: 0.472), b: CGPoint(x: 0.372, y: 0.458), valley: false, strength: 0.5),
            PaperCrease(group: .neck, a: CGPoint(x: 0.452, y: 0.492), b: CGPoint(x: 0.376, y: 0.502), valley: false, strength: 0.5),
            PaperCrease(group: .neck, a: CGPoint(x: 0.548, y: 0.472), b: CGPoint(x: 0.628, y: 0.458), valley: false, strength: 0.5),
            PaperCrease(group: .neck, a: CGPoint(x: 0.548, y: 0.492), b: CGPoint(x: 0.624, y: 0.502), valley: false, strength: 0.5),
        ]

        let occlusion: [PaperOcclusion] = [
            PaperOcclusion(center: CGPoint(x: 0.500, y: 0.550), radius: 0.09, group: .body),  // under the chin
            PaperOcclusion(center: CGPoint(x: 0.500, y: 0.340), radius: 0.07, group: .wing),  // between the ear bases
            PaperOcclusion(center: CGPoint(x: 0.595, y: 0.770), radius: 0.07, group: .tail),  // tail root
        ]

        // The hover head-tilt is one gentle rotation applied identically to the head,
        // muzzle, and ears (same pivot/speed/phase → the whole face leans as one piece);
        // the ears' own twitch composes on top of it.
        let headTiltPivot = CGPoint(x: 0.500, y: 0.430)

        return PaperFigure(
            species: .cat,
            facets: facets,
            creases: creases,
            occlusion: occlusion,
            packetTriangle: PaperFigure.packet,
            groundCenter: CGPoint(x: 0.500, y: 0.845),
            specular: PaperSpecular(from: CGPoint(x: 0.545, y: 0.330), to: CGPoint(x: 0.610, y: 0.430), group: .head),
            palette: .slate,
            // Distinctly un-dog-like motion: the ears stay near rest and snap through a
            // quick, sharp flick (`.twitch`), the tail sways in a slow, smooth curl
            // (`.sway`, well below the dog's tail speed), and on hover the whole face
            // adds a gentle, curious tilt (`hoverOnly`) while the twitch sharpens and
            // the tail curl deepens (`excitable`).
            idle: [
                PaperWag(group: .wing, pivot: CGPoint(x: 0.500, y: 0.330), amplitude: 0.10, speed: 9.0,
                         motion: .twitch, excitable: true),
                PaperWag(group: .tail, pivot: CGPoint(x: 0.600, y: 0.790), amplitude: 0.16, speed: 1.6,
                         motion: .sway, excitable: true),
                PaperWag(group: .head, pivot: headTiltPivot, amplitude: 0.07, speed: 1.3,
                         motion: .sway, hoverOnly: true),
                PaperWag(group: .neck, pivot: headTiltPivot, amplitude: 0.07, speed: 1.3,
                         motion: .sway, hoverOnly: true),
                PaperWag(group: .wing, pivot: headTiltPivot, amplitude: 0.07, speed: 1.3,
                         motion: .sway, hoverOnly: true),
            ]
        )
    }()
}

// MARK: - Renderer

private enum FoldMarkRenderer {
    static func draw(in context: inout GraphicsContext, size: CGSize, state: FoldState, figure: PaperFigure, idle: IdlePhase) {
        let side = min(size.width, size.height)
        guard side > 0 else { return }

        // Fade + subtle scale-in of the whole mark, plus a gentle idle breath and sway
        // once settled — this is the default, always-on liveliness (independent of any
        // hover state), so the pet reads as alive at a glance even at rest.
        context.opacity = state.sheet
        let breath = 1 + 0.022 * sin(idle.phase * 2.6) * idle.intensity
        let sway = 0.030 * sin(idle.phase * 1.7 + 0.6) * idle.intensity
        let scale = (0.92 + 0.08 * state.sheet) * breath
        let mid = CGPoint(x: size.width / 2, y: size.height / 2)
        context.translateBy(x: mid.x, y: mid.y)
        context.rotate(by: .radians(sway))
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -mid.x, y: -mid.y)

        let tileRect = CGRect(x: (size.width - side) / 2, y: (size.height - side) / 2, width: side, height: side)
        let tilePath = Path(roundedRect: tileRect, cornerRadius: side * 0.22, style: .continuous)

        drawTile(in: &context, path: tilePath, rect: tileRect, side: side)

        // Keep all paper contained within the rounded tile.
        context.clip(to: tilePath)

        // Luminous cross-bloom that smooths the crane→icon hand-off: a soft swell of
        // light peaking exactly as the paper dissolves and the icon materializes.
        if figure.resolvesToAppIcon {
            let bloom = 4 * state.paperOut * (1 - state.paperOut)   // bell, peaks mid-dissolve
            if bloom > 0.01 {
                let center = CGPoint(x: tileRect.midX, y: tileRect.minY + tileRect.height * 0.44)
                let radius = side * 0.62
                context.drawLayer { layer in
                    layer.opacity = bloom
                    layer.fill(
                        Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
                        with: .radialGradient(
                            Gradient(colors: [
                                Color(.sRGB, red: 0.88, green: 0.96, blue: 0.99, opacity: 0.55),
                                Color(.sRGB, red: 0.62, green: 0.86, blue: 0.92, opacity: 0.18),
                                .clear,
                            ]),
                            center: center, startRadius: 0, endRadius: radius))
                }
            }
        }

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
        drawFigure(in: &context, tileRect: tileRect, side: side, state: state, figure: figure, idle: idle, at: at)
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
        idle: IdlePhase,
        at: (CGPoint) -> CGPoint
    ) {
        let overall = max(state.bloomBody, state.bloomWing, state.bloomTail, state.bloomNeck, state.bloomHead)
        guard overall > 0.001 else { return }

        // The live idle wags: each group carries an ordered list of (pivot, angle)
        // rotations composed in sequence, so a tile-unit transform can be applied only
        // to that group's points (identity for every other group). A figure can carry
        // more than one wag per group — the cat's ears twitch around the crown while
        // the whole face (head + muzzle + ears) tilts around the head's center on hover.
        var wagTransforms: [BloomGroup: [(pivot: CGPoint, angle: Double)]] = [:]
        for w in figure.idle {
            let speedBoost = w.excitable ? 1 + idle.excitement * 0.6 : 1
            let ampBoost = w.excitable ? 1 + idle.excitement * 0.35 : 1
            let gate = w.hoverOnly ? idle.excitement : 1
            let raw = sin(idle.phase * w.speed * speedBoost)
            let shaped: Double
            switch w.motion {
            case .sway:
                shaped = raw
            case .twitch:
                // Stays near rest for most of the cycle, then snaps through a brief,
                // sharp flick — reads as alert/reflexive rather than rhythmic.
                shaped = copysign(pow(abs(raw), 6), raw)
            }
            let angle = shaped * w.amplitude * ampBoost * gate * idle.intensity
            guard angle != 0 else { continue }
            wagTransforms[w.group, default: []].append((w.pivot, angle))
        }
        func wag(_ group: BloomGroup) -> (CGPoint) -> CGPoint {
            guard let transforms = wagTransforms[group], !transforms.isEmpty else { return { $0 } }
            return { p in transforms.reduce(p) { rotate($0, around: $1.pivot, angle: $1.angle) } }
        }

        // Contact shadow beneath the settling figure — a single soft ellipse.
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

        // Resolve each visible facet's current (unfolding, wagging) path.
        var silhouette = Path()
        var visible: [(facet: PaperFacet, path: Path, opacity: Double)] = []
        for facet in figure.facets {
            let p = facet.group.progress(state)
            guard p > 0.001 else { continue }
            let eased = ease(p)
            let path = unfoldPath(facet.pts, progress: eased, packet: figure.packetTriangle,
                                  transform: wag(facet.group), at: at)
            silhouette.addPath(path)
            visible.append((facet, path, min(1, eased * 1.6)))
        }
        guard !visible.isEmpty else { return }

        // One soft drop shadow for the whole figure, then facets tile over it.
        context.drawLayer { layer in
            layer.addFilter(.shadow(color: .black.opacity(0.22 * overall), radius: side * 0.03, x: side * 0.006, y: side * 0.016))
            layer.fill(silhouette, with: .color(.white))
        }

        // A soft rim glow behind the silhouette lifts the paper off the tile.
        context.drawLayer { layer in
            layer.opacity = 0.35 * overall
            layer.addFilter(.blur(radius: side * 0.006))
            layer.stroke(silhouette, with: .color(.white.opacity(0.85)), lineWidth: side * 0.010)
        }

        // Facets — two-tone paper shaded against cool light, in the figure's own palette,
        // with a crisp hairline at each facet's edge so adjoining panels read as distinct
        // planes. Opacity is baked into the fill/stroke colors rather than a `drawLayer`
        // wrapper to avoid an offscreen-layer allocation per facet per frame.
        for entry in visible {
            let palette = entry.facet.overridePalette ?? figure.palette
            context.fill(entry.path, with: .linearGradient(
                Gradient(colors: [palette.tone(entry.facet.hi).opacity(entry.opacity),
                                  palette.tone(entry.facet.lo).opacity(entry.opacity)]),
                startPoint: at(entry.facet.gradFrom), endPoint: at(entry.facet.gradTo)
            ))
            context.stroke(entry.path, with: .color(.black.opacity(0.05 * entry.opacity)), lineWidth: max(0.5, side * 0.0022))
        }

        // One quiet specular streak where the light catches the paper most directly,
        // clipped tight to the silhouette.
        if let specular = figure.specular {
            let specularP = specular.group.progress(state)
            if specularP > 0.05 {
                let t = wag(specular.group)
                context.drawLayer { layer in
                    layer.clip(to: silhouette)
                    var streak = Path()
                    streak.move(to: at(t(specular.from))); streak.addLine(to: at(t(specular.to)))
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
                let c = at(wag(occ.group)(occ.center))
                let r = side * occ.radius
                layer.fill(
                    Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                    with: .radialGradient(
                        Gradient(colors: [Color(.sRGB, red: 0.22, green: 0.27, blue: 0.40, opacity: 0.20 * ease(p)), .clear]),
                        center: c, startRadius: 0, endRadius: r
                    )
                )
            }
        }

        // Fold creases as a paired bevel — a dark shadow hairline immediately beside a
        // bright ridge hairline — reads as an embossed, engraved seam.
        for crease in figure.creases {
            let p = crease.group.progress(state)
            guard p > 0.06 else { continue }
            let t = wag(crease.group)
            let ca = t(crease.a), cb = t(crease.b)
            let a = at(ca), b = at(cb)
            let fade = min(1, ease(p) * 1.5)
            let n = perpendicular(ca, cb)
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

        // Washi paper grain + top-light sheen, clipped to the figure. The grain's fiber
        // positions are hashed from their index and never change, so `grainFibers` builds
        // the two fiber paths (in unit tile space) exactly once and this just maps them
        // into canvas space with a single affine transform per color.
        context.drawLayer { layer in
            layer.clip(to: silhouette)
            layer.opacity = overall

            let transform = CGAffineTransform(a: side, b: 0, c: 0, d: side, tx: tileRect.minX, ty: tileRect.minY)
            let lineWidth = max(0.5, side * 0.0016)
            layer.stroke(grainFibers.dark.applying(transform), with: .color(.black.opacity(0.07)), lineWidth: lineWidth)
            layer.stroke(grainFibers.light.applying(transform), with: .color(.white.opacity(0.10)), lineWidth: lineWidth)

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

    /// Grain fiber segments in unit tile space (0...1), split into two combined paths by
    /// tint. Built once on first use and reused — the hash-based positions are
    /// deterministic, so recomputing them every frame would be pure waste.
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

    /// Unfolds a facet's points from their nearest anchor on the folded packet's outline
    /// out to their final tile-unit positions, applies the live wag transform, then
    /// converts to canvas space.
    private static func unfoldPath(
        _ pts: [CGPoint],
        progress: Double,
        packet: [CGPoint],
        transform: (CGPoint) -> CGPoint,
        at: (CGPoint) -> CGPoint
    ) -> Path {
        var path = Path()
        let resolved = pts.map { pt -> CGPoint in
            let anchor = nearestPointOnPolygon(pt, polygon: packet)
            return at(transform(lerp(anchor, pt, t: progress)))
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

    /// Smooth 0→1 ramp with eased ends, clamped. The animation clock's workhorse.
    static func smoothstep(_ x: Double) -> Double {
        let t = max(0, min(1, x))
        return t * t * (3 - 2 * t)
    }

    /// Rotate a tile-unit point around a pivot by `angle` radians (used for the wag).
    private static func rotate(_ p: CGPoint, around pivot: CGPoint, angle: Double) -> CGPoint {
        let s = sin(angle), c = cos(angle)
        let dx = p.x - pivot.x, dy = p.y - pivot.y
        return CGPoint(x: pivot.x + dx * c - dy * s, y: pivot.y + dx * s + dy * c)
    }

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
