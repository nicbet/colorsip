import Foundation
import Testing
@testable import ColorsipCore

@MainActor
final class FakeHotKeyRegistrar: HotKeyRegistrar {
    var onPress: ((ShortcutAction) -> Void)?
    /// Shortcuts another app holds: registering them fails.
    var takenByOtherApps: Set<KeyboardShortcut> = []
    var reservedBySystem: Set<KeyboardShortcut> = []
    private(set) var registered: [ShortcutAction: KeyboardShortcut] = [:]

    func register(_ shortcut: KeyboardShortcut, for action: ShortcutAction) -> Bool {
        guard !takenByOtherApps.contains(shortcut) else { return false }
        registered[action] = shortcut
        return true
    }

    func unregister(_ action: ShortcutAction) {
        registered[action] = nil
    }

    func isReservedBySystem(_ shortcut: KeyboardShortcut) -> Bool {
        reservedBySystem.contains(shortcut)
    }

    func press(_ action: ShortcutAction) {
        if registered[action] != nil { onPress?(action) }
    }
}

private let hyperP = ShortcutAction.picker.defaultShortcut!
private let cmdShiftC = KeyboardShortcut(keyCode: 8, modifiers: [.command, .shift])
private let optM = KeyboardShortcut(keyCode: 46, modifiers: [.option])

@Suite("Shortcut manager")
@MainActor
struct ShortcutManagerTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "ColorsipTests-\(UUID().uuidString)")
    let registrar = FakeHotKeyRegistrar()

    func makeSettings() -> SettingsStore {
        SettingsStore(store: LibraryStore(folder: root.appending(path: "Library")))
    }

    func makeManager(_ settings: SettingsStore? = nil, release: Release = .mvp) -> ShortcutManager {
        ShortcutManager(settings: settings ?? makeSettings(), registrar: registrar, release: release)
    }

    func cleanUp() { try? FileManager.default.removeItem(at: root) }

    @Test func registersThePickerDefaultAtLaunch() {
        defer { cleanUp() }
        let manager = makeManager()
        #expect(registrar.registered == [.picker: hyperP])
        #expect(manager.problems.isEmpty)
    }

    @Test func registersOnlyVisibleActions() {
        defer { cleanUp() }
        let settings = makeSettings()
        settings.update { $0.shortcuts[.mainWindow] = optM }
        _ = makeManager(settings, release: .mvp)
        #expect(registrar.registered == [.picker: hyperP])
    }

    @Test func registersV2ActionsInV2() {
        defer { cleanUp() }
        let settings = makeSettings()
        settings.update { $0.shortcuts[.mainWindow] = optM }
        _ = makeManager(settings, release: .v2)
        #expect(registrar.registered == [.picker: hyperP, .mainWindow: optM])
    }

    @Test func pressCallsTheHandler() {
        defer { cleanUp() }
        let manager = makeManager()
        var triggered: [ShortcutAction] = []
        manager.onTrigger = { triggered.append($0) }
        registrar.press(.picker)
        #expect(triggered == [.picker])
    }

    @Test func launchConflictIsReported() {
        defer { cleanUp() }
        registrar.takenByOtherApps = [hyperP]
        let manager = makeManager()
        #expect(manager.problems[.picker] == .inUseByAnotherApp)
        #expect(registrar.registered.isEmpty)
    }

    @Test func setReplacesAndSaves() {
        defer { cleanUp() }
        let settings = makeSettings()
        let manager = makeManager(settings)
        #expect(manager.set(cmdShiftC, for: .picker) == nil)
        #expect(registrar.registered == [.picker: cmdShiftC])
        #expect(manager.shortcut(for: .picker) == cmdShiftC)
        #expect(makeSettings().settings.shortcuts[.picker] == cmdShiftC)
    }

    @Test func setClearsAPreviousProblem() {
        defer { cleanUp() }
        registrar.takenByOtherApps = [hyperP]
        let manager = makeManager()
        #expect(manager.set(cmdShiftC, for: .picker) == nil)
        #expect(manager.problems[.picker] == nil)
    }

    @Test func clearingUnregisters() {
        defer { cleanUp() }
        let manager = makeManager()
        #expect(manager.set(nil, for: .picker) == nil)
        #expect(registrar.registered.isEmpty)
        #expect(manager.shortcut(for: .picker) == nil)
        #expect(makeSettings().settings.shortcuts[.picker] == nil)
    }

    @Test func restoreDefault() {
        defer { cleanUp() }
        let manager = makeManager()
        manager.set(cmdShiftC, for: .picker)
        #expect(manager.restoreDefault(for: .picker) == nil)
        #expect(registrar.registered == [.picker: hyperP])
        #expect(makeSettings().settings == AppSettings())
    }

    @Test func settingTheSameShortcutIsANoOp() {
        defer { cleanUp() }
        let manager = makeManager()
        #expect(manager.set(hyperP, for: .picker) == nil)
        #expect(registrar.registered == [.picker: hyperP])
    }

    @Test func rejectsAShortcutWithoutModifier() {
        defer { cleanUp() }
        let manager = makeManager()
        let plainP = KeyboardShortcut(keyCode: 35, modifiers: [.shift])
        #expect(manager.set(plainP, for: .picker) == .needsModifier)
        // `problems` describes the current shortcut, which is still fine.
        #expect(manager.problems.isEmpty)
        #expect(registrar.registered == [.picker: hyperP])
        #expect(manager.shortcut(for: .picker) == hyperP)
    }

    @Test func rejectsAShortcutUsedByAnotherAction() {
        defer { cleanUp() }
        let manager = makeManager(release: .v2)
        #expect(manager.set(hyperP, for: .mainWindow) == .usedBy(.picker))
        #expect(manager.shortcut(for: .mainWindow) == nil)
        #expect(registrar.registered == [.picker: hyperP])
    }

    @Test func rejectsASystemShortcut() {
        defer { cleanUp() }
        let cmdSpace = KeyboardShortcut(keyCode: 49, modifiers: [.command])
        registrar.reservedBySystem = [cmdSpace]
        let manager = makeManager()
        #expect(manager.set(cmdSpace, for: .picker) == .reservedBySystem)
        #expect(registrar.registered == [.picker: hyperP])
    }

    @Test func registrationFailureKeepsTheOldShortcut() {
        defer { cleanUp() }
        registrar.takenByOtherApps = [cmdShiftC]
        let manager = makeManager()
        #expect(manager.set(cmdShiftC, for: .picker) == .inUseByAnotherApp)
        #expect(registrar.registered == [.picker: hyperP])
        #expect(manager.shortcut(for: .picker) == hyperP)
        #expect(makeSettings().settings.shortcuts[.picker] == hyperP)
    }

    @Test func validateReportsWithoutChangingAnything() {
        defer { cleanUp() }
        let manager = makeManager(release: .v2)
        #expect(manager.validate(hyperP, for: .contrastChecker) == .usedBy(.picker))
        #expect(manager.validate(hyperP, for: .picker) == nil)
        #expect(manager.problems.isEmpty)
    }

    @Test func suspendAndResume() {
        defer { cleanUp() }
        let manager = makeManager()
        manager.suspend()
        #expect(registrar.registered.isEmpty)
        // A change while suspended is saved but only registered on resume.
        manager.set(cmdShiftC, for: .picker)
        #expect(registrar.registered.isEmpty)
        manager.resume()
        #expect(registrar.registered == [.picker: cmdShiftC])
    }

    @Test func registrationFailureWhileSuspendedIsCheckedOnResume() {
        defer { cleanUp() }
        registrar.takenByOtherApps = [cmdShiftC]
        let manager = makeManager()
        manager.suspend()
        #expect(manager.set(cmdShiftC, for: .picker) == .inUseByAnotherApp)
        manager.resume()
        #expect(registrar.registered == [.picker: hyperP])
    }
}
