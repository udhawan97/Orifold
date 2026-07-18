import SwiftUI
import PDFKit
import AppKit
import Combine
import CoreServices
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
        case .pdf: return L10n.string("exportFormat.pdf.menuTitle")
        case .word: return L10n.string("exportFormat.word.menuTitle")
        case .legacyWord: return L10n.string("exportFormat.legacyWord.menuTitle")
        case .odt: return L10n.string("exportFormat.odt.menuTitle")
        case .rtf: return L10n.string("exportFormat.rtf.menuTitle")
        case .text: return L10n.string("exportFormat.text.menuTitle")
        case .markdown: return L10n.string("exportFormat.markdown.menuTitle")
        case .html: return L10n.string("exportFormat.html.menuTitle")
        case .png: return L10n.string("exportFormat.png.menuTitle")
        case .jpeg: return L10n.string("exportFormat.jpeg.menuTitle")
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
    case selectObject = "selectObject"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .selectObject: return L10n.string("annotationTool.selectObject.label")
        case .none:      return L10n.string("annotationTool.none.label")
        case .highlight: return L10n.string("annotationTool.highlight.label")
        case .note:      return L10n.string("annotationTool.note.label")
        case .comment:   return L10n.string("annotationTool.comment.label")
        case .commentRegion: return L10n.string("annotationTool.commentRegion.label")
        case .editText:  return L10n.string("annotationTool.editText.label")
        case .ink:       return L10n.string("annotationTool.ink.label")
        case .eraser:    return L10n.string("annotationTool.eraser.label")
        case .underline: return L10n.string("annotationTool.underline.label")
        case .strikeout: return L10n.string("annotationTool.strikeout.label")
        case .signature: return L10n.string("annotationTool.signature.label")
        case .stamp:     return L10n.string("annotationTool.stamp.label")
        }
    }

    var iconName: String {
        switch self {
        case .selectObject: return "hand.point.up.left"
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
        case .selectObject: return L10n.string("annotationTool.selectObject.helpText")
        case .none:      return L10n.string("annotationTool.none.helpText")
        case .highlight: return L10n.string("annotationTool.highlight.helpText")
        case .note:      return L10n.string("annotationTool.note.helpText")
        case .comment:   return L10n.string("annotationTool.comment.helpText")
        case .commentRegion: return L10n.string("annotationTool.commentRegion.helpText")
        case .editText:  return L10n.string("annotationTool.editText.helpText")
        case .ink:       return L10n.string("annotationTool.ink.helpText")
        case .eraser:    return L10n.string("annotationTool.eraser.helpText")
        case .underline: return L10n.string("annotationTool.underline.helpText")
        case .strikeout: return L10n.string("annotationTool.strikeout.helpText")
        case .signature: return L10n.string("annotationTool.signature.helpText")
        case .stamp:     return L10n.string("annotationTool.stamp.helpText")
        }
    }

    var isColorable: Bool {
        switch self {
        case .highlight, .note, .editText, .ink, .underline, .strikeout: return true
        case .none, .comment, .commentRegion, .eraser, .signature, .stamp, .selectObject: return false
        }
    }

    var usesInkColor: Bool { self == .ink }

    var isReaderModeAllowed: Bool {
        switch self {
        case .editText, .signature, .selectObject:
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
    var isReplaceRevealed = false
    var replaceText = ""
    /// The single armed click-to-place action; see `PendingPlacement`. The four
    /// `pending*` properties below read out of this one slot, so exclusion between
    /// placements is structural rather than hand-maintained.
    var armedPlacement: PendingPlacement? = nil
    var pendingSignatureData: Data? {
        if case .signature(let data, _, _) = armedPlacement { return data }
        return nil
    }
    var pendingSignatureOptions: PendingSignaturePlacementOptions? {
        if case .signature(_, let options, _) = armedPlacement { return options }
        return nil
    }
    var pendingStampOptions: PendingStampPlacementOptions? {
        if case .stamp(let options) = armedPlacement { return options }
        return nil
    }
    var pendingHankoOptions: PendingHankoPlacementOptions? {
        if case .hanko(let options) = armedPlacement { return options }
        return nil
    }
    var pendingBarcodeOptions: PendingBarcodePlacementOptions? {
        if case .barcode(let options) = armedPlacement { return options }
        return nil
    }
    /// Drives the barcode/QR composer sheet (Feature G). Set from the More-menu "Insert
    /// barcode/QR" row; the sheet arms `pendingBarcodeOptions` on Insert, then dismisses.
    var isShowingBarcodeComposer = false
    /// Non-nil while the barcode scan-result sheet is presented; carries the barcodes found on
    /// the scanned page (empty array → the sheet shows its "no barcodes" empty state).
    var barcodeScanResults: BarcodeScanResults? = nil
    var selectedStampDecorationID: UUID? = nil {
        didSet { if selectedStampDecorationID != nil { objectSelection = nil } }
    }
    private(set) var decorationStateVersion = 0
    var selectedPageRefID: UUID? = nil
    var selectedPageRefIDs: Set<UUID> = []
    var draggedPageRefID: UUID? = nil
    var draggedMemberID: UUID? = nil
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
    /// True once the user has pinned Format Painter (⌥-click Copy Style) so it stays armed
    /// and re-applies to every subsequently opened editor, instead of disarming after one
    /// paste — mirrors Word's double-click-to-lock Format Painter behavior.
    var isFormatPainterPinned = false
    var operationProgress = WorkspaceOperationProgress()
    var formSummary = PDFFormSummary()
    var highlightFormFields = false
    var selectedFormFieldIndex: Int? = nil
    var appAppearanceMode: AppAppearanceMode = .system
    var documentComfortSettings = DocumentComfortSettings.default

    var hasPendingSignaturePlacement: Bool {
        if case .signature = armedPlacement { return true }
        return false
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
    var selectedAnnotation: PDFAnnotation? = nil {
        didSet { if selectedAnnotation != nil { objectSelection = nil } }
    }

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

    var isSigningInProgress: Bool { activeSigningTask != nil }

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
    private let pageInspectionCache = PDFPageObjectInspection.Cache()
    private var pageInspectionRevisions: [UUID: PDFPageObjectInspection.Revision] = [:]
    private var textAnalysisCache: [UUID: PDFTextPageAnalysis] = [:]
    // Object editing (docs/OBJECT_EDITING_PLAN.md §3.5/§8). Detection map cached per PageRef;
    // `objectBaseData` is the canonical per-member replay base. Both text and object operations
    // are derived from it by WorkspaceEditReplayEngine, so neither lane can bake over the other.
    private var objectAnalysisCache: [UUID: PageObjectMap] = [:]
    private var objectBaseData: [UUID: Data] = [:]
    private var pendingSigningIdentity: (any SigningIdentity)? {
        if case .signature(_, _, let identity) = armedPlacement { return identity }
        return nil
    }
    private var signingIdentitiesByPlacementID: [UUID: any SigningIdentity] = [:]
    @ObservationIgnored private var searchDebounceTask: Task<Void, Never>?
    @ObservationIgnored private var activeCompressionTask: Task<Void, Never>?
    @ObservationIgnored private var activeCompressionCancellation: OperationCancellationToken?
    @ObservationIgnored private var activeCompressionID: UUID?
    @ObservationIgnored private var activeSigningTask: Task<Void, Never>?
    @ObservationIgnored private var activeSigningCancellation: OperationCancellationToken?
    @ObservationIgnored private var activeSigningID: UUID?
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

    /// Read-aloud controller (Feature C), built on first access to the `readAloud` property.
    /// In practice that happens when a `ReadingCanvas` is created and subscribes to the
    /// controller's `$highlight` to mirror it as a selection — i.e. once per workspace window,
    /// whether or not read-aloud is ever started, since the canvas needs the publisher wired up
    /// front. Built on the main actor (its own isolation), so never off-main. Not a leak: every
    /// back-reference the controller holds into this view model is weak. `@ObservationIgnored`
    /// because it's a self-contained `ObservableObject`; its `state` is mirrored into
    /// `readAloudState` (below) so SwiftUI views — which observe this `@Observable` view model,
    /// not the nested controller — react.
    @ObservationIgnored private var _readAloud: ReadAloudController?
    @ObservationIgnored private var readAloudCancellables = Set<AnyCancellable>()

    /// The read-aloud controller's state, mirrored here so the toolbar/menu/capsule (which
    /// observe this view model) show/hide and toggle reactively. `.idle` until reading starts.
    private(set) var readAloudState: ReadAloudController.State = .idle

    /// Selected read-aloud speed. Change it through `setReadAloudRate(_:)` so the value also
    /// reaches the (main-actor-isolated) controller and takes effect on the next spoken sentence.
    private(set) var readAloudRate: ReadAloudRate = .normal

    /// Raw PDF bytes captured ONCE when each member is first loaded or attached.
    /// Never mutated during editing — used as the immutable base for page regeneration
    /// so multiple edits on the same page always start from the original content.
    private var originalMemberPDFData: [UUID: Data] = [:]

    /// Immutable snapshot of the document exactly as it finished loading — the baseline
    /// behind "Discard Changes & Close". Captured once at the end of `init`; `Data` and
    /// `Workspace` are value types (copy-on-write), so this only retains the original
    /// member buffers, it doesn't eagerly duplicate them until an edit replaces an entry.
    @ObservationIgnored private var initialDocumentState: InitialDocumentState?

    /// The AppKit window hosting this document, resolved by a background accessor in
    /// `ContentView`. `discardChangesAndClose()` uses it to close the window directly,
    /// bypassing the save-on-close path that can dead-end at "The file couldn't be saved."
    @ObservationIgnored weak var hostingWindow: NSWindow?

    private struct InitialDocumentState {
        var workspace: Workspace
        var memberPDFData: [UUID: Data]
        var sourcePayloads: [UUID: SourceDocumentPayload]
        var originalMemberPDFData: [UUID: Data]
    }
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
        /// Defaults to `.unknown` so existing call sites that only have a raw error
        /// message keep compiling; call sites that know more (recents, export-reopen)
        /// pass real classification for recovery-action rendering.
        var kind: ImportFailureKind = .unknown
        /// Set when this failure originated from a `RecentFileEntry`, so the alert can
        /// offer "Remove from Recents".
        var recentEntryID: UUID? = nil
        /// The URL that failed to open, when known — used for "Show in Finder" and to
        /// scope a "Choose File Again" panel to the right folder.
        var sourceURL: URL? = nil
    }

    struct ExportError: Identifiable {
        let id = UUID()
        var message: String
    }

    struct ExportSuccess: Identifiable {
        let id = UUID()
        var url: URL
        var detail: String? = nil
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
        var certificateProfileID: UUID?

        static var visualTyped: PendingSignaturePlacementOptions {
            PendingSignaturePlacementOptions(
                kind: .visualTyped,
                signerName: nil,
                signerIdentityRef: nil,
                reason: nil,
                location: nil,
                contactInfo: nil,
                subFilter: nil,
                timestampRequested: false,
                certificateProfileID: nil
            )
        }
    }

    struct PendingStampPlacementOptions: Equatable {
        var text: String
        var swatch: PageDecorationSwatch
    }

    struct PendingHankoPlacementOptions: Equatable {
        var text: String
        var shape: HankoShape
    }

    /// The generated barcode image armed for click-to-place. `pixelSize` lets `placeBarcode`
    /// derive an aspect-correct page rect so a wide 1-D code (Code 128) isn't squished into a
    /// square, while a QR stays square.
    struct PendingBarcodePlacementOptions: Equatable {
        var imageData: Data
        var pixelSize: CGSize
    }

    /// The one armed click-to-place action. A page click resolves to exactly one
    /// placement, so this is a single slot rather than four parallel optionals:
    /// arming any placement structurally disarms the rest, instead of each entry
    /// point having to remember to nil out its three siblings.
    ///
    /// The signature case carries its identity alongside its options because the
    /// three travel together — a cryptographic placement is meaningless with the
    /// identity dropped, which parallel optionals allowed.
    enum PendingPlacement {
        case signature(data: Data, options: PendingSignaturePlacementOptions, identity: (any SigningIdentity)?)
        case stamp(PendingStampPlacementOptions)
        case hanko(PendingHankoPlacementOptions)
        case barcode(PendingBarcodePlacementOptions)
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
        var unreadableMemberIDs: Set<UUID> = []
        for member in document.workspace.documents {
            if let data = document.memberPDFData[member.id],
               let pdf = PDFDocument(data: data) {
                smokeValidatePDFData(data)
                sanitizeInkAnnotations(in: pdf)
                loadedPDFs.append((member, pdf))
                // Capture original (pre-edit) bytes exactly once for clean regeneration.
                // A workspace saved WITH committed edit operations persists its true
                // pristine bytes separately (`restoredOriginalMemberPDFData`) — the loaded
                // member bytes already contain the baked edits in that case and must not
                // be mistaken for a pristine base, or every re-edit would erase/redraw on
                // top of the previous bake instead of regenerating from the original.
                if let pristine = document.restoredOriginalMemberPDFData[member.id] {
                    originalMemberPDFData[member.id] = pristine
                } else {
                    originalMemberPDFData[member.id] = data
                    // With no separately-persisted pristine payload, the pristine base IS
                    // the loaded bytes — whose page layout mirrors member.pageRefs, not
                    // whatever sourcePageIndex each ref carried when it was first
                    // imported. Structural ops (delete/reorder/duplicate) before the save
                    // left refs pointing at stale indices; keeping them would make every
                    // regeneration/hit-test read a NEIGHBORING page of the new base
                    // (data-destroying). Renormalize to the layout the base actually has.
                    for (localIdx, refID) in member.pageRefs.enumerated() {
                        if let orderIdx = document.workspace.pageOrder.firstIndex(where: { $0.id == refID }),
                           document.workspace.pageOrder[orderIdx].sourcePageIndex != localIdx {
                            document.workspace.pageOrder[orderIdx].sourcePageIndex = localIdx
                        }
                    }
                }
            } else {
                unreadableMemberIDs.insert(member.id)
            }
        }
        // A member whose bytes fail to parse must not linger in the workspace structure:
        // pageOrder/pageCount would keep counting its pages while combinedPDF omits them,
        // so every later page's click/marker/export index resolves to the WRONG PageRef.
        // Drop it from the in-memory structure too (bytes stay in memberPDFData untouched
        // in case a later build can recover them) and tell the user.
        if !unreadableMemberIDs.isEmpty {
            let names = document.workspace.documents
                .filter { unreadableMemberIDs.contains($0.id) }
                .map(\.displayName)
                .joined(separator: ", ")
            NSLog("[Orifold] Warning: dropping unreadable member document(s) from the workspace structure: %@", names)
            document.workspace.documents.removeAll { unreadableMemberIDs.contains($0.id) }
            document.workspace.pageOrder.removeAll { unreadableMemberIDs.contains($0.memberDocId) }
            importError = ImportError(
                fileName: names,
                message: L10n.string("error.import.unreadableSavedMember")
            )
        }

        // The file changed on disk since Orifold last saved it: the loader kept the visible
        // content and dropped the now-stale edit operations. Tell the user once (unless a
        // hard load error already claimed the alert).
        if document.externalModificationDetected, importError == nil {
            importError = ImportError(
                fileName: document.workspace.title,
                message: L10n.string("notice.externalModification.detected")
            )
        }

        // Snapshot hook: bake live annotation state before each save
        document.currentPDFDataProvider = { [weak self] in
            guard let self else { return [:] }
            return try self.currentPDFDataForExport()
        }
        // Snapshot hook: persist pristine bytes for members with committed edits so a
        // fresh session can always regenerate f(pristine, operations) exactly.
        document.currentOriginalPDFDataProvider = { [weak self] in
            guard let self else { return [:] }
            return self.pristineDataForMembersWithCommittedEdits()
        }

        // A freshly-opened workspace must SHOW its committed edits — never trust that the
        // saved bytes and the saved operations agree (a historical divergence otherwise
        // stays trapped forever: the editor "remembers" the edit while the page and every
        // export silently miss it).
        reconcileCommittedEditsWithLoadedPages()

        if !loadedPDFs.isEmpty { rebuild() }

        // Capture the document exactly as opened (post-reconcile, post-normalization) so
        // "Discard Changes & Close" can always roll back to this known-good baseline.
        initialDocumentState = InitialDocumentState(
            workspace: document.workspace,
            memberPDFData: document.memberPDFData,
            sourcePayloads: document.sourcePayloads,
            originalMemberPDFData: originalMemberPDFData
        )
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
        activeSigningCancellation?.cancel()
        activeSigningTask?.cancel()
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
                message: String(localized: "Could not open \"\(failure.url.lastPathComponent)\". \(DocumentImportConverter.userMessage(for: failure.error))", locale: L10n.currentLocale),
                kind: ImportFailureClassifier.classify(error: failure.error, url: failure.url),
                sourceURL: failure.url
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
            guard !cancellation.isCancelled, !Task.isCancelled else {
                return .failure(AsyncImportFailure(url: url, error: CancellationError()))
            }
            let isSecurityScoped = url.startAccessingSecurityScopedResource()
            defer {
                if isSecurityScoped { url.stopAccessingSecurityScopedResource() }
            }
            if let preflightKind = ImportFailureClassifier.preflight(url: url) {
                ImportLog.recordAttempt(
                    source: .openPanel,
                    fileExtension: url.pathExtension,
                    securityScopeGranted: isSecurityScoped,
                    fileExists: preflightKind != .fileMissing,
                    isReadable: false,
                    parserResult: .failed
                )
                return .failure(AsyncImportFailure(url: url, error: preflightKind))
            }
            do {
                let document = try await DocumentImportConverter.importedDocumentAsync(from: url)
                try Task.checkCancellation()
                guard !cancellation.isCancelled else { throw CancellationError() }
                ImportLog.recordAttempt(
                    source: .openPanel,
                    fileExtension: url.pathExtension,
                    securityScopeGranted: isSecurityScoped,
                    fileExists: true,
                    isReadable: true,
                    parserResult: .ok
                )
                return .success(AsyncImportedDocument(url: url, document: document))
            } catch {
                ImportLog.recordAttempt(
                    source: .openPanel,
                    fileExtension: url.pathExtension,
                    securityScopeGranted: isSecurityScoped,
                    fileExists: true,
                    isReadable: true,
                    parserResult: .failed,
                    errorDomain: (error as NSError).domain,
                    errorCode: (error as NSError).code
                )
                return .failure(AsyncImportFailure(url: url, error: error))
            }
        }.value
    }

    private func addFileSynchronously(from url: URL) {
        let fileName = url.lastPathComponent
        let isSecurityScoped = url.startAccessingSecurityScopedResource()
        defer {
            if isSecurityScoped { url.stopAccessingSecurityScopedResource() }
        }

        if let preflightKind = ImportFailureClassifier.preflight(url: url) {
            ImportLog.recordAttempt(
                source: .openPanel,
                fileExtension: url.pathExtension,
                securityScopeGranted: isSecurityScoped,
                fileExists: preflightKind != .fileMissing,
                isReadable: false,
                parserResult: .failed
            )
            importError = ImportError(
                fileName: fileName,
                message: DocumentImportConverter.userMessage(for: preflightKind),
                kind: preflightKind,
                sourceURL: url
            )
            return
        }

        let imported: DocumentImportConverter.ImportedDocument
        do {
            imported = try DocumentImportConverter.importedDocument(from: url)
        } catch {
            ImportLog.recordAttempt(
                source: .openPanel,
                fileExtension: url.pathExtension,
                securityScopeGranted: isSecurityScoped,
                fileExists: true,
                isReadable: true,
                parserResult: .failed,
                errorDomain: (error as NSError).domain,
                errorCode: (error as NSError).code
            )
            importError = ImportError(
                fileName: fileName,
                message: String(localized: "Could not open \"\(fileName)\". \(DocumentImportConverter.userMessage(for: error))", locale: L10n.currentLocale),
                kind: ImportFailureClassifier.classify(error: error, url: url),
                sourceURL: url
            )
            return
        }
        ImportLog.recordAttempt(
            source: .openPanel,
            fileExtension: url.pathExtension,
            securityScopeGranted: isSecurityScoped,
            fileExists: true,
            isReadable: true,
            parserResult: .ok
        )
        let pdf = imported.pdfDocument
        if pdf.isLocked {
            enqueuePasswordImport(pdf: pdf, url: url)
            return
        }
        attachPDF(pdf, from: url, sourcePayload: imported.sourcePayload, originalPDFData: imported.originalPDFData)
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
        return attachPDF(
            pdf,
            from: url,
            sourcePayload: imported.sourcePayload,
            insertingAfter: targetPageRefID,
            originalPDFData: imported.originalPDFData
        )
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
                           insertingAfter targetPageRefID: UUID? = nil,
                           originalPDFData: Data? = nil) -> MemberDocument? {
        sanitizeInkAnnotations(in: pdf)

        // The normalizer's structural agreement gate uses its own PDFium validation
        // internally (the default), intentionally decoupled from `processingEngine` — that
        // engine drives `smokeValidatePDFData`/`lastProcessingValidation` and may be a test
        // double, whereas the trust gate must reflect the real renderer.
        guard let data = PDFImportNormalizer.normalizedData(
            originalPDFData: originalPDFData,
            renderedPDF: pdf
        ) else {
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
        // Abort any in-flight read-aloud before the page set changes underneath it. A structural
        // mutation (delete/insert/reorder/undo) reshuffles combinedPDF's indices, so the
        // controller's snapshot — its chunk offsets and page index — would now point into the
        // wrong page, landing the highlight out of bounds. Read-aloud is user-driven and only
        // ever active on the main thread, where its (main-actor-isolated) controller lives; the
        // main-thread guard skips the off-main rebuilds that background import/init perform (the
        // controller is guaranteed inactive there) rather than trap in `assumeIsolated`.
        // `_readAloud?` never forces the lazy controller into existence.
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                if let readAloud = _readAloud, readAloud.isActive { readAloud.stop() }
            }
        }
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
        removedIds.forEach { invalidatePageInspection(for: $0) }
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
        /// Canonical member bases must travel with page structure. Member-atomic replay indexes
        /// operations into these bytes, so restoring one without the other can target a neighbor.
        var originalMemberPDFData: [UUID: Data]
        var sourcePayloads: [UUID: SourceDocumentPayload]
        /// Captured together with `pdfData` because the two must move as a unit: the PDF
        /// bytes contain the BAKED result of these operations. Restoring bytes from one
        /// point in time with operations from another leaves an edit that the editor
        /// "remembers" but the page/export doesn't show (or vice versa, ghost ink with no
        /// backing operation).
        var pageEditStates: [PageEditState]
        /// Same rule as `pageEditStates`, for the object-editing lane: `objectBaseData` is the
        /// frozen per-member base that `objectEditStates`' ops replay onto, so the two must move
        /// together with `pdfData` or a later object edit re-derives bytes from a base that no
        /// longer matches the restored ops.
        var objectEditStates: [PageObjectEditState]
        var objectBaseData: [UUID: Data]
        /// Restoring this is what makes `restore()` a true timeline jump for the selection too:
        /// whatever was selected at snapshot time comes back — nil if nothing was, or an
        /// unrelated valid selection elsewhere in the document that had nothing to do with
        /// whatever's being undone/redone. A blanket clear would drop that unrelated selection.
        var objectSelection: ObjectSelectionState?
    }

    private struct InlineTextEditSnapshot {
        var editStates: [PageEditState]
        var objectEditStates: [PageObjectEditState]   // object editing rides the same snapshot
        var objectBaseData: [UUID: Data]              // per-member base bytes object ops apply to
        var objectSelection: ObjectSelectionState?    // so undo doesn't leave a stale overlay
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
            originalMemberPDFData: originalMemberPDFData,
            sourcePayloads: document.sourcePayloads,
            pageEditStates: document.workspace.pageEditStates,
            objectEditStates: document.workspace.objectEditStates,
            objectBaseData: objectBaseData,
            objectSelection: objectSelection
        )
    }

    private func restore(_ snapshot: OrderSnapshot) {
        // Register the inverse so the restore itself is redoable — undo closures that
        // register nothing leave NSUndoManager's redo stack empty, which silently made
        // every order-snapshot operation (page delete/move/duplicate, document reorder,
        // OCR, form reset) un-redoable after its undo.
        let inverse = captureOrderSnapshot()
        registerIsolatedUndo {
            undoManager?.registerUndo(withTarget: self) { vm in
                guard vm.canPerformUndoMutation() else { return }
                vm.restore(inverse)
            }
        }
        document.workspace.documents = snapshot.documents
        document.workspace.pageOrder = snapshot.pageOrder
        document.workspace.comments = snapshot.comments
        document.workspace.signatures = snapshot.signatures
        document.workspace.decorations = snapshot.decorations
        signingIdentitiesByPlacementID = snapshot.signatureIdentities
        document.memberPDFData = snapshot.pdfData
        originalMemberPDFData = snapshot.originalMemberPDFData
        invalidatePageInspection()
        document.sourcePayloads = snapshot.sourcePayloads
        document.workspace.pageEditStates = snapshot.pageEditStates
        document.workspace.objectEditStates = snapshot.objectEditStates
        objectBaseData = snapshot.objectBaseData
        loadedPDFs = snapshot.documents.compactMap { member in
            guard let data = snapshot.pdfData[member.id],
                  let pdf = PDFDocument(data: data) else { return nil }
            return (member, pdf)
        }
        textAnalysisCache.removeAll()
        objectAnalysisCache.removeAll()
        objectSelection = snapshot.objectSelection
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
            objectEditStates: document.workspace.objectEditStates,
            objectBaseData: objectBaseData,
            objectSelection: objectSelection,
            pageRotations: currentPageRotations(),
            pdfData: currentPDFData()
        )
    }

    private func restoreInlineTextEditSnapshot(_ snapshot: InlineTextEditSnapshot, actionName: String) {
        let inverse = captureInlineTextEditSnapshot()
        document.workspace.pageEditStates = snapshot.editStates
        document.workspace.objectEditStates = snapshot.objectEditStates
        objectBaseData = snapshot.objectBaseData
        objectSelection = snapshot.objectSelection
        objectAnalysisCache.removeAll()
        // Merge rather than replace: members imported AFTER this snapshot was captured
        // have no entry in it, and wholesale replacement silently dropped them from
        // loadedPDFs/memberPDFData (vanishing from the canvas and every export) while
        // they remained in the workspace structure.
        var mergedPDFData = document.memberPDFData
        for (memberID, data) in snapshot.pdfData {
            mergedPDFData[memberID] = data
        }
        document.memberPDFData = mergedPDFData
        loadedPDFs = document.workspace.documents.compactMap { member in
            guard let data = mergedPDFData[member.id],
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

    /// Returns whether the body was actually applied — callers that count successful
    /// mutations (like Replace All) need this instead of assuming success, since a
    /// rewrite that trims down to empty (e.g. replacing a whole-body match with "")
    /// is intentionally rejected here rather than leaving a blank comment behind.
    @discardableResult
    func updateCommentBody(_ comment: WorkspaceComment, body rawBody: String) -> Bool {
        guard canPerformMutatingAction() else { return false }
        let body = rawBody.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty,
              let index = document.workspace.comments.firstIndex(where: { $0.id == comment.id }),
              document.workspace.comments[index].body != body else {
            return false
        }
        var updated = document.workspace.comments[index]
        updated.body = body
        replaceComment(at: index, with: updated, actionName: L10n.string("undo.editComment"))
        return true
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
                guard decoration.isSeal,
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
        guard activeSigningTask == nil else {
            editingStatus = .warning(L10n.string("status.sign.finishBeforeMoreChanges"))
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
            showEditMessage(L10n.string("status.readerMode.blockedEditText"), isError: false)
        case .signature:
            showEditMessage(L10n.string("status.readerMode.blockedSignature"), isError: false)
        default:
            showEditMessage(L10n.string("status.readerMode.blockedGeneric"), isError: false)
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

    // MARK: - Discard changes & close

    /// True once the document differs from how it was opened. Drives whether the
    /// "Discard Changes & Close" escape hatch is offered. Reads `structureRevision` so it
    /// re-evaluates after AppKit-driven commits (object move/resize/delete) that don't
    /// otherwise trigger a SwiftUI refresh — the same gap the toolbar Undo button reads.
    var hasUnsavedChanges: Bool {
        _ = structureRevision
        return undoManager?.canUndo == true
    }

    /// Rolls every piece of in-memory document state back to the `initialDocumentState`
    /// captured at open, mirroring `restore(_:)` but WITHOUT registering undo — this
    /// intentionally throws the edit history away rather than making the reset itself
    /// undoable. Safe to call when nothing changed (a no-op restore).
    func revertToInitialState() {
        guard let initial = initialDocumentState else { return }
        document.workspace = initial.workspace
        document.memberPDFData = initial.memberPDFData
        document.sourcePayloads = initial.sourcePayloads
        originalMemberPDFData = initial.originalMemberPDFData
        invalidatePageInspection()
        // Session-only editing caches/selection that must not outlive the reverted content.
        signingIdentitiesByPlacementID = [:]
        objectBaseData = [:]
        objectSelection = nil
        selectedAnnotation = nil
        selectedStampDecorationID = nil
        textAnalysisCache.removeAll()
        objectAnalysisCache.removeAll()
        loadedPDFs = initial.workspace.documents.compactMap { member in
            guard let data = initial.memberPDFData[member.id],
                  let pdf = PDFDocument(data: data) else { return nil }
            return (member, pdf)
        }
        rebuild()
    }

    /// The escape hatch for the "The file couldn't be saved" dead-end: restores the
    /// document to how it was opened (discarding this session's edits), clears the undo
    /// history so SwiftUI no longer marks the window edited, then closes the window. Users
    /// can open a document, try things, and back out cleanly even when the normal
    /// save-on-close path is failing.
    func discardChangesAndClose() {
        revertToInitialState()
        // Wipe undo/redo so the framework stops treating the document as edited; otherwise
        // closing could re-trigger the very save-on-close that was failing.
        undoManager?.removeAllActions()
        // Close on the next runloop turn so this method (usually invoked from a menu/dialog
        // button) fully unwinds first. Use `close()`, NOT `performClose(_:)`: `close()` is
        // unconditional and never routes back through the save-on-close machinery.
        let window = hostingWindow
        DispatchQueue.main.async {
            window?.close()
        }
    }

    /// Undo/redo is a strong, explicit signal the user is backing out of recent actions —
    /// silently auto-applying a copied format (armed via "Copy" before the undo/redo) to
    /// the next unrelated edit the user opens would be more surprising than helpful right
    /// after rolling the document back or forward. Format-painter state armed BEFORE the
    /// undo/redo is no longer meaningfully tied to what the user is looking at afterward.
    /// Also called when the user switches tools away from Edit Text (`AnnotationToolPicker
    /// .select`) or explicitly restores a block's original format — not `private` so those
    /// call sites can reach it. Deliberately NOT called when an editor is merely cancelled/
    /// Escaped: Copy Style is only reachable from inside an editor, so "Copy in A, Cancel A
    /// without committing, then open B to Paste" is the normal, expected way to move a style
    /// between two blocks — disarming on that cancel would wipe the just-copied style before
    /// it ever reaches B.
    func disarmFormatPainter() {
        guard isInlineTextFormatPainterArmed || isFormatPainterPinned else { return }
        isInlineTextFormatPainterArmed = false
        isFormatPainterPinned = false
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
        if let sel = objectSelection, let ref = workspacePageRef(sel.pageRefID),
           result.dataByMemberID[ref.memberDocId] != nil {
            clearObjectSelection()
        }
        for (memberID, data) in result.dataByMemberID {
            document.memberPDFData[memberID] = data
            // The OCR'd bytes are the member's new pristine base. Leaving the pre-OCR
            // base in place meant every later page regeneration (inline edit, revert,
            // reconcile) rebuilt from the pre-OCR scan — silently stripping the freshly
            // added text layer page by page as the user edited.
            invalidatePageInspection(for: memberID)
            originalMemberPDFData[memberID] = data
            // Same rule for the object-editing lane: a member with a frozen object-edit
            // base must re-freeze to the new OCR'd bytes, or the next object edit
            // regenerates from the pre-OCR base and silently strips the text layer OCR
            // just added for that whole member. The OCR'd bytes already reflect every
            // committed op's effect (OCR runs on the live, already-edited document), so the
            // ops themselves must be dropped too — replaying them again onto this new base
            // would apply their effect a second time.
            if objectBaseData[memberID] != nil {
                objectBaseData[memberID] = data
                if let member = document.workspace.documents.first(where: { $0.id == memberID }) {
                    let pageRefIDs = Set(member.pageRefs)
                    document.workspace.objectEditStates.removeAll { pageRefIDs.contains($0.pageRefID) }
                }
            }
        }
        loadedPDFs = document.workspace.documents.compactMap { member in
            guard let data = result.dataByMemberID[member.id] ?? document.memberPDFData[member.id],
                  let pdf = PDFDocument(data: data) else {
                return nil
            }
            return (member, pdf)
        }
        textAnalysisCache.removeAll()
        objectAnalysisCache.removeAll()
        rebuild()
    }

    // MARK: - Document metadata

    /// The member backing the currently-selected page, else the first member.
    ///
    /// Correct for per-member state like attachments: the export collects embedded
    /// files from EVERY member, so each one's attachments reach the file and
    /// following the page selection is what the user means.
    private func activeAttachmentsMemberID() -> UUID? {
        if let selectedPageRefID,
           let ref = document.workspace.pageOrder.first(where: { $0.id == selectedPageRefID }) {
            return ref.memberDocId
        }
        return document.workspace.documents.first?.id
    }

    /// The member whose document properties the exported file will actually carry.
    ///
    /// A merged PDF has exactly ONE `/Info` dictionary, so assembling several members
    /// has to pick whose properties survive, and `concatenateForExport` adopts the
    /// first member's. The Info tab therefore reads and writes THAT member rather than
    /// following the page selection: targeting the selected member instead let a user
    /// edit the title on page 5, watch it stick in the app, and export a file still
    /// carrying member 1's title -- the edit discarded by the merge with no error.
    private func metadataMemberID() -> UUID? {
        document.workspace.documents.first?.id
    }

    /// Identity of the member the Inspector currently targets; its tabs re-seed when
    /// this changes (e.g. the user selects a page belonging to a different document).
    var activeDocumentID: UUID? { activeAttachmentsMemberID() }

    /// The Info-dict metadata of the member backing the currently-selected page,
    /// for seeding the Inspector editor. `nil` when there is no member or its
    /// bytes can't be read (e.g. an encrypted member with no stored password).
    func activeDocumentMetadata() -> PDFDocumentMetadata? {
        guard let memberID = metadataMemberID(),
              let data = document.memberPDFData[memberID] else { return nil }
        return try? PDFMetadataService.read(from: data)
    }

    /// True when the active member also carries an XMP `/Metadata` stream, which
    /// may repeat stale Info values independently of the fields edited here.
    var activeDocumentHasXMPMetadata: Bool {
        guard let memberID = metadataMemberID(),
              let data = document.memberPDFData[memberID] else { return false }
        return QPDFService.hasXMPMetadata(data)
    }

    /// Applies edited Info-dict metadata to the active member, routed through
    /// BOTH the text-layer-preserving qpdf lane (`memberPDFData` + the replay
    /// bases) and the PDFKit `documentAttributes` lane that export re-serializes
    /// -- so the edit survives future edit replays AND reaches the exported file.
    /// This edits only the `/Info` dictionary; the separate XMP `/Metadata`
    /// stream is deliberately left untouched. Stripping XMP is the job of
    /// "Sanitize for sharing" on export, which removes `/Metadata` from the
    /// FINAL exported bytes (this metadata edit runs on a lane that Save/Export
    /// re-serialize past, so an XMP strip here would never reach the file).
    /// Registers a single named, atomic undo step.
    @discardableResult
    func applyMetadataEdit(_ metadata: PDFDocumentMetadata) -> Bool {
        guard canPerformMutatingAction() else { return false }
        // Unlike an attachment edit, this one also writes the PDFKit lane, so the
        // member must be loaded — without a live document there is nowhere to put
        // the `documentAttributes` half and export would silently lose the edit.
        guard let memberID = metadataMemberID(),
              loadedPDFs.contains(where: { $0.0.id == memberID }),
              let currentLive = document.memberPDFData[memberID] else { return false }

        return mutateMemberBytes(
            of: memberID,
            currentLive: currentLive,
            actionNameKey: "undo.editMetadata",
            failureKey: "status.metadata.applyFailed",
            options: MemberMutationOptions(
                nextDocumentAttributes: { [self] base in
                    documentAttributes(basedOn: base, applying: metadata)
                },
                invalidatesAnalysisCaches: true
            )
        ) { data in
            try? PDFMetadataService.write(metadata, to: data)
        }
    }

    private func documentAttributes(
        basedOn base: [AnyHashable: Any]?,
        applying metadata: PDFDocumentMetadata
    ) -> [AnyHashable: Any] {
        var attributes = base ?? [:]
        func set(_ key: PDFDocumentAttribute, _ value: String?) {
            if let value, !value.isEmpty {
                attributes[key] = value
            } else {
                attributes.removeValue(forKey: key)
            }
        }
        set(.titleAttribute, metadata.title)
        set(.authorAttribute, metadata.author)
        set(.subjectAttribute, metadata.subject)
        set(.keywordsAttribute, metadata.keywords)
        return attributes
    }

    // MARK: - Attachments

    /// Every attachment on the currently-targeted member, for the Attachments
    /// inspector tab. `nil` distinguishes "can't manage attachments" (no member,
    /// or an encrypted member qpdf can't open) from `[]` ("readable, none yet") —
    /// the tab disables add/remove and shows a hint on `nil`.
    func activeMemberAttachments() -> [PDFAttachment]? {
        guard let memberID = activeAttachmentsMemberID(),
              let data = document.memberPDFData[memberID] else { return nil }
        return try? AttachmentsService.list(in: data)
    }

    /// Adds the file at `fileURL` as an attachment on the active member, routed
    /// through the preserved byte lane (live + pristine base + object base) with a
    /// single named, atomic undo step — mirroring `applyMetadataEdit`. Attachments
    /// are document-level, so no page re-render is needed; `rebuild()` only bumps
    /// `structureRevision` so the inspector re-seeds its list.
    @discardableResult
    func addAttachment(_ fileURL: URL) -> Bool {
        guard canPerformMutatingAction() else { return false }
        guard let memberID = activeAttachmentsMemberID(),
              let currentLive = document.memberPDFData[memberID] else { return false }
        let fileData = SecurityScopedAccess.withAccess(to: fileURL) { url in
            try? Data(contentsOf: url)
        }
        guard let fileData else {
            showEditMessage(L10n.string("status.attachments.addFailed"), isError: true)
            return false
        }
        let name = fileURL.lastPathComponent
        let mimeType = attachmentMIMEType(for: fileURL)
        return mutateMemberBytes(
            of: memberID,
            currentLive: currentLive,
            actionNameKey: "undo.addAttachment",
            failureKey: "status.attachments.addFailed"
        ) { data in
            try? AttachmentsService.add(fileData, name: name, mimeType: mimeType, to: data)
        }
    }

    /// Removes the attachment whose name-tree key is `name` from the active member,
    /// with a single named, atomic undo step.
    @discardableResult
    func removeAttachment(named name: String) -> Bool {
        guard canPerformMutatingAction() else { return false }
        guard let memberID = activeAttachmentsMemberID(),
              let currentLive = document.memberPDFData[memberID] else { return false }
        return mutateMemberBytes(
            of: memberID,
            currentLive: currentLive,
            actionNameKey: "undo.removeAttachment",
            failureKey: "status.attachments.removeFailed"
        ) { data in
            // The pristine/object bases may not carry this key (they diverge from
            // live over an editing session); qpdf errors on removing a missing key,
            // so no-op those lanes rather than failing the whole edit.
            let present = (try? AttachmentsService.list(in: data))?.contains { $0.name == name } ?? false
            guard present else { return data }
            return try? AttachmentsService.remove(name, from: data)
        }
    }

    /// Writes the decoded bytes of attachment `name` to `url`, tagging the result
    /// with a quarantine attribute — the payload is untrusted content lifted out
    /// of an arbitrary PDF, so it should trip Gatekeeper like any other download.
    func extractAttachment(named name: String, to url: URL) {
        guard let memberID = activeAttachmentsMemberID(),
              let data = document.memberPDFData[memberID],
              let bytes = try? AttachmentsService.extract(name, from: data) else {
            showEditMessage(L10n.string("status.attachments.extractFailed"), isError: true)
            return
        }
        do {
            try bytes.write(to: url)
            var mutableURL = url
            var values = URLResourceValues()
            values.quarantineProperties = [
                kLSQuarantineTypeKey as String: kLSQuarantineTypeOtherDownload as String
            ]
            try? mutableURL.setResourceValues(values)
        } catch {
            showEditMessage(L10n.string("status.attachments.extractFailed"), isError: true)
        }
    }

    private func attachmentMIMEType(for url: URL) -> String? {
        UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
    }

    // MARK: - Member byte mutation

    /// Every lane one member-byte mutation swaps, captured so it can be restored
    /// wholesale by undo. `original` and `objectBase` are nil when the member has
    /// no such lane; `attributes` is meaningful only when the mutation declares
    /// `nextDocumentAttributes`, and nil there legitimately means "this member had
    /// no attributes", which undo must restore faithfully.
    private struct MemberByteSnapshot {
        var live: Data
        var original: Data?
        var objectBase: Data?
        var attributes: [AnyHashable: Any]?
    }

    /// The lanes a mutation touches BEYOND the three byte lanes every mutation
    /// swaps. Both are opt-in because the two callers genuinely differ, and the
    /// difference is load-bearing rather than incidental:
    ///
    /// - `nextDocumentAttributes` — metadata must also land on the live PDFDocument
    ///   because export re-serializes `loadedPDFs`, not the qpdf byte lane. Supply
    ///   a closure mapping the member's current attributes to the edited ones.
    ///   Attachment edits leave the PDFKit lane alone.
    /// - `invalidatesAnalysisCaches` — metadata clears the text/object analysis
    ///   caches, attachments does not. Both edits are document-level and change no
    ///   page content, so the metadata clear looks like over-invalidation; it is
    ///   preserved here rather than quietly dropped, because narrowing it is a
    ///   behaviour change that deserves its own commit and its own test.
    private struct MemberMutationOptions {
        var nextDocumentAttributes: (([AnyHashable: Any]?) -> [AnyHashable: Any])?
        var invalidatesAnalysisCaches: Bool = false
    }

    /// Applies `transform` to the member's live bytes and, when present, its
    /// pristine and object-edit bases, then commits the swap with a single
    /// recursive-inverse undo step.
    ///
    /// The replay bases carry NO baked edits, so they are transformed
    /// independently: re-applying the change to the pristine base keeps a later
    /// edit replay from resurrecting the old state without double-applying the
    /// committed edits the live bytes already bake in.
    ///
    /// Any lane failing aborts the whole edit having mutated nothing — every
    /// transform runs and is validated before the first byte is written.
    @discardableResult
    private func mutateMemberBytes(
        of memberID: UUID,
        currentLive: Data,
        actionNameKey: String,
        failureKey: String,
        options: MemberMutationOptions = MemberMutationOptions(),
        _ transform: (Data) -> Data?
    ) -> Bool {
        func failed() -> Bool {
            showEditMessage(L10n.string(forKey: failureKey), isError: true)
            return false
        }

        guard let newLive = transform(currentLive) else { return failed() }
        var newOriginal: Data? = nil
        if let original = originalMemberPDFData[memberID] {
            guard let transformed = transform(original) else { return failed() }
            newOriginal = transformed
        }
        var newObjectBase: Data? = nil
        if let objectBase = objectBaseData[memberID] {
            guard let transformed = transform(objectBase) else { return failed() }
            newObjectBase = transformed
        }

        let currentAttributes = loadedPDFs.first { $0.0.id == memberID }?.1.documentAttributes
        let previous = MemberByteSnapshot(
            live: currentLive,
            original: originalMemberPDFData[memberID],
            objectBase: objectBaseData[memberID],
            attributes: currentAttributes
        )
        let next = MemberByteSnapshot(
            live: newLive,
            original: newOriginal,
            objectBase: newObjectBase,
            attributes: options.nextDocumentAttributes?(currentAttributes)
        )
        applyMemberByteSnapshot(next, to: memberID, previous: previous, actionNameKey: actionNameKey, options: options)
        return true
    }

    private func applyMemberByteSnapshot(
        _ snapshot: MemberByteSnapshot,
        to memberID: UUID,
        previous: MemberByteSnapshot,
        actionNameKey: String,
        options: MemberMutationOptions
    ) {
        document.memberPDFData[memberID] = snapshot.live
        if let original = snapshot.original {
            originalMemberPDFData[memberID] = original
        }
        if let objectBase = snapshot.objectBase {
            objectBaseData[memberID] = objectBase
        }
        if options.nextDocumentAttributes != nil,
           let loadedIndex = loadedPDFs.firstIndex(where: { $0.0.id == memberID }) {
            loadedPDFs[loadedIndex].1.documentAttributes = snapshot.attributes
        }
        invalidatePageInspection(for: memberID)
        if options.invalidatesAnalysisCaches {
            textAnalysisCache.removeAll()
            objectAnalysisCache.removeAll()
        }
        rebuild()
        markWorkspaceModified()
        // Recursive inverse: each application registers the undo that restores the
        // other state, so undo AND redo both work and each is its own atomic step.
        registerIsolatedUndo {
            undoManager?.registerUndo(withTarget: self) { vm in
                guard vm.canPerformUndoMutation() else { return }
                vm.applyMemberByteSnapshot(
                    previous, to: memberID, previous: snapshot,
                    actionNameKey: actionNameKey, options: options)
            }
            undoManager?.setActionName(L10n.string(forKey: actionNameKey))
        }
    }

    private struct CollectedAttachment {
        let name: String
        let data: Data
        let mimeType: String?
    }

    /// Snapshots every member's attachments into decoded `(name, bytes, mime)`
    /// tuples. Captured at the *start* of an export — before reconcile/replay,
    /// which regenerate member bytes from the page-content lanes that don't carry
    /// document-level embedded files — so the attachments survive to re-injection.
    private func collectMemberAttachments() -> [CollectedAttachment] {
        var collected: [CollectedAttachment] = []
        for member in document.workspace.documents {
            guard let data = document.memberPDFData[member.id],
                  let attachments = try? AttachmentsService.list(in: data), !attachments.isEmpty else { continue }
            for attachment in attachments {
                guard let bytes = try? AttachmentsService.extract(attachment.name, from: data) else { continue }
                collected.append(CollectedAttachment(name: attachment.name, data: bytes, mimeType: attachment.mimeType))
            }
        }
        return collected
    }

    /// Re-grafts collected attachments onto assembled export bytes. `add` itself
    /// disambiguates colliding keys, so attachments with the same name across
    /// merged members land under distinct keys.
    private func reinjectingAttachments(_ collected: [CollectedAttachment], into exportData: Data) -> Data {
        guard !collected.isEmpty else { return exportData }
        var result = exportData
        for item in collected {
            if let updated = try? AttachmentsService.add(item.data, name: item.name, mimeType: item.mimeType, to: result) {
                result = updated
            }
        }
        return result
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
        case .hanko:
            return PageDecoration(kind: .hanko)
        case .image:
            return PageDecoration(kind: .image)
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
        case .stamp, .hanko, .image:
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

    /// Page refs for the sidebar's current selection, used by toolbar-level page actions
    /// (the overflow menu) that don't have a specific right-clicked thumbnail to anchor to.
    var currentSelectionPageRefs: [PageRef] {
        guard let id = selectedPageRefID,
              let ref = document.workspace.pageOrder.first(where: { $0.id == id }) else { return [] }
        return pageRefsForCurrentSelection(including: ref)
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
        draggedMemberID = nil
        draggedPageRefID = ref.id
    }

    /// The member document that owns the page currently being dragged, if any. Used by the
    /// sidebar to gate page-reorder drops to same-document targets (the MVP scope).
    var draggedPageMemberID: UUID? {
        guard let draggedPageRefID else { return nil }
        return document.workspace.pageOrder.first(where: { $0.id == draggedPageRefID })?.memberDocId
    }

    /// Reorders the dragged page relative to `targetRef` within the SAME document.
    /// `insertAbove` mirrors the sidebar's insertion indicator: `true` drops the page just
    /// before the target, `false` just after. Cross-document moves are intentionally refused
    /// here — they force a pristine-base rebase on both members (see `movePage(_:after:)`),
    /// which is the wrong trade-off to trigger from an easy-to-fat-finger drag.
    @discardableResult
    func moveDraggedPage(to targetRef: PageRef, insertAbove: Bool) -> Bool {
        guard canPerformMutatingAction() else { draggedPageRefID = nil; return false }
        guard let draggedPageRefID,
              draggedPageRefID != targetRef.id,
              let sourceRef = document.workspace.pageOrder.first(where: { $0.id == draggedPageRefID }),
              sourceRef.memberDocId == targetRef.memberDocId,
              let memberIndex = document.workspace.documents.firstIndex(where: { $0.id == targetRef.memberDocId }),
              let targetIndex = document.workspace.documents[memberIndex].pageRefs.firstIndex(of: targetRef.id)
        else {
            self.draggedPageRefID = nil
            return false
        }

        // `movePage(_:toIndex:)` takes a pre-removal destination index (SwiftUI `.onMove`
        // convention) and adjusts internally when moving downward, so `targetIndex` inserts
        // before the target and `targetIndex + 1` inserts after.
        let destination = insertAbove ? targetIndex : targetIndex + 1
        guard movePage(sourceRef, toIndex: destination) else {
            self.draggedPageRefID = nil
            return false
        }
        selectedPageRefID = sourceRef.id
        self.draggedPageRefID = nil
        return true
    }

    func beginDraggingDocument(_ member: MemberDocument) {
        guard canPerformMutatingAction() else { return }
        draggedPageRefID = nil
        draggedMemberID = member.id
    }

    /// Reorders the dragged member document relative to `targetID`. `insertAbove` mirrors the
    /// sidebar's insertion indicator. Delegates to the tested `moveDocument(from:to:)` path.
    @discardableResult
    func moveDraggedDocument(to targetID: UUID, insertAbove: Bool) -> Bool {
        guard canPerformMutatingAction() else { draggedMemberID = nil; return false }
        guard let draggedMemberID,
              draggedMemberID != targetID,
              let sourceIndex = loadedPDFs.firstIndex(where: { $0.0.id == draggedMemberID }),
              let targetIndex = loadedPDFs.firstIndex(where: { $0.0.id == targetID })
        else {
            self.draggedMemberID = nil
            return false
        }

        // `moveDocument(from:to:)` uses `Array.move(fromOffsets:toOffset:)`, whose destination
        // is a pre-removal index: `targetIndex` inserts before the target, `targetIndex + 1`
        // after.
        let destination = insertAbove ? targetIndex : targetIndex + 1
        moveDocument(from: IndexSet(integer: sourceIndex), to: destination)
        self.draggedMemberID = nil
        return true
    }

    // MARK: - Annotations

    func editableTextBlock(at pagePoint: CGPoint, on page: PDFPage, in pdfDocument: PDFDocument?) -> (pageRef: PageRef, block: EditableTextBlock, sourceFormat: PDFTextEditFormat, matchFormat: PDFTextEditFormat)? {
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
                pageRotation: page.rotation,
                baseline: syntheticBounds.minY,
                confidence: .high
            )
            let matchFormat = inferredNearbyMatchFormat(around: syntheticBlock, in: analysis, fallback: sourceFormat)
            return (ref, syntheticBlock, sourceFormat, matchFormat)
        }
        let block = textAnalysisEngine.hitTest(pagePoint, in: analysis) ??
            insertionTextBlock(at: pagePoint, pageRefID: ref.id, page: page, nearbyBlocks: analysis.blocks)
        let ownFormat = PDFTextEditFormat(block: block)
        let matchFormat = inferredNearbyMatchFormat(around: block, in: analysis, fallback: ownFormat)
        return (ref, block, ownFormat, matchFormat)
    }

    /// Infers the style Match Format should adopt: the dominant nearby BODY paragraph
    /// style around `target`, deliberately NOT the target's own style (that is what Reset
    /// restores). Ranking mirrors the plan's precedence — same column and vertically
    /// adjacent wins first, then the dominant body-text cluster on the page — while
    /// excluding the target itself, headings (much larger than the local body size), and
    /// tiny footer/caption text. Falls back to `fallback` when nothing suitable is nearby.
    private func inferredNearbyMatchFormat(
        around target: EditableTextBlock,
        in analysis: PDFTextPageAnalysis,
        fallback: PDFTextEditFormat
    ) -> PDFTextEditFormat {
        let targetBounds = target.bounds.standardized
        let graphics = analysis.graphics
        // When the edit target is NOT itself inside a ruled grid, table cells must not win
        // as the body-style source (the user is editing prose, not a cell).
        let targetInGrid = graphics.isInsideRuledGrid(targetBounds)
        let candidates = analysis.blocks.filter { block in
            guard block.id != target.id,
                  block.editability != .insertion,
                  !block.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  block.fontSize > 0 else { return false }
            // Exclude clearly-invisible OCR/low-visibility layers — matching them would
            // hand the edit an invisible style.
            guard block.editability != .hiddenOCRLayer, block.editability != .lowVisibility else { return false }
            // Exclude a standalone list/bullet marker (its "style" is a glyph, not body text).
            let trimmed = block.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.range(of: #"^([•\-–—*·▪◦]|\(?[0-9A-Za-z]{1,2}\)|[0-9A-Za-z]{1,2}[.)])$"#, options: .regularExpression) != nil {
                return false
            }
            // Exclude table cells when editing outside any grid.
            if !targetInGrid, graphics.isInsideRuledGrid(block.bounds.standardized) { return false }
            return true
        }
        guard !candidates.isEmpty else { return fallback }

        // The page's dominant body size: the median size of the mass of text, which
        // headings sit well above and footnotes/captions below.
        let sizes = candidates.map(\.fontSize).sorted()
        let bodySize = sizes[sizes.count / 2]
        // Body-like = within ~25% of the dominant size (excludes headings and micro-text).
        let bodyLike = candidates.filter { abs($0.fontSize - bodySize) <= bodySize * 0.25 }
        let pool = bodyLike.isEmpty ? candidates : bodyLike

        func sameColumn(_ block: EditableTextBlock) -> Bool {
            guard let column = block.columnBounds?.standardized else { return false }
            return targetBounds.midX >= column.minX - 4 && targetBounds.midX <= column.maxX + 4
        }
        let sameColumnPool = pool.filter(sameColumn)
        var rankingPool = sameColumnPool.isEmpty ? pool : sameColumnPool

        // Restrict to the DOMINANT local body style cluster before ranking by proximity, so
        // a lone italic caption / off-style neighbor sitting a little closer to the click
        // can't win over the surrounding body text. A style signature is (family, bold,
        // italic); the most common signature is the body, and proximity only tie-breaks
        // WITHIN that cluster. Skipped when there's no clear majority (all singletons).
        struct StyleKey: Hashable { let family: String; let bold: Bool; let italic: Bool }
        func styleKey(_ block: EditableTextBlock) -> StyleKey {
            let lower = block.fontName.lowercased()
            return StyleKey(
                family: Self.fontFamilyRoot(block.fontName),
                bold: lower.contains("bold") || lower.contains("black") || lower.contains("heavy") || lower.contains("semibold"),
                italic: lower.contains("italic") || lower.contains("oblique")
            )
        }
        let counts = Dictionary(grouping: rankingPool, by: styleKey).mapValues(\.count)
        if let (dominantKey, dominantCount) = counts.max(by: { $0.value < $1.value }), dominantCount >= 2 {
            let dominantCluster = rankingPool.filter { styleKey($0) == dominantKey }
            if !dominantCluster.isEmpty { rankingPool = dominantCluster }
        }

        let ranked = rankingPool.min { lhs, rhs in
            let lDist = abs(lhs.bounds.standardized.midY - targetBounds.midY)
            let rDist = abs(rhs.bounds.standardized.midY - targetBounds.midY)
            return lDist < rDist
        }
        guard let best = ranked else { return fallback }
        return PDFTextEditFormat(block: best)
    }

    /// The family root of a PDF font name (strips a subset tag and any style suffix), used
    /// to cluster style signatures for Match inference. "ABCDEF+Helvetica-Bold" → "helvetica".
    private static func fontFamilyRoot(_ name: String) -> String {
        var base = name
        if let plus = base.firstIndex(of: "+"), base.distance(from: base.startIndex, to: plus) == 6 {
            base = String(base[base.index(after: plus)...])
        }
        if let dash = base.firstIndex(of: "-") { base = String(base[..<dash]) }
        return base.lowercased()
    }

    /// The font name to seed a fresh insertion with. A known unembedded standard font
    /// (Arial/Times New Roman/Courier New/Calibri/Cambria) is swapped for its bundled
    /// metric-compatible face — preserving bold/italic so the new text matches nearby
    /// styling and renders identically on export instead of depending on whether the
    /// substituted Windows font happens to be installed. Anything else is kept verbatim.
    private static func substitutedInsertionFontName(for fontName: String, rawFontName: String? = nil) -> String {
        // Substitute on the nearby block's RAW `/BaseFont` name when available (so inserting
        // next to Calibri/Cambria seeds Carlito/Caladea), not the normalized `fontName`.
        guard let family = FontSubstitution.substituteFamily(for: rawFontName ?? fontName) else { return fontName }
        let source = NSFont(name: fontName, size: 12) ?? .systemFont(ofSize: 12)
        let traits = NSFontManager.shared.traits(of: source).intersection([.boldFontMask, .italicFontMask])
        let styled = NSFontManager.shared.font(withFamily: family, traits: traits, weight: 5, size: 12)
        return styled?.fontName ?? family
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
        // No block anywhere on the page AND the page itself looks like a scanned/flattened
        // image (no text layer, but visible ink) — the click can't be bound to any known text
        // region, so tell the user honestly instead of silently opening what looks like a
        // normal "detected this line" editor. A page with a real (if sparse) text layer, or
        // any genuinely blank spot on an otherwise-editable page, stays a plain `.insertion`.
        let isOnFlattenedPage = nearbyBlocks.isEmpty && PDFOCRService.isLikelyScannedPage(page)
        return EditableTextBlock(
            pageRefID: pageRefID,
            text: "",
            bounds: bounds,
            lines: [],
            columnBounds: pageBounds.insetBy(dx: 12, dy: 12),
            fontName: Self.substitutedInsertionFontName(for: nearbyStyle?.fontName ?? "Helvetica", rawFontName: nearbyStyle?.rawFontName),
            fontSize: nearbyStyle?.fontSize ?? 14,
            textColor: nearbyStyle?.textColor ?? .documentText,
            alignment: nearbyStyle?.alignment,
            rotation: 0,
            pageRotation: page.rotation,
            baseline: bounds.minY,
            confidence: .medium,
            editability: isOnFlattenedPage ? .overlayOnly : .insertion,
            textSource: .none
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
            showEditMessage(L10n.string("error.pageEdit.cannotAccessOriginal"), isError: true)
            return false
        }

        let previousSnapshot = captureInlineTextEditSnapshot()
        var operation = PDFTextEditOperation(
            pageRefID: pageRef.id,
            sourceBlockID: sourceBlock.id,
            sourceBounds: sourceBlock.bounds,
            sourceLineBounds: sourceBlock.lines.map(\.bounds),
            sourceUnderlineBounds: sourceBlock.underlineBounds,
            sourcePreserveRuleBounds: sourceBlock.protectedRuleBounds,
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
            operation.sourceUnderlineBounds = existingOp.sourceUnderlineBounds
            operation.sourcePreserveRuleBounds = existingOp.sourcePreserveRuleBounds
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
        guard regenerateEditedPage(pageRef: pageRef) else {
            document.workspace.pageEditStates = previousSnapshot.editStates
            showEditMessage(L10n.string("error.pageEdit.regenerateFailed"), isError: true)
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

    /// Rebuilds the containing member through the shared two-lane replay module. The
    /// explicit page id keeps revert-to-empty operations in the replay even after their
    /// PageEditState has been removed.
    private func regenerateEditedPage(pageRef: PageRef) -> Bool {
        replayCommittedEdits(for: pageRef.memberDocId, forcingPageRefIDs: [pageRef.id])
    }

    /// The bake stamp currently on a page, or nil if the page has never been stamped (legacy
    /// bytes, or a third-party rewrite that dropped the annotation).
    private static func bakeStamp(on page: PDFPage) -> String? {
        BakeStamp.value(on: page)
    }

    // MARK: - Object editing (docs/OBJECT_EDITING_PLAN.md §5/§8)

    /// The PageRef in the workspace with `id`, or nil.
    func workspacePageRef(_ id: UUID) -> PageRef? {
        document.workspace.pageOrder.first { $0.id == id }
    }

    /// The detected object map for a page, cached per PageRef. The full PDFium inspection is
    /// shared with text analysis against canonical bytes, then committed absolute object ops are
    /// projected over that snapshot so selection reflects the live state without a second scan.
    func objectMap(for pageRef: PageRef) -> PageObjectMap {
        if let cached = objectAnalysisCache[pageRef.id] { return cached }
        guard let lookup = memberPDF(for: pageRef),
              let localIdx = localIndex(ref: pageRef, memberIndex: lookup.documentIndex) else {
            return PageObjectMap(pageRefID: pageRef.id, objects: [])
        }
        guard let data = originalMemberPDFData[pageRef.memberDocId]
                ?? objectBaseData[pageRef.memberDocId]
                ?? document.memberPDFData[pageRef.memberDocId] else {
            return PageObjectMap(pageRefID: pageRef.id, objects: [])
        }
        let canonicalIndex = pageRef.sourcePageIndex >= 0 ? pageRef.sourcePageIndex : localIdx
        let inspection = pageInspectionCache.result(
            pdfData: data,
            pageIndex: canonicalIndex,
            pageRefID: pageRef.id,
            revision: pageInspectionRevision(for: pageRef.memberDocId)
        )
        let canonicalMap = inspection.objectMap
        let operations = document.workspace.objectEditStates
            .filter { $0.pageRefID == pageRef.id }
            .flatMap(\.operations)
        let projectedMap = PDFObjectDetectionEngine.projecting(canonicalMap, operations: operations)
        let liveRotation = CGFloat(lookup.pdf.page(at: localIdx)?.rotation ?? 0)
        let rotationAwareMap = PDFObjectDetectionEngine.applyingPageRotation(
            liveRotation,
            to: projectedMap
        )
        let map = PDFObjectDetectionEngine.applyingEditingPermission(
            canPerformMutatingAction(),
            to: rotationAwareMap
        )
        // Global pressure refusal is retryable after another member revision is removed. Do not
        // let the downstream cache turn that temporary fail-closed result into a permanent one.
        if !inspection.wasRefused {
            objectAnalysisCache[pageRef.id] = map
        }
        return map
    }

    /// True when the document permits object editing at all (permission-restricted / signed docs
    /// disallow it, mirroring the text-edit gate).
    var objectEditingAllowed: Bool { canPerformMutatingAction() }

    var hasObjectEdits: Bool { document.workspace.objectEditStates.contains { !$0.operations.isEmpty } }

    /// Commit one or more object operations atomically: snapshot → upsert → regenerate affected
    /// members via the PDFium structural engine → live update → single undo step. Rolls back
    /// (including member bytes) on any regeneration failure. Returns false if blocked or failed.
    /// True when any inline-text edit exists on a page belonging to `memberID`.
    func memberHasTextEdits(_ memberID: UUID) -> Bool {
        document.workspace.pageEditStates.contains { state in
            !state.operations.isEmpty && workspacePageRef(state.pageRefID)?.memberDocId == memberID
        }
    }

    /// True when any object edit exists on a page belonging to `memberID`.
    func memberHasObjectEdits(_ memberID: UUID) -> Bool {
        document.workspace.objectEditStates.contains { state in
            !state.operations.isEmpty && workspacePageRef(state.pageRefID)?.memberDocId == memberID
        }
    }

    @discardableResult
    func applyObjectEdit(_ operations: [ObjectEditOperation], undoActionNameKey: String = "undo.editObject") -> Bool {
        guard canPerformMutatingAction(), !operations.isEmpty else { return false }

        let affectedMembers = Set(operations.compactMap { workspacePageRef($0.pageRefID)?.memberDocId })
        guard !affectedMembers.isEmpty else { return false }

        let snapshot = captureInlineTextEditSnapshot()

        // Freeze the canonical pre-edit base on the first object edit. Persisted object ops are
        // retained and replayed from this base; dropping them here used to make reopen + re-edit
        // silently forget earlier operations.
        for memberID in affectedMembers where objectBaseData[memberID] == nil {
            objectBaseData[memberID] = originalMemberPDFData[memberID] ?? document.memberPDFData[memberID]
        }

        operations.forEach { upsertObjectEditOperation($0) }

        var succeeded = true
        for memberID in affectedMembers where !regenerateObjectEditedMember(memberID) { succeeded = false; break }
        guard succeeded else {
            // Silent byte-exact rollback (fixes the text path's partial-rollback gap).
            document.workspace.pageEditStates = snapshot.editStates
            document.workspace.objectEditStates = snapshot.objectEditStates
            objectBaseData = snapshot.objectBaseData
            objectSelection = snapshot.objectSelection
            document.memberPDFData = snapshot.pdfData
            loadedPDFs = document.workspace.documents.compactMap { m in
                snapshot.pdfData[m.id].flatMap { PDFDocument(data: $0) }.map { (m, $0) }
            }
            objectAnalysisCache.removeAll(); textAnalysisCache.removeAll()
            rebuild()
            showEditWarning(.objectCommitFailed)
            return false
        }

        rebuild()
        markWorkspaceModified()
        // Set the action name INSIDE the isolated group. Doing it after the group closed (as the
        // move/resize/delete callers used to) left NSUndoManager to open a fresh implicit group to
        // hold the name — a spurious, empty top group that swallowed the first Undo.
        let undoActionName = L10n.string(forKey: undoActionNameKey)
        registerIsolatedUndo {
            undoManager?.registerUndo(withTarget: self) { vm in
                guard vm.canPerformUndoMutation() else { return }
                vm.restoreInlineTextEditSnapshot(snapshot, actionName: undoActionName)
            }
            undoManager?.setActionName(undoActionName)
        }
        return true
    }

    /// Compatibility adapter for object-edit callers; the shared replay engine owns both lanes.
    private func regenerateObjectEditedMember(_ memberID: UUID) -> Bool {
        replayCommittedEdits(for: memberID)
    }

    /// Adapts workspace identities and state into the replay engine's compact per-member input.
    /// This is the only path that materializes committed text/object operations into live bytes.
    private func replayCommittedEdits(
        for memberID: UUID,
        forcingPageRefIDs: Set<UUID> = []
    ) -> Bool {
        guard let memberIndex = document.workspace.documents.firstIndex(where: { $0.id == memberID }),
              let baseData = objectBaseData[memberID]
                ?? originalMemberPDFData[memberID]
                ?? document.memberPDFData[memberID] else { return false }

        let textByPage = document.workspace.pageEditStates.reduce(
            into: [UUID: [PDFTextEditOperation]]()
        ) { result, state in
            result[state.pageRefID, default: []].append(contentsOf: state.operations)
        }
        let objectsByPage = document.workspace.objectEditStates.reduce(
            into: [UUID: [ObjectEditOperation]]()
        ) { result, state in
            result[state.pageRefID, default: []].append(contentsOf: state.operations)
        }
        let editedRefIDs = Set(textByPage.keys)
            .union(objectsByPage.keys)
            .union(forcingPageRefIDs)
        let pages = editedRefIDs.compactMap { refID -> WorkspaceEditReplayEngine.PageReplay? in
            guard let ref = workspacePageRef(refID), ref.memberDocId == memberID,
                  let pageIndex = localIndex(ref: ref, memberIndex: memberIndex) else { return nil }
            return WorkspaceEditReplayEngine.PageReplay(
                pageIndex: pageIndex,
                textOperations: textByPage[refID] ?? [],
                objectOperations: objectsByPage[refID] ?? []
            )
        }
        let currentData = loadedPDFs.first(where: { $0.0.id == memberID })
            .flatMap { PDFSerializer.data(from: $0.1) }
            ?? document.memberPDFData[memberID]
        guard let result = WorkspaceEditReplayEngine.replay(
            baseData: baseData,
            currentData: currentData,
            pages: pages
        ) else { return false }
        guard result.unresolvedObjectOperationIDs.isEmpty else {
            NSLog(
                "[Orifold] Warning: refusing partial member replay because %ld object operation(s) could not be rebound.",
                result.unresolvedObjectOperationIDs.count
            )
            return false
        }
        guard let freshPDF = PDFDocument(data: result.data),
              let loadedIndex = loadedPDFs.firstIndex(where: { $0.0.id == memberID }) else { return false }

        document.memberPDFData[memberID] = result.data
        loadedPDFs[loadedIndex] = (loadedPDFs[loadedIndex].0, freshPDF)
        objectAnalysisCache.removeAll()
        textAnalysisCache.removeAll()
        return true
    }

    /// Upsert an op into `objectEditStates`, keyed by (pageRefID, sourceObjectKey). A delete
    /// supersedes and removes any transform/style/reorder for the same object; a transform/style
    /// coalesces with an existing one so a drag-in-progress collapses to a single op.
    private func upsertObjectEditOperation(_ op: ObjectEditOperation) {
        let stateIndex: Int
        if let existing = document.workspace.objectEditStates.firstIndex(where: { $0.pageRefID == op.pageRefID }) {
            stateIndex = existing
        } else {
            document.workspace.objectEditStates.append(PageObjectEditState(pageRefID: op.pageRefID))
            stateIndex = document.workspace.objectEditStates.count - 1
        }

        if op.type == .objectDelete {
            // Delete wins: drop all non-delete ops for this object, then record the delete.
            document.workspace.objectEditStates[stateIndex].operations.removeAll {
                $0.sourceObjectKey == op.sourceObjectKey && $0.type != .objectDelete
            }
        } else if document.workspace.objectEditStates[stateIndex].operations.contains(where: {
            $0.sourceObjectKey == op.sourceObjectKey && $0.type == .objectDelete
        }) {
            // A delete for this object is already recorded — the object is gone; ignore further
            // transforms/styles for it (prevents a stranded non-delete op reaching the engine).
            return
        }

        if let opIndex = document.workspace.objectEditStates[stateIndex].operations.firstIndex(where: {
            $0.sourceObjectKey == op.sourceObjectKey && $0.type == op.type
        }) {
            var merged = document.workspace.objectEditStates[stateIndex].operations[opIndex]
            merged.newTransform = op.newTransform
            merged.newBoundsPdf = op.newBoundsPdf
            if op.newStylePayload != nil { merged.newStylePayload = op.newStylePayload }
            merged.newZIndex = op.newZIndex
            if op.replacementImageData != nil { merged.replacementImageData = op.replacementImageData }
            merged.updatedAt = Date()
            document.workspace.objectEditStates[stateIndex].operations[opIndex] = merged
        } else {
            document.workspace.objectEditStates[stateIndex].operations.append(op)
        }
    }

    // MARK: - Object selection (canvas UI, docs/OBJECT_EDITING_PLAN.md §5)

    struct ObjectSelectionState: Equatable {
        var pageRefID: UUID
        var object: DetectedObject
        var bounds: CGRect { object.boundsPdf }
    }

    /// The currently-selected content object (mutually exclusive with annotation/stamp lanes).
    var objectSelection: ObjectSelectionState?

    /// Hit-test a page-space point against the page's detected objects. Returns the best
    /// selectable object (frontmost, smallest, high/medium confidence, not background/read-only),
    /// or nil. `scaleFactor` is the PDFView zoom, so slop and min-target feel constant on screen.
    func objectHit(at pagePoint: CGPoint, on pageRef: PageRef, scaleFactor: CGFloat) -> DetectedObject? {
        let map = objectMap(for: pageRef)
        let scale = max(scaleFactor, 0.01)
        let slop: CGFloat = 6 / scale
        let minTarget: CGFloat = 12 / scale

        struct Hit { let object: DetectedObject; let area: CGFloat }
        var hits: [Hit] = []
        for object in map.objects {
            guard object.confidence != .low, !object.isBackgroundLike,
                  !object.editability.capabilities.isReadOnly else { continue }
            var rect = object.boundsPdf.standardized
            if rect.width < minTarget { rect = rect.insetBy(dx: -(minTarget - rect.width) / 2, dy: 0) }
            if rect.height < minTarget { rect = rect.insetBy(dx: 0, dy: -(minTarget - rect.height) / 2) }
            if rect.insetBy(dx: -slop, dy: -slop).contains(pagePoint) {
                hits.append(Hit(object: object, area: object.boundsPdf.width * object.boundsPdf.height))
            }
        }
        // Frontmost first (higher zOrder), then smaller area, then higher confidence.
        return hits.sorted { a, b in
            if a.object.zOrder != b.object.zOrder { return a.object.zOrder > b.object.zOrder }
            if a.area != b.area { return a.area < b.area }
            return a.object.confidence.rank > b.object.confidence.rank
        }.first?.object
    }

    func selectObject(_ object: DetectedObject, on pageRef: PageRef) {
        objectSelection = ObjectSelectionState(pageRefID: pageRef.id, object: object)
        selectedAnnotation = nil
        selectedStampDecorationID = nil
    }

    func clearObjectSelection() {
        guard objectSelection != nil else { return }
        objectSelection = nil
    }

    /// The localized "%@ · %@" tooltip for the current selection (type · editability).
    func objectSelectionTooltip() -> String? {
        guard let object = objectSelection?.object else { return nil }
        let type: String
        switch object.objectType {
        case .imageXObject, .flattenedRaster: type = L10n.string("object.type.image")
        case .line: type = L10n.string("object.type.line")
        case .formWidget: type = L10n.string("object.type.formField")
        case .formXObject, .tableGrid: type = L10n.string("object.type.group")
        case .shading: type = L10n.string("object.type.shading")
        default: type = L10n.string("object.type.vectorShape")
        }
        let state = object.editability.capabilities.isReadOnly
            ? L10n.string("object.editability.visualOnly")
            : L10n.string("object.editability.editable")
        return L10n.format("object.tooltip.format", type, state)
    }

    /// Commit a move/resize from the overlay's old→new page-space bounds by composing the
    /// old-rect→new-rect affine onto the object's matrix. Returns the applied bounds.
    @discardableResult
    func commitObjectBoundsChange(from oldBoundsPdf: CGRect, to proposedBoundsPdf: CGRect) -> CGRect {
        guard let sel = objectSelection, sel.object.editability.capabilities.canMove,
              sel.object.pageRotation == 0,   // rotated-page editing is punted in v1
              oldBoundsPdf.width > 0.5, oldBoundsPdf.height > 0.5,
              proposedBoundsPdf.width > 1, proposedBoundsPdf.height > 1 else { return oldBoundsPdf }
        let object = sel.object
        // `oldBoundsPdf`/`newBoundsPdf` are AABBs (see boundsPdf's doc comment) — scaling from them
        // is only correct when the object's own transform has no rotation/skew, i.e. its AABB equals
        // its local rect. For a rotated/skewed object the AABB is larger than the local rect, so a
        // naive AABB-fit scale composed onto the existing (rotated) matrix shears the object. Punt
        // resize the same way rotated pages are punted; translate is always safe (AABB delta ==
        // content delta for any affine transform).
        let m = object.transform.cgAffineTransform
        let isAxisAligned = abs(m.b) < 0.0001 && abs(m.c) < 0.0001
        let canResize = object.editability.capabilities.canResize && isAxisAligned
        // If resize isn't permitted, keep the original size and only translate.
        let newBounds = canResize ? proposedBoundsPdf
            : CGRect(origin: proposedBoundsPdf.origin, size: oldBoundsPdf.size)

        let sx = newBounds.width / oldBoundsPdf.width
        let sy = newBounds.height / oldBoundsPdf.height
        let t = CGAffineTransform(a: sx, b: 0, c: 0, d: sy,
                                  tx: newBounds.minX - oldBoundsPdf.minX * sx,
                                  ty: newBounds.minY - oldBoundsPdf.minY * sy)
        let newMatrix = PDFTextTransform(object.transform.cgAffineTransform.concatenating(t))
        let ref = workspacePageRef(sel.pageRefID)
        let op = ObjectEditOperation(
            type: .objectTransform, documentID: ref?.memberDocId ?? UUID(), pageRefID: sel.pageRefID,
            sourceObjectKey: object.stableKey, objectType: object.objectType, editability: object.editability,
            originalBoundsPdf: object.boundsPdf, newBoundsPdf: newBounds,
            originalTransform: object.transform, newTransform: newMatrix, pageRotation: Int(object.pageRotation),
            originalZIndex: object.zOrder, newZIndex: object.zOrder, replacementStrategy: .pdfiumStructural)

        let actionKey = (canResize && sx != 1) ? "undo.resizeObject" : "undo.moveObject"
        guard applyObjectEdit([op], undoActionNameKey: actionKey) else { return oldBoundsPdf }
        // Keep the selection in sync so a subsequent drag composes from the new state.
        var updated = object
        updated.boundsPdf = newBounds
        updated.transform = newMatrix
        objectSelection = ObjectSelectionState(pageRefID: sel.pageRefID, object: updated)
        return newBounds
    }

    /// Structurally delete the selected object. Returns true on success.
    @discardableResult
    func deleteSelectedObject() -> Bool {
        guard let sel = objectSelection, sel.object.editability.capabilities.canDeleteStructurally else { return false }
        let object = sel.object
        let ref = workspacePageRef(sel.pageRefID)
        let op = ObjectEditOperation(
            type: .objectDelete, documentID: ref?.memberDocId ?? UUID(), pageRefID: sel.pageRefID,
            sourceObjectKey: object.stableKey, objectType: object.objectType, editability: object.editability,
            originalBoundsPdf: object.boundsPdf, newBoundsPdf: object.boundsPdf,
            originalTransform: object.transform, newTransform: object.transform, pageRotation: Int(object.pageRotation),
            originalZIndex: object.zOrder, newZIndex: object.zOrder, replacementStrategy: .pdfiumStructural)
        guard applyObjectEdit([op], undoActionNameKey: "undo.deleteObject") else { return false }
        objectSelection = nil
        return true
    }

    /// A target z-index deliberately above any real page-object count. The edit engine clamps
    /// `newZIndex` to `poe_CountObjects(page)`, so passing this reliably lands the object at the
    /// very front (topmost) without the VM needing PDFium's exact raw object count.
    private static let frontZIndexSentinel = 1_000_000

    /// True when the current selection is a content object whose z-order can be changed.
    /// Rotated-page object editing is punted in v1, mirroring move/resize/delete.
    var canLayerSelectedObject: Bool {
        guard let sel = objectSelection else { return false }
        return sel.object.editability.capabilities.canLayer && sel.object.pageRotation == 0
    }

    /// Bring the selected object to the front of the page's draw order (drawn last, on top).
    @discardableResult
    func bringSelectedObjectToFront() -> Bool { reorderSelectedObject(toFront: true) }

    /// Send the selected object to the back of the page's draw order (drawn first, behind).
    @discardableResult
    func sendSelectedObjectToBack() -> Bool { reorderSelectedObject(toFront: false) }

    /// Realizes a z-order change via an `.objectReorder` op (engine: RemoveObject + InsertObjectAtIndex).
    /// No-ops when the object is already at the requested absolute extreme, so a repeated click doesn't
    /// queue a redundant regenerate. Afterward the selection keeps the same object with its `zOrder`
    /// updated in place to the new absolute index, so a subsequent reorder's guard stays correct.
    @discardableResult
    private func reorderSelectedObject(toFront: Bool) -> Bool {
        guard let sel = objectSelection, sel.object.editability.capabilities.canLayer,
              sel.object.pageRotation == 0, let ref = workspacePageRef(sel.pageRefID) else { return false }
        let object = sel.object
        // The engine realizes "front" as the ABSOLUTE top draw index (it clamps `newZIndex` to
        // `poe_CountObjects`, which counts text objects too) and "back" as absolute 0. The no-op
        // guard must use that same absolute space — `rawObjectCount - 1` and `0` — not the
        // detected subset's extremes (which exclude the text lane). Using the detected extremes
        // made bring/send silently no-op for the common case of one image sitting under a text
        // layer (there `min == max == the image's own index`).
        let rawObjectCount = objectMap(for: ref).rawObjectCount
        let absoluteTop = max(0, rawObjectCount - 1)
        if toFront, object.zOrder >= absoluteTop { return false }
        if !toFront, object.zOrder <= 0 { return false }

        let targetZ = toFront ? Self.frontZIndexSentinel : 0
        let op = ObjectEditOperation(
            type: .objectReorder, documentID: ref.memberDocId, pageRefID: sel.pageRefID,
            sourceObjectKey: object.stableKey, objectType: object.objectType, editability: object.editability,
            originalBoundsPdf: object.boundsPdf, newBoundsPdf: object.boundsPdf,
            originalTransform: object.transform, newTransform: object.transform, pageRotation: Int(object.pageRotation),
            originalZIndex: object.zOrder, newZIndex: targetZ, replacementStrategy: .pdfiumStructural)
        let actionKey = toFront ? "undo.bringObjectToFront" : "undo.sendObjectToBack"
        guard applyObjectEdit([op], undoActionNameKey: actionKey) else { return false }
        // Keep the SAME selected object (bounds/transform/digest are unchanged by a reorder) and
        // just set its new absolute draw index — the engine landed it at the top (`absoluteTop`)
        // or the bottom (0). This mirrors the move lane's "update the selection in place" and
        // avoids a digest-only re-detect, which for identical twin objects (same structuralDigest,
        // different positions) could bind the selection to the wrong twin.
        var updated = object
        updated.zOrder = toFront ? absoluteTop : 0
        objectSelection = ObjectSelectionState(pageRefID: sel.pageRefID, object: updated)
        return true
    }

    // MARK: - Committed edit ↔ page byte reconciliation

    /// Canonical pre-edit bytes for every member with committed text or object operations.
    /// Saving both lanes against the same base makes replay deterministic after reopen.
    private func pristineDataForMembersWithCommittedEdits() -> [UUID: Data] {
        var result: [UUID: Data] = [:]
        let editedPageRefIDs = document.workspace.pageEditStates
            .filter { !$0.operations.isEmpty }
            .map(\.pageRefID)
            + document.workspace.objectEditStates
            .filter { !$0.operations.isEmpty }
            .map(\.pageRefID)
        for pageRefID in editedPageRefIDs {
            guard let ref = document.workspace.pageOrder.first(where: { $0.id == pageRefID }),
                  result[ref.memberDocId] == nil,
                  let pristine = originalMemberPDFData[ref.memberDocId] else { continue }
            result[ref.memberDocId] = pristine
        }
        return result
    }

    /// Adopts a member's CURRENT live bytes as its new pristine base and renormalizes its
    /// refs' `sourcePageIndex` to the live layout. Used when a structural operation makes
    /// the old pristine mapping unrepresentable (cross-member page moves). Any baked edit
    /// in the member becomes part of the pristine background from this point on; object ops
    /// are therefore retired so a later replay cannot apply their transforms twice.
    private func rebasePristineToLiveBytes(memberID: UUID) {
        guard let memberIndex = document.workspace.documents.firstIndex(where: { $0.id == memberID }),
              let loaded = loadedPDFs.first(where: { $0.0.id == memberID }) else { return }
        let liveBytes = PDFSerializer.data(from: loaded.1) ?? document.memberPDFData[memberID]
        guard let liveBytes else { return }
        invalidatePageInspection(for: memberID)
        originalMemberPDFData[memberID] = liveBytes
        if objectBaseData[memberID] != nil {
            objectBaseData[memberID] = liveBytes
        }
        let pageRefIDs = Set(document.workspace.documents[memberIndex].pageRefs)
        document.workspace.objectEditStates.removeAll { pageRefIDs.contains($0.pageRefID) }
        for (localIdx, refID) in document.workspace.documents[memberIndex].pageRefs.enumerated() {
            if let orderIdx = document.workspace.pageOrder.firstIndex(where: { $0.id == refID }),
               document.workspace.pageOrder[orderIdx].sourcePageIndex != localIdx {
                document.workspace.pageOrder[orderIdx].sourcePageIndex = localIdx
            }
        }
        for refID in document.workspace.documents[memberIndex].pageRefs {
            textAnalysisCache.removeValue(forKey: refID)
            objectAnalysisCache.removeValue(forKey: refID)
        }
    }

    /// Realigns a member's canonical replay bytes after a same-member delete, duplicate, or
    /// reorder. The new base is assembled from the OLD pristine pages in the member's NEW ref
    /// order, so committed text/object operations remain re-editable instead of becoming baked
    /// background. Page refs are then normalized to the new base's local indexes.
    private func realignCanonicalReplayBaseAfterStructuralChange(memberID: UUID) {
        guard let memberIndex = document.workspace.documents.firstIndex(where: { $0.id == memberID }),
              let canonicalData = originalMemberPDFData[memberID]
                ?? objectBaseData[memberID]
                ?? document.memberPDFData[memberID],
              let canonicalPDF = PDFDocument(data: canonicalData) else { return }

        let member = document.workspace.documents[memberIndex]
        let realigned = PDFDocument()
        for refID in member.pageRefs {
            guard let ref = workspacePageRef(refID),
                  ref.sourcePageIndex >= 0,
                  let page = canonicalPDF.page(at: ref.sourcePageIndex),
                  let copy = page.copy() as? PDFPage else { return }
            realigned.insert(copy, at: realigned.pageCount)
        }
        guard let realignedData = PDFSerializer.data(from: realigned) else { return }

        invalidatePageInspection(for: memberID)
        originalMemberPDFData[memberID] = realignedData
        if objectBaseData[memberID] != nil {
            objectBaseData[memberID] = realignedData
        }
        for (localIndex, refID) in member.pageRefs.enumerated() {
            if let orderIndex = document.workspace.pageOrder.firstIndex(where: { $0.id == refID }) {
                document.workspace.pageOrder[orderIndex].sourcePageIndex = localIndex
            }
            textAnalysisCache.removeValue(forKey: refID)
            objectAnalysisCache.removeValue(forKey: refID)
        }
    }

    /// Verifies that every page with committed text or object operations actually reflects
    /// them in its current bytes. A stale page invalidates the containing member because replay
    /// is intentionally member-atomic. Regenerating from the canonical base is the
    /// self-healing half of the "operations are the source of truth" contract: the ops
    /// live in workspace state while the visible result lives in `memberPDFData`, and any
    /// historical divergence between the two (e.g. a file saved by an older build
    /// with ops but no bake) would otherwise persist forever — the editor "remembers" the
    /// edit while the page and every export silently miss it.
    ///
    /// Detection is stamp-first: each regenerated page carries a `/OrifoldBakeStamp` hash of
    /// the operations it was baked from (see [[BakeStamp]]). A matching stamp means the bytes
    /// are current — including for style-only edits, which the text-presence fallback cannot
    /// verify. A missing stamp (legacy bytes saved before stamping existed) falls back to the
    /// text-presence check. A mismatched stamp means the operations changed since the bytes
    /// were written, so regenerate.
    @discardableResult
    func reconcileCommittedEditsWithLoadedPages() -> Int {
        let textByPage = document.workspace.pageEditStates.reduce(
            into: [UUID: [PDFTextEditOperation]]()
        ) { result, state in
            result[state.pageRefID, default: []].append(contentsOf: state.operations)
        }
        let objectsByPage = document.workspace.objectEditStates.reduce(
            into: [UUID: [ObjectEditOperation]]()
        ) { result, state in
            result[state.pageRefID, default: []].append(contentsOf: state.operations)
        }
        let editedPageRefIDs = Set(textByPage.keys).union(objectsByPage.keys)
        var staleMembers: [UUID: Set<UUID>] = [:]
        for pageRefID in editedPageRefIDs {
            guard let ref = workspacePageRef(pageRefID) else { continue }
            if pageBytesAreCurrent(
                textOperations: textByPage[pageRefID] ?? [],
                objectOperations: objectsByPage[pageRefID] ?? [],
                ref: ref
            ) { continue }
            staleMembers[ref.memberDocId, default: []].insert(pageRefID)
        }

        var regeneratedPages = 0
        for (memberID, stalePageRefIDs) in staleMembers {
            if replayCommittedEdits(for: memberID) {
                regeneratedPages += stalePageRefIDs.count
            } else {
                NSLog(
                    "[Orifold] Warning: member %@ has committed edits its bytes do not show, and replay failed.",
                    memberID.uuidString
                )
            }
        }
        return regeneratedPages
    }

    /// True when a page's current stamp reflects both lanes. The legacy text-presence fallback
    /// remains valid only for text-only pages; object operations require deterministic replay.
    private func pageBytesAreCurrent(
        textOperations: [PDFTextEditOperation],
        objectOperations: [ObjectEditOperation],
        ref: PageRef
    ) -> Bool {
        if let lookup = memberPDF(for: ref),
           let localIdx = localIndex(ref: ref, memberIndex: lookup.documentIndex),
           let page = lookup.pdf.page(at: localIdx),
           let stamp = Self.bakeStamp(on: page) {
            return stamp == BakeStamp.hash(
                textOperations: textOperations,
                objectOperations: objectOperations
            )
        }
        guard objectOperations.isEmpty else { return false }
        return pageVisiblyReflects(operations: textOperations, ref: ref)
    }

    /// True when the page's CURRENT bytes visibly contain every operation's replacement
    /// text. Whitespace-collapsed comparison, because the committed replacement wraps into
    /// lines during rendering and extraction re-inserts line breaks at arbitrary points.
    /// Style-only operations (replacement text equal to the source, or empty) are treated
    /// as reflected — text presence can't distinguish their bake.
    private func pageVisiblyReflects(operations: [PDFTextEditOperation], ref: PageRef) -> Bool {
        guard let lookup = memberPDF(for: ref),
              let localIdx = localIndex(ref: ref, memberIndex: lookup.documentIndex),
              let page = lookup.pdf.page(at: localIdx) else {
            // No page to check against — nothing sensible to regenerate either.
            return true
        }
        // `.attributedString`, not `.string`: PDFKit's `.string` interleaves characters for
        // overlapping text runs on the CI toolchain (see
        // [[ci-xcode164-pdfkit-string-extraction-quirk]] / UserFlowRegressionTests) — and an
        // edited page is exactly that shape (replacement drawn over the covered original).
        let pageText = Self.collapsedWhitespace(page.attributedString?.string ?? "")
        for operation in operations {
            let replacement = Self.collapsedWhitespace(operation.replacementText)
            let source = Self.collapsedWhitespace(operation.sourceText)
            guard !replacement.isEmpty, replacement != source else { continue }
            if !pageText.contains(replacement) { return false }
        }
        return true
    }

    private static func collapsedWhitespace(_ text: String) -> String {
        text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    // MARK: - Inline text edit revert

    enum InlineTextEditKind: String, Equatable {
        case insertion   // brand-new text
        case deletion    // text emptied
        case styleOnly   // same text, restyled
        case edit        // text changed
    }

    struct InlineTextEditListItem: Identifiable, Equatable {
        var id: UUID
        var pageRefID: UUID
        var pageNumber: Int
        var memberName: String
        var originalText: String
        var replacementText: String
        var isInsertion: Bool
        var kind: InlineTextEditKind
        /// 1-based position among the edits ON THIS PAGE (for "edit 2 of 3 on p.4").
        var orderOnPage: Int
        /// Total edits on this page (the "of N" in the label above).
        var totalOnPage: Int
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
            // Stable order for "edit N of M on this page": by creation time.
            let ordered = state.operations.sorted { $0.createdAt < $1.createdAt }
            let total = ordered.count
            for (opIndex, operation) in ordered.enumerated() {
                let trimmedReplacement = operation.replacementText.trimmingCharacters(in: .whitespacesAndNewlines)
                let trimmedSource = operation.sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
                let kind: InlineTextEditKind
                if operation.isInsertion {
                    kind = .insertion
                } else if trimmedReplacement.isEmpty {
                    kind = .deletion
                } else if trimmedReplacement == trimmedSource {
                    kind = .styleOnly
                } else {
                    kind = .edit
                }
                items.append(InlineTextEditListItem(
                    id: operation.id,
                    pageRefID: ref.id,
                    pageNumber: index + 1,
                    memberName: memberName,
                    originalText: operation.sourceText,
                    replacementText: operation.replacementText,
                    isInsertion: operation.isInsertion,
                    kind: kind,
                    orderOnPage: opIndex + 1,
                    totalOnPage: total
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
        guard regenerateEditedPage(pageRef: pageRef) else {
            document.workspace.pageEditStates = previousSnapshot.editStates
            showEditMessage(L10n.string("error.pageEdit.restoreFailed"), isError: true)
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
            if !regenerateEditedPage(pageRef: pageRef) {
                failedPageRefIDs.append(state.pageRefID)
            }
        }
        if !failedPageRefIDs.isEmpty {
            // Keep the edits we could not visually revert so the document and the edit
            // list stay consistent.
            document.workspace.pageEditStates = states.filter { failedPageRefIDs.contains($0.pageRefID) }
            showEditMessage(L10n.string("error.pageEdit.restoreSomeFailed"), isError: true)
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
            showEditMessage(L10n.string("error.markup.eraseTargetMissing"), isError: true)
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
        armedPlacement = .signature(
            data: imageData,
            options: PendingSignaturePlacementOptions(
                kind: kind,
                signerName: signerName,
                signerIdentityRef: nil,
                reason: nil,
                location: nil,
                contactInfo: nil,
                subFilter: nil,
                timestampRequested: false,
                certificateProfileID: nil
            ),
            identity: nil
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
                                              identity: (any SigningIdentity)? = nil,
                                              certificateProfileID: UUID? = nil) {
        guard canPerformSigningAction() else { return }
        armedPlacement = .signature(
            data: imageData,
            options: PendingSignaturePlacementOptions(
                kind: .cryptographic,
                signerName: signerName,
                signerIdentityRef: signerIdentityRef,
                reason: reason,
                location: location,
                contactInfo: contactInfo,
                subFilter: "ETSI.CAdES.detached",
                timestampRequested: timestampRequested,
                certificateProfileID: certificateProfileID
            ),
            identity: identity
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

    /// Disarms only a signature. Leaving the `.signature` tool must not disarm a
    /// stamp the user armed separately, so this stays case-scoped rather than
    /// clearing the slot outright.
    private func clearPendingSignaturePlacement() {
        if case .signature = armedPlacement { armedPlacement = nil }
    }

    func beginStampPlacement(text: String, swatch: PageDecorationSwatch) {
        guard canPerformMutatingAction() else { return }
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }
        armedPlacement = .stamp(PendingStampPlacementOptions(text: trimmedText, swatch: swatch))
        currentTool = .stamp
        isShowingSignaturePalette = false
        isShowingStampPalette = false
    }

    /// Arms a hanko seal for click-to-place. Reuses the `.stamp` tool + canvas gesture (the
    /// gesture checks `pendingHankoOptions` first), so a hanko lands on the next page click
    /// exactly as a text stamp does.
    func beginHankoPlacement(text: String, shape: HankoShape) {
        guard canPerformMutatingAction() else { return }
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }
        armedPlacement = .hanko(PendingHankoPlacementOptions(text: trimmedText, shape: shape))
        currentTool = .stamp
        isShowingSignaturePalette = false
        isShowingStampPalette = false
    }

    /// Arms a generated barcode/QR image for click-to-place. Reuses the `.stamp` tool + canvas
    /// gesture (which checks `pendingBarcodeOptions` first), so the barcode lands on the next
    /// page click exactly as a text stamp does. Called by `BarcodeComposerView` once it has
    /// rendered the PNG.
    func beginBarcodePlacement(imageData: Data, pixelSize: CGSize) {
        guard canPerformMutatingAction() else { return }
        guard !imageData.isEmpty else { return }
        armedPlacement = .barcode(PendingBarcodePlacementOptions(imageData: imageData, pixelSize: pixelSize))
        currentTool = .stamp
        isShowingSignaturePalette = false
        isShowingStampPalette = false
    }

    // MARK: - Certificate profiles (persistent digital IDs)

    /// All persisted signing identities (self-signed, imported `.p12`, or Keychain
    /// references) available for the Digital ID picker. Persistent — the same self-signed
    /// certificate is offered every time, rather than a fresh one being minted per signature.
    @MainActor
    var certificateProfiles: [DigitalCertificateProfile] {
        CertificateProfileStore.shared.profiles
    }

    /// Generates a self-signed certificate ONCE and registers it as a reusable profile. Call
    /// this only from the "Create local self-signed ID…" flow — never per-signature — so the
    /// resulting certificate stays stable enough for a recipient to eventually trust it.
    @MainActor
    func createSelfSignedCertificateProfile(commonName: String, emailAddress: String?, validityDays: Int) throws -> DigitalCertificateProfile {
        let trimmedName = commonName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { throw SigningError.missingIdentity }
        let identity = try SelfSignedSigningIdentityProvider.generate(
            request: SelfSignedIdentityRequest(commonName: trimmedName, emailAddress: emailAddress, validityDays: validityDays)
        )
        return try CertificateProfileStore.shared.register(identity: identity, label: trimmedName, source: .selfSignedGenerated)
    }

    /// Opens a file picker for a `.p12`/`.pfx`. Returns nil if the user cancels.
    func chooseCertificateFileURL() -> URL? {
        let panel = NSOpenPanel()
        panel.title = L10n.string("savePanel.importDigitalID.title")
        panel.prompt = L10n.string("savePanel.import.prompt")
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = ["p12", "pfx"].compactMap { UTType(filenameExtension: $0) }
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    /// Single-attempt `.p12`/`.pfx` import. Deliberately does not retry internally — the
    /// caller (an in-app password sheet) owns the retry loop so it can show an inline
    /// "wrong password" message and let the user try again without re-choosing the file.
    @MainActor
    func importCertificateProfile(fileURL: URL, passphrase: String, label: String) throws -> DigitalCertificateProfile {
        let data = try Data(contentsOf: fileURL)
        let identity = try PKCS12SigningIdentityProvider.importIdentity(from: data, passphrase: passphrase)
        return try CertificateProfileStore.shared.register(
            identity: identity,
            label: label,
            source: .importedP12(originalFilename: fileURL.lastPathComponent)
        )
    }

    /// Registers every identity already present in the macOS login Keychain as a profile
    /// (idempotent — an identity already registered is refreshed in place, not duplicated).
    @discardableResult
    @MainActor
    func addKeychainCertificateProfiles() throws -> [DigitalCertificateProfile] {
        let identities = try KeychainSigningIdentityProvider.identities()
        guard !identities.isEmpty else { throw SigningError.missingIdentity }
        return try CertificateProfileStore.shared.registerAll(
            identities: identities,
            label: { $0.commonName ?? L10n.string("signAlert.untitledDigitalID") },
            source: .keychainReference
        )
    }

    @MainActor
    func removeCertificateProfile(id: UUID) {
        CertificateProfileStore.shared.remove(id: id)
    }

    @MainActor
    func resolveSigningIdentity(certificateProfileID: UUID) throws -> any SigningIdentity {
        guard let profile = CertificateProfileStore.shared.profiles.first(where: { $0.id == certificateProfileID }) else {
            throw SigningError.missingIdentity
        }
        return try CertificateProfileStore.shared.resolveIdentity(for: profile)
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
            timestampApplied: false,
            certificateProfileID: options.certificateProfileID
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
        armedPlacement = nil
        replaceDecorations(decorations, actionName: "Place stamp")
        return decoration
    }

    @discardableResult
    func placeHanko(at pagePoint: CGPoint,
                    on page: PDFPage,
                    size: CGSize = CGSize(width: 96, height: 96)) -> PageDecoration? {
        guard canPerformMutatingAction() else { return nil }
        guard let options = pendingHankoOptions,
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
        let decoration = PageDecoration.hanko(
            text: options.text,
            shape: options.shape,
            pageRefID: refID,
            rect: bounds
        )
        var decorations = document.workspace.decorations
        decorations.append(decoration)
        selectedAnnotation = nil
        selectedStampDecorationID = decoration.id
        armedPlacement = nil
        replaceDecorations(decorations, actionName: "Place hanko")
        return decoration
    }

    /// Commits the armed barcode image onto `page` at the clicked point, sized to an
    /// aspect-correct rect. Clones the `placeStamp`/`placeHanko` flow so the placed barcode is
    /// selectable, movable, resizable, and part of the same atomic decoration undo.
    @discardableResult
    func placeBarcode(at pagePoint: CGPoint,
                      on page: PDFPage,
                      longestEdge: CGFloat = 132) -> PageDecoration? {
        guard canPerformMutatingAction() else { return nil }
        guard let options = pendingBarcodeOptions,
              let refID = pageRefID(for: page) else { return nil }
        let size = fittedBarcodeSize(pixelSize: options.pixelSize, longestEdge: longestEdge)
        let bounds = constrainedSignatureBounds(
            CGRect(
                x: pagePoint.x - size.width / 2,
                y: pagePoint.y - size.height / 2,
                width: size.width,
                height: size.height
            ),
            on: page
        )
        let decoration = PageDecoration.image(
            imageData: options.imageData,
            pageRefID: refID,
            rect: bounds
        )
        var decorations = document.workspace.decorations
        decorations.append(decoration)
        selectedAnnotation = nil
        selectedStampDecorationID = decoration.id
        armedPlacement = nil
        replaceDecorations(decorations, actionName: "Insert barcode")
        return decoration
    }

    /// Scales a barcode's pixel dimensions down to a page rect whose longest edge is
    /// `longestEdge` points, preserving aspect ratio (square QR stays square, wide Code 128
    /// stays wide).
    private func fittedBarcodeSize(pixelSize: CGSize, longestEdge: CGFloat) -> CGSize {
        let width = max(1, pixelSize.width)
        let height = max(1, pixelSize.height)
        let scale = longestEdge / max(width, height)
        return CGSize(width: width * scale, height: height * scale)
    }

    /// Scans the currently-viewed page for barcodes and presents the result sheet (which shows
    /// its own empty state when none are found). The page is rasterized on the main actor
    /// (`PDFPage` isn't `Sendable`), then Vision detection runs off-main so the first-scan model
    /// warmup (~1s) doesn't freeze the UI — mirroring `PDFOCRService`'s detached-task pattern.
    func scanBarcodesOnCurrentPage() {
        let index = combinedPageIndex(forWorkspacePageNumber: max(1, currentPageNumber)) ?? 0
        guard let image = combinedPDF.page(at: index).flatMap({ PDFOCRService.rasterizedImage(for: $0) }) else {
            barcodeScanResults = BarcodeScanResults(barcodes: [])
            return
        }
        Task.detached(priority: .userInitiated) {
            let found = BarcodeScanner.scan(image)
            await MainActor.run { self.barcodeScanResults = BarcodeScanResults(barcodes: found) }
        }
    }

    func stampDecoration(id: UUID) -> PageDecoration? {
        document.workspace.decorations.first { $0.id == id && $0.isSeal }
    }

    func stampDecoration(at pagePoint: CGPoint, on page: PDFPage, in pdfDocument: PDFDocument?) -> PageDecoration? {
        guard let pageRef = pageRef(for: page, in: pdfDocument) else { return nil }
        return document.workspace.decorations.reversed().first { decoration in
            guard decoration.isSeal,
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
        guard let index = decorations.firstIndex(where: { $0.id == id && $0.isSeal }) else { return }
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
        guard let index = document.workspace.decorations.firstIndex(where: { $0.id == decorationID && $0.isSeal }) else {
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

    @MainActor
    func signAndExportCryptographicPDF(timestampRequested: Bool, preferredTSA: TimestampAuthorityOption = .freeTSA) {
        guard canPerformSigningAction() else { return }
        guard let placement = document.workspace.signatures.last(where: { $0.isCryptographic }) else {
            showEditMessage(L10n.string("status.sign.placeCertificateFirst"), isError: true)
            return
        }
        let identity: any SigningIdentity
        do {
            if let resolvedIdentity = signingIdentitiesByPlacementID[placement.id] {
                identity = resolvedIdentity
            } else if let profileID = placement.certificateProfileID {
                // The in-memory identity cache doesn't survive a document close/reopen —
                // fall back to re-resolving from the persisted certificate profile so a
                // cryptographic placement made in an earlier session can still be signed.
                identity = try resolveSigningIdentity(certificateProfileID: profileID)
            } else {
                throw SigningError.missingIdentity
            }
        } catch SigningError.missingIdentity {
            exportError = ExportError(message: L10n.string("error.export.chooseSigningIdentity"))
            return
        } catch {
            exportError = ExportError(message: String(localized: "Orifold couldn’t prepare the signing identity. \(error.localizedDescription)", locale: L10n.currentLocale))
            return
        }
        // Review found nothing in the actual signing path ever checked this — a placement
        // made while a certificate was valid could otherwise be silently signed and
        // exported after it expired, producing a PDF that looks successfully signed.
        guard !identity.isCertificateExpired else {
            exportError = ExportError(message: L10n.string("error.export.identityExpired"))
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

        let estimatedDERBytes = try? CMSSignatureBuilder.estimatedMaxDEREncodedSize(
            identity: identity,
            includeTimestampSlack: timestampRequested
        )
        let field = SignatureFieldSpec(
            pageIndex: pageIndex,
            rect: placement.rect,
            signerName: placement.signerName ?? "Signer",
            reason: placement.reason,
            location: placement.location,
            contactInfo: placement.contactInfo,
            subFilter: placement.subFilter ?? "ETSI.CAdES.detached",
            estimatedSignatureDERBytes: estimatedDERBytes
        )
        let appearance: PDFAppearanceStream?
        do {
            appearance = try SignatureAppearanceRenderer.pdfAppearanceStream(
                for: .typedName(placement.signerName ?? "Signer"),
                bounds: placement.rect
            )
        } catch {
            exportError = ExportError(message: String(localized: "Orifold couldn’t prepare the visible signature. \(error.localizedDescription)", locale: L10n.currentLocale))
            return
        }

        operationProgress.start(
            title: L10n.string("signProgress.title"),
            detail: L10n.string("signProgress.signing"),
            isCancellable: true
        )
        let cancellation = OperationCancellationToken()
        let operationID = UUID()
        activeSigningCancellation = cancellation
        activeSigningID = operationID

        // The heavy work below (byte-range math, CMS build, optional TSA round-trip, file
        // write, verify) is unchanged from before — it's the SAME already pdfsig-verified
        // call chain, just moved off the main thread so the UI can show progress and the
        // window doesn't freeze while, e.g., a slow timestamp authority responds.
        //
        // `Task.detached` (not plain `Task { }`) — an unstructured `Task { }` created inside
        // an `@MainActor` function inherits MainActor isolation, which would run this whole
        // synchronous sign/CMS/hash pipeline right back on the main thread and defeat the
        // entire point of moving it off of it. `.detached` runs on the global concurrent
        // executor unconditionally.
        activeSigningTask = Task.detached { [weak self, pdfData, field, appearance, identity, timestampRequested, preferredTSA, targetURL, placementID = placement.id, cancellation, operationID] in
            guard let self else { return }
            do {
                if cancellation.isCancelled || Task.isCancelled { throw SigningError.cancelled }

                // A reference-type box, not two loose captured `var`s — mutated from within
                // the CMS builder's synchronous nested closures (called sequentially, never
                // truly concurrently, but the compiler can't prove that across a closure
                // typed to cross a Sendable boundary), matching the same idiom already used
                // by `fetchTimestampSynchronously`'s `TimestampBox` just below.
                final class SigningOutcomeBox: @unchecked Sendable {
                    var timestampWasApplied = false
                    var timestampFallbackMessage: String?
                }
                let outcome = SigningOutcomeBox()
                let signedData = try PDFIncrementalSigner().sign(pdf: pdfData, field: field, appearance: appearance) { byteRangeBytes in
                    if timestampRequested {
                        // Guarded by `activeSigningID == operationID` (not just fired
                        // unconditionally) — otherwise this fire-and-forget update can land
                        // AFTER the operation has already been cancelled/finished (or after
                        // an unrelated, newer operation has started), resurrecting stale
                        // "Requesting trusted timestamp…" text. Matches the same guard
                        // already used at the OCR/compression progress callbacks elsewhere
                        // in this file.
                        Task { @MainActor in
                            guard self.activeSigningID == operationID, self.operationProgress.isActive else { return }
                            self.operationProgress.update(fraction: 0.5, detail: L10n.string("signProgress.timestamping"))
                        }
                        return try CMSSignatureBuilder.buildCMS(byteRangeBytes: byteRangeBytes, identity: identity) { signatureValue in
                            do {
                                let token = try Self.fetchTimestampSynchronously(
                                    for: signatureValue,
                                    preferring: preferredTSA,
                                    onAttempt: { option in
                                        Task { @MainActor in
                                            guard self.activeSigningID == operationID, self.operationProgress.isActive else { return }
                                            self.operationProgress.update(
                                                fraction: 0.5,
                                                detail: L10n.format("signProgress.timestampingWithProvider", option.displayName)
                                            )
                                        }
                                    }
                                ).cmsTimeStampToken
                                outcome.timestampWasApplied = true
                                return token
                            } catch SigningError.cancelled {
                                // Must propagate, not fall back — otherwise cancelling
                                // during a hung TSA request would silently continue signing
                                // (just without a timestamp) instead of actually stopping.
                                throw SigningError.cancelled
                            } catch {
                                outcome.timestampFallbackMessage = L10n.string("status.sign.timestampUnavailable")
                                return nil
                            }
                        }
                    }
                    return try CMSSignatureBuilder.buildCMS(byteRangeBytes: byteRangeBytes, identity: identity, timestamp: nil)
                }

                if cancellation.isCancelled || Task.isCancelled { throw SigningError.cancelled }
                await MainActor.run {
                    self.operationProgress.update(fraction: 0.85, detail: L10n.string("signProgress.writing"))
                }
                try self.writeExportData(signedData, to: targetURL)

                await MainActor.run {
                    self.operationProgress.update(fraction: 0.95, detail: L10n.string("signProgress.verifying"))
                }
                try self.verifyExportedFile(at: targetURL)
                // A local, best-effort self-check (not a substitute for opening the file in
                // a real PDF reader) confirming the /ByteRange we just wrote covers the
                // entire exported file, so "signed successfully" isn't just "a file exists."
                let selfCheck = SignatureSelfCheck.verify(signedPDF: signedData)
                let selfCheckNote = selfCheck.coversWholeDocument
                    ? L10n.string("signSelfCheck.wholeDocumentVerified")
                    : L10n.string("signSelfCheck.coverageWarning")

                await MainActor.run {
                    guard self.activeSigningID == operationID else { return }
                    self.operationProgress.finish()
                    self.activeSigningTask = nil
                    self.activeSigningCancellation = nil
                    self.activeSigningID = nil
                    if let index = self.document.workspace.signatures.firstIndex(where: { $0.id == placementID }) {
                        self.document.workspace.signatures[index].timestampApplied = outcome.timestampWasApplied
                    }
                    let note = [outcome.timestampFallbackMessage, selfCheckNote].compactMap { $0 }.joined(separator: " ")
                    self.finalizeSuccessfulExport(url: targetURL, format: .pdf, note: note)
                }
            } catch {
                await MainActor.run {
                    guard self.activeSigningID == operationID else { return }
                    self.operationProgress.finish()
                    self.activeSigningTask = nil
                    self.activeSigningCancellation = nil
                    self.activeSigningID = nil
                    switch error {
                    case let writeError as ExportWriteError:
                        self.exportError = ExportError(message: writeError.userMessage)
                    case SigningError.cancelled:
                        self.editingStatus = .warning(L10n.string("status.sign.cancelled"))
                    case SigningError.notImplemented:
                        self.exportError = ExportError(message: L10n.string("error.export.signingNotAvailable"))
                    case SigningError.missingIdentity:
                        self.exportError = ExportError(message: L10n.string("error.export.chooseSigningIdentity"))
                    case SigningError.unsupportedPDFStructure:
                        self.exportError = ExportError(message: L10n.string("error.export.unsupportedPDFStructure"))
                    default:
                        self.exportError = ExportError(message: String(localized: "Orifold couldn’t sign the PDF. \(error.localizedDescription)", locale: L10n.currentLocale))
                    }
                }
            }
        }
    }

    private func pageIndex(forSignaturePlacement placement: SignaturePlacement) -> Int? {
        document.workspace.pageOrder.firstIndex { $0.id == placement.pageRefId }
    }

    private static func fetchTimestampSynchronously(
        for signatureValue: Data,
        preferring preferredTSA: TimestampAuthorityOption = .freeTSA,
        onAttempt: (@Sendable (TimestampAuthorityOption) -> Void)? = nil
    ) throws -> TimeStampToken {
        let semaphore = DispatchSemaphore(value: 0)
        // @unchecked Sendable, matching SigningOutcomeBox just above: writes happen on the
        // detached fetch task, the read happens after semaphore.wait() establishes a
        // happens-before edge — safe, but the annotation keeps that reasoning explicit and
        // consistent instead of silently relying on this package's relaxed Swift 5 mode.
        final class TimestampBox: @unchecked Sendable {
            var result: Result<TimeStampToken, Error>?
        }
        let box = TimestampBox()

        let fetchTask = Task.detached {
            do {
                box.result = .success(
                    try await TimestampAuthorityFallbackChain.fetchTimestamp(
                        for: signatureValue,
                        preferring: preferredTSA,
                        onAttempt: onAttempt
                    )
                )
            } catch {
                box.result = .failure(error)
            }
            semaphore.signal()
        }

        // Poll instead of an unconditional `semaphore.wait()` — the enclosing signing
        // operation may be cancelled while up to 4 TSA endpoints are being tried in
        // sequence (each with its own network timeout), and an unconditional wait would
        // make the "Cancel" button in the progress UI do nothing until that whole chain
        // finally times out on its own. `Task.isCancelled` here reflects the OUTER
        // `Task.detached` this function is called from (task-local cancellation state is
        // visible across synchronous call frames within the same executing task), so
        // cancelling the signing task actually interrupts a hung timestamp request.
        while semaphore.wait(timeout: .now() + 0.2) == .timedOut {
            if Task.isCancelled {
                fetchTask.cancel()
                throw SigningError.cancelled
            }
        }

        switch box.result {
        case .success(let token):
            return token
        case .failure(let error):
            throw error
        case nil:
            throw SigningError.timestampUnavailable
        }
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

    // MARK: - Read aloud (Feature C)

    /// The read-aloud controller for this workspace, created on first use. It reads directly
    /// from `combinedPDF` (indices are composed-document indices, banners included) and skips
    /// pages with no speakable text, so boundary banners and image-only pages are passed over.
    @MainActor
    var readAloud: ReadAloudController {
        if let existing = _readAloud { return existing }
        let controller = ReadAloudController(
            synthesizer: AVSpeechSynthesizerAdapter(),
            pageTextProvider: { [weak self] index in self?.readAloudPageText(at: index) },
            pageCount: { [weak self] in self?.combinedPDF.pageCount ?? 0 }
        )
        controller.rate = Float(readAloudRate.rawValue)
        // Mirror the controller's published state onto this view model so the UI stays reactive
        // without observing the nested ObservableObject directly.
        controller.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in self?.readAloudState = state }
            .store(in: &readAloudCancellables)
        _readAloud = controller
        return controller
    }

    #if DEBUG
    /// Test seam: install a read-aloud controller backed by a caller-supplied synthesizer (a
    /// fake, so no real audio device is touched) with optional canned page providers, wired
    /// through this view model's real state mirror and stored as the live `_readAloud`. Lets
    /// document-mutation auto-stop be verified deterministically, without depending on live
    /// PDF text extraction.
    @MainActor
    @discardableResult
    func installReadAloudControllerForTesting(
        synthesizer: SpeechSynthesizing,
        pageText: ((Int) -> String?)? = nil,
        pageCount: (() -> Int)? = nil
    ) -> ReadAloudController {
        let controller = ReadAloudController(
            synthesizer: synthesizer,
            pageTextProvider: pageText ?? { [weak self] index in self?.readAloudPageText(at: index) },
            pageCount: pageCount ?? { [weak self] in self?.combinedPDF.pageCount ?? 0 }
        )
        controller.rate = Float(readAloudRate.rawValue)
        controller.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in self?.readAloudState = state }
            .store(in: &readAloudCancellables)
        _readAloud = controller
        return controller
    }
    #endif

    /// Whether read-aloud is currently active (speaking or paused). Derived from the mirrored
    /// state, so reading it never forces the controller (and its synthesizer) into existence.
    var isReadingAloud: Bool { readAloudState != .idle }

    /// Set the read-aloud speed and forward it to the live controller (if any). Main-actor
    /// because the controller's `rate` is main-actor-isolated.
    @MainActor
    func setReadAloudRate(_ rate: ReadAloudRate) {
        readAloudRate = rate
        _readAloud?.rate = Float(rate.rawValue)
    }

    /// Start reading, or stop if already active — the single entry point the toolbar/menu bind
    /// to so one control both starts and stops.
    @MainActor
    func toggleReadAloud() {
        if readAloud.isActive {
            readAloud.stop()
        } else {
            startReadAloudFromCurrentPage()
        }
    }

    @MainActor
    func startReadAloudFromCurrentPage() {
        // `currentPageNumber` is a workspace (banner-excluded) page number; map it to the
        // composed-document index the controller reads. Fall back to the top of the document.
        let startIndex = combinedPageIndex(forWorkspacePageNumber: max(1, currentPageNumber)) ?? 0
        readAloud.start(fromPage: startIndex)
    }

    /// Page text for read-aloud. Uses `attributedString?.string` (NOT `.string`, which
    /// interleaves characters on the CI SDK — see the read-aloud plan). Boundary banners have
    /// no document text and are skipped outright.
    private func readAloudPageText(at index: Int) -> String? {
        guard index >= 0, index < combinedPDF.pageCount,
              let page = combinedPDF.page(at: index),
              !(page is BoundaryPage) else { return nil }
        return page.attributedString?.string
    }

    // MARK: - Find & Replace

    /// Comments whose body contains the current search query.
    var replaceableCommentMatches: [WorkspaceComment] {
        guard !searchQuery.isEmpty else { return [] }
        return document.workspace.comments.filter {
            $0.body.range(of: searchQuery, options: .caseInsensitive) != nil
        }
    }

    /// Replaces every occurrence of `searchQuery` in a single comment's body with
    /// `replaceText`, advancing past each replacement's own text so a replacement that
    /// itself contains the search query (e.g. "cat" → "cats") can't loop or re-match.
    private func replacingAllOccurrences(of query: String, with replacement: String, in text: String) -> String {
        guard !query.isEmpty else { return text }
        var result = ""
        var searchRange = text.startIndex..<text.endIndex
        while let range = text.range(of: query, options: .caseInsensitive, range: searchRange) {
            result += text[searchRange.lowerBound..<range.lowerBound]
            result += replacement
            searchRange = range.upperBound..<text.endIndex
        }
        result += text[searchRange]
        return result
    }

    /// All non-overlapping case-insensitive ranges of `query` within `text`, in order.
    private func caseInsensitiveOccurrences(of query: String, in text: String) -> [Range<String.Index>] {
        guard !query.isEmpty else { return [] }
        var ranges: [Range<String.Index>] = []
        var searchRange = text.startIndex..<text.endIndex
        while let range = text.range(of: query, options: .caseInsensitive, range: searchRange) {
            ranges.append(range)
            searchRange = range.upperBound..<text.endIndex
        }
        return ranges
    }

    /// Replaces only the occurrence at `index` (from `caseInsensitiveOccurrences`) with
    /// `replacement`, leaving every other occurrence in `text` untouched.
    private func replacingOccurrence(at index: Int, of query: String, with replacement: String, in text: String) -> String {
        let occurrences = caseInsensitiveOccurrences(of: query, in: text)
        guard occurrences.indices.contains(index) else { return text }
        var result = text
        result.replaceSubrange(occurrences[index], with: replacement)
        return result
    }

    /// Replaces every match of `searchQuery` in `comment`'s body with `replaceText` and
    /// commits it through the existing comment-edit path, so undo naming and the
    /// modified-document flag behave exactly like a manual comment edit. Returns whether
    /// the body actually changed — `updateCommentBody` rejects a rewrite that would leave
    /// the comment blank, and callers need to know that rather than assuming success.
    @discardableResult
    func replaceMatches(in comment: WorkspaceComment) -> Bool {
        guard !searchQuery.isEmpty else { return false }
        let updated = replacingAllOccurrences(of: searchQuery, with: replaceText, in: comment.body)
        guard updated != comment.body else { return false }
        return updateCommentBody(comment, body: updated)
    }

    /// Replaces every match across every editable comment in one atomic undo step.
    /// Returns the number of comments actually changed, for the confirmation/result UI.
    @discardableResult
    func replaceAllCommentMatches() -> Int {
        let matches = replaceableCommentMatches
        guard !matches.isEmpty, !searchQuery.isEmpty else { return 0 }
        var changedCount = 0
        registerIsolatedUndo {
            for comment in matches {
                let updated = replacingAllOccurrences(of: searchQuery, with: replaceText, in: comment.body)
                guard updated != comment.body else { continue }
                if updateCommentBody(comment, body: updated) {
                    changedCount += 1
                }
            }
            if changedCount > 0 {
                undoManager?.setActionName(L10n.string("undo.replaceText"))
            }
        }
        return changedCount
    }

    // MARK: - Find & Replace: document body text
    //
    // Body-text Replace reuses the exact same op-based engine behind the click-to-edit
    // "Edit Text" tool (`applyInlineTextEdit`/`PDFTextEditOperation`) rather than touching
    // PDF content streams directly, so erase-patching, reflow, undo, persistence, and every
    // export path (PDF, Word/RTF/ODT, etc. — all of which already reconcile committed
    // `PDFTextEditOperation`s) behave exactly as they do for a manual edit.

    /// A page-body paragraph containing at least one occurrence of the current search
    /// query, plus the live (possibly already-edited) text/geometry to replace within.
    private struct BodyTextMatch {
        var pageRef: PageRef
        var block: EditableTextBlock
        var occurrences: [Range<String.Index>]
    }

    /// The text-analysis blocks for `ref`, with any block that already has a committed
    /// inline-edit operation swapped for a SYNTHETIC block carrying that operation's live
    /// replacement text/geometry/format instead of the stale pristine reading — mirroring
    /// exactly how `editableTextBlock(at:)` routes a click into a re-edit of an existing op
    /// (same geometry containment check, same `id: existingOp.sourceBlockID` trick so a
    /// later `applyInlineTextEdit` call recognizes this as an update to that same operation
    /// rather than a brand-new one). Needed because `textAnalysis` always reads PRISTINE
    /// bytes — without this, Find & Replace would search text the user already edited away.
    private func liveTextBlocks(for ref: PageRef, page: PDFPage, memberID: UUID, localIndex: Int) -> [EditableTextBlock] {
        let analysis = textAnalysis(for: ref, page: page, memberID: memberID, localIndex: localIndex)
        let ops = document.workspace.pageEditStates.first(where: { $0.pageRefID == ref.id })?.operations ?? []
        guard !ops.isEmpty else { return analysis.blocks }

        var consumedOpIDs = Set<UUID>()
        var result: [EditableTextBlock] = []
        for block in analysis.blocks {
            let center = CGPoint(x: block.bounds.midX, y: block.bounds.midY)
            // Nearest candidate by distance, not first-in-array-order: an op's `editedBounds`
            // can grow well past its original footprint (see `measuredBounds`), so its inset
            // box can contain more than one fresh block's center. Picking by proximity keeps a
            // block from being paired with a farther op just because it happened to iterate
            // first, which would otherwise report/replace that block's text as the wrong op's
            // (stale-looking or duplicated) live content.
            guard let op = ops
                .filter({ op in
                    !consumedOpIDs.contains(op.id) &&
                    (op.editedBounds.insetBy(dx: -3, dy: -3).contains(center) ||
                     op.sourceBounds.insetBy(dx: -2, dy: -2).contains(center))
                })
                .min(by: { distanceSquared(from: center, to: $0.editedBounds) < distanceSquared(from: center, to: $1.editedBounds) })
            else {
                result.append(block)
                continue
            }
            consumedOpIDs.insert(op.id)
            result.append(syntheticLiveBlock(for: op, pageRefID: ref.id, page: page))
        }
        // Ops with no corresponding fresh block at all — a pure insertion into blank space,
        // or an edit whose original geometry no longer matches any detected block — still
        // hold live, user-authored text that Find & Replace must be able to reach.
        for op in ops where !consumedOpIDs.contains(op.id) {
            result.append(syntheticLiveBlock(for: op, pageRefID: ref.id, page: page))
        }
        return result
    }

    private func syntheticLiveBlock(for op: PDFTextEditOperation, pageRefID: UUID, page: PDFPage) -> EditableTextBlock {
        let bounds = reopenedBounds(for: op)
        return EditableTextBlock(
            id: op.sourceBlockID,
            pageRefID: pageRefID,
            text: op.replacementText,
            bounds: bounds,
            lines: [],
            columnBounds: op.columnBounds,
            fontName: op.fontName,
            fontSize: op.fontSize,
            textColor: op.textColor,
            alignment: op.alignment,
            underline: op.underline,
            rotation: 0,
            pageRotation: page.rotation,
            baseline: bounds.minY,
            confidence: .high
        )
    }

    /// One page-order walk of the whole document producing both halves of what Replace All
    /// needs — the replaceable matches AND the skipped-occurrence count — instead of two
    /// separate full-document scans (each independently re-running `liveTextBlocks`/
    /// `textAnalysis` per page) for what's ultimately one classification pass over the same
    /// blocks.
    private struct BodyMatchScan {
        var matches: [BodyTextMatch]
        var skippedCount: Int
    }

    private func scanBodyMatches(query: String) -> BodyMatchScan {
        guard !query.isEmpty else { return BodyMatchScan(matches: [], skippedCount: 0) }
        var matches: [BodyTextMatch] = []
        var skippedCount = 0
        for ref in document.workspace.pageOrder {
            guard let lookup = memberPDF(for: ref),
                  let localIdx = localIndex(ref: ref, memberIndex: lookup.documentIndex),
                  let page = lookup.pdf.page(at: localIdx) else { continue }
            for block in liveTextBlocks(for: ref, page: page, memberID: ref.memberDocId, localIndex: localIdx) {
                switch block.editability {
                case .direct, .replace:
                    let occurrences = caseInsensitiveOccurrences(of: query, in: block.text)
                    guard !occurrences.isEmpty else { continue }
                    matches.append(BodyTextMatch(pageRef: ref, block: block, occurrences: occurrences))
                case .hiddenOCRLayer, .lowVisibility:
                    // Real, findable text Replace deliberately skips rather than rewrites in
                    // bulk — counted so a Replace All total lower than the visible search
                    // count is always explained, never silently unaccounted for.
                    skippedCount += caseInsensitiveOccurrences(of: query, in: block.text).count
                case .overlayOnly, .insertion:
                    continue
                }
            }
        }
        return BodyMatchScan(matches: matches, skippedCount: skippedCount)
    }

    /// Total body-text occurrences of the current search query that Replace can act on —
    /// the count the Replace row and Replace All gating use.
    var bodyReplaceMatchCount: Int {
        scanBodyMatches(query: searchQuery).matches.reduce(0) { $0 + $1.occurrences.count }
    }

    private func overlapArea(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let intersection = a.standardized.intersection(b.standardized)
        guard !intersection.isNull else { return 0 }
        return intersection.width * intersection.height
    }

    /// Disambiguates WHICH occurrence in a multi-occurrence block the current selection
    /// actually points at, by matching the selection's line against the block's own
    /// per-line bounds. Deliberately has no further fallback beyond occurrence 0: a
    /// character-count-to-pixel-position proportional guess was tried here and removed —
    /// Swift `Character` counts don't correspond proportionally to rendered glyph width for
    /// any real proportional font, so that guess could confidently land on the WRONG
    /// occurrence and silently replace text the user never selected while leaving the
    /// clicked occurrence untouched. Occurrence 0 is at least deterministic and, unlike the
    /// proportional guess, never claims a precision it doesn't have.
    private func bestOccurrenceIndex(selectionBounds: CGRect, block: EditableTextBlock, occurrences: [Range<String.Index>]) -> Int {
        guard occurrences.count > 1 else { return 0 }
        return lineBasedOccurrenceIndex(selectionBounds: selectionBounds, block: block, occurrences: occurrences) ?? 0
    }

    private func lineBasedOccurrenceIndex(selectionBounds: CGRect, block: EditableTextBlock, occurrences: [Range<String.Index>]) -> Int? {
        guard !block.lines.isEmpty else { return nil }
        let text = block.text
        var cursor = text.startIndex
        var lineRanges: [(range: Range<String.Index>, bounds: CGRect)] = []
        for line in block.lines {
            let trimmed = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, let found = text.range(of: trimmed, range: cursor..<text.endIndex) else { continue }
            lineRanges.append((found, line.bounds))
            cursor = found.upperBound
        }
        guard !lineRanges.isEmpty else { return nil }
        let targetY = selectionBounds.midY
        guard let nearestLine = lineRanges.min(by: { abs($0.bounds.midY - targetY) < abs($1.bounds.midY - targetY) }) else { return nil }
        return occurrences.enumerated().first { nearestLine.range.contains($0.element.lowerBound) }?.offset
    }

    private func commitBodyBlockReplacement(pageRef: PageRef, block: EditableTextBlock, newText: String) -> Bool {
        guard newText != block.text else { return false }
        return applyInlineTextEdit(
            pageRef: pageRef,
            sourceBlock: block,
            replacementText: newText,
            editedBounds: block.bounds,
            fontName: block.fontName,
            fontSize: block.fontSize,
            textColor: block.textColor.nsColor,
            alignment: (block.alignment ?? .left).nsTextAlignment,
            underline: block.underline
        )
    }

    /// A resolved single-Replace target: which block on which page, and which occurrence
    /// within that block's text corresponds to the currently-selected search result.
    private struct CurrentBodyReplaceTarget {
        var pageRef: PageRef
        var block: EditableTextBlock
        var occurrenceIndex: Int
    }

    /// Resolves `searchResults[searchResultIndex]` to a specific replaceable block and
    /// occurrence, or nil when the current selection isn't (or is no longer) a live,
    /// eligible body match — shared by `canReplaceCurrentMatch` (so the Replace button can
    /// reflect eligibility BEFORE a click) and `replaceCurrentBodyMatch` (so the commit acts
    /// on exactly what was reported as eligible), rather than the two independently
    /// re-deriving candidates and risking disagreement.
    private func currentBodyReplaceTarget() -> CurrentBodyReplaceTarget? {
        guard searchResults.indices.contains(searchResultIndex) else { return nil }
        let selection = searchResults[searchResultIndex]
        guard let page = selection.pages.first,
              let ref = pageRef(for: page, in: combinedPDF),
              let lookup = memberPDF(for: ref),
              let localIdx = localIndex(ref: ref, memberIndex: lookup.documentIndex),
              let memberPage = lookup.pdf.page(at: localIdx) else { return nil }

        let selectionBounds = selection.bounds(for: page)
        let candidates = liveTextBlocks(for: ref, page: memberPage, memberID: ref.memberDocId, localIndex: localIdx)
            .filter { $0.editability == .direct || $0.editability == .replace }
            .compactMap { block -> (block: EditableTextBlock, overlap: CGFloat, occurrences: [Range<String.Index>])? in
                let occurrences = caseInsensitiveOccurrences(of: searchQuery, in: block.text)
                guard !occurrences.isEmpty else { return nil }
                return (block, overlapArea(block.bounds, selectionBounds), occurrences)
            }
        guard !candidates.isEmpty else { return nil }

        // Prefer genuine geometric overlap with the selection. When nothing overlaps at all
        // (e.g. the block was relocated via Match/Apply Style — `didApplyMatchedGeometry` —
        // and `reopenedBounds` doesn't yet reflect that new location), fall back to the
        // NEAREST candidate by distance rather than an arbitrary array-order pick, so the
        // choice is at least the geometrically closest real occurrence on the page.
        let chosen: (block: EditableTextBlock, overlap: CGFloat, occurrences: [Range<String.Index>])
        if let overlapping = candidates.filter({ $0.overlap > 0 }).max(by: { $0.overlap < $1.overlap }) {
            chosen = overlapping
        } else {
            let selectionCenter = CGPoint(x: selectionBounds.midX, y: selectionBounds.midY)
            chosen = candidates.min(by: { distanceSquared(from: selectionCenter, to: $0.block.bounds) < distanceSquared(from: selectionCenter, to: $1.block.bounds) })!
        }

        let occurrenceIndex = bestOccurrenceIndex(selectionBounds: selectionBounds, block: chosen.block, occurrences: chosen.occurrences)
        return CurrentBodyReplaceTarget(pageRef: ref, block: chosen.block, occurrenceIndex: occurrenceIndex)
    }

    /// Whether `replaceCurrentMatch()` can actually act on the current selection. A search
    /// result can land on text that's real and findable but not eligible for rewriting (an
    /// invisible OCR layer, a near-transparent fill — see `scanBodyMatches`); without this
    /// check the Replace button stayed enabled for that selection and clicking it silently
    /// no-opped with a misleading "would leave the comment empty" message, since no comment
    /// was ever involved.
    var canReplaceCurrentMatch: Bool {
        guard !searchQuery.isEmpty else { return false }
        if searchResults.indices.contains(searchResultIndex) {
            return currentBodyReplaceTarget() != nil
        }
        return !replaceableCommentMatches.isEmpty
    }

    /// Replaces the currently-selected search result (a body-text match) if there is one;
    /// falls back to the first replaceable comment when the query only appears in comments
    /// (there is no comment entry in the results list to "select"). Returns whether a
    /// replacement actually happened.
    @discardableResult
    func replaceCurrentMatch() -> Bool {
        guard !searchQuery.isEmpty else { return false }
        if replaceCurrentBodyMatch() { return true }
        guard let comment = replaceableCommentMatches.first else { return false }
        return replaceMatches(in: comment)
    }

    private func replaceCurrentBodyMatch() -> Bool {
        guard let target = currentBodyReplaceTarget() else { return false }
        let newText = replacingOccurrence(at: target.occurrenceIndex, of: searchQuery, with: replaceText, in: target.block.text)
        guard commitBodyBlockReplacement(pageRef: target.pageRef, block: target.block, newText: newText) else { return false }
        performSearch(query: searchQuery, autoJump: true)
        return true
    }

    /// Replaces every occurrence of `searchQuery` with `replaceText` across every eligible
    /// body-text paragraph AND every comment, in one atomic undo step. Returns the number
    /// of occurrences actually replaced and the number skipped as unsafe to rewrite in bulk.
    @discardableResult
    func replaceAllMatches() -> (replaced: Int, skipped: Int) {
        guard !searchQuery.isEmpty else { return (0, 0) }
        let scan = scanBodyMatches(query: searchQuery)
        let bodyMatches = scan.matches
        let skipped = scan.skippedCount
        guard !bodyMatches.isEmpty || !replaceableCommentMatches.isEmpty else { return (0, skipped) }

        var totalReplaced = 0
        registerIsolatedUndo {
            for match in bodyMatches {
                let newText = replacingAllOccurrences(of: searchQuery, with: replaceText, in: match.block.text)
                guard commitBodyBlockReplacement(pageRef: match.pageRef, block: match.block, newText: newText) else { continue }
                totalReplaced += match.occurrences.count
            }
            totalReplaced += replaceAllCommentMatches()
            if totalReplaced > 0 {
                undoManager?.setActionName(L10n.string("undo.replaceText"))
            }
        }
        performSearch(query: searchQuery, autoJump: false)
        return (totalReplaced, skipped)
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
                exportError = ExportError(message: String(localized: "Orifold couldn’t save the PDF. \(error.localizedDescription) Check that the destination still exists and that you have permission to write there, then try again.", locale: L10n.currentLocale))
            }
            return false
        }
    }

    func dataForPDFExport(options: WorkspaceExportOptions = WorkspaceExportOptions()) throws -> Data {
        if (options.encryption != nil || options.sanitization != nil), hasCryptographicSignaturePlacement {
            throw PDFEncryptionError.digitalSignatureConflict
        }
        // Attachments live only in the member byte lane and are dropped by the
        // PDFKit export assembly (and the compression/imposition passes). Capture
        // them BEFORE reconcile/replay can regenerate member bytes from the
        // page-content lanes, then re-graft them below.
        let preservedAttachments = collectMemberAttachments()
        // Belt-and-braces against any in-session ops↔bytes divergence: exported bytes must
        // reflect every committed edit operation, so verify (and self-heal) right before
        // they leave the app rather than trusting accumulated state.
        reconcileCommittedEditsWithLoadedPages()
        let snapshot = WorkspacePackage(
            workspace: document.workspace,
            memberPDFData: try currentPDFDataForExport(),
            sourcePayloads: document.sourcePayloads,
            originalMemberPDFData: pristineDataForMembersWithCommittedEdits()
        )
        // The assembly flattens signatures, decorations, comments and form fields into page
        // content. That is what makes the bytes safe to impose, so this is the one place that
        // mints `BakedPDFData` -- downstream stages carry the proof rather than restate it.
        var baked = BakedPDFData(alreadyFlattened:
            try document.exportedPDFDataThrowing(from: snapshot, options: options))
        if let preset = options.compressionPreset {
            baked = try baked.mapping { data in
                try PDFCompressionService.reduceFileSize(
                    of: data,
                    preset: preset,
                    processingEngine: processingEngine
                ).data
            }
        }
        // Imposition flows through sanitize + encryption below, so those options are never
        // silently dropped when combined with a layout.
        let imposedData: Data
        if let layout = options.imposition {
            imposedData = try PDFImpositionEngine.impose(baked, layout: layout)
        } else {
            imposedData = baked.bytes
        }
        // Re-graft attachments after every page-content pass (assembly, compression,
        // imposition — all of which drop them) but before sanitize, which
        // deliberately strips embedded files, and encryption, which preserves them.
        let attachedData = reinjectingAttachments(preservedAttachments, into: imposedData)
        let sanitizedData = try Self.sanitized(attachedData, options: options.sanitization)
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
        // Strip Orifold's own embedded metadata FIRST when removing metadata — qpdf's
        // sanitize never touches annotations, so without this the invisible
        // /OrifoldWorkspaceComments blob (full edit history, base64 member bytes, extracted
        // source text, all comments) survived into a supposedly-sanitized share.
        let preStripped = options.removesMetadata
            ? WorkspaceDocument.dataStrippedOfOrifoldMetadata(data)
            : data
        guard let result = QPDFService.sanitized(preStripped, removingMetadata: options.removesMetadata) else {
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
        // Persist a security-scoped bookmark for the exported destination so a later
        // reopen (from Recents, or double-clicking the file in Finder) survives the
        // sandbox boundary instead of hitting a bare, non-durable path URL — this is
        // what actually closes the "exported edited.pdf can't be reopened" gap: a
        // freshly-written export otherwise has no recorded access token at all.
        if format == .pdf, FileManager.default.isReadableFile(atPath: url.path) {
            Task { @MainActor in
                RecentsStore.shared.recordOpen(url: url)
            }
        }
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
                exportError = ExportError(message: String(localized: "Orifold couldn’t export page images. \(error.localizedDescription) Check that the destination folder exists and has free space, then try again.", locale: L10n.currentLocale))
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
                exportError = ExportError(message: String(localized: "Orifold couldn’t write the \(format.menuTitle) export. \(error.localizedDescription) Check that the destination folder exists and has free space, then try again.", locale: L10n.currentLocale))
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
            for annotation in BakeStamp.userAnnotations(on: page) {
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
        let inspectionRevision = pageInspectionRevision(for: member.id)
        for pagePosition in member.pageRefs.indices {
            let pageRefID = member.pageRefs[pagePosition]
            guard let pageRef = document.workspace.pageOrder.first(where: { $0.id == pageRefID }),
                  let basePage = originalBasePage(for: pageRef) else {
                continue
            }
            let analysisData = originalMemberPDFData[member.id] ?? document.memberPDFData[member.id] ?? Data()
            let inspection = pageInspectionCache.result(
                pdfData: analysisData,
                pageIndex: pageRef.sourcePageIndex,
                pageRefID: pageRef.id,
                revision: inspectionRevision
            )
            let blocks = textAnalysisEngine
                .analyze(
                    data: analysisData,
                    pageIndex: pageRef.sourcePageIndex,
                    pageRefID: pageRef.id,
                    fallbackPage: basePage,
                    inspection: inspection
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
            return String(localized: "Orifold couldn’t create the \(format.menuTitle) export. \(error.localizedDescription)", locale: L10n.currentLocale)
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
        // The object selection overlay draws in unrotated content space and object editing is
        // punted on rotated pages — a rotation invalidates an active selection ON THIS PAGE only;
        // a selection on an unrelated page must survive rotating a different page. Captured (not
        // just cleared) so undoing the rotation brings the selection back too — this function
        // recurses through its own undo/redo rather than going through OrderSnapshot/restore(),
        // so it has to carry the selection through by hand.
        let clearedSelection = objectSelection?.pageRefID == ref.id ? objectSelection : nil
        if clearedSelection != nil {
            clearObjectSelection()
        }
        objectAnalysisCache.removeValue(forKey: ref.id)
        rebuild()
        markWorkspaceModified()
        undoManager?.registerUndo(withTarget: self) { vm in
            guard vm.canPerformUndoMutation() else { return }
            vm.setRotation(for: ref, to: before, actionName: actionName)
            if let clearedSelection {
                vm.objectSelection = clearedSelection
            }
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
        document.workspace.objectEditStates.removeAll { $0.pageRefID == ref.id }
        clearCommentAnchors(forRemovedPageRefIDs: [ref.id])
        removeSignaturePlacements(forRemovedPageRefIDs: [ref.id])
        removeDecorations(forRemovedPageRefIDs: [ref.id])
        textAnalysisCache.removeValue(forKey: ref.id)
        objectAnalysisCache.removeValue(forKey: ref.id)
        if objectSelection?.pageRefID == ref.id {
            clearObjectSelection()
        }

        // Drop empty member
        if document.workspace.documents[lookup.documentIndex].pageRefs.isEmpty {
            loadedPDFs.remove(at: lookup.loadedIndex)
            document.workspace.documents.remove(at: lookup.documentIndex)
            objectBaseData.removeValue(forKey: ref.memberDocId)
            invalidatePageInspection(for: ref.memberDocId)
        } else {
            loadedPDFs[lookup.loadedIndex].0 = document.workspace.documents[lookup.documentIndex]
            // Deleting a page shifts every later page's local index within this member; a frozen
            // object-edit base still has the old indices, so it must move to the post-delete bytes.
            realignCanonicalReplayBaseAfterStructuralChange(memberID: ref.memberDocId)
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
            document.workspace.objectEditStates.removeAll { $0.pageRefID == ref.id }
            clearCommentAnchors(forRemovedPageRefIDs: [ref.id])
            removeSignaturePlacements(forRemovedPageRefIDs: [ref.id])
            removeDecorations(forRemovedPageRefIDs: [ref.id])
            textAnalysisCache.removeValue(forKey: ref.id)
            objectAnalysisCache.removeValue(forKey: ref.id)
        }
        if let sel = objectSelection, uniqueIDs.contains(sel.pageRefID) {
            clearObjectSelection()
        }
        for index in document.workspace.documents.indices.reversed() where document.workspace.documents[index].pageRefs.isEmpty {
            let id = document.workspace.documents[index].id
            document.workspace.documents.remove(at: index)
            loadedPDFs.removeAll { $0.0.id == id }
            document.memberPDFData.removeValue(forKey: id)
            document.sourcePayloads.removeValue(forKey: id)
            objectBaseData.removeValue(forKey: id)
            invalidatePageInspection(for: id)
        }
        for loadedIndex in loadedPDFs.indices {
            let memberID = loadedPDFs[loadedIndex].0.id
            if let updated = document.workspace.documents.first(where: { $0.id == memberID }) {
                loadedPDFs[loadedIndex].0 = updated
            }
        }
        // Deleting pages shifts every later page's local index within a surviving member; a
        // frozen object-edit base still has the old indices, so it must move to the post-delete
        // bytes (members dropped entirely above already had their base removed).
        for memberID in Set(orderedRefs.map(\.memberDocId)) {
            realignCanonicalReplayBaseAfterStructuralChange(memberID: memberID)
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
            objectAnalysisCache.removeValue(forKey: ref.id)
        }
        // Same rule as the single-page path: a rotation invalidates a selection only if it's on
        // one of the pages that actually rotated.
        if let sel = objectSelection, uniqueIDs.contains(sel.pageRefID) {
            clearObjectSelection()
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
            // The copied page's bytes visibly include any baked inline edits, so the
            // duplicate ref must own copies of the operations too — otherwise the first
            // regeneration of the duplicate (any new edit on it) rebuilds pristine + only
            // the new op, silently reverting the edits the copy visibly carried.
            if let sourceState = document.workspace.pageEditStates.first(where: { $0.pageRefID == ref.id }),
               !sourceState.operations.isEmpty {
                let clonedOps = sourceState.operations.map { op -> PDFTextEditOperation in
                    var clone = op
                    clone.id = UUID()
                    clone.pageRefID = duplicate.id
                    return clone
                }
                document.workspace.pageEditStates.append(PageEditState(pageRefID: duplicate.id, operations: clonedOps))
            }
            if let sourceState = document.workspace.objectEditStates.first(where: { $0.pageRefID == ref.id }),
               !sourceState.operations.isEmpty {
                let clonedOperations = sourceState.operations.map { operation -> ObjectEditOperation in
                    var clone = operation
                    clone.id = UUID()
                    clone.pageRefID = duplicate.id
                    clone.sourceObjectKey.pageRefID = duplicate.id
                    return clone
                }
                document.workspace.objectEditStates.append(
                    PageObjectEditState(pageRefID: duplicate.id, operations: clonedOperations)
                )
            }
        }
        // Inserting a page shifts every later local index. Rebuild the canonical base in the new
        // ref order; both operation lanes were cloned above, so source and duplicate stay editable.
        for memberID in Set(orderedRefs.map(\.memberDocId)) {
            realignCanonicalReplayBaseAfterStructuralChange(memberID: memberID)
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
                exportError = ExportError(message: String(localized: "Orifold couldn’t export the selected pages. \(error.localizedDescription)", locale: L10n.currentLocale))
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
        // `objectBaseData` is a frozen whole-member byte snapshot; `localIndex(ref:memberIndex:)`
        // always reflects the CURRENT page order. Reordering without refreezing would apply a
        // later object edit's ops (indexed by the new order) against the old order baked into
        // the frozen bytes — silently editing the wrong page.
        realignCanonicalReplayBaseAfterStructuralChange(memberID: ref.memberDocId)
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
            objectBaseData.removeValue(forKey: removedID)
            originalMemberPDFData.removeValue(forKey: removedID)
            invalidatePageInspection(for: removedID)
        }
        for loadedIndex in loadedPDFs.indices {
            let memberID = loadedPDFs[loadedIndex].0.id
            if let updated = document.workspace.documents.first(where: { $0.id == memberID }) {
                loadedPDFs[loadedIndex].0 = updated
            }
        }
        // A cross-member move breaks the pristine mapping on BOTH sides: the moved page
        // has no representation in the target's pristine bytes at all (so
        // `originalBasePage`/hit-testing would read a completely different page — the
        // confirmed data-destroying case), and the source's pristine keeps a page its
        // live layout no longer has. Rebase both members' pristine bases to their
        // post-move live bytes and renormalize their refs' sourcePageIndex to the new
        // layout. Trade-off: any already-baked edit in these members becomes part of the
        // pristine background from here on (a re-edit erases over the bake instead of
        // regenerating from the true original) — degraded but consistent, versus
        // regenerating the wrong page's content entirely.
        rebasePristineToLiveBytes(memberID: targetRef.memberDocId)
        rebasePristineToLiveBytes(memberID: ref.memberDocId)
        if objectSelection?.pageRefID == movedRef.id {
            clearObjectSelection()
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

    /// Prints the workspace. When `imposition` is non-nil the exported bytes are imposed
    /// (booklet / N-up) before printing, exactly as the export path does.
    func printWorkspace(imposition: ImpositionLayout? = nil) {
        let printableDocument: PDFDocument
        do {
            // `dataForPDFExport` returns fully-assembled export bytes, so the bake has run.
            var data = try dataForPDFExport()
            if let imposition {
                data = try PDFImpositionEngine.impose(
                    BakedPDFData(alreadyFlattened: data), layout: imposition)
            }
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
        // consistent with regeneration always starting from the original page. That also
        // means indexing them by `sourcePageIndex` (the ref's position in the PRISTINE
        // bytes), exactly like `originalBasePage` — the ref's CURRENT local position
        // diverges from it after any in-session delete/reorder of an earlier page, and
        // analyzing the wrong pristine page made click-to-edit open editors filled with a
        // deleted page's text (and bake erase patches sized to it).
        let data = originalMemberPDFData[memberID] ?? document.memberPDFData[memberID] ?? currentPDFData()[memberID] ?? Data()
        let pristineIndex = ref.sourcePageIndex >= 0 ? ref.sourcePageIndex : localIndex
        let inspection = pageInspectionCache.result(
            pdfData: data,
            pageIndex: pristineIndex,
            pageRefID: ref.id,
            revision: pageInspectionRevision(for: memberID)
        )
        let analysis = textAnalysisEngine.analyze(
            data: data,
            pageIndex: pristineIndex,
            pageRefID: ref.id,
            fallbackPage: page,
            inspection: inspection
        )
        // A global admission refusal can become admissible after another member releases cache
        // capacity. Preserve fail-closed behavior now without pinning the empty analysis forever.
        if !inspection.wasRefused {
            textAnalysisCache[ref.id] = analysis
        }
        return analysis
    }

    private func pageInspectionRevision(for memberID: UUID) -> PDFPageObjectInspection.Revision {
        if let existing = pageInspectionRevisions[memberID] { return existing }
        let revision = PDFPageObjectInspection.Revision()
        pageInspectionRevisions[memberID] = revision
        return revision
    }

    private func invalidatePageInspection(for memberID: UUID? = nil) {
        if let memberID {
            if let revision = pageInspectionRevisions.removeValue(forKey: memberID) {
                pageInspectionCache.remove(revision: revision)
            }
        } else {
            pageInspectionRevisions.removeAll()
            pageInspectionCache.removeAll()
        }
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
