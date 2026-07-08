import AppKit
import SwiftUI

/// Externally-hosted links referenced from menu commands and in-app help surfaces.
enum OrifoldLinks {
    static let documentation = URL(string: "https://udhawan97.github.io/Orifold/")!
}

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
            AddFolderCommandButton(locale: locale)
            Divider()
            ReduceFileSizeCommandButton(locale: locale)
            MakeSearchableCommandButton(locale: locale)
            Divider()
        }

        CommandGroup(replacing: .undoRedo) {
            UndoRedoCommandButtons(locale: locale)
        }

        CommandGroup(after: .textEditing) {
            FindNavigationCommandButtons(locale: locale)
        }

        CommandGroup(after: .saveItem) {
            PrintCommandButton(locale: locale)
        }

        CommandGroup(after: .toolbar) {
            ViewToggleCommandButtons(locale: locale)
            Divider()
            PetBuddyCommandToggle(locale: locale)
            PetSpeciesCommandPicker(locale: locale)
            Divider()
            ZoomCommandButtons(locale: locale)
        }

        // Replace the default "About" item with the witty popover version
        CommandGroup(replacing: .appInfo) {
            AboutCommandButton(locale: locale)
        }

        CommandGroup(after: .help) {
            ViewDocumentationCommandLink(locale: locale)
            ShowKeyboardShortcutsCommandButton(locale: locale)
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

private struct AddFolderCommandButton: View {
    @FocusedValue(\.orifoldWorkspaceViewModel) private var viewModel
    var locale: Locale

    var body: some View {
        Button(L10n.string("appCommands.addFolderToWorkspace.button", locale: locale)) {
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
        .keyboardShortcut("y", modifiers: .command)
        .disabled(importInProgress || undoManager?.canRedo != true)
    }
}

/// Reader mode and Table of Contents used to carry their shortcuts on toolbar buttons. Now
/// that those controls live behind the More overflow, the shortcuts belong in the View menu as
/// first-class, menu-bar-discoverable commands. They post notifications rather than mutate the
/// view model directly, because the toggles also touch `ContentView`-local state (the inspector
/// tab / column visibility) that `@FocusedValue` can't reach.
private struct ViewToggleCommandButtons: View {
    @FocusedValue(\.orifoldWorkspaceViewModel) private var viewModel
    var locale: Locale

    var body: some View {
        Button(L10n.string("toolbar.readerMode.label", locale: locale)) {
            NotificationCenter.default.post(name: .orifoldToggleReaderMode, object: nil)
        }
        .keyboardShortcut("r", modifiers: [.command, .shift])
        .disabled(viewModel == nil)

        Button(L10n.string("toolbar.contents.label", locale: locale)) {
            NotificationCenter.default.post(name: .orifoldToggleTableOfContents, object: nil)
        }
        .keyboardShortcut("1", modifiers: [.command, .option])
        .disabled(viewModel == nil)
    }
}

private struct FindNavigationCommandButtons: View {
    @FocusedValue(\.orifoldWorkspaceViewModel) private var viewModel
    var locale: Locale

    var body: some View {
        Button(L10n.string("appCommands.findNext.button", locale: locale)) {
            viewModel?.searchNext()
        }
        .keyboardShortcut("g", modifiers: .command)
        .disabled(viewModel == nil || viewModel?.searchResults.isEmpty != false)

        Button(L10n.string("appCommands.findPrevious.button", locale: locale)) {
            viewModel?.searchPrevious()
        }
        .keyboardShortcut("g", modifiers: [.command, .shift])
        .disabled(viewModel == nil || viewModel?.searchResults.isEmpty != false)
    }
}

private struct PrintCommandButton: View {
    @FocusedValue(\.orifoldWorkspaceViewModel) private var viewModel
    var locale: Locale

    var body: some View {
        Button(L10n.string("appCommands.print.button", locale: locale)) {
            NotificationCenter.default.post(name: .orifoldPrint, object: nil)
        }
        .keyboardShortcut("p", modifiers: .command)
        .disabled(viewModel == nil)
    }
}

private struct ZoomCommandButtons: View {
    @FocusedValue(\.orifoldWorkspaceViewModel) private var viewModel
    var locale: Locale

    var body: some View {
        Button(L10n.string("appCommands.zoomIn.button", locale: locale)) {
            viewModel?.zoomIn()
        }
        .keyboardShortcut("+", modifiers: .command)
        .disabled(viewModel == nil)

        Button(L10n.string("appCommands.zoomOut.button", locale: locale)) {
            viewModel?.zoomOut()
        }
        .keyboardShortcut("-", modifiers: .command)
        .disabled(viewModel == nil)

        Button(L10n.string("appCommands.zoomFit.button", locale: locale)) {
            viewModel?.zoomFit()
        }
        .keyboardShortcut("0", modifiers: .command)
        .disabled(viewModel == nil)
    }
}

private struct ShowKeyboardShortcutsCommandButton: View {
    var locale: Locale

    var body: some View {
        Button(L10n.string("appCommands.keyboardShortcuts.button", locale: locale)) {
            NotificationCenter.default.post(name: .orifoldShowShortcuts, object: nil)
        }
        .keyboardShortcut("/", modifiers: .command)
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
                Text(verbatim: species.displayName(locale: locale)).tag(species)
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

private struct ViewDocumentationCommandLink: View {
    var locale: Locale

    var body: some View {
        Link(L10n.string("help.viewDocumentation.button", locale: locale), destination: OrifoldLinks.documentation)
    }
}
