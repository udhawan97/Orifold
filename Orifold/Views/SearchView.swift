import SwiftUI
import PDFKit
import AppKit

struct SearchView: View {
    @Bindable var viewModel: WorkspaceViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var fieldFocused: Bool
    @State private var isConfirmingReplaceAll = false
    @State private var replaceResultMessage: String?

    private enum Layout {
        static let width: CGFloat = 460
        static let resultAreaHeight: CGFloat = 300
        static let rowMinHeight: CGFloat = 54
    }

    private var resultLabel: String {
        let n = viewModel.searchResults.count
        if n == 0 { return "" }
        let i = viewModel.searchResultIndex
        if i >= 0 { return L10n.format("search.results.position", i + 1, n) }
        return L10n.format(n == 1 ? "search.results.count.one" : "search.results.count.other", n)
    }

    private var shouldReduceMotion: Bool {
        reduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private var replaceMatchCount: Int { viewModel.replaceableCommentMatches.count }

    private var replaceStatusLabel: String {
        guard !viewModel.searchQuery.isEmpty else { return "" }
        if replaceMatchCount == 0 { return L10n.string("search.replace.noMatches") }
        return L10n.format(replaceMatchCount == 1 ? "search.replace.matches.one" : "search.replace.matches.other", replaceMatchCount)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack(spacing: .dsSM) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Color.dsTextTertiary)
                    .font(.system(size: 13))

                TextField("search.placeholder", text: $viewModel.searchQuery)
                    .textFieldStyle(.plain)
                    .font(.dsBody())
                    .focused($fieldFocused)
                    .onSubmit { viewModel.commitSearch() }
                    .onChange(of: viewModel.searchQuery) { _, q in
                        viewModel.scheduleSearch(query: q)
                        replaceResultMessage = nil
                    }

                if !viewModel.searchQuery.isEmpty {
                    Text(resultLabel)
                        .font(.dsCaption())
                        .foregroundStyle(Color.dsTextTertiary)
                        .contentTransition(shouldReduceMotion ? .identity : .numericText())
                        .animation(shouldReduceMotion ? nil : .easeInOut(duration: 0.16), value: resultLabel)

                    Divider().frame(height: 14)

                    Button { viewModel.searchPrevious() } label: {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.dsTextSecondary)
                    .disabled(viewModel.searchResults.isEmpty)

                    Button { viewModel.searchNext() } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.dsTextSecondary)
                    .disabled(viewModel.searchResults.isEmpty)

                    Button {
                        viewModel.searchQuery = ""
                        viewModel.searchResults = []
                        viewModel.searchResultIndex = -1
                        replaceResultMessage = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.dsTextTertiary)
                }

                Divider().frame(height: 14)

                Button {
                    withAnimation(shouldReduceMotion ? nil : .easeOut(duration: 0.15)) {
                        viewModel.isReplaceRevealed.toggle()
                    }
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(viewModel.isReplaceRevealed ? Color.dsAccent : Color.dsTextSecondary)
                .help("search.replace.disclosure.help")
            }
            .padding(.horizontal, .dsMD)
            .padding(.vertical, .dsMD)

            if viewModel.isReplaceRevealed {
                Rectangle().fill(Color.dsSeparator).frame(height: 0.5)
                replaceRow
            }

            Rectangle().fill(Color.dsSeparator).frame(height: 0.5)

            Group {
                if viewModel.searchResults.isEmpty && !viewModel.searchQuery.isEmpty {
                    VStack(spacing: .dsSM) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(Color.dsTextTertiary)
                        Text("search.noResults")
                            .font(.dsBody())
                            .foregroundStyle(Color.dsTextSecondary)
                    }
                    .padding(.dsXL)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if !viewModel.searchResults.isEmpty {
                    let rows = Array(viewModel.searchResults.enumerated())
                    List(rows, id: \.offset) { i, result in
                        SearchResultRow(
                            result: result,
                            isActive: i == viewModel.searchResultIndex
                        )
                        .frame(minHeight: Layout.rowMinHeight, alignment: .leading)
                        .listRowBackground(
                            i == viewModel.searchResultIndex ? Color.dsAccentSoft : Color.clear
                        )
                        .onTapGesture {
                            guard viewModel.searchResults.indices.contains(i) else { return }
                            viewModel.searchResultIndex = i
                            NotificationCenter.default.post(
                                name: .orifoldJumpToSelection,
                                object: result
                            )
                        }
                    }
                    .listStyle(.plain)
                } else {
                    Spacer(minLength: 0)
                }
            }
            .frame(height: Layout.resultAreaHeight)
        }
        .frame(width: Layout.width)
        .background(Color.dsSurface)
        .onAppear { fieldFocused = true }
    }

    private var replaceRow: some View {
        VStack(alignment: .leading, spacing: .dsSM) {
            HStack(spacing: .dsSM) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundStyle(Color.dsTextTertiary)
                    .font(.system(size: 13))

                TextField("search.replace.placeholder", text: $viewModel.replaceText)
                    .textFieldStyle(.plain)
                    .font(.dsBody())
                    .onChange(of: viewModel.replaceText) { _, _ in replaceResultMessage = nil }

                Button("search.replace.one.button") {
                    replaceCurrentMatch()
                }
                .buttonStyle(.bordered)
                .font(.dsCaption())
                .help("search.replace.one.help")
                .disabled(!canReplaceCurrentMatch)

                Button("search.replace.all.button") {
                    isConfirmingReplaceAll = true
                }
                .buttonStyle(.bordered)
                .font(.dsCaption())
                .disabled(replaceMatchCount == 0)
            }

            if let replaceResultMessage {
                Text(replaceResultMessage)
                    .font(.dsCaption())
                    .foregroundStyle(Color.dsSuccessAccent)
            } else if !viewModel.searchQuery.isEmpty {
                Text(replaceStatusLabel)
                    .font(.dsCaption())
                    .foregroundStyle(Color.dsTextTertiary)
            }

            Text("search.replace.locked.notice")
                .font(.dsCaption())
                .foregroundStyle(Color.dsTextTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, .dsMD)
        .padding(.vertical, .dsSM)
        .confirmationDialog(
            "search.replace.confirm.title",
            isPresented: $isConfirmingReplaceAll,
            titleVisibility: .visible
        ) {
            Button("search.replace.confirm.replace") {
                let count = viewModel.replaceAllCommentMatches()
                replaceResultMessage = L10n.format(count == 1 ? "search.replace.result.one" : "search.replace.result.other", count)
            }
            Button("search.replace.confirm.cancel", role: .cancel) {}
        } message: {
            let count = replaceMatchCount
            if count == 1 {
                Text(L10n.format("search.replace.confirm.message.one", viewModel.replaceText))
            } else {
                Text(L10n.format("search.replace.confirm.message.other", count, viewModel.replaceText))
            }
        }
    }

    /// The active search result row must actually be one of the currently editable comment
    /// matches — not a PDF-page-text match — before the single "Replace" button can act.
    private var canReplaceCurrentMatch: Bool {
        guard !viewModel.searchQuery.isEmpty, !viewModel.replaceableCommentMatches.isEmpty else { return false }
        return true
    }

    private func replaceCurrentMatch() {
        guard let comment = viewModel.replaceableCommentMatches.first else { return }
        viewModel.replaceMatches(in: comment)
        replaceResultMessage = L10n.string("search.replace.result.one")
    }
}

struct SearchResultRow: View {
    var result: PDFSelection
    var isActive: Bool

    private var pageLabel: String {
        result.pages.first.flatMap { $0.label } ?? "?"
    }
    private var snippet: String {
        result.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(snippet)
                .font(.dsBody())
                .foregroundStyle(isActive ? Color.dsAccent : Color.dsTextPrimary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(L10n.format("search.pageLabel", pageLabel))
                .font(.dsCaption())
                .foregroundStyle(Color.dsTextTertiary)
        }
        .padding(.vertical, .dsXS)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension Notification.Name {
    static let orifoldJumpToSelection = Notification.Name("orifoldJumpToSelection")
    static let orifoldJumpToPageIndex = Notification.Name("orifoldJumpToPageIndex")
    static let orifoldJumpToFormField = Notification.Name("orifoldJumpToFormField")
    static let orifoldJumpToAnnotation = Notification.Name("orifoldJumpToAnnotation")
    static let orifoldEditAnnotation   = Notification.Name("orifoldEditAnnotation")
    static let orifoldPrint           = Notification.Name("orifoldPrint")
    static let orifoldCreateCommentFromSelection = Notification.Name("orifoldCreateCommentFromSelection")
    static let orifoldZoomIn          = Notification.Name("orifoldZoomIn")
    static let orifoldZoomOut         = Notification.Name("orifoldZoomOut")
    static let orifoldZoomFit         = Notification.Name("orifoldZoomFit")
}
