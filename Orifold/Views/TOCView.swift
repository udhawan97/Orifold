import SwiftUI
import PDFKit

struct TOCView: View {
    var viewModel: WorkspaceViewModel
    var onJump: ((Int) -> Void)?
    // Passed into L10n.format() below so this view's `body` actually reads it —
    // SwiftUI only re-invokes `body` on a locale change for views that read
    // `\.locale` during the previous evaluation.
    @Environment(\.locale) private var locale

    /// Explicit user toggles only. Anything absent falls back to the default rule in
    /// `isExpanded(_:)`, so no `onAppear` seeding is needed and the popover opens in a
    /// known state every time. The popover dismisses on jump, so resetting expansion
    /// between openings is the intended behaviour rather than lost state.
    @State private var expansionOverrides: [String: Bool] = [:]

    private static let fileRowHeight: CGFloat = 54
    private static let bookmarkRowHeight: CGFloat = 30
    private static let indentPerLevel: CGFloat = 14

    private var entries: [WorkspaceViewModel.TOCEntry] {
        viewModel.tableOfContents
    }

    /// A source file starts expanded so its chapters are immediately visible; deeper
    /// bookmark levels start collapsed so a long manual stays scannable.
    private func isExpanded(_ entry: WorkspaceViewModel.TOCEntry) -> Bool {
        expansionOverrides[entry.id] ?? (entry.depth == 0)
    }

    private var visibleEntries: [WorkspaceViewModel.TOCEntry] {
        WorkspaceViewModel.TOCEntry.visibleEntries(in: entries, isExpanded: isExpanded)
    }

    private func rowHeight(for entry: WorkspaceViewModel.TOCEntry) -> CGFloat {
        entry.depth == 0 ? Self.fileRowHeight : Self.bookmarkRowHeight
    }

    private var popoverHeight: CGFloat {
        let chromeHeight: CGFloat = 53
        let contentHeight = visibleEntries.reduce(0) { $0 + rowHeight(for: $1) }
        return min(max(contentHeight + chromeHeight, 120), 480)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L10n.string("toc.title", locale: locale))
                .font(.system(size: 15, weight: .semibold, design: .serif))
                .foregroundStyle(Color.dsTextPrimary)
                .padding(.horizontal, .dsLG)
                .padding(.top, .dsMD)
                .padding(.bottom, .dsSM)

            Rectangle().fill(Color.dsSeparator).frame(height: 0.5)

            if entries.isEmpty {
                Text(L10n.string("toc.empty", locale: locale))
                    .font(.dsBody())
                    .foregroundStyle(Color.dsTextSecondary)
                    .padding(.dsLG)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(visibleEntries) { entry in
                            if entry.depth == 0 {
                                fileRow(entry)
                            } else {
                                bookmarkRow(entry)
                            }
                        }
                    }
                }
                .background(Color.dsSurface)
            }
        }
        .frame(width: 340, height: popoverHeight)
        .background(Color.dsSurface)
    }

    // MARK: - Rows

    private func fileRow(_ entry: WorkspaceViewModel.TOCEntry) -> some View {
        HStack(spacing: .dsSM) {
            disclosure(for: entry)
            Button {
                onJump?(entry.jumpPageIndex)
            } label: {
                HStack(spacing: .dsSM) {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.dsAccent)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.title)
                            .font(.dsBody())
                            .foregroundStyle(Color.dsTextPrimary)
                            .lineLimit(1)
                        Text(L10n.format("toc.pageLabel", entry.displayPageNumber, locale: locale))
                            .font(.dsCaption())
                            .foregroundStyle(Color.dsTextTertiary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.dsTextTertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, .dsLG)
        .frame(height: Self.fileRowHeight)
    }

    private func bookmarkRow(_ entry: WorkspaceViewModel.TOCEntry) -> some View {
        HStack(spacing: .dsSM) {
            disclosure(for: entry)
            Button {
                onJump?(entry.jumpPageIndex)
            } label: {
                HStack(spacing: .dsSM) {
                    Text(entry.title)
                        .font(.dsCaption())
                        .foregroundStyle(Color.dsTextPrimary)
                        .lineLimit(1)
                    Spacer(minLength: .dsSM)
                    Text("\(entry.displayPageNumber)")
                        .font(.dsCaption())
                        .foregroundStyle(Color.dsTextTertiary)
                        .monospacedDigit()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        // Depth 1 aligns under the file row's title; each further level steps in.
        .padding(.leading, .dsLG + CGFloat(entry.depth - 1) * Self.indentPerLevel)
        .padding(.trailing, .dsLG)
        .frame(height: Self.bookmarkRowHeight)
    }

    /// Fixed-width slot whether or not the row has children, so titles at the same depth
    /// line up regardless of which rows happen to be expandable.
    @ViewBuilder
    private func disclosure(for entry: WorkspaceViewModel.TOCEntry) -> some View {
        if entry.hasChildren {
            let expanded = isExpanded(entry)
            Button {
                expansionOverrides[entry.id] = !expanded
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.dsTextSecondary)
                    .rotationEffect(.degrees(expanded ? 90 : 0))
                    .frame(width: 12, height: 12)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(expanded
                ? L10n.string("toc.collapse", locale: locale)
                : L10n.string("toc.expand", locale: locale))
        } else {
            Color.clear.frame(width: 12, height: 12)
        }
    }
}
