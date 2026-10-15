/// A release from the roadmap (`spec.md` §2). UI that belongs to a later release than `current`
/// is hidden, never shown disabled.
public enum Release: Int, Comparable, Sendable, CaseIterable {
    case mvp, v2, v3

    public static let current: Release = .mvp

    public static func < (lhs: Release, rhs: Release) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// A control in the menubar popover's toolbar or bottom bar (`spec.md` §3.1).
public enum PopoverItem: Sendable, CaseIterable {
    // Toolbar
    case picker, contrastChecker, newPalette, visionSimulation
    // Bottom bar
    case settings, visionMode, openMainWindow, quit

    public var release: Release {
        switch self {
        case .picker, .newPalette, .settings, .quit: .mvp
        case .contrastChecker, .visionSimulation, .visionMode, .openMainWindow: .v2
        }
    }

    /// The toolbar controls visible in `release`, in display order.
    public static func toolbar(for release: Release) -> [PopoverItem] {
        [.picker, .contrastChecker, .newPalette, .visionSimulation].filter { $0.release <= release }
    }

    /// The bottom-bar controls visible in `release`, in display order.
    public static func bottomBar(for release: Release) -> [PopoverItem] {
        [.settings, .visionMode, .openMainWindow, .quit].filter { $0.release <= release }
    }
}

/// A tab of the main window (`spec.md` §3.2).
public enum MainWindowTab: Sendable, CaseIterable {
    /// The three-pane palette library.
    case library
    case settings

    public var release: Release {
        switch self {
        case .library: .v2
        case .settings: .mvp
        }
    }

    /// The tabs visible in `release`, in display order.
    public static func visible(for release: Release) -> [MainWindowTab] {
        allCases.filter { $0.release <= release }
    }
}

/// A pane of the Settings tab (`spec.md` §10).
public enum SettingsPane: String, Sendable, CaseIterable {
    case general, shortcuts, picker, profiles, permissions, formats, sync

    public var release: Release {
        switch self {
        case .general, .shortcuts, .picker, .profiles, .permissions: .mvp
        case .formats, .sync: .v3
        }
    }

    /// The panes visible in `release`, in display order.
    public static func visible(for release: Release) -> [SettingsPane] {
        allCases.filter { $0.release <= release }
    }
}
