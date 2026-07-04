import SwiftUI

struct StampPalette: View {
    @Bindable var viewModel: WorkspaceViewModel

    @State private var customText = "Reviewed"
    @State private var selectedSwatch: PageDecorationSwatch = .accent

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Rectangle().fill(Color.dsSeparator).frame(height: 0.5)

            VStack(alignment: .leading, spacing: .dsLG) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: .dsSM) {
                    ForEach(StampPreset.allCases) { preset in
                        Button {
                            viewModel.beginStampPlacement(text: preset.title, swatch: preset.swatch)
                        } label: {
                            StampPreviewLabel(title: preset.title, swatch: preset.swatch)
                        }
                        .buttonStyle(.plain)
                        .help("Place \(preset.title.lowercased()) stamp")
                    }
                }

                VStack(alignment: .leading, spacing: .dsSM) {
                    TextField("Custom text", text: $customText)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(placeCustomStamp)

                    HStack(spacing: .dsSM) {
                        ForEach(PageDecorationSwatch.stampChoices, id: \.self) { swatch in
                            Button {
                                selectedSwatch = swatch
                            } label: {
                                Circle()
                                    .fill(swatch.viewColor)
                                    .frame(width: 18, height: 18)
                                    .overlay {
                                        Circle()
                                            .strokeBorder(selectedSwatch == swatch ? Color.dsTextPrimary : Color.dsSeparator, lineWidth: selectedSwatch == swatch ? 2 : 1)
                                    }
                            }
                            .buttonStyle(.plain)
                            .help(swatch.label)
                        }

                        Spacer()

                        Button(action: placeCustomStamp) {
                            Label("Place", systemImage: "seal")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.dsAccent)
                        .disabled(customText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .padding(.dsLG)
        }
        .frame(width: 300)
        .background(Color.dsSurface)
    }

    private var header: some View {
        Text("Stamps")
            .font(.system(size: 15, weight: .semibold, design: .serif))
            .foregroundStyle(Color.dsTextPrimary)
            .padding(.horizontal, .dsLG)
            .padding(.top, .dsMD)
            .padding(.bottom, .dsSM)
    }

    private func placeCustomStamp() {
        viewModel.beginStampPlacement(
            text: customText.trimmingCharacters(in: .whitespacesAndNewlines),
            swatch: selectedSwatch
        )
    }
}

private struct StampPreviewLabel: View {
    var title: String
    var swatch: PageDecorationSwatch

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(swatch.viewColor)
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            .frame(maxWidth: .infinity, minHeight: 38)
            .padding(.horizontal, .dsSM)
            .overlay {
                RoundedRectangle(cornerRadius: .dsRadiusSm, style: .continuous)
                    .strokeBorder(swatch.viewColor, lineWidth: 1.5)
            }
            .contentShape(RoundedRectangle(cornerRadius: .dsRadiusSm, style: .continuous))
    }
}

private enum StampPreset: CaseIterable, Identifiable {
    case approved
    case draft
    case confidential
    case final
    case void

    var id: Self { self }

    var title: String {
        switch self {
        case .approved:
            return "Approved"
        case .draft:
            return "Draft"
        case .confidential:
            return "Confidential"
        case .final:
            return "Final"
        case .void:
            return "Void"
        }
    }

    var swatch: PageDecorationSwatch {
        switch self {
        case .approved:
            return .sage
        case .draft:
            return .tertiary
        case .confidential:
            return .coral
        case .final:
            return .accent
        case .void:
            return .lavender
        }
    }
}

private extension PageDecorationSwatch {
    static var stampChoices: [PageDecorationSwatch] {
        [.accent, .sage, .coral, .tertiary, .lavender]
    }

    var viewColor: Color {
        switch self {
        case .accent:
            return .dsAccent
        case .sage:
            return .dsAnnotationSage
        case .coral:
            return .dsAnnotationCoral
        case .tertiary:
            return .dsTextTertiary
        case .lavender:
            return .dsAnnotationLavender
        }
    }

    var label: String {
        switch self {
        case .accent:
            return "Accent"
        case .sage:
            return "Sage"
        case .coral:
            return "Coral"
        case .tertiary:
            return "Gray"
        case .lavender:
            return "Lavender"
        }
    }
}
