import SwiftUI
import PDFKit

// MARK: - Reading canvas shell (PDF + zoom/page bar)

struct ReadingCanvas: View {
    @Bindable var viewModel: WorkspaceViewModel

    var body: some View {
        VStack(spacing: 0) {
            PDFViewRepresentable(viewModel: viewModel)
            ZoomPageBar(viewModel: viewModel)
        }
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
            Text("PDFold v3 workspace")
                .font(.system(size: 11, weight: .medium, design: .serif))
                .foregroundStyle(Color.dsTextTertiary)
                .lineLimit(1)
        }
        .accessibilityLabel("PDFold version 3 workspace")
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
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject {
        var viewModel: WorkspaceViewModel
        weak var pdfView: PDFoldPDFView?
        let inkOverlay = InkOverlayView()

        init(viewModel: WorkspaceViewModel) {
            self.viewModel = viewModel
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
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
            guard let page = pdfView.page(for: viewPoint, nearest: false),
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
                if let ann = page.annotation(at: pagePoint), ann.type == "FreeText" {
                    let rect = pdfView.convert(ann.bounds, from: page)
                    showNoteEditor(for: ann, near: rect, in: pdfView)
                } else if let selection = editableTextSelection(at: pagePoint, on: page),
                          let ann = viewModel.addEditableTextOverlay(from: selection, on: page) {
                    pdfView.setCurrentSelection(selection, animate: false)
                    let rect = pdfView.convert(ann.bounds, from: page)
                    showNoteEditor(for: ann, near: rect, in: pdfView)
                } else {
                    let ann = viewModel.addTextBox(at: pagePoint, on: page)
                    let rect = pdfView.convert(ann.bounds, from: page)
                    showNoteEditor(for: ann, near: rect, in: pdfView)
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
            let vc = NoteEditorViewController(annotation: annotation)
            let popover = NSPopover()
            popover.contentViewController = vc
            popover.behavior = .transient
            popover.show(relativeTo: rect, of: view, preferredEdge: .maxY)
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
    private weak var textView: NSTextView?
    private weak var scrollView: NSScrollView?
    private weak var sizeLabel: NSTextField?
    private var originalAnnotationFont: NSFont?
    private var originalAnnotationBackgroundColor: NSColor?
    private let minimumEditorFontSize: CGFloat = 10
    private var styleChanged = false
    private var editorFontFamily: String
    private var editorFontSize: CGFloat
    private var editorFontTraits: NSFontTraitMask
    private var editorTextColor: NSColor
    private var editorAlignment: NSTextAlignment
    private var isFreeTextAnnotation: Bool { annotation.type == "FreeText" }
    private var isTextReplacementAnnotation: Bool {
        (annotation.value(forAnnotationKey: WorkspaceViewModel.textReplacementAnnotationKey) as? Bool) == true
    }

    init(annotation: PDFAnnotation) {
        self.annotation = annotation
        let resolvedFont = annotation.font ?? .systemFont(ofSize: 16)
        self.originalAnnotationFont = annotation.font
        self.originalAnnotationBackgroundColor = annotation.color
        self.editorFontFamily = resolvedFont.familyName ?? NSFont.systemFont(ofSize: 16).familyName ?? "System"
        self.editorFontSize = max(resolvedFont.pointSize, minimumEditorFontSize)
        self.editorFontTraits = NSFontManager.shared.traits(of: resolvedFont).intersection([.boldFontMask, .italicFontMask])
        self.editorTextColor = annotation.fontColor ?? .dsTextPrimaryNS
        self.editorAlignment = annotation.alignment
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { nil }

    override func loadView() {
        let editorWidth = isFreeTextAnnotation ? max(420, min(560, annotation.bounds.width * 2.4)) : 300
        let editorHeight: CGFloat = isFreeTextAnnotation ? 286 : 210
        let headerHeight: CGFloat = 44
        let footerHeight: CGFloat = 52
        let controlsHeight: CGFloat = isFreeTextAnnotation ? 74 : 0
        let textMargin: CGFloat = 14
        let textHeight = editorHeight - headerHeight - footerHeight - controlsHeight - textMargin
        let textWidth = editorWidth - (textMargin * 2)
        let container = NSView(frame: CGRect(x: 0, y: 0, width: editorWidth, height: editorHeight))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.dsSurfaceNS.cgColor
        container.layer?.cornerRadius = 12
        container.layer?.cornerCurve = .continuous

        let titleLabel = NSTextField(labelWithString: isFreeTextAnnotation ? "Edit PDF Text" : "Edit Note")
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .dsTextPrimaryNS
        titleLabel.frame = CGRect(x: 16, y: editorHeight - 28, width: editorWidth - 32, height: 18)
        container.addSubview(titleLabel)

        let scroll = NSScrollView(frame: CGRect(x: textMargin, y: footerHeight + controlsHeight, width: textWidth, height: textHeight))
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = true
        scroll.backgroundColor = editorFieldBackgroundColor()
        scroll.wantsLayer = true
        scroll.layer?.backgroundColor = editorFieldBackgroundColor().cgColor
        scroll.layer?.cornerRadius = 8
        scroll.layer?.cornerCurve = .continuous
        scroll.layer?.borderWidth = 1
        scroll.layer?.borderColor = NSColor.dsSeparatorNS.withAlphaComponent(0.85).cgColor

        let tv = NSTextView(frame: CGRect(x: 0, y: 0, width: textWidth, height: textHeight))
        tv.isRichText = false
        tv.font = editorFont()
        tv.textContainerInset = NSSize(width: 10, height: 10)
        tv.string = annotation.contents ?? ""
        tv.backgroundColor = editorFieldBackgroundColor()
        tv.textColor = editorTextColor
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
        commitChanges()
    }

    @objc private func commit() {
        commitChanges()
        dismiss(nil)
    }

    private func commitChanges() {
        guard let textView else { return }
        annotation.contents = textView.string
        if isFreeTextAnnotation {
            annotation.font = documentFont()
            annotation.fontColor = editorTextColor
            annotation.alignment = editorAlignment
            annotation.color = replacementBackgroundColor()
            resizeFreeTextAnnotationToFit(textView.string, preserveReplacementWidth: isTextReplacementAnnotation)
        }
    }

    private func resizeFreeTextAnnotationToFit(_ text: String, preserveReplacementWidth: Bool) {
        guard isFreeTextAnnotation else { return }
        let font = annotation.font ?? NSFont.systemFont(ofSize: minimumEditorFontSize)
        let measured = (text.isEmpty ? " " : text) as NSString
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let currentBounds = annotation.bounds
        let measurementWidth = preserveReplacementWidth ? max(currentBounds.width - 10, 1) : 520
        let size = measured.boundingRect(
            with: CGSize(width: measurementWidth, height: CGFloat.infinity),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes
        ).size
        var bounds = currentBounds
        if !preserveReplacementWidth {
            bounds.size.width = max(36, min(620, ceil(size.width) + 12))
        }
        bounds.size.height = max(font.pointSize * 1.45, ceil(size.height) + 8)
        annotation.bounds = bounds
    }

    private func formattingControls(frame: CGRect) -> NSView {
        let controls = NSView(frame: frame)

        let family = NSPopUpButton(frame: CGRect(x: 0, y: 40, width: 172, height: 26), pullsDown: false)
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
        family.toolTip = "Font"
        controls.addSubview(family)

        let align = NSSegmentedControl(labels: ["L", "C", "R"], trackingMode: .selectOne, target: self, action: #selector(changeAlignment(_:)))
        align.frame = CGRect(x: 184, y: 40, width: 92, height: 26)
        align.toolTip = "Text alignment"
        align.selectedSegment = selectedAlignmentSegment()
        controls.addSubview(align)

        let bold = formattingButton(title: "B", x: 0, action: #selector(toggleBold), isToggle: true)
        bold.font = .boldSystemFont(ofSize: 13)
        bold.state = editorFontTraits.contains(.boldFontMask) ? .on : .off
        bold.toolTip = "Bold"
        controls.addSubview(bold)

        let italic = formattingButton(title: "I", x: 34, action: #selector(toggleItalic), isToggle: true)
        italic.font = NSFontManager.shared.convert(NSFont.systemFont(ofSize: 13), toHaveTrait: .italicFontMask)
        italic.state = editorFontTraits.contains(.italicFontMask) ? .on : .off
        italic.toolTip = "Italic"
        controls.addSubview(italic)

        let sizeDown = formattingButton(title: "A-", x: 76, action: #selector(decreaseFontSize))
        sizeDown.toolTip = "Decrease font size"
        controls.addSubview(sizeDown)

        let label = NSTextField(labelWithString: "\(Int(round(editorFontSize)))")
        label.alignment = .center
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.frame = CGRect(x: 112, y: 8, width: 34, height: 18)
        controls.addSubview(label)
        sizeLabel = label

        let sizeUp = formattingButton(title: "A+", x: 148, action: #selector(increaseFontSize))
        sizeUp.toolTip = "Increase font size"
        controls.addSubview(sizeUp)

        let swatches: [(NSColor, CGFloat, String, Int)] = [
            (.black, 204, "Black", 0),
            (.dsTextPrimaryNS, 232, "Blue", 1),
            (.systemRed, 260, "Red", 2),
            (.white, 288, "White", 3)
        ]
        for (color, x, name, tag) in swatches {
            let button = NSButton(title: "", target: self, action: #selector(changeTextColor(_:)))
            button.frame = CGRect(x: x, y: 8, width: 20, height: 20)
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

    private func formattingButton(title: String, x: CGFloat, action: Selector, isToggle: Bool = false) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.frame = CGRect(x: x, y: 5, width: 30, height: 26)
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

    @objc private func decreaseFontSize() {
        editorFontSize = max(8, editorFontSize - 1)
        applyFormatting()
    }

    @objc private func increaseFontSize() {
        editorFontSize = min(72, editorFontSize + 1)
        applyFormatting()
    }

    @objc private func changeTextColor(_ sender: NSButton) {
        switch sender.tag {
        case 1: editorTextColor = .dsTextPrimaryNS
        case 2: editorTextColor = .systemRed
        case 3: editorTextColor = .white
        default: editorTextColor = .black
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
        textView?.font = editorFont()
        textView?.textColor = editorTextColor
        textView?.alignment = editorAlignment
        textView?.backgroundColor = editorFieldBackgroundColor()
        scrollView?.backgroundColor = editorFieldBackgroundColor()
        scrollView?.layer?.backgroundColor = editorFieldBackgroundColor().cgColor
    }

    private func editorFont() -> NSFont {
        let descriptor = NSFontDescriptor(fontAttributes: [.family: editorFontFamily])
        let base = NSFont(descriptor: descriptor, size: editorFontSize) ?? NSFont.systemFont(ofSize: editorFontSize)
        return applyTraits(to: base)
    }

    private func documentFont() -> NSFont {
        guard styleChanged else {
            return originalAnnotationFont ?? annotation.font ?? editorFont()
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

    private func replacementBackgroundColor() -> NSColor {
        guard isTextReplacementAnnotation else {
            return originalAnnotationBackgroundColor ?? .clear
        }
        return originalAnnotationBackgroundColor ?? NSColor.white.withAlphaComponent(0.96)
    }

    private func editorFieldBackgroundColor() -> NSColor {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        let color = editorTextColor.usingColorSpace(.sRGB) ?? editorTextColor
        color.getRed(&red, green: &green, blue: &blue, alpha: nil)
        let relativeLuminance = (0.2126 * red) + (0.7152 * green) + (0.0722 * blue)
        return relativeLuminance > 0.72
            ? NSColor(srgbRed: 0.071, green: 0.082, blue: 0.098, alpha: 1)
            : .textBackgroundColor
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
