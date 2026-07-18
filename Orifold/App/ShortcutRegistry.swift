import SwiftUI

/// A chord the app binds itself, in the form SwiftUI takes it.
///
/// Binding sites apply these rather than repeating literals, so the keycaps the cheat
/// sheet renders are DERIVED from the binding the app actually installs. Hand-typing
/// the glyphs beside each `.keyboardShortcut(...)` is what let the two drift: the
/// editor's ⌘B/⌘I/⌘U and the format painter's ⌘⇧C/⌘⇧V were real bindings that the
/// sheet never mentioned.
struct ShortcutChord: Equatable, Hashable {
    let character: Character
    let modifiers: EventModifiers

    init(character: Character, modifiers: EventModifiers) {
        self.character = character
        self.modifiers = modifiers
    }

    var keyEquivalent: KeyEquivalent { KeyEquivalent(character) }

    /// Keycap glyphs, ⌘ first, matching how this app's cheat sheet has always rendered
    /// them (⌘ ⇧ O, ⌘ ⌥ I) rather than the ⌃⌥⇧⌘ order menu bars use.
    var keycaps: [String] {
        var caps: [String] = []
        if modifiers.contains(.command) { caps.append("⌘") }
        if modifiers.contains(.control) { caps.append("⌃") }
        if modifiers.contains(.option) { caps.append("⌥") }
        if modifiers.contains(.shift) { caps.append("⇧") }
        caps.append(Self.glyph(for: character))
        return caps
    }

    private static func glyph(for character: Character) -> String {
        switch character {
        case "-": return "−"   // typographic minus, as the sheet rendered by hand
        default: return String(character).uppercased()
        }
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(character)
        hasher.combine(modifiers.rawValue)
    }
}

extension ShortcutChord {
    // File
    static let addFiles = ShortcutChord(character: "o", modifiers: [.command, .shift])
    static let export = ShortcutChord(character: "e", modifiers: .command)
    static let print = ShortcutChord(character: "p", modifiers: .command)
    static let printNUp = ShortcutChord(character: "p", modifiers: [.command, .shift])

    // Editing
    static let undo = ShortcutChord(character: "z", modifiers: .command)
    static let redo = ShortcutChord(character: "y", modifiers: .command)
    static let bold = ShortcutChord(character: "b", modifiers: .command)
    static let italic = ShortcutChord(character: "i", modifiers: .command)
    static let underline = ShortcutChord(character: "u", modifiers: .command)
    static let copyStyle = ShortcutChord(character: "c", modifiers: [.command, .shift])
    static let pasteStyle = ShortcutChord(character: "v", modifiers: [.command, .shift])

    // Search
    static let find = ShortcutChord(character: "f", modifiers: .command)
    static let findNext = ShortcutChord(character: "g", modifiers: .command)
    static let findPrevious = ShortcutChord(character: "g", modifiers: [.command, .shift])

    // Navigation
    static let zoomIn = ShortcutChord(character: "+", modifiers: .command)
    static let zoomOut = ShortcutChord(character: "-", modifiers: .command)
    static let zoomFit = ShortcutChord(character: "0", modifiers: .command)

    // View
    static let toggleContents = ShortcutChord(character: "1", modifiers: [.command, .option])
    static let toggleInspector = ShortcutChord(character: "i", modifiers: [.command, .option])
    static let readerMode = ShortcutChord(character: "r", modifiers: [.command, .shift])

    // Help
    static let keyboardShortcuts = ShortcutChord(character: "/", modifiers: .command)
}

extension View {
    /// Binds a registry chord, so the binding and the documentation cannot disagree.
    func keyboardShortcut(_ chord: ShortcutChord) -> some View {
        keyboardShortcut(chord.keyEquivalent, modifiers: chord.modifiers)
    }
}

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
    /// The chord the app binds for this row, when the app binds it itself. `nil` for
    /// rows documenting bindings AppKit provides for free (⌘X/⌘C/⌘V, Esc, Return,
    /// Page ↑/↓): there is no binding site of ours to derive glyphs from.
    let chord: ShortcutChord?
    private let literalKeycaps: [String]
    let isMostUseful: Bool

    /// Derived from `chord` whenever the app owns the binding, so the sheet cannot
    /// describe a chord the app does not install.
    var keycaps: [String] { chord?.keycaps ?? literalKeycaps }

    init(id: String, category: ShortcutCategory, labelKey: String, chord: ShortcutChord, isMostUseful: Bool = false) {
        self.id = id
        self.category = category
        self.labelKey = labelKey
        self.chord = chord
        self.literalKeycaps = []
        self.isMostUseful = isMostUseful
    }

    /// A row for a system-provided binding, whose glyphs have no chord of ours behind them.
    init(id: String, category: ShortcutCategory, labelKey: String, systemKeycaps: [String], isMostUseful: Bool = false) {
        self.id = id
        self.category = category
        self.labelKey = labelKey
        self.chord = nil
        self.literalKeycaps = systemKeycaps
        self.isMostUseful = isMostUseful
    }
}

/// Single source of truth for the Mac-only shortcuts Orifold documents and surfaces
/// in-app.
///
/// Rows carrying a `ShortcutChord` are bound from that same chord at the site that
/// installs them (AppCommands, ContentView, ReadingCanvas), so their keycaps are
/// derived rather than transcribed. Rows carrying `systemKeycaps` document bindings
/// AppKit provides for free and have no binding site of ours behind them.
enum ShortcutRegistry {
    static let all: [ShortcutSpec] = [
        // File
        ShortcutSpec(
            id: "file.open", category: .file,
            labelKey: "shortcut.openWorkspace.label", systemKeycaps: ["⌘", "O"], isMostUseful: true
        ),
        ShortcutSpec(
            id: "file.addFiles", category: .file,
            labelKey: "toolbar.addFiles.label", chord: .addFiles
        ),
        ShortcutSpec(
            id: "file.save", category: .file,
            labelKey: "shortcut.saveWorkspace.label", systemKeycaps: ["⌘", "S"], isMostUseful: true
        ),
        ShortcutSpec(
            id: "file.duplicate", category: .file,
            labelKey: "shortcut.duplicateWorkspace.label", systemKeycaps: ["⌘", "⇧", "S"]
        ),
        ShortcutSpec(
            id: "file.export", category: .file,
            labelKey: "toolbar.export.menuItem.export", chord: .export, isMostUseful: true
        ),
        ShortcutSpec(
            id: "file.print", category: .file,
            labelKey: "toolbar.export.menuItem.print", chord: .print, isMostUseful: true
        ),
        ShortcutSpec(
            id: "file.printNUp", category: .file,
            labelKey: "imposition.print.nup", chord: .printNUp
        ),
        ShortcutSpec(
            id: "file.closeWindow", category: .file,
            labelKey: "shortcut.closeWindow.label", systemKeycaps: ["⌘", "W"]
        ),

        // Editing
        ShortcutSpec(
            id: "editing.undo", category: .editing,
            labelKey: "appCommands.undo.button", chord: .undo, isMostUseful: true
        ),
        ShortcutSpec(
            id: "editing.redo", category: .editing,
            labelKey: "appCommands.redo.button", chord: .redo, isMostUseful: true
        ),
        ShortcutSpec(id: "editing.cut", category: .editing, labelKey: "shortcut.cut.label", systemKeycaps: ["⌘", "X"]),
        ShortcutSpec(id: "editing.copy", category: .editing, labelKey: "shortcut.copy.label", systemKeycaps: ["⌘", "C"]),
        ShortcutSpec(id: "editing.paste", category: .editing, labelKey: "shortcut.paste.label", systemKeycaps: ["⌘", "V"]),
        ShortcutSpec(
            id: "editing.selectAll", category: .editing,
            labelKey: "shortcut.selectAll.label", systemKeycaps: ["⌘", "A"]
        ),
        ShortcutSpec(id: "editing.bold", category: .editing, labelKey: "shortcut.bold.label", chord: .bold),
        ShortcutSpec(id: "editing.italic", category: .editing, labelKey: "shortcut.italic.label", chord: .italic),
        ShortcutSpec(
            id: "editing.underline", category: .editing,
            labelKey: "shortcut.underline.label", chord: .underline
        ),
        ShortcutSpec(
            id: "editing.copyStyle", category: .editing,
            labelKey: "shortcut.copyStyle.label", chord: .copyStyle
        ),
        ShortcutSpec(
            id: "editing.pasteStyle", category: .editing,
            labelKey: "shortcut.pasteStyle.label", chord: .pasteStyle
        ),

        // Search
        ShortcutSpec(
            id: "search.find", category: .search,
            labelKey: "shortcut.find.label", chord: .find, isMostUseful: true
        ),
        ShortcutSpec(
            id: "search.findNext", category: .search,
            labelKey: "appCommands.findNext.button", chord: .findNext
        ),
        ShortcutSpec(
            id: "search.findPrevious", category: .search,
            labelKey: "appCommands.findPrevious.button", chord: .findPrevious
        ),

        // PDF Navigation
        ShortcutSpec(
            id: "navigation.zoomIn", category: .navigation,
            labelKey: "appCommands.zoomIn.button", chord: .zoomIn
        ),
        ShortcutSpec(
            id: "navigation.zoomOut", category: .navigation,
            labelKey: "appCommands.zoomOut.button", chord: .zoomOut
        ),
        ShortcutSpec(
            id: "navigation.zoomFit", category: .navigation,
            labelKey: "appCommands.zoomFit.button", chord: .zoomFit
        ),
        ShortcutSpec(
            id: "navigation.pageNavigation", category: .navigation,
            labelKey: "shortcut.pageNavigation.label", systemKeycaps: ["Page ↑", "Page ↓"]
        ),

        // View
        ShortcutSpec(
            id: "view.toggleContents", category: .view,
            labelKey: "toolbar.contents.label", chord: .toggleContents
        ),
        ShortcutSpec(
            id: "view.toggleInspector", category: .view,
            labelKey: "toolbar.inspector.label", chord: .toggleInspector
        ),
        ShortcutSpec(
            id: "view.readerMode", category: .view,
            labelKey: "toolbar.readerMode.label", chord: .readerMode
        ),

        // Dialogs
        ShortcutSpec(
            id: "dialogs.cancel", category: .dialogs,
            labelKey: "shortcut.cancelDialog.label", systemKeycaps: ["Esc"]
        ),
        ShortcutSpec(
            id: "dialogs.confirm", category: .dialogs,
            labelKey: "shortcut.confirmDialog.label", systemKeycaps: ["Return"]
        ),

        // Help
        ShortcutSpec(
            id: "help.shortcuts", category: .help,
            labelKey: "appCommands.keyboardShortcuts.button", chord: .keyboardShortcuts
        ),
        ShortcutSpec(
            id: "help.documentation", category: .help,
            labelKey: "help.viewDocumentation.button", systemKeycaps: []
        )
    ]

    static var mostUseful: [ShortcutSpec] { all.filter(\.isMostUseful) }

    static func specs(in category: ShortcutCategory) -> [ShortcutSpec] {
        all.filter { $0.category == category }
    }
}
