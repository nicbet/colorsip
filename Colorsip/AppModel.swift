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
    let history: ColorHistoryController
    @ObservationIgnored private let clipboard = SystemClipboard()
    /// Opens the permissions guide on every missing permission; set by `AppDelegate`.
    @ObservationIgnored var startPermissionsGuide: @MainActor () -> Void = {}
    var mainWindowTab: MainWindowTab = .settings
    /// The palette, group or swatch edit shown in the popover, if any.
    var edit: LibraryEdit?
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
        history = ColorHistoryController(store: libraryStore)
        self.localSettings = localSettings
        let pane = localSettings.settingsPane
        settingsPane = SettingsPane.visible(for: .current).contains(pane) ? pane : .general
    }

    /// Copies `color` in `format`, or in the active format.
    func copy(_ color: CSipColor, as format: OutputFormat? = nil) {
        copyValue(of: color, as: format ?? outputFormat, to: clipboard)
    }

    /// Adds a pick to Color History under its friendly name.
    func recordPick(_ color: CSipColor) {
        history.record(color, name: color.friendlyName)
    }

    /// Creates a palette and opens its Rename popover.
    func newPalette() {
        edit = .renamePalette(library.newPalette())
    }
}

/// An edit in progress in the popover: the small popover anchored to a palette row shows it.
enum LibraryEdit: Hashable, Identifiable {
    case renamePalette(Palette.ID)
    case editDescription(Palette.ID)
    case setIcon(Palette.ID)
    case confirmDeletePalette(Palette.ID)
    case renameGroup(SwatchGroup.ID, in: Palette.ID)
    case deleteGroup(SwatchGroup.ID, in: Palette.ID)
    case renameSwatch(Swatch.ID, in: SectionID)

    var id: Self { self }

    /// The palette whose row the edit is anchored to.
    var palette: Palette.ID {
        switch self {
        case .renamePalette(let p), .editDescription(let p), .setIcon(let p), .confirmDeletePalette(let p),
             .renameGroup(_, let p), .deleteGroup(_, let p):
            p
        case .renameSwatch(_, let section):
            section.palette
        }
    }
}
