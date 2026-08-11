import SwiftUI

/// Rule picker for "Split into Files": every N pages, explicit ranges, or top-level
/// bookmarks. The sheet dismisses itself first and hands the chosen rule to the view
/// model on the next runloop tick, so the folder panel never presents on top of it.
struct SplitExportSheet: View {
    @Bindable var viewModel: WorkspaceViewModel
    @Environment(\.locale) private var locale

    private enum Mode: String, CaseIterable, Identifiable {
        case everyN
        case ranges
        case bookmarks

        var id: String { rawValue }

        var titleKey: String {
            switch self {
            case .everyN: return "split.mode.everyN"
            case .ranges: return "split.mode.ranges"
            case .bookmarks: return "split.mode.bookmarks"
            }
        }
    }

    @State private var mode: Mode = .everyN
    @State private var pagesPerFile = 1
    @State private var rangesText = ""
    @State private var showsRangeError = false

    private var bookmarkBoundaries: [PDFSplitPlanner.Boundary] {
        viewModel.topLevelBookmarkBoundaries()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.string("split.sheet.title", locale: locale))
                .font(.headline)

            Picker(L10n.string("split.sheet.title", locale: locale), selection: $mode) {
                ForEach(Mode.allCases) { mode in
                    Text(L10n.string(forKey: mode.titleKey, locale: locale)).tag(mode)
                }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()

            switch mode {
            case .everyN:
                Stepper(value: $pagesPerFile, in: 1...max(viewModel.pageCount, 1)) {
                    Text("\(L10n.string("split.everyN.label", locale: locale)): \(pagesPerFile)")
                }
            case .ranges:
                VStack(alignment: .leading, spacing: 4) {
                    TextField(
                        L10n.string("split.ranges.placeholder", locale: locale),
                        text: $rangesText
                    )
                    .textFieldStyle(.roundedBorder)
                    if showsRangeError {
                        Text(L10n.string("split.ranges.invalid", locale: locale))
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            case .bookmarks:
                if bookmarkBoundaries.isEmpty {
                    Text(L10n.string("split.bookmarks.none", locale: locale))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Spacer()
                Button(L10n.string("contentView.exportSheet.cancel.button", locale: locale)) {
                    viewModel.isShowingSplitExport = false
                }
                .keyboardShortcut(.cancelAction)
                Button(L10n.string("split.action", locale: locale)) {
                    performSplit()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(mode == .bookmarks && bookmarkBoundaries.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
    }

    private func performSplit() {
        let rule: PDFSplitPlanner.Rule
        switch mode {
        case .everyN:
            rule = .everyN(pagesPerFile)
        case .ranges:
            guard let ranges = PDFSplitPlanner.parseRanges(rangesText, totalPages: viewModel.pageCount) else {
                showsRangeError = true
                return
            }
            rule = .ranges(ranges)
        case .bookmarks:
            rule = .bookmarks(bookmarkBoundaries)
        }
        viewModel.isShowingSplitExport = false
        // Same runloop-hop rule as the More menu: let this sheet tear down before the
        // folder panel presents.
        DispatchQueue.main.async {
            viewModel.splitExport(rule: rule)
        }
    }
}
