import SwiftUI
import PDFKit
import UniformTypeIdentifiers

struct SidebarView: View {
    var viewModel: WorkspaceViewModel
    @State private var expandedDocs: Set<UUID> = []

    var body: some View {
        List {
            ForEach(viewModel.document.workspace.documents) { member in
                MemberDocRow(member: member, viewModel: viewModel, expandedDocs: $expandedDocs)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
            }
            .onMove { viewModel.moveDocument(from: $0, to: $1) }
            .onDelete { viewModel.removeDocument(at: $0) }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

// MARK: - Member document row with expandable thumbnail strip

struct MemberDocRow: View {
    var member: MemberDocument
    var viewModel: WorkspaceViewModel
    @Binding var expandedDocs: Set<UUID>

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
            HStack(spacing: 8) {
                Image(systemName: "doc.richtext.fill")
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(member.displayName)
                            .font(.callout.weight(.semibold))
                            .lineLimit(1)
                    }
                    Text("\(member.pageRefs.count) page\(member.pageRefs.count == 1 ? "" : "s") • \(member.sourcePDFRef)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            .padding(.vertical, 3)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06))
        }
    }
}

// MARK: - Thumbnail strip

struct ThumbnailStrip: View {
    var member: MemberDocument
    var pdf: PDFDocument
    var viewModel: WorkspaceViewModel

    var body: some View {
        VStack(spacing: 6) {
            ForEach(Array(zip(member.pageRefs.indices, member.pageRefs)), id: \.1) { i, refId in
                if let page = pdf.page(at: i),
                   let ref = viewModel.document.workspace.pageOrder.first(where: { $0.id == refId }) {
                    ThumbnailCell(
                        page: page,
                        pageRef: ref,
                        pageNumber: i + 1,
                        viewModel: viewModel
                    )
                }
            }
        }
        .padding(.leading, 6)
        .padding(.vertical, 6)
    }
}

// MARK: - Individual thumbnail cell with async rendering

struct ThumbnailCell: View {
    var page: PDFPage
    var pageRef: PageRef
    var pageNumber: Int
    var viewModel: WorkspaceViewModel
    @State private var thumbnail: NSImage? = nil

    private static let thumbSize = CGSize(width: 52, height: 68)
    private var isSelected: Bool { viewModel.selectedPageRefID == pageRef.id }

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let img = thumbnail {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: Self.thumbSize.width, height: Self.thumbSize.height)
                        .cornerRadius(3)
                        .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
                } else {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.secondary.opacity(0.15))
                        .frame(width: Self.thumbSize.width, height: Self.thumbSize.height)
                }
            }
            .contextMenu {
                Button("Rotate 90° CW") {
                    viewModel.rotatePage(pageRef, by: 90)
                    thumbnail = nil  // invalidate cache
                }
                Button("Rotate 90° CCW") {
                    viewModel.rotatePage(pageRef, by: -90)
                    thumbnail = nil
                }
                Divider()
                Button("Delete Page", role: .destructive) {
                    viewModel.deletePage(pageRef)
                }
            }
            Text("p. \(pageNumber)")
                .font(.caption2)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundStyle(isSelected ? .primary : .secondary)
            Spacer()
            Image(systemName: "line.3.horizontal")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .opacity(isSelected ? 1 : 0.55)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.accentColor.opacity(0.18))
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(0.035))
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSelected ? Color.accentColor.opacity(0.5) : Color.primary.opacity(0.05), lineWidth: 1)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.selectPage(pageRef)
        }
        .onDrag {
            viewModel.beginDraggingPage(pageRef)
            return NSItemProvider(object: pageRef.id.uuidString as NSString)
        }
        .onDrop(of: [UTType.text], isTargeted: nil) { _ in
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
