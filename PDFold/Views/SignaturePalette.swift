import SwiftUI
import PDFKit
import AppKit

struct SignaturePalette: View {
    @Bindable var viewModel: WorkspaceViewModel

    @State private var selectedMode: SignaturePaletteMode = .type
    @State private var typedName: String = SignaturePalette.defaultSignerName
    @State private var initials: String = SignaturePalette.defaultInitials(from: SignaturePalette.defaultSignerName)
    @State private var digitalSignerName: String = SignaturePalette.defaultSignerName
    @State private var selectedIdentity: DigitalIdentityOption = .importP12
    @State private var reason: String = ""
    @State private var location: String = ""
    @State private var contactInfo: String = ""
    @State private var useTimestamp: Bool = true
    @State private var isShowingGuide = false
    @State private var isShowingTrustInfo = false

    private static var defaultSignerName: String {
        let name = NSFullUserName().trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Signer" : name
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Rectangle().fill(Color.dsSeparator).frame(height: 0.5)

            VStack(alignment: .leading, spacing: .dsLG) {
                Picker("Signature mode", selection: $selectedMode) {
                    ForEach(SignaturePaletteMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                switch selectedMode {
                case .type:
                    typedSignaturePanel
                case .initials:
                    initialsPanel
                case .digital:
                    digitalSignaturePanel
                }
            }
            .padding(.dsLG)
        }
        .frame(width: 360)
        .background(Color.dsSurface)
        .sheet(isPresented: $isShowingGuide) {
            CertificateGuideSheet()
        }
    }

    private var header: some View {
        Text("Signatures")
            .font(.system(size: 15, weight: .semibold, design: .serif))
            .foregroundStyle(Color.dsTextPrimary)
            .padding(.horizontal, .dsLG)
            .padding(.top, .dsMD)
            .padding(.bottom, .dsSM)
    }

    private var typedSignaturePanel: some View {
        VStack(alignment: .leading, spacing: .dsMD) {
            TextField("Name", text: $typedName)
                .textFieldStyle(.roundedBorder)
                .onSubmit(addTypedSignature)

            SignaturePreview(data: typedSignatureData)

            Button(action: addTypedSignature) {
                Label("Add", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.dsAccent)
            .disabled(trimmed(typedName).isEmpty || typedSignatureData == nil)
        }
    }

    private var initialsPanel: some View {
        VStack(alignment: .leading, spacing: .dsMD) {
            TextField("Initials", text: $initials)
                .textFieldStyle(.roundedBorder)
                .onSubmit(addInitialsSignature)

            SignaturePreview(data: initialsSignatureData)

            Button(action: addInitialsSignature) {
                Label("Add", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.dsAccent)
            .disabled(trimmed(initials).isEmpty || initialsSignatureData == nil)
        }
    }

    private var digitalSignaturePanel: some View {
        VStack(alignment: .leading, spacing: .dsMD) {
            HStack(spacing: .dsSM) {
                Picker("Digital ID", selection: $selectedIdentity) {
                    ForEach(DigitalIdentityOption.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.menu)

                if selectedIdentity == .importP12 {
                    Button {
                        isShowingTrustInfo.toggle()
                    } label: {
                        Image(systemName: "info.circle")
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(Color.dsAccent)
                    .help("Certificate trust and cost")
                    .popover(isPresented: $isShowingTrustInfo, arrowEdge: .trailing) {
                        CertificateTrustPopover(isShowingGuide: $isShowingGuide)
                    }
                }
            }

            if selectedIdentity == .selfSigned {
                Text("Free — but recipients see 'identity not verified' until they trust it once.")
                    .font(.dsCaption())
                    .foregroundStyle(Color.dsTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            TextField("Signer name", text: $digitalSignerName)
                .textFieldStyle(.roundedBorder)
            TextField("Reason", text: $reason)
                .textFieldStyle(.roundedBorder)
            TextField("Location", text: $location)
                .textFieldStyle(.roundedBorder)
            TextField("Contact", text: $contactInfo)
                .textFieldStyle(.roundedBorder)

            Toggle(isOn: $useTimestamp) {
                Label("Timestamp", systemImage: "clock.badge.checkmark")
            }
            .toggleStyle(.checkbox)

            SignaturePreview(data: digitalSignatureData)

            HStack(spacing: .dsSM) {
                Button(action: placeDigitalSignature) {
                    Label("Place", systemImage: "checkmark.seal")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(Color.dsAccent)
                .disabled(trimmed(digitalSignerName).isEmpty || digitalSignatureData == nil)

                Button(action: signAndExport) {
                    Label("Sign & Export…", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.dsAccent)
                .disabled(!viewModel.hasCryptographicSignaturePlacement)
            }
        }
    }

    private var typedSignatureData: Data? {
        SignatureImageRenderer.render(text: trimmed(typedName), kind: .visualTyped)
    }

    private var initialsSignatureData: Data? {
        SignatureImageRenderer.render(text: trimmed(initials).uppercased(), kind: .visualInitials)
    }

    private var digitalSignatureData: Data? {
        SignatureImageRenderer.render(text: trimmed(digitalSignerName), kind: .cryptographic)
    }

    private func addTypedSignature() {
        guard let data = typedSignatureData else { return }
        viewModel.beginVisualSignaturePlacement(
            imageData: data,
            kind: .visualTyped,
            signerName: trimmed(typedName)
        )
    }

    private func addInitialsSignature() {
        guard let data = initialsSignatureData else { return }
        viewModel.beginVisualSignaturePlacement(
            imageData: data,
            kind: .visualInitials,
            signerName: trimmed(initials).uppercased()
        )
    }

    private func placeDigitalSignature() {
        guard let data = digitalSignatureData else { return }
        let signerName = trimmed(digitalSignerName)
        do {
            let identity = try viewModel.resolveSigningIdentity(
                reference: selectedIdentity.identityReference,
                signerName: signerName
            )
            viewModel.beginCryptographicSignaturePlacement(
                imageData: data,
                signerName: signerName,
                signerIdentityRef: selectedIdentity.identityReference,
                reason: optionalTrimmed(reason),
                location: optionalTrimmed(location),
                contactInfo: optionalTrimmed(contactInfo),
                timestampRequested: useTimestamp,
                identity: identity
            )
        } catch SigningError.missingIdentity {
            viewModel.exportError = WorkspaceViewModel.ExportError(
                message: "Choose or import a signing identity before placing a digital signature."
            )
        } catch {
            viewModel.exportError = WorkspaceViewModel.ExportError(
                message: "pdFold could not prepare that signing identity: \(error.localizedDescription)"
            )
        }
    }

    private func signAndExport() {
        viewModel.signAndExportCryptographicPDF(timestampRequested: useTimestamp)
    }

    private func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func optionalTrimmed(_ value: String) -> String? {
        let value = trimmed(value)
        return value.isEmpty ? nil : value
    }

    private static func defaultInitials(from name: String) -> String {
        let letters = name
            .split(whereSeparator: { $0.isWhitespace || $0 == "-" })
            .compactMap(\.first)
            .prefix(3)
        let initials = String(letters).uppercased()
        return initials.isEmpty ? "AB" : initials
    }
}

private enum SignaturePaletteMode: String, CaseIterable, Identifiable {
    case type
    case initials
    case digital

    var id: String { rawValue }

    var title: String {
        switch self {
        case .type: return "Type"
        case .initials: return "Initials"
        case .digital: return "Digital"
        }
    }
}

private enum DigitalIdentityOption: String, CaseIterable, Identifiable {
    case importP12
    case keychain
    case selfSigned

    var id: String { rawValue }

    var title: String {
        switch self {
        case .importP12: return "Import .p12 / CA-issued Digital ID"
        case .keychain: return "Choose Keychain Digital ID"
        case .selfSigned: return "Generate self-signed ID"
        }
    }

    var identityReference: String {
        switch self {
        case .importP12: return "p12"
        case .keychain: return "keychain"
        case .selfSigned: return "self-signed"
        }
    }
}

private struct SignaturePreview: View {
    var data: Data?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: .dsRadiusSm, style: .continuous)
                .fill(Color.dsCard)
            if let data, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(.dsMD)
            } else {
                Image(systemName: "signature")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(Color.dsTextTertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 104)
        .overlay {
            RoundedRectangle(cornerRadius: .dsRadiusSm, style: .continuous)
                .strokeBorder(Color.dsSeparator, lineWidth: 1)
        }
    }
}

private struct CertificateTrustPopover: View {
    @Binding var isShowingGuide: Bool
    @State private var isShowingSteps = false

    var body: some View {
        VStack(alignment: .leading, spacing: .dsMD) {
            Text(CertificateGuideResource.shortPopoverCopy)
                .font(.dsCaption())
                .foregroundStyle(Color.dsTextPrimary)
                .fixedSize(horizontal: false, vertical: true)

            DisclosureGroup("How to get one", isExpanded: $isShowingSteps) {
                ScrollView {
                    Text(CertificateGuideResource.acquisitionGuideText())
                        .font(.dsCaption())
                        .foregroundStyle(Color.dsTextSecondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, .dsSM)
                }
                .frame(maxHeight: 260)
            }

            Button {
                isShowingGuide = true
            } label: {
                Label("Learn more…", systemImage: "book")
            }
            .buttonStyle(.bordered)
            .tint(Color.dsAccent)
        }
        .padding(.dsLG)
        .frame(width: 360)
        .background(Color.dsSurface)
    }
}

private struct CertificateGuideSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Getting a Digital ID")
                    .font(.system(size: 15, weight: .semibold, design: .serif))
                    .foregroundStyle(Color.dsTextPrimary)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.dsLG)

            Rectangle().fill(Color.dsSeparator).frame(height: 0.5)

            ScrollView {
                Text(CertificateGuideResource.guideText())
                    .font(.dsBody())
                    .foregroundStyle(Color.dsTextPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.dsLG)
            }
        }
        .frame(width: 620, height: 720)
        .background(Color.dsSurface)
    }
}

enum CertificateGuideResource {
    static let shortPopoverCopy = "Signing in pdFold is free. A signature made with a self-signed or Keychain ID is valid and tamper-evident, but recipients will see 'identity not verified' until they trust it once. To have Adobe Acrobat/Reader trust your identity automatically, you need a CA-issued Digital ID from a trusted provider (an 'AATL' certificate). These are a paid third-party product (~US $180–600/yr). pdFold never charges for signing — you buy the certificate directly from the provider, then import the `.p12` file here."

    static func guideText() -> String {
        if let url = Bundle.module.url(forResource: "CERTIFICATE_GUIDE", withExtension: "md"),
           let text = try? String(contentsOf: url, encoding: .utf8) {
            return text
        }

        let fallbackURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("CERTIFICATE_GUIDE.md")
        if let text = try? String(contentsOf: fallbackURL, encoding: .utf8) {
            return text
        }

        return "CERTIFICATE_GUIDE.md could not be loaded."
    }

    static func acquisitionGuideText() -> String {
        let text = guideText()
        guard let start = text.range(of: "## Getting a CA-issued (AATL) Digital ID"),
              let end = text.range(of: "## FAQ", range: start.lowerBound..<text.endIndex) else {
            return text
        }
        return String(text[start.lowerBound..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private enum SignatureImageRenderer {
    static func render(text: String, kind: SignaturePlacement.Kind) -> Data? {
        guard !text.isEmpty else { return nil }

        let size = CGSize(width: 360, height: 140)
        // Draw directly into an NSBitmapImageRep rather than NSImage(size:).lockFocus() +
        // tiffRepresentation: with a transparent (.clear) fill, CGImageDestination can fail
        // to finalize the TIFF ("CGImageDestinationFinalize failed for output type 'public.tiff'"),
        // silently returning nil and leaving the signature preview/Add button permanently empty.
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width),
            pixelsHigh: Int(size.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        NSGraphicsContext.current = context

        NSColor.clear.setFill()
        NSRect(origin: .zero, size: size).fill()

        let fontSize: CGFloat = kind == .visualInitials ? 78 : 52
        let font = NSFont(name: "Snell Roundhand", size: fontSize)
            ?? NSFont.systemFont(ofSize: fontSize, weight: .regular)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black,
            .paragraphStyle: paragraph
        ]
        let drawBounds = CGRect(x: 18, y: 28, width: size.width - 36, height: size.height - 44)
        NSString(string: text).draw(with: drawBounds, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes)

        return bitmap.representation(using: .png, properties: [:])
    }
}
