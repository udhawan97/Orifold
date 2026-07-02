import SwiftUI
import PDFKit
import AppKit

struct InspectorView: View {
    @Bindable var viewModel: WorkspaceViewModel
    @Binding var selectedTab: Tab

    enum Tab: String, CaseIterable {
        case info = "Info"
        case tags = "Tags"
        case comments = "Comments"
        case markup = "Markup"
        case decorate = "Decorate"

        var iconName: String {
            switch self {
            case .info: return "info.circle"
            case .tags: return "tag"
            case .comments: return "text.bubble"
            case .markup: return "highlighter"
            case .decorate: return "paintbrush.pointed"
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
                case .decorate: InspectorDecorateView(viewModel: viewModel)
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
                    .foregroundStyle(selectedTab == tab ? Color.dsSurface : Color.dsTextSecondary)
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
            InspectorRow(label: "Comments",    value: "\(viewModel.totalCommentCount)")
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

    private var workspaceComments: [WorkspaceComment] {
        viewModel.filteredWorkspaceComments
    }

    private var allWorkspaceComments: [WorkspaceComment] {
        viewModel.document.workspace.comments
    }

    private var noteComments: [WorkspaceViewModel.PDFNoteComment] {
        viewModel.pdfNoteComments
    }

    private var hasComments: Bool {
        !allWorkspaceComments.isEmpty || !noteComments.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: .dsMD) {
            InspectorTextEditor(
                text: $draftComment,
                placeholder: "Write a comment...",
                minHeight: 96,
                background: Color.dsCard,
                font: .dsBody()
            )
            .accessibilityLabel("Comment")

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

            Picker("Comment filter", selection: $viewModel.commentFilter) {
                Text("Open").tag(WorkspaceViewModel.CommentFilter.open)
                Text("Resolved").tag(WorkspaceViewModel.CommentFilter.resolved)
                Text("All").tag(WorkspaceViewModel.CommentFilter.all)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if !hasComments {
                InspectorEmptyState(icon: "text.bubble", title: "No comments yet.")
            } else {
                LazyVStack(alignment: .leading, spacing: .dsMD) {
                    if !workspaceComments.isEmpty {
                        InspectorSectionHeader(title: "Workspace", count: workspaceComments.count)
                        ForEach(workspaceComments) { comment in
                            WorkspaceCommentRow(viewModel: viewModel, comment: comment)
                        }
                    } else if !allWorkspaceComments.isEmpty {
                        InspectorEmptyState(icon: "line.3.horizontal.decrease.circle", title: "No matching comments.")
                    }

                    if !noteComments.isEmpty {
                        InspectorSectionHeader(title: "PDF Notes", count: noteComments.count)
                        ForEach(noteComments) { note in
                            PDFNoteCommentRow(note: note) {
                                viewModel.jumpToNoteComment(note)
                            } onRemove: {
                                viewModel.removeNoteComment(note)
                            }
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

private struct InspectorSectionHeader: View {
    var title: String
    var count: Int

    var body: some View {
        HStack(spacing: .dsXS) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.dsTextTertiary)
            Text("\(count)")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.dsTextSecondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.dsAccentSoft, in: Capsule())
        }
        .padding(.top, .dsXS)
    }
}

private struct InspectorTextEditor: View {
    @Binding var text: String
    var placeholder: String
    var minHeight: CGFloat
    var background: Color
    var font: Font
    var focusOnAppear = false
    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $text)
                .font(font)
                .foregroundStyle(Color.dsTextPrimary)
                .tint(Color.dsAccent)
                .scrollContentBackground(.hidden)
                .padding(.vertical, 8)
                .focused($isFocused)

            if text.isEmpty {
                Text(placeholder)
                    .font(font)
                    .foregroundStyle(Color.dsTextTertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 8)
                    .allowsHitTesting(false)
            }
        }
        .frame(minHeight: minHeight)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: .dsRadiusSm, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: .dsRadiusSm, style: .continuous)
                .strokeBorder(Color.dsSeparator, lineWidth: 1)
        }
        .onAppear {
            if focusOnAppear {
                isFocused = true
            }
        }
    }
}

private struct WorkspaceCommentRow: View {
    @Bindable var viewModel: WorkspaceViewModel
    var comment: WorkspaceComment
    @State private var isEditing = false
    @State private var draftBody = ""
    @State private var draftTag = ""

    private let colorChoices: [(label: String, hex: String, color: Color)] = [
        ("Dark", "#1F2933", Color.dsTextPrimary),
        ("Blue", "#1D6FA3", Color.dsAccent),
        ("Red", "#B42318", Color.dsAnnotationCoral),
        ("Green", "#087443", Color.dsAnnotationSage),
        ("Violet", "#6941C6", Color.dsAnnotationLavender)
    ]

    private var displayedBody: String {
        isEditing ? draftBody : comment.body
    }

    var body: some View {
        VStack(alignment: .leading, spacing: .dsSM) {
            HStack(alignment: .firstTextBaseline) {
                Text(relativeTimestamp(for: comment.createdAt))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.dsTextTertiary)
                    .help(comment.createdAt.formatted(date: .complete, time: .shortened))
                Spacer()
                Toggle(isOn: Binding(
                    get: { comment.isResolved },
                    set: { viewModel.updateCommentResolved(comment, isResolved: $0) }
                )) {
                    Image(systemName: comment.isResolved ? "checkmark.circle.fill" : "circle")
                        .frame(width: 16, height: 16)
                }
                .toggleStyle(.button)
                .buttonStyle(.plain)
                .foregroundStyle(comment.isResolved ? Color.dsAccent : Color.dsTextTertiary)
                .help(comment.isResolved ? "Mark open" : "Mark resolved")

                Button {
                    draftBody = comment.body
                    isEditing.toggle()
                } label: {
                    Image(systemName: isEditing ? "xmark" : "square.and.pencil")
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.dsTextTertiary)
                .help(isEditing ? "Cancel edit" : "Edit comment")

                Button {
                    viewModel.removeComment(comment)
                } label: {
                    Image(systemName: "trash")
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.dsTextTertiary)
                .help("Delete comment")
            }

            if let subtitle = viewModel.anchorSubtitle(for: comment) {
                Button {
                    viewModel.jumpToComment(comment)
                } label: {
                    HStack(spacing: .dsXS) {
                        Image(systemName: comment.anchor == nil ? "exclamationmark.circle" : "arrowshape.turn.up.right")
                            .frame(width: 14, height: 14)
                        Text(subtitle)
                            .lineLimit(1)
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(comment.anchor == nil ? Color.dsTextTertiary : Color.dsAccent)
                }
                .buttonStyle(.plain)
                .disabled(comment.anchor == nil)
                .help(comment.anchor == nil ? "The anchored page was removed" : "Jump to anchor")
            }

            if isEditing {
                InspectorTextEditor(
                    text: $draftBody,
                    placeholder: "Edit comment...",
                    minHeight: 76,
                    background: Color.dsSurface,
                    font: .system(size: commentFontSize(for: comment.style.textSize)),
                    focusOnAppear: viewModel.selectedCommentID == comment.id
                )
                .accessibilityLabel("Edit comment")
                Button {
                    viewModel.updateCommentBody(comment, body: draftBody)
                    isEditing = false
                } label: {
                    Label("Save", systemImage: "checkmark")
                        .frame(maxWidth: .infinity, minHeight: 28)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.dsAccent)
                .disabled(draftBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } else {
                Text(displayedBody)
                    .font(.system(
                        size: commentFontSize(for: comment.style.textSize),
                        weight: comment.style.isBold ? .semibold : .regular
                    ))
                    .italic(comment.style.isItalic)
                    .foregroundStyle(displayColor(fromHex: comment.style.colorHex))
                    .fixedSize(horizontal: false, vertical: true)
            }

            commentFormatControls
            commentTags
        }
        .padding(.dsMD)
        .background(Color.dsCard, in: RoundedRectangle(cornerRadius: .dsRadiusSm, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: .dsRadiusSm, style: .continuous)
                .strokeBorder(viewModel.selectedCommentID == comment.id ? Color.dsAccent : Color.dsSeparator, lineWidth: viewModel.selectedCommentID == comment.id ? 1.5 : 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: .dsRadiusSm, style: .continuous))
        .onTapGesture {
            viewModel.selectedCommentID = comment.id
        }
        .onAppear {
            if draftBody.isEmpty {
                draftBody = comment.body
            }
            if comment.body.isEmpty && viewModel.selectedCommentID == comment.id {
                isEditing = true
            }
        }
        .onChange(of: comment.body) { _, newValue in
            if !isEditing {
                draftBody = newValue
            }
        }
    }

    private var commentFormatControls: some View {
        HStack(spacing: .dsSM) {
            Button {
                var style = comment.style
                style.isBold.toggle()
                viewModel.updateCommentStyle(comment, style: style)
            } label: {
                Image(systemName: "bold")
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(comment.style.isBold ? Color.dsAccent : Color.dsTextTertiary)
            .help("Bold")

            Button {
                var style = comment.style
                style.isItalic.toggle()
                viewModel.updateCommentStyle(comment, style: style)
            } label: {
                Image(systemName: "italic")
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(comment.style.isItalic ? Color.dsAccent : Color.dsTextTertiary)
            .help("Italic")

            Menu {
                ForEach(WorkspaceCommentTextSize.allCases) { size in
                    Button(commentTextSizeLabel(size)) {
                        var style = comment.style
                        style.textSize = size
                        viewModel.updateCommentStyle(comment, style: style)
                    }
                }
            } label: {
                Image(systemName: "textformat.size")
                    .frame(width: 18, height: 18)
            }
            .menuStyle(.borderlessButton)
            .help("Text size")

            Menu {
                ForEach(colorChoices, id: \.hex) { choice in
                    Button(choice.label) {
                        var style = comment.style
                        style.colorHex = choice.hex
                        viewModel.updateCommentStyle(comment, style: style)
                    }
                }
            } label: {
                Circle()
                    .fill(color(fromHex: comment.style.colorHex))
                    .frame(width: 14, height: 14)
                    .overlay(Circle().strokeBorder(Color.dsSeparator, lineWidth: 1))
                    .frame(width: 18, height: 18)
            }
            .menuStyle(.borderlessButton)
            .help("Text color")

            Spacer()
        }
    }

    private var commentTags: some View {
        VStack(alignment: .leading, spacing: .dsSM) {
            if !comment.tags.isEmpty {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(comment.tags, id: \.self) { tag in
                        TagChip(tag: tag) {
                            viewModel.removeTag(tag, from: comment)
                        }
                    }
                }
            }
            HStack(spacing: .dsSM) {
                TextField("Add tag", text: $draftTag)
                    .textFieldStyle(.roundedBorder)
                    .font(.dsCaption())
                    .onSubmit(addCommentTag)

                Menu {
                    ForEach(tagSuggestions, id: \.self) { tag in
                        Button(tag) {
                            viewModel.addTag(tag, to: comment)
                            draftTag = ""
                        }
                    }
                } label: {
                    Image(systemName: "tag")
                        .frame(width: 16, height: 16)
                }
                .menuStyle(.borderlessButton)
                .disabled(tagSuggestions.isEmpty)
                .help("Tag suggestions")

                Button(action: addCommentTag) {
                    Image(systemName: "plus")
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.bordered)
                .disabled(draftTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help("Add tag to comment")
            }
        }
    }

    private var tagSuggestions: [String] {
        viewModel.usedCommentTags.filter { suggestion in
            !comment.tags.contains { existing in
                existing.localizedCaseInsensitiveCompare(suggestion) == .orderedSame
            }
        }
    }

    private func addCommentTag() {
        viewModel.addTag(draftTag, to: comment)
        draftTag = ""
    }

    private func commentTextSizeLabel(_ size: WorkspaceCommentTextSize) -> String {
        switch size {
        case .small: return "Small"
        case .regular: return "Regular"
        case .large: return "Large"
        }
    }

    private func commentFontSize(for size: WorkspaceCommentTextSize) -> CGFloat {
        switch size {
        case .small: return 11
        case .regular: return 13
        case .large: return 16
        }
    }

    private func relativeTimestamp(for date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()
        if calendar.isDateInYesterday(date) {
            return "Yesterday"
        }
        if let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day,
           days >= 7 {
            return date.formatted(.dateTime.month(.abbreviated).day())
        }
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 60 {
            return "Just now"
        }
        if seconds < 3_600 {
            return "\(Int(seconds / 60))m ago"
        }
        if seconds < 86_400 {
            return "\(Int(seconds / 3_600))h ago"
        }
        return "\(Int(seconds / 86_400))d ago"
    }

    private func color(fromHex value: String) -> Color {
        guard let nsColor = nsColor(fromHex: value) else { return Color.dsTextPrimary }
        return Color(nsColor: nsColor)
    }

    private func displayColor(fromHex value: String) -> Color {
        value.trimmingCharacters(in: .whitespacesAndNewlines).localizedCaseInsensitiveCompare("#1F2933") == .orderedSame
            ? Color.dsTextPrimary
            : color(fromHex: value)
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
}

private struct PDFNoteCommentRow: View {
    var note: WorkspaceViewModel.PDFNoteComment
    var onJump: () -> Void
    var onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: .dsSM) {
            HStack(alignment: .firstTextBaseline) {
                Label("Page \(note.pageNumber)", systemImage: "note.text")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.dsTextTertiary)
                Spacer()
                Button(action: onJump) {
                    Image(systemName: "arrowshape.turn.up.right")
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.dsTextTertiary)
                .help("Show note")

                Button(action: onRemove) {
                    Image(systemName: "trash")
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.dsTextTertiary)
                .help("Delete note")
            }

            Text(note.body)
                .font(.dsBody())
                .foregroundStyle(Color.dsTextPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text(note.memberName)
                .font(.system(size: 11))
                .foregroundStyle(Color.dsTextTertiary)
                .lineLimit(1)
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

private struct InspectorDecorateView: View {
    @Bindable var viewModel: WorkspaceViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shouldReduceMotion: Bool {
        reduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private var watermarkEnabled: Binding<Bool> {
        Binding(
            get: { viewModel.isDecorationEnabled(.watermark) },
            set: { viewModel.setDecoration(.watermark, enabled: $0) }
        )
    }

    private var pageNumbersEnabled: Binding<Bool> {
        Binding(
            get: { viewModel.isDecorationEnabled(.pageNumber) },
            set: { viewModel.setDecoration(.pageNumber, enabled: $0) }
        )
    }

    private var batesEnabled: Binding<Bool> {
        Binding(
            get: { viewModel.isDecorationEnabled(.bates) },
            set: { viewModel.setDecoration(.bates, enabled: $0) }
        )
    }

    private var watermarkText: Binding<String> {
        Binding(
            get: { viewModel.decorationText(for: .watermark) },
            set: { viewModel.setDecorationText(.watermark, text: $0) }
        )
    }

    private var batesPrefix: Binding<String> {
        Binding(
            get: { viewModel.decorationPrefix(for: .bates) },
            set: { viewModel.setDecorationPrefix(.bates, prefix: $0) }
        )
    }

    private var batesStartNumber: Binding<Int> {
        Binding(
            get: { viewModel.decorationStartNumber(for: .bates) },
            set: { viewModel.setDecorationStartNumber(.bates, startNumber: $0) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            decorationRow(title: "Watermark", isOn: watermarkEnabled) {
                TextField("Text", text: watermarkText)
                    .textFieldStyle(.roundedBorder)
            }

            Rectangle().fill(Color.dsSeparator).frame(height: 0.5)

            decorationRow(title: "Page numbers", isOn: pageNumbersEnabled) {
                Text("Page 1 of \(max(viewModel.pageCount, 1))")
                    .font(.dsCaption())
                    .foregroundStyle(Color.dsTextSecondary)
            }

            Rectangle().fill(Color.dsSeparator).frame(height: 0.5)

            decorationRow(title: "Bates stamp", isOn: batesEnabled) {
                VStack(alignment: .leading, spacing: .dsSM) {
                    TextField("Prefix", text: batesPrefix)
                        .textFieldStyle(.roundedBorder)
                    Stepper(value: batesStartNumber, in: 0...999_999) {
                        Text("Start number \(viewModel.decorationStartNumber(for: .bates))")
                            .font(.dsCaption())
                            .foregroundStyle(Color.dsTextSecondary)
                    }
                }
            }
        }
        .padding(.vertical, .dsXS)
    }

    private func decorationRow<Controls: View>(title: String,
                                               isOn: Binding<Bool>,
                                               @ViewBuilder controls: () -> Controls) -> some View {
        VStack(alignment: .leading, spacing: .dsSM) {
            Toggle(title, isOn: isOn)
                .toggleStyle(.checkbox)
                .font(.dsBody())
                .foregroundStyle(Color.dsTextPrimary)

            if isOn.wrappedValue {
                controls()
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, .dsLG)
        .padding(.vertical, .dsMD)
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(shouldReduceMotion ? nil : .easeInOut(duration: 0.16), value: isOn.wrappedValue)
    }
}

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
