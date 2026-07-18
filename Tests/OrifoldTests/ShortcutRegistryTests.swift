import SwiftUI
import XCTest
@testable import Orifold

/// The cheat sheet and the docs page render from `ShortcutRegistry`, while the real
/// `.keyboardShortcut(...)` bindings live beside the controls they trigger. When the
/// keycaps were hand-typed alongside those bindings the two drifted — the text
/// formatting chords the editor really binds never appeared in the sheet at all.
///
/// These pin the registry to the bindings: keycaps are derived from the chord the app
/// binds, so a documented shortcut cannot describe a chord the app does not have.
final class ShortcutRegistryTests: XCTestCase {
    func testEveryShortcutIDIsUnique() {
        let ids = ShortcutRegistry.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "duplicate shortcut ids: \(ids.duplicates())")
    }

    // Two rows claiming the same chord means the sheet documents one of them wrongly.
    func testNoTwoShortcutsClaimTheSameChord() {
        let chords = ShortcutRegistry.all.compactMap(\.chord)
        for (index, chord) in chords.enumerated() {
            let rest = chords[(index + 1)...]
            XCTAssertFalse(rest.contains(chord),
                           "\(chord.keycaps.joined()) is claimed by more than one shortcut row")
        }
    }

    // Keycaps must come from the chord, in the order macOS renders modifiers.
    func testKeycapsAreDerivedFromTheChord() {
        XCTAssertEqual(ShortcutChord(character: "z", modifiers: .command).keycaps, ["⌘", "Z"])
        XCTAssertEqual(ShortcutChord(character: "o", modifiers: [.command, .shift]).keycaps, ["⌘", "⇧", "O"])
        XCTAssertEqual(ShortcutChord(character: "1", modifiers: [.command, .option]).keycaps, ["⌘", "⌥", "1"])
        XCTAssertEqual(ShortcutChord(character: "-", modifiers: .command).keycaps, ["⌘", "−"],
                       "minus should render as the typographic minus the sheet used by hand")
    }

    // The bindings that had drifted: real chords in ReadingCanvas's keyDown override,
    // absent from the cheat sheet, so the app advertised them nowhere.
    func testTextFormattingChordsAreDocumented() {
        let documented = Set(ShortcutRegistry.all.compactMap(\.chord))
        for chord in [ShortcutChord.bold, .italic, .underline, .copyStyle, .pasteStyle] {
            XCTAssertTrue(documented.contains(chord),
                          "\(chord.keycaps.joined()) is bound by the editor but missing from the cheat sheet")
        }
    }

    // Every row must carry keycaps to render — a blank row is a broken sheet entry.
    // The documentation-only Help row is the deliberate exception.
    func testEveryShortcutRendersSomething() {
        for spec in ShortcutRegistry.all where spec.id != "help.documentation" {
            XCTAssertFalse(spec.keycaps.isEmpty, "\(spec.id) renders no keycaps")
        }
    }
}

private extension Array where Element: Hashable {
    func duplicates() -> [Element] {
        var seen: Set<Element> = []
        return filter { !seen.insert($0).inserted }
    }
}
