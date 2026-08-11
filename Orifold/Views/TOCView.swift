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
    /// `isExpanded(_:)`, so no `onAppear` seeding is needed and a file the user has
    /// never touched always opens in a known state.
    ///
    /// Verified against the running app: because `ContentView` retains this view across
    /// presentations of the popover, these toggles survive closing and reopening it —
    /// the reader keeps their place instead of re-expanding the same chapter each time.
    /// Do not "fix" this by seeding the dictionary on appear.
    @State private var expansionOverrides: [String: Bool] = [:]

    /// Edit mode: rows grow reorder/indent/delete controls and the footer offers
    /// add/revert. Entering it seeds the workspace outline override.
    @State private var isEditing = false
    @State private var renamingNodeID: UUID?
    @State private var renameDraft = ""

    private static let fileRowHeight: CGFloat = 54
    private static let bookmarkRowHeight: CGFloat = 30
    private static let noticeRowHeight: CGFloat = 34
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

    /// True when any file's bookmarks hit the reader's emit caps — the list is real but
    /// incomplete, which is indistinguishable from lost bookmarks unless we say so.
    private var isTruncated: Bool {
        entries.contains { $0.outlineWasTruncated }
    }

    private var popoverHeight: CGFloat {
        let chromeHeight: CGFloat = 53
        let contentHeight = visibleEntries.reduce(0) { $0 + rowHeight(for: $1) }
            + (isTruncated ? Self.noticeRowHeight : 0)
            + (isEditing ? 76 : 0)  // footer: add + revert rows
        return min(max(contentHeight + chromeHeight, 120), 480)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(L10n.string("toc.title", locale: locale))
                    .font(.system(size: 15, weight: .semibold, design: .serif))
                    .foregroundStyle(Color.dsTextPrimary)
                Spacer()
                if viewModel.pageCount > 0 {
                    Button(isEditing
                        ? L10n.string("toc.doneEditing", locale: locale)
                        : L10n.string("toc.edit", locale: locale)) {
                        if !isEditing { viewModel.beginOutlineEditing() }
                        isEditing.toggle()
                        renamingNodeID = nil
                    }
                    .buttonStyle(.plain)
                    .font(.dsCaption())
                    .foregroundStyle(Color.dsAccent)
                }
            }
            .padding(.horizontal, .dsLG)
            .padding(.top, .dsMD)
            .padding(.bottom, .dsSM)

            Rectangle().fill(Color.dsSeparator).frame(height: 0.5)

            if entries.isEmpty && !isEditing {
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
                            } else if isEditing, let nodeID = entry.outlineNodeID {
                                editableBookmarkRow(entry, nodeID: nodeID)
                            } else {
                                bookmarkRow(entry)
                            }
                        }
                        if isTruncated { truncationNotice }
                    }
                }
                .background(Color.dsSurface)
            }
            if isEditing { editingFooter }
        }
        .frame(width: isEditing ? 420 : 340, height: popoverHeight)
        .background(Color.dsSurface)
    }

    // MARK: - Editing

    private var editingFooter: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(Color.dsSeparator).frame(height: 0.5)
            Button {
                guard let ref = viewModel.bookmarkTargetRef else { return }
                viewModel.addBookmark(
                    title: L10n.string("toc.newBookmark.defaultTitle", locale: locale),
                    at: ref
                )
            } label: {
                Label(L10n.string("toc.addBookmark", locale: locale), systemImage: "plus")
                    .font(.dsCaption())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.dsAccent)
            .padding(.horizontal, .dsLG)
            .padding(.vertical, .dsSM)
            .disabled(viewModel.bookmarkTargetRef == nil)
            Button {
                viewModel.clearOutlineOverride()
                isEditing = false
                renamingNodeID = nil
            } label: {
                Label(L10n.string("toc.revertOutline", locale: locale), systemImage: "arrow.uturn.backward")
                    .font(.dsCaption())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.dsTextSecondary)
            .padding(.horizontal, .dsLG)
            .padding(.bottom, .dsSM)
        }
    }

    private func editableBookmarkRow(_ entry: WorkspaceViewModel.TOCEntry, nodeID: UUID) -> some View {
        OutlineEditRow(
            viewModel: viewModel,
            entry: entry,
            nodeID: nodeID,
            indent: .dsLG + CGFloat(entry.depth - 1) * Self.indentPerLevel,
            height: Self.bookmarkRowHeight,
            renamingNodeID: $renamingNodeID,
            renameDraft: $renameDraft
        )
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

    /// Last row, styled below a bookmark row rather than as an alert: nothing is wrong,
    /// there is simply more outline than the list shows.
    private var truncationNotice: some View {
        Text(L10n.string("toc.truncated", locale: locale))
            .font(.dsCaption())
            .foregroundStyle(Color.dsTextTertiary)
            .lineLimit(2)
            .padding(.horizontal, .dsLG)
            .frame(maxWidth: .infinity, minHeight: Self.noticeRowHeight, alignment: .leading)
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
    // (disclosure below; the edit-mode row lives in `OutlineEditRow` at file scope, which
    // also keeps TOCView inside SwiftLint's type-body budget.)
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

/// One bookmark row in the TOC's edit mode: inline rename plus reorder / indent / delete
/// controls, all routed straight to the view model's outline operations.
private struct OutlineEditRow: View {
    var viewModel: WorkspaceViewModel
    let entry: WorkspaceViewModel.TOCEntry
    let nodeID: UUID
    let indent: CGFloat
    let height: CGFloat
    @Binding var renamingNodeID: UUID?
    @Binding var renameDraft: String
    @Environment(\.locale) private var locale

    var body: some View {
        HStack(spacing: .dsSM) {
            if renamingNodeID == nodeID {
                TextField("", text: $renameDraft)
                    .textFieldStyle(.roundedBorder)
                    .font(.dsCaption())
                    .onSubmit {
                        let trimmed = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty { viewModel.renameBookmark(nodeID, to: trimmed) }
                        renamingNodeID = nil
                    }
            } else {
                Text(entry.title)
                    .font(.dsCaption())
                    .foregroundStyle(Color.dsTextPrimary)
                    .lineLimit(1)
            }
            Spacer(minLength: .dsSM)
            control("pencil", help: "toc.rename") {
                renameDraft = entry.title
                renamingNodeID = nodeID
            }
            control("arrow.up", help: "toc.moveUp") { viewModel.moveBookmark(nodeID, up: true) }
            control("arrow.down", help: "toc.moveDown") { viewModel.moveBookmark(nodeID, up: false) }
            control("decrease.indent", help: "toc.outdent") {
                viewModel.setBookmarkDepth(nodeID, depth: entry.depth - 2)
            }
            control("increase.indent", help: "toc.indent") {
                viewModel.setBookmarkDepth(nodeID, depth: entry.depth)
            }
            control("trash", help: "toc.delete") { viewModel.deleteBookmark(nodeID) }
        }
        .padding(.leading, indent)
        .padding(.trailing, .dsLG)
        .frame(height: height)
    }

    private func control(_ systemImage: String, help key: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.dsTextSecondary)
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(L10n.string(forKey: key, locale: locale))
        .accessibilityLabel(L10n.string(forKey: key, locale: locale))
    }
}
