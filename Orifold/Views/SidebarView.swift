import SwiftUI
import PDFKit
import UniformTypeIdentifiers
import AppKit

struct SidebarView: View {
    var viewModel: WorkspaceViewModel
    var onImportDrop: ([NSItemProvider], UUID?) -> Bool = { _, _ in false }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expandedDocs: Set<UUID> = []
    @State private var isImportDropTargeted = false
    @State private var dropZoneErrorFlash = false
    @State private var dropZoneErrorFlashWorkItem: DispatchWorkItem?
    // Read so SwiftUI re-invokes `body` when the app language changes; the sidebar's
    // inputs are otherwise stable, so without a `\.locale` read its localized text
    // (and that of its child rows) would stay in the previous language.
    @Environment(\.locale) private var locale

    private var shouldReduceMotion: Bool {
        reduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || viewModel.documentComfortSettings.reduceAnimations
    }

    var body: some View {
        let _ = locale
        VStack(spacing: 0) {
            WorkspaceHeaderCard(viewModel: viewModel, expandedDocs: $expandedDocs)
                .padding(.horizontal, 10)
                .padding(.top, .dsSM)
                .padding(.bottom, .dsXS)
                .onDrop(of: importDropContentTypes, isTargeted: $isImportDropTargeted) { providers in
                    onImportDrop(providers, nil)
                }

            CreaseRule().padding(.horizontal, .dsMD)

            documentsList

            CreaseRule().padding(.horizontal, .dsMD)

            SidebarDropZone(
                isImporting: viewModel.isImporting,
                errorFlash: dropZoneErrorFlash,
                reduceAnimations: viewModel.documentComfortSettings.reduceAnimations,
                onOpenPanel: { openFilesForImport(into: viewModel) },
                onDrop: { providers in onImportDrop(providers, nil) }
            )
            .padding(.horizontal, 10)
            .padding(.vertical, .dsSM)
        }
        .background(Color.dsSurface)
        .contentShape(Rectangle())
        .overlay { importDropOverlay }
        .onDrop(
            of: importDropContentTypes,
            isTargeted: $isImportDropTargeted,
        ) { providers in
            onImportDrop(providers, nil)
        }
        .onChange(of: viewModel.importError?.id) { _, newValue in
            guard newValue != nil, !shouldReduceMotion else { return }
            dropZoneErrorFlashWorkItem?.cancel()
            withAnimation(.easeInOut(duration: 0.2)) { dropZoneErrorFlash = true }
            let workItem = DispatchWorkItem {
                withAnimation(.easeInOut(duration: 0.3)) { dropZoneErrorFlash = false }
            }
            dropZoneErrorFlashWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: workItem)
        }
    }

    private var documentsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader

            // A plain ScrollView + LazyVStack rather than a `List`: on macOS a `List` with
            // `.onMove` is NSTableView-backed and its row-drag machinery swallows the nested
            // `.onDrag` on page thumbnails, so page-level reordering never fired. Custom
            // drag/drop here drives BOTH file-level and page-level reordering with a shared
            // insertion indicator and no gesture conflict.
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(viewModel.memberDocuments) { member in
                        MemberDocRow(
                            member: member,
                            viewModel: viewModel,
                            expandedDocs: $expandedDocs,
                            onImportDrop: { providers in onImportDrop(providers, member.pageRefs.last) }
                        )
                        .padding(.horizontal, 10)
                        .padding(.vertical, 2)
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollContentBackground(.hidden)
        }
        .frame(maxHeight: .infinity)
    }

    private var sectionHeader: some View {
        HStack(spacing: 4) {
            Text(L10n.string("sidebar.section.documents"))
                .font(.system(size: 11, weight: .semibold))
                .tracking(.dsLabelTracking)
                .textCase(.uppercase)
                .foregroundStyle(Color.dsTextTertiary)
            Text(verbatim: "· \(viewModel.memberDocuments.count)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.dsTextTertiary)
                .monospacedDigit()
            Spacer()
        }
        .padding(.leading, 18)
        .padding(.trailing, .dsMD)
        .padding(.top, .dsSM)
        .padding(.bottom, 2)
    }

    private var importDropOverlay: some View {
        RoundedRectangle(cornerRadius: .dsRadiusMd, style: .continuous)
            .strokeBorder(Color.dsAccent.opacity(isImportDropTargeted ? 0.55 : 0), lineWidth: 1.5)
            .background {
                if isImportDropTargeted {
                    ZStack {
                        Color.dsAccent.opacity(0.08)
                        VStack(spacing: .dsSM) {
                            Image(systemName: "tray.and.arrow.down.fill")
                                .font(.system(size: 26, weight: .light))
                                .symbolRenderingMode(.hierarchical)
                            Text(L10n.string("contentView.dropOverlay.title"))
                                .font(.dsHeadline())
                            Text(L10n.string("contentView.dropOverlay.subtitle"))
                                .font(.dsCaption())
                        }
                        .foregroundStyle(Color.dsAccent)
                        .padding(.horizontal, .dsLG)
                        .padding(.vertical, .dsMD)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: .dsRadiusMd, style: .continuous))
                    }
                }
            }
            .padding(.dsSM)
            .allowsHitTesting(false)
            .animation(shouldReduceMotion ? nil : .easeInOut(duration: 0.15), value: isImportDropTargeted)
    }
}

// MARK: - Workspace header card

private struct WorkspaceHeaderCard: View {
    var viewModel: WorkspaceViewModel
    @Binding var expandedDocs: Set<UUID>
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // Passed into L10n.string() below so this view's `body` actually reads it —
    // SwiftUI only re-invokes `body` on a locale change for views that read
    // `\.locale` during the previous evaluation.
    @Environment(\.locale) private var locale

    private var shouldReduceMotion: Bool {
        reduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || viewModel.documentComfortSettings.reduceAnimations
    }

    private var documentCount: Int { viewModel.document.workspace.documents.count }
    private var pageCount: Int { viewModel.document.workspace.pageOrder.count }
    private var commentCount: Int { viewModel.totalCommentCount }

    private var metadataLine: String {
        var parts = [
            "\(documentCount) " + L10n.string(documentCount == 1 ? "sidebar.metric.file" : "sidebar.metric.files", locale: locale),
            "\(pageCount) " + L10n.string(pageCount == 1 ? "sidebar.metric.page" : "sidebar.metric.pages", locale: locale),
        ]
        if commentCount > 0 {
            parts.append("\(commentCount) " + L10n.string(commentCount == 1 ? "sidebar.metric.comment" : "sidebar.metric.comments", locale: locale))
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: .dsSM) {
            HStack(spacing: .dsSM) {
                AppIconMark(size: 22)
                Text(viewModel.document.workspace.title)
                    .font(.dsDisplay(size: 13))
                    .tracking(.dsWordmarkTracking)
                    .foregroundStyle(Color.dsTextPrimary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.trailing, .dsXS)
                    .help(viewModel.document.workspace.title)
                    .accessibilityLabel(viewModel.document.workspace.title)
                overflowMenu
            }

            Text(metadataLine)
                .font(.system(size: 11))
                .foregroundStyle(Color.dsTextTertiary)
                .monospacedDigit()
                .lineLimit(1)

            addFilesButton
        }
        .padding(.dsMD)
        .foldedCard(fill: Color.dsCard.opacity(0.72))
    }

    private var addFilesButton: some View {
        Button(action: { openFilesForImport(into: viewModel) }) {
            Label(L10n.string("sidebar.addFiles.label"), systemImage: "plus")
                .font(.system(size: 12, weight: .semibold))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.dsAccent)
        .padding(.horizontal, .dsSM)
        .padding(.vertical, 5)
        .background(Color.dsAccentSoft, in: Capsule())
        .help(L10n.string("sidebar.addFiles.help"))
    }

    private var overflowMenu: some View {
        Menu {
            Button(L10n.string("sidebar.overflow.expandAll")) {
                withAnimation(shouldReduceMotion ? nil : .easeInOut(duration: 0.15)) {
                    expandedDocs = Set(viewModel.memberDocuments.map(\.id))
                }
            }
            Button(L10n.string("sidebar.overflow.collapseAll")) {
                withAnimation(shouldReduceMotion ? nil : .easeInOut(duration: 0.15)) {
                    expandedDocs = []
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.dsTextTertiary)
                .frame(width: 20, height: 20)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(L10n.string("sidebar.overflow.help"))
        .accessibilityLabel(L10n.string("sidebar.overflow.help", locale: locale))
    }
}

/// Shared by the header card's "Add Files" button and the drop-zone footer's own
/// click target — both just open a file picker and hand the result to the same import path.
private func openFilesForImport(into viewModel: WorkspaceViewModel) {
    let panel = NSOpenPanel()
    configureImportOpenPanel(panel)
    if panel.runModal() == .OK {
        importFilesWithBatchLimit(urls: panel.urls, into: viewModel)
    }
}

// MARK: - Drop zone footer

private struct SidebarDropZone: View {
    var isImporting: Bool
    var errorFlash: Bool
    var reduceAnimations: Bool
    var onOpenPanel: () -> Void
    var onDrop: ([NSItemProvider]) -> Bool

    @State private var isHovered = false
    @State private var isTargeted = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // Passed into L10n.string() below so this view's `body` actually reads it —
    // SwiftUI only re-invokes `body` on a locale change for views that read
    // `\.locale` during the previous evaluation.
    @Environment(\.locale) private var locale

    private var shouldReduceMotion: Bool {
        reduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || reduceAnimations
    }

    private var borderColor: Color {
        if errorFlash { return .dsErrorAccent }
        if isTargeted { return .dsAccent }
        if isHovered { return Color.dsAccent.opacity(0.45) }
        return Color.dsSeparator
    }

    var body: some View {
        Button(action: onOpenPanel) {
            HStack(spacing: .dsSM) {
                if isImporting {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "plus.rectangle.on.folder")
                        .font(.system(size: 15, weight: .light))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(isTargeted || isHovered ? Color.dsAccent : Color.dsTextTertiary)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(L10n.string(isImporting ? "sidebar.dropZone.importing" : "sidebar.dropZone.title", locale: locale))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.dsTextSecondary)
                        .lineLimit(1)
                    if !isImporting {
                        Text(L10n.string("sidebar.dropZone.subtitle"))
                            .font(.system(size: 10.5))
                            .foregroundStyle(Color.dsTextTertiary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, .dsMD)
            .frame(height: 64)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .disabled(isImporting)
        .background {
            (isTargeted ? Color.dsAccentSoft : Color.clear)
                .clipShape(FoldedCornerRect(cornerRadius: .dsRadiusMd, foldSize: 8))
        }
        .overlay {
            FoldedCornerRect(cornerRadius: .dsRadiusMd, foldSize: 8)
                .strokeBorder(borderColor, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onDrop(of: importDropContentTypes, isTargeted: $isTargeted, perform: onDrop)
        .animation(shouldReduceMotion ? nil : .easeInOut(duration: 0.15), value: isTargeted)
        .animation(shouldReduceMotion ? nil : .easeInOut(duration: 0.15), value: isHovered)
        .animation(shouldReduceMotion ? nil : .easeInOut(duration: 0.2), value: errorFlash)
        .help(L10n.string("sidebar.addFiles.help"))
        .accessibilityLabel(L10n.string("sidebar.addFiles.label", locale: locale))
        .accessibilityHint(L10n.string("sidebar.dropZone.accessibilityHint", locale: locale))
    }
}

// MARK: - Member document row

struct MemberDocRow: View {
    var member: MemberDocument
    var viewModel: WorkspaceViewModel
    @Binding var expandedDocs: Set<UUID>
    var onImportDrop: ([NSItemProvider]) -> Bool = { _ in false }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection
    @State private var isHovered = false
    @State private var dropEdge: VerticalEdge?
    @State private var cardHeight: CGFloat = 0
    // Passed into L10n.format()/L10n.string() below so this view's `body` actually
    // reads it — SwiftUI only re-invokes `body` on a locale change for views that
    // read `\.locale` during the previous evaluation.
    @Environment(\.locale) private var locale
    @State private var isRenaming = false
    @State private var renameText = ""
    @FocusState private var isRenameFieldFocused: Bool
    @FocusState private var isOverflowMenuFocused: Bool
    @State private var miniThumbnail: NSImage?

    private static let miniThumbSize = CGSize(width: 32, height: 42)

    private var shouldReduceMotion: Bool {
        reduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || viewModel.documentComfortSettings.reduceAnimations
    }

    private var isExpanded: Bool {
        get { expandedDocs.contains(member.id) }
        nonmutating set { if newValue { expandedDocs.insert(member.id) } else { expandedDocs.remove(member.id) } }
    }

    private var sourcePDF: PDFDocument? {
        viewModel.loadedPDFs.first(where: { $0.0.id == member.id })?.1
    }

    private var isSelected: Bool {
        guard let selectedPageRefID = viewModel.selectedPageRefID else { return false }
        return member.pageRefs.contains(selectedPageRefID)
    }

    private var commentCount: Int { viewModel.commentCount(for: member) }

    private var pagesPhrase: String {
        member.pageRefs.count == 1
            ? L10n.format("sidebar.pageCount.one", member.pageRefs.count, locale: locale)
            : L10n.format("sidebar.pageCount.other", member.pageRefs.count, locale: locale)
    }

    private var commentsPhrase: String? {
        guard commentCount > 0 else { return nil }
        return commentCount == 1
            ? L10n.format("sidebar.doc.commentCount.one", commentCount, locale: locale)
            : L10n.format("sidebar.doc.commentCount.other", commentCount, locale: locale)
    }

    private var metadataLine: String {
        [pagesPhrase, commentsPhrase].compactMap { $0 }.joined(separator: " · ")
    }

    private var combinedAccessibilityLabel: String {
        var parts = [member.displayName, pagesPhrase]
        if let commentsPhrase { parts.append(commentsPhrase) }
        if isSelected { parts.append(L10n.string("sidebar.doc.selected.accessibilitySuffix", locale: locale)) }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            cardRow
            if isExpanded, let pdf = sourcePDF {
                HStack(alignment: .top, spacing: .dsXS) {
                    Rectangle()
                        .fill(Color.dsSeparator)
                        .frame(width: 1)
                        .padding(.leading, 14)
                    ThumbnailStrip(member: member, pdf: pdf, viewModel: viewModel)
                }
            }
        }
    }

    private var cardRow: some View {
        HStack(spacing: .dsSM) {
            chevronButton
            miniThumbnailView
            VStack(alignment: .leading, spacing: 2) {
                titleView
                Text(metadataLine)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.dsTextTertiary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            overflowMenu
                .opacity(isHovered || isOverflowMenuFocused ? 1 : 0)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, .dsSM)
        .background {
            if isSelected {
                let shape = FoldedCornerRect(cornerRadius: .dsRadiusSm, foldSize: 6)
                Color.dsAccentSoft
                    .clipShape(shape)
                    .overlay(shape.strokeBorder(Color.dsAccent.opacity(0.25), lineWidth: 0.75))
            } else if isHovered {
                Color.dsSeparator
                    .clipShape(RoundedRectangle(cornerRadius: .dsRadiusSm, style: .continuous))
            }
        }
        .overlay(alignment: .leading) {
            if isSelected {
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(Color.dsAccent)
                    .frame(width: 2)
                    .padding(.vertical, 4)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isRenaming else { return }
            viewModel.selectDocument(member)
        }
        .onHover { isHovered = $0 }
        .animation(shouldReduceMotion ? nil : .easeInOut(duration: 0.12), value: isHovered)
        .contextMenu { menuItems }
        .accessibilityElement(children: isRenaming ? .contain : .combine)
        .accessibilityLabel(isRenaming ? "" : combinedAccessibilityLabel)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityAction(named: Text(verbatim: L10n.string(isExpanded ? "sidebar.doc.collapse.accessibilityLabel" : "sidebar.doc.expand.accessibilityLabel", locale: locale))) {
            toggleExpanded()
        }
        .accessibilityAction(named: Text(verbatim: L10n.string("sidebar.doc.menu.rename", locale: locale))) { beginRename() }
        .accessibilityAction(named: Text(verbatim: L10n.format("sidebar.export", member.displayName, locale: locale))) { exportDocument() }
        .accessibilityAction(named: Text(verbatim: L10n.string("sidebar.removeDocument.contextMenu", locale: locale))) {
            guard viewModel.canRemoveDocuments else { return }
            viewModel.removeDocument(member)
        }
        .background {
            GeometryReader { geo in
                Color.clear
                    .onAppear { cardHeight = geo.size.height }
                    .onChange(of: geo.size.height) { _, newValue in cardHeight = newValue }
            }
        }
        .overlay(alignment: .top) { if dropEdge == .top { SidebarInsertionLine() } }
        .overlay(alignment: .bottom) { if dropEdge == .bottom { SidebarInsertionLine() } }
        .onDrag {
            viewModel.beginDraggingDocument(member)
            let provider = NSItemProvider()
            provider.registerDataRepresentation(
                forTypeIdentifier: UTType.orifoldDocRef.identifier,
                visibility: .ownProcess
            ) { completion in
                completion(member.id.uuidString.data(using: .utf8), nil)
                return nil
            }
            return provider
        }
        .onDrop(
            of: [.orifoldDocRef] + importDropContentTypes,
            delegate: SidebarReorderDropDelegate(
                reorderType: .orifoldDocRef,
                importTypes: importDropContentTypes,
                rowHeight: cardHeight,
                isReorderActive: { viewModel.draggedMemberID != nil && viewModel.draggedMemberID != member.id },
                setEdge: { dropEdge = $0 },
                onReorder: { above in viewModel.moveDraggedDocument(to: member.id, insertAbove: above) },
                onImport: onImportDrop
            )
        )
    }

    @ViewBuilder private var titleView: some View {
        if isRenaming {
            TextField(L10n.string("sidebar.doc.rename.placeholder"), text: $renameText)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.dsTextPrimary)
                .focused($isRenameFieldFocused)
                .onSubmit(commitRename)
                .onExitCommand(perform: cancelRename)
                .onChange(of: isRenameFieldFocused) { _, focused in
                    // Return/Escape already set isRenaming = false before the field tears
                    // down and loses focus; only a genuine external blur (clicking another
                    // row, the drop zone, etc. while still renaming) reaches this guard.
                    guard !focused, isRenaming else { return }
                    commitRename()
                }
                .accessibilityLabel(L10n.string("sidebar.doc.rename.placeholder", locale: locale))
        } else {
            Text(member.displayName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.dsTextPrimary)
                .lineLimit(2)
                .truncationMode(.middle)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .help(member.displayName)
                .accessibilityLabel(member.displayName)
        }
    }

    @ViewBuilder private var miniThumbnailView: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let miniThumbnail {
                    Image(nsImage: miniThumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.dsSeparator)
                }
            }
            .frame(width: Self.miniThumbSize.width, height: Self.miniThumbSize.height)
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(Color.dsSeparator, lineWidth: 0.5)
            }

            typeChip.offset(x: layoutDirection == .rightToLeft ? 2 : -2, y: 2)
        }
        .task(id: member.id) {
            guard miniThumbnail == nil, let pdf = sourcePDF, let page = pdf.page(at: 0) else { return }
            miniThumbnail = page.thumbnail(
                of: CGSize(width: Self.miniThumbSize.width * 2, height: Self.miniThumbSize.height * 2),
                for: .mediaBox
            )
        }
    }

    private var typeChip: some View {
        let type = SidebarFileType(filename: member.sourcePDFRef)
        return Text(type.badgeText)
            .font(.system(size: 6, weight: .black))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(type.foreground)
            .padding(.horizontal, 3)
            .padding(.vertical, 1)
            .background(type.tint, in: RoundedRectangle(cornerRadius: 2, style: .continuous))
    }

    private var chevronButton: some View {
        Button(action: toggleExpanded) {
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.dsTextTertiary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.string(isExpanded ? "sidebar.doc.collapse.accessibilityLabel" : "sidebar.doc.expand.accessibilityLabel", locale: locale))
    }

    private var overflowMenu: some View {
        Menu {
            menuItems
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.dsTextTertiary)
                .frame(width: 20, height: 20)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .focused($isOverflowMenuFocused)
        .help(L10n.format("sidebar.doc.menu.help", member.displayName, locale: locale))
        .accessibilityLabel(L10n.format("sidebar.doc.menu.help", member.displayName, locale: locale))
    }

    @ViewBuilder private var menuItems: some View {
        Button {
            beginRename()
        } label: {
            Label(L10n.string("sidebar.doc.menu.rename"), systemImage: "pencil")
        }
        Button {
            exportDocument()
        } label: {
            Label(L10n.format("sidebar.export", member.displayName, locale: locale), systemImage: "square.and.arrow.up")
        }
        Button {
            openFilesInsertingAfterDocument()
        } label: {
            Label(L10n.string("sidebar.thumbnail.insertFilesAfter.contextMenu"), systemImage: "tray.and.arrow.down")
        }
        Divider()
        Button(role: .destructive) {
            viewModel.removeDocument(member)
        } label: {
            Label(L10n.string("sidebar.removeDocument.contextMenu"), systemImage: "trash")
        }
        .disabled(!viewModel.canRemoveDocuments)
    }

    private func toggleExpanded() {
        withAnimation(shouldReduceMotion ? nil : .easeInOut(duration: 0.15)) {
            isExpanded.toggle()
        }
    }

    private func beginRename() {
        renameText = member.displayName
        isRenaming = true
        isRenameFieldFocused = true
    }

    private func commitRename() {
        guard !renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            cancelRename()
            return
        }
        viewModel.renameDocument(member, to: renameText)
        isRenaming = false
    }

    private func cancelRename() {
        isRenaming = false
    }

    private func exportDocument() {
        let ids = Set(member.pageRefs)
        let refs = viewModel.document.workspace.pageOrder.filter { ids.contains($0.id) }
        viewModel.exportPages(refs)
    }

    private func openFilesInsertingAfterDocument() {
        let panel = NSOpenPanel()
        configureImportOpenPanel(panel)
        if panel.runModal() == .OK {
            importFilesWithBatchLimit(urls: panel.urls, into: viewModel, insertingAfter: member.pageRefs.last)
        }
    }
}

// MARK: - File type badge

private struct SidebarFileType {
    let badgeText: String
    let symbolName: String
    let tint: Color
    let foreground: Color

    init(filename: String) {
        switch URL(fileURLWithPath: filename).pathExtension.lowercased() {
        case "pdf":
            self.init("PDF", "doc.fill", Color(red: 0.78, green: 0.20, blue: 0.24), .white)
        case "html", "htm":
            self.init("HTML", "globe", Color(red: 0.047, green: 0.404, blue: 0.651), .white)
        case "doc", "docx", "odt", "rtf":
            self.init("DOC", "doc.text.fill", Color(red: 0.10, green: 0.30, blue: 0.52), .white)
        case "md", "markdown":
            self.init("MD", "text.alignleft", Color(red: 0.27, green: 0.35, blue: 0.40), .white)
        case "txt":
            self.init("TXT", "doc.text", Color(red: 0.38, green: 0.47, blue: 0.52), .white)
        case "csv":
            self.init("CSV", "tablecells.fill", Color(red: 0.09, green: 0.52, blue: 0.44), .white)
        case "json":
            self.init("JSON", "curlybraces.square.fill", Color(red: 0.58, green: 0.42, blue: 0.16), .white)
        case "xml":
            self.init("XML", "chevron.left.forwardslash.chevron.right", Color(red: 0.43, green: 0.38, blue: 0.68), .white)
        case "png", "jpg", "jpeg", "heic", "tiff", "gif", "bmp":
            self.init("IMG", "photo.fill", Color(red: 0.10, green: 0.58, blue: 0.63), .white)
        default:
            self.init("FILE", "doc.fill", Color.dsAccent, .white)
        }
    }

    private init(_ badgeText: String, _ symbolName: String, _ tint: Color, _ foreground: Color) {
        self.badgeText = badgeText
        self.symbolName = symbolName
        self.tint = tint
        self.foreground = foreground
    }
}

// MARK: - Thumbnail strip

struct ThumbnailStrip: View {
    var member: MemberDocument
    var pdf: PDFDocument
    var viewModel: WorkspaceViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shouldReduceMotion: Bool {
        reduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    var body: some View {
        LazyVStack(spacing: 4) {
            ForEach(Array(zip(member.pageRefs.indices, member.pageRefs)), id: \.1) { i, refId in
                if let page = pdf.page(at: i),
                   let ref = viewModel.document.workspace.pageOrder.first(where: { $0.id == refId }) {
                    ThumbnailCell(page: page, pageRef: ref, pageNumber: i + 1, viewModel: viewModel)
                        .transition(shouldReduceMotion ? .identity : .scale(scale: 0.92).combined(with: .opacity))
                }
            }
        }
        .padding(.leading, 4)
        .padding(.vertical, 4)
        .animation(
            shouldReduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8),
            value: member.pageRefs
        )
    }
}

// MARK: - Individual thumbnail cell

struct ThumbnailCell: View {
    var page: PDFPage
    var pageRef: PageRef
    var pageNumber: Int
    var viewModel: WorkspaceViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var thumbnail: NSImage? = nil
    @State private var isHovered = false
    @State private var isConfirmingDelete = false
    @State private var dropEdge: VerticalEdge?
    @State private var cellHeight: CGFloat = 0
    // Passed into L10n.format()/L10n.string() below so this view's `body` actually
    // reads it — SwiftUI only re-invokes `body` on a locale change for views that
    // read `\.locale` during the previous evaluation.
    @Environment(\.locale) private var locale

    private static let thumbSize = CGSize(width: 48, height: 64)
    private var isSelected: Bool {
        viewModel.selectedPageRefIDs.contains(pageRef.id) || viewModel.selectedPageRefID == pageRef.id
    }
    private var commentCount: Int { viewModel.commentCount(for: pageRef.id) }
    private var shouldReduceMotion: Bool {
        reduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    var body: some View {
        HStack(spacing: .dsSM) {
            // Thumbnail image
            Group {
                if let img = thumbnail {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: Self.thumbSize.width, height: Self.thumbSize.height)
                } else {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.dsSeparator)
                        .frame(width: Self.thumbSize.width, height: Self.thumbSize.height)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.dsAccent : Color.dsSeparator,
                        lineWidth: isSelected ? 1.5 : 0.5
                    )
            }
            .overlay(alignment: .topTrailing) {
                if commentCount > 0 {
                    Text("\(commentCount)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.white)
                        .frame(minWidth: 15, minHeight: 15)
                        .background(Color.dsAccent, in: Circle())
                        .offset(x: 5, y: -5)
                        .accessibilityLabel(L10n.format("sidebar.commentsOnPage.accessibilityLabel", commentCount, locale: locale))
                }
            }
            .shadow(color: .black.opacity(0.10), radius: 3, x: 0, y: 1)
            .background(Color.dsCard, in: RoundedRectangle(cornerRadius: 3))
            .contextMenu {
                let selection = viewModel.pageRefsForCurrentSelection(including: pageRef)
                let selectionLabel = selection.count == 1
                    ? L10n.string("sidebar.selection.page", locale: locale)
                    : L10n.format("sidebar.selection.pages", selection.count, locale: locale)
                Button(L10n.format("sidebar.rotateCW", selectionLabel, locale: locale))  {
                    viewModel.rotatePages(selection, by: 90)
                    thumbnail = nil
                }
                Button(L10n.format("sidebar.rotateCCW", selectionLabel, locale: locale)) {
                    viewModel.rotatePages(selection, by: -90)
                    thumbnail = nil
                }
                Button(L10n.format("sidebar.duplicate", selectionLabel, locale: locale)) {
                    viewModel.duplicatePages(selection)
                    thumbnail = nil
                }
                Button(L10n.format("sidebar.export", selectionLabel, locale: locale)) {
                    viewModel.exportPages(selection)
                }
                Divider()
                Button(L10n.string("sidebar.thumbnail.insertFilesAfter.contextMenu")) {
                    openFiles(insertingAfter: pageRef)
                }
                Divider()
                Button(L10n.format("sidebar.delete", selectionLabel, locale: locale), role: .destructive) {
                    isConfirmingDelete = true
                }
            }

            // Label
            Text(L10n.format("sidebar.pageLabel.short", pageNumber, locale: locale))
                .font(.dsCaption())
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundStyle(isSelected ? Color.dsAccent : Color.dsTextSecondary)

            Spacer()

            Image(systemName: "line.3.horizontal")
                .font(.caption2)
                .foregroundStyle(Color.dsTextTertiary)
                .opacity(isHovered || isSelected ? 1 : 0)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background {
            RoundedRectangle(cornerRadius: .dsRadiusSm, style: .continuous)
                .fill(isSelected ? Color.dsAccentSoft : (isHovered ? Color.dsSeparator : Color.clear))
        }
        .scaleEffect(shouldReduceMotion ? 1.0 : (isSelected ? 1.03 : 1.0))
        .animation(shouldReduceMotion ? nil : .easeInOut(duration: 0.12), value: isSelected)
        .animation(shouldReduceMotion ? nil : .easeInOut(duration: 0.10), value: isHovered)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture {
            let flags = NSApp.currentEvent?.modifierFlags ?? []
            viewModel.selectPage(pageRef, extendingSelection: flags.contains(.command) || flags.contains(.shift))
        }
        .background {
            GeometryReader { geo in
                Color.clear
                    .onAppear { cellHeight = geo.size.height }
                    .onChange(of: geo.size.height) { _, newValue in cellHeight = newValue }
            }
        }
        .overlay(alignment: .top) { if dropEdge == .top { SidebarInsertionLine() } }
        .overlay(alignment: .bottom) { if dropEdge == .bottom { SidebarInsertionLine() } }
        .onDrag {
            viewModel.beginDraggingPage(pageRef)
            let provider = NSItemProvider()
            provider.registerDataRepresentation(
                forTypeIdentifier: UTType.orifoldPageRef.identifier,
                visibility: .ownProcess
            ) { completion in
                completion(pageRef.id.uuidString.data(using: .utf8), nil)
                return nil
            }
            return provider
        }
        .onDrop(
            of: [.orifoldPageRef],
            delegate: SidebarReorderDropDelegate(
                reorderType: .orifoldPageRef,
                importTypes: [],
                rowHeight: cellHeight,
                // Same-document only (MVP): reject drops when the dragged page belongs to
                // another member so the indicator never shows and the drop is refused.
                isReorderActive: {
                    viewModel.draggedPageMemberID == pageRef.memberDocId
                        && viewModel.draggedPageRefID != pageRef.id
                },
                setEdge: { dropEdge = $0 },
                onReorder: { above in viewModel.moveDraggedPage(to: pageRef, insertAbove: above) },
                onImport: { _ in false }
            )
        )
        .task(id: pageNumber) {
            guard thumbnail == nil else { return }
            thumbnail = page.thumbnail(of: Self.thumbSize, for: .mediaBox)
        }
        .confirmationDialog(
            L10n.string("sidebar.deletePages.confirmation.title"),
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button(L10n.string("sidebar.deletePages.confirmation.delete"), role: .destructive) {
                viewModel.deletePages(viewModel.pageRefsForCurrentSelection(including: pageRef))
                thumbnail = nil
            }
            Button(L10n.string("sidebar.deletePages.confirmation.cancel"), role: .cancel) {}
        } message: {
            let count = viewModel.pageRefsForCurrentSelection(including: pageRef).count
            if count == 1 {
                Text(L10n.string("sidebar.deletePages.confirmation.messageSingular"))
            } else {
                Text(L10n.format("sidebar.removePages.confirmation.plural", count, locale: locale))
            }
        }
    }

    private func openFiles(insertingAfter ref: PageRef) {
        let panel = NSOpenPanel()
        configureImportOpenPanel(panel)
        if panel.runModal() == .OK {
            importFilesWithBatchLimit(urls: panel.urls, into: viewModel, insertingAfter: ref.id)
        }
    }
}

// MARK: - Reorder drag/drop

/// A 2pt accent rule shown at a row's top or bottom edge to preview where a dragged
/// file or page will land.
private struct SidebarInsertionLine: View {
    var body: some View {
        Capsule()
            .fill(Color.dsAccent)
            .frame(height: 2)
            .padding(.horizontal, 4)
            .transition(.opacity)
    }
}

/// Drives custom drag-reordering for both the file rows and the page thumbnails. A single
/// delegate handles the reorder type (drawing the insertion indicator and calling
/// `onReorder`) and, for file rows, the file-import types (which fall through to `onImport`
/// with no indicator). `rowHeight` is the measured height of the drop target and is used to
/// decide whether the cursor is in the top or bottom half — i.e. insert before vs. after.
private struct SidebarReorderDropDelegate: DropDelegate {
    let reorderType: UTType
    let importTypes: [UTType]
    let rowHeight: CGFloat
    let isReorderActive: () -> Bool
    let setEdge: (VerticalEdge?) -> Void
    let onReorder: (_ insertAbove: Bool) -> Bool
    let onImport: ([NSItemProvider]) -> Bool

    private func isReorder(_ info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [reorderType]) && isReorderActive()
    }

    private func edge(for info: DropInfo) -> VerticalEdge {
        (rowHeight > 0 && info.location.y > rowHeight / 2) ? .bottom : .top
    }

    func validateDrop(info: DropInfo) -> Bool {
        if info.hasItemsConforming(to: [reorderType]) { return isReorderActive() }
        return !importTypes.isEmpty && info.hasItemsConforming(to: importTypes)
    }

    func dropEntered(info: DropInfo) {
        if isReorder(info) { setEdge(edge(for: info)) }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        if isReorder(info) {
            setEdge(edge(for: info))
            return DropProposal(operation: .move)
        }
        setEdge(nil)
        return DropProposal(operation: .copy)
    }

    func dropExited(info: DropInfo) {
        setEdge(nil)
    }

    func performDrop(info: DropInfo) -> Bool {
        let wasReorder = isReorder(info)
        let insertAbove = edge(for: info) == .top
        setEdge(nil)
        if wasReorder {
            return onReorder(insertAbove)
        }
        guard !importTypes.isEmpty else { return false }
        return onImport(info.itemProviders(for: importTypes))
    }
}
