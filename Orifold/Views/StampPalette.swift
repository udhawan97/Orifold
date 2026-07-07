import SwiftUI

struct StampPalette: View {
    @Bindable var viewModel: WorkspaceViewModel

    @State private var customText = "Reviewed"
    @State private var selectedSwatch: PageDecorationSwatch = .accent
    // Passed into L10n.string()/L10n.format() below so this view's `body` actually
    // reads it — SwiftUI only re-invokes `body` on a locale change for views that
    // read `\.locale` during the previous evaluation.
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Rectangle().fill(Color.dsSeparator).frame(height: 0.5)

            VStack(alignment: .leading, spacing: .dsLG) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: .dsSM) {
                    ForEach(StampPreset.allCases) { preset in
                        Button {
                            viewModel.beginStampPlacement(text: preset.title(locale: locale), swatch: preset.swatch)
                        } label: {
                            StampPreviewLabel(title: preset.title(locale: locale), swatch: preset.swatch)
                        }
                        .buttonStyle(.plain)
                        .help(L10n.format("stampPalette.place.help", preset.title(locale: locale).lowercased(), locale: locale))
                    }
                }

                VStack(alignment: .leading, spacing: .dsSM) {
                    TextField("stampPalette.customText.placeholder", text: $customText)
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
                            .help(swatch.label(locale: locale))
                        }

                        Spacer()

                        Button(action: placeCustomStamp) {
                            Label("stampPalette.place.button", systemImage: "seal")
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
        Text("stampPalette.title")
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

    func title(locale: Locale) -> String {
        switch self {
        case .approved:
            return L10n.string("stampPreset.approved.title", locale: locale)
        case .draft:
            return L10n.string("stampPreset.draft.title", locale: locale)
        case .confidential:
            return L10n.string("stampPreset.confidential.title", locale: locale)
        case .final:
            return L10n.string("stampPreset.final.title", locale: locale)
        case .void:
            return L10n.string("stampPreset.void.title", locale: locale)
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

    // Reuses the same catalog keys as the identical swatch labels in InspectorView.swift.
    func label(locale: Locale) -> String {
        switch self {
        case .accent:
            return L10n.string("inspector.colorSwatch.accent.label", locale: locale)
        case .sage:
            return L10n.string("inspector.colorSwatch.sage.label", locale: locale)
        case .coral:
            return L10n.string("inspector.colorSwatch.coral.label", locale: locale)
        case .tertiary:
            return L10n.string("inspector.colorSwatch.gray.label", locale: locale)
        case .lavender:
            return L10n.string("inspector.colorSwatch.lavender.label", locale: locale)
        }
    }
}
