import SwiftUI
import PDFKit
import UniformTypeIdentifiers
import AppKit

struct SidebarView: View {
    var viewModel: WorkspaceViewModel
    var onImportDrop: ([NSItemProvider]) -> Bool = { _ in false }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expandedDocs: Set<UUID> = []
    @State private var isImportDropTargeted = false

    private var shouldReduceMotion: Bool {
        reduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    var body: some View {
        List {
            SidebarBrandMasthead(
                documentCount: viewModel.document.workspace.documents.count,
                pageCount: viewModel.document.workspace.pageOrder.count,
                commentCount: viewModel.totalCommentCount
            )
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10))

            ForEach(viewModel.memberDocuments) { member in
                MemberDocRow(member: member, viewModel: viewModel, expandedDocs: $expandedDocs)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 3, leading: 10, bottom: 3, trailing: 10))
            }
            .onMove { viewModel.moveDocument(from: $0, to: $1) }
            .onDelete { viewModel.removeDocument(at: $0) }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Color.dsSurface)
        .overlay { importDropOverlay }
        .onDrop(
            of: WorkspaceDocument.importableContentTypes + [.fileURL],
            isTargeted: $isImportDropTargeted,
            perform: onImportDrop
        )
    }

    private var importDropOverlay: some View {
        RoundedRectangle(cornerRadius: .dsRadiusMd, style: .continuous)
            .strokeBorder(Color.dsAccent.opacity(isImportDropTargeted ? 0.55 : 0), lineWidth: 1.5)
            .background {
                if isImportDropTargeted {
                    ZStack {
                        Color.dsAccent.opacity(0.08)
                        VStack(spacing: .dsSM) {
                            Image(systemName: "tray.and.arrow.down.fill")
                                .font(.system(size: 26, weight: .light))
                                .symbolRenderingMode(.hierarchical)
                            Text("Drop to add documents")
                                .font(.dsHeadline())
                        }
                        .foregroundStyle(Color.dsAccent)
                        .padding(.horizontal, .dsLG)
                        .padding(.vertical, .dsMD)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: .dsRadiusMd, style: .continuous))
                    }
                }
            }
            .padding(.dsSM)
            .allowsHitTesting(false)
            .animation(shouldReduceMotion ? nil : .easeInOut(duration: 0.15), value: isImportDropTargeted)
    }
}

// MARK: - Brand masthead

private struct SidebarBrandMasthead: View {
    var documentCount: Int
    var pageCount: Int
    var commentCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: .dsMD) {
            AppBrandLockup(
                iconSize: 38,
                titleSize: 13,
                subtitleSize: 10.5,
                subtitle: "Fold messy documents into one clean PDF."
            )

            ViewThatFits(in: .horizontal) {
                HStack(spacing: .dsSM) {
                    SidebarMetric(value: "\(documentCount)", label: documentCount == 1 ? "file" : "files")
                    SidebarMetric(value: "\(pageCount)", label: pageCount == 1 ? "page" : "pages")
                    SidebarMetric(value: "\(commentCount)", label: commentCount == 1 ? "comment" : "comments")
                }

                VStack(alignment: .leading, spacing: .dsSM) {
                    HStack(spacing: .dsSM) {
                        SidebarMetric(value: "\(documentCount)", label: documentCount == 1 ? "file" : "files")
                        SidebarMetric(value: "\(pageCount)", label: pageCount == 1 ? "page" : "pages")
                    }
                    SidebarMetric(value: "\(commentCount)", label: commentCount == 1 ? "comment" : "comments")
                }
            }
        }
        .padding(.dsMD)
        .background {
            RoundedRectangle(cornerRadius: .dsRadiusMd, style: .continuous)
                .fill(Color.dsCard.opacity(0.72))
        }
        .overlay {
            RoundedRectangle(cornerRadius: .dsRadiusMd, style: .continuous)
                .strokeBorder(Color.dsSeparator, lineWidth: 1)
        }
    }
}

private struct SidebarMetric: View {
    var value: String
    var label: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(value)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.dsTextPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.dsTextTertiary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(Color.dsAccentSoft, in: Capsule())
        .fixedSize(horizontal: true, vertical: false)
    }
}

// MARK: - Member document row

struct MemberDocRow: View {
    var member: MemberDocument
    var viewModel: WorkspaceViewModel
    @Binding var expandedDocs: Set<UUID>
    @State private var isHovered = false

    private var isExpanded: Bool {
        get { expandedDocs.contains(member.id) }
        nonmutating set { if newValue { expandedDocs.insert(member.id) } else { expandedDocs.remove(member.id) } }
    }

    private var sourcePDF: PDFDocument? {
        viewModel.loadedPDFs.first(where: { $0.0.id == member.id })?.1
    }

    var body: some View {
        DisclosureGroup(
            isExpanded: Binding(get: { isExpanded }, set: { isExpanded = $0 })
        ) {
            if let pdf = sourcePDF {
                ThumbnailStrip(member: member, pdf: pdf, viewModel: viewModel)
            }
        } label: {
            HStack(spacing: .dsSM) {
                FileTypeBadge(filename: member.sourcePDFRef)
                VStack(alignment: .leading, spacing: 2) {
                    Text(member.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.dsTextPrimary)
                        .lineLimit(1)
                    Text("\(member.pageRefs.count) page\(member.pageRefs.count == 1 ? "" : "s")")
                        .font(.dsCaption())
                        .foregroundStyle(Color.dsTextTertiary)
                }
            }
            .padding(.vertical, 2)
        }
        .padding(.horizontal, .dsSM)
        .padding(.vertical, 5)
        .background {
            if isHovered {
                RoundedRectangle(cornerRadius: .dsRadiusSm, style: .continuous)
                    .fill(Color.dsAccentSoft)
            }
        }
        .onHover { isHovered = $0 }
    }
}

// MARK: - File type badge

private struct FileTypeBadge: View {
    var filename: String

    private var type: SidebarFileType {
        SidebarFileType(filename: filename)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(type.tint)
            VStack(spacing: -1) {
                Image(systemName: type.symbolName)
                    .font(.system(size: 9, weight: .semibold))
                Text(type.badgeText)
                    .font(.system(size: type.badgeText.count > 3 ? 5.3 : 6.3, weight: .black))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(width: 22)
            }
            .foregroundStyle(type.foreground)
        }
        .frame(width: 24, height: 24)
        .accessibilityLabel(type.accessibilityLabel)
    }
}

private struct SidebarFileType {
    let badgeText: String
    let symbolName: String
    let tint: Color
    let foreground: Color
    let accessibilityLabel: String

    init(filename: String) {
        switch URL(fileURLWithPath: filename).pathExtension.lowercased() {
        case "pdf":
            self.init("PDF", "doc.fill", Color(red: 0.78, green: 0.20, blue: 0.24), .white, "PDF file")
        case "html", "htm":
            self.init("HTML", "globe", Color(red: 0.07, green: 0.48, blue: 0.65), .white, "HTML file")
        case "doc", "docx", "odt", "rtf":
            self.init("DOC", "doc.text.fill", Color(red: 0.10, green: 0.30, blue: 0.52), .white, "Word document")
        case "md", "markdown":
            self.init("MD", "text.alignleft", Color(red: 0.27, green: 0.35, blue: 0.40), .white, "Markdown file")
        case "txt":
            self.init("TXT", "doc.text", Color(red: 0.38, green: 0.47, blue: 0.52), .white, "Text file")
        case "csv":
            self.init("CSV", "tablecells.fill", Color(red: 0.09, green: 0.52, blue: 0.44), .white, "CSV file")
        case "json":
            self.init("JSON", "curlybraces.square.fill", Color(red: 0.58, green: 0.42, blue: 0.16), .white, "JSON file")
        case "xml":
            self.init("XML", "chevron.left.forwardslash.chevron.right", Color(red: 0.43, green: 0.38, blue: 0.68), .white, "XML file")
        case "png", "jpg", "jpeg", "heic", "tiff", "gif", "bmp":
            self.init("IMG", "photo.fill", Color(red: 0.10, green: 0.58, blue: 0.63), .white, "Image file")
        default:
            self.init("FILE", "doc.fill", Color.dsAccent, .white, "File")
        }
    }

    private init(_ badgeText: String, _ symbolName: String, _ tint: Color, _ foreground: Color, _ accessibilityLabel: String) {
        self.badgeText = badgeText
        self.symbolName = symbolName
        self.tint = tint
        self.foreground = foreground
        self.accessibilityLabel = accessibilityLabel
    }
}

// MARK: - Thumbnail strip

struct ThumbnailStrip: View {
    var member: MemberDocument
    var pdf: PDFDocument
    var viewModel: WorkspaceViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shouldReduceMotion: Bool {
        reduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    var body: some View {
        VStack(spacing: 4) {
            ForEach(Array(zip(member.pageRefs.indices, member.pageRefs)), id: \.1) { i, refId in
                if let page = pdf.page(at: i),
                   let ref = viewModel.document.workspace.pageOrder.first(where: { $0.id == refId }) {
                    ThumbnailCell(page: page, pageRef: ref, pageNumber: i + 1, viewModel: viewModel)
                        .transition(shouldReduceMotion ? .identity : .scale(scale: 0.92).combined(with: .opacity))
                }
            }
        }
        .padding(.leading, 4)
        .padding(.vertical, 4)
        .animation(
            shouldReduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8),
            value: member.pageRefs
        )
    }
}

// MARK: - Individual thumbnail cell

struct ThumbnailCell: View {
    var page: PDFPage
    var pageRef: PageRef
    var pageNumber: Int
    var viewModel: WorkspaceViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var thumbnail: NSImage? = nil
    @State private var isHovered = false

    private static let thumbSize = CGSize(width: 48, height: 64)
    private var isSelected: Bool { viewModel.selectedPageRefID == pageRef.id }
    private var commentCount: Int { viewModel.commentCount(for: pageRef.id) }
    private var shouldReduceMotion: Bool {
        reduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    var body: some View {
        HStack(spacing: .dsSM) {
            // Thumbnail image
            Group {
                if let img = thumbnail {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: Self.thumbSize.width, height: Self.thumbSize.height)
                } else {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.dsSeparator)
                        .frame(width: Self.thumbSize.width, height: Self.thumbSize.height)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.dsAccent : Color.dsSeparator,
                        lineWidth: isSelected ? 1.5 : 0.5
                    )
            }
            .overlay(alignment: .topTrailing) {
                if commentCount > 0 {
                    Text("\(commentCount)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.white)
                        .frame(minWidth: 15, minHeight: 15)
                        .background(Color.dsAccent, in: Circle())
                        .offset(x: 5, y: -5)
                        .accessibilityLabel("\(commentCount) comments on page")
                }
            }
            .shadow(color: .black.opacity(0.10), radius: 3, x: 0, y: 1)
            .background(Color.dsCard, in: RoundedRectangle(cornerRadius: 3))
            .contextMenu {
                Button("Rotate 90° CW")  { viewModel.rotatePage(pageRef, by: 90);  thumbnail = nil }
                Button("Rotate 90° CCW") { viewModel.rotatePage(pageRef, by: -90); thumbnail = nil }
                Divider()
                Button("Delete Page", role: .destructive) { viewModel.deletePage(pageRef) }
            }

            // Label
            Text("p. \(pageNumber)")
                .font(.dsCaption())
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundStyle(isSelected ? Color.dsAccent : Color.dsTextSecondary)

            Spacer()

            Image(systemName: "line.3.horizontal")
                .font(.caption2)
                .foregroundStyle(Color.dsTextTertiary)
                .opacity(isHovered || isSelected ? 1 : 0)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background {
            RoundedRectangle(cornerRadius: .dsRadiusSm, style: .continuous)
                .fill(isSelected ? Color.dsAccentSoft : (isHovered ? Color.dsSeparator : Color.clear))
        }
        .scaleEffect(shouldReduceMotion ? 1.0 : (isSelected ? 1.03 : 1.0))
        .animation(shouldReduceMotion ? nil : .easeInOut(duration: 0.12), value: isSelected)
        .animation(shouldReduceMotion ? nil : .easeInOut(duration: 0.10), value: isHovered)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture { viewModel.selectPage(pageRef) }
        .onDrag {
            viewModel.beginDraggingPage(pageRef)
            let provider = NSItemProvider()
            provider.registerDataRepresentation(
                forTypeIdentifier: UTType.pdfoldPageRef.identifier,
                visibility: .ownProcess
            ) { completion in
                completion(pageRef.id.uuidString.data(using: .utf8), nil)
                return nil
            }
            return provider
        }
        .onDrop(of: [.pdfoldPageRef], isTargeted: nil) { _ in
            viewModel.moveDraggedPage(to: pageRef)
        }
        .task(id: pageNumber) {
            guard thumbnail == nil else { return }
            let size = Self.thumbSize
            let p = page
            thumbnail = await Task.detached(priority: .utility) {
                p.thumbnail(of: size, for: .mediaBox)
            }.value
        }
    }
}
