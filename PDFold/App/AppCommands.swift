import SwiftUI

struct AppCommands: Commands {
    var body: some Commands {
        // File menu additions — DocumentGroup already provides New, Open, Save, etc.
        CommandGroup(after: .newItem) {
            Divider()
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
        Button("About PDFold") { isPresented = true }
            .popover(isPresented: $isPresented) {
                AppAboutPopover(isPresented: $isPresented)
            }
    }
}
