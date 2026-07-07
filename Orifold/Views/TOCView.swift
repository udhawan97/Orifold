import SwiftUI
import PDFKit

struct TOCView: View {
    var viewModel: WorkspaceViewModel
    var onJump: ((Int) -> Void)?
    // Passed into L10n.format() below so this view's `body` actually reads it —
    // SwiftUI only re-invokes `body` on a locale change for views that read
    // `\.locale` during the previous evaluation.
    @Environment(\.locale) private var locale

    private var entries: [WorkspaceViewModel.TOCEntry] {
        viewModel.tableOfContents
    }

    private var popoverHeight: CGFloat {
        let rowHeight: CGFloat = 54
        let chromeHeight: CGFloat = 53
        return min(max(CGFloat(entries.count) * rowHeight + chromeHeight, 120), 360)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("toc.title")
                .font(.system(size: 15, weight: .semibold, design: .serif))
                .foregroundStyle(Color.dsTextPrimary)
                .padding(.horizontal, .dsLG)
                .padding(.top, .dsMD)
                .padding(.bottom, .dsSM)

            Rectangle().fill(Color.dsSeparator).frame(height: 0.5)

            if entries.isEmpty {
                Text("toc.empty")
                    .font(.dsBody())
                    .foregroundStyle(Color.dsTextSecondary)
                    .padding(.dsLG)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(entries) { entry in
                            Button {
                                onJump?(entry.jumpPageIndex)
                            } label: {
                                HStack(spacing: .dsSM) {
                                    Image(systemName: "doc.text.fill")
                                        .font(.system(size: 13))
                                        .foregroundStyle(Color.dsAccent)
                                        .frame(width: 18)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(entry.title)
                                            .font(.dsBody())
                                            .foregroundStyle(Color.dsTextPrimary)
                                            .lineLimit(1)
                                        Text(L10n.format("toc.pageLabel", entry.displayPageNumber, locale: locale))
                                            .font(.dsCaption())
                                            .foregroundStyle(Color.dsTextTertiary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(Color.dsTextTertiary)
                                }
                                .padding(.horizontal, .dsLG)
                                .frame(height: 54)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .background(Color.dsSurface)
            }
        }
        .frame(width: 280, height: popoverHeight)
        .background(Color.dsSurface)
    }
}
