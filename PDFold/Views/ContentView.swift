import SwiftUI
import PDFKit
import UniformTypeIdentifiers

struct ContentView: View {
    var document: WorkspaceDocument
    @State private var viewModel: WorkspaceViewModel
    @State private var showInspector = false
    @State private var showTOC = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @Environment(\.undoManager) private var undoManager

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
                    SidebarView(viewModel: viewModel)
                        .navigationSplitViewColumnWidth(min: 200, ideal: 260, max: 320)
                } detail: {
                    HStack(spacing: 0) {
                        ReadingCanvas(viewModel: viewModel)
                        if showInspector {
                            Rectangle().fill(Color.dsSeparator).frame(width: 0.5)
                            InspectorView(viewModel: viewModel)
                                .frame(width: 240)
                        }
                    }
                    .animation(.easeInOut(duration: 0.18), value: showInspector)
                }
                .navigationTitle(viewModel.document.workspace.title)
                .toolbar { mainToolbar }
            }
        }
        .animation(.easeInOut(duration: 0.18), value: viewModel.memberDocuments.isEmpty)
        .tint(Color.dsAccent)
        .onDrop(of: WorkspaceDocument.importableContentTypes + [.fileURL], isTargeted: nil, perform: handleDrop)
        .onAppear { viewModel.undoManager = undoManager }
        .onChange(of: undoManager) { _, um in viewModel.undoManager = um }
        .popover(isPresented: $viewModel.isShowingSearch, arrowEdge: .top) {
            SearchView(viewModel: viewModel)
        }
        .popover(isPresented: $viewModel.isShowingSignaturePalette, arrowEdge: .top) {
            SignaturePalette(viewModel: viewModel)
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
        // Leading: brand + add source files
        ToolbarItem(placement: .navigation) {
            AppIconButton(size: 22)
        }

        ToolbarItem(placement: .navigation) {
            Button { openFiles() } label: {
                Label("Add Files", systemImage: "plus.circle")
            }
            .help("Add files (⌘O)")
            .keyboardShortcut("o", modifiers: .command)
        }

        // Center: annotation tools + color swatch
        ToolbarItem(placement: .principal) {
            HStack(spacing: .dsSM) {
                AnnotationToolPicker(selection: $viewModel.currentTool)

                if viewModel.currentTool.isColorable {
                    AnnotationColorButton(viewModel: viewModel)
                        .transition(.opacity.combined(with: .scale(scale: 0.85)))
                }
            }
            .animation(.easeInOut(duration: 0.15), value: viewModel.currentTool.isColorable)
        }

        // Trailing primary: Share + Inspector
        ToolbarItemGroup(placement: .primaryAction) {
            Menu {
                ForEach(WorkspaceExportFormat.allCases) { format in
                    Button("Export as \(format.menuTitle)…") {
                        viewModel.exportWorkspace(as: format)
                    }
                }
                Divider()
                Button("Print…") {
                    NotificationCenter.default.post(name: .pdfoldPrint, object: nil)
                }
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .help("Export / Print (⌘⇧E)")
            .keyboardShortcut("e", modifiers: [.command, .shift])

            Button { showInspector.toggle() } label: {
                Label("Inspector", systemImage: "sidebar.right")
            }
            .help("Toggle inspector")
        }

        // Trailing secondary: nav tools
        ToolbarItemGroup(placement: .primaryAction) {
            Divider()

            Button { showTOC.toggle() } label: {
                Label("Contents", systemImage: "list.bullet.rectangle.portrait")
            }
            .help("Table of contents")

            Button {
                viewModel.isShowingSignaturePalette.toggle()
                viewModel.currentTool = .signature
            } label: {
                Label("Signature", systemImage: "signature")
            }
            .help("Place signature")

            Button { viewModel.isShowingSearch.toggle() } label: {
                Label("Search", systemImage: "magnifyingglass")
            }
            .help("Search (⌘F)")
            .keyboardShortcut("f", modifiers: .command)

            GuideButton(autoShow: true)
        }
    }

    // MARK: - Helpers

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        resolveImportURLs(from: providers) { viewModel.importFiles(urls: $0) }
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

private struct AnnotationToolPicker: View {
    @Binding var selection: AnnotationTool
    @State private var hoveredTool: AnnotationTool?
    @State private var popoverTool: AnnotationTool?
    @State private var hoverTask: Task<Void, Never>?

    private let tools: [AnnotationTool] = [
        .none, .highlight, .note, .editText, .ink, .underline, .strikeout
    ]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(tools) { tool in
                Button {
                    selection = tool
                } label: {
                    Image(systemName: tool.iconName)
                        .font(.system(size: 16, weight: .medium))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(selection == tool ? Color.white : Color.dsTextSecondary)
                        .frame(width: 32, height: 28)
                        .contentShape(RoundedRectangle(cornerRadius: .dsRadiusSm, style: .continuous))
                }
                .buttonStyle(.plain)
                .background {
                    if selection == tool {
                        RoundedRectangle(cornerRadius: .dsRadiusSm, style: .continuous)
                            .fill(Color.dsAccent.opacity(0.82))
                    }
                }
                .popover(isPresented: popoverBinding(for: tool), arrowEdge: .bottom) {
                    AnnotationToolPopover(tool: tool)
                }
                .onHover { isHovered in
                    updatePopoverHover(isHovered, for: tool)
                }
                .help(tool.label)
            }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 4)
        .background(.bar, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.dsSeparator, lineWidth: 1))
        .help("Annotation tool")
    }

    private func popoverBinding(for tool: AnnotationTool) -> Binding<Bool> {
        Binding {
            popoverTool == tool
        } set: { isPresented in
            if !isPresented, popoverTool == tool {
                popoverTool = nil
            }
        }
    }

    private func updatePopoverHover(_ isHovered: Bool, for tool: AnnotationTool) {
        hoverTask?.cancel()

        if isHovered {
            hoveredTool = tool
            hoverTask = Task {
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    if hoveredTool == tool {
                        popoverTool = tool
                    }
                }
            }
        } else if hoveredTool == tool {
            hoveredTool = nil
            popoverTool = nil
        }
    }
}

private struct AnnotationToolPopover: View {
    var tool: AnnotationTool

    var body: some View {
        VStack(alignment: .leading, spacing: .dsXS) {
            HStack(spacing: .dsSM) {
                Image(systemName: tool.iconName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.dsAccent)
                    .frame(width: 18)
                Text(tool.label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.dsTextPrimary)
            }

            Text(tool.helpText)
                .font(.dsCaption())
                .foregroundStyle(Color.dsTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: 220, alignment: .leading)
        .padding(.dsMD)
        .background(Color.dsSurface)
    }
}

// MARK: - Annotation color picker button

private struct AnnotationColorButton: View {
    @Bindable var viewModel: WorkspaceViewModel
    @State private var showPalette = false

    private var displayColor: Color {
        viewModel.currentTool.usesInkColor
            ? Color(nsColor: viewModel.inkColor)
            : Color(nsColor: viewModel.annotationColor)
    }

    var body: some View {
        Button { showPalette.toggle() } label: {
            Circle()
                .fill(displayColor)
                .frame(width: 20, height: 20)
                .overlay(Circle().strokeBorder(Color.dsSeparator, lineWidth: 1))
        }
        .buttonStyle(.plain)
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
    var urls: [URL] = []
    let lock = DispatchQueue(label: "PDFold.importURLs")
    let group = DispatchGroup()
    for provider in providers {
        guard provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else { continue }
        group.enter()
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            defer { group.leave() }
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil),
                  isSupportedImportURL(url) else { return }
            lock.sync { urls.append(url) }
        }
    }
    group.notify(queue: .main) { completion(urls) }
}

func isSupportedImportURL(_ url: URL) -> Bool {
    guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
    return WorkspaceDocument.importableContentTypes.contains { type.conforms(to: $0) }
}
