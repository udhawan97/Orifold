import SwiftUI

struct AppCommands: Commands {
    var body: some Commands {
        // File menu additions — DocumentGroup already provides New, Open, Save, etc.
        CommandGroup(after: .newItem) {
            Divider()
        }

        CommandGroup(after: .saveItem) {
            Button("Save as PDF\u{2026}") {
                NotificationCenter.default.post(name: .pdfoldSaveAsPDF, object: nil)
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
        }

        // Replace the default "About" item with the witty popover version
        CommandGroup(replacing: .appInfo) {
            AboutCommandButton()
        }
    }
}

private struct AboutCommandButton: View {
    @State private var isPresented = false

    var body: some View {
        Button("About pdFold") { isPresented = true }
            .popover(isPresented: $isPresented) {
                AppAboutPopover(isPresented: $isPresented)
            }
    }
}
