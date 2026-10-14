# cs-5cda46 — Menubar status item and popover shell

Refines `spec.md` §1 (launch at login), §2 (release gating), §3.1 (menubar popover), §3.2 (main
window, stub only).

## What
The app's first visible surface: a status-bar icon that opens a non-detachable popover with the
toolbar, the format dropdown, an empty palette-list area, and the bottom bar. Settings opens a
stub **main window** on its **Settings tab**. It also adds launch at login through `SMAppService`,
off by default.

## Why
Every later MVP issue (palette list, settings, onboarding, picker) needs this shell to hang off.
Settings lives in the main window (not a separate Settings scene), so the window that later gains
the library, editor and inspector (§3.2) is established now.

## How

### ColorsipCore (unit-tested)
- **`Release`** (`mvp`, `v2`, `v3`, comparable) and `Release.current = .mvp`.
- **`PopoverItem`**: every toolbar and bottom-bar control from §3.1, each tagged with its release:
  - Toolbar: `picker` (MVP), `contrastChecker` (V2), `newPalette` (MVP), `visionSimulation` (V2)
  - Bottom bar: `settings` (MVP), `visionMode` (V2), `openMainWindow` (V2), `quit` (MVP)
  - `PopoverItem.toolbar(for: Release)` and `.bottomBar(for: Release)` return the visible items in
    §3.1 order. Later-release items are left out, never disabled (§2).
- **`MainWindowTab`**: the main window's tabs, each tagged with its release. For now `library`
  (V2, the §3.2 three-pane view) and `settings` (MVP). `MainWindowTab.visible(for:)` returns the
  visible tabs in order, so the MVP window shows only Settings.
- **`OutputFormat`**: the ten formats of §5.3 in table order, each with its display name
  ("CSS Hex", "CSS Hex (no #)", …). `OutputFormat.default = .cssHex`. No formatting logic:
  cs-86d22b adds it.
- **`LaunchAtLogin`**: an `@Observable`, `@MainActor` model over a `LoginItemService` protocol
  (`status`, `register()`, `unregister()`).
  - `isEnabled` reflects the service: on for `.enabled` and `.requiresApproval`.
  - `setEnabled(true/false)` registers/unregisters, then re-reads the status. A thrown error is
    kept in `lastError` and the state re-read from the service, so the toggle never lies.
    A later success clears `lastError`.
  - `refresh()` re-reads the status (changes made in System Settings).
  - `requiresApproval` is exposed so the UI can say "Allow Colorsip in System Settings → Login Items".
  - Nothing is registered at launch, so it's off by default.

### App target (thin, verified by hand)
- **`AppModel`** (`@Observable`): shared state for popover and main window: `launchAtLogin`,
  `outputFormat` (in memory), `mainWindowTab`. Owned by the `AppDelegate`.
- **`StatusItemController`** (AppKit): `NSStatusItem` with a template SF Symbol
  (`eyedropper.halffull`), toggles an `NSPopover` (`.transient`, `animates`), activating the app
  first so the transient popover closes on outside clicks. The popover delegate's
  `popoverShouldDetach` returns `false`. Actions that open UI (picker, settings) close the popover
  first.
- **`SMAppServiceLoginItem`**: `LoginItemService` adapter over `SMAppService.mainApp`.
- **`PopoverView`** (SwiftUI, 320×420pt), top to bottom:
  1. Toolbar from `PopoverItem.toolbar(for: .current)`, icon buttons with tooltips.
  2. Format dropdown: a `Menu` with a custom label, full width, **28pt tall**, rounded rectangle
     (quiet fill and hairline stroke), the format name on the left and a small secondary
     `chevron.down` on the right (no system up/down accent indicator). Its content is an inline
     `Picker` over `OutputFormat.allCases` bound to `AppModel.outputFormat`, so the selected
     format gets a checkmark.
  3. Palette-list placeholder: an empty, flexible area (cs-a29255 fills it).
  4. Bottom bar from `PopoverItem.bottomBar(for: .current)`, Quit pushed to the trailing edge.
- **Main window**: `MainWindowController` owns a single AppKit `NSWindow` hosting the SwiftUI
  `MainWindowView`, created lazily and kept (`isReleasedWhenClosed = false`), so it is never open
  at launch and reopening reuses it. `show(tab)` sets `AppModel.mainWindowTab`, activates the app
  and brings the window forward. `MainWindowView` is a `TabView` over
  `MainWindowTab.visible(for: .current)` bound to `mainWindowTab`.
  The Settings tab is a stub General section with only the "Launch at login" toggle bound to
  `LaunchAtLogin`, the approval hint and any error; it refreshes the status on appear.
  cs-7f6ead fills the Settings tab out.
- **Actions**: Quit → `NSApp.terminate`. Settings → `MainWindowController.show(.settings)`.
  Picker and New palette → no-op hooks until cs-40b6c9 / cs-d6bd2c.
- The SwiftUI `App` keeps an empty `Settings` scene only because it needs one scene; all UI is
  driven from the `AppDelegate`.

## Acceptance criteria
- [ ] Launching shows a status-bar icon, no Dock icon and no window; clicking the icon toggles the popover.
- [ ] Clicking outside closes the popover; it can't be dragged off into a window.
- [ ] Toolbar shows only Picker and New palette; bottom bar only Settings and Quit (no disabled V2 controls).
- [ ] Format dropdown lists the ten §5.3 formats, CSS Hex selected (checkmarked); it is 28pt tall,
      rounded, with a subtle chevron.
- [ ] Settings opens the main window in front, on the Settings tab, with a Launch at login toggle
      that is off on a fresh install. Clicking Settings again reuses the same window.
- [ ] Toggling it registers/unregisters the login item (visible in System Settings → Login Items).
- [ ] Quit terminates the app.
- [ ] Core tests cover release gating (popover items and main window tabs), format catalogue
      order/names/default, and `LaunchAtLogin` (default off, enable, disable, requiresApproval,
      error leaves state consistent).

## Out of scope
Palette list (cs-a29255), formatting (cs-86d22b), persisting the default format and the full
Settings content (cs-7f6ead), picker (cs-40b6c9), new-palette behavior (cs-d6bd2c), the V2
library tab.

## Decisions
1. Settings opens the main window on a Settings tab (user decision); no separate Settings window.
2. Picker and New palette are visible but no-ops until their issues land (user approved).
3. Format selection is in memory only; cs-7f6ead persists it as the default format (user approved).
4. Status icon is the SF Symbol `eyedropper.halffull` as a placeholder (user approved).
5. The main window is an AppKit `NSWindow` hosting SwiftUI, not a SwiftUI `Window` scene: the
   popover lives outside SwiftUI's scene graph, where `openWindow` isn't reliably available, and an
   agent app needs explicit activation and ordering anyway. Revisit if a SwiftUI scene is needed
   for scene-level features (e.g. window toolbars via `.toolbar` work in hosted views too).
6. The format dropdown is a custom-styled `Menu` (28pt, rounded, subtle chevron) instead of the
   stock menu-style `Picker`, whose size and blue up/down indicator looked squished and loud
   (review feedback).
