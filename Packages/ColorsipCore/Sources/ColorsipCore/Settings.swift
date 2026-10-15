import Foundation
import Observation

/// The synced settings in `settings.json` (`spec.md` §10, §11.1):
///
/// ```json
/// {
///   "formatVersion": 1,
///   "defaultFormat": "cssHex",
///   "shortcuts": { "picker": { "keyCode": 35, "modifiers": ["command", "control", "option"] } },
///   "loupe": { "diameter": 200, "gridSize": 11 },
///   "profiles": { "rules": [{ "bundleID": "com.apple.Safari", "name": "Safari", "profile": "srgb" }], "fallback": "srgb" }
/// }
/// ```
///
/// Decoding is lenient: a missing or unknown value falls back to its default, so one bad value
/// doesn't lose the rest. Only a newer `formatVersion` makes the whole file unreadable.
public struct AppSettings: Equatable, Sendable, Codable {
    public static let formatVersion = 1

    /// The active output format: the popover's format dropdown and Settings ▸ General.
    public var defaultFormat: OutputFormat = .default
    public var shortcuts = ShortcutBindings()
    /// The loupe size. The picker's mouse wheel and Settings ▸ Picker change the same values.
    public var loupe = LoupeSettings()
    /// Smart Profiles: Settings ▸ Profiles.
    public var profiles = SmartProfiles()

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case formatVersion, defaultFormat, shortcuts, loupe, profiles
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let version = try? container.decodeIfPresent(Int.self, forKey: .formatVersion), version > Self.formatVersion {
            throw ColorsipFormatError.newerFormat(version)
        }
        defaultFormat = (try? container.decodeIfPresent(OutputFormat.self, forKey: .defaultFormat)) ?? .default
        shortcuts = (try? container.decodeIfPresent(ShortcutBindings.self, forKey: .shortcuts)) ?? ShortcutBindings()
        loupe = (try? container.decodeIfPresent(LoupeSettings.self, forKey: .loupe)) ?? LoupeSettings()
        profiles = (try? container.decodeIfPresent(SmartProfiles.self, forKey: .profiles)) ?? SmartProfiles()
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.formatVersion, forKey: .formatVersion)
        try container.encode(defaultFormat, forKey: .defaultFormat)
        try container.encode(shortcuts, forKey: .shortcuts)
        try container.encode(loupe, forKey: .loupe)
        try container.encode(profiles, forKey: .profiles)
    }
}

/// The shortcut of each action. Only shortcuts that differ from the action's default are stored
/// (a cleared one as `null`), so changing a default later reaches users who never changed it.
public struct ShortcutBindings: Equatable, Sendable, Codable {
    private var overrides: [ShortcutAction: KeyboardShortcut?] = [:]

    public init() {}

    public subscript(action: ShortcutAction) -> KeyboardShortcut? {
        get { overrides[action] ?? action.defaultShortcut }
        set {
            if newValue == action.defaultShortcut {
                overrides[action] = nil
            } else {
                overrides[action] = .some(newValue)
            }
        }
    }

    private struct ActionKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    /// Unknown actions and invalid shortcuts are skipped.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: ActionKey.self)
        for key in container.allKeys {
            guard let action = ShortcutAction(rawValue: key.stringValue) else { continue }
            if (try? container.decodeNil(forKey: key)) == true {
                self[action] = nil
            } else if let shortcut = try? container.decode(KeyboardShortcut.self, forKey: key) {
                self[action] = shortcut
            }
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: ActionKey.self)
        for (action, shortcut) in overrides {
            try container.encode(shortcut, forKey: ActionKey(stringValue: action.rawValue))
        }
    }
}

/// The loupe's size (`spec.md` §4.2). Values are always kept in range: the diameter on a 20 pt
/// step, the grid size odd, so the center pixel is in the middle.
public struct LoupeSettings: Equatable, Sendable, Codable {
    public static let diameterRange = 120...400
    public static let diameterStep = 20
    public static let gridSizeRange = 5...31

    /// In points.
    public var diameter: Int {
        didSet { diameter = Self.clampedDiameter(diameter) }
    }

    /// Pixels across.
    public var gridSize: Int {
        didSet { gridSize = Self.clampedGridSize(gridSize) }
    }

    public init(diameter: Int = 200, gridSize: Int = 11) {
        self.diameter = Self.clampedDiameter(diameter)
        self.gridSize = Self.clampedGridSize(gridSize)
    }

    private enum CodingKeys: String, CodingKey {
        case diameter, gridSize
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = LoupeSettings()
        self.init(
            diameter: (try? container.decodeIfPresent(Int.self, forKey: .diameter)) ?? defaults.diameter,
            gridSize: (try? container.decodeIfPresent(Int.self, forKey: .gridSize)) ?? defaults.gridSize)
    }

    /// The nearest step in range.
    static func clampedDiameter(_ value: Int) -> Int {
        let range = diameterRange
        let steps = (Double(value - range.lowerBound) / Double(diameterStep)).rounded()
        return min(max(range.lowerBound + Int(steps) * diameterStep, range.lowerBound), range.upperBound)
    }

    /// Even values go up to the next odd one, then into range.
    static func clampedGridSize(_ value: Int) -> Int {
        let odd = value.isMultiple(of: 2) ? value + 1 : value
        return min(max(odd, gridSizeRange.lowerBound), gridSizeRange.upperBound)
    }
}

/// Loads and saves `settings.json`. Every change is saved at once, atomically. A file that
/// couldn't be loaded (corrupt or from a newer Colorsip) is never overwritten: the app runs on
/// defaults for the session and reports `loadIssue`.
@MainActor
@Observable
public final class SettingsStore {
    public private(set) var settings: AppSettings
    public private(set) var loadIssue: LibraryLoadIssue?
    /// The last save error, cleared by the next successful save.
    public private(set) var lastError: (any Error)?

    private let store: LibraryStore

    public init(store: LibraryStore) {
        self.store = store
        let file = LibraryFile.settings.rawValue
        do {
            settings = try store.load(AppSettings.self, from: .settings) ?? AppSettings()
        } catch ColorsipFormatError.newerFormat(let version) {
            settings = AppSettings()
            loadIssue = .newerFormat(file: file, version: version)
        } catch {
            settings = AppSettings()
            loadIssue = .unreadable(file: file)
        }
    }

    public func update(_ change: (inout AppSettings) -> Void) {
        var changed = settings
        change(&changed)
        guard changed != settings else { return }
        settings = changed
        guard loadIssue == nil else { return }
        do {
            try store.save(settings, to: .settings)
            lastError = nil
        } catch {
            lastError = error
        }
    }
}

/// Machine-local state in `UserDefaults` (`spec.md` §11.1). It doesn't sync.
public struct LocalSettings {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The Settings pane that was open last.
    public var settingsPane: SettingsPane {
        get { defaults.string(forKey: "settingsPane").flatMap(SettingsPane.init(rawValue:)) ?? .general }
        nonmutating set { defaults.set(newValue.rawValue, forKey: "settingsPane") }
    }

    /// The color editor's model switcher choice.
    public var editorModel: EditorModel {
        get { defaults.string(forKey: "editorModel").flatMap(EditorModel.init(rawValue:)) ?? .hex }
        nonmutating set { defaults.set(newValue.rawValue, forKey: "editorModel") }
    }

    /// Permissions the user skipped in the onboarding guide; the launch check leaves them out.
    public var skippedPermissions: Set<Permission> {
        get { Set((defaults.stringArray(forKey: "skippedPermissions") ?? []).compactMap(Permission.init(rawValue:))) }
        nonmutating set { defaults.set(newValue.map(\.rawValue).sorted(), forKey: "skippedPermissions") }
    }
}
