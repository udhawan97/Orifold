import AppKit
import PDFKit
import SwiftUI

/// A proofing-desk treatment for the lossy scan cleanup operation: the current page stays
/// visible before and after, while scope and processing choices remain explicit below it.
struct ScanCleanupSheet: View {
    @Bindable var viewModel: WorkspaceViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    @State private var scope: ScanCleanupScope = .currentPage
    @State private var options = ScanCleanupOptions()
    @State private var preview: PreviewImages?
    @State private var isPreviewLoading = false
    @State private var previewFailed = false

    private var targetPageCount: Int {
        viewModel.scanCleanupTargetPageRefIDs(scope: scope).count
    }

    private var hasOperation: Bool {
        options.deskew || options.binarize || options.despeckle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: .dsLG) {
            header
            proofingDesk
            controls
            warning
            footer
        }
        .padding(.dsXL)
        .frame(width: 720)
        .background(Color.dsSurface)
        .interactiveDismissDisabled(viewModel.isApplyingScanCleanup)
        .task(id: options) {
            await refreshPreview()
        }
    }

    private var header: some View {
        HStack(spacing: .dsMD) {
            ZStack {
                RoundedRectangle(cornerRadius: .dsRadiusSm, style: .continuous)
                    .fill(LinearGradient.dsAccent)
                Image(systemName: "viewfinder.rectangular")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 42, height: 42)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.string("scanCleanup.title", locale: locale))
                    .font(.system(size: 18, weight: .semibold, design: .serif))
                    .foregroundStyle(Color.dsTextPrimary)
                Text(L10n.string("scanCleanup.subtitle", locale: locale))
                    .font(.system(size: 12))
                    .foregroundStyle(Color.dsTextSecondary)
            }
        }
    }

    private var proofingDesk: some View {
        HStack(spacing: 10) {
            previewCard(
                titleKey: "scanCleanup.preview.before",
                image: preview?.before,
                isCleaned: false
            )

            ZStack {
                Circle().fill(Color.dsAccentSoft)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.dsAccent)
            }
            .frame(width: 28, height: 28)
            .accessibilityHidden(true)

            previewCard(
                titleKey: "scanCleanup.preview.after",
                image: preview?.after,
                isCleaned: true
            )
        }
    }

    private func previewCard(titleKey: String, image: CGImage?, isCleaned: Bool) -> some View {
        VStack(alignment: .leading, spacing: .dsSM) {
            HStack {
                Text(L10n.string(forKey: titleKey, locale: locale))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.dsTextSecondary)
                    .textCase(.uppercase)
                Spacer()
                if isCleaned, !isPreviewLoading, image != nil {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.dsSuccessAccent)
                        .accessibilityHidden(true)
                }
            }

            ZStack {
                RoundedRectangle(cornerRadius: .dsRadiusSm, style: .continuous)
                    .fill(Color.dsCanvas)
                if isPreviewLoading {
                    ProgressView()
                        .controlSize(.small)
                } else if let image {
                    Image(nsImage: NSImage(
                        cgImage: image,
                        size: NSSize(width: image.width, height: image.height)
                    ))
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .padding(.dsSM)
                    .accessibilityHidden(true)
                } else {
                    VStack(spacing: .dsSM) {
                        Image(systemName: previewFailed ? "exclamationmark.triangle" : "doc")
                            .font(.system(size: 24))
                        Text(L10n.string(
                            previewFailed ? "scanCleanup.preview.failed" : "scanCleanup.preview.empty",
                            locale: locale
                        ))
                        .font(.system(size: 11))
                    }
                    .foregroundStyle(Color.dsTextTertiary)
                }
            }
            .frame(height: 230)
            .overlay {
                RoundedRectangle(cornerRadius: .dsRadiusSm, style: .continuous)
                    .strokeBorder(
                        isCleaned ? Color.dsAccent.opacity(0.45) : Color.dsSeparator,
                        lineWidth: 1
                    )
            }
        }
        .padding(.dsMD)
        .background(Color.dsCard)
        .clipShape(RoundedRectangle(cornerRadius: .dsRadiusMd, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: .dsRadiusMd, style: .continuous)
                .strokeBorder(Color.dsSeparator, lineWidth: 1)
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: .dsMD) {
            Picker(L10n.string("scanCleanup.title", locale: locale), selection: $scope) {
                Text(L10n.string("scanCleanup.scope.current", locale: locale))
                    .tag(ScanCleanupScope.currentPage)
                Text(L10n.format("scanCleanup.scope.document", viewModel.pageCount, locale: locale))
                    .tag(ScanCleanupScope.document)
            }
            .pickerStyle(.segmented)

            HStack(spacing: .dsSM) {
                optionToggle(
                    value: $options.deskew,
                    icon: "rotate.left",
                    titleKey: "scanCleanup.option.deskew",
                    detailKey: "scanCleanup.option.deskew.detail"
                )
                optionToggle(
                    value: $options.binarize,
                    icon: "circle.lefthalf.filled",
                    titleKey: "scanCleanup.option.binarize",
                    detailKey: "scanCleanup.option.binarize.detail"
                )
                optionToggle(
                    value: $options.despeckle,
                    icon: "sparkles",
                    titleKey: "scanCleanup.option.despeckle",
                    detailKey: "scanCleanup.option.despeckle.detail"
                )
            }
        }
    }

    private func optionToggle(
        value: Binding<Bool>,
        icon: String,
        titleKey: String,
        detailKey: String
    ) -> some View {
        HStack(alignment: .top, spacing: .dsSM) {
            Image(systemName: icon)
                .frame(width: 18)
                .foregroundStyle(value.wrappedValue ? Color.dsAccent : Color.dsTextTertiary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.string(forKey: titleKey, locale: locale))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.dsTextPrimary)
                Text(L10n.string(forKey: detailKey, locale: locale))
                    .font(.system(size: 10))
                    .foregroundStyle(Color.dsTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            Toggle("", isOn: value)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
        }
        .padding(.dsSM)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .topLeading)
        .background(value.wrappedValue ? Color.dsAccentSoft : Color.dsCanvas)
        .clipShape(RoundedRectangle(cornerRadius: .dsRadiusSm, style: .continuous))
    }

    private var warning: some View {
        Label {
            Text(L10n.string("scanCleanup.lossyWarning", locale: locale))
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
        }
        .font(.system(size: 11))
        .foregroundStyle(Color.dsWarningAccent)
        .padding(.horizontal, 2)
    }

    private var footer: some View {
        HStack {
            Text(L10n.string("scanCleanup.localOnly", locale: locale))
                .font(.system(size: 10))
                .foregroundStyle(Color.dsTextTertiary)
            Spacer()
            if viewModel.isApplyingScanCleanup {
                Button(L10n.string("contentView.exportSheet.cancel.button", locale: locale)) {
                    viewModel.cancelActiveOperation()
                }
            } else {
                Button(L10n.string("contentView.exportSheet.cancel.button", locale: locale)) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            Button {
                apply()
            } label: {
                if viewModel.isApplyingScanCleanup {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label(applyTitle, systemImage: "wand.and.stars")
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.dsAccent)
            .keyboardShortcut(.defaultAction)
            .disabled(!hasOperation || targetPageCount == 0 || viewModel.isApplyingScanCleanup)
        }
    }

    private var applyTitle: String {
        targetPageCount == 1
            ? L10n.string("scanCleanup.apply.one", locale: locale)
            : L10n.format("scanCleanup.apply.many", targetPageCount, locale: locale)
    }

    private func apply() {
        let pageRefIDs = viewModel.scanCleanupTargetPageRefIDs(scope: scope)
        let selectedOptions = options
        Task {
            if await viewModel.applyScanCleanup(pageRefIDs: pageRefIDs, options: selectedOptions) {
                dismiss()
            }
        }
    }

    @MainActor
    private func refreshPreview() async {
        guard let source = viewModel.scanCleanupPreviewSource() else {
            preview = nil
            previewFailed = true
            isPreviewLoading = false
            return
        }
        isPreviewLoading = true
        previewFailed = false
        let selectedOptions = options
        let rendered = await Task.detached(priority: .userInitiated) { () -> PreviewImages? in
            guard let document = PDFDocument(data: source.pdfData),
                  let page = document.page(at: source.pageIndex),
                  let before = PDFOCRService.rasterizedImage(for: page, dpi: 110) else { return nil }
            return PreviewImages(
                before: before,
                after: ScanCleanup.clean(before, options: selectedOptions)
            )
        }.value
        guard !Task.isCancelled else { return }
        preview = rendered
        previewFailed = rendered == nil
        isPreviewLoading = false
    }
}

private struct PreviewImages: @unchecked Sendable {
    let before: CGImage
    let after: CGImage
}
