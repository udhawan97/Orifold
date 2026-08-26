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
