import SwiftUI
import PDFKit
import AppKit
import UniformTypeIdentifiers

struct InspectorView: View {
    @Bindable var viewModel: WorkspaceViewModel
    @Binding var selectedTab: Tab
    /// The Info tab's un-applied edits live HERE, above the tab switch, because SwiftUI
    /// tears the tab's own view down the moment the user looks at another tab — which
    /// silently threw away whatever they had typed and not yet applied.
    @State private var metadataDraft = MetadataDraft()
    // Read so SwiftUI re-invokes `body` when the app language changes; the
    // inspector's inputs are otherwise stable (a class-reference view model), so
    // without a `\.locale` read its localized text would stay in the old language.
    @Environment(\.locale) private var locale

    enum Tab: String, CaseIterable {
        case info = "Info"
        case tags = "Tags"
        case comments = "Comments"
        case markup = "Markup"
        case decorate = "Decorate"
        case ocr = "OCR"
        case attachments = "Attachments"
        case structure = "Structure"

        var iconName: String {
            switch self {
            case .info: return "info.circle"
            case .tags: return "tag"
            case .comments: return "text.bubble"
            case .markup: return "highlighter"
            case .decorate: return "paintbrush.pointed"
            case .ocr: return "doc.text.viewfinder"
            case .attachments: return "paperclip"
            case .structure: return "list.bullet.indent"
            }
        }

        /// Translation key for the tab's display name. The `rawValue` is a stable,
        /// non-localized identifier (persisted/compared in code); the label shown to
        /// the user must come from the catalog so non-English users see their language.
        private var titleKey: String {
            switch self {
            case .info: return "inspector.tab.info"
            case .tags: return "inspector.tab.tags"
            case .comments: return "inspector.tab.comments"
            case .markup: return "inspector.tab.markup"
            case .decorate: return "inspector.tab.decorate"
            case .ocr: return "inspector.tab.ocr"
            case .attachments: return "inspector.tab.attachments"
            case .structure: return "inspector.tab.structure"
            }
        }

        func title(locale: Locale) -> String {
            L10n.string(forKey: titleKey, locale: locale)
        }
    }

    var body: some View {
        let _ = locale
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(L10n.string("inspector.title"))
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
                case .info: InspectorInfoView(viewModel: viewModel, draft: $metadataDraft)
                case .tags: InspectorTagsView(viewModel: viewModel)
                case .comments: InspectorWorkspaceCommentsView(viewModel: viewModel)
                case .markup: InspectorMarkupView(viewModel: viewModel)
                case .decorate: InspectorDecorateView(viewModel: viewModel)
                case .ocr: InspectorOCRView(viewModel: viewModel)
                case .attachments: InspectorAttachmentsView(viewModel: viewModel)
                case .structure: InspectorStructureView(viewModel: viewModel)
                }
            }
        }
        .background(Color.dsSurface)
    }
}

private struct InspectorTabPicker: View {
    @Binding var selectedTab: InspectorView.Tab
    // Read so SwiftUI re-invokes `body` when the app language changes.
    @Environment(\.locale) private var locale

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
                        Text(tab.title(locale: locale))
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

/// The four editable Info-dict fields plus the values they were last seeded from.
///
/// Keeping both halves is what makes "has the user typed something we would be throwing
/// away?" answerable. Re-seeding used to be unconditional, so an undo, a page click, or a
/// glance at another tab overwrote in-progress typing with the stored values.
struct MetadataDraft: Equatable {
    var title = ""
    var author = ""
    var subject = ""
    var keywords = ""
    /// False for an encrypted member with no stored password (or an empty workspace) —
    /// the editor disables itself rather than silently writing nothing.
    var metadataReadable = false
    var hasXMP = false

    private var seeded = Values()

    private struct Values: Equatable {
        var title = ""
        var author = ""
        var subject = ""
        var keywords = ""
    }

    var isDirty: Bool {
        title != seeded.title || author != seeded.author
            || subject != seeded.subject || keywords != seeded.keywords
    }

    mutating func seed(from metadata: PDFDocumentMetadata?, hasXMP: Bool) {
        seeded = Values(
            title: metadata?.title ?? "",
            author: metadata?.author ?? "",
            subject: metadata?.subject ?? "",
            keywords: metadata?.keywords ?? ""
        )
        title = seeded.title
        author = seeded.author
        subject = seeded.subject
        keywords = seeded.keywords
        metadataReadable = metadata != nil
        self.hasXMP = metadata != nil ? hasXMP : false
    }

    /// Called after a successful Apply: the document now holds what the draft holds, so
    /// the draft is clean again and the next re-seed may proceed.
    mutating func markApplied() {
        seeded = Values(title: title, author: author, subject: subject, keywords: keywords)
    }
}

private struct InspectorInfoView: View {
    var viewModel: WorkspaceViewModel
    // Read so SwiftUI re-invokes `body` when the app language changes.
    @Environment(\.locale) private var locale

    @Binding var draft: MetadataDraft

    private var visualSignatureCount: Int {
        viewModel.document.workspace.signatures.filter { !$0.isCryptographic }.count
    }

    private var digitalSignatureCount: Int {
        viewModel.document.workspace.signatures.filter(\.isCryptographic).count
    }

    var body: some View {
        let _ = locale
        VStack(alignment: .leading, spacing: .dsLG) {
            InspectorRow(label: L10n.string("inspector.info.documents", locale: locale),   value: "\(viewModel.document.workspace.documents.count)")
            InspectorRow(label: L10n.string("inspector.info.totalPages", locale: locale),  value: "\(viewModel.document.workspace.pageOrder.count)")
            InspectorRow(label: L10n.string("inspector.info.signatures", locale: locale),  value: "\(viewModel.document.workspace.signatures.count)")
            InspectorRow(label: L10n.string("inspector.info.visual", locale: locale),      value: "\(visualSignatureCount)")
            InspectorRow(label: L10n.string("inspector.info.digital", locale: locale),     value: "\(digitalSignatureCount)")
            InspectorRow(label: L10n.string("inspector.info.tags", locale: locale),        value: "\(viewModel.document.workspace.tags.count)")
            InspectorRow(label: L10n.string("inspector.info.comments", locale: locale),    value: "\(viewModel.totalCommentCount)")
            InspectorRow(label: L10n.string("inspector.info.created", locale: locale),     value: viewModel.document.workspace.createdAt.formatted(
                date: .abbreviated, time: .omitted))

            InspectorSignatureValidationSection(viewModel: viewModel)

            if !viewModel.document.workspace.documents.isEmpty {
                Rectangle()
                    .fill(Color.dsSeparator)
                    .frame(height: 0.5)
                metadataSection
            }
        }
        .padding(.horizontal, .dsLG)
        .padding(.vertical, .dsXL)
        .frame(maxWidth: .infinity, alignment: .leading)
        .inspectorDraft(from: viewModel, seed: seedMetadataFields)
    }

    /// The member whose Info dictionary these fields read and write. Always the first —
    /// combining members produces one `/Info`, and the assembly keeps that one.
    private var metadataTargetName: String? {
        viewModel.document.workspace.documents.first?.displayName
    }

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: .dsMD) {
            Text(L10n.string("inspector.metadata.section", locale: locale).uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.dsTextTertiary)
                .tracking(0.5)

            // Which document these fields belong to is not guessable from the fields
            // themselves: they always target the first member, whatever page the reader is
            // looking at, and the other members' properties are dropped when files are
            // combined. Saying so beats letting someone edit a document they can't see.
            if let metadataTargetName, viewModel.document.workspace.documents.count > 1 {
                Text(L10n.format("inspector.metadata.target", metadataTargetName, locale: locale))
                    .font(.dsCaption())
                    .foregroundStyle(Color.dsTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            metadataField(L10n.string("inspector.metadata.title", locale: locale), text: $draft.title)
            metadataField(L10n.string("inspector.metadata.author", locale: locale), text: $draft.author)
            metadataField(L10n.string("inspector.metadata.subject", locale: locale), text: $draft.subject)
            metadataField(L10n.string("inspector.metadata.keywords", locale: locale), text: $draft.keywords)

            if draft.hasXMP {
                Text(L10n.string("inspector.metadata.xmpWarning", locale: locale))
                    .font(.dsCaption())
                    .foregroundStyle(Color.dsTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                applyMetadata()
            } label: {
                Text(L10n.string("inspector.metadata.apply", locale: locale))
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 32)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.dsAccent)
            .disabled(!draft.metadataReadable)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metadataField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.dsTextTertiary)
                .tracking(0.5)
            TextField("", text: text)
                .textFieldStyle(.roundedBorder)
                .font(.dsBody())
                .disabled(!draft.metadataReadable)
                .accessibilityLabel(label)
        }
    }

    private func seedMetadataFields() {
        // Never overwrite typing the user has not applied yet. Re-seeding fires on undo,
        // redo and every member switch, none of which the user reads as "discard my edit"
        // — and the fields always target the same member anyway, so a selection change is
        // no reason to reload them.
        guard !draft.isDirty else { return }
        draft.seed(
            from: viewModel.activeDocumentMetadata(),
            hasXMP: viewModel.activeDocumentHasXMPMetadata
        )
    }

    private func applyMetadata() {
        let metadata = PDFDocumentMetadata(
            title: trimmedOrNil(draft.title),
            author: trimmedOrNil(draft.author),
            subject: trimmedOrNil(draft.subject),
            keywords: trimmedOrNil(draft.keywords)
        )
        if viewModel.applyMetadataEdit(metadata) {
            // The document now holds what the draft holds, so the draft is no longer
            // dirty — without this the dirty guard would block every later re-seed.
            draft.markApplied()
            // Re-seed so the fields reflect the canonical stored state instead of
            // the just-typed draft.
            seedMetadataFields()
        }
    }

    private func trimmedOrNil(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct InspectorSignatureReport: Identifiable {
    var memberID: UUID
    var memberName: String
    var report: PDFSignatureValidation

    var id: String { "\(memberID.uuidString)-\(report.id)" }
}

private struct InspectorSignatureValidationSection: View {
    var viewModel: WorkspaceViewModel

    @Environment(\.locale) private var locale
    @State private var signatureReports: [InspectorSignatureReport] = []
    @State private var isValidatingSignatures = false

    var body: some View {
        // Keep an actual view mounted even before validation starts. A `Group` whose
        // conditional content was initially empty did not appear in the hierarchy, so its
        // `.task` never ran and the Inspector could never discover incoming signatures.
        VStack(alignment: .leading, spacing: 0) {
            if isValidatingSignatures || !signatureReports.isEmpty {
                Rectangle()
                    .fill(Color.dsSeparator)
                    .frame(height: 0.5)
                sectionContent
            }
        }
        .task(id: viewModel.structureRevision) {
            await loadSignatureReports()
        }
    }

    private var sectionContent: some View {
        VStack(alignment: .leading, spacing: .dsMD) {
            Text(L10n.string("signature.validation.section", locale: locale).uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.dsTextTertiary)
                .tracking(0.5)

            if isValidatingSignatures {
                ProgressView(L10n.string("signature.validation.checking", locale: locale))
                    .font(.dsCaption())
            }

            ForEach(signatureReports) { item in
                signatureCard(item)
            }

            Text(L10n.string("signature.validation.noLTV", locale: locale))
                .font(.dsCaption())
                .foregroundStyle(Color.dsTextTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func signatureCard(_ item: InspectorSignatureReport) -> some View {
        VStack(alignment: .leading, spacing: .dsSM) {
            if viewModel.document.workspace.documents.count > 1 {
                Text(item.memberName)
                    .font(.dsCaption())
                    .foregroundStyle(Color.dsTextTertiary)
            }
            Text(item.report.signerCommonName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.dsTextPrimary)

            signingTimeView(for: item.report)
            signatureVerdictRow(
                label: L10n.string("signature.validation.integrity.label", locale: locale),
                value: integrityText(item.report.integrity),
                color: item.report.integrity == .valid
                    ? Color.dsAnnotationSage
                    : Color.dsAnnotationCoral
            )
            signatureVerdictRow(
                label: L10n.string("signature.validation.trust.label", locale: locale),
                value: trustText(item.report.trust),
                color: trustColor(item.report.trust)
            )
            signatureVerdictRow(
                label: L10n.string("signature.validation.coverage.label", locale: locale),
                value: coverageText(item.report.coverage),
                color: item.report.coverage == .entireDocument
                    ? Color.dsAnnotationSage
                    : Color.dsAnnotationCoral
            )
        }
        .padding(.dsMD)
        .background(
            Color.dsCard,
            in: RoundedRectangle(cornerRadius: .dsRadiusSm, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: .dsRadiusSm, style: .continuous)
                .strokeBorder(Color.dsSeparator, lineWidth: 1)
        }
    }

    @ViewBuilder
    private func signingTimeView(for report: PDFSignatureValidation) -> some View {
        if let signingTime = report.signingTime {
            Text(signingTimeText(signingTime, timestamped: report.isTimestamped))
                .font(.dsCaption())
                .foregroundStyle(Color.dsTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(L10n.string("signature.validation.time.unavailable", locale: locale))
                .font(.dsCaption())
                .foregroundStyle(Color.dsTextSecondary)
        }
    }

    private func signatureVerdictRow(label: String, value: String, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: .dsSM) {
            Text(label)
                .font(.dsCaption())
                .foregroundStyle(Color.dsTextTertiary)
            Spacer(minLength: .dsSM)
            Text(value)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)
                .multilineTextAlignment(.trailing)
        }
    }

    private func signingTimeText(_ date: Date, timestamped: Bool) -> String {
        let formatted = date.formatted(date: .abbreviated, time: .shortened)
        return timestamped
            ? L10n.format("signature.validation.time.timestampPresent", formatted, locale: locale)
            : L10n.format("signature.validation.time.unverified", formatted, locale: locale)
    }

    private func integrityText(_ verdict: PDFSignatureIntegrityVerdict) -> String {
        L10n.string(
            verdict == .valid
                ? "signature.validation.integrity.valid"
                : "signature.validation.integrity.invalid",
            locale: locale
        )
    }

    private func trustText(_ verdict: PDFSignatureTrustVerdict) -> String {
        switch verdict {
        case .trusted:
            return L10n.string("signature.validation.trust.trusted", locale: locale)
        case .revoked:
            return L10n.string("signature.validation.trust.revoked", locale: locale)
        case .notTrusted:
            return L10n.string("signature.validation.trust.notTrusted", locale: locale)
        case .unavailable:
            return L10n.string("signature.validation.trust.unavailable", locale: locale)
        }
    }

    private func trustColor(_ verdict: PDFSignatureTrustVerdict) -> Color {
        switch verdict {
        case .trusted:
            return Color.dsAnnotationSage
        case .revoked:
            return Color.dsAnnotationCoral
        case .notTrusted, .unavailable:
            return Color.dsTextSecondary
        }
    }

    private func coverageText(_ verdict: PDFSignatureCoverageVerdict) -> String {
        switch verdict {
        case .entireDocument:
            return L10n.string("signature.validation.coverage.entireDocument", locale: locale)
        case .changedAfterSigning:
            return L10n.string("signature.validation.coverage.changedAfterSigning", locale: locale)
        case .invalid:
            return L10n.string("signature.validation.coverage.invalid", locale: locale)
        }
    }

    @MainActor
    private func loadSignatureReports() async {
        isValidatingSignatures = true
        var loaded: [InspectorSignatureReport] = []
        for member in viewModel.document.workspace.documents {
            guard !Task.isCancelled else { return }
            guard let data = viewModel.signatureValidationData(for: member.id) else { continue }
            let reports = await PDFSignatureValidationService.validate(pdf: data)
            loaded.append(contentsOf: reports.map {
                InspectorSignatureReport(memberID: member.id, memberName: member.displayName, report: $0)
            })
        }
        guard !Task.isCancelled else { return }
        signatureReports = loaded
        isValidatingSignatures = false
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
    // Read so SwiftUI re-invokes `body` when the app language changes.
    @Environment(\.locale) private var locale

    var body: some View {
        let _ = locale
        VStack(alignment: .leading, spacing: .dsMD) {
            HStack(spacing: .dsSM) {
                TextField(L10n.string("inspector.tags.addTag.placeholder"), text: $draftTag)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addTag)
                Button(action: addTag) {
                    Image(systemName: "plus")
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.dsAccent)
                .disabled(draftTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help(L10n.string("inspector.tags.addTag.help"))
            }

            if viewModel.document.workspace.tags.isEmpty {
                InspectorEmptyState(icon: "tag", title: L10n.string("inspector.tags.empty"))
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
    // Read so SwiftUI re-invokes `body` when the app language changes (refreshes
    // the remove-button tooltip).
    @Environment(\.locale) private var locale

    var body: some View {
        let _ = locale
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
            .help(L10n.string("inspector.tags.removeTag.help"))
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
    @Environment(\.locale) private var locale

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
                placeholder: L10n.string(viewModel.isReaderMode ? "inspector.comments.studyNote.placeholder" : "inspector.comments.comment.placeholder", locale: locale),
                minHeight: 96,
                background: Color.dsCard,
                font: .dsBody()
            )
            .accessibilityLabel(L10n.string(viewModel.isReaderMode ? "inspector.comments.studyNote.accessibilityLabel" : "inspector.comments.comment.accessibilityLabel", locale: locale))

            Button {
                viewModel.addComment(draftComment)
                draftComment = ""
            } label: {
                Label(L10n.string(viewModel.isReaderMode ? "inspector.comments.saveNote.button" : "inspector.comments.addComment.button", locale: locale), systemImage: "text.bubble")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 32)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.dsAccent)
            .disabled(draftComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Picker(L10n.string("inspector.comments.filter.picker"), selection: $viewModel.commentFilter) {
                Text(L10n.string("inspector.comments.filter.open")).tag(WorkspaceViewModel.CommentFilter.open)
                Text(L10n.string("inspector.comments.filter.resolved")).tag(WorkspaceViewModel.CommentFilter.resolved)
                Text(L10n.string("inspector.comments.filter.all")).tag(WorkspaceViewModel.CommentFilter.all)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if !hasComments {
                InspectorEmptyState(icon: "text.bubble", title: L10n.string("inspector.comments.empty", locale: locale))
            } else {
                LazyVStack(alignment: .leading, spacing: .dsMD) {
                    if !workspaceComments.isEmpty {
                        InspectorSectionHeader(title: L10n.string("inspector.comments.section.workspace", locale: locale), count: workspaceComments.count)
                        ForEach(workspaceComments) { comment in
                            WorkspaceCommentRow(viewModel: viewModel, comment: comment)
                        }
                    } else if !allWorkspaceComments.isEmpty {
                        InspectorEmptyState(icon: "line.3.horizontal.decrease.circle", title: L10n.string("inspector.comments.noMatching", locale: locale))
                    }

                    if !noteComments.isEmpty {
                        InspectorSectionHeader(title: L10n.string("inspector.comments.section.pdfNotes", locale: locale), count: noteComments.count)
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
                .help(L10n.string(current.isResolved ? "inspector.comments.markOpen.help" : "inspector.comments.markResolved.help", locale: locale))

                Button {
                    draftBody = liveComment.body
                    isEditing.toggle()
                } label: {
                    Image(systemName: isEditing ? "xmark" : "square.and.pencil")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Color.dsTextTertiary)
                .help(L10n.string(isEditing ? "inspector.comments.cancelEdit.help" : "inspector.comments.editComment.help", locale: locale))

                Button {
                    viewModel.removeComment(liveComment)
                } label: {
                    Image(systemName: "trash")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Color.dsTextTertiary)
                .help(L10n.string("inspector.comments.deleteComment.help"))
            }

            if let subtitle = viewModel.anchorSubtitle(for: current, locale: locale) {
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
                .help(L10n.string(current.anchor == nil ? "inspector.comments.anchorRemoved.help" : "inspector.comments.jumpToAnchor.help", locale: locale))
            }

            if isEditing {
                InspectorTextEditor(
                    text: $draftBody,
                    placeholder: L10n.string("inspector.textEdit.editComment.placeholder", locale: locale),
                    minHeight: 76,
                    background: Color.dsSurface,
                    font: .system(size: commentFontSize(for: current.style.textSize)),
                    focusOnAppear: viewModel.selectedCommentID == current.id
                )
                .accessibilityLabel(L10n.string("inspector.textEdit.editComment.accessibilityLabel"))
                Button {
                    viewModel.updateCommentBody(liveComment, body: draftBody)
                    isEditing = false
                } label: {
                    Label(L10n.string("inspector.comments.save.button"), systemImage: "checkmark")
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
            .help(L10n.string("inspector.comments.format.bold.help"))

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
            .help(L10n.string("inspector.comments.format.italic.help"))

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
            .help(L10n.string("inspector.comments.format.textSize.help"))

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
            .help(L10n.string("inspector.comments.format.textColor.help"))

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
                TextField(L10n.string("inspector.comments.addTag.placeholder"), text: $draftTag)
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
                .help(L10n.string("inspector.comments.tagSuggestions.help"))

                Button(action: addCommentTag) {
                    Image(systemName: "plus")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.bordered)
                .disabled(draftTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help(L10n.string("inspector.comments.addTagToComment.help"))
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
            return L10n.format("inspector.relativeTime.minutes", minutes, locale: locale)
        }
        if seconds < 86_400 {
            let hours = Int(seconds / 3_600)
            return L10n.format("inspector.relativeTime.hours", hours, locale: locale)
        }
        let days = Int(seconds / 86_400)
        return L10n.format("inspector.relativeTime.days", days, locale: locale)
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
                .help(L10n.string("inspector.pdfNote.show.help"))

                Button(action: onRemove) {
                    Image(systemName: "trash")
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.dsTextTertiary)
                .help(L10n.string("inspector.pdfNote.delete.help"))
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
    @State private var isShowingCropSheet = false
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
            decorationRow(title: L10n.string("inspector.decorate.watermark.title", locale: locale), isOn: watermarkEnabled) {
                VStack(alignment: .leading, spacing: .dsSM) {
                    TextField(L10n.string("inspector.decorate.watermark.text.placeholder"), text: watermarkText)
                        .textFieldStyle(.roundedBorder)

                    decorationSizeControl(.watermark, range: 24...96, step: 2)
                    decorationOpacityControl(.watermark)
                    decorationSwatchControl(.watermark)
                }
            }

            Rectangle().fill(Color.dsSeparator).frame(height: 0.5)

            decorationRow(title: L10n.string("inspector.decorate.pageNumbers.title", locale: locale), isOn: pageNumbersEnabled) {
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

            decorationRow(title: L10n.string("inspector.decorate.batesStamp.title", locale: locale), isOn: batesEnabled) {
                VStack(alignment: .leading, spacing: .dsSM) {
                    TextField(L10n.string("inspector.decorate.bates.prefix.placeholder"), text: batesPrefix)
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

            Rectangle().fill(Color.dsSeparator).frame(height: 0.5)

            OverlayPDFDecorationSection(viewModel: viewModel)

            Rectangle().fill(Color.dsSeparator).frame(height: 0.5)

            Button {
                isShowingCropSheet = true
            } label: {
                HStack(spacing: .dsSM) {
                    Image(systemName: "crop")
                        .frame(width: 22, height: 22)
                    Text(L10n.string("inspector.crop.open", locale: locale))
                        .font(.dsBody())
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.dsTextTertiary)
                }
                .foregroundStyle(Color.dsTextPrimary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, .dsLG)
            .padding(.vertical, .dsMD)
            .disabled(viewModel.document.workspace.pageOrder.isEmpty)
        }
        .padding(.vertical, .dsXS)
        .sheet(isPresented: $isShowingCropSheet) {
            PageCropSheet(viewModel: viewModel)
        }
    }

    private func decorationRow<Controls: View>(title: String,
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
            .accessibilityValue(L10n.string(isOn.wrappedValue ? "inspector.decorate.toggle.on" : "inspector.decorate.toggle.off", locale: locale))

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
        .help(L10n.string("inspector.decorate.decorationColor.help"))
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

private struct OverlayPDFDecorationSection: View {
    private enum Target: String {
        case allPages
        case thisPage
        case targetedPage
    }

    var viewModel: WorkspaceViewModel

    @Environment(\.locale) private var locale
    @State private var isShowingImporter = false
    @State private var isShowingImportError = false
    @State private var selectedTarget = Target.allPages

    private var overlay: PageDecoration? {
        viewModel.overlayPDFDecoration()
    }

    private var overlayPDFPlacement: Binding<PageDecorationPDFPlacement> {
        Binding(
            get: { overlay?.overlayPDFPlacement ?? .over },
            set: { viewModel.setOverlayPDFPlacement($0, pageRefID: overlay?.pageRefID) }
        )
    }

    private var overlayPDFEnabled: Binding<Bool> {
        Binding(
            get: { overlay?.isEnabled == true },
            set: { viewModel.setOverlayPDFEnabled($0) }
        )
    }

    private var currentPageRef: PageRef? {
        let order = viewModel.document.workspace.pageOrder
        if let selectedPageRefID = viewModel.selectedPageRefID,
           let selected = order.first(where: { $0.id == selectedPageRefID }) {
            return selected
        }
        let index = viewModel.currentPageNumber - 1
        return order.indices.contains(index) ? order[index] : order.first
    }

    private var persistedTarget: Target {
        guard let targetID = overlay?.pageRefID else { return .allPages }
        return targetID == currentPageRef?.id ? .thisPage : .targetedPage
    }

    private var targetedPageNumber: Int? {
        guard let targetID = overlay?.pageRefID,
              let index = viewModel.document.workspace.pageOrder.firstIndex(where: {
                $0.id == targetID
              }) else { return nil }
        return index + 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: .dsSM) {
            titleRow
            if overlay != nil {
                Toggle(
                    L10n.string("inspector.decorate.overlayPDF.enabled", locale: locale),
                    isOn: overlayPDFEnabled
                )
                if currentPageRef != nil {
                    targetPicker
                }
                placementPicker
            }
            actionButtons
        }
        .padding(.horizontal, .dsLG)
        .padding(.vertical, .dsMD)
        .task {
            selectedTarget = persistedTarget
        }
        .onChange(of: viewModel.decorationStateVersion) {
            selectedTarget = persistedTarget
        }
        .onChange(of: currentPageRef?.id) {
            selectedTarget = persistedTarget
        }
        .fileImporter(
            isPresented: $isShowingImporter,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: false,
            onCompletion: importOverlayPDF
        )
        .alert(
            L10n.string("inspector.decorate.overlayPDF.invalid.title", locale: locale),
            isPresented: $isShowingImportError
        ) {
            Button(L10n.string("common.ok", locale: locale), role: .cancel) {}
        } message: {
            Text(L10n.string("inspector.decorate.overlayPDF.invalid.message", locale: locale))
        }
    }

    private var titleRow: some View {
        HStack(spacing: .dsSM) {
            Image(systemName: "doc.richtext")
                .frame(width: 22, height: 22)
                .foregroundStyle(Color.dsAccent)
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.string("inspector.decorate.overlayPDF.title", locale: locale))
                    .font(.dsBody())
                    .foregroundStyle(Color.dsTextPrimary)
                Text(L10n.string("inspector.decorate.overlayPDF.description", locale: locale))
                    .font(.dsCaption())
                    .foregroundStyle(Color.dsTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var placementPicker: some View {
        Picker(
            L10n.string("inspector.decorate.overlayPDF.placement", locale: locale),
            selection: overlayPDFPlacement
        ) {
            Text(L10n.string("inspector.decorate.overlayPDF.over", locale: locale))
                .tag(PageDecorationPDFPlacement.over)
            Text(L10n.string("inspector.decorate.overlayPDF.under", locale: locale))
                .tag(PageDecorationPDFPlacement.under)
        }
        .pickerStyle(.segmented)
    }

    private var targetPicker: some View {
        Picker(
            L10n.string("inspector.decorate.overlayPDF.target", locale: locale),
            selection: $selectedTarget
        ) {
            Text(L10n.string("inspector.decorate.overlayPDF.allPages", locale: locale))
                .tag(Target.allPages)
            Text(L10n.string("inspector.decorate.overlayPDF.thisPage", locale: locale))
                .tag(Target.thisPage)
            if let targetedPageNumber, persistedTarget == .targetedPage {
                Text(L10n.format("toc.pageLabel", targetedPageNumber, locale: locale))
                    .tag(Target.targetedPage)
            }
        }
        .pickerStyle(.segmented)
        .onChange(of: selectedTarget) {
            switch selectedTarget {
            case .allPages:
                _ = viewModel.setOverlayPDFTarget(nil)
            case .thisPage:
                _ = viewModel.setOverlayPDFTarget(currentPageRef?.id)
            case .targetedPage:
                break
            }
        }
    }

    private var actionButtons: some View {
        HStack(spacing: .dsSM) {
            Button(chooseButtonTitle) {
                isShowingImporter = true
            }

            if let overlay {
                Button(
                    L10n.string("inspector.decorate.overlayPDF.remove", locale: locale),
                    role: .destructive
                ) {
                    _ = viewModel.setOverlayPDF(
                        data: nil,
                        placement: overlayPDFPlacement.wrappedValue,
                        pageRefID: overlay.pageRefID
                    )
                }
            }
        }
    }

    private var chooseButtonTitle: String {
        L10n.string(
            overlay == nil
                ? "inspector.decorate.overlayPDF.choose"
                : "inspector.decorate.overlayPDF.replace",
            locale: locale
        )
    }

    private func importOverlayPDF(_ result: Result<[URL], any Error>) {
        guard case let .success(urls) = result, let url = urls.first else { return }
        do {
            let data = try SecurityScopedAccess.withAccess(to: url) { scopedURL in
                try Data(contentsOf: scopedURL)
            }
            let didSetOverlay = if overlay != nil {
                viewModel.replaceOverlayPDF(
                    data: data,
                    placement: overlayPDFPlacement.wrappedValue
                )
            } else {
                viewModel.setOverlayPDF(
                    data: data,
                    placement: overlayPDFPlacement.wrappedValue,
                    pageRefID: selectedTarget == .thisPage ? currentPageRef?.id : nil
                )
            }
            if !didSetOverlay {
                isShowingImportError = true
            }
        } catch {
            isShowingImportError = true
        }
    }
}

private struct PageCropSheet: View {
    @Bindable var viewModel: WorkspaceViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var top = 0.0
    @State private var bottom = 0.0
    @State private var left = 0.0
    @State private var right = 0.0

    private var margins: PageCropMargins {
        PageCropMargins(
            top: CGFloat(top),
            bottom: CGFloat(bottom),
            left: CGFloat(left),
            right: CGFloat(right)
        )
    }

    private var currentPageRef: PageRef? {
        let pageOrder = viewModel.document.workspace.pageOrder
        let currentIndex = viewModel.currentPageNumber - 1
        if pageOrder.indices.contains(currentIndex) {
            return pageOrder[currentIndex]
        }
        if let selectedPageRefID = viewModel.selectedPageRefID {
            return pageOrder.first { $0.id == selectedPageRefID }
        }
        return pageOrder.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: .dsLG) {
            VStack(alignment: .leading, spacing: .dsXS) {
                Text(L10n.string("inspector.crop.title", locale: locale))
                    .font(.system(size: 18, weight: .semibold, design: .serif))
                    .foregroundStyle(Color.dsTextPrimary)
                Text(L10n.string("inspector.crop.description", locale: locale))
                    .font(.dsCaption())
                    .foregroundStyle(Color.dsTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: .dsSM) {
                marginStepper(L10n.string("inspector.crop.top", locale: locale), value: $top)
                marginStepper(L10n.string("inspector.crop.bottom", locale: locale), value: $bottom)
                marginStepper(L10n.string("inspector.crop.left", locale: locale), value: $left)
                marginStepper(L10n.string("inspector.crop.right", locale: locale), value: $right)
            }

            HStack(spacing: .dsSM) {
                Button(L10n.string("inspector.crop.cancel", locale: locale)) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button(L10n.string("inspector.crop.applyThisPage", locale: locale)) {
                    guard let currentPageRef,
                          viewModel.applyPageCrop(margins: margins, to: [currentPageRef]) else { return }
                    dismiss()
                }
                .disabled(currentPageRef == nil)

                Button(L10n.string("inspector.crop.applyAllPages", locale: locale)) {
                    guard viewModel.applyPageCrop(
                        margins: margins,
                        to: viewModel.document.workspace.pageOrder
                    ) else { return }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.dsAccent)
                .disabled(viewModel.document.workspace.pageOrder.isEmpty)
            }
        }
        .padding(.dsXL)
        .frame(width: 460)
        .background(Color.dsSurface)
    }

    private func marginStepper(_ label: String, value: Binding<Double>) -> some View {
        Stepper(value: value, in: 0...2_000, step: 1) {
            Text(L10n.format("inspector.crop.marginValue", label, Int(value.wrappedValue), locale: locale))
                .font(.dsBody())
                .foregroundStyle(Color.dsTextPrimary)
        }
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

    private var selectedPageDescription: String {
        switch viewModel.ocrPageSelection {
        case .scannedPagesOnly:
            return viewModel.scannedPageCount == 1
                ? L10n.format("inspector.ocr.scannedPages.one", viewModel.scannedPageCount, locale: locale)
                : L10n.format("inspector.ocr.scannedPages.other", viewModel.scannedPageCount, locale: locale)
        case .allVisiblePages:
            return viewModel.ocrCandidatePageCount == 1
                ? L10n.format("inspector.ocr.visiblePages.one", viewModel.ocrCandidatePageCount, locale: locale)
                : L10n.format("inspector.ocr.visiblePages.other", viewModel.ocrCandidatePageCount, locale: locale)
        }
    }

    private var statusTitle: String {
        if viewModel.isMakingSearchable {
            return L10n.string("inspector.ocr.status.makingSearchable", locale: locale)
        }
        if viewModel.lastOCRQualityReport != nil {
            return L10n.string("inspector.ocr.status.qualityReceipt", locale: locale)
        }
        if viewModel.hasScannedPages && !viewModel.canStartSearchable {
            return L10n.string("inspector.ocr.status.waiting", locale: locale)
        }
        if viewModel.hasScannedPages {
            return L10n.string("inspector.ocr.status.scannedPagesDetected", locale: locale)
        }
        if viewModel.ocrCandidatePageCount > 0 {
            return L10n.string("inspector.ocr.status.textLayerDetected", locale: locale)
        }
        return L10n.string("inspector.ocr.status.searchableReady", locale: locale)
    }

    private var statusDetail: String {
        if viewModel.isMakingSearchable {
            return viewModel.operationProgress.detail
        }
        if viewModel.hasCommittedEditsBlockingOCR {
            return L10n.string("status.ocr.finishEditsBeforeOCR", locale: locale)
        }
        if viewModel.lastOCRQualityReport != nil {
            return L10n.string("inspector.ocr.detail.qualityReceipt", locale: locale)
        }
        if viewModel.hasScannedPages && !viewModel.canStartSearchable {
            return L10n.string("inspector.ocr.detail.finishBeforeRunningOCR", locale: locale)
        }
        if viewModel.hasScannedPages {
            return viewModel.scannedPageCount == 1
                ? L10n.format("inspector.ocr.scannedPages.one", viewModel.scannedPageCount, locale: locale)
                : L10n.format("inspector.ocr.scannedPages.other", viewModel.scannedPageCount, locale: locale)
        }
        if viewModel.ocrCandidatePageCount > 0 {
            return L10n.string("inspector.ocr.detail.textFoundNoAutoRun", locale: locale)
        }
        return L10n.string("inspector.ocr.detail.noPagesNeedOCR", locale: locale)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: .dsLG) {
            VStack(alignment: .leading, spacing: .dsMD) {
                HStack(alignment: .top, spacing: .dsMD) {
                    Image(systemName: statusIconName)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(statusIconColor)
                        .frame(width: 24, height: 24)

                    VStack(alignment: .leading, spacing: .dsXS) {
                        Text(statusTitle)
                            .font(.dsBody().weight(.semibold))
                            .foregroundStyle(Color.dsTextPrimary)
                        Text(statusDetail)
                            .font(.dsCaption())
                            .foregroundStyle(Color.dsTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if viewModel.isMakingSearchable {
                    ProgressView(value: viewModel.operationProgress.fraction)
                        .progressViewStyle(.linear)
                        .tint(Color.dsAccent)
                }

                OCRPipelineRail(
                    hasEligiblePages: viewModel.ocrSelectedPageCount > 0,
                    isRunning: viewModel.isMakingSearchable,
                    report: viewModel.lastOCRQualityReport,
                    locale: locale
                )
            }
            .padding(.dsLG)
            .foldedCard(
                fill: Color.dsCard,
                stroke: viewModel.lastOCRQualityReport?.needsReview == true
                    ? Color.dsWarningAccent.opacity(0.35)
                    : Color.dsSeparator,
                foldSize: 12
            )

            VStack(alignment: .leading, spacing: .dsMD) {
                Label(L10n.string("inspector.ocr.workbench.title", locale: locale), systemImage: "slider.horizontal.3")
                    .font(.dsCaption().weight(.semibold))
                    .foregroundStyle(Color.dsTextPrimary)

                OCRSettingRow(title: L10n.string("inspector.ocr.pages.label", locale: locale)) {
                    Picker("", selection: $viewModel.ocrPageSelection) {
                        Text(L10n.string("inspector.ocr.pages.scansOnly", locale: locale))
                            .tag(PDFOCROptions.PageSelection.scannedPagesOnly)
                        Text(L10n.string("inspector.ocr.pages.allVisible", locale: locale))
                            .tag(PDFOCROptions.PageSelection.allVisiblePages)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .disabled(viewModel.isMakingSearchable)
                }

                Text(selectedPageDescription)
                    .font(.dsCaption())
                    .foregroundStyle(Color.dsTextTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                Divider()

                OCRSettingRow(title: L10n.string("inspector.ocr.language.label", locale: locale)) {
                    Picker("", selection: $viewModel.ocrRecognitionLanguage) {
                        Text(L10n.string("inspector.ocr.language.automatic", locale: locale)).tag("")
                        ForEach(viewModel.supportedOCRLanguages, id: \.self) { language in
                            Text(languageName(for: language)).tag(language)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .disabled(viewModel.isMakingSearchable)
                }

                OCRSettingRow(title: L10n.string("inspector.ocr.engine.label", locale: locale)) {
                    Label(
                        L10n.string("inspector.ocr.engine.vision", locale: locale),
                        systemImage: "cpu"
                    )
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.dsTextSecondary)
                    .multilineTextAlignment(.trailing)
                }

                Toggle(
                    L10n.string("inspector.ocr.continueAfterFailure.label", locale: locale),
                    isOn: $viewModel.ocrContinuesAfterPageFailure
                )
                .font(.dsCaption())
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(viewModel.isMakingSearchable)

                Text(L10n.string("inspector.ocr.continueAfterFailure.detail", locale: locale))
                    .font(.dsCaption())
                    .foregroundStyle(Color.dsTextTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                if viewModel.ocrPageSelection == .allVisiblePages {
                    Label(
                        L10n.string("inspector.ocr.pages.allVisibleWarning", locale: locale),
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.dsCaption())
                    .foregroundStyle(Color.dsWarningAccent)
                    .fixedSize(horizontal: false, vertical: true)
                }

                if viewModel.hasCryptographicSignaturePlacement || viewModel.hasThirdPartyCryptographicSignature {
                    Label(
                        L10n.string(
                            viewModel.hasCryptographicSignaturePlacement
                                ? "status.signature.editInvalidates"
                                : "status.signature.thirdPartyEditInvalidates",
                            locale: locale
                        ),
                        systemImage: "signature"
                    )
                    .font(.dsCaption())
                    .foregroundStyle(Color.dsWarningAccent)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let report = viewModel.lastOCRQualityReport {
                OCRQualityReceipt(report: report, locale: locale)
            }

            Label(L10n.string("inspector.ocr.privacy.localOnly", locale: locale), systemImage: "lock.shield")
                .font(.dsCaption())
                .foregroundStyle(Color.dsTextSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                if viewModel.isMakingSearchable {
                    viewModel.cancelActiveOperation()
                } else {
                    viewModel.makeSearchable()
                }
            } label: {
                Label(buttonTitle,
                      systemImage: viewModel.isMakingSearchable ? "xmark.circle" : "doc.text.viewfinder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .disabled(!viewModel.isMakingSearchable && !viewModel.canStartConfiguredOCR)
            .help(buttonHelp)
        }
        .padding(.horizontal, .dsLG)
        .padding(.vertical, .dsXL)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var buttonHelp: String {
        if viewModel.isMakingSearchable {
            return L10n.string("inspector.ocr.help.cancelMakingSearchable", locale: locale)
        }
        if viewModel.hasCommittedEditsBlockingOCR {
            return L10n.string("status.ocr.finishEditsBeforeOCR", locale: locale)
        }
        if viewModel.canStartConfiguredOCR {
            return L10n.string("inspector.ocr.help.runLocalOCR", locale: locale)
        }
        if viewModel.canAddOCRLayerToSearchablePages {
            return L10n.string("inspector.ocr.help.runOCRAnyway", locale: locale)
        }
        if viewModel.hasScannedPages {
            return L10n.string("inspector.ocr.help.finishBeforeRunningOCR", locale: locale)
        }
        if viewModel.ocrCandidatePageCount > 0 {
            return L10n.string("inspector.ocr.help.finishBeforeRepairing", locale: locale)
        }
        return L10n.string("inspector.ocr.help.noPagesDetected", locale: locale)
    }

    private var buttonTitle: String {
        if viewModel.isMakingSearchable {
            return L10n.string("inspector.ocr.button.cancelOCR", locale: locale)
        }
        if viewModel.ocrPageSelection == .allVisiblePages {
            return L10n.string("inspector.ocr.button.runOCRAnyway", locale: locale)
        }
        return L10n.string("inspector.ocr.button.makeSearchable", locale: locale)
    }

    private var statusIconName: String {
        if viewModel.isMakingSearchable { return "waveform.badge.magnifyingglass" }
        if viewModel.lastOCRQualityReport?.needsReview == true { return "checkmark.circle.badge.questionmark" }
        if viewModel.lastOCRQualityReport != nil { return "checkmark.seal" }
        if viewModel.hasScannedPages { return "doc.text.viewfinder" }
        return viewModel.ocrCandidatePageCount > 0 ? "text.viewfinder" : "checkmark.circle"
    }

    private var statusIconColor: Color {
        if viewModel.lastOCRQualityReport?.needsReview == true { return Color.dsWarningAccent }
        if viewModel.lastOCRQualityReport != nil { return Color.dsSuccessAccent }
        return viewModel.ocrCandidatePageCount > 0 ? Color.dsAccent : Color.dsSuccessAccent
    }

    private func languageName(for identifier: String) -> String {
        locale.localizedString(forIdentifier: identifier)
            ?? Locale.current.localizedString(forIdentifier: identifier)
            ?? identifier
    }
}

private struct OCRSettingRow<Control: View>: View {
    let title: String
    let control: Control

    init(title: String, @ViewBuilder control: () -> Control) {
        self.title = title
        self.control = control()
    }

    var body: some View {
        HStack(spacing: .dsMD) {
            Text(title)
                .font(.dsCaption())
                .foregroundStyle(Color.dsTextSecondary)
            Spacer(minLength: .dsSM)
            control
                .frame(maxWidth: 158, alignment: .trailing)
        }
    }
}

private struct OCRQualityReceipt: View {
    let report: PDFOCRQualityReport
    let locale: Locale

    var body: some View {
        VStack(alignment: .leading, spacing: .dsMD) {
            HStack(spacing: .dsSM) {
                Image(systemName: report.needsReview ? "checkmark.circle.badge.questionmark" : "checkmark.seal")
                    .foregroundStyle(report.needsReview ? Color.dsWarningAccent : Color.dsSuccessAccent)
                Text(L10n.string("inspector.ocr.receipt.title", locale: locale))
                    .font(.dsCaption().weight(.semibold))
                    .foregroundStyle(Color.dsTextPrimary)
            }

            HStack(alignment: .top, spacing: .dsSM) {
                qualityMetric(
                    value: "\(report.recognizedPageCount)/\(report.requestedPageCount)",
                    label: L10n.string("inspector.ocr.receipt.pages", locale: locale)
                )
                qualityMetric(
                    value: "\(report.recognizedLineCount)",
                    label: L10n.string("inspector.ocr.receipt.lines", locale: locale)
                )
                qualityMetric(
                    value: "\(report.reviewItemCount)",
                    label: L10n.string("inspector.ocr.receipt.confidence", locale: locale)
                )
            }

            Label(
                L10n.string("inspector.ocr.receipt.integrityPassed", locale: locale),
                systemImage: report.integrityChecksPassed ? "checkmark.shield" : "exclamationmark.shield"
            )
            .font(.dsCaption())
            .foregroundStyle(report.integrityChecksPassed ? Color.dsSuccessAccent : Color.dsWarningAccent)
            .fixedSize(horizontal: false, vertical: true)

            if !report.skippedPageNumbers.isEmpty {
                Label(
                    L10n.format(
                        "inspector.ocr.receipt.skippedPages",
                        report.skippedPageNumbers.map(String.init).joined(separator: ", "),
                        locale: locale
                    ),
                    systemImage: "exclamationmark.triangle"
                )
                .font(.dsCaption())
                .foregroundStyle(Color.dsWarningAccent)
                .fixedSize(horizontal: false, vertical: true)
            }

            if report.lowConfidenceLineCount > 0 {
                Text(L10n.format("inspector.ocr.receipt.lowConfidence", report.lowConfidenceLineCount, locale: locale))
                    .font(.dsCaption())
                    .foregroundStyle(Color.dsTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(L10n.string("inspector.ocr.receipt.caveat", locale: locale))
                .font(.system(size: 11))
                .foregroundStyle(Color.dsTextTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.dsLG)
        .foldedCard(
            fill: Color.dsCard,
            stroke: report.needsReview ? Color.dsWarningAccent.opacity(0.35) : Color.dsSeparator
        )
        .accessibilityElement(children: .contain)
    }

    private func qualityMetric(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.dsTextPrimary)
                .monospacedDigit()
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(Color.dsTextTertiary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct OCRPipelineRail: View {
    private enum StageState: Equatable {
        case idle
        case active
        case complete
        case review

        var color: Color {
            switch self {
            case .idle: Color.dsTextTertiary
            case .active: Color.dsAccent
            case .complete: Color.dsSuccessAccent
            case .review: Color.dsWarningAccent
            }
        }
    }

    let hasEligiblePages: Bool
    let isRunning: Bool
    let report: PDFOCRQualityReport?
    let locale: Locale

    private var pageState: StageState {
        hasEligiblePages || report != nil ? .complete : .idle
    }

    private var recognitionState: StageState {
        if isRunning { return .active }
        if report != nil { return .complete }
        return hasEligiblePages ? .active : .idle
    }

    private var verificationState: StageState {
        guard let report else { return .idle }
        return report.needsReview ? .review : .complete
    }

    var body: some View {
        HStack(spacing: 0) {
            stage(
                title: L10n.string("inspector.ocr.pages.label", locale: locale),
                icon: "doc.on.doc",
                state: pageState
            )
            connector(from: pageState, to: recognitionState)
            stage(
                title: L10n.string("inspector.ocr.pipeline.recognize", locale: locale),
                icon: "text.viewfinder",
                state: recognitionState
            )
            connector(from: recognitionState, to: verificationState)
            stage(
                title: L10n.string("inspector.ocr.pipeline.verify", locale: locale),
                icon: "checkmark.shield",
                state: verificationState
            )
        }
        .padding(.top, .dsXS)
    }

    private func stage(title: String, icon: String, state: StageState) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(state.color)
                .frame(width: 24, height: 24)
                .background(state.color.opacity(state == .idle ? 0.08 : 0.14), in: Circle())
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(state.color)
                .lineLimit(1)
        }
        .frame(width: 60)
    }

    private func connector(from: StageState, to: StageState) -> some View {
        let color = from == .complete && to != .idle ? to.color : Color.dsSeparator
        return Capsule()
            .fill(color.opacity(to == .idle ? 1 : 0.55))
            .frame(maxWidth: .infinity)
            .frame(height: 2)
            .offset(y: -8)
    }
}

// MARK: - Attachments tab

private struct InspectorAttachmentsView: View {
    var viewModel: WorkspaceViewModel
    // Read so SwiftUI re-invokes `body` when the app language changes.
    @Environment(\.locale) private var locale

    // Attachments of the active member; `manageable == false` means qpdf can't
    // read the member (encrypted, no stored password) or there is no member, in
    // which case add/remove are disabled and a hint is shown.
    @State private var attachments: [PDFAttachment] = []
    @State private var manageable = false
    @State private var isDropTargeted = false

    private static let sizeFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    var body: some View {
        let _ = locale
        VStack(alignment: .leading, spacing: .dsLG) {
            if manageable {
                if attachments.isEmpty {
                    Text(L10n.string("attachments.empty", locale: locale))
                        .font(.dsBody())
                        .foregroundStyle(Color.dsTextSecondary)
                } else {
                    VStack(spacing: .dsSM) {
                        ForEach(attachments, id: \.name) { attachment in
                            attachmentRow(attachment)
                        }
                    }
                }

                Button {
                    presentAddPanel()
                } label: {
                    Label(L10n.string("attachments.add", locale: locale), systemImage: "paperclip")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.dsAccent)

                Text(L10n.string("attachments.dropHint", locale: locale))
                    .font(.dsCaption())
                    .foregroundStyle(Color.dsTextTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                Text(L10n.string("attachments.encrypted.disabled", locale: locale))
                    .font(.dsBody())
                    .foregroundStyle(Color.dsTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, .dsLG)
        .padding(.vertical, .dsXL)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: .dsRadiusSm, style: .continuous)
                .fill(isDropTargeted ? Color.dsAccent.opacity(0.08) : Color.clear)
        }
        .inspectorDraft(from: viewModel, seed: reload)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
    }

    private func attachmentRow(_ attachment: PDFAttachment) -> some View {
        HStack(spacing: .dsMD) {
            Image(systemName: "doc")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.dsTextSecondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(attachment.name)
                    .font(.dsBody())
                    .foregroundStyle(Color.dsTextPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(subtitle(for: attachment))
                    .font(.dsCaption())
                    .foregroundStyle(Color.dsTextTertiary)
            }

            Spacer(minLength: .dsSM)

            Button {
                presentExtractPanel(for: attachment)
            } label: {
                Image(systemName: "square.and.arrow.down")
            }
            .buttonStyle(.borderless)
            .help(L10n.string("attachments.extract", locale: locale))
            .accessibilityLabel(L10n.string("attachments.extract", locale: locale))

            Button {
                viewModel.removeAttachment(named: attachment.name)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help(L10n.string("attachments.remove", locale: locale))
            .accessibilityLabel(L10n.string("attachments.remove", locale: locale))
        }
        .padding(.vertical, .dsXS)
    }

    private func subtitle(for attachment: PDFAttachment) -> String {
        let size = Self.sizeFormatter.string(fromByteCount: Int64(attachment.byteCount))
        if let mime = attachment.mimeType, !mime.isEmpty {
            return "\(size) · \(mime)"
        }
        return size
    }

    private func reload() {
        if let list = viewModel.activeMemberAttachments() {
            attachments = list
            manageable = true
        } else {
            attachments = []
            manageable = false
        }
    }

    private func presentAddPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.title = L10n.string("attachments.add", locale: locale)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        viewModel.addAttachment(url)
    }

    private func presentExtractPanel(for attachment: PDFAttachment) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = attachment.name
        panel.title = L10n.string("attachments.extract", locale: locale)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        viewModel.extractAttachment(named: attachment.name, to: url)
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard manageable, let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            DispatchQueue.main.async {
                viewModel.addAttachment(url)
            }
        }
        return true
    }
}

private struct InspectorMarkupView: View {
    @Bindable var viewModel: WorkspaceViewModel
    // Read so SwiftUI re-invokes `body` when the app language changes.
    @Environment(\.locale) private var locale

    private var allAnnotations: [(page: PDFPage, annotation: PDFAnnotation, memberName: String)] {
        var result: [(PDFPage, PDFAnnotation, String)] = []
        for (member, pdf) in viewModel.loadedPDFs {
            for i in 0..<pdf.pageCount {
                guard let page = pdf.page(at: i) else { continue }
                for ann in BakeStamp.userAnnotations(on: page) {
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
        let _ = locale
        // Compute the (expensive) cross-document annotation walk and the text-edit
        // list ONCE per render, not per property access. `allAnnotations` iterates
        // every loaded PDF × every page × every annotation; reading it separately for
        // the empty-check and the ForEach did that whole walk twice on every `body`
        // evaluation (and `body` re-runs on any @Observable view-model change while
        // this tab is open). One local snapshot also fixes the stale-index risk: rows
        // key off the captured element's own object identity, never a recomputed array.
        let annotations = allAnnotations
        let edits = textEdits
        if annotations.isEmpty && viewModel.selectedAnnotation == nil && edits.isEmpty
            && !viewModel.canRestyleSelectedObject {
            VStack(spacing: .dsSM) {
                Image(systemName: "highlighter")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(Color.dsTextTertiary)
                Text(L10n.string("inspector.markup.empty.title"))
                    .font(.dsBody())
                    .foregroundStyle(Color.dsTextSecondary)
                Text(L10n.string("inspector.markup.empty.subtitle"))
                    .font(.dsCaption())
                    .foregroundStyle(Color.dsTextTertiary)
                    .multilineTextAlignment(.center)
            }
            .padding(.dsXXL)
            .frame(maxWidth: .infinity)
        } else {
            LazyVStack(alignment: .leading, spacing: 0) {
                if viewModel.canRestyleSelectedObject {
                    InspectorObjectStyleSection(viewModel: viewModel)
                        .id(viewModel.objectSelection?.object.stableKey)
                    Rectangle().fill(Color.dsSeparator).frame(height: 0.5)
                }
                if let selected = viewModel.selectedAnnotation {
                    InspectorEditingDetails(ann: selected)
                    Rectangle().fill(Color.dsSeparator).frame(height: 0.5)
                }
                if !edits.isEmpty {
                    InspectorTextEditsSection(viewModel: viewModel, textEdits: edits)
                    Rectangle().fill(Color.dsSeparator).frame(height: 0.5)
                }
                ForEach(annotations, id: \.annotation) { entry in
                    InspectorAnnotationRow(
                        ann: entry.annotation,
                        memberName: entry.memberName,
                        isSelected: viewModel.selectedAnnotation === entry.annotation,
                        onSelect: {
                            viewModel.selectedAnnotation = entry.annotation
                            viewModel.selectedStampDecorationID = nil
                            NotificationCenter.default.post(
                                name: .orifoldJumpToAnnotation,
                                object: entry.annotation
                            )
                        },
                        onEdit: {
                            viewModel.selectedAnnotation = entry.annotation
                            viewModel.selectedStampDecorationID = nil
                            NotificationCenter.default.post(
                                name: .orifoldEditAnnotation,
                                object: entry.annotation
                            )
                        },
                        onDelete: {
                            viewModel.selectedAnnotation = entry.annotation
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

private struct InspectorObjectStyleSection: View {
    @Bindable var viewModel: WorkspaceViewModel
    @Environment(\.locale) private var locale
    @State private var fillColor: Color
    @State private var strokeColor: Color
    @State private var lineWidth: CGFloat

    init(viewModel: WorkspaceViewModel) {
        self.viewModel = viewModel
        let style = viewModel.objectSelection?.object.style ?? PDFObjectStyle()
        _fillColor = State(initialValue: Color(nsColor: style.fillColor?.nsColor ?? .black))
        _strokeColor = State(initialValue: Color(nsColor: style.strokeColor?.nsColor ?? .black))
        _lineWidth = State(initialValue: min(max(style.lineWidth, 0.25), 24))
    }

    private var fillPayload: CodableColor? {
        viewModel.selectedObjectHasEditableFill
            ? CodableColor(nsColor: NSColor(fillColor))
            : nil
    }

    private var strokePayload: CodableColor? {
        viewModel.selectedObjectHasEditableStroke
            ? CodableColor(nsColor: NSColor(strokeColor))
            : nil
    }

    private var isDirty: Bool {
        guard let style = viewModel.objectSelection?.object.style else { return false }
        if viewModel.selectedObjectHasEditableFill, fillPayload != style.fillColor { return true }
        if viewModel.selectedObjectHasEditableStroke {
            if strokePayload != style.strokeColor { return true }
            if abs(lineWidth - style.lineWidth) > 0.001 { return true }
        }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: .dsMD) {
            HStack(alignment: .top, spacing: .dsSM) {
                Image(systemName: "paintpalette")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.dsAccent)
                    .frame(width: 20, height: 20)
                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.string("object.style.title", locale: locale))
                        .font(.dsBody().weight(.semibold))
                        .foregroundStyle(Color.dsTextPrimary)
                    Text(L10n.string("object.style.description", locale: locale))
                        .font(.dsCaption())
                        .foregroundStyle(Color.dsTextTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if viewModel.selectedObjectHasEditableFill {
                ColorPicker(
                    L10n.string("object.style.fill", locale: locale),
                    selection: $fillColor,
                    supportsOpacity: false
                )
                .font(.dsBody())
            }

            if viewModel.selectedObjectHasEditableStroke {
                ColorPicker(
                    L10n.string("object.style.stroke", locale: locale),
                    selection: $strokeColor,
                    supportsOpacity: false
                )
                .font(.dsBody())

                Stepper(value: $lineWidth, in: 0.25...24, step: 0.25) {
                    HStack {
                        Text(L10n.string("object.style.lineWidth", locale: locale))
                        Spacer()
                        Text(lineWidth, format: .number.precision(.fractionLength(0...2)))
                            .foregroundStyle(Color.dsTextSecondary)
                            .monospacedDigit()
                    }
                    .font(.dsBody())
                }
            }

            HStack {
                Spacer()
                Button(L10n.string("inspector.metadata.apply", locale: locale)) {
                    _ = viewModel.restyleSelectedObject(
                        fillColor: fillPayload,
                        strokeColor: strokePayload,
                        lineWidth: viewModel.selectedObjectHasEditableStroke ? lineWidth : nil
                    )
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.dsAccent)
                .disabled(!isDirty)
            }
        }
        .padding(.horizontal, .dsLG)
        .padding(.vertical, .dsXL)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct InspectorTextEditsSection: View {
    @Bindable var viewModel: WorkspaceViewModel
    var textEdits: [WorkspaceViewModel.InlineTextEditListItem]
    // Read so SwiftUI re-invokes `body` when the app language changes.
    @Environment(\.locale) private var locale

    var body: some View {
        let _ = locale
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: .dsSM) {
                InspectorSectionHeader(title: L10n.string("inspector.textEdit.section.title", locale: locale), count: textEdits.count)
                Spacer()
                Button(L10n.string("inspector.textEdit.revertAll.button")) {
                    viewModel.revertAllInlineTextEdits()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.dsAccent)
                .padding(.trailing, .dsMD)
                .help(L10n.string("inspector.textEdit.revertAll.help"))
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

    private var kindBadge: (title: String, color: Color, icon: String) {
        switch item.kind {
        case .insertion: return (L10n.string("inspector.textEdit.kind.added", locale: locale), .dsAccent, "plus.square")
        case .deletion: return (L10n.string("inspector.textEdit.kind.deleted", locale: locale), Color(nsColor: .systemRed), "text.badge.minus")
        case .styleOnly: return (L10n.string("inspector.textEdit.kind.restyled", locale: locale), Color(nsColor: .systemPurple), "paintbrush")
        case .edit: return (L10n.string("inspector.textEdit.kind.edited", locale: locale), Color(nsColor: .systemTeal), "character.cursor.ibeam")
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
            .help(L10n.string("inspector.textEdit.showThisPage.help"))

            Button(action: onRevert) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Color.dsTextTertiary)
            .help(L10n.string(item.isInsertion ? "inspector.textEdit.removeAdded.help" : "inspector.textEdit.restoreOriginal.help", locale: locale))
        }
        .padding(.horizontal, .dsMD)
        .padding(.vertical, .dsSM)
        .contentShape(Rectangle())
    }
}

private struct InspectorEditingDetails: View {
    var ann: PDFAnnotation
    // Read so SwiftUI re-invokes `body` when the app language changes.
    @Environment(\.locale) private var locale

    private var isEditableText: Bool { ann.type == "FreeText" || ann.type == "Text" }

    var body: some View {
        let _ = locale
        VStack(alignment: .leading, spacing: .dsSM) {
            HStack(spacing: .dsSM) {
                Image(systemName: "slider.horizontal.3")
                    .foregroundStyle(Color.dsAccent)
                Text(L10n.string("inspector.editingDetails.title"))
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
            .help(L10n.string("inspector.annotation.select.help"))

            if canEditContents {
                Button(action: onEdit) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Color.dsTextTertiary)
                .help(L10n.string("inspector.annotation.edit.help"))
            }

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Color.dsTextTertiary)
            .help(L10n.string("inspector.annotation.delete.help"))
        }
        .padding(.horizontal, .dsMD)
        .padding(.vertical, .dsSM)
        .background(isSelected ? Color.dsAccentSoft.opacity(0.35) : Color.clear)
        .contentShape(Rectangle())
    }
}

/// The lifecycle an inspector tab needs when it edits through a local draft: seed the draft
/// from the model on appear, re-seed when the targeted member changes, and re-seed when the
/// workspace rebuilds.
///
/// That third trigger is the load-bearing one and the least obvious. Undo/redo of a member
/// edit reverts the model but leaves `activeDocumentID` unchanged, so without it the fields
/// keep showing pre-undo values — and a re-Apply re-commits them. It was added once as a bug
/// fix and then hand-copied to the next tab; as a modifier a new tab gets it by default rather
/// than having to know it exists.
///
/// Tabs need no manual re-seed after their own mutations: every mutation that changes the
/// model routes through `rebuild()`, which bumps `structureRevision` and fires this.
private struct InspectorDraftLifecycle: ViewModifier {
    let viewModel: WorkspaceViewModel
    let seed: () -> Void

    func body(content: Content) -> some View {
        content
            .onAppear(perform: seed)
            .onChange(of: viewModel.activeDocumentID) { _, _ in seed() }
            .onChange(of: viewModel.structureRevision) { _, _ in seed() }
    }
}

private extension View {
    func inspectorDraft(from viewModel: WorkspaceViewModel, seed: @escaping () -> Void) -> some View {
        modifier(InspectorDraftLifecycle(viewModel: viewModel, seed: seed))
    }
}

// MARK: - Structure

/// `OutlineGroup` needs stable identity, and `StructureNode` deliberately carries none —
/// it is derived from bytes, so a per-walk UUID would make two reads of the same document
/// compare unequal. The index path supplies identity here, at the display layer, where it
/// belongs.
private struct StructureRow: Identifiable {
    let id: String
    let node: StructureNode
    /// nil rather than empty: `OutlineGroup` draws a disclosure control for an empty
    /// array, which would expand to nothing.
    let children: [StructureRow]?

    static func rows(from nodes: [StructureNode], prefix: String = "") -> [StructureRow] {
        nodes.enumerated().map { index, node in
            let id = prefix.isEmpty ? "\(index)" : "\(prefix).\(index)"
            return StructureRow(
                id: id,
                node: node,
                children: node.children.isEmpty ? nil : rows(from: node.children, prefix: id)
            )
        }
    }
}

/// Reports a page's tagged structure, and says plainly when there is none.
///
/// Read-only by design: PDFium exposes no tag-writing API, so this tab can tell a user
/// their document is inaccessible to screen readers but cannot offer to fix it. Saying so
/// honestly is the whole feature — a silent empty tab would read as "nothing to see here"
/// rather than "this document has an accessibility problem."
private struct InspectorStructureView: View {
    @Bindable var viewModel: WorkspaceViewModel
    // Read so SwiftUI re-invokes `body` when the app language changes.
    @Environment(\.locale) private var locale

    private var structure: PageStructure? {
        // Touch both so the view re-evaluates when the document changes and when the
        // reader turns the page; the view model caches on exactly this pair.
        _ = viewModel.structureRevision
        _ = viewModel.currentPageNumber
        return viewModel.currentPageStructure()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: .dsMD) {
            if let structure {
                if !structure.isTagged {
                    untaggedCard
                } else if structure.roots.isEmpty {
                    Text(L10n.string("structure.empty", locale: locale))
                        .font(.dsBody())
                        .foregroundStyle(Color.dsTextSecondary)
                } else {
                    altTextSummary(for: structure)
                    tree(for: structure)
                }
            } else {
                Text(L10n.string("structure.empty", locale: locale))
                    .font(.dsBody())
                    .foregroundStyle(Color.dsTextSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.dsLG)
    }

    private var untaggedCard: some View {
        VStack(alignment: .leading, spacing: .dsSM) {
            HStack(spacing: .dsSM) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.dsWarningAccent)
                Text(L10n.string("structure.untagged.title", locale: locale))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.dsTextPrimary)
            }
            Text(L10n.string("structure.untagged.body", locale: locale))
                .font(.dsCaption())
                .foregroundStyle(Color.dsTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.dsMD)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.dsCard)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    /// The headline the tree can't give you: per-node badges only count if the reader
    /// expands every branch, and the tree arrives collapsed. This is the number someone
    /// auditing a document for accessibility actually came for.
    @ViewBuilder
    private func altTextSummary(for structure: PageStructure) -> some View {
        let missing = structure.imagesMissingAltText
        HStack(spacing: .dsSM) {
            Image(systemName: missing == 0 ? "checkmark.seal" : "exclamationmark.triangle.fill")
                .foregroundStyle(missing == 0 ? Color.dsSuccessAccent : Color.dsWarningAccent)
            Text(missing == 0
                 ? L10n.string("structure.altText.allPresent", locale: locale)
                 : L10n.format(
                    missing == 1 ? "structure.altText.missing.one" : "structure.altText.missing.other",
                    missing,
                    locale: locale
                 ))
                .font(.dsCaption())
                .foregroundStyle(Color.dsTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tree(for structure: PageStructure) -> some View {
        OutlineGroup(
            StructureRow.rows(from: structure.roots),
            children: \.children
        ) { row in
            HStack(spacing: .dsSM) {
                Text(row.node.role)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.dsAccent)
                if let title = row.node.title {
                    Text(title)
                        .font(.dsCaption())
                        .foregroundStyle(Color.dsTextPrimary)
                        .lineLimit(1)
                }
                if row.node.isImageLike, row.node.altText?.isEmpty ?? true {
                    Text(L10n.string("structure.noAltText", locale: locale))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.dsWarningAccent)
                        .padding(.horizontal, .dsXS)
                        .padding(.vertical, 1)
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(Color.dsWarningAccent.opacity(0.5), lineWidth: 0.5)
                        )
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 1)
        }
    }
}
