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
        case ocr = "OCR"

        var iconName: String {
            switch self {
            case .info: return "info.circle"
            case .tags: return "tag"
            case .comments: return "text.bubble"
            case .markup: return "highlighter"
            case .decorate: return "paintbrush.pointed"
            case .ocr: return "doc.text.viewfinder"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("inspector.title")
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
                case .ocr: InspectorOCRView(viewModel: viewModel)
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
                .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
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
                TextField("inspector.tags.addTag.placeholder", text: $draftTag)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addTag)
                Button(action: addTag) {
                    Image(systemName: "plus")
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.dsAccent)
                .disabled(draftTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help("inspector.tags.addTag.help")
            }

            if viewModel.document.workspace.tags.isEmpty {
                InspectorEmptyState(icon: "tag", title: "inspector.tags.empty")
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
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Color.dsTextTertiary)
            .help("inspector.tags.removeTag.help")
        }
        .padding(.leading, 8)
        .padding(.trailing, 4)
        .padding(.vertical, 3)
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
                placeholder: viewModel.isReaderMode ? "inspector.comments.studyNote.placeholder" : "inspector.comments.comment.placeholder",
                minHeight: 96,
                background: Color.dsCard,
                font: .dsBody()
            )
            .accessibilityLabel(viewModel.isReaderMode ? "inspector.comments.studyNote.accessibilityLabel" : "inspector.comments.comment.accessibilityLabel")

            Button {
                viewModel.addComment(draftComment)
                draftComment = ""
            } label: {
                Label(viewModel.isReaderMode ? "inspector.comments.saveNote.button" : "inspector.comments.addComment.button", systemImage: "text.bubble")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 32)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.dsAccent)
            .disabled(draftComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Picker("inspector.comments.filter.picker", selection: $viewModel.commentFilter) {
                Text("inspector.comments.filter.open").tag(WorkspaceViewModel.CommentFilter.open)
                Text("inspector.comments.filter.resolved").tag(WorkspaceViewModel.CommentFilter.resolved)
                Text("inspector.comments.filter.all").tag(WorkspaceViewModel.CommentFilter.all)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if !hasComments {
                InspectorEmptyState(icon: "text.bubble", title: "inspector.comments.empty")
            } else {
                LazyVStack(alignment: .leading, spacing: .dsMD) {
                    if !workspaceComments.isEmpty {
                        InspectorSectionHeader(title: "Workspace", count: workspaceComments.count)
                        ForEach(workspaceComments) { comment in
                            WorkspaceCommentRow(viewModel: viewModel, comment: comment)
                        }
                    } else if !allWorkspaceComments.isEmpty {
                        InspectorEmptyState(icon: "line.3.horizontal.decrease.circle", title: "inspector.comments.noMatching")
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
    var placeholder: LocalizedStringKey
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
    // Passed into L10n.string() below so this view's `body` actually reads it —
    // SwiftUI only re-invokes `body` on a locale change for views that read
    // `\.locale` during the previous evaluation.
    @Environment(\.locale) private var locale

    private let colorChoices: [(label: String, hex: String, color: Color)] = [
        ("Dark", "#1F2933", Color.dsTextPrimary),
        ("Blue", "#1D6FA3", Color.dsAccent),
        ("Red", "#B42318", Color.dsAnnotationCoral),
        ("Green", "#087443", Color.dsAnnotationSage),
        ("Violet", "#6941C6", Color.dsAnnotationLavender)
    ]

    private var displayedBody: String {
        isEditing ? draftBody : liveComment.body
    }

    private var liveComment: WorkspaceComment {
        _ = viewModel.commentRevision
        return viewModel.document.workspace.comments.first { $0.id == comment.id } ?? comment
    }

    var body: some View {
        let current = liveComment
        VStack(alignment: .leading, spacing: .dsSM) {
            HStack(alignment: .firstTextBaseline) {
                Text(relativeTimestamp(for: current.createdAt, locale: locale))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.dsTextTertiary)
                    .help(current.createdAt.formatted(date: .complete, time: .shortened))
                Spacer()
                Toggle(isOn: Binding(
                    get: { liveComment.isResolved },
                    set: { viewModel.updateCommentResolved(liveComment, isResolved: $0) }
                )) {
                    Image(systemName: current.isResolved ? "checkmark.circle.fill" : "circle")
                        .frame(width: 24, height: 24)
                }
                .toggleStyle(.button)
                .buttonStyle(.borderless)
                .foregroundStyle(current.isResolved ? Color.dsAccent : Color.dsTextTertiary)
                .help(current.isResolved ? "inspector.comments.markOpen.help" : "inspector.comments.markResolved.help")

                Button {
                    draftBody = liveComment.body
                    isEditing.toggle()
                } label: {
                    Image(systemName: isEditing ? "xmark" : "square.and.pencil")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Color.dsTextTertiary)
                .help(isEditing ? "inspector.comments.cancelEdit.help" : "inspector.comments.editComment.help")

                Button {
                    viewModel.removeComment(liveComment)
                } label: {
                    Image(systemName: "trash")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Color.dsTextTertiary)
                .help("inspector.comments.deleteComment.help")
            }

            if let subtitle = viewModel.anchorSubtitle(for: current) {
                Button {
                    viewModel.jumpToComment(liveComment)
                } label: {
                    HStack(spacing: .dsXS) {
                        Image(systemName: current.anchor == nil ? "exclamationmark.circle" : "arrowshape.turn.up.right")
                            .frame(width: 14, height: 14)
                        Text(subtitle)
                            .lineLimit(1)
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(current.anchor == nil ? Color.dsTextTertiary : Color.dsAccent)
                }
                .buttonStyle(.plain)
                .disabled(current.anchor == nil)
                .help(current.anchor == nil ? "inspector.comments.anchorRemoved.help" : "inspector.comments.jumpToAnchor.help")
            }

            if isEditing {
                InspectorTextEditor(
                    text: $draftBody,
                    placeholder: "inspector.textEdit.editComment.placeholder",
                    minHeight: 76,
                    background: Color.dsSurface,
                    font: .system(size: commentFontSize(for: current.style.textSize)),
                    focusOnAppear: viewModel.selectedCommentID == current.id
                )
                .accessibilityLabel("inspector.textEdit.editComment.accessibilityLabel")
                Button {
                    viewModel.updateCommentBody(liveComment, body: draftBody)
                    isEditing = false
                } label: {
                    Label("inspector.comments.save.button", systemImage: "checkmark")
                        .frame(maxWidth: .infinity, minHeight: 28)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.dsAccent)
                .disabled(draftBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } else {
                Text(displayedBody)
                    .font(.system(
                        size: commentFontSize(for: current.style.textSize),
                        weight: current.style.isBold ? .semibold : .regular
                    ))
                    .italic(current.style.isItalic)
                    .foregroundStyle(displayColor(fromHex: current.style.colorHex))
                    .fixedSize(horizontal: false, vertical: true)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.selectedCommentID = liveComment.id
                    }
            }

            commentFormatControls
            commentTags
        }
        .padding(.dsMD)
        .background(Color.dsCard, in: RoundedRectangle(cornerRadius: .dsRadiusSm, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: .dsRadiusSm, style: .continuous)
                .strokeBorder(viewModel.selectedCommentID == current.id ? Color.dsAccent : Color.dsSeparator, lineWidth: viewModel.selectedCommentID == current.id ? 1.5 : 1)
        }
        .onAppear {
            if draftBody.isEmpty {
                draftBody = liveComment.body
            }
            if liveComment.body.isEmpty && viewModel.selectedCommentID == liveComment.id {
                isEditing = true
            }
        }
        .onChange(of: liveComment.body) { _, newValue in
            if !isEditing {
                draftBody = newValue
            }
        }
    }

    private var commentFormatControls: some View {
        HStack(spacing: .dsSM) {
            Button {
                var style = liveComment.style
                style.isBold.toggle()
                viewModel.updateCommentStyle(liveComment, style: style)
            } label: {
                Image(systemName: "bold")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(liveComment.style.isBold ? Color.dsAccent : Color.dsTextTertiary)
            .help("inspector.comments.format.bold.help")

            Button {
                var style = liveComment.style
                style.isItalic.toggle()
                viewModel.updateCommentStyle(liveComment, style: style)
            } label: {
                Image(systemName: "italic")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(liveComment.style.isItalic ? Color.dsAccent : Color.dsTextTertiary)
            .help("inspector.comments.format.italic.help")

            Menu {
                ForEach(WorkspaceCommentTextSize.allCases) { size in
                    Button(commentTextSizeLabel(size, locale: locale)) {
                        var style = liveComment.style
                        style.textSize = size
                        viewModel.updateCommentStyle(liveComment, style: style)
                    }
                }
            } label: {
                Image(systemName: "textformat.size")
                    .frame(width: 24, height: 24)
            }
            .menuStyle(.borderlessButton)
            .help("inspector.comments.format.textSize.help")

            Menu {
                ForEach(colorChoices, id: \.hex) { choice in
                    Button(choice.label) {
                        var style = liveComment.style
                        style.colorHex = choice.hex
                        viewModel.updateCommentStyle(liveComment, style: style)
                    }
                }
            } label: {
                Circle()
                    .fill(color(fromHex: liveComment.style.colorHex))
                    .frame(width: 14, height: 14)
                    .overlay(Circle().strokeBorder(Color.dsSeparator, lineWidth: 1))
                    .frame(width: 24, height: 24)
            }
            .menuStyle(.borderlessButton)
            .help("inspector.comments.format.textColor.help")

            Spacer()
        }
    }

    private var commentTags: some View {
        VStack(alignment: .leading, spacing: .dsSM) {
            if !liveComment.tags.isEmpty {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(liveComment.tags, id: \.self) { tag in
                        TagChip(tag: tag) {
                            viewModel.removeTag(tag, from: liveComment)
                        }
                    }
                }
            }
            HStack(spacing: .dsSM) {
                TextField("inspector.comments.addTag.placeholder", text: $draftTag)
                    .textFieldStyle(.roundedBorder)
                    .font(.dsCaption())
                    .onSubmit(addCommentTag)

                Menu {
                    ForEach(tagSuggestions, id: \.self) { tag in
                        Button(tag) {
                            viewModel.addTag(tag, to: liveComment)
                            draftTag = ""
                        }
                    }
                } label: {
                    Image(systemName: "tag")
                        .frame(width: 24, height: 24)
                }
                .menuStyle(.borderlessButton)
                .disabled(tagSuggestions.isEmpty)
                .help("inspector.comments.tagSuggestions.help")

                Button(action: addCommentTag) {
                    Image(systemName: "plus")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.bordered)
                .disabled(draftTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help("inspector.comments.addTagToComment.help")
            }
        }
    }

    private var tagSuggestions: [String] {
        viewModel.usedCommentTags.filter { suggestion in
            !liveComment.tags.contains { existing in
                existing.localizedCaseInsensitiveCompare(suggestion) == .orderedSame
            }
        }
    }

    private func addCommentTag() {
        viewModel.addTag(draftTag, to: liveComment)
        draftTag = ""
    }

    private func commentTextSizeLabel(_ size: WorkspaceCommentTextSize, locale: Locale) -> String {
        switch size {
        case .small: return L10n.string("inspector.commentTextSize.small.label", locale: locale)
        case .regular: return L10n.string("inspector.commentTextSize.regular.label", locale: locale)
        case .large: return L10n.string("inspector.commentTextSize.large.label", locale: locale)
        }
    }

    private func commentFontSize(for size: WorkspaceCommentTextSize) -> CGFloat {
        switch size {
        case .small: return 11
        case .regular: return 13
        case .large: return 16
        }
    }

    private func relativeTimestamp(for date: Date, locale: Locale) -> String {
        let calendar = Calendar.current
        let now = Date()
        if calendar.isDateInYesterday(date) {
            return L10n.string("inspector.relativeTime.yesterday", locale: locale)
        }
        if let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day,
           days >= 7 {
            return date.formatted(.dateTime.month(.abbreviated).day())
        }
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 60 {
            return L10n.string("inspector.relativeTime.justNow", locale: locale)
        }
        if seconds < 3_600 {
            let minutes = Int(seconds / 60)
            return String(localized: "\(minutes)m ago", locale: locale)
        }
        if seconds < 86_400 {
            let hours = Int(seconds / 3_600)
            return String(localized: "\(hours)h ago", locale: locale)
        }
        let days = Int(seconds / 86_400)
        return String(localized: "\(days)d ago", locale: locale)
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
    // Passed into L10n.format() below so this view's `body` actually reads it —
    // SwiftUI only re-invokes `body` on a locale change for views that read
    // `\.locale` during the previous evaluation.
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: .dsSM) {
            HStack(alignment: .firstTextBaseline) {
                Label(L10n.format("inspector.pdfNote.pageLabel", note.pageNumber, locale: locale), systemImage: "note.text")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.dsTextTertiary)
                Spacer()
                Button(action: onJump) {
                    Image(systemName: "arrowshape.turn.up.right")
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.dsTextTertiary)
                .help("inspector.pdfNote.show.help")

                Button(action: onRemove) {
                    Image(systemName: "trash")
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.dsTextTertiary)
                .help("inspector.pdfNote.delete.help")
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
    // Passed into L10n.format()/PageDecorationSwatch.label() below so this view's
    // `body` actually reads it — SwiftUI only re-invokes `body` on a locale change
    // for views that read `\.locale` during the previous evaluation.
    @Environment(\.locale) private var locale

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
        let _ = viewModel.decorationStateVersion
        VStack(alignment: .leading, spacing: 0) {
            decorationRow(title: "inspector.decorate.watermark.title", isOn: watermarkEnabled) {
                VStack(alignment: .leading, spacing: .dsSM) {
                    TextField("inspector.decorate.watermark.text.placeholder", text: watermarkText)
                        .textFieldStyle(.roundedBorder)

                    decorationSizeControl(.watermark, range: 24...96, step: 2)
                    decorationOpacityControl(.watermark)
                    decorationSwatchControl(.watermark)
                }
            }

            Rectangle().fill(Color.dsSeparator).frame(height: 0.5)

            decorationRow(title: "inspector.decorate.pageNumbers.title", isOn: pageNumbersEnabled) {
                VStack(alignment: .leading, spacing: .dsSM) {
                    Text(L10n.format("inspector.pageOf", max(viewModel.pageCount, 1), locale: locale))
                        .font(.dsCaption())
                        .foregroundStyle(Color.dsTextSecondary)

                    decorationSizeControl(.pageNumber, range: 8...24, step: 1)
                    decorationOpacityControl(.pageNumber)
                    decorationSwatchControl(.pageNumber)
                }
            }

            Rectangle().fill(Color.dsSeparator).frame(height: 0.5)

            decorationRow(title: "inspector.decorate.batesStamp.title", isOn: batesEnabled) {
                VStack(alignment: .leading, spacing: .dsSM) {
                    TextField("inspector.decorate.bates.prefix.placeholder", text: batesPrefix)
                        .textFieldStyle(.roundedBorder)
                    Stepper(value: batesStartNumber, in: 0...999_999) {
                        Text(L10n.format("inspector.decorate.startNumber", viewModel.decorationStartNumber(for: .bates), locale: locale))
                            .font(.dsCaption())
                            .foregroundStyle(Color.dsTextSecondary)
                    }

                    decorationSizeControl(.bates, range: 8...24, step: 1)
                    decorationOpacityControl(.bates)
                    decorationSwatchControl(.bates)
                }
            }
        }
        .padding(.vertical, .dsXS)
    }

    private func decorationRow<Controls: View>(title: LocalizedStringKey,
                                               isOn: Binding<Bool>,
                                               @ViewBuilder controls: () -> Controls) -> some View {
        VStack(alignment: .leading, spacing: .dsSM) {
            Button {
                isOn.wrappedValue.toggle()
            } label: {
                HStack(spacing: .dsSM) {
                    ZStack {
                        RoundedRectangle(cornerRadius: .dsRadiusSm, style: .continuous)
                            .fill(isOn.wrappedValue ? Color.dsAccent : Color.dsCard)
                        RoundedRectangle(cornerRadius: .dsRadiusSm, style: .continuous)
                            .strokeBorder(isOn.wrappedValue ? Color.dsAccent : Color.dsSeparator, lineWidth: 1)
                        if isOn.wrappedValue {
                            Image(systemName: "checkmark")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Color.dsSurface)
                        }
                    }
                    .frame(width: 22, height: 22)

                    Text(title)
                        .font(.dsBody())
                        .foregroundStyle(Color.dsTextPrimary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityValue(isOn.wrappedValue ? "inspector.decorate.toggle.on" : "inspector.decorate.toggle.off")

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

    private func decorationSizeControl(_ kind: PageDecoration.Kind,
                                       range: ClosedRange<Double>,
                                       step: Double) -> some View {
        Stepper(value: decorationFontSizeBinding(for: kind), in: range, step: step) {
            Text(L10n.format("inspector.decorate.fontSize", Int(viewModel.decorationFontSize(for: kind)), locale: locale))
                .font(.dsCaption())
                .foregroundStyle(Color.dsTextSecondary)
        }
    }

    private func decorationOpacityControl(_ kind: PageDecoration.Kind) -> some View {
        HStack(spacing: .dsSM) {
            Image(systemName: "circle.lefthalf.filled")
                .frame(width: 16, height: 16)
                .foregroundStyle(Color.dsTextTertiary)
            Slider(value: decorationOpacityBinding(for: kind), in: 0.1...1, step: 0.05)
            Text("\(Int(viewModel.decorationOpacity(for: kind) * 100))%")
                .font(.dsCaption())
                .foregroundStyle(Color.dsTextSecondary)
                .frame(width: 36, alignment: .trailing)
        }
    }

    private func decorationSwatchControl(_ kind: PageDecoration.Kind) -> some View {
        Menu {
            ForEach(PageDecorationSwatch.globalDecorationChoices, id: \.self) { swatch in
                Button {
                    viewModel.setDecorationSwatch(kind, swatch: swatch)
                } label: {
                    HStack {
                        Text(swatch.label(locale: locale))
                        if viewModel.decorationSwatch(for: kind) == swatch {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: .dsSM) {
                Circle()
                    .fill(viewModel.decorationSwatch(for: kind).viewColor)
                    .frame(width: 14, height: 14)
                    .overlay(Circle().strokeBorder(Color.dsSeparator, lineWidth: 1))
                Text(viewModel.decorationSwatch(for: kind).label(locale: locale))
                    .font(.dsCaption())
                    .foregroundStyle(Color.dsTextSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .menuStyle(.borderlessButton)
        .help("inspector.decorate.decorationColor.help")
    }

    private func decorationFontSizeBinding(for kind: PageDecoration.Kind) -> Binding<Double> {
        Binding(
            get: { viewModel.decorationFontSize(for: kind) },
            set: { viewModel.setDecorationFontSize(kind, fontSize: $0) }
        )
    }

    private func decorationOpacityBinding(for kind: PageDecoration.Kind) -> Binding<Double> {
        Binding(
            get: { viewModel.decorationOpacity(for: kind) },
            set: { viewModel.setDecorationOpacity(kind, opacity: $0) }
        )
    }
}

private extension PageDecorationSwatch {
    static var globalDecorationChoices: [PageDecorationSwatch] {
        [.tertiary, .accent, .sage, .coral, .lavender]
    }

    var viewColor: Color {
        switch self {
        case .accent:
            return .dsAccent
        case .sage:
            return .dsAnnotationSage
        case .coral:
            return .dsAnnotationCoral
        case .tertiary:
            return .dsTextTertiary
        case .lavender:
            return .dsAnnotationLavender
        }
    }

    func label(locale: Locale) -> String {
        switch self {
        case .accent:
            return L10n.string("inspector.colorSwatch.accent.label", locale: locale)
        case .sage:
            return L10n.string("inspector.colorSwatch.sage.label", locale: locale)
        case .coral:
            return L10n.string("inspector.colorSwatch.coral.label", locale: locale)
        case .tertiary:
            return L10n.string("inspector.colorSwatch.gray.label", locale: locale)
        case .lavender:
            return L10n.string("inspector.colorSwatch.lavender.label", locale: locale)
        }
    }
}

// MARK: - OCR tab

private struct InspectorOCRView: View {
    @Bindable var viewModel: WorkspaceViewModel
    // Passed into L10n.format() below so this view's `body` actually reads it —
    // SwiftUI only re-invokes `body` on a locale change for views that read
    // `\.locale` during the previous evaluation.
    @Environment(\.locale) private var locale

    private var statusTitle: LocalizedStringKey {
        if viewModel.isMakingSearchable {
            return "inspector.ocr.status.makingSearchable"
        }
        if viewModel.hasScannedPages && !viewModel.canStartSearchable {
            return "inspector.ocr.status.waiting"
        }
        if viewModel.hasScannedPages {
            return "inspector.ocr.status.scannedPagesDetected"
        }
        if viewModel.ocrCandidatePageCount > 0 {
            return "inspector.ocr.status.textLayerDetected"
        }
        return "inspector.ocr.status.searchableReady"
    }

    private var statusDetail: LocalizedStringKey {
        if viewModel.isMakingSearchable {
            return LocalizedStringKey(viewModel.operationProgress.detail)
        }
        if viewModel.hasScannedPages && !viewModel.canStartSearchable {
            return "inspector.ocr.detail.finishBeforeRunningOCR"
        }
        if viewModel.hasScannedPages {
            return LocalizedStringKey(viewModel.scannedPageCount == 1
                ? L10n.format("inspector.ocr.scannedPages.one", viewModel.scannedPageCount, locale: locale)
                : L10n.format("inspector.ocr.scannedPages.other", viewModel.scannedPageCount, locale: locale))
        }
        if viewModel.ocrCandidatePageCount > 0 {
            return "inspector.ocr.detail.textFoundNoAutoRun"
        }
        return "inspector.ocr.detail.noPagesNeedOCR"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: .dsLG) {
            HStack(alignment: .top, spacing: .dsMD) {
                Image(systemName: viewModel.hasScannedPages ? "doc.text.viewfinder" : statusIconName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(viewModel.hasScannedPages ? Color.dsAccent : statusIconColor)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: .dsXS) {
                    Text(statusTitle)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.dsTextPrimary)
                    Text(statusDetail)
                        .font(.dsCaption())
                        .foregroundStyle(Color.dsTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Button {
                if viewModel.isMakingSearchable {
                    viewModel.cancelActiveOperation()
                } else if viewModel.hasScannedPages {
                    viewModel.makeSearchable()
                } else {
                    viewModel.makeSearchable(includePagesWithText: true)
                }
            } label: {
                Label(buttonTitle,
                      systemImage: viewModel.isMakingSearchable ? "xmark.circle" : "doc.text.viewfinder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .disabled(!viewModel.isMakingSearchable && !canRunButtonAction)
            .help(buttonHelp)
        }
        .padding(.horizontal, .dsLG)
        .padding(.vertical, .dsXL)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var buttonHelp: LocalizedStringKey {
        if viewModel.isMakingSearchable {
            return "inspector.ocr.help.cancelMakingSearchable"
        }
        if viewModel.canStartSearchable {
            return "inspector.ocr.help.runLocalOCR"
        }
        if viewModel.canRepairSearchableText {
            return "inspector.ocr.help.runOCRAnyway"
        }
        if viewModel.hasScannedPages {
            return "inspector.ocr.help.finishBeforeRunningOCR"
        }
        if viewModel.ocrCandidatePageCount > 0 {
            return "inspector.ocr.help.finishBeforeRepairing"
        }
        return "inspector.ocr.help.noPagesDetected"
    }

    private var buttonTitle: LocalizedStringKey {
        if viewModel.isMakingSearchable {
            return "inspector.ocr.button.cancelOCR"
        }
        if viewModel.hasScannedPages {
            return "inspector.ocr.button.makeSearchable"
        }
        if viewModel.ocrCandidatePageCount > 0 {
            return "inspector.ocr.button.runOCRAnyway"
        }
        return "inspector.ocr.button.makeSearchable"
    }

    private var canRunButtonAction: Bool {
        viewModel.canStartSearchable || viewModel.canRepairSearchableText
    }

    private var statusIconName: String {
        viewModel.ocrCandidatePageCount > 0 ? "text.viewfinder" : "checkmark.circle"
    }

    private var statusIconColor: Color {
        viewModel.ocrCandidatePageCount > 0 ? Color.dsAccent : Color.dsAnnotationSage
    }
}

private struct InspectorMarkupView: View {
    @Bindable var viewModel: WorkspaceViewModel

    private var allAnnotations: [(page: PDFPage, annotation: PDFAnnotation, memberName: String)] {
        var result: [(PDFPage, PDFAnnotation, String)] = []
        for (member, pdf) in viewModel.loadedPDFs {
            for i in 0..<pdf.pageCount {
                guard let page = pdf.page(at: i) else { continue }
                for ann in page.annotations {
                    // The invisible bake stamp is engine bookkeeping, not user markup.
                    if BakeStamp.isStamp(ann) { continue }
                    result.append((page, ann, member.displayName))
                }
            }
        }
        return result
    }

    private var textEdits: [WorkspaceViewModel.InlineTextEditListItem] {
        viewModel.inlineTextEditListItems()
    }

    var body: some View {
        if allAnnotations.isEmpty && viewModel.selectedAnnotation == nil && textEdits.isEmpty {
            VStack(spacing: .dsSM) {
                Image(systemName: "highlighter")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(Color.dsTextTertiary)
                Text("inspector.markup.empty.title")
                    .font(.dsBody())
                    .foregroundStyle(Color.dsTextSecondary)
                Text("inspector.markup.empty.subtitle")
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
                if !textEdits.isEmpty {
                    InspectorTextEditsSection(viewModel: viewModel, textEdits: textEdits)
                    Rectangle().fill(Color.dsSeparator).frame(height: 0.5)
                }
                ForEach(allAnnotations.indices, id: \.self) { i in
                    InspectorAnnotationRow(
                        ann: allAnnotations[i].annotation,
                        memberName: allAnnotations[i].memberName,
                        isSelected: viewModel.selectedAnnotation === allAnnotations[i].annotation,
                        onSelect: {
                            viewModel.selectedAnnotation = allAnnotations[i].annotation
                            viewModel.selectedStampDecorationID = nil
                            NotificationCenter.default.post(
                                name: .orifoldJumpToAnnotation,
                                object: allAnnotations[i].annotation
                            )
                        },
                        onEdit: {
                            viewModel.selectedAnnotation = allAnnotations[i].annotation
                            viewModel.selectedStampDecorationID = nil
                            NotificationCenter.default.post(
                                name: .orifoldEditAnnotation,
                                object: allAnnotations[i].annotation
                            )
                        },
                        onDelete: {
                            viewModel.selectedAnnotation = allAnnotations[i].annotation
                            viewModel.selectedStampDecorationID = nil
                            viewModel.deleteSelectedAnnotation()
                        }
                    )
                    Rectangle().fill(Color.dsSeparator).frame(height: 0.5)
                }
            }
            .padding(.vertical, .dsXS)
        }
    }
}

private struct InspectorTextEditsSection: View {
    @Bindable var viewModel: WorkspaceViewModel
    var textEdits: [WorkspaceViewModel.InlineTextEditListItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: .dsSM) {
                InspectorSectionHeader(title: "Text Edits", count: textEdits.count)
                Spacer()
                Button("inspector.textEdit.revertAll.button") {
                    viewModel.revertAllInlineTextEdits()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.dsAccent)
                .padding(.trailing, .dsMD)
                .help("inspector.textEdit.revertAll.help")
            }
            ForEach(textEdits) { item in
                InspectorTextEditRow(
                    item: item,
                    onSelect: {
                        if let ref = viewModel.document.workspace.pageOrder.first(where: { $0.id == item.pageRefID }) {
                            viewModel.selectPage(ref)
                        }
                    },
                    onRevert: {
                        viewModel.revertInlineTextEdit(pageRefID: item.pageRefID, operationID: item.id)
                    }
                )
            }
        }
        .padding(.vertical, .dsXS)
    }
}

private struct InspectorTextEditRow: View {
    var item: WorkspaceViewModel.InlineTextEditListItem
    var onSelect: () -> Void
    var onRevert: () -> Void
    // Passed into L10n.format() below so this view's `body` actually reads it —
    // SwiftUI only re-invokes `body` on a locale change for views that read
    // `\.locale` during the previous evaluation.
    @Environment(\.locale) private var locale

    private var changeSummary: String {
        switch item.kind {
        case .insertion:
            return "Added \u{201C}\(item.replacementText)\u{201D}"
        case .deletion:
            return "Deleted \u{201C}\(item.originalText)\u{201D}"
        case .styleOnly:
            return "Restyled \u{201C}\(item.originalText)\u{201D}"
        case .edit:
            return "\u{201C}\(item.originalText)\u{201D} \u{2192} \u{201C}\(item.replacementText)\u{201D}"
        }
    }

    private var kindBadge: (title: LocalizedStringKey, color: Color, icon: String) {
        switch item.kind {
        case .insertion: return ("inspector.textEdit.kind.added", .dsAccent, "plus.square")
        case .deletion: return ("inspector.textEdit.kind.deleted", Color(nsColor: .systemRed), "text.badge.minus")
        case .styleOnly: return ("inspector.textEdit.kind.restyled", Color(nsColor: .systemPurple), "paintbrush")
        case .edit: return ("inspector.textEdit.kind.edited", Color(nsColor: .systemTeal), "character.cursor.ibeam")
        }
    }

    private var contextLabel: String {
        var label = L10n.format("inspector.versionHistory.pageLabel", item.pageNumber, locale: locale)
        if item.totalOnPage > 1 {
            label += " · " + L10n.format("inspector.textEdit.orderOnPage", item.orderOnPage, item.totalOnPage, locale: locale)
        }
        if !item.memberName.isEmpty {
            label += " · \(item.memberName)"
        }
        return label
    }

    var body: some View {
        let badge = kindBadge
        HStack(alignment: .top, spacing: .dsXS) {
            Button(action: onSelect) {
                HStack(alignment: .top, spacing: .dsSM) {
                    Image(systemName: badge.icon)
                        .font(.system(size: 11))
                        .foregroundStyle(badge.color)
                        .frame(width: 16)
                        .padding(.top, 2)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(badge.title)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(badge.color)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(badge.color.opacity(0.14), in: Capsule())
                        Text(changeSummary)
                            .font(.dsCaption())
                            .foregroundStyle(Color.dsTextPrimary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(contextLabel)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.dsTextTertiary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .help("inspector.textEdit.showThisPage.help")

            Button(action: onRevert) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Color.dsTextTertiary)
            .help(item.isInsertion ? "inspector.textEdit.removeAdded.help" : "inspector.textEdit.restoreOriginal.help")
        }
        .padding(.horizontal, .dsMD)
        .padding(.vertical, .dsSM)
        .contentShape(Rectangle())
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
                Text("inspector.editingDetails.title")
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
    var title: LocalizedStringKey

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
    var isSelected: Bool
    var onSelect: () -> Void
    var onEdit: () -> Void
    var onDelete: () -> Void
    // Passed into L10n.string() below so this view's `body` actually reads it —
    // SwiftUI only re-invokes `body` on a locale change for views that read
    // `\.locale` during the previous evaluation.
    @Environment(\.locale) private var locale

    private var canEditContents: Bool {
        ann.type == "Text" || ann.type == "FreeText"
    }

    private var typeLabel: String {
        switch ann.type {
        case "Highlight": return L10n.string("inspector.annotationType.highlight.label", locale: locale)
        case "Text":      return L10n.string("inspector.annotationType.note.label", locale: locale)
        case "Ink":       return L10n.string("inspector.annotationType.ink.label", locale: locale)
        case "FreeText":  return L10n.string("inspector.annotationType.textBox.label", locale: locale)
        case "Underline": return L10n.string("inspector.annotationType.underline.label", locale: locale)
        case "StrikeOut": return L10n.string("inspector.annotationType.strikeout.label", locale: locale)
        default:          return ann.type ?? L10n.string("inspector.annotationType.generic.label", locale: locale)
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
        HStack(alignment: .top, spacing: .dsXS) {
            Button(action: onSelect) {
                HStack(alignment: .top, spacing: .dsSM) {
                    Image(systemName: icon)
                        .font(.system(size: 11))
                        .foregroundStyle(isSelected ? Color.dsAccent : Color.dsTextTertiary)
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
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)
            .help("inspector.annotation.select.help")

            if canEditContents {
                Button(action: onEdit) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Color.dsTextTertiary)
                .help("inspector.annotation.edit.help")
            }

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Color.dsTextTertiary)
            .help("inspector.annotation.delete.help")
        }
        .padding(.horizontal, .dsMD)
        .padding(.vertical, .dsSM)
        .background(isSelected ? Color.dsAccentSoft.opacity(0.35) : Color.clear)
        .contentShape(Rectangle())
    }
}
