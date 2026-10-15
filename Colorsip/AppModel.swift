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

    /// Sends a pick to Color History, the pick target and the clipboard (`spec.md` §4.5).
    func didPick(_ color: CSipColor) {
        routePick(color, format: outputFormat, history: history, library: library, clipboard: clipboard)
    }

    /// Creates a palette and opens its Rename popover.
    func newPalette() {
        edit = .renamePalette(library.newPalette())
    }

    // MARK: - Drag and drop (`spec.md` §7.5)

    /// The swatch being dragged in the popover. The drag's pasteboard only carries the value for
    /// other apps, and SwiftUI's drop targets can't read it back anyway, so drop targets in the
    /// popover learn what is dragged from here. It's cleared when the drag session ends, so a
    /// cancelled drag can't be mistaken for a later drag from another app, and when the popover
    /// closes.
    var drag: SwatchDragSource?
    /// The swatch a refused duplicate drop points at, ringed for about a second (`spec.md` §7.2).
    var highlightedSwatch: Swatch.ID?

    /// Drops the current drag into `slot` of `destination`.
    func dropDrag(onto destination: SectionID, at slot: Int, option: Bool) {
        defer { drag = nil }
        guard let drag else { return }
        if case .duplicate(let existing) = library.dropSwatch(drag, onto: destination, at: slot, option: option) {
            highlight(existing)
        }
    }

    private func highlight(_ swatch: Swatch.ID) {
        highlightedSwatch = swatch
        Task {
            try? await Task.sleep(for: .seconds(1))
            if highlightedSwatch == swatch { highlightedSwatch = nil }
        }
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
