import SwiftUI
import PDFKit

struct SearchView: View {
    @Bindable var viewModel: WorkspaceViewModel
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

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack(spacing: .dsSM) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Color.dsTextTertiary)
                    .font(.system(size: 13))

                TextField("Search workspace…", text: $viewModel.searchQuery)
                    .textFieldStyle(.plain)
                    .font(.dsBody())
                    .focused($fieldFocused)
                    .onSubmit { viewModel.searchNext() }
                    .onChange(of: viewModel.searchQuery) { _, q in
                        if q.isEmpty { viewModel.searchResults = []; viewModel.searchResultIndex = -1 }
                        else { viewModel.search(query: q) }
                    }

                if !viewModel.searchQuery.isEmpty {
                    Text(resultLabel)
                        .font(.dsCaption())
                        .foregroundStyle(Color.dsTextTertiary)
                        .animation(.none, value: resultLabel)

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
                        Text("No results")
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
                                name: .pdfoldJumpToSelection,
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
    static let pdfoldJumpToSelection = Notification.Name("pdfoldJumpToSelection")
    static let pdfoldJumpToPageIndex = Notification.Name("pdfoldJumpToPageIndex")
    static let pdfoldPrint           = Notification.Name("pdfoldPrint")
    static let pdfoldZoomIn          = Notification.Name("pdfoldZoomIn")
    static let pdfoldZoomOut         = Notification.Name("pdfoldZoomOut")
    static let pdfoldZoomFit         = Notification.Name("pdfoldZoomFit")
}
