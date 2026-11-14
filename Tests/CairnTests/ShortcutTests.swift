import AppKit
import Carbon.HIToolbox
import SwiftUI
import XCTest
@testable import CairnCore

final class ShortcutTests: XCTestCase {

    func testDefaultsAreUniqueUsableAndNotReserved() {
        let settings = ShortcutSettings()
        var seen: [KeyCombo] = []
        for action in ShortcutAction.allCases {
            let combo = action.defaultCombo
            XCTAssertTrue(combo.isUsable, action.title)
            XCTAssertNotNil(combo.keyboardShortcut, action.title)
            XCTAssertFalse(ShortcutSettings.reserved.contains { $0.sameKeys(as: combo) }, action.title)
            XCTAssertFalse(seen.contains { $0.sameKeys(as: combo) }, "doublon : \(action.title)")
            XCTAssertNil(settings.problem(with: combo, for: action), action.title)
            seen.append(combo)
        }
        XCTAssertNotNil(ShortcutAction.quickCapture.defaultCombo.keyCode, "le raccourci global a besoin du code de touche")
    }

    func testDisplay() {
        XCTAssertEqual(KeyCombo("n", shift: true).display, "⇧⌘N")
        XCTAssertEqual(KeyCombo("n", command: false, option: true, control: true).display, "⌃⌥N")
        XCTAssertEqual(KeyCombo("return").display, "⌘↩")
        XCTAssertEqual(KeyCombo("k").spelledOut, "Cmd+K")
        XCTAssertEqual(KeyCombo("e", shift: true).spelledOut, "Maj+Cmd+E")
    }

    func testKeyboardShortcutMapping() throws {
        let shortcut = try XCTUnwrap(KeyCombo("x", shift: true).keyboardShortcut)
        XCTAssertEqual(shortcut.key, KeyEquivalent("x"))
        XCTAssertEqual(shortcut.modifiers, [.command, .shift])
        XCTAssertEqual(KeyCombo("up", command: false, control: true).keyboardShortcut?.key, .upArrow)
        XCTAssertNotNil(KeyCombo("f5", command: false).keyboardShortcut)
        XCTAssertNil(KeyCombo("touche-inconnue").keyboardShortcut)
    }

    func testUsability() {
        XCTAssertFalse(KeyCombo("n", command: false).isUsable)
        XCTAssertFalse(KeyCombo("n", command: false, shift: true).isUsable)
        XCTAssertFalse(KeyCombo("n", command: false, option: true).isUsable, "⌥N tape « ~ » : interdit")
        XCTAssertTrue(KeyCombo("n", command: false, control: true).isUsable)
        XCTAssertTrue(KeyCombo("f6", command: false).isUsable)
    }

    func testChangeResetAndDisable() {
        var settings = ShortcutSettings()
        settings.set(KeyCombo("j"), for: .search)
        XCTAssertEqual(settings.combo(for: .search), KeyCombo("j"))
        XCTAssertFalse(settings.isDefault(.search))

        // Revenir à la valeur par défaut efface la personnalisation.
        settings.set(KeyCombo("k"), for: .search)
        XCTAssertTrue(settings.isDefault(.search))
        XCTAssertFalse(settings.hasChanges)

        settings.set(nil, for: .favorite)
        XCTAssertNil(settings.combo(for: .favorite))
        XCTAssertNil(settings.shortcut(for: .favorite))
        XCTAssertEqual(settings.help("Favori", .favorite), "Favori")

        settings.reset(.favorite)
        XCTAssertEqual(settings.combo(for: .favorite), ShortcutAction.favorite.defaultCombo)
        XCTAssertEqual(settings.help("Favori", .favorite), "Favori (Cmd+D)")
    }

    func testProblems() {
        let settings = ShortcutSettings()
        XCTAssertEqual(settings.problem(with: KeyCombo("q"), for: .search), .reserved)
        XCTAssertEqual(settings.problem(with: KeyCombo("c"), for: .search), .reserved)
        XCTAssertEqual(settings.problem(with: KeyCombo("n", command: false), for: .search), .unusable)
        XCTAssertEqual(settings.problem(with: KeyCombo("n"), for: .search), .usedBy(.newPage))
        XCTAssertNil(settings.problem(with: KeyCombo("k"), for: .search), "son propre raccourci n'est pas un conflit")
        XCTAssertNil(settings.problem(with: KeyCombo("j"), for: .search))
        // Le raccourci global compte aussi : ⌃⌥N est déjà pris par la capture rapide.
        XCTAssertEqual(settings.problem(with: KeyCombo("n", command: false, option: true, control: true), for: .bold),
                       .usedBy(.quickCapture))
    }

    func testFreedShortcutCanBeReused() {
        var settings = ShortcutSettings()
        settings.set(nil, for: .newPage)
        XCTAssertNil(settings.problem(with: KeyCombo("n"), for: .search))
    }

    func testJSONRoundTripAndBadInput() {
        var settings = ShortcutSettings()
        settings.set(KeyCombo("j", option: true), for: .search)
        settings.set(nil, for: .reload)
        XCTAssertEqual(ShortcutSettings.load(from: settings.json), settings)
        XCTAssertEqual(ShortcutSettings.load(from: ""), ShortcutSettings())
        XCTAssertEqual(ShortcutSettings.load(from: "{pas du json"), ShortcutSettings())
    }

    func testGlobalShortcutKeepsItsKeyCode() {
        var settings = ShortcutSettings()
        let combo = KeyCombo("space", command: false, option: true, control: true, keyCode: kVK_Space)
        settings.set(combo, for: .quickCapture)
        XCTAssertEqual(settings.combo(for: .quickCapture)?.keyCode, kVK_Space)
        XCTAssertEqual(combo.carbonModifiers, controlKey | optionKey)
    }

    func testRecordingFromKeyEvents() throws {
        func event(_ characters: String, code: Int, flags: NSEvent.ModifierFlags) -> NSEvent? {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0,
                             context: nil, characters: characters, charactersIgnoringModifiers: characters,
                             isARepeat: false, keyCode: UInt16(code))
        }
        let up = try XCTUnwrap(event("\u{F700}", code: kVK_UpArrow, flags: [.control]))
        XCTAssertEqual(KeyCombo(event: up), KeyCombo("up", command: false, control: true, keyCode: kVK_UpArrow))
        let f5 = try XCTUnwrap(event("\u{F708}", code: kVK_F5, flags: []))
        XCTAssertEqual(KeyCombo(event: f5)?.key, "f5")
        let escape = try XCTUnwrap(event("\u{1B}", code: kVK_Escape, flags: [.command]))
        XCTAssertEqual(KeyCombo(event: escape)?.key, "escape")
    }
}
