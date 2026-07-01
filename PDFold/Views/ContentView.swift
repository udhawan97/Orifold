import SwiftUI
import PDFKit
import UniformTypeIdentifiers

struct ContentView: View {
    var document: WorkspaceDocument
    @State private var viewModel: WorkspaceViewModel
    @State private var showInspector = false
    @State private var showTOC = false
    @State private var isWorkspaceDropTargeted = false
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
                                .frame(width: 280)
                        }
                    }
                    .animation(.easeInOut(duration: 0.18), value: showInspector)
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
        .animation(.easeInOut(duration: 0.18), value: viewModel.memberDocuments.isEmpty)
        .tint(Color.dsAccent)
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
        // Leading: add source files
        ToolbarItem(placement: .navigation) {
            Button { openFiles() } label: {
                Label("Add Files", systemImage: "plus.circle")
            }
            .help("Add files (⌘O)")
            .keyboardShortcut("o", modifiers: .command)
        }

        // Center: annotation tools + color swatch
        ToolbarItem(placement: .principal) {
            AnnotationToolPicker(viewModel: viewModel)
        }

        // Trailing primary: Save as PDF + Share + Inspector
        ToolbarItemGroup(placement: .primaryAction) {
            Button { viewModel.saveFlattenedPDF() } label: {
                Label("Save as PDF", systemImage: "arrow.down.doc.fill")
            }
            .help("Save as PDF\u{2026} (\u{2318}\u{21E7}S)")

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
            .animation(.easeInOut(duration: 0.15), value: isWorkspaceDropTargeted)
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

private struct AnnotationToolPicker: View {
    @Bindable var viewModel: WorkspaceViewModel
    @State private var hoveredTool: AnnotationTool?
    @State private var popoverTool: AnnotationTool?
    @State private var hoverTask: Task<Void, Never>?

    private let tools: [AnnotationTool] = [
        .none, .highlight, .note, .editText, .ink, .underline, .strikeout
    ]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(tools) { tool in
                toolButton(tool)
                .popover(isPresented: popoverBinding(for: tool), arrowEdge: .bottom) {
                    AnnotationToolPopover(tool: tool)
                }
                .onHover { isHovered in
                    updatePopoverHover(isHovered, for: tool)
                }
                .help(tool.label)
            }

            if viewModel.currentTool.isColorable {
                Divider()
                    .frame(height: 22)
                    .padding(.horizontal, 3)
                AnnotationColorButton(viewModel: viewModel)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(.regularMaterial, in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(Color.dsSeparator.opacity(0.75), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.16), radius: 10, x: 0, y: 4)
        .help("Annotation tool")
    }

    @ViewBuilder
    private func toolButton(_ tool: AnnotationTool) -> some View {
        let isSelected = viewModel.currentTool == tool

        Button {
            viewModel.currentTool = tool
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: .dsRadiusMd, style: .continuous)
                    .fill(isSelected ? Color.dsAccent : Color.clear)
                toolIcon(tool, isSelected: isSelected)
            }
            .frame(width: tool == .editText ? 50 : 36, height: 32)
            .contentShape(RoundedRectangle(cornerRadius: .dsRadiusMd, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func toolIcon(_ tool: AnnotationTool, isSelected: Bool) -> some View {
        let foreground = isSelected ? Color.white : Color.dsTextSecondary

        if tool == .editText {
            Text("Aa")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(foreground)
        } else {
            Image(systemName: tool.iconName)
                .font(.system(size: tool == .none ? 15 : 17, weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(foreground)
        }
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
            ZStack {
                RoundedRectangle(cornerRadius: .dsRadiusMd, style: .continuous)
                    .fill(showPalette ? Color.dsTextPrimary.opacity(0.12) : Color.clear)
                Circle()
                    .fill(displayColor)
                    .frame(width: 24, height: 24)
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.72), lineWidth: 1))
                    .shadow(color: Color.black.opacity(0.18), radius: 2, x: 0, y: 1)
            }
            .frame(width: 36, height: 32)
            .contentShape(RoundedRectangle(cornerRadius: .dsRadiusMd, style: .continuous))
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

private extension Array where Element == URL {
    func uniquedByFileURL() -> [URL] {
        var seen: Set<String> = []
        return filter { url in
            let key = url.isFileURL ? url.standardizedFileURL.path : url.absoluteString
            return seen.insert(key).inserted
        }
    }
}
