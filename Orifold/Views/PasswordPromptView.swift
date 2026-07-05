import SwiftUI
import PDFKit

struct PasswordPromptView: View {
    var fileName: String
    var pdf: PDFDocument
    var url: URL
    var viewModel: WorkspaceViewModel

    @State private var password = ""
    @State private var failed = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.fill")
                .font(.system(size: 36))
                .foregroundStyle(Color.dsTextSecondary)

            Text("\"\(fileName)\" is password-protected")
                .font(.dsHeadline())
                .foregroundStyle(Color.dsTextPrimary)

            if failed {
                Text("passwordPrompt.incorrectPassword.message")
                    .font(.dsCaption())
                    .foregroundStyle(Color.dsAnnotationCoral)
            }

            SecureField("passwordPrompt.password.field", text: $password)
                .textFieldStyle(.roundedBorder)
                .frame(width: 280)
                .onSubmit { attemptUnlock() }

            HStack {
                Button("passwordPrompt.cancel.button") {
                    viewModel.cancelPendingPasswordImport()
                    dismiss()
                }
                    .keyboardShortcut(.cancelAction)
                Button("passwordPrompt.unlock.button") { attemptUnlock() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(password.isEmpty)
            }
        }
        .padding(32)
        .frame(width: 360)
    }

    private func attemptUnlock() {
        if viewModel.unlock(pdf: pdf, password: password, url: url) {
            if viewModel.pendingPasswordPDF == nil {
                dismiss()
            }
        } else {
            failed = true
            password = ""
        }
    }
}
