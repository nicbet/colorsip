# cs-5cda46 walkthrough — Menubar status item and popover shell

## What was built
Colorsip's first visible UI: a menubar icon that opens a popover (toolbar, format dropdown, empty
palette-list area, bottom bar), and a stub main window whose only tab is Settings, holding the
"Launch at login" toggle.

## How the pieces fit

```
AppDelegate ── owns ── AppModel (@Observable: launchAtLogin, outputFormat, mainWindowTab)
   ├── StatusItemController ── NSStatusItem + NSPopover ── PopoverView (SwiftUI)
   └── MainWindowController ── NSWindow ── MainWindowView (TabView) ── SettingsTab
```

- **ColorsipCore** holds everything that has rules, so it's unit-tested:
  - `Release.swift`: `Release` (`mvp < v2 < v3`, `current = .mvp`) plus `PopoverItem` and
    `MainWindowTab`, each tagged with the release it belongs to. `toolbar(for:)`,
    `bottomBar(for:)` and `visible(for:)` filter by release. This is how §2's "later-release UI is
    hidden, never disabled" is enforced: views iterate these lists instead of hard-coding buttons.
    Shipping V2 means flipping `Release.current`, and the controls appear in spec order.
  - `OutputFormat.swift`: the §5.3 catalogue (order, display names, default CSS Hex). Formatting
    itself is cs-86d22b.
  - `LaunchAtLogin.swift`: wraps a `LoginItemService` protocol. Its state is always re-read
    from the service after register/unregister, even after an error, so the toggle reflects the
    system rather than the user's intent. `requiresApproval` counts as enabled (registered, waiting
    for the user in System Settings) and drives a hint in the UI.
- **App target** stays thin:
  - `SMAppServiceLoginItem` adapts `SMAppService.mainApp` to the protocol.
  - `StatusItemController` toggles a `.transient` popover. It calls `NSApp.activate()` before
    showing it: an agent app that isn't active doesn't get the outside-click dismissal.
    `popoverShouldDetach` returns `false` (§3.1). Actions that open other UI close the popover first.
  - `PopoverView` renders the gated items. The format dropdown is a `Menu` with a custom
    28pt rounded label and a small secondary chevron; inside it an inline `Picker` gives the
    checkmark on the active format.
  - `MainWindowController.show(_:)` sets the tab, activates the app and brings forward a single
    lazily-created window (`isReleasedWhenClosed = false`, so it's reused).

## Key decisions
- **Settings lives in the main window** (user decision), not a SwiftUI `Settings` scene, so the
  window that grows into the §3.2 library already exists. The `Settings { EmptyView() }` scene in
  `ColorsipApp` remains only because a SwiftUI `App` needs one scene.
- **AppKit `NSWindow` instead of a SwiftUI `Window` scene**: the popover sits outside SwiftUI's
  scene graph, where `openWindow` isn't reliably available, and an agent app needs explicit
  activation/ordering anyway.
- **Format selection is in memory**; cs-7f6ead will persist it as the default format.
- **Picker / New palette buttons are no-op hooks** in `AppDelegate` until cs-40b6c9 / cs-d6bd2c.
- **Custom format dropdown** (review feedback): the stock menu picker looked squished and its blue
  up/down indicator was too loud.

## Verification
- `swift test`: 57 tests, including new release-gating, format-catalogue and launch-at-login
  suites (fake `LoginItemService`).
- Status item, popover, window and SMAppService behavior were verified by hand by the user
  (not automatable).

## Notes for future work
- cs-a29255 replaces the `Color.clear` placeholder in `PopoverView` with the palette list.
- cs-7f6ead expands `SettingsTab`; reuse `MainWindowController.show(.settings)` for any
  "open settings" entry point (e.g. permissions onboarding).
- A Debug build's login item points at the build location; test launch at login with care.
