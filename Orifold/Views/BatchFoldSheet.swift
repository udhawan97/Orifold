import AppKit
import SwiftUI

/// Options for "Fold a Folder…": pick which operations run over every PDF in the chosen
/// folder. The sheet dismisses itself and hands the options to the view model on the next
/// runloop tick, so the folder panel never presents on top of it.
struct BatchFoldSheet: View {
    @Bindable var viewModel: WorkspaceViewModel
    @Environment(\.locale) private var locale

    @State private var savedPreset: BatchFoldConfiguration?
    @State private var compressionEnabled = false
    @State private var compressionPreset: PDFCompressionPreset = .balanced
    @State private var runsOCR = false
    @State private var watermarkEnabled = false
    @State private var watermarkMode: WatermarkMode = .standard
    @State private var watermarkText = ""

    private enum WatermarkMode: String {
        case standard
        case custom
    }

    private var options: BatchFoldService.Options {
        selection.resolvedOptions(locale: locale)
    }

    private var selection: BatchFoldSelection {
        let watermark: BatchFoldWatermarkChoice
        if !watermarkEnabled {
            watermark = .none
        } else if watermarkMode == .standard {
            watermark = .standard
        } else {
            watermark = .custom(watermarkText)
        }
        return BatchFoldSelection(
            runsOCR: runsOCR,
            compressionPreset: compressionEnabled ? compressionPreset : nil,
            watermark: watermark
        )
    }

    private var persistableConfiguration: BatchFoldConfiguration {
        selection.persistableConfiguration
    }

    private var activeBuiltInPreset: BatchFoldPreset? {
        guard !(watermarkEnabled && watermarkMode == .custom) else { return nil }
        return BatchFoldPreset.allCases.first { $0.configuration == persistableConfiguration }
    }

    private var isSavedPresetActive: Bool {
        guard !(watermarkEnabled && watermarkMode == .custom),
              activeBuiltInPreset == nil,
              let savedPreset else { return false }
        return persistableConfiguration == savedPreset
    }

    private var presetMenuTitle: String {
        if let activeBuiltInPreset {
            return activeBuiltInPreset.title(locale: locale)
        }
        if isSavedPresetActive {
            return L10n.string("batchFold.preset.saved.title", locale: locale)
        }
        return L10n.string("batchFold.preset.choose", locale: locale)
    }

    private var optionSummary: String {
        var parts: [String] = []
        if runsOCR {
            parts.append(L10n.string("batchFold.option.ocr", locale: locale))
        }
        if watermarkEnabled {
            let key = watermarkMode == .standard
                ? "batchFold.preset.watermark.standard"
                : "batchFold.preset.watermark.custom"
            parts.append(L10n.string(forKey: key, locale: locale))
        }
        if compressionEnabled {
            parts.append(L10n.string(
                forKey: "pdfCompressionPreset.\(compressionPreset.rawValue).label",
                locale: locale
            ))
        }
        return parts.isEmpty
            ? L10n.string("batchFold.preset.summary.empty", locale: locale)
            : parts.joined(separator: " • ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.string("batchFold.sheet.title", locale: locale))
                .font(.headline)
            Text(L10n.string("batchFold.sheet.subtitle", locale: locale))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            presetControls

            Toggle(L10n.string("batchFold.option.ocr", locale: locale), isOn: $runsOCR)

            Toggle(L10n.string("batchFold.option.watermark", locale: locale), isOn: $watermarkEnabled)
            if watermarkEnabled {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("", selection: $watermarkMode) {
                        Text(L10n.string("batchFold.preset.watermark.standard", locale: locale))
                            .tag(WatermarkMode.standard)
                        Text(L10n.string("batchFold.preset.watermark.custom", locale: locale))
                            .tag(WatermarkMode.custom)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    if watermarkMode == .custom {
                        TextField(
                            L10n.string("batchFold.watermark.placeholder", locale: locale),
                            text: $watermarkText
                        )
                        .textFieldStyle(.roundedBorder)
                        Text(L10n.string("batchFold.preset.customWatermarkNotSaved", locale: locale))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text(L10n.string("decoration.defaultWatermark", locale: locale))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
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
        .frame(width: 440)
        .onAppear {
            savedPreset = BatchFoldPresetStore().load()
            if watermarkText.isEmpty {
                watermarkText = L10n.string("decoration.defaultWatermark", locale: locale)
            }
        }
    }

    private var presetControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.string("batchFold.preset.section", locale: locale))
                .font(.subheadline.weight(.semibold))

            HStack {
                Menu {
                    ForEach(BatchFoldPreset.allCases) { preset in
                        Button {
                            apply(preset.configuration)
                        } label: {
                            Label(preset.title(locale: locale), systemImage: preset.systemImage)
                        }
                    }
                    if let savedPreset {
                        Divider()
                        Button {
                            apply(savedPreset)
                        } label: {
                            Label(
                                L10n.string("batchFold.preset.saved.title", locale: locale),
                                systemImage: "person.crop.circle"
                            )
                        }
                    }
                } label: {
                    Label(presetMenuTitle, systemImage: "slider.horizontal.3")
                }

                Spacer()

                Button(savedPreset == nil
                    ? L10n.string("batchFold.preset.save", locale: locale)
                    : L10n.string("batchFold.preset.replace", locale: locale)) {
                    perform(.savePreset)
                }
                .disabled(persistableConfiguration.isEmpty)

                if savedPreset != nil {
                    Button {
                        perform(.deletePreset)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .help(L10n.string("batchFold.preset.delete", locale: locale))
                    .accessibilityLabel(L10n.string("batchFold.preset.delete", locale: locale))
                }
            }

            Text(optionSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(Color.dsCard, in: RoundedRectangle(cornerRadius: .dsRadiusSm))
    }

    private func apply(_ configuration: BatchFoldConfiguration) {
        let applied = selection.applying(configuration)
        runsOCR = applied.runsOCR
        compressionEnabled = applied.compressionPreset != nil
        compressionPreset = applied.compressionPreset ?? .balanced
        watermarkEnabled = applied.watermark == .standard
        watermarkMode = .standard
    }

    private func performFold() {
        perform(.chooseFolder)
    }

    private func perform(_ intent: BatchFoldSheetIntent) {
        guard let command = selection.command(for: intent, locale: locale) else { return }
        switch command {
        case .savePreset(let configuration):
            guard BatchFoldPresetStore().save(configuration) else { return }
            savedPreset = configuration
        case .deletePreset:
            BatchFoldPresetStore().delete()
            savedPreset = nil
        case .chooseFolder(let chosen):
            viewModel.isShowingBatchFold = false
            // Same runloop-hop rule as the More menu: let this sheet tear down before the
            // folder panel presents.
            DispatchQueue.main.async {
                viewModel.batchFold(options: chosen)
            }
        }
    }
}
