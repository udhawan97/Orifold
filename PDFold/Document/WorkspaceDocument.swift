import AppKit
import SwiftUI
import PDFKit
import UniformTypeIdentifiers

extension UTType {
    static let pdfoldPageRef = UTType(exportedAs: "com.ud.PDFold.page-ref")
    static let docx = UTType(filenameExtension: "docx") ?? UTType(importedAs: "org.openxmlformats.wordprocessingml.document")
    static let wordDoc = UTType(filenameExtension: "doc") ?? UTType(importedAs: "com.microsoft.word.doc")
    static let odt = UTType(filenameExtension: "odt") ?? UTType(importedAs: "org.oasis-open.opendocument.text")
    static let markdown = UTType(filenameExtension: "md") ?? UTType(importedAs: "net.daringfireball.markdown")
    static let csv = UTType(filenameExtension: "csv") ?? UTType(importedAs: "public.comma-separated-values-text")
}

struct WorkspacePackage {
    var workspace: Workspace
    /// Raw PDF bytes keyed by MemberDocument.id; annotations are baked in.
    var memberPDFData: [UUID: Data]
    /// Original rich/text imports keyed by MemberDocument.id for faithful non-PDF export.
    var sourcePayloads: [UUID: SourceDocumentPayload] = [:]
}

final class WorkspaceDocument: ReferenceFileDocument {
    typealias Snapshot = WorkspacePackage
    private static let workspaceCommentsAnnotationKey = PDFAnnotationKey(rawValue: "/PDFoldWorkspaceComments")
    private static let bakedWorkspaceCommentAnnotationKey = PDFAnnotationKey(rawValue: "/PDFoldBakedWorkspaceComment")
    private static let commentSubjectAnnotationKey = PDFAnnotationKey(rawValue: "/Subj")
    private static let commentAnchorRectAnnotationKey = PDFAnnotationKey(rawValue: "/PDFoldCommentAnchorRect")

    private struct PDFoldMetadata: Codable {
        var comments: [WorkspaceComment]
        var sourcePayloads: [UUID: SourceDocumentPayload] = [:]

        init(comments: [WorkspaceComment] = [], sourcePayloads: [UUID: SourceDocumentPayload] = [:]) {
            self.comments = comments
            self.sourcePayloads = sourcePayloads
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            comments = try c.decodeIfPresent([WorkspaceComment].self, forKey: .comments) ?? []
            sourcePayloads = try c.decodeIfPresent([UUID: SourceDocumentPayload].self, forKey: .sourcePayloads) ?? [:]
        }
    }

    static let importableContentTypes: [UTType] = [
        .pdf,
        .html,
        .docx,
        .wordDoc,
        .odt,
        .rtf,
        .plainText,
        .text,
        .markdown,
        .csv,
        .json,
        .xml,
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

    /// ViewModel sets this so snapshot() can capture live annotation state.
    var currentPDFDataProvider: (() throws -> [UUID: Data])?

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
        guard Self.importableContentTypes.contains(where: { contentType.conforms(to: $0) }),
              !file.isDirectory,
              file.isRegularFile,
              let data = file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        workspace = Workspace()
        try importFileData(
            data,
            filename: filename ?? "Imported Document",
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
        try importPDFDocument(imported.pdfDocument, filename: filename, sourcePayload: imported.sourcePayload)
    }

    private func importPDFDocument(_ pdf: PDFDocument, filename: String, sourcePayload: SourceDocumentPayload?) throws {
        let metadata = Self.metadata(from: pdf)
        guard let pdfData = PDFSerializer.data(from: pdf) else {
            throw DocumentImportConverter.ConversionError.renderingFailed
        }

        let displayName = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
        var member = MemberDocument(displayName: displayName, sourcePDFRef: filename)
        let pageCount = pdf.pageCount
        let refs = (0..<pageCount).map { PageRef(memberDocId: member.id, sourcePageIndex: $0) }

        member.pageRefs = refs.map(\.id)
        workspace.title = displayName.isEmpty ? "Untitled Workspace" : displayName
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
        return WorkspacePackage(workspace: workspace, memberPDFData: pdfData, sourcePayloads: sourcePayloads)
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
        let visualPlacements = snapshot.workspace.signatures.filter { !$0.isCryptographic }
        guard !visualPlacements.isEmpty else {
            let formData = try Self.applyFormExportAdditions(to: pdfData, workspace: snapshot.workspace, options: options)
            let decoratedData = try Self.applyDecorationExportAdditions(to: formData, workspace: snapshot.workspace)
            let commentData = Self.applyCommentExportAdditions(to: decoratedData, workspace: snapshot.workspace) ?? decoratedData
            return Self.embedMetadata(in: commentData, workspace: snapshot.workspace, sourcePayloads: sourcePayloads, omittingComments: omitsCommentMetadata) ?? commentData
        }

        do {
            let bakedData = try SignatureExportBaker.bake(placements: visualPlacements, into: pdfData) { placement in
                snapshot.workspace.pageOrder.firstIndex { $0.id == placement.pageRefId }
            }
            let formData = try Self.applyFormExportAdditions(to: bakedData, workspace: snapshot.workspace, options: options)
            let decoratedData = try Self.applyDecorationExportAdditions(to: formData, workspace: snapshot.workspace)
            let commentData = Self.applyCommentExportAdditions(to: decoratedData, workspace: snapshot.workspace) ?? decoratedData
            return Self.embedMetadata(in: commentData, workspace: snapshot.workspace, sourcePayloads: sourcePayloads, omittingComments: omitsCommentMetadata) ?? commentData
        } catch SigningError.notImplemented {
            let formData = try Self.applyFormExportAdditions(to: pdfData, workspace: snapshot.workspace, options: options)
            let decoratedData = try Self.applyDecorationExportAdditions(to: formData, workspace: snapshot.workspace)
            let commentData = Self.applyCommentExportAdditions(to: decoratedData, workspace: snapshot.workspace) ?? decoratedData
            return Self.embedMetadata(in: commentData, workspace: snapshot.workspace, sourcePayloads: sourcePayloads, omittingComments: omitsCommentMetadata) ?? commentData
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

    private static func applyCommentExportAdditions(to data: Data, workspace: Workspace) -> Data? {
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

        return PDFSerializer.data(from: pdf)
    }

    private static func existingPDFNoteSummaryItems(from pdf: PDFDocument) -> [PDFCommentSummaryItem] {
        var items: [PDFCommentSummaryItem] = []
        for pageIndex in 0..<pdf.pageCount {
            guard let page = pdf.page(at: pageIndex) else { continue }
            for annotation in page.annotations where annotation.type == "Text" {
                let body = annotation.contents?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !body.isEmpty else { continue }
                items.append(PDFCommentSummaryItem(
                    title: "PDF note, page \(pageIndex + 1)",
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
                return "p. \(pageIndex + 1) - \(snippet)"
            }
            return "p. \(pageIndex + 1)"
        }
        if comment.anchorWasRemoved {
            return "(page removed)"
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

        output.append(NSAttributedString(string: "Comments\n\n", attributes: titleAttributes))
        appendSummaryItems(items.filter { !$0.isResolved }, to: output, metaAttributes: metaAttributes, bodyAttributes: bodyAttributes)
        let resolved = items.filter(\.isResolved)
        if !resolved.isEmpty {
            output.append(NSAttributedString(string: "\nResolved\n", attributes: headingAttributes))
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
                output.append(NSAttributedString(string: "Tags: \(item.tags.joined(separator: ", "))\n", attributes: bodyAttributes))
            }
            output.append(NSAttributedString(string: "\(item.body)\n\n", attributes: bodyAttributes))
        }
    }

    private static func metadata(from pdf: PDFDocument) -> PDFoldMetadata {
        var metadata = PDFoldMetadata()
        for pageIndex in 0..<pdf.pageCount {
            guard let page = pdf.page(at: pageIndex) else { continue }
            for annotation in Array(page.annotations) {
                if annotation.value(forAnnotationKey: bakedWorkspaceCommentAnnotationKey) != nil {
                    page.removeAnnotation(annotation)
                    continue
                }
                guard let rawValue = annotation.value(forAnnotationKey: workspaceCommentsAnnotationKey) as? String else {
                    continue
                }
                if metadata.comments.isEmpty,
                   metadata.sourcePayloads.isEmpty,
                   let data = rawValue.data(using: .utf8),
                   let decoded = try? JSONDecoder().decode(PDFoldMetadata.self, from: data) {
                    metadata = decoded
                }
                page.removeAnnotation(annotation)
            }
        }
        return metadata
    }

    private static func embedMetadata(in data: Data,
                                      workspace: Workspace,
                                      sourcePayloads: [UUID: SourceDocumentPayload],
                                      omittingComments: Bool = false) -> Data? {
        guard let pdf = PDFDocument(data: data) else {
            return data
        }
        let removedExistingMetadata = removeMetadataAnnotations(from: pdf)
        let comments = omittingComments ? [] : workspace.comments
        guard !comments.isEmpty || !sourcePayloads.isEmpty else {
            return removedExistingMetadata ? PDFSerializer.data(from: pdf) : data
        }
        guard let metadataData = try? JSONEncoder().encode(PDFoldMetadata(comments: comments, sourcePayloads: sourcePayloads)),
              let metadataString = String(data: metadataData, encoding: .utf8) else {
            return removedExistingMetadata ? PDFSerializer.data(from: pdf) : data
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
        return PDFSerializer.data(from: pdf)
    }

    @discardableResult
    private static func removeMetadataAnnotations(from pdf: PDFDocument) -> Bool {
        var removed = false
        for pageIndex in 0..<pdf.pageCount {
            guard let page = pdf.page(at: pageIndex) else { continue }
            for annotation in Array(page.annotations) where annotation.value(forAnnotationKey: workspaceCommentsAnnotationKey) != nil {
                page.removeAnnotation(annotation)
                removed = true
            }
        }
        return removed
    }

    func fileWrapper(snapshot: WorkspacePackage, configuration: WriteConfiguration) throws -> FileWrapper {
        guard configuration.contentType.conforms(to: .pdf) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let pdfData = try exportedPDFDataThrowing(from: snapshot)
        PetBuddyHook.trigger(.save)
        return FileWrapper(regularFileWithContents: pdfData)
    }
}
