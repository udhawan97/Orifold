import SwiftUI
import PDFKit
import AppKit
import Observation
import UniformTypeIdentifiers

enum WorkspaceExportFormat: String, CaseIterable, Identifiable {
    case pdf
    case word
    case legacyWord
    case odt
    case rtf
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
        case .legacyWord: return "Word 97-2004 (.doc)"
        case .odt: return "OpenDocument Text (.odt)"
        case .rtf: return "Rich Text (.rtf)"
        case .text: return "Text (.txt)"
        case .markdown: return "Markdown (.md)"
        case .html: return "HTML (.html)"
        case .png: return "PNG images (.png)"
        case .jpeg: return "JPEG images (.jpg)"
        }
    }

    var fileExtension: String {
        switch self {
        case .pdf: return "pdf"
        case .word: return "docx"
        case .legacyWord: return "doc"
        case .odt: return "odt"
        case .rtf: return "rtf"
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
        case .legacyWord: return .wordDoc
        case .odt: return .odt
        case .rtf: return .rtf
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
        case .pdf, .word, .legacyWord, .odt, .rtf, .text, .markdown, .html: return false
        }
    }
}

enum AnnotationTool: String, CaseIterable, Identifiable {
    case none      = "select"
    case highlight = "highlighter"
    case note      = "note.text"
    case comment   = "text.bubble"
    case commentRegion = "rectangle.and.text.magnifyingglass"
    case editText  = "textformat"
    case ink       = "pencil.tip"
    case eraser    = "eraser"
    case underline = "underline"
    case strikeout = "strikethrough"
    case signature = "signature"
    case stamp     = "seal"

    var id: String { rawValue }
    var label: String {
        switch self {
        case .none:      return "Select"
        case .highlight: return "Highlight"
        case .note:      return "Note"
        case .comment:   return "Comment"
        case .commentRegion: return "Region Comment"
        case .editText:  return "Edit Text"
        case .ink:       return "Ink"
        case .eraser:    return "Eraser"
        case .underline: return "Underline"
        case .strikeout: return "Strikeout"
        case .signature: return "Signature"
        case .stamp:     return "Stamp"
        }
    }

    var iconName: String {
        switch self {
        case .none:      return "cursorarrow"
        case .highlight: return "highlighter"
        case .note:      return "note.text"
        case .comment:   return "text.bubble"
        case .commentRegion: return "rectangle.dashed"
        case .editText:  return "character.cursor.ibeam"
        case .ink:       return "scribble.variable"
        case .eraser:    return "eraser"
        case .underline: return "underline"
        case .strikeout: return "strikethrough"
        case .signature: return "signature"
        case .stamp:     return "seal"
        }
    }

    var helpText: String {
        switch self {
        case .none:      return "Select annotations on the page. Press Delete to remove the selected annotation."
        case .highlight: return "Select PDF text to mark it with color."
        case .note:      return "Click the page to add a sticky note, or click an existing note to edit it."
        case .comment:   return "Select PDF text, then create an anchored comment."
        case .commentRegion: return "Drag a rectangle over a figure or region to create an anchored comment."
        case .editText:  return "Click existing text to replace it, or click blank space to add text."
        case .ink:       return "Draw freehand marks on the page."
        case .eraser:    return "Click a highlight, underline, or strikeout to remove it."
        case .underline: return "Select PDF text to underline it."
        case .strikeout: return "Select PDF text to strike it out."
        case .signature: return "Place a saved signature on the page."
        case .stamp:     return "Place a stamp on the page."
        }
    }

    var isColorable: Bool {
        switch self {
        case .highlight, .note, .editText, .ink, .underline, .strikeout: return true
        case .none, .comment, .commentRegion, .eraser, .signature, .stamp: return false
        }
    }

    var usesInkColor: Bool { self == .ink }

    var isReaderModeAllowed: Bool {
        switch self {
        case .editText, .signature:
            return false
        case .none, .highlight, .note, .comment, .commentRegion, .ink, .eraser, .underline, .strikeout, .stamp:
            return true
        }
    }
}

@Observable
final class WorkspaceOperationProgress {
    var title = ""
    var detail = ""
    var fraction: Double = 0
    var isActive = false
    var isCancellable = false

    func start(title: String, detail: String = "", isCancellable: Bool = true) {
        self.title = title
        self.detail = detail
        self.fraction = 0
        self.isActive = true
        self.isCancellable = isCancellable
    }

    func update(fraction: Double, detail: String? = nil) {
        self.fraction = min(max(fraction, 0), 1)
        if let detail {
            self.detail = detail
        }
    }

    func finish() {
        title = ""
        detail = ""
        fraction = 0
        isActive = false
        isCancellable = false
    }
}

final class OperationCancellationToken: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    var isCancelled: Bool {
        lock.lock()
        let value = cancelled
        lock.unlock()
        return value
    }
}

private final class ProgressUpdateThrottle: @unchecked Sendable {
    private let lock = NSLock()
    private var lastUpdate = Date.distantPast
    private let interval: TimeInterval = 0.1

    func shouldEmit(_ fraction: Double) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let now = Date()
        guard fraction >= 1 || now.timeIntervalSince(lastUpdate) >= interval else {
            return false
        }
        lastUpdate = now
        return true
    }
}

@Observable
final class WorkspaceViewModel {
    var document: WorkspaceDocument
    var combinedPDF: PDFDocument = PDFDocument()
    /// Ordered parallel to workspace.documents.
    var loadedPDFs: [(MemberDocument, PDFDocument)] = []

    // MARK: - UI state
    // A single, centralized integration point for the pet's "warning" reaction: every
    // import/export failure in the app funnels through one of these two properties, so
    // observing them here fires exactly one throttled pet reaction per surfaced error
    // rather than scattering `PetBuddyHook.trigger(.warning)` across ~20 failure sites.
    var importError: ImportError? = nil {
        didSet { if importError != nil { PetBuddyHook.trigger(.warning) } }
    }
    var exportError: ExportError? = nil {
        didSet { if exportError != nil { PetBuddyHook.trigger(.warning) } }
    }
    var exportSuccess: ExportSuccess? = nil
    var isImporting = false
    var pendingPasswordURL: URL? = nil
    var pendingPasswordPDF: PDFDocument? = nil
    var isShowingPasswordPrompt = false
    var currentTool: AnnotationTool = .none {
        didSet {
            if isReaderMode && !currentTool.isReaderModeAllowed {
                let blockedTool = currentTool
                currentTool = .none
                showReaderModeBlockedMessage(for: blockedTool)
                return
            }
            if oldValue != currentTool {
                selectedAnnotation = nil
                selectedStampDecorationID = nil
            }
            if oldValue == .signature, currentTool != .signature {
                clearPendingSignaturePlacement()
            }
        }
    }
    var isReaderMode = false {
        didSet {
            guard oldValue != isReaderMode else { return }
            if isReaderMode {
                if !currentTool.isReaderModeAllowed {
                    currentTool = .none
                }
                isShowingSignaturePalette = false
                clearPendingSignaturePlacement()
                showEditMessage(L10n.string("status.readerMode.on"), severity: .info)
            } else {
                showEditMessage(L10n.string("status.readerMode.off"), severity: .info)
            }
        }
    }
    var isShowingSearch = false
    var isShowingSignaturePalette = false
    var isShowingStampPalette = false
    var searchQuery = ""
    var searchResults: [PDFSelection] = []
    var searchResultIndex: Int = -1
    var pendingSignatureData: Data? = nil
    var pendingSignatureOptions: PendingSignaturePlacementOptions? = nil
    var pendingStampOptions: PendingStampPlacementOptions? = nil
    var selectedStampDecorationID: UUID? = nil
    private(set) var decorationStateVersion = 0
    var selectedPageRefID: UUID? = nil
    var selectedPageRefIDs: Set<UUID> = []
    var draggedPageRefID: UUID? = nil
    var selectedCommentID: UUID? = nil
    var commentFilter: CommentFilter = .open
    private(set) var commentRevision = 0
    /// Bumped by `rebuild()` — every operation that changes which documents/pages are
    /// loaded (import, remove, move, rotate, duplicate, delete, undo/redo restore) calls
    /// `rebuild()`, so this catches structural changes that `commentRevision` alone would
    /// miss (e.g. removing a document that has no anchored `WorkspaceComment`s but does
    /// carry PDF-native sticky notes `pdfNoteComments` still needs to stop enumerating).
    private(set) var structureRevision = 0
    @ObservationIgnored private var pdfNoteCommentsCache: (commentRevision: Int, structureRevision: Int, notes: [PDFNoteComment])?
    var editingStatus: EditingStatus? = nil
    var copiedInlineTextFormat: PDFTextEditFormat? = nil
    var isInlineTextFormatPainterArmed = false
    var operationProgress = WorkspaceOperationProgress()
    var formSummary = PDFFormSummary()
    var highlightFormFields = false
    var selectedFormFieldIndex: Int? = nil
    var appAppearanceMode: AppAppearanceMode = .system
    var documentComfortSettings = DocumentComfortSettings.default

    var hasPendingSignaturePlacement: Bool {
        pendingSignatureData != nil && pendingSignatureOptions != nil
    }
    var scannedPageCount = 0
    var ocrCandidatePageCount = 0
    var isMakingSearchable: Bool {
        activeOCRTask != nil
    }
    var canStartSearchable: Bool {
        hasScannedPages && canRunOCROperation
    }
    var canRepairSearchableText: Bool {
        !hasScannedPages && ocrCandidatePageCount > 0 && canRunOCROperation
    }

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
    var canRemoveDocuments: Bool {
        !isImporting && activeCompressionTask == nil && activeOCRTask == nil && !loadedPDFs.isEmpty
    }

    /// True once there's genuinely nothing to export or save — zero documents,
    /// zero pages, and no active selection. Export/save flows should treat this
    /// as a no-op rather than routing into the PDF assembly pipeline, which
    /// rejects zero-page documents as an error.
    var isWorkspaceEmpty: Bool {
        document.workspace.documents.isEmpty && pageCount == 0 && selectedPageRefID == nil
    }

    weak var undoManager: UndoManager?

    private let engine: PDFEngine
    private let processingEngine: PDFProcessingEngine
    private let textAnalysisEngine = PDFTextAnalysisEngine()
    private var textAnalysisCache: [UUID: PDFTextPageAnalysis] = [:]
    private var pendingSigningIdentity: (any SigningIdentity)?
    private var signingIdentitiesByPlacementID: [UUID: any SigningIdentity] = [:]
    @ObservationIgnored private var searchDebounceTask: Task<Void, Never>?
    @ObservationIgnored private var activeCompressionTask: Task<Void, Never>?
    @ObservationIgnored private var activeCompressionCancellation: OperationCancellationToken?
    @ObservationIgnored private var activeCompressionID: UUID?
    @ObservationIgnored private var activeImportTask: Task<Void, Never>?
    @ObservationIgnored private var activeImportCancellation: OperationCancellationToken?
    @ObservationIgnored private var pendingPasswordImports: [PendingPasswordImport] = []
    @ObservationIgnored private var activeOCRTask: Task<Void, Never>?
    @ObservationIgnored private var activeOCRCancellation: OperationCancellationToken?
    @ObservationIgnored private var activeOCRID: UUID?
    @ObservationIgnored private var searchNotificationTokens: [NSObjectProtocol] = []
    @ObservationIgnored private var activeSearchID = UUID()
    @ObservationIgnored private var pendingSearchResults: [PDFSelection] = []
    @ObservationIgnored private(set) var searchResultsQuery = ""
    /// Raw PDF bytes captured ONCE when each member is first loaded or attached.
    /// Never mutated during editing — used as the immutable base for page regeneration
    /// so multiple edits on the same page always start from the original content.
    private var originalMemberPDFData: [UUID: Data] = [:]
    private static let legacyBrandToken = ["PDF", "old"].joined()
    static let textReplacementAnnotationKey = PDFAnnotationKey(rawValue: "/OrifoldTextReplacement")
    static let legacyTextReplacementAnnotationKey = PDFAnnotationKey(rawValue: "/\(legacyBrandToken)TextReplacement")
    static let draftTextAnnotationKey = PDFAnnotationKey(rawValue: "/OrifoldDraftText")
    static let legacyDraftTextAnnotationKey = PDFAnnotationKey(rawValue: "/\(legacyBrandToken)DraftText")
    static let signaturePlacementAnnotationKey = PDFAnnotationKey(rawValue: "/OrifoldSignaturePlacementID")
    static let legacySignaturePlacementAnnotationKey = PDFAnnotationKey(rawValue: "/\(legacyBrandToken)SignaturePlacementID")

    static func annotationHasBooleanFlag(_ annotation: PDFAnnotation, key: PDFAnnotationKey, legacyKey: PDFAnnotationKey) -> Bool {
        (annotation.value(forAnnotationKey: key) as? Bool) == true ||
        (annotation.value(forAnnotationKey: legacyKey) as? Bool) == true
    }

    struct ImportError: Identifiable {
        let id = UUID()
        var fileName: String
        var message: String
    }

    struct ExportError: Identifiable {
        let id = UUID()
        var message: String
    }

    struct ExportSuccess: Identifiable {
        let id = UUID()
        var url: URL
        var detail: String? = nil

        var message: String {
            let folderName = url.deletingLastPathComponent().lastPathComponent
            var text = "\"\(url.lastPathComponent)\" was saved to \"\(folderName)\"."
            if let detail, !detail.isEmpty {
                text += " \(detail)"
            }
            return text
        }
    }

    struct EditingStatus: Identifiable, Equatable {
        enum Severity: Equatable {
            /// A confirmation that something the user asked for actually happened
            /// ("Format copied", "Matched nearby formatting") — distinct from `.warning`
            /// so it doesn't read as a caution/hint.
            case success
            case info
            case warning
            case error
        }

        let id = UUID()
        var message: String
        var severity: Severity

        var isError: Bool { severity == .error }

        static func success(_ message: String) -> EditingStatus {
            EditingStatus(message: message, severity: .success)
        }

        static func info(_ message: String) -> EditingStatus {
            EditingStatus(message: message, severity: .info)
        }

        static func warning(_ message: String) -> EditingStatus {
            EditingStatus(message: message, severity: .warning)
        }

        static func error(_ message: String) -> EditingStatus {
            EditingStatus(message: message, severity: .error)
        }

        static func == (lhs: EditingStatus, rhs: EditingStatus) -> Bool {
            lhs.id == rhs.id &&
            lhs.message == rhs.message &&
            lhs.severity == rhs.severity
        }
    }

    struct PendingSignaturePlacementOptions: Equatable {
        var kind: SignaturePlacement.Kind
        var signerName: String?
        var signerIdentityRef: String?
        var reason: String?
        var location: String?
        var contactInfo: String?
        var subFilter: String?
        var timestampRequested: Bool

        static var visualTyped: PendingSignaturePlacementOptions {
            PendingSignaturePlacementOptions(
                kind: .visualTyped,
                signerName: nil,
                signerIdentityRef: nil,
                reason: nil,
                location: nil,
                contactInfo: nil,
                subFilter: nil,
                timestampRequested: false
            )
        }
    }

    struct PendingStampPlacementOptions: Equatable {
        var text: String
        var swatch: PageDecorationSwatch
    }

    struct PDFNoteComment: Identifiable {
        var id: String
        var pageRef: PageRef
        var pageNumber: Int
        var memberName: String
        var annotation: PDFAnnotation

        var body: String {
            annotation.contents?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
    }

    enum CommentFilter: String, CaseIterable, Identifiable {
        case open = "Open"
        case resolved = "Resolved"
        case all = "All"

        var id: String { rawValue }
    }

    var hasCryptographicSignaturePlacement: Bool {
        document.workspace.signatures.contains { $0.isCryptographic }
    }

    /// True when any loaded member's PDF bytes already contain a digital signature that
    /// Orifold itself did not place — e.g. a PDF signed elsewhere (DocuSign, Adobe Sign, a
    /// notarized government document) before it was imported. `hasCryptographicSignaturePlacement`
    /// only tracks signatures placed via Orifold's own signing UI (`workspace.signatures`),
    /// so a pre-signed import previously got no warning at all before an edit silently
    /// invalidated it: any edit fully re-serializes the member's PDF bytes
    /// (`PDFSerializer.data(from:)`), which does not preserve the exact byte layout a
    /// `/ByteRange`-based signature's hash was computed over. `/ByteRange` is a PDF
    /// construct used only by signature dictionaries (per the PDF spec), so its presence in
    /// the raw bytes is a reliable, vendor-agnostic signal — checked here as a lightweight
    /// byte scan rather than a full AcroForm parse, consistent with the other lightweight
    /// content-sniffing helpers already used elsewhere in this codebase (e.g.
    /// `DocumentImportConverter.looksLikeHTML`).
    var hasThirdPartyCryptographicSignature: Bool {
        let byteRangeMarker = Data("/ByteRange".utf8)
        return document.workspace.documents.contains { member in
            let data = originalMemberPDFData[member.id] ?? document.memberPDFData[member.id]
            guard let data else { return false }
            return data.range(of: byteRangeMarker) != nil
        }
    }

    var pdfNoteComments: [PDFNoteComment] {
        if let cache = pdfNoteCommentsCache,
           cache.commentRevision == commentRevision,
           cache.structureRevision == structureRevision {
            return cache.notes
        }
        let notes = computePDFNoteComments()
        pdfNoteCommentsCache = (commentRevision, structureRevision, notes)
        return notes
    }

    /// The uncached scan behind `pdfNoteComments`. Walks every loaded PDF page's live
    /// annotations, so this is O(total pages) — cheap for typical workspaces, but expensive
    /// enough (e.g. from a sidebar row re-rendering on every hover) to be worth memoizing
    /// above rather than calling this directly.
    private func computePDFNoteComments() -> [PDFNoteComment] {
        var notes: [PDFNoteComment] = []
        for (member, pdf) in loadedPDFs {
            for localPageIndex in 0..<pdf.pageCount {
                guard let page = pdf.page(at: localPageIndex),
                      member.pageRefs.indices.contains(localPageIndex),
                      let pageRef = document.workspace.pageOrder.first(where: { $0.id == member.pageRefs[localPageIndex] })
                else { continue }

                let workspacePageNumber = (document.workspace.pageOrder.firstIndex(where: { $0.id == pageRef.id }) ?? localPageIndex) + 1
                for (annotationIndex, annotation) in page.annotations.enumerated() where annotation.type == "Text" {
                    let body = annotation.contents?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    guard !body.isEmpty else { continue }
                    notes.append(PDFNoteComment(
                        id: "\(pageRef.id.uuidString)-\(annotationIndex)-\(Int(annotation.bounds.minX))-\(Int(annotation.bounds.minY))",
                        pageRef: pageRef,
                        pageNumber: workspacePageNumber,
                        memberName: member.displayName,
                        annotation: annotation
                    ))
                }
            }
        }
        return notes
    }

    var totalCommentCount: Int {
        _ = commentRevision
        return document.workspace.comments.count + pdfNoteComments.count
    }

    var currentPageCommentCount: Int {
        _ = commentRevision
        if currentPageNumber > 0,
           document.workspace.pageOrder.indices.contains(currentPageNumber - 1) {
            return commentCount(for: document.workspace.pageOrder[currentPageNumber - 1].id)
        }
        if let selectedPageRefID {
            return commentCount(for: selectedPageRefID)
        }
        return 0
    }

    var filteredWorkspaceComments: [WorkspaceComment] {
        _ = commentRevision
        switch commentFilter {
        case .open:
            return document.workspace.comments.filter { !$0.isResolved }
        case .resolved:
            return document.workspace.comments.filter(\.isResolved)
        case .all:
            return document.workspace.comments
        }
    }

    var usedCommentTags: [String] {
        _ = commentRevision
        let tags = document.workspace.tags + document.workspace.comments.flatMap(\.tags)
        return tags.reduce(into: [String]()) { result, tag in
            guard !tag.isEmpty,
                  !result.contains(where: { $0.localizedCaseInsensitiveCompare(tag) == .orderedSame }) else {
                return
            }
            result.append(tag)
        }
        .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
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
            return try self.currentPDFDataForExport()
        }

        if !loadedPDFs.isEmpty { rebuild() }
    }

    deinit {
        cancelPendingSearch()
        activeImportCancellation?.cancel()
        activeImportTask?.cancel()
        activeCompressionTask?.cancel()
        activeOCRTask?.cancel()
    }

    // MARK: - Import

    func importFiles(urls: [URL], insertingAfter targetPageRefID: UUID? = nil) {
        guard canPerformMutatingAction() else { return }
        let batch = limitedImportBatch(from: urls)
        if batch.wasLimited {
            importError = ImportError(fileName: "Selected Files", message: importBatchLimitMessage)
        }
        guard !batch.urls.isEmpty else { return }
        guard beginImportIfPossible() else { return }
        let cancellation = OperationCancellationToken()
        activeImportCancellation = cancellation
        activeImportTask = Task { [weak self] in
            await self?.performImport(urls: batch.urls, insertingAfter: targetPageRefID, cancellation: cancellation)
        }
    }

    func importPDFs(urls: [URL]) {
        importFiles(urls: urls)
    }

    func addFile(from url: URL) {
        guard canPerformMutatingAction() else { return }
        addFileSynchronously(from: url)
    }

    private func beginImportIfPossible() -> Bool {
        guard !isImporting else {
            editingStatus = .warning("An import is already in progress.")
            return false
        }
        isImporting = true
        return true
    }

    private func performImport(urls: [URL], insertingAfter targetPageRefID: UUID? = nil, cancellation: OperationCancellationToken) async {
        await MainActor.run {
            self.operationProgress.start(
                title: "Importing files",
                detail: importProgressDetail(currentIndex: 0, totalCount: urls.count),
                isCancellable: true
            )
        }
        var insertionAnchorID = targetPageRefID
        var failures: [AsyncImportFailure] = []
        var importedCount = 0
        for (index, url) in urls.enumerated() {
            if cancellation.isCancelled || Task.isCancelled { break }
            await MainActor.run {
                self.operationProgress.update(
                    fraction: Double(index) / Double(max(urls.count, 1)),
                    detail: importProgressDetail(currentIndex: index + 1, totalCount: urls.count, fileName: url.lastPathComponent)
                )
            }
            let result = await importDocument(from: url, cancellation: cancellation)
            switch result {
            case .success(let imported):
                let targetID = insertionAnchorID
                let attachedLastPageID = await MainActor.run {
                    self.attachImportedDocument(imported.document, from: imported.url, insertingAfter: targetID)?.pageRefs.last
                }
                if let attachedLastPageID {
                    insertionAnchorID = attachedLastPageID
                    importedCount += 1
                }
            case .failure(let failure):
                failures.append(failure)
            }
        }
        let finalImportedCount = importedCount
        let finalFailures = failures
        await MainActor.run {
            self.operationProgress.update(
                fraction: 1,
                detail: importProgressDetail(currentIndex: urls.count, totalCount: urls.count)
            )
            self.rebuild()
            self.isImporting = false
            self.activeImportTask = nil
            self.activeImportCancellation = nil
            self.operationProgress.finish()
            if cancellation.isCancelled || Task.isCancelled {
                self.editingStatus = .warning(finalImportedCount > 0 ? "Import canceled after adding \(finalImportedCount) file\(finalImportedCount == 1 ? "" : "s")." : "Import canceled.")
            } else if !finalFailures.isEmpty {
                self.importError = self.importError(for: finalFailures, importedCount: finalImportedCount, totalCount: urls.count)
            }
            if self.pendingPasswordPDF != nil {
                self.isShowingPasswordPrompt = true
            }
        }
    }

    func cancelActiveOperation() {
        if isImporting {
            activeImportCancellation?.cancel()
            activeImportTask?.cancel()
            return
        }
        activeCompressionCancellation?.cancel()
        activeCompressionTask?.cancel()
        activeOCRCancellation?.cancel()
        activeOCRTask?.cancel()
    }

    private func importProgressDetail(currentIndex: Int, totalCount: Int, fileName: String? = nil) -> String {
        guard totalCount > 1 else {
            if let fileName, !fileName.isEmpty {
                return fileName
            }
            return "Preparing document"
        }
        guard currentIndex > 0 else {
            return "Preparing \(totalCount) files"
        }
        let countText = "File \(min(currentIndex, totalCount)) of \(totalCount)"
        guard let fileName, !fileName.isEmpty else {
            return countText
        }
        return "\(countText) - \(fileName)"
    }

    private func importError(for failures: [AsyncImportFailure], importedCount: Int, totalCount: Int) -> ImportError {
        guard failures.count > 1 else {
            let failure = failures[0]
            return ImportError(
                fileName: failure.url.lastPathComponent,
                message: String(localized: "Could not open \"\(failure.url.lastPathComponent)\". \(DocumentImportConverter.userMessage(for: failure.error))", locale: L10n.currentLocale)
            )
        }

        let names = failures.prefix(3).map { $0.url.lastPathComponent }.joined(separator: ", ")
        let suffix = failures.count > 3 ? ", and \(failures.count - 3) more" : ""
        let importedText = importedCount > 0 ? " \(importedCount) of \(totalCount) files were added." : " No files were added."
        return ImportError(
            fileName: "Selected Files",
            message: String(localized: "Could not open \(failures.count) files: \(names)\(suffix).\(importedText)", locale: L10n.currentLocale)
        )
    }

    private struct AsyncImportedDocument {
        var url: URL
        var document: DocumentImportConverter.ImportedDocument
    }

    private struct AsyncImportFailure: Error {
        var url: URL
        var error: Error
    }

    private struct PendingPasswordImport {
        var url: URL
        var pdf: PDFDocument
        var insertingAfter: UUID?
    }

    private func importDocument(from url: URL, cancellation: OperationCancellationToken) async -> Result<AsyncImportedDocument, AsyncImportFailure> {
        await Task.detached(priority: .userInitiated) {
            let fileName = url.lastPathComponent
            guard !cancellation.isCancelled, !Task.isCancelled else {
                return .failure(AsyncImportFailure(url: URL(fileURLWithPath: fileName), error: CancellationError()))
            }
            let isSecurityScoped = url.startAccessingSecurityScopedResource()
            defer {
                if isSecurityScoped { url.stopAccessingSecurityScopedResource() }
            }
            do {
                let document = try await DocumentImportConverter.importedDocumentAsync(from: url)
                try Task.checkCancellation()
                guard !cancellation.isCancelled else { throw CancellationError() }
                return .success(AsyncImportedDocument(url: url, document: document))
            } catch {
                let failedURL = URL(fileURLWithPath: fileName)
                return .failure(AsyncImportFailure(url: failedURL, error: error))
            }
        }.value
    }

    private func addFileSynchronously(from url: URL) {
        let fileName = url.lastPathComponent
        let isSecurityScoped = url.startAccessingSecurityScopedResource()
        defer {
            if isSecurityScoped { url.stopAccessingSecurityScopedResource() }
        }

        let imported: DocumentImportConverter.ImportedDocument
        do {
            imported = try DocumentImportConverter.importedDocument(from: url)
        } catch {
            importError = ImportError(
                fileName: fileName,
                message: String(localized: "Could not open \"\(fileName)\". \(DocumentImportConverter.userMessage(for: error))", locale: L10n.currentLocale)
            )
            return
        }
        let pdf = imported.pdfDocument
        if pdf.isLocked {
            enqueuePasswordImport(pdf: pdf, url: url)
            return
        }
        attachPDF(pdf, from: url, sourcePayload: imported.sourcePayload)
    }

    @discardableResult
    private func attachImportedDocument(_ imported: DocumentImportConverter.ImportedDocument,
                                        from url: URL,
                                        insertingAfter targetPageRefID: UUID? = nil) -> MemberDocument? {
        let pdf = imported.pdfDocument
        if pdf.isLocked {
            enqueuePasswordImport(pdf: pdf, url: url, insertingAfter: targetPageRefID)
            return nil
        }
        return attachPDF(pdf, from: url, sourcePayload: imported.sourcePayload, insertingAfter: targetPageRefID)
    }

    func unlock(pdf: PDFDocument, password: String, url: URL) -> Bool {
        guard canPerformMutatingAction() else { return false }
        guard pdf.unlock(withPassword: password) else { return false }
        let pending = pendingPasswordImports.first
        smokeValidatePDFData(pdf.dataRepresentation(), password: password)
        attachPDF(pdf, from: url, sourcePayload: nil, insertingAfter: pending?.insertingAfter)
        removeCurrentPasswordImport()
        rebuild()
        return true
    }

    func cancelPendingPasswordImport() {
        removeCurrentPasswordImport()
    }

    private func enqueuePasswordImport(pdf: PDFDocument, url: URL, insertingAfter targetPageRefID: UUID? = nil) {
        pendingPasswordImports.append(PendingPasswordImport(url: url, pdf: pdf, insertingAfter: targetPageRefID))
        presentPendingPasswordImportIfNeeded()
    }

    private func removeCurrentPasswordImport() {
        if !pendingPasswordImports.isEmpty {
            pendingPasswordImports.removeFirst()
        }
        pendingPasswordURL = nil
        pendingPasswordPDF = nil
        presentPendingPasswordImportIfNeeded()
    }

    private func presentPendingPasswordImportIfNeeded() {
        guard pendingPasswordPDF == nil, pendingPasswordURL == nil else { return }
        guard let next = pendingPasswordImports.first else {
            isShowingPasswordPrompt = false
            return
        }
        pendingPasswordURL = next.url
        pendingPasswordPDF = next.pdf
        if !isImporting {
            isShowingPasswordPrompt = true
        }
    }

    @discardableResult
    private func attachPDF(_ pdf: PDFDocument,
                           from url: URL,
                           sourcePayload: SourceDocumentPayload? = nil,
                           insertingAfter targetPageRefID: UUID? = nil) -> MemberDocument? {
        sanitizeInkAnnotations(in: pdf)

        guard let data = PDFSerializer.data(from: pdf) else {
            importError = ImportError(
                fileName: url.lastPathComponent,
                message: L10n.string("error.import.preparePDFForSaving")
            )
            return nil
        }
        smokeValidatePDFData(data)

        let name = url.deletingPathExtension().lastPathComponent
        var member = MemberDocument(displayName: name, sourcePDFRef: url.lastPathComponent)
        let refs = (0..<pdf.pageCount).map { i in PageRef(memberDocId: member.id, sourcePageIndex: i) }
        member.pageRefs = refs.map(\.id)
        if document.workspace.title == "Untitled Workspace", document.workspace.documents.isEmpty, !name.isEmpty {
            document.workspace.title = name
        }
        if let targetPageRefID,
           let targetDocIndex = document.workspace.documents.firstIndex(where: { $0.pageRefs.contains(targetPageRefID) }),
           let lastTargetPageID = document.workspace.documents[targetDocIndex].pageRefs.last,
           let targetPageIndex = document.workspace.pageOrder.firstIndex(where: { $0.id == lastTargetPageID }) {
            document.workspace.documents.insert(member, at: min(targetDocIndex + 1, document.workspace.documents.count))
            document.workspace.pageOrder.insert(contentsOf: refs, at: min(targetPageIndex + 1, document.workspace.pageOrder.count))
        } else {
            document.workspace.documents.append(member)
            document.workspace.pageOrder.append(contentsOf: refs)
        }
        document.memberPDFData[member.id] = data
        if let sourcePayload {
            document.sourcePayloads[member.id] = sourcePayload
        }
        originalMemberPDFData[member.id] = data
        memberSourceURLs[member.id] = url
        loadedPDFs.append((member, pdf))
        syncLoadedPDFsOrder()
        PetBuddyHook.trigger(.addFile)
        return member
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
        cancelPendingSearch()
        combinedPDF = engine.concatenate(documents: loadedPDFs, includeBanners: true)
        pageCount = document.workspace.pageOrder.count
        normalizePageSelection()
        refreshFormSummary()
        refreshScannedPageSummary()
        structureRevision += 1
        // PDFSelections are bound to the old document; drop them so search navigation
        // doesn't jump to pages in a detached doc.
        searchResults = []
        searchResultsQuery = ""
        searchResultIndex = -1
    }

    private func normalizePageSelection() {
        let validIDs = Set(document.workspace.pageOrder.map(\.id))
        selectedPageRefIDs = selectedPageRefIDs.filter { validIDs.contains($0) }
        if let selectedPageRefID, validIDs.contains(selectedPageRefID) {
            return
        }
        selectedPageRefID = selectedPageRefIDs.first ?? document.workspace.pageOrder.first?.id
        if let selectedPageRefID, selectedPageRefIDs.isEmpty {
            selectedPageRefIDs = [selectedPageRefID]
        }
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
        guard canPerformMutatingAction() else { return }
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
        registerUndo(snapshot: snapshot, actionName: L10n.string("undo.moveDocument"))
    }

    func removeDocument(at offsets: IndexSet) {
        guard canPerformMutatingAction() else { return }
        let validOffsets = offsets.filter { loadedPDFs.indices.contains($0) }
        guard validOffsets.count == offsets.count else { return }
        removeDocuments(withIDs: Set(validOffsets.map { loadedPDFs[$0].0.id }))
    }

    func removeDocument(_ member: MemberDocument) {
        guard canPerformMutatingAction() else { return }
        guard loadedPDFs.contains(where: { $0.0.id == member.id }) else { return }
        removeDocuments(withIDs: [member.id])
    }

    private func removeDocuments(withIDs removedIds: Set<UUID>) {
        guard !removedIds.isEmpty else { return }
        let snapshot = captureOrderSnapshot()
        let removedPageRefIDs = Set(document.workspace.documents
            .filter { removedIds.contains($0.id) }
            .flatMap(\.pageRefs))
        document.workspace.documents.removeAll { removedIds.contains($0.id) }
        document.workspace.pageEditStates.removeAll { removedPageRefIDs.contains($0.pageRefID) }
        clearCommentAnchors(forRemovedPageRefIDs: removedPageRefIDs)
        removeSignaturePlacements(forRemovedPageRefIDs: removedPageRefIDs)
        removeDecorations(forRemovedPageRefIDs: removedPageRefIDs)
        removedIds.forEach { document.memberPDFData.removeValue(forKey: $0) }
        removedIds.forEach { document.sourcePayloads.removeValue(forKey: $0) }
        loadedPDFs.removeAll { removedIds.contains($0.0.id) }
        selectedPageRefIDs.subtract(removedPageRefIDs)
        rebuildPageOrder()
        rebuild()
        registerUndo(snapshot: snapshot, actionName: L10n.string("undo.removeDocument"))
    }

    // MARK: - Rename (with undo)

    func renameDocument(_ member: MemberDocument, to newName: String) {
        guard canPerformMutatingAction() else { return }
        guard let loadedIndex = loadedPDFs.firstIndex(where: { $0.0.id == member.id }),
              let docIndex = document.workspace.documents.firstIndex(where: { $0.id == member.id }) else { return }
        // Read the live current name rather than trusting the caller's possibly-stale
        // `member` snapshot, so the no-op guard and the undo's captured "previous name"
        // are always correct even if the view passed a value from an earlier render.
        let currentName = document.workspace.documents[docIndex].displayName
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != currentName else { return }
        applyRename(loadedIndex: loadedIndex, docIndex: docIndex, name: trimmed)
        registerRenameUndo(memberID: member.id, previousName: currentName)
    }

    private func applyRename(loadedIndex: Int, docIndex: Int, name: String) {
        document.workspace.documents[docIndex].displayName = name
        loadedPDFs[loadedIndex].0.displayName = name
        markWorkspaceModified()
    }

    /// Isolated (see `registerIsolatedUndo`) so two renames committed in the same run-loop
    /// turn — e.g. correcting a typo and immediately refining the name again — don't
    /// collapse into a single undo step; each rename steps back individually.
    private func registerRenameUndo(memberID: UUID, previousName: String) {
        registerIsolatedUndo {
            undoManager?.registerUndo(withTarget: self) { vm in
                guard vm.canPerformUndoMutation(),
                      let loadedIndex = vm.loadedPDFs.firstIndex(where: { $0.0.id == memberID }),
                      let docIndex = vm.document.workspace.documents.firstIndex(where: { $0.id == memberID }) else { return }
                let currentName = vm.document.workspace.documents[docIndex].displayName
                vm.applyRename(loadedIndex: loadedIndex, docIndex: docIndex, name: previousName)
                vm.registerRenameUndo(memberID: memberID, previousName: currentName)
            }
            undoManager?.setActionName(L10n.string("undo.renameDocument"))
        }
    }

    private struct OrderSnapshot: @unchecked Sendable {
        var documents: [MemberDocument]
        var pageOrder: [PageRef]
        var comments: [WorkspaceComment]
        var signatures: [SignaturePlacement]
        var decorations: [PageDecoration]
        var signatureIdentities: [UUID: any SigningIdentity]
        var pageRotations: [UUID: Int]
        var pdfData: [UUID: Data]
        var sourcePayloads: [UUID: SourceDocumentPayload]
    }

    private struct InlineTextEditSnapshot {
        var editStates: [PageEditState]
        var pageRotations: [UUID: Int]
        var pdfData: [UUID: Data]
    }

    private func captureOrderSnapshot() -> OrderSnapshot {
        OrderSnapshot(
            documents: document.workspace.documents,
            pageOrder: document.workspace.pageOrder,
            comments: document.workspace.comments,
            signatures: document.workspace.signatures,
            decorations: document.workspace.decorations,
            signatureIdentities: signingIdentitiesByPlacementID,
            pageRotations: currentPageRotations(),
            pdfData: currentPDFData(),
            sourcePayloads: document.sourcePayloads
        )
    }

    private func restore(_ snapshot: OrderSnapshot) {
        document.workspace.documents = snapshot.documents
        document.workspace.pageOrder = snapshot.pageOrder
        document.workspace.comments = snapshot.comments
        document.workspace.signatures = snapshot.signatures
        document.workspace.decorations = snapshot.decorations
        signingIdentitiesByPlacementID = snapshot.signatureIdentities
        document.memberPDFData = snapshot.pdfData
        document.sourcePayloads = snapshot.sourcePayloads
        loadedPDFs = snapshot.documents.compactMap { member in
            guard let data = snapshot.pdfData[member.id],
                  let pdf = PDFDocument(data: data) else { return nil }
            return (member, pdf)
        }
        applyPageRotations(snapshot.pageRotations)
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

    private func currentPDFDataForExport() throws -> [UUID: Data] {
        var result: [UUID: Data] = [:]
        for (member, pdf) in loadedPDFs {
            guard let data = PDFSerializer.data(from: pdf),
                  PDFDocument(data: data)?.pageCount == pdf.pageCount else {
                throw PDFKitEngine.ExportAssemblyError.unreadableMember(member.displayName)
            }
            result[member.id] = data
        }
        return result
    }

    private func registerUndo(snapshot: OrderSnapshot, actionName: String) {
        undoManager?.registerUndo(withTarget: self) { vm in
            guard vm.canPerformUndoMutation() else { return }
            vm.restore(snapshot)
        }
        undoManager?.setActionName(actionName)
    }

    /// Registers `registration` as its own isolated, atomic undo step, regardless of where
    /// this is called from in the run loop. `UndoManager.groupsByEvent` (the default) only
    /// auto-closes its implicit group at a run-loop boundary — several inline edits
    /// committed back-to-back with no run-loop turn between them (a scripted/batch edit
    /// flow, or just a few fast edits inside the same event, as happens in tests and in
    /// some programmatic call paths) would otherwise all land in the SAME implicit group,
    /// so a single `undo()` would revert every one of them at once instead of stepping
    /// back one edit at a time. Nesting a plain `beginUndoGrouping`/`endUndoGrouping` pair
    /// inside that still-open implicit group does not help — it only manipulates the
    /// nested grouping level, leaving the ambient group open underneath. Temporarily
    /// disabling `groupsByEvent` forces this bracket to form a genuine standalone top-level
    /// group, which is then restored to whatever it was before.
    private func registerIsolatedUndo(_ registration: () -> Void) {
        guard let undoManager else {
            registration()
            return
        }
        let priorGroupsByEvent = undoManager.groupsByEvent
        undoManager.groupsByEvent = false
        undoManager.beginUndoGrouping()
        registration()
        undoManager.endUndoGrouping()
        undoManager.groupsByEvent = priorGroupsByEvent
    }

    private func captureInlineTextEditSnapshot() -> InlineTextEditSnapshot {
        InlineTextEditSnapshot(
            editStates: document.workspace.pageEditStates,
            pageRotations: currentPageRotations(),
            pdfData: currentPDFData()
        )
    }

    private func restoreInlineTextEditSnapshot(_ snapshot: InlineTextEditSnapshot, actionName: String) {
        let inverse = captureInlineTextEditSnapshot()
        document.workspace.pageEditStates = snapshot.editStates
        document.memberPDFData = snapshot.pdfData
        loadedPDFs = document.workspace.documents.compactMap { member in
            guard let data = snapshot.pdfData[member.id],
                  let pdf = PDFDocument(data: data) else { return nil }
            return (member, pdf)
        }
        applyPageRotations(snapshot.pageRotations)
        textAnalysisCache.removeAll()
        rebuild()
        markWorkspaceModified()
        registerIsolatedUndo {
            undoManager?.registerUndo(withTarget: self) { vm in
                guard vm.canPerformUndoMutation() else { return }
                vm.restoreInlineTextEditSnapshot(inverse, actionName: actionName)
            }
            undoManager?.setActionName(actionName)
        }
    }

    private func syncLoadedPDFsOrder() {
        let order = document.workspace.documents.map(\.id)
        loadedPDFs.sort {
            (order.firstIndex(of: $0.0.id) ?? Int.max) < (order.firstIndex(of: $1.0.id) ?? Int.max)
        }
    }

    private func currentPageRotations() -> [UUID: Int] {
        var rotations: [UUID: Int] = [:]
        for (member, pdf) in loadedPDFs {
            for (pageIndex, refID) in member.pageRefs.enumerated() {
                if let page = pdf.page(at: pageIndex) {
                    rotations[refID] = page.rotation
                }
            }
        }
        return rotations
    }

    private func applyPageRotations(_ rotations: [UUID: Int]) {
        guard !rotations.isEmpty else { return }
        for loadedIndex in loadedPDFs.indices {
            let member = loadedPDFs[loadedIndex].0
            let pdf = loadedPDFs[loadedIndex].1
            for (pageIndex, refID) in member.pageRefs.enumerated() {
                guard let rotation = rotations[refID],
                      let page = pdf.page(at: pageIndex) else { continue }
                page.rotation = rotation
            }
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
        guard canPerformMutatingAction() else { return }
        let tag = normalizedTag(rawValue)
        guard !tag.isEmpty,
              !document.workspace.tags.contains(where: { $0.localizedCaseInsensitiveCompare(tag) == .orderedSame }) else {
            return
        }
        document.workspace.tags.append(tag)
        markWorkspaceModified()
        commentRevision += 1
        undoManager?.registerUndo(withTarget: self) { vm in
            guard vm.canPerformUndoMutation() else { return }
            vm.removeTag(tag)
        }
        undoManager?.setActionName(L10n.string("undo.addTag"))
        PetBuddyHook.trigger(.tag)
    }

    func removeTag(_ tag: String) {
        guard canPerformMutatingAction() else { return }
        guard let index = document.workspace.tags.firstIndex(of: tag) else { return }
        let removed = document.workspace.tags.remove(at: index)
        markWorkspaceModified()
        commentRevision += 1
        undoManager?.registerUndo(withTarget: self) { vm in
            guard vm.canPerformUndoMutation() else { return }
            vm.document.workspace.tags.insert(removed, at: min(index, vm.document.workspace.tags.count))
            vm.markWorkspaceModified()
            vm.commentRevision += 1
        }
        undoManager?.setActionName(L10n.string("undo.removeTag"))
    }

    func addComment(_ rawBody: String) {
        guard canPerformMutatingAction() else { return }
        let body = rawBody.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        let comment = WorkspaceComment(body: body)
        document.workspace.comments.insert(comment, at: 0)
        markCommentsModified()
        undoManager?.registerUndo(withTarget: self) { vm in
            guard vm.canPerformUndoMutation() else { return }
            vm.removeComment(comment)
        }
        undoManager?.setActionName(L10n.string("undo.addComment"))
        PetBuddyHook.trigger(.comment)
    }

    @discardableResult
    func createAnchoredComment(body rawBody: String = "", anchor: WorkspaceCommentAnchor) -> UUID? {
        guard canPerformMutatingAction() else { return nil }
        let comment = WorkspaceComment(
            body: rawBody.trimmingCharacters(in: .whitespacesAndNewlines),
            anchor: anchor,
            anchorWasRemoved: false
        )
        document.workspace.comments.insert(comment, at: 0)
        selectedCommentID = comment.id
        markCommentsModified()
        undoManager?.registerUndo(withTarget: self) { vm in
            guard vm.canPerformUndoMutation() else { return }
            vm.removeComment(comment)
        }
        undoManager?.setActionName(L10n.string("undo.addComment"))
        PetBuddyHook.trigger(.comment)
        return comment.id
    }

    @discardableResult
    func createAnchoredTextComment(from selection: PDFSelection, in pdfDocument: PDFDocument?) -> UUID? {
        guard let anchor = commentAnchor(from: selection, in: pdfDocument) else { return nil }
        return createAnchoredComment(anchor: anchor)
    }

    @discardableResult
    func createAnchoredRegionComment(rect: CGRect, on page: PDFPage, in pdfDocument: PDFDocument?) -> UUID? {
        guard let ref = pageRef(for: page, in: pdfDocument) else { return nil }
        let anchorRect = rect.standardized
        guard anchorRect.width >= 8, anchorRect.height >= 8 else { return nil }
        let anchor = WorkspaceCommentAnchor(
            pageRefID: ref.id,
            rect: anchorRect,
            kind: .region,
            snippet: nil
        )
        return createAnchoredComment(anchor: anchor)
    }

    func removeComment(_ comment: WorkspaceComment) {
        guard canPerformMutatingAction() else { return }
        guard let index = document.workspace.comments.firstIndex(where: { $0.id == comment.id }) else { return }
        let removed = document.workspace.comments.remove(at: index)
        let previousSelection = selectedCommentID
        if selectedCommentID == removed.id {
            if document.workspace.comments.isEmpty {
                selectedCommentID = nil
            } else {
                selectedCommentID = document.workspace.comments[min(index, document.workspace.comments.count - 1)].id
            }
        }
        markCommentsModified()
        undoManager?.registerUndo(withTarget: self) { vm in
            guard vm.canPerformUndoMutation() else { return }
            vm.document.workspace.comments.insert(removed, at: min(index, vm.document.workspace.comments.count))
            vm.selectedCommentID = previousSelection
            vm.markCommentsModified()
        }
        undoManager?.setActionName(L10n.string("undo.removeComment"))
    }

    func updateCommentBody(_ comment: WorkspaceComment, body rawBody: String) {
        guard canPerformMutatingAction() else { return }
        let body = rawBody.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty,
              let index = document.workspace.comments.firstIndex(where: { $0.id == comment.id }),
              document.workspace.comments[index].body != body else {
            return
        }
        var updated = document.workspace.comments[index]
        updated.body = body
        replaceComment(at: index, with: updated, actionName: L10n.string("undo.editComment"))
    }

    func updateCommentStyle(_ comment: WorkspaceComment, style: WorkspaceCommentStyle) {
        guard canPerformMutatingAction() else { return }
        guard let index = document.workspace.comments.firstIndex(where: { $0.id == comment.id }),
              document.workspace.comments[index].style != style else {
            return
        }
        var updated = document.workspace.comments[index]
        updated.style = style
        replaceComment(at: index, with: updated, actionName: L10n.string("undo.formatComment"))
    }

    func updateCommentResolved(_ comment: WorkspaceComment, isResolved: Bool) {
        guard canPerformMutatingAction() else { return }
        guard let index = document.workspace.comments.firstIndex(where: { $0.id == comment.id }),
              document.workspace.comments[index].isResolved != isResolved else {
            return
        }
        var updated = document.workspace.comments[index]
        updated.isResolved = isResolved
        replaceComment(at: index, with: updated, actionName: isResolved ? L10n.string("undo.resolveComment") : L10n.string("undo.reopenComment"))
    }

    func addTag(_ rawTag: String, to comment: WorkspaceComment) {
        guard canPerformMutatingAction() else { return }
        let tag = normalizedTag(rawTag)
        guard !tag.isEmpty,
              let index = document.workspace.comments.firstIndex(where: { $0.id == comment.id }),
              !document.workspace.comments[index].tags.contains(where: { $0.localizedCaseInsensitiveCompare(tag) == .orderedSame }) else {
            return
        }
        var updated = document.workspace.comments[index]
        updated.tags.append(tag)
        replaceComment(at: index, with: updated, actionName: L10n.string("undo.tagComment"))
        PetBuddyHook.trigger(.tag)
    }

    func removeTag(_ tag: String, from comment: WorkspaceComment) {
        guard canPerformMutatingAction() else { return }
        guard let index = document.workspace.comments.firstIndex(where: { $0.id == comment.id }),
              document.workspace.comments[index].tags.contains(tag) else {
            return
        }
        var updated = document.workspace.comments[index]
        updated.tags.removeAll { $0 == tag }
        replaceComment(at: index, with: updated, actionName: L10n.string("undo.untagComment"))
    }

    private func replaceComment(at index: Int, with updated: WorkspaceComment, actionName: String) {
        guard document.workspace.comments.indices.contains(index) else { return }
        let previous = document.workspace.comments[index]
        document.workspace.comments[index] = updated
        markCommentsModified()
        undoManager?.registerUndo(withTarget: self) { vm in
            guard vm.canPerformUndoMutation() else { return }
            vm.restoreComment(previous, actionName: actionName)
        }
        undoManager?.setActionName(actionName)
    }

    private func restoreComment(_ comment: WorkspaceComment, actionName: String) {
        guard let index = document.workspace.comments.firstIndex(where: { $0.id == comment.id }) else { return }
        let inverse = document.workspace.comments[index]
        document.workspace.comments[index] = comment
        markCommentsModified()
        undoManager?.registerUndo(withTarget: self) { vm in
            guard vm.canPerformUndoMutation() else { return }
            vm.restoreComment(inverse, actionName: actionName)
        }
        undoManager?.setActionName(actionName)
    }

    private func commentAnchor(from selection: PDFSelection, in pdfDocument: PDFDocument?) -> WorkspaceCommentAnchor? {
        guard let page = selection.pages.first,
              let ref = pageRef(for: page, in: pdfDocument) else {
            return nil
        }
        let rect = selection.bounds(for: page)
        guard !rect.isEmpty else { return nil }
        return WorkspaceCommentAnchor(
            pageRefID: ref.id,
            rect: rect,
            kind: .text,
            snippet: Self.commentSnippet(from: selection.string)
        )
    }

    static func commentSnippet(from text: String?) -> String? {
        let normalized = (text ?? "")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        return String(normalized.prefix(60))
    }

    func pageNumber(for anchor: WorkspaceCommentAnchor) -> Int? {
        guard let index = document.workspace.pageOrder.firstIndex(where: { $0.id == anchor.pageRefID }) else {
            return nil
        }
        return index + 1
    }

    func anchorSubtitle(for comment: WorkspaceComment) -> String? {
        guard let anchor = comment.anchor else {
            return comment.anchorWasRemoved ? "(page removed)" : nil
        }
        guard let pageNumber = pageNumber(for: anchor) else { return "(page removed)" }
        if let snippet = anchor.snippet, !snippet.isEmpty {
            return "p. \(pageNumber) - \(snippet)"
        }
        return "p. \(pageNumber)"
    }

    func commentCount(for pageRefID: UUID) -> Int {
        _ = commentRevision
        let workspaceCount = document.workspace.comments.filter { $0.anchor?.pageRefID == pageRefID }.count
        let noteCount = pdfNoteComments.filter { $0.pageRef.id == pageRefID }.count
        return workspaceCount + noteCount
    }

    /// Total comment count across every page belonging to `member`, for the sidebar's
    /// per-document metadata line.
    func commentCount(for member: MemberDocument) -> Int {
        member.pageRefs.reduce(0) { $0 + commentCount(for: $1) }
    }

    func isCommentVisibleOnPage(_ comment: WorkspaceComment) -> Bool {
        filteredWorkspaceComments.contains { $0.id == comment.id }
    }

    func jumpToComment(_ comment: WorkspaceComment) {
        selectedCommentID = comment.id
        guard let anchor = comment.anchor,
              let ref = document.workspace.pageOrder.first(where: { $0.id == anchor.pageRefID }) else {
            return
        }
        selectPage(ref)
    }

    private func clearCommentAnchors(forRemovedPageRefIDs removedPageRefIDs: Set<UUID>) {
        guard !removedPageRefIDs.isEmpty else { return }
        var didChange = false
        for index in document.workspace.comments.indices {
            guard let anchor = document.workspace.comments[index].anchor,
                  removedPageRefIDs.contains(anchor.pageRefID) else {
                continue
            }
            document.workspace.comments[index].anchor = nil
            document.workspace.comments[index].anchorWasRemoved = true
            didChange = true
        }
        if didChange {
            markCommentsModified()
        }
    }

    private func removeSignaturePlacements(forRemovedPageRefIDs removedPageRefIDs: Set<UUID>) {
        guard !removedPageRefIDs.isEmpty else { return }
        let removedPlacementIDs = Set(
            document.workspace.signatures
                .filter { removedPageRefIDs.contains($0.pageRefId) }
                .map(\.id)
        )
        guard !removedPlacementIDs.isEmpty else { return }
        document.workspace.signatures.removeAll { removedPlacementIDs.contains($0.id) }
        for placementID in removedPlacementIDs {
            signingIdentitiesByPlacementID.removeValue(forKey: placementID)
        }
    }

    private func removeDecorations(forRemovedPageRefIDs removedPageRefIDs: Set<UUID>) {
        guard !removedPageRefIDs.isEmpty else { return }
        let removedStampIDs = Set(
            document.workspace.decorations.compactMap { decoration -> UUID? in
                guard decoration.kind == .stamp,
                      let pageRefID = decoration.pageRefID,
                      removedPageRefIDs.contains(pageRefID) else {
                    return nil
                }
                return decoration.id
            }
        )
        document.workspace.decorations.removeAll { decoration in
            guard let pageRefID = decoration.pageRefID else { return false }
            return removedPageRefIDs.contains(pageRefID)
        }
        decorationStateVersion &+= 1
        if let selectedStampDecorationID,
           removedStampIDs.contains(selectedStampDecorationID) {
            self.selectedStampDecorationID = nil
        }
    }

    func jumpToNoteComment(_ note: PDFNoteComment) {
        selectedAnnotation = note.annotation
        selectPage(note.pageRef)
    }

    func removeNoteComment(_ note: PDFNoteComment) {
        guard canPerformMutatingAction() else { return }
        guard let page = note.annotation.page else { return }
        page.removeAnnotation(note.annotation)
        if selectedAnnotation === note.annotation {
            selectedAnnotation = nil
        }
        markAnnotationsModified()
        undoManager?.registerUndo(withTarget: self) { vm in
            guard vm.canPerformUndoMutation() else { return }
            page.addAnnotation(note.annotation)
            vm.markAnnotationsModified()
        }
        undoManager?.setActionName(L10n.string("undo.removeNote"))
    }

    func registerAnnotationEdit(_ annotation: PDFAnnotation,
                                from oldSnapshot: PDFAnnotationEditSnapshot,
                                actionName: String) {
        guard canPerformMutatingAction() else { return }
        guard annotation.page != nil else {
            markAnnotationsModified()
            return
        }
        registerAnnotationSnapshotUndo(annotation, restore: oldSnapshot, actionName: actionName)
        markAnnotationsModified()
    }

    private func registerAnnotationSnapshotUndo(_ annotation: PDFAnnotation,
                                                restore snapshot: PDFAnnotationEditSnapshot,
                                                actionName: String) {
        let redoSnapshot = PDFAnnotationEditSnapshot(annotation: annotation)
        undoManager?.registerUndo(withTarget: self) { vm in
            guard vm.canPerformUndoMutation() else { return }
            snapshot.restore(to: annotation)
            vm.markAnnotationsModified()
            vm.registerAnnotationSnapshotUndo(annotation, restore: redoSnapshot, actionName: actionName)
        }
        undoManager?.setActionName(actionName)
    }

    private func normalizedTag(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
    }

    private func markWorkspaceModified() {
        document.workspace.modifiedAt = Date()
    }

    private func markCommentsModified() {
        commentRevision += 1
        markWorkspaceModified()
    }

    private func canPerformMutatingAction() -> Bool {
        guard !isImporting else {
            editingStatus = .warning("Finish importing before making more changes.")
            return false
        }
        guard activeCompressionTask == nil else {
            editingStatus = .warning("Finish reducing file size before making more changes.")
            return false
        }
        guard activeOCRTask == nil else {
            editingStatus = .warning("Finish making this document searchable before making more changes.")
            return false
        }
        return true
    }

    private func canPerformSigningAction() -> Bool {
        guard !isReaderMode else {
            showReaderModeBlockedMessage(for: .signature)
            return false
        }
        return canPerformMutatingAction()
    }

    private func showReaderModeBlockedMessage(for tool: AnnotationTool) {
        switch tool {
        case .editText:
            showEditMessage("Reader Mode keeps the document text locked. Turn it off to edit PDF text.", isError: false)
        case .signature:
            showEditMessage("Reader Mode keeps signing locked. Turn it off to place or export signatures.", isError: false)
        default:
            showEditMessage("Reader Mode keeps authoring tools locked.", isError: false)
        }
    }

    private func canPerformUndoMutation() -> Bool {
        canPerformMutatingAction()
    }

    func performUndoCommand() {
        guard canPerformMutatingAction() else { return }
        guard let undoManager else {
            showEditMessage(L10n.string("status.undo.nothingToUndo"), severity: .info)
            return
        }
        guard undoManager.canUndo else {
            showEditMessage(L10n.string("status.undo.nothingLeftToUndo"), severity: .info)
            return
        }

        undoManager.undo()
        disarmFormatPainter()

        if !undoManager.canUndo {
            showEditMessage(L10n.string("status.undo.backAtBeginning"), severity: .info)
        }
    }

    func performRedoCommand() {
        guard canPerformMutatingAction() else { return }
        guard let undoManager, undoManager.canRedo else { return }
        undoManager.redo()
        disarmFormatPainter()
    }

    /// Undo/redo is a strong, explicit signal the user is backing out of recent actions —
    /// silently auto-applying a copied format (armed via "Copy" before the undo/redo) to
    /// the next unrelated edit the user opens would be more surprising than helpful right
    /// after rolling the document back or forward. Format-painter state armed BEFORE the
    /// undo/redo is no longer meaningfully tied to what the user is looking at afterward.
    private func disarmFormatPainter() {
        guard isInlineTextFormatPainterArmed else { return }
        isInlineTextFormatPainterArmed = false
        copiedInlineTextFormat = nil
    }

    #if DEBUG
    func setProcessingStateForTesting(compressionActive: Bool = false, ocrActive: Bool = false) {
        activeCompressionTask = compressionActive ? Task { } : nil
        activeOCRTask = ocrActive ? Task { } : nil
    }
    #endif

    func markAnnotationsModified(warnAboutSignatureInvalidation: Bool = true) {
        markWorkspaceModified()
        commentRevision += 1
        if warnAboutSignatureInvalidation {
            warnIfEditingWouldInvalidateSignatures()
        }
    }

    // MARK: - Forms

    var hasFillableFormFields: Bool {
        formSummary.containsForm
    }

    var hasFormNotice: Bool {
        formSummary.containsForm || formSummary.hasUnsupportedDynamicFeatures
    }

    var canvasBannerInset: CGFloat {
        var inset: CGFloat = 0
        if hasScannedPages { inset += 48 }
        if hasFormNotice { inset += 48 }
        return inset
    }

    private func refreshFormSummary() {
        formSummary = PDFFormSupport.scan(documents: loadedPDFs, pageOrder: document.workspace.pageOrder)
        if !formSummary.containsForm {
            selectedFormFieldIndex = nil
            highlightFormFields = false
        } else if let selectedFormFieldIndex,
                  !formSummary.fields.indices.contains(selectedFormFieldIndex) {
            self.selectedFormFieldIndex = nil
        }
    }

    var hasScannedPages: Bool {
        scannedPageCount > 0
    }

    private var canRunOCROperation: Bool {
        !isImporting && activeCompressionTask == nil && activeOCRTask == nil
    }

    private func refreshScannedPageSummary() {
        var scannedCount = 0
        var candidateCount = 0
        for (_, pdf) in loadedPDFs {
            for pageIndex in 0..<pdf.pageCount {
                guard let page = pdf.page(at: pageIndex) else { continue }
                if PDFOCRService.hasVisibleContent(page) {
                    candidateCount += 1
                }
                if PDFOCRService.isLikelyScannedPage(page) {
                    scannedCount += 1
                }
            }
        }
        scannedPageCount = scannedCount
        ocrCandidatePageCount = candidateCount
    }

    func selectNextFormField() {
        selectFormField(offset: 1)
    }

    func selectPreviousFormField() {
        selectFormField(offset: -1)
    }

    private func selectFormField(offset: Int) {
        guard !formSummary.fields.isEmpty else { return }
        let current = selectedFormFieldIndex ?? (offset > 0 ? -1 : formSummary.fields.count)
        let next = (current + offset + formSummary.fields.count) % formSummary.fields.count
        selectedFormFieldIndex = next
        let field = formSummary.fields[next]
        if let ref = document.workspace.pageOrder.first(where: { $0.id == field.pageRefID }),
           let pageIndex = combinedPageIndex(for: ref) {
            NotificationCenter.default.post(
                name: .orifoldJumpToFormField,
                object: PDFFormFieldNavigationTarget(
                    pageIndex: pageIndex,
                    bounds: field.bounds,
                    fieldType: field.fieldType
                )
            )
        }
    }

    func resetFormFields() {
        guard canPerformMutatingAction(), formSummary.containsForm else { return }
        let snapshot = captureOrderSnapshot()
        var changed = false
        for (_, pdf) in loadedPDFs {
            for pageIndex in 0..<pdf.pageCount {
                guard let page = pdf.page(at: pageIndex) else { continue }
                for annotation in page.annotations where annotation.isPDFWidget {
                    if annotation.widgetFieldType == .button {
                        if annotation.buttonWidgetState != .offState {
                            annotation.buttonWidgetState = .offState
                            changed = true
                        }
                    } else if !(annotation.widgetStringValue ?? "").isEmpty {
                        annotation.widgetStringValue = ""
                        changed = true
                    }
                }
            }
        }
        guard changed else { return }
        markAnnotationsModified()
        refreshFormSummary()
        registerUndo(snapshot: snapshot, actionName: "Reset form")
    }

    // MARK: - Searchable scans

    func makeSearchable(includePagesWithText: Bool = false) {
        let hasEligiblePages = includePagesWithText ? ocrCandidatePageCount > 0 : hasScannedPages
        guard canPerformMutatingAction(), hasEligiblePages else { return }
        let snapshot = captureOrderSnapshot()
        let sourceDocuments: [(MemberDocument, Data)]
        do {
            let currentData = try currentPDFDataForExport()
            sourceDocuments = document.workspace.documents.compactMap { member in
                guard let data = currentData[member.id] else { return nil }
                return (member, data)
            }
            guard sourceDocuments.count == document.workspace.documents.count else {
                throw PDFOCRError.invalidPDF(memberName: document.workspace.title)
            }
        } catch {
            exportError = ExportError(message: userMessage(for: error, exporting: .pdf))
            return
        }

        operationProgress.start(title: "Making searchable", detail: "Preparing pages")
        let cancellation = OperationCancellationToken()
        let operationID = UUID()
        activeOCRCancellation = cancellation
        activeOCRID = operationID
        activeOCRTask = Task { [weak self, sourceDocuments, snapshot, cancellation, operationID] in
            guard let self else { return }
            do {
                let result = try await self.searchableData(
                    from: sourceDocuments,
                    includePagesWithText: includePagesWithText,
                    cancellation: cancellation,
                    operationID: operationID
                )
                if cancellation.isCancelled || Task.isCancelled {
                    throw PDFOCRError.cancelled
                }
                await MainActor.run {
                    guard self.activeOCRID == operationID else { return }
                    self.applyOCRResult(result)
                    self.operationProgress.finish()
                    self.activeOCRTask = nil
                    self.activeOCRCancellation = nil
                    self.activeOCRID = nil
                    self.markWorkspaceModified()
                    self.warnIfEditingWouldInvalidateSignatures()
                    self.undoManager?.registerUndo(withTarget: self) { vm in
                        guard vm.canPerformUndoMutation() else { return }
                        vm.restore(snapshot)
                    }
                    self.undoManager?.setActionName(L10n.string("undo.makeSearchable"))
                    self.editingStatus = .success(L10n.string("status.ocr.searchableNow"))
                }
            } catch {
                await MainActor.run {
                    guard self.activeOCRID == operationID else { return }
                    self.operationProgress.finish()
                    self.activeOCRTask = nil
                    self.activeOCRCancellation = nil
                    self.activeOCRID = nil
                    if let ocrError = error as? PDFOCRError, ocrError == .cancelled {
                        self.editingStatus = .warning(PDFOCRError.cancelled.errorDescription ?? "Making this document searchable was cancelled.")
                    } else if error is CancellationError {
                        self.editingStatus = .warning(PDFOCRError.cancelled.errorDescription ?? "Making this document searchable was cancelled.")
                    } else {
                        self.exportError = ExportError(message: self.userMessage(for: error, exporting: .pdf))
                    }
                }
            }
        }
    }

    private func searchableData(
        from sourceDocuments: [(MemberDocument, Data)],
        includePagesWithText: Bool,
        cancellation: OperationCancellationToken,
        operationID: UUID
    ) async throws -> PDFOCRResult {
        let progressThrottle = ProgressUpdateThrottle()
        return try await PDFOCRService.makeSearchable(
            documents: sourceDocuments,
            includePagesWithText: includePagesWithText,
            progress: { progress in
                guard progressThrottle.shouldEmit(progress) else { return }
                Task { @MainActor [weak self] in
                    guard self?.activeOCRID == operationID,
                          self?.operationProgress.isActive == true else { return }
                    self?.operationProgress.update(
                        fraction: progress,
                        detail: "\(Int((progress * 100).rounded()))%"
                    )
                }
            },
            isCancelled: {
                cancellation.isCancelled || Task.isCancelled
            }
        )
    }

    private func applyOCRResult(_ result: PDFOCRResult) {
        for (memberID, data) in result.dataByMemberID {
            document.memberPDFData[memberID] = data
        }
        loadedPDFs = document.workspace.documents.compactMap { member in
            guard let data = result.dataByMemberID[member.id] ?? document.memberPDFData[member.id],
                  let pdf = PDFDocument(data: data) else {
                return nil
            }
            return (member, pdf)
        }
        textAnalysisCache.removeAll()
        rebuild()
    }

    // MARK: - Decorations

    func decoration(of kind: PageDecoration.Kind) -> PageDecoration? {
        document.workspace.decorations.first { $0.kind == kind && $0.pageRefID == nil }
    }

    func isDecorationEnabled(_ kind: PageDecoration.Kind) -> Bool {
        decoration(of: kind)?.isEnabled == true
    }

    func decorationText(for kind: PageDecoration.Kind) -> String {
        decoration(of: kind)?.text ?? defaultDecoration(for: kind).text
    }

    func decorationPrefix(for kind: PageDecoration.Kind) -> String {
        decoration(of: kind)?.prefix ?? defaultDecoration(for: kind).prefix
    }

    func decorationStartNumber(for kind: PageDecoration.Kind) -> Int {
        decoration(of: kind)?.startNumber ?? defaultDecoration(for: kind).startNumber
    }

    func decorationFontSize(for kind: PageDecoration.Kind) -> Double {
        Double(decoration(of: kind)?.fontSize ?? defaultDecoration(for: kind).fontSize)
    }

    func decorationOpacity(for kind: PageDecoration.Kind) -> Double {
        decoration(of: kind)?.opacity ?? defaultDecoration(for: kind).opacity
    }

    func decorationSwatch(for kind: PageDecoration.Kind) -> PageDecorationSwatch {
        decoration(of: kind)?.swatch ?? defaultDecoration(for: kind).swatch
    }

    func setDecoration(_ kind: PageDecoration.Kind, enabled: Bool) {
        var decorations = document.workspace.decorations
        if let index = decorations.firstIndex(where: { $0.kind == kind && $0.pageRefID == nil }) {
            if enabled {
                decorations[index].isEnabled = true
            } else {
                decorations.remove(at: index)
            }
        } else if enabled {
            decorations.append(defaultDecoration(for: kind))
        }
        replaceDecorations(decorations, actionName: decorationActionName(for: kind))
    }

    func setDecorationText(_ kind: PageDecoration.Kind, text: String) {
        if kind == .watermark,
           text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            setDecoration(kind, enabled: false)
            return
        }
        updateDecoration(kind, actionName: decorationActionName(for: kind)) { decoration in
            decoration.text = text
        }
    }

    func setDecorationPrefix(_ kind: PageDecoration.Kind, prefix: String) {
        updateDecoration(kind, actionName: decorationActionName(for: kind)) { decoration in
            decoration.prefix = prefix
        }
    }

    func setDecorationStartNumber(_ kind: PageDecoration.Kind, startNumber: Int) {
        updateDecoration(kind, actionName: decorationActionName(for: kind)) { decoration in
            decoration.startNumber = max(0, startNumber)
        }
    }

    func setDecorationFontSize(_ kind: PageDecoration.Kind, fontSize: Double) {
        updateDecoration(kind, actionName: decorationActionName(for: kind)) { decoration in
            decoration.fontSize = CGFloat(min(max(fontSize, 6), 96))
        }
    }

    func setDecorationOpacity(_ kind: PageDecoration.Kind, opacity: Double) {
        updateDecoration(kind, actionName: decorationActionName(for: kind)) { decoration in
            decoration.opacity = min(max(opacity, 0.05), 1)
        }
    }

    func setDecorationSwatch(_ kind: PageDecoration.Kind, swatch: PageDecorationSwatch) {
        updateDecoration(kind, actionName: decorationActionName(for: kind)) { decoration in
            decoration.swatch = swatch
        }
    }

    private func updateDecoration(_ kind: PageDecoration.Kind,
                                  actionName: String,
                                  mutate: (inout PageDecoration) -> Void) {
        var decorations = document.workspace.decorations
        let index: Int
        if let existingIndex = decorations.firstIndex(where: { $0.kind == kind && $0.pageRefID == nil }) {
            index = existingIndex
        } else {
            decorations.append(defaultDecoration(for: kind))
            index = decorations.count - 1
        }
        mutate(&decorations[index])
        replaceDecorations(decorations, actionName: actionName)
    }

    private func replaceDecorations(_ decorations: [PageDecoration], actionName: String) {
        guard canPerformMutatingAction() else { return }
        let previous = document.workspace.decorations
        guard previous != decorations else { return }
        document.workspace.decorations = decorations
        decorationStateVersion &+= 1
        if let selectedStampDecorationID,
           !decorations.contains(where: { $0.id == selectedStampDecorationID }) {
            self.selectedStampDecorationID = nil
        }
        markAnnotationsModified()
        undoManager?.registerUndo(withTarget: self) { vm in
            guard vm.canPerformUndoMutation() else { return }
            vm.replaceDecorations(previous, actionName: actionName)
        }
        undoManager?.setActionName(actionName)
    }

    private func defaultDecoration(for kind: PageDecoration.Kind) -> PageDecoration {
        switch kind {
        case .watermark:
            return .watermark()
        case .pageNumber:
            return .pageNumber()
        case .bates:
            return .bates()
        case .stamp:
            return PageDecoration(kind: .stamp)
        }
    }

    private func decorationActionName(for kind: PageDecoration.Kind) -> String {
        switch kind {
        case .watermark:
            return L10n.string("undo.changeWatermark")
        case .pageNumber:
            return L10n.string("undo.changePageNumbers")
        case .bates:
            return L10n.string("undo.changeBatesStamp")
        case .stamp:
            return L10n.string("undo.changeStamp")
        }
    }

    private func warnIfEditingWouldInvalidateSignatures() {
        if hasCryptographicSignaturePlacement {
            editingStatus = .warning("Editing after a digital signature invalidates existing signatures.")
        } else if hasThirdPartyCryptographicSignature {
            editingStatus = .warning("This document already contains a digital signature from another source. Editing it will invalidate that signature.")
        }
    }

    func selectPage(_ ref: PageRef, extendingSelection: Bool = false) {
        if extendingSelection {
            if selectedPageRefIDs.contains(ref.id) {
                selectedPageRefIDs.remove(ref.id)
            } else {
                selectedPageRefIDs.insert(ref.id)
            }
            selectedPageRefID = selectedPageRefIDs.first ?? ref.id
        } else {
            selectedPageRefID = ref.id
            selectedPageRefIDs = [ref.id]
        }
        if let pageIndex = combinedPageIndex(for: ref) {
            NotificationCenter.default.post(name: .orifoldJumpToPageIndex, object: pageIndex)
        }
    }

    func selectDocument(_ member: MemberDocument) {
        guard let firstPageRefID = member.pageRefs.first,
              let ref = document.workspace.pageOrder.first(where: { $0.id == firstPageRefID }) else {
            selectedPageRefID = nil
            selectedPageRefIDs = []
            return
        }
        selectPage(ref)
    }

    func pageRefsForCurrentSelection(including ref: PageRef) -> [PageRef] {
        let selectedIDs = selectedPageRefIDs.isEmpty ? [ref.id] : selectedPageRefIDs.union([ref.id])
        return document.workspace.pageOrder.filter { selectedIDs.contains($0.id) }
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
        guard canPerformMutatingAction() else { return }
        draggedPageRefID = ref.id
    }

    func moveDraggedPage(to targetRef: PageRef) -> Bool {
        guard canPerformMutatingAction() else { return false }
        guard let draggedPageRefID,
              draggedPageRefID != targetRef.id,
              let sourceRef = document.workspace.pageOrder.first(where: { $0.id == draggedPageRefID }),
              let memberIndex = document.workspace.documents.firstIndex(where: { $0.id == targetRef.memberDocId }),
              let targetIndex = document.workspace.documents[memberIndex].pageRefs.firstIndex(of: targetRef.id)
        else {
            self.draggedPageRefID = nil
            return false
        }

        let didMove: Bool
        if sourceRef.memberDocId == targetRef.memberDocId,
           let sourceIndex = document.workspace.documents[memberIndex].pageRefs.firstIndex(of: sourceRef.id) {
            let destination = targetIndex > sourceIndex ? targetIndex + 1 : targetIndex
            didMove = movePage(sourceRef, toIndex: destination)
        } else {
            didMove = movePage(sourceRef, after: targetRef)
        }
        guard didMove else {
            self.draggedPageRefID = nil
            return false
        }
        selectedPageRefID = sourceRef.id
        self.draggedPageRefID = nil
        return true
    }

    // MARK: - Annotations

    func editableTextBlock(at pagePoint: CGPoint, on page: PDFPage, in pdfDocument: PDFDocument?) -> (pageRef: PageRef, block: EditableTextBlock, sourceFormat: PDFTextEditFormat)? {
        guard let ref = pageRef(for: page, in: pdfDocument),
              let lookup = memberPDF(for: ref),
              let localIdx = localIndex(ref: ref, memberIndex: lookup.documentIndex) else {
            return nil
        }
        let analysis = textAnalysis(for: ref, page: page, memberID: ref.memberDocId, localIndex: localIdx)
        // If the click lands inside a previously-placed replacement (editedBounds) or the
        // original source area (sourceBounds), re-route to that operation so the editor
        // opens with the current replacement text and updates the op in-place rather than
        // accumulating a second operation for the same location.
        if let pageState = document.workspace.pageEditStates.first(where: { $0.pageRefID == ref.id }),
           let existingOp = pageState.operations.first(where: {
               $0.editedBounds.insetBy(dx: -3, dy: -3).contains(pagePoint) ||
               $0.sourceBounds.insetBy(dx: -2, dy: -2).contains(pagePoint)
           }) {
            let syntheticBounds = reopenedBounds(for: existingOp)
            let sourceFormat = originalFormat(for: existingOp, in: analysis)
            let shouldPreserveReplacementStyle = existingOp.didManuallyChangeStyle
            let reopenedFontName = shouldPreserveReplacementStyle ? existingOp.fontName : sourceFormat.fontName
            let reopenedFontSize = shouldPreserveReplacementStyle ? existingOp.fontSize : sourceFormat.fontSize
            let reopenedTextColor = shouldPreserveReplacementStyle ? existingOp.textColor : sourceFormat.textColor
            let reopenedAlignment = shouldPreserveReplacementStyle ? existingOp.alignment : sourceFormat.alignment
            let reopenedUnderline = shouldPreserveReplacementStyle ? existingOp.underline : sourceFormat.underline
            let syntheticBlock = EditableTextBlock(
                id: existingOp.sourceBlockID,
                pageRefID: ref.id,
                text: existingOp.replacementText,
                bounds: syntheticBounds,
                lines: [],
                columnBounds: existingOp.columnBounds,
                fontName: reopenedFontName,
                fontSize: reopenedFontSize,
                textColor: reopenedTextColor,
                alignment: reopenedAlignment,
                underline: reopenedUnderline,
                rotation: 0,
                baseline: syntheticBounds.minY,
                confidence: .high
            )
            return (ref, syntheticBlock, sourceFormat)
        }
        let block = textAnalysisEngine.hitTest(pagePoint, in: analysis) ??
            insertionTextBlock(at: pagePoint, pageRefID: ref.id, page: page, nearbyBlocks: analysis.blocks)
        return (ref, block, PDFTextEditFormat(block: block))
    }

    private func reopenedBounds(for operation: PDFTextEditOperation) -> CGRect {
        let edited = operation.editedBounds.standardized
        guard !operation.didManuallyReposition,
              !operation.didManuallyResizeWidth,
              operation.sourceBounds.standardized.width > 0 else {
            return edited
        }
        let source = operation.sourceBounds.standardized
        let height = operation.didManuallyResizeHeight ? edited.height : max(1, edited.height)
        return CGRect(
            x: source.minX,
            y: edited.maxY - height,
            width: source.width,
            height: height
        )
    }

    /// Resolves the true original formatting for a reopened edit. A fresh text-analysis
    /// pass over the pristine original page is the most accurate source when it can
    /// confidently re-locate the same paragraph (exact id match, or — since re-analysis
    /// assigns every block a brand-new random id, see `PDFTextAnalysisEngine` — the
    /// closest block to where this operation's original text sat). When no analysis
    /// block can be found nearby at all (e.g. the page was reordered, or analysis
    /// otherwise can't re-derive a match), fall back to the format captured once at this
    /// edit's creation (`operation.originalFormat`) rather than silently reusing the
    /// operation's own current/edited styling as if it were the original — that fallback
    /// is what previously let Match/Copy/Restore "restore" an edit right back to its own
    /// already-wrong formatting.
    private func originalFormat(for operation: PDFTextEditOperation, in analysis: PDFTextPageAnalysis) -> PDFTextEditFormat {
        if let exact = analysis.blocks.first(where: { $0.id == operation.sourceBlockID }) {
            return PDFTextEditFormat(block: exact)
        }
        let sourceBounds = operation.sourceBounds.standardized
        let sourceCenter = CGPoint(x: sourceBounds.midX, y: sourceBounds.midY)
        guard let nearest = closestTextBlock(to: sourceCenter, in: analysis.blocks, maxDistance: 80) else {
            return operation.originalFormat
        }
        return PDFTextEditFormat(block: nearest)
    }

    private func insertionTextBlock(at pagePoint: CGPoint, pageRefID: UUID, page: PDFPage, nearbyBlocks: [EditableTextBlock]) -> EditableTextBlock {
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
        let nearbyStyle = nearbyTextStyle(near: pagePoint, in: nearbyBlocks)
        return EditableTextBlock(
            pageRefID: pageRefID,
            text: "",
            bounds: bounds,
            lines: [],
            columnBounds: pageBounds.insetBy(dx: 12, dy: 12),
            fontName: nearbyStyle?.fontName ?? "Helvetica",
            fontSize: nearbyStyle?.fontSize ?? 14,
            textColor: nearbyStyle?.textColor ?? .documentText,
            alignment: nearbyStyle?.alignment,
            rotation: CGFloat(page.rotation),
            baseline: bounds.minY,
            confidence: .medium
        )
    }

    private func nearbyTextStyle(near point: CGPoint, in blocks: [EditableTextBlock]) -> EditableTextBlock? {
        closestTextBlock(to: point, in: blocks, maxDistance: 160)
    }

    /// Finds the closest candidate block to `point` for "match the nearby style"
    /// purposes. Prefers blocks whose reading column actually contains `point` over
    /// whatever block is merely nearest by raw center-to-point distance, so a caption in
    /// an adjacent column or a table cell in the next row over never wins against the
    /// paragraph directly above/below in the same column — the case a plain nearest-rect
    /// search gets wrong most often in dense, multi-column layouts.
    private func closestTextBlock(to point: CGPoint, in blocks: [EditableTextBlock], maxDistance: CGFloat) -> EditableTextBlock? {
        let candidates = blocks.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !candidates.isEmpty else { return nil }

        func isSameColumn(_ block: EditableTextBlock) -> Bool {
            guard let column = block.columnBounds else { return false }
            return point.x >= column.minX - 4 && point.x <= column.maxX + 4
        }

        let sameColumnCandidates = candidates.filter(isSameColumn)
        let pool = sameColumnCandidates.isEmpty ? candidates : sameColumnCandidates
        guard let nearest = pool.min(by: { distanceSquared(from: point, to: $0.bounds) < distanceSquared(from: point, to: $1.bounds) }),
              distanceSquared(from: point, to: nearest.bounds) <= maxDistance * maxDistance else {
            return nil
        }
        return nearest
    }

    private func distanceSquared(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let box = rect.standardized
        let dx: CGFloat
        if point.x < box.minX {
            dx = box.minX - point.x
        } else if point.x > box.maxX {
            dx = point.x - box.maxX
        } else {
            dx = 0
        }
        let dy: CGFloat
        if point.y < box.minY {
            dy = box.minY - point.y
        } else if point.y > box.maxY {
            dy = point.y - box.maxY
        } else {
            dy = 0
        }
        return dx * dx + dy * dy
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
        alignment: NSTextAlignment,
        underline: Bool = false,
        didManuallyReposition: Bool = false,
        didManuallyResizeWidth: Bool = false,
        didManuallyResizeHeight: Bool = false,
        didManuallyChangeStyle: Bool = false,
        didApplyMatchedGeometry: Bool = false,
        didRestoreOriginalStyle: Bool = false
    ) -> Bool {
        guard canPerformMutatingAction() else { return false }
        guard let basePage = originalBasePage(for: pageRef) else {
            showEditMessage("Orifold could not access the original page for editing.", isError: true)
            return false
        }

        let previousSnapshot = captureInlineTextEditSnapshot()
        var operation = PDFTextEditOperation(
            pageRefID: pageRef.id,
            sourceBlockID: sourceBlock.id,
            sourceBounds: sourceBlock.bounds,
            sourceLineBounds: sourceBlock.lines.map(\.bounds),
            sourceText: sourceBlock.text,
            editedBounds: editedBounds,
            columnBounds: sourceBlock.columnBounds,
            replacementText: replacementText,
            fontName: fontName,
            fontSize: fontSize,
            textColor: CodableColor(nsColor: textColor),
            alignment: CodableTextAlignment(alignment),
            underline: underline,
            // `sourceBlock.alignment` is nil when detection couldn't determine one — in
            // that case trust the alignment actually being committed (which, whenever
            // `didManuallyChangeStyle` is false, is exactly what the original showed)
            // rather than silently defaulting to `.left` and losing it on next reopen.
            originalFormat: PDFTextEditFormat(
                fontName: sourceBlock.fontName,
                fontSize: sourceBlock.fontSize,
                textColor: sourceBlock.textColor,
                alignment: sourceBlock.alignment ?? CodableTextAlignment(alignment),
                underline: sourceBlock.underline,
                bounds: sourceBlock.bounds,
                columnBounds: sourceBlock.columnBounds
            ),
            isInsertion: sourceBlock.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && sourceBlock.lines.isEmpty,
            didManuallyReposition: didManuallyReposition,
            didManuallyResizeWidth: didManuallyResizeWidth,
            didManuallyResizeHeight: didManuallyResizeHeight,
            didManuallyChangeStyle: didManuallyChangeStyle,
            didApplyMatchedGeometry: didApplyMatchedGeometry
        )
        // When updating an existing op (same sourceBlockID), preserve the original
        // sourceBounds so erase targeting and edit identity remain tied to the
        // original text even when the user re-edits a previously-placed replacement.
        if let stateIndex = document.workspace.pageEditStates.firstIndex(where: { $0.pageRefID == pageRef.id }),
           let existingOp = document.workspace.pageEditStates[stateIndex].operations.first(where: { $0.sourceBlockID == sourceBlock.id }) {
            operation.sourceBounds = existingOp.sourceBounds
            operation.sourceLineBounds = existingOp.sourceLineBounds
            operation.didApplyMatchedGeometry = operation.didApplyMatchedGeometry || existingOp.didApplyMatchedGeometry
            operation.sourceText = existingOp.sourceText.isEmpty ? operation.sourceText : existingOp.sourceText
            operation.columnBounds = operation.columnBounds ?? existingOp.columnBounds
            // Never re-derive: `sourceBlock` here may itself be the synthetic
            // reopened-edit stand-in (already-edited font/color/bounds), not the true
            // original PDF text, so the *only* trustworthy source is whatever was
            // captured the first time this block was edited.
            operation.originalFormat = existingOp.originalFormat
            operation.isInsertion = operation.isInsertion || existingOp.isInsertion
            operation.didManuallyReposition = operation.didManuallyReposition || existingOp.didManuallyReposition
            operation.didManuallyResizeWidth = operation.didManuallyResizeWidth || existingOp.didManuallyResizeWidth
            operation.didManuallyResizeHeight = operation.didManuallyResizeHeight || existingOp.didManuallyResizeHeight
            operation.didManuallyChangeStyle = didRestoreOriginalStyle
                ? operation.didManuallyChangeStyle
                : (operation.didManuallyChangeStyle || existingOp.didManuallyChangeStyle)
        }
        // The live editor has already committed its page-space box. Keep that geometry
        // intact, then let measuredBounds expand only as needed for longer text.
        operation.editedBounds = PDFEditedPageRenderer.measuredBounds(
            for: operation,
            pageBounds: basePage.bounds(for: .cropBox),
            sourcePage: basePage
        )
        if let stateIndex = document.workspace.pageEditStates.firstIndex(where: { $0.pageRefID == pageRef.id }) {
            document.workspace.pageEditStates[stateIndex].operations.removeAll { $0.sourceBlockID == sourceBlock.id }
            document.workspace.pageEditStates[stateIndex].operations.append(operation)
        } else {
            document.workspace.pageEditStates.append(PageEditState(pageRefID: pageRef.id, operations: [operation]))
        }
        let operations = document.workspace.pageEditStates.first(where: { $0.pageRefID == pageRef.id })?.operations ?? []
        guard regenerateEditedPage(pageRef: pageRef, operations: operations) else {
            document.workspace.pageEditStates = previousSnapshot.editStates
            showEditMessage("Orifold could not regenerate that edited page. The original page is unchanged.", isError: true)
            return false
        }

        rebuild()
        markWorkspaceModified()
        warnIfEditingWouldInvalidateSignatures()

        registerIsolatedUndo {
            undoManager?.registerUndo(withTarget: self) { vm in
                guard vm.canPerformUndoMutation() else { return }
                vm.restoreInlineTextEditSnapshot(previousSnapshot, actionName: L10n.string("undo.editPDFText"))
            }
            undoManager?.setActionName(L10n.string("undo.editPDFText"))
        }
        PetBuddyHook.trigger(.edit)
        return true
    }

    /// Loads the pristine (pre-any-edit) version of the page backing `pageRef`.
    /// Regeneration always starts from this page so repeated edits never stack erase
    /// patches on top of previously-regenerated content, and reverting simply means
    /// regenerating with fewer (or zero) operations.
    private func originalBasePage(for pageRef: PageRef) -> PDFPage? {
        guard let lookup = memberPDF(for: pageRef),
              let localIdx = localIndex(ref: pageRef, memberIndex: lookup.documentIndex),
              lookup.pdf.page(at: localIdx) != nil else { return nil }
        let baseData = originalMemberPDFData[pageRef.memberDocId] ?? document.memberPDFData[pageRef.memberDocId]
        let originalPageIndex = pageRef.sourcePageIndex >= 0 ? pageRef.sourcePageIndex : localIdx
        guard let baseData,
              let basePDF = PDFDocument(data: baseData),
              let basePage = basePDF.page(at: originalPageIndex) else { return nil }
        return basePage
    }

    /// Rebuilds the live page for `pageRef` from its pristine original, applying
    /// `operations` (empty = restore the original page), while carrying over rotation
    /// and any annotations the user already placed on the current page. Serializes the
    /// member PDF and reloads it fresh so PDFKit cannot reuse stale render caches.
    private func regenerateEditedPage(pageRef: PageRef, operations: [PDFTextEditOperation]) -> Bool {
        guard let lookup = memberPDF(for: pageRef),
              let localIdx = localIndex(ref: pageRef, memberIndex: lookup.documentIndex),
              let basePage = originalBasePage(for: pageRef),
              let regenerated = PDFEditedPageRenderer.regeneratedPage(from: basePage, applying: operations) else {
            return false
        }

        let currentPage = lookup.pdf.page(at: localIdx)
        let preservedRotation = currentPage?.rotation ?? regenerated.rotation
        let preservedAnnotations = currentPage?.annotations ?? []
        lookup.pdf.removePage(at: localIdx)
        regenerated.rotation = preservedRotation
        lookup.pdf.insert(regenerated, at: localIdx)
        preservedAnnotations.forEach { regenerated.addAnnotation($0) }
        textAnalysisCache.removeValue(forKey: pageRef.id)

        let serialized = PDFSerializer.data(from: lookup.pdf)
        if let serialized, let freshPDF = PDFDocument(data: serialized) {
            document.memberPDFData[pageRef.memberDocId] = serialized
            loadedPDFs[lookup.documentIndex] = (loadedPDFs[lookup.documentIndex].0, freshPDF)
        } else {
            NSLog("[Orifold] Warning: could not reload fresh PDF after inline edit on page %@; using mutated document in place.", pageRef.id.uuidString)
            if let serialized {
                document.memberPDFData[pageRef.memberDocId] = serialized
            }
        }
        return true
    }

    // MARK: - Inline text edit revert

    struct InlineTextEditListItem: Identifiable, Equatable {
        var id: UUID
        var pageRefID: UUID
        var pageNumber: Int
        var memberName: String
        var originalText: String
        var replacementText: String
        var isInsertion: Bool
    }

    var hasInlineTextEdits: Bool {
        document.workspace.pageEditStates.contains { !$0.operations.isEmpty }
    }

    func hasInlineTextEditOperation(pageRefID: UUID, sourceBlockID: UUID) -> Bool {
        document.workspace.pageEditStates
            .first(where: { $0.pageRefID == pageRefID })?
            .operations.contains(where: { $0.sourceBlockID == sourceBlockID }) ?? false
    }

    /// All committed inline text edits, ordered by the workspace page order, for the
    /// inspector's "Text Edits" list.
    func inlineTextEditListItems() -> [InlineTextEditListItem] {
        var items: [InlineTextEditListItem] = []
        for (index, ref) in document.workspace.pageOrder.enumerated() {
            guard let state = document.workspace.pageEditStates.first(where: { $0.pageRefID == ref.id }) else { continue }
            let memberName = document.workspace.documents.first(where: { $0.id == ref.memberDocId })?.displayName ?? ""
            for operation in state.operations {
                items.append(InlineTextEditListItem(
                    id: operation.id,
                    pageRefID: ref.id,
                    pageNumber: index + 1,
                    memberName: memberName,
                    originalText: operation.sourceText,
                    replacementText: operation.replacementText,
                    isInsertion: operation.isInsertion
                ))
            }
        }
        return items
    }

    /// Removes a single committed text edit and re-renders its page from the pristine
    /// original with the remaining edits, restoring the untouched document appearance
    /// for that spot. Undoable.
    @discardableResult
    func revertInlineTextEdit(pageRefID: UUID, where matches: (PDFTextEditOperation) -> Bool) -> Bool {
        guard canPerformMutatingAction() else { return false }
        guard let stateIndex = document.workspace.pageEditStates.firstIndex(where: { $0.pageRefID == pageRefID }),
              document.workspace.pageEditStates[stateIndex].operations.contains(where: matches),
              let pageRef = document.workspace.pageOrder.first(where: { $0.id == pageRefID }) else {
            return false
        }
        let previousSnapshot = captureInlineTextEditSnapshot()
        var remaining = document.workspace.pageEditStates[stateIndex].operations
        remaining.removeAll(where: matches)
        if remaining.isEmpty {
            document.workspace.pageEditStates.remove(at: stateIndex)
        } else {
            document.workspace.pageEditStates[stateIndex].operations = remaining
        }
        guard regenerateEditedPage(pageRef: pageRef, operations: remaining) else {
            document.workspace.pageEditStates = previousSnapshot.editStates
            showEditMessage("Orifold could not restore that page. The edit was left in place.", isError: true)
            return false
        }
        rebuild()
        markWorkspaceModified()
        undoManager?.registerUndo(withTarget: self) { vm in
            guard vm.canPerformUndoMutation() else { return }
            vm.restoreInlineTextEditSnapshot(previousSnapshot, actionName: L10n.string("undo.revertTextEdit"))
        }
        undoManager?.setActionName(L10n.string("undo.revertTextEdit"))
        return true
    }

    @discardableResult
    func revertInlineTextEdit(pageRefID: UUID, operationID: UUID) -> Bool {
        revertInlineTextEdit(pageRefID: pageRefID) { $0.id == operationID }
    }

    @discardableResult
    func revertInlineTextEdit(pageRefID: UUID, sourceBlockID: UUID) -> Bool {
        revertInlineTextEdit(pageRefID: pageRefID) { $0.sourceBlockID == sourceBlockID }
    }

    /// Removes every committed text edit in the workspace and restores each touched page
    /// to its pristine original rendering (annotations and rotations are kept). Undoable.
    @discardableResult
    func revertAllInlineTextEdits() -> Bool {
        guard canPerformMutatingAction(), hasInlineTextEdits else { return false }
        let previousSnapshot = captureInlineTextEditSnapshot()
        let states = document.workspace.pageEditStates
        document.workspace.pageEditStates = []
        var failedPageRefIDs: [UUID] = []
        for state in states {
            guard let pageRef = document.workspace.pageOrder.first(where: { $0.id == state.pageRefID }) else { continue }
            if !regenerateEditedPage(pageRef: pageRef, operations: []) {
                failedPageRefIDs.append(state.pageRefID)
            }
        }
        if !failedPageRefIDs.isEmpty {
            // Keep the edits we could not visually revert so the document and the edit
            // list stay consistent.
            document.workspace.pageEditStates = states.filter { failedPageRefIDs.contains($0.pageRefID) }
            showEditMessage("Orifold could not restore some pages; their edits were left in place.", isError: true)
        }
        rebuild()
        markWorkspaceModified()
        undoManager?.registerUndo(withTarget: self) { vm in
            guard vm.canPerformUndoMutation() else { return }
            vm.restoreInlineTextEditSnapshot(previousSnapshot, actionName: L10n.string("undo.revertAllTextEdits"))
        }
        undoManager?.setActionName(L10n.string("undo.revertAllTextEdits"))
        return failedPageRefIDs.isEmpty
    }

    @discardableResult
    func applyHighlight(to selection: PDFSelection) -> Bool {
        guard canPerformMutatingAction() else { return false }
        var didAddAnnotation = false
        selection.selectionsByLine().forEach { line in
            guard let page = line.pages.first else { return }
            let bounds = line.bounds(for: page)
            guard !hasEquivalentAnnotation(on: page, subtype: .highlight, bounds: bounds) else { return }
            let ann = PDFAnnotation(bounds: bounds, forType: .highlight, withProperties: nil)
            ann.color = annotationColor.withAlphaComponent(0.4)
            page.addAnnotation(ann)
            undoManager?.registerUndo(withTarget: self) { vm in
                guard vm.canPerformUndoMutation() else { return }
                page.removeAnnotation(ann)
            }
            didAddAnnotation = true
        }
        if didAddAnnotation {
            markAnnotationsModified()
            undoManager?.setActionName(L10n.string("undo.highlight"))
            PetBuddyHook.trigger(.highlight)
        }
        return didAddAnnotation
    }

    @discardableResult
    func addNote(at pagePoint: CGPoint, on page: PDFPage) -> PDFAnnotation? {
        guard canPerformMutatingAction() else { return nil }
        let size: CGFloat = 24
        let bounds = CGRect(x: pagePoint.x - size / 2, y: pagePoint.y - size / 2,
                            width: size, height: size)
        let ann = PDFAnnotation(bounds: bounds, forType: .text, withProperties: nil)
        ann.contents = ""
        ann.color = annotationColor
        ann.setValue(true, forAnnotationKey: Self.draftTextAnnotationKey)
        page.addAnnotation(ann)
        markAnnotationsModified()
        undoManager?.registerUndo(withTarget: self) { vm in
            guard vm.canPerformUndoMutation() else { return }
            page.removeAnnotation(ann)
        }
        undoManager?.setActionName(L10n.string("undo.addNote"))
        PetBuddyHook.trigger(.note)
        return ann
    }

    @discardableResult
    func addTextBox(at pagePoint: CGPoint, on page: PDFPage) -> PDFAnnotation? {
        guard canPerformMutatingAction() else { return nil }
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
        undoManager?.registerUndo(withTarget: self) { vm in
            guard vm.canPerformUndoMutation() else { return }
            page.removeAnnotation(ann)
        }
        undoManager?.setActionName(L10n.string("undo.addTextBox"))
        return ann
    }

    @discardableResult
    func addEditableTextOverlay(from selection: PDFSelection, on page: PDFPage) -> PDFAnnotation? {
        guard canPerformMutatingAction() else { return nil }
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
        undoManager?.registerUndo(withTarget: self) { vm in
            guard vm.canPerformUndoMutation() else { return }
            page.removeAnnotation(ann)
        }
        undoManager?.setActionName(L10n.string("undo.replacePDFText"))
        return ann
    }

    func showEditWarning(_ warning: PDFTextEditWarning) {
        editingStatus = .warning(warning.message)
    }

    func showEditMessage(_ message: String, severity: EditingStatus.Severity) {
        editingStatus = EditingStatus(message: message, severity: severity)
    }

    func showEditMessage(_ message: String, isError: Bool = false) {
        editingStatus = isError ? .error(message) : .warning(message)
    }

    func addInkStroke(path: NSBezierPath, on page: PDFPage) {
        guard canPerformMutatingAction() else { return }
        guard path.elementCount > 1, !path.bounds.isEmpty else { return }
        let bounds = path.bounds.insetBy(dx: -2, dy: -2)
        let localPath = inkPath(path, offsetBy: CGSize(width: -bounds.minX, height: -bounds.minY))
        let ann = PDFAnnotation(bounds: bounds, forType: .ink, withProperties: nil)
        ann.color = inkColor
        ann.border = PDFBorder()
        ann.border?.lineWidth = 2
        ann.add(localPath)
        page.addAnnotation(ann)
        markAnnotationsModified()
        undoManager?.registerUndo(withTarget: self) { vm in
            guard vm.canPerformUndoMutation() else { return }
            page.removeAnnotation(ann)
        }
        undoManager?.setActionName(L10n.string("undo.inkStroke"))
        PetBuddyHook.trigger(.ink)
    }

    private func inkPath(_ path: NSBezierPath, offsetBy offset: CGSize) -> NSBezierPath {
        let translated = NSBezierPath()
        translated.lineWidth = path.lineWidth
        translated.lineCapStyle = path.lineCapStyle
        translated.lineJoinStyle = path.lineJoinStyle
        translated.miterLimit = path.miterLimit
        translated.flatness = path.flatness

        var pts = [NSPoint](repeating: .zero, count: 3)
        func shifted(_ point: NSPoint) -> NSPoint {
            NSPoint(x: point.x + offset.width, y: point.y + offset.height)
        }

        for index in 0..<path.elementCount {
            let element = path.element(at: index, associatedPoints: &pts)
            switch element {
            case .moveTo:
                translated.move(to: shifted(pts[0]))
            case .lineTo:
                translated.line(to: shifted(pts[0]))
            case .curveTo, .cubicCurveTo:
                translated.curve(to: shifted(pts[2]),
                                 controlPoint1: shifted(pts[0]),
                                 controlPoint2: shifted(pts[1]))
            case .quadraticCurveTo:
                translated.curve(to: shifted(pts[1]),
                                 controlPoint1: shifted(pts[0]),
                                 controlPoint2: shifted(pts[0]))
            case .closePath:
                translated.close()
            @unknown default:
                break
            }
        }
        return translated
    }

    func deleteSelectedAnnotation() {
        guard canPerformMutatingAction() else { return }
        if selectedAnnotation == nil, selectedStampDecorationID != nil {
            deleteSelectedStampDecoration()
            return
        }
        guard let ann = selectedAnnotation, let page = ann.page else {
            showEditWarning(.annotationCreationFailed)
            return
        }
        let removedSignature = signaturePlacement(for: ann)
        let removedIdentity = removedSignature.flatMap { signingIdentitiesByPlacementID[$0.id] }
        page.removeAnnotation(ann)
        if let removedSignature {
            document.workspace.signatures.removeAll { $0.id == removedSignature.id }
            signingIdentitiesByPlacementID.removeValue(forKey: removedSignature.id)
        }
        selectedAnnotation = nil
        selectedStampDecorationID = nil
        markAnnotationsModified()
        undoManager?.registerUndo(withTarget: self) { vm in
            guard vm.canPerformUndoMutation() else { return }
            page.addAnnotation(ann)
            if let removedSignature {
                vm.document.workspace.signatures.append(removedSignature)
                if let removedIdentity {
                    vm.signingIdentitiesByPlacementID[removedSignature.id] = removedIdentity
                }
            }
            vm.selectedAnnotation = ann
        }
        undoManager?.setActionName(L10n.string("undo.deleteAnnotation"))
    }

    @discardableResult
    func eraseMarkupAnnotation(at pagePoint: CGPoint, on page: PDFPage) -> Bool {
        guard canPerformMutatingAction() else { return false }
        guard let ann = erasableMarkupAnnotation(at: pagePoint, on: page) else {
            showEditMessage("Click a highlight, underline, or strikeout to erase it.", isError: true)
            return false
        }
        page.removeAnnotation(ann)
        if selectedAnnotation === ann {
            selectedAnnotation = nil
        }
        markAnnotationsModified()
        undoManager?.registerUndo(withTarget: self) { vm in
            guard vm.canPerformUndoMutation() else { return }
            page.addAnnotation(ann)
            vm.selectedAnnotation = ann
        }
        undoManager?.setActionName(L10n.string("undo.eraseMarkup"))
        return true
    }

    private func erasableMarkupAnnotation(at pagePoint: CGPoint, on page: PDFPage) -> PDFAnnotation? {
        page.annotations.reversed().first { annotation in
            Self.isErasableMarkup(annotation) &&
                annotation.bounds.insetBy(dx: -3, dy: -3).contains(pagePoint)
        }
    }

    private static func isErasableMarkup(_ annotation: PDFAnnotation) -> Bool {
        switch annotation.type {
        case "Highlight", "Underline", "StrikeOut":
            return true
        default:
            return false
        }
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

    func beginVisualSignaturePlacement(imageData: Data,
                                       kind: SignaturePlacement.Kind,
                                       signerName: String?) {
        guard canPerformSigningAction() else { return }
        pendingSignatureData = imageData
        pendingSignatureOptions = PendingSignaturePlacementOptions(
            kind: kind,
            signerName: signerName,
            signerIdentityRef: nil,
            reason: nil,
            location: nil,
            contactInfo: nil,
            subFilter: nil,
            timestampRequested: false
        )
        currentTool = .signature
        isShowingSignaturePalette = false
        isShowingStampPalette = false
        editingStatus = .warning("Click a page to place the signature.")
    }

    func beginCryptographicSignaturePlacement(imageData: Data,
                                              signerName: String,
                                              signerIdentityRef: String?,
                                              reason: String?,
                                              location: String?,
                                              contactInfo: String?,
                                              timestampRequested: Bool,
                                              identity: (any SigningIdentity)? = nil) {
        guard canPerformSigningAction() else { return }
        pendingSignatureData = imageData
        pendingSigningIdentity = identity
        pendingSignatureOptions = PendingSignaturePlacementOptions(
            kind: .cryptographic,
            signerName: signerName,
            signerIdentityRef: signerIdentityRef,
            reason: reason,
            location: location,
            contactInfo: contactInfo,
            subFilter: "ETSI.CAdES.detached",
            timestampRequested: timestampRequested
        )
        currentTool = .signature
        isShowingSignaturePalette = false
        isShowingStampPalette = false
        editingStatus = .warning("Click a page to place the digital signature.")
    }

    func cancelSignaturePlacement() {
        clearPendingSignaturePlacement()
        if currentTool == .signature {
            currentTool = .none
        }
        editingStatus = nil
    }

    private func clearPendingSignaturePlacement() {
        pendingSignatureData = nil
        pendingSignatureOptions = nil
        pendingSigningIdentity = nil
    }

    func beginStampPlacement(text: String, swatch: PageDecorationSwatch) {
        guard canPerformMutatingAction() else { return }
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }
        pendingStampOptions = PendingStampPlacementOptions(text: trimmedText, swatch: swatch)
        clearPendingSignaturePlacement()
        currentTool = .stamp
        isShowingSignaturePalette = false
        isShowingStampPalette = false
    }

    func resolveSigningIdentity(reference: String, signerName: String) throws -> any SigningIdentity {
        switch reference {
        case "p12":
            return try importPKCS12SigningIdentity()
        case "keychain":
            return try chooseKeychainSigningIdentity()
        case "self-signed":
            let request = SelfSignedIdentityRequest(commonName: signerName)
            return try SelfSignedSigningIdentityProvider.generate(request: request)
        default:
            throw SigningError.missingIdentity
        }
    }

    @discardableResult
    func placeSignature(imageData: Data, at pagePoint: CGPoint, on page: PDFPage, size: CGSize = CGSize(width: 120, height: 48)) -> PDFAnnotation? {
        guard canPerformSigningAction() else { return nil }
        guard let refID = pageRefID(for: page) else { return nil }
        let options = pendingSignatureOptions ?? .visualTyped
        let identity = pendingSigningIdentity
        let placementSize = options.kind == .cryptographic ? CGSize(width: 240, height: 112) : size
        let bounds = CGRect(
            x: pagePoint.x - placementSize.width / 2,
            y: pagePoint.y - placementSize.height / 2,
            width: placementSize.width, height: placementSize.height
        )
        let placement = SignaturePlacement(
            pageRefId: refID,
            imageData: imageData,
            rect: bounds,
            kind: options.kind,
            signerName: options.signerName,
            signedAt: Date(),
            signerIdentityRef: options.signerIdentityRef,
            reason: options.reason,
            location: options.location,
            contactInfo: options.contactInfo,
            subFilter: options.subFilter,
            timestampApplied: false
        )
        document.workspace.signatures.append(placement)
        if options.kind == .cryptographic, let identity {
            signingIdentitiesByPlacementID[placement.id] = identity
        }
        markAnnotationsModified(warnAboutSignatureInvalidation: options.kind != .cryptographic)
        clearPendingSignaturePlacement()

        if let image = NSImage(data: imageData) {
            let ann = SignatureImageAnnotation(bounds: bounds, image: image, placementID: placement.id)
            page.addAnnotation(ann)
            selectedAnnotation = ann
            let placementID = placement.id
            undoManager?.registerUndo(withTarget: self) { vm in
                guard vm.canPerformUndoMutation() else { return }
                page.removeAnnotation(ann)
                vm.document.workspace.signatures.removeAll { $0.id == placementID }
                vm.signingIdentitiesByPlacementID.removeValue(forKey: placementID)
            }
        } else {
            let placementID = placement.id
            document.workspace.signatures.removeAll { $0.id == placementID }
            signingIdentitiesByPlacementID.removeValue(forKey: placementID)
            return nil
        }
        undoManager?.setActionName(L10n.string("undo.placeSignature"))
        PetBuddyHook.trigger(.sign)
        return selectedAnnotation
    }

    func signaturePlacementID(for annotation: PDFAnnotation) -> UUID? {
        if let id = (annotation as? SignatureImageAnnotation)?.placementID {
            return id
        }
        if let value = annotation.value(forAnnotationKey: Self.signaturePlacementAnnotationKey) as? String ??
            annotation.value(forAnnotationKey: Self.legacySignaturePlacementAnnotationKey) as? String {
            return UUID(uuidString: value)
        }
        return nil
    }

    func signaturePlacement(for annotation: PDFAnnotation) -> SignaturePlacement? {
        guard let id = signaturePlacementID(for: annotation) else { return nil }
        return document.workspace.signatures.first { $0.id == id }
    }

    @discardableResult
    func placeStamp(at pagePoint: CGPoint,
                    on page: PDFPage,
                    size: CGSize = CGSize(width: 150, height: 48)) -> PageDecoration? {
        guard canPerformMutatingAction() else { return nil }
        guard let options = pendingStampOptions,
              let refID = pageRefID(for: page) else { return nil }
        let bounds = constrainedSignatureBounds(
            CGRect(
                x: pagePoint.x - size.width / 2,
                y: pagePoint.y - size.height / 2,
                width: size.width,
                height: size.height
            ),
            on: page
        )
        let decoration = PageDecoration.stamp(
            text: options.text,
            swatch: options.swatch,
            pageRefID: refID,
            rect: bounds
        )
        var decorations = document.workspace.decorations
        decorations.append(decoration)
        selectedAnnotation = nil
        selectedStampDecorationID = decoration.id
        pendingStampOptions = nil
        replaceDecorations(decorations, actionName: "Place stamp")
        return decoration
    }

    func stampDecoration(id: UUID) -> PageDecoration? {
        document.workspace.decorations.first { $0.id == id && $0.kind == .stamp }
    }

    func stampDecoration(at pagePoint: CGPoint, on page: PDFPage, in pdfDocument: PDFDocument?) -> PageDecoration? {
        guard let pageRef = pageRef(for: page, in: pdfDocument) else { return nil }
        return document.workspace.decorations.reversed().first { decoration in
            guard decoration.kind == .stamp,
                  decoration.isEnabled,
                  decoration.pageRefID == pageRef.id,
                  let rect = decoration.rect?.insetBy(dx: -4, dy: -4) else {
                return false
            }
            return rect.contains(pagePoint)
        }
    }

    func deleteSelectedStampDecoration() {
        guard let selectedStampDecorationID else { return }
        removeStampDecoration(id: selectedStampDecorationID)
    }

    func removeStampDecoration(id: UUID) {
        var decorations = document.workspace.decorations
        guard let index = decorations.firstIndex(where: { $0.id == id && $0.kind == .stamp }) else { return }
        decorations.remove(at: index)
        selectedStampDecorationID = nil
        replaceDecorations(decorations, actionName: "Delete stamp")
    }

    @discardableResult
    func updateStampDecoration(id decorationID: UUID,
                               on page: PDFPage,
                               to proposedBounds: CGRect,
                               registerUndoFrom oldBounds: CGRect? = nil) -> CGRect {
        let fallbackBounds = stampDecoration(id: decorationID)?.rect ?? proposedBounds
        guard canPerformMutatingAction() else { return fallbackBounds }
        guard let index = document.workspace.decorations.firstIndex(where: { $0.id == decorationID && $0.kind == .stamp }) else {
            return fallbackBounds
        }

        let bounds = constrainedSignatureBounds(proposedBounds, on: page)
        let previousBounds = oldBounds ?? document.workspace.decorations[index].rect ?? fallbackBounds
        let shouldRegisterUndo = oldBounds.map { !$0.isApproximatelyEqual(to: bounds) } ?? false
        guard !(document.workspace.decorations[index].rect?.isApproximatelyEqual(to: bounds) ?? false) ||
              shouldRegisterUndo else {
            return bounds
        }

        document.workspace.decorations[index].rect = bounds
        decorationStateVersion &+= 1
        markAnnotationsModified()

        if shouldRegisterUndo {
            undoManager?.registerUndo(withTarget: self) { vm in
                guard vm.canPerformUndoMutation() else { return }
                vm.updateStampDecoration(id: decorationID, on: page, to: previousBounds, registerUndoFrom: bounds)
            }
            undoManager?.setActionName(L10n.string("undo.moveStamp"))
        }
        return bounds
    }

    @discardableResult
    func updateSignaturePlacement(for annotation: PDFAnnotation,
                                  to proposedBounds: CGRect,
                                  registerUndoFrom oldBounds: CGRect? = nil) -> CGRect {
        guard canPerformMutatingAction() else { return annotation.bounds }
        guard let page = annotation.page,
              let placementID = signaturePlacementID(for: annotation),
              let index = document.workspace.signatures.firstIndex(where: { $0.id == placementID }) else {
            return annotation.bounds
        }

        let bounds = constrainedSignatureBounds(proposedBounds, on: page)
        let previousBounds = oldBounds ?? document.workspace.signatures[index].rect
        let shouldRegisterUndo = oldBounds.map { !$0.isApproximatelyEqual(to: bounds) } ?? false
        guard !annotation.bounds.isApproximatelyEqual(to: bounds) ||
              !(document.workspace.signatures[index].rect.isApproximatelyEqual(to: bounds)) ||
              shouldRegisterUndo else {
            return bounds
        }

        annotation.bounds = bounds
        document.workspace.signatures[index].rect = bounds
        let warn = document.workspace.signatures[index].kind != .cryptographic
        markAnnotationsModified(warnAboutSignatureInvalidation: warn)

        if shouldRegisterUndo {
            undoManager?.registerUndo(withTarget: self) { vm in
                guard vm.canPerformUndoMutation() else { return }
                vm.updateSignaturePlacement(for: annotation, to: previousBounds, registerUndoFrom: bounds)
            }
            undoManager?.setActionName(L10n.string("undo.moveSignature"))
        }
        return bounds
    }

    private func constrainedSignatureBounds(_ bounds: CGRect, on page: PDFPage) -> CGRect {
        let pageBounds = page.bounds(for: .cropBox)
        var result = bounds.standardized
        result.size.width = min(max(result.width, 24), pageBounds.width)
        result.size.height = min(max(result.height, 12), pageBounds.height)
        if result.minX < pageBounds.minX {
            result.origin.x = pageBounds.minX
        }
        if result.maxX > pageBounds.maxX {
            result.origin.x = pageBounds.maxX - result.width
        }
        if result.minY < pageBounds.minY {
            result.origin.y = pageBounds.minY
        }
        if result.maxY > pageBounds.maxY {
            result.origin.y = pageBounds.maxY - result.height
        }
        return result
    }

    func signAndExportCryptographicPDF(timestampRequested: Bool) {
        guard canPerformSigningAction() else { return }
        guard let placement = document.workspace.signatures.last(where: { $0.isCryptographic }) else {
            showEditMessage(L10n.string("status.sign.placeCertificateFirst"), isError: true)
            return
        }
        let identity: any SigningIdentity
        do {
            guard let resolvedIdentity = signingIdentitiesByPlacementID[placement.id] else {
                throw SigningError.missingIdentity
            }
            identity = resolvedIdentity
        } catch SigningError.missingIdentity {
            exportError = ExportError(message: L10n.string("error.export.chooseSigningIdentity"))
            return
        } catch {
            exportError = ExportError(message: String(localized: "Orifold could not prepare the signing identity: \(error.localizedDescription)", locale: L10n.currentLocale))
            return
        }
        guard let pageIndex = pageIndex(forSignaturePlacement: placement) else {
            exportError = ExportError(message: L10n.string("error.export.locatePageForSignature"))
            return
        }

        let pdfData: Data
        do {
            let snapshot = WorkspacePackage(
                workspace: document.workspace,
                memberPDFData: try currentPDFDataForExport(),
                sourcePayloads: document.sourcePayloads
            )
            pdfData = try document.exportedPDFDataThrowing(from: snapshot)
        } catch {
            exportError = ExportError(message: userMessage(for: error, exporting: .pdf))
            return
        }

        let targetURL: URL
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "\(safeFilename(document.workspace.title))-signed.pdf"
        panel.title = L10n.string("savePanel.signExport.title")
        guard panel.runModal() == .OK, let chosenURL = panel.url else { return }
        targetURL = chosenURL

        let field = SignatureFieldSpec(
            pageIndex: pageIndex,
            rect: placement.rect,
            signerName: placement.signerName ?? "Signer",
            reason: placement.reason,
            location: placement.location,
            contactInfo: placement.contactInfo,
            subFilter: placement.subFilter ?? "ETSI.CAdES.detached"
        )
        let appearance: PDFAppearanceStream?
        do {
            appearance = try SignatureAppearanceRenderer.pdfAppearanceStream(
                for: .typedName(placement.signerName ?? "Signer"),
                bounds: placement.rect
            )
        } catch {
            exportError = ExportError(message: String(localized: "Orifold could not prepare the visible signature appearance: \(error.localizedDescription)", locale: L10n.currentLocale))
            return
        }

        do {
            var timestampWasApplied = false
            var timestampFallbackMessage: String?
            let signedData = try PDFIncrementalSigner().sign(pdf: pdfData, field: field, appearance: appearance) { byteRangeBytes in
                if timestampRequested {
                    return try CMSSignatureBuilder.buildCMS(byteRangeBytes: byteRangeBytes, identity: identity) { signatureValue in
                        do {
                            let token = try Self.fetchTimestampSynchronously(for: signatureValue).cmsTimeStampToken
                            timestampWasApplied = true
                            return token
                        } catch {
                            timestampFallbackMessage = L10n.string("status.sign.timestampUnavailable")
                            return nil
                        }
                    }
                }
                return try CMSSignatureBuilder.buildCMS(byteRangeBytes: byteRangeBytes, identity: identity, timestamp: nil)
            }
            try writeExportData(signedData, to: targetURL)
            try verifyExportedFile(at: targetURL)
            if let index = document.workspace.signatures.firstIndex(where: { $0.id == placement.id }) {
                document.workspace.signatures[index].timestampApplied = timestampWasApplied
            }
            finalizeSuccessfulExport(url: targetURL, format: .pdf, note: timestampFallbackMessage)
        } catch let writeError as ExportWriteError {
            exportError = ExportError(message: writeError.userMessage)
        } catch SigningError.notImplemented {
            exportError = ExportError(message: L10n.string("error.export.signingNotAvailable"))
        } catch SigningError.missingIdentity {
            exportError = ExportError(message: L10n.string("error.export.chooseSigningIdentity"))
        } catch {
            exportError = ExportError(message: String(localized: "Orifold could not sign the PDF: \(error.localizedDescription)", locale: L10n.currentLocale))
        }
    }

    private func pageIndex(forSignaturePlacement placement: SignaturePlacement) -> Int? {
        document.workspace.pageOrder.firstIndex { $0.id == placement.pageRefId }
    }

    private static func fetchTimestampSynchronously(for signatureValue: Data) throws -> TimeStampToken {
        let semaphore = DispatchSemaphore(value: 0)
        final class TimestampBox {
            var result: Result<TimeStampToken, Error>?
        }
        let box = TimestampBox()

        Task.detached {
            do {
                box.result = .success(try await TimestampClient().fetchTimestamp(for: signatureValue))
            } catch {
                box.result = .failure(error)
            }
            semaphore.signal()
        }

        semaphore.wait()
        switch box.result {
        case .success(let token):
            return token
        case .failure(let error):
            throw error
        case nil:
            throw SigningError.timestampUnavailable
        }
    }

    private func importPKCS12SigningIdentity() throws -> any SigningIdentity {
        let panel = NSOpenPanel()
        panel.title = L10n.string("savePanel.importDigitalID.title")
        panel.prompt = L10n.string("savePanel.import.prompt")
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = ["p12", "pfx"].compactMap { UTType(filenameExtension: $0) }
        guard panel.runModal() == .OK, let url = panel.url else {
            throw SigningError.missingIdentity
        }
        let passphrase = try promptForPKCS12Passphrase()
        return try PKCS12SigningIdentityProvider.importIdentity(from: url) { passphrase }
    }

    private func chooseKeychainSigningIdentity() throws -> any SigningIdentity {
        let identities = try KeychainSigningIdentityProvider.identities()
        guard !identities.isEmpty else {
            throw SigningError.missingIdentity
        }
        guard identities.count > 1 else {
            return identities[0]
        }

        let alert = NSAlert()
        alert.messageText = L10n.string("signAlert.chooseKeychainID.message")
        alert.informativeText = L10n.string("signAlert.chooseKeychainID.info")
        alert.addButton(withTitle: L10n.string("signAlert.choose.button"))
        alert.addButton(withTitle: L10n.string("signAlert.cancel.button"))

        let popup = NSPopUpButton(frame: CGRect(x: 0, y: 0, width: 360, height: 28), pullsDown: false)
        for identity in identities {
            popup.addItem(withTitle: identity.commonName ?? L10n.string("signAlert.untitledDigitalID"))
        }
        alert.accessoryView = popup

        guard alert.runModal() == .alertFirstButtonReturn else {
            throw SigningError.missingIdentity
        }
        return identities[max(0, popup.indexOfSelectedItem)]
    }

    private func promptForPKCS12Passphrase() throws -> String {
        let alert = NSAlert()
        alert.messageText = L10n.string("signAlert.digitalIDPassword.message")
        alert.informativeText = L10n.string("signAlert.digitalIDPassword.info")
        alert.addButton(withTitle: L10n.string("signAlert.unlock.button"))
        alert.addButton(withTitle: L10n.string("signAlert.cancel.button"))

        let field = NSSecureTextField(frame: CGRect(x: 0, y: 0, width: 320, height: 24))
        alert.accessoryView = field

        guard alert.runModal() == .alertFirstButtonReturn else {
            throw SigningError.missingIdentity
        }
        return field.stringValue
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
        cancelPendingSearch()
        performSearch(query: query, autoJump: true)
    }

    func scheduleSearch(query: String) {
        searchDebounceTask?.cancel()
        combinedPDF.cancelFindString()
        removeSearchObservers()

        if query != searchResultsQuery {
            finishSearch(with: [], query: query, autoJump: false)
        }

        guard !query.isEmpty else {
            activeSearchID = UUID()
            finishSearch(with: [], query: "", autoJump: false)
            return
        }

        let searchID = UUID()
        activeSearchID = searchID
        searchDebounceTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: 250_000_000)
            } catch {
                return
            }
            guard let self,
                  self.activeSearchID == searchID,
                  self.searchQuery == query else { return }
            self.performSearch(query: query, autoJump: true)
        }
    }

    func commitSearch() {
        searchDebounceTask?.cancel()
        combinedPDF.cancelFindString()
        removeSearchObservers()
        guard !searchQuery.isEmpty else {
            activeSearchID = UUID()
            finishSearch(with: [], query: "", autoJump: false)
            return
        }

        if searchResultsQuery == searchQuery, !searchResults.isEmpty {
            if searchResultIndex < 0 { searchResultIndex = 0 }
            jumpToSearchResult(searchResultIndex)
        } else {
            performSearch(query: searchQuery, autoJump: true)
        }
    }

    private func performSearch(query: String, autoJump: Bool) {
        removeSearchObservers()
        searchResults = []
        searchResultIndex = -1
        searchResultsQuery = query
        guard !query.isEmpty else { return }
        combinedPDF.cancelFindString()
        let results = combinedPDF.findString(query, withOptions: .caseInsensitive)
        finishSearch(with: results, query: query, autoJump: autoJump)
    }

    private func beginAsyncSearch(query: String, searchID: UUID, autoJump: Bool) {
        removeSearchObservers()
        pendingSearchResults = []
        searchResults = []
        searchResultIndex = -1

        let center = NotificationCenter.default
        let matchToken = center.addObserver(
            forName: .PDFDocumentDidFindMatch,
            object: combinedPDF,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  self.activeSearchID == searchID,
                  self.searchQuery == query,
                  let selection = notification.userInfo?[PDFDocumentFoundSelectionKey] as? PDFSelection else { return }
            self.pendingSearchResults.append(selection)
        }
        let endToken = center.addObserver(
            forName: .PDFDocumentDidEndFind,
            object: combinedPDF,
            queue: .main
        ) { [weak self] _ in
            guard let self,
                  self.activeSearchID == searchID,
                  self.searchQuery == query else { return }
            let results = self.pendingSearchResults
            self.removeSearchObservers()
            self.finishSearch(with: results, query: query, autoJump: autoJump)
        }
        searchNotificationTokens = [matchToken, endToken]
        combinedPDF.cancelFindString()
        combinedPDF.beginFindString(query, withOptions: .caseInsensitive)
    }

    private func finishSearch(with results: [PDFSelection], query: String, autoJump: Bool) {
        searchResultsQuery = query
        searchResults = results
        searchResultIndex = -1
        if !results.isEmpty {
            searchResultIndex = 0
            if autoJump { jumpToSearchResult(0) }
            PetBuddyHook.trigger(.search)
        }
    }

    private func cancelPendingSearch() {
        searchDebounceTask?.cancel()
        searchDebounceTask = nil
        activeSearchID = UUID()
        combinedPDF.cancelFindString()
        removeSearchObservers()
    }

    private func removeSearchObservers() {
        let center = NotificationCenter.default
        for token in searchNotificationTokens {
            center.removeObserver(token)
        }
        searchNotificationTokens = []
        pendingSearchResults = []
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
        NotificationCenter.default.post(name: .orifoldJumpToSelection, object: searchResults[index])
    }

    // MARK: - Zoom

    func zoomIn()  { NotificationCenter.default.post(name: .orifoldZoomIn,  object: nil) }
    func zoomOut() { NotificationCenter.default.post(name: .orifoldZoomOut, object: nil) }
    func zoomFit() { NotificationCenter.default.post(name: .orifoldZoomFit, object: nil) }

    // MARK: - Export

    @discardableResult
    /// Each branch finalizes its own success (see `finalizeSuccessfulExport`) once the
    /// file is actually verified on disk -- the compressed-PDF branch writes
    /// asynchronously, so `true` here only means "started", not "written".
    func exportWorkspace(as format: WorkspaceExportFormat, options: WorkspaceExportOptions = WorkspaceExportOptions()) -> Bool {
        guard !isWorkspaceEmpty else {
            exportError = ExportError(message: L10n.string("error.export.emptyWorkspace"))
            return false
        }
        guard canPerformMutatingAction() else { return false }
        switch format {
        case .pdf:
            return exportPlainPDF(options: options)
        case .word:
            return exportRichDocument(as: .word)
        case .legacyWord:
            return exportRichDocument(as: .legacyWord)
        case .odt:
            return exportRichDocument(as: .odt)
        case .rtf:
            return exportRichDocument(as: .rtf)
        case .text:
            return exportPlainText()
        case .markdown:
            return exportMarkdown()
        case .html:
            return exportHTML()
        case .png, .jpeg:
            return exportPageImages(as: format)
        }
    }

    @discardableResult
    func exportPlainPDF(options: WorkspaceExportOptions = WorkspaceExportOptions()) -> Bool {
        guard !isWorkspaceEmpty else {
            exportError = ExportError(message: L10n.string("error.export.emptyWorkspace"))
            return false
        }
        guard canPerformMutatingAction() else { return false }
        if options.compressionPreset != nil {
            return exportCompressedPDF(options: options)
        }
        return saveFlattenedPDF(to: nil, options: options, triggerPet: false)
    }

    @discardableResult
    func saveFlattenedPDF(to url: URL? = nil, options: WorkspaceExportOptions = WorkspaceExportOptions()) -> Bool {
        guard !isWorkspaceEmpty else {
            exportError = ExportError(message: L10n.string("error.export.emptyWorkspace"))
            return false
        }
        guard canPerformMutatingAction() else { return false }
        return saveFlattenedPDF(to: url, options: options, triggerPet: true)
    }

    private func saveFlattenedPDF(to url: URL?, options: WorkspaceExportOptions, triggerPet: Bool) -> Bool {
        let pdfData: Data
        do {
            pdfData = try dataForPDFExport(options: options)
        } catch {
            exportError = ExportError(message: userMessage(for: error, exporting: .pdf))
            return false
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
            panel.title = L10n.string("savePanel.exportPDF.title")
            guard panel.runModal() == .OK, let chosenURL = panel.url else { return false }
            targetURL = chosenURL
        }

        do {
            try writePDFExportData(pdfData, to: targetURL, validationOptions: options.encryption)
            finalizeSuccessfulExport(url: targetURL, format: .pdf)
            if triggerPet {
                PetBuddyHook.trigger(.save)
            }
            return true
        } catch {
            if let writeError = error as? ExportWriteError {
                exportError = ExportError(message: writeError.userMessage)
            } else if let encryptionError = error as? PDFEncryptionError {
                exportError = ExportError(message: encryptionError.userMessage)
            } else if let assemblyError = error as? PDFKitEngine.ExportAssemblyError {
                exportError = ExportError(message: assemblyError.localizedDescription)
            } else if let validationError = error as? PDFExportValidationError {
                exportError = ExportError(message: validationError.userMessage)
            } else {
                exportError = ExportError(message: String(localized: "Orifold could not save the PDF: \(error.localizedDescription)", locale: L10n.currentLocale))
            }
            return false
        }
    }

    func dataForPDFExport(options: WorkspaceExportOptions = WorkspaceExportOptions()) throws -> Data {
        if (options.encryption != nil || options.sanitization != nil), hasCryptographicSignaturePlacement {
            throw PDFEncryptionError.digitalSignatureConflict
        }
        let snapshot = WorkspacePackage(
            workspace: document.workspace,
            memberPDFData: try currentPDFDataForExport(),
            sourcePayloads: document.sourcePayloads
        )
        let pdfData = try document.exportedPDFDataThrowing(from: snapshot, options: options)
        let reducedData: Data
        if let preset = options.compressionPreset {
            reducedData = try PDFCompressionService.reduceFileSize(
                of: pdfData,
                preset: preset,
                processingEngine: processingEngine
            ).data
        } else {
            reducedData = pdfData
        }
        let sanitizedData = try Self.sanitized(reducedData, options: options.sanitization)
        guard let encryption = options.encryption else { return sanitizedData }
        let encryptedData = try PDFEncryptionService.encryptedData(from: sanitizedData, options: encryption)
        if options.compressionPreset != nil {
            _ = try PDFiumProcessingEngine().validatePDF(data: encryptedData, password: encryption.userPassword)
        }
        return encryptedData
    }

    /// Applies `options.sanitization` if present. Throws rather than falling
    /// back to unsanitized data on failure -- sanitize is a privacy/security
    /// feature, so silently shipping the original bytes when it can't run
    /// would be worse than failing the export outright.
    static func sanitized(_ data: Data, options: PDFSanitizationOptions?) throws -> Data {
        guard let options else { return data }
        guard let result = QPDFService.sanitized(data, removingMetadata: options.removesMetadata) else {
            throw PDFSanitizationError.sanitizationFailed
        }
        return result
    }

    func reduceFileSize(preset: PDFCompressionPreset = .balanced) {
        guard canPerformMutatingAction() else { return }
        let targetURL: URL
        let defaultName = "\(safeFilename(document.workspace.title))-reduced.pdf"
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = defaultName
        panel.title = L10n.string("savePanel.reduceFileSize.title")
        panel.prompt = L10n.string("savePanel.reduce.prompt")
        guard panel.runModal() == .OK, let chosenURL = panel.url else { return }
        targetURL = chosenURL

        let sourceData: Data
        do {
            var options = WorkspaceExportOptions()
            options.lockFormAnswers = hasFillableFormFields
            sourceData = try dataForPDFExport(options: options)
        } catch {
            exportError = ExportError(message: userMessage(for: error, exporting: .pdf))
            return
        }

        operationProgress.start(title: "Reducing file size", detail: "Preparing PDF")
        let cancellation = OperationCancellationToken()
        let operationID = UUID()
        activeCompressionCancellation = cancellation
        activeCompressionID = operationID
        activeCompressionTask = Task { [weak self, sourceData, targetURL, preset, cancellation, operationID] in
            guard let self else { return }
            do {
                let result = try await self.reducedData(
                    from: sourceData,
                    preset: preset,
                    encryption: nil,
                    cancellation: cancellation,
                    operationID: operationID
                ).compressionResult
                if cancellation.isCancelled || Task.isCancelled {
                    throw PDFCompressionError.cancelled
                }
                guard QPDFService.isStructurallySound(result.data) else {
                    throw PDFExportValidationError.structurallyUnsound
                }
                try self.writeExportData(result.data, to: targetURL)
                try self.verifyExportedFile(at: targetURL)
                await MainActor.run {
                    guard self.activeCompressionID == operationID else { return }
                    self.operationProgress.finish()
                    self.activeCompressionTask = nil
                    self.activeCompressionCancellation = nil
                    self.activeCompressionID = nil
                    self.finalizeSuccessfulExport(url: targetURL, format: .pdf, note: self.compressionSummary(result))
                }
            } catch {
                await MainActor.run {
                    guard self.activeCompressionID == operationID else { return }
                    self.operationProgress.finish()
                    self.activeCompressionTask = nil
                    self.activeCompressionCancellation = nil
                    self.activeCompressionID = nil
                    if let compressionError = error as? PDFCompressionError, compressionError == .cancelled {
                        self.editingStatus = .warning(PDFCompressionError.cancelled.errorDescription ?? "File-size reduction was cancelled.")
                    } else if error is CancellationError {
                        self.editingStatus = .warning(PDFCompressionError.cancelled.errorDescription ?? "File-size reduction was cancelled.")
                    } else {
                        self.exportError = ExportError(message: self.userMessage(for: error, exporting: .pdf))
                    }
                }
            }
        }
    }

    private func exportCompressedPDF(options: WorkspaceExportOptions) -> Bool {
        guard let preset = options.compressionPreset else { return false }
        if (options.encryption != nil || options.sanitization != nil), hasCryptographicSignaturePlacement {
            exportError = ExportError(message: PDFEncryptionError.digitalSignatureConflict.userMessage)
            return false
        }
        let targetURL: URL
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
        panel.title = L10n.string("savePanel.exportPDF.title")
        guard panel.runModal() == .OK, let chosenURL = panel.url else { return false }
        targetURL = chosenURL

        let encryption = options.encryption
        if let encryption {
            do {
                try PDFEncryptionService.validate(encryption)
            } catch {
                exportError = ExportError(message: userMessage(for: error, exporting: .pdf))
                return false
            }
        }

        let sourceData: Data
        do {
            let baseOptions = WorkspaceExportOptions(lockFormAnswers: options.lockFormAnswers)
            sourceData = try dataForPDFExport(options: baseOptions)
        } catch {
            exportError = ExportError(message: userMessage(for: error, exporting: .pdf))
            return false
        }

        operationProgress.start(title: "Reducing file size", detail: "Preparing PDF")
        let cancellation = OperationCancellationToken()
        let operationID = UUID()
        activeCompressionCancellation = cancellation
        activeCompressionID = operationID
        let sanitization = options.sanitization
        activeCompressionTask = Task { [weak self, sourceData, targetURL, preset, sanitization, encryption, cancellation, operationID] in
            guard let self else { return }
            do {
                let output = try await self.reducedData(
                    from: sourceData,
                    preset: preset,
                    sanitization: sanitization,
                    encryption: encryption,
                    cancellation: cancellation,
                    operationID: operationID
                )
                if cancellation.isCancelled || Task.isCancelled {
                    throw PDFCompressionError.cancelled
                }
                // Same structural gate writePDFExportData applies to the
                // plain export path -- this path writes directly and would
                // otherwise skip it entirely.
                guard QPDFService.isStructurallySound(output.data, password: encryption?.userPassword) else {
                    throw PDFExportValidationError.structurallyUnsound
                }
                try self.writeExportData(output.data, to: targetURL)
                try self.verifyExportedFile(at: targetURL)
                await MainActor.run {
                    guard self.activeCompressionID == operationID else { return }
                    self.operationProgress.finish()
                    self.activeCompressionTask = nil
                    self.activeCompressionCancellation = nil
                    self.activeCompressionID = nil
                    self.finalizeSuccessfulExport(url: targetURL, format: .pdf, note: self.compressionSummary(output.compressionResult))
                }
            } catch {
                await MainActor.run {
                    guard self.activeCompressionID == operationID else { return }
                    self.operationProgress.finish()
                    self.activeCompressionTask = nil
                    self.activeCompressionCancellation = nil
                    self.activeCompressionID = nil
                    if let compressionError = error as? PDFCompressionError, compressionError == .cancelled {
                        self.editingStatus = .warning(PDFCompressionError.cancelled.errorDescription ?? "File-size reduction was cancelled.")
                    } else if error is CancellationError {
                        self.editingStatus = .warning(PDFCompressionError.cancelled.errorDescription ?? "File-size reduction was cancelled.")
                    } else {
                        self.exportError = ExportError(message: self.userMessage(for: error, exporting: .pdf))
                    }
                }
            }
        }
        return true
    }

    func reducedData(
        from sourceData: Data,
        preset: PDFCompressionPreset,
        sanitization: PDFSanitizationOptions? = nil,
        encryption: PDFEncryptionOptions?,
        cancellation: OperationCancellationToken,
        operationID: UUID
    ) async throws -> (data: Data, compressionResult: PDFCompressionResult) {
        let progressThrottle = ProgressUpdateThrottle()
        return try await Task.detached(priority: .userInitiated) {
            let result = try PDFCompressionService.reduceFileSize(
                of: sourceData,
                preset: preset,
                processingEngine: PDFiumProcessingEngine(),
                progress: { progress in
                    guard progressThrottle.shouldEmit(progress) else { return }
                    Task { @MainActor [weak self] in
                        guard self?.activeCompressionID == operationID,
                              self?.operationProgress.isActive == true else { return }
                        self?.operationProgress.update(
                            fraction: progress,
                            detail: "\(Int((progress * 100).rounded()))%"
                        )
                    }
                },
                isCancelled: {
                    cancellation.isCancelled || Task.isCancelled
                }
            )
            if cancellation.isCancelled || Task.isCancelled {
                throw PDFCompressionError.cancelled
            }
            let sanitizedData = try Self.sanitized(result.data, options: sanitization)
            if cancellation.isCancelled || Task.isCancelled {
                throw PDFCompressionError.cancelled
            }
            guard let encryption else {
                return (data: sanitizedData, compressionResult: result)
            }
            let encrypted = try PDFEncryptionService.encryptedData(from: sanitizedData, options: encryption)
            if cancellation.isCancelled || Task.isCancelled {
                throw PDFCompressionError.cancelled
            }
            _ = try PDFiumProcessingEngine().validatePDF(data: encrypted, password: encryption.userPassword)
            if cancellation.isCancelled || Task.isCancelled {
                throw PDFCompressionError.cancelled
            }
            return (data: encrypted, compressionResult: result)
        }.value
    }

    enum PDFExportValidationError: Error, Equatable {
        case structurallyUnsound

        var userMessage: String {
            switch self {
            case .structurallyUnsound:
                return L10n.string("error.export.structurallyUnsound")
            }
        }
    }

    enum ExportWriteError: Error, LocalizedError {
        case fileNotFound
        case emptyFile

        var errorDescription: String? { userMessage }

        var userMessage: String {
            switch self {
            case .fileNotFound:
                return L10n.string("error.export.writeFileNotFound")
            case .emptyFile:
                return L10n.string("error.export.writeEmptyFile")
            }
        }
    }

    /// The only source of truth for "did the export actually land on disk" --
    /// callers must not report success from a Task/panel return value alone.
    private func verifyExportedFile(at url: URL) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw ExportWriteError.fileNotFound
        }
        if isDirectory.boolValue {
            let contents = try FileManager.default.contentsOfDirectory(atPath: url.path)
            guard !contents.isEmpty else { throw ExportWriteError.emptyFile }
        } else {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
            guard size > 0 else { throw ExportWriteError.emptyFile }
        }
    }

    /// `commentExportStatusMessage` reports counts across the whole workspace,
    /// so callers that export only a page subset (not the full workspace)
    /// must pass `includeCommentStatus: false` -- otherwise the message would
    /// cite comments that aren't actually in the exported pages.
    private func finalizeSuccessfulExport(
        url: URL,
        format: WorkspaceExportFormat,
        note: String? = nil,
        includeCommentStatus: Bool = true
    ) {
        let commentStatus = includeCommentStatus ? commentExportStatusMessage(for: format) : nil
        let detail = [commentStatus, note]
            .compactMap { $0 }
            .joined(separator: " ")
        exportSuccess = ExportSuccess(url: url, detail: detail.isEmpty ? nil : detail)
        PetBuddyHook.trigger(.export)
    }

    /// Writes export bytes to `targetURL`, preferring a crash-safe temp-file +
    /// atomic swap so a crash or force-quit mid-write can't leave a truncated
    /// file at the user's real destination. Falls back to a direct,
    /// non-atomic write only if the temp-sibling-file write itself can't even
    /// start -- some sandboxed destinations only grant write access to the
    /// exact NSSavePanel-chosen path, not sibling paths in the same folder
    /// (which is also why neither write uses `.atomic`: that option creates
    /// its own hidden sibling temp file, which would hit the same problem).
    /// `validate` runs against the written bytes before they're committed to
    /// `targetURL`, so a validation failure never lands at the real destination.
    private func writeExportData(_ data: Data, to targetURL: URL, validate: ((Data) throws -> Void)? = nil) throws {
        let fileManager = FileManager.default
        let directory = targetURL.deletingLastPathComponent()
        let tempURL = directory.appendingPathComponent(".Orifold-export-\(UUID().uuidString)")

        let wroteTemp: Bool
        do {
            try data.write(to: tempURL)
            wroteTemp = true
        } catch {
            wroteTemp = false
        }

        if wroteTemp {
            defer { try? fileManager.removeItem(at: tempURL) }
            if let validate {
                try validate(try Data(contentsOf: tempURL))
            }
            if fileManager.fileExists(atPath: targetURL.path) {
                guard try fileManager.replaceItemAt(
                    targetURL,
                    withItemAt: tempURL,
                    backupItemName: nil,
                    options: [.usingNewMetadataOnly]
                ) != nil else {
                    throw ExportWriteError.fileNotFound
                }
            } else {
                try fileManager.moveItem(at: tempURL, to: targetURL)
            }
        } else {
            if let validate {
                try validate(data)
            }
            try data.write(to: targetURL)
        }
    }

    private func writePDFExportData(_ data: Data, to targetURL: URL, validationOptions: PDFEncryptionOptions?) throws {
        // Defense in depth: qpdf's structural checker runs on every export,
        // encrypted or not, catching malformed output PDFKit's own leniency
        // might read back successfully but other PDF readers would reject.
        // Encrypted data must be checked with its user password -- qpdf can't
        // parse (and would wrongly report as unsound) a file it can't decrypt.
        guard QPDFService.isStructurallySound(data, password: validationOptions?.userPassword) else {
            throw PDFExportValidationError.structurallyUnsound
        }

        try writeExportData(data, to: targetURL) { writtenData in
            if let validationOptions {
                try PDFEncryptionService.validateEncryptedData(writtenData, options: validationOptions)
            }
        }
        try verifyExportedFile(at: targetURL)
    }

    private func exportRichDocument(as format: WorkspaceExportFormat) -> Bool {
        do {
            return saveData(try dataForWorkspaceExport(as: format), as: format)
        } catch {
            exportError = ExportError(message: userMessage(for: error, exporting: format))
            return false
        }
    }

    private func exportPlainText() -> Bool {
        do {
            return saveData(try dataForWorkspaceExport(as: .text), as: .text)
        } catch {
            exportError = ExportError(message: userMessage(for: error, exporting: .text))
            return false
        }
    }

    private func exportMarkdown() -> Bool {
        do {
            return saveData(try dataForWorkspaceExport(as: .markdown), as: .markdown)
        } catch {
            exportError = ExportError(message: userMessage(for: error, exporting: .markdown))
            return false
        }
    }

    private func exportHTML() -> Bool {
        do {
            return saveData(try dataForWorkspaceExport(as: .html), as: .html)
        } catch {
            exportError = ExportError(message: userMessage(for: error, exporting: .html))
            return false
        }
    }

    private func exportPageImages(as format: WorkspaceExportFormat) -> Bool {
        let exportData: Data
        do {
            let snapshot = WorkspacePackage(
                workspace: document.workspace,
                memberPDFData: try currentPDFDataForExport(),
                sourcePayloads: document.sourcePayloads
            )
            let options = WorkspaceExportOptions(lockFormAnswers: false)
            exportData = try document.exportedPDFDataThrowing(from: snapshot, options: options)
        } catch {
            exportError = ExportError(message: userMessage(for: error, exporting: format))
            return false
        }
        guard let exportDoc = PDFDocument(data: exportData) else {
            exportError = ExportError(message: L10n.string("error.export.preparePagesForImageExport"))
            return false
        }
        guard exportDoc.pageCount > 0 else {
            exportError = ExportError(message: L10n.string("error.export.noPagesToExport"))
            return false
        }

        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "\(safeFilename(document.workspace.title)) \(format.fileExtension.uppercased()) Pages"
        panel.title = String(localized: "Export \(format.menuTitle)", locale: L10n.currentLocale)
        panel.prompt = L10n.string("savePanel.export.prompt")
        guard panel.runModal() == .OK, let folderURL = panel.url else { return false }

        // Render every page into memory up front so a mid-export render
        // failure is caught before anything on disk is touched -- neither
        // the temp-folder path nor the sandbox fallback ever has to unwind a
        // partially-written or partially-deleted destination folder.
        var renderedPages: [(filename: String, data: Data)] = []
        for pageIndex in 0..<exportDoc.pageCount {
            guard let page = exportDoc.page(at: pageIndex),
                  let data = imageData(for: page, format: format) else {
                exportError = ExportError(message: "Orifold could not render page \(pageIndex + 1) for export.")
                return false
            }
            let filename = "page-\(String(format: "%03d", pageIndex + 1)).\(format.fileExtension)"
            renderedPages.append((filename, data))
        }

        func writePages(into folder: URL) throws {
            for page in renderedPages {
                try page.data.write(to: folder.appendingPathComponent(page.filename))
            }
        }

        let fileManager = FileManager.default
        let parentURL = folderURL.deletingLastPathComponent()
        let tempFolderURL = parentURL.appendingPathComponent(".Orifold-image-export-\(UUID().uuidString)", isDirectory: true)
        do {
            // Some sandboxed destinations only grant write access to the exact
            // path the user picked in NSSavePanel, not sibling paths in the
            // same folder -- if the temp-folder dance can't even get started,
            // fall back to writing folderURL directly.
            var wroteTemp = true
            do {
                try fileManager.createDirectory(at: tempFolderURL, withIntermediateDirectories: true)
                try writePages(into: tempFolderURL)
            } catch {
                try? fileManager.removeItem(at: tempFolderURL)
                wroteTemp = false
            }

            if wroteTemp {
                if fileManager.fileExists(atPath: folderURL.path) {
                    let replacement = try fileManager.replaceItemAt(
                        folderURL,
                        withItemAt: tempFolderURL,
                        backupItemName: nil,
                        options: [.usingNewMetadataOnly]
                    )
                    guard replacement != nil else {
                        throw ExportFailure("Could not replace the selected folder.")
                    }
                } else {
                    try fileManager.moveItem(at: tempFolderURL, to: folderURL)
                }
            } else {
                // Fully replace any existing folder at this path rather than
                // writing into it -- otherwise leftover pages from a prior,
                // larger export would survive alongside the new ones. Safe to
                // delete-then-write here because every page was already
                // rendered successfully above.
                if fileManager.fileExists(atPath: folderURL.path) {
                    try fileManager.removeItem(at: folderURL)
                }
                try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
                try writePages(into: folderURL)
            }

            try verifyExportedFile(at: folderURL)
            finalizeSuccessfulExport(url: folderURL, format: format)
            return true
        } catch {
            try? fileManager.removeItem(at: tempFolderURL)
            if let writeError = error as? ExportWriteError {
                exportError = ExportError(message: writeError.userMessage)
            } else {
                exportError = ExportError(message: String(localized: "Orifold could not export page images: \(error.localizedDescription)", locale: L10n.currentLocale))
            }
            return false
        }
    }

    private func saveData(_ data: Data, as format: WorkspaceExportFormat) -> Bool {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.contentType]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "\(safeFilename(document.workspace.title)).\(format.fileExtension)"
        panel.title = String(localized: "Export \(format.menuTitle)", locale: L10n.currentLocale)
        guard panel.runModal() == .OK, let url = panel.url else { return false }

        do {
            try writeExportData(data, to: url)
            try verifyExportedFile(at: url)
            finalizeSuccessfulExport(url: url, format: format)
            return true
        } catch {
            if let writeError = error as? ExportWriteError {
                exportError = ExportError(message: writeError.userMessage)
            } else {
                exportError = ExportError(message: String(localized: "Orifold could not write the \(format.menuTitle) export: \(error.localizedDescription)", locale: L10n.currentLocale))
            }
            return false
        }
    }

    private func commentExportStatusMessage(for format: WorkspaceExportFormat) -> String? {
        guard totalCommentCount > 0 else { return nil }
        if [.pdf, .png, .jpeg].contains(format),
           hasCryptographicSignaturePlacement {
            return "Exported without embedded comments because digital signatures are present; \(commentCountPhrase(totalCommentCount)) skipped to preserve signed bytes."
        }

        var parts: [String] = []
        let workspaceCount = document.workspace.comments.filter { $0.anchor == nil }.count
        if workspaceCount > 0 {
            parts.append("\(workspaceCount) workspace")
        }

        let anchoredPages = document.workspace.comments.compactMap { comment -> Int? in
            guard let anchor = comment.anchor else { return nil }
            return pageNumber(for: anchor)
        }
        if !anchoredPages.isEmpty {
            let pages = Array(Set(anchoredPages)).sorted().map(String.init).joined(separator: ", ")
            parts.append("\(anchoredPages.count) anchored on pages \(pages)")
        }

        let noteCount = pdfNoteComments.count
        if noteCount > 0 {
            parts.append("\(noteCount) PDF notes")
        }

        let detail = parts.isEmpty ? "" : " (\(parts.joined(separator: ", ")))"
        return "Exported with \(commentCountPhrase(totalCommentCount))\(detail)."
    }

    private func commentCountPhrase(_ count: Int) -> String {
        count == 1 ? "1 comment" : "\(count) comments"
    }

    enum ExportBuildError: Error {
        case unsupportedFormat
        case unsupportedRichTextFormat
        case cannotMapEdit(memberName: String, sourceText: String)
        case ambiguousSourceText(memberName: String, sourceText: String)
        case pdfOnlyEditsCannotMap(memberName: String)
        case editedPackageFormatRequiresPDF(formatName: String)
        case cannotEncode(formatName: String)
        case originFormatHasNoSourcePayload(memberName: String, originFormatDescription: String)
    }

    /// File extensions whose import path (`DocumentImportConverter`) explicitly declines to
    /// capture a `SourceDocumentPayload` — RTFD packages and Office/EPUB containers are
    /// flattened to plain text or a rendered attributed string at import time, with no
    /// faithful original bytes kept. Exporting such a member to any rich/plain-text SOURCE
    /// format (not PDF/image) would otherwise silently fall through to the same generic
    /// flatten-from-rendered-PDF-text fallback used for ordinary PDF-origin content — except
    /// here the user's mental model is "my Excel/RTFD file," and the result would silently
    /// contain none of that file's real structure/formatting/images with no indication
    /// anything was lost. `MemberDocument.sourcePDFRef` retains the original import
    /// filename, so its extension is enough to detect this without persisting new state.
    private static let fidelityDeclinedOriginExtensions: [String: String] = [
        "rtfd": "RTFD",
        "xlsx": "Excel spreadsheet (.xlsx)",
        "pptx": "PowerPoint presentation (.pptx)",
        "epub": "EPUB e-book"
    ]

    private func fidelityDeclinedOriginDescription(for member: MemberDocument) -> String? {
        let ext = URL(fileURLWithPath: member.sourcePDFRef).pathExtension.lowercased()
        return Self.fidelityDeclinedOriginExtensions[ext]
    }

    func dataForWorkspaceExport(as format: WorkspaceExportFormat) throws -> Data {
        if let sourceData = try sourcePreservingDataForWorkspaceExport(as: format) {
            return sourceData
        }

        // Only formats that actually claim source fidelity (word/legacyWord/odt/rtf/
        // text/markdown/html) are at risk here — .pdf/.png/.jpeg always render from the
        // live PDF and never claimed to preserve a non-PDF original, so they proceed
        // unaffected (`sourceFormat(for:)` returns nil for them).
        if sourceFormat(for: format) != nil {
            for member in document.workspace.documents {
                if let originDescription = fidelityDeclinedOriginDescription(for: member) {
                    throw ExportBuildError.originFormatHasNoSourcePayload(
                        memberName: member.displayName,
                        originFormatDescription: originDescription
                    )
                }
            }
        }

        switch format {
        case .word, .legacyWord, .odt, .rtf:
            guard let documentType = sourceFormat(for: format)?.documentType else {
                throw ExportBuildError.unsupportedRichTextFormat
            }
            let attributed = try richAttributedTextForDocumentExport()
            return try attributed.data(
                from: NSRange(location: 0, length: attributed.length),
                documentAttributes: [.documentType: documentType]
            )
        case .text:
            guard let data = plainTextForDocumentExport().data(using: .utf8) else {
                throw ExportBuildError.cannotEncode(formatName: format.menuTitle)
            }
            return data
        case .markdown:
            guard let data = markdownForDocumentExport().data(using: .utf8) else {
                throw ExportBuildError.cannotEncode(formatName: format.menuTitle)
            }
            return data
        case .html:
            guard let data = htmlForDocumentExport().data(using: .utf8) else {
                throw ExportBuildError.cannotEncode(formatName: format.menuTitle)
            }
            return data
        case .pdf, .png, .jpeg:
            throw ExportBuildError.unsupportedFormat
        }
    }

    private func sourcePreservingDataForWorkspaceExport(as format: WorkspaceExportFormat) throws -> Data? {
        guard !hasWorkspaceExportAdditions,
              loadedPDFs.count == 1,
              let member = loadedPDFs.first?.0,
              let payload = document.sourcePayloads[member.id],
              let targetFormat = sourceFormat(for: format),
              payload.format == targetFormat else {
            return nil
        }

        guard sourcePayloadCanRepresentCurrentPDF(member: member, payload: payload) else {
            throw ExportBuildError.pdfOnlyEditsCannotMap(memberName: member.displayName)
        }

        if hasPDFOnlyEdits(for: member) {
            throw ExportBuildError.pdfOnlyEditsCannotMap(memberName: member.displayName)
        }

        let edits = inlineTextEdits(for: member)
        guard !edits.isEmpty else { return payload.originalData }

        switch targetFormat {
        case .markdown, .html, .plainText:
            guard let original = payload.originalString else { return nil }
            let edited = try applyTextEdits(
                edits,
                to: original,
                memberName: member.displayName,
                member: member,
                replacementTransform: replacementTransform(for: targetFormat),
                sourceNeedleTransform: sourceNeedleTransform(for: targetFormat)
            )
            guard let data = edited.data(using: .utf8) else {
                throw ExportBuildError.cannotEncode(formatName: format.menuTitle)
            }
            return data
        case .docx, .wordDoc, .odt:
            throw ExportBuildError.editedPackageFormatRequiresPDF(formatName: format.menuTitle)
        case .rtf:
            guard let documentType = targetFormat.documentType,
                  let attributed = payload.attributedString()?.mutableCopy() as? NSMutableAttributedString else {
                return nil
            }
            try applyTextEdits(edits, to: attributed, memberName: member.displayName)
            return try attributed.data(
                from: NSRange(location: 0, length: attributed.length),
                documentAttributes: [.documentType: documentType]
            )
        }
    }

    private var hasWorkspaceExportAdditions: Bool {
        !document.workspace.comments.isEmpty ||
            document.workspace.hasActiveDecorations ||
            !document.workspace.tags.isEmpty ||
            pdfNoteComments.contains { !$0.body.isEmpty }
    }

    private func sourceFormat(for format: WorkspaceExportFormat) -> SourceDocumentFormat? {
        switch format {
        case .word: return .docx
        case .legacyWord: return .wordDoc
        case .odt: return .odt
        case .rtf: return .rtf
        case .text: return .plainText
        case .markdown: return .markdown
        case .html: return .html
        case .pdf, .png, .jpeg: return nil
        }
    }

    private func inlineTextEdits(for member: MemberDocument) -> [PDFTextEditOperation] {
        let pageRefIDs = Set(member.pageRefs)
        return document.workspace.pageEditStates
            .filter { pageRefIDs.contains($0.pageRefID) }
            .flatMap(\.operations)
            .sorted { $0.createdAt < $1.createdAt }
    }

    private func sourcePayloadCanRepresentCurrentPDF(member: MemberDocument, payload: SourceDocumentPayload) -> Bool {
        guard document.workspace.documents.count == 1,
              document.workspace.signatures.isEmpty,
              !document.workspace.hasActiveDecorations,
              document.workspace.pageOrder.map(\.id) == member.pageRefs else {
            return false
        }

        if let renderedPageCount = payload.renderedPageCount,
           renderedPageCount != member.pageRefs.count {
            return false
        }

        for (expectedSourcePageIndex, pageRefID) in member.pageRefs.enumerated() {
            guard let pageRef = document.workspace.pageOrder.first(where: { $0.id == pageRefID }),
                  pageRef.memberDocId == member.id,
                  pageRef.sourcePageIndex == expectedSourcePageIndex else {
                return false
            }
        }

        guard let loaded = loadedPDFs.first(where: { $0.0.id == member.id }) else {
            return false
        }

        for pageIndex in 0..<loaded.1.pageCount {
            guard let page = loaded.1.page(at: pageIndex) else { return false }
            if page.rotation != 0 { return false }
        }
        return true
    }

    private func hasPDFOnlyEdits(for member: MemberDocument) -> Bool {
        guard document.sourcePayloads[member.id] != nil,
              let loaded = loadedPDFs.first(where: { $0.0.id == member.id }) else {
            return false
        }
        let pdf = loaded.1
        for pageIndex in 0..<pdf.pageCount {
            guard let page = pdf.page(at: pageIndex) else { continue }
            for annotation in page.annotations {
                if annotation.value(forAnnotationKey: Self.draftTextAnnotationKey) != nil ||
                    annotation.value(forAnnotationKey: Self.legacyDraftTextAnnotationKey) != nil ||
                    annotation.value(forAnnotationKey: Self.textReplacementAnnotationKey) != nil ||
                    annotation.value(forAnnotationKey: Self.legacyTextReplacementAnnotationKey) != nil ||
                    annotation.type == "FreeText" ||
                    annotation.type == "Ink" ||
                    annotation.type == "Highlight" ||
                    annotation.type == "Underline" ||
                    annotation.type == "StrikeOut" {
                    return true
                }
                if let contents = annotation.contents?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !contents.isEmpty {
                    return true
                }
            }
        }
        return false
    }

    private func applyTextEdits(
        _ edits: [PDFTextEditOperation],
        to original: String,
        memberName: String,
        member: MemberDocument? = nil,
        replacementTransform: (String) -> String = { $0 },
        sourceNeedleTransform: (String) -> String? = { _ in nil }
    ) throws -> String {
        var output = original
        let replacements = try resolvedStringReplacements(
            for: edits,
            in: original,
            memberName: memberName,
            member: member,
            sourceNeedleTransform: sourceNeedleTransform
        )
        for replacement in replacements.sorted(by: { $0.range.lowerBound > $1.range.lowerBound }) {
            output.replaceSubrange(replacement.range, with: replacementTransform(replacement.text))
        }
        return output
    }

    private func resolvedStringReplacements(
        for edits: [PDFTextEditOperation],
        in original: String,
        memberName: String,
        member: MemberDocument?,
        sourceNeedleTransform: (String) -> String?
    ) throws -> [StringReplacement] {
        var replacements: [StringReplacement] = []
        for edit in edits where !edit.replacementText.isEmpty || !edit.sourceText.isEmpty {
            if edit.sourceText.isEmpty {
                throw ExportBuildError.pdfOnlyEditsCannotMap(memberName: memberName)
            }
            var matchedRanges = ranges(of: edit.sourceText, in: original)
            if matchedRanges.isEmpty, let transformedNeedle = sourceNeedleTransform(edit.sourceText) {
                matchedRanges = ranges(of: transformedNeedle, in: original)
            }
            guard matchedRanges.count == 1 else {
                if matchedRanges.isEmpty {
                    throw ExportBuildError.cannotMapEdit(memberName: memberName, sourceText: edit.sourceText)
                }
                // Disambiguating a repeated paragraph maps a PDF *visual reading-order*
                // occurrence index onto a raw-*source*-order list of substring matches.
                // Those two orderings only line up when they enumerate the same set: the
                // count of rendered blocks carrying this text must equal the count of raw
                // matches. When markup, whitespace, reflow, columns or floats make them
                // diverge, the index would silently patch the WRONG occurrence — worse than
                // failing. So only trust the index when the counts agree; otherwise fail
                // clearly and let the user fall back to PDF export.
                if let member,
                   let occurrence = sourceOccurrence(for: edit, sourceText: edit.sourceText, member: member),
                   occurrence.total == matchedRanges.count,
                   matchedRanges.indices.contains(occurrence.index) {
                    replacements.append(StringReplacement(range: matchedRanges[occurrence.index], text: edit.replacementText))
                    continue
                }
                throw ExportBuildError.ambiguousSourceText(memberName: memberName, sourceText: edit.sourceText)
            }
            guard let range = matchedRanges.first else {
                throw ExportBuildError.cannotMapEdit(memberName: memberName, sourceText: edit.sourceText)
            }
            replacements.append(StringReplacement(range: range, text: edit.replacementText))
        }
        return replacements
    }

    /// The edited block's occurrence index (in PDF visual reading order across the member)
    /// AND the total number of rendered blocks carrying the same text. Callers compare
    /// `total` against the number of raw-source matches to prove the two orderings
    /// enumerate the same set before trusting `index`.
    private struct SourceOccurrence {
        var index: Int
        var total: Int
    }

    private func sourceOccurrence(for edit: PDFTextEditOperation, sourceText: String, member: MemberDocument) -> SourceOccurrence? {
        let normalizedNeedle = normalizedSourceText(sourceText)
        guard !normalizedNeedle.isEmpty,
              let editedPagePosition = member.pageRefs.firstIndex(of: edit.pageRefID) else {
            return nil
        }

        var occurrenceOffset = 0
        var resolvedIndex: Int?
        var total = 0
        // Iterate every page fully so `total` counts all matching blocks, not just those up
        // to the edited page — the count guard needs the whole-document total.
        for pagePosition in member.pageRefs.indices {
            let pageRefID = member.pageRefs[pagePosition]
            guard let pageRef = document.workspace.pageOrder.first(where: { $0.id == pageRefID }),
                  let basePage = originalBasePage(for: pageRef) else {
                continue
            }
            let blocks = textAnalysisEngine
                .analyze(
                    data: originalMemberPDFData[member.id] ?? document.memberPDFData[member.id] ?? Data(),
                    pageIndex: pageRef.sourcePageIndex,
                    pageRefID: pageRef.id,
                    fallbackPage: basePage
                )
                .blocks
                .filter { normalizedSourceText($0.text) == normalizedNeedle }
                .sorted(by: sourceReadingOrder)

            if pagePosition == editedPagePosition, let localIndex = nearestSourceBlockIndex(to: edit.sourceBounds, in: blocks) {
                resolvedIndex = occurrenceOffset + localIndex
            }
            occurrenceOffset += blocks.count
            total += blocks.count
        }
        guard let resolvedIndex else { return nil }
        return SourceOccurrence(index: resolvedIndex, total: total)
    }

    private func nearestSourceBlockIndex(to sourceBounds: CGRect, in blocks: [EditableTextBlock]) -> Int? {
        guard !blocks.isEmpty else { return nil }
        let sourceCenter = CGPoint(x: sourceBounds.standardized.midX, y: sourceBounds.standardized.midY)
        return blocks.indices.min {
            distanceSquared(from: sourceCenter, to: blocks[$0].bounds) < distanceSquared(from: sourceCenter, to: blocks[$1].bounds)
        }
    }

    private func sourceReadingOrder(_ lhs: EditableTextBlock, _ rhs: EditableTextBlock) -> Bool {
        let verticalTolerance = max(lhs.fontSize, rhs.fontSize, 4)
        if abs(lhs.bounds.midY - rhs.bounds.midY) > verticalTolerance {
            return lhs.bounds.midY > rhs.bounds.midY
        }
        return lhs.bounds.minX < rhs.bounds.minX
    }

    private func normalizedSourceText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func applyTextEdits(_ edits: [PDFTextEditOperation], to attributed: NSMutableAttributedString, memberName: String) throws {
        let original = attributed.string
        var replacements: [(range: NSRange, text: String, attributes: [NSAttributedString.Key: Any])] = []
        for edit in edits where !edit.replacementText.isEmpty || !edit.sourceText.isEmpty {
            if edit.sourceText.isEmpty {
                throw ExportBuildError.pdfOnlyEditsCannotMap(memberName: memberName)
            }
            let ranges = nsRanges(of: edit.sourceText, in: original)
            guard ranges.count == 1 else {
                if ranges.isEmpty {
                    throw ExportBuildError.cannotMapEdit(memberName: memberName, sourceText: edit.sourceText)
                }
                throw ExportBuildError.ambiguousSourceText(memberName: memberName, sourceText: edit.sourceText)
            }
            guard let range = ranges.first else {
                throw ExportBuildError.cannotMapEdit(memberName: memberName, sourceText: edit.sourceText)
            }
            replacements.append((
                range,
                edit.replacementText,
                attributedReplacementAttributes(in: attributed, range: range, edit: edit)
            ))
        }
        for replacement in replacements.sorted(by: { $0.range.location > $1.range.location }) {
            attributed.replaceCharacters(
                in: replacement.range,
                with: NSAttributedString(
                    string: replacement.text,
                    attributes: replacement.attributes
                )
            )
        }
    }

    private func replacementTransform(for format: SourceDocumentFormat) -> (String) -> String {
        switch format {
        case .html:
            return escapeHTMLText
        case .markdown:
            return escapeMarkdownText
        case .plainText, .rtf, .docx, .wordDoc, .odt:
            return { $0 }
        }
    }

    private func sourceNeedleTransform(for format: SourceDocumentFormat) -> (String) -> String? {
        switch format {
        case .html:
            return escapeHTMLText
        case .plainText, .markdown, .rtf, .docx, .wordDoc, .odt:
            return { _ in nil }
        }
    }

    private func escapeHTMLText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private func escapeMarkdownText(_ text: String) -> String {
        let escapable = Set("\\`*_{}[]()#+-.!|<>")
        var escaped = ""
        escaped.reserveCapacity(text.count)
        for character in text {
            if escapable.contains(character) {
                escaped.append("\\")
            }
            escaped.append(character)
        }
        return escaped
    }

    private func ranges(of needle: String, in haystack: String) -> [Range<String.Index>] {
        guard !needle.isEmpty else { return [] }
        var ranges: [Range<String.Index>] = []
        var searchStart = haystack.startIndex
        while searchStart < haystack.endIndex,
              let range = haystack.range(of: needle, range: searchStart..<haystack.endIndex) {
            ranges.append(range)
            searchStart = range.upperBound
        }
        return ranges
    }

    private func nsRanges(of needle: String, in haystack: String) -> [NSRange] {
        ranges(of: needle, in: haystack).map { NSRange($0, in: haystack) }
    }

    private struct StringReplacement {
        var range: Range<String.Index>
        var text: String
    }

    private func attributes(for edit: PDFTextEditOperation) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = edit.alignment.nsTextAlignment
        return [
            .font: NSFont(name: edit.fontName, size: edit.fontSize) ?? NSFont.systemFont(ofSize: edit.fontSize),
            .foregroundColor: edit.textColor.nsColor,
            .paragraphStyle: paragraph
        ]
    }

    private func attributedReplacementAttributes(
        in attributed: NSAttributedString,
        range: NSRange,
        edit: PDFTextEditOperation
    ) -> [NSAttributedString.Key: Any] {
        guard attributed.length > 0, range.location < attributed.length else {
            return attributes(for: edit)
        }
        var attributes = attributed.attributes(at: range.location, effectiveRange: nil)
        if attributes[.font] == nil {
            attributes[.font] = NSFont(name: edit.fontName, size: edit.fontSize) ?? NSFont.systemFont(ofSize: edit.fontSize)
        }
        if attributes[.foregroundColor] == nil {
            attributes[.foregroundColor] = edit.textColor.nsColor
        }
        return attributes
    }

    private func userMessage(for error: Error, exporting format: WorkspaceExportFormat) -> String {
        if let writeError = error as? ExportWriteError {
            return writeError.userMessage
        }
        if let encryptionError = error as? PDFEncryptionError {
            return encryptionError.userMessage
        }
        if let sanitizationError = error as? PDFSanitizationError {
            return sanitizationError.userMessage
        }
        if let validationError = error as? PDFExportValidationError {
            return validationError.userMessage
        }
        switch error {
        case ExportBuildError.cannotMapEdit(let memberName, let sourceText):
            let preview = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
            let detail = preview.isEmpty ? "." : ": \"\(preview)\"."
            return String(localized: "Orifold could not map an edit in \"\(memberName)\" back to the original \(format.menuTitle) source\(detail) Export as PDF to preserve the visual edit, or edit text that exists in the original document.", locale: L10n.currentLocale)
        case ExportBuildError.ambiguousSourceText(let memberName, let sourceText):
            let preview = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
            let detail = preview.isEmpty ? "." : ": \"\(preview)\"."
            return String(localized: "Orifold found more than one matching source text in \"\(memberName)\"\(detail) Export as PDF to preserve the visual edit.", locale: L10n.currentLocale)
        case ExportBuildError.pdfOnlyEditsCannotMap(let memberName):
            return String(localized: "Orifold found PDF-only annotations, signatures, or page changes in \"\(memberName)\". Export as PDF to preserve those visual edits.", locale: L10n.currentLocale)
        case ExportBuildError.editedPackageFormatRequiresPDF(let formatName):
            return String(localized: "Orifold can preserve the original \(formatName) bytes when unchanged, but edited package exports are not faithful enough yet. Export as PDF to preserve the edit.", locale: L10n.currentLocale)
        case ExportBuildError.cannotEncode(let formatName):
            return String(localized: "Orifold could not encode the \(formatName) export.", locale: L10n.currentLocale)
        case ExportBuildError.originFormatHasNoSourcePayload(let memberName, let originFormatDescription):
            return String(localized: "\"\(memberName)\" was imported from a \(originFormatDescription) file, which Orifold flattens to plain text and cannot reconstruct into \(format.menuTitle). Export as PDF to keep the current content, or re-export from the original \(originFormatDescription) file if you need it in another format.", locale: L10n.currentLocale)
        case ExportBuildError.unsupportedRichTextFormat:
            return String(localized: "Orifold does not have a rich-text writer for \(format.menuTitle).", locale: L10n.currentLocale)
        case PDFDecorationExportBaker.BakeError.invalidPDF:
            return L10n.string("error.export.decorationInvalidPDF")
        case PDFDecorationExportBaker.BakeError.pageOrderMismatch:
            return L10n.string("error.export.decorationPageOrderMismatch")
        case PDFDecorationExportBaker.BakeError.invalidDecoration:
            return L10n.string("error.export.invalidDecoration")
        case PDFDecorationExportBaker.BakeError.invalidStampDecoration:
            return L10n.string("error.export.invalidStampDecoration")
        case PDFDecorationExportBaker.BakeError.documentTooLargeForDecorationExport:
            return L10n.string("error.export.documentTooLargeForDecoration")
        case PDFFormSupport.FormError.invalidPDF:
            return L10n.string("error.export.formInvalidPDF")
        case PDFFormSupport.FormError.pageOrderMismatch:
            return L10n.string("error.export.formPageOrderMismatch")
        case let compressionError as PDFCompressionError:
            return compressionError.errorDescription ?? L10n.string("error.export.reduceFileSizeFailed")
        case let ocrError as PDFOCRError:
            return ocrError.errorDescription ?? L10n.string("error.export.ocrFailed")
        case _ as PDFProcessingError:
            return L10n.string("error.export.verifyReducedPDFFailed")
        case let error as PDFKitEngine.ExportAssemblyError:
            return error.localizedDescription
        default:
            return String(localized: "Orifold could not create the \(format.menuTitle) export: \(error.localizedDescription)", locale: L10n.currentLocale)
        }
    }

    private func compressionSummary(_ result: PDFCompressionResult) -> String {
        let original = formattedByteCount(result.originalByteCount)
        let compressed = formattedByteCount(result.compressedByteCount)
        let percent = result.percentSmaller
        return String(localized: "\(original) → \(compressed), \(percent)% smaller", locale: L10n.currentLocale)
    }

    private func formattedByteCount(_ count: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: Int64(count))
    }

    func richAttributedTextForDocumentExport() throws -> NSAttributedString {
        let output = NSMutableAttributedString()
        let headingAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 18),
            .foregroundColor: NSColor.labelColor
        ]
        let bodyAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.labelColor
        ]

        appendAttributedComments(to: output, headingAttributes: headingAttributes, bodyAttributes: bodyAttributes)

        let shouldAddMemberHeadings = hasWorkspaceExportAdditions || loadedPDFs.count != 1
        for (index, item) in loadedPDFs.enumerated() {
            let member = item.0
            if output.length > 0 || (index > 0 && shouldAddMemberHeadings) {
                output.append(NSAttributedString(string: "\n\n"))
            }
            if shouldAddMemberHeadings {
                output.append(NSAttributedString(string: member.displayName + "\n", attributes: headingAttributes))
                output.append(NSAttributedString(string: String(repeating: "-", count: max(3, member.displayName.count)) + "\n\n", attributes: bodyAttributes))
            }

            let memberAttributed: NSMutableAttributedString
            if let payload = document.sourcePayloads[member.id],
               let attributed = payload.attributedString()?.mutableCopy() as? NSMutableAttributedString {
                memberAttributed = attributed
            } else {
                memberAttributed = NSMutableAttributedString(string: text(from: item.1), attributes: bodyAttributes)
            }
            try applyTextEdits(inlineTextEdits(for: member), to: memberAttributed, memberName: member.displayName)
            output.append(memberAttributed)
        }
        return output.length == 0 ? NSAttributedString(string: " ") : output
    }

    func attributedTextForDocumentExport() -> NSAttributedString {
        if let attributed = try? richAttributedTextForDocumentExport() {
            return attributed
        }
        return flattenedAttributedTextForDocumentExport()
    }

    private func flattenedAttributedTextForDocumentExport() -> NSAttributedString {
        let output = NSMutableAttributedString()
        let headingAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 18),
            .foregroundColor: NSColor.labelColor
        ]
        let bodyAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.labelColor
        ]

        appendAttributedComments(to: output, headingAttributes: headingAttributes, bodyAttributes: bodyAttributes)

        for (index, item) in loadedPDFs.enumerated() {
            if output.length > 0 || index > 0 {
                output.append(NSAttributedString(string: "\n\n"))
            }
            output.append(NSAttributedString(string: item.0.displayName + "\n", attributes: headingAttributes))
            output.append(NSAttributedString(string: String(repeating: "-", count: max(3, item.0.displayName.count)) + "\n\n", attributes: bodyAttributes))
            output.append(NSAttributedString(string: text(from: item.1), attributes: bodyAttributes))
        }
        return output.length == 0 ? NSAttributedString(string: " ") : output
    }

    func plainTextForDocumentExport() -> String {
        if let data = try? sourcePreservingDataForWorkspaceExport(as: .text),
           let sourceText = String(data: data, encoding: .utf8) {
            return sourceText
        }
        var sections: [String] = []
        if let comments = plainTextCommentsSection() {
            sections.append(comments)
        }
        sections += loadedPDFs.map { member, pdf in
            "\(member.displayName)\n\(String(repeating: "=", count: max(3, member.displayName.count)))\n\n\(text(from: pdf))"
        }
        return sections.joined(separator: "\n\n")
    }

    func markdownForDocumentExport() -> String {
        if let data = try? sourcePreservingDataForWorkspaceExport(as: .markdown),
           let sourceMarkdown = String(data: data, encoding: .utf8) {
            return sourceMarkdown
        }
        let title = markdownHeadingEscaped(document.workspace.title)
        var sections: [String] = ["# \(title)"]

        var metadata: [String] = []
        metadata.append("- Documents: \(loadedPDFs.count)")
        metadata.append("- Pages: \(document.workspace.pageOrder.count)")
        if !document.workspace.tags.isEmpty {
            metadata.append("- Tags: \(document.workspace.tags.map(markdownInlineEscaped).joined(separator: ", "))")
        }
        if totalCommentCount > 0 {
            metadata.append("- Comments: \(totalCommentCount)")
        }
        sections.append("""
        ## Workspace Summary

        \(metadata.joined(separator: "\n"))
        """)

        if let comments = markdownCommentsSection() {
            sections.append(comments)
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

    func htmlForDocumentExport() -> String {
        if let data = try? sourcePreservingDataForWorkspaceExport(as: .html),
           let sourceHTML = String(data: data, encoding: .utf8) {
            return sourceHTML
        }
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
            h2 { font-size: 18px; margin: 0 0 14px; }
            pre { white-space: pre-wrap; font: 13px/1.5 ui-monospace, SFMono-Regular, Menlo, monospace; }
            .comment { border-left: 3px solid #d4d7dc; padding: 8px 0 8px 12px; margin: 0 0 14px; }
            .comment-meta { color: #667085; font-size: 12px; margin-bottom: 4px; }
            .tag { display: inline-block; border: 1px solid #d0d5dd; border-radius: 999px; padding: 1px 7px; margin-right: 4px; font-size: 11px; color: #344054; }
          </style>
        </head>
        <body>
        \(htmlCommentsSection())
        \(body)
        </body>
        </html>
        """
    }

    private struct CommentExportItem {
        var title: String
        var body: String
        var tags: [String]
        var style: WorkspaceCommentStyle
        var createdAt: Date?
        var isResolved: Bool
    }

    private var commentExportItems: [CommentExportItem] {
        let workspaceItems = document.workspace.comments.map { comment in
            CommentExportItem(
                title: exportTitle(for: comment),
                body: comment.body,
                tags: comment.tags,
                style: comment.style,
                createdAt: comment.createdAt,
                isResolved: comment.isResolved
            )
        }
        let noteItems = pdfNoteComments.map { note in
            CommentExportItem(
                title: "PDF note, page \(note.pageNumber), \(note.memberName)",
                body: note.body,
                tags: [],
                style: WorkspaceCommentStyle(),
                createdAt: nil,
                isResolved: false
            )
        }
        return workspaceItems + noteItems
    }

    private func exportTitle(for comment: WorkspaceComment) -> String {
        if let anchor = comment.anchor,
           let pageNumber = pageNumber(for: anchor),
           let snippet = anchor.snippet,
           !snippet.isEmpty {
            return "p. \(pageNumber) - \(snippet)"
        }
        if let anchor = comment.anchor,
           let pageNumber = pageNumber(for: anchor) {
            return "p. \(pageNumber)"
        }
        if comment.anchorWasRemoved {
            return "(page removed)"
        }
        return comment.createdAt.formatted(date: .abbreviated, time: .shortened)
    }

    private func appendAttributedComments(to output: NSMutableAttributedString,
                                          headingAttributes: [NSAttributedString.Key: Any],
                                          bodyAttributes: [NSAttributedString.Key: Any]) {
        let comments = commentExportItems
        guard !comments.isEmpty else { return }
        output.append(NSAttributedString(string: "Comments\n", attributes: headingAttributes))
        output.append(NSAttributedString(string: "--------\n\n", attributes: bodyAttributes))
        let openComments = comments.filter { !$0.isResolved }
        let resolvedComments = comments.filter(\.isResolved)
        appendAttributedCommentItems(openComments, to: output, bodyAttributes: bodyAttributes)
        if !resolvedComments.isEmpty {
            output.append(NSAttributedString(string: "\n\nResolved\n", attributes: headingAttributes))
            output.append(NSAttributedString(string: "--------\n\n", attributes: bodyAttributes))
            appendAttributedCommentItems(resolvedComments, to: output, bodyAttributes: bodyAttributes)
        }
    }

    private func appendAttributedCommentItems(_ comments: [CommentExportItem],
                                              to output: NSMutableAttributedString,
                                              bodyAttributes: [NSAttributedString.Key: Any]) {
        for (index, item) in comments.enumerated() {
            if index > 0 {
                output.append(NSAttributedString(string: "\n\n", attributes: bodyAttributes))
            }
            output.append(NSAttributedString(string: item.title + "\n", attributes: bodyAttributes))
            if !item.tags.isEmpty {
                output.append(NSAttributedString(
                    string: "Tags: \(item.tags.joined(separator: ", "))\n",
                    attributes: bodyAttributes
                ))
            }
            output.append(NSAttributedString(string: item.body, attributes: attributedCommentAttributes(for: item.style)))
        }
    }

    private func attributedCommentAttributes(for style: WorkspaceCommentStyle) -> [NSAttributedString.Key: Any] {
        var traits: NSFontTraitMask = []
        if style.isBold { traits.insert(.boldFontMask) }
        if style.isItalic { traits.insert(.italicFontMask) }
        let size = commentPointSize(for: style.textSize)
        let baseFont = NSFont.systemFont(ofSize: size)
        let font = NSFontManager.shared.convert(baseFont, toHaveTrait: traits)
        return [
            .font: font,
            .foregroundColor: nsColor(fromHex: style.colorHex) ?? NSColor.labelColor
        ]
    }

    private func plainTextCommentsSection() -> String? {
        let comments = commentExportItems
        guard !comments.isEmpty else { return nil }
        func rows(_ items: [CommentExportItem]) -> [String] {
            items.map { item in
                var lines: [String] = [item.title]
                if !item.tags.isEmpty {
                    lines.append("Tags: \(item.tags.joined(separator: ", "))")
                }
                lines.append(item.body)
                return lines.joined(separator: "\n")
            }
        }
        let openRows = rows(comments.filter { !$0.isResolved })
        let resolvedRows = rows(comments.filter(\.isResolved))
        var sections: [String] = []
        if !openRows.isEmpty {
            sections.append(openRows.joined(separator: "\n\n"))
        }
        if !resolvedRows.isEmpty {
            sections.append("Resolved\n--------\n\n" + resolvedRows.joined(separator: "\n\n"))
        }
        return "Comments\n========\n\n" + sections.joined(separator: "\n\n")
    }

    private func markdownRows(_ comments: [CommentExportItem]) -> [String] {
        comments.map { item in
            var lines: [String] = [item.title]
            if !item.tags.isEmpty {
                lines.append("Tags: \(item.tags.map(markdownInlineEscaped).joined(separator: ", "))")
            }
            var line = "- **\(markdownInlineEscaped(item.title))**: \(markdownFormattedCommentBody(item.body, style: item.style))"
            if !item.tags.isEmpty {
                line += " _Tags: \(item.tags.map(markdownInlineEscaped).joined(separator: ", "))_"
            }
            return line
        }
    }

    private func markdownCommentsSection() -> String? {
        let comments = commentExportItems
        guard !comments.isEmpty else { return nil }
        let openRows = markdownRows(comments.filter { !$0.isResolved })
        let resolvedRows = markdownRows(comments.filter(\.isResolved))
        var sections: [String] = []
        if !openRows.isEmpty {
            sections.append(openRows.joined(separator: "\n"))
        }
        if !resolvedRows.isEmpty {
            sections.append("### Resolved\n\n" + resolvedRows.joined(separator: "\n"))
        }
        return "## Comments\n\n" + sections.joined(separator: "\n\n")
    }

    private func htmlCommentsSection() -> String {
        let comments = commentExportItems
        guard !comments.isEmpty else { return "" }
        func rows(_ items: [CommentExportItem]) -> String {
            items.map { item in
                let tags = item.tags.map { "<span class=\"tag\">\(htmlEscaped($0))</span>" }.joined(separator: " ")
                let tagLine = tags.isEmpty ? "" : "<div>\(tags)</div>"
                return """
                <div class="comment">
                  <div class="comment-meta">\(htmlEscaped(item.title))</div>
                  <div style="\(htmlStyle(for: item.style))">\(htmlEscaped(item.body).replacingOccurrences(of: "\n", with: "<br>"))</div>
                  \(tagLine)
                </div>
                """
            }
            .joined(separator: "\n")
        }
        let openRows = rows(comments.filter { !$0.isResolved })
        let resolvedRows = rows(comments.filter(\.isResolved))
        let resolvedSection = resolvedRows.isEmpty ? "" : """
          <h3>Resolved</h3>
          \(resolvedRows)
        """
        return """
        <section>
          <h2>Comments</h2>
          \(openRows)
          \(resolvedSection)
        </section>
        """
    }

    private func markdownFormattedCommentBody(_ body: String, style: WorkspaceCommentStyle) -> String {
        var value = markdownInlineEscaped(body)
        if style.isBold && style.isItalic {
            value = "***\(value)***"
        } else if style.isBold {
            value = "**\(value)**"
        } else if style.isItalic {
            value = "*\(value)*"
        }
        return value
    }

    private func htmlStyle(for style: WorkspaceCommentStyle) -> String {
        let weight = style.isBold ? "font-weight: 700;" : ""
        let italic = style.isItalic ? "font-style: italic;" : ""
        let size = "font-size: \(Int(commentPointSize(for: style.textSize)))px;"
        let color = "color: \(safeCommentColorHex(style.colorHex));"
        return [weight, italic, size, color].filter { !$0.isEmpty }.joined(separator: " ")
    }

    private func commentPointSize(for size: WorkspaceCommentTextSize) -> CGFloat {
        switch size {
        case .small: return 11
        case .regular: return 13
        case .large: return 16
        }
    }

    private func safeCommentColorHex(_ value: String) -> String {
        nsColor(fromHex: value) == nil ? "#1F2933" : value
    }

    private func nsColor(fromHex value: String) -> NSColor? {
        var hex = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") {
            hex.removeFirst()
        }
        guard hex.count == 6,
              let raw = Int(hex, radix: 16) else {
            return nil
        }
        return NSColor(
            srgbRed: CGFloat((raw >> 16) & 0xFF) / 255,
            green: CGFloat((raw >> 8) & 0xFF) / 255,
            blue: CGFloat(raw & 0xFF) / 255,
            alpha: 1
        )
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
        case .pdf, .word, .legacyWord, .odt, .rtf, .text, .markdown, .html:
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
        return trimmed.isEmpty ? "Orifold Export" : trimmed
    }

    private struct ExportFailure: LocalizedError {
        var errorDescription: String?

        init(_ message: String) {
            errorDescription = message
        }
    }

    // MARK: - Page operations (all keyed by PageRef.id, all undoable)

    func rotatePage(_ ref: PageRef, by degrees: Int) {
        guard canPerformMutatingAction() else { return }
        guard let currentRotation = rotation(for: ref) else { return }
        setRotation(for: ref, to: (currentRotation + degrees + 360) % 360, actionName: "Rotate Page")
        PetBuddyHook.trigger(.rotate)
    }

    private func rotation(for ref: PageRef) -> Int? {
        guard let lookup = memberPDF(for: ref),
              let localIdx = localIndex(ref: ref, memberIndex: lookup.documentIndex),
              let page = lookup.pdf.page(at: localIdx) else { return nil }
        return page.rotation
    }

    private func setRotation(for ref: PageRef, to rotation: Int, actionName: String) {
        guard let lookup = memberPDF(for: ref),
              let localIdx = localIndex(ref: ref, memberIndex: lookup.documentIndex),
              let page = lookup.pdf.page(at: localIdx) else { return }
        let before = page.rotation
        let normalizedRotation = (rotation + 360) % 360
        guard before != normalizedRotation else { return }
        page.rotation = normalizedRotation
        rebuild()
        markWorkspaceModified()
        undoManager?.registerUndo(withTarget: self) { vm in
            guard vm.canPerformUndoMutation() else { return }
            vm.setRotation(for: ref, to: before, actionName: actionName)
        }
        undoManager?.setActionName(actionName)
    }

    func deletePage(_ ref: PageRef) {
        guard canPerformMutatingAction() else { return }
        guard let lookup = memberPDF(for: ref),
              let localIdx = localIndex(ref: ref, memberIndex: lookup.documentIndex),
              lookup.pdf.page(at: localIdx) != nil else { return }

        let snapshot = captureOrderSnapshot()
        let pdf = lookup.pdf
        pdf.removePage(at: localIdx)
        document.workspace.pageOrder.removeAll { $0.id == ref.id }
        document.workspace.documents[lookup.documentIndex].pageRefs.removeAll { $0 == ref.id }
        document.workspace.pageEditStates.removeAll { $0.pageRefID == ref.id }
        clearCommentAnchors(forRemovedPageRefIDs: [ref.id])
        removeSignaturePlacements(forRemovedPageRefIDs: [ref.id])
        removeDecorations(forRemovedPageRefIDs: [ref.id])
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
            guard vm.canPerformUndoMutation() else { return }
            vm.restore(snapshot)
        }
        undoManager?.setActionName(L10n.string("undo.deletePage"))
        PetBuddyHook.trigger(.delete)
    }

    func deletePages(_ refs: [PageRef]) {
        guard canPerformMutatingAction() else { return }
        let uniqueIDs = Set(refs.map(\.id))
        let orderedRefs = document.workspace.pageOrder.filter { uniqueIDs.contains($0.id) }
        guard !orderedRefs.isEmpty else { return }

        let snapshot = captureOrderSnapshot()
        for ref in orderedRefs.reversed() {
            guard let lookup = memberPDF(for: ref),
                  let localIdx = localIndex(ref: ref, memberIndex: lookup.documentIndex),
                  lookup.pdf.page(at: localIdx) != nil else { continue }
            lookup.pdf.removePage(at: localIdx)
            document.workspace.pageOrder.removeAll { $0.id == ref.id }
            document.workspace.documents[lookup.documentIndex].pageRefs.removeAll { $0 == ref.id }
            document.workspace.pageEditStates.removeAll { $0.pageRefID == ref.id }
            clearCommentAnchors(forRemovedPageRefIDs: [ref.id])
            removeSignaturePlacements(forRemovedPageRefIDs: [ref.id])
            removeDecorations(forRemovedPageRefIDs: [ref.id])
            textAnalysisCache.removeValue(forKey: ref.id)
        }
        for index in document.workspace.documents.indices.reversed() where document.workspace.documents[index].pageRefs.isEmpty {
            let id = document.workspace.documents[index].id
            document.workspace.documents.remove(at: index)
            loadedPDFs.removeAll { $0.0.id == id }
            document.memberPDFData.removeValue(forKey: id)
            document.sourcePayloads.removeValue(forKey: id)
        }
        for loadedIndex in loadedPDFs.indices {
            let memberID = loadedPDFs[loadedIndex].0.id
            if let updated = document.workspace.documents.first(where: { $0.id == memberID }) {
                loadedPDFs[loadedIndex].0 = updated
            }
        }
        rebuild()
        undoManager?.registerUndo(withTarget: self) { vm in
            guard vm.canPerformUndoMutation() else { return }
            vm.restore(snapshot)
        }
        undoManager?.setActionName(orderedRefs.count == 1 ? L10n.string("undo.deletePage") : L10n.string("undo.deletePages"))
        PetBuddyHook.trigger(.delete)
    }

    func rotatePages(_ refs: [PageRef], by degrees: Int) {
        guard canPerformMutatingAction() else { return }
        let uniqueIDs = Set(refs.map(\.id))
        let orderedRefs = document.workspace.pageOrder.filter { uniqueIDs.contains($0.id) }
        guard !orderedRefs.isEmpty else { return }
        let snapshot = captureOrderSnapshot()
        for ref in orderedRefs {
            guard let lookup = memberPDF(for: ref),
                  let localIdx = localIndex(ref: ref, memberIndex: lookup.documentIndex),
                  let page = lookup.pdf.page(at: localIdx) else { continue }
            page.rotation = (page.rotation + degrees + 360) % 360
        }
        rebuild()
        markWorkspaceModified()
        undoManager?.registerUndo(withTarget: self) { vm in
            guard vm.canPerformUndoMutation() else { return }
            vm.restore(snapshot)
        }
        undoManager?.setActionName(orderedRefs.count == 1 ? "Rotate Page" : "Rotate Pages")
        PetBuddyHook.trigger(.rotate)
    }

    func duplicatePages(_ refs: [PageRef]) {
        guard canPerformMutatingAction() else { return }
        let uniqueIDs = Set(refs.map(\.id))
        let orderedRefs = document.workspace.pageOrder.filter { uniqueIDs.contains($0.id) }
        guard !orderedRefs.isEmpty else { return }
        let snapshot = captureOrderSnapshot()
        for ref in orderedRefs.reversed() {
            guard let lookup = memberPDF(for: ref),
                  let localIdx = localIndex(ref: ref, memberIndex: lookup.documentIndex),
                  let page = lookup.pdf.page(at: localIdx),
                  let copiedPage = page.copy() as? PDFPage else { continue }
            let duplicate = PageRef(memberDocId: ref.memberDocId, sourcePageIndex: ref.sourcePageIndex, rotation: ref.rotation, cropBox: ref.cropBox)
            lookup.pdf.insert(copiedPage, at: localIdx + 1)
            document.workspace.documents[lookup.documentIndex].pageRefs.insert(duplicate.id, at: localIdx + 1)
            if let pageOrderIndex = document.workspace.pageOrder.firstIndex(where: { $0.id == ref.id }) {
                document.workspace.pageOrder.insert(duplicate, at: pageOrderIndex + 1)
            }
            loadedPDFs[lookup.loadedIndex].0 = document.workspace.documents[lookup.documentIndex]
        }
        rebuild()
        markWorkspaceModified()
        undoManager?.registerUndo(withTarget: self) { vm in
            guard vm.canPerformUndoMutation() else { return }
            vm.restore(snapshot)
        }
        undoManager?.setActionName(orderedRefs.count == 1 ? "Duplicate Page" : "Duplicate Pages")
    }

    func exportPages(_ refs: [PageRef]) {
        let uniqueIDs = Set(refs.map(\.id))
        let orderedRefs = document.workspace.pageOrder.filter { uniqueIDs.contains($0.id) }
        guard !orderedRefs.isEmpty else { return }
        let output = PDFDocument()
        for ref in orderedRefs {
            guard let lookup = memberPDF(for: ref),
                  let localIdx = localIndex(ref: ref, memberIndex: lookup.documentIndex),
                  let page = lookup.pdf.page(at: localIdx),
                  let copiedPage = page.copy() as? PDFPage else { continue }
            output.insert(copiedPage, at: output.pageCount)
        }
        guard output.pageCount > 0,
              let data = PDFSerializer.data(from: output) else {
            exportError = ExportError(message: L10n.string("error.export.preparePagesForExport"))
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "\(safeFilename(document.workspace.title))-selected-pages.pdf"
        panel.title = L10n.string("savePanel.exportSelectedPages.title")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try writeExportData(data, to: url)
            try verifyExportedFile(at: url)
            finalizeSuccessfulExport(url: url, format: .pdf, includeCommentStatus: false)
        } catch {
            if let writeError = error as? ExportWriteError {
                exportError = ExportError(message: writeError.userMessage)
            } else {
                exportError = ExportError(message: String(localized: "Orifold could not export the selected pages: \(error.localizedDescription)", locale: L10n.currentLocale))
            }
        }
    }

    @discardableResult
    func movePage(_ ref: PageRef, toIndex destination: Int) -> Bool {
        guard canPerformMutatingAction() else { return false }
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
            guard vm.canPerformUndoMutation() else { return }
            vm.restore(snapshot)
        }
        undoManager?.setActionName(L10n.string("undo.movePage"))
        return true
    }

    @discardableResult
    func movePage(_ ref: PageRef, after targetRef: PageRef) -> Bool {
        guard canPerformMutatingAction() else { return false }
        guard ref.memberDocId != targetRef.memberDocId,
              let sourceLookup = memberPDF(for: ref),
              let targetLookup = memberPDF(for: targetRef),
              let sourceLocalIdx = localIndex(ref: ref, memberIndex: sourceLookup.documentIndex),
              let targetLocalIdx = localIndex(ref: targetRef, memberIndex: targetLookup.documentIndex),
              let page = sourceLookup.pdf.page(at: sourceLocalIdx) else { return false }

        let snapshot = captureOrderSnapshot()
        sourceLookup.pdf.removePage(at: sourceLocalIdx)
        let targetInsertIndex = min(targetLocalIdx + 1, targetLookup.pdf.pageCount)
        targetLookup.pdf.insert(page, at: targetInsertIndex)

        document.workspace.documents[sourceLookup.documentIndex].pageRefs.removeAll { $0 == ref.id }
        var movedRef = ref
        movedRef.memberDocId = targetRef.memberDocId
        movedRef.sourcePageIndex = targetInsertIndex
        document.workspace.documents[targetLookup.documentIndex].pageRefs.insert(
            movedRef.id,
            at: min(targetInsertIndex, document.workspace.documents[targetLookup.documentIndex].pageRefs.count)
        )
        if let pageOrderIndex = document.workspace.pageOrder.firstIndex(where: { $0.id == movedRef.id }) {
            document.workspace.pageOrder.remove(at: pageOrderIndex)
        }
        if let targetPageOrderIndex = document.workspace.pageOrder.firstIndex(where: { $0.id == targetRef.id }) {
            document.workspace.pageOrder.insert(movedRef, at: min(targetPageOrderIndex + 1, document.workspace.pageOrder.count))
        } else {
            document.workspace.pageOrder.append(movedRef)
        }

        document.sourcePayloads.removeValue(forKey: ref.memberDocId)
        document.sourcePayloads.removeValue(forKey: targetRef.memberDocId)
        if document.workspace.documents[sourceLookup.documentIndex].pageRefs.isEmpty {
            let removedID = document.workspace.documents[sourceLookup.documentIndex].id
            document.workspace.documents.remove(at: sourceLookup.documentIndex)
            loadedPDFs.removeAll { $0.0.id == removedID }
            document.memberPDFData.removeValue(forKey: removedID)
            document.sourcePayloads.removeValue(forKey: removedID)
        }
        for loadedIndex in loadedPDFs.indices {
            let memberID = loadedPDFs[loadedIndex].0.id
            if let updated = document.workspace.documents.first(where: { $0.id == memberID }) {
                loadedPDFs[loadedIndex].0 = updated
            }
        }
        selectedPageRefID = movedRef.id
        selectedPageRefIDs = [movedRef.id]
        rebuild()
        undoManager?.registerUndo(withTarget: self) { vm in
            guard vm.canPerformUndoMutation() else { return }
            vm.restore(snapshot)
        }
        undoManager?.setActionName(L10n.string("undo.movePage"))
        return true
    }

    // MARK: - Annotation helpers (underline, strikeout)

    @discardableResult
    func applyMarkup(_ type: PDFAnnotationSubtype, to selection: PDFSelection) -> Bool {
        guard canPerformMutatingAction() else { return false }
        var didAddAnnotation = false
        selection.selectionsByLine().forEach { line in
            guard let page = line.pages.first else { return }
            let bounds = line.bounds(for: page)
            guard !hasEquivalentAnnotation(on: page, subtype: type, bounds: bounds) else { return }
            let ann = PDFAnnotation(bounds: bounds, forType: type, withProperties: nil)
            ann.color = annotationColor.withAlphaComponent(0.8)
            page.addAnnotation(ann)
            undoManager?.registerUndo(withTarget: self) { vm in
                guard vm.canPerformUndoMutation() else { return }
                page.removeAnnotation(ann)
            }
            didAddAnnotation = true
        }
        if didAddAnnotation {
            markAnnotationsModified()
            undoManager?.setActionName(type == .underline ? "Underline" : "Strikeout")
            PetBuddyHook.trigger(.highlight)
        }
        return didAddAnnotation
    }

    private func hasEquivalentAnnotation(on page: PDFPage, subtype: PDFAnnotationSubtype, bounds: CGRect) -> Bool {
        let typeName = subtype.rawValue.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return page.annotations.contains { annotation in
            annotation.type == typeName && annotation.bounds.isApproximatelyEqual(to: bounds)
        }
    }

    // MARK: - TOC synthesis

    struct TOCEntry: Identifiable {
        var id: UUID
        var title: String
        var jumpPageIndex: Int
        var displayPageNumber: Int
    }

    var tableOfContents: [TOCEntry] {
        var entries: [TOCEntry] = []
        var combinedIdx = 0
        var realPageNumber = 1
        for member in document.workspace.documents {
            entries.append(TOCEntry(
                id: member.id,
                title: member.displayName,
                jumpPageIndex: combinedIdx + 1,
                displayPageNumber: realPageNumber
            ))
            combinedIdx += 1 + member.pageRefs.count  // 1 banner + N pages
            realPageNumber += member.pageRefs.count
        }
        return entries
    }

    // MARK: - Print

    func printWorkspace() {
        let printableDocument: PDFDocument
        do {
            let data = try dataForPDFExport()
            guard let document = PDFDocument(data: data) else {
                exportError = ExportError(message: L10n.string("error.export.preparePrinting"))
                return
            }
            printableDocument = document
        } catch {
            exportError = ExportError(message: userMessage(for: error, exporting: .pdf))
            return
        }

        let info = NSPrintInfo.shared
        info.horizontalPagination = .fit
        info.verticalPagination = .fit
        info.isHorizontallyCentered = true
        info.isVerticallyCentered = false

        let printView = PDFView(frame: NSRect(x: 0, y: 0, width: 612, height: 792))
        printView.document = printableDocument
        printView.displayMode = .singlePageContinuous
        printView.autoScales = true

        let op = NSPrintOperation(view: printView, printInfo: info)
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

private extension CGRect {
    func isApproximatelyEqual(to other: CGRect, tolerance: CGFloat = 0.25) -> Bool {
        abs(minX - other.minX) <= tolerance &&
            abs(minY - other.minY) <= tolerance &&
            abs(width - other.width) <= tolerance &&
            abs(height - other.height) <= tolerance
    }
}

private final class SignatureImageAnnotation: PDFAnnotation {
    let placementID: UUID
    private let signatureImage: NSImage

    init(bounds: CGRect, image: NSImage, placementID: UUID) {
        self.placementID = placementID
        self.signatureImage = image
        super.init(bounds: bounds, forType: .stamp, withProperties: nil)
        setValue(placementID.uuidString, forAnnotationKey: WorkspaceViewModel.signaturePlacementAnnotationKey)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        guard let cgImage = signatureImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return
        }
        context.saveGState()
        context.interpolationQuality = .high
        context.draw(cgImage, in: bounds)
        context.restoreGState()
    }
}
