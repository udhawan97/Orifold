import SwiftUI
import PDFKit

/// Review step of blank-page removal: every candidate shows its thumbnail and workspace
/// page number, checked by default. Nothing is deleted until the user confirms, and
/// unchecking keeps a page — detection only ever proposes.
struct BlankPageReviewSheet: View {
    @Bindable var viewModel: WorkspaceViewModel
    let review: WorkspaceViewModel.BlankPageReview
    @Environment(\.locale) private var locale

    @State private var checkedRefIDs: Set<UUID> = []
    @State private var didSeed = false

    private var checkedRefs: [PageRef] {
        review.refs.filter { checkedRefIDs.contains($0.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.string("blank.sheet.title", locale: locale))
                .font(.headline)
            Text(L10n.string("blank.sheet.subtitle", locale: locale))
                .font(.caption)
                .foregroundStyle(.secondary)

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 12)], spacing: 12) {
                    ForEach(review.refs, id: \.id) { ref in
                        candidateCell(for: ref)
                    }
                }
                .padding(2)
            }
            .frame(minHeight: 140, maxHeight: 320)

            HStack {
                Spacer()
                Button(L10n.string("contentView.exportSheet.cancel.button", locale: locale)) {
                    viewModel.blankPageReview = nil
                }
                .keyboardShortcut(.cancelAction)
                Button(role: .destructive) {
                    viewModel.removeBlankPages(checkedRefs)
                } label: {
                    Text(removeButtonTitle)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(checkedRefs.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 440)
        .onAppear {
            guard !didSeed else { return }
            didSeed = true
            checkedRefIDs = Set(review.refs.map(\.id))
        }
    }

    private var removeButtonTitle: String {
        checkedRefs.count == 1
            ? L10n.string("blank.remove.one", locale: locale)
            : L10n.format("blank.remove.many", checkedRefs.count, locale: locale)
    }

    @ViewBuilder
    private func candidateCell(for ref: PageRef) -> some View {
        let isChecked = checkedRefIDs.contains(ref.id)
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                thumbnail(for: ref)
                    .frame(width: 88, height: 112)
                    .background(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(isChecked ? Color.accentColor : Color.secondary.opacity(0.3),
                                    lineWidth: isChecked ? 2 : 1)
                    )
                Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isChecked ? Color.accentColor : Color.secondary)
                    .padding(4)
            }
            Text(pageLabel(for: ref))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isChecked {
                checkedRefIDs.remove(ref.id)
            } else {
                checkedRefIDs.insert(ref.id)
            }
        }
        .accessibilityAddTraits(isChecked ? [.isSelected] : [])
    }

    @ViewBuilder
    private func thumbnail(for ref: PageRef) -> some View {
        if let page = viewModel.pdfPage(for: ref) {
            Image(nsImage: page.thumbnail(of: CGSize(width: 88, height: 112), for: .mediaBox))
                .resizable()
                .scaledToFit()
        } else {
            Rectangle().fill(Color.secondary.opacity(0.1))
        }
    }

    private func pageLabel(for ref: PageRef) -> String {
        let number = (viewModel.document.workspace.pageOrder.firstIndex { $0.id == ref.id }).map { $0 + 1 } ?? 0
        return L10n.format("blank.page.label", number, locale: locale)
    }
}
