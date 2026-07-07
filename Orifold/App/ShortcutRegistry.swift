import Foundation

/// Groups shared by the keyboard-shortcuts cheat sheet. Kept in one place so the
/// in-app overlay and the docs page describe the same set of bindings.
enum ShortcutCategory: String, CaseIterable, Identifiable {
    case file, editing, search, navigation, view, dialogs, help

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .file:       return "shortcut.category.file"
        case .editing:    return "shortcut.category.editing"
        case .search:     return "shortcut.category.search"
        case .navigation: return "shortcut.category.navigation"
        case .view:       return "shortcut.category.view"
        case .dialogs:    return "shortcut.category.dialogs"
        case .help:       return "shortcut.category.help"
        }
    }
}

/// One row in the keyboard-shortcuts cheat sheet: a localized label paired with
/// the keycap glyphs to render. `isMostUseful` promotes it into the pinned
/// summary shown at the top of the sheet and in the first-run discovery hint.
struct ShortcutSpec: Identifiable {
    let id: String
    let category: ShortcutCategory
    let labelKey: String
    let keycaps: [String]
    let isMostUseful: Bool

    init(id: String, category: ShortcutCategory, labelKey: String, keycaps: [String], isMostUseful: Bool = false) {
        self.id = id
        self.category = category
        self.labelKey = labelKey
        self.keycaps = keycaps
        self.isMostUseful = isMostUseful
    }
}

/// Single source of truth for the Mac-only shortcuts Orifold documents and
/// surfaces in-app. Purely descriptive — the actual `.keyboardShortcut(...)`
/// bindings live alongside the controls they trigger (AppCommands, ContentView,
/// ReadingCanvas), but their keys/labels are kept in sync with this list by hand.
enum ShortcutRegistry {
    static let all: [ShortcutSpec] = [
        // File
        ShortcutSpec(
            id: "file.open", category: .file,
            labelKey: "shortcut.openWorkspace.label", keycaps: ["⌘", "O"], isMostUseful: true
        ),
        ShortcutSpec(
            id: "file.addFiles", category: .file,
            labelKey: "toolbar.addFiles.label", keycaps: ["⌘", "⇧", "O"]
        ),
        ShortcutSpec(
            id: "file.save", category: .file,
            labelKey: "shortcut.saveWorkspace.label", keycaps: ["⌘", "S"], isMostUseful: true
        ),
        ShortcutSpec(
            id: "file.duplicate", category: .file,
            labelKey: "shortcut.duplicateWorkspace.label", keycaps: ["⌘", "⇧", "S"]
        ),
        ShortcutSpec(
            id: "file.export", category: .file,
            labelKey: "toolbar.export.menuItem.export", keycaps: ["⌘", "E"], isMostUseful: true
        ),
        ShortcutSpec(
            id: "file.print", category: .file,
            labelKey: "toolbar.export.menuItem.print", keycaps: ["⌘", "P"], isMostUseful: true
        ),
        ShortcutSpec(
            id: "file.closeWindow", category: .file,
            labelKey: "shortcut.closeWindow.label", keycaps: ["⌘", "W"]
        ),

        // Editing
        ShortcutSpec(
            id: "editing.undo", category: .editing,
            labelKey: "appCommands.undo.button", keycaps: ["⌘", "Z"], isMostUseful: true
        ),
        ShortcutSpec(
            id: "editing.redo", category: .editing,
            labelKey: "appCommands.redo.button", keycaps: ["⌘", "Y"], isMostUseful: true
        ),
        ShortcutSpec(id: "editing.cut", category: .editing, labelKey: "shortcut.cut.label", keycaps: ["⌘", "X"]),
        ShortcutSpec(id: "editing.copy", category: .editing, labelKey: "shortcut.copy.label", keycaps: ["⌘", "C"]),
        ShortcutSpec(id: "editing.paste", category: .editing, labelKey: "shortcut.paste.label", keycaps: ["⌘", "V"]),
        ShortcutSpec(
            id: "editing.selectAll", category: .editing,
            labelKey: "shortcut.selectAll.label", keycaps: ["⌘", "A"]
        ),

        // Search
        ShortcutSpec(
            id: "search.find", category: .search,
            labelKey: "shortcut.find.label", keycaps: ["⌘", "F"], isMostUseful: true
        ),
        ShortcutSpec(
            id: "search.findNext", category: .search,
            labelKey: "appCommands.findNext.button", keycaps: ["⌘", "G"]
        ),
        ShortcutSpec(
            id: "search.findPrevious", category: .search,
            labelKey: "appCommands.findPrevious.button", keycaps: ["⌘", "⇧", "G"]
        ),

        // PDF Navigation
        ShortcutSpec(
            id: "navigation.zoomIn", category: .navigation,
            labelKey: "appCommands.zoomIn.button", keycaps: ["⌘", "+"]
        ),
        ShortcutSpec(
            id: "navigation.zoomOut", category: .navigation,
            labelKey: "appCommands.zoomOut.button", keycaps: ["⌘", "−"]
        ),
        ShortcutSpec(
            id: "navigation.zoomFit", category: .navigation,
            labelKey: "appCommands.zoomFit.button", keycaps: ["⌘", "0"]
        ),
        ShortcutSpec(
            id: "navigation.pageNavigation", category: .navigation,
            labelKey: "shortcut.pageNavigation.label", keycaps: ["Page ↑", "Page ↓"]
        ),

        // View
        ShortcutSpec(
            id: "view.toggleContents", category: .view,
            labelKey: "toolbar.contents.label", keycaps: ["⌘", "⌥", "1"]
        ),
        ShortcutSpec(
            id: "view.toggleInspector", category: .view,
            labelKey: "toolbar.inspector.label", keycaps: ["⌘", "⌥", "I"]
        ),
        ShortcutSpec(
            id: "view.readerMode", category: .view,
            labelKey: "toolbar.readerMode.label", keycaps: ["⌘", "⇧", "R"]
        ),

        // Dialogs
        ShortcutSpec(
            id: "dialogs.cancel", category: .dialogs,
            labelKey: "shortcut.cancelDialog.label", keycaps: ["Esc"]
        ),
        ShortcutSpec(
            id: "dialogs.confirm", category: .dialogs,
            labelKey: "shortcut.confirmDialog.label", keycaps: ["Return"]
        ),

        // Help
        ShortcutSpec(
            id: "help.shortcuts", category: .help,
            labelKey: "appCommands.keyboardShortcuts.button", keycaps: ["⌘", "/"]
        ),
        ShortcutSpec(
            id: "help.documentation", category: .help,
            labelKey: "help.viewDocumentation.button", keycaps: []
        )
    ]

    static var mostUseful: [ShortcutSpec] { all.filter(\.isMostUseful) }

    static func specs(in category: ShortcutCategory) -> [ShortcutSpec] {
        all.filter { $0.category == category }
    }
}
