import SwiftUI
import PDFKit

struct SignaturePalette: View {
    @Bindable var viewModel: WorkspaceViewModel
    @State private var savedSignatures: [Data] = SignatureStore.shared.all()
    @State private var isDrawing = false
    @State private var isShowingDigitalSignatureNotice = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Signatures")
                .font(.system(size: 15, weight: .semibold, design: .serif))
                .foregroundStyle(Color.dsTextPrimary)
                .padding(.horizontal, .dsLG)
                .padding(.top, .dsMD)
                .padding(.bottom, .dsSM)

            Rectangle().fill(Color.dsSeparator).frame(height: 0.5)

            if savedSignatures.isEmpty {
                VStack(spacing: .dsSM) {
                    Image(systemName: "signature")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(Color.dsTextTertiary)
                    Text("No saved signatures")
                        .font(.dsBody())
                        .foregroundStyle(Color.dsTextSecondary)
                    Text("Draw one below to get started.")
                        .font(.dsCaption())
                        .foregroundStyle(Color.dsTextTertiary)
                }
                .padding(.dsXL)
                .frame(maxWidth: .infinity)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: .dsMD) {
                        ForEach(savedSignatures.indices, id: \.self) { i in
                            SignatureThumbnail(data: savedSignatures[i])
                                .onTapGesture {
                                    viewModel.pendingSignatureData = savedSignatures[i]
                                    viewModel.currentTool = .signature
                                }
                        }
                    }
                    .padding(.horizontal, .dsLG)
                    .padding(.vertical, .dsMD)
                }
            }

            Rectangle().fill(Color.dsSeparator).frame(height: 0.5)

            VStack(spacing: .dsSM) {
                Button {
                    isDrawing = true
                } label: {
                    Label("Local Drawn Signature", systemImage: "pencil.and.outline")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(Color.dsAccent)

                Button {
                    isShowingDigitalSignatureNotice = true
                } label: {
                    Label("Digital Signature", systemImage: "checkmark.seal")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding(.dsLG)
        }
        .frame(width: 300)
        .background(Color.dsSurface)
        .sheet(isPresented: $isDrawing) {
            SignatureDrawingView { newData in
                SignatureStore.shared.save(newData)
                savedSignatures = SignatureStore.shared.all()
                viewModel.pendingSignatureData = newData
                viewModel.currentTool = .signature
                isDrawing = false
            } onCancel: {
                isDrawing = false
            }
        }
        .alert("Digital Signature", isPresented: $isShowingDigitalSignatureNotice) {
            Button("OK") {}
        } message: {
            Text("A standards-compliant PDF digital signature needs certificate-backed signing with a PDF /Sig field, /ByteRange, and CMS signature data. PDFKit cannot create that directly, so pdFold keeps this separate from local drawn signatures until a signing engine is added.")
        }
    }
}

// MARK: - Signature thumbnail

struct SignatureThumbnail: View {
    var data: Data

    var body: some View {
        if let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 88, height: 40)
                .background(Color.dsCard)
                .clipShape(RoundedRectangle(cornerRadius: .dsRadiusSm, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: .dsRadiusSm, style: .continuous)
                        .strokeBorder(Color.dsSeparator, lineWidth: 1)
                }
        }
    }
}

// MARK: - Signature drawing sheet

struct SignatureDrawingView: View {
    var onSave: (Data) -> Void
    var onCancel: () -> Void

    @State private var paths: [NSBezierPath] = []

    var body: some View {
        VStack(spacing: .dsLG) {
            Text("Draw your signature")
                .font(.system(size: 15, weight: .semibold, design: .serif))
                .foregroundStyle(Color.dsTextPrimary)

            SignatureCanvas(paths: $paths)
                .frame(width: 360, height: 140)
                .background(Color.dsCard)
                .clipShape(RoundedRectangle(cornerRadius: .dsRadiusSm, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: .dsRadiusSm, style: .continuous)
                        .strokeBorder(Color.dsSeparator, lineWidth: 1)
                }

            HStack {
                Button("Clear") { paths = [] }
                    .buttonStyle(.bordered)
                    .tint(Color.dsTextTertiary)
                Spacer()
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    if let data = renderSignature(paths: paths, size: CGSize(width: 360, height: 140)) {
                        onSave(data)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.dsAccent)
                .disabled(paths.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.dsXXL)
        .frame(width: 420)
        .background(Color.dsSurface)
    }

    private func renderSignature(paths: [NSBezierPath], size: CGSize) -> Data? {
        let image = NSImage(size: size, flipped: false) { _ in
            NSColor.black.setStroke()
            paths.forEach { $0.lineWidth = 2; $0.stroke() }
            return true
        }
        guard let tiff = image.tiffRepresentation,
              let bmp = NSBitmapImageRep(data: tiff) else { return nil }
        return bmp.representation(using: .png, properties: [:])
    }
}

// MARK: - NSView canvas for drawing

struct SignatureCanvas: NSViewRepresentable {
    @Binding var paths: [NSBezierPath]

    func makeNSView(context: Context) -> SignatureCanvasView {
        let v = SignatureCanvasView()
        v.onPathsChanged = { context.coordinator.paths = $0; paths = $0 }
        return v
    }

    func updateNSView(_ nsView: SignatureCanvasView, context: Context) {
        nsView.paths = paths
        nsView.needsDisplay = true
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    class Coordinator { var paths: [NSBezierPath] = [] }
}

final class SignatureCanvasView: NSView {
    var paths: [NSBezierPath] = []
    var onPathsChanged: (([NSBezierPath]) -> Void)?
    private var currentPath: NSBezierPath?

    override var isFlipped: Bool { true }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let path = NSBezierPath()
        path.lineWidth = 2
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.move(to: p)
        currentPath = path
    }

    override func mouseDragged(with event: NSEvent) {
        guard let path = currentPath else { return }
        path.line(to: convert(event.locationInWindow, from: nil))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let path = currentPath else { return }
        paths.append(path)
        currentPath = nil
        onPathsChanged?(paths)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        dirtyRect.fill()
        NSColor.black.setStroke()
        paths.forEach { $0.stroke() }
        currentPath?.stroke()
    }
}

// MARK: - Signature persistence

final class SignatureStore {
    static let shared = SignatureStore()
    private let dir: URL

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        dir = support.appendingPathComponent("PDFold/Signatures", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    func all() -> [Data] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.creationDateKey]
        ))?.sorted { a, b in
            let aDate = (try? a.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let bDate = (try? b.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return aDate < bDate
        } ?? []
        return urls.compactMap { try? Data(contentsOf: $0) }
    }

    func save(_ data: Data) {
        let url = dir.appendingPathComponent("\(UUID().uuidString).png")
        try? data.write(to: url)
    }
}
