import SwiftUI
import PDFKit
import UniformTypeIdentifiers
import AppKit

private struct ExportSuccessOverlay: ViewModifier {
    @Bindable var viewModel: WorkspaceViewModel

    func body(content: Content) -> some View {
        content.overlay {
            if let success = viewModel.exportSuccess {
                ExportSuccessPanel(success: success) {
                    viewModel.exportSuccess = nil
                }
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.95).combined(with: .opacity),
                    removal: .scale(scale: 0.98).combined(with: .opacity)
                ))
                .zIndex(100)
            }
        }
        .animation(.spring(duration: 0.26, bounce: 0.12), value: viewModel.exportSuccess?.id)
    }
}

private struct ExportSuccessPanel: View {
    let success: WorkspaceViewModel.ExportSuccess
    let onDone: () -> Void

    @State private var finderFailed = false
    @FocusState private var doneButtonFocused: Bool

    private var fileName: String { success.url.lastPathComponent }
    private var folderName: String {
        let name = success.url.deletingLastPathComponent().lastPathComponent
        return name.isEmpty ? success.url.deletingLastPathComponent().path : name
    }
    private var hasFolderPath: Bool { !folderName.isEmpty }

    var body: some View {
        ZStack {
            Color.black.opacity(0.22)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack(alignment: .center, spacing: .dsMD) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(Color.dsSuccessAccent)
                        .symbolRenderingMode(.hierarchical)
                        .accessibilityHidden(true)

                    Text("contentView.exportSuccess.pdfSaved.title")
                        .font(.dsTitle())
                        .foregroundStyle(Color.dsTextPrimary)
                }
                .padding(.horizontal, .dsXL)
                .padding(.top, .dsXL)
                .padding(.bottom, .dsLG)

                Divider()

                // Body
                VStack(alignment: .leading, spacing: .dsSM) {
                    Text(fileName)
                        .font(.dsBody())
                        .foregroundStyle(Color.dsTextPrimary)
                        .lineLimit(2)
                        .truncationMode(.middle)

                    if hasFolderPath {
                        HStack(alignment: .firstTextBaseline, spacing: .dsXS) {
                            Text("contentView.exportSuccess.savedTo.label")
                                .font(.dsCaption())
                                .foregroundStyle(Color.dsTextTertiary)
                            Text(folderName)
                                .font(.dsCaption())
                                .foregroundStyle(Color.dsTextSecondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .help(success.url.deletingLastPathComponent().path)
                        }
                    }

                    if let detail = success.detail, !detail.isEmpty {
                        Text(detail)
                            .font(.dsCaption())
                            .foregroundStyle(Color.dsTextTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if finderFailed {
                        Text("contentView.exportSuccess.finderFailed.message")
                            .font(.dsCaption())
                            .foregroundStyle(Color.dsErrorAccent)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, .dsXL)
                .padding(.vertical, .dsLG)

                Divider()

                // Buttons
                HStack(spacing: .dsSM) {
                    Button {
                        let fileExists = FileManager.default.fileExists(atPath: success.url.path)
                        if fileExists {
                            NSWorkspace.shared.activateFileViewerSelecting([success.url])
                            onDone()
                        } else {
                            finderFailed = true
                        }
                    } label: {
                        Text("contentView.showInFinder.button")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                    Button {
                        onDone()
                    } label: {
                        Text("contentView.done.button")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(Color.dsAccent)
                    .keyboardShortcut(.defaultAction)
                    .focused($doneButtonFocused)
                }
                .padding(.horizontal, .dsXL)
                .padding(.vertical, .dsLG)
            }
            .background(Color.dsCard, in: RoundedRectangle(cornerRadius: .dsRadiusLg))
            .overlay {
                RoundedRectangle(cornerRadius: .dsRadiusLg)
                    .strokeBorder(Color.dsSeparator, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.10), radius: 20, x: 0, y: 8)
            .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
            .frame(width: 320)
            .onExitCommand { onDone() }
            .onAppear { doneButtonFocused = true }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text("contentView.exportSuccess.pdfSaved.title"))
        }
    }
}

struct ContentView: View {
    var document: WorkspaceDocument
    @State private var viewModel: WorkspaceViewModel
    @State private var showInspector = false
    @State private var inspectorTab: InspectorView.Tab = .info
    @State private var showTOC = false
    @State private var isShowingExportSheet = false
    @State private var isWorkspaceDropTargeted = false
    @State private var isNavigationDropTargeted = false
    @State private var isShowingNightModeControls = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @AppStorage("orifoldAppAppearanceMode") private var persistedAppAppearanceMode = AppAppearanceMode.system.rawValue
    @AppStorage("orifoldNightModeEnabled") private var persistedNightModeEnabled = false
    @AppStorage("orifoldNightModeWarmth") private var persistedNightModeWarmth = NightModeSettings.default.warmth
    @AppStorage("orifoldNightModeIntensity") private var persistedNightModeIntensity = NightModeSettings.default.intensity
    @AppStorage("orifoldNightModeDimming") private var persistedNightModeDimming = NightModeSettings.default.dimming
    @Environment(\.undoManager) private var undoManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shouldReduceMotion: Bool {
        reduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    init(document: WorkspaceDocument) {
        self.document = document
        _viewModel = State(initialValue: WorkspaceViewModel(document: document))
    }

    var body: some View {
        Group {
            if viewModel.memberDocuments.isEmpty {
                EmptyStateView(viewModel: viewModel)
            } else {
                NavigationSplitView(columnVisibility: $columnVisibility) {
                    SidebarView(viewModel: viewModel) { providers, targetPageRefID in
                        handleDrop(providers: providers, insertingAfter: targetPageRefID)
                    }
                        .navigationSplitViewColumnWidth(min: 200, ideal: 260, max: 320)
                } detail: {
                    HStack(spacing: 0) {
                        ReadingCanvas(viewModel: viewModel)
                            .overlay(alignment: .topLeading) {
                                if viewModel.isReaderMode {
                                    ReaderModePill(viewModel: viewModel) {
                                        inspectorTab = .comments
                                        showInspector = true
                                    } onExit: {
                                        viewModel.isReaderMode = false
                                    }
                                    .padding(.top, 48)
                                    .padding(.leading, .dsLG)
                                }
                            }
                            .overlay(alignment: .topTrailing) {
                                DocumentCommentsIndicator(count: viewModel.currentPageCommentCount) {
                                    inspectorTab = .comments
                                    showInspector = true
                                }
                                .padding(.top, 48)
                                .padding(.trailing, .dsLG)
                            }
                        if showInspector {
                            Rectangle().fill(Color.dsSeparator).frame(width: 0.5)
                            InspectorView(viewModel: viewModel, selectedTab: $inspectorTab)
                                .frame(width: 280)
                        }
                    }
                    .animation(shouldReduceMotion ? nil : .easeInOut(duration: 0.18), value: showInspector)
                    .overlay { workspaceDropOverlay }
                    .onDrop(
                        of: importDropContentTypes,
                        isTargeted: $isWorkspaceDropTargeted,
                    ) { providers in
                        handleDrop(providers: providers)
                    }
                }
                .navigationTitle(viewModel.document.workspace.title)
                .toolbar { mainToolbar }
            }
        }
        .animation(shouldReduceMotion ? nil : .easeInOut(duration: 0.18), value: viewModel.memberDocuments.isEmpty)
        .preferredColorScheme(viewModel.appAppearanceMode.colorScheme)
        .tint(Color.dsAccent)
        .overlay(alignment: .bottomTrailing) {
            if !viewModel.memberDocuments.isEmpty {
                PetOverlay().padding(18)
            }
        }
        .overlay(alignment: .bottom) {
            if viewModel.operationProgress.isActive {
                WorkspaceOperationProgressView(progress: viewModel.operationProgress) {
                    viewModel.cancelActiveOperation()
                }
                .padding(.bottom, .dsLG)
                .transition(.opacity)
            }
        }
        .animation(shouldReduceMotion ? nil : .easeInOut(duration: 0.16), value: viewModel.operationProgress.isActive)
        .focusedSceneValue(\.orifoldIsImporting, viewModel.isImporting)
        .focusedSceneValue(\.orifoldWorkspaceViewModel, viewModel)
        .onAppear {
            viewModel.undoManager = undoManager
            setAppAppearanceMode(persistedAppAppearanceModeValue)
            viewModel.isNightModeEnabled = persistedNightModeEnabled
            viewModel.nightModeSettings = persistedNightModeSettings
        }
        .onChange(of: undoManager) { _, um in viewModel.undoManager = um }
        .onChange(of: viewModel.appAppearanceMode) { _, mode in
            persistedAppAppearanceModeValue = mode
            applyAppAppearanceMode(mode)
        }
        .onChange(of: persistedAppAppearanceMode) { _, _ in
            syncPersistedAppAppearanceMode()
        }
        .onChange(of: viewModel.isNightModeEnabled) { _, enabled in
            persistedNightModeEnabled = enabled
        }
        .onChange(of: viewModel.nightModeSettings) { _, settings in
            persistedNightModeSettings = settings
        }
        .onChange(of: viewModel.selectedCommentID) { _, newValue in
            guard newValue != nil else { return }
            inspectorTab = .comments
            showInspector = true
        }
        .popover(isPresented: $viewModel.isShowingSearch, arrowEdge: .top) {
            SearchView(viewModel: viewModel)
        }
        .popover(isPresented: $viewModel.isShowingSignaturePalette, arrowEdge: .top) {
            SignaturePalette(viewModel: viewModel)
        }
        .popover(isPresented: $viewModel.isShowingStampPalette, arrowEdge: .top) {
            StampPalette(viewModel: viewModel)
        }
        .sheet(isPresented: $isShowingExportSheet) {
            ExportSheet(viewModel: viewModel, isPresented: $isShowingExportSheet)
        }
        .popover(isPresented: $showTOC, arrowEdge: .top) {
            TOCView(viewModel: viewModel) { pageIndex in
                NotificationCenter.default.post(name: .orifoldJumpToPageIndex, object: pageIndex)
                showTOC = false
            }
        }
        .alert("contentView.importError.title", isPresented: Binding(
            get: { viewModel.importError != nil },
            set: { if !$0 { viewModel.importError = nil } }
        ), presenting: viewModel.importError) { _ in
            Button("contentView.ok.button") { viewModel.importError = nil }
        } message: { err in
            Text(err.message)
        }
        .alert("contentView.exportError.title", isPresented: Binding(
            get: { viewModel.exportError != nil },
            set: { if !$0 { viewModel.exportError = nil } }
        ), presenting: viewModel.exportError) { _ in
            Button("contentView.ok.button") { viewModel.exportError = nil }
        } message: { err in
            Text(err.message)
        }
        .modifier(ExportSuccessOverlay(viewModel: viewModel))
        .sheet(isPresented: $viewModel.isShowingPasswordPrompt) {
            if let url = viewModel.pendingPasswordURL,
               let pdf = viewModel.pendingPasswordPDF {
                PasswordPromptView(
                    fileName: url.lastPathComponent,
                    pdf: pdf,
                    url: url,
                    viewModel: viewModel
                )
                .id(url)
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var mainToolbar: some ToolbarContent {
        // Leading: add source files
        ToolbarItem(placement: .navigation) {
            Button { openFiles() } label: {
                Label("toolbar.addFiles.label", systemImage: "plus.circle")
            }
            .acceptsImportDrops { providers in
                handleDrop(providers: providers)
            }
            .help("toolbar.addFiles.help")
            .keyboardShortcut("o", modifiers: [.command, .shift])
        }

        // Header navigation: keep document structure near the title.
        ToolbarItem(placement: .navigation) {
            Button { showTOC.toggle() } label: {
                Label("toolbar.contents.label", systemImage: "list.bullet.rectangle.portrait")
            }
            .acceptsImportDrops { providers in
                handleDrop(providers: providers)
            }
            .help("toolbar.contents.help")
        }

        // Center: annotation tools + color swatch
        ToolbarItem(placement: .principal) {
            AnnotationToolPicker(viewModel: viewModel)
                .acceptsImportDrops(isTargeted: $isNavigationDropTargeted, showsHighlight: true) { providers in
                    handleDrop(providers: providers)
                }
        }

        // Trailing: search, document actions, view controls, help
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                viewModel.isReaderMode.toggle()
                if viewModel.isReaderMode {
                    inspectorTab = .comments
                    showInspector = true
                }
            } label: {
                Label("toolbar.readerMode.label", systemImage: viewModel.isReaderMode ? "book.fill" : "book")
            }
            .acceptsImportDrops { providers in
                handleDrop(providers: providers)
            }
            .help(viewModel.isReaderMode ? "toolbar.readerMode.exit.help" : "toolbar.readerMode.enter.help")

            Button { viewModel.isShowingSearch.toggle() } label: {
                Label("toolbar.search.label", systemImage: "magnifyingglass")
            }
            .acceptsImportDrops { providers in
                handleDrop(providers: providers)
            }
            .help("toolbar.search.help")
            .keyboardShortcut("f", modifiers: .command)

            Menu {
                Button("toolbar.export.menuItem.export") {
                    isShowingExportSheet = true
                }
                Divider()
                Button("toolbar.export.menuItem.print") {
                    NotificationCenter.default.post(name: .orifoldPrint, object: nil)
                }
            } label: {
                Label("toolbar.export.label", systemImage: "square.and.arrow.up")
            }
            .acceptsImportDrops { providers in
                handleDrop(providers: providers)
            }
            .help("toolbar.export.help")
            .keyboardShortcut("e", modifiers: [.command, .shift])

            Button { showInspector.toggle() } label: {
                Label("toolbar.inspector.label", systemImage: "sidebar.right")
            }
            .acceptsImportDrops { providers in
                handleDrop(providers: providers)
            }
            .help("toolbar.inspector.help")

            Button {
                viewModel.isNightModeEnabled.toggle()
            } label: {
                Label("toolbar.nightMode.label", systemImage: viewModel.isNightModeEnabled ? "moon.stars.fill" : "moon.stars")
            }
            .acceptsImportDrops { providers in
                handleDrop(providers: providers)
            }
            .help(viewModel.isNightModeEnabled ? "toolbar.nightMode.turnOff.help" : "toolbar.nightMode.turnOn.help")

            Button {
                isShowingNightModeControls.toggle()
            } label: {
                Label("toolbar.nightTone.label", systemImage: "slider.horizontal.3")
            }
            .acceptsImportDrops { providers in
                handleDrop(providers: providers)
            }
            .help("toolbar.nightTone.help")
            .popover(isPresented: $isShowingNightModeControls, arrowEdge: .top) {
                NightModeControls(viewModel: viewModel)
                    .frame(width: 320)
            }

            GuideButton(autoShow: true)
                .acceptsImportDrops { providers in
                    handleDrop(providers: providers)
                }
        }
    }

    // MARK: - Helpers

    private var persistedNightModeSettings: NightModeSettings {
        get {
            NightModeSettings(
                warmth: persistedNightModeWarmth,
                intensity: persistedNightModeIntensity,
                dimming: persistedNightModeDimming
            ).clamped
        }
        nonmutating set {
            let settings = newValue.clamped
            persistedNightModeWarmth = settings.warmth
            persistedNightModeIntensity = settings.intensity
            persistedNightModeDimming = settings.dimming
        }
    }

    private var persistedAppAppearanceModeValue: AppAppearanceMode {
        get {
            AppAppearanceMode(rawValue: persistedAppAppearanceMode) ?? .system
        }
        nonmutating set {
            persistedAppAppearanceMode = newValue.rawValue
        }
    }

    private func applyAppAppearanceMode(_ mode: AppAppearanceMode) {
        NSApp.appearance = mode.nsAppearance
    }

    private func syncPersistedAppAppearanceMode() {
        setAppAppearanceMode(persistedAppAppearanceModeValue)
    }

    private func setAppAppearanceMode(_ mode: AppAppearanceMode) {
        guard viewModel.appAppearanceMode != mode else {
            applyAppAppearanceMode(mode)
            return
        }
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            viewModel.appAppearanceMode = mode
        }
        applyAppAppearanceMode(mode)
    }

    private var workspaceDropOverlay: some View {
        RoundedRectangle(cornerRadius: .dsRadiusLg, style: .continuous)
            .strokeBorder(
                Color.dsAccent.opacity(isWorkspaceDropTargeted ? 0.55 : 0),
                lineWidth: 2
            )
            .background {
                if isWorkspaceDropTargeted {
                    ZStack {
                        Color.dsAccent.opacity(0.08)
                        VStack(spacing: .dsSM) {
                            Image(systemName: "tray.and.arrow.down.fill")
                                .font(.system(size: 34, weight: .light))
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(LinearGradient.dsAccent)
                            Text("contentView.dropOverlay.title")
                                .font(.dsHeadline())
                                .foregroundStyle(Color.dsAccent)
                            Text("contentView.dropOverlay.subtitle")
                                .font(.dsCaption())
                                .foregroundStyle(Color.dsAccent.opacity(0.82))
                        }
                        .padding(.horizontal, .dsXL)
                        .padding(.vertical, .dsLG)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: .dsRadiusLg, style: .continuous))
                    }
                }
            }
            .padding(.dsMD)
            .allowsHitTesting(false)
            .animation(shouldReduceMotion ? nil : .easeInOut(duration: 0.15), value: isWorkspaceDropTargeted)
    }

    private func handleDrop(providers: [NSItemProvider], insertingAfter targetPageRefID: UUID? = nil) -> Bool {
        resolveImportURLs(from: providers, maxCount: maximumImportBatchSize) { urls, wasLimited in
            guard !urls.isEmpty else {
                viewModel.importError = WorkspaceViewModel.ImportError(
                    fileName: "Dropped Files",
                    message: L10n.string("contentView.dropImportError.noSupportedDocument")
                )
                return
            }
            if wasLimited {
                viewModel.importError = WorkspaceViewModel.ImportError(
                    fileName: "Dropped Files",
                    message: importDropProviderLimitMessage
                )
            }
            importFilesWithBatchLimit(
                urls: urls,
                into: viewModel,
                insertingAfter: targetPageRefID,
                sourceName: "Dropped Files"
            )
        }
        return true
    }

    private func openFiles() {
        let panel = NSOpenPanel()
        configureImportOpenPanel(panel)
        if panel.runModal() == .OK {
            importFilesWithBatchLimit(urls: panel.urls, into: viewModel)
        }
    }
}

private struct ReaderModePill: View {
    @Bindable var viewModel: WorkspaceViewModel
    var openNotes: () -> Void
    var onExit: () -> Void
    @State private var isShowingToneControls = false

    var body: some View {
        HStack(spacing: .dsSM) {
            Label("contentView.readerModePill.reader.label", systemImage: "book.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.dsTextPrimary)

            Button {
                isShowingToneControls.toggle()
            } label: {
                Image(systemName: viewModel.isNightModeEnabled ? "moon.stars.fill" : "slider.horizontal.3")
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(viewModel.isNightModeEnabled ? Color.dsAccent : Color.dsTextTertiary)
            .help("contentView.readerModePill.toneControls.help")
            .popover(isPresented: $isShowingToneControls, arrowEdge: .top) {
                NightModeControls(viewModel: viewModel)
                    .frame(width: 320)
            }

            Button(action: openNotes) {
                Image(systemName: "text.bubble")
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Color.dsAccent)
            .help("contentView.readerModePill.openNotes.help")

            Button(action: onExit) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Color.dsTextTertiary)
            .help("toolbar.readerMode.exit.help")
        }
        .padding(.leading, .dsMD)
        .padding(.trailing, .dsSM)
        .padding(.vertical, 7)
        .background(.regularMaterial, in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(Color.dsSeparator, lineWidth: 1)
        }
        .shadow(color: Color.dsTextPrimary.opacity(0.10), radius: 8, x: 0, y: 2)
    }
}

private struct NightModeControls: View {
    @Bindable var viewModel: WorkspaceViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: .dsMD) {
            VStack(alignment: .leading, spacing: .dsSM) {
                Label("contentView.nightModeControls.application.label", systemImage: "macwindow")
                    .font(.dsHeadline())
                Picker("contentView.nightModeControls.applicationAppearance.picker", selection: appAppearanceModeBinding) {
                    ForEach(AppAppearanceMode.allCases) { mode in
                        Label(mode.title, systemImage: mode.systemImage)
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Divider()

            Toggle(isOn: $viewModel.isNightModeEnabled) {
                Label("toolbar.nightMode.label", systemImage: viewModel.isNightModeEnabled ? "moon.stars.fill" : "moon.stars")
                    .font(.dsHeadline())
            }

            HStack(spacing: .dsSM) {
                ForEach(NightModePreset.allCases) { preset in
                    Button {
                        viewModel.isNightModeEnabled = true
                        viewModel.nightModeSettings = preset.settings
                    } label: {
                        Label(preset.title, systemImage: preset.systemImage)
                            .labelStyle(.titleAndIcon)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }

            VStack(alignment: .leading, spacing: .dsSM) {
                nightModeSlider(
                    title: "contentView.nightModeControls.warmth.title",
                    systemImage: "thermometer.sun",
                    value: Binding(
                        get: { viewModel.nightModeSettings.warmth },
                        set: { viewModel.nightModeSettings.warmth = $0 }
                    )
                )
                nightModeSlider(
                    title: "contentView.nightModeControls.tone.title",
                    systemImage: "circle.lefthalf.filled",
                    value: Binding(
                        get: { viewModel.nightModeSettings.intensity },
                        set: { viewModel.nightModeSettings.intensity = $0 }
                    )
                )
                nightModeSlider(
                    title: "contentView.nightModeControls.dimming.title",
                    systemImage: "sun.min",
                    value: Binding(
                        get: { viewModel.nightModeSettings.dimming },
                        set: { viewModel.nightModeSettings.dimming = $0 }
                    )
                )
            }

            HStack {
                Spacer()
                Button("contentView.nightModeControls.reset.button") {
                    viewModel.nightModeSettings = .default
                }
            }
        }
        .padding(.dsLG)
    }

    private var appAppearanceModeBinding: Binding<AppAppearanceMode> {
        Binding(
            get: { viewModel.appAppearanceMode },
            set: { mode in
                setAppAppearanceMode(mode)
            }
        )
    }

    private func setAppAppearanceMode(_ mode: AppAppearanceMode) {
        guard viewModel.appAppearanceMode != mode else { return }
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            viewModel.appAppearanceMode = mode
        }
    }

    private func nightModeSlider(title: LocalizedStringKey, systemImage: String, value: Binding<Double>) -> some View {
        HStack(spacing: .dsSM) {
            Image(systemName: systemImage)
                .frame(width: 18)
                .foregroundStyle(Color.dsTextTertiary)
            Text(title)
                .font(.dsCaption())
                .foregroundStyle(Color.dsTextSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: 78, alignment: .leading)
            Slider(value: value, in: 0...1, step: 0.01)
            Text("\(Int(value.wrappedValue * 100))%")
                .font(.dsCaption())
                .foregroundStyle(Color.dsTextSecondary)
                .monospacedDigit()
                .frame(width: 42, alignment: .trailing)
        }
    }
}

private struct ExportSheet: View {
    @Bindable var viewModel: WorkspaceViewModel
    @Binding var isPresented: Bool
    @State private var selectedFormat: WorkspaceExportFormat = .pdf
    @State private var isProtectionExpanded = false
    @State private var protectWithPassword = false
    @State private var password = ""
    @State private var passwordConfirmation = ""
    @State private var allowsPrinting = true
    @State private var allowsCopying = true
    @State private var lockFormAnswers = false
    @State private var isFormLockExpanded = false
    @State private var reduceFileSize = false
    @State private var isCompressionExpanded = false
    @State private var compressionPreset: PDFCompressionPreset = .balanced
    @State private var sanitizeForSharing = false
    @State private var removesMetadata = false
    @State private var isSanitizeExpanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shouldReduceMotion: Bool {
        reduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private var canProtectSelectedFormat: Bool {
        selectedFormat == .pdf && !viewModel.hasCryptographicSignaturePlacement
    }

    private var passwordMismatch: Bool {
        protectWithPassword &&
            !password.isEmpty &&
            !passwordConfirmation.isEmpty &&
            password != passwordConfirmation
    }

    private var passwordValidationMessage: String? {
        guard protectWithPassword else { return nil }
        if !canProtectSelectedFormat {
            return nil
        }
        if password.isEmpty {
            return L10n.string("contentView.exportSheet.passwordMissing.message")
        }
        if passwordConfirmation.isEmpty {
            return L10n.string("contentView.exportSheet.confirmationMissing.message")
        }
        if passwordMismatch {
            return L10n.string("contentView.exportSheet.passwordMismatch.message")
        }
        return nil
    }

    private var canExport: Bool {
        guard protectWithPassword && canProtectSelectedFormat else { return true }
        return !password.isEmpty && password == passwordConfirmation
    }

    var body: some View {
        VStack(alignment: .leading, spacing: .dsLG) {
            Text("contentView.exportSheet.title")
                .font(.dsTitle())
                .foregroundStyle(Color.dsTextPrimary)

            Picker("contentView.exportSheet.format.picker", selection: $selectedFormat) {
                ForEach(WorkspaceExportFormat.allCases) { format in
                    Text(format.menuTitle).tag(format)
                }
            }
            .pickerStyle(.menu)

            VStack(alignment: .leading, spacing: .dsSM) {
                DisclosureGroup(isExpanded: $isProtectionExpanded) {
                    VStack(alignment: .leading, spacing: .dsSM) {
                        SecureField("contentView.exportSheet.password.field", text: $password)
                            .textFieldStyle(.roundedBorder)
                            .disabled(!protectWithPassword || !canProtectSelectedFormat)
                        SecureField("contentView.exportSheet.confirmPassword.field", text: $passwordConfirmation)
                            .textFieldStyle(.roundedBorder)
                            .disabled(!protectWithPassword || !canProtectSelectedFormat)

                        Toggle("contentView.exportSheet.allowPrinting.toggle", isOn: $allowsPrinting)
                            .disabled(!protectWithPassword || !canProtectSelectedFormat)
                        Toggle("contentView.exportSheet.allowCopying.toggle", isOn: $allowsCopying)
                            .disabled(!protectWithPassword || !canProtectSelectedFormat)

                        if let passwordValidationMessage {
                            Text(passwordValidationMessage)
                                .font(.dsCaption())
                                .foregroundStyle(Color.dsAnnotationCoral)
                        }
                    }
                    .padding(.top, .dsSM)
                } label: {
                    Toggle("contentView.exportSheet.protectWithPassword.toggle", isOn: Binding(
                        get: { protectWithPassword },
                        set: { newValue in
                            protectWithPassword = newValue && canProtectSelectedFormat
                            if protectWithPassword {
                                isProtectionExpanded = true
                            }
                        }
                    ))
                    .disabled(!canProtectSelectedFormat)
                }

                if selectedFormat != .pdf {
                    Text("contentView.exportSheet.passwordProtectionPdfOnly.message")
                        .font(.dsCaption())
                        .foregroundStyle(Color.dsTextTertiary)
                } else if viewModel.hasCryptographicSignaturePlacement {
                    Text("contentView.exportSheet.passwordProtectionUnavailableSigned.message")
                        .font(.dsCaption())
                        .foregroundStyle(Color.dsTextTertiary)
                }
            }
            .animation(shouldReduceMotion ? nil : .easeInOut(duration: 0.16), value: isProtectionExpanded)
            .animation(shouldReduceMotion ? nil : .easeInOut(duration: 0.16), value: protectWithPassword)
            .onChange(of: viewModel.hasCryptographicSignaturePlacement) { _, hasSignature in
                guard hasSignature else { return }
                protectWithPassword = false
                isProtectionExpanded = false
                sanitizeForSharing = false
                isSanitizeExpanded = false
            }
            .onChange(of: selectedFormat) { _, _ in
                if !canProtectSelectedFormat {
                    protectWithPassword = false
                }
                if selectedFormat != .pdf {
                    reduceFileSize = false
                    sanitizeForSharing = false
                }
            }

            DisclosureGroup(isExpanded: $isCompressionExpanded) {
                Picker("contentView.exportSheet.compressionPreset.picker", selection: $compressionPreset) {
                    ForEach(PDFCompressionPreset.allCases) { preset in
                        Text(preset.label).tag(preset)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(!reduceFileSize || selectedFormat != .pdf)
                .padding(.top, .dsSM)

                if selectedFormat != .pdf {
                    Text("contentView.exportSheet.fileSizeReductionPdfOnly.message")
                        .font(.dsCaption())
                        .foregroundStyle(Color.dsTextTertiary)
                }
            } label: {
                Toggle("contentView.exportSheet.reduceFileSize.toggle", isOn: Binding(
                    get: { reduceFileSize },
                    set: { newValue in
                        reduceFileSize = newValue && selectedFormat == .pdf
                        if reduceFileSize {
                            isCompressionExpanded = true
                        }
                    }
                ))
                .disabled(selectedFormat != .pdf)
            }
            .animation(shouldReduceMotion ? nil : .easeInOut(duration: 0.16), value: isCompressionExpanded)
            .animation(shouldReduceMotion ? nil : .easeInOut(duration: 0.16), value: reduceFileSize)

            if selectedFormat == .pdf {
                DisclosureGroup(isExpanded: $isSanitizeExpanded) {
                    VStack(alignment: .leading, spacing: .dsSM) {
                        Toggle("contentView.exportSheet.removeMetadata.toggle", isOn: $removesMetadata)
                            .disabled(!sanitizeForSharing)
                        Text("contentView.exportSheet.sanitizeStripsDetail.message")
                            .font(.dsCaption())
                            .foregroundStyle(Color.dsTextTertiary)
                    }
                    .padding(.top, .dsSM)
                } label: {
                    Toggle("contentView.exportSheet.sanitizeForSharing.toggle", isOn: Binding(
                        get: { sanitizeForSharing },
                        set: { newValue in
                            sanitizeForSharing = newValue && !viewModel.hasCryptographicSignaturePlacement
                            if sanitizeForSharing {
                                isSanitizeExpanded = true
                            }
                        }
                    ))
                    .disabled(viewModel.hasCryptographicSignaturePlacement)
                }
                .animation(shouldReduceMotion ? nil : .easeInOut(duration: 0.16), value: isSanitizeExpanded)
                .animation(shouldReduceMotion ? nil : .easeInOut(duration: 0.16), value: sanitizeForSharing)

                if viewModel.hasCryptographicSignaturePlacement {
                    Text("contentView.exportSheet.sanitizeUnavailableSigned.message")
                        .font(.dsCaption())
                        .foregroundStyle(Color.dsTextTertiary)
                }
            }

            if viewModel.hasFillableFormFields && selectedFormat == .pdf {
                DisclosureGroup(isExpanded: $isFormLockExpanded) {
                    Toggle("contentView.exportSheet.lockFormAnswers.toggle", isOn: $lockFormAnswers)
                        .padding(.top, .dsSM)
                } label: {
                    Text("contentView.exportSheet.lockFormAnswers.toggle")
                        .font(.dsBody())
                        .foregroundStyle(Color.dsTextPrimary)
                }
                .animation(shouldReduceMotion ? nil : .easeInOut(duration: 0.16), value: isFormLockExpanded)
                .onAppear {
                    lockFormAnswers = true
                }
            }

            HStack {
                Spacer()
                Button("contentView.exportSheet.cancel.button") {
                    isPresented = false
                }
                Button("contentView.exportSheet.export.button") {
                    export()
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.dsAccent)
                .disabled(!canExport)
            }
        }
        .padding(.dsXL)
        .frame(width: 380)
        .background(Color.dsSurface)
    }

    private func export() {
        var options = WorkspaceExportOptions()
        if protectWithPassword && canProtectSelectedFormat {
            options.encryption = PDFEncryptionOptions(
                userPassword: password,
                ownerPassword: "Orifold-owner-\(UUID().uuidString)",
                allowsPrinting: allowsPrinting,
                allowsCopying: allowsCopying
            )
        }
        options.lockFormAnswers = selectedFormat == .pdf && viewModel.hasFillableFormFields && lockFormAnswers
        if selectedFormat == .pdf && reduceFileSize {
            options.compressionPreset = compressionPreset
        }
        if selectedFormat == .pdf && sanitizeForSharing {
            options.sanitization = PDFSanitizationOptions(removesMetadata: removesMetadata)
        }
        if viewModel.exportWorkspace(as: selectedFormat, options: options) {
            isPresented = false
        }
    }
}

private struct WorkspaceOperationProgressView: View {
    @Bindable var progress: WorkspaceOperationProgress
    var cancel: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isBreathing = false

    private var shouldReduceMotion: Bool {
        reduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    var body: some View {
        HStack(spacing: .dsMD) {
            ZStack {
                Circle()
                    .stroke(Color.dsAccent.opacity(0.16), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: max(0.08, progress.fraction))
                    .stroke(
                        LinearGradient.dsAccent,
                        style: StrokeStyle(lineWidth: 5, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(shouldReduceMotion ? nil : .easeInOut(duration: 0.18), value: progress.fraction)
                Image(systemName: "tray.and.arrow.down.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(LinearGradient.dsAccent)
                    .scaleEffect(isBreathing && !shouldReduceMotion ? 1.08 : 1)
            }
            .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(progress.title)
                    .font(.dsCaption())
                    .foregroundStyle(Color.dsTextPrimary)
                if !progress.detail.isEmpty {
                    Text(progress.detail)
                        .font(.dsCaption())
                        .foregroundStyle(Color.dsTextSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                ProgressView(value: progress.fraction)
                    .progressViewStyle(.linear)
                    .frame(width: 190)
            }
            if progress.isCancellable {
                Button("contentView.operationProgress.cancel.button", action: cancel)
                    .font(.dsCaption())
            }
        }
        .padding(.horizontal, .dsLG)
        .padding(.vertical, .dsSM)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: .dsRadiusSm, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: .dsRadiusSm, style: .continuous)
                .strokeBorder(Color.dsSeparator, lineWidth: 1)
        }
        .shadow(color: Color.dsAccent.opacity(0.18), radius: 18, x: 0, y: 8)
        .onAppear {
            guard !shouldReduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.95).repeatForever(autoreverses: true)) {
                isBreathing = true
            }
        }
    }
}

private struct AnnotationToolPicker: View {
    @Bindable var viewModel: WorkspaceViewModel
    @State private var hoveredTool: AnnotationTool?
    @State private var tooltipTool: AnnotationTool?
    @State private var tooltipTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selectionNamespace

    private var shouldReduceMotion: Bool {
        reduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    // Keep the highest-frequency creation tools up front as distinct services,
    // then selection, text markup (+ eraser), and free-form page content.
    private let toolGroups: [[AnnotationTool]] = [
        [.editText],
        [.signature, .stamp],
        [.none],
        [.comment, .commentRegion],
        [.highlight, .underline, .strikeout, .eraser],
        [.note, .ink]
    ]

    private var visibleToolGroups: [[AnnotationTool]] {
        toolGroups
            .map { group in
                viewModel.isReaderMode ? group.filter(\.isReaderModeAllowed) : group
            }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(visibleToolGroups.indices, id: \.self) { groupIndex in
                if groupIndex > 0 {
                    groupDivider
                }
                ForEach(visibleToolGroups[groupIndex]) { tool in
                    toolButton(tool, shouldReduceMotion: shouldReduceMotion)
                }
            }

            if viewModel.currentTool.isColorable {
                groupDivider
                AnnotationColorButton(viewModel: viewModel)
                    .transition(shouldReduceMotion ? .identity : .scale(scale: 0.85).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(Color.dsSeparator, lineWidth: 1)
        )
        .shadow(color: Color.dsTextPrimary.opacity(0.10), radius: 8, x: 0, y: 2)
        .animation(shouldReduceMotion ? nil : .spring(response: 0.31, dampingFraction: 0.79), value: viewModel.currentTool)
        .overlayPreferenceValue(ToolBoundsKey.self) { anchors in
            GeometryReader { proxy in
                if let tool = tooltipTool, let anchor = anchors[tool] {
                    let rect = proxy[anchor]
                    let minX: CGFloat = 4
                    let maxX = max(minX, proxy.size.width - ToolTipBubble.width - 4)
                    let x = min(max(rect.midX - ToolTipBubble.width / 2, minX), maxX)
                    ToolTipBubble(tool: tool)
                        .offset(x: x, y: rect.maxY + 8)
                        .transition(.opacity)
                }
            }
            .allowsHitTesting(false)
        }
        .animation(shouldReduceMotion ? nil : .easeOut(duration: 0.12), value: tooltipTool)
        .onChange(of: hoveredTool) { _, newValue in
            tooltipTask?.cancel()
            guard let newValue else {
                tooltipTool = nil
                return
            }
            if tooltipTool != nil {
                // Tooltip already visible — track the pointer between buttons.
                tooltipTool = newValue
            } else {
                tooltipTask = Task {
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    guard !Task.isCancelled else { return }
                    if hoveredTool == newValue {
                        tooltipTool = newValue
                    }
                }
            }
        }
    }

    private var groupDivider: some View {
        Rectangle()
            .fill(Color.dsSeparator)
            .frame(width: 1, height: 16)
            .padding(.horizontal, 5)
    }

    @ViewBuilder
    private func toolButton(_ tool: AnnotationTool, shouldReduceMotion: Bool) -> some View {
        let isSelected = viewModel.currentTool == tool
        let isHovered = hoveredTool == tool
        let accent = toolAccent(for: tool)

        Button {
            select(tool)
        } label: {
            ZStack {
                if isSelected {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(accent)
                        .matchedGeometryEffect(id: "selectedTool", in: selectionNamespace)
                }

                toolIcon(tool, isSelected: isSelected)
                    .foregroundStyle(isSelected ? Color.dsSurface : Color.dsTextSecondary)
            }
            .frame(width: 28, height: 28)
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(ToolButtonStyle(isHovered: isHovered, isSelected: isSelected, hoverFill: toolAccentSoft(for: tool), reduceMotion: shouldReduceMotion))
        .anchorPreference(key: ToolBoundsKey.self, value: .bounds) { [tool: $0] }
        .onHover { isHovered in
            if isHovered {
                hoveredTool = tool
            } else if hoveredTool == tool {
                hoveredTool = nil
            }
        }
        .accessibilityLabel(tool.label)
        .accessibilityHint(tool.helpText)
    }

    private func toolAccent(for tool: AnnotationTool) -> Color {
        switch tool {
        case .editText:
            return Color.dsEditTextAccent
        case .signature, .stamp:
            return Color.dsSignatureAccent
        default:
            return Color.dsAccent
        }
    }

    private func toolAccentSoft(for tool: AnnotationTool) -> Color {
        switch tool {
        case .editText:
            return Color.dsEditTextHover
        case .signature, .stamp:
            return Color.dsSignatureHover
        default:
            return Color.dsAccentSoft
        }
    }

    private func select(_ tool: AnnotationTool) {
        guard !viewModel.isReaderMode || tool.isReaderModeAllowed else {
            viewModel.currentTool = tool
            return
        }
        if tool == .signature {
            viewModel.isShowingSignaturePalette = true
            viewModel.isShowingStampPalette = false
        } else if tool == .stamp {
            viewModel.isShowingStampPalette = true
            viewModel.isShowingSignaturePalette = false
        } else {
            viewModel.isShowingSignaturePalette = false
            viewModel.isShowingStampPalette = false
        }
        viewModel.currentTool = tool
        if tool == .comment {
            NotificationCenter.default.post(name: .orifoldCreateCommentFromSelection, object: nil)
        }
    }

    @ViewBuilder
    private func toolIcon(_ tool: AnnotationTool, isSelected: Bool) -> some View {
        if tool == .highlight {
            HighlightGlyph(isSelected: isSelected)
        } else {
            Image(systemName: tool.iconName)
                .font(.system(size: tool == .none ? 13 : 14, weight: .semibold))
                .symbolRenderingMode(.monochrome)
        }
    }
}

private struct ToolBoundsKey: PreferenceKey {
    static var defaultValue: [AnnotationTool: Anchor<CGRect>] = [:]

    static func reduce(
        value: inout [AnnotationTool: Anchor<CGRect>],
        nextValue: () -> [AnnotationTool: Anchor<CGRect>]
    ) {
        value.merge(nextValue()) { $1 }
    }
}

private struct ToolTipBubble: View {
    static let width: CGFloat = 190

    var tool: AnnotationTool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(tool.label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.dsTextPrimary)
            Text(tool.helpText)
                .font(.system(size: 10))
                .foregroundStyle(Color.dsTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: Self.width - 20, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.dsSeparator, lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.16), radius: 10, x: 0, y: 4)
        .accessibilityHidden(true)
    }
}

private struct ToolButtonStyle: ButtonStyle {
    var isHovered: Bool
    var isSelected: Bool = false
    var hoverFill: Color = Color.dsAccentSoft
    var reduceMotion: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                if isHovered && !isSelected {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(hoverFill)
                }
            }
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovered)
    }
}

private struct HighlightGlyph: View {
    var isSelected: Bool

    var body: some View {
        ZStack(alignment: .bottom) {
            Image(systemName: "highlighter")
                .font(.system(size: 13, weight: .semibold))
                .symbolRenderingMode(.monochrome)

            Capsule()
                .fill(isSelected ? Color.white.opacity(0.65) : Color.dsHighlightYellow)
                .frame(width: 15, height: 2.5)
                .offset(y: 2.5)
        }
        .frame(width: 17, height: 16)
    }
}

// MARK: - Annotation color picker button

private struct AnnotationColorButton: View {
    @Bindable var viewModel: WorkspaceViewModel
    @State private var showPalette = false
    @State private var isHovered = false

    private var displayColor: Color {
        viewModel.currentTool.usesInkColor
            ? Color(nsColor: viewModel.inkColor)
            : Color(nsColor: viewModel.annotationColor)
    }

    var body: some View {
        Button { showPalette.toggle() } label: {
            ZStack {
                Circle()
                    .fill(displayColor)
                    .frame(width: 18, height: 18)
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.72), lineWidth: 1))
                    .shadow(color: Color.black.opacity(0.18), radius: 2, x: 0, y: 1)
            }
            .frame(width: 28, height: 28)
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(ToolButtonStyle(isHovered: isHovered || showPalette))
        .onHover { isHovered = $0 }
        .help("contentView.annotationColorButton.help")
        .popover(isPresented: $showPalette, arrowEdge: .bottom) {
            AnnotationPalettePopover(viewModel: viewModel)
        }
    }
}

private struct AnnotationPalettePopover: View {
    @Bindable var viewModel: WorkspaceViewModel

    var body: some View {
        HStack(spacing: .dsMD) {
            ForEach(Color.annotationSwatches.indices, id: \.self) { i in
                let (swiftUI, ns) = Color.annotationSwatches[i]
                let isSelected = isCurrentColor(ns)
                Button {
                    if viewModel.currentTool.usesInkColor {
                        viewModel.inkColor = ns
                    } else {
                        viewModel.annotationColor = ns
                    }
                } label: {
                    Circle()
                        .fill(swiftUI)
                        .frame(width: 26, height: 26)
                        .overlay {
                            Circle()
                                .strokeBorder(
                                    isSelected ? Color.dsTextPrimary : Color.dsSeparator,
                                    lineWidth: isSelected ? 2 : 1
                                )
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.dsMD)
        .background(Color.dsSurface)
    }

    private func isCurrentColor(_ ns: NSColor) -> Bool {
        let current = viewModel.currentTool.usesInkColor
            ? viewModel.inkColor : viewModel.annotationColor
        return current.isEqual(to: ns)
    }
}

// MARK: - Shared drop helper

let maximumImportBatchSize = 50
let importDropContentTypes = WorkspaceDocument.importableContentTypes + [.fileURL, .url]
var importBatchPanelMessage: String { L10n.string("contentView.importBatchPanel.message") }
var importBatchLimitMessage: String { L10n.string("contentView.importBatchLimit.message") }
var importDropProviderLimitMessage: String { L10n.string("contentView.importDropProviderLimit.message") }

func configureImportOpenPanel(_ panel: NSOpenPanel) {
    panel.allowsMultipleSelection = true
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowedContentTypes = WorkspaceDocument.importableContentTypes
    panel.message = importBatchPanelMessage
}

func importFilesWithBatchLimit(
    urls: [URL],
    into viewModel: WorkspaceViewModel,
    insertingAfter targetPageRefID: UUID? = nil,
    sourceName: String = "Selected Files"
) {
    let batch = limitedImportBatch(from: urls)
    if batch.wasLimited {
        viewModel.importError = WorkspaceViewModel.ImportError(
            fileName: sourceName,
            message: importBatchLimitMessage
        )
    }
    guard !batch.urls.isEmpty else { return }
    viewModel.importFiles(urls: batch.urls, insertingAfter: targetPageRefID)
}

func limitedImportBatch(from urls: [URL]) -> (urls: [URL], wasLimited: Bool) {
    (Array(urls.prefix(maximumImportBatchSize)), urls.count > maximumImportBatchSize)
}

func resolveImportURLs(from providers: [NSItemProvider], maxCount: Int = maximumImportBatchSize, completion: @escaping ([URL], Bool) -> Void) {
    let effectiveMaxCount = max(0, maxCount)
    guard effectiveMaxCount > 0 else {
        DispatchQueue.main.async {
            completion([], !providers.isEmpty)
        }
        return
    }

    var resolvedURLs: [URL] = []
    var seenURLs: Set<String> = []
    var nextProviderIndex = 0

    func resolveNextProvider() {
        guard resolvedURLs.count < effectiveMaxCount else {
            completion(resolvedURLs, nextProviderIndex < providers.count)
            return
        }
        guard nextProviderIndex < providers.count else {
            completion(resolvedURLs, false)
            return
        }

        let provider = providers[nextProviderIndex]
        nextProviderIndex += 1
        loadImportURL(from: provider) { url in
            if let url, isSupportedImportURL(url) {
                let key = url.fileURLIdentityKey
                if seenURLs.insert(key).inserted {
                    resolvedURLs.append(url)
                }
            }
            DispatchQueue.main.async {
                resolveNextProvider()
            }
        }
    }

    DispatchQueue.main.async {
        resolveNextProvider()
    }
}

private func loadImportURL(from provider: NSItemProvider, completion: @escaping (URL?) -> Void) {
    loadProviderURL(from: provider, type: .fileURL) { fileURL in
        if let fileURL {
            completion(fileURL)
            return
        }

        loadProviderURL(from: provider, type: .url) { url in
            if let url {
                completion(url)
                return
            }

            loadImportFileRepresentation(from: provider, completion: completion)
        }
    }
}

private func loadProviderURL(from provider: NSItemProvider, type: UTType, completion: @escaping (URL?) -> Void) {
    guard provider.hasItemConformingToTypeIdentifier(type.identifier) else {
        completion(nil)
        return
    }

    provider.loadItem(forTypeIdentifier: type.identifier, options: nil) { item, _ in
        guard let url = urlFromProviderItem(item), url.isFileURL else {
            completion(nil)
            return
        }
        completion(durableDroppedImportURL(from: url))
    }
}

private func loadImportFileRepresentation(from provider: NSItemProvider, completion: @escaping (URL?) -> Void) {
    guard let type = supportedImportContentType(from: provider) else {
        completion(nil)
        return
    }

    provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { url, _ in
        guard let url else {
            completion(nil)
            return
        }
        completion(copyTemporaryDropFile(from: url, contentType: type))
    }
}

private func supportedImportContentType(from provider: NSItemProvider) -> UTType? {
    for identifier in provider.registeredTypeIdentifiers {
        guard let type = UTType(identifier),
              WorkspaceDocument.importableContentTypes.contains(where: { type.conforms(to: $0) }) else {
            continue
        }
        return type
    }

    return WorkspaceDocument.importableContentTypes.first {
        provider.hasItemConformingToTypeIdentifier($0.identifier)
    }
}

private func urlFromProviderItem(_ item: NSSecureCoding?) -> URL? {
    if let url = item as? URL { return url }
    if let url = item as? NSURL { return url as URL }
    if let data = item as? Data {
        return URL(dataRepresentation: data, relativeTo: nil)
    }
    if let string = item as? String {
        if let url = URL(string: string), url.isFileURL {
            return url
        }
        return URL(fileURLWithPath: string)
    }
    return nil
}

private func copyTemporaryDropFile(from url: URL, contentType: UTType) -> URL? {
    let existingExtension = url.pathExtension
    let extensionHint = isSupportedImportExtension(existingExtension)
        ? existingExtension
        : preferredImportExtension(for: contentType, fallback: existingExtension)
    let name = url.deletingPathExtension().lastPathComponent.isEmpty
        ? UUID().uuidString
        : url.deletingPathExtension().lastPathComponent
    let destination = FileManager.default.temporaryDirectory
        .appendingPathComponent("OrifoldDrops", isDirectory: true)
        .appendingPathComponent("\(name)-\(UUID().uuidString).\(extensionHint)")

    do {
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: url, to: destination)
        return destination
    } catch {
        return nil
    }
}

private func durableDroppedImportURL(from url: URL) -> URL? {
    guard isTemporaryDropProviderURL(url) else { return url }
    let resourceType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType
    let contentType = resourceType ?? UTType(filenameExtension: url.pathExtension) ?? .data
    return copyTemporaryDropFile(from: url, contentType: contentType) ?? url
}

private func isTemporaryDropProviderURL(_ url: URL) -> Bool {
    let standardizedPath = url.standardizedFileURL.path
    let temporaryRoots = [
        FileManager.default.temporaryDirectory.standardizedFileURL.path,
        URL(fileURLWithPath: NSTemporaryDirectory()).standardizedFileURL.path,
        "/private/var/folders/",
        "/var/folders/",
    ]
    return temporaryRoots.contains { root in
        standardizedPath == root || standardizedPath.hasPrefix(root.hasSuffix("/") ? root : "\(root)/")
    }
}

func isSupportedImportURL(_ url: URL) -> Bool {
    guard url.isFileURL else { return false }
    if let resourceType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType,
       WorkspaceDocument.importableContentTypes.contains(where: { resourceType.conforms(to: $0) }) {
        return true
    }
    guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
    return WorkspaceDocument.importableContentTypes.contains { type.conforms(to: $0) }
}

private func isSupportedImportExtension(_ pathExtension: String) -> Bool {
    guard !pathExtension.isEmpty,
          let type = UTType(filenameExtension: pathExtension) else {
        return false
    }
    return WorkspaceDocument.importableContentTypes.contains { type.conforms(to: $0) }
}

private func preferredImportExtension(for contentType: UTType, fallback: String) -> String {
    if let preferred = contentType.preferredFilenameExtension,
       isSupportedImportExtension(preferred) {
        return preferred
    }
    if contentType.conforms(to: .pdf) { return "pdf" }
    if contentType.conforms(to: .html) { return "html" }
    if contentType.conforms(to: .rtf) { return "rtf" }
    if contentType.conforms(to: .json) { return "json" }
    if contentType.conforms(to: .xml) { return "xml" }
    if contentType.conforms(to: .image) { return "png" }
    if contentType.conforms(to: .plainText) || contentType.conforms(to: .text) { return "txt" }
    return fallback.isEmpty ? "dat" : fallback
}

private struct DocumentCommentsIndicator: View {
    var count: Int
    var action: () -> Void

    var body: some View {
        if count > 0 {
            Button(action: action) {
                HStack(spacing: .dsXS) {
                    Image(systemName: "text.bubble.fill")
                        .font(.system(size: 12, weight: .semibold))
                    Text("\(count)")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(Color.dsTextPrimary)
                .padding(.horizontal, .dsSM)
                .frame(height: 30)
                .background(.regularMaterial, in: Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(Color.dsAccent.opacity(0.55), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .help(count == 1 ? L10n.string("contentView.viewComments.one") : L10n.format("contentView.viewComments.other", count))
            .accessibilityLabel(count == 1 ? L10n.string("contentView.viewComments.one") : L10n.format("contentView.viewComments.other", count))
            .transition(.opacity.combined(with: .scale(scale: 0.96)))
        }
    }
}

private extension Array where Element == URL {
    func uniquedByFileURL() -> [URL] {
        var seen: Set<String> = []
        return filter { url in
            seen.insert(url.fileURLIdentityKey).inserted
        }
    }
}

private extension URL {
    var fileURLIdentityKey: String {
        isFileURL ? standardizedFileURL.path : absoluteString
    }
}

private extension View {
    func acceptsImportDrops(
        isTargeted: Binding<Bool>? = nil,
        showsHighlight: Bool = false,
        perform: @escaping ([NSItemProvider]) -> Bool
    ) -> some View {
        modifier(ImportDropTargetModifier(
            isTargeted: isTargeted,
            showsHighlight: showsHighlight,
            perform: perform
        ))
    }
}

private struct ImportDropTargetModifier: ViewModifier {
    var isTargeted: Binding<Bool>?
    var showsHighlight: Bool
    var perform: ([NSItemProvider]) -> Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shouldReduceMotion: Bool {
        reduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .overlay {
                if showsHighlight, isTargeted?.wrappedValue == true {
                    RoundedRectangle(cornerRadius: .dsRadiusLg, style: .continuous)
                        .strokeBorder(Color.dsAccent.opacity(0.65), lineWidth: 1.5)
                        .background(Color.dsAccent.opacity(0.08), in: RoundedRectangle(cornerRadius: .dsRadiusLg, style: .continuous))
                        .allowsHitTesting(false)
                }
            }
            .animation(shouldReduceMotion ? nil : .easeInOut(duration: 0.15), value: isTargeted?.wrappedValue ?? false)
            .onDrop(
                of: importDropContentTypes,
                isTargeted: isTargeted,
                perform: perform
            )
    }
}
