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
}

final class WorkspaceDocument: ReferenceFileDocument {
    typealias Snapshot = WorkspacePackage

    static let importableContentTypes: [UTType] = [
        .pdf,
        .html,
        .docx,
        .wordDoc,
        .odt,
        .rtf,
        .plainText,
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
        let pdf = try DocumentImportConverter.pdfDocument(
            from: data,
            contentType: contentType,
            filename: filename,
            baseURL: nil
        )
        try importPDFDocument(pdf, filename: filename)
    }

    private func importPDFDocument(_ pdf: PDFDocument, filename: String) throws {
        guard let pdfData = pdf.dataRepresentation() else {
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
        memberPDFData[member.id] = pdfData
    }

    // MARK: - Snapshot (called on main thread before write)

    func snapshot(contentType: UTType) throws -> WorkspacePackage {
        let pdfData = currentPDFDataProvider?() ?? memberPDFData
        return WorkspacePackage(workspace: workspace, memberPDFData: pdfData)
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
        guard !visualPlacements.isEmpty else { return pdfData }

        do {
            return try SignatureExportBaker.bake(placements: visualPlacements, into: pdfData) { placement in
                snapshot.workspace.pageOrder.firstIndex { $0.id == placement.pageRefId }
            }
        } catch SigningError.notImplemented {
            return pdfData
        } catch {
            return nil
        }
    }

    func fileWrapper(snapshot: WorkspacePackage, configuration: WriteConfiguration) throws -> FileWrapper {
        guard configuration.contentType.conforms(to: .pdf),
              let pdfData = exportedPDFData(from: snapshot) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return FileWrapper(regularFileWithContents: pdfData)
    }
}
