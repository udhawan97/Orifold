import SwiftUI

/// Feature G2: the barcode/QR composer. Pick a symbology, type the payload, watch a live
/// preview, and Insert — which renders the barcode to PNG, arms it for click-to-place (the
/// same gesture stamps/hanko use), and dismisses. Over-capacity payloads surface an inline
/// error instead of a broken barcode.
struct BarcodeComposerView: View {
    @Bindable var viewModel: WorkspaceViewModel
    @Environment(\.dismiss) private var dismiss
    // Read so SwiftUI re-invokes `body` on a language change (see L10n.string docs).
    @Environment(\.locale) private var locale

    @State private var symbology: BarcodeSymbology = .qr
    @State private var payload = ""

    var body: some View {
        let render = render(for: payload, symbology: symbology)

        VStack(alignment: .leading, spacing: .dsLG) {
            Text(L10n.string("barcode.insert.title", locale: locale))
                .font(.system(size: 15, weight: .semibold, design: .serif))
                .foregroundStyle(Color.dsTextPrimary)

            VStack(alignment: .leading, spacing: .dsSM) {
                Text(L10n.string("barcode.symbology.label", locale: locale))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.dsTextSecondary)
                Picker(L10n.string("barcode.symbology.label", locale: locale), selection: $symbology) {
                    ForEach(BarcodeSymbology.allCases) { symbology in
                        Text(symbology.displayName).tag(symbology)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: .dsSM) {
                Text(L10n.string("barcode.payload.label", locale: locale))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.dsTextSecondary)
                TextField("", text: $payload, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                    .font(.system(size: 13, design: .monospaced))
            }

            preview(render.image)

            if let message = render.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.dsAnnotationCoral)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button(L10n.string("contentView.exportSheet.cancel.button", locale: locale)) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button {
                    insert(render.image)
                } label: {
                    Label(L10n.string("barcode.insert.title", locale: locale), systemImage: "barcode")
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.dsAccent)
                .keyboardShortcut(.defaultAction)
                .disabled(render.image == nil)
            }
        }
        .padding(.dsXL)
        .frame(width: 340)
        .background(Color.dsSurface)
    }

    /// The framed live preview: the rendered barcode when there is one, otherwise a quiet
    /// placeholder so the panel doesn't jump as the user types.
    @ViewBuilder
    private func preview(_ image: CGImage?) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: .dsRadiusSm, style: .continuous)
                .fill(Color.dsCanvas)
                .overlay {
                    RoundedRectangle(cornerRadius: .dsRadiusSm, style: .continuous)
                        .strokeBorder(Color.dsSeparator, lineWidth: 1)
                }
            if let image {
                Image(nsImage: NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height)))
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .padding(.dsMD)
                    .accessibilityHidden(true)
            } else {
                Image(systemName: "qrcode")
                    .font(.system(size: 34))
                    .foregroundStyle(Color.dsTextTertiary)
                    .accessibilityHidden(true)
            }
        }
        .frame(height: 150)
    }

    /// Renders the barcode for the current inputs, mapping an over-capacity payload to the
    /// localized `barcode.error.tooLong` message. An empty payload yields neither image nor
    /// error (the Insert button is simply disabled).
    private func render(for payload: String, symbology: BarcodeSymbology) -> (image: CGImage?, errorMessage: String?) {
        guard !payload.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return (nil, nil)
        }
        do {
            return (try BarcodeGenerator.image(for: payload, symbology: symbology), nil)
        } catch BarcodeError.payloadTooLong(let max) {
            return (nil, L10n.format("barcode.error.tooLong", max, locale: locale))
        } catch {
            return (nil, nil)
        }
    }

    private func insert(_ image: CGImage?) {
        guard let image, let png = pngData(from: image) else { return }
        viewModel.beginBarcodePlacement(
            imageData: png,
            pixelSize: CGSize(width: image.width, height: image.height)
        )
        dismiss()
    }

    private func pngData(from image: CGImage) -> Data? {
        NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }
}

private extension BarcodeSymbology {
    /// The standard, brand-neutral name for each symbology. Deliberately not localized —
    /// "QR", "Aztec", "Code 128", and "PDF417" are the codes' proper names in every language.
    var displayName: String {
        switch self {
        case .qr: return "QR"
        case .aztec: return "Aztec"
        case .code128: return "Code 128"
        case .pdf417: return "PDF417"
        }
    }
}
