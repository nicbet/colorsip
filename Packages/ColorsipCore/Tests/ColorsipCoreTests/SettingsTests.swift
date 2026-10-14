import Foundation
import Testing
@testable import ColorsipCore

private func decode(_ json: String) throws -> AppSettings {
    try JSONDecoder.library.decode(AppSettings.self, from: Data(json.utf8))
}

/// A settings store in a fresh temporary library folder.
private struct TempFolder {
    let root = FileManager.default.temporaryDirectory.appending(path: "ColorsipTests-\(UUID().uuidString)")
    var store: LibraryStore { LibraryStore(folder: root.appending(path: "Library")) }
    var settingsURL: URL { store.folder.appending(path: "settings.json") }

    func write(_ string: String) throws {
        try FileManager.default.createDirectory(at: store.folder, withIntermediateDirectories: true)
        try Data(string.utf8).write(to: settingsURL)
    }
    func contents() throws -> String { String(decoding: try Data(contentsOf: settingsURL), as: UTF8.self) }
    func cleanUp() { try? FileManager.default.removeItem(at: root) }
}

@Suite("Settings")
struct SettingsTests {
    @Test func defaults() {
        let settings = AppSettings()
        #expect(settings.defaultFormat == .cssHex)
        #expect(settings.shortcuts[.picker] == ShortcutAction.picker.defaultShortcut)
        #expect(settings.shortcuts[.contrastChecker] == nil)
        #expect(settings.loupe.diameter == 200)
        #expect(settings.loupe.gridSize == 11)
    }

    @Test func roundTrip() throws {
        var settings = AppSettings()
        settings.defaultFormat = .swiftUI
        settings.shortcuts[.picker] = KeyboardShortcut(keyCode: 8, modifiers: [.command, .shift])
        settings.shortcuts[.mainWindow] = KeyboardShortcut(keyCode: 46, modifiers: [.option])
        settings.loupe.diameter = 260
        settings.loupe.gridSize = 15
        let decoded = try JSONDecoder.library.decode(AppSettings.self, from: JSONEncoder.library.encode(settings))
        #expect(decoded == settings)
    }

    @Test func clearedShortcutIsStoredAsNull() throws {
        var settings = AppSettings()
        settings.shortcuts[.picker] = nil
        let json = String(decoding: try JSONEncoder.library.encode(settings), as: UTF8.self)
        #expect(json.contains(#""picker" : null"#))
        #expect(try decode(json).shortcuts[.picker] == nil)
    }

    @Test func settingTheDefaultForgetsTheOverride() throws {
        var settings = AppSettings()
        settings.shortcuts[.picker] = nil
        settings.shortcuts[.picker] = ShortcutAction.picker.defaultShortcut
        #expect(settings == AppSettings())
    }

    @Test func writesTheFormatVersion() throws {
        let json = String(decoding: try JSONEncoder.library.encode(AppSettings()), as: UTF8.self)
        #expect(json.contains(#""formatVersion" : 1"#))
    }

    @Test func missingKeysFallBackToDefaults() throws {
        #expect(try decode("{}") == AppSettings())
        #expect(try decode(#"{ "formatVersion": 1, "loupe": { "gridSize": 7 } }"#).loupe
            == LoupeSettings(diameter: 200, gridSize: 7))
    }

    @Test func unknownValuesFallBackToDefaults() throws {
        let settings = try decode(#"""
            { "formatVersion": 1, "defaultFormat": "cmyk", "shortcuts": { "picker": 3, "teleport": null } }
            """#)
        #expect(settings == AppSettings())
    }

    @Test func newerFormatIsRejected() {
        #expect(throws: ColorsipFormatError.newerFormat(2)) { try decode(#"{ "formatVersion": 2 }"#) }
    }

    @Test func loupeDiameterIsClampedToTheRangeAndStep() {
        var loupe = LoupeSettings()
        loupe.diameter = 50
        #expect(loupe.diameter == 120)
        loupe.diameter = 999
        #expect(loupe.diameter == 400)
        loupe.diameter = 249
        #expect(loupe.diameter == 240)
        loupe.diameter = 251
        #expect(loupe.diameter == 260)
    }

    @Test func gridSizeIsClampedToOddValuesInRange() {
        var loupe = LoupeSettings()
        loupe.gridSize = 1
        #expect(loupe.gridSize == 5)
        loupe.gridSize = 40
        #expect(loupe.gridSize == 31)
        loupe.gridSize = 12
        #expect(loupe.gridSize == 13)
        loupe.gridSize = 9
        #expect(loupe.gridSize == 9)
    }

    @Test func loadedLoupeValuesAreClamped() throws {
        #expect(try decode(#"{ "loupe": { "diameter": 1000, "gridSize": 4 } }"#).loupe
            == LoupeSettings(diameter: 400, gridSize: 5))
    }
}

@Suite("AppSettings store")
@MainActor
struct SettingsStoreTests {
    @Test func missingFileGivesDefaults() {
        let temp = TempFolder()
        defer { temp.cleanUp() }
        let store = SettingsStore(store: temp.store)
        #expect(store.settings == AppSettings())
        #expect(store.loadIssue == nil)
    }

    @Test func updateSavesAndReloads() throws {
        let temp = TempFolder()
        defer { temp.cleanUp() }
        let store = SettingsStore(store: temp.store)
        store.update { $0.defaultFormat = .cssOKLCH }
        #expect(store.settings.defaultFormat == .cssOKLCH)
        #expect(store.lastError == nil)
        #expect(SettingsStore(store: temp.store).settings.defaultFormat == .cssOKLCH)
    }

    @Test func updateWithoutChangeDoesNotWrite() {
        let temp = TempFolder()
        defer { temp.cleanUp() }
        let store = SettingsStore(store: temp.store)
        store.update { $0.defaultFormat = .cssHex }
        #expect(!FileManager.default.fileExists(atPath: temp.settingsURL.path))
    }

    @Test func corruptFileIsReportedAndNeverOverwritten() throws {
        let temp = TempFolder()
        defer { temp.cleanUp() }
        try temp.write("not json")
        let store = SettingsStore(store: temp.store)
        #expect(store.loadIssue == .unreadable(file: "settings.json"))
        #expect(store.settings == AppSettings())
        store.update { $0.defaultFormat = .android }
        #expect(store.settings.defaultFormat == .android) // works for this session
        #expect(try temp.contents() == "not json")
    }

    @Test func newerFileIsReportedAndNeverOverwritten() throws {
        let temp = TempFolder()
        defer { temp.cleanUp() }
        let newer = #"{ "formatVersion": 7, "defaultFormat": "swiftUI" }"#
        try temp.write(newer)
        let store = SettingsStore(store: temp.store)
        #expect(store.loadIssue == .newerFormat(file: "settings.json", version: 7))
        #expect(store.settings == AppSettings())
        store.update { $0.loupe.diameter = 300 }
        #expect(try temp.contents() == newer)
    }

    @Test func failedSaveKeepsTheChangeAndRecordsTheError() throws {
        let temp = TempFolder()
        defer { temp.cleanUp() }
        // A file where the library folder should be makes the write fail.
        try FileManager.default.createDirectory(at: temp.root, withIntermediateDirectories: true)
        try Data().write(to: temp.store.folder)
        let store = SettingsStore(store: temp.store)
        store.update { $0.defaultFormat = .nsColor }
        #expect(store.settings.defaultFormat == .nsColor)
        #expect(store.lastError != nil)
    }
}

@Suite("Local settings")
@MainActor
struct LocalSettingsTests {
    @Test func remembersTheSettingsPane() throws {
        let suite = "ColorsipTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(LocalSettings(defaults: defaults).settingsPane == .general)
        LocalSettings(defaults: defaults).settingsPane = .picker
        #expect(LocalSettings(defaults: defaults).settingsPane == .picker)
    }

    @Test func unknownStoredPaneFallsBackToGeneral() throws {
        let suite = "ColorsipTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("teleport", forKey: "settingsPane")
        #expect(LocalSettings(defaults: defaults).settingsPane == .general)
    }

    @Test func remembersSkippedPermissions() throws {
        let temp = try TemporaryDefaults()
        #expect(temp.localSettings.skippedPermissions.isEmpty)
        temp.localSettings.skippedPermissions = [.accessibility]
        #expect(temp.localSettings.skippedPermissions == [.accessibility])
    }

    @Test func unknownSkippedPermissionsAreIgnored() throws {
        let temp = try TemporaryDefaults()
        temp.defaults.set(["accessibility", "telepathy"], forKey: "skippedPermissions")
        #expect(temp.localSettings.skippedPermissions == [.accessibility])
    }
}

@Suite("AppSettings panes")
struct SettingsPaneTests {
    @Test func mvpShowsGeneralShortcutsPickerAndPermissions() {
        // Profiles (cs-615265) appears once its content exists.
        #expect(SettingsPane.visible(for: .mvp) == [.general, .shortcuts, .picker, .permissions])
    }

    @Test func v3AddsFormatsAndSync() {
        #expect(SettingsPane.visible(for: .v3) == [.general, .shortcuts, .picker, .permissions, .formats, .sync])
    }
}
