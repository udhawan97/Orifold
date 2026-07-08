import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Small pill summarizing a certificate profile's trust state — self-signed / CA-issued /
/// expiring soon / expired. Never claims a trust verdict Orifold can't back up; see the
/// honest-language matrix in docs/signing/SIGNATURE_EXPERIENCE_PLAN.md §1.
struct CertificateStatusChip: View {
    var profile: DigitalCertificateProfile
    @Environment(\.locale) private var locale

    var body: some View {
        Label(titleKey, systemImage: systemImage)
            .font(.dsCaption())
            .padding(.horizontal, .dsSM)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(tint.opacity(0.15))
            )
            .foregroundStyle(tint)
    }

    private var titleKey: String {
        if profile.isExpired { return L10n.string("certificateChip.expired", locale: locale) }
        if profile.expiresSoon { return L10n.string("certificateChip.expiresSoon", locale: locale) }
        return L10n.string(profile.isSelfSigned ? "certificateChip.selfSigned" : "certificateChip.caIssued", locale: locale)
    }

    private var systemImage: String {
        if profile.isExpired { return "exclamationmark.triangle.fill" }
        if profile.expiresSoon { return "clock.badge.exclamationmark" }
        return profile.isSelfSigned ? "checkmark.seal" : "checkmark.seal.fill"
    }

    private var tint: Color {
        if profile.isExpired { return Color.dsErrorAccent }
        if profile.expiresSoon { return Color.dsWarningAccent }
        return profile.isSelfSigned ? Color.dsAccent : Color.dsSuccessAccent
    }
}

/// "Create local self-signed ID…" — generates a certificate exactly ONCE (the resulting
/// profile is reused for every future signing) and explains, in one line, what it can and
/// cannot guarantee.
struct CreateSelfSignedCertificateSheet: View {
    var viewModel: WorkspaceViewModel
    var onCreated: (DigitalCertificateProfile) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var email: String = ""
    @State private var validityYears: Int = 2
    @State private var errorMessage: String?
    // Read so SwiftUI re-invokes `body` when the app language changes.
    @Environment(\.locale) private var locale

    var body: some View {
        let _ = locale
        VStack(alignment: .leading, spacing: .dsMD) {
            Text(L10n.string("certificateSheet.createSelfSigned.title"))
                .font(.system(size: 15, weight: .semibold, design: .serif))
                .foregroundStyle(Color.dsTextPrimary)

            Text(L10n.string("certificateSheet.createSelfSigned.notice"))
                .font(.dsCaption())
                .foregroundStyle(Color.dsTextSecondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField(L10n.string("certificateSheet.name.placeholder"), text: $name)
                .textFieldStyle(.roundedBorder)
            TextField(L10n.string("certificateSheet.email.placeholder"), text: $email)
                .textFieldStyle(.roundedBorder)

            Picker(L10n.string("certificateSheet.validity.picker"), selection: $validityYears) {
                Text(L10n.string("certificateSheet.validity.oneYear")).tag(1)
                Text(L10n.string("certificateSheet.validity.twoYears")).tag(2)
                Text(L10n.string("certificateSheet.validity.fiveYears")).tag(5)
            }
            .pickerStyle(.segmented)

            if let errorMessage {
                Text(errorMessage)
                    .font(.dsCaption())
                    .foregroundStyle(Color.dsErrorAccent)
            }

            HStack {
                Spacer()
                Button(L10n.string("certificateSheet.cancel.button")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(L10n.string("certificateSheet.create.button"), action: create)
                    .buttonStyle(.borderedProminent)
                    .tint(Color.dsAccent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(.dsLG)
        .frame(width: 380)
        .background(Color.dsSurface)
    }

    private func create() {
        do {
            let profile = try viewModel.createSelfSignedCertificateProfile(
                commonName: name,
                emailAddress: email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : email,
                validityDays: validityYears * 365
            )
            onCreated(profile)
            dismiss()
        } catch {
            errorMessage = L10n.format("certificateSheet.error.createFailed", error.localizedDescription)
        }
    }
}

/// Password entry for a `.p12`/`.pfx` import. Owns its own retry loop so a wrong password
/// shows an inline, specific message and lets the user try again without re-choosing the
/// file — instead of a raw `NSAlert` failure with no path back.
struct ImportCertificatePasswordSheet: View {
    var viewModel: WorkspaceViewModel
    var fileURL: URL
    var onImported: (DigitalCertificateProfile) -> Void

    @Environment(\.dismiss) private var dismiss
    // Passed into L10n.format()/L10n.string() below so this view's `body`
    // actually reads it — SwiftUI only re-invokes `body` on a locale change
    // for views that read `\.locale` during the previous evaluation.
    @Environment(\.locale) private var locale
    @State private var password = ""
    @State private var errorMessage: String?
    @State private var attemptCount = 0

    var body: some View {
        VStack(alignment: .leading, spacing: .dsMD) {
            Text(L10n.string("certificateSheet.importPassword.title"))
                .font(.system(size: 15, weight: .semibold, design: .serif))
                .foregroundStyle(Color.dsTextPrimary)

            Text(L10n.format("certificateSheet.importPassword.fileName", fileURL.lastPathComponent, locale: locale))
                .font(.dsCaption())
                .foregroundStyle(Color.dsTextSecondary)

            SecureField(L10n.string("certificateSheet.importPassword.placeholder"), text: $password)
                .textFieldStyle(.roundedBorder)
                .onSubmit(attemptImport)

            if let errorMessage {
                Text(errorMessage)
                    .font(.dsCaption())
                    .foregroundStyle(Color.dsErrorAccent)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button(L10n.string("certificateSheet.cancel.button")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(L10n.string("certificateSheet.unlock.button"), action: attemptImport)
                    .buttonStyle(.borderedProminent)
                    .tint(Color.dsAccent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(password.isEmpty)
            }
        }
        .padding(.dsLG)
        .frame(width: 400)
        .background(Color.dsSurface)
    }

    private func attemptImport() {
        attemptCount += 1
        do {
            let profile = try viewModel.importCertificateProfile(
                fileURL: fileURL,
                passphrase: password,
                label: fileURL.deletingPathExtension().lastPathComponent
            )
            onImported(profile)
            dismiss()
        } catch {
            password = ""
            if attemptCount >= 3 {
                errorMessage = L10n.string("certificateSheet.importPassword.tooManyAttempts")
            } else {
                errorMessage = L10n.string("certificateSheet.importPassword.wrongPassword")
            }
        }
    }
}

/// "Manage certificates…" — inspect, and delete, every persisted signing identity. Deleting
/// removes both the profile and its Keychain entry; previously exported PDFs remain valid,
/// since the signature already lives in those files independent of the local Keychain.
struct ManageCertificatesSheet: View {
    var viewModel: WorkspaceViewModel

    @Environment(\.dismiss) private var dismiss
    // Passed into L10n.string()/L10n.format() below so this view's `body`
    // actually reads it — SwiftUI only re-invokes `body` on a locale change
    // for views that read `\.locale` during the previous evaluation.
    @Environment(\.locale) private var locale
    @State private var pendingDeletion: DigitalCertificateProfile?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L10n.string("certificateSheet.manage.title"))
                    .font(.system(size: 15, weight: .semibold, design: .serif))
                    .foregroundStyle(Color.dsTextPrimary)
                Spacer()
                Button(L10n.string("certificateSheet.done.button")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.dsLG)

            Rectangle().fill(Color.dsSeparator).frame(height: 0.5)

            if viewModel.certificateProfiles.isEmpty {
                VStack(spacing: .dsSM) {
                    Image(systemName: "checkmark.seal")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(Color.dsTextTertiary)
                    Text(L10n.string("certificateSheet.manage.empty"))
                        .font(.dsCaption())
                        .foregroundStyle(Color.dsTextSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: .dsSM) {
                        ForEach(viewModel.certificateProfiles) { profile in
                            certificateRow(profile)
                        }
                    }
                    .padding(.dsLG)
                }
            }
        }
        .frame(width: 480, height: 420)
        .background(Color.dsSurface)
        .alert(
            L10n.string("certificateSheet.delete.confirmTitle", locale: locale),
            isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } })
        ) {
            Button(L10n.string("certificateSheet.cancel.button"), role: .cancel) { pendingDeletion = nil }
            Button(L10n.string("certificateSheet.delete.button"), role: .destructive) {
                if let profile = pendingDeletion {
                    viewModel.removeCertificateProfile(id: profile.id)
                }
                pendingDeletion = nil
            }
        } message: {
            Text(L10n.string("certificateSheet.delete.confirmMessage"))
        }
    }

    private func certificateRow(_ profile: DigitalCertificateProfile) -> some View {
        VStack(alignment: .leading, spacing: .dsSM) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.label)
                        .font(.dsBody().weight(.medium))
                        .foregroundStyle(Color.dsTextPrimary)
                    Text(profile.subjectCommonName)
                        .font(.dsCaption())
                        .foregroundStyle(Color.dsTextSecondary)
                }
                Spacer()
                CertificateStatusChip(profile: profile)
            }

            Text(L10n.format("certificateSheet.manage.expiryDetail", Self.dateFormatter.string(from: profile.notAfter), locale: locale))
                .font(.dsCaption())
                .foregroundStyle(Color.dsTextTertiary)

            CertificateTrustCheckRow(profile: profile)

            HStack {
                Button(action: { exportPublicCertificate(profile) }) {
                    Label(L10n.string("certificateSheet.manage.exportPublicCert"), systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderless)
                .font(.dsCaption())

                Spacer()

                Button(role: .destructive) { pendingDeletion = profile } label: {
                    Label(L10n.string("certificateSheet.delete.button"), systemImage: "trash")
                }
                .buttonStyle(.borderless)
                .font(.dsCaption())
            }
        }
        .padding(.dsMD)
        .background(RoundedRectangle(cornerRadius: .dsRadiusSm, style: .continuous).fill(Color.dsCard))
    }

    private func exportPublicCertificate(_ profile: DigitalCertificateProfile) {
        guard let leafDER = profile.chainCertificatesDER.first else { return }
        let panel = NSSavePanel()
        panel.title = L10n.string("certificateSheet.manage.exportPublicCert")
        panel.nameFieldStringValue = "\(profile.subjectCommonName).cer"
        panel.allowedContentTypes = [UTType(filenameExtension: "cer") ?? .data]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? leafDER.write(to: url, options: .atomic)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}

/// On-demand chain-trust + revocation check, using macOS's own Security.framework
/// (`SecTrust` + `SecPolicyCreateRevocation`) rather than any hand-rolled OCSP/CRL client.
/// Never runs automatically — only when the user presses the button — since revocation
/// checking can make a network request to the certificate issuer's responder.
private struct CertificateTrustCheckRow: View {
    var profile: DigitalCertificateProfile

    @State private var isChecking = false
    @State private var result: CertificateTrustEvaluation?
    @State private var errorMessage: String?
    // Read so `body` re-runs on a live language switch while the sheet is open.
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: .dsSM) {
                Button(action: check) {
                    if isChecking {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label(L10n.string("certificateSheet.manage.checkTrust"), systemImage: "network")
                    }
                }
                .buttonStyle(.borderless)
                .font(.dsCaption())
                .disabled(isChecking)
                .help(L10n.string("certificateSheet.manage.checkTrust.help"))

                if let result {
                    resultBadge(for: result)
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.dsCaption())
                    .foregroundStyle(Color.dsErrorAccent)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func check() {
        isChecking = true
        errorMessage = nil
        Task {
            do {
                let evaluation = try await CertificateTrustEvaluator.evaluate(profile: profile)
                await MainActor.run {
                    result = evaluation
                    isChecking = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isChecking = false
                }
            }
        }
    }

    @ViewBuilder
    private func resultBadge(for evaluation: CertificateTrustEvaluation) -> some View {
        switch evaluation.verdict {
        case .trusted:
            // Honest-language note: `SecTrustEvaluateWithError` reports this same verdict
            // whether revocation was actually checked and came back clean, OR the OCSP/CRL
            // responder was simply unreachable — it doesn't distinguish the two. Say so
            // rather than implying a stronger revocation guarantee than Orifold can back up.
            Label(L10n.string("certificateSheet.manage.trustResult.trusted"), systemImage: "checkmark.seal.fill")
                .font(.dsCaption())
                .foregroundStyle(Color.dsSuccessAccent)
                .help(L10n.string("certificateSheet.manage.trustResult.trusted.help"))
        case .revoked:
            Label(L10n.string("certificateSheet.manage.trustResult.revoked"), systemImage: "xmark.seal.fill")
                .font(.dsCaption())
                .foregroundStyle(Color.dsErrorAccent)
        case .notTrusted:
            // Expected, non-alarming result for a self-signed identity — phrased per the
            // honest-language matrix, not as an error.
            Label(
                L10n.string(profile.isSelfSigned
                    ? "certificateSheet.manage.trustResult.notTrustedSelfSigned"
                    : "certificateSheet.manage.trustResult.notTrusted", locale: locale),
                systemImage: "questionmark.circle"
            )
            .font(.dsCaption())
            .foregroundStyle(Color.dsTextSecondary)
        }
    }
}
