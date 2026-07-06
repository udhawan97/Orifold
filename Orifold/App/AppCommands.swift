import AppKit
import SwiftUI

struct AppCommands: Commands {
    var body: some Commands {
        // File menu additions — DocumentGroup already provides New, Open, Save, etc.
        CommandGroup(after: .newItem) {
            AddFilesCommandButton()
            AddFolderCommandButton()
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
    // Subscribing to LanguageManager (an ObservableObject) is what makes SwiftUI
    // re-evaluate this Commands-hosted view's body — and thus re-resolve the
    // L10n.string() label below — when the user switches languages. Without it,
    // menu titles built from L10n.string() go stale until the app relaunches,
    // since nothing else here depends on the stored language preference.
    @EnvironmentObject private var languageManager: LanguageManager
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

private struct AddFolderCommandButton: View {
    @EnvironmentObject private var languageManager: LanguageManager
    @FocusedValue(\.orifoldWorkspaceViewModel) private var viewModel

    var body: some View {
        Button(L10n.string("appCommands.addFolderToWorkspace.button")) {
            let panel = NSOpenPanel()
            configureFolderImportOpenPanel(panel)
            guard panel.runModal() == .OK, let viewModel else { return }
            let folders = panel.urls
            Task {
                let outcome = await importPickedOrDropped(files: [], folders: folders)
                await MainActor.run {
                    applyFolderImportOutcome(outcome, into: viewModel) { batch in
                        presentOverLimitAlert(for: batch, into: viewModel)
                    }
                }
            }
        }
        .disabled(viewModel == nil)
    }
}

@MainActor
private func presentOverLimitAlert(for batch: PendingFolderImportBatch, into viewModel: WorkspaceViewModel) {
    let alert = NSAlert()
    alert.messageText = folderImportOverLimitTitle(supportedCount: batch.urls.count)
    if batch.wasTruncated {
        alert.informativeText = L10n.string("folderImport.overLimit.truncatedNote")
    }
    alert.addButton(withTitle: folderImportOverLimitImportFirstLabel(count: maximumImportBatchSize))
    alert.addButton(withTitle: L10n.string("folderImport.overLimit.cancel"))
    guard alert.runModal() == .alertFirstButtonReturn else { return }
    importFirstFromPendingBatch(batch, into: viewModel)
}

private struct MakeSearchableCommandButton: View {
    @EnvironmentObject private var languageManager: LanguageManager
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
    @EnvironmentObject private var languageManager: LanguageManager
    @FocusedValue(\.orifoldWorkspaceViewModel) private var viewModel

    var body: some View {
        Button(L10n.string("appCommands.reduceFileSize.button")) {
            viewModel?.reduceFileSize()
        }
        .disabled(viewModel == nil)
    }
}

private struct UndoRedoCommandButtons: View {
    @EnvironmentObject private var languageManager: LanguageManager
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
    @EnvironmentObject private var languageManager: LanguageManager
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
    @EnvironmentObject private var languageManager: LanguageManager
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
    @EnvironmentObject private var languageManager: LanguageManager
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(L10n.string("appCommands.aboutOrifold.button")) { openWindow(id: "about-orifold") }
    }
}
