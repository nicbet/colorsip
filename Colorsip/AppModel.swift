import ColorsipCore
import Observation

/// State shared by the popover and the main window.
@MainActor
@Observable
final class AppModel {
    let launchAtLogin: LaunchAtLogin
    let settings: SettingsStore
    let shortcuts: ShortcutManager
    let permissions: Permissions
    let library: LibraryController
    @ObservationIgnored private let clipboard = SystemClipboard()
    /// Opens the permissions guide on every missing permission; set by `AppDelegate`.
    @ObservationIgnored var startPermissionsGuide: @MainActor () -> Void = {}
    var mainWindowTab: MainWindowTab = .settings
    var settingsPane: SettingsPane {
        didSet { localSettings.settingsPane = settingsPane }
    }

    @ObservationIgnored private let localSettings: LocalSettings

    /// The format dropdown and Settings ▸ General share this one persisted value.
    var outputFormat: OutputFormat {
        get { settings.settings.defaultFormat }
        set { settings.update { $0.defaultFormat = newValue } }
    }

    init(
        loginItemService: any LoginItemService,
        hotKeyRegistrar: any HotKeyRegistrar,
        permissionChecker: any PermissionChecker,
        libraryStore: LibraryStore = LibraryStore(folder: LibraryStore.defaultFolder),
        localSettings: LocalSettings = LocalSettings()
    ) {
        launchAtLogin = LaunchAtLogin(service: loginItemService)
        settings = SettingsStore(store: libraryStore)
        shortcuts = ShortcutManager(settings: settings, registrar: hotKeyRegistrar)
        permissions = Permissions(checker: permissionChecker, localSettings: localSettings)
        library = LibraryController(store: libraryStore)
        self.localSettings = localSettings
        let pane = localSettings.settingsPane
        settingsPane = SettingsPane.visible(for: .current).contains(pane) ? pane : .general
    }

    /// Copies `color` in `format`, or in the active format.
    func copy(_ color: CSipColor, as format: OutputFormat? = nil) {
        copyValue(of: color, as: format ?? outputFormat, to: clipboard)
    }

    /// Makes `palette` the pick target. The radio button is only shown on unlocked palettes, so this
    /// doesn't fail in practice; if it does, nothing changes.
    func setPickTarget(_ palette: Palette.ID) {
        try? library.perform("Set Pick Target") { library throws(LibraryError) in try library.setPickTarget(palette) }
    }
}
