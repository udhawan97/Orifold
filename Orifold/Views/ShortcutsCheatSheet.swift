import SwiftUI

/// A single keycap glyph, styled like a physical Mac key.
private struct KeycapView: View {
    var symbol: String

    var body: some View {
        Text(symbol)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(Color.dsTextPrimary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.dsSurface, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(Color.dsSeparator, lineWidth: 1)
            }
    }
}

/// Renders a shortcut's keycaps in order (e.g. ⌘ ⇧ O), with a combined
/// accessibility label so VoiceOver reads "Command Shift O" instead of glyphs.
private struct ShortcutKeycapsView: View {
    var keycaps: [String]

    private static let spokenNames: [String: String] = [
        "⌘": "Command", "⇧": "Shift", "⌥": "Option", "⌃": "Control",
        "Esc": "Escape", "Return": "Return", "+": "Plus", "−": "Minus",
        "/": "Slash", "Page ↑": "Page Up", "Page ↓": "Page Down"
    ]

    private var accessibilityLabel: String {
        keycaps.map { Self.spokenNames[$0] ?? $0 }.joined(separator: " ")
    }

    var body: some View {
        HStack(spacing: 3) {
            ForEach(keycaps, id: \.self) { KeycapView(symbol: $0) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct ShortcutRow: View {
    var spec: ShortcutSpec
    // Passed into L10n.string() below so this view's `body` actually reads it —
    // SwiftUI only re-invokes `body` on a locale change for views that read
    // `\.locale` during the previous evaluation.
    @Environment(\.locale) private var locale

    var body: some View {
        HStack {
            Text(L10n.string(forKey: spec.labelKey, locale: locale))
                .font(.dsBody())
                .foregroundStyle(Color.dsTextPrimary)
            Spacer(minLength: .dsMD)
            if !spec.keycaps.isEmpty {
                ShortcutKeycapsView(keycaps: spec.keycaps)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ShortcutCategorySection: View {
    var category: ShortcutCategory
    // Passed into L10n.string() below so this view's `body` actually reads it —
    // SwiftUI only re-invokes `body` on a locale change for views that read
    // `\.locale` during the previous evaluation.
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: .dsXS) {
            Text(L10n.string(forKey: category.titleKey, locale: locale))
                .font(.dsCaption())
                .fontWeight(.semibold)
                .tracking(.dsLabelTracking)
                .foregroundStyle(Color.dsTextSecondary)
                .textCase(.uppercase)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(ShortcutRegistry.specs(in: category)) { spec in
                    ShortcutRow(spec: spec)
                }
            }
        }
    }
}

/// The full keyboard-shortcuts cheat sheet: a "Most Useful" summary up top,
/// then every remaining shortcut grouped by category.
struct ShortcutsCheatSheetView: View {
    @Binding var isPresented: Bool
    // Read so `body` re-runs on a live language switch while the sheet is open.
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: .dsLG) {
            HStack {
                Text(L10n.string("shortcuts.cheatSheet.title", locale: locale))
                    .font(.dsTitle())
                    .foregroundStyle(Color.dsTextPrimary)
                Spacer()
            }

            LinearGradient(colors: [.clear, Color.dsSeparator, .clear], startPoint: .leading, endPoint: .trailing)
                .frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: .dsLG) {
                    VStack(alignment: .leading, spacing: .dsXS) {
                        Text(L10n.string("shortcuts.cheatSheet.mostUseful.section", locale: locale))
                            .font(.dsCaption())
                            .fontWeight(.semibold)
                            .tracking(.dsLabelTracking)
                            .foregroundStyle(Color.dsTextSecondary)
                            .textCase(.uppercase)
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(ShortcutRegistry.mostUseful) { spec in
                                ShortcutRow(spec: spec)
                            }
                        }
                    }

                    ForEach(ShortcutCategory.allCases) { category in
                        ShortcutCategorySection(category: category)
                    }
                }
                .padding(.vertical, 1)
            }
            .scrollIndicators(.hidden)
            .frame(maxHeight: 420)

            HStack {
                Link(L10n.string("help.viewDocumentation.button", locale: locale), destination: OrifoldLinks.documentation)
                    .font(.dsCaption())
                    .foregroundStyle(Color.dsTextSecondary)
                Spacer()
                Button(L10n.string("shortcuts.cheatSheet.done.button", locale: locale)) { isPresented = false }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.dsAccent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.dsLG)
        .frame(width: 420)
        .accessibilityElement(children: .contain)
    }
}

/// A one-time, dismissible nudge introducing the shortcuts cheat sheet, shown
/// the first time a workspace opens. Mirrors `GuideButton`'s autoShow pattern.
struct ShortcutsFirstRunPopover: View {
    @Binding var isPresented: Bool
    var onSeeAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: .dsMD) {
            Text(L10n.string("shortcuts.firstRun.title"))
                .font(.dsBody())
                .fontWeight(.semibold)
                .foregroundStyle(Color.dsTextPrimary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: .dsSM) {
                ForEach(["⌘Z", "⌘Y", "⌘F"], id: \.self) { combo in
                    Text(combo)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.dsTextPrimary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.dsSurface, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Color.dsSeparator, lineWidth: 1)
                        }
                }
            }
            .accessibilityHidden(true)

            HStack {
                Button(L10n.string("shortcuts.firstRun.seeAll.button")) {
                    isPresented = false
                    onSeeAll()
                }
                .font(.dsCaption())
                Spacer()
                Button(L10n.string("guidePopover.gotIt.button")) { isPresented = false }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.dsAccent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.dsLG)
        .frame(width: 300)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(L10n.string("shortcuts.firstRun.title")))
    }
}

/// Toolbar entry point for keyboard-shortcut discovery: a persistent keyboard
/// icon that opens the full cheat sheet, plus a one-time first-run popover
/// (shown once per install, dismissible, `Esc`-friendly via the popover's own
/// default dismiss behavior) that points new users at it.
struct ShortcutsCheatSheetButton: View {
    @Binding var isPresented: Bool
    var autoShow = false
    @State private var isShowingFirstRunHint = false
    @AppStorage("Orifold.hasSeenShortcutsHint") private var hasSeenShortcutsHint = false
    // `.popover` content on macOS doesn't inherit the `.environment(\.locale:)`
    // override applied at the scene root — it resets to the system default —
    // so it must be re-applied explicitly to each popover's presented content.
    @Environment(\.locale) private var locale

    var body: some View {
        Button {
            isPresented.toggle()
            hasSeenShortcutsHint = true
        } label: {
            Image(systemName: "keyboard")
        }
        .help(L10n.string("shortcuts.cheatSheet.help"))
        .accessibilityLabel(Text(L10n.string("shortcuts.cheatSheet.title")))
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            ShortcutsCheatSheetView(isPresented: $isPresented)
                .environment(\.locale, locale)
        }
        .popover(isPresented: $isShowingFirstRunHint, arrowEdge: .bottom) {
            ShortcutsFirstRunPopover(isPresented: $isShowingFirstRunHint) {
                isPresented = true
            }
            .environment(\.locale, locale)
        }
        .onAppear {
            guard autoShow, !hasSeenShortcutsHint else { return }
            hasSeenShortcutsHint = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                isShowingFirstRunHint = true
            }
        }
    }
}
