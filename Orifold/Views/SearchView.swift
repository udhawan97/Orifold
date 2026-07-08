import SwiftUI
import PDFKit
import AppKit

struct SearchView: View {
    @Bindable var viewModel: WorkspaceViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var fieldFocused: Bool
    @State private var isConfirmingReplaceAll = false
    @State private var replaceResultMessage: String?
    @State private var replaceResultWasSkipped = false
    // Passed into L10n.string()/L10n.format() below so this view's `body`
    // actually reads it — SwiftUI only re-invokes `body` on a locale change
    // for views that read `\.locale` during the previous evaluation.
    @Environment(\.locale) private var locale

    private enum Layout {
        static let width: CGFloat = 460
        static let resultAreaHeight: CGFloat = 300
        static let rowMinHeight: CGFloat = 54
    }

    private var resultLabel: String {
        let n = viewModel.searchResults.count
        if n == 0 { return "" }
        let i = viewModel.searchResultIndex
        if i >= 0 { return L10n.format("search.results.position", i + 1, n, locale: locale) }
        return L10n.format(n == 1 ? "search.results.count.one" : "search.results.count.other", n, locale: locale)
    }

    private var shouldReduceMotion: Bool {
        reduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private var replaceMatchCount: Int { viewModel.bodyReplaceMatchCount + viewModel.replaceableCommentMatches.count }

    private var replaceStatusLabel: String {
        guard !viewModel.searchQuery.isEmpty else { return L10n.string("search.replace.emptyQuery", locale: locale) }
        if replaceMatchCount == 0 { return L10n.string("search.replace.noMatches", locale: locale) }
        return L10n.format(replaceMatchCount == 1 ? "search.replace.matches.one" : "search.replace.matches.other", replaceMatchCount, locale: locale)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack(spacing: .dsSM) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Color.dsTextTertiary)
                    .font(.system(size: 13))

                TextField(L10n.string("search.placeholder"), text: $viewModel.searchQuery)
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
                .help(L10n.string("search.replace.disclosure.help"))
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
                        Text(L10n.string("search.noResults"))
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

                TextField(L10n.string("search.replace.placeholder"), text: $viewModel.replaceText)
                    .textFieldStyle(.plain)
                    .font(.dsBody())
                    .onChange(of: viewModel.replaceText) { _, _ in replaceResultMessage = nil }

                Button(L10n.string("search.replace.one.button")) {
                    replaceCurrentMatch()
                }
                .buttonStyle(.bordered)
                .font(.dsCaption())
                .help(L10n.string("search.replace.one.help"))
                .disabled(!viewModel.canReplaceCurrentMatch)

                Button(L10n.string("search.replace.all.button")) {
                    isConfirmingReplaceAll = true
                }
                .buttonStyle(.bordered)
                .font(.dsCaption())
                .disabled(replaceMatchCount == 0)
            }

            if let replaceResultMessage {
                Text(replaceResultMessage)
                    .font(.dsCaption())
                    .foregroundStyle(replaceResultWasSkipped ? Color.dsWarningAccent : Color.dsSuccessAccent)
            } else {
                Text(replaceStatusLabel)
                    .font(.dsCaption())
                    .foregroundStyle(Color.dsTextTertiary)
            }
        }
        .padding(.horizontal, .dsMD)
        .padding(.vertical, .dsSM)
        .confirmationDialog(
            L10n.string("search.replace.confirm.title"),
            isPresented: $isConfirmingReplaceAll,
            titleVisibility: .visible
        ) {
            Button(L10n.string("search.replace.confirm.replace")) {
                performReplaceAll()
            }
            Button(L10n.string("search.replace.confirm.cancel"), role: .cancel) {}
        } message: {
            let count = replaceMatchCount
            if count == 1 {
                Text(L10n.format("search.replace.confirm.message.one", viewModel.replaceText, locale: locale))
            } else {
                Text(L10n.format("search.replace.confirm.message.other", count, viewModel.replaceText, locale: locale))
            }
        }
    }

    private func replaceCurrentMatch() {
        let didReplace = viewModel.replaceCurrentMatch()
        replaceResultWasSkipped = !didReplace
        replaceResultMessage = didReplace
            ? L10n.format("search.replace.result.one", viewModel.searchQuery, viewModel.replaceText, locale: locale)
            : L10n.string("search.replace.skippedEmpty", locale: locale)
    }

    private func performReplaceAll() {
        let (replaced, skipped) = viewModel.replaceAllMatches()
        replaceResultWasSkipped = false
        guard replaced > 0 else {
            replaceResultMessage = L10n.format("search.replace.all.result.zero", viewModel.searchQuery, locale: locale)
            return
        }
        var message = replaced == 1
            ? L10n.format("search.replace.all.result.one", viewModel.searchQuery, viewModel.replaceText, locale: locale)
            : L10n.format("search.replace.all.result.other", replaced, viewModel.searchQuery, viewModel.replaceText, locale: locale)
        if skipped > 0 {
            message += skipped == 1
                ? L10n.format("search.replace.all.result.skippedSuffix.one", skipped, locale: locale)
                : L10n.format("search.replace.all.result.skippedSuffix.other", skipped, locale: locale)
            replaceResultWasSkipped = true
        }
        replaceResultMessage = message
    }
}

struct SearchResultRow: View {
    var result: PDFSelection
    var isActive: Bool
    // Passed into L10n.format() below so this view's `body` actually reads it —
    // SwiftUI only re-invokes `body` on a locale change for views that read
    // `\.locale` during the previous evaluation.
    @Environment(\.locale) private var locale

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
            Text(L10n.format("search.pageLabel", pageLabel, locale: locale))
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
    static let orifoldShowShortcuts   = Notification.Name("orifoldShowShortcuts")
    static let orifoldToggleReaderMode = Notification.Name("orifoldToggleReaderMode")
    static let orifoldToggleTableOfContents = Notification.Name("orifoldToggleTableOfContents")
}
