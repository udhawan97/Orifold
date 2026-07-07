import AppKit
import SwiftUI

struct AppCommands: Commands {
    // `@ObservedObject` (not `@Environment`) because `Commands` has no
    // `.environmentObject`/`.environment` modifier to inject it — this is the
    // one mechanism that reliably re-invokes `body` when the language changes,
    // so `locale` below is always resolved fresh for each command button.
    @ObservedObject var languageManager: LanguageManager

    private var locale: Locale { languageManager.effectiveLocale }

    var body: some Commands {
        // File menu additions — DocumentGroup already provides New, Open, Save, etc.
        CommandGroup(after: .newItem) {
            AddFilesCommandButton(locale: locale)
            Divider()
            ReduceFileSizeCommandButton(locale: locale)
            MakeSearchableCommandButton(locale: locale)
            Divider()
        }

        CommandGroup(replacing: .undoRedo) {
            UndoRedoCommandButtons(locale: locale)
        }

        CommandGroup(after: .toolbar) {
            PetBuddyCommandToggle(locale: locale)
            PetSpeciesCommandPicker(locale: locale)
        }

        // Replace the default "About" item with the witty popover version
        CommandGroup(replacing: .appInfo) {
            AboutCommandButton(locale: locale)
        }
    }
}

private struct AddFilesCommandButton: View {
    @FocusedValue(\.orifoldWorkspaceViewModel) private var viewModel
    var locale: Locale

    var body: some View {
        Button(L10n.string("appCommands.addFilesToWorkspace.button", locale: locale)) {
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
    var locale: Locale

    var body: some View {
        Button(L10n.string("appCommands.makeSearchable.button", locale: locale)) {
            let shouldRepairExistingText = viewModel?.hasScannedPages != true
            viewModel?.makeSearchable(includePagesWithText: shouldRepairExistingText)
        }
        .disabled(viewModel?.canStartSearchable != true && viewModel?.canRepairSearchableText != true)
    }
}

private struct ReduceFileSizeCommandButton: View {
    @FocusedValue(\.orifoldWorkspaceViewModel) private var viewModel
    var locale: Locale

    var body: some View {
        Button(L10n.string("appCommands.reduceFileSize.button", locale: locale)) {
            viewModel?.reduceFileSize()
        }
        .disabled(viewModel == nil)
    }
}

private struct UndoRedoCommandButtons: View {
    @Environment(\.undoManager) private var undoManager
    @FocusedValue(\.orifoldIsImporting) private var isImporting
    @FocusedValue(\.orifoldWorkspaceViewModel) private var viewModel
    var locale: Locale

    private var importInProgress: Bool { isImporting == true }

    var body: some View {
        Button(L10n.string("appCommands.undo.button", locale: locale)) {
            viewModel?.performUndoCommand()
        }
        .keyboardShortcut("z", modifiers: .command)
        .disabled(importInProgress || viewModel == nil || undoManager?.canUndo != true)

        Button(L10n.string("appCommands.redo.button", locale: locale)) {
            viewModel?.performRedoCommand()
        }
        .keyboardShortcut("z", modifiers: [.command, .shift])
        .disabled(importInProgress || undoManager?.canRedo != true)
    }
}

private struct PetBuddyCommandToggle: View {
    @AppStorage("petEnabled") private var petEnabled = true
    @State private var buddy = PetBuddy.shared
    var locale: Locale

    var body: some View {
        Toggle(L10n.string("appCommands.showBuddy.toggle", locale: locale), isOn: Binding(
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
    var locale: Locale

    var body: some View {
        Picker(L10n.string("appCommands.companion.title", locale: locale), selection: Binding(
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
    var locale: Locale

    var body: some View {
        Button(L10n.string("appCommands.aboutOrifold.button", locale: locale)) { openWindow(id: "about-orifold") }
    }
}
