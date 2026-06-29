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
                .foregroundStyle(.secondary)

            Text("\"\(fileName)\" is password-protected")
                .font(.headline)

            if failed {
                Text("Incorrect password. Try again.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            SecureField("Password", text: $password)
                .textFieldStyle(.roundedBorder)
                .frame(width: 280)
                .onSubmit { attemptUnlock() }

            HStack {
                Button("Cancel") {
                    viewModel.pendingPasswordURL = nil
                    viewModel.pendingPasswordPDF = nil
                    dismiss()
                }
                    .keyboardShortcut(.cancelAction)
                Button("Unlock") { attemptUnlock() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(password.isEmpty)
            }
        }
        .padding(32)
        .frame(width: 360)
    }

    private func attemptUnlock() {
        if viewModel.unlock(pdf: pdf, password: password, url: url) {
            viewModel.isShowingPasswordPrompt = false
            viewModel.pendingPasswordURL = nil
            dismiss()
        } else {
            failed = true
            password = ""
        }
    }
}
