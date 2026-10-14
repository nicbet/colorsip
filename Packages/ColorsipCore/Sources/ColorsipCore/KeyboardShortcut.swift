/// A global keyboard shortcut: a macOS virtual key code plus modifiers. Storing the key code
/// rather than a character keeps the shortcut on the same physical key when the keyboard layout
/// changes, which is also how Carbon hot keys are registered.
public struct KeyboardShortcut: Hashable, Sendable, Codable {
    public struct Modifiers: OptionSet, Hashable, Sendable, Codable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        public static let control = Modifiers(rawValue: 1 << 0)
        public static let option = Modifiers(rawValue: 1 << 1)
        public static let shift = Modifiers(rawValue: 1 << 2)
        public static let command = Modifiers(rawValue: 1 << 3)

        /// In Apple's display order, with their symbols and names in `settings.json`.
        private static let all: [(Modifiers, symbol: String, name: String, carbon: UInt32, cocoa: UInt)] = [
            (.control, "⌃", "control", 0x1000, 1 << 18),
            (.option, "⌥", "option", 0x800, 1 << 19),
            (.shift, "⇧", "shift", 0x200, 1 << 17),
            (.command, "⌘", "command", 0x100, 1 << 20),
        ]

        /// From Carbon modifier flags (`cmdKey`, `optionKey`, …). Other bits are ignored.
        public init(carbonFlags: UInt32) {
            self = Self(Self.all.filter { carbonFlags & $0.carbon != 0 }.map(\.0))
        }

        /// From `NSEvent.ModifierFlags.rawValue`. Other bits are ignored.
        public init(cocoaFlags: UInt) {
            self = Self(Self.all.filter { cocoaFlags & $0.cocoa != 0 }.map(\.0))
        }

        public var carbonFlags: UInt32 {
            Self.all.filter { contains($0.0) }.reduce(0) { $0 | $1.carbon }
        }

        /// "⌃⌥⇧⌘", only the ones present.
        public var symbols: String {
            Self.all.filter { contains($0.0) }.map(\.symbol).joined()
        }

        public init(from decoder: any Decoder) throws {
            let names = try decoder.singleValueContainer().decode([String].self)
            self = Self(Self.all.filter { names.contains($0.name) }.map(\.0))
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(Self.all.filter { contains($0.0) }.map(\.name).sorted())
        }
    }

    public var keyCode: UInt16
    public var modifiers: Modifiers

    public init(keyCode: UInt16, modifiers: Modifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// A global shortcut needs ⌘, ⌃ or ⌥, so it doesn't swallow ordinary typing. Function keys
    /// are the exception.
    public var hasRequiredModifier: Bool {
        !modifiers.isDisjoint(with: [.command, .control, .option]) || KeyCode.functionKeys.contains(keyCode)
    }

    /// For example "⌃⌥⌘P". `keyName` gives the character the key types in the current keyboard
    /// layout; without it (or if it returns `nil`), the US ANSI layout is assumed. Keys that don't
    /// type a character (F-keys, arrows, Space, …) always use their standard names.
    public func displayString(keyName: (UInt16) -> String? = { _ in nil }) -> String {
        let key = KeyCode.specialNames[keyCode]
            ?? keyName(keyCode).flatMap { $0.allSatisfy(\.isWhitespace) ? nil : $0.uppercased() }
            ?? KeyCode.ansiNames[keyCode]
            ?? "Key \(keyCode)"
        return modifiers.symbols + key
    }
}

/// macOS virtual key codes (`kVK_*` in Carbon's `Events.h`).
enum KeyCode {
    static let functionKeys: Set<UInt16> = Set(functionKeyCodes)

    /// F1 to F20.
    private static let functionKeyCodes: [UInt16] = [
        122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 105, 107, 113, 106, 64, 79, 80, 90,
    ]

    /// Keys whose name doesn't depend on the layout.
    static let specialNames: [UInt16: String] = {
        var names: [UInt16: String] = [
            36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋", 76: "⌤", 117: "⌦",
            115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
            123: "←", 124: "→", 125: "↓", 126: "↑",
        ]
        for (index, code) in functionKeyCodes.enumerated() { names[code] = "F\(index + 1)" }
        return names
    }()

    /// Character keys on the US ANSI layout.
    static let ansiNames: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V", 11: "B",
        12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4",
        22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "O",
        32: "U", 33: "[", 34: "I", 35: "P", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\",
        43: ",", 44: "/", 45: "N", 46: "M", 47: ".", 50: "`",
    ]
}

/// An action with a global shortcut (`spec.md` §4.1).
public enum ShortcutAction: String, Sendable, CaseIterable, Codable {
    case picker
    case contrastChecker
    case mainWindow

    public var release: Release {
        switch self {
        case .picker: .mvp
        case .contrastChecker, .mainWindow: .v2
        }
    }

    /// ⌃⌥⌘P (Hyper+P) for the picker; the others have none until the user assigns one.
    public var defaultShortcut: KeyboardShortcut? {
        switch self {
        case .picker: KeyboardShortcut(keyCode: 35, modifiers: [.control, .option, .command])
        case .contrastChecker, .mainWindow: nil
        }
    }

    /// The actions visible in `release`, in display order.
    public static func visible(for release: Release) -> [ShortcutAction] {
        allCases.filter { $0.release <= release }
    }
}
