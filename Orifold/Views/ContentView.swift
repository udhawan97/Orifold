import SwiftUI
import PDFKit
import UniformTypeIdentifiers
import AppKit

struct ContentView: View {
    var document: WorkspaceDocument
    @State private var viewModel: WorkspaceViewModel
    @State private var showInspector = false
    @State private var inspectorTab: InspectorView.Tab = .info
    @State private var showTOC = false
    @State private var isShowingExportSheet = false
    @State private var isWorkspaceDropTargeted = false
    @State private var isNavigationDropTargeted = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @AppStorage("orifoldNightModeEnabled") private var persistedNightModeEnabled = false
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
            viewModel.isNightModeEnabled = persistedNightModeEnabled
        }
        .onChange(of: undoManager) { _, um in viewModel.undoManager = um }
        .onChange(of: viewModel.isNightModeEnabled) { _, enabled in
            persistedNightModeEnabled = enabled
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
        .alert("Import Error", isPresented: Binding(
            get: { viewModel.importError != nil },
            set: { if !$0 { viewModel.importError = nil } }
        ), presenting: viewModel.importError) { _ in
            Button("OK") { viewModel.importError = nil }
        } message: { err in
            Text(err.message)
        }
        .alert("Export Error", isPresented: Binding(
            get: { viewModel.exportError != nil },
            set: { if !$0 { viewModel.exportError = nil } }
        ), presenting: viewModel.exportError) { _ in
            Button("OK") { viewModel.exportError = nil }
        } message: { err in
            Text(err.message)
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
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var mainToolbar: some ToolbarContent {
        // Leading: add source files
        ToolbarItem(placement: .navigation) {
            Button { openFiles() } label: {
                Label("Add Files", systemImage: "plus.circle")
            }
            .acceptsImportDrops { providers in
                handleDrop(providers: providers)
            }
            .help("Add files to this workspace (⌘⇧O)")
            .keyboardShortcut("o", modifiers: [.command, .shift])
        }

        // Header navigation: keep document structure near the title.
        ToolbarItem(placement: .navigation) {
            Button { showTOC.toggle() } label: {
                Label("Contents", systemImage: "list.bullet.rectangle.portrait")
            }
            .acceptsImportDrops { providers in
                handleDrop(providers: providers)
            }
            .help("Table of contents")
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
            Button { viewModel.isShowingSearch.toggle() } label: {
                Label("Search", systemImage: "magnifyingglass")
            }
            .acceptsImportDrops { providers in
                handleDrop(providers: providers)
            }
            .help("Search (⌘F)")
            .keyboardShortcut("f", modifiers: .command)

            Menu {
                Button("Export…") {
                    isShowingExportSheet = true
                }
                Divider()
                Button("Print…") {
                    NotificationCenter.default.post(name: .orifoldPrint, object: nil)
                }
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .acceptsImportDrops { providers in
                handleDrop(providers: providers)
            }
            .help("Export / Print (⌘⇧E)")
            .keyboardShortcut("e", modifiers: [.command, .shift])

            Button { showInspector.toggle() } label: {
                Label("Inspector", systemImage: "sidebar.right")
            }
            .acceptsImportDrops { providers in
                handleDrop(providers: providers)
            }
            .help("Toggle inspector")

            Button {
                viewModel.isNightModeEnabled.toggle()
            } label: {
                Label("Night Mode", systemImage: viewModel.isNightModeEnabled ? "moon.stars.fill" : "moon.stars")
            }
            .acceptsImportDrops { providers in
                handleDrop(providers: providers)
            }
            .help(viewModel.isNightModeEnabled ? "Turn off night document tone" : "Dim and warm document pages for night reading")

            GuideButton(autoShow: true)
                .acceptsImportDrops { providers in
                    handleDrop(providers: providers)
                }
        }
    }

    // MARK: - Helpers

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
                            Text("Drop to add documents")
                                .font(.dsHeadline())
                                .foregroundStyle(Color.dsAccent)
                            Text("Up to 50 files at a time")
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
            return "Password is missing. Enter a password."
        }
        if passwordConfirmation.isEmpty {
            return "Confirmation is missing. Re-enter the password."
        }
        if passwordMismatch {
            return "Passwords do not match. Re-enter the confirmation."
        }
        return nil
    }

    private var canExport: Bool {
        guard protectWithPassword && canProtectSelectedFormat else { return true }
        return !password.isEmpty && password == passwordConfirmation
    }

    var body: some View {
        VStack(alignment: .leading, spacing: .dsLG) {
            Text("Export")
                .font(.dsTitle())
                .foregroundStyle(Color.dsTextPrimary)

            Picker("Format", selection: $selectedFormat) {
                ForEach(WorkspaceExportFormat.allCases) { format in
                    Text(format.menuTitle).tag(format)
                }
            }
            .pickerStyle(.menu)

            VStack(alignment: .leading, spacing: .dsSM) {
                DisclosureGroup(isExpanded: $isProtectionExpanded) {
                    VStack(alignment: .leading, spacing: .dsSM) {
                        SecureField("Password", text: $password)
                            .textFieldStyle(.roundedBorder)
                            .disabled(!protectWithPassword || !canProtectSelectedFormat)
                        SecureField("Confirm password", text: $passwordConfirmation)
                            .textFieldStyle(.roundedBorder)
                            .disabled(!protectWithPassword || !canProtectSelectedFormat)

                        Toggle("Allow printing", isOn: $allowsPrinting)
                            .disabled(!protectWithPassword || !canProtectSelectedFormat)
                        Toggle("Allow copying", isOn: $allowsCopying)
                            .disabled(!protectWithPassword || !canProtectSelectedFormat)

                        if let passwordValidationMessage {
                            Text(passwordValidationMessage)
                                .font(.dsCaption())
                                .foregroundStyle(Color.dsAnnotationCoral)
                        }
                    }
                    .padding(.top, .dsSM)
                } label: {
                    Toggle("Protect with password", isOn: Binding(
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
                    Text("Password protection is available for PDF exports.")
                        .font(.dsCaption())
                        .foregroundStyle(Color.dsTextTertiary)
                } else if viewModel.hasCryptographicSignaturePlacement {
                    Text("Password protection is unavailable because this PDF has a digital signature.")
                        .font(.dsCaption())
                        .foregroundStyle(Color.dsTextTertiary)
                }
            }
            .animation(shouldReduceMotion ? nil : .easeInOut(duration: 0.16), value: isProtectionExpanded)
            .animation(shouldReduceMotion ? nil : .easeInOut(duration: 0.16), value: protectWithPassword)
            .onChange(of: selectedFormat) { _, _ in
                if !canProtectSelectedFormat {
                    protectWithPassword = false
                }
                if selectedFormat != .pdf {
                    reduceFileSize = false
                }
            }

            DisclosureGroup(isExpanded: $isCompressionExpanded) {
                Picker("Preset", selection: $compressionPreset) {
                    ForEach(PDFCompressionPreset.allCases) { preset in
                        Text(preset.label).tag(preset)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(!reduceFileSize || selectedFormat != .pdf)
                .padding(.top, .dsSM)

                if selectedFormat != .pdf {
                    Text("File-size reduction is available for PDF exports.")
                        .font(.dsCaption())
                        .foregroundStyle(Color.dsTextTertiary)
                }
            } label: {
                Toggle("Reduce file size", isOn: Binding(
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

            if viewModel.hasFillableFormFields && selectedFormat == .pdf {
                DisclosureGroup(isExpanded: $isFormLockExpanded) {
                    Toggle("Lock form answers in place", isOn: $lockFormAnswers)
                        .padding(.top, .dsSM)
                } label: {
                    Text("Lock form answers in place")
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
                Button("Cancel") {
                    isPresented = false
                }
                Button("Export") {
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
                Button("Cancel", action: cancel)
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

    var body: some View {
        HStack(spacing: 2) {
            ForEach(toolGroups.indices, id: \.self) { groupIndex in
                if groupIndex > 0 {
                    groupDivider
                }
                ForEach(toolGroups[groupIndex]) { tool in
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
        .help("Annotation color")
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
let importBatchPanelMessage = "Select up to 50 files. Larger batches can be added after this import finishes."
let importBatchLimitMessage = "Only 50 files can be added at a time. The first 50 from this selection will be added. To add more, run Add Files again after this import finishes."
let importDropProviderLimitMessage = "Orifold prepared 50 files from this drop. If you expected more, run another import after this one finishes."

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
        completion(url)
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
            .help(count == 1 ? "View 1 comment" : "View \(count) comments")
            .accessibilityLabel(count == 1 ? "View 1 comment" : "View \(count) comments")
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
