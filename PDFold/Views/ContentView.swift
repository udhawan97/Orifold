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
                    SidebarView(viewModel: viewModel, onImportDrop: handleDrop)
                        .navigationSplitViewColumnWidth(min: 200, ideal: 260, max: 320)
                } detail: {
                    HStack(spacing: 0) {
                        ReadingCanvas(viewModel: viewModel)
                            .overlay(alignment: .topTrailing) {
                                DocumentCommentsIndicator(count: viewModel.totalCommentCount) {
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
                        of: WorkspaceDocument.importableContentTypes + [.fileURL],
                        isTargeted: $isWorkspaceDropTargeted,
                        perform: handleDrop
                    )
                }
                .navigationTitle(viewModel.document.workspace.title)
                .toolbar { mainToolbar }
            }
        }
        .animation(shouldReduceMotion ? nil : .easeInOut(duration: 0.18), value: viewModel.memberDocuments.isEmpty)
        .tint(Color.dsAccent)
        .overlay(alignment: .bottomTrailing) { PetOverlay().padding(18) }
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
        .focusedSceneValue(\.pdfoldIsImporting, viewModel.isImporting)
        .focusedSceneValue(\.pdfoldWorkspaceViewModel, viewModel)
        .onAppear { viewModel.undoManager = undoManager }
        .onChange(of: undoManager) { _, um in viewModel.undoManager = um }
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
                NotificationCenter.default.post(name: .pdfoldJumpToPageIndex, object: pageIndex)
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
            .acceptsImportDrops(perform: handleDrop)
            .help("Add files (⌘O)")
            .keyboardShortcut("o", modifiers: .command)
        }

        // Header navigation: keep document structure near the title.
        ToolbarItem(placement: .navigation) {
            Button { showTOC.toggle() } label: {
                Label("Contents", systemImage: "list.bullet.rectangle.portrait")
            }
            .acceptsImportDrops(perform: handleDrop)
            .help("Table of contents")
        }

        // Center: annotation tools + color swatch
        ToolbarItem(placement: .principal) {
            AnnotationToolPicker(viewModel: viewModel)
                .acceptsImportDrops(isTargeted: $isNavigationDropTargeted, showsHighlight: true, perform: handleDrop)
        }

        // Trailing: search, document actions, view controls, help
        ToolbarItemGroup(placement: .primaryAction) {
            Button { viewModel.isShowingSearch.toggle() } label: {
                Label("Search", systemImage: "magnifyingglass")
            }
            .acceptsImportDrops(perform: handleDrop)
            .help("Search (⌘F)")
            .keyboardShortcut("f", modifiers: .command)

            Menu {
                Button("Export…") {
                    isShowingExportSheet = true
                }
                Divider()
                Button("Print…") {
                    NotificationCenter.default.post(name: .pdfoldPrint, object: nil)
                }
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .acceptsImportDrops(perform: handleDrop)
            .help("Export / Print (⌘⇧E)")
            .keyboardShortcut("e", modifiers: [.command, .shift])

            Button { showInspector.toggle() } label: {
                Label("Inspector", systemImage: "sidebar.right")
            }
            .acceptsImportDrops(perform: handleDrop)
            .help("Toggle inspector")

            GuideButton(autoShow: true)
                .acceptsImportDrops(perform: handleDrop)
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
                            Text("Drop to add documents")
                                .font(.dsHeadline())
                        }
                        .foregroundStyle(Color.dsAccent)
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

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
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

    private func openFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = WorkspaceDocument.importableContentTypes
        if panel.runModal() == .OK { viewModel.importFiles(urls: panel.urls) }
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
                ownerPassword: "pdFold-owner-\(UUID().uuidString)",
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

    var body: some View {
        HStack(spacing: .dsMD) {
            ProgressView(value: progress.fraction)
                .progressViewStyle(.linear)
                .frame(width: 150)
            VStack(alignment: .leading, spacing: 2) {
                Text(progress.title)
                    .font(.dsCaption())
                    .foregroundStyle(Color.dsTextPrimary)
                if !progress.detail.isEmpty {
                    Text(progress.detail)
                        .font(.dsCaption())
                        .foregroundStyle(Color.dsTextSecondary)
                }
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
    }
}

private struct AnnotationToolPicker: View {
    @Bindable var viewModel: WorkspaceViewModel
    @State private var hoveredTool: AnnotationTool?
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
        HStack(spacing: 9) {
            ForEach(toolGroups.indices, id: \.self) { groupIndex in
                let tools = toolGroups[groupIndex]
                toolGroup(tools, style: groupStyle(for: tools))
            }

            AnnotationColorButton(viewModel: viewModel)
                .opacity(viewModel.currentTool.isColorable ? 1 : 0)
                .scaleEffect(viewModel.currentTool.isColorable ? 1 : 0.92)
                .allowsHitTesting(viewModel.currentTool.isColorable)
                .accessibilityHidden(!viewModel.currentTool.isColorable)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(Color.dsSeparator, lineWidth: 1)
        )
        .shadow(color: Color.dsTextPrimary.opacity(0.10), radius: 8, x: 0, y: 2)
        .help("Annotation tool")
        .animation(shouldReduceMotion ? nil : .spring(response: 0.31, dampingFraction: 0.79), value: viewModel.currentTool)
    }

    private func toolGroup(_ tools: [AnnotationTool], style: ToolGroupStyle) -> some View {
        HStack(spacing: 4) {
            ForEach(tools) { tool in
                toolButton(tool, shouldReduceMotion: shouldReduceMotion)
            }
        }
        .padding(.horizontal, style.horizontalPadding)
        .background {
            if let fill = style.fill {
                Capsule()
                    .fill(fill)
                    .overlay(
                        Capsule()
                            .strokeBorder(style.stroke, lineWidth: 1)
                    )
            }
        }
    }

    @ViewBuilder
    private func toolButton(_ tool: AnnotationTool, shouldReduceMotion: Bool) -> some View {
        let isSelected = viewModel.currentTool == tool
        let isHovered = hoveredTool == tool
        let accent = toolAccent(for: tool)
        let hoverFill = toolHoverFill(for: tool)

        Button {
            select(tool)
        } label: {
            ZStack {
                if isSelected {
                    Capsule()
                        .fill(accent)
                        .matchedGeometryEffect(id: "selectedTool", in: selectionNamespace)
                }

                toolIcon(tool, isSelected: isSelected)
                    .foregroundStyle(isSelected ? Color.dsSurface : Color.dsTextSecondary)
            }
            .frame(width: 32, height: 32)
            .contentShape(Capsule())
        }
        .buttonStyle(ToolButtonStyle(isHovered: isHovered, isSelected: isSelected, hoverFill: hoverFill, reduceMotion: shouldReduceMotion))
        .onHover { isHovered in
            if isHovered {
                hoveredTool = tool
            } else if hoveredTool == tool {
                hoveredTool = nil
            }
        }
        .help(tool.helpText)
        .accessibilityLabel(tool.label)
    }

    private func groupStyle(for tools: [AnnotationTool]) -> ToolGroupStyle {
        guard tools.count == 1, let tool = tools.first, tool.isServiceTool else {
            return ToolGroupStyle()
        }

        return ToolGroupStyle(
            horizontalPadding: 3,
            fill: toolServiceFill(for: tool),
            stroke: toolAccent(for: tool).opacity(0.18)
        )
    }

    private func toolAccent(for tool: AnnotationTool) -> Color {
        switch tool {
        case .editText:
            return Color.dsEditTextAccent
        case .signature, .stamp:
            return Color.dsSignatureAccent
        case .comment, .commentRegion:
            return Color.dsAccent
        default:
            return Color.dsAccent
        }
    }

    private func toolServiceFill(for tool: AnnotationTool) -> Color {
        switch tool {
        case .editText:
            return Color.dsEditTextSoft
        case .signature, .stamp:
            return Color.dsSignatureSoft
        case .comment, .commentRegion:
            return Color.dsAccentSoft
        default:
            return Color.dsAccentSoft
        }
    }

    private func toolHoverFill(for tool: AnnotationTool) -> Color {
        switch tool {
        case .editText:
            return Color.dsEditTextHover
        case .signature, .stamp:
            return Color.dsSignatureHover
        case .comment, .commentRegion:
            return Color.dsAccentSoft
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
    }

    @ViewBuilder
    private func toolIcon(_ tool: AnnotationTool, isSelected: Bool) -> some View {
        if tool == .highlight {
            HighlightGlyph(isSelected: isSelected)
        } else {
            Image(systemName: tool.iconName)
                .font(.system(size: tool == .none ? 15 : 17, weight: .semibold))
                .symbolRenderingMode(.monochrome)
        }
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
                    Capsule()
                        .fill(hoverFill)
                }
            }
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovered)
    }
}

private struct ToolGroupStyle {
    var horizontalPadding: CGFloat = 0
    var fill: Color?
    var stroke: Color = Color.clear
}

private extension AnnotationTool {
    var isServiceTool: Bool {
        self == .editText || self == .signature || self == .comment
    }
}

private struct HighlightGlyph: View {
    var isSelected: Bool

    var body: some View {
        ZStack(alignment: .bottom) {
            Image(systemName: "highlighter")
                .font(.system(size: 15, weight: .semibold))
                .symbolRenderingMode(.monochrome)

            Capsule()
                .fill(isSelected ? Color.white.opacity(0.65) : Color.dsHighlightYellow)
                .frame(width: 17, height: 3)
                .offset(y: 3)
        }
        .frame(width: 19, height: 18)
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
                    .frame(width: 24, height: 24)
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.72), lineWidth: 1))
                    .shadow(color: Color.black.opacity(0.18), radius: 2, x: 0, y: 1)
            }
            .frame(width: 36, height: 32)
            .contentShape(RoundedRectangle(cornerRadius: .dsRadiusMd, style: .continuous))
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

func resolveImportURLs(from providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) {
    var resolvedURLs: [(index: Int, url: URL)] = []
    let lock = DispatchQueue(label: "PDFold.importURLs")
    let group = DispatchGroup()

    for (index, provider) in providers.enumerated() {
        group.enter()

        loadImportURL(from: provider) { url in
            defer { group.leave() }
            guard let url, isSupportedImportURL(url) else { return }
            lock.sync { resolvedURLs.append((index, url)) }
        }
    }

    group.notify(queue: .main) {
        let urls = resolvedURLs
            .sorted { $0.index < $1.index }
            .map(\.url)
            .uniquedByFileURL()
        completion(urls)
    }
}

private func loadImportURL(from provider: NSItemProvider, completion: @escaping (URL?) -> Void) {
    if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            completion(urlFromProviderItem(item))
        }
        return
    }

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
        .appendingPathComponent("PDFoldDrops", isDirectory: true)
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
            let key = url.isFileURL ? url.standardizedFileURL.path : url.absoluteString
            return seen.insert(key).inserted
        }
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
                of: WorkspaceDocument.importableContentTypes + [.fileURL],
                isTargeted: isTargeted,
                perform: perform
            )
    }
}
