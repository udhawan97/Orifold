import SwiftUI

/// A native control path to the same placement geometry and undo operations as dragging.
struct PlacementGeometryControls: View {
    @Bindable var viewModel: WorkspaceViewModel
    @Environment(\.locale) private var locale
    @State private var isPresented = false
    @State private var x = ""
    @State private var y = ""
    @State private var width = ""
    @State private var height = ""

    private var proposedBounds: CGRect? {
        guard let x = coordinate(x), let y = coordinate(y),
              let width = coordinate(width), let height = coordinate(height),
              width > 0, height > 0 else { return nil }
        return CGRect(x: x, y: y, width: width, height: height)
    }

    var body: some View {
        HStack {
            Button(L10n.string("placement.geometry.title", locale: locale)) {
                refreshDraft()
                isPresented = true
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .focusable()
            .popover(isPresented: $isPresented) {
                VStack(alignment: .leading, spacing: .dsMD) {
                    Text(L10n.string("placement.geometry.title", locale: locale))
                        .font(.headline)
                    geometryField("placement.geometry.x", text: $x)
                    geometryField("placement.geometry.y", text: $y)
                    geometryField("placement.geometry.width", text: $width)
                    geometryField("placement.geometry.height", text: $height)
                    HStack {
                        Button(L10n.string("placement.geometry.delete", locale: locale)) {
                            viewModel.deleteSelectedAnnotation()
                            isPresented = false
                        }
                        Spacer()
                        Button(L10n.string("placement.geometry.apply", locale: locale)) {
                            guard let proposedBounds else { return }
                            _ = viewModel.applySelectedPlacementBounds(proposedBounds)
                            refreshDraft()
                        }
                        .keyboardShortcut(.defaultAction)
                        .disabled(proposedBounds == nil)
                    }
                    Button(L10n.string("readingCanvas.signaturePlacement.cancel.button", locale: locale)) {
                        isPresented = false
                    }
                    .keyboardShortcut(.cancelAction)
                }
                .padding(.dsLG)
                .frame(width: 280)
                .environment(\.locale, locale)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, .dsMD)
        .padding(.vertical, .dsXS)
        .onChange(of: viewModel.selectedPlacementBounds) { _, _ in
            if viewModel.selectedPlacementBounds == nil { isPresented = false }
            else if isPresented { refreshDraft() }
        }
    }

    private func geometryField(_ key: String, text: Binding<String>) -> some View {
        LabeledContent(L10n.string(forKey: key, locale: locale)) {
            TextField(L10n.string(forKey: key, locale: locale), text: text)
                .textFieldStyle(.roundedBorder)
                .frame(width: 90)
                .accessibilityLabel(L10n.string(forKey: key, locale: locale))
        }
    }

    private func coordinate(_ text: String) -> Double? {
        let separator = locale.decimalSeparator ?? "."
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: separator, with: ".")
        guard let value = Double(normalized), value.isFinite else { return nil }
        return value
    }

    private func refreshDraft() {
        guard let bounds = viewModel.selectedPlacementBounds else { return }
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.maximumFractionDigits = 4
        func formatted(_ value: CGFloat) -> String {
            formatter.string(from: NSNumber(value: Double(value))) ?? String(Double(value))
        }
        x = formatted(bounds.minX)
        y = formatted(bounds.minY)
        width = formatted(bounds.width)
        height = formatted(bounds.height)
    }
}
