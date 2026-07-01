import SwiftUI
import PDFKit

// MARK: - Reading canvas shell (PDF + zoom/page bar)

struct ReadingCanvas: View {
    @Bindable var viewModel: WorkspaceViewModel

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                PDFViewRepresentable(viewModel: viewModel)
                if let status = viewModel.editingStatus {
                    EditingStatusBanner(status: status) {
                        viewModel.editingStatus = nil
                    }
                    .padding(.top, .dsMD)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task(id: status.id) {
                        guard !status.isError else { return }
                        try? await Task.sleep(for: .seconds(4))
                        guard !Task.isCancelled, viewModel.editingStatus?.id == status.id else { return }
                        viewModel.editingStatus = nil
                    }
                }
            }
            ZoomPageBar(viewModel: viewModel)
        }
        .animation(.easeInOut(duration: 0.18), value: viewModel.editingStatus?.id)
    }
}

private struct EditingStatusBanner: View {
    var status: WorkspaceViewModel.EditingStatus
    var dismiss: () -> Void

    var body: some View {
        HStack(spacing: .dsSM) {
            Image(systemName: status.isError ? "exclamationmark.triangle.fill" : "info.circle.fill")
                .foregroundStyle(status.isError ? Color.orange : Color.dsAccent)
            Text(status.message)
                .font(.dsCaption())
                .foregroundStyle(Color.dsTextPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.dsTextTertiary)
            .help("Dismiss")
        }
        .padding(.horizontal, .dsMD)
        .padding(.vertical, .dsSM)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: .dsRadiusSm, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: .dsRadiusSm, style: .continuous)
                .strokeBorder(Color.dsSeparator, lineWidth: 1)
        }
        .frame(maxWidth: 520)
    }
}

// MARK: - Zoom / page bar

private struct ZoomPageBar: View {
    @Bindable var viewModel: WorkspaceViewModel
    @State private var pageInput: String = ""
    @FocusState private var pageFieldFocused: Bool

    var body: some View {
        HStack(spacing: .dsSM) {
            // Zoom controls
            Button { viewModel.zoomOut() } label: {
                Image(systemName: "minus")
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Color.dsTextSecondary)
            .help("Zoom out")

            Button { viewModel.zoomFit() } label: {
                Image(systemName: "arrow.up.left.and.down.right.magnifyingglass")
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Color.dsTextSecondary)
            .help("Fit page")

            Button { viewModel.zoomIn() } label: {
                Image(systemName: "plus")
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Color.dsTextSecondary)
            .help("Zoom in")

            Divider()
                .frame(height: 16)

            BottomBarBrand()

            Spacer()

            if viewModel.pageCount > 0 {
                HStack(spacing: 4) {
                    Text("Page")
                    TextField("", text: $pageInput)
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.center)
                        .frame(width: 30)
                        .focused($pageFieldFocused)
                        .onSubmit {
                            if let n = Int(pageInput),
                               let combinedIndex = viewModel.combinedPageIndex(forWorkspacePageNumber: n) {
                                NotificationCenter.default.post(name: .pdfoldJumpToPageIndex, object: combinedIndex)
                            } else {
                                pageInput = "\(viewModel.currentPageNumber)"
                            }
                            pageFieldFocused = false
                        }
                    Text("of \(viewModel.pageCount)")
                }
                .font(.dsCaption())
                .foregroundStyle(Color.dsTextSecondary)
                .onChange(of: viewModel.currentPageNumber) { _, n in
                    if !pageFieldFocused { pageInput = "\(n)" }
                }
                .onAppear { pageInput = "\(max(1, viewModel.currentPageNumber))" }
            }
        }
        .padding(.horizontal, .dsLG)
        .padding(.vertical, 6)
        .background(Color.dsSurface)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.dsSeparator).frame(height: 0.5)
        }
        .accessibilityElement(children: .contain)
    }
}

private struct BottomBarBrand: View {
    var body: some View {
        HStack(spacing: .dsXS) {
            AppIconMark(size: 16)
            Text("pdFold v3 workspace")
                .font(.system(size: 11, weight: .medium, design: .serif))
                .foregroundStyle(Color.dsTextTertiary)
                .lineLimit(1)
        }
        .accessibilityLabel("pdFold version 3 workspace")
    }
}

// MARK: - NSViewRepresentable

struct PDFViewRepresentable: NSViewRepresentable {
    @Bindable var viewModel: WorkspaceViewModel

    func makeCoordinator() -> Coordinator { Coordinator(viewModel: viewModel) }

    func makeNSView(context: Context) -> PDFoldPDFView {
        let view = PDFoldPDFView()
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.autoScales = true
        view.displaysPageBreaks = false
        view.backgroundColor = .dsCanvasNS

        // Wire up delete key handler
        view.onDeleteKey = { [weak coordinator = context.coordinator] in
            coordinator?.viewModel.deleteSelectedAnnotation()
        }

        // Click gesture
        let click = NSClickGestureRecognizer(target: context.coordinator,
                                             action: #selector(Coordinator.handleClick(_:)))
        click.numberOfClicksRequired = 1
        view.addGestureRecognizer(click)

        // Ink overlay
        let overlay = context.coordinator.inkOverlay
        overlay.frame = view.bounds
        overlay.autoresizingMask = [.width, .height]
        overlay.isHidden = true
        view.addSubview(overlay)

        // Notifications
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.selectionChanged(_:)),
            name: .PDFViewSelectionChanged, object: view)
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.jumpToSelection(_:)),
            name: .pdfoldJumpToSelection, object: nil)
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.jumpToPageIndex(_:)),
            name: .pdfoldJumpToPageIndex, object: nil)
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.printDocument(_:)),
            name: .pdfoldPrint, object: nil)
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.zoomIn(_:)),
            name: .pdfoldZoomIn, object: nil)
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.zoomOut(_:)),
            name: .pdfoldZoomOut, object: nil)
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.zoomFit(_:)),
            name: .pdfoldZoomFit, object: nil)
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pageChanged(_:)),
            name: .PDFViewPageChanged, object: view)
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.saveAsPDF(_:)),
            name: .pdfoldSaveAsPDF, object: nil)

        context.coordinator.pdfView = view
        context.coordinator.setupInkOverlay()
        return view
    }

    func updateNSView(_ nsView: PDFoldPDFView, context: Context) {
        if nsView.document !== viewModel.combinedPDF {
            nsView.document = viewModel.combinedPDF
        }
        context.coordinator.viewModel = viewModel
        context.coordinator.inkOverlay.isHidden = (viewModel.currentTool != .ink)
        context.coordinator.inkOverlay.inkColor = viewModel.inkColor
        // Switching to a different tool (e.g. clicking Highlight) without clicking Done
        // first must not silently drop whatever text is still being edited.
        if viewModel.currentTool != .editText {
            context.coordinator.finishInlineEditingIfNeeded()
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSPopoverDelegate {
        var viewModel: WorkspaceViewModel
        weak var pdfView: PDFoldPDFView?
        let inkOverlay = InkOverlayView()
        private weak var inlineEditor: InlineTextEditorOverlay?
        private var notePopover: NSPopover?

        init(viewModel: WorkspaceViewModel) {
            self.viewModel = viewModel
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        func finishInlineEditingIfNeeded() {
            inlineEditor?.finishForHandoff()
        }

        @objc func selectionChanged(_ notification: Notification) {
            guard let pdfView,
                  let selection = pdfView.currentSelection,
                  !(selection.string?.isEmpty ?? true) else { return }
            switch viewModel.currentTool {
            case .highlight:
                viewModel.applyHighlight(to: selection)
                pdfView.clearSelection()
            case .underline:
                viewModel.applyMarkup(.underline, to: selection)
                pdfView.clearSelection()
            case .strikeout:
                viewModel.applyMarkup(.strikeOut, to: selection)
                pdfView.clearSelection()
            default:
                break
            }
        }

        @objc func handleClick(_ gesture: NSClickGestureRecognizer) {
            guard let pdfView else { return }
            let viewPoint = gesture.location(in: pdfView)
            guard let page = pdfView.page(for: viewPoint, nearest: true),
                  !(page is BoundaryPage) else { return }
            let pagePoint = pdfView.convert(viewPoint, to: page)

            switch viewModel.currentTool {
            case .note:
                if let ann = page.annotation(at: pagePoint), ann.type == "Text" {
                    // Edit existing note
                    let rect = pdfView.convert(ann.bounds, from: page)
                    showNoteEditor(for: ann, near: rect, in: pdfView)
                } else {
                    // Place new note and immediately open editor
                    let ann = viewModel.addNote(at: pagePoint, on: page)
                    let rect = pdfView.convert(ann.bounds, from: page)
                    showNoteEditor(for: ann, near: rect, in: pdfView)
                }
            case .editText:
                inlineEditor?.finishForHandoff()
                if let target = viewModel.editableTextBlock(at: pagePoint, on: page, in: pdfView.document) {
                    showInlineTextEditor(for: target.block, pageRef: target.pageRef, on: page, in: pdfView)
                }
            case .signature:
                if let signatureData = viewModel.pendingSignatureData {
                    viewModel.placeSignature(imageData: signatureData, at: pagePoint, on: page)
                } else {
                    viewModel.isShowingSignaturePalette = true
                }
            case .none:
                // Track clicked annotation for Delete-key deletion
                viewModel.selectedAnnotation = page.annotation(at: pagePoint)
            default:
                viewModel.selectedAnnotation = nil
            }
        }

        private func editableTextSelection(at point: CGPoint, on page: PDFPage) -> PDFSelection? {
            if let word = page.selectionForWord(at: point),
               isUsableTextSelection(word, near: point, on: page, tolerance: 5) {
                return word
            }

            let searchRect = CGRect(x: point.x - 6, y: point.y - 6, width: 12, height: 12)
            if let nearby = page.selection(for: searchRect),
               isUsableTextSelection(nearby, near: point, on: page, tolerance: 10) {
                return nearby
            }

            if let line = page.selectionForLine(at: point),
               isUsableTextSelection(line, near: point, on: page, tolerance: 8),
               line.bounds(for: page).width <= 160 {
                return line
            }

            return nil
        }

        private func isUsableTextSelection(_ selection: PDFSelection, near point: CGPoint, on page: PDFPage, tolerance: CGFloat) -> Bool {
            guard let text = selection.string?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else { return false }
            let bounds = selection.bounds(for: page).insetBy(dx: -tolerance, dy: -tolerance)
            return bounds.contains(point)
        }

        private func showNoteEditor(for annotation: PDFAnnotation, near rect: CGRect, in view: NSView) {
            notePopover?.close()
            let vc = NoteEditorViewController(
                annotation: annotation,
                statusHandler: { [weak self, weak view] message, isError in
                    self?.viewModel.showEditMessage(message, isError: isError)
                    view?.needsDisplay = true
                },
                changeHandler: { [weak self, weak view] in
                    self?.viewModel.markAnnotationsModified()
                    view?.needsDisplay = true
                }
            )
            let popover = NSPopover()
            popover.contentViewController = vc
            popover.behavior = .transient
            popover.delegate = self
            notePopover = popover
            popover.show(relativeTo: rect, of: view, preferredEdge: .maxY)
        }

        func popoverDidClose(_ notification: Notification) {
            guard let popover = notification.object as? NSPopover, popover === notePopover else { return }
            notePopover = nil
        }

        private func showInlineTextEditor(for block: EditableTextBlock, pageRef: PageRef, on page: PDFPage, in pdfView: PDFoldPDFView) {
            // Callers are expected to finish (commit or cancel) any previously open editor
            // before calling this — see the `.editText` handleClick case.
            assert(inlineEditor == nil, "a previous inline editor should already be finished")
            let editor = InlineTextEditorOverlay(
                frame: pdfView.bounds,
                pdfView: pdfView,
                page: page,
                pageRef: pageRef,
                block: block
            ) { [weak self, weak pdfView] result in
                guard let self else { return }
                switch result {
                case .commit(let edit):
                    // Capture scroll position so the edit appears in place (not jumping to page 1).
                    let savedDestination = pdfView?.currentDestination
                    let savedPageIdx: Int? = {
                        guard let pv = pdfView,
                              let pg = pv.currentPage,
                              let doc = pv.document else { return nil }
                        let idx = doc.index(for: pg)
                        return idx == NSNotFound ? nil : idx
                    }()

                    let didApply = viewModel.applyInlineTextEdit(
                        pageRef: edit.pageRef,
                        sourceBlock: edit.block,
                        replacementText: edit.text,
                        editedBounds: edit.editedBounds,
                        fontName: edit.fontName,
                        fontSize: edit.fontSize,
                        textColor: edit.textColor,
                        alignment: edit.alignment
                    )
                    if didApply {
                        let newDoc = viewModel.combinedPDF
                        // Always assign; SwiftUI may not have fired updateNSView yet.
                        pdfView?.document = newDoc
                        if let idx = savedPageIdx, let targetPage = newDoc.page(at: idx) {
                            if let dest = savedDestination {
                                pdfView?.go(to: PDFDestination(page: targetPage, at: dest.point))
                            } else {
                                pdfView?.go(to: targetPage)
                            }
                        }
                        pdfView?.layoutDocumentView()
                        pdfView?.needsDisplay = true
                    }
                case .cancel:
                    break
                }
                inlineEditor = nil
            }
            editor.autoresizingMask = [.width, .height]
            inlineEditor = editor
            pdfView.addSubview(editor)
            editor.beginEditing()
        }

        @objc func jumpToSelection(_ notification: Notification) {
            guard let selection = notification.object as? PDFSelection else { return }
            pdfView?.go(to: selection)
            pdfView?.setCurrentSelection(selection, animate: true)
        }

        @objc func jumpToPageIndex(_ notification: Notification) {
            guard let idx = notification.object as? Int,
                  let page = pdfView?.document?.page(at: idx) else { return }
            pdfView?.go(to: page)
        }

        @objc func printDocument(_ notification: Notification) {
            guard let pdfView else { return }
            viewModel.printWorkspace(pdfView: pdfView)
        }

        @objc func zoomIn(_ notification: Notification) {
            pdfView?.zoomIn(nil)
        }

        @objc func zoomOut(_ notification: Notification) {
            pdfView?.zoomOut(nil)
        }

        @objc func zoomFit(_ notification: Notification) {
            pdfView?.autoScales = true
        }

        @objc func pageChanged(_ notification: Notification) {
            guard let pdfView, let doc = pdfView.document,
                  let page = pdfView.currentPage else { return }
            viewModel.currentPageNumber = viewModel.workspacePageNumber(for: page, in: doc)
        }

        @objc func saveAsPDF(_ notification: Notification) {
            viewModel.saveFlattenedPDF()
        }

        func setupInkOverlay() {
            inkOverlay.onStrokeCommitted = { [weak self] overlayPath in
                guard let self, let pdfView,
                      let page = pdfView.currentPage else { return }
                let pagePath = convertOverlayPath(overlayPath, pdfView: pdfView, page: page)
                viewModel.addInkStroke(path: pagePath, on: page)
                inkOverlay.clearCommittedPaths()
            }
        }

        private func convertOverlayPath(_ path: NSBezierPath, pdfView: PDFView, page: PDFPage) -> NSBezierPath {
            let pagePath = NSBezierPath()
            pagePath.lineWidth = path.lineWidth
            var pts = [NSPoint](repeating: .zero, count: 3)
            let overlayHeight = inkOverlay.bounds.height
            func toPDFPage(_ p: NSPoint) -> NSPoint {
                let viewPt = NSPoint(x: p.x, y: overlayHeight - p.y)
                return pdfView.convert(viewPt, to: page)
            }
            for i in 0..<path.elementCount {
                let kind = path.element(at: i, associatedPoints: &pts)
                switch kind {
                case .moveTo:                    pagePath.move(to: toPDFPage(pts[0]))
                case .lineTo:                    pagePath.line(to: toPDFPage(pts[0]))
                case .curveTo, .cubicCurveTo:
                    pagePath.curve(to: toPDFPage(pts[2]),
                                   controlPoint1: toPDFPage(pts[0]),
                                   controlPoint2: toPDFPage(pts[1]))
                default: break
                }
            }
            return pagePath
        }
    }
}

// MARK: - Custom PDFView subclass (handles Delete key)

final class PDFoldPDFView: PDFView {
    var onDeleteKey: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        // Delete (51) or Forward Delete (117)
        if event.keyCode == 51 || event.keyCode == 117, let block = onDeleteKey {
            block()
        } else {
            super.keyDown(with: event)
        }
    }
}

// MARK: - Note editor popover (NSPopover backed)

final class NoteEditorViewController: NSViewController {
    private let annotation: PDFAnnotation
    private let statusHandler: (String, Bool) -> Void
    private let changeHandler: () -> Void
    private weak var textView: NSTextView?
    private weak var scrollView: NSScrollView?
    private weak var sizeLabel: NSTextField?
    private let originalSnapshot: PDFAnnotationEditSnapshot
    private let minimumEditorFontSize: CGFloat = 10
    private var styleChanged = false
    private var editorFontFamily: String
    private var editorFontSize: CGFloat
    private var editorFontTraits: NSFontTraitMask
    private var editorTextColor: NSColor
    private var editorAlignment: NSTextAlignment
    private var didCommit = false
    private var didCancel = false
    private var isFreeTextAnnotation: Bool { annotation.type == "FreeText" }
    private var isDraftAnnotation: Bool {
        (annotation.value(forAnnotationKey: WorkspaceViewModel.draftTextAnnotationKey) as? Bool) == true
    }
    private var isTextReplacementAnnotation: Bool {
        (annotation.value(forAnnotationKey: WorkspaceViewModel.textReplacementAnnotationKey) as? Bool) == true
    }
    private var editorTitle: String {
        if isTextReplacementAnnotation { return "Edit PDF Text" }
        return isFreeTextAnnotation ? "Text Box" : "Edit Note"
    }

    init(
        annotation: PDFAnnotation,
        statusHandler: @escaping (String, Bool) -> Void = { _, _ in },
        changeHandler: @escaping () -> Void = {}
    ) {
        self.annotation = annotation
        self.statusHandler = statusHandler
        self.changeHandler = changeHandler
        self.originalSnapshot = PDFAnnotationEditSnapshot(annotation: annotation)
        let resolvedFont = annotation.font ?? .systemFont(ofSize: 16)
        self.editorFontFamily = resolvedFont.familyName ?? NSFont.systemFont(ofSize: 16).familyName ?? "System"
        self.editorFontSize = max(resolvedFont.pointSize, minimumEditorFontSize)
        self.editorFontTraits = NSFontManager.shared.traits(of: resolvedFont).intersection([.boldFontMask, .italicFontMask])
        self.editorTextColor = annotation.fontColor ?? .dsTextPrimaryNS
        self.editorAlignment = annotation.alignment
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { nil }

    override func loadView() {
        let editorWidth = isFreeTextAnnotation ? max(460, min(640, annotation.bounds.width * 2.6)) : 340
        let editorHeight: CGFloat = isFreeTextAnnotation ? 336 : 224
        let headerHeight: CGFloat = 46
        let footerHeight: CGFloat = 58
        let controlsHeight: CGFloat = isFreeTextAnnotation ? 96 : 0
        let textMargin: CGFloat = 16
        let textHeight = editorHeight - headerHeight - footerHeight - controlsHeight - textMargin
        let textWidth = editorWidth - (textMargin * 2)
        let container = NSView(frame: CGRect(x: 0, y: 0, width: editorWidth, height: editorHeight))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.dsSurfaceNS.cgColor
        container.layer?.cornerRadius = 8
        container.layer?.cornerCurve = .continuous

        let titleLabel = NSTextField(labelWithString: editorTitle)
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .dsTextPrimaryNS
        titleLabel.frame = CGRect(x: 16, y: editorHeight - 30, width: editorWidth - 32, height: 18)
        container.addSubview(titleLabel)

        let scroll = NSScrollView(frame: CGRect(x: textMargin, y: footerHeight + controlsHeight, width: textWidth, height: textHeight))
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = true
        let fieldColors = PDFEditingSupport.editorFieldColors(for: editorTextColor)
        scroll.backgroundColor = fieldColors.background
        scroll.wantsLayer = true
        scroll.layer?.backgroundColor = fieldColors.background.cgColor
        scroll.layer?.cornerRadius = 6
        scroll.layer?.cornerCurve = .continuous
        scroll.layer?.borderWidth = 1
        scroll.layer?.borderColor = NSColor.dsSeparatorNS.withAlphaComponent(0.85).cgColor

        let tv = NSTextView(frame: CGRect(x: 0, y: 0, width: textWidth, height: textHeight))
        tv.isRichText = false
        tv.font = editorFont()
        tv.textContainerInset = NSSize(width: 10, height: 10)
        tv.string = annotation.contents ?? ""
        tv.backgroundColor = fieldColors.background
        tv.textColor = fieldColors.foreground
        tv.insertionPointColor = NSColor.dsAccentNS
        tv.alignment = editorAlignment
        tv.isEditable = true
        tv.isSelectable = true
        tv.allowsUndo = true
        tv.minSize = NSSize(width: 0, height: textHeight)
        tv.maxSize = NSSize(width: CGFloat.infinity, height: CGFloat.infinity)
        tv.isVerticallyResizable = true
        tv.textContainer?.containerSize = NSSize(width: textWidth - 20, height: CGFloat.infinity)
        tv.textContainer?.widthTracksTextView = true
        scroll.documentView = tv
        container.addSubview(scroll)

        if isFreeTextAnnotation {
            let controls = formattingControls(frame: CGRect(x: 12, y: footerHeight, width: editorWidth - 24, height: controlsHeight))
            container.addSubview(controls)
        }

        let footer = NSView(frame: CGRect(x: 0, y: 0, width: editorWidth, height: footerHeight))
        footer.wantsLayer = true
        footer.layer?.backgroundColor = NSColor.dsSurfaceNS.cgColor

        let done = NSButton(title: "Done", target: self, action: #selector(commit))
        done.bezelStyle = .rounded
        done.controlSize = .large
        done.keyEquivalent = "\r"
        done.contentTintColor = .dsAccentNS
        done.frame = CGRect(x: editorWidth - 88 - 12, y: 10, width: 88, height: 28)
        footer.addSubview(done)

        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancel.bezelStyle = .rounded
        cancel.controlSize = .large
        cancel.keyEquivalent = "\u{1b}"
        cancel.frame = CGRect(x: editorWidth - 88 - 12 - 80, y: 10, width: 72, height: 28)
        footer.addSubview(cancel)
        container.addSubview(footer)

        let sep = NSView(frame: CGRect(x: 12, y: footerHeight - 0.5, width: editorWidth - 24, height: 0.5))
        sep.wantsLayer = true
        sep.layer?.backgroundColor = NSColor.dsSeparatorNS.cgColor
        container.addSubview(sep)

        view = container
        textView = tv
        scrollView = scroll
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(textView)
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        if !didCommit && !didCancel {
            cancelChanges()
        }
    }

    @objc private func commit() {
        guard commitChanges() else { return }
        didCommit = true
        dismiss(nil)
    }

    @objc private func cancel() {
        cancelChanges()
        dismiss(nil)
    }

    private func commitChanges() -> Bool {
        guard let textView else { return false }
        switch PDFEditingSupport.emptyEditAction(
            text: textView.string,
            isDraft: isDraftAnnotation,
            isReplacement: isTextReplacementAnnotation
        ) {
        case .removeDraft:
            annotation.page?.removeAnnotation(annotation)
            changeHandler()
            return true
        case .rejectReplacement:
            statusHandler("Replacement text cannot be empty. Use a text box or a future redaction tool for removal.", true)
            return false
        case .allow:
            break
        }
        annotation.contents = textView.string
        annotation.setValue(false, forAnnotationKey: WorkspaceViewModel.draftTextAnnotationKey)
        if !isFreeTextAnnotation {
            changeHandler()
            return true
        }
        if isFreeTextAnnotation {
            annotation.font = documentFont()
            annotation.fontColor = editorTextColor
            annotation.alignment = editorAlignment
            annotation.color = PDFEditingSupport.replacementBackgroundColor(
                isReplacement: isTextReplacementAnnotation,
                originalBackground: originalSnapshot.color
            )
            guard resizeFreeTextAnnotationToFit(textView.string, preserveReplacementWidth: isTextReplacementAnnotation) else {
                originalSnapshot.restore(to: annotation)
                statusHandler(PDFTextEditWarning.invalidAnnotationBounds.message, true)
                return false
            }
        }
        if let document = annotation.page?.document, PDFSerializer.data(from: document) == nil {
            originalSnapshot.restore(to: annotation)
            statusHandler(PDFTextEditWarning.serializationFailed.message, true)
            return false
        }
        changeHandler()
        return true
    }

    private func cancelChanges() {
        didCancel = true
        if isDraftAnnotation, (originalSnapshot.contents ?? "").isEmpty {
            annotation.page?.removeAnnotation(annotation)
            changeHandler()
        } else {
            originalSnapshot.restore(to: annotation)
        }
    }

    private func resizeFreeTextAnnotationToFit(_ text: String, preserveReplacementWidth: Bool) -> Bool {
        guard isFreeTextAnnotation else { return true }
        let font = annotation.font ?? NSFont.systemFont(ofSize: minimumEditorFontSize)
        guard let bounds = PDFEditingSupport.resizedFreeTextBounds(
            currentBounds: annotation.bounds,
            text: text,
            font: font,
            preserveWidth: preserveReplacementWidth
        ) else {
            return false
        }
        annotation.bounds = bounds
        return true
    }

    private func formattingControls(frame: CGRect) -> NSView {
        let controls = NSView(frame: frame)

        let family = NSPopUpButton(frame: CGRect(x: 4, y: 58, width: 184, height: 28), pullsDown: false)
        let families = ["Helvetica", "Times", "Courier", "Avenir", "Menlo"]
        family.addItems(withTitles: families)
        if let match = families.first(where: { editorFontFamily.localizedCaseInsensitiveContains($0) || $0.localizedCaseInsensitiveContains(editorFontFamily) }) {
            family.selectItem(withTitle: match)
        } else {
            family.insertItem(withTitle: editorFontFamily, at: 0)
            family.selectItem(at: 0)
        }
        family.target = self
        family.action = #selector(changeFontFamily(_:))
        family.toolTip = "Font family"
        controls.addSubview(family)

        let sizeStepper = NSStepper(frame: CGRect(x: 252, y: 58, width: 18, height: 28))
        sizeStepper.minValue = 8
        sizeStepper.maxValue = 72
        sizeStepper.integerValue = Int(round(editorFontSize))
        sizeStepper.target = self
        sizeStepper.action = #selector(changeFontSize(_:))
        sizeStepper.toolTip = "Font size"
        controls.addSubview(sizeStepper)

        let label = NSTextField(labelWithString: "\(Int(round(editorFontSize)))")
        label.alignment = .center
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.frame = CGRect(x: 198, y: 63, width: 44, height: 18)
        controls.addSubview(label)
        sizeLabel = label

        let bold = formattingButton(title: "B", x: 4, y: 18, action: #selector(toggleBold), isToggle: true)
        bold.font = .boldSystemFont(ofSize: 13)
        bold.state = editorFontTraits.contains(.boldFontMask) ? .on : .off
        bold.toolTip = "Bold"
        controls.addSubview(bold)

        let italic = formattingButton(title: "I", x: 42, y: 18, action: #selector(toggleItalic), isToggle: true)
        italic.font = NSFontManager.shared.convert(NSFont.systemFont(ofSize: 13), toHaveTrait: .italicFontMask)
        italic.state = editorFontTraits.contains(.italicFontMask) ? .on : .off
        italic.toolTip = "Italic"
        controls.addSubview(italic)

        let align = NSSegmentedControl(labels: ["L", "C", "R"], trackingMode: .selectOne, target: self, action: #selector(changeAlignment(_:)))
        align.frame = CGRect(x: 88, y: 18, width: 96, height: 28)
        align.toolTip = "Text alignment"
        align.selectedSegment = selectedAlignmentSegment()
        controls.addSubview(align)

        let swatches: [(NSColor, CGFloat, String, Int)] = [
            (.labelColor, 204, "Default", 0),
            (.dsTextPrimaryNS, 234, "PDFold blue", 1),
            (.systemRed, 264, "Red", 2),
            (.white, 294, "White", 3)
        ]
        for (color, x, name, tag) in swatches {
            let button = NSButton(title: "", target: self, action: #selector(changeTextColor(_:)))
            button.frame = CGRect(x: x, y: 21, width: 20, height: 20)
            button.bezelStyle = .shadowlessSquare
            button.setButtonType(.momentaryChange)
            button.isBordered = false
            button.image = nil
            button.attributedTitle = NSAttributedString(string: "")
            button.toolTip = "\(name) text"
            button.wantsLayer = true
            button.layer?.backgroundColor = color.cgColor
            button.layer?.cornerRadius = 10
            button.layer?.borderWidth = 1
            button.layer?.borderColor = NSColor.dsSeparatorNS.cgColor
            button.tag = tag
            controls.addSubview(button)
        }

        return controls
    }

    private func formattingButton(title: String, x: CGFloat, y: CGFloat, action: Selector, isToggle: Bool = false) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.frame = CGRect(x: x, y: y, width: 30, height: 28)
        button.bezelStyle = .rounded
        button.setButtonType(isToggle ? .toggle : .momentaryPushIn)
        button.controlSize = .small
        return button
    }

    @objc private func toggleBold(_ sender: NSButton) {
        toggleTrait(.boldFontMask, enabled: sender.state == .on)
    }

    @objc private func toggleItalic(_ sender: NSButton) {
        toggleTrait(.italicFontMask, enabled: sender.state == .on)
    }

    @objc private func changeFontSize(_ sender: NSStepper) {
        editorFontSize = CGFloat(sender.integerValue)
        applyFormatting()
    }

    @objc private func changeTextColor(_ sender: NSButton) {
        switch sender.tag {
        case 1: editorTextColor = .dsTextPrimaryNS
        case 2: editorTextColor = .systemRed
        case 3: editorTextColor = .white
        default: editorTextColor = .labelColor
        }
        applyFormatting()
    }

    @objc private func changeFontFamily(_ sender: NSPopUpButton) {
        editorFontFamily = sender.titleOfSelectedItem ?? editorFontFamily
        applyFormatting()
    }

    @objc private func changeAlignment(_ sender: NSSegmentedControl) {
        switch sender.selectedSegment {
        case 1: editorAlignment = .center
        case 2: editorAlignment = .right
        default: editorAlignment = .left
        }
        applyFormatting()
    }

    private func toggleTrait(_ trait: NSFontTraitMask, enabled: Bool) {
        if enabled {
            editorFontTraits.insert(trait)
        } else {
            editorFontTraits.remove(trait)
        }
        applyFormatting()
    }

    private func applyFormatting() {
        styleChanged = true
        sizeLabel?.stringValue = "\(Int(round(editorFontSize)))"
        let fieldColors = PDFEditingSupport.editorFieldColors(for: editorTextColor)
        textView?.font = editorFont()
        textView?.textColor = fieldColors.foreground
        textView?.alignment = editorAlignment
        textView?.backgroundColor = fieldColors.background
        scrollView?.backgroundColor = fieldColors.background
        scrollView?.layer?.backgroundColor = fieldColors.background.cgColor
    }

    private func editorFont() -> NSFont {
        let descriptor = NSFontDescriptor(fontAttributes: [.family: editorFontFamily])
        let base = NSFont(descriptor: descriptor, size: editorFontSize) ?? NSFont.systemFont(ofSize: editorFontSize)
        return applyTraits(to: base)
    }

    private func documentFont() -> NSFont {
        guard styleChanged else {
            return originalSnapshot.font ?? annotation.font ?? editorFont()
        }
        let base = NSFont(name: editorFontFamily, size: editorFontSize) ?? editorFont()
        return applyTraits(to: base)
    }

    private func applyTraits(to font: NSFont) -> NSFont {
        var resolved = font
        if editorFontTraits.contains(.boldFontMask) {
            resolved = NSFontManager.shared.convert(resolved, toHaveTrait: .boldFontMask)
        } else {
            resolved = NSFontManager.shared.convert(resolved, toNotHaveTrait: .boldFontMask)
        }
        if editorFontTraits.contains(.italicFontMask) {
            resolved = NSFontManager.shared.convert(resolved, toHaveTrait: .italicFontMask)
        } else {
            resolved = NSFontManager.shared.convert(resolved, toNotHaveTrait: .italicFontMask)
        }
        return resolved
    }

    private func selectedAlignmentSegment() -> Int {
        switch editorAlignment {
        case .center: return 1
        case .right: return 2
        default: return 0
        }
    }

}

// MARK: - Inline PDF text editor

final class InlineTextEditorOverlay: NSView, NSTextViewDelegate {
    struct EditResult {
        var pageRef: PageRef
        var block: EditableTextBlock
        var text: String
        var editedBounds: CGRect
        var fontName: String
        var fontSize: CGFloat
        var textColor: NSColor
        var alignment: NSTextAlignment
    }

    enum Completion {
        case commit(EditResult)
        case cancel
    }

    private weak var pdfView: PDFView?
    private weak var page: PDFPage?
    private let pageRef: PageRef
    private let block: EditableTextBlock
    private let completion: (Completion) -> Void
    private let patchView = NSView()
    private let toolbar = NSView()
    private let textView = NSTextView()
    private let resizeHandle = InlineResizeHandle()
    private let familyPopup = NSPopUpButton()
    private let sizeStepper = NSStepper()
    private let sizeLabel = NSTextField(labelWithString: "")
    private let boldButton = NSButton(title: "B", target: nil, action: nil)
    private let italicButton = NSButton(title: "I", target: nil, action: nil)
    private let alignControl = NSSegmentedControl(labels: ["L", "C", "R"], trackingMode: .selectOne, target: nil, action: nil)
    private var editorFontName: String
    private var editorFontSize: CGFloat
    private var editorTextColor: NSColor
    private var editorAlignment: NSTextAlignment = .left
    private var didFinish = false
    private var editorTopY: CGFloat = 0
    private var didManuallyResizeWidth = false

    init(
        frame: CGRect,
        pdfView: PDFView,
        page: PDFPage,
        pageRef: PageRef,
        block: EditableTextBlock,
        completion: @escaping (Completion) -> Void
    ) {
        self.pdfView = pdfView
        self.page = page
        self.pageRef = pageRef
        self.block = block
        self.completion = completion
        editorFontName = block.fontName
        editorFontSize = max(8, block.fontSize)
        editorTextColor = block.textColor.nsColor
        super.init(frame: frame)
        setup()
        layoutEditor()
    }

    required init?(coder: NSCoder) { nil }

    func beginEditing() {
        window?.makeFirstResponder(textView)
        if textView.string.isEmpty {
            textView.setSelectedRange(NSRange(location: 0, length: 0))
        } else {
            textView.selectAll(nil)
        }
    }

    func cancel() {
        guard !didFinish else { return }
        didFinish = true
        removeFromSuperview()
        completion(.cancel)
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil, !didFinish {
            didFinish = true
            completion(.cancel)
        }
    }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        patchView.wantsLayer = true
        patchView.layer?.backgroundColor = NSColor.white.cgColor
        addSubview(patchView)

        textView.delegate = self
        textView.string = block.text
        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.drawsBackground = true
        textView.backgroundColor = NSColor.white.withAlphaComponent(0.98)
        textView.textColor = editorTextColor
        textView.insertionPointColor = .dsAccentNS
        textView.textContainerInset = NSSize(width: 3, height: 2)
        textView.textContainer?.lineFragmentPadding = 0
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = []
        textView.wantsLayer = true
        textView.layer?.borderWidth = 1
        textView.layer?.borderColor = NSColor.dsAccentNS.withAlphaComponent(0.75).cgColor
        textView.layer?.cornerRadius = 2
        addSubview(textView)

        resizeHandle.onDrag = { [weak self] deltaX in
            self?.resizeEditor(by: deltaX)
        }
        addSubview(resizeHandle)

        toolbar.wantsLayer = true
        toolbar.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.96).cgColor
        toolbar.layer?.cornerRadius = 7
        toolbar.layer?.cornerCurve = .continuous
        toolbar.layer?.shadowColor = NSColor.black.cgColor
        toolbar.layer?.shadowOpacity = 0.16
        toolbar.layer?.shadowRadius = 10
        toolbar.layer?.shadowOffset = CGSize(width: 0, height: -2)
        addSubview(toolbar)
        setupToolbar()
        applyFormatting()
    }

    private func setupToolbar() {
        let families = ["Helvetica", "Times", "Courier", "Avenir", "Menlo"]
        // Capture bold/italic from the detected font BEFORE the family list below
        // collapses e.g. "Times New Roman Bold" down to the generic "Times" entry, so the
        // toggle buttons (and applyFormatting()) can still reconstruct the right weight.
        let detectedFont = NSFont(name: editorFontName, size: editorFontSize) ?? .systemFont(ofSize: editorFontSize)
        let detectedTraits = NSFontManager.shared.traits(of: detectedFont)
        familyPopup.addItems(withTitles: families)
        if let match = families.first(where: { editorFontName.localizedCaseInsensitiveContains($0) }) {
            familyPopup.selectItem(withTitle: match)
            editorFontName = match
        } else {
            familyPopup.insertItem(withTitle: editorFontName, at: 0)
            familyPopup.selectItem(at: 0)
        }
        familyPopup.target = self
        familyPopup.action = #selector(changeFamily(_:))
        familyPopup.frame = CGRect(x: 8, y: 8, width: 142, height: 26)
        toolbar.addSubview(familyPopup)

        sizeLabel.alignment = .center
        sizeLabel.font = .systemFont(ofSize: 12, weight: .medium)
        sizeLabel.frame = CGRect(x: 154, y: 12, width: 34, height: 18)
        toolbar.addSubview(sizeLabel)

        sizeStepper.minValue = 6
        sizeStepper.maxValue = 96
        sizeStepper.integerValue = Int(round(editorFontSize))
        sizeStepper.target = self
        sizeStepper.action = #selector(changeSize(_:))
        sizeStepper.frame = CGRect(x: 190, y: 8, width: 18, height: 26)
        toolbar.addSubview(sizeStepper)

        boldButton.target = self
        boldButton.action = #selector(toggleBold)
        boldButton.setButtonType(.toggle)
        boldButton.bezelStyle = .rounded
        boldButton.font = .boldSystemFont(ofSize: 12)
        boldButton.state = detectedTraits.contains(.boldFontMask) ? .on : .off
        boldButton.frame = CGRect(x: 222, y: 8, width: 32, height: 26)
        toolbar.addSubview(boldButton)

        italicButton.target = self
        italicButton.action = #selector(toggleItalic)
        italicButton.setButtonType(.toggle)
        italicButton.bezelStyle = .rounded
        italicButton.font = NSFontManager.shared.convert(NSFont.systemFont(ofSize: 12), toHaveTrait: .italicFontMask)
        italicButton.state = detectedTraits.contains(.italicFontMask) ? .on : .off
        italicButton.frame = CGRect(x: 258, y: 8, width: 32, height: 26)
        toolbar.addSubview(italicButton)

        alignControl.target = self
        alignControl.action = #selector(changeAlignment(_:))
        alignControl.selectedSegment = 0
        alignControl.frame = CGRect(x: 302, y: 8, width: 82, height: 26)
        toolbar.addSubview(alignControl)

        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelButton))
        cancel.bezelStyle = .rounded
        cancel.frame = CGRect(x: 398, y: 8, width: 68, height: 26)
        toolbar.addSubview(cancel)

        let done = NSButton(title: "Done", target: self, action: #selector(commitButton))
        done.bezelStyle = .rounded
        done.contentTintColor = .dsAccentNS
        done.keyEquivalent = "\r"
        done.frame = CGRect(x: 472, y: 8, width: 62, height: 26)
        toolbar.addSubview(done)
    }

    private func layoutEditor() {
        guard let pdfView, let page else { return }
        let sourceRect = pdfView.convert(block.bounds, from: page)
        let minWidth: CGFloat = 48
        let editorRect = CGRect(
            x: sourceRect.minX,
            y: sourceRect.minY,
            width: max(minWidth, sourceRect.width),
            height: max(sourceRect.height + 6, editorFontSize * 1.5)
        )
        editorTopY = editorRect.maxY
        patchView.frame = sourceRect.insetBy(dx: -2, dy: -2)
        textView.frame = editorRect
        toolbar.frame = toolbarFrame(near: editorRect)
        resizeHandle.frame = CGRect(x: editorRect.maxX - 5, y: editorRect.minY - 5, width: 10, height: 10)
        resizeTextViewHeight()
    }

    private func toolbarFrame(near editorRect: CGRect) -> CGRect {
        let size = CGSize(width: 542, height: 42)
        let x = min(max(editorRect.midX - size.width / 2, 8), max(8, bounds.width - size.width - 8))
        let aboveY = editorRect.maxY + 8
        let y = aboveY + size.height < bounds.height ? aboveY : max(8, editorRect.minY - size.height - 8)
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }

    private func resizeTextViewHeight() {
        autoFitWidthIfNeeded()
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }
        layoutManager.ensureLayout(for: textContainer)
        let used = layoutManager.usedRect(for: textContainer)
        var frame = textView.frame
        let minimumHeight = max(24, ceil(editorFontSize * 1.55))
        frame.size.height = max(minimumHeight, ceil(used.height + textView.textContainerInset.height * 2 + 4))
        frame.origin.y = editorTopY - frame.height
        textView.frame = frame
        toolbar.frame = toolbarFrame(near: frame)
        resizeHandle.frame = CGRect(x: frame.maxX - 5, y: frame.minY - 5, width: 10, height: 10)
    }

    /// Grows the text box to fit what's currently typed, so a short original word (e.g.
    /// "Hi") replaced with a much longer phrase doesn't get word-wrapped/clipped inside a
    /// box still sized for the original text. No-ops once the user has manually dragged
    /// the resize handle, so an explicit width choice is always respected.
    private func autoFitWidthIfNeeded() {
        guard !didManuallyResizeWidth, let pdfView, let page else { return }
        let font = textView.font ?? NSFont(name: editorFontName, size: editorFontSize) ?? .systemFont(ofSize: editorFontSize)
        let text = textView.string.isEmpty ? " " : textView.string
        let unwrapped = (text as NSString).boundingRect(
            with: CGSize(width: .greatestFiniteMagnitude, height: font.pointSize * 2),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        )
        let desired = ceil(unwrapped.width) + textView.textContainerInset.width * 2 + 6

        let pageViewBounds = pdfView.convert(page.bounds(for: .cropBox), from: page).standardized
        let maxAvailable = max(120, pageViewBounds.maxX - textView.frame.minX - 12)
        let maxWidth = min(620, maxAvailable)
        let minWidth: CGFloat = 48
        let newWidth = min(max(minWidth, desired), maxWidth)

        guard abs(newWidth - textView.frame.width) > 0.5 else { return }
        var frame = textView.frame
        frame.size.width = newWidth
        textView.frame = frame
        textView.textContainer?.containerSize = NSSize(width: newWidth - textView.textContainerInset.width * 2, height: .infinity)
    }

    private func resizeEditor(by deltaX: CGFloat) {
        didManuallyResizeWidth = true
        var frame = textView.frame
        frame.size.width = max(48, frame.width + deltaX)
        textView.frame = frame
        textView.textContainer?.containerSize = NSSize(width: frame.width - textView.textContainerInset.width * 2, height: CGFloat.infinity)
        resizeTextViewHeight()
    }

    func textDidChange(_ notification: Notification) {
        resizeTextViewHeight()
    }

    @objc private func changeFamily(_ sender: NSPopUpButton) {
        editorFontName = sender.titleOfSelectedItem ?? editorFontName
        applyFormatting()
    }

    @objc private func changeSize(_ sender: NSStepper) {
        editorFontSize = CGFloat(sender.integerValue)
        applyFormatting()
    }

    @objc private func toggleBold() {
        applyFormatting()
    }

    @objc private func toggleItalic() {
        applyFormatting()
    }

    @objc private func changeAlignment(_ sender: NSSegmentedControl) {
        switch sender.selectedSegment {
        case 1: editorAlignment = .center
        case 2: editorAlignment = .right
        default: editorAlignment = .left
        }
        applyFormatting()
    }

    private func applyFormatting() {
        sizeLabel.stringValue = "\(Int(round(editorFontSize)))"
        var font = NSFont(name: editorFontName, size: editorFontSize) ?? .systemFont(ofSize: editorFontSize)
        if boldButton.state == .on {
            font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
        }
        if italicButton.state == .on {
            font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
        }
        textView.font = font
        textView.textColor = editorTextColor
        textView.alignment = editorAlignment
        resizeTextViewHeight()
    }

    /// Commits the pending edit (same as pressing Done) if there's something worth saving,
    /// otherwise cancels cleanly. Called when the user starts editing a different block
    /// while this one is still open, so switching targets saves in-progress work instead
    /// of silently discarding it — clicking away should behave like Adobe/most editors,
    /// not like an implicit "undo everything I just typed."
    func finishForHandoff() {
        guard !didFinish else { return }
        if textView.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            cancel()
        } else {
            commitButton()
        }
    }

    @objc fileprivate func commitButton() {
        guard !didFinish, let pdfView, let page else { return }
        didFinish = true
        // Use the live editor box's own position AND size, converted to page space —
        // not just its size merged onto the original (pre-edit) block position. The box
        // commonly moves (its top-anchored height grows as text wraps) and re-using the
        // stale origin here placed the replacement text somewhere the user never saw it.
        // Two-step conversion (overlay-local → pdfView space → PDF page space) avoids
        // relying on the overlay's frame origin always being (0,0).
        let viewFrame = convert(textView.frame, to: pdfView)
        var pageBounds = pdfView.convert(viewFrame, to: page).standardized
        pageBounds.size.width = max(24, pageBounds.width)
        pageBounds.size.height = max(24, pageBounds.height)
        let result = EditResult(
            pageRef: pageRef,
            block: block,
            text: textView.string,
            editedBounds: pageBounds,
            fontName: textView.font?.fontName ?? editorFontName,
            fontSize: textView.font?.pointSize ?? editorFontSize,
            textColor: editorTextColor,
            alignment: editorAlignment
        )
        removeFromSuperview()
        completion(.commit(result))
    }

    @objc private func cancelButton() {
        cancel()
    }
}

final class InlineResizeHandle: NSView {
    var onDrag: ((CGFloat) -> Void)?
    private var lastPoint: CGPoint?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.dsAccentNS.cgColor
        layer?.cornerRadius = 5
    }

    required init?(coder: NSCoder) { nil }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    override func mouseDown(with event: NSEvent) {
        lastPoint = convert(event.locationInWindow, from: nil)
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let lastPoint {
            onDrag?(point.x - lastPoint.x)
        }
        self.lastPoint = point
    }

    override func mouseUp(with event: NSEvent) {
        lastPoint = nil
    }
}

// MARK: - Ink drawing overlay

final class InkOverlayView: NSView {
    var onStrokeCommitted: ((NSBezierPath) -> Void)?
    var inkColor: NSColor = .dsInk

    private var currentPath: NSBezierPath?
    private var committedPaths: [NSBezierPath] = []
    private let lineWidth: CGFloat = 2.0

    override var isFlipped: Bool { true }

    func clearCommittedPaths() {
        committedPaths.removeAll()
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let path = NSBezierPath()
        path.lineWidth = lineWidth
        path.move(to: point)
        currentPath = path
    }

    override func mouseDragged(with event: NSEvent) {
        guard let path = currentPath else { return }
        path.line(to: convert(event.locationInWindow, from: nil))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let path = currentPath, path.elementCount > 1 else {
            currentPath = nil
            return
        }
        committedPaths.append(path)
        currentPath = nil
        onStrokeCommitted?(path)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill()
        inkColor.withAlphaComponent(0.8).setStroke()
        committedPaths.forEach { $0.stroke() }
        currentPath?.stroke()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        isHidden ? nil : super.hitTest(point)
    }
}
