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
    var currentPDFDataProvider: (() -> [UUID: Data])?

    // MARK: - New document

    init() {
        workspace = Workspace()
    }

    // MARK: - Open existing

    required init(configuration: ReadConfiguration) throws {
        if Self.importableContentTypes.contains(where: { configuration.contentType.conforms(to: $0) }),
           let data = configuration.file.regularFileContents {
            workspace = Workspace()
            try importFileData(
                data,
                filename: configuration.file.preferredFilename ?? "Imported Document",
                contentType: configuration.contentType
            )
            return
        }

        workspace = Workspace()
    }

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
        } else if let savedPayload = metadata.sourcePayloads[member.id] ?? metadata.sourcePayloads.values.first {
            sourcePayloads[member.id] = savedPayload
        }
    }

    func importPDFDocumentForTesting(_ pdf: PDFDocument, filename: String) throws {
        try importPDFDocument(pdf, filename: filename, sourcePayload: nil)
    }

    // MARK: - Snapshot (called on main thread before write)

    func snapshot(contentType: UTType) throws -> WorkspacePackage {
        let pdfData = currentPDFDataProvider?() ?? memberPDFData
        return WorkspacePackage(workspace: workspace, memberPDFData: pdfData, sourcePayloads: sourcePayloads)
    }

    // MARK: - Write

    /// Flattens a snapshot into plain PDF bytes (banners stripped), the same bytes used
    /// when macOS autosaves an imported PDF document as a flat `.pdf` file. Pulled out of
    /// `fileWrapper` so it's independently testable — this is the exact path an inline
    /// text edit's saved bytes go through, and it's worth being able to assert on directly.
    func exportedPDFData(from snapshot: WorkspacePackage) -> Data? {
        let docs: [(MemberDocument, PDFDocument)] = snapshot.workspace.documents.compactMap { member in
            guard let data = snapshot.memberPDFData[member.id],
                  let pdf = PDFDocument(data: data) else { return nil }
            return (member, pdf)
        }
        let flat = PDFKitEngine().concatenate(documents: docs, includeBanners: false)
        guard let pdfData = PDFSerializer.data(from: flat) else { return nil }

        let visualPlacements = snapshot.workspace.signatures.filter { !$0.isCryptographic }
        guard !visualPlacements.isEmpty else {
            return Self.embedMetadata(in: pdfData, workspace: snapshot.workspace, sourcePayloads: snapshot.sourcePayloads) ?? pdfData
        }

        do {
            let bakedData = try SignatureExportBaker.bake(placements: visualPlacements, into: pdfData) { placement in
                snapshot.workspace.pageOrder.firstIndex { $0.id == placement.pageRefId }
            }
            return Self.embedMetadata(in: bakedData, workspace: snapshot.workspace, sourcePayloads: snapshot.sourcePayloads) ?? bakedData
        } catch SigningError.notImplemented {
            return Self.embedMetadata(in: pdfData, workspace: snapshot.workspace, sourcePayloads: snapshot.sourcePayloads) ?? pdfData
        } catch {
            return nil
        }
    }

    private static func metadata(from pdf: PDFDocument) -> PDFoldMetadata {
        var metadata = PDFoldMetadata()
        for pageIndex in 0..<pdf.pageCount {
            guard let page = pdf.page(at: pageIndex) else { continue }
            for annotation in Array(page.annotations) {
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

    private static func embedMetadata(in data: Data, workspace: Workspace, sourcePayloads: [UUID: SourceDocumentPayload]) -> Data? {
        guard let pdf = PDFDocument(data: data) else {
            return data
        }
        let removedExistingMetadata = removeMetadataAnnotations(from: pdf)
        guard !workspace.comments.isEmpty || !sourcePayloads.isEmpty else {
            return removedExistingMetadata ? PDFSerializer.data(from: pdf) : data
        }
        guard let metadataData = try? JSONEncoder().encode(PDFoldMetadata(comments: workspace.comments, sourcePayloads: sourcePayloads)),
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
        guard configuration.contentType.conforms(to: .pdf),
              let pdfData = exportedPDFData(from: snapshot) else {
            throw CocoaError(.fileWriteUnknown)
        }
        PetBuddyHook.trigger(.save)
        return FileWrapper(regularFileWithContents: pdfData)
    }
}
