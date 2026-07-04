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
        .help("About Orifold")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            AppAboutPopover(isPresented: $isPresented)
        }
    }
}

struct AppBrandLockup: View {
    var iconSize: CGFloat = 28
    var titleSize: CGFloat = 14
    var subtitleSize: CGFloat = 11
    var subtitle: String? = "A calmer way to assemble PDFs."

    var body: some View {
        HStack(spacing: .dsSM) {
            AppIconMark(size: iconSize)
            VStack(alignment: .leading, spacing: 2) {
                Text("Orifold")
                    .font(.system(size: titleSize, weight: .semibold, design: .serif))
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
            Text("Orifold")
                .font(.system(size: titleSize, weight: .semibold, design: .serif))
                .foregroundStyle(Color.dsTextPrimary)
        }
        .accessibilityElement(children: .combine)
    }
}

struct AppAboutPopover: View {
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: .dsLG) {
            VStack(alignment: .leading, spacing: .dsXS) {
                AppBrandLockup(iconSize: 40, titleSize: 15, subtitle: "A calmer way to assemble PDFs.")
                Text("v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "3.0")")
                    .font(.dsCaption())
                    .foregroundStyle(Color.dsTextTertiary)
                    .padding(.leading, 40 + .dsSM)
            }

            Text("Built for the small-but-real PDF chores: combine the pieces, mark what matters, and send out something tidy.")
                .font(.dsBody())
                .foregroundStyle(Color.dsTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 240)

            Text("No ceremony. No mystery panels. Just a focused workspace for getting documents into shape.")
                .font(.dsCaption())
                .foregroundStyle(Color.dsTextTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 240)

            HStack {
                Spacer()
                Button("Close") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(.dsLG)
        .frame(width: 272)
        .background(Color.dsSurface)
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
        .help("Show quick guide")
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
                AppBrandLockup(iconSize: 40, titleSize: 15, subtitle: "A calmer way to finish PDFs.")
                Text("Bring scattered files together, clean them up, and send out the version people actually need.")
                    .font(.dsCaption())
                    .foregroundStyle(Color.dsTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 40 + .dsSM)
            }

            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: .dsMD), GridItem(.flexible(), spacing: .dsMD)], spacing: .dsMD) {
                    ForEach(GuideFeature.all) { feature in
                        GuideFeatureTile(feature: feature)
                    }
                }
                .padding(.vertical, 1)
            }
            .scrollIndicators(.hidden)
            .frame(maxHeight: 420)

            HStack {
                Spacer()
                Button("Got it") { isPresented = false }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.dsAccent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.dsLG)
        .frame(width: 430)
        .background(Color.dsSurface)
    }
}

private struct GuideFeature: Identifiable {
    var id: String { title }
    var icon: String
    var title: String
    var detail: String

    static let all = [
        GuideFeature(icon: "doc.badge.plus",
                     title: "Import",
                     detail: "Drop in PDFs, Word, HTML, Markdown, text, data files, and images."),
        GuideFeature(icon: "square.stack.3d.down.right",
                     title: "Assemble",
                     detail: "Combine files, reorder pages, rotate, delete, and reshape the packet."),
        GuideFeature(icon: "text.cursor",
                     title: "Edit text",
                     detail: "Adjust detected PDF text or add new text boxes directly on the page."),
        GuideFeature(icon: "highlighter",
                     title: "Mark up",
                     detail: "Highlight, underline, strike out, draw ink, erase marks, and add notes."),
        GuideFeature(icon: "bubble.left.and.text.bubble.right",
                     title: "Review",
                     detail: "Track workspace comments, anchored notes, tags, metadata, and search results."),
        GuideFeature(icon: "signature",
                     title: "Sign",
                     detail: "Place visual signatures or create cryptographically signed PDF output."),
        GuideFeature(icon: "seal",
                     title: "Decorate",
                     detail: "Add stamps, watermarks, page numbers, and Bates-style numbering."),
        GuideFeature(icon: "checklist",
                     title: "Forms",
                     detail: "Fill forms and optionally lock answers into the final PDF."),
        GuideFeature(icon: "doc.text.viewfinder",
                     title: "OCR",
                     detail: "Make scanned pages searchable before sharing or archiving."),
        GuideFeature(icon: "arrow.down.circle",
                     title: "Compress",
                     detail: "Reduce PDF size with export-time validation."),
        GuideFeature(icon: "lock.shield",
                     title: "Protect",
                     detail: "Password-protect compatible exports and control copy or print permissions."),
        GuideFeature(icon: "square.and.arrow.up",
                     title: "Export",
                     detail: "Save PDF workspaces or export PDF, DOCX, Markdown, text, HTML, PNG, and JPEG.")
    ]
}

private struct GuideFeatureTile: View {
    var feature: GuideFeature

    var body: some View {
        HStack(alignment: .top, spacing: .dsSM) {
            Image(systemName: feature.icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.dsAccent)
                .frame(width: 20, height: 20)
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
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}
