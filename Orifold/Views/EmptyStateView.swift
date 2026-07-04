import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct EmptyStateView: View {
    var viewModel: WorkspaceViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isDropTargeted = false
    @State private var hasIntroducedOptions = false
    @State private var optionGuidance: String?
    @State private var chooseFilesNudge = 0

    private var shouldReduceMotion: Bool {
        reduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private let featureOptions: [EmptyStateOption] = [
        EmptyStateOption(icon: "square.stack.3d.down.right", title: "Assemble", accent: .dsAccent, guidance: "Choose files below to start assembling a packet."),
        EmptyStateOption(icon: "highlighter", title: "Mark up", accent: .dsAnnotationSky, guidance: "Choose files below, then mark up the pages that matter."),
        EmptyStateOption(icon: "checklist", title: "Fill forms", accent: .dsAnnotationSage, guidance: "Choose files below to open a form and finish it here."),
        EmptyStateOption(icon: "text.viewfinder", title: "Search scans", accent: .dsAccentBright, guidance: "Choose files below to import scans, then make them searchable."),
        EmptyStateOption(icon: "seal", title: "Stamp", accent: .dsSignatureAccent, guidance: "Choose files below, then add stamps, watermarks, or page numbers."),
        EmptyStateOption(icon: "lock.shield", title: "Protect", accent: .dsAnnotationLavender, guidance: "Choose files below, then export a protected copy when it is ready.")
    ]

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
                            Text("Orifold")
                                .font(.dsDisplay(size: 36))
                                .foregroundStyle(Color.dsTextPrimary)
                            Text("Fold scattered pages into one polished PDF.")
                                .font(.dsHeadline())
                                .foregroundStyle(Color.dsTextPrimary)
                            Text("Combine, arrange, annotate, and export documents in one calm workspace. Start with up to 50 files at once.")
                                .font(.dsBody())
                                .foregroundStyle(Color.dsTextSecondary)
                                .multilineTextAlignment(.center)
                                .lineSpacing(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        featureOptionGrid

                        if let optionGuidance {
                            Label(optionGuidance, systemImage: "arrow.down.circle.fill")
                                .font(.dsCaption())
                                .foregroundStyle(Color.dsAccent)
                                .padding(.horizontal, .dsMD)
                                .padding(.vertical, 7)
                                .background(Color.dsAccentSoft, in: Capsule())
                                .transition(shouldReduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
                        }
                    }

                    // Drop zone card
                    VStack(spacing: .dsLG) {
                        dropZoneIcon

                        VStack(spacing: 5) {
                            Text(isDropTargeted ? "Release to import" : "Drop files to begin")
                                .font(.dsHeadline())
                                .foregroundStyle(Color.dsTextPrimary)
                            Text("PDF, Word, HTML, text, images. Up to 50 files.")
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
                        .scaleEffect(chooseFilesNudge.isMultiple(of: 2) || shouldReduceMotion ? 1 : 1.045)
                        .shadow(color: Color.dsAccent.opacity(chooseFilesNudge.isMultiple(of: 2) ? 0 : 0.24), radius: 12, x: 0, y: 5)
                        .animation(shouldReduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.48), value: chooseFilesNudge)
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

            EmptyStatePetIntro()
                .padding(.trailing, .dsXL)
                .padding(.bottom, .dsXL)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
        .overlay {
            RoundedRectangle(cornerRadius: .dsRadiusMd, style: .continuous)
                .strokeBorder(Color.dsAccent.opacity(isDropTargeted ? 0.5 : 0), lineWidth: 1.5)
                .padding(.dsMD)
                .animation(shouldReduceMotion ? nil : .easeInOut(duration: 0.15), value: isDropTargeted)
        }
        .onDrop(of: importDropContentTypes, isTargeted: $isDropTargeted) { providers in
            resolveImportURLs(from: providers) { urls, wasLimited in
                guard !urls.isEmpty else {
                    viewModel.importError = WorkspaceViewModel.ImportError(
                        fileName: "Dropped Files",
                        message: "Orifold could not find a supported document in that drop."
                    )
                    return
                }
                if wasLimited {
                    viewModel.importError = WorkspaceViewModel.ImportError(
                        fileName: "Dropped Files",
                        message: importDropProviderLimitMessage
                    )
                }
                importFilesWithBatchLimit(urls: urls, into: viewModel, sourceName: "Dropped Files")
            }
            return true
        }
        .onAppear {
            guard !hasIntroducedOptions else { return }
            if shouldReduceMotion {
                hasIntroducedOptions = true
            } else {
                withAnimation(.spring(response: 0.46, dampingFraction: 0.82).delay(0.08)) {
                    hasIntroducedOptions = true
                }
            }
        }
    }

    private func showGuidance(for option: EmptyStateOption) {
        optionGuidance = option.guidance
        chooseFilesNudge += 1
        guard !shouldReduceMotion else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            chooseFilesNudge += 1
        }
    }

    private var featureOptionGrid: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: .dsSM) {
                featureOptionPills
            }

            VStack(spacing: .dsSM) {
                HStack(spacing: .dsSM) {
                    featureOptionPills(range: 0..<3)
                }
                HStack(spacing: .dsSM) {
                    featureOptionPills(range: 3..<featureOptions.count)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var featureOptionPills: some View {
        ForEach(Array(featureOptions.enumerated()), id: \.element.id) { index, option in
            EmptyStatePill(
                option: option,
                isIntroduced: hasIntroducedOptions,
                index: index,
                reduceMotion: shouldReduceMotion,
                action: { showGuidance(for: option) }
            )
        }
    }

    private func featureOptionPills(range: Range<Int>) -> some View {
        ForEach(Array(featureOptions[range].enumerated()), id: \.element.id) { offset, option in
            let index = range.lowerBound + offset
            EmptyStatePill(
                option: option,
                isIntroduced: hasIntroducedOptions,
                index: index,
                reduceMotion: shouldReduceMotion,
                action: { showGuidance(for: option) }
            )
        }
    }

    @ViewBuilder
    private var dropZoneIcon: some View {
        let icon = Image(systemName: isDropTargeted ? "tray.and.arrow.down.fill" : "doc.badge.plus")
            .font(.system(size: 28, weight: .light))
            .foregroundStyle(LinearGradient.dsAccent)
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
        configureImportOpenPanel(panel)
        if panel.runModal() == .OK {
            importFilesWithBatchLimit(urls: panel.urls, into: viewModel)
        }
    }
}

private struct EmptyStateOption: Identifiable {
    var icon: String
    var title: String
    var accent: Color
    var guidance: String

    var id: String { title }
}

private struct EmptyStatePill: View {
    var option: EmptyStateOption
    var isIntroduced: Bool
    var index: Int
    var reduceMotion: Bool
    var action: () -> Void

    @State private var isHovered = false
    @State private var glintOffset: CGFloat = -54

    private var entranceDelay: Double {
        reduceMotion ? 0 : Double(index) * 0.035
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: option.icon)
                    .font(.system(size: 11, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .rotationEffect(reduceMotion || !isHovered ? .zero : .degrees(-5))
                    .symbolEffect(.bounce, value: reduceMotion ? false : isHovered)
                Text(option.title)
                    .font(.system(size: 11, weight: .medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .foregroundStyle(option.accent)
        .background {
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            option.accent.opacity(isHovered ? 0.24 : 0.15),
                            option.accent.opacity(isHovered ? 0.13 : 0.09)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .overlay {
            Capsule()
                .strokeBorder(option.accent.opacity(isHovered ? 0.38 : 0.18), lineWidth: 1)
        }
        .overlay {
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            .white.opacity(0),
                            .white.opacity(isHovered ? 0.22 : 0),
                            .white.opacity(0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 22)
                .rotationEffect(.degrees(18))
                .offset(x: glintOffset)
                .blur(radius: 0.5)
                .allowsHitTesting(false)
                .clipShape(Capsule())
        }
        .shadow(color: option.accent.opacity(isHovered ? 0.20 : 0), radius: 8, x: 0, y: 3)
        .scaleEffect(isHovered && !reduceMotion ? 1.035 : 1)
        .offset(y: isIntroduced || reduceMotion ? (isHovered && !reduceMotion ? -1 : 0) : 5)
        .opacity(isIntroduced || reduceMotion ? 1 : 0)
        .onHover { hovering in
            if reduceMotion {
                isHovered = hovering
            } else {
                withAnimation(.easeOut(duration: 0.14)) {
                    isHovered = hovering
                }
                if hovering {
                    glintOffset = -54
                    withAnimation(.easeOut(duration: 0.34).delay(0.03)) {
                        glintOffset = 54
                    }
                } else {
                    glintOffset = -54
                }
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.82).delay(entranceDelay), value: isIntroduced)
        .accessibilityLabel(option.title)
        .accessibilityHint("Use Choose Files to continue.")
    }
}

private struct EmptyStatePetIntro: View {
    @State private var buddy = PetBuddy.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared = false

    private var shouldReduceMotion: Bool {
        reduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    var body: some View {
        if buddy.isEnabled {
            HStack(alignment: .bottom, spacing: .dsSM) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Hi, I am Foldy.")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.dsTextPrimary)
                    Text("Choose files and I will help keep the PDF chores moving.")
                        .font(.dsCaption())
                        .foregroundStyle(Color.dsTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, .dsMD)
                .padding(.vertical, .dsSM)
                .frame(width: 220, alignment: .leading)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: .dsRadiusMd, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: .dsRadiusMd, style: .continuous)
                        .strokeBorder(Color.dsAccent.opacity(0.24), lineWidth: 1)
                }
                .shadow(color: Color.dsAccent.opacity(0.16), radius: 16, x: 0, y: 7)
                .offset(x: hasAppeared || shouldReduceMotion ? 0 : 10)
                .opacity(hasAppeared || shouldReduceMotion ? 1 : 0)

                PetView(presentation: .welcome)
            }
            .transition(shouldReduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.94, anchor: .bottomTrailing)))
            .onAppear {
                guard !shouldReduceMotion else {
                    hasAppeared = true
                    return
                }
                withAnimation(.spring(response: 0.48, dampingFraction: 0.76).delay(0.22)) {
                    hasAppeared = true
                }
            }
        }
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
        let glowOpacity = colorScheme == .dark ? 0.10 : 0.06
        let tertiaryOpacity = colorScheme == .dark ? 0.07 : 0.045

        drawAmbientGlows(in: &context, size: size, phase: phase, opacity: glowOpacity)
        drawPageOutlines(in: &context, size: size, phase: phase, opacity: tertiaryOpacity)
    }

    private func drawAmbientGlows(
        in context: inout GraphicsContext,
        size: CGSize,
        phase: TimeInterval,
        opacity: Double
    ) {
        // Large, slow-drifting radial glows — a quiet gradient wash instead of drawn lines.
        // Spaced so their radii don't stack in the window's center (avoids a bright, muddy core).
        let glows: [(x: CGFloat, y: CGFloat, radius: CGFloat, speed: Double)] = [
            (0.15, 0.15, 0.32, 0.9),
            (0.85, 0.20, 0.30, 0.7),
            (0.50, 0.90, 0.34, 0.5)
        ]

        for (index, glow) in glows.enumerated() {
            let drift = Double(index) * 2.1
            let cx = size.width * glow.x + CGFloat(sin(phase * glow.speed + drift)) * size.width * 0.04
            let cy = size.height * glow.y + CGFloat(cos(phase * glow.speed * 0.8 + drift)) * size.height * 0.03
            let radius = max(size.width, size.height) * glow.radius
            let center = CGPoint(x: cx, y: cy)

            let gradient = Gradient(stops: [
                .init(color: Color.dsAccent.opacity(opacity), location: 0),
                .init(color: Color.dsAccent.opacity(opacity * 0.4), location: 0.45),
                .init(color: Color.dsAccent.opacity(0), location: 1)
            ])

            context.fill(
                Path(ellipseIn: CGRect(
                    x: center.x - radius,
                    y: center.y - radius,
                    width: radius * 2,
                    height: radius * 2
                )),
                with: .radialGradient(gradient, center: center, startRadius: 0, endRadius: radius)
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
