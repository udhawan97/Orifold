import AppKit
import PDFKit
import SwiftUI

/// Side-by-side compare sheet: the current workspace against another PDF, page pair by page
/// pair, with visual change highlights, a word-level text summary, and a changed-pages strip.
struct ComparePanelView: View {
    let request: PDFComparisonRequest
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var model: ComparePanelModel

    init(request: PDFComparisonRequest) {
        self.request = request
        _model = State(initialValue: ComparePanelModel(request: request))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.string("compare.sheet.title", locale: locale))
                .font(.headline)

            if case .running(let progress) = model.runState {
                Spacer()
                VStack(spacing: 12) {
                    ProgressView(value: progress, total: 1) {
                        Text(L10n.string("compare.comparing", locale: locale))
                    }
                    .frame(maxWidth: 320)
                    Text(progress.formatted(.percent.precision(.fractionLength(0))))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                Spacer()
            } else if model.runState == .cancelled {
                stateMessage("compare.cancelled")
            } else if model.runState == .failed {
                stateMessage("compare.failed")
            } else if let pair = model.currentPair {
                pairView(pair)
            } else if model.runResult?.isComplete == false {
                stateMessage("compare.scope.incomplete")
            } else {
                Spacer()
                HStack {
                    Spacer()
                    Text(L10n.string("compare.noChanges", locale: locale))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                Spacer()
            }

            footer
        }
        .padding(20)
        .frame(width: 940, height: 660)
        .task { await model.run() }
        .onDisappear { model.cancel() }
    }

    private func stateMessage(_ key: String) -> some View {
        VStack {
            Spacer()
            Text(L10n.string(forKey: key, locale: locale))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func pairView(_ pair: PDFComparisonService.PagePair) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 16) {
                pane(
                    title: pageTitle(request.leftTitle, number: pair.left?.number),
                    image: model.leftImage(for: pair),
                    missingKey: Self.panePlaceholderKey(
                        pageExists: pair.left != nil,
                        absentKey: "compare.page.rightOnly"
                    )
                )
                pane(
                    title: pageTitle(request.rightTitle, number: pair.right?.number),
                    image: model.rightImage(for: pair),
                    missingKey: Self.panePlaceholderKey(
                        pageExists: pair.right != nil,
                        absentKey: "compare.page.leftOnly"
                    )
                )
            }
            .frame(maxHeight: .infinity)

            Text(statusText(for: pair))
                .font(.caption)
                .foregroundStyle(pair.change == .unchanged ? .secondary : .primary)
            if pair.visual.isUnavailable {
                unavailableChannel("compare.channel.visualUnavailable")
            }
            if pair.text.isUnavailable {
                unavailableChannel("compare.channel.textUnavailable")
            }
        }
    }

    private func pageTitle(_ title: String, number: Int?) -> String {
        guard let number else { return title }
        return L10n.format("compare.page.title", title, number, locale: locale)
    }

    static func panePlaceholderKey(pageExists: Bool, absentKey: String) -> String {
        pageExists ? "compare.page.previewUnavailable" : absentKey
    }

    private func unavailableChannel(_ key: String) -> some View {
        Label(L10n.string(forKey: key, locale: locale), systemImage: "exclamationmark.triangle")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func pane(title: String, image: NSImage?, missingKey: String) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(nsColor: .textBackgroundColor))
                    .border(Color(nsColor: .separatorColor))
            } else {
                ZStack {
                    Color(nsColor: .windowBackgroundColor)
                    Text(L10n.string(forKey: missingKey, locale: locale))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .border(Color(nsColor: .separatorColor))
            }
        }
    }

    private func statusText(for pair: PDFComparisonService.PagePair) -> String {
        switch pair.change {
        case .unchanged:
            return L10n.string("compare.page.unchanged", locale: locale)
        case .incomplete:
            return L10n.string("compare.page.incomplete", locale: locale)
        case .leftOnly:
            return L10n.string("compare.page.leftOnly", locale: locale)
        case .rightOnly:
            return L10n.string("compare.page.rightOnly", locale: locale)
        case .changed:
            if let text = pair.text.value, text.hasChanges {
                if text.comparedExhaustively {
                    return L10n.format(
                        "compare.text.summary", text.insertedWords, text.deletedWords, locale: locale
                    )
                }
                return L10n.string("compare.text.coarse", locale: locale)
            }
            return L10n.string("compare.page.changed", locale: locale)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let result = model.runResult, result.hasUnavailableChannels {
                Text(L10n.string("compare.scope.incomplete", locale: locale))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let excludedCount = model.runResult?.coverage.excludedRightPageNumbers.count,
               excludedCount > 0 {
                Text(L10n.format("compare.scope.excludedRight", excludedCount, locale: locale))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if model.incompletePairCount > 0 {
                Text(L10n.format("compare.incompletePages", model.incompletePairCount, locale: locale))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !model.isComparing, !model.changedPairs.isEmpty {
                HStack(spacing: 6) {
                    Text(L10n.format("compare.changedPages", model.changedPairs.count, locale: locale))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(model.changedPairs) { pair in
                                Button("\(pair.left?.number ?? pair.right?.number ?? pair.id + 1)") {
                                    model.currentIndex = pair.id
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                    }
                }
            }

            HStack(spacing: 12) {
                Button {
                    model.currentIndex = max(0, model.currentIndex - 1)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(model.isComparing || model.currentIndex == 0)

                Text(L10n.format(
                    "compare.page.position",
                    model.currentIndex + 1,
                    max(model.pairs.count, 1),
                    locale: locale
                ))
                    .font(.caption)
                    .monospacedDigit()

                Button {
                    model.currentIndex = min(model.pairs.count - 1, model.currentIndex + 1)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(model.isComparing || model.currentIndex >= model.pairs.count - 1)

                Divider().frame(height: 16)

                Stepper(
                    value: Binding(
                        get: { model.rightOffset },
                        set: { model.setOffset($0) }
                    ),
                    in: -200...200
                ) {
                    Text("\(L10n.string("compare.offset.label", locale: locale)): \(model.rightOffset)")
                        .font(.caption)
                        .monospacedDigit()
                }
                Toggle(L10n.string("compare.highlight.toggle", locale: locale), isOn: $model.showsHighlights)
                    .toggleStyle(.checkbox)
                    .font(.caption)

                Spacer()

                if model.isComparing {
                    Button(L10n.string("contentView.operationProgress.cancel.button", locale: locale)) {
                        model.cancel()
                    }
                }

                Button(L10n.string("compare.done", locale: locale)) {
                    model.cancel()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
    }
}
