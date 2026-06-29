import SwiftUI
import PDFKit
import Observation

enum AnnotationTool: String, CaseIterable, Identifiable {
    case none      = "cursor.arrow"
    case highlight = "highlighter"
    case note      = "note.text"
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
        case .ink:       return "Ink"
        case .underline: return "Underline"
        case .strikeout: return "Strikeout"
        case .signature: return "Signature"
        }
    }
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
    var pendingSignatureData: Data? = nil
    var selectedPageRefID: UUID? = nil
    var draggedPageRefID: UUID? = nil

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

    func applyHighlight(to selection: PDFSelection, color: NSColor = .yellow) {
        selection.selectionsByLine().forEach { line in
            guard let page = line.pages.first else { return }
            let bounds = line.bounds(for: page)
            let ann = PDFAnnotation(bounds: bounds, forType: .highlight, withProperties: nil)
            ann.color = color.withAlphaComponent(0.4)
            page.addAnnotation(ann)
            undoManager?.registerUndo(withTarget: self) { _ in page.removeAnnotation(ann) }
        }
        undoManager?.setActionName("Highlight")
    }

    func addNote(at pagePoint: CGPoint, on page: PDFPage) {
        let size: CGFloat = 24
        let bounds = CGRect(x: pagePoint.x - size / 2, y: pagePoint.y - size / 2,
                            width: size, height: size)
        let ann = PDFAnnotation(bounds: bounds, forType: .text, withProperties: nil)
        ann.contents = ""
        ann.color = .yellow
        page.addAnnotation(ann)
        undoManager?.registerUndo(withTarget: self) { _ in page.removeAnnotation(ann) }
        undoManager?.setActionName("Add Note")
    }

    func addInkStroke(path: NSBezierPath, on page: PDFPage, color: NSColor = NSColor.systemBlue) {
        let bounds = path.bounds.insetBy(dx: -2, dy: -2)
        let ann = PDFAnnotation(bounds: bounds, forType: .ink, withProperties: nil)
        ann.color = color
        ann.border = PDFBorder()
        ann.border?.lineWidth = 2
        // Store path points via the PDF annotation dictionary
        let flatPoints = bezierPathToFlatPoints(path)
        ann.setValue(flatPoints, forAnnotationKey: PDFAnnotationKey(rawValue: "/InkList"))
        page.addAnnotation(ann)
        undoManager?.registerUndo(withTarget: self) { _ in page.removeAnnotation(ann) }
        undoManager?.setActionName("Ink Stroke")
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
        guard !query.isEmpty else { return }
        combinedPDF.cancelFindString()
        let results = combinedPDF.findString(query, withOptions: .caseInsensitive)
        searchResults = results
    }

    // MARK: - Export

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

    // MARK: - .pdfold bundle export

    func exportPDFoldBundle() {
        // 1. Build the plain concatenated PDF
        let plainDoc = engine.concatenate(documents: loadedPDFs, includeBanners: false)
        guard let pdfData = plainDoc.dataRepresentation() else {
            exportError = ExportError(message: "PDFold could not prepare the PDF data for export.")
            return
        }

        // 2. Build the manifest — page counts must sum exactly to total
        let manifestDocs = document.workspace.documents.map { member in
            PDFoldManifest.ManifestDocument(
                id: member.id.uuidString,
                name: member.displayName,
                pageCount: member.pageRefs.count
            )
        }
        let manifest = PDFoldManifest(
            title: document.workspace.title,
            documents: manifestDocs
        )
        guard let manifestData = try? JSONEncoder().encode(manifest),
              manifest.isValid(totalPages: plainDoc.pageCount) else {
            exportError = ExportError(message: "PDFold could not build a valid bundle manifest.")
            return
        }

        // 3. Embed manifest via incremental update
        guard let bundleData = PDFAttachmentWriter.embed(
            attachmentData: manifestData,
            filename: "pdfold-manifest.json",
            mimeType: "application/json",
            in: pdfData
        ) else {
            exportError = ExportError(message: "PDFold could not embed the workspace manifest in this PDF.")
            return
        }

        // 4. Save
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "\(document.workspace.title).pdfold"
        panel.title = "Export PDFold Bundle"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try bundleData.write(to: url, options: .atomic)
        } catch {
            exportError = ExportError(message: "PDFold could not write the PDFold bundle: \(error.localizedDescription)")
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

    func applyMarkup(_ type: PDFAnnotationSubtype, to selection: PDFSelection, color: NSColor = .systemBlue) {
        selection.selectionsByLine().forEach { line in
            guard let page = line.pages.first else { return }
            let bounds = line.bounds(for: page)
            let ann = PDFAnnotation(bounds: bounds, forType: type, withProperties: nil)
            ann.color = color.withAlphaComponent(0.8)
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
