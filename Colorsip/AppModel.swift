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
    /// The color editor's model switcher choice, remembered on this Mac.
    var editorModel: EditorModel {
        didSet { localSettings.editorModel = editorModel }
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
        editorModel = localSettings.editorModel
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

    // MARK: - Color editor (`spec.md` §5.4)

    /// The color editor, while it's open in the popover.
    var colorEditor: ColorEditorSession?
    /// Whether the editor's eyedropper is picking. Closing the popover keeps the editor meanwhile.
    private(set) var isRepicking = false

    func openEditor(_ swatch: Swatch, in section: SectionID) {
        edit = nil
        colorEditor = ColorEditorSession(editor: ColorEditor(swatch: swatch), section: section)
    }

    /// Saves the draft as one undoable step and closes the editor. A color the section already has
    /// keeps the editor open and names the swatch that has it.
    func saveEditor() {
        guard let session = colorEditor else { return }
        switch library.save(session.editor, in: session.section) {
        case .changed, .unchanged, .failed:
            colorEditor = nil
        case .duplicate(let existing):
            let swatches = library.library.palette(session.section.palette)?.swatches(in: session.section.group)
            colorEditor?.duplicateName = swatches?.first { $0.id == existing }?.name ?? ""
        }
    }

    /// Closes the editor without saving, unless its eyedropper is picking.
    func discardEditor() {
        guard !isRepicking else { return }
        colorEditor = nil
    }

    func startRepick() {
        isRepicking = true
    }

    /// Ends the eyedropper's pick: `color` replaces the draft's color, or `nil` if it was cancelled.
    func endRepick(_ color: CSipColor?) {
        isRepicking = false
        if let color { colorEditor?.editor.setPicked(color) }
    }

    /// Closes the editor if its swatch is gone, for example after an undo.
    func closeEditorIfSwatchIsGone() {
        guard let session = colorEditor else { return }
        let swatches = library.library.palette(session.section.palette)?.swatches(in: session.section.group)
        if swatches?.contains(where: { $0.id == session.editor.original.id }) != true { colorEditor = nil }
    }

    private func highlight(_ swatch: Swatch.ID) {
        highlightedSwatch = swatch
        Task {
            try? await Task.sleep(for: .seconds(1))
            if highlightedSwatch == swatch { highlightedSwatch = nil }
        }
    }
}

/// The color editor's draft and the section of the swatch it edits.
struct ColorEditorSession {
    var editor: ColorEditor
    let section: SectionID
    /// The name of the swatch that already has the color, after Done was refused.
    var duplicateName: String?
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
