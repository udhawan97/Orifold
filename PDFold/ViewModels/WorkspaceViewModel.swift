import SwiftUI
import PDFKit
import AppKit
import Observation
import UniformTypeIdentifiers

enum WorkspaceExportFormat: String, CaseIterable, Identifiable {
    case pdf
    case word
    case text
    case html
    case png
    case jpeg

    var id: String { rawValue }

    var menuTitle: String {
        switch self {
        case .pdf: return "PDF (.pdf)"
        case .word: return "Word (.docx)"
        case .text: return "Text (.txt)"
        case .html: return "HTML (.html)"
        case .png: return "PNG Images (.png)"
        case .jpeg: return "JPEG Images (.jpg)"
        }
    }

    var fileExtension: String {
        switch self {
        case .pdf: return "pdf"
        case .word: return "docx"
        case .text: return "txt"
        case .html: return "html"
        case .png: return "png"
        case .jpeg: return "jpg"
        }
    }

    var contentType: UTType {
        switch self {
        case .pdf: return .pdf
        case .word: return UTType(filenameExtension: "docx") ?? .data
        case .text: return .plainText
        case .html: return .html
        case .png: return .png
        case .jpeg: return .jpeg
        }
    }

    var exportsDirectory: Bool {
        switch self {
        case .png, .jpeg: return true
        case .pdf, .word, .text, .html: return false
        }
    }
}

enum AnnotationTool: String, CaseIterable, Identifiable {
    case none      = "select"
    case highlight = "highlighter"
    case note      = "note.text"
    case editText  = "textformat"
    case ink       = "pencil.tip"
    case underline = "underline"
    case strikeout = "strikethrough"
    case signature = "signature"

    var id: String { rawValue }
    var label: String {
        switch self {
        case .none:      return "Select"
        case .highlight: return "Highlight"
        case .note:      return "Note"
        case .editText:  return "Edit Text"
        case .ink:       return "Ink"
        case .underline: return "Underline"
        case .strikeout: return "Strikeout"
        case .signature: return "Signature"
        }
    }

    var iconName: String {
        switch self {
        case .none:      return "rectangle.dashed"
        case .highlight: return "pencil.tip.crop.circle"
        case .note:      return "note.text"
        case .editText:  return "textformat"
        case .ink:       return "pencil.tip"
        case .underline: return "underline"
        case .strikeout: return "strikethrough"
        case .signature: return "signature"
        }
    }

    var helpText: String {
        switch self {
        case .none:      return "Select annotations on the page. Press Delete to remove the selected annotation."
        case .highlight: return "Select PDF text to add a colored highlight."
        case .note:      return "Click the page to add a sticky note, or click an existing note to edit it."
        case .editText:  return "Click the page to place editable text, or click an existing text box to change it."
        case .ink:       return "Draw freehand marks on the page."
        case .underline: return "Select PDF text to underline it."
        case .strikeout: return "Select PDF text to strike it out."
        case .signature: return "Place a saved signature on the page."
        }
    }

    var isColorable: Bool {
        switch self {
        case .highlight, .note, .editText, .ink, .underline, .strikeout: return true
        case .none, .signature: return false
        }
    }

    var usesInkColor: Bool { self == .ink }
}

@Observable
final class WorkspaceViewModel {
    var document: WorkspaceDocument
    var combinedPDF: PDFDocument = PDFDocument()
    /// Ordered parallel to workspace.documents.
    var loadedPDFs: [(MemberDocument, PDFDocument)] = []

    // MARK: - UI state
    var importError: ImportError? = nil
    var exportError: ExportError? = nil
    var pendingPasswordURL: URL? = nil
    var pendingPasswordPDF: PDFDocument? = nil
    var isShowingPasswordPrompt = false
    var currentTool: AnnotationTool = .none
    var isShowingExport = false
    var isShowingSearch = false
    var isShowingSignaturePalette = false
    var searchQuery = ""
    var searchResults: [PDFSelection] = []
    var searchResultIndex: Int = -1
    var pendingSignatureData: Data? = nil
    var selectedPageRefID: UUID? = nil
    var draggedPageRefID: UUID? = nil

    // MARK: - Annotation colors (curated palette)
    var annotationColor: NSColor = .dsAnnotationYellow   // highlight, note, underline, strikeout
    var inkColor: NSColor = .dsInk                        // ink strokes

    // MARK: - Annotation selection (for Delete key deletion)
    var selectedAnnotation: PDFAnnotation? = nil

    // MARK: - Canvas state (updated by PDFView via Coordinator)
    var currentPageNumber: Int = 0
    var pageCount: Int = 0

    /// Reactive list of member documents — backed by loadedPDFs so the sidebar
    /// re-renders whenever documents are added, removed, or reordered.
    var memberDocuments: [MemberDocument] { loadedPDFs.map { $0.0 } }

    weak var undoManager: UndoManager?

    private let engine = PDFKitEngine()

    struct ImportError: Identifiable {
        let id = UUID()
        var fileName: String
        var message: String
    }

    struct ExportError: Identifiable {
        let id = UUID()
        var message: String
    }

    // MARK: - Init

    init(document: WorkspaceDocument) {
        self.document = document

        // Reconstruct loadedPDFs from saved package data (document open path)
        for member in document.workspace.documents {
            if let data = document.memberPDFData[member.id],
               let pdf = PDFDocument(data: data) {
                loadedPDFs.append((member, pdf))
            }
        }

        // Snapshot hook: bake live annotation state before each save
        document.currentPDFDataProvider = { [weak self] in
            guard let self else { return [:] }
            var result: [UUID: Data] = [:]
            for (member, pdf) in self.loadedPDFs {
                result[member.id] = pdf.dataRepresentation()
            }
            return result
        }

        if !loadedPDFs.isEmpty { rebuild() }
    }

    // MARK: - Import

    func importFiles(urls: [URL]) {
        for url in urls { addFile(from: url) }
        rebuild()
    }

    func importPDFs(urls: [URL]) {
        importFiles(urls: urls)
    }

    func addFile(from url: URL) {
        let fileName = url.lastPathComponent
        let isSecurityScoped = url.startAccessingSecurityScopedResource()
        defer {
            if isSecurityScoped { url.stopAccessingSecurityScopedResource() }
        }

        let pdf: PDFDocument
        do {
            pdf = try engine.loadDocument(from: url)
        } catch {
            importError = ImportError(
                fileName: fileName,
                message: "Could not open \"\(fileName)\". \(DocumentImportConverter.userMessage(for: error))"
            )
            return
        }
        if pdf.isLocked {
            pendingPasswordURL = url
            pendingPasswordPDF = pdf
            isShowingPasswordPrompt = true
            return
        }
        attachPDF(pdf, from: url)
    }

    func unlock(pdf: PDFDocument, password: String, url: URL) -> Bool {
        guard pdf.unlock(withPassword: password) else { return false }
        attachPDF(pdf, from: url)
        pendingPasswordPDF = nil
        rebuild()
        return true
    }

    private func attachPDF(_ pdf: PDFDocument, from url: URL) {
        let name = url.deletingPathExtension().lastPathComponent
        var member = MemberDocument(displayName: name, sourcePDFRef: url.lastPathComponent)
        let refs = (0..<pdf.pageCount).map { i in PageRef(memberDocId: member.id, sourcePageIndex: i) }
        member.pageRefs = refs.map(\.id)
        document.workspace.documents.append(member)
        document.workspace.pageOrder.append(contentsOf: refs)
        document.memberPDFData[member.id] = pdf.dataRepresentation()
        loadedPDFs.append((member, pdf))
    }

    func rebuild() {
        combinedPDF = engine.concatenate(documents: loadedPDFs, includeBanners: true)
        pageCount = combinedPDF.pageCount
    }

    // MARK: - Reorder / Remove (with undo)

    func moveDocument(from source: IndexSet, to destination: Int) {
        let snapshot = captureOrderSnapshot()
        document.workspace.documents.move(fromOffsets: source, toOffset: destination)
        syncLoadedPDFsOrder()
        rebuildPageOrder()
        rebuild()
        registerUndo(snapshot: snapshot, actionName: "Move Document")
    }

    func removeDocument(at offsets: IndexSet) {
        let snapshot = captureOrderSnapshot()
        let removedIds = Set(offsets.map { document.workspace.documents[$0].id })
        document.workspace.documents.remove(atOffsets: offsets)
        loadedPDFs.removeAll { removedIds.contains($0.0.id) }
        rebuildPageOrder()
        rebuild()
        registerUndo(snapshot: snapshot, actionName: "Remove Document")
    }

    private struct OrderSnapshot {
        var documents: [MemberDocument]
        var pageOrder: [PageRef]
        var pdfData: [UUID: Data]
    }

    private func captureOrderSnapshot() -> OrderSnapshot {
        OrderSnapshot(
            documents: document.workspace.documents,
            pageOrder: document.workspace.pageOrder,
            pdfData: currentPDFData()
        )
    }

    private func restore(_ snapshot: OrderSnapshot) {
        document.workspace.documents = snapshot.documents
        document.workspace.pageOrder = snapshot.pageOrder
        document.memberPDFData = snapshot.pdfData
        loadedPDFs = snapshot.documents.compactMap { member in
            guard let data = snapshot.pdfData[member.id],
                  let pdf = PDFDocument(data: data) else { return nil }
            return (member, pdf)
        }
        rebuild()
    }

    private func currentPDFData() -> [UUID: Data] {
        var result: [UUID: Data] = [:]
        for (member, pdf) in loadedPDFs {
            if let data = pdf.dataRepresentation() {
                result[member.id] = data
            }
        }
        return result
    }

    private func registerUndo(snapshot: OrderSnapshot, actionName: String) {
        undoManager?.registerUndo(withTarget: self) { vm in
            vm.restore(snapshot)
        }
        undoManager?.setActionName(actionName)
    }

    private func syncLoadedPDFsOrder() {
        let order = document.workspace.documents.map(\.id)
        loadedPDFs.sort {
            (order.firstIndex(of: $0.0.id) ?? Int.max) < (order.firstIndex(of: $1.0.id) ?? Int.max)
        }
    }

    private func rebuildPageOrder() {
        var refsByID: [UUID: PageRef] = [:]
        for ref in document.workspace.pageOrder {
            refsByID[ref.id] = ref
        }
        document.workspace.pageOrder = document.workspace.documents.flatMap { member in
            member.pageRefs.compactMap { refsByID[$0] }
        }
    }

    func selectPage(_ ref: PageRef) {
        selectedPageRefID = ref.id
        if let pageIndex = combinedPageIndex(for: ref) {
            NotificationCenter.default.post(name: .pdfoldJumpToPageIndex, object: pageIndex)
        }
    }

    func combinedPageIndex(for ref: PageRef) -> Int? {
        var combinedIndex = 0
        for member in document.workspace.documents {
            combinedIndex += 1  // source-file banner page
            if member.id == ref.memberDocId {
                guard let localIndex = member.pageRefs.firstIndex(of: ref.id) else { return nil }
                return combinedIndex + localIndex
            }
            combinedIndex += member.pageRefs.count
        }
        return nil
    }

    func beginDraggingPage(_ ref: PageRef) {
        draggedPageRefID = ref.id
    }

    func moveDraggedPage(to targetRef: PageRef) -> Bool {
        guard let draggedPageRefID,
              draggedPageRefID != targetRef.id,
              let sourceRef = document.workspace.pageOrder.first(where: { $0.id == draggedPageRefID }),
              sourceRef.memberDocId == targetRef.memberDocId,
              let memberIndex = document.workspace.documents.firstIndex(where: { $0.id == targetRef.memberDocId }),
              let sourceIndex = document.workspace.documents[memberIndex].pageRefs.firstIndex(of: sourceRef.id),
              let targetIndex = document.workspace.documents[memberIndex].pageRefs.firstIndex(of: targetRef.id)
        else {
            self.draggedPageRefID = nil
            return false
        }

        let destination = targetIndex > sourceIndex ? targetIndex + 1 : targetIndex
        movePage(sourceRef, toIndex: destination)
        selectedPageRefID = sourceRef.id
        self.draggedPageRefID = nil
        return true
    }

    // MARK: - Annotations

    func applyHighlight(to selection: PDFSelection) {
        selection.selectionsByLine().forEach { line in
            guard let page = line.pages.first else { return }
            let bounds = line.bounds(for: page)
            let ann = PDFAnnotation(bounds: bounds, forType: .highlight, withProperties: nil)
            ann.color = annotationColor.withAlphaComponent(0.4)
            page.addAnnotation(ann)
            undoManager?.registerUndo(withTarget: self) { _ in page.removeAnnotation(ann) }
        }
        undoManager?.setActionName("Highlight")
    }

    @discardableResult
    func addNote(at pagePoint: CGPoint, on page: PDFPage) -> PDFAnnotation {
        let size: CGFloat = 24
        let bounds = CGRect(x: pagePoint.x - size / 2, y: pagePoint.y - size / 2,
                            width: size, height: size)
        let ann = PDFAnnotation(bounds: bounds, forType: .text, withProperties: nil)
        ann.contents = ""
        ann.color = annotationColor
        page.addAnnotation(ann)
        undoManager?.registerUndo(withTarget: self) { _ in page.removeAnnotation(ann) }
        undoManager?.setActionName("Add Note")
        return ann
    }

    @discardableResult
    func addTextBox(at pagePoint: CGPoint, on page: PDFPage) -> PDFAnnotation {
        let size = CGSize(width: 160, height: 48)
        let bounds = CGRect(x: pagePoint.x - size.width / 2,
                            y: pagePoint.y - size.height / 2,
                            width: size.width,
                            height: size.height)
        let ann = PDFAnnotation(bounds: bounds, forType: .freeText, withProperties: nil)
        ann.contents = ""
        ann.font = .systemFont(ofSize: 14)
        ann.fontColor = .dsTextPrimaryNS
        ann.color = annotationColor.withAlphaComponent(0.18)
        let border = PDFBorder()
        border.lineWidth = 1
        ann.border = border
        page.addAnnotation(ann)
        undoManager?.registerUndo(withTarget: self) { _ in page.removeAnnotation(ann) }
        undoManager?.setActionName("Add Text Box")
        return ann
    }

    func addInkStroke(path: NSBezierPath, on page: PDFPage) {
        let bounds = path.bounds.insetBy(dx: -2, dy: -2)
        let ann = PDFAnnotation(bounds: bounds, forType: .ink, withProperties: nil)
        ann.color = inkColor
        ann.border = PDFBorder()
        ann.border?.lineWidth = 2
        let flatPoints = bezierPathToFlatPoints(path)
        ann.setValue(flatPoints, forAnnotationKey: PDFAnnotationKey(rawValue: "/InkList"))
        page.addAnnotation(ann)
        undoManager?.registerUndo(withTarget: self) { _ in page.removeAnnotation(ann) }
        undoManager?.setActionName("Ink Stroke")
    }

    func deleteSelectedAnnotation() {
        guard let ann = selectedAnnotation, let page = ann.page else { return }
        page.removeAnnotation(ann)
        selectedAnnotation = nil
        undoManager?.registerUndo(withTarget: self) { vm in
            page.addAnnotation(ann)
            vm.selectedAnnotation = ann
        }
        undoManager?.setActionName("Delete Annotation")
    }

    private func bezierPathToFlatPoints(_ path: NSBezierPath) -> [[CGFloat]] {
        var result: [CGFloat] = []
        var pts = [NSPoint](repeating: .zero, count: 3)
        for i in 0..<path.elementCount {
            let type = path.element(at: i, associatedPoints: &pts)
            switch type {
            case .moveTo, .lineTo:
                result.append(contentsOf: [pts[0].x, pts[0].y])
            case .curveTo, .cubicCurveTo:
                result.append(contentsOf: [pts[2].x, pts[2].y])
            case .quadraticCurveTo:
                result.append(contentsOf: [pts[1].x, pts[1].y])
            case .closePath:
                break
            @unknown default:
                break
            }
        }
        return [result]  // single-stroke array
    }

    // MARK: - Signature

    func placeSignature(imageData: Data, at pagePoint: CGPoint, on page: PDFPage, size: CGSize = CGSize(width: 120, height: 48)) {
        let bounds = CGRect(
            x: pagePoint.x - size.width / 2,
            y: pagePoint.y - size.height / 2,
            width: size.width, height: size.height
        )
        let placement = SignaturePlacement(
            pageRefId: pageRefID(for: page),
            imageData: imageData,
            rect: bounds,
            signedAt: Date()
        )
        document.workspace.signatures.append(placement)

        // Render as a stamp annotation for display
        if let image = NSImage(data: imageData) {
            let ann = PDFAnnotation(bounds: bounds, forType: .stamp, withProperties: nil)
            ann.setValue(image, forAnnotationKey: .widgetValue)
            page.addAnnotation(ann)
        }
        undoManager?.setActionName("Place Signature")
    }

    private func pageRefID(for page: PDFPage) -> UUID {
        // Map the PDFPage back to a PageRef.id using position in combinedPDF
        guard let doc = page.document,
              let idx = (0..<doc.pageCount).first(where: { doc.page(at: $0) === page })
        else { return UUID() }
        // The combinedPDF interleaves banner pages; skip them
        var realPageIdx = 0
        for i in 0..<idx {
            if !(doc.page(at: i) is BoundaryPage) { realPageIdx += 1 }
        }
        let refs = document.workspace.pageOrder
        guard realPageIdx < refs.count else { return UUID() }
        return refs[realPageIdx].id
    }

    // MARK: - Search

    func search(query: String) {
        searchResults = []
        searchResultIndex = -1
        guard !query.isEmpty else { return }
        combinedPDF.cancelFindString()
        let results = combinedPDF.findString(query, withOptions: .caseInsensitive)
        searchResults = results
        if !results.isEmpty {
            searchResultIndex = 0
            jumpToSearchResult(0)
        }
    }

    func searchNext() {
        guard !searchResults.isEmpty else { return }
        searchResultIndex = (searchResultIndex + 1) % searchResults.count
        jumpToSearchResult(searchResultIndex)
    }

    func searchPrevious() {
        guard !searchResults.isEmpty else { return }
        searchResultIndex = (searchResultIndex - 1 + searchResults.count) % searchResults.count
        jumpToSearchResult(searchResultIndex)
    }

    private func jumpToSearchResult(_ index: Int) {
        guard index >= 0, index < searchResults.count else { return }
        NotificationCenter.default.post(name: .pdfoldJumpToSelection, object: searchResults[index])
    }

    // MARK: - Zoom

    func zoomIn()  { NotificationCenter.default.post(name: .pdfoldZoomIn,  object: nil) }
    func zoomOut() { NotificationCenter.default.post(name: .pdfoldZoomOut, object: nil) }
    func zoomFit() { NotificationCenter.default.post(name: .pdfoldZoomFit, object: nil) }

    // MARK: - Export

    func exportWorkspace(as format: WorkspaceExportFormat) {
        switch format {
        case .pdf:
            exportPlainPDF()
        case .word:
            exportWordDocument()
        case .text:
            exportPlainText()
        case .html:
            exportHTML()
        case .png, .jpeg:
            exportPageImages(as: format)
        }
    }

    func exportPlainPDF() {
        let exportDoc = engine.concatenate(documents: loadedPDFs, includeBanners: false)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "\(document.workspace.title).pdf"
        panel.title = "Export as PDF"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard exportDoc.write(to: url) else {
            exportError = ExportError(message: "PDFold could not write the exported PDF. Check that the destination is writable and has enough free space.")
            return
        }
    }

    private func exportWordDocument() {
        let attributed = attributedTextForDocumentExport()
        do {
            let data = try attributed.data(
                from: NSRange(location: 0, length: attributed.length),
                documentAttributes: [.documentType: NSAttributedString.DocumentType.officeOpenXML]
            )
            saveData(data, as: .word)
        } catch {
            exportError = ExportError(message: "PDFold could not create the Word export: \(error.localizedDescription)")
        }
    }

    private func exportPlainText() {
        guard let data = plainTextForDocumentExport().data(using: .utf8) else {
            exportError = ExportError(message: "PDFold could not encode the text export.")
            return
        }
        saveData(data, as: .text)
    }

    private func exportHTML() {
        let html = htmlForDocumentExport()
        guard let data = html.data(using: .utf8) else {
            exportError = ExportError(message: "PDFold could not encode the HTML export.")
            return
        }
        saveData(data, as: .html)
    }

    private func exportPageImages(as format: WorkspaceExportFormat) {
        let exportDoc = engine.concatenate(documents: loadedPDFs, includeBanners: false)
        guard exportDoc.pageCount > 0 else {
            exportError = ExportError(message: "There are no pages to export.")
            return
        }

        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "\(safeFilename(document.workspace.title)) \(format.fileExtension.uppercased()) Pages"
        panel.title = "Export \(format.menuTitle)"
        panel.prompt = "Export"
        guard panel.runModal() == .OK, let folderURL = panel.url else { return }

        do {
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
            for pageIndex in 0..<exportDoc.pageCount {
                guard let page = exportDoc.page(at: pageIndex),
                      let data = imageData(for: page, format: format) else {
                    throw ExportFailure("Could not render page \(pageIndex + 1).")
                }
                let filename = "page-\(String(format: "%03d", pageIndex + 1)).\(format.fileExtension)"
                try data.write(to: folderURL.appendingPathComponent(filename), options: .atomic)
            }
        } catch {
            exportError = ExportError(message: "PDFold could not export page images: \(error.localizedDescription)")
        }
    }

    private func saveData(_ data: Data, as format: WorkspaceExportFormat) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.contentType]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "\(safeFilename(document.workspace.title)).\(format.fileExtension)"
        panel.title = "Export \(format.menuTitle)"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try data.write(to: url, options: .atomic)
        } catch {
            exportError = ExportError(message: "PDFold could not write the \(format.menuTitle) export: \(error.localizedDescription)")
        }
    }

    private func attributedTextForDocumentExport() -> NSAttributedString {
        let output = NSMutableAttributedString()
        let headingAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 18),
            .foregroundColor: NSColor.labelColor
        ]
        let bodyAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.labelColor
        ]

        for (index, item) in loadedPDFs.enumerated() {
            if index > 0 {
                output.append(NSAttributedString(string: "\n\n"))
            }
            output.append(NSAttributedString(string: item.0.displayName + "\n", attributes: headingAttributes))
            output.append(NSAttributedString(string: String(repeating: "-", count: max(3, item.0.displayName.count)) + "\n\n", attributes: bodyAttributes))
            output.append(NSAttributedString(string: text(from: item.1), attributes: bodyAttributes))
        }
        return output.length == 0 ? NSAttributedString(string: " ") : output
    }

    private func plainTextForDocumentExport() -> String {
        loadedPDFs.map { member, pdf in
            "\(member.displayName)\n\(String(repeating: "=", count: max(3, member.displayName.count)))\n\n\(text(from: pdf))"
        }
        .joined(separator: "\n\n")
    }

    private func htmlForDocumentExport() -> String {
        let body = loadedPDFs.map { member, pdf in
            """
            <section>
              <h1>\(htmlEscaped(member.displayName))</h1>
              <pre>\(htmlEscaped(text(from: pdf)))</pre>
            </section>
            """
        }
        .joined(separator: "\n")

        return """
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <title>\(htmlEscaped(document.workspace.title))</title>
          <style>
            body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; margin: 48px; color: #111; }
            section { margin-bottom: 40px; }
            h1 { font-size: 22px; margin-bottom: 12px; }
            pre { white-space: pre-wrap; font: 13px/1.5 ui-monospace, SFMono-Regular, Menlo, monospace; }
          </style>
        </head>
        <body>
        \(body)
        </body>
        </html>
        """
    }

    private func text(from pdf: PDFDocument) -> String {
        var parts: [String] = []
        for pageIndex in 0..<pdf.pageCount {
            if let pageText = pdf.page(at: pageIndex)?.string?.trimmingCharacters(in: .whitespacesAndNewlines),
               !pageText.isEmpty {
                parts.append(pageText)
            }
        }
        return parts.joined(separator: "\n\n")
    }

    private func imageData(for page: PDFPage, format: WorkspaceExportFormat) -> Data? {
        let bounds = page.bounds(for: .mediaBox)
        let scale: CGFloat = 2
        let pixelWidth = max(1, Int(bounds.width * scale))
        let pixelHeight = max(1, Int(bounds.height * scale))
        let alpha = format == .png

        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelWidth,
            pixelsHigh: pixelHeight,
            bitsPerSample: 8,
            samplesPerPixel: alpha ? 4 : 3,
            hasAlpha: alpha,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            NSGraphicsContext.restoreGraphicsState()
            return nil
        }
        NSGraphicsContext.current = context
        context.cgContext.setFillColor(NSColor.white.cgColor)
        context.cgContext.fill(CGRect(x: 0, y: 0, width: CGFloat(pixelWidth), height: CGFloat(pixelHeight)))
        context.cgContext.scaleBy(x: scale, y: scale)
        context.cgContext.translateBy(x: -bounds.minX, y: -bounds.minY)
        page.draw(with: .mediaBox, to: context.cgContext)
        NSGraphicsContext.restoreGraphicsState()

        switch format {
        case .png:
            return bitmap.representation(using: .png, properties: [:])
        case .jpeg:
            return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.9])
        case .pdf, .word, .text, .html:
            return nil
        }
    }

    private func htmlEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private func safeFilename(_ value: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>").union(.controlCharacters)
        let filtered = value.unicodeScalars.map { invalid.contains($0) ? "-" : String($0) }.joined()
        let trimmed = filtered.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "PDFold Export" : trimmed
    }

    private struct ExportFailure: LocalizedError {
        var errorDescription: String?

        init(_ message: String) {
            errorDescription = message
        }
    }

    // MARK: - Page operations (all keyed by PageRef.id, all undoable)

    func rotatePage(_ ref: PageRef, by degrees: Int) {
        guard let (mi, pdf) = memberPDF(for: ref),
              let localIdx = localIndex(ref: ref, memberIndex: mi),
              let page = pdf.page(at: localIdx) else { return }
        let before = page.rotation
        page.rotation = (page.rotation + degrees + 360) % 360
        rebuild()
        undoManager?.registerUndo(withTarget: self) { vm in
            page.rotation = before
            vm.rebuild()
        }
        undoManager?.setActionName("Rotate Page")
    }

    func deletePage(_ ref: PageRef) {
        guard let (mi, pdf) = memberPDF(for: ref),
              let localIdx = localIndex(ref: ref, memberIndex: mi),
              pdf.page(at: localIdx) != nil else { return }

        let snapshot = captureOrderSnapshot()
        pdf.removePage(at: localIdx)
        document.workspace.pageOrder.removeAll { $0.id == ref.id }
        document.workspace.documents[mi].pageRefs.removeAll { $0 == ref.id }

        // Drop empty member
        if document.workspace.documents[mi].pageRefs.isEmpty {
            loadedPDFs.remove(at: mi)
            document.workspace.documents.remove(at: mi)
        } else {
            loadedPDFs[mi].0 = document.workspace.documents[mi]
        }
        rebuild()

        undoManager?.registerUndo(withTarget: self) { vm in
            vm.restore(snapshot)
        }
        undoManager?.setActionName("Delete Page")
    }

    func movePage(_ ref: PageRef, toIndex destination: Int) {
        guard let (mi, pdf) = memberPDF(for: ref),
              let localIdx = localIndex(ref: ref, memberIndex: mi),
              let page = pdf.page(at: localIdx) else { return }

        let snapshot = captureOrderSnapshot()
        // Move in PDFDocument
        pdf.removePage(at: localIdx)
        let adjustedDest = destination > localIdx ? destination - 1 : destination
        pdf.insert(page, at: min(adjustedDest, pdf.pageCount))

        // Update pageRefs array for that member
        var refs = document.workspace.documents[mi].pageRefs
        refs.remove(at: localIdx)
        refs.insert(ref.id, at: min(adjustedDest, refs.count))
        document.workspace.documents[mi].pageRefs = refs
        loadedPDFs[mi].0 = document.workspace.documents[mi]

        // Rebuild flat pageOrder
        rebuildPageOrder()
        rebuild()

        undoManager?.registerUndo(withTarget: self) { vm in
            vm.restore(snapshot)
        }
        undoManager?.setActionName("Move Page")
    }

    // MARK: - Annotation helpers (underline, strikeout)

    func applyMarkup(_ type: PDFAnnotationSubtype, to selection: PDFSelection) {
        selection.selectionsByLine().forEach { line in
            guard let page = line.pages.first else { return }
            let bounds = line.bounds(for: page)
            let ann = PDFAnnotation(bounds: bounds, forType: type, withProperties: nil)
            ann.color = annotationColor.withAlphaComponent(0.8)
            page.addAnnotation(ann)
            undoManager?.registerUndo(withTarget: self) { _ in page.removeAnnotation(ann) }
        }
        undoManager?.setActionName(type == .underline ? "Underline" : "Strikeout")
    }

    // MARK: - TOC synthesis

    struct TOCEntry: Identifiable {
        var id: UUID
        var title: String
        var startPageIndex: Int  // index in combinedPDF (including banner pages)
    }

    var tableOfContents: [TOCEntry] {
        var entries: [TOCEntry] = []
        var combinedIdx = 0
        for member in document.workspace.documents {
            entries.append(TOCEntry(id: member.id, title: member.displayName, startPageIndex: combinedIdx))
            combinedIdx += 1 + member.pageRefs.count  // 1 banner + N pages
        }
        return entries
    }

    // MARK: - Print

    func printWorkspace(pdfView: PDFView) {
        let info = NSPrintInfo.shared
        info.horizontalPagination = .fit
        info.verticalPagination = .fit
        info.isHorizontallyCentered = true
        info.isVerticallyCentered = false
        let op = NSPrintOperation(view: pdfView, printInfo: info)
        op.showsPrintPanel = true
        op.run()
    }

    // MARK: - Page lookup helpers

    private func memberPDF(for ref: PageRef) -> (Int, PDFDocument)? {
        guard let mi = document.workspace.documents.firstIndex(where: { $0.id == ref.memberDocId }),
              mi < loadedPDFs.count else { return nil }
        return (mi, loadedPDFs[mi].1)
    }

    private func localIndex(ref: PageRef, memberIndex mi: Int) -> Int? {
        document.workspace.documents[mi].pageRefs.firstIndex(of: ref.id)
    }
}
