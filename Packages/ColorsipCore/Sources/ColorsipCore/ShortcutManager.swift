import Observation

/// Why a shortcut can't be used.
public enum ShortcutProblem: Equatable, Sendable {
    /// It has none of ⌘, ⌃ or ⌥ and isn't a function key.
    case needsModifier
    /// Another Colorsip action already has it.
    case usedBy(ShortcutAction)
    /// macOS reserves it (an enabled system shortcut such as ⌘Space).
    case reservedBySystem
    /// Registering it failed because another app holds it.
    case inUseByAnotherApp
}

/// The system service that registers global hot keys. The app adapts Carbon's
/// `RegisterEventHotKey`; tests use a fake.
@MainActor
public protocol HotKeyRegistrar: AnyObject {
    /// Called when a registered shortcut is pressed.
    var onPress: ((ShortcutAction) -> Void)? { get set }
    /// Registers `shortcut` for `action`. Returns `false` if another app holds it.
    func register(_ shortcut: KeyboardShortcut, for action: ShortcutAction) -> Bool
    /// Unregisters `action`'s shortcut, if any.
    func unregister(_ action: ShortcutAction)
    func isReservedBySystem(_ shortcut: KeyboardShortcut) -> Bool
}

/// Registers the global shortcuts from the settings (`spec.md` §4.1) and changes them. A
/// shortcut that is rejected for any reason leaves the previous one in place.
@MainActor
@Observable
public final class ShortcutManager {
    /// Actions whose current shortcut couldn't be registered.
    public private(set) var problems: [ShortcutAction: ShortcutProblem] = [:]
    /// Called when the shortcut of `action` is pressed.
    @ObservationIgnored public var onTrigger: ((ShortcutAction) -> Void)?
    public private(set) var isSuspended = false

    private let settings: SettingsStore
    private let registrar: any HotKeyRegistrar
    private let release: Release

    public init(settings: SettingsStore, registrar: any HotKeyRegistrar, release: Release = .current) {
        self.settings = settings
        self.registrar = registrar
        self.release = release
        registrar.onPress = { [weak self] action in self?.onTrigger?(action) }
        registerAll()
    }

    /// The actions that have a shortcut in this release, in display order.
    public var actions: [ShortcutAction] {
        ShortcutAction.visible(for: release)
    }

    public func shortcut(for action: ShortcutAction) -> KeyboardShortcut? {
        settings.settings.shortcuts[action]
    }

    /// Checks `shortcut` for `action` without registering it. Doesn't detect other apps' hot keys;
    /// only `set` can.
    public func validate(_ shortcut: KeyboardShortcut, for action: ShortcutAction) -> ShortcutProblem? {
        if !shortcut.hasRequiredModifier { return .needsModifier }
        if let other = actions.first(where: { $0 != action && self.shortcut(for: $0) == shortcut }) {
            return .usedBy(other)
        }
        if registrar.isReservedBySystem(shortcut) { return .reservedBySystem }
        return nil
    }

    /// Sets `action`'s shortcut, or clears it with `nil`, and saves it. Returns the problem if
    /// `shortcut` was rejected; the previous shortcut then stays.
    @discardableResult
    public func set(_ shortcut: KeyboardShortcut?, for action: ShortcutAction) -> ShortcutProblem? {
        if let shortcut {
            if let problem = validate(shortcut, for: action) { return problem }
            let previous = self.shortcut(for: action)
            registrar.unregister(action)
            guard registrar.register(shortcut, for: action) else {
                if !isSuspended, let previous, !registrar.register(previous, for: action) {
                    problems[action] = .inUseByAnotherApp
                }
                return .inUseByAnotherApp
            }
            // While suspended, registering was only a check.
            if isSuspended { registrar.unregister(action) }
        } else {
            registrar.unregister(action)
        }
        settings.update { $0.shortcuts[action] = shortcut }
        problems[action] = nil
        return nil
    }

    @discardableResult
    public func restoreDefault(for action: ShortcutAction) -> ShortcutProblem? {
        set(action.defaultShortcut, for: action)
    }

    /// Unregisters every shortcut, so a shortcut recorder can capture them as ordinary key presses.
    public func suspend() {
        guard !isSuspended else { return }
        isSuspended = true
        actions.forEach(registrar.unregister)
    }

    /// Registers the shortcuts again after `suspend()`.
    public func resume() {
        guard isSuspended else { return }
        isSuspended = false
        registerAll()
    }

    private func registerAll() {
        for action in actions {
            guard let shortcut = shortcut(for: action) else { continue }
            problems[action] = registrar.register(shortcut, for: action) ? nil : .inUseByAnotherApp
        }
    }
}
