import SwiftUI
import PDFKit

struct TOCView: View {
    var viewModel: WorkspaceViewModel
    /// Called when the user taps an entry — jump the PDFView to that page.
    var onJump: ((Int) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Documents")
                .font(.headline)
                .padding(.horizontal)
                .padding(.vertical, 10)

            Divider()

            if viewModel.tableOfContents.isEmpty {
                Text("No documents in workspace.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
                    .padding()
            } else {
                List(viewModel.tableOfContents) { entry in
                    Button {
                        onJump?(entry.startPageIndex)
                    } label: {
                        HStack {
                            Image(systemName: "doc.richtext.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.title)
                                    .font(.callout)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text("Jump to first page")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }
        }
        .frame(width: 260)
    }
}
