import AppKit
import SwiftUI
import PDFKit
import UniformTypeIdentifiers

extension UTType {
    static let orifoldPageRef = UTType(exportedAs: "com.ud.Orifold.page-ref")
    static let docx = UTType(filenameExtension: "docx") ?? UTType(importedAs: "org.openxmlformats.wordprocessingml.document")
    static let wordDoc = UTType(filenameExtension: "doc") ?? UTType(importedAs: "com.microsoft.word.doc")
    static let odt = UTType(filenameExtension: "odt") ?? UTType(importedAs: "org.oasis-open.opendocument.text")
    static let orifoldXLSX = UTType(filenameExtension: "xlsx") ?? UTType(importedAs: "org.openxmlformats.spreadsheetml.sheet")
    static let orifoldPPTX = UTType(filenameExtension: "pptx") ?? UTType(importedAs: "org.openxmlformats.presentationml.presentation")
    static let orifoldEPUB = UTType(filenameExtension: "epub") ?? UTType(importedAs: "org.idpf.epub-container")
    static let orifoldRTFD = UTType(filenameExtension: "rtfd") ?? UTType(importedAs: "com.apple.rtfd")
    static let markdown = UTType(filenameExtension: "md") ?? UTType(importedAs: "net.daringfireball.markdown")
    static let csv = UTType(filenameExtension: "csv") ?? UTType(importedAs: "public.comma-separated-values-text")
    static let orifoldSVG = UTType(filenameExtension: "svg") ?? UTType(importedAs: "public.svg-image")
    static let orifoldTSV = UTType(filenameExtension: "tsv") ?? UTType(importedAs: "public.tab-separated-values-text")
    static let orifoldYAML = UTType(filenameExtension: "yaml") ?? UTType(importedAs: "public.yaml")
    static let orifoldTOML = UTType(filenameExtension: "toml") ?? UTType(importedAs: "public.toml")
    static let orifoldLog = UTType(filenameExtension: "log") ?? UTType(importedAs: "public.log")
    static let orifoldSourceCode = UTType(filenameExtension: "swift") ?? UTType(importedAs: "public.source-code")
    static let orifoldShellScript = UTType(filenameExtension: "sh") ?? UTType(importedAs: "public.shell-script")
    static let orifoldSQL = UTType(filenameExtension: "sql") ?? UTType(importedAs: "public.sql")
}

struct WorkspacePackage {
    var workspace: Workspace
    /// Raw PDF bytes keyed by MemberDocument.id; annotations are baked in.
    var memberPDFData: [UUID: Data]
    /// Original rich/text imports keyed by MemberDocument.id for faithful non-PDF export.
    var sourcePayloads: [UUID: SourceDocumentPayload] = [:]
    /// Pristine (pre-any-inline-text-edit) PDF bytes for members that have committed edit
    /// operations. Persisted alongside the baked bytes so a reopened workspace can always
    /// regenerate `f(pristine, operations)` exactly, instead of re-baking on top of
    /// already-baked pages (ghost ink) or — worse — trusting baked bytes that a historical
    /// divergence left WITHOUT the bake (the "edit remembered but invisible" trap).
    var originalMemberPDFData: [UUID: Data] = [:]
}

final class WorkspaceDocument: ReferenceFileDocument {
    typealias Snapshot = WorkspacePackage
    private static let legacyBrandToken = ["PDF", "old"].joined()
    private static let workspaceCommentsAnnotationKey = PDFAnnotationKey(rawValue: "/OrifoldWorkspaceComments")
    private static let legacyWorkspaceCommentsAnnotationKey = PDFAnnotationKey(rawValue: "/\(legacyBrandToken)WorkspaceComments")
    private static let bakedWorkspaceCommentAnnotationKey = PDFAnnotationKey(rawValue: "/OrifoldBakedWorkspaceComment")
    private static let legacyBakedWorkspaceCommentAnnotationKey = PDFAnnotationKey(rawValue: "/\(legacyBrandToken)BakedWorkspaceComment")
    private static let commentSubjectAnnotationKey = PDFAnnotationKey(rawValue: "/Subj")
    private static let commentAnchorRectAnnotationKey = PDFAnnotationKey(rawValue: "/OrifoldCommentAnchorRect")
    private static let legacyCommentAnchorRectAnnotationKey = PDFAnnotationKey(rawValue: "/\(legacyBrandToken)CommentAnchorRect")

    private struct OrifoldMetadata: Codable {
        var comments: [WorkspaceComment]
        var sourcePayloads: [UUID: SourceDocumentPayload] = [:]
        var editableWorkspace: Workspace?
        var editableMemberPDFData: [UUID: Data] = [:]
        /// See `WorkspacePackage.originalMemberPDFData` — pristine pre-edit bytes, only
        /// for members that have committed inline text edit operations. Absent in files
        /// saved by older builds; loaders must treat that as "pristine unknown".
        var editableOriginalMemberPDFData: [UUID: Data] = [:]

        init(comments: [WorkspaceComment] = [],
             sourcePayloads: [UUID: SourceDocumentPayload] = [:],
             editableWorkspace: Workspace? = nil,
             editableMemberPDFData: [UUID: Data] = [:],
             editableOriginalMemberPDFData: [UUID: Data] = [:]) {
            self.comments = comments
            self.sourcePayloads = sourcePayloads
            self.editableWorkspace = editableWorkspace
            self.editableMemberPDFData = editableMemberPDFData
            self.editableOriginalMemberPDFData = editableOriginalMemberPDFData
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            comments = try c.decodeIfPresent([WorkspaceComment].self, forKey: .comments) ?? []
            sourcePayloads = try c.decodeIfPresent([UUID: SourceDocumentPayload].self, forKey: .sourcePayloads) ?? [:]
            editableWorkspace = try c.decodeIfPresent(Workspace.self, forKey: .editableWorkspace)
            editableMemberPDFData = try c.decodeIfPresent([UUID: Data].self, forKey: .editableMemberPDFData) ?? [:]
            editableOriginalMemberPDFData = try c.decodeIfPresent([UUID: Data].self, forKey: .editableOriginalMemberPDFData) ?? [:]
        }
    }

    private static let explicitTextImportExtensions = [
        "text", "log", "tsv", "jsonl", "yaml", "yml", "toml", "plist",
        "swift", "js", "ts", "tsx", "jsx", "py", "rb", "go", "rs", "java", "kt",
        "c", "cc", "cpp", "h", "hpp", "m", "mm", "cs", "php", "sh", "zsh",
        "bash", "sql", "ini", "conf", "env"
    ]

    private static let explicitTextImportTypes = explicitTextImportExtensions.map {
        UTType(filenameExtension: $0) ?? UTType(importedAs: "com.ud.Orifold.import.\($0)")
    }

    static let importableContentTypes: [UTType] = [
        .pdf,
        .html,
        .orifoldSVG,
        .docx,
        .wordDoc,
        .odt,
        .orifoldXLSX,
        .orifoldPPTX,
        .orifoldEPUB,
        .orifoldRTFD,
        .rtf,
        .plainText,
        .text,
        .markdown,
        .csv,
        .orifoldTSV,
        .json,
        .xml,
        .orifoldYAML,
        .orifoldTOML,
        .propertyList,
        .orifoldLog,
        .orifoldSourceCode,
        .orifoldShellScript,
        .orifoldSQL
    ] + explicitTextImportTypes + [
        .image
    ]

    static var readableContentTypes: [UTType] { importableContentTypes }
    static var writableContentTypes: [UTType] { [.pdf] }

    // @Published so SwiftUI's DocumentGroup (which observes objectWillChange to know when
    // to mark the window edited / trigger autosave) actually sees mutations made by
    // WorkspaceViewModel — e.g. `document.workspace.pageEditStates[...] = ...` after an
    // inline text edit. Without this, edits could apply correctly in memory yet never
    // trigger a save because the framework had no signal that anything changed.
    @Published var workspace: Workspace
    @Published var memberPDFData: [UUID: Data] = [:]
    @Published var sourcePayloads: [UUID: SourceDocumentPayload] = [:]

    /// Pristine pre-edit member bytes restored from a saved workspace's embedded metadata
    /// (see `OrifoldMetadata.editableOriginalMemberPDFData`). Read once by
    /// `WorkspaceViewModel.init` to seed its own pristine-base cache; empty for fresh
    /// imports and for files saved before this payload existed.
    private(set) var restoredOriginalMemberPDFData: [UUID: Data] = [:]

    /// ViewModel sets this so snapshot() can capture live annotation state.
    var currentPDFDataProvider: (() throws -> [UUID: Data])?

    /// ViewModel sets this so snapshot() can persist pristine pre-edit member bytes for
    /// members that currently have committed inline text edit operations.
    var currentOriginalPDFDataProvider: (() -> [UUID: Data])?

    // MARK: - New document

    init() {
        workspace = Workspace()
    }

    // MARK: - Open existing

    required convenience init(configuration: ReadConfiguration) throws {
        try self.init(
            file: configuration.file,
            contentType: configuration.contentType,
            filename: configuration.file.preferredFilename
        )
    }

    private init(file: FileWrapper, contentType: UTType, filename: String?) throws {
        if contentType.conforms(to: .orifoldRTFD), file.isDirectory {
            let fallbackRTFDFilename = L10n.string("document.importedDocument") + ".rtfd"
            let imported = try DocumentImportConverter.importedRTFDDocument(
                fromFileWrappers: file.fileWrappers ?? [:],
                filename: filename ?? fallbackRTFDFilename
            )
            workspace = Workspace()
            try importPDFDocument(imported.pdfDocument, filename: filename ?? fallbackRTFDFilename, sourcePayload: imported.sourcePayload)
            return
        }

        guard Self.importableContentTypes.contains(where: { contentType.conforms(to: $0) }),
              !file.isDirectory,
              file.isRegularFile,
              let data = file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        workspace = Workspace()
        try importFileData(
            data,
            filename: filename ?? L10n.string("document.importedDocument"),
            contentType: contentType
        )
    }

    #if DEBUG
    convenience init(testingFile file: FileWrapper, contentType: UTType, filename: String? = nil) throws {
        try self.init(file: file, contentType: contentType, filename: filename)
    }
    #endif

    private func importFileData(_ data: Data, filename: String, contentType: UTType) throws {
        let imported = try DocumentImportConverter.importedDocument(
            from: data,
            contentType: contentType,
            filename: filename,
            baseURL: nil
        )
        try importPDFDocument(
            imported.pdfDocument,
            filename: filename,
            sourcePayload: imported.sourcePayload,
            originalPDFData: imported.originalPDFData
        )
    }

    private func importPDFDocument(
        _ pdf: PDFDocument,
        filename: String,
        sourcePayload: SourceDocumentPayload?,
        originalPDFData: Data? = nil
    ) throws {
        guard !pdf.isLocked else {
            throw DocumentImportConverter.ConversionError.passwordProtected
        }
        let (metadata, didStripAnnotations) = Self.metadata(from: pdf)
        if let editableWorkspace = metadata.editableWorkspace,
           !metadata.editableMemberPDFData.isEmpty {
            workspace = editableWorkspace
            memberPDFData = metadata.editableMemberPDFData
            sourcePayloads = metadata.sourcePayloads
            restoredOriginalMemberPDFData = metadata.editableOriginalMemberPDFData
            return
        }
        // If `metadata(from:)` stripped baked Orifold annotations, the on-disk `originalPDFData`
        // still contains them and is now stale relative to the cleaned in-memory `pdf`.
        // Force a re-serialization of the cleaned document (originalPDFData: nil) so those
        // annotations don't resurface — this only affects Orifold's own exported PDFs, which
        // were re-serialized at export anyway, never fresh third-party imports.
        let preferredOriginal = didStripAnnotations ? nil : originalPDFData
        guard let pdfData = PDFImportNormalizer.normalizedData(originalPDFData: preferredOriginal, renderedPDF: pdf) else {
            throw DocumentImportConverter.ConversionError.renderingFailed
        }

        let displayName = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
        var member = MemberDocument(displayName: displayName, sourcePDFRef: filename)
        let pageCount = pdf.pageCount
        let refs = (0..<pageCount).map { PageRef(memberDocId: member.id, sourcePageIndex: $0) }

        member.pageRefs = refs.map(\.id)
        workspace.title = displayName.isEmpty ? L10n.string("document.untitledWorkspace") : displayName
        workspace.documents = [member]
        workspace.pageOrder = refs
        workspace.comments = metadata.comments
        memberPDFData[member.id] = pdfData
        if let sourcePayload {
            sourcePayloads[member.id] = sourcePayload
        } else if metadata.sourcePayloads.count == 1,
                  let savedPayload = metadata.sourcePayloads.values.first,
                  savedPayload.renderedPageCount.map({ $0 == pageCount }) ?? true {
            sourcePayloads[member.id] = savedPayload
        }
    }

    func importPDFDocumentForTesting(_ pdf: PDFDocument, filename: String) throws {
        try importPDFDocument(pdf, filename: filename, sourcePayload: nil)
    }

    // MARK: - Snapshot (called on main thread before write)

    func snapshot(contentType: UTType) throws -> WorkspacePackage {
        let pdfData = try currentPDFDataProvider?() ?? memberPDFData
        // Without a live view model (e.g. a document being saved headlessly), fall back to
        // whatever pristine bytes the load restored — never to the current baked bytes,
        // which would freeze the bake into the "pristine" slot for every future session.
        let originals = currentOriginalPDFDataProvider?() ?? restoredOriginalMemberPDFData
        return WorkspacePackage(
            workspace: workspace,
            memberPDFData: pdfData,
            sourcePayloads: sourcePayloads,
            originalMemberPDFData: originals
        )
    }

    // MARK: - Write

    /// Flattens a snapshot into plain PDF bytes (banners stripped), the same bytes used
    /// when macOS autosaves an imported PDF document as a flat `.pdf` file. Pulled out of
    /// `fileWrapper` so it's independently testable — this is the exact path an inline
    /// text edit's saved bytes go through, and it's worth being able to assert on directly.
    func exportedPDFDataThrowing(from snapshot: WorkspacePackage,
                                 options: WorkspaceExportOptions = WorkspaceExportOptions()) throws -> Data {
        let docs: [(MemberDocument, PDFDocument)] = try snapshot.workspace.documents.map { member in
            guard let data = snapshot.memberPDFData[member.id],
                  let pdf = PDFDocument(data: data) else {
                throw PDFKitEngine.ExportAssemblyError.unreadableMember(member.displayName)
            }
            return (member, pdf)
        }
        let flat = try PDFKitEngine().concatenateForExport(documents: docs)
        guard let pdfData = PDFSerializer.data(from: flat) else {
            throw PDFKitEngine.ExportAssemblyError.emptyDocument
        }

        let omitsCommentMetadata = snapshot.workspace.signatures.contains { $0.isCryptographic }
        let sourcePayloads = Self.sourcePayloadsForPDFMetadata(from: snapshot)
        let editableWorkspace = options.embedsEditableWorkspaceState ? snapshot.workspace : nil
        let editableMemberPDFData = options.embedsEditableWorkspaceState ? snapshot.memberPDFData : [:]
        // Persist pristine bytes ONLY for members that actually have committed edit
        // operations — that's the only case regeneration ever needs a base, and it keeps
        // the metadata payload from doubling for the (common) unedited workspace.
        let membersWithEdits = Set(
            snapshot.workspace.pageEditStates
                .filter { !$0.operations.isEmpty }
                .compactMap { state in
                    snapshot.workspace.pageOrder.first(where: { $0.id == state.pageRefID })?.memberDocId
                }
        )
        let editableOriginalMemberPDFData = options.embedsEditableWorkspaceState
            ? snapshot.originalMemberPDFData.filter { membersWithEdits.contains($0.key) }
            : [:]
        let visualPlacements = snapshot.workspace.signatures.filter { !$0.isCryptographic }
        guard !visualPlacements.isEmpty else {
            let formData = try Self.applyFormExportAdditions(to: pdfData, workspace: snapshot.workspace, options: options)
            let decoratedData = try Self.applyDecorationExportAdditions(to: formData, workspace: snapshot.workspace)
            let commentData = try Self.applyCommentExportAdditions(to: decoratedData, workspace: snapshot.workspace)
            return try Self.embedMetadata(
                in: commentData,
                workspace: snapshot.workspace,
                sourcePayloads: sourcePayloads,
                editableWorkspace: editableWorkspace,
                editableMemberPDFData: editableMemberPDFData,
                editableOriginalMemberPDFData: editableOriginalMemberPDFData,
                omittingComments: omitsCommentMetadata
            )
        }

        do {
            let bakedData = try SignatureExportBaker.bake(placements: visualPlacements, into: pdfData) { placement in
                snapshot.workspace.pageOrder.firstIndex { $0.id == placement.pageRefId }
            }
            let formData = try Self.applyFormExportAdditions(to: bakedData, workspace: snapshot.workspace, options: options)
            let decoratedData = try Self.applyDecorationExportAdditions(to: formData, workspace: snapshot.workspace)
            let commentData = try Self.applyCommentExportAdditions(to: decoratedData, workspace: snapshot.workspace)
            return try Self.embedMetadata(
                in: commentData,
                workspace: snapshot.workspace,
                sourcePayloads: sourcePayloads,
                editableWorkspace: editableWorkspace,
                editableMemberPDFData: editableMemberPDFData,
                editableOriginalMemberPDFData: editableOriginalMemberPDFData,
                omittingComments: omitsCommentMetadata
            )
        } catch SigningError.notImplemented {
            let formData = try Self.applyFormExportAdditions(to: pdfData, workspace: snapshot.workspace, options: options)
            let decoratedData = try Self.applyDecorationExportAdditions(to: formData, workspace: snapshot.workspace)
            let commentData = try Self.applyCommentExportAdditions(to: decoratedData, workspace: snapshot.workspace)
            return try Self.embedMetadata(
                in: commentData,
                workspace: snapshot.workspace,
                sourcePayloads: sourcePayloads,
                editableWorkspace: editableWorkspace,
                editableMemberPDFData: editableMemberPDFData,
                editableOriginalMemberPDFData: editableOriginalMemberPDFData,
                omittingComments: omitsCommentMetadata
            )
        } catch {
            throw error
        }
    }

    private static func applyDecorationExportAdditions(to pdfData: Data, workspace: Workspace) throws -> Data {
        let activeDecorations = workspace.decorations.filter(\.isEnabled)
        guard !activeDecorations.isEmpty else { return pdfData }
        return try PDFDecorationExportBaker.bake(
            decorations: activeDecorations,
            pageOrder: workspace.pageOrder,
            into: pdfData
        )
    }

    private static func applyFormExportAdditions(to pdfData: Data,
                                                 workspace: Workspace,
                                                 options: WorkspaceExportOptions) throws -> Data {
        guard options.lockFormAnswers else { return pdfData }
        return try PDFFormSupport.flattenedData(from: pdfData, pageOrder: workspace.pageOrder)
    }

    private static func sourcePayloadsForPDFMetadata(from snapshot: WorkspacePackage) -> [UUID: SourceDocumentPayload] {
        guard snapshot.workspace.documents.count == 1,
              snapshot.workspace.signatures.isEmpty,
              !snapshot.workspace.hasActiveDecorations,
              snapshot.workspace.pageEditStates.isEmpty,
              let member = snapshot.workspace.documents.first,
              let payload = snapshot.sourcePayloads[member.id],
              snapshot.workspace.pageOrder.map(\.id) == member.pageRefs else {
            return [:]
        }

        if let renderedPageCount = payload.renderedPageCount,
           renderedPageCount != member.pageRefs.count {
            return [:]
        }

        for (expectedSourcePageIndex, pageRefID) in member.pageRefs.enumerated() {
            guard let pageRef = snapshot.workspace.pageOrder.first(where: { $0.id == pageRefID }),
                  pageRef.memberDocId == member.id,
                  pageRef.sourcePageIndex == expectedSourcePageIndex,
                  pageRef.rotation == 0 else {
                return [:]
            }
        }

        guard let data = snapshot.memberPDFData[member.id],
              let pdf = PDFDocument(data: data),
              pdf.pageCount == member.pageRefs.count else {
            return [:]
        }

        for pageIndex in 0..<pdf.pageCount {
            guard let page = pdf.page(at: pageIndex) else { return [:] }
            if page.rotation != 0 { return [:] }
            if page.annotations.contains(where: isPDFOnlyAnnotation) {
                return [:]
            }
        }

        return [member.id: payload]
    }

    private static func isPDFOnlyAnnotation(_ annotation: PDFAnnotation) -> Bool {
        if annotation.type == "FreeText" ||
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
        return false
    }

    private struct PDFCommentSummaryItem {
        var title: String
        var body: String
        var tags: [String]
        var isResolved: Bool
    }

    /// Bakes workspace comments (and any pre-existing PDF sticky notes) into a summary
    /// page and per-anchor annotations. Throws rather than silently discarding the
    /// comments on a `PDFSerializer` failure -- an export that silently drops the user's
    /// own notes with no warning is worse than one that fails loudly and lets them retry.
    private static func applyCommentExportAdditions(to data: Data, workspace: Workspace) throws -> Data {
        guard !workspace.signatures.contains(where: { $0.isCryptographic }),
              let pdf = PDFDocument(data: data) else {
            return data
        }

        let existingNotes = existingPDFNoteSummaryItems(from: pdf)
        let workspaceItems = workspace.comments.map { comment in
            PDFCommentSummaryItem(
                title: commentExportTitle(comment, workspace: workspace),
                body: comment.body,
                tags: comment.tags,
                isResolved: comment.isResolved
            )
        }
        guard !workspaceItems.isEmpty || !existingNotes.isEmpty else {
            return data
        }

        for comment in workspace.comments {
            guard let anchor = comment.anchor,
                  let pageIndex = workspace.pageOrder.firstIndex(where: { $0.id == anchor.pageRefID }),
                  let page = pdf.page(at: pageIndex) else {
                continue
            }
            let annotation = PDFAnnotation(bounds: anchor.rect, forType: .text, withProperties: nil)
            annotation.contents = comment.body
            annotation.color = NSColor.systemYellow
            annotation.setValue(true, forAnnotationKey: bakedWorkspaceCommentAnnotationKey)
            annotation.setValue(NSStringFromRect(anchor.rect), forAnnotationKey: commentAnchorRectAnnotationKey)
            if !comment.tags.isEmpty {
                annotation.setValue(comment.tags.joined(separator: ", "), forAnnotationKey: commentSubjectAnnotationKey)
            }
            page.addAnnotation(annotation)
        }

        let summaryItems = workspaceItems + existingNotes
        if let summaryPage = commentsSummaryPage(for: summaryItems) {
            pdf.insert(summaryPage, at: pdf.pageCount)
        }

        guard let result = PDFSerializer.data(from: pdf) else {
            throw PDFKitEngine.ExportAssemblyError.metadataEmbedFailed
        }
        return result
    }

    private static func existingPDFNoteSummaryItems(from pdf: PDFDocument) -> [PDFCommentSummaryItem] {
        var items: [PDFCommentSummaryItem] = []
        for pageIndex in 0..<pdf.pageCount {
            guard let page = pdf.page(at: pageIndex) else { continue }
            for annotation in page.annotations where annotation.type == "Text" {
                let body = annotation.contents?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !body.isEmpty else { continue }
                items.append(PDFCommentSummaryItem(
                    title: String(localized: "PDF note, page \(pageIndex + 1)", locale: L10n.currentLocale),
                    body: body,
                    tags: [],
                    isResolved: false
                ))
            }
        }
        return items
    }

    private static func commentExportTitle(_ comment: WorkspaceComment, workspace: Workspace) -> String {
        if let anchor = comment.anchor,
           let pageIndex = workspace.pageOrder.firstIndex(where: { $0.id == anchor.pageRefID }) {
            if let snippet = anchor.snippet, !snippet.isEmpty {
                return String(localized: "p. \(pageIndex + 1) - \(snippet)", locale: L10n.currentLocale)
            }
            return String(localized: "p. \(pageIndex + 1)", locale: L10n.currentLocale)
        }
        if comment.anchorWasRemoved {
            return L10n.string("document.commentPageRemoved")
        }
        return comment.createdAt.formatted(date: .abbreviated, time: .shortened)
    }

    private static func commentsSummaryPage(for items: [PDFCommentSummaryItem]) -> PDFPage? {
        let pageBounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        let data = NSMutableData()
        var mediaBox = pageBounds
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            return nil
        }

        context.beginPDFPage(nil)
        NSGraphicsContext.saveGraphicsState()
        let graphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.current = graphicsContext
        context.translateBy(x: 0, y: pageBounds.height)
        context.scaleBy(x: 1, y: -1)

        let text = commentsSummaryAttributedString(for: items)
        text.draw(in: CGRect(x: 54, y: 48, width: pageBounds.width - 108, height: pageBounds.height - 96))

        NSGraphicsContext.restoreGraphicsState()
        context.endPDFPage()
        context.closePDF()

        guard let summaryDocument = PDFDocument(data: data as Data) else { return nil }
        return summaryDocument.page(at: 0)
    }

    private static func commentsSummaryAttributedString(for items: [PDFCommentSummaryItem]) -> NSAttributedString {
        let output = NSMutableAttributedString()
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 22),
            .foregroundColor: NSColor.labelColor
        ]
        let headingAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 14),
            .foregroundColor: NSColor.labelColor
        ]
        let bodyAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.labelColor
        ]
        let metaAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 11),
            .foregroundColor: NSColor.labelColor
        ]

        output.append(NSAttributedString(string: L10n.string("document.commentsSummary.title") + "\n\n", attributes: titleAttributes))
        appendSummaryItems(items.filter { !$0.isResolved }, to: output, metaAttributes: metaAttributes, bodyAttributes: bodyAttributes)
        let resolved = items.filter(\.isResolved)
        if !resolved.isEmpty {
            output.append(NSAttributedString(string: "\n" + L10n.string("document.commentsSummary.resolved") + "\n", attributes: headingAttributes))
            appendSummaryItems(resolved, to: output, metaAttributes: metaAttributes, bodyAttributes: bodyAttributes)
        }
        return output
    }

    private static func appendSummaryItems(_ items: [PDFCommentSummaryItem],
                                           to output: NSMutableAttributedString,
                                           metaAttributes: [NSAttributedString.Key: Any],
                                           bodyAttributes: [NSAttributedString.Key: Any]) {
        for item in items {
            output.append(NSAttributedString(string: "\(item.title)\n", attributes: metaAttributes))
            if !item.tags.isEmpty {
                let tagsLine = String(localized: "Tags: \(item.tags.joined(separator: ", "))", locale: L10n.currentLocale)
                output.append(NSAttributedString(string: tagsLine + "\n", attributes: bodyAttributes))
            }
            output.append(NSAttributedString(string: "\(item.body)\n\n", attributes: bodyAttributes))
        }
    }

    /// Extracts embedded Orifold metadata (workspace comments / source payloads / editable
    /// workspace) from a freshly-loaded PDF and, as a side effect, **removes** the baked
    /// annotations that carry it — both the invisible metadata annotation and the visible
    /// baked comment notes. `didStripAnnotations` reports whether anything was removed: when
    /// true the in-memory `pdf` no longer matches its on-disk bytes, so the caller must
    /// re-serialize the cleaned document rather than persist the (stale) original bytes,
    /// otherwise the stripped comment notes resurface as duplicate PDF sticky notes.
    private static func metadata(from pdf: PDFDocument) -> (metadata: OrifoldMetadata, didStripAnnotations: Bool) {
        var metadata = OrifoldMetadata()
        var didStripAnnotations = false
        for pageIndex in 0..<pdf.pageCount {
            guard let page = pdf.page(at: pageIndex) else { continue }
            for annotation in Array(page.annotations) {
                if annotation.value(forAnnotationKey: bakedWorkspaceCommentAnnotationKey) != nil ||
                    annotation.value(forAnnotationKey: legacyBakedWorkspaceCommentAnnotationKey) != nil {
                    page.removeAnnotation(annotation)
                    didStripAnnotations = true
                    continue
                }
                guard let rawValue = annotation.value(forAnnotationKey: workspaceCommentsAnnotationKey) as? String ??
                        annotation.value(forAnnotationKey: legacyWorkspaceCommentsAnnotationKey) as? String else {
                    continue
                }
                if metadata.comments.isEmpty,
                   metadata.sourcePayloads.isEmpty,
                   let data = rawValue.data(using: .utf8),
                   let decoded = try? JSONDecoder().decode(OrifoldMetadata.self, from: data) {
                    metadata = decoded
                }
                page.removeAnnotation(annotation)
                didStripAnnotations = true
            }
        }
        return (metadata, didStripAnnotations)
    }

    /// Embeds Orifold's own round-trip metadata (comments, source payloads, editable
    /// workspace state) as an invisible annotation. Throws rather than silently falling
    /// back to pre-removal `data` on a `PDFSerializer` failure -- that fallback would
    /// silently resurrect metadata `removeMetadataAnnotations` just stripped (stale
    /// comments reappearing) or silently drop everything this export was meant to embed.
    private static func embedMetadata(in data: Data,
                                      workspace: Workspace,
                                      sourcePayloads: [UUID: SourceDocumentPayload],
                                      editableWorkspace: Workspace? = nil,
                                      editableMemberPDFData: [UUID: Data] = [:],
                                      editableOriginalMemberPDFData: [UUID: Data] = [:],
                                      omittingComments: Bool = false) throws -> Data {
        guard let pdf = PDFDocument(data: data) else {
            return data
        }
        let removedExistingMetadata = removeMetadataAnnotations(from: pdf)
        let comments = omittingComments ? [] : workspace.comments
        guard !comments.isEmpty || !sourcePayloads.isEmpty || editableWorkspace != nil || !editableMemberPDFData.isEmpty else {
            guard removedExistingMetadata else { return data }
            guard let result = PDFSerializer.data(from: pdf) else {
                throw PDFKitEngine.ExportAssemblyError.metadataEmbedFailed
            }
            return result
        }
        guard let metadataData = try? JSONEncoder().encode(OrifoldMetadata(
            comments: comments,
            sourcePayloads: sourcePayloads,
            editableWorkspace: editableWorkspace,
            editableMemberPDFData: editableMemberPDFData,
            editableOriginalMemberPDFData: editableOriginalMemberPDFData
        )),
              let metadataString = String(data: metadataData, encoding: .utf8) else {
            guard removedExistingMetadata else { return data }
            guard let result = PDFSerializer.data(from: pdf) else {
                throw PDFKitEngine.ExportAssemblyError.metadataEmbedFailed
            }
            return result
        }
        guard let firstPage = pdf.page(at: 0) else { return data }
        let annotation = PDFAnnotation(
            bounds: CGRect(x: -10, y: -10, width: 1, height: 1),
            forType: .freeText,
            withProperties: nil
        )
        annotation.color = .clear
        annotation.fontColor = .clear
        annotation.contents = nil
        annotation.setValue(metadataString, forAnnotationKey: workspaceCommentsAnnotationKey)
        firstPage.addAnnotation(annotation)
        guard let result = PDFSerializer.data(from: pdf) else {
            throw PDFKitEngine.ExportAssemblyError.metadataEmbedFailed
        }
        return result
    }

    @discardableResult
    private static func removeMetadataAnnotations(from pdf: PDFDocument) -> Bool {
        var removed = false
        for pageIndex in 0..<pdf.pageCount {
            guard let page = pdf.page(at: pageIndex) else { continue }
            for annotation in Array(page.annotations) {
                if annotation.value(forAnnotationKey: workspaceCommentsAnnotationKey) != nil ||
                    annotation.value(forAnnotationKey: legacyWorkspaceCommentsAnnotationKey) != nil {
                    page.removeAnnotation(annotation)
                    removed = true
                }
            }
        }
        return removed
    }

    /// Strips ALL Orifold-embedded metadata from `data` for the "Sanitize for sharing"
    /// export path: the invisible `/OrifoldWorkspaceComments` JSON blob (which embeds the
    /// full editable workspace — every edit operation's text, base64 member bytes, extracted
    /// source-document text, and every comment) AND the baked visible workspace-comment
    /// sticky notes. qpdf's `sanitized` (which only touches `/Info`, `/Metadata`, actions,
    /// and JavaScript) never removed these, so a "sanitized" file leaked the entire editing
    /// history and source content. Returns `data` unchanged when nothing was stripped or the
    /// bytes can't be re-serialized (fail-safe: better an unstripped export than a corrupt
    /// one — the caller still runs qpdf sanitize afterwards).
    static func dataStrippedOfOrifoldMetadata(_ data: Data) -> Data {
        guard let pdf = PDFDocument(data: data) else { return data }
        var removed = removeMetadataAnnotations(from: pdf)
        for pageIndex in 0..<pdf.pageCount {
            guard let page = pdf.page(at: pageIndex) else { continue }
            for annotation in Array(page.annotations) {
                if annotation.value(forAnnotationKey: bakedWorkspaceCommentAnnotationKey) != nil ||
                    annotation.value(forAnnotationKey: legacyBakedWorkspaceCommentAnnotationKey) != nil {
                    page.removeAnnotation(annotation)
                    removed = true
                }
            }
        }
        guard removed, let result = PDFSerializer.data(from: pdf) else { return data }
        return result
    }

    func fileWrapper(snapshot: WorkspacePackage, configuration: WriteConfiguration) throws -> FileWrapper {
        guard configuration.contentType.conforms(to: .pdf) else {
            throw CocoaError(.fileWriteUnknown)
        }
        // An emptied-out workspace (last document deleted) has nothing to preserve.
        // Autosave/close-save must not fail here — that's the save-before-close path,
        // distinct from an explicit user-triggered Export, which is guarded separately
        // in WorkspaceViewModel and surfaces its own "nothing to export" message.
        guard !snapshot.workspace.documents.isEmpty else {
            let emptyData = PDFSerializer.data(from: PDFDocument()) ?? Data()
            return FileWrapper(regularFileWithContents: emptyData)
        }
        let pdfData = try exportedPDFDataThrowing(
            from: snapshot,
            options: WorkspaceExportOptions(embedsEditableWorkspaceState: true)
        )
        PetBuddyHook.trigger(.save)
        return FileWrapper(regularFileWithContents: pdfData)
    }
}
