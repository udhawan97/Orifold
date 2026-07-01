import SwiftUI

struct AppCommands: Commands {
    var body: some Commands {
        // File menu additions — DocumentGroup already provides New, Open, Save, etc.
        CommandGroup(after: .newItem) {
            Divider()
        }

        CommandGroup(replacing: .undoRedo) {
            UndoRedoCommandButtons()
        }

        CommandGroup(after: .toolbar) {
            PetBuddyCommandToggle()
        }

        // Replace the default "About" item with the witty popover version
        CommandGroup(replacing: .appInfo) {
            AboutCommandButton()
        }
    }
}

private struct UndoRedoCommandButtons: View {
    @Environment(\.undoManager) private var undoManager
    @FocusedValue(\.pdfoldIsImporting) private var isImporting

    private var importInProgress: Bool { isImporting == true }

    var body: some View {
        Button("Undo") {
            undoManager?.undo()
        }
        .keyboardShortcut("z", modifiers: .command)
        .disabled(importInProgress || undoManager?.canUndo != true)

        Button("Redo") {
            undoManager?.redo()
        }
        .keyboardShortcut("z", modifiers: [.command, .shift])
        .disabled(importInProgress || undoManager?.canRedo != true)
    }
}

private struct PetBuddyCommandToggle: View {
    @AppStorage("petEnabled") private var petEnabled = true
    @State private var buddy = PetBuddy.shared

    var body: some View {
        Toggle("Show PDFold Buddy", isOn: Binding(
            get: { petEnabled },
            set: { isShowing in
                petEnabled = isShowing
                if isShowing {
                    buddy.enable()
                } else {
                    buddy.disable()
                }
            }
        ))
        .onAppear {
            if petEnabled {
                buddy.enable()
            } else {
                buddy.disable()
            }
        }
    }
}

private struct PDFoldIsImportingFocusedKey: FocusedValueKey {
    typealias Value = Bool
}

extension FocusedValues {
    var pdfoldIsImporting: Bool? {
        get { self[PDFoldIsImportingFocusedKey.self] }
        set { self[PDFoldIsImportingFocusedKey.self] = newValue }
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
