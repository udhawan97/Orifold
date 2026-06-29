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
            .shadow(color: .black.opacity(0.12), radius: size * 0.12, x: 0, y: size * 0.06)
    }
}

/// Tappable version of the app icon that shows a witty "about" popover.
struct AppIconButton: View {
    var size: CGFloat = 24
    @State private var isPresented = false

    var body: some View {
        Button { isPresented.toggle() } label: {
            AppIconMark(size: size)
        }
        .buttonStyle(.plain)
        .help("About PDFold")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            AppAboutPopover(isPresented: $isPresented)
        }
    }
}

struct AppAboutPopover: View {
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                AppIconMark(size: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text("PDFold")
                        .font(.headline)
                    Text("v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "2.0")")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Text("Here to fix the tiny PDF annoyances macOS somehow left as character-building exercises.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 240)

            Text("Combine, annotate, reorder, and export documents — without the ceremony.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 240)

            HStack {
                Spacer()
                Button("Close") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(16)
        .frame(width: 272)
    }
}

struct GuideButton: View {
    var autoShow = false
    @State private var isPresented = false
    @AppStorage("PDFold.hasSeenGuidePopover") private var hasSeenGuidePopover = false

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
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                AppIconMark(size: 42)
                VStack(alignment: .leading, spacing: 2) {
                    Text("PDFold")
                        .font(.headline)
                    Text("A calmer way to assemble PDFs.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                GuideStep(icon: "plus.circle", title: "Add files", detail: "Drop documents into the window or use the add button.")
                GuideStep(icon: "square.stack.3d.down.right", title: "Arrange pages", detail: "Expand a source file, select pages, then drag thumbnails up or down.")
                GuideStep(icon: "square.and.arrow.up", title: "Finish", detail: "Export a clean PDF or save the editable workspace.")
            }

            HStack {
                Spacer()
                Button("Got it") {
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 310)
    }
}

private struct GuideStep: View {
    var icon: String
    var title: String
    var detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
