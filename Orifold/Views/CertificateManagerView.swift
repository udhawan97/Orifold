import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Small pill summarizing a certificate profile's trust state — self-signed / CA-issued /
/// expiring soon / expired. Never claims a trust verdict Orifold can't back up; see the
/// honest-language matrix in docs/signing/SIGNATURE_EXPERIENCE_PLAN.md §1.
struct CertificateStatusChip: View {
    var profile: DigitalCertificateProfile

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

    private var titleKey: LocalizedStringKey {
        if profile.isExpired { return "certificateChip.expired" }
        if profile.expiresSoon { return "certificateChip.expiresSoon" }
        return profile.isSelfSigned ? "certificateChip.selfSigned" : "certificateChip.caIssued"
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

    var body: some View {
        VStack(alignment: .leading, spacing: .dsMD) {
            Text("certificateSheet.createSelfSigned.title")
                .font(.system(size: 15, weight: .semibold, design: .serif))
                .foregroundStyle(Color.dsTextPrimary)

            Text("certificateSheet.createSelfSigned.notice")
                .font(.dsCaption())
                .foregroundStyle(Color.dsTextSecondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField("certificateSheet.name.placeholder", text: $name)
                .textFieldStyle(.roundedBorder)
            TextField("certificateSheet.email.placeholder", text: $email)
                .textFieldStyle(.roundedBorder)

            Picker("certificateSheet.validity.picker", selection: $validityYears) {
                Text("certificateSheet.validity.oneYear").tag(1)
                Text("certificateSheet.validity.twoYears").tag(2)
                Text("certificateSheet.validity.fiveYears").tag(5)
            }
            .pickerStyle(.segmented)

            if let errorMessage {
                Text(errorMessage)
                    .font(.dsCaption())
                    .foregroundStyle(Color.dsErrorAccent)
            }

            HStack {
                Spacer()
                Button("certificateSheet.cancel.button") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("certificateSheet.create.button", action: create)
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
    @State private var password = ""
    @State private var errorMessage: String?
    @State private var attemptCount = 0

    var body: some View {
        VStack(alignment: .leading, spacing: .dsMD) {
            Text("certificateSheet.importPassword.title")
                .font(.system(size: 15, weight: .semibold, design: .serif))
                .foregroundStyle(Color.dsTextPrimary)

            Text(L10n.format("certificateSheet.importPassword.fileName", fileURL.lastPathComponent))
                .font(.dsCaption())
                .foregroundStyle(Color.dsTextSecondary)

            SecureField("certificateSheet.importPassword.placeholder", text: $password)
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
                Button("certificateSheet.cancel.button") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("certificateSheet.unlock.button", action: attemptImport)
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
    @State private var pendingDeletion: DigitalCertificateProfile?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("certificateSheet.manage.title")
                    .font(.system(size: 15, weight: .semibold, design: .serif))
                    .foregroundStyle(Color.dsTextPrimary)
                Spacer()
                Button("certificateSheet.done.button") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.dsLG)

            Rectangle().fill(Color.dsSeparator).frame(height: 0.5)

            if viewModel.certificateProfiles.isEmpty {
                VStack(spacing: .dsSM) {
                    Image(systemName: "checkmark.seal")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(Color.dsTextTertiary)
                    Text("certificateSheet.manage.empty")
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
            L10n.string("certificateSheet.delete.confirmTitle"),
            isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } })
        ) {
            Button("certificateSheet.cancel.button", role: .cancel) { pendingDeletion = nil }
            Button("certificateSheet.delete.button", role: .destructive) {
                if let profile = pendingDeletion {
                    viewModel.removeCertificateProfile(id: profile.id)
                }
                pendingDeletion = nil
            }
        } message: {
            Text("certificateSheet.delete.confirmMessage")
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

            Text(L10n.format("certificateSheet.manage.expiryDetail", Self.dateFormatter.string(from: profile.notAfter)))
                .font(.dsCaption())
                .foregroundStyle(Color.dsTextTertiary)

            HStack {
                Button(action: { exportPublicCertificate(profile) }) {
                    Label("certificateSheet.manage.exportPublicCert", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderless)
                .font(.dsCaption())

                Spacer()

                Button(role: .destructive) { pendingDeletion = profile } label: {
                    Label("certificateSheet.delete.button", systemImage: "trash")
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
