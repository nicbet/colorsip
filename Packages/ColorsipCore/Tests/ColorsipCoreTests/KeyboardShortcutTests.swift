import Foundation
import Testing
@testable import ColorsipCore

@Suite("Keyboard shortcut")
struct KeyboardShortcutTests {
    @Test func pickerDefaultIsHyperP() {
        let shortcut = ShortcutAction.picker.defaultShortcut
        #expect(shortcut == KeyboardShortcut(keyCode: 35, modifiers: [.control, .option, .command]))
        #expect(shortcut?.displayString() == "⌃⌥⌘P")
    }

    @Test func v2ActionsHaveNoDefault() {
        #expect(ShortcutAction.contrastChecker.defaultShortcut == nil)
        #expect(ShortcutAction.mainWindow.defaultShortcut == nil)
    }

    @Test func displayUsesAppleModifierOrder() {
        let shortcut = KeyboardShortcut(keyCode: 0, modifiers: [.command, .shift, .option, .control])
        #expect(shortcut.displayString() == "⌃⌥⇧⌘A")
    }

    @Test func displayUsesTheLayoutKeyName() {
        let shortcut = KeyboardShortcut(keyCode: 6, modifiers: [.command])
        // keyCode 6 is "Z" on ANSI and "Y" on a German layout.
        #expect(shortcut.displayString { _ in "y" } == "⌘Y")
        #expect(shortcut.displayString { _ in nil } == "⌘Z")
    }

    @Test func displayNamesSpecialKeysIgnoringTheLayout() {
        #expect(KeyboardShortcut(keyCode: 49, modifiers: [.option]).displayString { _ in " " } == "⌥Space")
        #expect(KeyboardShortcut(keyCode: 122, modifiers: []).displayString() == "F1")
        #expect(KeyboardShortcut(keyCode: 126, modifiers: [.command]).displayString() == "⌘↑")
        #expect(KeyboardShortcut(keyCode: 51, modifiers: [.command]).displayString() == "⌘⌫")
    }

    @Test func displayFallsBackToTheKeyCode() {
        #expect(KeyboardShortcut(keyCode: 200, modifiers: [.command]).displayString() == "⌘Key 200")
    }

    @Test func requiresCommandControlOrOption() {
        #expect(KeyboardShortcut(keyCode: 35, modifiers: [.command]).hasRequiredModifier)
        #expect(KeyboardShortcut(keyCode: 35, modifiers: [.control]).hasRequiredModifier)
        #expect(KeyboardShortcut(keyCode: 35, modifiers: [.option]).hasRequiredModifier)
        #expect(!KeyboardShortcut(keyCode: 35, modifiers: []).hasRequiredModifier)
        #expect(!KeyboardShortcut(keyCode: 35, modifiers: [.shift]).hasRequiredModifier)
    }

    @Test func functionKeysNeedNoModifier() {
        #expect(KeyboardShortcut(keyCode: 122, modifiers: []).hasRequiredModifier) // F1
        #expect(KeyboardShortcut(keyCode: 90, modifiers: [.shift]).hasRequiredModifier) // F20
    }

    @Test func convertsFromCarbonFlags() {
        // cmdKey 0x100, shiftKey 0x200, optionKey 0x800, controlKey 0x1000; other bits ignored.
        #expect(KeyboardShortcut.Modifiers(carbonFlags: 0x100 | 0x1000) == [.command, .control])
        #expect(KeyboardShortcut.Modifiers(carbonFlags: 0x200 | 0x800 | 0x80_0000) == [.shift, .option])
        #expect(KeyboardShortcut.Modifiers([.command, .shift, .option, .control]).carbonFlags == 0x1B00)
    }

    @Test func convertsFromCocoaFlags() {
        // NSEvent.ModifierFlags: shift 1<<17, control 1<<18, option 1<<19, command 1<<20.
        #expect(KeyboardShortcut.Modifiers(cocoaFlags: 1 << 20 | 1 << 18 | 1 << 16) == [.command, .control])
        #expect(KeyboardShortcut.Modifiers(cocoaFlags: 1 << 17 | 1 << 19) == [.shift, .option])
    }

    @Test func encodesModifiersAsNames() throws {
        let shortcut = KeyboardShortcut(keyCode: 35, modifiers: [.option, .command, .control])
        let json = String(decoding: try JSONEncoder.library.encode(shortcut), as: UTF8.self)
        #expect(json.contains(#""modifiers" : ["#))
        #expect(json.contains(#""command""#) && json.contains(#""control""#) && json.contains(#""option""#))
        #expect(try JSONDecoder.library.decode(KeyboardShortcut.self, from: Data(json.utf8)) == shortcut)
    }

    @Test func ignoresUnknownModifierNames() throws {
        let json = #"{ "keyCode": 35, "modifiers": ["command", "hyper"] }"#
        #expect(try JSONDecoder.library.decode(KeyboardShortcut.self, from: Data(json.utf8))
            == KeyboardShortcut(keyCode: 35, modifiers: [.command]))
    }
}

@Suite("Shortcut actions")
struct ShortcutActionTests {
    @Test func mvpShowsOnlyThePicker() {
        #expect(ShortcutAction.visible(for: .mvp) == [.picker])
    }

    @Test func v2AddsContrastCheckerAndMainWindow() {
        #expect(ShortcutAction.visible(for: .v2) == [.picker, .contrastChecker, .mainWindow])
    }
}
