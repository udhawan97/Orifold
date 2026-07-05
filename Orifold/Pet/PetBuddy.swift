import AppKit
import Observation
import SwiftUI

enum PetEvent: CaseIterable {
    case highlight, comment, tag, sign, note, edit, ink, rotate, delete, export, save, addFile, search, greeting
}

enum PetLines {
    static var byEvent: [PetEvent: [String]] {
        [
            .highlight: [
                L10n.string("pet.event.highlight.1"),
                L10n.string("pet.event.highlight.2"),
                L10n.string("pet.event.highlight.3"),
                L10n.string("pet.event.highlight.4")
            ],
            .comment: [
                L10n.string("pet.event.comment.1"),
                L10n.string("pet.event.comment.2"),
                L10n.string("pet.event.comment.3"),
                L10n.string("pet.event.comment.4")
            ],
            .tag: [
                L10n.string("pet.event.tag.1"),
                L10n.string("pet.event.tag.2"),
                L10n.string("pet.event.tag.3")
            ],
            .sign: [
                L10n.string("pet.event.sign.1"),
                L10n.string("pet.event.sign.2"),
                L10n.string("pet.event.sign.3"),
                L10n.string("pet.event.sign.4")
            ],
            .note: [
                L10n.string("pet.event.note.1"),
                L10n.string("pet.event.note.2")
            ],
            .edit: [
                L10n.string("pet.event.edit.1"),
                L10n.string("pet.event.edit.2"),
                L10n.string("pet.event.edit.3")
            ],
            .ink: [
                L10n.string("pet.event.ink.1"),
                L10n.string("pet.event.ink.2")
            ],
            .rotate: [
                L10n.string("pet.event.rotate.1"),
                L10n.string("pet.event.rotate.2")
            ],
            .delete: [
                L10n.string("pet.event.delete.1"),
                L10n.string("pet.event.delete.2")
            ],
            .export: [
                L10n.string("pet.event.export.1"),
                L10n.string("pet.event.export.2")
            ],
            .save: [
                L10n.string("pet.event.save.1"),
                L10n.string("pet.event.save.2")
            ],
            .addFile: [
                L10n.string("pet.event.addFile.1"),
                L10n.string("pet.event.addFile.2")
            ],
            .search: [
                L10n.string("pet.event.search.1"),
                L10n.string("pet.event.search.2")
            ],
            .greeting: [
                L10n.string("pet.event.greeting.1"),
                L10n.string("pet.event.greeting.2")
            ]
        ]
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

    var isEnabled = true {
        didSet { isEnabledStorage = isEnabled }
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
            sourceLines = PetLines.byEvent[event] ?? []
        }

        var line = sourceLines.randomElement()
        if line == lastLine, sourceLines.count > 1 {
            line = sourceLines.randomElement()
        }
        guard let selectedLine = line, !selectedLine.isEmpty else { return }

        currentMessage = selectedLine
        isBubbleVisible = true
        lastShownAt = now
        lastLine = selectedLine

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
    @State private var isBreathing = false
    @State private var isBouncing = false
    @State private var isPopoverPresented = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    private var shouldReduceMotion: Bool {
        reduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

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
                .scaleEffect(scale)
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
        .animation(shouldReduceMotion ? nil : .easeInOut(duration: 3).repeatForever(autoreverses: true), value: isBreathing)
        .animation(shouldReduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.42), value: isBouncing)
        .onAppear {
            guard !shouldReduceMotion else { return }
            isBreathing = true
        }
        .onChange(of: buddy.currentMessage) { _, _ in
            bounce()
        }
    }

    private var petIcon: some View {
        Group {
            if presentation == .workspace {
                // Dashboard pet reuses the landing screen's origami-fold intro mark
                // as its avatar, so the same brand moment plays here too.
                OrifoldFoldMark(size: iconSize, interactive: false)
            } else if let icon = NSApp.applicationIconImage {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "doc.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Color.dsAccent)
            }
        }
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

    private var scale: CGFloat {
        if isBouncing { return 1.12 }
        let breathingScale: CGFloat = presentation == .welcome ? 1.06 : 1.025
        return isBreathing && !shouldReduceMotion ? breathingScale : 1.0
    }

    private func bounce() {
        guard !shouldReduceMotion else { return }
        isBouncing = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [isBreathing] in
            guard self.isBreathing == isBreathing else { return }
            self.isBouncing = false
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
