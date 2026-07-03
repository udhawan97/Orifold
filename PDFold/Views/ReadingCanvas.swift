import SwiftUI
import PDFKit

// MARK: - Reading canvas shell (PDF + zoom/page bar)

private let canvasBannerHeight: CGFloat = 48

struct ReadingCanvas: View {
    @Bindable var viewModel: WorkspaceViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shouldReduceMotion: Bool {
        reduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    var body: some View {
        VStack(spacing: 0) {
            ZoomPageBar(viewModel: viewModel)
            ZStack(alignment: .top) {
                PDFViewRepresentable(viewModel: viewModel)
                ScanBar(viewModel: viewModel)
                    .frame(height: canvasBannerHeight)
                    .opacity(viewModel.hasScannedPages ? 1 : 0)
                    .allowsHitTesting(viewModel.hasScannedPages)
                    .accessibilityHidden(!viewModel.hasScannedPages)
                    .animation(shouldReduceMotion ? nil : .easeInOut(duration: 0.18), value: viewModel.hasScannedPages)
                FormBar(viewModel: viewModel)
                    .frame(height: canvasBannerHeight)
                    .padding(.top, viewModel.hasScannedPages ? canvasBannerHeight : 0)
                    .opacity(viewModel.hasFormNotice ? 1 : 0)
                    .allowsHitTesting(viewModel.hasFormNotice)
                    .accessibilityHidden(!viewModel.hasFormNotice)
                    .animation(shouldReduceMotion ? nil : .easeInOut(duration: 0.18), value: viewModel.hasFormNotice)
                if viewModel.hasPendingSignaturePlacement {
                    SignaturePlacementBanner {
                        viewModel.cancelSignaturePlacement()
                    }
                    .padding(.top, viewModel.canvasBannerInset + .dsMD)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                if let status = viewModel.editingStatus {
                    EditingStatusBanner(status: status) {
                        viewModel.editingStatus = nil
                    }
                    .padding(.top, viewModel.canvasBannerInset + (viewModel.hasPendingSignaturePlacement ? 48 : 0) + .dsMD)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task(id: status.id) {
                        guard !viewModel.hasPendingSignaturePlacement else { return }
                        guard !status.isError else { return }
                        try? await Task.sleep(for: .seconds(4))
                        guard !Task.isCancelled, viewModel.editingStatus?.id == status.id else { return }
                        viewModel.editingStatus = nil
                    }
                }
            }
        }
        .animation(shouldReduceMotion ? nil : .easeInOut(duration: 0.18), value: viewModel.editingStatus?.id)
    }
}

private struct SignaturePlacementBanner: View {
    var cancel: () -> Void

    var body: some View {
        HStack(spacing: .dsSM) {
            Image(systemName: "signature")
                .foregroundStyle(Color.dsSignatureAccent)
            Text("Click a page to place the signature.")
                .font(.dsCaption())
                .foregroundStyle(Color.dsTextPrimary)
            Button("Cancel", action: cancel)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Cancel signature placement")
        }
        .padding(.horizontal, .dsMD)
        .padding(.vertical, .dsSM)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: .dsRadiusSm, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: .dsRadiusSm, style: .continuous)
                .strokeBorder(Color.dsSeparator, lineWidth: 1)
        }
    }
}

private struct ScanBar: View {
    @Bindable var viewModel: WorkspaceViewModel

    var body: some View {
        HStack(spacing: .dsMD) {
            Image(systemName: "doc.text.viewfinder")
                .foregroundStyle(Color.dsAccent)
            Text("This document is a scan")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.dsTextPrimary)
            Spacer()
            Button("Make it searchable") {
                viewModel.makeSearchable()
            }
            .font(.dsCaption())
            .disabled(viewModel.operationProgress.isActive)
        }
        .padding(.horizontal, .dsLG)
        .padding(.vertical, .dsSM)
        .background(.regularMaterial)
        .overlay {
            RoundedRectangle(cornerRadius: .dsRadiusSm, style: .continuous)
                .strokeBorder(Color.dsSeparator, lineWidth: 1)
        }
        .padding(.horizontal, .dsLG)
    }
}

private struct FormBar: View {
    @Bindable var viewModel: WorkspaceViewModel

    var body: some View {
        HStack(spacing: .dsMD) {
            Image(systemName: "rectangle.and.pencil.and.ellipsis")
                .foregroundStyle(Color.dsAccent)
            VStack(alignment: .leading, spacing: 2) {
                if viewModel.hasFillableFormFields {
                    HStack(spacing: .dsSM) {
                        Text("This PDF has fillable fields")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.dsTextPrimary)
                        Text("\(viewModel.formSummary.fieldCount) fields")
                            .font(.dsCaption())
                            .foregroundStyle(Color.dsTextSecondary)
                    }
                }
                if viewModel.formSummary.hasUnsupportedDynamicFeatures {
                    Text("Some dynamic form features may not work in pdFold.")
                        .font(.dsCaption())
                        .foregroundStyle(Color.dsTextTertiary)
                }
            }
            Spacer()
            if viewModel.hasFillableFormFields {
                Toggle("Highlight fields", isOn: $viewModel.highlightFormFields)
                    .toggleStyle(.checkbox)
                    .font(.dsCaption())
                    .tint(Color.dsAccentSoft)
                Button {
                    viewModel.selectPreviousFormField()
                } label: {
                    Image(systemName: "chevron.up")
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.borderless)
                .help("Previous field")
                Button {
                    viewModel.selectNextFormField()
                } label: {
                    Image(systemName: "chevron.down")
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.borderless)
                .help("Next field")
                Button("Reset form") {
                    viewModel.resetFormFields()
                }
                .font(.dsCaption())
            }
        }
        .padding(.horizontal, .dsLG)
        .padding(.vertical, .dsSM)
        .background(.regularMaterial)
        .overlay {
            RoundedRectangle(cornerRadius: .dsRadiusSm, style: .continuous)
                .strokeBorder(Color.dsSeparator, lineWidth: 1)
        }
        .padding(.horizontal, .dsLG)
    }
}

private struct EditingStatusBanner: View {
    var status: WorkspaceViewModel.EditingStatus
    var dismiss: () -> Void

    var body: some View {
        HStack(spacing: .dsSM) {
            Image(systemName: status.isError ? "exclamationmark.triangle.fill" : "info.circle.fill")
                .foregroundStyle(status.isError ? Color.dsAnnotationCoral : Color.dsAccent)
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
                HStack(spacing: 6) {
                    Text("Page")
                        .foregroundStyle(Color.dsTextTertiary)
                    TextField("", text: $pageInput)
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.center)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.dsTextPrimary)
                        .frame(width: 34, height: 22)
                        .background(Color.dsSurface, in: RoundedRectangle(cornerRadius: .dsRadiusSm, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: .dsRadiusSm, style: .continuous)
                                .strokeBorder(pageFieldFocused ? Color.dsAccent : Color.dsSeparator, lineWidth: 1)
                        }
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
                    Text("/ \(viewModel.pageCount)")
                        .monospacedDigit()
                        .foregroundStyle(Color.dsTextSecondary)
                }
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Color.dsCard, in: Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(Color.dsSeparator.opacity(0.85), lineWidth: 1)
                }
                .onChange(of: viewModel.currentPageNumber) { _, n in
                    if !pageFieldFocused { pageInput = "\(n)" }
                }
                .onAppear { pageInput = "\(max(1, viewModel.currentPageNumber))" }
                .help("Jump to page")
            }
        }
        .padding(.horizontal, .dsLG)
        .padding(.vertical, 6)
        .background(Color.dsSurface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.dsSeparator).frame(height: 0.5)
        }
        .accessibilityElement(children: .contain)
    }
}

private struct BottomBarBrand: View {
    var body: some View {
        HStack(spacing: .dsXS) {
            AppIconMark(size: 16)
            Text("pdFold")
                .font(.system(size: 11, weight: .medium, design: .serif))
                .foregroundStyle(Color.dsTextTertiary)
                .lineLimit(1)
        }
        .accessibilityLabel("pdFold")
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
        view.pageOverlayViewProvider = context.coordinator

        // Wire up delete key handler
        view.onDeleteKey = { [weak coordinator = context.coordinator] in
            coordinator?.viewModel.deleteSelectedAnnotation()
            coordinator?.refreshSignatureOverlay()
            coordinator?.refreshDecorationOverlays()
        }
        view.onTabKey = { [weak coordinator = context.coordinator] moveBackward in
            guard let viewModel = coordinator?.viewModel,
                  viewModel.hasFillableFormFields else {
                return false
            }
            if moveBackward {
                viewModel.selectPreviousFormField()
            } else {
                viewModel.selectNextFormField()
            }
            coordinator?.refreshDecorationOverlays()
            return true
        }
        view.onSelectionCommitted = { [weak coordinator = context.coordinator] in
            coordinator?.commitCurrentMarkupSelection()
        }
        view.onCommentMenu = { [weak coordinator = context.coordinator] in
            coordinator?.createCommentFromCurrentSelection()
        }

        // Click gesture
        let click = NSClickGestureRecognizer(target: context.coordinator,
                                             action: #selector(Coordinator.handleClick(_:)))
        click.numberOfClicksRequired = 1
        click.delegate = context.coordinator
        view.addGestureRecognizer(click)

        // Ink overlay
        let overlay = context.coordinator.inkOverlay
        overlay.frame = view.bounds
        overlay.autoresizingMask = [.width, .height]
        overlay.isHidden = true
        view.addSubview(overlay)

        let signatureOverlay = context.coordinator.signatureOverlay
        signatureOverlay.frame = view.bounds
        signatureOverlay.autoresizingMask = [.width, .height]
        signatureOverlay.isHidden = true
        view.addSubview(signatureOverlay)

        let markerOverlay = context.coordinator.commentMarkerOverlay
        markerOverlay.frame = view.bounds
        markerOverlay.autoresizingMask = [.width, .height]
        view.addSubview(markerOverlay)

        let regionOverlay = context.coordinator.commentRegionOverlay
        regionOverlay.frame = view.bounds
        regionOverlay.autoresizingMask = [.width, .height]
        regionOverlay.isHidden = true
        view.addSubview(regionOverlay)

        // Notifications
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
            selector: #selector(Coordinator.jumpToFormField(_:)),
            name: .pdfoldJumpToFormField, object: nil)
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.jumpToAnnotation(_:)),
            name: .pdfoldJumpToAnnotation, object: nil)
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.editAnnotation(_:)),
            name: .pdfoldEditAnnotation, object: nil)
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.printDocument(_:)),
            name: .pdfoldPrint, object: nil)
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.createCommentFromSelection(_:)),
            name: .pdfoldCreateCommentFromSelection, object: nil)
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
            selector: #selector(Coordinator.pdfViewGeometryChanged(_:)),
            name: .PDFViewScaleChanged, object: view)

        context.coordinator.pdfView = view
        context.coordinator.observePDFViewBounds(view)
        context.coordinator.setupInkOverlay()
        context.coordinator.setupSignatureOverlay()
        context.coordinator.setupCommentRegionOverlay()
        return view
    }

    func updateNSView(_ nsView: PDFoldPDFView, context: Context) {
        if nsView.document !== viewModel.combinedPDF {
            nsView.document = viewModel.combinedPDF
        }
        context.coordinator.viewModel = viewModel
        context.coordinator.inkOverlay.isHidden = (viewModel.currentTool != .ink)
        context.coordinator.inkOverlay.inkColor = viewModel.inkColor
        context.coordinator.refreshSignatureOverlay()
        context.coordinator.refreshDecorationOverlays()
        context.coordinator.refreshCommentOverlays()
        context.coordinator.updateCanvasBannerInset(viewModel.canvasBannerInset)
        // Switching to a different tool (e.g. clicking Highlight) without clicking Done
        // first must not silently drop whatever text is still being edited.
        if viewModel.currentTool != .editText {
            context.coordinator.finishInlineEditingIfNeeded()
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSPopoverDelegate, NSGestureRecognizerDelegate, PDFPageOverlayViewProvider {
        var viewModel: WorkspaceViewModel
        weak var pdfView: PDFoldPDFView?
        let inkOverlay = InkOverlayView()
        let signatureOverlay = SignatureSelectionOverlayView()
        let commentMarkerOverlay = CommentMarkerOverlayView()
        let commentRegionOverlay = CommentRegionOverlayView()
        private weak var inlineEditor: InlineTextEditorOverlay?
        private var notePopover: NSPopover?
        private let decorationOverlays = NSHashTable<PageDecorationOverlayView>.weakObjects()
        private weak var observedClipView: NSClipView?

        init(viewModel: WorkspaceViewModel) {
            self.viewModel = viewModel
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        func observePDFViewBounds(_ pdfView: PDFoldPDFView) {
            if let observedClipView {
                NotificationCenter.default.removeObserver(
                    self,
                    name: NSView.boundsDidChangeNotification,
                    object: observedClipView
                )
            }
            guard let clipView = pdfView.findEnclosingScrollView()?.contentView else {
                observedClipView = nil
                return
            }
            clipView.postsBoundsChangedNotifications = true
            observedClipView = clipView
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(pdfViewGeometryChanged(_:)),
                name: NSView.boundsDidChangeNotification,
                object: clipView
            )
        }

        func finishInlineEditingIfNeeded() {
            inlineEditor?.finishForHandoff()
        }

        func commitCurrentMarkupSelection() {
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
            case .comment:
                createComment(from: selection)
            default:
                break
            }
        }

        func createCommentFromCurrentSelection() {
            guard let pdfView,
                  let selection = pdfView.currentSelection,
                  !(selection.string?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) else {
                viewModel.showEditMessage("Select text before adding a comment.", isError: false)
                return
            }
            createComment(from: selection)
        }

        @objc func createCommentFromSelection(_ notification: Notification) {
            createCommentFromCurrentSelection()
        }

        private func createComment(from selection: PDFSelection) {
            guard let pdfView,
                  viewModel.createAnchoredTextComment(from: selection, in: pdfView.document) != nil else { return }
            pdfView.clearSelection()
            refreshCommentOverlays()
        }

        @objc func handleClick(_ gesture: NSClickGestureRecognizer) {
            guard let pdfView else { return }
            let viewPoint = gesture.location(in: pdfView)
            if inlineEditor?.containsInteractivePoint(viewPoint) == true {
                return
            }
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
                    guard let ann = viewModel.addNote(at: pagePoint, on: page),
                          ann.page != nil else { return }
                    let rect = pdfView.convert(ann.bounds, from: page)
                    showNoteEditor(for: ann, near: rect, in: pdfView)
                }
            case .editText:
                inlineEditor?.finishForHandoff()
                if let target = viewModel.editableTextBlock(at: pagePoint, on: page, in: pdfView.document) {
                    showInlineTextEditor(
                        for: target.block,
                        pageRef: target.pageRef,
                        sourceFormat: target.sourceFormat,
                        on: page,
                        in: pdfView
                    )
                }
            case .signature:
                if let signatureData = viewModel.pendingSignatureData {
                    viewModel.placeSignature(imageData: signatureData, at: pagePoint, on: page)
                    refreshSignatureOverlay()
                } else {
                    viewModel.isShowingSignaturePalette = true
                }
            case .stamp:
                if viewModel.pendingStampOptions != nil {
                    viewModel.placeStamp(at: pagePoint, on: page)
                    refreshSignatureOverlay()
                    refreshDecorationOverlays()
                } else {
                    viewModel.isShowingStampPalette = true
                }
            case .eraser:
                viewModel.eraseMarkupAnnotation(at: pagePoint, on: page)
            case .none:
                // Track clicked annotation for Delete-key deletion
                if let stamp = viewModel.stampDecoration(at: pagePoint, on: page, in: pdfView.document) {
                    viewModel.selectedAnnotation = nil
                    viewModel.selectedStampDecorationID = stamp.id
                } else if let annotation = page.annotation(at: pagePoint) {
                    viewModel.selectedAnnotation = annotation
                    viewModel.selectedStampDecorationID = nil
                } else {
                    viewModel.selectedAnnotation = nil
                    viewModel.selectedStampDecorationID = nil
                }
                refreshSignatureOverlay()
            default:
                viewModel.selectedAnnotation = nil
                viewModel.selectedStampDecorationID = nil
                refreshSignatureOverlay()
            }
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: NSGestureRecognizer) -> Bool {
            guard let pdfView else { return true }
            let viewPoint = gestureRecognizer.location(in: pdfView)
            if signatureOverlay.containsInteractivePoint(viewPoint) {
                return false
            }
            return inlineEditor?.containsInteractivePoint(viewPoint) != true
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
                changeHandler: { [weak self, weak view] annotation, snapshot, actionName in
                    self?.viewModel.registerAnnotationEdit(annotation, from: snapshot, actionName: actionName)
                    view?.needsDisplay = true
                }
            )
            let popover = NSPopover()
            popover.contentViewController = vc
            popover.behavior = .transient
            popover.delegate = self
            vc.closeHandler = { [weak popover] in
                popover?.close()
            }
            notePopover = popover
            popover.show(relativeTo: rect, of: view, preferredEdge: .maxY)
        }

        func popoverDidClose(_ notification: Notification) {
            guard let popover = notification.object as? NSPopover, popover === notePopover else { return }
            notePopover = nil
        }

        private func showInlineTextEditor(
            for block: EditableTextBlock,
            pageRef: PageRef,
            sourceFormat: PDFTextEditFormat,
            on page: PDFPage,
            in pdfView: PDFoldPDFView
        ) {
            // Callers are expected to finish (commit or cancel) any previously open editor
            // before calling this — see the `.editText` handleClick case.
            assert(inlineEditor == nil, "a previous inline editor should already be finished")
            let isExistingEdit = viewModel.hasInlineTextEditOperation(pageRefID: pageRef.id, sourceBlockID: block.id)
            let editor = InlineTextEditorOverlay(
                frame: pdfView.bounds,
                viewModel: viewModel,
                pdfView: pdfView,
                page: page,
                pageRef: pageRef,
                block: block,
                sourceFormat: sourceFormat,
                isExistingEdit: isExistingEdit
            ) { [weak self, weak pdfView] result in
                guard let self else { return }
                switch result {
                case .commit(let edit):
                    self.mutateDocumentPreservingViewport(in: pdfView) {
                        self.viewModel.applyInlineTextEdit(
                            pageRef: edit.pageRef,
                            sourceBlock: edit.block,
                            replacementText: edit.text,
                            editedBounds: edit.editedBounds,
                            fontName: edit.fontName,
                            fontSize: edit.fontSize,
                            textColor: edit.textColor,
                            alignment: edit.alignment,
                            didManuallyReposition: edit.didManuallyReposition,
                            didManuallyResizeWidth: edit.didManuallyResizeWidth,
                            didManuallyResizeHeight: edit.didManuallyResizeHeight
                        )
                    }
                case .revertToOriginal:
                    self.mutateDocumentPreservingViewport(in: pdfView) {
                        self.viewModel.revertInlineTextEdit(pageRefID: pageRef.id, sourceBlockID: block.id)
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

        /// Runs a document-regenerating mutation while pinning the scroll viewport.
        /// Captures the actual scroll origin first — in continuous mode PDFKit's
        /// currentPage can be a different page than the mutation target, so page-based
        /// restoration alone can visibly jump after the document is regenerated.
        private func mutateDocumentPreservingViewport(in pdfView: PDFoldPDFView?, _ mutation: () -> Bool) {
            let savedViewportOrigin = visibleDocumentOrigin(in: pdfView)
            let savedDestination = pdfView?.currentDestination
            let savedPageIdx: Int? = {
                guard let pv = pdfView,
                      let pg = pv.currentPage,
                      let doc = pv.document else { return nil }
                let idx = doc.index(for: pg)
                return idx == NSNotFound ? nil : idx
            }()

            guard mutation() else { return }

            let newDoc = viewModel.combinedPDF
            // Always assign; SwiftUI may not have fired updateNSView yet.
            pdfView?.document = newDoc
            pdfView?.layoutDocumentView()
            if let origin = savedViewportOrigin {
                restoreVisibleDocumentOrigin(origin, in: pdfView)
            } else if let idx = savedPageIdx, let targetPage = newDoc.page(at: idx) {
                if let dest = savedDestination {
                    pdfView?.go(to: PDFDestination(page: targetPage, at: dest.point))
                } else {
                    pdfView?.go(to: targetPage)
                }
            }
            pdfView?.needsDisplay = true
        }

        private func visibleDocumentOrigin(in pdfView: PDFView?) -> CGPoint? {
            guard let documentView = pdfView?.documentView,
                  let clipView = documentView.enclosingScrollView?.contentView else { return nil }
            return clipView.bounds.origin
        }

        private func restoreVisibleDocumentOrigin(_ origin: CGPoint, in pdfView: PDFView?) {
            guard let documentView = pdfView?.documentView,
                  let scrollView = documentView.enclosingScrollView else { return }
            let clipView = scrollView.contentView
            let documentBounds = documentView.bounds
            let maxOrigin = CGPoint(
                x: max(0, documentBounds.maxX - clipView.bounds.width),
                y: max(0, documentBounds.maxY - clipView.bounds.height)
            )
            let restoredOrigin = CGPoint(
                x: min(max(0, origin.x), maxOrigin.x),
                y: min(max(0, origin.y), maxOrigin.y)
            )
            clipView.scroll(to: restoredOrigin)
            scrollView.reflectScrolledClipView(clipView)
        }

        @objc func jumpToSelection(_ notification: Notification) {
            guard let selection = notification.object as? PDFSelection else { return }
            pdfView?.go(to: selection)
            pdfView?.setCurrentSelection(selection, animate: true)
            refreshSignatureOverlay()
        }

        @objc func jumpToPageIndex(_ notification: Notification) {
            guard let idx = notification.object as? Int,
                  let page = pdfView?.document?.page(at: idx) else { return }
            pdfView?.go(to: page)
            refreshSignatureOverlay()
        }

        @objc func jumpToFormField(_ notification: Notification) {
            guard let target = notification.object as? PDFFormFieldNavigationTarget,
                  let pdfView,
                  let page = pdfView.document?.page(at: target.pageIndex) else { return }
            let destination = PDFDestination(page: page, at: CGPoint(x: target.bounds.midX, y: target.bounds.maxY))
            pdfView.go(to: destination)
            if target.fieldType != PDFAnnotationWidgetSubtype.button.rawValue {
                DispatchQueue.main.async { [weak pdfView] in
                    self.focusTextFormField(target, page: page, pdfView: pdfView)
                }
            } else {
                pdfView.window?.makeFirstResponder(pdfView)
            }
            refreshDecorationOverlays()
            refreshSignatureOverlay()
        }

        @objc func jumpToAnnotation(_ notification: Notification) {
            guard let annotation = notification.object as? PDFAnnotation,
                  let page = annotation.page,
                  let pdfView else { return }
            viewModel.selectedAnnotation = annotation
            viewModel.selectedStampDecorationID = nil
            goToAnnotation(annotation, on: page, in: pdfView)
            refreshSignatureOverlay()
            refreshDecorationOverlays()
            pdfView.needsDisplay = true
        }

        @objc func editAnnotation(_ notification: Notification) {
            guard let annotation = notification.object as? PDFAnnotation,
                  let page = annotation.page,
                  let pdfView else { return }
            viewModel.selectedAnnotation = annotation
            viewModel.selectedStampDecorationID = nil
            goToAnnotation(annotation, on: page, in: pdfView)
            guard annotation.type == "Text" || annotation.type == "FreeText" else {
                viewModel.showEditMessage("Only notes and text boxes can be edited directly. Use delete to remove this markup.", isError: false)
                return
            }
            let rect = pdfView.convert(annotation.bounds, from: page)
            showNoteEditor(for: annotation, near: rect, in: pdfView)
        }

        private func goToAnnotation(_ annotation: PDFAnnotation, on page: PDFPage, in pdfView: PDFView) {
            let targetPoint = CGPoint(x: annotation.bounds.midX, y: annotation.bounds.maxY)
            pdfView.go(to: PDFDestination(page: page, at: targetPoint))
        }

        private func focusTextFormField(_ target: PDFFormFieldNavigationTarget, page: PDFPage, pdfView: PDFView?) {
            guard let pdfView,
                  let window = pdfView.window else { return }
            let pagePoint = CGPoint(x: target.bounds.midX, y: target.bounds.midY)
            let viewPoint = pdfView.convert(pagePoint, from: page)
            guard pdfView.bounds.contains(viewPoint) else { return }
            let windowPoint = pdfView.convert(viewPoint, to: nil)
            let hitView = pdfView.hitTest(viewPoint) ?? pdfView
            if hitView !== pdfView, hitView.acceptsFirstResponder {
                window.makeFirstResponder(hitView)
            }
            let timestamp = ProcessInfo.processInfo.systemUptime
            guard let mouseDown = NSEvent.mouseEvent(
                with: .leftMouseDown,
                location: windowPoint,
                modifierFlags: [],
                timestamp: timestamp,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 1
            ),
            let mouseUp = NSEvent.mouseEvent(
                with: .leftMouseUp,
                location: windowPoint,
                modifierFlags: [],
                timestamp: timestamp,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 0
            ) else { return }
            hitView.mouseDown(with: mouseDown)
            hitView.mouseUp(with: mouseUp)
            if window.firstResponder == nil || window.firstResponder === window {
                window.makeFirstResponder(pdfView)
            }
        }

        @objc func printDocument(_ notification: Notification) {
            viewModel.printWorkspace()
        }

        @objc func zoomIn(_ notification: Notification) {
            pdfView?.zoomIn(nil)
        }

        @objc func zoomOut(_ notification: Notification) {
            pdfView?.zoomOut(nil)
        }

        @objc func zoomFit(_ notification: Notification) {
            pdfView?.autoScales = true
            refreshSignatureOverlay()
        }

        @objc func pageChanged(_ notification: Notification) {
            guard let pdfView, let doc = pdfView.document,
                  let page = pdfView.currentPage else { return }
            viewModel.currentPageNumber = viewModel.workspacePageNumber(for: page, in: doc)
            refreshSignatureOverlay()
            refreshCommentOverlays()
        }

        @objc func pdfViewGeometryChanged(_ notification: Notification) {
            refreshSignatureOverlay()
            refreshCommentOverlays()
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

        func setupSignatureOverlay() {
            signatureOverlay.onBoundsChanged = { [weak self] target, proposedBounds, oldBounds in
                guard let self else { return proposedBounds }
                let applied: CGRect
                if let annotation = target.annotation,
                   self.viewModel.signaturePlacementID(for: annotation) != nil {
                    applied = self.viewModel.updateSignaturePlacement(
                        for: annotation,
                        to: proposedBounds,
                        registerUndoFrom: oldBounds
                    )
                } else if let stampID = target.stampDecorationID,
                          let page = target.page {
                    applied = self.viewModel.updateStampDecoration(
                        id: stampID,
                        on: page,
                        to: proposedBounds,
                        registerUndoFrom: oldBounds
                    )
                } else {
                    applied = proposedBounds
                }
                self.pdfView?.setNeedsDisplay(self.pdfView?.bounds ?? .zero)
                self.refreshDecorationOverlays()
                return applied
            }
            signatureOverlay.onDelete = { [weak self] target in
                guard let self else { return }
                if let annotation = target.annotation {
                    self.viewModel.selectedAnnotation = annotation
                    self.viewModel.selectedStampDecorationID = nil
                    self.viewModel.deleteSelectedAnnotation()
                } else if let stampID = target.stampDecorationID {
                    self.viewModel.selectedAnnotation = nil
                    self.viewModel.selectedStampDecorationID = stampID
                    self.viewModel.deleteSelectedStampDecoration()
                }
                self.refreshSignatureOverlay()
                self.refreshDecorationOverlays()
                self.pdfView?.setNeedsDisplay(self.pdfView?.bounds ?? .zero)
            }
        }

        func setupCommentRegionOverlay() {
            commentRegionOverlay.onRegionCommitted = { [weak self] page, rect in
                guard let self, let pdfView else { return }
                if self.viewModel.createAnchoredRegionComment(rect: rect, on: page, in: pdfView.document) != nil {
                    self.refreshCommentOverlays()
                }
            }
        }

        func refreshSignatureOverlay() {
            guard let pdfView else { return }
            signatureOverlay.pdfView = pdfView
            if let annotation = viewModel.selectedAnnotation,
               viewModel.signaturePlacementID(for: annotation) != nil {
                signatureOverlay.select(annotation)
            } else if let stampID = viewModel.selectedStampDecorationID,
                      let decoration = viewModel.stampDecoration(id: stampID),
                      let page = page(for: decoration, in: pdfView),
                      let rect = decoration.rect {
                signatureOverlay.selectStamp(id: stampID, page: page, bounds: rect)
            } else {
                signatureOverlay.clearSelection()
            }
        }

        private func page(for decoration: PageDecoration, in pdfView: PDFView) -> PDFPage? {
            guard let pageRefID = decoration.pageRefID,
                  let ref = viewModel.document.workspace.pageOrder.first(where: { $0.id == pageRefID }),
                  let pageIndex = viewModel.combinedPageIndex(for: ref) else {
                return nil
            }
            return pdfView.document?.page(at: pageIndex)
        }

        func refreshDecorationOverlays() {
            for overlay in decorationOverlays.allObjects {
                overlay.viewModel = viewModel
                overlay.needsDisplay = true
            }
        }

        func pdfView(_ view: PDFView, overlayViewFor page: PDFPage) -> NSView? {
            let overlay = PageDecorationOverlayView(page: page)
            overlay.viewModel = viewModel
            overlay.pdfView = view
            decorationOverlays.add(overlay)
            return overlay
        }

        func refreshCommentOverlays() {
            guard let pdfView else { return }
            commentMarkerOverlay.pdfView = pdfView
            commentMarkerOverlay.viewModel = viewModel
            commentMarkerOverlay.reload()

            commentRegionOverlay.pdfView = pdfView
            commentRegionOverlay.isHidden = viewModel.currentTool != .commentRegion
        }

        func updateCanvasBannerInset(_ desiredTopInset: CGFloat) {
            guard let pdfView,
                  let scrollView = pdfView.documentView?.enclosingScrollView ?? pdfView.subviews.compactMap({ $0 as? NSScrollView }).first else {
                return
            }
            guard abs(scrollView.contentInsets.top - desiredTopInset) > 0.5 else { return }
            var insets = scrollView.contentInsets
            insets.top = desiredTopInset
            scrollView.contentInsets = insets
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
    var onTabKey: ((Bool) -> Bool)?
    var onSelectionCommitted: (() -> Void)?
    var onCommentMenu: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        // Delete (51) or Forward Delete (117)
        if event.keyCode == 51 || event.keyCode == 117, let block = onDeleteKey {
            block()
        } else if event.keyCode == 48,
                  onTabKey?(event.modifierFlags.contains(.shift)) == true {
            return
        } else {
            super.keyDown(with: event)
        }
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        onSelectionCommitted?()
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        guard let selection = currentSelection,
              !(selection.string?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) else {
            return menu
        }
        if menu.items.contains(where: { $0.action == #selector(commentFromContextMenu(_:)) }) {
            return menu
        }
        if !menu.items.isEmpty {
            menu.addItem(.separator())
        }
        let item = NSMenuItem(title: "Comment", action: #selector(commentFromContextMenu(_:)), keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return menu
    }

    @objc private func commentFromContextMenu(_ sender: Any?) {
        onCommentMenu?()
    }
}

final class CommentMarkerOverlayView: NSView {
    weak var pdfView: PDFView?
    var viewModel: WorkspaceViewModel?

    private let markerSize: CGFloat = 20

    override var isFlipped: Bool { false }

    func reload() {
        subviews.forEach { $0.removeFromSuperview() }
        guard let pdfView,
              let viewModel,
              let document = pdfView.document else { return }

        for comment in viewModel.filteredWorkspaceComments {
            guard let anchor = comment.anchor,
                  let pageRef = viewModel.document.workspace.pageOrder.first(where: { $0.id == anchor.pageRefID }),
                  let pageIndex = viewModel.combinedPageIndex(for: pageRef),
                  let page = document.page(at: pageIndex) else {
                continue
            }
            let rect = pdfView.convert(anchor.rect, from: page)
            let marker = CommentMarkerButton(commentID: comment.id)
            marker.actionHandler = { [weak viewModel] id in
                guard let comment = viewModel?.document.workspace.comments.first(where: { $0.id == id }) else { return }
                viewModel?.selectedCommentID = comment.id
            }
            marker.frame = CGRect(
                x: rect.maxX - markerSize * 0.45,
                y: rect.maxY - markerSize * 0.55,
                width: markerSize,
                height: markerSize
            )
            addSubview(marker)
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        for subview in subviews.reversed() {
            let local = convert(point, to: subview)
            if let hit = subview.hitTest(local) {
                return hit
            }
        }
        return nil
    }
}

private final class CommentMarkerButton: NSButton {
    let commentID: UUID
    var actionHandler: ((UUID) -> Void)?

    init(commentID: UUID) {
        self.commentID = commentID
        super.init(frame: .zero)
        image = NSImage(systemSymbolName: "text.bubble.fill", accessibilityDescription: "Comment")
        imagePosition = .imageOnly
        isBordered = false
        contentTintColor = .dsAccentNS
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.88).cgColor
        layer?.cornerRadius = 10
        target = self
        action = #selector(selectComment)
    }

    required init?(coder: NSCoder) {
        nil
    }

    @objc private func selectComment() {
        actionHandler?(commentID)
    }
}

final class CommentRegionOverlayView: NSView {
    weak var pdfView: PDFView?
    var onRegionCommitted: ((PDFPage, CGRect) -> Void)?

    private var startPoint: CGPoint?
    private var dragRect: CGRect?

    override var isFlipped: Bool { false }

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        dragRect = nil
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let startPoint else { return }
        let current = convert(event.locationInWindow, from: nil)
        dragRect = CGRect(
            x: min(startPoint.x, current.x),
            y: min(startPoint.y, current.y),
            width: abs(current.x - startPoint.x),
            height: abs(current.y - startPoint.y)
        )
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            startPoint = nil
            dragRect = nil
            needsDisplay = true
        }
        guard let pdfView,
              let startPoint,
              let page = pdfView.page(for: startPoint, nearest: true) else {
            return
        }
        let endPoint = convert(event.locationInWindow, from: nil)
        let pageStart = pdfView.convert(startPoint, to: page)
        let pageEnd = pdfView.convert(endPoint, to: page)
        let rect = CGRect(
            x: min(pageStart.x, pageEnd.x),
            y: min(pageStart.y, pageEnd.y),
            width: abs(pageEnd.x - pageStart.x),
            height: abs(pageEnd.y - pageStart.y)
        )
        guard rect.width >= 8, rect.height >= 8 else { return }
        onRegionCommitted?(page, rect)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let dragRect else { return }
        NSColor.dsAccentNS.withAlphaComponent(0.12).setFill()
        dragRect.fill()
        NSColor.dsAccentNS.setStroke()
        let path = NSBezierPath(rect: dragRect)
        path.lineWidth = 1.5
        path.setLineDash([5, 3], count: 2, phase: 0)
        path.stroke()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        isHidden ? nil : self
    }
}

final class PageDecorationOverlayView: NSView {
    weak var viewModel: WorkspaceViewModel?
    weak var pdfView: PDFView?
    private weak var page: PDFPage?

    init(page: PDFPage) {
        self.page = page
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var isOpaque: Bool { false }
    override var isFlipped: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let page,
              let viewModel,
              let document = page.document,
              let pageRef = viewModel.pageRef(for: page, in: document),
              let pageIndex = viewModel.document.workspace.pageOrder.firstIndex(where: { $0.id == pageRef.id }) else {
            return
        }
        drawFormHighlights(on: page, pageRef: pageRef, viewModel: viewModel)
        let decorations = viewModel.document.workspace.decorations.filter(\.isEnabled)
        guard !decorations.isEmpty else { return }
        let pageCount = viewModel.document.workspace.pageOrder.count
        for decoration in decorations {
            switch decoration.kind {
            case .watermark:
                drawWatermark(decoration, pageIndex: pageIndex, pageCount: pageCount)
            case .pageNumber:
                drawFooterText(
                    PDFDecorationExportBaker.text(for: decoration, pageIndex: pageIndex, pageCount: pageCount),
                    decoration: decoration,
                    alignment: .center
                )
            case .bates:
                drawFooterText(
                    PDFDecorationExportBaker.text(for: decoration, pageIndex: pageIndex, pageCount: pageCount),
                    decoration: decoration,
                    alignment: .left
                )
            case .stamp:
                guard decoration.pageRefID == pageRef.id else { continue }
                drawStamp(decoration, pageIndex: pageIndex, pageCount: pageCount)
            }
        }
    }

    private func drawFormHighlights(on page: PDFPage, pageRef: PageRef, viewModel: WorkspaceViewModel) {
        guard viewModel.highlightFormFields else { return }
        let selectedID = viewModel.selectedFormFieldIndex.flatMap { index in
            viewModel.formSummary.fields.indices.contains(index) ? viewModel.formSummary.fields[index].id : nil
        }
        for (annotationIndex, annotation) in page.annotations.enumerated() where annotation.isPDFWidget {
            guard let rect = pageRectToOverlayRect(annotation.bounds)?.standardized,
                  rect.width > 2,
                  rect.height > 2 else { continue }
            let id = "\(pageRef.id.uuidString)-\(annotation.fieldName ?? "\(annotationIndex)")"
            let isSelected = id == selectedID
            NSColor.dsAccentSoftNS.withAlphaComponent(isSelected ? 0.40 : 0.24).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).fill()
            if isSelected {
                NSColor.dsAccentNS.setStroke()
                let path = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4)
                path.lineWidth = 1.5
                path.stroke()
            }
        }
    }

    private func drawWatermark(_ decoration: PageDecoration, pageIndex: Int, pageCount: Int) {
        let text = PDFDecorationExportBaker.text(for: decoration, pageIndex: pageIndex, pageCount: pageCount)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let font = NSFont.boldSystemFont(ofSize: min(decoration.fontSize, max(24, bounds.width * 0.13)))
        let attributes = textAttributes(for: decoration, font: font)
        let size = NSString(string: text).size(withAttributes: attributes)
        NSGraphicsContext.current?.cgContext.saveGState()
        let transform = NSAffineTransform()
        transform.translateX(by: bounds.midX, yBy: bounds.midY)
        transform.rotate(byRadians: -.pi / 5)
        transform.concat()
        NSString(string: text).draw(
            in: CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width + 2, height: size.height + 2),
            withAttributes: attributes
        )
        NSGraphicsContext.current?.cgContext.restoreGState()
    }

    private func drawFooterText(_ text: String, decoration: PageDecoration, alignment: NSTextAlignment) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let font = alignment == .left
            ? NSFont.monospacedDigitSystemFont(ofSize: decoration.fontSize, weight: .regular)
            : NSFont.systemFont(ofSize: decoration.fontSize)
        let attributes = textAttributes(for: decoration, font: font)
        let size = NSString(string: text).size(withAttributes: attributes)
        let x = alignment == .left ? bounds.minX + 28 : bounds.midX - size.width / 2
        NSString(string: text).draw(
            in: CGRect(x: x, y: bounds.minY + 18, width: size.width + 2, height: size.height + 2),
            withAttributes: attributes
        )
    }

    private func drawStamp(_ decoration: PageDecoration, pageIndex: Int, pageCount: Int) {
        guard let pageRect = decoration.rect,
              let rect = pageRectToOverlayRect(pageRect)?.standardized,
              rect.width > 4,
              rect.height > 4 else { return }
        let text = PDFDecorationExportBaker.text(for: decoration, pageIndex: pageIndex, pageCount: pageCount)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let color = decoration.swatch.overlayColor.withAlphaComponent(CGFloat(decoration.opacity))
        color.setStroke()
        let path = NSBezierPath(rect: rect)
        path.lineWidth = 2
        path.stroke()

        let font = NSFont.boldSystemFont(ofSize: min(decoration.fontSize, max(10, rect.height * 0.34)))
        let attributes = textAttributes(for: decoration, font: font)
        let size = NSString(string: text).size(withAttributes: attributes)
        NSString(string: text).draw(
            in: CGRect(
                x: rect.midX - size.width / 2,
                y: rect.midY - size.height / 2,
                width: size.width + 2,
                height: size.height + 2
            ),
            withAttributes: attributes
        )
    }

    private func pageRectToOverlayRect(_ rect: CGRect) -> CGRect? {
        guard let page, let pdfView else { return nil }
        let pdfViewRect = pdfView.convert(rect, from: page)
        return convert(pdfViewRect, from: pdfView).standardized
    }

    private func textAttributes(for decoration: PageDecoration, font: NSFont) -> [NSAttributedString.Key: Any] {
        [
            .font: font,
            .foregroundColor: decoration.swatch.overlayColor.withAlphaComponent(CGFloat(decoration.opacity))
        ]
    }
}

private extension PageDecorationSwatch {
    var overlayColor: NSColor {
        switch self {
        case .accent: return .dsAccentNS
        case .sage: return .dsAnnotationSageNS
        case .coral: return .dsAnnotationCoralNS
        case .tertiary: return .dsTextTertiaryNS
        case .lavender: return .dsAnnotationLavNS
        }
    }
}

final class PageObjectSelectionTarget {
    weak var annotation: PDFAnnotation?
    weak var stampPage: PDFPage?
    var stampDecorationID: UUID?
    private var storedBounds: CGRect

    var page: PDFPage? {
        annotation?.page ?? stampPage
    }

    var bounds: CGRect {
        get { annotation?.bounds ?? storedBounds }
        set {
            storedBounds = newValue
            annotation?.bounds = newValue
        }
    }

    init(annotation: PDFAnnotation) {
        self.annotation = annotation
        self.storedBounds = annotation.bounds
    }

    init(stampDecorationID: UUID, page: PDFPage, bounds: CGRect) {
        self.stampDecorationID = stampDecorationID
        self.stampPage = page
        self.storedBounds = bounds
    }
}

final class SignatureSelectionOverlayView: NSView {
    weak var pdfView: PDFView?
    var onBoundsChanged: ((PageObjectSelectionTarget, CGRect, CGRect?) -> CGRect)?
    var onDelete: ((PageObjectSelectionTarget) -> Void)?

    private var selectionTarget: PageObjectSelectionTarget?
    private var dragMode: DragMode?
    private var initialMousePoint: CGPoint = .zero
    private var initialFrame: CGRect = .zero
    private var initialPageBounds: CGRect?
    private let handleSize: CGFloat = 9
    private let deleteButtonSize: CGFloat = 18
    private let minimumViewSize = CGSize(width: 28, height: 18)

    override var isOpaque: Bool { false }

    func select(_ annotation: PDFAnnotation) {
        selectionTarget = PageObjectSelectionTarget(annotation: annotation)
        isHidden = false
        needsDisplay = true
    }

    func selectStamp(id: UUID, page: PDFPage, bounds: CGRect) {
        selectionTarget = PageObjectSelectionTarget(stampDecorationID: id, page: page, bounds: bounds)
        isHidden = false
        needsDisplay = true
    }

    func clearSelection() {
        selectionTarget = nil
        dragMode = nil
        initialPageBounds = nil
        isHidden = true
        needsDisplay = true
    }

    func containsInteractivePoint(_ pdfViewPoint: CGPoint) -> Bool {
        guard !isHidden else { return false }
        let point = convert(pdfViewPoint, from: pdfView)
        return interactionFrame()?.contains(point) == true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden,
              alphaValue > 0,
              interactionFrame()?.contains(point) == true else { return nil }
        return self
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let frame = selectionFrame() else { return }

        NSColor.dsAccentNS.setStroke()
        let outline = NSBezierPath(rect: frame)
        outline.lineWidth = 1.5
        outline.stroke()

        NSColor.white.setFill()
        NSColor.dsAccentNS.setStroke()
        for rect in handleRects(for: frame).values {
            let handle = NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2)
            handle.lineWidth = 1
            handle.fill()
            handle.stroke()
        }

        let deleteFrame = deleteButtonRect(for: frame)
        NSColor.systemRed.setFill()
        NSColor.white.setStroke()
        let deleteCircle = NSBezierPath(ovalIn: deleteFrame)
        deleteCircle.fill()
        deleteCircle.lineWidth = 1
        deleteCircle.stroke()

        let inset = deleteFrame.insetBy(dx: 5.5, dy: 5.5)
        let xPath = NSBezierPath()
        xPath.lineWidth = 1.7
        xPath.lineCapStyle = .round
        xPath.move(to: CGPoint(x: inset.minX, y: inset.minY))
        xPath.line(to: CGPoint(x: inset.maxX, y: inset.maxY))
        xPath.move(to: CGPoint(x: inset.maxX, y: inset.minY))
        xPath.line(to: CGPoint(x: inset.minX, y: inset.maxY))
        xPath.stroke()
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        guard let frame = selectionFrame() else { return }
        addCursorRect(frame, cursor: .openHand)
        addCursorRect(deleteButtonRect(for: frame).insetBy(dx: -3, dy: -3), cursor: .pointingHand)
        for (handle, rect) in handleRects(for: frame) {
            addCursorRect(rect.insetBy(dx: -4, dy: -4), cursor: handle.cursor)
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard let frame = selectionFrame(),
              let selectionTarget else { return }
        let point = convert(event.locationInWindow, from: nil)
        if deleteButtonRect(for: frame).insetBy(dx: -3, dy: -3).contains(point) {
            onDelete?(selectionTarget)
            return
        }
        initialMousePoint = point
        initialFrame = frame
        initialPageBounds = selectionTarget.bounds
        if let handle = handle(at: point, in: frame) {
            dragMode = .resize(handle)
            handle.cursor.set()
        } else {
            dragMode = .move
            NSCursor.closedHand.set()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragMode,
              let selectionTarget,
              let pdfView,
              let page = selectionTarget.page else { return }
        let point = convert(event.locationInWindow, from: nil)
        let delta = CGPoint(x: point.x - initialMousePoint.x, y: point.y - initialMousePoint.y)
        let proposedFrame: CGRect
        switch dragMode {
        case .move:
            proposedFrame = initialFrame.offsetBy(dx: delta.x, dy: delta.y)
        case .resize(let handle):
            proposedFrame = resizedFrame(initialFrame, handle: handle, delta: delta)
        }
        let proposedPageBounds = pdfView.convert(proposedFrame.standardized, to: page).standardized
        let applied = onBoundsChanged?(selectionTarget, proposedPageBounds, nil) ?? proposedPageBounds
        selectionTarget.bounds = applied
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let selectionTarget,
              let oldBounds = initialPageBounds else {
            dragMode = nil
            initialPageBounds = nil
            NSCursor.arrow.set()
            return
        }
        let currentPageBounds = selectionTarget.bounds.standardized
        let applied = onBoundsChanged?(selectionTarget, currentPageBounds, oldBounds) ?? currentPageBounds
        selectionTarget.bounds = applied
        dragMode = nil
        initialPageBounds = nil
        NSCursor.arrow.set()
        needsDisplay = true
    }

    private func selectionFrame() -> CGRect? {
        guard let selectionTarget,
              let page = selectionTarget.page,
              let pdfView else { return nil }
        return pdfView.convert(selectionTarget.bounds, from: page).standardized
    }

    private func interactionFrame() -> CGRect? {
        selectionFrame()?.insetBy(dx: -18, dy: -18)
    }

    private func deleteButtonRect(for frame: CGRect) -> CGRect {
        CGRect(
            x: frame.maxX - deleteButtonSize / 2,
            y: frame.maxY - deleteButtonSize / 2,
            width: deleteButtonSize,
            height: deleteButtonSize
        )
    }

    private func handle(at point: CGPoint, in frame: CGRect) -> ResizeHandle? {
        handleRects(for: frame).first { _, rect in
            rect.insetBy(dx: -5, dy: -5).contains(point)
        }?.key
    }

    private func handleRects(for frame: CGRect) -> [ResizeHandle: CGRect] {
        let half = handleSize / 2
        func rect(center: CGPoint) -> CGRect {
            CGRect(x: center.x - half, y: center.y - half, width: handleSize, height: handleSize)
        }
        return [
            .topLeft: rect(center: CGPoint(x: frame.minX, y: frame.maxY)),
            .top: rect(center: CGPoint(x: frame.midX, y: frame.maxY)),
            .topRight: rect(center: CGPoint(x: frame.maxX, y: frame.maxY)),
            .right: rect(center: CGPoint(x: frame.maxX, y: frame.midY)),
            .bottomRight: rect(center: CGPoint(x: frame.maxX, y: frame.minY)),
            .bottom: rect(center: CGPoint(x: frame.midX, y: frame.minY)),
            .bottomLeft: rect(center: CGPoint(x: frame.minX, y: frame.minY)),
            .left: rect(center: CGPoint(x: frame.minX, y: frame.midY))
        ]
    }

    private func resizedFrame(_ frame: CGRect, handle: ResizeHandle, delta: CGPoint) -> CGRect {
        var minX = frame.minX
        var maxX = frame.maxX
        var minY = frame.minY
        var maxY = frame.maxY

        if handle.movesLeft { minX += delta.x }
        if handle.movesRight { maxX += delta.x }
        if handle.movesBottom { minY += delta.y }
        if handle.movesTop { maxY += delta.y }

        if maxX - minX < minimumViewSize.width {
            if handle.movesLeft {
                minX = maxX - minimumViewSize.width
            } else {
                maxX = minX + minimumViewSize.width
            }
        }
        if maxY - minY < minimumViewSize.height {
            if handle.movesBottom {
                minY = maxY - minimumViewSize.height
            } else {
                maxY = minY + minimumViewSize.height
            }
        }

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private enum DragMode {
        case move
        case resize(ResizeHandle)
    }

    private enum ResizeHandle: CaseIterable {
        case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left

        var movesLeft: Bool { self == .topLeft || self == .bottomLeft || self == .left }
        var movesRight: Bool { self == .topRight || self == .bottomRight || self == .right }
        var movesTop: Bool { self == .topLeft || self == .top || self == .topRight }
        var movesBottom: Bool { self == .bottomLeft || self == .bottom || self == .bottomRight }

        var cursor: NSCursor {
            switch self {
            case .left, .right:
                return .resizeLeftRight
            case .top, .bottom:
                return .resizeUpDown
            case .topLeft, .bottomRight, .topRight, .bottomLeft:
                return .crosshair
            }
        }
    }
}

// MARK: - Note editor popover (NSPopover backed)

final class NoteEditorViewController: NSViewController {
    private let annotation: PDFAnnotation
    private let statusHandler: (String, Bool) -> Void
    private let changeHandler: (PDFAnnotation, PDFAnnotationEditSnapshot, String) -> Void
    var closeHandler: (() -> Void)?
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
        changeHandler: @escaping (PDFAnnotation, PDFAnnotationEditSnapshot, String) -> Void = { _, _, _ in }
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
            finishForDismissal()
        }
    }

    @objc private func commit() {
        guard commitChanges() else { return }
        didCommit = true
        closeEditor()
    }

    @objc private func cancel() {
        cancelChanges()
        closeEditor()
    }

    private func closeEditor() {
        if let closeHandler {
            closeHandler()
        } else {
            dismiss(nil)
        }
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
            changeHandler(annotation, originalSnapshot, editorTitle)
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
            changeHandler(annotation, originalSnapshot, editorTitle)
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
        changeHandler(annotation, originalSnapshot, editorTitle)
        return true
    }

    private func cancelChanges() {
        didCancel = true
        if isDraftAnnotation, (originalSnapshot.contents ?? "").isEmpty {
            annotation.page?.removeAnnotation(annotation)
            changeHandler(annotation, originalSnapshot, editorTitle)
        } else {
            originalSnapshot.restore(to: annotation)
        }
    }

    private func finishForDismissal() {
        if commitChanges() {
            didCommit = true
        } else {
            cancelChanges()
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

    final class InlineTextEditorOverlay: NSView, NSTextViewDelegate, NSTextFieldDelegate {
    struct EditResult {
        var pageRef: PageRef
        var block: EditableTextBlock
        var text: String
        var editedBounds: CGRect
        var fontName: String
        var fontSize: CGFloat
        var textColor: NSColor
        var alignment: NSTextAlignment
        var didManuallyReposition: Bool
        var didManuallyResizeWidth: Bool
        var didManuallyResizeHeight: Bool
    }

    enum Completion {
        case commit(EditResult)
        case revertToOriginal
        case cancel
    }

    private weak var pdfView: PDFView?
    private weak var page: PDFPage?
    private weak var viewModel: WorkspaceViewModel?
    private let pageRef: PageRef
    private let block: EditableTextBlock
    private let sourceFormat: PDFTextEditFormat
    private let isExistingEdit: Bool
    private let completion: (Completion) -> Void
    private let patchView = NSView()
    private let toolbar = NSView()
    private let textView = InlineEditableTextView()
    private let moveHandle = InlineMoveHandle()
    private let resizeHandle = InlineResizeHandle()
    private let familyPopup = NSPopUpButton()
    private let sizeStepper = NSStepper()
    private let sizeField = NSTextField(string: "")
    private let boldButton = NSButton(title: "B", target: nil, action: nil)
    private let italicButton = NSButton(title: "I", target: nil, action: nil)
    private let alignControl = NSSegmentedControl(labels: ["L", "C", "R"], trackingMode: .selectOne, target: nil, action: nil)
    private let colorPopup = NSPopUpButton()
    private let matchFormatButton = NSButton(title: "Match", target: nil, action: nil)
    private let copyFormatButton = NSButton(title: "", target: nil, action: nil)
    private let applyFormatButton = NSButton(title: "", target: nil, action: nil)
    private var editorFontFamily: String
    private var documentFontSize: CGFloat
    private var editorFontTraits: NSFontTraitMask
    private var editorTextColor: NSColor
    private let textColorChoices: [TextColorChoice]
    private var editorAlignment: NSTextAlignment = .left
    private var didFinish = false
    private var editorTopY: CGFloat = 0
    private var manualEditorPageOrigin: CGPoint?
    private var didManuallyResizeWidth = false
    private var didManuallyResizeHeight = false
    private var didManuallyReposition = false
    private var manualEditorPageWidth: CGFloat?
    private var manualEditorPageHeight: CGFloat?
    private var didChangeStyle = false
    private let originalText: String
    private let originalFontFamily: String
    private let originalFontSize: CGFloat
    private let originalFontTraits: NSFontTraitMask
    private let originalAlignment: NSTextAlignment
    private static let defaultInsertedTextColor = NSColor.black
    private static let defaultTextColorChoices: [TextColorChoice] = [
        TextColorChoice(name: "Black", color: .black, isDetected: false),
        TextColorChoice(name: "White", color: .white, isDetected: false),
        TextColorChoice(name: "Red", color: .systemRed, isDetected: false),
        TextColorChoice(name: "Blue", color: .systemBlue, isDetected: false),
        TextColorChoice(name: "Green", color: .systemGreen, isDetected: false)
    ]
    private static let maxDetectedTextColors = 24

    private struct TextColorChoice {
        var name: String
        var color: NSColor
        var isDetected: Bool
    }

    init(
        frame: CGRect,
        viewModel: WorkspaceViewModel,
        pdfView: PDFView,
        page: PDFPage,
        pageRef: PageRef,
        block: EditableTextBlock,
        sourceFormat: PDFTextEditFormat,
        isExistingEdit: Bool = false,
        completion: @escaping (Completion) -> Void
    ) {
        self.viewModel = viewModel
        self.pdfView = pdfView
        self.page = page
        self.pageRef = pageRef
        self.block = block
        self.sourceFormat = sourceFormat
        self.isExistingEdit = isExistingEdit
        self.completion = completion
        // Preserve the ORIGINAL detected point size so edited text renders at the same size
        // as the surrounding document. A hard `max(8, …)` floor here inflated smaller body
        // text (6–8pt is common in dense resumes/footnotes), which both changed the visible
        // size and — because the box grows downward to fit the taller glyphs — pushed the
        // replacement onto the line below. Only guard against a non-positive/garbage detection.
        documentFontSize = block.fontSize > 0 ? block.fontSize : 12
        let initialFont = NSFont(name: block.fontName, size: documentFontSize) ?? .systemFont(ofSize: documentFontSize)
        editorFontFamily = Self.editingFamilyName(for: initialFont, fallback: block.fontName)
        editorFontTraits = NSFontManager.shared.traits(of: initialFont).intersection([.boldFontMask, .italicFontMask])
        editorTextColor = Self.initialTextColor(for: block)
        textColorChoices = Self.textColorChoices(for: block, document: pdfView.document, initialColor: editorTextColor)
        editorAlignment = block.alignment?.nsTextAlignment ?? .left
        originalText = block.text
        originalFontFamily = editorFontFamily
        originalFontSize = documentFontSize
        originalFontTraits = editorFontTraits
        originalAlignment = editorAlignment
        super.init(frame: frame)
        setup()
        applyArmedFormatPainterIfNeeded()
        layoutEditor()
    }

    required init?(coder: NSCoder) { nil }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

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

    func containsInteractivePoint(_ pdfViewPoint: CGPoint) -> Bool {
        let point = convert(pdfViewPoint, from: pdfView)
        return textView.frame.insetBy(dx: -6, dy: -6).contains(point) ||
            toolbar.frame.insetBy(dx: -4, dy: -4).contains(point) ||
            moveHandle.frame.insetBy(dx: -6, dy: -6).contains(point) ||
            resizeHandle.frame.insetBy(dx: -8, dy: -8).contains(point)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, alphaValue > 0, bounds.contains(point) else { return nil }
        return hitTestInteractiveSubview(resizeHandle, point: point, padding: 8) ??
            hitTestInteractiveSubview(moveHandle, point: point, padding: 1) ??
            hitTestInteractiveSubview(toolbar, point: point, padding: 4) ??
            hitTestTextView(point)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    private func hitTestInteractiveSubview(_ view: NSView, point: NSPoint, padding: CGFloat) -> NSView? {
        guard !view.isHidden, view.alphaValue > 0 else { return nil }
        let converted = view.convert(point, from: self)
        guard view.bounds.insetBy(dx: -padding, dy: -padding).contains(converted) else { return nil }
        return view.hitTest(point) ?? view
    }

    private func hitTestTextView(_ point: NSPoint) -> NSView? {
        guard !textView.isHidden, textView.alphaValue > 0 else { return nil }
        let converted = textView.convert(point, from: self)
        guard textView.bounds.insetBy(dx: -6, dy: -6).contains(converted) else { return nil }
        return textView
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

        textView.onMoveDrag = { [weak self] delta in
            self?.moveEditor(by: delta)
        }
        textView.onEscape = { [weak self] in
            self?.cancel()
        }
        textView.onUndoShortcut = { [weak self] in
            self?.performEditorUndo()
        }
        moveHandle.onDrag = { [weak self] delta in
            self?.moveEditor(by: delta)
        }
        addSubview(moveHandle)

        resizeHandle.onDrag = { [weak self] delta in
            self?.resizeEditor(by: delta)
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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(pdfViewScaleChanged(_:)),
            name: .PDFViewScaleChanged,
            object: pdfView
        )
        applyFormatting()
    }

    private func setupToolbar() {
        let families = Self.fontFamilyMenuItems(originalFamily: editorFontFamily)
        familyPopup.addItems(withTitles: families)
        if let match = families.first(where: { editorFontFamily.localizedCaseInsensitiveCompare($0) == .orderedSame }) {
            familyPopup.selectItem(withTitle: match)
            editorFontFamily = match
        } else {
            familyPopup.insertItem(withTitle: editorFontFamily, at: 0)
            familyPopup.selectItem(at: 0)
        }
        familyPopup.target = self
        familyPopup.action = #selector(changeFamily(_:))
        familyPopup.frame = CGRect(x: 8, y: 8, width: 142, height: 26)
        toolbar.addSubview(familyPopup)

        sizeField.alignment = .center
        sizeField.font = .systemFont(ofSize: 12, weight: .medium)
        sizeField.controlSize = .small
        sizeField.bezelStyle = .roundedBezel
        sizeField.isEditable = true
        sizeField.isSelectable = true
        sizeField.target = self
        sizeField.action = #selector(commitSizeField(_:))
        sizeField.delegate = self
        sizeField.toolTip = "Font size"
        sizeField.frame = CGRect(x: 154, y: 8, width: 42, height: 26)
        toolbar.addSubview(sizeField)

        sizeStepper.minValue = 4
        sizeStepper.maxValue = 96
        sizeStepper.integerValue = Int(round(documentFontSize))
        sizeStepper.target = self
        sizeStepper.action = #selector(changeSize(_:))
        sizeStepper.toolTip = "Font size"
        sizeStepper.frame = CGRect(x: 200, y: 8, width: 20, height: 26)
        toolbar.addSubview(sizeStepper)

        boldButton.target = self
        boldButton.action = #selector(toggleBold)
        boldButton.setButtonType(.toggle)
        boldButton.bezelStyle = .rounded
        boldButton.font = .boldSystemFont(ofSize: 12)
        boldButton.state = editorFontTraits.contains(.boldFontMask) ? .on : .off
        boldButton.frame = CGRect(x: 234, y: 8, width: 32, height: 26)
        toolbar.addSubview(boldButton)

        italicButton.target = self
        italicButton.action = #selector(toggleItalic)
        italicButton.setButtonType(.toggle)
        italicButton.bezelStyle = .rounded
        italicButton.font = NSFontManager.shared.convert(NSFont.systemFont(ofSize: 12), toHaveTrait: .italicFontMask)
        italicButton.state = editorFontTraits.contains(.italicFontMask) ? .on : .off
        italicButton.frame = CGRect(x: 270, y: 8, width: 32, height: 26)
        toolbar.addSubview(italicButton)

        alignControl.target = self
        alignControl.action = #selector(changeAlignment(_:))
        alignControl.selectedSegment = selectedAlignmentSegment()
        alignControl.frame = CGRect(x: 314, y: 8, width: 82, height: 26)
        toolbar.addSubview(alignControl)

        colorPopup.target = self
        colorPopup.action = #selector(changeTextColor(_:))
        colorPopup.toolTip = "Text color"
        colorPopup.frame = CGRect(x: 410, y: 8, width: 102, height: 26)
        populateColorPopup()
        toolbar.addSubview(colorPopup)

        let signature = NSButton(title: "", target: self, action: #selector(addSignatureBox))
        signature.image = NSImage(systemSymbolName: "signature", accessibilityDescription: "Signature")
        signature.imagePosition = .imageOnly
        signature.bezelStyle = .rounded
        signature.toolTip = "Add signature box"
        signature.frame = CGRect(x: 522, y: 8, width: 34, height: 26)
        toolbar.addSubview(signature)

        matchFormatButton.target = self
        matchFormatButton.action = #selector(matchNearbyFormat)
        matchFormatButton.bezelStyle = .rounded
        matchFormatButton.toolTip = "Match nearby text format"
        matchFormatButton.frame = CGRect(x: 566, y: 8, width: 62, height: 26)
        toolbar.addSubview(matchFormatButton)

        copyFormatButton.target = self
        copyFormatButton.action = #selector(copyCurrentFormat)
        copyFormatButton.image = NSImage(systemSymbolName: "paintbrush", accessibilityDescription: "Copy format")
        copyFormatButton.imagePosition = .imageOnly
        copyFormatButton.bezelStyle = .rounded
        copyFormatButton.toolTip = "Copy format"
        copyFormatButton.frame = CGRect(x: 634, y: 8, width: 34, height: 26)
        toolbar.addSubview(copyFormatButton)

        applyFormatButton.target = self
        applyFormatButton.action = #selector(applyCopiedFormat)
        applyFormatButton.image = NSImage(systemSymbolName: "paintbrush.pointed", accessibilityDescription: "Apply copied format")
        applyFormatButton.imagePosition = .imageOnly
        applyFormatButton.bezelStyle = .rounded
        applyFormatButton.toolTip = "Apply copied format"
        applyFormatButton.frame = CGRect(x: 674, y: 8, width: 34, height: 26)
        toolbar.addSubview(applyFormatButton)

        var buttonX: CGFloat = 718
        if isExistingEdit {
            let revert = NSButton(title: "Revert", target: self, action: #selector(revertButton))
            revert.bezelStyle = .rounded
            revert.toolTip = "Remove this edit and restore the original text"
            revert.frame = CGRect(x: buttonX, y: 8, width: 66, height: 26)
            toolbar.addSubview(revert)
            buttonX += 72
        }

        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelButton))
        cancel.bezelStyle = .rounded
        cancel.frame = CGRect(x: buttonX, y: 8, width: 68, height: 26)
        toolbar.addSubview(cancel)
        buttonX += 74

        let done = NSButton(title: "Done", target: self, action: #selector(commitButton))
        done.bezelStyle = .rounded
        done.contentTintColor = .dsAccentNS
        done.keyEquivalent = "\r"
        done.frame = CGRect(x: buttonX, y: 8, width: 62, height: 26)
        toolbar.addSubview(done)
        refreshColorPopup()
        refreshSizeControls()
    }

    private var toolbarSize: CGSize {
        CGSize(width: isExistingEdit ? 934 : 862, height: 42)
    }

    private func layoutEditor() {
        guard let pdfView, let page else { return }
        let originalSourceRect = pdfView.convert(block.bounds, from: page)
        var editorPageBounds = block.bounds
        if let manualEditorPageOrigin {
            editorPageBounds.origin = manualEditorPageOrigin
        }
        if let manualEditorPageWidth {
            editorPageBounds.size.width = manualEditorPageWidth
        }
        if let manualEditorPageHeight {
            editorPageBounds.size.height = manualEditorPageHeight
        }
        let sourceRect = pdfView.convert(editorPageBounds, from: page)
        let minWidth: CGFloat = block.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 180 : 156
        let editorWidth: CGFloat
        if let manualEditorPageWidth {
            let manualPageRect = CGRect(
                x: block.bounds.minX,
                y: block.bounds.minY,
                width: manualEditorPageWidth,
                height: max(block.bounds.height, 1)
            )
            editorWidth = max(minWidth, pdfView.convert(manualPageRect, from: page).standardized.width)
        } else {
            editorWidth = min(max(minWidth, sourceRect.width), columnConstrainedWidth(fromX: sourceRect.minX))
        }
        let editorHeight = didManuallyResizeHeight
            ? max(1, sourceRect.height)
            : max(sourceRect.height + 6, displayFontSize * 1.5)
        let editorY = didManuallyReposition ? sourceRect.minY : sourceRect.maxY - editorHeight
        let editorRect = CGRect(
            x: sourceRect.minX,
            y: editorY,
            width: editorWidth,
            height: editorHeight
        )
        editorTopY = editorRect.maxY
        patchView.frame = originalSourceRect.insetBy(dx: -2, dy: -2)
        textView.frame = editorRect
        updateTextContainerWidth()
        toolbar.frame = toolbarFrame(near: editorRect)
        positionEditorChrome(for: editorRect)
        resizeTextViewHeight()
    }

    private func toolbarFrame(near editorRect: CGRect) -> CGRect {
        let size = toolbarSize
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
        let minimumHeight = max(24, ceil(displayFontSize * 1.55))
        if didManuallyResizeHeight {
            frame.size.height = max(minimumHeight, frame.height)
        } else {
            frame.size.height = max(minimumHeight, ceil(used.height + textView.textContainerInset.height * 2 + 4))
        }
        frame.origin.y = editorTopY - frame.height
        textView.frame = frame
        toolbar.frame = toolbarFrame(near: frame)
        positionEditorChrome(for: frame)
    }

    private func positionEditorChrome(for editorRect: CGRect) {
        moveHandle.frame = CGRect(
            x: editorRect.minX,
            y: editorRect.maxY + 1,
            width: editorRect.width,
            height: 6
        )
        resizeHandle.frame = CGRect(
            x: editorRect.maxX - 8,
            y: editorRect.minY - 8,
            width: 16,
            height: 16
        )
    }

    /// Grows the text box to fit what's currently typed, so a short original word (e.g.
    /// "Hi") replaced with a much longer phrase doesn't get word-wrapped/clipped inside a
    /// box still sized for the original text. No-ops once the user has manually dragged
    /// the resize handle, so an explicit width choice is always respected.
    private func autoFitWidthIfNeeded() {
        guard !didManuallyResizeWidth else { return }
        let font = textView.font ?? displayFont()
        let text = textView.string.isEmpty ? " " : textView.string
        let desired = fittingTextViewWidth(for: text, font: font, minimumWidth: visualMinimumEditorWidth)

        let maxWidth = columnConstrainedWidth(fromX: textView.frame.minX)
        let minWidth = visualMinimumEditorWidth
        let newWidth = min(max(minWidth, desired), maxWidth)

        guard abs(newWidth - textView.frame.width) > 0.5 else { return }
        var frame = textView.frame
        frame.size.width = newWidth
        textView.frame = frame
        updateTextContainerWidth()
    }

    private var visualMinimumEditorWidth: CGFloat {
        block.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 180 : 156
    }

    private var committedMinimumEditorWidth: CGFloat {
        block.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 120 : 24
    }

    private func fittingTextViewWidth(for text: String, font: NSFont, minimumWidth: CGFloat) -> CGFloat {
        let unwrapped = ((text.isEmpty ? " " : text) as NSString).boundingRect(
            with: CGSize(width: .greatestFiniteMagnitude, height: font.pointSize * 2),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        )
        return max(minimumWidth, ceil(unwrapped.width) + textView.textContainerInset.width * 2 + 6)
    }

    private func columnConstrainedWidth(fromX minX: CGFloat) -> CGFloat {
        guard let pdfView, let page else { return 620 }
        let pageViewBounds = pdfView.convert(page.bounds(for: .cropBox), from: page).standardized
        let columnMaxX: CGFloat
        if let columnBounds = block.columnBounds {
            columnMaxX = pdfView.convert(columnBounds, from: page).standardized.maxX
        } else {
            columnMaxX = pageViewBounds.maxX
        }
        return max(48, min(620, columnMaxX - minX - 12))
    }

    private func moveEditor(by delta: CGPoint) {
        guard delta.x.isFinite, delta.y.isFinite else { return }
        didManuallyReposition = true
        var frame = textView.frame
        frame.origin.x += delta.x
        frame.origin.y += delta.y
        textView.frame = frame
        editorTopY = frame.maxY
        toolbar.frame = toolbarFrame(near: frame)
        positionEditorChrome(for: frame)
        if let pdfView, let page {
            manualEditorPageOrigin = pdfView.convert(convert(frame, to: pdfView), to: page).standardized.origin
        }
    }

    private func resizeEditor(by delta: CGPoint) {
        didManuallyResizeWidth = true
        didManuallyResizeHeight = true
        var frame = textView.frame
        frame.size.width = max(48, frame.width + delta.x)
        frame.size.height = max(max(24, ceil(displayFontSize * 1.55)), frame.height - delta.y)
        frame.origin.y = editorTopY - frame.height
        textView.frame = frame
        updateTextContainerWidth()
        if let pdfView, let page {
            let pageFrame = pdfView.convert(convert(frame, to: pdfView), to: page).standardized
            manualEditorPageOrigin = pageFrame.origin
            manualEditorPageWidth = pageFrame.width
            manualEditorPageHeight = pageFrame.height
        }
        resizeTextViewHeight()
    }

    func textDidChange(_ notification: Notification) {
        resizeTextViewHeight()
    }

    @objc private func changeFamily(_ sender: NSPopUpButton) {
        editorFontFamily = sender.titleOfSelectedItem ?? editorFontFamily
        didChangeStyle = true
        applyFormatting()
        refocusEditor()
    }

    @objc private func changeSize(_ sender: NSStepper) {
        setDocumentFontSize(CGFloat(sender.integerValue))
        refocusEditor()
    }

    @objc private func commitSizeField(_ sender: NSTextField) {
        guard commitSizeFieldValue() else { return }
        refocusEditor()
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard obj.object as? NSTextField === sizeField else { return }
        _ = commitSizeFieldValue()
    }

    private func commitSizeFieldValue() -> Bool {
        guard let parsed = parsedFontSize(from: sizeField.stringValue) else {
            refreshSizeControls()
            return false
        }
        setDocumentFontSize(parsed)
        return true
    }

    private func setDocumentFontSize(_ size: CGFloat) {
        let clamped = min(max(size, CGFloat(sizeStepper.minValue)), CGFloat(sizeStepper.maxValue))
        guard abs(documentFontSize - clamped) >= 0.01 else {
            documentFontSize = clamped
            refreshSizeControls()
            return
        }
        documentFontSize = clamped
        didChangeStyle = true
        applyFormatting()
    }

    @objc private func toggleBold() {
        didChangeStyle = true
        if boldButton.state == .on {
            editorFontTraits.insert(.boldFontMask)
        } else {
            editorFontTraits.remove(.boldFontMask)
        }
        applyFormatting()
        refocusEditor()
    }

    @objc private func toggleItalic() {
        didChangeStyle = true
        if italicButton.state == .on {
            editorFontTraits.insert(.italicFontMask)
        } else {
            editorFontTraits.remove(.italicFontMask)
        }
        applyFormatting()
        refocusEditor()
    }

    @objc private func changeAlignment(_ sender: NSSegmentedControl) {
        didChangeStyle = true
        switch sender.selectedSegment {
        case 1: editorAlignment = .center
        case 2: editorAlignment = .right
        default: editorAlignment = .left
        }
        applyFormatting()
        refocusEditor()
    }

    @objc private func changeTextColor(_ sender: NSPopUpButton) {
        guard let index = sender.selectedItem?.representedObject as? Int,
              textColorChoices.indices.contains(index) else { return }
        editorTextColor = textColorChoices[index].color
        didChangeStyle = true
        applyFormatting()
        refocusEditor()
    }

    @objc private func matchNearbyFormat() {
        applySourceFormat(markStyleChange: true)
        viewModel?.showEditMessage("Matched the edited text to nearby document formatting.", isError: false)
        refocusEditor()
    }

    private func applySourceFormat(markStyleChange: Bool) {
        apply(format: sourceFormat, markStyleChange: markStyleChange)
    }

    @objc private func copyCurrentFormat() {
        viewModel?.copiedInlineTextFormat = currentFormat
        viewModel?.isInlineTextFormatPainterArmed = true
        viewModel?.showEditMessage("Copied text format. Click another text edit to paint it, or use Apply here.", isError: false)
        refocusEditor()
    }

    @objc private func applyCopiedFormat() {
        guard let format = viewModel?.copiedInlineTextFormat else {
            viewModel?.showEditMessage("Copy a text format first, then apply it to another edit.", isError: false)
            refocusEditor()
            return
        }
        apply(format: format, markStyleChange: true)
        viewModel?.isInlineTextFormatPainterArmed = false
        viewModel?.showEditMessage("Applied copied text format.", isError: false)
        refocusEditor()
    }

    private func applyArmedFormatPainterIfNeeded() {
        guard let viewModel,
              viewModel.isInlineTextFormatPainterArmed,
              let format = viewModel.copiedInlineTextFormat else { return }
        apply(format: format, markStyleChange: true)
        viewModel.isInlineTextFormatPainterArmed = false
        viewModel.showEditMessage("Applied copied text format.", isError: false)
    }

    private var currentFormat: PDFTextEditFormat {
        PDFTextEditFormat(
            fontName: documentFont().fontName,
            fontSize: documentFontSize,
            textColor: CodableColor(nsColor: editorTextColor),
            alignment: CodableTextAlignment(editorAlignment)
        )
    }

    private func apply(format: PDFTextEditFormat, markStyleChange: Bool) {
        documentFontSize = format.fontSize > 0 ? format.fontSize : originalFontSize
        let sourceFont = NSFont(name: format.fontName, size: documentFontSize) ?? .systemFont(ofSize: documentFontSize)
        editorFontFamily = Self.editingFamilyName(for: sourceFont, fallback: format.fontName)
        editorFontTraits = NSFontManager.shared.traits(of: sourceFont).intersection([.boldFontMask, .italicFontMask])
        editorTextColor = format.textColor.nsColor
        editorAlignment = format.alignment.nsTextAlignment
        if markStyleChange {
            didChangeStyle = true
        }
        applyFormatting()
    }

    private func performEditorUndo() {
        if textView.undoManager?.canUndo == true {
            textView.undoManager?.undo()
            resizeTextViewHeight()
        } else {
            window?.undoManager?.undo()
        }
    }

    private func refocusEditor() {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.didFinish else { return }
            self.window?.makeFirstResponder(self.textView)
        }
    }

    private func applyFormatting() {
        refreshSizeControls()
        refreshColorPopup()
        let font = displayFont()
        textView.font = font
        textView.textColor = editorTextColor
        textView.alignment = editorAlignment
        textView.typingAttributes = [
            .font: font,
            .foregroundColor: editorTextColor
        ]
        if let storage = textView.textStorage {
            let selectedRange = textView.selectedRange()
            let fullRange = NSRange(location: 0, length: storage.length)
            storage.setAttributes([
                .font: font,
                .foregroundColor: editorTextColor
            ], range: fullRange)
            textView.setAlignment(editorAlignment, range: fullRange)
            textView.setSelectedRange(selectedRange)
        }
        resizeTextViewHeight()
    }

    private func refreshSizeControls() {
        sizeField.stringValue = formattedFontSize(documentFontSize)
        sizeStepper.integerValue = Int(round(documentFontSize))
    }

    private func populateColorPopup() {
        colorPopup.removeAllItems()
        var insertedSeparator = false
        for (index, choice) in textColorChoices.enumerated() {
            if choice.isDetected && !insertedSeparator {
                colorPopup.menu?.addItem(.separator())
                insertedSeparator = true
            }
            colorPopup.addItem(withTitle: choice.name)
            let item = colorPopup.lastItem
            item?.representedObject = index
            item?.image = Self.colorSwatchImage(for: choice.color)
        }
    }

    private func refreshColorPopup() {
        guard let index = textColorChoices.firstIndex(where: {
            Self.colorsApproximatelyEqual(editorTextColor, $0.color, tolerance: 0.025)
        }) else { return }
        for itemIndex in 0..<colorPopup.numberOfItems {
            guard colorPopup.item(at: itemIndex)?.representedObject as? Int == index else { continue }
            colorPopup.selectItem(at: itemIndex)
            break
        }
    }

    private func parsedFontSize(from value: String) -> CGFloat? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let number = Double(trimmed.replacingOccurrences(of: ",", with: ".")),
              number.isFinite else { return nil }
        return CGFloat(number)
    }

    private func formattedFontSize(_ size: CGFloat) -> String {
        let rounded = round(size)
        if abs(size - rounded) < 0.05 {
            return "\(Int(rounded))"
        }
        return String(format: "%.1f", Double(size))
    }

    @objc private func pdfViewScaleChanged(_ notification: Notification) {
        guard !didFinish else { return }
        layoutEditor()
        applyFormatting()
    }

    private var displayScaleFactor: CGFloat {
        max(pdfView?.scaleFactor ?? 1, 0.01)
    }

    private var displayFontSize: CGFloat {
        max(1, documentFontSize * displayScaleFactor)
    }

    private func displayFont() -> NSFont {
        Self.editingFont(family: editorFontFamily, traits: editorFontTraits, size: displayFontSize)
    }

    private func documentFont() -> NSFont {
        Self.editingFont(family: editorFontFamily, traits: editorFontTraits, size: documentFontSize)
    }

    private func updateTextContainerWidth() {
        let textWidth = max(1, textView.frame.width - textView.textContainerInset.width * 2)
        textView.textContainer?.containerSize = NSSize(width: textWidth, height: CGFloat.infinity)
    }

    private func selectedAlignmentSegment() -> Int {
        switch editorAlignment {
        case .center: return 1
        case .right: return 2
        default: return 0
        }
    }

    private static func initialTextColor(for block: EditableTextBlock) -> NSColor {
        if block.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return defaultInsertedTextColor
        }
        return block.textColor.nsColor
    }

    private static func textColorChoices(for block: EditableTextBlock, document: PDFDocument?, initialColor: NSColor) -> [TextColorChoice] {
        var choices = defaultTextColorChoices

        func appendDetected(_ color: NSColor) {
            let normalized = normalizedColor(color)
            guard normalized.alphaComponent > 0.05,
                  !choices.contains(where: { colorsApproximatelyEqual($0.color, normalized, tolerance: 0.025) }) else { return }
            choices.append(TextColorChoice(name: "Detected \(hexString(for: normalized))", color: normalized, isDetected: true))
        }

        appendDetected(initialColor)
        appendDetected(block.textColor.nsColor)
        for line in block.lines {
            for run in line.runs {
                appendDetected(run.textColor.nsColor)
            }
        }
        for color in detectedDocumentTextColors(in: document) {
            appendDetected(color)
        }
        return choices
    }

    private static func detectedDocumentTextColors(in document: PDFDocument?) -> [NSColor] {
        guard let document else { return [] }
        var colors: [NSColor] = []
        if let data = document.dataRepresentation() {
            let engine = PDFTextAnalysisEngine()
            for pageIndex in 0..<document.pageCount {
                let page = document.page(at: pageIndex)
                let analysis = engine.analyze(data: data, pageIndex: pageIndex, fallbackPage: page)
                colors.append(contentsOf: analysis.blocks.map { $0.textColor.nsColor })
                if colors.count >= maxDetectedTextColors { return colors }
            }
            if !colors.isEmpty { return colors }
        }

        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex),
                  let attributed = page.attributedString,
                  attributed.length > 0 else { continue }
            let range = NSRange(location: 0, length: attributed.length)
            attributed.enumerateAttribute(.foregroundColor, in: range) { value, _, _ in
                if let color = value as? NSColor {
                    colors.append(color)
                }
            }
            if colors.count >= maxDetectedTextColors { return colors }
        }
        return colors
    }

    private static func normalizedColor(_ color: NSColor) -> NSColor {
        color.usingColorSpace(.sRGB) ?? .black
    }

    private static func hexString(for color: NSColor) -> String {
        let normalized = normalizedColor(color)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        normalized.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return String(
            format: "#%02X%02X%02X",
            Int(round(red * 255)),
            Int(round(green * 255)),
            Int(round(blue * 255))
        )
    }

    private static func colorSwatchImage(for color: NSColor) -> NSImage {
        let size = NSSize(width: 14, height: 14)
        let image = NSImage(size: size)
        image.lockFocus()
        let rect = NSRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3)
        normalizedColor(color).setFill()
        path.fill()
        NSColor.black.withAlphaComponent(0.28).setStroke()
        path.lineWidth = 1
        path.stroke()
        image.unlockFocus()
        return image
    }

    private static func colorsApproximatelyEqual(_ lhs: NSColor, _ rhs: NSColor, tolerance: CGFloat) -> Bool {
        guard let left = lhs.usingColorSpace(.sRGB),
              let right = rhs.usingColorSpace(.sRGB) else {
            return false
        }
        var leftRed: CGFloat = 0
        var leftGreen: CGFloat = 0
        var leftBlue: CGFloat = 0
        var leftAlpha: CGFloat = 0
        var rightRed: CGFloat = 0
        var rightGreen: CGFloat = 0
        var rightBlue: CGFloat = 0
        var rightAlpha: CGFloat = 0
        left.getRed(&leftRed, green: &leftGreen, blue: &leftBlue, alpha: &leftAlpha)
        right.getRed(&rightRed, green: &rightGreen, blue: &rightBlue, alpha: &rightAlpha)
        return abs(leftRed - rightRed) <= tolerance &&
            abs(leftGreen - rightGreen) <= tolerance &&
            abs(leftBlue - rightBlue) <= tolerance &&
            abs(leftAlpha - rightAlpha) <= tolerance
    }

    static func editingFamilyName(for font: NSFont, fallback: String) -> String {
        if let family = font.familyName, !family.isEmpty {
            return family
        }

        let fallbackFont = NSFont(name: fallback, size: font.pointSize)
        if let family = fallbackFont?.familyName, !family.isEmpty {
            return family
        }

        return fallback
            .replacingOccurrences(of: "-BoldItalic", with: "")
            .replacingOccurrences(of: "-BoldOblique", with: "")
            .replacingOccurrences(of: "-Bold", with: "")
            .replacingOccurrences(of: "-Italic", with: "")
            .replacingOccurrences(of: "-Oblique", with: "")
    }

    static func fontFamilyMenuItems(originalFamily: String) -> [String] {
        var seen = Set<String>()
        var families: [String] = []
        func append(_ family: String) {
            let trimmed = family.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            let key = trimmed.lowercased()
            guard seen.insert(key).inserted else { return }
            families.append(trimmed)
        }

        append(originalFamily)
        NSFontManager.shared.availableFontFamilies
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            .forEach(append)
        return families
    }

    static func editingFont(family: String, traits: NSFontTraitMask, size: CGFloat) -> NSFont {
        let manager = NSFontManager.shared
        if let matched = manager.font(
            withFamily: family,
            traits: traits,
            weight: traits.contains(.boldFontMask) ? 9 : 5,
            size: size
        ) {
            return matched
        }

        let base = manager.font(withFamily: family, traits: [], weight: 5, size: size)
            ?? NSFont(name: family, size: size)
            ?? NSFont(name: "Helvetica", size: size)
            ?? NSFont.systemFont(ofSize: size)

        var resolved = base
        if traits.contains(.boldFontMask) {
            resolved = manager.convert(resolved, toHaveTrait: .boldFontMask)
        } else {
            resolved = manager.convert(resolved, toNotHaveTrait: .boldFontMask)
        }
        if traits.contains(.italicFontMask) {
            resolved = manager.convert(resolved, toHaveTrait: .italicFontMask)
        } else {
            resolved = manager.convert(resolved, toNotHaveTrait: .italicFontMask)
        }
        return resolved
    }

    /// Commits the pending edit (same as pressing Done) if there's something worth saving,
    /// otherwise cancels cleanly. Called when the user starts editing a different block
    /// while this one is still open, so switching targets saves in-progress work instead
    /// of silently discarding it — clicking away should behave like Adobe/most editors,
    /// not like an implicit "undo everything I just typed."
    func finishForHandoff() {
        guard !didFinish else { return }
        if shouldCancelWithoutCommit {
            cancel()
        } else {
            commitButton()
        }
    }

    @objc fileprivate func commitButton() {
        guard !didFinish, let pdfView, let page else { return }
        _ = commitSizeFieldValue()
        if shouldCancelWithoutCommit {
            cancel()
            return
        }
        didFinish = true
        // Use the live editor box's own position AND size, converted to page space —
        // not just its size merged onto the original (pre-edit) block position. The box
        // commonly moves (its top-anchored height grows as text wraps) and re-using the
        // stale origin here placed the replacement text somewhere the user never saw it.
        // Two-step conversion (overlay-local → pdfView space → PDF page space) avoids
        // relying on the overlay's frame origin always being (0,0).
        var commitFrame = textView.frame
        if !didManuallyResizeWidth {
            let font = textView.font ?? displayFont()
            let fittingWidth = fittingTextViewWidth(
                for: textView.string,
                font: font,
                minimumWidth: committedMinimumEditorWidth
            )
            commitFrame.size.width = min(textView.frame.width, fittingWidth)
        }
        let inset = textView.textContainerInset
        let insetX = min(inset.width, max(0, (commitFrame.width - 1) / 2))
        let insetY = min(inset.height, max(0, (commitFrame.height - 1) / 2))
        commitFrame = commitFrame.insetBy(dx: insetX, dy: insetY)
        let viewFrame = convert(commitFrame, to: pdfView)
        var pageBounds = pdfView.convert(viewFrame, to: page).standardized
        pageBounds.size.width = max(1, pageBounds.width)
        pageBounds.size.height = max(1, pageBounds.height)
        let sourcePageBounds = block.bounds.standardized
        if !block.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if !didManuallyResizeWidth {
                pageBounds.size.width = max(pageBounds.width, sourcePageBounds.width)
            }
            if !didManuallyResizeHeight {
                pageBounds.size.height = max(pageBounds.height, sourcePageBounds.height)
            }
        }
        if !didManuallyReposition {
            pageBounds.origin.y = sourcePageBounds.maxY - pageBounds.height
        }
        let result = EditResult(
            pageRef: pageRef,
            block: block,
            text: textView.string,
            editedBounds: pageBounds,
            fontName: documentFont().fontName,
            fontSize: documentFontSize,
            textColor: editorTextColor,
            alignment: editorAlignment,
            didManuallyReposition: didManuallyReposition,
            didManuallyResizeWidth: didManuallyResizeWidth,
            didManuallyResizeHeight: didManuallyResizeHeight
        )
        if formattingDiffersFromSource {
            viewModel?.showEditMessage(
                "Edited text formatting does not match nearby document text. Use Match before Done to copy the nearby format.",
                isError: false
            )
        }
        removeFromSuperview()
        completion(.commit(result))
    }

    private var formattingDiffersFromSource: Bool {
        didChangeStyle && (
            currentFormat.fontName != sourceFormat.fontName ||
            abs(currentFormat.fontSize - sourceFormat.fontSize) >= 0.01 ||
            currentFormat.alignment != sourceFormat.alignment ||
            !Self.colorsApproximatelyEqual(currentFormat.textColor.nsColor, sourceFormat.textColor.nsColor, tolerance: 0.025)
        )
    }

    private var shouldCancelWithoutCommit: Bool {
        let trimmed = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        return textView.string == originalText &&
            editorFontFamily == originalFontFamily &&
            abs(documentFontSize - originalFontSize) < 0.01 &&
            editorFontTraits == originalFontTraits &&
            editorAlignment == originalAlignment &&
            !didManuallyReposition &&
            !didManuallyResizeWidth &&
            !didManuallyResizeHeight &&
            !didChangeStyle
    }

    @objc private func cancelButton() {
        cancel()
    }

    @objc private func revertButton() {
        guard !didFinish else { return }
        didFinish = true
        removeFromSuperview()
        completion(.revertToOriginal)
    }

    @objc private func addSignatureBox() {
        guard !didFinish else { return }
        let viewModel = viewModel
        finishForHandoff()
        viewModel?.currentTool = .signature
        viewModel?.isShowingSignaturePalette = true
    }
}

final class InlineEditableTextView: NSTextView {
    var onMoveDrag: ((CGPoint) -> Void)?
    var onEscape: (() -> Void)?
    var onUndoShortcut: (() -> Void)?
    private var isMoving = false
    private var lastPoint: CGPoint?

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }

    override func keyDown(with event: NSEvent) {
        if event.charactersIgnoringModifiers?.lowercased() == "z",
           !event.modifierFlags.intersection([.command, .control]).isEmpty {
            onUndoShortcut?()
            return
        }
        super.keyDown(with: event)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(CGRect(x: 0, y: bounds.height - 8, width: bounds.width, height: 8), cursor: .openHand)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if point.y >= bounds.height - 8 {
            isMoving = true
            lastPoint = superview?.convert(event.locationInWindow, from: nil)
            NSCursor.closedHand.set()
            return
        }
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard isMoving else {
            super.mouseDragged(with: event)
            return
        }
        guard let parent = superview else { return }
        let point = parent.convert(event.locationInWindow, from: nil)
        if let lastPoint {
            onMoveDrag?(CGPoint(x: point.x - lastPoint.x, y: point.y - lastPoint.y))
        }
        self.lastPoint = point
    }

    override func mouseUp(with event: NSEvent) {
        if isMoving {
            isMoving = false
            lastPoint = nil
            NSCursor.arrow.set()
            return
        }
        super.mouseUp(with: event)
    }
}

final class InlineMoveHandle: NSView {
    var onDrag: ((CGPoint) -> Void)?
    private var lastPoint: CGPoint?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.dsAccentNS.withAlphaComponent(0.18).cgColor
        layer?.borderColor = NSColor.dsAccentNS.withAlphaComponent(0.8).cgColor
        layer?.borderWidth = 1
        layer?.cornerRadius = 3
    }

    required init?(coder: NSCoder) { nil }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    override func mouseDown(with event: NSEvent) {
        lastPoint = superview?.convert(event.locationInWindow, from: nil)
        NSCursor.closedHand.set()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let parent = superview else { return }
        let point = parent.convert(event.locationInWindow, from: nil)
        if let lastPoint {
            onDrag?(CGPoint(x: point.x - lastPoint.x, y: point.y - lastPoint.y))
        }
        self.lastPoint = point
    }

    override func mouseUp(with event: NSEvent) {
        lastPoint = nil
        NSCursor.arrow.set()
    }
}

final class InlineResizeHandle: NSView {
    var onDrag: ((CGPoint) -> Void)?
    private var lastPoint: CGPoint?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.dsAccentNS.cgColor
        layer?.borderColor = NSColor.white.withAlphaComponent(0.9).cgColor
        layer?.borderWidth = 1
        layer?.cornerRadius = 8
    }

    required init?(coder: NSCoder) { nil }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func mouseDown(with event: NSEvent) {
        lastPoint = superview?.convert(event.locationInWindow, from: nil)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let parent = superview else { return }
        let point = parent.convert(event.locationInWindow, from: nil)
        if let lastPoint {
            onDrag?(CGPoint(x: point.x - lastPoint.x, y: point.y - lastPoint.y))
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

private extension NSView {
    func findEnclosingScrollView() -> NSScrollView? {
        if let scrollView = self as? NSScrollView {
            return scrollView
        }
        for subview in subviews {
            if let scrollView = subview.findEnclosingScrollView() {
                return scrollView
            }
        }
        return enclosingScrollView
    }
}
