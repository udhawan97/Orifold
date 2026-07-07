import AppKit
import Observation
import SwiftUI

enum PetEvent: CaseIterable {
    case highlight, comment, tag, sign, note, edit, ink, rotate, delete, export, save, addFile, search, greeting, warning
}

enum PetLines {
    /// The curated "hero" events that get a distinct dog/cat voice. Every other
    /// event reuses the shared, species-neutral copy so the localization burden
    /// stays bounded while personality lands where it's most visible.
    private static let heroEvents: Set<PetEvent> = [.greeting, .export, .save, .warning]

    /// Resolve the lines for an event, giving the chosen companion its own voice on
    /// the hero events and falling back to shared copy everywhere else.
    static func lines(for species: PetSpecies, event: PetEvent) -> [String] {
        if heroEvents.contains(event), let hero = speciesHero(species, event) {
            return hero
        }
        return shared(for: event)
    }

    static func isHero(_ event: PetEvent) -> Bool {
        heroEvents.contains(event)
    }

    // Keys must be string literals: `L10n.string` takes a `LocalizationValue`, so any
    // interpolated variable would be captured as a format argument (looking up
    // "pet.%@.greeting.1") rather than the concrete key. Hence the explicit switch.
    //
    // Gami (dog) uses the `gami.*` namespace with a calm, professional voice; Ori
    // (cat) uses the `ori.*` namespace — curious, clever, elegant, calm, and
    // charmingly bossy rather than Gami's warm encouragement.
    private static func speciesHero(_ species: PetSpecies, _ event: PetEvent) -> [String]? {
        switch (species, event) {
        case (.dog, .greeting):
            return [L10n.string("gami.greeting.1"), L10n.string("gami.greeting.2")]
        case (.dog, .export):
            return [L10n.string("gami.export.1"), L10n.string("gami.export.2")]
        case (.dog, .save):
            return [L10n.string("gami.save.1"), L10n.string("gami.save.2")]
        case (.cat, .greeting):
            return [L10n.string("ori.greeting.1"), L10n.string("ori.greeting.2")]
        case (.cat, .export):
            return [L10n.string("ori.export.1"), L10n.string("ori.export.2")]
        case (.cat, .save):
            return [L10n.string("ori.save.1"), L10n.string("ori.save.2")]
        case (.dog, .warning):
            return [L10n.string("gami.warning.1"), L10n.string("gami.warning.2")]
        case (.cat, .warning):
            return [L10n.string("ori.warning.1"), L10n.string("ori.warning.2")]
        default:
            return nil
        }
    }

    /// A one-time, more instructive line shown the first time a feature fires for the
    /// user, species-neutral (both companions share the same useful tip). Returns
    /// `nil` for events with no dedicated first-use line — those fall back to the
    /// shared per-event copy the first time too.
    static func firstUseLine(for event: PetEvent) -> String? {
        switch event {
        case .edit: return L10n.string("pet.firstUse.edit")
        case .search: return L10n.string("pet.firstUse.search")
        case .sign: return L10n.string("pet.firstUse.sign")
        case .addFile: return L10n.string("pet.firstUse.addFile")
        default: return nil
        }
    }

    private static func shared(for event: PetEvent) -> [String] {
        switch event {
        case .highlight:
            return [
                L10n.string("pet.event.highlight.1"),
                L10n.string("pet.event.highlight.2"),
                L10n.string("pet.event.highlight.3"),
                L10n.string("pet.event.highlight.4")
            ]
        case .comment:
            return [
                L10n.string("pet.event.comment.1"),
                L10n.string("pet.event.comment.2"),
                L10n.string("pet.event.comment.3"),
                L10n.string("pet.event.comment.4")
            ]
        case .tag:
            return [
                L10n.string("pet.event.tag.1"),
                L10n.string("pet.event.tag.2"),
                L10n.string("pet.event.tag.3")
            ]
        case .sign:
            return [
                L10n.string("pet.event.sign.1"),
                L10n.string("pet.event.sign.2"),
                L10n.string("pet.event.sign.3"),
                L10n.string("pet.event.sign.4")
            ]
        case .note:
            return [
                L10n.string("pet.event.note.1"),
                L10n.string("pet.event.note.2")
            ]
        case .edit:
            return [
                L10n.string("pet.event.edit.1"),
                L10n.string("pet.event.edit.2"),
                L10n.string("pet.event.edit.3")
            ]
        case .ink:
            return [
                L10n.string("pet.event.ink.1"),
                L10n.string("pet.event.ink.2")
            ]
        case .rotate:
            return [
                L10n.string("pet.event.rotate.1"),
                L10n.string("pet.event.rotate.2")
            ]
        case .delete:
            return [
                L10n.string("pet.event.delete.1"),
                L10n.string("pet.event.delete.2")
            ]
        case .export:
            return [
                L10n.string("pet.event.export.1"),
                L10n.string("pet.event.export.2")
            ]
        case .save:
            return [
                L10n.string("pet.event.save.1"),
                L10n.string("pet.event.save.2")
            ]
        case .addFile:
            return [
                L10n.string("pet.event.addFile.1"),
                L10n.string("pet.event.addFile.2")
            ]
        case .search:
            return [
                L10n.string("pet.event.search.1"),
                L10n.string("pet.event.search.2")
            ]
        case .greeting:
            return [
                L10n.string("pet.event.greeting.1"),
                L10n.string("pet.event.greeting.2")
            ]
        case .warning:
            // Warning is always a hero event (both species define their own lines), so
            // this species-neutral fallback is only reached if a species ever loses its
            // hero copy — kept exhaustive for the compiler and as a safe default.
            return [
                L10n.string("gami.warning.1"),
                L10n.string("ori.warning.1")
            ]
        }
    }

    /// The one-time "meet my sibling" line shown when the user switches from an
    /// already-chosen companion to the other — the Origami joke (Gami + Ori =
    /// Origami, siblings from another mother), used sparingly so it never repeats
    /// at random alongside the rotating hover/event pools.
    static func siblingSwitchLines(for newSpecies: PetSpecies) -> [String] {
        switch newSpecies {
        case .dog: return [L10n.string("gami.sibling.switch")]
        case .cat: return [L10n.string("ori.sibling.switch")]
        }
    }

    static var feedback: [String] {
        [
            L10n.string("pet.feedback.1"),
            L10n.string("pet.feedback.2"),
            L10n.string("pet.feedback.3")
        ]
    }

    static var inspiration: [String] {
        [
            L10n.string("pet.inspiration.1"),
            L10n.string("pet.inspiration.2"),
            L10n.string("pet.inspiration.3"),
            L10n.string("pet.inspiration.4"),
            L10n.string("pet.inspiration.5"),
            L10n.string("pet.inspiration.6"),
            L10n.string("pet.inspiration.7"),
            L10n.string("pet.inspiration.8"),
            L10n.string("pet.inspiration.9"),
            L10n.string("pet.inspiration.10")
        ]
    }

    /// A quick in-character line shown when the user hovers the workspace pet — an
    /// affordance hint, not a feature notification, so it bypasses the event throttle
    /// entirely and is always available on hover.
    static func hoverTip(for species: PetSpecies) -> String {
        let lines: [String]
        switch species {
        case .dog:
            lines = [
                L10n.string("gami.hoverTip.1"),
                L10n.string("gami.hoverTip.2"),
                L10n.string("gami.hoverTip.3"),
                L10n.string("gami.hoverTip.4"),
                L10n.string("gami.hoverTip.5"),
                L10n.string("gami.hoverTip.6")
            ]
        case .cat:
            lines = [
                L10n.string("ori.hoverTip.1"),
                L10n.string("ori.hoverTip.2"),
                L10n.string("ori.hoverTip.3"),
                L10n.string("ori.hoverTip.4"),
                L10n.string("ori.hoverTip.5"),
                L10n.string("ori.hoverTip.6")
            ]
        }
        return lines.randomElement() ?? ""
    }
}

enum PetBuddyHook {
    static func trigger(_ event: PetEvent) {
        guard isEnabled else { return }
        Task { @MainActor in
            PetBuddy.shared.trigger(event)
        }
    }

    private static var isEnabled: Bool {
        if UserDefaults.standard.object(forKey: "petEnabled") == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: "petEnabled")
    }
}

@MainActor @Observable final class PetBuddy {
    static let shared = PetBuddy()

    @ObservationIgnored @AppStorage("petEnabled") var isEnabledStorage = true
    @ObservationIgnored @AppStorage("petTriggerCount") private var triggerCountStorage = 0
    @ObservationIgnored @AppStorage("petSpecies") private var speciesStorage = PetSpecies.fallback.rawValue
    @ObservationIgnored @AppStorage("petSpeciesChosen") private var speciesChosenStorage = false
    /// Separate from `petEnabled` (which hides the whole companion): this only
    /// silences the hint bubble/hover tip while keeping the chip and popover.
    @ObservationIgnored @AppStorage("gamiTipsEnabled") var tipsEnabledStorage = true
    /// Comma-joined `PetEvent` raw values the user has already triggered once —
    /// drives the one-time, more-instructive first-use line per feature.
    @ObservationIgnored @AppStorage("gamiSeenEvents") private var seenEventsStorage = ""

    var isEnabled = true {
        didSet { isEnabledStorage = isEnabled }
    }
    var tipsEnabled = true {
        didSet { tipsEnabledStorage = tipsEnabled }
    }
    /// The chosen companion — *identity*, persisted and stable across launches,
    /// navigation, and document opens. Deliberately separate from the transient
    /// message/bounce/bubble state below, so switching pages never resets it.
    var species: PetSpecies = .fallback {
        didSet { speciesStorage = species.rawValue }
    }
    /// Whether the user has ever explicitly picked a companion (vs. defaulting to
    /// dog). Drives the first-run picker on the empty state.
    var hasChosenSpecies = false {
        didSet { speciesChosenStorage = hasChosenSpecies }
    }
    var currentMessage: String?
    var isBubbleVisible = false
    /// Set for hints that shouldn't auto-dismiss quietly (currently: warnings) —
    /// the bubble grows a dismiss button and becomes hit-testable.
    var isCurrentSticky = false
    /// Mirrors `PetView`'s hover state so `PetOverlay` can widen the gap above
    /// the pet before it grows into the space the message bubble occupies —
    /// the pet's `scaleEffect` doesn't change its layout size, so the VStack
    /// spacing has to be told about the hover growth explicitly.
    var isHovered = false
    /// Bumped on every event, independent of whether a bubble is shown — drives the
    /// chip's acknowledgment pulse even when the message is suppressed (non-hero
    /// repeat events collapse to a pulse only, per the reduced-chatter redesign).
    var pulseToken = 0
    /// The most recent message that was suppressed into a hint-chip badge instead of
    /// a floating bubble (window too small, or export/save chrome busy nearby) — the
    /// popover surfaces it under "Latest tip" so nothing is silently lost.
    var lastCollapsedMessage: String?
    /// True while export/save chrome that occupies the bottom of the window is
    /// active — set by the workspace layer. While true, hints collapse to the
    /// hint-chip badge instead of a floating bubble, guaranteeing no overlap with
    /// that chrome without needing its exact geometry.
    var isChromeBusy = false
    /// Hooks for a future workspace-level editing/selection gate: while either is
    /// true, non-critical hints are deferred rather than shown immediately. Not yet
    /// wired to live PDF selection/edit state (see GAMI_REDESIGN_PLAN.md §5) — safe
    /// no-op defaults until that follow-up lands.
    var isUserEditing = false {
        didSet { if !isUserEditing, !isUserSelecting { flushDeferredHintIfPossible() } }
    }
    var isUserSelecting = false {
        didSet { if !isUserSelecting, !isUserEditing { flushDeferredHintIfPossible() } }
    }

    // MARK: Companion-switch launch hint
    //
    // A one-time popover teaching that the *other* companion exists and the chip
    // can switch between them — shown from the third session onward, and only if
    // the user hasn't already discovered the popover or switched species on their
    // own. See GAMI_REDESIGN_PLAN.md's sibling `ORI_REDESIGN_PLAN.md` §6.

    @ObservationIgnored @AppStorage("gamiSessionCount") private var sessionCountStorage = 0
    @ObservationIgnored @AppStorage("companionSwitchHintShown") private var switchHintShownStorage = false
    @ObservationIgnored @AppStorage("gamiPopoverOpened") private var popoverOpenedStorage = false
    @ObservationIgnored @AppStorage("gamiHasSwitchedSpecies") private var hasSwitchedSpeciesStorage = false

    /// Cached at launch from `sessionCountStorage` (read once, like `seenEvents`
    /// below) rather than read live on every `isSwitchHintEligible` check —
    /// `@AppStorage` on a plain `@Observable` class isn't guaranteed to reflect
    /// external `UserDefaults` writes on every access. Settable for tests.
    var sessionCount = 0
    var switchHintShown = false {
        didSet { switchHintShownStorage = switchHintShown }
    }
    /// Set the moment the user opens the real popover on their own — this
    /// pre-empts the teaching hint permanently, since they've already found it.
    var hasOpenedPopover = false {
        didSet {
            popoverOpenedStorage = hasOpenedPopover
            if hasOpenedPopover { switchHintShown = true }
        }
    }
    /// Set the moment the user switches species on their own — same pre-emption
    /// as `hasOpenedPopover`.
    var hasSwitchedSpecies = false {
        didSet {
            hasSwitchedSpeciesStorage = hasSwitchedSpecies
            if hasSwitchedSpecies { switchHintShown = true }
        }
    }
    /// True while the teaching hint is presented — event bubbles are suppressed
    /// during this window so the two never compete for attention.
    var isSwitchHintPresented = false

    /// Whether the one-time companion-switch hint is eligible to show right now.
    /// Callers still need to check window/chrome constraints (cramped window,
    /// import/export in progress) before actually presenting it.
    var isSwitchHintEligible: Bool {
        isEnabled && sessionCount >= 3 && !switchHintShown
    }

    /// Marks the hint permanently done — called on any interaction with it
    /// (dismiss, "Switch anytime," or click-away) so it never shows again.
    func markSwitchHintShown() {
        switchHintShown = true
    }

    /// Minimum gap between bubbles — long enough that Gami reads as occasional
    /// guidance, not chatter, during focused editing.
    let minInterval: TimeInterval = 45

    var lastShownAt: Date?
    /// The last few *resolved* strings shown, most-recent first, capped at 5 — a
    /// message is never repeated back-to-back while any of these are still fresh.
    var recentLines: [String] = []
    var triggerCount = 0 {
        didSet { triggerCountStorage = triggerCount }
    }
    var lastFeedbackAt: Date?
    var lastInspirationAt: Date?
    @ObservationIgnored var dismissWorkItem: DispatchWorkItem?
    // Internal (not private) so tests can reset it directly — `PetBuddy.shared`
    // is a per-process singleton, and once an event has been marked seen there is
    // no way to simulate "first use" again without direct access.
    @ObservationIgnored var seenEvents: Set<String> = []
    @ObservationIgnored private var pendingDeferredEvent: PetEvent?
    @ObservationIgnored private var pendingDeferredExpiry: Date?

    private init() {
        isEnabled = isEnabledStorage
        tipsEnabled = tipsEnabledStorage
        triggerCount = triggerCountStorage
        species = PetSpecies.resolved(from: speciesStorage)
        hasChosenSpecies = speciesChosenStorage
        seenEvents = Set(seenEventsStorage.split(separator: ",").map(String.init))
        switchHintShown = switchHintShownStorage
        hasOpenedPopover = popoverOpenedStorage
        hasSwitchedSpecies = hasSwitchedSpeciesStorage
        // `PetBuddy.shared` is constructed exactly once per launch, making `init`
        // the natural place to count sessions for the switch-hint trigger.
        sessionCountStorage += 1
        sessionCount = sessionCountStorage
    }

    func trigger(_ event: PetEvent) {
        guard isEnabled else { return }

        pulseToken += 1

        // The teaching hint and event bubbles never compete for attention.
        guard !isSwitchHintPresented else { return }

        let now = Date()
        let isFirstUse = !seenEvents.contains(rawKey(for: event))
        markSeen(event)

        // Hero moments (greeting/export/save/warning) and a feature's first-ever
        // firing always get a chance at a bubble; everything else after that is
        // acknowledged with a pulse only, per the reduced-chatter redesign.
        let isHero = PetLines.isHero(event)
        guard isHero || isFirstUse else { return }

        guard tipsEnabled else { return }

        // A first-use tip is a one-shot educational moment — `markSeen` above has
        // already spent it, so letting the throttle eat it here would lose it
        // forever instead of just delaying it. Warnings are exempt for the same
        // "don't silently drop something important" reason.
        if let lastShownAt, now.timeIntervalSince(lastShownAt) < minInterval, event != .warning, !isFirstUse {
            return
        }

        // Non-critical hints wait out an active edit/selection instead of covering
        // it; warnings are allowed through immediately (see `isUserEditing`/
        // `isUserSelecting` doc comments for the current no-op-by-default wiring).
        if event != .warning, isUserEditing || isUserSelecting {
            pendingDeferredEvent = event
            pendingDeferredExpiry = now.addingTimeInterval(20)
            return
        }

        triggerCount += 1
        let shouldShowFeedback = triggerCount.isMultiple(of: 15) &&
            lastFeedbackAt.map { now.timeIntervalSince($0) > 8 * 60 } ?? true
        let shouldShowInspiration = triggerCount.isMultiple(of: 7) &&
            lastInspirationAt.map { now.timeIntervalSince($0) > 5 * 60 } ?? true

        let sourceLines: [String]
        if shouldShowFeedback {
            sourceLines = PetLines.feedback
            lastFeedbackAt = now
        } else if shouldShowInspiration {
            sourceLines = PetLines.inspiration
            lastInspirationAt = now
        } else if isFirstUse, let firstUse = PetLines.firstUseLine(for: event) {
            sourceLines = [firstUse]
        } else {
            sourceLines = PetLines.lines(for: species, event: event)
        }

        guard let selectedLine = pickLine(from: sourceLines) else { return }
        show(selectedLine, at: now, isSticky: event == .warning)
    }

    /// Picks a line that isn't among the last few shown, falling back to any line
    /// (even a repeat) if every candidate has recently been shown.
    private func pickLine(from lines: [String]) -> String? {
        guard !lines.isEmpty else { return nil }
        let fresh = lines.filter { !recentLines.contains($0) }
        return (fresh.isEmpty ? lines : fresh).randomElement()
    }

    private func rawKey(for event: PetEvent) -> String {
        String(describing: event)
    }

    private func markSeen(_ event: PetEvent) {
        let key = rawKey(for: event)
        guard seenEvents.insert(key).inserted else { return }
        seenEventsStorage = seenEvents.sorted().joined(separator: ",")
    }

    /// If the editing/selection gate just cleared and a hint was waiting, show it
    /// now (unless it expired while we waited).
    private func flushDeferredHintIfPossible() {
        guard let event = pendingDeferredEvent, let expiry = pendingDeferredExpiry else { return }
        pendingDeferredEvent = nil
        pendingDeferredExpiry = nil
        guard Date() < expiry else { return }
        trigger(event)
    }

    /// Switch the chosen companion (from the picker, avatar popover, or menu). Updates
    /// identity only; the transient message state is untouched except for an immediate
    /// confirmation greeting in the new pet's voice. Persists automatically via the
    /// `species`/`hasChosenSpecies` `didSet`s.
    func selectSpecies(_ newSpecies: PetSpecies) {
        // A real switch (an already-chosen companion swapped for the other one) gets
        // the one-time "meet my sibling" joke instead of the plain greeting — first
        // pick has no prior companion to reference.
        let wasActualSwitch = hasChosenSpecies && newSpecies != species
        let isNewChoice = newSpecies != species || !hasChosenSpecies
        species = newSpecies
        hasChosenSpecies = true
        if wasActualSwitch { hasSwitchedSpecies = true }
        guard isEnabled, isNewChoice else { return }
        // Bypass the inter-message throttle so the choice confirms right away.
        let lines = wasActualSwitch ? PetLines.siblingSwitchLines(for: newSpecies) : PetLines.lines(for: newSpecies, event: .greeting)
        guard let line = pickLine(from: lines) else { return }
        show(line, at: Date(), isSticky: false)
    }

    /// Present a line in the bubble (or, when window/chrome constraints demand it,
    /// collapse it into the hint-chip badge) and schedule its dismissal. Shared by
    /// event triggers and explicit species-selection confirmations.
    private func show(_ line: String, at now: Date, isSticky: Bool) {
        recentLines.insert(line, at: 0)
        if recentLines.count > 5 { recentLines.removeLast(recentLines.count - 5) }
        lastShownAt = now

        // `isBubbleVisible` drives both the floating bubble and the collapsed
        // hint-chip badge (the overlay picks between them based on window/chrome
        // constraints, including the cramped-window case this method can't see) —
        // `lastCollapsedMessage` always mirrors the latest line so the popover can
        // surface it if the overlay ends up rendering the badge instead of the
        // floating bubble for any reason.
        lastCollapsedMessage = line
        currentMessage = isChromeBusy ? nil : line
        isBubbleVisible = true
        isCurrentSticky = isSticky

        dismissWorkItem?.cancel()
        guard !isSticky else { return }
        let item = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.isBubbleVisible = false
            }
        }
        dismissWorkItem = item
        let duration = GamiHintBubble.displayDuration(for: line)
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: item)
    }

    func hush() {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
        isBubbleVisible = false
        isCurrentSticky = false
        currentMessage = nil
    }

    func disable() {
        isEnabled = false
        hush()
    }

    func enable() {
        isEnabled = true
    }
}

struct PetOverlay: View {
    /// True while export/save chrome along the bottom of the window is active
    /// (e.g. `WorkspaceOperationProgressView`) — passed down from `ContentView`,
    /// which already tracks it, rather than re-deriving it here. While true, any
    /// hint collapses into the hint-chip badge instead of a floating bubble, which
    /// guarantees no overlap with that chrome without needing its exact geometry.
    var isChromeBusy = false

    @State private var buddy = PetBuddy.shared
    @State private var windowObserver = GamiWindowSizeObserver()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Below this width or height, the workspace area is considered cramped: the
    /// chip shrinks and every hint collapses to the badge rather than risking a
    /// bubble that has nowhere safe to sit.
    private static let crampedWidth: CGFloat = 700
    private static let crampedHeight: CGFloat = 500

    private var isCramped: Bool {
        windowObserver.size.width > 0 &&
            (windowObserver.size.width < Self.crampedWidth || windowObserver.size.height < Self.crampedHeight)
    }

    var body: some View {
        if buddy.isEnabled {
            VStack(alignment: .trailing, spacing: bubbleSpacing) {
                if showsBubble, let message = buddy.currentMessage {
                    GamiHintBubble(
                        message: message,
                        notchEdge: .bottom,
                        isSticky: buddy.isCurrentSticky,
                        onDismiss: buddy.isCurrentSticky ? { buddy.hush() } : nil
                    )
                    .transition(bubbleTransition)
                } else if showsHintChipBadge {
                    GamiHintChipBadge()
                        .transition(.opacity)
                }
                PetView(presentation: .workspace, isCramped: isCramped)
            }
            .animation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.82), value: buddy.isBubbleVisible)
            .animation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.82), value: buddy.isHovered)
            .onAppear {
                buddy.isChromeBusy = isChromeBusy
                buddy.trigger(.greeting)
            }
            .onChange(of: isChromeBusy) { _, busy in buddy.isChromeBusy = busy }
        }
    }

    /// While at rest, the pet's compact size only needs the base 8pt rhythm.
    /// On hover the pet scales up (from a bottom-trailing anchor, growing
    /// upward) without changing its layout size, so the bubble above it needs
    /// extra room reserved for that growth plus a safe gap, or the enlarged
    /// pet visually pushes into the bubble.
    private var bubbleSpacing: CGFloat {
        guard buddy.isHovered else { return .gamiBubbleGap }
        return PetView.hoverGrowthDelta(for: .workspace) + PetView.popoverGap
    }

    private var showsBubble: Bool {
        buddy.isBubbleVisible && !isCramped && !buddy.isChromeBusy
    }

    /// A hint exists but the window/chrome constraints ruled out a floating
    /// bubble — show the small badge instead (its message surfaces in the popover).
    private var showsHintChipBadge: Bool {
        buddy.isBubbleVisible && (isCramped || buddy.isChromeBusy)
    }

    private var bubbleTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .trailing))
    }
}

/// A small accent-colored badge shown on/near the chip when a hint exists but
/// couldn't safely render as a floating bubble (cramped window, busy chrome). No
/// text — the message is still available via the popover's "Latest tip" row.
private struct GamiHintChipBadge: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(Color.dsAccent)
            .frame(width: 8, height: 8)
            .scaleEffect(pulse ? 1.15 : 0.9)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
            .accessibilityHidden(true)
    }
}

/// Observes the key window's frame size via `NSWindow.didResizeNotification`,
/// purely for cramped-window detection — no layout dependency on `ContentView`'s
/// own view hierarchy, so this stays additive and low-risk.
@MainActor @Observable private final class GamiWindowSizeObserver {
    var size: CGSize = .zero
    @ObservationIgnored private var observer: NSObjectProtocol?

    init() {
        size = NSApp.keyWindow?.frame.size ?? .zero
        observer = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.size = NSApp.keyWindow?.frame.size ?? .zero
            }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }
}

enum PetPresentation {
    case workspace
    case welcome
}

struct PetView: View {
    var presentation: PetPresentation = .workspace
    /// True when the workspace window is small enough that the chip should dock
    /// smaller and skip hover expansion — the popover remains the way to see hints.
    var isCramped: Bool = false

    @State private var buddy = PetBuddy.shared
    @State private var isPopoverPresented = false
    @State private var isSwitchHintPresented = false
    @State private var switchHintWorkItem: DispatchWorkItem?
    @State private var replayToken = 0
    @State private var isHovered = false
    @State private var isPulsing = false
    @State private var pulseResetWorkItem: DispatchWorkItem?
    @State private var hoverTipMessage: String?
    @State private var hoverShowWorkItem: DispatchWorkItem?
    @State private var hoverHideWorkItem: DispatchWorkItem?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // `.popover` content on macOS doesn't inherit the `.environment(\.locale:)`
    // override applied at the scene root — it resets to the system default —
    // so it must be re-applied explicitly to the presented content below.
    @EnvironmentObject private var languageManager: LanguageManager

    private var shouldReduceMotion: Bool {
        reduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// Only the workspace pet grows on hover and shows a hover tip — the welcome
    /// (intro) pet is already large and expressive, and sits beside its own greeting.
    private var supportsHoverExpansion: Bool { presentation == .workspace && !isCramped }

    var body: some View {
        // IMPORTANT: background/border/opacity/scaleEffect/shadow are chained OUTSIDE
        // the Button (decorating it), not nested inside its label. Nesting a transform
        // like `scaleEffect` inside a Button's label can get its rendered bounds pinned
        // to the label's pre-transform layout size on macOS, silently clipping the
        // visual growth — this mirrors the proven-working hover pattern already used by
        // `EmptyStatePill` elsewhere in this app, which decorates its Button the same way.
        Button {
            // Never present both popovers at once — a click always means "open the
            // real popover," which also counts as the user discovering it organically.
            isSwitchHintPresented = false
            isPopoverPresented.toggle()
        } label: {
            petIcon
                .frame(width: iconSize, height: iconSize)
                .padding(iconPadding)
        }
        .buttonStyle(.plain)
        .background(alignment: .center) {
            petBackground
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 1)
        }
        .overlay {
            if presentation == .welcome {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(LinearGradient.dsAccent.opacity(0.55), lineWidth: 1)
                    .blur(radius: 0.4)
            } else if isHovered {
                // Soft accent glow that fades in on hover — the interactive
                // affordance the tiny workspace chip was missing.
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.dsAccent.opacity(colorScheme == .dark ? 0.5 : 0.4), lineWidth: 1.25)
            }
        }
        .opacity(presentation == .workspace && !isHovered ? 0.88 : 1)
        .scaleEffect(currentScale, anchor: .bottomTrailing)
        .shadow(color: shadowColor, radius: shadowRadius, x: 0, y: shadowYOffset)
        // A larger invisible margin around the visible chip so users don't need
        // pixel-perfect hovering — the hit area extends past the paper card.
        .padding(hitAreaPadding)
        .contentShape(Rectangle())
        .help("gami.avatar.help")
        .accessibilityLabel("gami.a11y.label")
        .accessibilityHint("gami.a11y.hint")
        .popover(isPresented: $isPopoverPresented, arrowEdge: .bottom) {
            PetControlPopover(
                presentation: presentation,
                isPresented: $isPopoverPresented,
                buddy: buddy
            )
            .environmentObject(languageManager)
            .environment(\.locale, languageManager.effectiveLocale)
        }
        // A separate, mutually-exclusive popover for the one-time "you can switch
        // companions" teaching hint — see `PetBuddy.isSwitchHintEligible`.
        .popover(isPresented: $isSwitchHintPresented, arrowEdge: .bottom) {
            CompanionSwitchHintCard(
                onSwitchAnytime: {
                    isSwitchHintPresented = false
                    isPopoverPresented = true
                },
                onDismiss: { isSwitchHintPresented = false }
            )
            .environmentObject(languageManager)
            .environment(\.locale, languageManager.effectiveLocale)
        }
        .overlay(alignment: .topTrailing) {
            if presentation == .workspace, let hoverTipMessage {
                // The tip only ever shows while hovered, i.e. while the chip is
                // scaled up — but `.overlay(alignment:)` positions against the
                // pre-scale layout frame (scaleEffect doesn't change layout
                // size), so the offset has to add back the hover growth (which
                // extends upward, since the scale anchor is bottomTrailing)
                // plus a safe gap, or the tip lands on top of the enlarged pet.
                GamiHintBubble(message: hoverTipMessage, notchEdge: nil)
                    .fixedSize()
                    .offset(x: 6, y: -(14 + Self.hoverGrowthDelta(for: .workspace) + Self.popoverGap))
                    .transition(hoverTipTransition)
            }
        }
        // A raw AppKit hover sensor, not SwiftUI's `.onHover` — `.onHover` can be
        // silently swallowed when layered above a Button that also hosts a popover
        // and overlay content, as this one does. NSTrackingArea is the lower-level
        // mechanism `.onHover` itself wraps, and it never intercepts clicks (see
        // `HoverSensor.hitTest`), so every tap still lands on the Button beneath it.
        .overlay(HoverSensor(onChange: handleHover))
        // Re-fold the companion each time a feature fires a fresh message, pulse for
        // a moment of visible feedback even without hovering, and hide any hover tip
        // so the two bubbles never stack.
        .onChange(of: buddy.currentMessage) { _, newValue in
            if newValue != nil {
                replayToken += 1
                hideHoverTipImmediately()
                pulse()
            }
        }
        // A popover taking focus should not leave a stray hover tip behind it.
        .onChange(of: isPopoverPresented) { _, isPresented in
            if isPresented {
                hideHoverTipImmediately()
                buddy.hasOpenedPopover = true
            }
        }
        .onChange(of: isSwitchHintPresented) { _, isPresented in
            buddy.isSwitchHintPresented = isPresented
            if !isPresented { buddy.markSwitchHintShown() }
        }
        .onAppear {
            guard presentation == .workspace else { return }
            scheduleSwitchHintIfEligible()
        }
        .onDisappear {
            hoverShowWorkItem?.cancel()
            hoverHideWorkItem?.cancel()
            pulseResetWorkItem?.cancel()
            switchHintWorkItem?.cancel()
        }
    }

    /// A single, one-shot attempt to show the companion-switch hint, 5s after the
    /// chip appears — long enough that it never competes with the launch greeting
    /// bubble. If any condition isn't met at that moment (cramped window, an
    /// operation in progress, a bubble already visible, the real popover already
    /// open), the hint simply doesn't show this session; it isn't rescheduled,
    /// since `isSwitchHintEligible` stays true until it's shown or pre-empted, and
    /// the next launch tries again.
    private func scheduleSwitchHintIfEligible() {
        guard buddy.isSwitchHintEligible else { return }
        switchHintWorkItem?.cancel()
        let item = DispatchWorkItem {
            guard buddy.isSwitchHintEligible,
                  !isCramped,
                  !buddy.isChromeBusy,
                  !buddy.isBubbleVisible,
                  !isPopoverPresented else { return }
            isSwitchHintPresented = true
        }
        switchHintWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: item)
    }

    /// The chip's combined scale: hover growth and the brief event pulse compose
    /// multiplicatively, so either can be mid-animation without fighting the other.
    private var currentScale: CGFloat {
        let hover = isHovered && supportsHoverExpansion ? hoverScale : 1
        let pulse = isPulsing ? 1.09 : 1
        return hover * pulse
    }

    /// A quick, springy "acknowledged!" pop — independent of hover — so the pet
    /// visibly reacts to every feature event even if the user's mouse is elsewhere.
    /// This is the default liveliness layered on top of the fold replay + idle wag.
    private func pulse() {
        guard !shouldReduceMotion else { return }
        pulseResetWorkItem?.cancel()
        withAnimation(.spring(response: 0.22, dampingFraction: 0.45)) {
            isPulsing = true
        }
        let item = DispatchWorkItem {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.62)) {
                isPulsing = false
            }
        }
        pulseResetWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16, execute: item)
    }

    private var petIcon: some View {
        // The avatar folds into the user's chosen companion (dog or cat) and stays alive
        // — breathing, and wagging its tail (dog) or ears+tail (cat). It re-folds on
        // each feature event via `replayToken`. Motion/idle are handled inside the
        // mark; `excitement` rides the same hover state that already grows the chip,
        // so a dog's tail visibly picks up when the cursor is close.
        OrifoldFoldMark(size: iconSize, interactive: false,
                        figure: .forSpecies(buddy.species), replayTrigger: replayToken,
                        excitement: isHovered ? 1 : 0)
            .clipShape(RoundedRectangle(cornerRadius: .dsRadiusSm, style: .continuous))
    }

    private func handleHover(_ hovering: Bool) {
        if hovering {
            NSCursor.pointingHand.push()
        } else {
            NSCursor.pop()
        }

        hoverShowWorkItem?.cancel()
        hoverHideWorkItem?.cancel()

        withAnimation(shouldReduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.78)) {
            isHovered = hovering
        }

        guard presentation == .workspace else { return }

        // Mirrored onto the shared buddy so `PetOverlay`'s VStack (a sibling,
        // not a descendant of this view) can widen its spacing before this
        // chip finishes growing into the space above it.
        withAnimation(shouldReduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.78)) {
            buddy.isHovered = hovering
        }

        if hovering {
            // A brief pause before the tip appears, so a mouse just passing over the
            // corner doesn't spam a message every time. Ori's pause is longer than
            // Gami's — she doesn't leap to attention, she notices you first.
            let delay: TimeInterval = shouldReduceMotion ? 0.05 : buddy.species.hoverTipDelay
            let item = DispatchWorkItem {
                // Never stack the hover tip on top of a live feature-event bubble.
                guard !buddy.isBubbleVisible else { return }
                let message = PetLines.hoverTip(for: buddy.species)
                if shouldReduceMotion {
                    hoverTipMessage = message
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        hoverTipMessage = message
                    }
                }
            }
            hoverShowWorkItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
        } else {
            let item = DispatchWorkItem { hideHoverTipImmediately() }
            hoverHideWorkItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: item)
        }
    }

    private func hideHoverTipImmediately() {
        guard hoverTipMessage != nil else { return }
        if shouldReduceMotion {
            hoverTipMessage = nil
        } else {
            withAnimation(.easeOut(duration: 0.16)) {
                hoverTipMessage = nil
            }
        }
    }

    private var hoverTipTransition: AnyTransition {
        shouldReduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.94, anchor: .bottomTrailing))
    }

    // MARK: Sizing
    //
    // Workspace and welcome (intro) contexts are sized independently: the intro pet is
    // already large and brand-forward, while the workspace pet docks compactly and
    // grows only on hover/interaction. Sizes are clamped to explicit min/max bounds
    // (rather than one hardcoded literal) so the compact chip, hover-expanded chip, and
    // hit area stay in their intended ranges even if the base constants are tuned later.

    /// Compact (at-rest) container size — icon + its padding — clamped to Apple HIG's
    /// comfortable-but-unobtrusive dock-widget range. Docks smaller still in a
    /// cramped workspace window, where hover expansion is also disabled.
    private var compactContainerSize: CGFloat {
        isCramped ? .gamiChipCramped : Self.compactContainerSize(for: presentation)
    }

    /// How much larger the container becomes on hover, clamped to a clearly-bigger but
    /// still-corner-sized preview. Equal to the compact size in cramped mode, so
    /// `hoverScale` becomes a no-op (see `supportsHoverExpansion`).
    private var hoverContainerSize: CGFloat {
        isCramped ? .gamiChipCramped : Self.hoverContainerSize(for: presentation)
    }

    private var hoverScale: CGFloat {
        hoverContainerSize / compactContainerSize
    }

    static func compactContainerSize(for presentation: PetPresentation) -> CGFloat {
        switch presentation {
        case .welcome: return 64
        case .workspace: return .gamiChipCompact
        }
    }

    static func hoverContainerSize(for presentation: PetPresentation) -> CGFloat {
        switch presentation {
        case .welcome: return compactContainerSize(for: presentation) * 1.15
        case .workspace: return .gamiChipHover
        }
    }

    /// How much the container's top edge grows upward on hover — the scale
    /// anchor is `.bottomTrailing`, so this growth is entirely up-and-left;
    /// the right/bottom edges never move. Callers outside `PetView` (like
    /// `PetOverlay`) use this to keep floating bubbles clear of the enlarged
    /// pet without needing to measure rendered geometry at runtime.
    static func hoverGrowthDelta(for presentation: PetPresentation) -> CGFloat {
        hoverContainerSize(for: presentation) - compactContainerSize(for: presentation)
    }

    /// Minimum safe gap between the pet's scaled bounds and any floating
    /// bubble — mirrors a `--pet-popover-gap` design token.
    static let popoverGap: CGFloat = .dsLG

    private var iconPadding: CGFloat {
        presentation == .welcome ? 5 : 8
    }

    private var iconSize: CGFloat {
        compactContainerSize - iconPadding * 2
    }

    private var cornerRadius: CGFloat {
        presentation == .welcome ? 16 : 14
    }

    /// Extra invisible margin around the visible chip, so the button's tappable/
    /// hoverable region is comfortably larger than the paper card without visually
    /// growing it — a standard "generous hit target" pattern.
    private var hitAreaPadding: CGFloat {
        presentation == .welcome ? 4 : 10
    }

    @ViewBuilder
    private var petBackground: some View {
        switch presentation {
        case .welcome:
            Color.dsCard.opacity(colorScheme == .dark ? 0.92 : 0.96)
        case .workspace:
            // A single light frosted card — resting quietly on the page rather than
            // announcing itself as an opaque block.
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Color.dsSurface.opacity(colorScheme == .dark ? (isHovered ? 0.55 : 0.48) : (isHovered ? 0.40 : 0.32))
            }
        }
    }

    private var borderColor: Color {
        switch presentation {
        case .welcome:
            return Color.dsAccent.opacity(colorScheme == .dark ? 0.34 : 0.24)
        case .workspace:
            return Color.dsSeparator.opacity(colorScheme == .dark ? 0.90 : 1)
        }
    }

    private var shadowColor: Color {
        switch presentation {
        case .welcome:
            return Color.dsAccent.opacity(colorScheme == .dark ? 0.22 : 0.18)
        case .workspace:
            // A quiet paper-card shadow at rest; only slightly deeper on hover — the
            // chip should read as resting on the page, not floating above it.
            let base = Color.black.opacity(colorScheme == .dark ? 0.20 : 0.08)
            return isHovered ? Color.black.opacity(colorScheme == .dark ? 0.28 : 0.14) : base
        }
    }

    private var shadowRadius: CGFloat {
        switch presentation {
        case .welcome: return 18
        case .workspace: return isHovered ? 12 : 8
        }
    }

    private var shadowYOffset: CGFloat {
        switch presentation {
        case .welcome: return 8
        case .workspace: return isHovered ? 4 : 3
        }
    }
}

/// A minimal AppKit hover sensor used in place of SwiftUI's `.onHover`, which proved
/// unreliable layered above a Button that also hosts a popover and dynamic overlay
/// content. `NSTrackingArea` is the actual lower-level mechanism `.onHover` wraps, so
/// this is the same signal with none of the layering ambiguity — and `hitTest` always
/// returns `nil`, so this view is fully transparent to clicks; the SwiftUI Button
/// beneath it keeps receiving every tap untouched.
private struct HoverSensor: NSViewRepresentable {
    var onChange: (Bool) -> Void

    func makeNSView(context: Context) -> SensorView {
        let view = SensorView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ nsView: SensorView, context: Context) {
        nsView.onChange = onChange
    }

    final class SensorView: NSView {
        var onChange: ((Bool) -> Void)?
        private var trackingArea: NSTrackingArea?

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let trackingArea { removeTrackingArea(trackingArea) }
            let area = NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(area)
            trackingArea = area
        }

        override func mouseEntered(with event: NSEvent) { onChange?(true) }
        override func mouseExited(with event: NSEvent) { onChange?(false) }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

/// A one-time teaching popover: "you can switch companions." Shown at most once,
/// anchored to the chip like the real control popover, and pre-empted the moment
/// the user discovers either path (opening the popover, switching species) on
/// their own. See `PetBuddy.isSwitchHintEligible`.
private struct CompanionSwitchHintCard: View {
    var onSwitchAnytime: () -> Void
    var onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var didAnimateIn = false

    private var shouldReduceMotion: Bool {
        reduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    var body: some View {
        VStack(alignment: .leading, spacing: .dsMD) {
            Text("companionHint.title")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.dsTextPrimary)

            HStack(alignment: .top, spacing: .dsMD) {
                companionRow(species: .dog, lineKey: "companionHint.gami")
                companionRow(species: .cat, lineKey: "companionHint.ori")
            }

            HStack {
                Button("companionHint.dismiss", action: onDismiss)
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.dsTextSecondary)
                Spacer()
                Button("companionHint.switch", action: onSwitchAnytime)
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.dsAccent)
            }
            .font(.dsCaption())
        }
        .padding(.dsMD)
        .frame(width: 260, alignment: .leading)
        .background(alignment: .center) {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Color.dsSurface.opacity(colorScheme == .dark ? 0.55 : 0.42)
            }
            .clipShape(RoundedRectangle(cornerRadius: .dsRadiusMd, style: .continuous))
        }
        .overlay {
            RoundedRectangle(cornerRadius: .dsRadiusMd, style: .continuous)
                .strokeBorder(Color.dsSeparator.opacity(colorScheme == .dark ? 0.7 : 0.9), lineWidth: 1)
        }
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.24 : 0.10), radius: 10, x: 0, y: 4)
        .scaleEffect(didAnimateIn || shouldReduceMotion ? 1 : 0.96, anchor: .bottomTrailing)
        .opacity(didAnimateIn || shouldReduceMotion ? 1 : 0)
        .accessibilityElement(children: .contain)
        .onAppear {
            guard !shouldReduceMotion else {
                didAnimateIn = true
                return
            }
            withAnimation(.spring(response: 0.34, dampingFraction: 0.78)) {
                didAnimateIn = true
            }
        }
    }

    private func companionRow(species: PetSpecies, lineKey: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            OrifoldFoldMark(size: 28, interactive: false, figure: .forSpecies(species))
                .clipShape(RoundedRectangle(cornerRadius: .dsRadiusSm, style: .continuous))
            Text(lineKey)
                .font(.system(size: 10.5, weight: .regular))
                .foregroundStyle(Color.dsTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PetControlPopover: View {
    var presentation: PetPresentation
    @Binding var isPresented: Bool
    var buddy: PetBuddy

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    // Passed into species.displayName(locale:) below so this view's `body`
    // actually reads it — SwiftUI only re-invokes `body` on a locale change
    // for views that read `\.locale` during the previous evaluation.
    @Environment(\.locale) private var locale
    @State private var didAnimateIn = false

    private var shouldReduceMotion: Bool {
        reduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private var feedbackURL: URL? {
        URL(string: "mailto:umangdhawan97@gmail.com")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: presentation == .welcome ? .dsMD : .dsSM) {
            if presentation == .welcome {
                welcomeHeader
            } else {
                workspaceHeader
            }

            if let lastCollapsedMessage = buddy.lastCollapsedMessage {
                latestTipRow(lastCollapsedMessage)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("petBuddy.menu.companion.title")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.dsTextSecondary)
                PetSpeciesSwitcher(selected: buddy.species) { buddy.selectSpecies($0) }
            }

            Divider().opacity(0.6)

            Toggle(isOn: Binding(
                get: { !buddy.tipsEnabled },
                set: { buddy.tipsEnabled = !$0 }
            )) {
                Text("gami.menu.hideTips")
            }
            .toggleStyle(.checkbox)

            Button {
                buddy.hush()
                isPresented = false
            } label: {
                Label("petBuddy.menu.shush.title", systemImage: "speaker.slash")
            }

            Button {
                buddy.disable()
                isPresented = false
            } label: {
                Label("petBuddy.menu.hide.title", systemImage: "eye.slash")
            }

            if let feedbackURL {
                Link(destination: feedbackURL) {
                    Label("petBuddy.menu.sendFeedback.title", systemImage: "paperplane")
                }
            }
        }
        .labelStyle(.titleAndIcon)
        .buttonStyle(.plain)
        .font(.dsCaption())
        .foregroundStyle(Color.dsTextPrimary)
        .padding(presentation == .welcome ? .dsLG : .dsMD)
        .frame(width: presentation == .welcome ? 286 : 190, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: presentation == .welcome ? .dsRadiusLg : .dsRadiusMd, style: .continuous))
        .background(
            RoundedRectangle(cornerRadius: presentation == .welcome ? .dsRadiusLg : .dsRadiusMd, style: .continuous)
                .fill(Color.dsSurface.opacity(colorScheme == .dark ? 0.86 : 0.72))
        )
        .overlay {
            RoundedRectangle(cornerRadius: presentation == .welcome ? .dsRadiusLg : .dsRadiusMd, style: .continuous)
                .strokeBorder(Color.dsSeparator.opacity(colorScheme == .dark ? 0.85 : 1), lineWidth: 1)
        }
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.28 : 0.14), radius: presentation == .welcome ? 20 : 12, x: 0, y: 8)
        .scaleEffect(didAnimateIn || shouldReduceMotion ? 1 : 0.96, anchor: .bottomTrailing)
        .opacity(didAnimateIn || shouldReduceMotion ? 1 : 0)
        .onAppear {
            guard !shouldReduceMotion else {
                didAnimateIn = true
                return
            }
            withAnimation(.spring(response: 0.34, dampingFraction: 0.78)) {
                didAnimateIn = true
            }
        }
        .onDisappear {
            buddy.lastCollapsedMessage = nil
        }
    }

    /// Names the character and its role in the popover header — the chip itself
    /// stays text-free, so this is the one place the "Gami · Orifold Guide" label
    /// is spelled out in full.
    private var workspaceHeader: some View {
        HStack(alignment: .center, spacing: .dsSM) {
            OrifoldFoldMark(size: 28, interactive: false, figure: .forSpecies(buddy.species))
                .clipShape(RoundedRectangle(cornerRadius: .dsRadiusSm, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(buddy.species.displayName(locale: locale))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.dsTextPrimary)
                Text("gami.popover.subtitle")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(Color.dsTextSecondary)
            }
        }
    }

    /// A hint that couldn't safely render as a floating bubble (cramped window,
    /// busy export/save chrome) is never silently lost — it surfaces here.
    private func latestTipRow(_ message: String) -> some View {
        Text(message)
            .font(.dsCaption())
            .foregroundStyle(Color.dsTextPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.dsSM)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.dsSurface.opacity(colorScheme == .dark ? 0.5 : 0.4), in: RoundedRectangle(cornerRadius: .dsRadiusSm, style: .continuous))
    }

    private var welcomeHeader: some View {
        HStack(alignment: .top, spacing: .dsSM) {
            Image(systemName: "sparkles")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(LinearGradient.dsAccent)
                .rotationEffect(didAnimateIn && !shouldReduceMotion ? .degrees(8) : .zero)
            VStack(alignment: .leading, spacing: 3) {
                Text("petBuddy.welcome.title")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.dsTextPrimary)
                Text("petBuddy.welcome.subtitle")
                    .font(.dsCaption())
                    .foregroundStyle(Color.dsTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.bottom, .dsXS)
    }
}

/// Compact two-up segmented control for switching the companion between dog and cat.
/// Used in the pet popover; changing identity here persists immediately via
/// `PetBuddy.selectSpecies`.
struct PetSpeciesSwitcher: View {
    var selected: PetSpecies
    var onSelect: (PetSpecies) -> Void

    @Environment(\.colorScheme) private var colorScheme
    // Passed into species.displayName(locale:)/accessibilityLabel(locale:) below
    // so this view's `body` actually reads it — SwiftUI only re-invokes `body`
    // on a locale change for views that read `\.locale` during the previous
    // evaluation.
    @Environment(\.locale) private var locale

    var body: some View {
        HStack(spacing: 4) {
            ForEach(PetSpecies.allCases, id: \.self) { species in
                let isSelected = species == selected
                Button {
                    onSelect(species)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: species.symbolName)
                            .font(.system(size: 11, weight: .semibold))
                        Text(species.displayName(locale: locale))
                            .font(.system(size: 11, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
                    .foregroundStyle(isSelected ? Color.dsAccent : Color.dsTextSecondary)
                    .background {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color.dsAccentSoft)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .strokeBorder(Color.dsAccent.opacity(0.3), lineWidth: 1)
                                }
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(species.accessibilityLabel(locale: locale))
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.dsSurface.opacity(colorScheme == .dark ? 0.55 : 0.5))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.dsSeparator.opacity(0.6), lineWidth: 1)
        }
    }
}
