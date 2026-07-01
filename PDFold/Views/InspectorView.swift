import SwiftUI
import PDFKit

struct InspectorView: View {
    @Bindable var viewModel: WorkspaceViewModel
    @State private var selectedTab: Tab = .info

    enum Tab: String, CaseIterable {
        case info = "Info"
        case tags = "Tags"
        case comments = "Comments"
        case markup = "Markup"

        var iconName: String {
            switch self {
            case .info: return "info.circle"
            case .tags: return "tag"
            case .comments: return "text.bubble"
            case .markup: return "highlighter"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Inspector")
                    .font(.system(size: 13, weight: .semibold, design: .serif))
                    .foregroundStyle(Color.dsTextPrimary)
                Spacer()
            }
            .padding(.horizontal, .dsLG)
            .padding(.top, .dsMD)
            .padding(.bottom, .dsSM)

            InspectorTabPicker(selectedTab: $selectedTab)
                .padding(.horizontal, .dsLG)
                .padding(.bottom, .dsLG)

            Rectangle()
                .fill(Color.dsSeparator)
                .frame(height: 0.5)

            ScrollView {
                switch selectedTab {
                case .info: InspectorInfoView(viewModel: viewModel)
                case .tags: InspectorTagsView(viewModel: viewModel)
                case .comments: InspectorWorkspaceCommentsView(viewModel: viewModel)
                case .markup: InspectorMarkupView(viewModel: viewModel)
                }
            }
        }
        .background(Color.dsSurface)
    }
}

private struct InspectorTabPicker: View {
    @Binding var selectedTab: InspectorView.Tab

    private let columns = [
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(InspectorView.Tab.allCases, id: \.self) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.iconName)
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 14, height: 14)
                        Text(tab.rawValue)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    .foregroundStyle(selectedTab == tab ? Color.white : Color.dsTextSecondary)
                    .frame(maxWidth: .infinity, minHeight: 32)
                    .padding(.horizontal, 8)
                    .background {
                        RoundedRectangle(cornerRadius: .dsRadiusSm, style: .continuous)
                            .fill(selectedTab == tab ? Color.dsAccent : Color.clear)
                    }
                    .contentShape(RoundedRectangle(cornerRadius: .dsRadiusSm, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color.dsCard.opacity(0.74), in: RoundedRectangle(cornerRadius: .dsRadiusMd, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: .dsRadiusMd, style: .continuous)
                .strokeBorder(Color.dsSeparator, lineWidth: 1)
        }
    }
}

// MARK: - Info tab

private struct InspectorInfoView: View {
    var viewModel: WorkspaceViewModel

    private var visualSignatureCount: Int {
        viewModel.document.workspace.signatures.filter { !$0.isCryptographic }.count
    }

    private var digitalSignatureCount: Int {
        viewModel.document.workspace.signatures.filter(\.isCryptographic).count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: .dsLG) {
            InspectorRow(label: "Documents",   value: "\(viewModel.document.workspace.documents.count)")
            InspectorRow(label: "Total pages", value: "\(viewModel.document.workspace.pageOrder.count)")
            InspectorRow(label: "Signatures",  value: "\(viewModel.document.workspace.signatures.count)")
            InspectorRow(label: "Visual",      value: "\(visualSignatureCount)")
            InspectorRow(label: "Digital",     value: "\(digitalSignatureCount)")
            InspectorRow(label: "Tags",        value: "\(viewModel.document.workspace.tags.count)")
            InspectorRow(label: "Comments",    value: "\(viewModel.document.workspace.comments.count)")
            InspectorRow(label: "Created",     value: viewModel.document.workspace.createdAt.formatted(
                date: .abbreviated, time: .omitted))
        }
        .padding(.horizontal, .dsLG)
        .padding(.vertical, .dsXL)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct InspectorRow: View {
    var label: String
    var value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.dsTextTertiary)
                .tracking(0.5)
            Text(value)
                .font(.dsBody())
                .foregroundStyle(Color.dsTextPrimary)
        }
    }
}

// MARK: - Tags tab

private struct InspectorTagsView: View {
    @Bindable var viewModel: WorkspaceViewModel
    @State private var draftTag = ""

    var body: some View {
        VStack(alignment: .leading, spacing: .dsMD) {
            HStack(spacing: .dsSM) {
                TextField("Add tag", text: $draftTag)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addTag)
                Button(action: addTag) {
                    Image(systemName: "plus")
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.dsAccent)
                .disabled(draftTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help("Add tag")
            }

            if viewModel.document.workspace.tags.isEmpty {
                InspectorEmptyState(icon: "tag", title: "No tags yet.")
            } else {
                LazyVStack(alignment: .leading, spacing: .dsSM) {
                    ForEach(viewModel.document.workspace.tags, id: \.self) { tag in
                        TagChip(tag: tag) {
                            viewModel.removeTag(tag)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, .dsLG)
        .padding(.vertical, .dsXL)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func addTag() {
        viewModel.addTag(draftTag)
        draftTag = ""
    }
}

private struct TagChip: View {
    var tag: String
    var onRemove: () -> Void

    var body: some View {
        HStack(spacing: 5) {
            Text(tag)
                .font(.dsCaption())
                .foregroundStyle(Color.dsTextPrimary)
                .lineLimit(1)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .frame(width: 12, height: 12)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.dsTextTertiary)
            .help("Remove tag")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.dsAccentSoft, in: Capsule())
    }
}

// MARK: - Workspace comments tab

private struct InspectorWorkspaceCommentsView: View {
    @Bindable var viewModel: WorkspaceViewModel
    @State private var draftComment = ""

    var body: some View {
        VStack(alignment: .leading, spacing: .dsMD) {
            TextEditor(text: $draftComment)
                .font(.dsBody())
                .frame(minHeight: 96)
                .scrollContentBackground(.hidden)
                .background(Color.dsCard)
                .clipShape(RoundedRectangle(cornerRadius: .dsRadiusSm, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: .dsRadiusSm, style: .continuous)
                        .strokeBorder(Color.dsSeparator, lineWidth: 1)
                }

            Button {
                viewModel.addComment(draftComment)
                draftComment = ""
            } label: {
                Label("Add Comment", systemImage: "text.bubble")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 32)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.dsAccent)
            .disabled(draftComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if viewModel.document.workspace.comments.isEmpty {
                InspectorEmptyState(icon: "text.bubble", title: "No comments yet.")
            } else {
                LazyVStack(alignment: .leading, spacing: .dsSM) {
                    ForEach(viewModel.document.workspace.comments) { comment in
                        WorkspaceCommentRow(comment: comment) {
                            viewModel.removeComment(comment)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, .dsLG)
        .padding(.vertical, .dsXL)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct WorkspaceCommentRow: View {
    var comment: WorkspaceComment
    var onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: .dsSM) {
            HStack(alignment: .firstTextBaseline) {
                Text(comment.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.dsTextTertiary)
                Spacer()
                Button(action: onRemove) {
                    Image(systemName: "trash")
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.dsTextTertiary)
                .help("Delete comment")
            }
            Text(comment.body)
                .font(.dsBody())
                .foregroundStyle(Color.dsTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.dsMD)
        .background(Color.dsCard, in: RoundedRectangle(cornerRadius: .dsRadiusSm, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: .dsRadiusSm, style: .continuous)
                .strokeBorder(Color.dsSeparator, lineWidth: 1)
        }
    }
}

// MARK: - Markup tab

private struct InspectorMarkupView: View {
    var viewModel: WorkspaceViewModel

    private var allAnnotations: [(page: PDFPage, annotation: PDFAnnotation, memberName: String)] {
        var result: [(PDFPage, PDFAnnotation, String)] = []
        for (member, pdf) in viewModel.loadedPDFs {
            for i in 0..<pdf.pageCount {
                guard let page = pdf.page(at: i) else { continue }
                for ann in page.annotations { result.append((page, ann, member.displayName)) }
            }
        }
        return result
    }

    var body: some View {
        if allAnnotations.isEmpty && viewModel.selectedAnnotation == nil {
            VStack(spacing: .dsSM) {
                Image(systemName: "highlighter")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(Color.dsTextTertiary)
                Text("No annotations yet.")
                    .font(.dsBody())
                    .foregroundStyle(Color.dsTextSecondary)
                Text("Use the toolbar to highlight,\nadd notes, or draw.")
                    .font(.dsCaption())
                    .foregroundStyle(Color.dsTextTertiary)
                    .multilineTextAlignment(.center)
            }
            .padding(.dsXXL)
            .frame(maxWidth: .infinity)
        } else {
            LazyVStack(alignment: .leading, spacing: 0) {
                if let selected = viewModel.selectedAnnotation {
                    InspectorEditingDetails(ann: selected)
                    Rectangle().fill(Color.dsSeparator).frame(height: 0.5)
                }
                ForEach(allAnnotations.indices, id: \.self) { i in
                    InspectorAnnotationRow(ann: allAnnotations[i].annotation,
                                          memberName: allAnnotations[i].memberName)
                    Rectangle().fill(Color.dsSeparator).frame(height: 0.5)
                }
            }
            .padding(.vertical, .dsXS)
        }
    }
}

private struct InspectorEditingDetails: View {
    var ann: PDFAnnotation

    private var isEditableText: Bool { ann.type == "FreeText" || ann.type == "Text" }

    var body: some View {
        VStack(alignment: .leading, spacing: .dsSM) {
            HStack(spacing: .dsSM) {
                Image(systemName: "slider.horizontal.3")
                    .foregroundStyle(Color.dsAccent)
                Text("Editing")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.dsTextPrimary)
                Spacer()
            }

            InspectorDetailLine(label: "Type", value: ann.type ?? "Annotation")
            InspectorDetailLine(label: "Bounds", value: "\(Int(ann.bounds.width)) x \(Int(ann.bounds.height))")
            if let font = ann.font {
                InspectorDetailLine(label: "Font", value: "\(font.displayName ?? font.familyName ?? "Font") \(Int(round(font.pointSize)))")
            }
            InspectorDetailLine(label: "Mode", value: isEditableText ? "Editable annotation" : "Markup annotation")
        }
        .padding(.horizontal, .dsMD)
        .padding(.vertical, .dsMD)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.dsAccentSoft.opacity(0.35))
    }
}

private struct InspectorDetailLine: View {
    var label: String
    var value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Color.dsTextTertiary)
                .frame(width: 54, alignment: .leading)
            Text(value)
                .font(.dsCaption())
                .foregroundStyle(Color.dsTextSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct InspectorEmptyState: View {
    var icon: String
    var title: String

    var body: some View {
        VStack(spacing: .dsSM) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(Color.dsTextTertiary)
            Text(title)
                .font(.dsBody())
                .foregroundStyle(Color.dsTextSecondary)
        }
        .padding(.dsXL)
        .frame(maxWidth: .infinity)
    }
}

private struct InspectorAnnotationRow: View {
    var ann: PDFAnnotation
    var memberName: String

    private var typeLabel: String {
        switch ann.type {
        case "Highlight": return "Highlight"
        case "Text":      return "Note"
        case "Ink":       return "Ink"
        case "FreeText":  return "Text Box"
        case "Underline": return "Underline"
        case "StrikeOut": return "Strikeout"
        default:          return ann.type ?? "Annotation"
        }
    }

    private var icon: String {
        switch ann.type {
        case "Highlight": return "highlighter"
        case "Text":      return "note.text"
        case "Ink":       return "pencil.tip"
        case "Underline": return "underline"
        case "StrikeOut": return "strikethrough"
        default:          return "pencil.and.outline"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: .dsSM) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(Color.dsTextTertiary)
                .frame(width: 16)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(typeLabel)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.dsTextPrimary)
                if let contents = ann.contents, !contents.isEmpty {
                    Text(contents)
                        .font(.dsCaption())
                        .foregroundStyle(Color.dsTextSecondary)
                        .lineLimit(2)
                }
                Text(memberName)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.dsTextTertiary)
            }
        }
        .padding(.horizontal, .dsMD)
        .padding(.vertical, .dsSM)
    }
}
