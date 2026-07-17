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
            DiscardCloseCommandButton(locale: locale)
            PrintCommandButton(locale: locale)
        }

        CommandGroup(after: .toolbar) {
            ViewToggleCommandButtons(locale: locale)
            ReadAloudCommandButton(locale: locale)
            Divider()
            PetBuddyCommandToggle(locale: locale)
            PetSpeciesCommandPicker(locale: locale)
            Divider()
            ZoomCommandButtons(locale: locale)
        }

        // Replace the default "About" item with the witty popover version, and add
        // "Check for Updates…" directly beneath it — the canonical macOS placement.
        CommandGroup(replacing: .appInfo) {
            AboutCommandButton(locale: locale)
            CheckForUpdatesCommandButton(locale: locale)
        }

        CommandGroup(after: .help) {
            ViewDocumentationCommandLink(locale: locale)
            ShowKeyboardShortcutsCommandButton(locale: locale)
            RestorePreviousVersionCommandButton(locale: locale)
        }
    }
}

/// "Restore Previous Version…" — enabled only when a rollback archive exists (i.e. an update
/// was installed during this app's lifetime). Confirms intent, guards unsaved work, then hands
/// the archived previous-version bundle to the unsandboxed restore script and quits.
private struct RestorePreviousVersionCommandButton: View {
    var locale: Locale
    @State private var updates = UpdateController.shared

    var body: some View {
        Button(L10n.string("appCommands.restorePreviousVersion.button", locale: locale)) {
            confirmRestore()
        }
        .disabled(!updates.canRestorePreviousVersion)
    }

    private func confirmRestore() {
        guard let version = updates.rollbackManifest?.version else { return }
        let blocking = updates.documentsBlockingInstall()
        guard blocking.isEmpty else { presentUnsavedWorkAlert(blocking); return }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.format("update.restore.confirmTitle", version, locale: locale)
        alert.informativeText = L10n.format("update.restore.confirmMessage", version, locale: locale)
        alert.addButton(withTitle: L10n.string("update.restore.confirmButton", locale: locale))  // default
        alert.addButton(withTitle: L10n.string("update.action.cancel", locale: locale))
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        Task { @MainActor in
            if await updates.restorePreviousVersion() == false { presentRestoreFailedAlert() }
        }
    }

    private func presentUnsavedWorkAlert(_ documents: [UpdateInstallPreflight.DocumentState]) {
        let names = documents.map(\.displayName).joined(separator: ", ")
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.string("update.install.unsavedTitle", locale: locale)
        alert.informativeText = L10n.format("update.restore.unsavedMessage", names, locale: locale)
        alert.addButton(withTitle: L10n.string("common.ok", locale: locale))
        alert.runModal()
    }

    private func presentRestoreFailedAlert() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.string("update.restore.failedTitle", locale: locale)
        alert.informativeText = L10n.string("update.restore.failed", locale: locale)
        alert.addButton(withTitle: L10n.string("common.ok", locale: locale))
        alert.runModal()
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
    @FocusedValue(\.orifoldIsImporting) private var isImporting
    @FocusedValue(\.orifoldWorkspaceViewModel) private var viewModel
    var locale: Locale

    private var importInProgress: Bool { isImporting == true }

    // Drive Undo/Redo from the view model's own undo manager — the one every edit registers on
    // and that `performUndoCommand`/`performRedoCommand` actually operate on — NOT
    // `@Environment(\.undoManager)`, which resolves to nil in the `.commands` scene and left the
    // controls permanently disabled for object edits (their edit was registered and undoable, but
    // the button never saw it). Reading `structureRevision` — bumped by every `rebuild()`,
    // including AppKit-driven object commits that don't originate from a SwiftUI interaction —
    // forces these buttons to re-evaluate their enabled state after such a commit.
    private var activeUndoManager: UndoManager? {
        _ = viewModel?.structureRevision
        return viewModel?.undoManager
    }

    private var undoTitle: String {
        guard let name = activeUndoManager?.undoActionName, !name.isEmpty else {
            return L10n.string("appCommands.undo.button", locale: locale)
        }
        return L10n.format("appCommands.undo.withAction", name, locale: locale)
    }

    private var redoTitle: String {
        guard let name = activeUndoManager?.redoActionName, !name.isEmpty else {
            return L10n.string("appCommands.redo.button", locale: locale)
        }
        return L10n.format("appCommands.redo.withAction", name, locale: locale)
    }

    var body: some View {
        let undo = activeUndoManager
        Button(undoTitle) {
            viewModel?.performUndoCommand()
        }
        .keyboardShortcut("z", modifiers: .command)
        .disabled(importInProgress || viewModel == nil || undo?.canUndo != true)

        Button(redoTitle) {
            viewModel?.performRedoCommand()
        }
        .keyboardShortcut("y", modifiers: .command)
        .disabled(importInProgress || undo?.canRedo != true)
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

/// "Read Aloud" / "Stop Reading" — starts read-aloud from the current page, or stops it if
/// already active. The title reflects the mirrored `isReadingAloud` state (menus re-query on
/// open), so one command both starts and stops.
private struct ReadAloudCommandButton: View {
    @FocusedValue(\.orifoldWorkspaceViewModel) private var viewModel
    var locale: Locale

    var body: some View {
        let active = viewModel?.isReadingAloud == true
        Button(L10n.string(active ? "readaloud.stop" : "readaloud.start", locale: locale)) {
            viewModel?.toggleReadAloud()
        }
        .disabled(viewModel == nil || viewModel?.pageCount == 0)
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

/// File-menu escape hatch mirroring the More-menu "Discard Changes & Close" row: posts a
/// notification so the focused document window presents the same confirmation dialog rather
/// than acting directly. Enabled only while a document with edits is open.
private struct DiscardCloseCommandButton: View {
    @FocusedValue(\.orifoldWorkspaceViewModel) private var viewModel
    var locale: Locale

    // Read `structureRevision` (bumped by every edit's `rebuild()`) so this re-evaluates its
    // enabled state, matching how the Undo command buttons stay in sync.
    private var hasChanges: Bool {
        _ = viewModel?.structureRevision
        return viewModel?.hasUnsavedChanges == true
    }

    var body: some View {
        Button(L10n.string("appCommands.discardClose.button", locale: locale)) {
            NotificationCenter.default.post(name: .orifoldRequestDiscardClose, object: nil)
        }
        .disabled(!hasChanges)
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
