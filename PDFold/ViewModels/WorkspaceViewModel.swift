import SwiftUI
import PDFKit
import AppKit
import Observation
import UniformTypeIdentifiers

enum WorkspaceExportFormat: String, CaseIterable, Identifiable {
    case pdf
    case word
    case text
    case markdown
    case html
    case png
    case jpeg

    var id: String { rawValue }

    var menuTitle: String {
        switch self {
        case .pdf: return "PDF (.pdf)"
        case .word: return "Word (.docx)"
        case .text: return "Text (.txt)"
        case .markdown: return "Markdown (.md)"
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
        case .markdown: return "md"
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
        case .markdown: return .markdown
        case .html: return .html
        case .png: return .png
        case .jpeg: return .jpeg
        }
    }

    var exportsDirectory: Bool {
        switch self {
        case .png, .jpeg: return true
        case .pdf, .word, .text, .markdown, .html: return false
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
        case .editText:  return "Replace Text"
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
        case .editText:  return "Click a word to place a matched replacement, or click blank space to add text."
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
    var currentTool: AnnotationTool = .none {
        didSet { if oldValue != currentTool { selectedAnnotation = nil } }
    }
    var isShowingSearch = false
    var isShowingSignaturePalette = false
    var searchQuery = ""
    var searchResults: [PDFSelection] = []
    var searchResultIndex: Int = -1
    var pendingSignatureData: Data? = nil
    var selectedPageRefID: UUID? = nil
    var draggedPageRefID: UUID? = nil
    var editingStatus: EditingStatus? = nil

    // MARK: - Annotation colors (curated palette)
    var annotationColor: NSColor = .dsAnnotationYellow   // highlight, note, underline, strikeout
    var inkColor: NSColor = .dsInk                        // ink strokes

    // MARK: - Annotation selection (for Delete key deletion)
    var selectedAnnotation: PDFAnnotation? = nil

    // MARK: - Canvas state (updated by PDFView via Coordinator)
    var currentPageNumber: Int = 0
    var pageCount: Int = 0
    private(set) var lastProcessingValidation: PDFProcessingValidation? = nil

    /// In-memory map from MemberDocument.id to the URL it was imported from.
    /// Used by saveFlattenedPDF to default the save-panel name to the original filename.
    private var memberSourceURLs: [UUID: URL] = [:]

    /// Reactive list of member documents — backed by loadedPDFs so the sidebar
    /// re-renders whenever documents are added, removed, or reordered.
    var memberDocuments: [MemberDocument] { loadedPDFs.map { $0.0 } }

    weak var undoManager: UndoManager?

    private let engine: PDFEngine
    private let processingEngine: PDFProcessingEngine
    private let textAnalysisEngine = PDFTextAnalysisEngine()
    private var textAnalysisCache: [UUID: PDFTextPageAnalysis] = [:]
    /// Raw PDF bytes captured ONCE when each member is first loaded or attached.
    /// Never mutated during editing — used as the immutable base for page regeneration
    /// so multiple edits on the same page always start from the original content.
    private var originalMemberPDFData: [UUID: Data] = [:]
    static let textReplacementAnnotationKey = PDFAnnotationKey(rawValue: "/PDFoldTextReplacement")
    static let draftTextAnnotationKey = PDFAnnotationKey(rawValue: "/PDFoldDraftText")

    struct ImportError: Identifiable {
        let id = UUID()
        var fileName: String
        var message: String
    }

    struct ExportError: Identifiable {
        let id = UUID()
        var message: String
    }

    struct EditingStatus: Identifiable, Equatable {
        let id = UUID()
        var message: String
        var isError: Bool

        static func warning(_ message: String) -> EditingStatus {
            EditingStatus(message: message, isError: false)
        }

        static func error(_ message: String) -> EditingStatus {
            EditingStatus(message: message, isError: true)
        }

        static func == (lhs: EditingStatus, rhs: EditingStatus) -> Bool {
            lhs.id == rhs.id &&
            lhs.message == rhs.message &&
            lhs.isError == rhs.isError
        }
    }

    // MARK: - Init

    init(
        document: WorkspaceDocument,
        engine: PDFEngine = PDFKitEngine(),
        processingEngine: PDFProcessingEngine = PDFiumProcessingEngine()
    ) {
        self.document = document
        self.engine = engine
        self.processingEngine = processingEngine

        // Reconstruct loadedPDFs from saved package data (document open path)
        for member in document.workspace.documents {
            if let data = document.memberPDFData[member.id],
               let pdf = PDFDocument(data: data) {
                smokeValidatePDFData(data)
                sanitizeInkAnnotations(in: pdf)
                loadedPDFs.append((member, pdf))
                // Capture original (pre-edit) bytes exactly once for clean regeneration.
                originalMemberPDFData[member.id] = data
            }
        }

        // Snapshot hook: bake live annotation state before each save
        document.currentPDFDataProvider = { [weak self] in
            guard let self else { return [:] }
            var result: [UUID: Data] = [:]
            for (member, pdf) in self.loadedPDFs {
                if let data = PDFSerializer.data(from: pdf) {
                    result[member.id] = data
                } else if let existingData = self.document.memberPDFData[member.id] {
                    // Surface a blocking, actionable error — do not silently drop edits.
                    self.exportError = ExportError(
                        message: "pdFold couldn\u{2019}t serialize \u{201C}\(member.displayName)\u{201D}; your edits to it weren\u{2019}t saved. Use \u{201C}Save as PDF\u{2026}\u{201D} (\u{2318}\u{21E7}S) to preserve your work."
                    )
                    result[member.id] = existingData
                }
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
        smokeValidatePDFData(pdf.dataRepresentation(), password: password)
        attachPDF(pdf, from: url)
        pendingPasswordPDF = nil
        rebuild()
        return true
    }

    private func attachPDF(_ pdf: PDFDocument, from url: URL) {
        sanitizeInkAnnotations(in: pdf)

        guard let data = PDFSerializer.data(from: pdf) else {
            importError = ImportError(
                fileName: url.lastPathComponent,
                message: "pdFold could not prepare this file for saving. Try exporting it to PDF first, then import the exported file."
            )
            return
        }
        smokeValidatePDFData(data)

        let name = url.deletingPathExtension().lastPathComponent
        var member = MemberDocument(displayName: name, sourcePDFRef: url.lastPathComponent)
        let refs = (0..<pdf.pageCount).map { i in PageRef(memberDocId: member.id, sourcePageIndex: i) }
        member.pageRefs = refs.map(\.id)
        document.workspace.documents.append(member)
        document.workspace.pageOrder.append(contentsOf: refs)
        document.memberPDFData[member.id] = data
        originalMemberPDFData[member.id] = data
        memberSourceURLs[member.id] = url
        loadedPDFs.append((member, pdf))
    }

    private func smokeValidatePDFData(_ data: Data?, password: String? = nil) {
        guard let data else {
            lastProcessingValidation = nil
            return
        }
        do {
            lastProcessingValidation = try processingEngine.validatePDF(data: data, password: password)
        } catch {
            lastProcessingValidation = nil
        }
    }

    func rebuild() {
        combinedPDF = engine.concatenate(documents: loadedPDFs, includeBanners: true)
        pageCount = document.workspace.pageOrder.count
        // PDFSelections are bound to the old document; drop them so search navigation
        // doesn't jump to pages in a detached doc.
        searchResults = []
        searchResultIndex = -1
    }

    func combinedPageIndex(forWorkspacePageNumber pageNumber: Int) -> Int? {
        guard pageNumber >= 1, pageNumber <= pageCount else { return nil }
        var workspacePageNumber = 0
        for combinedIndex in 0..<combinedPDF.pageCount {
            guard let page = combinedPDF.page(at: combinedIndex),
                  !(page is BoundaryPage) else { continue }
            workspacePageNumber += 1
            if workspacePageNumber == pageNumber {
                return combinedIndex
            }
        }
        return nil
    }

    func workspacePageNumber(for page: PDFPage, in document: PDFDocument) -> Int {
        guard pageCount > 0 else { return 0 }
        let combinedIndex = document.index(for: page)
        guard combinedIndex != NSNotFound else { return 1 }

        var realPagesThroughCurrentPosition = 0
        for index in 0...combinedIndex {
            if let candidate = document.page(at: index),
               !(candidate is BoundaryPage) {
                realPagesThroughCurrentPosition += 1
            }
        }

        if page is BoundaryPage {
            return min(max(realPagesThroughCurrentPosition + 1, 1), pageCount)
        }
        return min(max(realPagesThroughCurrentPosition, 1), pageCount)
    }

    // MARK: - Reorder / Remove (with undo)

    func moveDocument(from source: IndexSet, to destination: Int) {
        let validSource = source.filter { loadedPDFs.indices.contains($0) }
        guard validSource.count == source.count,
              destination >= 0,
              destination <= loadedPDFs.count else { return }

        let snapshot = captureOrderSnapshot()
        loadedPDFs.move(fromOffsets: IndexSet(validSource), toOffset: destination)
        let loadedIds = Set(loadedPDFs.map(\.0.id))
        let unloadedDocuments = document.workspace.documents.filter { !loadedIds.contains($0.id) }
        document.workspace.documents = loadedPDFs.map(\.0) + unloadedDocuments
        rebuildPageOrder()
        rebuild()
        registerUndo(snapshot: snapshot, actionName: "Move Document")
    }

    func removeDocument(at offsets: IndexSet) {
        let validOffsets = offsets.filter { loadedPDFs.indices.contains($0) }
        guard validOffsets.count == offsets.count else { return }

        let snapshot = captureOrderSnapshot()
        let removedIds = Set(validOffsets.map { loadedPDFs[$0].0.id })
        let removedPageRefIDs = Set(document.workspace.documents
            .filter { removedIds.contains($0.id) }
            .flatMap(\.pageRefs))
        document.workspace.documents.removeAll { removedIds.contains($0.id) }
        document.workspace.pageEditStates.removeAll { removedPageRefIDs.contains($0.pageRefID) }
        removedIds.forEach { document.memberPDFData.removeValue(forKey: $0) }
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
            if let data = PDFSerializer.data(from: pdf) {
                result[member.id] = data
            } else if let existingData = document.memberPDFData[member.id] {
                result[member.id] = existingData
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

    // MARK: - Workspace metadata

    func addTag(_ rawValue: String) {
        let tag = normalizedTag(rawValue)
        guard !tag.isEmpty,
              !document.workspace.tags.contains(where: { $0.localizedCaseInsensitiveCompare(tag) == .orderedSame }) else {
            return
        }
        document.workspace.tags.append(tag)
        markWorkspaceModified()
        undoManager?.registerUndo(withTarget: self) { vm in
            vm.removeTag(tag)
        }
        undoManager?.setActionName("Add Tag")
    }

    func removeTag(_ tag: String) {
        guard let index = document.workspace.tags.firstIndex(of: tag) else { return }
        let removed = document.workspace.tags.remove(at: index)
        markWorkspaceModified()
        undoManager?.registerUndo(withTarget: self) { vm in
            vm.document.workspace.tags.insert(removed, at: min(index, vm.document.workspace.tags.count))
            vm.markWorkspaceModified()
        }
        undoManager?.setActionName("Remove Tag")
    }

    func addComment(_ rawBody: String) {
        let body = rawBody.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        let comment = WorkspaceComment(body: body)
        document.workspace.comments.insert(comment, at: 0)
        markWorkspaceModified()
        undoManager?.registerUndo(withTarget: self) { vm in
            vm.removeComment(comment)
        }
        undoManager?.setActionName("Add Comment")
    }

    func removeComment(_ comment: WorkspaceComment) {
        guard let index = document.workspace.comments.firstIndex(where: { $0.id == comment.id }) else { return }
        let removed = document.workspace.comments.remove(at: index)
        markWorkspaceModified()
        undoManager?.registerUndo(withTarget: self) { vm in
            vm.document.workspace.comments.insert(removed, at: min(index, vm.document.workspace.comments.count))
            vm.markWorkspaceModified()
        }
        undoManager?.setActionName("Remove Comment")
    }

    private func normalizedTag(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
    }

    private func markWorkspaceModified() {
        document.workspace.modifiedAt = Date()
    }

    func markAnnotationsModified() {
        markWorkspaceModified()
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
        guard movePage(sourceRef, toIndex: destination) else {
            self.draggedPageRefID = nil
            return false
        }
        selectedPageRefID = sourceRef.id
        self.draggedPageRefID = nil
        return true
    }

    // MARK: - Annotations

    func editableTextBlock(at pagePoint: CGPoint, on page: PDFPage, in pdfDocument: PDFDocument?) -> (pageRef: PageRef, block: EditableTextBlock)? {
        guard let ref = pageRef(for: page, in: pdfDocument),
              let lookup = memberPDF(for: ref),
              let localIdx = localIndex(ref: ref, memberIndex: lookup.documentIndex) else {
            return nil
        }
        // If the click lands inside a previously-placed replacement (editedBounds) or the
        // original source area (sourceBounds), re-route to that operation so the editor
        // opens with the current replacement text and updates the op in-place rather than
        // accumulating a second operation for the same location.
        if let pageState = document.workspace.pageEditStates.first(where: { $0.pageRefID == ref.id }),
           let existingOp = pageState.operations.first(where: {
               $0.editedBounds.insetBy(dx: -3, dy: -3).contains(pagePoint) ||
               $0.sourceBounds.insetBy(dx: -2, dy: -2).contains(pagePoint)
           }) {
            let syntheticBlock = EditableTextBlock(
                id: existingOp.sourceBlockID,
                pageRefID: ref.id,
                text: existingOp.replacementText,
                bounds: existingOp.editedBounds,
                lines: [],
                fontName: existingOp.fontName,
                fontSize: existingOp.fontSize,
                textColor: existingOp.textColor,
                rotation: 0,
                baseline: existingOp.editedBounds.minY,
                confidence: .high
            )
            return (ref, syntheticBlock)
        }
        let analysis = textAnalysis(for: ref, page: page, memberID: ref.memberDocId, localIndex: localIdx)
        let block = textAnalysisEngine.hitTest(pagePoint, in: analysis) ?? insertionTextBlock(at: pagePoint, pageRefID: ref.id, page: page)
        return (ref, block)
    }

    private func insertionTextBlock(at pagePoint: CGPoint, pageRefID: UUID, page: PDFPage) -> EditableTextBlock {
        let pageBounds = page.bounds(for: .cropBox)
        let width = min(max(pageBounds.width * 0.34, 180), 320)
        let height: CGFloat = 24
        var bounds = CGRect(
            x: pagePoint.x,
            y: pagePoint.y - height,
            width: width,
            height: height
        )
        if bounds.maxX > pageBounds.maxX - 12 {
            bounds.origin.x = max(pageBounds.minX + 12, pageBounds.maxX - width - 12)
        }
        if bounds.minX < pageBounds.minX + 12 {
            bounds.origin.x = pageBounds.minX + 12
        }
        if bounds.minY < pageBounds.minY + 12 {
            bounds.origin.y = pageBounds.minY + 12
        }
        if bounds.maxY > pageBounds.maxY - 12 {
            bounds.origin.y = pageBounds.maxY - height - 12
        }
        return EditableTextBlock(
            pageRefID: pageRefID,
            text: "",
            bounds: bounds,
            lines: [],
            fontName: "Helvetica",
            fontSize: 14,
            textColor: .documentText,
            rotation: CGFloat(page.rotation),
            baseline: bounds.minY,
            confidence: .medium
        )
    }

    @discardableResult
    func applyInlineTextEdit(
        pageRef: PageRef,
        sourceBlock: EditableTextBlock,
        replacementText: String,
        editedBounds: CGRect,
        fontName: String,
        fontSize: CGFloat,
        textColor: NSColor,
        alignment: NSTextAlignment
    ) -> Bool {
        guard let lookup = memberPDF(for: pageRef),
              let localIdx = localIndex(ref: pageRef, memberIndex: lookup.documentIndex),
              lookup.pdf.page(at: localIdx) != nil else {
            showEditMessage("pdFold could not locate that page for inline editing.", isError: true)
            return false
        }
        // Always regenerate from the original (pre-edit) page so that multiple edits on
        // the same page don't stack erase patches on top of previously-regenerated content.
        // Fall back to current memberPDFData if the original snapshot is unavailable.
        let baseData = originalMemberPDFData[pageRef.memberDocId] ?? document.memberPDFData[pageRef.memberDocId]
        guard let baseData,
              let basePDF = PDFDocument(data: baseData),
              let basePage = basePDF.page(at: localIdx) else {
            showEditMessage("pdFold could not access the original page for editing.", isError: true)
            return false
        }

        let previousPDFData = currentPDFData()
        let previousEditStates = document.workspace.pageEditStates
        var operation = PDFTextEditOperation(
            pageRefID: pageRef.id,
            sourceBlockID: sourceBlock.id,
            sourceBounds: sourceBlock.bounds,
            editedBounds: editedBounds,
            replacementText: replacementText,
            fontName: fontName,
            fontSize: fontSize,
            textColor: CodableColor(nsColor: textColor),
            alignment: CodableTextAlignment(alignment)
        )
        // When updating an existing op (same sourceBlockID), preserve the original
        // sourceBounds so the erase patch targets the true original text location even
        // when the user re-edits a previously-placed replacement.
        if let stateIndex = document.workspace.pageEditStates.firstIndex(where: { $0.pageRefID == pageRef.id }),
           let existingOp = document.workspace.pageEditStates[stateIndex].operations.first(where: { $0.sourceBlockID == sourceBlock.id }) {
            operation.sourceBounds = existingOp.sourceBounds
        }
        operation.editedBounds = PDFEditedPageRenderer.measuredBounds(for: operation)
        if let stateIndex = document.workspace.pageEditStates.firstIndex(where: { $0.pageRefID == pageRef.id }) {
            document.workspace.pageEditStates[stateIndex].operations.removeAll { $0.sourceBlockID == sourceBlock.id }
            document.workspace.pageEditStates[stateIndex].operations.append(operation)
        } else {
            document.workspace.pageEditStates.append(PageEditState(pageRefID: pageRef.id, operations: [operation]))
        }
        guard let operations = document.workspace.pageEditStates.first(where: { $0.pageRefID == pageRef.id })?.operations,
              let regenerated = PDFEditedPageRenderer.regeneratedPage(from: basePage, applying: operations) else {
            document.workspace.pageEditStates = previousEditStates
            showEditMessage("pdFold could not regenerate that edited page. The original page is unchanged.", isError: true)
            return false
        }

        // Regeneration always rebuilds from the pristine original page (so repeated edits
        // never stack erase patches on top of each other), which would otherwise silently
        // drop any highlight/note/ink/text-box annotations already placed on this page.
        // Carry those over onto the freshly regenerated page.
        let preservedAnnotations = lookup.pdf.page(at: localIdx)?.annotations ?? []
        lookup.pdf.removePage(at: localIdx)
        lookup.pdf.insert(regenerated, at: localIdx)
        preservedAnnotations.forEach { regenerated.addAnnotation($0) }
        textAnalysisCache.removeValue(forKey: pageRef.id)

        // Serialize the mutated member PDF and load a completely fresh
        // PDFDocument from those bytes before calling rebuild(). This
        // gives PDFKit brand-new PDFPage objects so it cannot reuse
        // any render cache from the previous version of the page.
        let serialized = PDFSerializer.data(from: lookup.pdf)
        if let serialized, let freshPDF = PDFDocument(data: serialized) {
            document.memberPDFData[pageRef.memberDocId] = serialized
            loadedPDFs[lookup.documentIndex] = (loadedPDFs[lookup.documentIndex].0, freshPDF)
        } else {
            NSLog("[PDFold] Warning: could not reload fresh PDF after inline edit on page %@; using mutated document in place.", pageRef.id.uuidString)
            if let serialized {
                document.memberPDFData[pageRef.memberDocId] = serialized
            }
        }

        rebuild()
        markWorkspaceModified()

        undoManager?.registerUndo(withTarget: self) { vm in
            vm.document.workspace.pageEditStates = previousEditStates
            vm.document.memberPDFData = previousPDFData
            vm.loadedPDFs = vm.document.workspace.documents.compactMap { member in
                guard let data = previousPDFData[member.id],
                      let pdf = PDFDocument(data: data) else { return nil }
                return (member, pdf)
            }
            vm.textAnalysisCache.removeAll()
            vm.rebuild()
        }
        undoManager?.setActionName("Edit PDF Text")
        return true
    }

    func applyHighlight(to selection: PDFSelection) {
        selection.selectionsByLine().forEach { line in
            guard let page = line.pages.first else { return }
            let bounds = line.bounds(for: page)
            let ann = PDFAnnotation(bounds: bounds, forType: .highlight, withProperties: nil)
            ann.color = annotationColor.withAlphaComponent(0.4)
            page.addAnnotation(ann)
            undoManager?.registerUndo(withTarget: self) { _ in page.removeAnnotation(ann) }
        }
        markAnnotationsModified()
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
        ann.setValue(true, forAnnotationKey: Self.draftTextAnnotationKey)
        page.addAnnotation(ann)
        markAnnotationsModified()
        undoManager?.registerUndo(withTarget: self) { _ in page.removeAnnotation(ann) }
        undoManager?.setActionName("Add Note")
        return ann
    }

    @discardableResult
    func addTextBox(at pagePoint: CGPoint, on page: PDFPage) -> PDFAnnotation? {
        let bounds = PDFEditingSupport.textBoxBounds(
            centeredAt: pagePoint,
            pageBounds: page.bounds(for: .cropBox)
        )
        guard PDFEditingSupport.isValidPDFBounds(bounds) else {
            showEditWarning(.invalidAnnotationBounds)
            return nil
        }
        let ann = PDFAnnotation(bounds: bounds, forType: .freeText, withProperties: nil)
        ann.contents = ""
        ann.font = .systemFont(ofSize: 16)
        ann.fontColor = .dsTextPrimaryNS
        ann.color = .clear
        ann.alignment = .left
        ann.setValue(true, forAnnotationKey: Self.draftTextAnnotationKey)
        let border = PDFBorder()
        border.lineWidth = 0
        ann.border = border
        page.addAnnotation(ann)
        markAnnotationsModified()
        undoManager?.registerUndo(withTarget: self) { _ in page.removeAnnotation(ann) }
        undoManager?.setActionName("Add Text Box")
        return ann
    }

    @discardableResult
    func addEditableTextOverlay(from selection: PDFSelection, on page: PDFPage) -> PDFAnnotation? {
        guard let plan = PDFEditingSupport.replacementPlan(
            text: selection.string,
            selectionBounds: selection.bounds(for: page),
            attributedString: selection.attributedString,
            pageBounds: page.bounds(for: .cropBox)
        ) else {
            showEditWarning(.emptySelection)
            return nil
        }
        if let blockingWarning = plan.warnings.first(where: { warning in
            warning == .invalidSelectionBounds || warning == .invalidAnnotationBounds
        }) {
            showEditWarning(blockingWarning)
            return nil
        }
        plan.warnings.forEach(showEditWarning)
        guard plan.shouldUseReplacementBackground else {
            showEditWarning(.unsupportedReplacement)
            return nil
        }

        let ann = PDFAnnotation(bounds: plan.bounds, forType: .freeText, withProperties: nil)
        ann.contents = plan.text
        ann.font = plan.style.font
        ann.fontColor = plan.style.textColor
        ann.alignment = plan.style.alignment
        ann.color = PDFEditingSupport.replacementBackgroundColor(
            isReplacement: true,
            originalBackground: plan.style.backgroundColor == .clear ? nil : plan.style.backgroundColor
        )
        ann.setValue(true, forAnnotationKey: Self.textReplacementAnnotationKey)
        let border = PDFBorder()
        border.lineWidth = 0
        ann.border = border
        page.addAnnotation(ann)
        markAnnotationsModified()
        undoManager?.registerUndo(withTarget: self) { _ in page.removeAnnotation(ann) }
        undoManager?.setActionName("Replace PDF Text")
        return ann
    }

    func showEditWarning(_ warning: PDFTextEditWarning) {
        editingStatus = .warning(warning.message)
    }

    func showEditMessage(_ message: String, isError: Bool = false) {
        editingStatus = isError ? .error(message) : .warning(message)
    }

    func addInkStroke(path: NSBezierPath, on page: PDFPage) {
        guard path.elementCount > 1, !path.bounds.isEmpty else { return }
        let bounds = path.bounds.insetBy(dx: -2, dy: -2)
        let ann = PDFAnnotation(bounds: bounds, forType: .ink, withProperties: nil)
        ann.color = inkColor
        ann.border = PDFBorder()
        ann.border?.lineWidth = 2
        ann.add(path)
        page.addAnnotation(ann)
        markAnnotationsModified()
        undoManager?.registerUndo(withTarget: self) { _ in page.removeAnnotation(ann) }
        undoManager?.setActionName("Ink Stroke")
    }

    func deleteSelectedAnnotation() {
        guard let ann = selectedAnnotation, let page = ann.page else {
            showEditWarning(.annotationCreationFailed)
            return
        }
        page.removeAnnotation(ann)
        selectedAnnotation = nil
        markAnnotationsModified()
        undoManager?.registerUndo(withTarget: self) { vm in
            page.addAnnotation(ann)
            vm.selectedAnnotation = ann
        }
        undoManager?.setActionName("Delete Annotation")
    }

    private func sanitizeInkAnnotations(in pdf: PDFDocument) {
        for pageIndex in 0..<pdf.pageCount {
            guard let page = pdf.page(at: pageIndex) else { continue }
            for annotation in page.annotations where annotation.type == "Ink" {
                guard let replacement = replacementInkAnnotation(for: annotation) else { continue }
                page.removeAnnotation(annotation)
                page.addAnnotation(replacement)
            }
        }
    }

    private func replacementInkAnnotation(for annotation: PDFAnnotation) -> PDFAnnotation? {
        let inkListKey = PDFAnnotationKey(rawValue: "/InkList")
        guard let inkList = annotation.value(forAnnotationKey: inkListKey) else { return nil }

        if let paths = inkList as? [NSBezierPath], !paths.isEmpty {
            return nil
        }

        let rawStrokes: [Any]
        if let strokes = inkList as? [Any] {
            rawStrokes = strokes
        } else if let strokes = inkList as? NSArray {
            rawStrokes = strokes.map { $0 }
        } else {
            rawStrokes = []
        }

        let paths = rawStrokes.compactMap { bezierPath(fromInkListStroke: $0) }
        guard !paths.isEmpty else { return nil }

        let replacement = PDFAnnotation(bounds: annotation.bounds, forType: .ink, withProperties: nil)
        replacement.color = annotation.color
        replacement.border = annotation.border
        replacement.contents = annotation.contents
        paths.forEach { replacement.add($0) }
        return replacement
    }

    private func bezierPath(fromInkListStroke stroke: Any) -> NSBezierPath? {
        let numbers: [NSNumber]
        if let values = stroke as? [NSNumber] {
            numbers = values
        } else if let values = stroke as? [CGFloat] {
            numbers = values.map { NSNumber(value: Double($0)) }
        } else if let values = stroke as? [Double] {
            numbers = values.map { NSNumber(value: $0) }
        } else if let values = stroke as? NSArray {
            numbers = values.compactMap { $0 as? NSNumber }
        } else {
            return nil
        }

        guard numbers.count >= 4, numbers.count.isMultiple(of: 2) else { return nil }

        let path = NSBezierPath()
        path.lineWidth = 2
        path.move(to: CGPoint(x: numbers[0].doubleValue, y: numbers[1].doubleValue))
        var index = 2
        while index + 1 < numbers.count {
            path.line(to: CGPoint(x: numbers[index].doubleValue, y: numbers[index + 1].doubleValue))
            index += 2
        }
        return path
    }

    // MARK: - Signature

    func placeSignature(imageData: Data, at pagePoint: CGPoint, on page: PDFPage, size: CGSize = CGSize(width: 120, height: 48)) {
        guard let refID = pageRefID(for: page) else { return }
        let bounds = CGRect(
            x: pagePoint.x - size.width / 2,
            y: pagePoint.y - size.height / 2,
            width: size.width, height: size.height
        )
        let placement = SignaturePlacement(
            pageRefId: refID,
            imageData: imageData,
            rect: bounds,
            signedAt: Date()
        )
        document.workspace.signatures.append(placement)
        markAnnotationsModified()

        // Render as a stamp annotation for display
        if let image = NSImage(data: imageData) {
            let ann = PDFAnnotation(bounds: bounds, forType: .stamp, withProperties: nil)
            ann.setValue(image, forAnnotationKey: .widgetValue)
            page.addAnnotation(ann)
            let placementID = placement.id
            undoManager?.registerUndo(withTarget: self) { vm in
                page.removeAnnotation(ann)
                vm.document.workspace.signatures.removeAll { $0.id == placementID }
            }
        } else {
            let placementID = placement.id
            undoManager?.registerUndo(withTarget: self) { vm in
                vm.document.workspace.signatures.removeAll { $0.id == placementID }
            }
        }
        undoManager?.setActionName("Place Signature")
    }

    private func pageRefID(for page: PDFPage) -> UUID? {
        // Map the PDFPage back to a PageRef.id using position in combinedPDF.
        guard let doc = page.document,
              let idx = (0..<doc.pageCount).first(where: { doc.page(at: $0) === page })
        else { return nil }
        // combinedPDF interleaves BoundaryPage banners; count only real pages.
        var realPageIdx = 0
        for i in 0..<idx {
            if !(doc.page(at: i) is BoundaryPage) { realPageIdx += 1 }
        }
        let refs = document.workspace.pageOrder
        guard realPageIdx < refs.count else { return nil }
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
        case .markdown:
            exportMarkdown()
        case .html:
            exportHTML()
        case .png, .jpeg:
            exportPageImages(as: format)
        }
    }

    func exportPlainPDF() {
        saveFlattenedPDF()
    }

    func saveFlattenedPDF(to url: URL? = nil) {
        let exportDoc = engine.concatenate(documents: loadedPDFs, includeBanners: false)
        guard let pdfData = PDFSerializer.data(from: exportDoc) else {
            exportError = ExportError(message: "pdFold could not serialize the PDF for saving. Try exporting individual documents first.")
            return
        }

        let targetURL: URL
        if let url {
            targetURL = url
        } else {
            let defaultName: String
            if loadedPDFs.count == 1,
               let sourceURL = memberSourceURLs[loadedPDFs[0].0.id] {
                defaultName = sourceURL.lastPathComponent
            } else {
                defaultName = "\(safeFilename(document.workspace.title)).pdf"
            }
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.pdf]
            panel.nameFieldStringValue = defaultName
            panel.title = "Save as PDF"
            guard panel.runModal() == .OK, let chosenURL = panel.url else { return }
            targetURL = chosenURL
        }

        do {
            try pdfData.write(to: targetURL, options: .atomic)
        } catch {
            exportError = ExportError(message: "pdFold could not save the PDF: \(error.localizedDescription)")
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
            exportError = ExportError(message: "pdFold could not create the Word export: \(error.localizedDescription)")
        }
    }

    private func exportPlainText() {
        guard let data = plainTextForDocumentExport().data(using: .utf8) else {
            exportError = ExportError(message: "pdFold could not encode the text export.")
            return
        }
        saveData(data, as: .text)
    }

    private func exportMarkdown() {
        guard let data = markdownForDocumentExport().data(using: .utf8) else {
            exportError = ExportError(message: "pdFold could not encode the Markdown export.")
            return
        }
        saveData(data, as: .markdown)
    }

    private func exportHTML() {
        let html = htmlForDocumentExport()
        guard let data = html.data(using: .utf8) else {
            exportError = ExportError(message: "pdFold could not encode the HTML export.")
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
            exportError = ExportError(message: "pdFold could not export page images: \(error.localizedDescription)")
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
            exportError = ExportError(message: "pdFold could not write the \(format.menuTitle) export: \(error.localizedDescription)")
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

    private func markdownForDocumentExport() -> String {
        let title = markdownHeadingEscaped(document.workspace.title)
        var sections: [String] = ["# \(title)"]

        var metadata: [String] = []
        metadata.append("- Documents: \(loadedPDFs.count)")
        metadata.append("- Pages: \(document.workspace.pageOrder.count)")
        if !document.workspace.tags.isEmpty {
            metadata.append("- Tags: \(document.workspace.tags.map(markdownInlineEscaped).joined(separator: ", "))")
        }
        if !document.workspace.comments.isEmpty {
            metadata.append("- Comments: \(document.workspace.comments.count)")
        }
        sections.append("""
        ## Workspace Summary

        \(metadata.joined(separator: "\n"))
        """)

        if !document.workspace.comments.isEmpty {
            let comments = document.workspace.comments.map { comment in
                "- \(markdownInlineEscaped(comment.body))"
            }
            .joined(separator: "\n")
            sections.append("""
            ## Workspace Comments

            \(comments)
            """)
        }

        let documents = loadedPDFs.map { member, pdf in
            let extractedText = markdownBodyEscaped(text(from: pdf))
            let body = extractedText.isEmpty ? "_No extractable text._" : extractedText
            return """
            ## \(markdownHeadingEscaped(member.displayName))

            \(body)
            """
        }
        sections.append(documents.isEmpty ? "## Documents\n\n_No documents in workspace._" : documents.joined(separator: "\n\n"))

        return sections.joined(separator: "\n\n") + "\n"
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
        guard bounds.width.isFinite, bounds.height.isFinite, bounds.width > 0, bounds.height > 0 else {
            return nil
        }

        let scale: CGFloat = 2
        let maxPixelDimension = 12_000
        let actualScale = min(scale, CGFloat(maxPixelDimension) / max(bounds.width, bounds.height))
        let pixelWidth = max(1, Int(bounds.width * actualScale))
        let pixelHeight = max(1, Int(bounds.height * actualScale))
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
        context.cgContext.scaleBy(x: actualScale, y: actualScale)
        context.cgContext.translateBy(x: -bounds.minX, y: -bounds.minY)
        page.draw(with: .mediaBox, to: context.cgContext)
        NSGraphicsContext.restoreGraphicsState()

        switch format {
        case .png:
            return bitmap.representation(using: .png, properties: [:])
        case .jpeg:
            return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.9])
        case .pdf, .word, .text, .markdown, .html:
            return nil
        }
    }

    private func markdownHeadingEscaped(_ value: String) -> String {
        markdownInlineEscaped(value).replacingOccurrences(of: "#", with: "\\#")
    }

    private func markdownInlineEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "[", with: "\\[")
            .replacingOccurrences(of: "]", with: "\\]")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "*", with: "\\*")
            .replacingOccurrences(of: "_", with: "\\_")
    }

    private func markdownBodyEscaped(_ value: String) -> String {
        value
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                guard line.hasPrefix("#") else { return String(line) }
                return "\\" + line
            }
            .joined(separator: "\n")
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
        return trimmed.isEmpty ? "pdFold Export" : trimmed
    }

    private struct ExportFailure: LocalizedError {
        var errorDescription: String?

        init(_ message: String) {
            errorDescription = message
        }
    }

    // MARK: - Page operations (all keyed by PageRef.id, all undoable)

    func rotatePage(_ ref: PageRef, by degrees: Int) {
        guard let lookup = memberPDF(for: ref),
              let localIdx = localIndex(ref: ref, memberIndex: lookup.documentIndex),
              let page = lookup.pdf.page(at: localIdx) else { return }
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
        guard let lookup = memberPDF(for: ref),
              let localIdx = localIndex(ref: ref, memberIndex: lookup.documentIndex),
              lookup.pdf.page(at: localIdx) != nil else { return }

        let snapshot = captureOrderSnapshot()
        let pdf = lookup.pdf
        pdf.removePage(at: localIdx)
        document.workspace.pageOrder.removeAll { $0.id == ref.id }
        document.workspace.documents[lookup.documentIndex].pageRefs.removeAll { $0 == ref.id }
        document.workspace.pageEditStates.removeAll { $0.pageRefID == ref.id }
        textAnalysisCache.removeValue(forKey: ref.id)

        // Drop empty member
        if document.workspace.documents[lookup.documentIndex].pageRefs.isEmpty {
            loadedPDFs.remove(at: lookup.loadedIndex)
            document.workspace.documents.remove(at: lookup.documentIndex)
        } else {
            loadedPDFs[lookup.loadedIndex].0 = document.workspace.documents[lookup.documentIndex]
        }
        rebuild()

        undoManager?.registerUndo(withTarget: self) { vm in
            vm.restore(snapshot)
        }
        undoManager?.setActionName("Delete Page")
    }

    @discardableResult
    func movePage(_ ref: PageRef, toIndex destination: Int) -> Bool {
        guard let lookup = memberPDF(for: ref),
              let localIdx = localIndex(ref: ref, memberIndex: lookup.documentIndex),
              let page = lookup.pdf.page(at: localIdx) else { return false }

        let snapshot = captureOrderSnapshot()
        let pdf = lookup.pdf
        // Move in PDFDocument
        pdf.removePage(at: localIdx)
        let boundedDestination = min(max(destination, 0), pdf.pageCount + 1)
        let adjustedDest = boundedDestination > localIdx ? boundedDestination - 1 : boundedDestination
        let insertIndex = min(max(adjustedDest, 0), pdf.pageCount)
        pdf.insert(page, at: insertIndex)

        // Update pageRefs array for that member
        var refs = document.workspace.documents[lookup.documentIndex].pageRefs
        refs.remove(at: localIdx)
        refs.insert(ref.id, at: min(max(adjustedDest, 0), refs.count))
        document.workspace.documents[lookup.documentIndex].pageRefs = refs
        loadedPDFs[lookup.loadedIndex].0 = document.workspace.documents[lookup.documentIndex]

        // Rebuild flat pageOrder
        rebuildPageOrder()
        rebuild()

        undoManager?.registerUndo(withTarget: self) { vm in
            vm.restore(snapshot)
        }
        undoManager?.setActionName("Move Page")
        return true
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
        markAnnotationsModified()
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

    func pageRef(for page: PDFPage, in pdfDocument: PDFDocument?) -> PageRef? {
        guard let pdfDocument else { return nil }
        let combinedIndex = pdfDocument.index(for: page)
        guard combinedIndex != NSNotFound else { return nil }
        var realPageIndex = 0
        for index in 0...combinedIndex {
            guard let candidate = pdfDocument.page(at: index),
                  !(candidate is BoundaryPage) else { continue }
            if index == combinedIndex {
                guard document.workspace.pageOrder.indices.contains(realPageIndex) else { return nil }
                return document.workspace.pageOrder[realPageIndex]
            }
            realPageIndex += 1
        }
        return nil
    }

    private func textAnalysis(for ref: PageRef, page: PDFPage, memberID: UUID, localIndex: Int) -> PDFTextPageAnalysis {
        if let cached = textAnalysisCache[ref.id] {
            return cached
        }
        // Prefer original bytes so text-block hit-testing reflects the unedited PDF content,
        // consistent with regeneration always starting from the original page.
        let data = originalMemberPDFData[memberID] ?? document.memberPDFData[memberID] ?? currentPDFData()[memberID] ?? Data()
        let analysis = textAnalysisEngine.analyze(
            data: data,
            pageIndex: localIndex,
            pageRefID: ref.id,
            fallbackPage: page
        )
        textAnalysisCache[ref.id] = analysis
        return analysis
    }

    private func memberPDF(for ref: PageRef) -> (documentIndex: Int, loadedIndex: Int, pdf: PDFDocument)? {
        guard let documentIndex = document.workspace.documents.firstIndex(where: { $0.id == ref.memberDocId }),
              let loadedIndex = loadedPDFs.firstIndex(where: { $0.0.id == ref.memberDocId }) else {
            return nil
        }
        return (documentIndex, loadedIndex, loadedPDFs[loadedIndex].1)
    }

    private func localIndex(ref: PageRef, memberIndex mi: Int) -> Int? {
        guard document.workspace.documents.indices.contains(mi) else { return nil }
        return document.workspace.documents[mi].pageRefs.firstIndex(of: ref.id)
    }
}
