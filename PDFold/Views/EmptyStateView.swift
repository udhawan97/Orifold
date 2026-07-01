import SwiftUI
import UniformTypeIdentifiers

struct EmptyStateView: View {
    var viewModel: WorkspaceViewModel
    @State private var isDropTargeted = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.dsCanvas.ignoresSafeArea()

            VStack(spacing: .dsXL) {
                // Wordmark block
                VStack(spacing: .dsLG) {
                    AppIconMark(size: 80)

                    VStack(spacing: 6) {
                        Text("pdFold")
                            .font(.dsDisplay(size: 36))
                            .foregroundStyle(Color.dsTextPrimary)
                        Text("Fold scattered pages into one polished PDF.")
                            .font(.dsHeadline())
                            .foregroundStyle(Color.dsTextPrimary)
                        Text("Combine, arrange, annotate, and export documents in one calm workspace.")
                            .font(.dsBody())
                            .foregroundStyle(Color.dsTextSecondary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(3)
                    }

                    HStack(spacing: .dsSM) {
                        EmptyStatePill(icon: "square.stack.3d.down.right", title: "Assemble")
                        EmptyStatePill(icon: "highlighter", title: "Mark up")
                        EmptyStatePill(icon: "square.and.arrow.up", title: "Export")
                    }
                }

                // Drop zone card
                VStack(spacing: .dsLG) {
                    Image(systemName: isDropTargeted ? "tray.and.arrow.down.fill" : "doc.badge.plus")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(Color.dsAccent)
                        .symbolRenderingMode(.hierarchical)
                        .animation(.easeInOut(duration: 0.15), value: isDropTargeted)

                    VStack(spacing: 5) {
                        Text(isDropTargeted ? "Release to import" : "Drop files to begin")
                            .font(.dsHeadline())
                            .foregroundStyle(Color.dsTextPrimary)
                        Text("PDF, Word, HTML, text, and images")
                            .font(.dsCaption())
                            .foregroundStyle(Color.dsTextTertiary)
                    }

                    Button {
                        openFiles()
                    } label: {
                        Label("Choose Files", systemImage: "folder.badge.plus")
                            .frame(minWidth: 140)
                    }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                    .tint(Color.dsAccent)
                }
                .padding(.horizontal, .dsXXL)
                .padding(.vertical, .dsXXL)
                .background(Color.dsCard, in: RoundedRectangle(cornerRadius: .dsRadiusLg, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: .dsRadiusLg, style: .continuous)
                        .strokeBorder(
                            isDropTargeted ? Color.dsAccent : Color.dsSeparator,
                            lineWidth: isDropTargeted ? 1.5 : 1
                        )
                        .animation(.easeInOut(duration: 0.15), value: isDropTargeted)
                }
                .dsElevation()
            }
            .padding(.dsXXL)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

            GuideButton(autoShow: true)
                .buttonStyle(.borderless)
                .font(.title3)
                .padding(.dsXL)
        }
        .overlay {
            RoundedRectangle(cornerRadius: .dsRadiusMd, style: .continuous)
                .strokeBorder(Color.dsAccent.opacity(isDropTargeted ? 0.5 : 0), lineWidth: 1.5)
                .padding(.dsMD)
                .animation(.easeInOut(duration: 0.15), value: isDropTargeted)
        }
        .onDrop(of: WorkspaceDocument.importableContentTypes + [.fileURL], isTargeted: $isDropTargeted) { providers in
            resolveImportURLs(from: providers) { urls in
                guard !urls.isEmpty else {
                    viewModel.importError = WorkspaceViewModel.ImportError(
                        fileName: "Dropped Files",
                        message: "pdFold could not find a supported document in that drop."
                    )
                    return
                }
                viewModel.importFiles(urls: urls)
            }
            return true
        }
    }

    private func openFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = WorkspaceDocument.importableContentTypes
        if panel.runModal() == .OK { viewModel.importFiles(urls: panel.urls) }
    }
}

private struct EmptyStatePill: View {
    var icon: String
    var title: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
            Text(title)
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(Color.dsAccent)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.dsAccentSoft, in: Capsule())
    }
}
