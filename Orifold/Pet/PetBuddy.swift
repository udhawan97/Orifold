import AppKit
import Observation
import SwiftUI

enum PetEvent: CaseIterable {
    case highlight, comment, tag, sign, note, edit, ink, rotate, delete, export, save, addFile, search, greeting
}

enum PetLines {
    static let byEvent: [PetEvent: [String]] = [
        .highlight: ["Highlighted. Future-you will pretend they read the rest.", "That sentence never stood a chance.", "Tip: drag over text, then pick a color — highlights stack, so go easy.", "Yellow again? A classic never fails."],
        .comment: ["A comment — bold of you to leave a paper trail.", "Noted. Literally.", "Tip: tag a comment now and you'll find it in seconds later.", "Sharp feedback. Speaking of which… the dev would love yours 👀"],
        .tag: ["Tagged. Organized people are just tidy worriers with labels.", "Tip: reuse tags and your filters will thank you.", "One tag to rule them all."],
        .sign: ["Signed, sealed — hopefully not regretted.", "That's a legally-adjacent flourish right there.", "Tip: drag to resize the signature before you commit.", "Very official. Your future self approves."],
        .note: ["A sticky note. The Post-it lives on, digitally.", "Tip: notes stay put even after you rearrange pages."],
        .edit: ["Editing a PDF? Bold. They said it couldn't be done.", "Tip: click any text to tweak it in place.", "Rewriting history, one line at a time."],
        .ink: ["Freehand! Bob Ross would be proud.", "Tip: hold steady — undo is one ⌘Z away."],
        .rotate: ["Whoa, the page turned sideways. Better now?", "Tip: rotation applies only to the page you picked."],
        .delete: ["Gone. We don't talk about that page anymore.", "Tip: ⌘Z brings it back if you panic."],
        .export: ["Exported. Go attach it to something important.", "Tip: flatten before sharing so annotations stick."],
        .save: ["Saved. Responsible of you.", "Locked in. Nicely done."],
        .addFile: ["Two PDFs enter, one workspace leaves.", "Tip: drag pages between files to reshuffle."],
        .search: ["Looking for something? Aren't we all.", "Tip: results jump you straight to the page."],
        .greeting: ["Back again? I never left.", "Ready when you are."]
    ]

    static let feedback: [String] = [
        "Psst — Orifold is brand new. The developer would genuinely love your thoughts: umangdhawan97@gmail.com",
        "Enjoying this? Tell the human who made it: umangdhawan97@gmail.com — they read every message.",
        "You've done real work today. Worth a quick note? umangdhawan97@gmail.com"
    ]

    static let inspiration: [String] = [
        "Progress counts, even when it arrives wearing a loading spinner.",
        "Make the next page better. The whole document will get the hint.",
        "Clarity is a power move. So is saving before experimenting.",
        "One clean edit beats twelve heroic explanations.",
        "Your future self called. They appreciate the filenames.",
        "Small tidy choices compound. Annoyingly practical, deeply effective.",
        "Done is not the enemy of great. It is great's project manager.",
        "Read twice, mark once. Very professional. Suspiciously wise.",
        "Momentum loves a modest checklist and a good export.",
        "Today's masterpiece may be tomorrow's attachment. Keep going."
    ]
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
        .help("Foldy — your Orifold buddy")
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
            if let icon = NSApp.applicationIconImage {
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
                Label("Shush for now", systemImage: "speaker.slash")
            }

            Button {
                buddy.disable()
                isPresented = false
            } label: {
                Label("Hide Foldy", systemImage: "eye.slash")
            }

            if let feedbackURL {
                Link(destination: feedbackURL) {
                    Label("Send Feedback", systemImage: "paperplane")
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
                Text("Foldy is here to help")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.dsTextPrimary)
                Text("Start with Choose Files. Once a document is open, I will keep tips brief and stay out of the way.")
                    .font(.dsCaption())
                    .foregroundStyle(Color.dsTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.bottom, .dsXS)
    }
}
