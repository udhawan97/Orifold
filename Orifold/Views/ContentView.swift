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
    // Read so SwiftUI re-invokes `body` when the app language changes.
    @Environment(\.locale) private var locale

    private var fileName: String { success.url.lastPathComponent }
    private var folderName: String {
        let name = success.url.deletingLastPathComponent().lastPathComponent
        return name.isEmpty ? success.url.deletingLastPathComponent().path : name
    }
    private var hasFolderPath: Bool { !folderName.isEmpty }

    var body: some View {
        let _ = locale
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

                    Text(L10n.string("contentView.exportSuccess.pdfSaved.title"))
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
                            Text(L10n.string("contentView.exportSuccess.savedTo.label"))
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
                        Text(L10n.string("contentView.exportSuccess.finderFailed.message"))
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
                        Text(L10n.string("contentView.showInFinder.button"))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                    Button {
                        onDone()
                    } label: {
                        Text(L10n.string("contentView.done.button"))
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
            .accessibilityLabel(Text(L10n.string("contentView.exportSuccess.pdfSaved.title")))
        }
    }
}

/// Isolated from `ContentView`'s modifier chain so its `onAppear`/`onChange`/`onDisappear`
/// closures don't add to that chain's already-heavy type-checking cost.
private struct RecentsLifecycleModifier: ViewModifier {
    let fileURL: URL?
    let isEmpty: Bool
    let onOpen: () -> Void
    let onClose: () -> Void

    func body(content: Content) -> some View {
        content
            .onAppear(perform: onOpen)
            .onChange(of: fileURL) { _, _ in onOpen() }
            .onChange(of: isEmpty) { _, nowEmpty in
                if !nowEmpty { onOpen() }
            }
            .onDisappear(perform: onClose)
    }
}

struct ContentView: View {
    var document: WorkspaceDocument
    var fileURL: URL?
    @State private var viewModel: WorkspaceViewModel
    @State private var showInspector = false
    @State private var inspectorTab: InspectorView.Tab = .info
    @State private var showTOC = false
    @State private var isShowingExportSheet = false
    @State private var isWorkspaceDropTargeted = false
    @State private var isNavigationDropTargeted = false
    @State private var isConfirmingOverflowDelete = false
    @State private var isConfirmingDiscardClose = false
    @State private var isShowingDocumentComfortPopover = false
    @State private var isShowingShortcutsCheatSheet = false
    @State private var isShowingShortcutsFirstRun = false
    @State private var isShowingGuide = false
    @State private var isShowingMoreMenu = false
    // Set when a More-menu row wants to open a surface that presents its own popover/dialog.
    // We stash the intent, let the More popover finish dismissing, then present the target on
    // the next runloop — presenting a popover directly out of another popover's button is what
    // makes macOS drop/flicker it.
    @State private var pendingMoreRoute: MoreRoute?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @AppStorage("Orifold.hasSeenGuidePopover") private var hasSeenGuidePopover = false
    @AppStorage("Orifold.hasSeenShortcutsHint") private var hasSeenShortcutsHint = false
    @AppStorage("orifoldAppAppearanceMode") private var persistedAppAppearanceMode = AppAppearanceMode.system.rawValue
    @AppStorage("orifoldDocumentComfortSettings") private var persistedDocumentComfortSettingsData = Data()
    @Environment(\.undoManager) private var undoManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // `.popover` content on macOS doesn't inherit the `.environment(\.locale:)`
    // override applied at the scene root — it resets to the system default —
    // so it must be re-applied explicitly to each popover's presented content.
    @EnvironmentObject private var languageManager: LanguageManager

    private var shouldReduceMotion: Bool {
        reduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || viewModel.documentComfortSettings.reduceAnimations
    }

    init(document: WorkspaceDocument, fileURL: URL? = nil) {
        self.document = document
        self.fileURL = fileURL
        _viewModel = State(initialValue: WorkspaceViewModel(document: document))
    }

    private func recordRecentOpenIfNeeded() {
        guard let fileURL, !viewModel.memberDocuments.isEmpty else { return }
        RecentsStore.shared.recordOpen(url: fileURL)
    }

    private func recordRecentVisitOnClose() {
        guard let fileURL, !viewModel.memberDocuments.isEmpty else { return }
        RecentsStore.shared.recordVisit(
            url: fileURL,
            pageCount: viewModel.pageCount,
            currentPage: max(0, viewModel.currentPageNumber - 1),
            combinedPDF: viewModel.combinedPDF
        )
    }

    // Undo/Redo availability drives the toolbar buttons off the view model's own undo manager
    // (the one every edit registers on), and reads `structureRevision` so the buttons re-evaluate
    // after AppKit-driven object-edit commits, which don't otherwise trigger a SwiftUI refresh —
    // that gap is what left Undo/Redo stuck disabled after a move/resize/delete on the canvas.
    private var undoAvailable: Bool {
        _ = viewModel.structureRevision
        return viewModel.undoManager?.canUndo == true
    }

    private var redoAvailable: Bool {
        _ = viewModel.structureRevision
        return viewModel.undoManager?.canRedo == true
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
                        .overlay {
                            if viewModel.documentComfortSettings.focusMode {
                                Color.black.opacity(0.35).allowsHitTesting(false)
                            }
                        }
                        .animation(shouldReduceMotion ? nil : .easeInOut(duration: 0.2), value: viewModel.documentComfortSettings.focusMode)
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
                                .overlay {
                                    if viewModel.documentComfortSettings.focusMode {
                                        Color.black.opacity(0.35).allowsHitTesting(false)
                                    }
                                }
                        }
                    }
                    .animation(shouldReduceMotion ? nil : .easeInOut(duration: 0.18), value: showInspector)
                    .animation(shouldReduceMotion ? nil : .easeInOut(duration: 0.2), value: viewModel.documentComfortSettings.focusMode)
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
        .modifier(RecentsLifecycleModifier(
            fileURL: fileURL,
            isEmpty: viewModel.memberDocuments.isEmpty,
            onOpen: recordRecentOpenIfNeeded,
            onClose: recordRecentVisitOnClose
        ))
        .background(WorkspaceWindowAccessor { viewModel.hostingWindow = $0 })
        .overlay(alignment: .bottomTrailing) {
            if !viewModel.memberDocuments.isEmpty {
                PetOverlay(isChromeBusy: viewModel.operationProgress.isActive)
                    .padding(.gamiEdgeInset)
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
            viewModel.documentComfortSettings = persistedDocumentComfortSettings
            maybeAutoShowOnboarding()
        }
        .onChange(of: undoManager) { _, um in viewModel.undoManager = um }
        .onChange(of: viewModel.appAppearanceMode) { _, mode in
            persistedAppAppearanceModeValue = mode
            applyAppAppearanceMode(mode)
        }
        .onChange(of: persistedAppAppearanceMode) { _, _ in
            syncPersistedAppAppearanceMode()
        }
        .onChange(of: viewModel.documentComfortSettings) { _, settings in
            persistedDocumentComfortSettings = settings
        }
        .onChange(of: viewModel.selectedCommentID) { _, newValue in
            guard newValue != nil else { return }
            inspectorTab = .comments
            showInspector = true
        }
        .popover(isPresented: $viewModel.isShowingSearch, arrowEdge: .top) {
            SearchView(viewModel: viewModel)
                .environmentObject(languageManager)
                .environment(\.locale, languageManager.effectiveLocale)
        }
        .popover(isPresented: $viewModel.isShowingSignaturePalette, arrowEdge: .top) {
            SignaturePalette(viewModel: viewModel)
                .environmentObject(languageManager)
                .environment(\.locale, languageManager.effectiveLocale)
        }
        .popover(isPresented: $viewModel.isShowingStampPalette, arrowEdge: .top) {
            StampPalette(viewModel: viewModel)
                .environmentObject(languageManager)
                .environment(\.locale, languageManager.effectiveLocale)
        }
        .sheet(isPresented: $isShowingExportSheet) {
            ExportSheet(viewModel: viewModel, isPresented: $isShowingExportSheet)
                .environmentObject(languageManager)
                .environment(\.locale, languageManager.effectiveLocale)
        }
        .sheet(isPresented: $viewModel.isShowingBarcodeComposer) {
            BarcodeComposerView(viewModel: viewModel)
                .environmentObject(languageManager)
                .environment(\.locale, languageManager.effectiveLocale)
        }
        .sheet(item: $viewModel.barcodeScanResults) { results in
            BarcodeScanResultSheet(barcodes: results.barcodes)
                .environmentObject(languageManager)
                .environment(\.locale, languageManager.effectiveLocale)
        }
        .popover(isPresented: $showTOC, arrowEdge: .top) {
            TOCView(viewModel: viewModel) { pageIndex in
                NotificationCenter.default.post(name: .orifoldJumpToPageIndex, object: pageIndex)
                showTOC = false
            }
            .environmentObject(languageManager)
            .environment(\.locale, languageManager.effectiveLocale)
        }
        // Document comfort, shortcuts, and the guide used to be self-contained toolbar buttons
        // that owned their own popovers; now that they live behind the More overflow, their
        // presentation is hoisted to the scene root, bundled into one modifier (both to keep
        // the More hand-off logic in one place and to keep this already-large body under the
        // Swift type-checker's expression-complexity ceiling).
        .modifier(ToolbarOverflowPresentations(
            viewModel: viewModel,
            languageManager: languageManager,
            isShowingDocumentComfortPopover: $isShowingDocumentComfortPopover,
            isShowingShortcutsCheatSheet: $isShowingShortcutsCheatSheet,
            isShowingShortcutsFirstRun: $isShowingShortcutsFirstRun,
            isShowingGuide: $isShowingGuide,
            isConfirmingOverflowDelete: $isConfirmingOverflowDelete,
            isConfirmingDiscardClose: $isConfirmingDiscardClose,
            isShowingMoreMenu: $isShowingMoreMenu,
            pendingMoreRoute: $pendingMoreRoute,
            showTOC: $showTOC,
            onToggleReaderMode: { toggleReaderMode() },
            onAutoShowOnboarding: { maybeAutoShowOnboarding() }
        ))
        .alert(L10n.string("contentView.importError.title"), isPresented: Binding(
            get: { viewModel.importError != nil },
            set: { if !$0 { viewModel.importError = nil } }
        ), presenting: viewModel.importError) { err in
            importRecoveryButtons(for: err)
        } message: { err in
            Text(err.message)
        }
        .alert(L10n.string("contentView.exportError.title"), isPresented: Binding(
            get: { viewModel.exportError != nil },
            set: { if !$0 { viewModel.exportError = nil } }
        ), presenting: viewModel.exportError) { _ in
            Button(L10n.string("contentView.ok.button")) { viewModel.exportError = nil }
        } message: { err in
            Text(err.message)
        }
        .modifier(ExportSuccessOverlay(viewModel: viewModel))
        .onReceive(NotificationCenter.default.publisher(for: .orifoldShowShortcuts)) { _ in
            isShowingShortcutsCheatSheet.toggle()
        }
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
                .environmentObject(languageManager)
                .environment(\.locale, languageManager.effectiveLocale)
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var mainToolbar: some ToolbarContent {
        // Leading: add source files
        ToolbarItem(placement: .navigation) {
            ToolbarIconButton(labelKey: "toolbar.addFiles.label", systemImage: "plus.circle", helpKey: "toolbar.addFiles.help") {
                openFiles()
            }
            .acceptsImportDrops { providers in
                handleDrop(providers: providers)
            }
            .keyboardShortcut(.addFiles)
        }

        // Center: annotation tools + color swatch
        ToolbarItem(placement: .principal) {
            AnnotationToolPicker(viewModel: viewModel)
                .acceptsImportDrops(isTargeted: $isNavigationDropTargeted, showsHighlight: true) { providers in
                    handleDrop(providers: providers)
                }
        }

        // Trailing: undo/redo, search, document actions, view controls, overflow.
        // The leading padding on Undo gives the group deliberate breathing room from
        // the center capsule instead of the two clusters crowding each other; every
        // icon in this group renders through ToolbarIconButton/ToolbarMenuIconLabelStyle
        // so it matches the capsule's scale, weight, and hit area exactly.
        ToolbarItemGroup(placement: .primaryAction) {
            ToolbarIconButton(labelKey: "toolbar.undo.label", systemImage: "arrow.uturn.backward", helpKey: "toolbar.undo.help") {
                viewModel.performUndoCommand()
            }
            .acceptsImportDrops { providers in
                handleDrop(providers: providers)
            }
            .disabled(!undoAvailable)
            .padding(.leading, 8)

            ToolbarIconButton(labelKey: "toolbar.redo.label", systemImage: "arrow.uturn.forward", helpKey: "toolbar.redo.help") {
                viewModel.performRedoCommand()
            }
            .acceptsImportDrops { providers in
                handleDrop(providers: providers)
            }
            .disabled(!redoAvailable)

            // A bare `Divider()` placed directly in a `ToolbarItemGroup` (outside any
            // HStack/VStack) has no layout context to infer its axis from and can render as
            // a stray horizontal dash occupying its own toolbar-item slot — the reported
            // "-" control eating toolbar space. `ToolbarVerticalDivider` (shared with the
            // center capsule's `groupDivider`) is unambiguous regardless of ambient layout.
            ToolbarVerticalDivider(height: 18, horizontalPadding: 4)

            ToolbarIconButton(labelKey: "toolbar.search.label", systemImage: "magnifyingglass", helpKey: "toolbar.search.help") {
                viewModel.isShowingSearch.toggle()
            }
            .acceptsImportDrops { providers in
                handleDrop(providers: providers)
            }
            .keyboardShortcut(.find)

            Menu {
                Button(L10n.string("toolbar.export.menuItem.export")) {
                    isShowingExportSheet = true
                }
                Divider()
                Button(L10n.string("toolbar.export.menuItem.print")) {
                    NotificationCenter.default.post(name: .orifoldPrint, object: nil)
                }
            } label: {
                ToolbarMenuGlyph(labelKey: "toolbar.export.label", systemImage: "square.and.arrow.up")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .acceptsImportDrops { providers in
                handleDrop(providers: providers)
            }
            .help(L10n.string("toolbar.export.help"))
            .keyboardShortcut(.export)

            ToolbarIconButton(
                labelKey: "toolbar.inspector.label",
                systemImage: "sidebar.right",
                helpKey: "toolbar.inspector.help",
                isActive: showInspector,
                iconInset: 2
            ) {
                showInspector.toggle()
            }
            .acceptsImportDrops { providers in
                handleDrop(providers: providers)
            }
            .keyboardShortcut(.toggleInspector)

            // Everything secondary now folds into one calm overflow. Its own active tint is the
            // *soft* variant, not the full accent pill Inspector uses — a persistent solid-accent
            // ellipsis while reading would shout; a soft wash just says "a mode is on in here."
            ToolbarIconButton(
                labelKey: "toolbar.more.label",
                systemImage: "ellipsis",
                helpKey: "toolbar.more.help",
                isActive: viewModel.isReaderMode || !viewModel.documentComfortSettings.isAtDefault,
                activeStyle: .soft
            ) {
                isShowingMoreMenu.toggle()
            }
            .acceptsImportDrops { providers in
                handleDrop(providers: providers)
            }
            .popover(isPresented: $isShowingMoreMenu, arrowEdge: .top) {
                ToolbarMoreMenu(
                    viewModel: viewModel,
                    readerMode: Binding(
                        get: { viewModel.isReaderMode },
                        set: { setReaderMode($0) }
                    ),
                    onRoute: { requestMoreRoute($0) },
                    onReadAloud: {
                        isShowingMoreMenu = false
                        viewModel.toggleReadAloud()
                    },
                    onRotateLeft: {
                        viewModel.rotatePages(viewModel.currentSelectionPageRefs, by: -90)
                        isShowingMoreMenu = false
                    },
                    onRotateRight: {
                        viewModel.rotatePages(viewModel.currentSelectionPageRefs, by: 90)
                        isShowingMoreMenu = false
                    },
                    onDuplicate: {
                        viewModel.duplicatePages(viewModel.currentSelectionPageRefs)
                        isShowingMoreMenu = false
                    },
                    onSettings: {
                        isShowingMoreMenu = false
                        openSettings()
                    },
                    onAbout: {
                        isShowingMoreMenu = false
                        openWindow(id: "about-orifold")
                    }
                )
                .environmentObject(languageManager)
                .environment(\.locale, languageManager.effectiveLocale)
            }
        }
    }

    // MARK: - Helpers

    private var persistedDocumentComfortSettings: DocumentComfortSettings {
        get {
            guard let decoded = try? JSONDecoder().decode(DocumentComfortSettings.self, from: persistedDocumentComfortSettingsData) else {
                return .default
            }
            return decoded.clamped
        }
        nonmutating set {
            persistedDocumentComfortSettingsData = (try? JSONEncoder().encode(newValue.clamped)) ?? Data()
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

    // MARK: - Toolbar / More-menu coordination

    /// The single source of truth for entering/leaving reader mode, shared by the switch row in
    /// the More popover and the ⌘⇧R View-menu command. Entering reader mode also surfaces the
    /// comments inspector, matching the old toolbar button's behavior.
    private func setReaderMode(_ on: Bool) {
        viewModel.isReaderMode = on
        if on {
            inspectorTab = .comments
            showInspector = true
        }
    }

    private func toggleReaderMode() {
        guard !viewModel.memberDocuments.isEmpty else { return }
        setReaderMode(!viewModel.isReaderMode)
    }

    /// Stash a route and close the More popover; the actual presentation happens on the next
    /// runloop in the `onChange(of: isShowingMoreMenu)` handler, so we never stack one popover
    /// directly on top of another (which macOS drops/flickers).
    private func requestMoreRoute(_ route: MoreRoute) {
        pendingMoreRoute = route
        isShowingMoreMenu = false
    }

    /// First-run onboarding that used to ride on the (now-removed) Guide and Shortcuts toolbar
    /// buttons. Shows at most one nudge per launch, only once a document is open.
    private func maybeAutoShowOnboarding() {
        guard !viewModel.memberDocuments.isEmpty else { return }
        if !hasSeenGuidePopover {
            hasSeenGuidePopover = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { isShowingGuide = true }
        } else if !hasSeenShortcutsHint {
            hasSeenShortcutsHint = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { isShowingShortcutsFirstRun = true }
        }
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
                            Text(L10n.string("contentView.dropOverlay.title"))
                                .font(.dsHeadline())
                                .foregroundStyle(Color.dsAccent)
                            Text(L10n.string("contentView.dropOverlay.subtitle"))
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

    // MARK: - Import failure recovery

    @ViewBuilder
    private func importRecoveryButtons(for err: WorkspaceViewModel.ImportError) -> some View {
        if let url = err.sourceURL, FileManager.default.fileExists(atPath: url.path) {
            Button(L10n.string("contentView.showInFinder.button")) {
                NSWorkspace.shared.activateFileViewerSelecting([url])
                viewModel.importError = nil
            }
        }
        if err.kind.showsChooseFileAgain {
            Button(L10n.string("contentView.importRecovery.chooseFileAgain.button")) {
                chooseFileAgain(for: err)
            }
        }
        if err.kind.showsGrantFolderAccess {
            Button(L10n.string("contentView.importRecovery.grantFolderAccess.button")) {
                grantFolderAccess(for: err)
            }
        }
        if let recentEntryID = err.recentEntryID {
            Button(L10n.string("recentFiles.menu.remove"), role: .destructive) {
                RecentsStore.shared.remove(id: recentEntryID)
                viewModel.importError = nil
            }
        }
        Button(L10n.string("folderImport.overLimit.cancel"), role: .cancel) { viewModel.importError = nil }
    }

    private func chooseFileAgain(for err: WorkspaceViewModel.ImportError) {
        let panel = NSOpenPanel()
        configureImportOpenPanel(panel)
        if let url = err.sourceURL {
            panel.directoryURL = url.deletingLastPathComponent()
        }
        let recentEntryID = err.recentEntryID
        viewModel.importError = nil
        guard panel.runModal() == .OK else { return }
        if let recentEntryID {
            RecentsStore.shared.remove(id: recentEntryID)
        }
        importFilesWithBatchLimit(urls: panel.urls, into: viewModel)
    }

    private func grantFolderAccess(for err: WorkspaceViewModel.ImportError) {
        let panel = NSOpenPanel()
        configureFolderImportOpenPanel(panel)
        if let url = err.sourceURL {
            panel.directoryURL = url.deletingLastPathComponent()
        }
        let sourceURL = err.sourceURL
        let recentEntryID = err.recentEntryID
        viewModel.importError = nil
        guard panel.runModal() == .OK, let folderURL = panel.urls.first else { return }
        SecurityScopedAccess.grantFolderAccessForSession(folderURL)
        guard let sourceURL, FileManager.default.fileExists(atPath: sourceURL.path) else { return }
        if let recentEntryID {
            RecentsStore.shared.remove(id: recentEntryID)
        }
        importFilesWithBatchLimit(urls: [sourceURL], into: viewModel)
    }
}

private struct ReaderModePill: View {
    @Bindable var viewModel: WorkspaceViewModel
    var openNotes: () -> Void
    var onExit: () -> Void
    @State private var isShowingToneControls = false
    // `.popover` content on macOS doesn't inherit the `.environment(\.locale:)`
    // override applied at the scene root — it resets to the system default —
    // so it must be re-applied explicitly to the presented content below.
    @EnvironmentObject private var languageManager: LanguageManager

    var body: some View {
        HStack(spacing: .dsSM) {
            Label(L10n.string("contentView.readerModePill.reader.label"), systemImage: "book.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.dsTextPrimary)

            Button {
                isShowingToneControls.toggle()
            } label: {
                Image(systemName: "eyeglasses")
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(viewModel.documentComfortSettings.isAtDefault ? Color.dsTextTertiary : Color.dsAccent)
            .help(L10n.string("contentView.readerModePill.toneControls.help"))
            .accessibilityLabel(Text(L10n.string("toolbar.documentComfort.accessibilityLabel")))
            .popover(isPresented: $isShowingToneControls, arrowEdge: .top) {
                DocumentComfortPopover(viewModel: viewModel)
                    .frame(width: 360)
                    .environmentObject(languageManager)
                    .environment(\.locale, languageManager.effectiveLocale)
            }

            Button(action: openNotes) {
                Image(systemName: "text.bubble")
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Color.dsAccent)
            .help(L10n.string("contentView.readerModePill.openNotes.help"))

            Button(action: onExit) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Color.dsTextTertiary)
            .help(L10n.string("toolbar.readerMode.exit.help"))
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

/// A small info-circle affordance that opens a short plain-language explanation.
/// Being a real `Button`, it is reachable and activatable by both mouse and keyboard
/// focus (Tab + Space), and mirrors its copy into `.help()` so VoiceOver and the
/// hover tooltip both read the same text.
private struct ComfortInfoButton: View {
    let titleKey: String
    let infoKey: String
    @State private var isPresented = false
    // Passed into L10n.string() and re-applied to the popover content below —
    // SwiftUI only re-invokes `body` on a locale change for views that read
    // `\.locale` during the previous evaluation, and separately, .popover content
    // on macOS resets to the system default locale unless re-applied explicitly.
    @Environment(\.locale) private var locale

    private var titleText: Text { Text(L10n.string(forKey: titleKey, locale: locale)) }
    private var infoText: Text { Text(L10n.string(forKey: infoKey, locale: locale)) }
    private var helpText: String { L10n.string(forKey: infoKey, locale: locale) }

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 12))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.dsTextTertiary)
        .help(helpText)
        .accessibilityLabel(titleText)
        .accessibilityHint(infoText)
        .popover(isPresented: $isPresented, arrowEdge: .trailing) {
            infoText
                .font(.dsCaption())
                .foregroundStyle(Color.dsTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 220, alignment: .leading)
                .padding(.dsMD)
                .environment(\.locale, locale)
        }
    }
}

/// The unified "Document Comfort" control: one-tap reading presets, viewer-only page
/// modes, and fine-tune sliders/toggles that never touch PDF content or exported
/// output (see `DocumentComfortSettings`). Every row shares a common icon/label/value
/// grid so alignment stays consistent regardless of label length or language.
private struct DocumentComfortPopover: View {
    @Bindable var viewModel: WorkspaceViewModel
    @AppStorage("orifoldComfortAdvancedExpanded") private var isAdvancedExpanded = false
    @State private var pendingReset = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // Passed into AppAppearanceMode/PageMode/ComfortPreset's title(locale:) below
    // so this view's `body` actually reads it — SwiftUI only re-invokes `body` on
    // a locale change for views that read `\.locale` during the previous evaluation.
    @Environment(\.locale) private var locale

    private var shouldReduceMotion: Bool {
        reduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || viewModel.documentComfortSettings.reduceAnimations
    }

    var body: some View {
        VStack(alignment: .leading, spacing: .dsLG) {
            header

            presetsSection

            Rectangle()
                .fill(Color.dsSeparator.opacity(0.5))
                .frame(height: 1)

            appThemeSection

            pageModeSection

            advancedSection

            readingFocusSection

            Rectangle()
                .fill(Color.dsSeparator.opacity(0.5))
                .frame(height: 1)

            resetRow
        }
        .padding(.dsLG)
        .confirmationDialog(
            L10n.string("documentComfort.reset.confirm.title"),
            isPresented: $pendingReset,
            titleVisibility: .visible
        ) {
            Button(L10n.string("documentComfort.reset.confirm.confirm"), role: .destructive) {
                applyReset()
            }
            Button(L10n.string("documentComfort.reset.confirm.cancel"), role: .cancel) {}
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(L10n.string("documentComfort.title"))
                .font(.dsTitle())
            Text(L10n.string("documentComfort.subtitle"))
                .font(.dsCaption())
                .foregroundStyle(Color.dsTextSecondary)
        }
    }

    // MARK: - Reading Presets

    private var presetsSection: some View {
        VStack(alignment: .leading, spacing: .dsSM) {
            HStack(spacing: .dsXS) {
                sectionLabel("documentComfort.presets.section")
                ComfortInfoButton(
                    titleKey: "documentComfort.presets.section",
                    infoKey: "documentComfort.presets.info"
                )
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: .dsSM), count: 4), spacing: .dsSM) {
                ForEach(ComfortPreset.allCases) { preset in
                    presetChip(preset)
                }
            }
        }
    }

    private func presetChip(_ preset: ComfortPreset) -> some View {
        let isSelected = viewModel.documentComfortSettings.activePreset == preset
        return Button {
            applyPreset(preset)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: preset.systemImage)
                    .font(.system(size: 15))
                Text(preset.title(locale: locale))
                    .font(.dsCaption())
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
        }
        .buttonStyle(ComfortCardButtonStyle(isSelected: isSelected, shouldReduceMotion: shouldReduceMotion))
        .foregroundStyle(isSelected ? Color.dsAccent : Color.dsTextPrimary)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .help(preset.title(locale: locale))
    }

    private func applyPreset(_ preset: ComfortPreset) {
        var transaction = Transaction(animation: shouldReduceMotion ? nil : .easeInOut(duration: 0.15))
        transaction.disablesAnimations = shouldReduceMotion
        withTransaction(transaction) {
            viewModel.documentComfortSettings = preset.settings
        }
    }

    // MARK: - Application theme

    private var appThemeSection: some View {
        VStack(alignment: .leading, spacing: .dsSM) {
            HStack(spacing: .dsXS) {
                sectionLabel("contentView.nightModeControls.application.label")
                ComfortInfoButton(
                    titleKey: "contentView.nightModeControls.application.label",
                    infoKey: "documentComfort.appTheme.info"
                )
            }
            Picker(L10n.string("contentView.nightModeControls.applicationAppearance.picker"), selection: appAppearanceModeBinding) {
                ForEach(AppAppearanceMode.allCases) { mode in
                    Label(mode.title(locale: locale), systemImage: mode.systemImage)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    // MARK: - Page Mode

    private var pageModeSection: some View {
        VStack(alignment: .leading, spacing: .dsSM) {
            HStack(spacing: .dsXS) {
                sectionLabel("documentComfort.pageMode.section")
                ComfortInfoButton(
                    titleKey: "documentComfort.pageMode.section",
                    infoKey: "documentComfort.pageMode.info"
                )
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: .dsSM), count: 3), spacing: .dsSM) {
                ForEach(PageMode.allCases) { mode in
                    pageModeChip(mode)
                }
            }
        }
    }

    private func pageModeChip(_ mode: PageMode) -> some View {
        let isSelected = viewModel.documentComfortSettings.pageMode == mode
        return Button {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                viewModel.documentComfortSettings.pageMode = mode
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: mode.systemImage)
                    .font(.system(size: 15))
                Text(mode.title(locale: locale))
                    .font(.dsCaption())
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 64)
        }
        .buttonStyle(ComfortCardButtonStyle(isSelected: isSelected, shouldReduceMotion: shouldReduceMotion))
        .foregroundStyle(isSelected ? Color.dsAccent : Color.dsTextPrimary)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .help(mode.title(locale: locale))
    }

    // MARK: - Advanced (fine-tune) controls

    private var advancedSection: some View {
        DisclosureGroup(isExpanded: $isAdvancedExpanded) {
            VStack(alignment: .leading, spacing: .dsMD) {
                comfortSlider(
                    title: "documentComfort.brightness.title",
                    systemImage: "sun.max",
                    infoKey: "documentComfort.brightness.info",
                    value: Binding(
                        get: { viewModel.documentComfortSettings.brightness },
                        set: { viewModel.documentComfortSettings.brightness = $0 }
                    ),
                    range: 50...150
                )
                comfortSlider(
                    title: "documentComfort.contrast.title",
                    systemImage: "circle.lefthalf.filled",
                    infoKey: "documentComfort.contrast.info",
                    value: Binding(
                        get: { viewModel.documentComfortSettings.contrast },
                        set: { viewModel.documentComfortSettings.contrast = $0 }
                    ),
                    range: 50...150
                )
                comfortSlider(
                    title: "documentComfort.warmth.title",
                    systemImage: "thermometer.sun",
                    infoKey: "documentComfort.warmth.info",
                    value: Binding(
                        get: { viewModel.documentComfortSettings.warmth },
                        set: { viewModel.documentComfortSettings.warmth = $0 }
                    ),
                    range: 0...100
                )

                comfortToggle(
                    title: "documentComfort.reduceGlare.title",
                    systemImage: "sparkles",
                    infoKey: "documentComfort.reduceGlare.info",
                    isOn: Binding(
                        get: { viewModel.documentComfortSettings.reduceGlare },
                        set: { viewModel.documentComfortSettings.reduceGlare = $0 }
                    )
                )
                comfortToggle(
                    title: "documentComfort.softenWhitePages.title",
                    systemImage: "doc.text.image",
                    infoKey: "documentComfort.softenWhitePages.info",
                    isOn: Binding(
                        get: { viewModel.documentComfortSettings.softenWhitePages },
                        set: { viewModel.documentComfortSettings.softenWhitePages = $0 }
                    )
                )
            }
            .padding(.top, .dsSM)
        } label: {
            Text(L10n.string("documentComfort.advanced.disclosure"))
                .font(.dsCaption())
                .foregroundStyle(Color.dsTextSecondary)
        }
    }

    // MARK: - Reading Focus

    private var readingFocusSection: some View {
        VStack(alignment: .leading, spacing: .dsSM) {
            comfortToggle(
                title: "documentComfort.focusMode.title",
                systemImage: "viewfinder",
                infoKey: "documentComfort.focusMode.info",
                isOn: Binding(
                    get: { viewModel.documentComfortSettings.focusMode },
                    set: { viewModel.documentComfortSettings.focusMode = $0 }
                )
            )
            comfortToggle(
                title: "documentComfort.reduceAnimations.title",
                systemImage: "wand.and.stars",
                infoKey: "documentComfort.reduceAnimations.info",
                isOn: Binding(
                    get: { viewModel.documentComfortSettings.reduceAnimations },
                    set: { viewModel.documentComfortSettings.reduceAnimations = $0 }
                )
            )
        }
    }

    // MARK: - Reset

    private var resetRow: some View {
        HStack(spacing: .dsXS) {
            Button {
                if viewModel.documentComfortSettings.isAtDefault {
                    return
                }
                pendingReset = true
            } label: {
                Label(L10n.string("documentComfort.reset.button"), systemImage: "arrow.counterclockwise")
                    .font(.dsCaption())
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.documentComfortSettings.isAtDefault)

            ComfortInfoButton(
                titleKey: "documentComfort.reset.button",
                infoKey: "documentComfort.reset.info"
            )
        }
    }

    private func applyReset() {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            viewModel.documentComfortSettings = .default
        }
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

    private func sectionLabel(_ key: String) -> some View {
        Text(L10n.string(forKey: key, locale: locale))
            .font(.dsCaption())
            .fontWeight(.semibold)
            .tracking(.dsLabelTracking)
            .foregroundStyle(Color.dsTextSecondary)
            .textCase(.uppercase)
    }

    private func comfortSlider(
        title: String,
        systemImage: String,
        infoKey: String,
        value: Binding<Double>,
        range: ClosedRange<Double>
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: .dsSM) {
                Image(systemName: systemImage)
                    .frame(width: 20)
                    .foregroundStyle(Color.dsTextTertiary)
                Text(L10n.string(forKey: title, locale: locale))
                    .font(.dsCaption())
                    .foregroundStyle(Color.dsTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: .dsSM)
                Text("\(Int(value.wrappedValue))%")
                    .font(.dsCaption())
                    .foregroundStyle(Color.dsTextSecondary)
                    .monospacedDigit()
                    .frame(width: 44, alignment: .trailing)
                ComfortInfoButton(titleKey: title, infoKey: infoKey)
            }
            HStack(spacing: .dsSM) {
                Color.clear.frame(width: 20)
                Slider(value: value, in: range, step: 1)
            }
        }
    }

    private func comfortToggle(
        title: String,
        systemImage: String,
        infoKey: String,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: .dsSM) {
            Image(systemName: systemImage)
                .frame(width: 20)
                .foregroundStyle(Color.dsTextTertiary)
            Toggle(isOn: isOn) {
                Text(L10n.string(forKey: title, locale: locale))
                    .font(.dsCaption())
                    .fixedSize(horizontal: false, vertical: true)
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            ComfortInfoButton(titleKey: title, infoKey: infoKey)
        }
    }
}

/// Shared card visual for preset and page-mode chips: selected/hover/pressed states,
/// with hover/press motion gated behind Reduce Animations / OS reduced-motion.
private struct ComfortCardButtonStyle: ButtonStyle {
    let isSelected: Bool
    let shouldReduceMotion: Bool
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, 6)
            .background(
                fillColor(isPressed: configuration.isPressed),
                in: RoundedRectangle(cornerRadius: .dsRadiusSm, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: .dsRadiusSm, style: .continuous)
                    .strokeBorder(isSelected ? Color.dsAccent : Color.clear, lineWidth: 1.5)
            }
            .scaleEffect(configuration.isPressed && !shouldReduceMotion ? 0.97 : 1)
            .onHover { hovering in
                isHovered = hovering
            }
            .animation(shouldReduceMotion ? nil : .easeOut(duration: 0.1), value: configuration.isPressed)
    }

    private func fillColor(isPressed: Bool) -> Color {
        if isSelected {
            return Color.dsAccent.opacity(isPressed ? 0.26 : 0.18)
        }
        if isPressed {
            return Color.dsSeparator.opacity(0.6)
        }
        if isHovered {
            return Color.dsSeparator.opacity(0.5)
        }
        return Color.dsSeparator.opacity(0.35)
    }
}

/// Export-sheet imposition choices, mapped to the engine's `ImpositionLayout`. `.none` is the
/// "leave pages as-is" default so the picker can present a first option that clears imposition.
private enum ImpositionChoice: String, CaseIterable, Identifiable {
    case none, twoUp, booklet, fourUp

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: return L10n.string("imposition.none")
        case .twoUp: return L10n.string("imposition.twoUp")
        case .booklet: return L10n.string("imposition.booklet")
        case .fourUp: return L10n.string("imposition.fourUp")
        }
    }

    var layout: ImpositionLayout? {
        switch self {
        case .none: return nil
        case .twoUp: return .nUp(rows: 1, cols: 2)
        case .booklet: return .booklet
        case .fourUp: return .nUp(rows: 2, cols: 2)
        }
    }
}

private struct ExportSheet: View {
    @Bindable var viewModel: WorkspaceViewModel
    @Binding var isPresented: Bool
    @State private var selectedFormat: WorkspaceExportFormat = .pdf
    @State private var imposition: ImpositionChoice = .none
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
    // Passed into L10n.string() below so this view's `body` actually reads it —
    // SwiftUI only re-invokes `body` on a locale change for views that read
    // `\.locale` during the previous evaluation.
    @Environment(\.locale) private var locale

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
            return L10n.string("contentView.exportSheet.passwordMissing.message", locale: locale)
        }
        if passwordConfirmation.isEmpty {
            return L10n.string("contentView.exportSheet.confirmationMissing.message", locale: locale)
        }
        if passwordMismatch {
            return L10n.string("contentView.exportSheet.passwordMismatch.message", locale: locale)
        }
        return nil
    }

    private var canExport: Bool {
        guard protectWithPassword && canProtectSelectedFormat else { return true }
        return !password.isEmpty && password == passwordConfirmation
    }

    var body: some View {
        VStack(alignment: .leading, spacing: .dsLG) {
            Text(L10n.string("contentView.exportSheet.title"))
                .font(.dsTitle())
                .foregroundStyle(Color.dsTextPrimary)

            Picker(L10n.string("contentView.exportSheet.format.picker"), selection: $selectedFormat) {
                ForEach(WorkspaceExportFormat.allCases) { format in
                    Text(format.menuTitle).tag(format)
                }
            }
            .pickerStyle(.menu)

            VStack(alignment: .leading, spacing: .dsSM) {
                DisclosureGroup(isExpanded: $isProtectionExpanded) {
                    VStack(alignment: .leading, spacing: .dsSM) {
                        SecureField(L10n.string("contentView.exportSheet.password.field"), text: $password)
                            .textFieldStyle(.roundedBorder)
                            .disabled(!protectWithPassword || !canProtectSelectedFormat)
                        SecureField(L10n.string("contentView.exportSheet.confirmPassword.field"), text: $passwordConfirmation)
                            .textFieldStyle(.roundedBorder)
                            .disabled(!protectWithPassword || !canProtectSelectedFormat)

                        Toggle(L10n.string("contentView.exportSheet.allowPrinting.toggle"), isOn: $allowsPrinting)
                            .disabled(!protectWithPassword || !canProtectSelectedFormat)
                        Toggle(L10n.string("contentView.exportSheet.allowCopying.toggle"), isOn: $allowsCopying)
                            .disabled(!protectWithPassword || !canProtectSelectedFormat)

                        if let passwordValidationMessage {
                            Text(passwordValidationMessage)
                                .font(.dsCaption())
                                .foregroundStyle(Color.dsAnnotationCoral)
                        }
                    }
                    .padding(.top, .dsSM)
                } label: {
                    Toggle(L10n.string("contentView.exportSheet.protectWithPassword.toggle"), isOn: Binding(
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
                    Text(L10n.string("contentView.exportSheet.passwordProtectionPdfOnly.message"))
                        .font(.dsCaption())
                        .foregroundStyle(Color.dsTextTertiary)
                } else if viewModel.hasCryptographicSignaturePlacement {
                    Text(L10n.string("contentView.exportSheet.passwordProtectionUnavailableSigned.message"))
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
                Picker(L10n.string("contentView.exportSheet.compressionPreset.picker"), selection: $compressionPreset) {
                    ForEach(PDFCompressionPreset.allCases) { preset in
                        Text(preset.label).tag(preset)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(!reduceFileSize || selectedFormat != .pdf)
                .padding(.top, .dsSM)

                if selectedFormat != .pdf {
                    Text(L10n.string("contentView.exportSheet.fileSizeReductionPdfOnly.message"))
                        .font(.dsCaption())
                        .foregroundStyle(Color.dsTextTertiary)
                }
            } label: {
                Toggle(L10n.string("contentView.exportSheet.reduceFileSize.toggle"), isOn: Binding(
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
                VStack(alignment: .leading, spacing: .dsSM) {
                    Picker(L10n.string("imposition.label"), selection: $imposition) {
                        ForEach(ImpositionChoice.allCases) { choice in
                            Text(choice.label).tag(choice)
                        }
                    }
                    .pickerStyle(.menu)

                    if imposition != .none {
                        Text(L10n.string("imposition.flattenNote.message"))
                            .font(.dsCaption())
                            .foregroundStyle(Color.dsTextTertiary)
                    }
                }
            }

            if selectedFormat == .pdf {
                DisclosureGroup(isExpanded: $isSanitizeExpanded) {
                    VStack(alignment: .leading, spacing: .dsSM) {
                        Toggle(L10n.string("contentView.exportSheet.removeMetadata.toggle"), isOn: $removesMetadata)
                            .disabled(!sanitizeForSharing)
                        Text(L10n.string("contentView.exportSheet.sanitizeStripsDetail.message"))
                            .font(.dsCaption())
                            .foregroundStyle(Color.dsTextTertiary)
                    }
                    .padding(.top, .dsSM)
                } label: {
                    Toggle(L10n.string("contentView.exportSheet.sanitizeForSharing.toggle"), isOn: Binding(
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
                    Text(L10n.string("contentView.exportSheet.sanitizeUnavailableSigned.message"))
                        .font(.dsCaption())
                        .foregroundStyle(Color.dsTextTertiary)
                }
            }

            if viewModel.hasFillableFormFields && selectedFormat == .pdf {
                DisclosureGroup(isExpanded: $isFormLockExpanded) {
                    Toggle(L10n.string("contentView.exportSheet.lockFormAnswers.toggle"), isOn: $lockFormAnswers)
                        .padding(.top, .dsSM)
                } label: {
                    Text(L10n.string("contentView.exportSheet.lockFormAnswers.toggle"))
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
                Button(L10n.string("contentView.exportSheet.cancel.button")) {
                    isPresented = false
                }
                Button(L10n.string("contentView.exportSheet.export.button")) {
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
        if selectedFormat == .pdf, let layout = imposition.layout {
            options.imposition = layout
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
    // Read so SwiftUI re-invokes `body` when the app language changes.
    @Environment(\.locale) private var locale

    private var shouldReduceMotion: Bool {
        reduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    var body: some View {
        let _ = locale
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
                Button(L10n.string("contentView.operationProgress.cancel.button"), action: cancel)
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
    // Which markup tool the collapsed cluster reactivates on a plain click, so highlight →
    // underline → strikeout stays a one-click switch once chosen, not always a reset to highlight.
    @State private var lastMarkupTool: AnnotationTool = .highlight
    @State private var isShowingMarkupOptions = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selectionNamespace
    // Read so SwiftUI re-invokes `body` when the app language changes (refreshes the
    // per-tool accessibility labels and hover tooltips).
    @Environment(\.locale) private var locale

    private var shouldReduceMotion: Bool {
        reduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    // The text-markup family collapses into one cluster (a primary button for the active/last
    // markup tool + a disclosure for the rest) so the capsule reads as a short row of distinct
    // services instead of a long undifferentiated strip of markup glyphs.
    private let markupTools: [AnnotationTool] = [.highlight, .underline, .strikeout, .eraser]

    // Keep the highest-frequency creation tools up front as distinct services,
    // then selection, text markup (+ eraser), and free-form page content.
    private let toolGroups: [[AnnotationTool]] = [
        [.editText, .selectObject],
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
        let _ = locale
        // At full width the capsule shows every tool; when the window can't fit it,
        // ViewThatFits falls back to a single menu button rather than letting the whole
        // tool picker silently disappear (the previous behavior when a lone .principal
        // toolbar item didn't fit: it just vanished with no way to reach any tool).
        ViewThatFits(in: .horizontal) {
            capsule
            compactToolMenu
        }
    }

    private var capsule: some View {
        // Snapshot the computed, reader-mode-filtered groups into a local value so
        // every child closure indexes the exact array its indices came from. Reading
        // `visibleToolGroups` afresh inside the closure risks a stale index against a
        // freshly shortened array (e.g. when reader mode toggles) → an out-of-bounds
        // trap under SwiftUI's observation-driven child updates. See CRASH_AUDIT_PLAN.
        let groups = visibleToolGroups
        return HStack(spacing: 4) {
            ForEach(groups.indices, id: \.self) { groupIndex in
                if groupIndex > 0 {
                    groupDivider
                }
                if groups[groupIndex].contains(.highlight) {
                    markupCluster(groups[groupIndex], shouldReduceMotion: shouldReduceMotion)
                } else {
                    ForEach(groups[groupIndex]) { tool in
                        toolButton(tool, shouldReduceMotion: shouldReduceMotion)
                    }
                }
            }

            if viewModel.currentTool.isColorable {
                groupDivider
                AnnotationColorButton(viewModel: viewModel)
                    .transition(shouldReduceMotion ? .identity : .scale(scale: 0.85).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(Color.dsSeparator, lineWidth: 1)
        )
        .shadow(color: Color.dsTextPrimary.opacity(0.10), radius: 8, x: 0, y: 2)
        .fixedSize()
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

    /// Narrow-width fallback: every tool stays reachable through one menu button whose own
    /// icon always shows the currently active tool, so "the active mode is always obvious"
    /// holds even when there's no room for the full capsule.
    private var compactToolMenu: some View {
        // Snapshot for the same reason as `capsule`: closures must index the array
        // their indices came from, not a recomputed `visibleToolGroups`.
        let groups = visibleToolGroups
        return Menu {
            ForEach(groups.indices, id: \.self) { groupIndex in
                ForEach(groups[groupIndex]) { tool in
                    Button {
                        select(tool)
                    } label: {
                        Label(tool.label, systemImage: tool.iconName)
                    }
                }
                if groupIndex < groups.count - 1 {
                    Divider()
                }
            }
        } label: {
            Label(viewModel.currentTool.label, systemImage: viewModel.currentTool.iconName)
                .labelStyle(.iconOnly)
                .font(.system(size: 14, weight: .semibold))
        }
        .frame(width: 28, height: 28)
        .help(viewModel.currentTool.label)
    }

    private var groupDivider: some View {
        ToolbarVerticalDivider()
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

    /// The collapsed markup control: a primary button that activates the active-or-last markup
    /// tool (one click), plus a disclosure that reveals the full family. It joins the same
    /// `selectionNamespace`, so when a markup tool is active the selection pill lives here and
    /// slides in/out exactly like every other tool — the capsule keeps one pill, never two.
    @ViewBuilder
    private func markupCluster(_ tools: [AnnotationTool], shouldReduceMotion: Bool) -> some View {
        let active = markupPrimary(in: tools)
        let isActive = tools.contains(viewModel.currentTool)
        let isHovered = hoveredTool == active

        HStack(spacing: 0) {
            Button {
                select(active)
            } label: {
                ZStack {
                    if isActive {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.dsAccent)
                            .matchedGeometryEffect(id: "selectedTool", in: selectionNamespace)
                    }
                    toolIcon(active, isSelected: isActive)
                        .foregroundStyle(isActive ? Color.dsSurface : Color.dsTextSecondary)
                }
                .frame(width: 28, height: 28)
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(ToolButtonStyle(isHovered: isHovered, isSelected: isActive, hoverFill: Color.dsAccentSoft, reduceMotion: shouldReduceMotion))
            .anchorPreference(key: ToolBoundsKey.self, value: .bounds) { [active: $0] }
            .onHover { hovering in
                if hovering {
                    hoveredTool = active
                } else if hoveredTool == active {
                    hoveredTool = nil
                }
            }
            .accessibilityLabel(active.label)
            .accessibilityHint(active.helpText)

            if tools.count > 1 {
                Button {
                    isShowingMarkupOptions.toggle()
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .black))
                        .foregroundStyle(isActive ? Color.dsAccent : Color.dsTextSecondary.opacity(0.7))
                        .frame(width: 13, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(L10n.string("annotationTool.markup.options")))
                .popover(isPresented: $isShowingMarkupOptions, arrowEdge: .bottom) {
                    markupOptions(tools)
                }
            }
        }
    }

    private func markupOptions(_ tools: [AnnotationTool]) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(tools) { tool in
                Button {
                    select(tool)
                    isShowingMarkupOptions = false
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: tool.iconName)
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 20)
                            .foregroundStyle(viewModel.currentTool == tool ? Color.dsAccent : Color.dsTextSecondary)
                        Text(tool.label)
                            .font(.system(size: 13))
                            .foregroundStyle(Color.dsTextPrimary)
                        Spacer(minLength: 16)
                        if viewModel.currentTool == tool {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.dsAccent)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(MarkupOptionButtonStyle())
            }
        }
        .padding(6)
        .frame(width: 208)
    }

    /// The markup tool the primary button represents: the active one if a markup tool is
    /// selected, otherwise the last markup used, otherwise the family's first (highlight).
    private func markupPrimary(in tools: [AnnotationTool]) -> AnnotationTool {
        if tools.contains(viewModel.currentTool) { return viewModel.currentTool }
        if tools.contains(lastMarkupTool) { return lastMarkupTool }
        return tools.first ?? .highlight
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
        // Remember the last markup tool so the collapsed cluster's primary button reactivates
        // the user's actual choice, not always highlight.
        if markupTools.contains(tool) {
            lastMarkupTool = tool
        }
        // A copied-but-unused Format Painter style should never silently linger past an
        // explicit switch away from Edit Text — the user leaving the tool is a clear signal
        // they're done with that copy, so it doesn't surprise-apply to some unrelated
        // editor opened much later.
        if tool != .editText {
            viewModel.disarmFormatPainter()
        }
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

/// Row style for the markup-options popover: a quiet hover wash, matching the More menu's rows.
private struct MarkupOptionButtonStyle: ButtonStyle {
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(hovering ? 0.08 : 0))
            )
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
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
                // Always present (never conditionally inserted/removed) so hovering only
                // animates this layer's OWN opacity in place. A view that's inserted and
                // removed briefly renders under SwiftUI's default transition, which can
                // paint past the button's bounds mid-animation — clipping below guards
                // against that regardless, but avoiding the insertion/removal entirely is
                // the more robust fix.
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(hoverFill)
                    .opacity(isHovered && !isSelected ? 1 : 0)
            }
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovered)
    }
}

/// A thin, deliberately-sized vertical rule for separating logical toolbar groups — shared
/// by the center annotation-tool capsule and the trailing icon cluster. Never a bare
/// `Divider()`: outside an HStack/VStack a `Divider()` has no layout axis to infer from and
/// can render as a stray horizontal dash consuming its own toolbar-item slot instead of a
/// vertical rule.
private struct ToolbarVerticalDivider: View {
    var height: CGFloat = 16
    var horizontalPadding: CGFloat = 6

    var body: some View {
        Rectangle()
            .fill(Color.dsSeparator)
            .frame(width: 1, height: height)
            .padding(.horizontal, horizontalPadding)
    }
}

/// Standard icon size/weight/hit-area shared by every plain toolbar icon button —
/// the leading, trailing, and center-capsule tool icons all render at this scale so
/// the nav bar reads as one design system instead of native-toolbar-default icons
/// (bigger, inconsistently spaced) mixed with the custom capsule's smaller glyphs.
private enum ToolbarIconMetrics {
    static let symbolSize: CGFloat = 14
    static let symbolWeight: Font.Weight = .semibold
    static let hitSize: CGFloat = 28
    static let cornerRadius: CGFloat = 7
}

/// A toolbar action button styled identically to the center annotation-tool capsule's
/// buttons: same hit area, icon scale, hover fill, press scale, and — when `isActive`
/// is set for a persistent-mode toggle (reader mode, inspector, night mode) — the same
/// filled-pill "selected" treatment used for the active annotation tool, rather than a
/// `.tint()` approximation.
private struct ToolbarIconButton: View {
    /// How an `isActive` button paints its "on" state.
    /// - `.prominent`: the full accent-fill pill with a knocked-out glyph — for panel/mode
    ///   toggles the user flips directly (Inspector, night mode).
    /// - `.soft`: a quiet accent wash behind an accent glyph — for a control that merely
    ///   *contains* something active (the More overflow when reader mode/comfort is on), where
    ///   a persistent solid-accent fill would shout over the calm bar.
    enum ActiveStyle { case prominent, soft }

    var labelKey: String
    var systemImage: String
    var helpKey: String
    var isActive: Bool = false
    var activeStyle: ActiveStyle = .prominent
    /// Extra inset between the glyph and the hit-area edge, for symbols (e.g. wide
    /// two-lobed shapes like "sidebar.right" or "eyeglasses") that otherwise draw
    /// close enough to the frame edge that the active-state fill looks like it
    /// bleeds past the glyph instead of framing it.
    var iconInset: CGFloat = 0
    var action: () -> Void

    @State private var isHovered = false
    @FocusState private var isFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    // Passed into L10n.string() below so this view's `body` actually reads it —
    // SwiftUI only re-invokes `body` on a locale change for views that read
    // `\.locale` during the previous evaluation.
    @Environment(\.locale) private var locale

    private var shouldReduceMotion: Bool {
        reduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private var activeFill: Color { activeStyle == .soft ? Color.dsAccentSoft : Color.dsAccent }
    private var activeGlyph: Color { activeStyle == .soft ? Color.dsAccent : Color.dsSurface }

    var body: some View {
        Button(action: action) {
            ZStack {
                // Always present, never conditionally inserted/removed — flipping `isActive`
                // (e.g. toggling the eyeglasses comfort popover under an animated
                // `withTransaction`) animates only this layer's own opacity in place, so the
                // fill can never be caught mid-insertion rendering past the button's rounded
                // shape. `.clipShape` below is the hard guarantee regardless.
                RoundedRectangle(cornerRadius: ToolbarIconMetrics.cornerRadius, style: .continuous)
                    .fill(activeFill)
                    .opacity(isActive ? 1 : 0)
                Label(L10n.string(forKey: labelKey, locale: locale), systemImage: systemImage)
                    .labelStyle(.iconOnly)
                    .font(.system(size: ToolbarIconMetrics.symbolSize, weight: ToolbarIconMetrics.symbolWeight))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(isActive ? activeGlyph : Color.dsTextSecondary)
                    .padding(iconInset)
            }
            .frame(width: ToolbarIconMetrics.hitSize, height: ToolbarIconMetrics.hitSize)
            .clipShape(RoundedRectangle(cornerRadius: ToolbarIconMetrics.cornerRadius, style: .continuous))
            // Keyboard focus drawn as an inset ring inside the already-clipped bounds
            // rather than relying on AppKit's default focus ring, which halos outside
            // the control and reintroduces the exact "bleeds past the icon" look this
            // component exists to avoid.
            .overlay {
                RoundedRectangle(cornerRadius: ToolbarIconMetrics.cornerRadius, style: .continuous)
                    .strokeBorder(Color.dsAccent, lineWidth: 2)
                    .padding(1)
                    .opacity(isFocused ? 1 : 0)
            }
            .contentShape(RoundedRectangle(cornerRadius: ToolbarIconMetrics.cornerRadius, style: .continuous))
        }
        .buttonStyle(ToolButtonStyle(isHovered: isHovered, isSelected: isActive, reduceMotion: shouldReduceMotion))
        .focused($isFocused)
        .focusEffectDisabled()
        .opacity(isEnabled ? 1 : 0.35)
        .onHover { isHovered = $0 }
        .help(L10n.string(forKey: helpKey, locale: locale))
    }
}

/// Label content for `Menu`-based toolbar buttons (Export, More), styled to match
/// `ToolbarIconButton` exactly — same hit area, corner radius, and hover fill — so the
/// pair reads as one control instead of a plain icon frame nested inside separate,
/// system-drawn menu chrome. Callers must also apply `.menuStyle(.borderlessButton)`
/// and `.menuIndicator(.hidden)` to the enclosing `Menu`; otherwise AppKit's default
/// menu-button border and disclosure chevron widen the control past this glyph's own
/// clipped bounds, which is what was throwing off the spacing rhythm next to Search.
private struct ToolbarMenuGlyph: View {
    var labelKey: String
    var systemImage: String

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // Passed into L10n.string() below so this view's `body` actually reads it —
    // SwiftUI only re-invokes `body` on a locale change for views that read
    // `\.locale` during the previous evaluation.
    @Environment(\.locale) private var locale

    private var shouldReduceMotion: Bool {
        reduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    var body: some View {
        Label(L10n.string(forKey: labelKey, locale: locale), systemImage: systemImage)
            .labelStyle(.iconOnly)
            .font(.system(size: ToolbarIconMetrics.symbolSize, weight: ToolbarIconMetrics.symbolWeight))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(Color.dsTextSecondary)
            .frame(width: ToolbarIconMetrics.hitSize, height: ToolbarIconMetrics.hitSize)
            .background {
                RoundedRectangle(cornerRadius: ToolbarIconMetrics.cornerRadius, style: .continuous)
                    .fill(Color.dsAccentSoft)
                    .opacity(isHovered ? 1 : 0)
            }
            .clipShape(RoundedRectangle(cornerRadius: ToolbarIconMetrics.cornerRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: ToolbarIconMetrics.cornerRadius, style: .continuous))
            .animation(shouldReduceMotion ? nil : .easeOut(duration: 0.12), value: isHovered)
            .onHover { isHovered = $0 }
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
    // Read so SwiftUI re-invokes `body` when the app language changes (refreshes the tooltip).
    @Environment(\.locale) private var locale

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
        .help(L10n.string("contentView.annotationColorButton.help", locale: locale))
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

func folderImportSummaryMessage(importedCount: Int, skippedCount: Int) -> String {
    L10n.format("folderImport.summary.importedSkipped", importedCount, skippedCount)
}

/// Builds the post-import status toast for a `.ready` outcome, or nil if nothing
/// noteworthy happened (no unsupported files skipped, no truncation). Skipped-file
/// and truncation notes are independent facts and both need to reach the user when
/// both are true, rather than one silently overriding the other.
func folderImportReadyStatusMessage(importedCount: Int, unsupportedCount: Int, wasTruncated: Bool) -> String? {
    guard unsupportedCount > 0 || wasTruncated else { return nil }
    var message = unsupportedCount > 0
        ? folderImportSummaryMessage(importedCount: importedCount, skippedCount: unsupportedCount)
        : L10n.string("folderImport.overLimit.truncatedNote")
    if wasTruncated && unsupportedCount > 0 {
        message += " " + L10n.string("folderImport.overLimit.truncatedNote")
    }
    return message
}

func folderImportOverLimitTitle(supportedCount: Int) -> String {
    L10n.format("folderImport.overLimit.title", supportedCount)
}

func folderImportOverLimitImportFirstLabel(count: Int) -> String {
    L10n.format("folderImport.overLimit.importFirst", count)
}

/// What kind of items are currently hovering over an import drop zone, used to show
/// drag-specific release copy ("Release to import folder contents", etc.).
enum ImportDragKind {
    case files
    case folder
    case mixed
}

enum FolderScanPhase: Equatable {
    case idle
    case scanning
    case finding
}

/// Shared drop delegate for import drop zones that accept both files and folders.
/// Classifies the drag (files/folder/mixed) for live release copy, then resolves and
/// hands off to `onResolved` on drop.
struct ImportDropDelegate: DropDelegate {
    var onKindChange: (ImportDragKind?) -> Void
    var onResolved: (ResolvedImportDrop) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.folder]) || info.hasItemsConforming(to: importDropContentTypes)
    }

    func dropEntered(info: DropInfo) {
        onKindChange(classify(info))
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        onKindChange(classify(info))
        return DropProposal(operation: .copy)
    }

    func dropExited(info: DropInfo) {
        onKindChange(nil)
    }

    func performDrop(info: DropInfo) -> Bool {
        onKindChange(nil)
        let providers = info.itemProviders(for: importDropContentTypes)
        resolveImportDrop(from: providers) { resolved in
            onResolved(resolved)
        }
        return true
    }

    private func classify(_ info: DropInfo) -> ImportDragKind {
        let hasFolder = info.hasItemsConforming(to: [.folder])
        let hasFile = !info.itemProviders(for: WorkspaceDocument.importableContentTypes).isEmpty
        if hasFolder && hasFile { return .mixed }
        return hasFolder ? .folder : .files
    }
}

func configureImportOpenPanel(_ panel: NSOpenPanel) {
    panel.allowsMultipleSelection = true
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowedContentTypes = WorkspaceDocument.importableContentTypes
    panel.message = importBatchPanelMessage
}

func configureFolderImportOpenPanel(_ panel: NSOpenPanel) {
    panel.allowsMultipleSelection = true
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.message = L10n.string("folderImport.panel.message")
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

/// A drop resolved into files and folder roots, so folders can be scanned separately
/// instead of being silently dropped by `isSupportedImportURL` (which only recognizes
/// document types, never directories).
struct ResolvedImportDrop {
    var files: [URL]
    var folders: [URL]
    var wasLimited: Bool
}

func resolveImportDrop(from providers: [NSItemProvider], maxFileCount: Int = maximumImportBatchSize, completion: @escaping (ResolvedImportDrop) -> Void) {
    var files: [URL] = []
    var folders: [URL] = []
    var seenURLs: Set<String> = []
    var nextProviderIndex = 0
    var wasLimited = false

    func resolveNextProvider() {
        guard nextProviderIndex < providers.count else {
            completion(ResolvedImportDrop(files: files, folders: folders, wasLimited: wasLimited))
            return
        }

        let provider = providers[nextProviderIndex]
        nextProviderIndex += 1
        loadImportURL(from: provider) { url in
            if let url {
                let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                if isDirectory {
                    let key = url.fileURLIdentityKey
                    if seenURLs.insert(key).inserted {
                        folders.append(url)
                    }
                } else if isSupportedImportURL(url) {
                    if files.count < maxFileCount {
                        let key = url.fileURLIdentityKey
                        if seenURLs.insert(key).inserted {
                            files.append(url)
                        }
                    } else {
                        wasLimited = true
                    }
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

/// Outcome of resolving a mix of individually-selected/dropped files and folders, once any
/// folder roots have been scanned. The view maps each case to the appropriate alert, status
/// toast, or confirmation dialog. `.ready` does not perform the import itself — the caller
/// calls `viewModel.importFiles(urls:insertingAfter:)` so it can sequence UI state around it.
enum FolderImportOutcome {
    case ready(urls: [URL], unsupportedCount: Int, wasLimited: Bool, wasTruncated: Bool)
    case empty
    case onlyUnsupported
    case needsConfirmation(PendingFolderImportBatch)
    case nothingToImport
}

struct PendingFolderImportBatch {
    var urls: [URL]
    var unsupportedCount: Int
    var wasTruncated: Bool
}

func importPickedOrDropped(
    files: [URL],
    folders: [URL],
    wasLimited: Bool = false
) async -> FolderImportOutcome {
    guard !folders.isEmpty else {
        guard !files.isEmpty else { return .nothingToImport }
        return .ready(urls: files, unsupportedCount: 0, wasLimited: wasLimited, wasTruncated: false)
    }

    let scan = await FolderImportScanner.scan(folders: folders)

    var merged = files
    var seenKeys = Set(files.map(\.fileURLIdentityKey))
    for url in scan.supportedURLs where seenKeys.insert(url.fileURLIdentityKey).inserted {
        merged.append(url)
    }

    guard !merged.isEmpty else {
        return scan.unsupportedCount > 0 ? .onlyUnsupported : .empty
    }

    guard merged.count <= maximumImportBatchSize else {
        return .needsConfirmation(PendingFolderImportBatch(
            urls: merged,
            unsupportedCount: scan.unsupportedCount,
            wasTruncated: scan.wasTruncated
        ))
    }

    return .ready(urls: merged, unsupportedCount: scan.unsupportedCount, wasLimited: wasLimited, wasTruncated: scan.wasTruncated)
}

/// Shared handling for a `FolderImportOutcome`, used by every folder-import entry point
/// (intro drop zone, Choose Folder button, File-menu command) so they can't silently
/// diverge on error messages, skip summaries, or over-limit handling. The only thing
/// callers customize is how `.needsConfirmation` is presented, since a SwiftUI view can
/// show a `confirmationDialog` while a menu command needs a synchronous `NSAlert`.
@MainActor
func applyFolderImportOutcome(
    _ outcome: FolderImportOutcome,
    into viewModel: WorkspaceViewModel,
    onNeedsConfirmation: (PendingFolderImportBatch) -> Void
) {
    switch outcome {
    case .ready(let urls, let unsupportedCount, let wasLimited, let wasTruncated):
        viewModel.importFiles(urls: urls)
        if let message = folderImportReadyStatusMessage(importedCount: urls.count, unsupportedCount: unsupportedCount, wasTruncated: wasTruncated) {
            viewModel.editingStatus = .success(message)
            AccessibilityNotification.Announcement(message).post()
        }
        if wasLimited {
            viewModel.importError = WorkspaceViewModel.ImportError(
                fileName: "Dropped Files",
                message: importDropProviderLimitMessage
            )
        }
    case .empty:
        viewModel.importError = WorkspaceViewModel.ImportError(
            fileName: "Folder",
            message: L10n.string("folderImport.error.empty")
        )
    case .onlyUnsupported:
        viewModel.importError = WorkspaceViewModel.ImportError(
            fileName: "Folder",
            message: L10n.string("folderImport.error.onlyUnsupported")
        )
    case .needsConfirmation(let batch):
        onNeedsConfirmation(batch)
    case .nothingToImport:
        break
    }
}

/// Imports the first `maximumImportBatchSize` URLs from an over-limit folder batch,
/// shared by every entry point's "Import first 50" action.
@MainActor
func importFirstFromPendingBatch(_ batch: PendingFolderImportBatch, into viewModel: WorkspaceViewModel) {
    let firstBatch = Array(batch.urls.prefix(maximumImportBatchSize))
    viewModel.importFiles(urls: firstBatch)
    if let message = folderImportReadyStatusMessage(importedCount: firstBatch.count, unsupportedCount: batch.unsupportedCount, wasTruncated: batch.wasTruncated) {
        viewModel.editingStatus = .success(message)
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
    // Passed into L10n.string()/L10n.format() below so this view's `body`
    // actually reads it — SwiftUI only re-invokes `body` on a locale change
    // for views that read `\.locale` during the previous evaluation.
    @Environment(\.locale) private var locale

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
            .help(count == 1 ? L10n.string("contentView.viewComments.one", locale: locale) : L10n.format("contentView.viewComments.other", count, locale: locale))
            .accessibilityLabel(count == 1 ? L10n.string("contentView.viewComments.one", locale: locale) : L10n.format("contentView.viewComments.other", count, locale: locale))
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

// MARK: - Toolbar overflow ("More")

/// Bundles every presentation the More overflow can trigger — the comfort/shortcuts/guide
/// popovers, the delete confirmation, the More→target route hand-off, and the reader-mode /
/// table-of-contents menu-command receivers — into a single modifier. This both centralizes the
/// hand-off logic and keeps `ContentView.body` under the Swift type-checker's expression ceiling.
private struct ToolbarOverflowPresentations: ViewModifier {
    let viewModel: WorkspaceViewModel
    let languageManager: LanguageManager
    @Binding var isShowingDocumentComfortPopover: Bool
    @Binding var isShowingShortcutsCheatSheet: Bool
    @Binding var isShowingShortcutsFirstRun: Bool
    @Binding var isShowingGuide: Bool
    @Binding var isConfirmingOverflowDelete: Bool
    @Binding var isConfirmingDiscardClose: Bool
    @Binding var isShowingMoreMenu: Bool
    @Binding var pendingMoreRoute: MoreRoute?
    @Binding var showTOC: Bool
    let onToggleReaderMode: () -> Void
    let onAutoShowOnboarding: () -> Void

    func body(content: Content) -> some View {
        content
            .popover(isPresented: $isShowingDocumentComfortPopover, arrowEdge: .top) {
                DocumentComfortPopover(viewModel: viewModel)
                    .frame(width: 360)
                    .environmentObject(languageManager)
                    .environment(\.locale, languageManager.effectiveLocale)
            }
            .popover(isPresented: $isShowingShortcutsCheatSheet, arrowEdge: .top) {
                ShortcutsCheatSheetView(isPresented: $isShowingShortcutsCheatSheet)
                    .environment(\.locale, languageManager.effectiveLocale)
            }
            .popover(isPresented: $isShowingShortcutsFirstRun, arrowEdge: .top) {
                ShortcutsFirstRunPopover(isPresented: $isShowingShortcutsFirstRun) {
                    isShowingShortcutsCheatSheet = true
                }
                .environment(\.locale, languageManager.effectiveLocale)
            }
            .popover(isPresented: $isShowingGuide, arrowEdge: .top) {
                GuidePopover(isPresented: $isShowingGuide)
                    .environmentObject(languageManager)
                    .environment(\.locale, languageManager.effectiveLocale)
            }
            .confirmationDialog(
                L10n.string("sidebar.deletePages.confirmation.title"),
                isPresented: $isConfirmingOverflowDelete,
                titleVisibility: .visible
            ) {
                Button(L10n.string("sidebar.deletePages.confirmation.delete"), role: .destructive) {
                    viewModel.deletePages(viewModel.currentSelectionPageRefs)
                }
                Button(L10n.string("sidebar.deletePages.confirmation.cancel"), role: .cancel) {}
            } message: {
                let count = viewModel.currentSelectionPageRefs.count
                if count == 1 {
                    Text(L10n.string("sidebar.deletePages.confirmation.messageSingular"))
                } else {
                    Text(L10n.format("sidebar.removePages.confirmation.plural", count, locale: languageManager.effectiveLocale))
                }
            }
            .confirmationDialog(
                L10n.string("discardClose.confirm.title"),
                isPresented: $isConfirmingDiscardClose,
                titleVisibility: .visible
            ) {
                Button(L10n.string("discardClose.confirm.confirm"), role: .destructive) {
                    viewModel.discardChangesAndClose()
                }
                Button(L10n.string("discardClose.confirm.cancel"), role: .cancel) {}
            } message: {
                Text(L10n.string("discardClose.confirm.message"))
            }
            .onChange(of: isShowingMoreMenu) { _, isOpen in
                guard !isOpen, let route = pendingMoreRoute else { return }
                pendingMoreRoute = nil
                // One runloop hop lets the More popover fully tear down before the next
                // presents, which keeps the hand-off from flickering or being swallowed.
                DispatchQueue.main.async {
                    switch route {
                    case .comfort: isShowingDocumentComfortPopover = true
                    case .outline: showTOC = true
                    case .shortcuts: isShowingShortcutsCheatSheet = true
                    case .guide: isShowingGuide = true
                    case .deletePages: isConfirmingOverflowDelete = true
                    case .discardAndClose: isConfirmingDiscardClose = true
                    case .insertBarcode: viewModel.isShowingBarcodeComposer = true
                    case .scanBarcodes: viewModel.scanBarcodesOnCurrentPage()
                    }
                }
            }
            // The File-menu "Revert & Close Without Saving" command posts this rather than
            // acting directly, so it routes through the same confirmation as the More-menu row.
            .onReceive(NotificationCenter.default.publisher(for: .orifoldRequestDiscardClose)) { _ in
                isConfirmingDiscardClose = true
            }
            .onChange(of: viewModel.memberDocuments.isEmpty) { _, isEmpty in
                if !isEmpty { onAutoShowOnboarding() }
            }
            // Reader mode and the outline lost their always-visible toolbar buttons, so their
            // shortcuts now live as real View-menu commands (ViewToggleCommandButtons), which
            // reach back here through these notifications — menu-bar-discoverable, not invisible
            // responder-chain buttons.
            .onReceive(NotificationCenter.default.publisher(for: .orifoldToggleReaderMode)) { _ in
                onToggleReaderMode()
            }
            .onReceive(NotificationCenter.default.publisher(for: .orifoldToggleTableOfContents)) { _ in
                guard !viewModel.memberDocuments.isEmpty else { return }
                showTOC.toggle()
            }
    }
}

/// Secondary destinations that live behind the toolbar's "More" overflow. Presenting one of
/// these means *first* dismissing the More popover, *then* presenting the target on the next
/// runloop tick — never a popover inside a popover (which macOS renders unreliably). The
/// coordinator for that lives in `ContentView` (`pendingMoreRoute` + `onChange`).
enum MoreRoute: Equatable {
    case comfort
    case outline
    case shortcuts
    case guide
    case deletePages
    case discardAndClose
    case insertBarcode
    case scanBarcodes
}

/// Resolves the AppKit window hosting this document scene and hands it back so the view
/// model can close it directly. Needed because `discardChangesAndClose()` is invoked from a
/// popover/menu/dialog whose own window is key at that moment — `NSApp.keyWindow` would be
/// the wrong one — so the document window is captured up front instead.
private struct WorkspaceWindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { onResolve(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { onResolve(nsView.window) }
    }
}

/// The toolbar overflow: one calm, labeled panel that absorbs every secondary control so the
/// visible bar can stay down to the few actions used on almost every document. Rows are dense,
/// native, and self-describing (icon + label, a live switch for reader mode, a ⌘-hint, chevrons
/// for the things that open their own surface) — the "keep a place that tells the user what it
/// does" requirement, without a wall of subtitles.
private struct ToolbarMoreMenu: View {
    @Bindable var viewModel: WorkspaceViewModel
    var readerMode: Binding<Bool>
    var onRoute: (MoreRoute) -> Void
    var onReadAloud: () -> Void
    var onRotateLeft: () -> Void
    var onRotateRight: () -> Void
    var onDuplicate: () -> Void
    var onSettings: () -> Void
    var onAbout: () -> Void
    // Passed into L10n.string() below so this view's `body` actually reads it —
    // SwiftUI only re-invokes `body` on a locale change for views that read
    // `\.locale` during the previous evaluation.
    @Environment(\.locale) private var locale

    private var selectionEmpty: Bool { viewModel.currentSelectionPageRefs.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            sectionHeader("more.section.view")

            MoreReaderModeRow(readerMode: readerMode)

            MoreMenuRow(
                systemImage: "eyeglasses",
                titleKey: "toolbar.documentComfort.label",
                subtitleKey: "more.documentComfort.subtitle",
                trailing: { MoreChevron() },
                action: { onRoute(.comfort) }
            )

            MoreMenuRow(
                systemImage: "list.bullet.rectangle.portrait",
                titleKey: "toolbar.contents.label",
                subtitleKey: "more.contents.subtitle",
                trailing: { MoreChevron() },
                action: { onRoute(.outline) }
            )

            MoreMenuRow(
                systemImage: viewModel.isReadingAloud ? "stop.fill" : "speaker.wave.2",
                titleKey: viewModel.isReadingAloud ? "readaloud.stop" : "readaloud.start",
                action: onReadAloud
            )
            .disabled(viewModel.pageCount == 0)

            divider

            sectionHeader("more.section.pages")

            MoreMenuRow(systemImage: "rotate.left", titleKey: "more.pages.rotateLeft", action: onRotateLeft)
                .disabled(selectionEmpty)
            MoreMenuRow(systemImage: "rotate.right", titleKey: "more.pages.rotateRight", action: onRotateRight)
                .disabled(selectionEmpty)
            MoreMenuRow(systemImage: "plus.square.on.square", titleKey: "more.pages.duplicate", action: onDuplicate)
                .disabled(selectionEmpty)

            MoreMenuRow(systemImage: "barcode", titleKey: "barcode.insert.title") { onRoute(.insertBarcode) }
                .disabled(viewModel.pageCount == 0)
            MoreMenuRow(systemImage: "qrcode.viewfinder", titleKey: "barcode.scan.title") { onRoute(.scanBarcodes) }
                .disabled(viewModel.pageCount == 0)

            MoreMenuRow(systemImage: "trash", titleKey: "more.pages.delete", isDestructive: true) {
                onRoute(.deletePages)
            }
            .disabled(selectionEmpty)

            divider

            MoreMenuRow(systemImage: "keyboard", titleKey: "shortcuts.cheatSheet.title") { onRoute(.shortcuts) }
            MoreMenuRow(systemImage: "questionmark.circle", titleKey: "more.guide.label") { onRoute(.guide) }

            // Escape hatch: only surfaced once the document has edits to back out of, so a
            // clean viewing session never sees a destructive row it can't use.
            if viewModel.hasUnsavedChanges {
                divider
                MoreMenuRow(
                    systemImage: "arrow.uturn.backward.circle",
                    titleKey: "more.discardClose.label",
                    subtitleKey: "more.discardClose.subtitle",
                    isDestructive: true
                ) { onRoute(.discardAndClose) }
            }

            divider

            MoreMenuRow(systemImage: "gearshape", titleKey: "more.settings", trailing: { MoreShortcut("⌘,") }, action: onSettings)
            MoreMenuRow(systemImage: "info.circle", titleKey: "more.about", action: onAbout)
        }
        .padding(6)
        .frame(width: 288)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.dsSeparator.opacity(0.5))
            .frame(height: 0.5)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
    }

    private func sectionHeader(_ key: String) -> some View {
        Text(L10n.string(forKey: key, locale: locale))
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Color.dsTextSecondary)
            .padding(.horizontal, 9)
            .padding(.top, 5)
            .padding(.bottom, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Reader mode is the one persistent-mode toggle in the panel, so it reads as a switch row
/// (native `Toggle` → free VoiceOver "on/off" semantics, no extra localized strings) rather
/// than a button that opens something.
private struct MoreReaderModeRow: View {
    var readerMode: Binding<Bool>
    // Read so SwiftUI re-invokes `body` when the app language changes.
    @Environment(\.locale) private var locale

    var body: some View {
        let _ = locale
        HStack(spacing: 11) {
            MoreIconTile(systemImage: readerMode.wrappedValue ? "book.fill" : "book", isActive: readerMode.wrappedValue)
            VStack(alignment: .leading, spacing: 1) {
                Text(L10n.string("toolbar.readerMode.label"))
                    .font(.system(size: 13))
                    .foregroundStyle(Color.dsTextPrimary)
                Text(L10n.string("more.readerMode.subtitle"))
                    .font(.system(size: 11))
                    .foregroundStyle(Color.dsTextSecondary)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: readerMode)
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.mini)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

private struct MoreMenuRow<Trailing: View>: View {
    let systemImage: String
    let titleKey: String
    var subtitleKey: String?
    var isDestructive: Bool = false
    @ViewBuilder var trailing: () -> Trailing
    let action: () -> Void

    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled
    // Passed into L10n.string() below so this view's `body` actually reads it —
    // SwiftUI only re-invokes `body` on a locale change for views that read
    // `\.locale` during the previous evaluation.
    @Environment(\.locale) private var locale

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                MoreIconTile(systemImage: systemImage, isDestructive: isDestructive)
                VStack(alignment: .leading, spacing: 1) {
                    Text(L10n.string(forKey: titleKey, locale: locale))
                        .font(.system(size: 13))
                        .foregroundStyle(isDestructive ? Color.red : Color.dsTextPrimary)
                    if let subtitleKey {
                        Text(L10n.string(forKey: subtitleKey, locale: locale))
                            .font(.system(size: 11))
                            .foregroundStyle(Color.dsTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                trailing()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(hovering && isEnabled ? 0.08 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.38)
        .onHover { hovering = $0 }
    }
}

extension MoreMenuRow where Trailing == EmptyView {
    init(systemImage: String, titleKey: String, subtitleKey: String? = nil, isDestructive: Bool = false, action: @escaping () -> Void) {
        self.init(systemImage: systemImage, titleKey: titleKey, subtitleKey: subtitleKey, isDestructive: isDestructive, trailing: { EmptyView() }, action: action)
    }
}

private struct MoreIconTile: View {
    let systemImage: String
    var isActive: Bool = false
    var isDestructive: Bool = false

    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(isActive ? Color.dsAccentSoft : Color.primary.opacity(0.06))
            .frame(width: 28, height: 28)
            .overlay {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isDestructive ? Color.red : (isActive ? Color.dsAccent : Color.dsTextSecondary))
            }
    }
}

private struct MoreChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.dsTextSecondary.opacity(0.7))
    }
}

private struct MoreShortcut: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.system(size: 11, design: .rounded))
            .foregroundStyle(Color.dsTextSecondary)
    }
}
