import AppKit
import PDFKit
import SwiftUI

/// State for the compare panel: runs the comparison off the main actor, then serves
/// per-pair display images (main-thread thumbnails, display-only — the diff itself already
/// ran on the engine's own renders).
@MainActor
@Observable
final class ComparePanelModel {
    private(set) var pairs: [PDFComparisonService.PagePair] = []
    private(set) var isComparing = true
    var currentIndex = 0
    var showsHighlights = true
    private(set) var rightOffset = 0

    private let request: PDFComparisonRequest
    private let leftDocument: PDFDocument?
    private let rightDocument: PDFDocument?
    private var runToken = UUID()

    init(request: PDFComparisonRequest) {
        self.request = request
        leftDocument = request.engineRequest.leftDocuments.first.flatMap { PDFDocument(data: $0) }
        rightDocument = PDFDocument(data: request.engineRequest.rightData)
    }

    var currentPair: PDFComparisonService.PagePair? {
        pairs.indices.contains(currentIndex) ? pairs[currentIndex] : nil
    }

    var changedPairs: [PDFComparisonService.PagePair] {
        pairs.filter { $0.change != .unchanged }
    }

    func run() async {
        isComparing = true
        let token = UUID()
        runToken = token
        let engineRequest = request.engineRequest
        let offset = rightOffset
        let result = await Task.detached(priority: .userInitiated) {
            PDFComparisonService.compare(engineRequest, rightOffset: offset)
        }.value
        guard runToken == token else { return }
        pairs = result
        if currentIndex >= result.count {
            currentIndex = max(0, result.count - 1)
        }
        isComparing = false
    }

    func setOffset(_ newOffset: Int) {
        guard newOffset != rightOffset else { return }
        rightOffset = newOffset
        Task { await run() }
    }

    func leftImage(at index: Int) -> NSImage? {
        guard index < request.engineRequest.leftVisualPages.count else { return nil }
        let locator = request.engineRequest.leftVisualPages[index]
        guard let page = leftDocument?.page(at: locator.pageIndex) else { return nil }
        return pageImage(page, highlight: highlightResult(at: index))
    }

    func rightImage(at index: Int) -> NSImage? {
        let rightIndex = index + rightOffset
        guard rightIndex >= 0, let page = rightDocument?.page(at: rightIndex) else { return nil }
        return pageImage(page, highlight: highlightResult(at: index))
    }

    private func highlightResult(at index: Int) -> PDFVisualDiff.Result? {
        guard showsHighlights, pairs.indices.contains(index) else { return nil }
        return pairs[index].visual
    }

    /// A display thumbnail, with the changed regions composited in when highlighting is on.
    /// Normalized rects are bottom-left-origin, exactly like `NSImage.lockFocus` space.
    private func pageImage(_ page: PDFPage, highlight: PDFVisualDiff.Result?) -> NSImage {
        let bounds = page.bounds(for: .mediaBox)
        let maxEdge: CGFloat = 640
        let scale = min(maxEdge / max(bounds.width, 1), maxEdge / max(bounds.height, 1))
        let size = CGSize(width: max(bounds.width * scale, 1), height: max(bounds.height * scale, 1))
        let thumbnail = page.thumbnail(of: size, for: .mediaBox)
        guard let highlight, highlight.hasChanges else { return thumbnail }

        let composed = NSImage(size: thumbnail.size)
        composed.lockFocus()
        thumbnail.draw(in: NSRect(origin: .zero, size: thumbnail.size))
        for rect in highlight.changedRects {
            let drawRect = NSRect(
                x: rect.minX * thumbnail.size.width,
                y: rect.minY * thumbnail.size.height,
                width: rect.width * thumbnail.size.width,
                height: rect.height * thumbnail.size.height
            )
            NSColor.systemRed.withAlphaComponent(0.22).setFill()
            drawRect.fill(using: .sourceOver)
            NSColor.systemRed.withAlphaComponent(0.85).setStroke()
            NSBezierPath(rect: drawRect).stroke()
        }
        composed.unlockFocus()
        return composed
    }
}

/// Side-by-side compare sheet: the current workspace against another PDF, page pair by page
/// pair, with visual change highlights, a word-level text summary, and a changed-pages strip.
struct ComparePanelView: View {
    let request: PDFComparisonRequest
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var model: ComparePanelModel

    init(request: PDFComparisonRequest) {
        self.request = request
        _model = State(initialValue: ComparePanelModel(request: request))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.string("compare.sheet.title", locale: locale))
                .font(.headline)

            if model.isComparing {
                Spacer()
                HStack {
                    Spacer()
                    ProgressView(L10n.string("compare.comparing", locale: locale))
                    Spacer()
                }
                Spacer()
            } else if let pair = model.currentPair {
                pairView(pair)
            } else {
                Spacer()
                HStack {
                    Spacer()
                    Text(L10n.string("compare.noChanges", locale: locale))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                Spacer()
            }

            footer
        }
        .padding(20)
        .frame(width: 940, height: 660)
        .task { await model.run() }
    }

    private func pairView(_ pair: PDFComparisonService.PagePair) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 16) {
                pane(
                    title: request.leftTitle,
                    image: model.leftImage(at: pair.id),
                    missingKey: "compare.page.rightOnly"
                )
                pane(
                    title: request.rightTitle,
                    image: model.rightImage(at: pair.id),
                    missingKey: "compare.page.leftOnly"
                )
            }
            .frame(maxHeight: .infinity)

            Text(statusText(for: pair))
                .font(.caption)
                .foregroundStyle(pair.change == .unchanged ? .secondary : .primary)
        }
    }

    private func pane(title: String, image: NSImage?, missingKey: String) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(nsColor: .textBackgroundColor))
                    .border(Color(nsColor: .separatorColor))
            } else {
                ZStack {
                    Color(nsColor: .windowBackgroundColor)
                    Text(L10n.string(forKey: missingKey, locale: locale))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .border(Color(nsColor: .separatorColor))
            }
        }
    }

    private func statusText(for pair: PDFComparisonService.PagePair) -> String {
        switch pair.change {
        case .unchanged:
            return L10n.string("compare.page.unchanged", locale: locale)
        case .leftOnly:
            return L10n.string("compare.page.leftOnly", locale: locale)
        case .rightOnly:
            return L10n.string("compare.page.rightOnly", locale: locale)
        case .changed:
            if let text = pair.text, text.hasChanges {
                if text.comparedExhaustively {
                    return L10n.format(
                        "compare.text.summary", text.insertedWords, text.deletedWords, locale: locale
                    )
                }
                return L10n.string("compare.text.coarse", locale: locale)
            }
            return L10n.string("compare.page.changed", locale: locale)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !model.isComparing, !model.changedPairs.isEmpty {
                HStack(spacing: 6) {
                    Text(L10n.format("compare.changedPages", model.changedPairs.count, locale: locale))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(model.changedPairs) { pair in
                                Button("\(pair.id + 1)") {
                                    model.currentIndex = pair.id
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                    }
                }
            }

            HStack(spacing: 12) {
                Button {
                    model.currentIndex = max(0, model.currentIndex - 1)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(model.isComparing || model.currentIndex == 0)

                Text(L10n.format("compare.page.position", model.currentIndex + 1, max(model.pairs.count, 1), locale: locale))
                    .font(.caption)
                    .monospacedDigit()

                Button {
                    model.currentIndex = min(model.pairs.count - 1, model.currentIndex + 1)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(model.isComparing || model.currentIndex >= model.pairs.count - 1)

                Divider().frame(height: 16)

                Stepper(
                    value: Binding(
                        get: { model.rightOffset },
                        set: { model.setOffset($0) }
                    ),
                    in: -200...200
                ) {
                    Text("\(L10n.string("compare.offset.label", locale: locale)): \(model.rightOffset)")
                        .font(.caption)
                        .monospacedDigit()
                }
                .disabled(model.isComparing)

                Toggle(L10n.string("compare.highlight.toggle", locale: locale), isOn: $model.showsHighlights)
                    .toggleStyle(.checkbox)
                    .font(.caption)

                Spacer()

                Button(L10n.string("compare.done", locale: locale)) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
    }
}
