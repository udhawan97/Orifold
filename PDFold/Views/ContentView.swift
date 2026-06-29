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
            if viewModel.document.workspace.documents.isEmpty {
                EmptyStateView(viewModel: viewModel)
            } else {
                NavigationSplitView(columnVisibility: $columnVisibility) {
                    SidebarView(viewModel: viewModel)
                        .navigationSplitViewColumnWidth(min: 210, ideal: 270, max: 340)
                } detail: {
                    HStack(spacing: 0) {
                        ReadingCanvas(viewModel: viewModel)
                        if showInspector {
                            Divider()
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
        .animation(.easeInOut(duration: 0.18), value: viewModel.document.workspace.documents.isEmpty)
        .tint(Color.accentColor)
        .onDrop(of: WorkspaceDocument.importableContentTypes + [.fileURL], isTargeted: nil, perform: handleDrop)
        .onAppear { viewModel.undoManager = undoManager }
        .onChange(of: undoManager) { _, um in viewModel.undoManager = um }
        // Search popover
        .popover(isPresented: $viewModel.isShowingSearch, arrowEdge: .top) {
            SearchView(viewModel: viewModel)
        }
        // Signature palette popover
        .popover(isPresented: $viewModel.isShowingSignaturePalette, arrowEdge: .top) {
            SignaturePalette(viewModel: viewModel)
        }
        // TOC popover
        .popover(isPresented: $showTOC, arrowEdge: .top) {
            TOCView(viewModel: viewModel) { pageIndex in
                NotificationCenter.default.post(
                    name: .pdfoldJumpToPageIndex,
                    object: pageIndex
                )
                showTOC = false
            }
        }
        // Import error
        .alert("Import Error", isPresented: Binding(
            get: { viewModel.importError != nil },
            set: { if !$0 { viewModel.importError = nil } }
        ), presenting: viewModel.importError) { _ in
            Button("OK") { viewModel.importError = nil }
        } message: { err in
            Text(err.message)
        }
        // Password prompt
        .sheet(isPresented: $viewModel.isShowingPasswordPrompt) {
            if let url = viewModel.pendingPasswordURL,
               let pdf = PDFDocument(url: url) {
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
        // Leading: app icon (tappable) + add source files
        ToolbarItemGroup(placement: .navigation) {
            AppIconButton(size: 24)

            Button { openFiles() } label: {
                Label("Add Files", systemImage: "plus.circle")
            }
            .help("Add PDF, Word, HTML, text, or image files (⌘O)")
            .keyboardShortcut("o", modifiers: .command)
        }

        // Center: annotation tools
        ToolbarItemGroup(placement: .principal) {
            Picker("Tool", selection: $viewModel.currentTool) {
                ForEach([AnnotationTool.none, .highlight, .note, .ink]) { tool in
                    Label(tool.label, systemImage: tool.rawValue).tag(tool)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 240)
            .help("Annotation tool")
        }

        // Trailing: TOC, signature, search, inspector, export menus
        ToolbarItemGroup(placement: .primaryAction) {
            Button { showTOC.toggle() } label: {
                Label("Contents", systemImage: "list.bullet.indent")
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
            .help("Search workspace (⌘F)")
            .keyboardShortcut("f", modifiers: .command)

            GuideButton(autoShow: true)

            Button { showInspector.toggle() } label: {
                Label("Inspector", systemImage: "sidebar.right")
            }
            .help("Toggle inspector")

            Menu {
                Button("Export as PDF…") { viewModel.exportPlainPDF() }
                Button("Export as PDFold Bundle…") { viewModel.exportPDFoldBundle() }
                Divider()
                Button("Print…") {
                    NotificationCenter.default.post(name: .pdfoldPrint, object: nil)
                }
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .help("Export / Print (⌘⇧E)")
            .keyboardShortcut("e", modifiers: [.command, .shift])
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
