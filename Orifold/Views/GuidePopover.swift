import SwiftUI
import AppKit

struct AppIconMark: View {
    var size: CGFloat = 44

    var body: some View {
        Image(nsImage: NSApp.applicationIconImage)
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
            .shadow(color: .black.opacity(0.10), radius: size * 0.10, x: 0, y: size * 0.05)
    }
}

struct AppIconButton: View {
    var size: CGFloat = 24
    @State private var isPresented = false

    var body: some View {
        Button { isPresented.toggle() } label: {
            AppIconMark(size: size)
        }
        .buttonStyle(.plain)
        .help("guide.aboutOrifold.help")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            AppAboutPopover()
        }
    }
}

struct AppBrandLockup: View {
    var iconSize: CGFloat = 28
    var titleSize: CGFloat = 14
    var subtitleSize: CGFloat = 11
    var subtitle: String? = L10n.string("appBrandLockup.subtitle.default")

    var body: some View {
        HStack(spacing: .dsSM) {
            AppIconMark(size: iconSize)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "Orifold")
                    .font(.system(size: titleSize, weight: .semibold, design: .serif))
                    .tracking(.dsWordmarkTracking)
                    .foregroundStyle(Color.dsTextPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: subtitleSize, weight: .medium))
                        .foregroundStyle(Color.dsTextSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    var compact: some View {
        HStack(spacing: .dsXS) {
            AppIconMark(size: iconSize)
            Text(verbatim: "Orifold")
                .font(.system(size: titleSize, weight: .semibold, design: .serif))
                .tracking(.dsWordmarkTracking)
                .foregroundStyle(Color.dsTextPrimary)
        }
        .accessibilityElement(children: .combine)
    }
}

struct AppAboutPopover: View {
    @Environment(\.dismiss) private var dismiss

    private var versionString: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "3.0"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: .dsXL) {
            VStack(alignment: .leading, spacing: .dsMD) {
                ZStack(alignment: .topLeading) {
                    EnsoRing()
                        .stroke(Color.dsAccent.opacity(0.28), style: StrokeStyle(lineWidth: 1.25, lineCap: .round))
                        .frame(width: 56, height: 56)
                        .offset(x: -8, y: -8)
                    AppIconMark(size: 40)
                }
                .frame(width: 40, height: 40, alignment: .topLeading)

                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: "Orifold")
                        .font(.system(size: 17, weight: .semibold, design: .serif))
                        .tracking(.dsWordmarkTracking)
                        .foregroundStyle(Color.dsTextPrimary)
                    Text("appBrandLockup.subtitle.default")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.dsTextSecondary)
                }

                SealVersionBadge(version: versionString)
            }

            LinearGradient(colors: [.clear, Color.dsSeparator, .clear], startPoint: .leading, endPoint: .trailing)
                .frame(height: 1)

            VStack(alignment: .leading, spacing: .dsSM) {
                Text("appAbout.description.chores")
                    .font(.dsBody())
                    .foregroundStyle(Color.dsTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("appAbout.description.noCeremony")
                    .font(.dsCaption())
                    .foregroundStyle(Color.dsTextTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 248)

            HStack {
                Spacer()
                Button("appAbout.close.button") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(.dsLG)
        .frame(width: 280)
        .background(PopoverAuroraBackground())
    }
}

/// A small hanko-style stamp for the version number — a quiet nod to the
/// vermillion seal used on signed documents.
private struct SealVersionBadge: View {
    var version: String

    var body: some View {
        Text("v\(version)")
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .tracking(.dsLabelTracking)
            .foregroundStyle(Color.dsSignatureAccent)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .overlay {
                RoundedRectangle(cornerRadius: .dsRadiusSm, style: .continuous)
                    .strokeBorder(Color.dsSignatureAccent.opacity(0.45), lineWidth: 1)
            }
    }
}

struct GuideButton: View {
    var autoShow = false
    @State private var isPresented = false
    @AppStorage("Orifold.hasSeenGuidePopover") private var hasSeenGuidePopover = false
    private let legacyHasSeenGuideKey = ["PDF", "old.hasSeenGuidePopover"].joined()

    var body: some View {
        Button {
            isPresented.toggle()
            hasSeenGuidePopover = true
        } label: {
            Image(systemName: "questionmark.circle")
        }
        .help("guide.showQuickGuide.help")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            GuidePopover(isPresented: $isPresented)
        }
        .onAppear {
            if UserDefaults.standard.bool(forKey: legacyHasSeenGuideKey) {
                hasSeenGuidePopover = true
            }
            guard autoShow, !hasSeenGuidePopover else { return }
            hasSeenGuidePopover = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                isPresented = true
            }
        }
    }
}

private struct GuidePopover: View {
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: .dsLG) {
            VStack(alignment: .leading, spacing: .dsSM) {
                AppBrandLockup(iconSize: 40, titleSize: 15, subtitle: L10n.string("guidePopover.subtitle"))
                Text("guidePopover.description")
                    .font(.dsCaption())
                    .foregroundStyle(Color.dsTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 40 + .dsSM)
            }

            LinearGradient(colors: [.clear, Color.dsSeparator, .clear], startPoint: .leading, endPoint: .trailing)
                .frame(height: 1)

            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: .dsMD), GridItem(.flexible(), spacing: .dsMD)], spacing: .dsMD) {
                    ForEach(GuideFeature.all) { feature in
                        GuideFeatureTile(feature: feature)
                    }
                }
                .padding(.vertical, 1)
                .padding(.horizontal, 1)
            }
            .scrollIndicators(.hidden)
            .frame(maxHeight: 420)

            HStack {
                Spacer()
                Button("guidePopover.gotIt.button") { isPresented = false }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.dsAccent)
                    .keyboardShortcut(.defaultAction)
                    .shadow(color: Color.dsAccent.opacity(0.30), radius: 8, x: 0, y: 3)
            }
        }
        .padding(.dsLG)
        .frame(width: 430)
        .background(PopoverAuroraBackground())
    }
}

/// A quiet, static wash behind panels — two soft color glows over the base
/// surface, standing in for a texture without drawing attention to itself.
private struct PopoverAuroraBackground: View {
    var body: some View {
        ZStack {
            Color.dsSurface
            RadialGradient(
                colors: [Color.dsAccent.opacity(0.12), .clear],
                center: .topLeading, startRadius: 0, endRadius: 260
            )
            RadialGradient(
                colors: [Color.dsSignatureAccent.opacity(0.07), .clear],
                center: .bottomTrailing, startRadius: 0, endRadius: 240
            )
            LinearGradient(
                colors: [.white.opacity(0.05), .clear],
                startPoint: .top, endPoint: .init(x: 0.5, y: 0.35)
            )
        }
    }
}

private struct GuideFeature: Identifiable {
    var id: String { title }
    var icon: String
    var title: String
    var detail: String
    var tint: Color
    var iconIsDark: Bool = false

    static let all = [
        GuideFeature(icon: "doc.badge.plus",
                     title: L10n.string("guideFeature.import.title"),
                     detail: L10n.string("guideFeature.import.detail"),
                     tint: .dsAccent),
        GuideFeature(icon: "square.stack.3d.down.right",
                     title: L10n.string("guideFeature.assemble.title"),
                     detail: L10n.string("guideFeature.assemble.detail"),
                     tint: .dsAccentBright),
        GuideFeature(icon: "text.cursor",
                     title: L10n.string("guideFeature.editText.title"),
                     detail: L10n.string("guideFeature.editText.detail"),
                     tint: .dsAnnotationSky),
        GuideFeature(icon: "highlighter",
                     title: L10n.string("guideFeature.markUp.title"),
                     detail: L10n.string("guideFeature.markUp.detail"),
                     tint: .dsHighlightYellow, iconIsDark: true),
        GuideFeature(icon: "bubble.left.and.text.bubble.right",
                     title: L10n.string("guideFeature.review.title"),
                     detail: L10n.string("guideFeature.review.detail"),
                     tint: .dsAnnotationLavender),
        GuideFeature(icon: "signature",
                     title: L10n.string("guideFeature.sign.title"),
                     detail: L10n.string("guideFeature.sign.detail"),
                     tint: .dsSignatureAccent),
        GuideFeature(icon: "seal",
                     title: L10n.string("guideFeature.decorate.title"),
                     detail: L10n.string("guideFeature.decorate.detail"),
                     tint: .dsAnnotationCoral),
        GuideFeature(icon: "checklist",
                     title: L10n.string("guideFeature.forms.title"),
                     detail: L10n.string("guideFeature.forms.detail"),
                     tint: .dsAnnotationSage),
        GuideFeature(icon: "doc.text.viewfinder",
                     title: L10n.string("guideFeature.ocr.title"),
                     detail: L10n.string("guideFeature.ocr.detail"),
                     tint: .dsAccent),
        GuideFeature(icon: "arrow.down.circle",
                     title: L10n.string("guideFeature.compress.title"),
                     detail: L10n.string("guideFeature.compress.detail"),
                     tint: .dsAccentBright),
        GuideFeature(icon: "lock.shield",
                     title: L10n.string("guideFeature.protect.title"),
                     detail: L10n.string("guideFeature.protect.detail"),
                     tint: .dsGraphite),
        GuideFeature(icon: "square.and.arrow.up",
                     title: L10n.string("guideFeature.export.title"),
                     detail: L10n.string("guideFeature.export.detail"),
                     tint: .dsAnnotationSky)
    ]
}

/// A glossy, gradient-filled icon tile — the small colored badges macOS
/// System Settings uses per row, instead of a flat monochrome glyph.
private struct FeatureIconTile: View {
    var systemName: String
    var tint: Color
    var iconIsDark: Bool = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(LinearGradient(colors: [tint.opacity(0.88), tint], startPoint: .top, endPoint: .bottom))
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.4), .white.opacity(0)], startPoint: .top, endPoint: .bottom),
                    lineWidth: 0.75
                )
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(iconIsDark ? Color.black.opacity(0.65) : .white)
                .shadow(color: .black.opacity(iconIsDark ? 0 : 0.18), radius: 1, x: 0, y: 0.5)
        }
        .frame(width: 26, height: 26)
        .shadow(color: tint.opacity(0.4), radius: 4, x: 0, y: 2)
    }
}

private struct GuideFeatureTile: View {
    var feature: GuideFeature

    var body: some View {
        HStack(alignment: .top, spacing: .dsSM) {
            FeatureIconTile(systemName: feature.icon, tint: feature.tint, iconIsDark: feature.iconIsDark)
            VStack(alignment: .leading, spacing: 2) {
                Text(feature.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.dsTextPrimary)
                Text(feature.detail)
                    .font(.dsCaption())
                    .foregroundStyle(Color.dsTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.dsSM)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: .dsRadiusMd, style: .continuous)
                .fill(Color.dsCard.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: .dsRadiusMd, style: .continuous)
                .strokeBorder(Color.dsSeparator, lineWidth: 1)
        )
    }
}
