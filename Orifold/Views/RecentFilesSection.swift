import SwiftUI
import AppKit

/// "Recently viewed" row on the empty-state screen. Renders nothing when there
/// are no recents — the first-run screen is unchanged. See the design plan for
/// placement/behavior rationale.
struct RecentFilesSection: View {
    var store: RecentsStore
    var onOpen: (RecentFileEntry) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // Passed into L10n.string()/L10n.format() below so this view's `body`
    // actually reads it — SwiftUI only re-invokes `body` on a locale change
    // for views that read `\.locale` during the previous evaluation.
    @Environment(\.locale) private var locale
    @State private var isExpanded = false
    @State private var hasAppeared = false

    private var shouldReduceMotion: Bool {
        reduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private var visibleEntries: [RecentFileEntry] {
        isExpanded ? store.entries : Array(store.entries.prefix(RecentsStore.defaultVisibleCount))
    }

    private var hasOverflow: Bool { store.entries.count > RecentsStore.defaultVisibleCount }

    var body: some View {
        if !store.entries.isEmpty {
            VStack(alignment: .leading, spacing: .dsMD) {
                header

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: .dsMD) {
                        cards
                    }
                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: .dsMD), GridItem(.flexible(), spacing: .dsMD)],
                        alignment: .leading,
                        spacing: .dsMD
                    ) {
                        cards
                    }
                }
                .accessibilityElement(children: .contain)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(hasAppeared || shouldReduceMotion ? 1 : 0)
            .offset(y: hasAppeared || shouldReduceMotion ? 0 : 8)
            .onAppear {
                guard !hasAppeared else { return }
                if shouldReduceMotion {
                    hasAppeared = true
                } else {
                    withAnimation(.spring(response: 0.46, dampingFraction: 0.82).delay(0.15)) {
                        hasAppeared = true
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack {
            Text(L10n.string("recentFiles.header"))
                .font(.system(size: 11, weight: .semibold))
                .tracking(.dsLabelTracking)
                .textCase(.uppercase)
                .foregroundStyle(Color.dsTextTertiary)

            Spacer()

            if hasOverflow {
                Button {
                    withAnimation(shouldReduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.85)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Text(isExpanded ? L10n.string("recentFiles.showLess", locale: locale) : L10n.format("recentFiles.showAll", store.entries.count, locale: locale))
                        .font(.dsCaption())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.dsTextTertiary)
            }

            Button {
                store.clear()
            } label: {
                Text(L10n.string("recentFiles.clear"))
                    .font(.dsCaption())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.dsTextTertiary)
        }
    }

    @ViewBuilder
    private var cards: some View {
        ForEach(Array(visibleEntries.enumerated()), id: \.element.id) { index, entry in
            RecentFileCard(
                entry: entry,
                store: store,
                isMostRecent: index == 0 && !isExpanded,
                onOpen: onOpen
            )
        }
    }
}

private struct RecentFileCard: View {
    var entry: RecentFileEntry
    var store: RecentsStore
    var isMostRecent: Bool
    var onOpen: (RecentFileEntry) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // Passed into L10n.string()/L10n.format() below so this view's `body`
    // actually reads it — SwiftUI only re-invokes `body` on a locale change
    // for views that read `\.locale` during the previous evaluation.
    @Environment(\.locale) private var locale
    @State private var thumbnail: NSImage?
    @State private var isHovered = false
    @State private var isAvailable = true

    private static let thumbnailSize = CGSize(width: 140, height: 187)

    private var shouldReduceMotion: Bool {
        reduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private var relativeTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.locale = locale
        return formatter.localizedString(for: entry.lastOpened, relativeTo: Date())
    }

    private var metadataLine: String {
        guard isAvailable else { return L10n.string("recentFiles.notFound", locale: locale) }
        if let count = entry.pageCount, count > 0 {
            let pageLabel = count == 1
                ? L10n.string("recentFiles.pageCount.singular", locale: locale)
                : L10n.format("recentFiles.pageCount.plural", count, locale: locale)
            return "\(relativeTime) · \(pageLabel)"
        }
        return relativeTime
    }

    private var resumeLabel: String? {
        guard isAvailable else { return nil }
        if let page = entry.lastPageOpened {
            return L10n.format("recentFiles.resumeAtPage", page + 1, locale: locale)
        }
        return L10n.string("recentFiles.open", locale: locale)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            thumbnailArea
            textBlock
        }
        .frame(width: Self.thumbnailSize.width)
        .background(Color.dsCard, in: RoundedRectangle(cornerRadius: .dsRadiusMd, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: .dsRadiusMd, style: .continuous)
                .strokeBorder(borderColor, lineWidth: isMostRecent ? 1 : (isHovered ? 0.9 : 1))
        }
        .clipShape(RoundedRectangle(cornerRadius: .dsRadiusMd, style: .continuous))
        .shadow(color: .black.opacity(isHovered ? 0.10 : 0), radius: 14, x: 0, y: 6)
        .scaleEffect(isHovered && !shouldReduceMotion ? 1.02 : 1)
        .opacity(isAvailable ? 1 : 0.55)
        .onHover { hovering in
            if shouldReduceMotion {
                isHovered = hovering
            } else {
                withAnimation(.easeOut(duration: 0.14)) { isHovered = hovering }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { open() }
        .contextMenu { menuItems }
        .task(id: entry.thumbnailCacheKey) {
            thumbnail = store.thumbnailImage(for: entry)
        }
        .onAppear {
            isAvailable = store.isAvailable(entry)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(L10n.string("recentFiles.card.accessibilityHint"))
        .accessibilityAddTraits(.isButton)
    }

    private var borderColor: Color {
        if isMostRecent { return Color.dsAccent.opacity(isHovered ? 0.55 : 0.35) }
        return Color.dsSeparator.opacity(isHovered ? 0.9 : 0.6)
    }

    private var accessibilityLabel: String {
        var parts = [entry.displayName, metadataLine]
        if !isAvailable { parts.append(L10n.string("recentFiles.notFound", locale: locale)) }
        return parts.joined(separator: ", ")
    }

    @ViewBuilder
    private var thumbnailArea: some View {
        ZStack {
            Rectangle().fill(Color.dsSurface)

            if let thumbnail, isAvailable {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                thumbnailFallback
            }
        }
        .aspectRatio(3.0 / 4.0, contentMode: .fill)
        .frame(width: Self.thumbnailSize.width, height: Self.thumbnailSize.height)
        .clipped()
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.dsSeparator).frame(height: 0.5)
        }
        .overlay(alignment: .bottomLeading) {
            if let resumeLabel, isMostRecent || isHovered {
                Text(resumeLabel)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.dsAccent)
                    .padding(.horizontal, .dsSM)
                    .padding(.vertical, 3)
                    .background(Color.dsAccentSoft, in: Capsule())
                    .padding(.dsXS)
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .topTrailing) {
            overflowMenu
                .opacity(isHovered || shouldReduceMotion ? 1 : 0)
                .padding(4)
        }
    }

    @ViewBuilder
    private var thumbnailFallback: some View {
        Image(systemName: isAvailable ? "doc.text" : "questionmark.folder")
            .font(.system(size: 22, weight: .light))
            .foregroundStyle(Color.dsTextTertiary.opacity(0.6))
    }

    private var textBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entry.displayName)
                .font(.dsCaption())
                .fontWeight(.medium)
                .foregroundStyle(Color.dsTextPrimary)
                .lineLimit(1)
                .truncationMode(.middle)

            Text(metadataLine)
                .font(.system(size: 11))
                .foregroundStyle(isAvailable ? Color.dsTextTertiary : Color.dsWarningAccent)
                .lineLimit(1)
        }
        .padding(.dsSM)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var overflowMenu: some View {
        Menu {
            menuItems
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.dsTextPrimary)
                .frame(width: 20, height: 20)
                .background(.regularMaterial, in: Circle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    @ViewBuilder
    private var menuItems: some View {
        Button(L10n.string("recentFiles.menu.open")) { open() }
            .disabled(!isAvailable)
        Button(L10n.string("recentFiles.menu.showInFinder")) { store.revealInFinder(entry) }
            .disabled(!isAvailable)
        Divider()
        Button(L10n.string("recentFiles.menu.remove"), role: .destructive) {
            store.remove(id: entry.id)
        }
    }

    private func open() {
        guard store.resolvedURL(for: entry) != nil else {
            isAvailable = false
            return
        }
        onOpen(entry)
    }
}
