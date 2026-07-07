import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct EmptyStateView: View {
    var viewModel: WorkspaceViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // Unused directly, but its presence makes SwiftUI re-invoke this view's
    // `body` (and thus its descendants, including EmptyStatePetIntro/PetPickerCard,
    // whose text comes from PetSpecies' non-reactive L10n.string() properties)
    // when the app's language changes while this screen is already on screen.
    @Environment(\.locale) private var locale
    @State private var isDropTargeted = false
    @State private var hasIntroducedOptions = false
    @State private var optionGuidance: LocalizedStringKey?
    @State private var chooseFilesNudge = 0
    @State private var recentsStore = RecentsStore.shared
    @State private var draggedKind: ImportDragKind?
    @State private var scanPhase: FolderScanPhase = .idle
    @State private var pendingFolderBatch: PendingFolderImportBatch?
    @State private var activeImportTask: Task<Void, Never>?
    /// Shown once, near the folder-import button, so users understand macOS will ask
    /// them to grant access to whichever folder they pick — not a startup modal wall,
    /// just a quiet one-time caption dismissed the first time they act on either
    /// choose-files/choose-folder button.
    @AppStorage("Orifold.hasSeenFolderAccessHint") private var hasSeenFolderAccessHint = false

    private var shouldReduceMotion: Bool {
        reduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    // Stores translation *keys*, not resolved strings: `Text`/`Label` re-resolve a
    // `LocalizedStringKey` against the current environment locale on every render,
    // whereas a pre-resolved `String` (e.g. via `L10n.string()`) is frozen at
    // whatever language was active when this array was built and never updates.
    private let featureOptions: [EmptyStateOption] = [
        EmptyStateOption(icon: "square.stack.3d.down.right", titleKey: "emptyState.option.assemble.title", accent: .dsAccent, guidanceKey: "emptyState.option.assemble.guidance"),
        EmptyStateOption(icon: "highlighter", titleKey: "emptyState.option.markUp.title", accent: .dsAnnotationSky, guidanceKey: "emptyState.option.markUp.guidance"),
        EmptyStateOption(icon: "checklist", titleKey: "emptyState.option.fillForms.title", accent: .dsAnnotationSage, guidanceKey: "emptyState.option.fillForms.guidance"),
        EmptyStateOption(icon: "text.viewfinder", titleKey: "emptyState.option.searchScans.title", accent: .dsAccentBright, guidanceKey: "emptyState.option.searchScans.guidance"),
        EmptyStateOption(icon: "seal", titleKey: "emptyState.option.stamp.title", accent: .dsSignatureAccent, guidanceKey: "emptyState.option.stamp.guidance"),
        EmptyStateOption(icon: "lock.shield", titleKey: "emptyState.option.protect.title", accent: .dsAnnotationLavender, guidanceKey: "emptyState.option.protect.guidance")
    ]

    var body: some View {
        // Actually reading `locale` (not just declaring the @Environment property)
        // is what registers the dependency — SwiftUI only re-invokes `body` on a
        // locale change for views that read `\.locale` during the previous render.
        let _ = locale
        ZStack(alignment: .topTrailing) {
            Color.dsCanvas.ignoresSafeArea()
            EmptyStateAmbientBackground()

            ScrollView {
                VStack(spacing: .dsXL) {
                    // Wordmark block
                    VStack(spacing: .dsLG) {
                        OrifoldFoldMark(size: 80)

                        VStack(spacing: 6) {
                            Text(verbatim: "Orifold")
                                .font(.dsDisplay(size: 36))
                                .foregroundStyle(Color.dsTextPrimary)
                            Text("emptyState.headline")
                                .font(.dsHeadline())
                                .foregroundStyle(Color.dsTextPrimary)
                            Text("emptyState.subheadline")
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
                            Text(dropZoneHeadlineKey)
                                .font(.dsHeadline())
                                .foregroundStyle(Color.dsTextPrimary)
                            if let scanStatusKey {
                                Text(scanStatusKey)
                                    .font(.dsCaption())
                                    .foregroundStyle(Color.dsAccent)
                                    .transition(.opacity)
                            } else {
                                Text("emptyState.dropZone.supportedTypes")
                                    .font(.dsCaption())
                                    .foregroundStyle(Color.dsTextTertiary)
                            }
                        }
                        .animation(shouldReduceMotion ? nil : .easeInOut(duration: 0.15), value: scanPhase)

                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: .dsSM) { chooseButtons }
                            VStack(spacing: .dsSM) { chooseButtons }
                        }

                        if !hasSeenFolderAccessHint {
                            folderAccessHint
                        }
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
                    .help("emptyState.dropZone.tooltip")

                    RecentFilesSection(store: recentsStore, onOpen: openRecentFile)
                }
                .padding(.horizontal, .dsXXL)
                .padding(.top, recentsStore.entries.isEmpty ? 96 : 56)
                .padding(.bottom, .dsXXL)
                .frame(maxWidth: recentsStore.entries.isEmpty ? 640 : 700)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            LanguageSwitcher()
                .padding(.dsMD)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

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
        .onDrop(of: importDropContentTypes, delegate: ImportDropDelegate(
            onKindChange: { kind in
                draggedKind = kind
                isDropTargeted = kind != nil
            },
            onResolved: { resolved in
                handleResolvedDrop(resolved)
            }
        ))
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
        .confirmationDialog(
            overLimitTitle,
            isPresented: Binding(
                get: { pendingFolderBatch != nil },
                set: { if !$0 { pendingFolderBatch = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingFolderBatch
        ) { batch in
            Button(folderImportOverLimitImportFirstLabel(count: maximumImportBatchSize)) {
                confirmOverLimitImport(batch)
            }
            Button("folderImport.overLimit.cancel", role: .cancel) {
                pendingFolderBatch = nil
            }
        } message: { batch in
            if batch.wasTruncated {
                Text("folderImport.overLimit.truncatedNote")
            }
        }
    }

    private func showGuidance(for option: EmptyStateOption) {
        optionGuidance = option.guidanceKey
        chooseFilesNudge += 1
        guard !shouldReduceMotion else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            chooseFilesNudge += 1
        }
    }

    private var overLimitTitle: String {
        guard let pendingFolderBatch else { return "" }
        return folderImportOverLimitTitle(supportedCount: pendingFolderBatch.urls.count)
    }

    private var chooseButtons: some View {
        Group {
            Button {
                openFiles()
            } label: {
                Label("emptyState.chooseFiles.label", systemImage: "folder.badge.plus")
                    .frame(minWidth: 140)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .tint(Color.dsAccent)
            .scaleEffect(chooseFilesNudge.isMultiple(of: 2) || shouldReduceMotion ? 1 : 1.045)
            .shadow(color: Color.dsAccent.opacity(chooseFilesNudge.isMultiple(of: 2) ? 0 : 0.24), radius: 12, x: 0, y: 5)
            .animation(shouldReduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.48), value: chooseFilesNudge)
            .help("emptyState.chooseFiles.tooltip")
            .accessibilityHint("emptyState.chooseFiles.tooltip")

            Button {
                openFolder()
            } label: {
                Label("emptyState.chooseFolder.label", systemImage: "folder")
                    .frame(minWidth: 140)
            }
            .controlSize(.large)
            .buttonStyle(.bordered)
            .tint(Color.dsAccent)
            .help("emptyState.chooseFolder.tooltip")
            .accessibilityHint("emptyState.chooseFolder.tooltip")
        }
    }

    private var folderAccessHint: some View {
        HStack(alignment: .top, spacing: .dsXS) {
            Image(systemName: "info.circle")
                .font(.system(size: 11, weight: .medium))
            Text("emptyState.folderAccessHint.message")
                .font(.dsCaption())
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button {
                hasSeenFolderAccessHint = true
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("emptyState.folderAccessHint.dismiss.accessibilityLabel")
        }
        .foregroundStyle(Color.dsTextTertiary)
        .padding(.horizontal, .dsMD)
        .padding(.vertical, .dsSM)
        .background(Color.dsSurface, in: RoundedRectangle(cornerRadius: .dsRadiusMd, style: .continuous))
        .transition(.opacity)
    }

    private var dropZoneHeadlineKey: LocalizedStringKey {
        switch draggedKind {
        case .files: return "emptyState.dropZone.releaseFiles"
        case .folder: return "emptyState.dropZone.releaseFolder"
        case .mixed: return "emptyState.dropZone.releaseMixed"
        case nil: return "emptyState.dropZone.dropFilesOrFolders"
        }
    }

    private var scanStatusKey: LocalizedStringKey? {
        switch scanPhase {
        case .idle: return nil
        case .scanning: return "folderImport.scanning"
        case .finding: return "folderImport.findingSupported"
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
        hasSeenFolderAccessHint = true
        let panel = NSOpenPanel()
        configureImportOpenPanel(panel)
        if panel.runModal() == .OK {
            importFilesWithBatchLimit(urls: panel.urls, into: viewModel)
        }
    }

    private func openFolder() {
        hasSeenFolderAccessHint = true
        let panel = NSOpenPanel()
        configureFolderImportOpenPanel(panel)
        guard panel.runModal() == .OK else { return }
        handleResolvedDrop(ResolvedImportDrop(files: [], folders: panel.urls, wasLimited: false))
    }

    private func handleResolvedDrop(_ resolved: ResolvedImportDrop) {
        activeImportTask?.cancel()
        guard !resolved.files.isEmpty || !resolved.folders.isEmpty else {
            scanPhase = .idle
            viewModel.importError = WorkspaceViewModel.ImportError(
                fileName: "Dropped Files",
                message: L10n.string("contentView.dropImportError.noSupportedDocument")
            )
            return
        }
        scanPhase = resolved.folders.isEmpty ? .idle : .scanning
        activeImportTask = Task {
            if !resolved.folders.isEmpty {
                await MainActor.run { scanPhase = .finding }
            }
            let outcome = await importPickedOrDropped(
                files: resolved.files,
                folders: resolved.folders,
                wasLimited: resolved.wasLimited
            )
            guard !Task.isCancelled else { return }
            await MainActor.run {
                scanPhase = .idle
                applyOutcome(outcome)
            }
        }
    }

    private func applyOutcome(_ outcome: FolderImportOutcome) {
        applyFolderImportOutcome(outcome, into: viewModel) { batch in
            pendingFolderBatch = batch
        }
    }

    private func confirmOverLimitImport(_ batch: PendingFolderImportBatch) {
        importFirstFromPendingBatch(batch, into: viewModel)
        pendingFolderBatch = nil
    }

    private func openRecentFile(_ entry: RecentFileEntry) {
        guard let url = recentsStore.resolvedURL(for: entry) else {
            presentRecentFailure(kind: .fileMissing, entry: entry, url: nil)
            return
        }
        if let preflightKind = ImportFailureClassifier.preflight(url: url) {
            ImportLog.recordAttempt(
                source: .recent,
                fileExtension: url.pathExtension,
                securityScopeGranted: false,
                fileExists: preflightKind != .fileMissing,
                isReadable: false,
                parserResult: .failed
            )
            presentRecentFailure(kind: preflightKind, entry: entry, url: url)
            return
        }
        // `openDocument` reads the file asynchronously relative to this call, so the
        // security scope must stay open until its completion handler fires, not just
        // for the duration of this synchronous call.
        let didStartScope = url.startAccessingSecurityScopedResource()
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
            if didStartScope { url.stopAccessingSecurityScopedResource() }
            if let error {
                let kind = ImportFailureClassifier.classify(error: error, url: url)
                ImportLog.recordAttempt(
                    source: .recent,
                    fileExtension: url.pathExtension,
                    securityScopeGranted: didStartScope,
                    fileExists: true,
                    isReadable: true,
                    parserResult: .failed,
                    errorDomain: (error as NSError).domain,
                    errorCode: (error as NSError).code
                )
                presentRecentFailure(kind: kind, entry: entry, url: url)
            } else {
                ImportLog.recordAttempt(
                    source: .recent,
                    fileExtension: url.pathExtension,
                    securityScopeGranted: didStartScope,
                    fileExists: true,
                    isReadable: true,
                    parserResult: .ok
                )
            }
        }
    }

    private func presentRecentFailure(kind: ImportFailureKind, entry: RecentFileEntry, url: URL?) {
        viewModel.importError = WorkspaceViewModel.ImportError(
            fileName: entry.displayName,
            message: DocumentImportConverter.userMessage(for: kind),
            kind: kind,
            recentEntryID: entry.id,
            sourceURL: url
        )
    }
}

private struct EmptyStateOption: Identifiable {
    var icon: String
    var titleKey: LocalizedStringKey
    var accent: Color
    var guidanceKey: LocalizedStringKey

    var id: String { icon }
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
                Text(option.titleKey)
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
        .accessibilityLabel(Text(option.titleKey))
        .accessibilityHint("emptyState.pill.accessibilityHint")
    }
}

private struct EmptyStatePetIntro: View {
    @State private var buddy = PetBuddy.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // Passed into species.introGreeting(locale:)/introMessage(locale:) below so
    // this view's `body` actually reads it — SwiftUI only re-invokes `body` on a
    // locale change for views that read `\.locale` during the previous evaluation.
    @Environment(\.locale) private var locale
    @State private var hasAppeared = false

    private var shouldReduceMotion: Bool {
        reduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    var body: some View {
        if buddy.isEnabled {
            Group {
                if buddy.hasChosenSpecies {
                    chosenIntro
                } else {
                    // First run: let the user meet and pick a companion.
                    PetPicker { buddy.selectSpecies($0) }
                }
            }
            .transition(shouldReduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.94, anchor: .bottomTrailing)))
            .animation(shouldReduceMotion ? nil : .spring(response: 0.46, dampingFraction: 0.82), value: buddy.hasChosenSpecies)
        }
    }

    private var chosenIntro: some View {
        HStack(alignment: .bottom, spacing: .dsSM) {
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: buddy.species.introGreeting(locale: locale))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.dsTextPrimary)
                Text(verbatim: buddy.species.introMessage(locale: locale))
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

/// First-run companion picker shown on the empty state. Presents both origami pets
/// with live folding previews (tap to replay) and a Choose action. Selecting persists
/// the choice and collapses this into the normal chosen-pet intro.
private struct PetPicker: View {
    var onChoose: (PetSpecies) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var hasAppeared = false

    private var shouldReduceMotion: Bool {
        reduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    var body: some View {
        VStack(alignment: .leading, spacing: .dsMD) {
            VStack(alignment: .leading, spacing: 3) {
                Text("petPicker.title")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.dsTextPrimary)
                Text("petPicker.subtitle")
                    .font(.dsCaption())
                    .foregroundStyle(Color.dsTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: .dsSM) {
                ForEach(PetSpecies.allCases, id: \.self) { species in
                    PetPickerCard(species: species) { onChoose(species) }
                }
            }
        }
        .padding(.dsLG)
        .frame(width: 340)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: .dsRadiusLg, style: .continuous))
        .background(
            RoundedRectangle(cornerRadius: .dsRadiusLg, style: .continuous)
                .fill(Color.dsSurface.opacity(colorScheme == .dark ? 0.82 : 0.7))
        )
        .overlay {
            RoundedRectangle(cornerRadius: .dsRadiusLg, style: .continuous)
                .strokeBorder(Color.dsAccent.opacity(0.24), lineWidth: 1)
        }
        .shadow(color: Color.dsAccent.opacity(0.18), radius: 20, x: 0, y: 9)
        .offset(y: hasAppeared || shouldReduceMotion ? 0 : 12)
        .opacity(hasAppeared || shouldReduceMotion ? 1 : 0)
        .onAppear {
            guard !shouldReduceMotion else {
                hasAppeared = true
                return
            }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.3)) {
                hasAppeared = true
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct PetPickerCard: View {
    var species: PetSpecies
    var onChoose: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    // Passed into species.displayName(locale:)/tagline(locale:)/accessibilityLabel(locale:)
    // below so this view's `body` actually reads it — SwiftUI only re-invokes
    // `body` on a locale change for views that read `\.locale` during the
    // previous evaluation.
    @Environment(\.locale) private var locale
    @State private var isHovered = false

    var body: some View {
        VStack(spacing: .dsSM) {
            // Interactive: tapping the mark replays the fold as a preview. Hovering
            // the card also nudges the dog's tail into its more excited wag, the same
            // cue used in the workspace chip, so the preview reads consistently.
            OrifoldFoldMark(size: 76, interactive: true, figure: .forSpecies(species),
                            excitement: isHovered ? 1 : 0)

            VStack(spacing: 2) {
                Text(verbatim: species.displayName(locale: locale))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.dsTextPrimary)
                Text(verbatim: species.tagline(locale: locale))
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(Color.dsTextSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)

            Button(action: onChoose) {
                Text("petPicker.choose")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.dsAccent)
            .controlSize(.small)
        }
        .padding(.dsMD)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: .dsRadiusMd, style: .continuous)
                .fill(Color.dsCard.opacity(colorScheme == .dark ? 0.9 : 0.95))
        )
        .overlay {
            RoundedRectangle(cornerRadius: .dsRadiusMd, style: .continuous)
                .strokeBorder(Color.dsSeparator.opacity(isHovered ? 0.9 : 0.6), lineWidth: 1)
        }
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(species.accessibilityLabel(locale: locale))
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
