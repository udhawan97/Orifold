import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct EmptyStateView: View {
    var viewModel: WorkspaceViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isDropTargeted = false

    private var shouldReduceMotion: Bool {
        reduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.dsCanvas.ignoresSafeArea()
            EmptyStateAmbientBackground()

            ScrollView {
                VStack(spacing: .dsXL) {
                    // Wordmark block
                    VStack(spacing: .dsLG) {
                        AppIconMark(size: 80)

                        VStack(spacing: 6) {
                            Text("pdFold")
                                .font(.dsDisplay(size: 36))
                                .foregroundStyle(Color.dsTextPrimary)
                            Text("Fold scattered pages into one polished PDF.")
                                .font(.dsHeadline())
                                .foregroundStyle(Color.dsTextPrimary)
                            Text("Combine, arrange, annotate, and export documents in one calm workspace.")
                                .font(.dsBody())
                                .foregroundStyle(Color.dsTextSecondary)
                                .multilineTextAlignment(.center)
                                .lineSpacing(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        HStack(spacing: .dsSM) {
                            EmptyStatePill(icon: "square.stack.3d.down.right", title: "Assemble")
                            EmptyStatePill(icon: "highlighter", title: "Mark up")
                            EmptyStatePill(icon: "square.and.arrow.up", title: "Export")
                        }
                    }

                    // Drop zone card
                    VStack(spacing: .dsLG) {
                        dropZoneIcon

                        VStack(spacing: 5) {
                            Text(isDropTargeted ? "Release to import" : "Drop files to begin")
                                .font(.dsHeadline())
                                .foregroundStyle(Color.dsTextPrimary)
                            Text("PDF, Word, HTML, text, and images")
                                .font(.dsCaption())
                                .foregroundStyle(Color.dsTextTertiary)
                        }

                        Button {
                            openFiles()
                        } label: {
                            Label("Choose Files", systemImage: "folder.badge.plus")
                                .frame(minWidth: 140)
                        }
                        .controlSize(.large)
                        .buttonStyle(.borderedProminent)
                        .tint(Color.dsAccent)
                    }
                    .padding(.horizontal, .dsXXL)
                    .padding(.vertical, .dsXXL)
                    .background(Color.dsCard, in: RoundedRectangle(cornerRadius: .dsRadiusLg, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: .dsRadiusLg, style: .continuous)
                            .strokeBorder(
                                isDropTargeted ? Color.dsAccent : Color.dsSeparator,
                                lineWidth: isDropTargeted ? 1.5 : 1
                            )
                            .animation(shouldReduceMotion ? nil : .easeInOut(duration: 0.15), value: isDropTargeted)
                    }
                    .dsElevation()
                }
                .padding(.horizontal, .dsXXL)
                .padding(.top, 96)
                .padding(.bottom, .dsXXL)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            GuideButton(autoShow: true)
                .buttonStyle(.borderless)
                .font(.title3)
                .padding(.dsXL)
        }
        .overlay {
            RoundedRectangle(cornerRadius: .dsRadiusMd, style: .continuous)
                .strokeBorder(Color.dsAccent.opacity(isDropTargeted ? 0.5 : 0), lineWidth: 1.5)
                .padding(.dsMD)
                .animation(shouldReduceMotion ? nil : .easeInOut(duration: 0.15), value: isDropTargeted)
        }
        .onDrop(of: WorkspaceDocument.importableContentTypes + [.fileURL], isTargeted: $isDropTargeted) { providers in
            resolveImportURLs(from: providers) { urls in
                guard !urls.isEmpty else {
                    viewModel.importError = WorkspaceViewModel.ImportError(
                        fileName: "Dropped Files",
                        message: "pdFold could not find a supported document in that drop."
                    )
                    return
                }
                viewModel.importFiles(urls: urls)
            }
            return true
        }
    }

    @ViewBuilder
    private var dropZoneIcon: some View {
        let icon = Image(systemName: isDropTargeted ? "tray.and.arrow.down.fill" : "doc.badge.plus")
            .font(.system(size: 28, weight: .light))
            .foregroundStyle(Color.dsAccent)
            .symbolRenderingMode(.hierarchical)

        if shouldReduceMotion {
            icon
        } else {
            icon
                .contentTransition(.symbolEffect(.replace))
                .animation(.easeInOut(duration: 0.15), value: isDropTargeted)
        }
    }

    private func openFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = WorkspaceDocument.importableContentTypes
        if panel.runModal() == .OK { viewModel.importFiles(urls: panel.urls) }
    }
}

private struct EmptyStatePill: View {
    var icon: String
    var title: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
            Text(title)
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(Color.dsAccent)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.dsAccentSoft, in: Capsule())
    }
}

private struct EmptyStateAmbientBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    private var shouldReduceMotion: Bool {
        reduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 18.0, paused: shouldReduceMotion)) { timeline in
            Canvas(opaque: false, rendersAsynchronously: true) { context, size in
                drawBackground(in: &context, size: size, date: timeline.date)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func drawBackground(in context: inout GraphicsContext, size: CGSize, date: Date) {
        guard size.width > 0, size.height > 0 else { return }

        let time = shouldReduceMotion ? 0 : date.timeIntervalSinceReferenceDate
        let phase = time / 28
        let accentOpacity = colorScheme == .dark ? 0.10 : 0.075
        let tertiaryOpacity = colorScheme == .dark ? 0.07 : 0.045

        drawFlowLines(in: &context, size: size, phase: phase, opacity: accentOpacity)
        drawPageOutlines(in: &context, size: size, phase: phase, opacity: tertiaryOpacity)
    }

    private func drawFlowLines(
        in context: inout GraphicsContext,
        size: CGSize,
        phase: TimeInterval,
        opacity: Double
    ) {
        let lineCount = 7
        let startY = size.height * 0.18
        let spacing = max(size.height * 0.11, 72)

        for index in 0..<lineCount {
            let offset = sin(phase + Double(index) * 0.8) * 9
            let y = startY + CGFloat(index) * spacing + offset
            guard y > -40, y < size.height + 40 else { continue }

            var path = Path()
            path.move(to: CGPoint(x: -80, y: y))
            path.addCurve(
                to: CGPoint(x: size.width + 80, y: y + CGFloat(cos(phase * 0.7 + Double(index))) * 18),
                control1: CGPoint(x: size.width * 0.28, y: y - 26),
                control2: CGPoint(x: size.width * 0.68, y: y + 34)
            )

            let width = index == 2 ? 1.1 : 0.7
            context.stroke(
                path,
                with: .color(Color.dsAccent.opacity(opacity)),
                style: StrokeStyle(lineWidth: width, lineCap: .round)
            )
        }
    }

    private func drawPageOutlines(
        in context: inout GraphicsContext,
        size: CGSize,
        phase: TimeInterval,
        opacity: Double
    ) {
        let pages: [(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, speed: Double)] = [
            (0.08, 0.28, 34, 42, 0.10),
            (0.20, 0.62, 28, 36, 0.08),
            (0.34, 0.18, 31, 40, 0.12),
            (0.48, 0.76, 36, 45, 0.07),
            (0.62, 0.34, 27, 35, 0.09),
            (0.78, 0.58, 33, 41, 0.11),
            (0.91, 0.22, 29, 37, 0.08)
        ]

        for (index, page) in pages.enumerated() {
            let drift = CGFloat(sin(phase * page.speed * 8 + Double(index))) * 22
            let x = size.width * page.x + drift
            let y = size.height * page.y + CGFloat(cos(phase * page.speed * 7 + Double(index))) * 14
            let rect = CGRect(x: x, y: y, width: page.width, height: page.height)

            var outline = Path(roundedRect: rect, cornerRadius: 4)
            let foldSize = min(page.width, page.height) * 0.28
            outline.move(to: CGPoint(x: rect.maxX - foldSize, y: rect.minY))
            outline.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + foldSize))

            context.stroke(
                outline,
                with: .color(Color.dsTextSecondary.opacity(opacity)),
                style: StrokeStyle(lineWidth: 0.75, lineCap: .round, lineJoin: .round)
            )
        }
    }
}
