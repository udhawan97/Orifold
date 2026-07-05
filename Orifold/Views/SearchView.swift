import SwiftUI
import PDFKit
import AppKit

struct SearchView: View {
    @Bindable var viewModel: WorkspaceViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var fieldFocused: Bool

    private enum Layout {
        static let width: CGFloat = 460
        static let resultAreaHeight: CGFloat = 300
        static let rowMinHeight: CGFloat = 54
    }

    private var resultLabel: String {
        let n = viewModel.searchResults.count
        if n == 0 { return "" }
        let i = viewModel.searchResultIndex
        if i >= 0 { return "\(i + 1) of \(n)" }
        return "\(n) result\(n == 1 ? "" : "s")"
    }

    private var shouldReduceMotion: Bool {
        reduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
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
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.dsTextTertiary)
                }
            }
            .padding(.horizontal, .dsMD)
            .padding(.vertical, .dsMD)

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
            Text("Page \(pageLabel)")
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
