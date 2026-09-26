import AppKit
import SwiftUI

/// Options for "Fold a Folder…": pick which operations run over every PDF in the chosen
/// folder. The sheet dismisses itself and hands the options to the view model on the next
/// runloop tick, so the folder panel never presents on top of it.
struct BatchFoldSheet: View {
    @Bindable var viewModel: WorkspaceViewModel
    @Environment(\.locale) private var locale

    @State private var compressionEnabled = false
    @State private var compressionPreset: PDFCompressionPreset = .balanced
    @State private var runsOCR = false
    @State private var watermarkEnabled = false
    @State private var watermarkText = ""

    private var options: BatchFoldService.Options {
        BatchFoldService.Options(
            compressionPreset: compressionEnabled ? compressionPreset : nil,
            runsOCR: runsOCR,
            watermarkText: watermarkEnabled ? watermarkText : nil
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.string("batchFold.sheet.title", locale: locale))
                .font(.headline)
            Text(L10n.string("batchFold.sheet.subtitle", locale: locale))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Toggle(L10n.string("batchFold.option.ocr", locale: locale), isOn: $runsOCR)

            Toggle(L10n.string("batchFold.option.watermark", locale: locale), isOn: $watermarkEnabled)
            if watermarkEnabled {
                TextField(
                    L10n.string("batchFold.watermark.placeholder", locale: locale),
                    text: $watermarkText
                )
                .textFieldStyle(.roundedBorder)
                .padding(.leading, 18)
            }

            Toggle(L10n.string("batchFold.option.compress", locale: locale), isOn: $compressionEnabled)
            if compressionEnabled {
                Picker(L10n.string("batchFold.option.compress", locale: locale), selection: $compressionPreset) {
                    ForEach(PDFCompressionPreset.allCases) { preset in
                        Text(L10n.string(forKey: "pdfCompressionPreset.\(preset.rawValue).label", locale: locale))
                            .tag(preset)
                    }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                .padding(.leading, 18)
            }

            HStack {
                if viewModel.batchFoldResult != nil {
                    Button(L10n.string("batchFold.results.viewLast", locale: locale)) {
                        viewModel.isShowingBatchFold = false
                        DispatchQueue.main.async {
                            viewModel.isShowingBatchFoldResult = true
                        }
                    }
                }
                Spacer()
                Button(L10n.string("contentView.exportSheet.cancel.button", locale: locale)) {
                    viewModel.isShowingBatchFold = false
                }
                .keyboardShortcut(.cancelAction)
                Button(L10n.string("batchFold.action", locale: locale)) {
                    performFold()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(options.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 400)
        .onAppear {
            if watermarkText.isEmpty {
                watermarkText = L10n.string("decoration.defaultWatermark", locale: locale)
            }
        }
    }

    private func performFold() {
        let chosen = options
        viewModel.isShowingBatchFold = false
        // Same runloop-hop rule as the More menu: let this sheet tear down before the
        // folder panel presents.
        DispatchQueue.main.async {
            viewModel.batchFold(options: chosen)
        }
    }
}

/// The most recent folder-fold run. The report is session-only, and its input/output URLs stay
/// in memory rather than becoming a durable history of the user's document locations.
struct BatchFoldResultSheet: View {
    let result: BatchFoldService.RunResult

    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var filter: Filter = .all
    @State private var finderFailureURL: URL?

    private enum Filter: String, CaseIterable, Identifiable {
        case all
        case failed
        case notProcessed

        var id: String { rawValue }
    }

    private var filteredOutcomes: [BatchFoldService.FileOutcome] {
        result.outcomes.filter { outcome in
            switch (filter, outcome.result) {
            case (.all, _), (.failed, .failed), (.notProcessed, .cancelled), (.notProcessed, .notStarted):
                return true
            default:
                return false
            }
        }
    }

    private var duplicateNames: Set<String> {
        let counts = Dictionary(grouping: result.outcomes) { $0.sourceURL.lastPathComponent.lowercased() }
        return Set(counts.compactMap { $0.value.count > 1 ? $0.key : nil })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: .dsLG) {
            header
            summary
            notices
            resultList
            footer
        }
        .padding(.dsXL)
        .frame(width: 680, height: 560)
        .background(Color.dsSurface)
    }

    private var header: some View {
        HStack(spacing: .dsMD) {
            ZStack {
                RoundedRectangle(cornerRadius: .dsRadiusSm, style: .continuous)
                    .fill(LinearGradient.dsAccent)
                Image(systemName: "tray.full.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 42, height: 42)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.string("batchFold.results.title", locale: locale))
                    .font(.system(size: 18, weight: .semibold, design: .serif))
                    .foregroundStyle(Color.dsTextPrimary)
                Text(result.inputFolder.lastPathComponent)
                    .font(.dsCaption())
                    .foregroundStyle(Color.dsTextSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(result.inputFolder.path)
            }
        }
    }

    private var summary: some View {
        HStack(spacing: .dsSM) {
            summaryItem(result.outcomes.count, key: "batchFold.results.planned", color: Color.dsTextPrimary)
            summaryItem(result.foldedCount, key: "batchFold.results.completed", color: Color.dsSuccessAccent)
            summaryItem(result.failedCount, key: "batchFold.results.failed", color: Color.dsErrorAccent)
            summaryItem(result.notProcessedCount, key: "batchFold.results.notProcessed", color: Color.dsWarningAccent)
        }
    }

    private func summaryItem(_ count: Int, key: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(String(count))
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
            Text(L10n.string(forKey: key, locale: locale))
                .font(.dsCaption())
                .foregroundStyle(Color.dsTextSecondary)
        }
        .padding(.dsMD)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.dsCard, in: RoundedRectangle(cornerRadius: .dsRadiusSm))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var notices: some View {
        if let setupFailure = result.setupFailureMessage {
            notice(
                icon: "exclamationmark.octagon.fill",
                key: "batchFold.error.outputFolder",
                detail: setupFailure,
                color: Color.dsErrorAccent
            )
        }
        if result.scanWasTruncated {
            notice(
                icon: "exclamationmark.triangle.fill",
                key: "batchFold.results.scanTruncated",
                color: Color.dsWarningAccent
            )
        }
        if result.scanFailureCount > 0 {
            notice(
                icon: "folder.badge.questionmark",
                key: "batchFold.results.scanIncomplete",
                color: Color.dsWarningAccent
            )
        }
    }

    private func notice(icon: String, key: String, detail: String? = nil, color: Color) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.string(forKey: key, locale: locale))
                if let detail, !detail.isEmpty {
                    Text(detail).foregroundStyle(Color.dsTextSecondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: icon).accessibilityHidden(true)
        }
        .font(.dsCaption())
        .foregroundStyle(color)
        .padding(.dsMD)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.dsCard, in: RoundedRectangle(cornerRadius: .dsRadiusSm))
        .accessibilityElement(children: .combine)
    }

    private var resultList: some View {
        VStack(alignment: .leading, spacing: .dsSM) {
            Picker(L10n.string("batchFold.results.filter", locale: locale), selection: $filter) {
                Text(L10n.string("batchFold.results.filter.all", locale: locale)).tag(Filter.all)
                Text(L10n.string("batchFold.results.filter.failed", locale: locale)).tag(Filter.failed)
                Text(L10n.string("batchFold.results.filter.notProcessed", locale: locale))
                    .tag(Filter.notProcessed)
            }
            .pickerStyle(.segmented)

            if result.outcomes.isEmpty {
                Text(L10n.string("batchFold.results.empty", locale: locale))
                    .font(.dsBody())
                    .foregroundStyle(Color.dsTextSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredOutcomes.isEmpty {
                Text(L10n.string("batchFold.results.filterEmpty", locale: locale))
                    .font(.dsBody())
                    .foregroundStyle(Color.dsTextSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: .dsXS) {
                        ForEach(filteredOutcomes, id: \.sourceURL) { outcome in
                            outcomeRow(outcome)
                        }
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func outcomeRow(_ outcome: BatchFoldService.FileOutcome) -> some View {
        HStack(alignment: .top, spacing: .dsSM) {
            Image(systemName: outcome.symbolName)
                .foregroundStyle(outcome.tint)
                .frame(width: 20)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(outcome.sourceURL.lastPathComponent)
                    .font(.dsBody())
                    .foregroundStyle(Color.dsTextPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if duplicateNames.contains(outcome.sourceURL.lastPathComponent.lowercased()) {
                    Text(relativeParent(for: outcome.sourceURL))
                        .font(.dsCaption())
                        .foregroundStyle(Color.dsTextTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Text(outcome.statusText(locale: locale))
                    .font(.dsCaption())
                    .foregroundStyle(outcome.tint)
                    .fixedSize(horizontal: false, vertical: true)
                if let failedURL = finderFailureURL,
                   let outputURL = outcome.outputURL,
                   failedURL == outputURL {
                    Text(L10n.string("contentView.exportSuccess.finderFailed.message", locale: locale))
                        .font(.dsCaption())
                        .foregroundStyle(Color.dsErrorAccent)
                }
            }

            Spacer()
            if let outputURL = outcome.outputURL {
                Button(L10n.string("batchFold.results.revealOutput", locale: locale)) {
                    reveal(outputURL)
                }
                .controlSize(.small)
            }
        }
        .padding(.dsSM)
        .background(Color.dsCard, in: RoundedRectangle(cornerRadius: .dsRadiusSm))
        .accessibilityElement(children: .contain)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: .dsSM) {
            if let failedURL = finderFailureURL,
               let outputDirectory = result.outputDirectory,
               failedURL == outputDirectory {
                Text(L10n.string("contentView.exportSuccess.finderFailed.message", locale: locale))
                    .font(.dsCaption())
                    .foregroundStyle(Color.dsErrorAccent)
            }
            HStack {
                if let outputDirectory = result.outputDirectory {
                    Button(L10n.string("batchFold.results.revealFolder", locale: locale)) {
                        reveal(outputDirectory, opensFolder: true)
                    }
                }
                Spacer()
                Button(L10n.string("contentView.done.button", locale: locale)) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func relativeParent(for sourceURL: URL) -> String {
        let parent = sourceURL.deletingLastPathComponent().standardizedFileURL.path
        let root = result.inputFolder.standardizedFileURL.path
        guard parent != root, parent.hasPrefix(root + "/") else {
            return result.inputFolder.lastPathComponent
        }
        return String(parent.dropFirst(root.count + 1))
    }

    private func reveal(_ url: URL, opensFolder: Bool = false) {
        finderFailureURL = nil
        guard FileManager.default.fileExists(atPath: url.path) else {
            finderFailureURL = url
            return
        }
        if opensFolder {
            if !NSWorkspace.shared.open(url) { finderFailureURL = url }
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }
}

private extension BatchFoldService.FileOutcome {
    var outputURL: URL? {
        if case .folded(let outputURL) = result { return outputURL }
        return nil
    }

    var symbolName: String {
        switch result {
        case .folded: return "checkmark.circle.fill"
        case .failed: return "xmark.octagon.fill"
        case .cancelled: return "stop.circle.fill"
        case .notStarted: return "minus.circle"
        }
    }

    var tint: Color {
        switch result {
        case .folded: return Color.dsSuccessAccent
        case .failed: return Color.dsErrorAccent
        case .cancelled, .notStarted: return Color.dsWarningAccent
        }
    }

    func statusText(locale: Locale) -> String {
        switch result {
        case .folded:
            return L10n.string("batchFold.results.status.completed", locale: locale)
        case .failed(let message):
            return message
        case .cancelled:
            return L10n.string("batchFold.results.status.cancelled", locale: locale)
        case .notStarted:
            return L10n.string("batchFold.results.status.notStarted", locale: locale)
        }
    }
}
