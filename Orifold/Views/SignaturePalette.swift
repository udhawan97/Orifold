import SwiftUI
import PDFKit
import AppKit

struct SignaturePalette: View {
    @Bindable var viewModel: WorkspaceViewModel
    // Passed into L10n.string() (via `.title(locale:)`) below so this view's
    // `body` actually reads it — SwiftUI only re-invokes `body` on a locale
    // change for views that read `\.locale` during the previous evaluation.
    @Environment(\.locale) private var locale

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
                Picker("signaturePalette.mode.picker", selection: $selectedMode) {
                    ForEach(SignaturePaletteMode.allCases) { mode in
                        Text(mode.title(locale: locale)).tag(mode)
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
            // `.sheet`/`.popover` content on macOS doesn't inherit the
            // `.environment(\.locale:)` override applied at the scene root — it
            // resets to the system default — so it must be re-applied explicitly.
            CertificateGuideSheet()
                .environment(\.locale, locale)
        }
    }

    private var header: some View {
        Text("signaturePalette.title")
            .font(.system(size: 15, weight: .semibold, design: .serif))
            .foregroundStyle(Color.dsTextPrimary)
            .padding(.horizontal, .dsLG)
            .padding(.top, .dsMD)
            .padding(.bottom, .dsSM)
    }

    private var typedSignaturePanel: some View {
        VStack(alignment: .leading, spacing: .dsMD) {
            TextField("signaturePalette.typed.name.placeholder", text: $typedName)
                .textFieldStyle(.roundedBorder)
                .onSubmit(addTypedSignature)

            SignaturePreview(data: typedSignatureData)

            Button(action: addTypedSignature) {
                Label("signaturePalette.add.button", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.dsAccent)
            .disabled(trimmed(typedName).isEmpty || typedSignatureData == nil)
        }
    }

    private var initialsPanel: some View {
        VStack(alignment: .leading, spacing: .dsMD) {
            TextField("signaturePalette.initials.placeholder", text: $initials)
                .textFieldStyle(.roundedBorder)
                .onSubmit(addInitialsSignature)

            SignaturePreview(data: initialsSignatureData)

            Button(action: addInitialsSignature) {
                Label("signaturePalette.add.button", systemImage: "plus")
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
                Picker("signaturePalette.digitalId.picker", selection: $selectedIdentity) {
                    ForEach(DigitalIdentityOption.allCases) { option in
                        Text(option.title(locale: locale)).tag(option)
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
                    .help("signaturePalette.certificateTrustInfo.help")
                    .popover(isPresented: $isShowingTrustInfo, arrowEdge: .trailing) {
                        CertificateTrustPopover(isShowingGuide: $isShowingGuide)
                            .environment(\.locale, locale)
                    }
                }
            }

            if selectedIdentity == .selfSigned {
                Text("signaturePalette.selfSigned.notice")
                    .font(.dsCaption())
                    .foregroundStyle(Color.dsTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            TextField("signaturePalette.digital.signerName.placeholder", text: $digitalSignerName)
                .textFieldStyle(.roundedBorder)
            TextField("signaturePalette.digital.reason.placeholder", text: $reason)
                .textFieldStyle(.roundedBorder)
            TextField("signaturePalette.digital.location.placeholder", text: $location)
                .textFieldStyle(.roundedBorder)
            TextField("signaturePalette.digital.contact.placeholder", text: $contactInfo)
                .textFieldStyle(.roundedBorder)

            Toggle(isOn: $useTimestamp) {
                Label("signaturePalette.digital.timestamp.toggle", systemImage: "clock.badge.checkmark")
            }
            .toggleStyle(.checkbox)

            SignaturePreview(data: digitalSignatureData)

            HStack(spacing: .dsSM) {
                Button(action: placeDigitalSignature) {
                    Label("signaturePalette.digital.place.button", systemImage: "checkmark.seal")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(Color.dsAccent)
                .disabled(trimmed(digitalSignerName).isEmpty || digitalSignatureData == nil)

                Button(action: signAndExport) {
                    Label("signaturePalette.digital.signAndExport.button", systemImage: "square.and.arrow.up")
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
        SignatureImageRenderer.render(
            text: trimmed(digitalSignerName),
            kind: .cryptographic,
            metadata: SignatureImageRenderer.Metadata(
                signedAt: useTimestamp ? Date() : nil,
                location: optionalTrimmed(location),
                reason: optionalTrimmed(reason),
                contactInfo: optionalTrimmed(contactInfo)
            )
        )
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
                message: L10n.string("signaturePalette.error.missingIdentity")
            )
        } catch {
            viewModel.exportError = WorkspaceViewModel.ExportError(
                message: L10n.format("error.signingIdentity.preparationFailed", error.localizedDescription)
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

    func title(locale: Locale) -> String {
        switch self {
        case .type: return L10n.string("signatureMethod.type.title", locale: locale)
        case .initials: return L10n.string("signatureMethod.initials.title", locale: locale)
        case .digital: return L10n.string("signatureMethod.digital.title", locale: locale)
        }
    }
}

private enum DigitalIdentityOption: String, CaseIterable, Identifiable {
    case importP12
    case keychain
    case selfSigned

    var id: String { rawValue }

    func title(locale: Locale) -> String {
        switch self {
        case .importP12: return L10n.string("signatureMethod.importP12.title", locale: locale)
        case .keychain: return L10n.string("signatureMethod.keychain.title", locale: locale)
        case .selfSigned: return L10n.string("signatureMethod.selfSigned.title", locale: locale)
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
                .fill(Color.white)
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
                .strokeBorder(Color.dsSeparator.opacity(0.75), lineWidth: 1)
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

            DisclosureGroup("signaturePalette.certificateTrust.howToGetOne", isExpanded: $isShowingSteps) {
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
                Label("signaturePalette.certificateTrust.learnMore", systemImage: "book")
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
                Text("signaturePalette.certificateGuide.title")
                    .font(.system(size: 15, weight: .semibold, design: .serif))
                    .foregroundStyle(Color.dsTextPrimary)
                Spacer()
                Button("signaturePalette.certificateGuide.done") { dismiss() }
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
    static let shortPopoverCopy = "Signing in Orifold is free. A signature made with a self-signed or Keychain ID is valid and tamper-evident, but recipients will see 'identity not verified' until they trust it once. To have Adobe Acrobat/Reader trust your identity automatically, you need a CA-issued Digital ID from a trusted provider (an 'AATL' certificate). These are a paid third-party product (~US $180–600/yr). Orifold never charges for signing — you buy the certificate directly from the provider, then import the `.p12` file here."

    static func guideText() -> String {
        for bundle in guideBundles() {
            if let url = bundle.url(forResource: "CERTIFICATE_GUIDE", withExtension: "md"),
               let text = try? String(contentsOf: url, encoding: .utf8) {
                return text
            }
        }

        let fallbackRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        for fallbackURL in [
            fallbackRoot.appendingPathComponent("Orifold/Resources/CERTIFICATE_GUIDE.md"),
            fallbackRoot.appendingPathComponent("docs/signing/CERTIFICATE_GUIDE.md")
        ] {
            if let text = try? String(contentsOf: fallbackURL, encoding: .utf8) {
                return text
            }
        }

        return "CERTIFICATE_GUIDE.md could not be loaded."
    }

    private static func guideBundles() -> [Bundle] {
        var bundles: [Bundle] = []
        var seenPaths: Set<String> = []
        func appendBundle(_ bundle: Bundle?) {
            guard let bundle else { return }
            let path = bundle.bundleURL.standardizedFileURL.path
            guard seenPaths.insert(path).inserted else { return }
            bundles.append(bundle)
        }

        let legacyBundleIdentifier = ["com.ud.PDF", "old"].joined()
        appendBundle(Bundle.main)
        appendBundle(Bundle(identifier: "com.ud.Orifold"))
        appendBundle(Bundle(identifier: legacyBundleIdentifier))

        let environment = ProcessInfo.processInfo.environment
        if let productsDir = environment["BUILT_PRODUCTS_DIR"] {
            appendBundle(appBundle(at: URL(fileURLWithPath: productsDir).appendingPathComponent("Orifold.app")))
        }
        if let bundleLoader = environment["BUNDLE_LOADER"] {
            let loaderURL = URL(fileURLWithPath: bundleLoader)
            appendBundle(appBundle(at: loaderURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()))
        }
        if let siblingAppURL = siblingAppBundleURL(for: Bundle.main.bundleURL) {
            appendBundle(appBundle(at: siblingAppURL))
        }
        if let testBundle = Bundle.allBundles.first(where: { $0.bundleURL.pathExtension == "xctest" }),
           let siblingAppURL = siblingAppBundleURL(for: testBundle.bundleURL) {
            appendBundle(appBundle(at: siblingAppURL))
        }
        #if SWIFT_PACKAGE
        appendBundle(.module)
        #endif
        return bundles
    }

    private static func appBundle(at url: URL) -> Bundle? {
        let legacyBundleIdentifier = ["com.ud.PDF", "old"].joined()
        guard let bundle = Bundle(url: url),
              bundle.bundleIdentifier == "com.ud.Orifold" || bundle.bundleIdentifier == legacyBundleIdentifier else {
            return nil
        }
        return bundle
    }

    private static func siblingAppBundleURL(for bundleURL: URL) -> URL? {
        let appURL = bundleURL.deletingLastPathComponent().appendingPathComponent("Orifold.app")
        return FileManager.default.fileExists(atPath: appURL.path) ? appURL : nil
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
    struct Metadata {
        var signedAt: Date?
        var location: String?
        var reason: String?
        var contactInfo: String?
    }

    static func render(text: String,
                       kind: SignaturePlacement.Kind,
                       metadata: Metadata? = nil) -> Data? {
        guard !text.isEmpty else { return nil }

        let isCryptographic = kind == .cryptographic
        let size = isCryptographic ? CGSize(width: 360, height: 170) : CGSize(width: 360, height: 140)
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

        let fontSize: CGFloat
        if kind == .visualInitials {
            fontSize = 78
        } else if isCryptographic {
            fontSize = 38
        } else {
            fontSize = 52
        }
        let font = NSFont(name: "Snell Roundhand", size: fontSize)
            ?? NSFont.systemFont(ofSize: fontSize, weight: .regular)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black,
            .paragraphStyle: paragraph
        ]
        let drawBounds = isCryptographic
            ? CGRect(x: 18, y: 92, width: size.width - 36, height: 48)
            : CGRect(x: 18, y: 28, width: size.width - 36, height: size.height - 44)
        NSString(string: text).draw(with: drawBounds, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes)

        if isCryptographic, let metadata {
            let details = detailLines(from: metadata)
            if !details.isEmpty {
                let detailParagraph = NSMutableParagraphStyle()
                detailParagraph.alignment = .center
                detailParagraph.lineBreakMode = .byTruncatingTail
                let detailAttributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 9.5, weight: .regular),
                    .foregroundColor: NSColor.black.withAlphaComponent(0.72),
                    .paragraphStyle: detailParagraph
                ]
                let detailBounds = CGRect(x: 20, y: 24, width: size.width - 40, height: 62)
                NSString(string: details.joined(separator: "\n")).draw(
                    with: detailBounds,
                    options: [.usesLineFragmentOrigin, .usesFontLeading, .truncatesLastVisibleLine],
                    attributes: detailAttributes
                )
            }
        }

        return bitmap.representation(using: .png, properties: [:])
    }

    private static func detailLines(from metadata: Metadata) -> [String] {
        var lines: [String] = []
        if let signedAt = metadata.signedAt {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            lines.append("Signed: \(formatter.string(from: signedAt))")
        }
        if let reason = metadata.reason, !reason.isEmpty {
            lines.append("Reason: \(reason)")
        }
        if let location = metadata.location, !location.isEmpty {
            lines.append("Location: \(location)")
        }
        if let contactInfo = metadata.contactInfo, !contactInfo.isEmpty {
            lines.append("Contact: \(contactInfo)")
        }
        return lines
    }
}
