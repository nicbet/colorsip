# cs-7f6ead walkthrough — Settings window and global shortcuts

## What was built
The Settings tab of the main window now has General, Shortcuts and Picker panes. Synced
settings are persisted in `settings.json` in the library folder. A global picker shortcut
(default ⌃⌥⌘P) works from any app and can be re-recorded, cleared or restored, with inline
conflict feedback. Contrast checker and main window shortcuts are modelled but hidden until V2.

## How the pieces fit

```
AppDelegate
 └─ AppModel
     ├─ SettingsStore ── LibraryStore (.settings → settings.json)       [Core]
     ├─ ShortcutManager ── HotKeyRegistrar (protocol)                   [Core]
     │                       └─ CarbonHotKeyRegistrar (RegisterEventHotKey)  [App]
     ├─ LocalSettings ── UserDefaults (last settings pane)              [Core]
     └─ outputFormat ⇄ settings.defaultFormat (popover dropdown + General)

MainWindowView ── SettingsTab (TabView of SettingsPane.visible)
                   ├─ GeneralPane   launch at login, default format, quit, settings errors
                   ├─ ShortcutsPane ShortcutRecorder per ShortcutManager.actions
                   └─ PickerPane    loupe diameter slider, grid size stepper
```

### Core (`Packages/ColorsipCore`)
- **`KeyboardShortcut.swift`**
  - `KeyboardShortcut` is a virtual key code plus a `Modifiers` option set. It's stored in JSON as
    `{ keyCode, modifiers: ["command", …] }`.
  - `Modifiers` converts to and from Carbon flags (registration, `CopySymbolicHotKeys`) and Cocoa
    flags (`NSEvent` in the recorder). Both conversions are pure and unit-tested.
  - `displayString(keyName:)` renders "⌃⌥⇧⌘P". Non-character keys (F-keys, arrows, Space, …) use
    fixed names; character keys ask the app's layout closure and fall back to US ANSI.
  - `ShortcutAction` (`picker` MVP, `contrastChecker` / `mainWindow` V2) carries the release and
    the default shortcut.
- **`Settings.swift`**
  - `AppSettings` is the `settings.json` model: `defaultFormat`, `shortcuts`, `loupe`.
  - Decoding is lenient per field: a missing or bad value falls back to its default. Only a
    newer `formatVersion` throws (`ColorsipFormatError.newerFormat`).
  - `ShortcutBindings` stores only the shortcuts that differ from the defaults (`null` = cleared).
    Setting an action back to its default removes the override.
  - `LoupeSettings` clamps in `init` and `didSet`: diameter to the nearest 20 pt step in
    120–400, grid size to an odd value in 5–31. Loaded values get the same treatment.
  - `SettingsStore` saves on every real change. If the file was corrupt or from a newer
    version, it keeps running on defaults and **never writes** (`loadIssue`), like the other
    library files.
  - `LocalSettings` holds the machine-local state in UserDefaults (only the last pane so far).
- **`ShortcutManager.swift`** — the rules, independent of Carbon:
  - `validate`: needs ⌘/⌃/⌥ (F-keys exempt), not used by another visible action, not reserved by
    macOS.
  - `set`: validate, unregister the old shortcut, register the new one. If registration fails,
    put the old one back and return `.inUseByAnotherApp`. The setting is only saved on success.
  - `problems` describes the *current* shortcuts only (e.g. another app grabbed ⌃⌥⌘P before
    launch). A rejected attempt is returned to the caller, not stored. Otherwise `resume()`
    after recording would wipe the message the user needs to see.
  - `suspend()`/`resume()`: while suspended, `set` registers only as an availability check and
    unregisters again.
- **`Release.swift`** — `SettingsPane` with release gating plus `hasContent`. Profiles and
  Permissions are MVP panes but stay hidden until cs-615265 / cs-0fb394 flip `hasContent`.
  Formats and Sync are V3.

### App (`Colorsip/`)
- **`CarbonHotKeyRegistrar`**
  - Registers with `RegisterEventHotKey` using `kEventHotKeyExclusive`, which is what makes
    "another app holds it" detectable.
  - One `InstallEventHandler` on the application target maps the hot key ID (signature "CSIP",
    id = action index) back to the action.
  - `isReservedBySystem` reads the enabled entries of `CopySymbolicHotKeys`.
  - `keyName(for:)` uses `UCKeyTranslate` on the current layout for display.
- **`ShortcutRecorder`**
  - Click to record; this suspends the manager and installs a local `keyDown` monitor.
  - Esc cancels and ⌫/⌦ clear. Tab passes through for keyboard navigation.
  - Recording stops when the view disappears or the app resigns active.
  - Shows the last rejection, otherwise `manager.problems[action]`.
- **`SettingsTab.swift`** — the panes. They bind through `settings.update { … }`, so every
  change is saved.
- **`MainWindowView`** — while only one main-window tab is visible (MVP), it renders that tab
  directly, so the Settings panes aren't nested under a one-item tab bar.
- **`AppDelegate`**
  - The `.picker` hot key and the toolbar eyedropper call the same `picker` closure.
  - For now the closure logs "Picker requested" (os_log subsystem
    `com.nicolas-bettenburg.colorsip`, category `picker`); cs-40b6c9 replaces it.

## Key decisions
- **Carbon hot keys, no package** (KeyboardShortcuts/HotKey): no dependency and no Accessibility
  permission, and we get "already registered" errors for conflict feedback. The README no
  longer lists Accessibility for shortcuts.
- **Key code, not character**, so a shortcut stays on the same physical key when the layout
  changes. Only the label follows the layout.
- **One persisted format and one persisted loupe size** (user decision). The popover dropdown
  and General edit `defaultFormat`. The picker's mouse wheel (cs-40b6c9) should write
  `loupe.diameter`/`gridSize`, which the Picker pane shows.
- **A rejected shortcut keeps the previous one**, so the picker never silently loses its
  shortcut.
- **`AppSettings`, not `Settings`**, to avoid clashing with SwiftUI's `Settings` scene.

## Verification
- `swift test`: 216 tests pass, including new suites for keyboard shortcuts, settings
  (defaults, round trip, leniency, clamping, version gating), the store (no overwrite on a
  corrupt or newer file, save errors), local settings, settings panes and `ShortcutManager`
  with a fake registrar.
- Debug build with no warnings.
- Verified by hand by the user (Carbon and event monitors can't be unit-tested):
  - ⌃⌥⌘P from another app logs "Picker requested".
  - The recorder flows work.
  - Settings persist across a relaunch.
- Gotcha found during testing: an old build in `/Applications` doesn't have the shortcut, and
  the frontmost app just beeps. Test the worktree's build.

## Notes for future work
- **cs-40b6c9:**
  - Replace the `picker` closure in `AppDelegate`.
  - Read `model.settings.settings.loupe` and write wheel changes back with `settings.update`.
  - Use `model.outputFormat` for the label.
- **cs-615265:** add `profiles` to `AppSettings` (lenient decode, like the other fields), add the
  pane content, and set `SettingsPane.profiles.hasContent` to true.
- **cs-0fb394:** same for Permissions.
- **V2:** flipping `Release.current` shows the contrast checker and main window shortcut rows.
  Handle them in `AppDelegate`'s `onTrigger` switch.
- `CopySymbolicHotKeys` doesn't see other apps' menu shortcuts. Those can't be detected.
