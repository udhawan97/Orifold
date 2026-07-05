import AppKit
import Observation
import SwiftUI

enum PetEvent: CaseIterable {
    case highlight, comment, tag, sign, note, edit, ink, rotate, delete, export, save, addFile, search, greeting
}

enum PetLines {
    /// The curated "hero" events that get a distinct dog/cat voice. Every other
    /// event reuses the shared, species-neutral copy so the localization burden
    /// stays bounded while personality lands where it's most visible.
    private static let heroEvents: Set<PetEvent> = [.greeting, .export, .save]

    /// Resolve the lines for an event, giving the chosen companion its own voice on
    /// the hero events and falling back to shared copy everywhere else.
    static func lines(for species: PetSpecies, event: PetEvent) -> [String] {
        if heroEvents.contains(event), let hero = speciesHero(species, event) {
            return hero
        }
        return shared(for: event)
    }

    // Keys must be string literals: `L10n.string` takes a `LocalizationValue`, so any
    // interpolated variable would be captured as a format argument (looking up
    // "pet.%@.greeting.1") rather than the concrete key. Hence the explicit switch.
    private static func speciesHero(_ species: PetSpecies, _ event: PetEvent) -> [String]? {
        switch (species, event) {
        case (.dog, .greeting):
            return [L10n.string("pet.dog.greeting.1"), L10n.string("pet.dog.greeting.2")]
        case (.dog, .export):
            return [L10n.string("pet.dog.export.1"), L10n.string("pet.dog.export.2")]
        case (.dog, .save):
            return [L10n.string("pet.dog.save.1"), L10n.string("pet.dog.save.2")]
        case (.cat, .greeting):
            return [L10n.string("pet.cat.greeting.1"), L10n.string("pet.cat.greeting.2")]
        case (.cat, .export):
            return [L10n.string("pet.cat.export.1"), L10n.string("pet.cat.export.2")]
        case (.cat, .save):
            return [L10n.string("pet.cat.save.1"), L10n.string("pet.cat.save.2")]
        default:
            return nil
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

    var isEnabled = true {
        didSet { isEnabledStorage = isEnabled }
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

    let minInterval: TimeInterval = 6
    let displayDuration: TimeInterval = 4.5

    var lastShownAt: Date?
    var lastLine: String?
    var triggerCount = 0 {
        didSet { triggerCountStorage = triggerCount }
    }
    var lastFeedbackAt: Date?
    var lastInspirationAt: Date?
    @ObservationIgnored var dismissWorkItem: DispatchWorkItem?

    private init() {
        isEnabled = isEnabledStorage
        triggerCount = triggerCountStorage
        species = PetSpecies.resolved(from: speciesStorage)
        hasChosenSpecies = speciesChosenStorage
    }

    func trigger(_ event: PetEvent) {
        guard isEnabled else { return }

        let now = Date()
        if let lastShownAt, now.timeIntervalSince(lastShownAt) < minInterval {
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
        } else {
            sourceLines = PetLines.lines(for: species, event: event)
        }

        var line = sourceLines.randomElement()
        if line == lastLine, sourceLines.count > 1 {
            line = sourceLines.randomElement()
        }
        guard let selectedLine = line, !selectedLine.isEmpty else { return }

        show(selectedLine, at: now)
    }

    /// Switch the chosen companion (from the picker, avatar popover, or menu). Updates
    /// identity only; the transient message state is untouched except for an immediate
    /// confirmation greeting in the new pet's voice. Persists automatically via the
    /// `species`/`hasChosenSpecies` `didSet`s.
    func selectSpecies(_ newSpecies: PetSpecies) {
        let isNewChoice = newSpecies != species || !hasChosenSpecies
        species = newSpecies
        hasChosenSpecies = true
        guard isEnabled, isNewChoice else { return }
        // Bypass the inter-message throttle so the choice confirms right away.
        var line = PetLines.lines(for: newSpecies, event: .greeting).randomElement()
        if line == lastLine {
            line = PetLines.lines(for: newSpecies, event: .greeting).randomElement()
        }
        if let line, !line.isEmpty {
            show(line, at: Date())
        }
    }

    /// Present a line in the bubble and schedule its dismissal. Shared by event
    /// triggers and explicit species-selection confirmations.
    private func show(_ line: String, at now: Date) {
        currentMessage = line
        isBubbleVisible = true
        lastShownAt = now
        lastLine = line

        dismissWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.isBubbleVisible = false
            }
        }
        dismissWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + displayDuration, execute: item)
    }

    func hush() {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
        isBubbleVisible = false
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
    @State private var buddy = PetBuddy.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if buddy.isEnabled {
            VStack(alignment: .trailing, spacing: .dsSM) {
                if buddy.isBubbleVisible, let message = buddy.currentMessage {
                    PetBubble(message: message)
                        .allowsHitTesting(false)
                        .transition(bubbleTransition)
                }
                PetView(presentation: .workspace)
            }
            .animation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.82), value: buddy.isBubbleVisible)
            .onAppear { buddy.trigger(.greeting) }
        }
    }

    private var bubbleTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .trailing))
    }
}

struct PetBubble: View {
    let message: String
    @Environment(\.colorScheme) private var colorScheme

    private var feedbackURL: URL? {
        guard message.contains("umangdhawan97@gmail.com") else { return nil }
        return URL(string: "mailto:umangdhawan97@gmail.com")
    }

    var body: some View {
        Group {
            if let feedbackURL {
                Link(destination: feedbackURL) {
                    bubbleText
                }
                .buttonStyle(.plain)
            } else {
                bubbleText
            }
        }
        .padding(.horizontal, .dsMD)
        .padding(.vertical, .dsSM)
        .frame(maxWidth: 240, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: .dsRadiusMd, style: .continuous))
        .background(
            RoundedRectangle(cornerRadius: .dsRadiusMd, style: .continuous)
                .fill(Color.dsSurface.opacity(colorScheme == .dark ? 0.82 : 0.68))
        )
        .overlay {
            RoundedRectangle(cornerRadius: .dsRadiusMd, style: .continuous)
                .strokeBorder(Color.dsSeparator.opacity(colorScheme == .dark ? 0.85 : 1), lineWidth: 1)
        }
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.28 : 0.12), radius: 14, x: 0, y: 6)
    }

    private var bubbleText: some View {
        Text(message)
            .font(.dsCaption())
            .foregroundStyle(Color.dsTextPrimary)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

enum PetPresentation {
    case workspace
    case welcome
}

struct PetView: View {
    var presentation: PetPresentation = .workspace

    @State private var buddy = PetBuddy.shared
    @State private var isPopoverPresented = false
    @State private var replayToken = 0
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button {
            isPopoverPresented.toggle()
        } label: {
            petIcon
                .frame(width: iconSize, height: iconSize)
                .padding(iconPadding)
                .background(petBackground, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(borderColor, lineWidth: 1)
                }
                .overlay {
                    if presentation == .welcome {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(LinearGradient.dsAccent.opacity(0.55), lineWidth: 1)
                            .blur(radius: 0.4)
                    }
                }
                .opacity(presentation == .workspace ? 0.88 : 1)
                .shadow(color: shadowColor, radius: presentation == .welcome ? 18 : 10, x: 0, y: presentation == .welcome ? 8 : 4)
        }
        .buttonStyle(.plain)
        .help("petBuddy.avatar.help")
        .popover(isPresented: $isPopoverPresented, arrowEdge: .bottom) {
            PetControlPopover(
                presentation: presentation,
                isPresented: $isPopoverPresented,
                buddy: buddy
            )
        }
        // Re-fold the companion each time a feature fires a fresh message.
        .onChange(of: buddy.currentMessage) { _, newValue in
            if newValue != nil { replayToken += 1 }
        }
    }

    private var petIcon: some View {
        // The avatar folds into the user's chosen companion (dog or cat) and stays alive
        // — breathing, and wagging its tail (dog) or ears (cat). It re-folds on each
        // feature event via `replayToken`. Motion/idle are handled inside the mark.
        OrifoldFoldMark(size: iconSize, interactive: false,
                        figure: .forSpecies(buddy.species), replayTrigger: replayToken)
            .clipShape(RoundedRectangle(cornerRadius: .dsRadiusSm, style: .continuous))
    }

    private var feedbackURL: URL? {
        URL(string: "mailto:umangdhawan97@gmail.com")
    }

    private var iconSize: CGFloat {
        presentation == .welcome ? 54 : 34
    }

    private var iconPadding: CGFloat {
        presentation == .welcome ? 5 : 4
    }

    private var cornerRadius: CGFloat {
        presentation == .welcome ? 16 : 10
    }

    private var petBackground: Color {
        switch presentation {
        case .welcome:
            return Color.dsCard.opacity(colorScheme == .dark ? 0.92 : 0.96)
        case .workspace:
            return Color.dsSurface.opacity(colorScheme == .dark ? 0.86 : 0.78)
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
            return Color.black.opacity(colorScheme == .dark ? 0.24 : 0.12)
        }
    }

}

private struct PetControlPopover: View {
    var presentation: PetPresentation
    @Binding var isPresented: Bool
    var buddy: PetBuddy

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
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
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("petBuddy.menu.companion.title")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.dsTextSecondary)
                PetSpeciesSwitcher(selected: buddy.species) { buddy.selectSpecies($0) }
            }

            Divider().opacity(0.6)

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
                        Text(species.displayName)
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
                .accessibilityLabel(species.accessibilityLabel)
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
