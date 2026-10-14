# cs-7f6ead — Settings window and global shortcuts

## What
Fill out the Settings tab of the main window with the §10 panes, persist synced settings in
`settings.json`, and add a global picker shortcut (default ⌃⌥⌘P). Users can re-record or clear it
and get feedback when it conflicts. The shortcut infrastructure already models the V2 contrast
checker and main window shortcuts, which stay hidden until V2.

## Why
`spec.md` §4.1, §10, §11.1. It unblocks the picker (cs-40b6c9), Smart Profiles (cs-615265),
the contrast checker (cs-2544ad) and Smart Formats (cs-523d6a), which all read settings or
register shortcuts.

## Acceptance criteria
- [ ] The Settings tab shows the panes General, Shortcuts and Picker (Profiles and Permissions
      stay hidden until their issues add content; see Resolved question 1). Each pane is gated by `Release` like the popover items.
- [ ] **General**: launch at login (existing), default output format, Quit button.
- [ ] **Shortcuts**: a recorder for the picker shortcut. It shows ⌃⌥⌘P by default. Click it to
      record, press a combination to set it, Esc to cancel, ⌫ to clear. A "Restore default"
      button. Contrast checker and main window rows are hidden in the MVP.
- [ ] Pressing the picker shortcut anywhere, while any app is frontmost, calls the picker hook in
      `AppDelegate` (a no-op until cs-40b6c9; a log line for now).
- [ ] Conflict feedback, shown inline under the recorder, with the old shortcut kept:
      - no ⌘/⌃/⌥ modifier (Shift alone doesn't count; F1–F20 alone are allowed): "Use at least
        one of ⌘, ⌃ or ⌥."
      - already used by another Colorsip shortcut: "Already used by ‹action›."
      - reserved by macOS (enabled system symbolic hotkeys such as ⌘Space, ⌘⇥): "Used by macOS."
      - registration fails because another app holds it: "Another app is using this shortcut."
- [ ] **Picker**: default loupe diameter (120–400 pt, step 20, default 200) and grid size (5–31,
      odd only, default 11). Out-of-range or even values are clamped/rounded when set and when
      loaded.
- [ ] Synced settings live in `settings.json` in the library folder; every change saves it
      atomically. Missing keys fall back to defaults; a missing file means all defaults.
      A corrupt file or a newer `formatVersion` is never overwritten: Colorsip runs on defaults
      for that session and shows a note in General.
- [ ] Machine-local state goes in `UserDefaults` (a `LocalSettings` wrapper); in this issue that
      is only the last selected settings pane.
- [ ] Core tests: settings defaults, round trip, missing keys, clamping, version gating, store
      load/save/no-overwrite; shortcut validation, display strings, `ShortcutManager`
      registration/conflict/re-registration with a fake registrar.

## Flow
1. **Core `Settings.swift`** — `struct AppSettings: Codable, Equatable, Sendable` (not `Settings`,
   which would clash with SwiftUI's `Settings` scene in the app target)
   ```json
   {
     "formatVersion": 1,
     "defaultFormat": "cssHex",
     "shortcuts": { "picker": { "keyCode": 35, "modifiers": ["command", "control", "option"] } },
     "loupe": { "diameter": 200, "gridSize": 11 }
   }
   ```
   A shortcut set to "none" is stored as `null`; an absent key means "default". Custom
   `init(from:)` fills defaults and clamps. `OutputFormat` gains `Codable` (raw value).
   cs-615265 later adds `profiles`.
2. **Core `SettingsStore.swift`** — `@MainActor @Observable final class SettingsStore` around
   `LibraryStore` (`.settings` file). `settings` is observable; `update { $0.x = y }` mutates,
   saves and records `lastError`. `loadIssue: LibraryLoadIssue?` set for a corrupt/newer file,
   which also disables saving.
3. **Core `KeyboardShortcut.swift`** — `struct KeyboardShortcut: Codable, Hashable` (`keyCode:
   UInt16` = macOS virtual key code, `modifiers: Modifiers` OptionSet of command/control/option/
   shift). `displayString(keyName:)` gives "⌃⌥⇧⌘P" in Apple's modifier order; the key name comes
   from a closure (the app uses the current keyboard layout) with a built-in table for
   non-character keys (F-keys, arrows, Space, Return, ⌫, …).
4. **Core `ShortcutAction`** — `picker` (MVP), `contrastChecker`, `mainWindow` (V2), with
   `release`, `defaultShortcut` (picker: ⌃⌥⌘P, others none) and `visible(for:)`.
5. **Core `ShortcutManager`** — `@MainActor @Observable`, owns a `HotKeyRegistrar` protocol
   (`register(_:id:) throws`, `unregister(id:)`, `isReservedBySystem(_:) -> Bool`). It registers
   all visible actions from `SettingsStore`, exposes `validate(_:for:) -> ShortcutProblem?` and
   `set(_:for:) -> ShortcutProblem?`, which unregisters the old one, tries the new one, and on
   failure re-registers the old one and returns the problem. `problems` only describes the
   *current* shortcuts (e.g. "in use by another app" at launch); a rejected attempt is returned
   to the recorder, which shows it. `suspend()` / `resume()` for the
   recorder. A handler `(ShortcutAction) -> Void` is called on press.
6. **App `CarbonHotKeyRegistrar.swift`** — `RegisterEventHotKey` / `UnregisterEventHotKey` with one
   `InstallEventHandler` on the application target; `eventHotKeyExistsErr` maps to "in use".
   `isReservedBySystem` reads `CopySymbolicHotKeys` (enabled entries only).
7. **App `ShortcutRecorder.swift`** — a SwiftUI button-styled field; while recording it suspends
   the manager's hotkeys and captures the next `keyDown` with a local `NSEvent` monitor; it
   resumes on finish, cancel, or losing focus. Key names via `UCKeyTranslate` on the current
   layout.
8. **App `SettingsTab`** — split into `GeneralPane`, `ShortcutsPane`, `PickerPane`, shown as a
   segmented toolbar-style `TabView` inside the Settings tab, driven by a core `SettingsPane`
   enum with `release` gating. `AppModel` gains `settings: SettingsStore` and `shortcuts:
   ShortcutManager`; `outputFormat` becomes a computed pass-through to
   `settings.defaultFormat` (see Resolved question 2). While the main window has a single
   visible tab (the MVP), it shows that tab's content without an outer tab bar, so the Settings
   panes aren't nested under a one-item tab row.
9. **`AppDelegate`** wires the hotkey handler: `.picker` → the same hook the eyedropper uses.

## Decisions
- **Carbon `RegisterEventHotKey`, not a third-party package (KeyboardShortcuts, HotKey)** — no
  dependencies; it needs no Accessibility permission (unlike a CGEvent tap) and reports
  "already registered" for conflict feedback.
- **Shortcuts stored as virtual key code + modifiers**, not characters, so they survive layout
  switches, matching how Carbon registers them. The displayed character follows the current
  layout.
- **Recording pauses global hotkeys** — otherwise pressing the current shortcut while recording
  would fire the picker instead of being captured.
- **A rejected shortcut keeps the previous one**, so the picker never silently ends up without a
  shortcut.
- **No unknown-key preservation in `settings.json`**: an older Colorsip drops keys it doesn't
  know. `formatVersion` is bumped for incompatible changes, which older builds then refuse to
  overwrite. Same as the library files.

## Edge cases
- HIGH — Corrupt or newer `settings.json` (e.g. via sync in V3): never overwritten; defaults for
  the session plus a visible note.
- MEDIUM — Another app grabs ⌃⌥⌘P before Colorsip launches: registration at launch fails; the
  Shortcuts pane shows "Another app is using this shortcut" on the picker row. No alert at launch.
- MEDIUM — The user records the shortcut already assigned to that same action: no-op, no error.
- LOW — Modifier-only presses are ignored while recording; Tab isn't captured (focus moves).
- LOW — `CopySymbolicHotKeys` doesn't list every system/app shortcut (e.g. menu shortcuts of
  other apps). Those can't be detected; we accept that.

## Assumptions
- Settings stays a tab of the single main window (cs-5cda46 decision), not a separate SwiftUI
  `Settings` scene. "Settings window" in the title means that window.
- The quit button in General calls `NSApp.terminate`, like the popover.
- `settings.json` sits in the library folder now and will move with it in V3 sync.

## Resolved questions (user accepted the recommendations)
1. **Profiles and Permissions panes** are not shown yet. This issue adds the `SettingsPane` cases
   (gated off) and the pane container; cs-615265 and cs-0fb394 add the content and un-gate them.
2. **The popover format dropdown and the General "default output format" are one persisted
   value** (`defaultFormat`), so the last choice survives a relaunch.
3. **The loupe size is one persisted value.** Wheel changes in the picker (cs-40b6c9) write back
   to `loupe.diameter`/`gridSize`; the Picker pane edits the same values.
