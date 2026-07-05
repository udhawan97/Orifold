import AppKit
import SwiftUI

struct AppCommands: Commands {
    var body: some Commands {
        // File menu additions — DocumentGroup already provides New, Open, Save, etc.
        CommandGroup(after: .newItem) {
            AddFilesCommandButton()
            Divider()
            ReduceFileSizeCommandButton()
            MakeSearchableCommandButton()
            Divider()
        }

        CommandGroup(replacing: .undoRedo) {
            UndoRedoCommandButtons()
        }

        CommandGroup(after: .toolbar) {
            PetBuddyCommandToggle()
            PetSpeciesCommandPicker()
        }

        // Replace the default "About" item with the witty popover version
        CommandGroup(replacing: .appInfo) {
            AboutCommandButton()
        }
    }
}

private struct AddFilesCommandButton: View {
    @FocusedValue(\.orifoldWorkspaceViewModel) private var viewModel

    var body: some View {
        Button(L10n.string("appCommands.addFilesToWorkspace.button")) {
            let panel = NSOpenPanel()
            configureImportOpenPanel(panel)
            if panel.runModal() == .OK {
                if let viewModel {
                    importFilesWithBatchLimit(urls: panel.urls, into: viewModel)
                }
            }
        }
        .keyboardShortcut("o", modifiers: [.command, .shift])
        .disabled(viewModel == nil)
    }
}

private struct MakeSearchableCommandButton: View {
    @FocusedValue(\.orifoldWorkspaceViewModel) private var viewModel

    var body: some View {
        Button(L10n.string("appCommands.makeSearchable.button")) {
            let shouldRepairExistingText = viewModel?.hasScannedPages != true
            viewModel?.makeSearchable(includePagesWithText: shouldRepairExistingText)
        }
        .disabled(viewModel?.canStartSearchable != true && viewModel?.canRepairSearchableText != true)
    }
}

private struct ReduceFileSizeCommandButton: View {
    @FocusedValue(\.orifoldWorkspaceViewModel) private var viewModel

    var body: some View {
        Button(L10n.string("appCommands.reduceFileSize.button")) {
            viewModel?.reduceFileSize()
        }
        .disabled(viewModel == nil)
    }
}

private struct UndoRedoCommandButtons: View {
    @Environment(\.undoManager) private var undoManager
    @FocusedValue(\.orifoldIsImporting) private var isImporting
    @FocusedValue(\.orifoldWorkspaceViewModel) private var viewModel

    private var importInProgress: Bool { isImporting == true }

    var body: some View {
        Button(L10n.string("appCommands.undo.button")) {
            viewModel?.performUndoCommand()
        }
        .keyboardShortcut("z", modifiers: .command)
        .disabled(importInProgress || viewModel == nil || undoManager?.canUndo != true)

        Button(L10n.string("appCommands.redo.button")) {
            viewModel?.performRedoCommand()
        }
        .keyboardShortcut("z", modifiers: [.command, .shift])
        .disabled(importInProgress || undoManager?.canRedo != true)
    }
}

private struct PetBuddyCommandToggle: View {
    @AppStorage("petEnabled") private var petEnabled = true
    @State private var buddy = PetBuddy.shared

    var body: some View {
        Toggle(L10n.string("appCommands.showBuddy.toggle"), isOn: Binding(
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

private struct PetSpeciesCommandPicker: View {
    @AppStorage("petEnabled") private var petEnabled = true
    @State private var buddy = PetBuddy.shared

    var body: some View {
        Picker(L10n.string("appCommands.companion.title"), selection: Binding(
            get: { buddy.species },
            set: { buddy.selectSpecies($0) }
        )) {
            ForEach(PetSpecies.allCases, id: \.self) { species in
                Text(verbatim: species.displayName).tag(species)
            }
        }
        .disabled(!petEnabled)
    }
}

private struct OrifoldIsImportingFocusedKey: FocusedValueKey {
    typealias Value = Bool
}

private struct OrifoldWorkspaceViewModelFocusedKey: FocusedValueKey {
    typealias Value = WorkspaceViewModel
}

extension FocusedValues {
    var orifoldIsImporting: Bool? {
        get { self[OrifoldIsImportingFocusedKey.self] }
        set { self[OrifoldIsImportingFocusedKey.self] = newValue }
    }

    var orifoldWorkspaceViewModel: WorkspaceViewModel? {
        get { self[OrifoldWorkspaceViewModelFocusedKey.self] }
        set { self[OrifoldWorkspaceViewModelFocusedKey.self] = newValue }
    }
}

private struct AboutCommandButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(L10n.string("appCommands.aboutOrifold.button")) { openWindow(id: "about-orifold") }
    }
}
