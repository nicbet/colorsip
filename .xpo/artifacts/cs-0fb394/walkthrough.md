# cs-0fb394 — Permissions onboarding walkthrough

## What was built
A guide that walks the user through Colorsip's two macOS permissions (`spec.md` §9):
- **Screen Recording**, required by the picker.
- **Accessibility**, which is optional and only needed for Cmd+click paste.

The guide opens at launch, and when a feature needs a permission that is missing.
Settings ▸ Permissions shows each permission's status and can start the guide again.

## How the pieces fit

### Core (`Permissions.swift`, unit-tested)
- `Permission`: the two cases in guide order, with `isSkippable` (Accessibility only).
- `PermissionChecker`: a protocol for reading TCC status. The app adapts the system APIs, and
  tests use `FakePermissionChecker`.
- `PermissionGuide`: a **value type** for the guide's progress.
  - `pending` holds the permissions still to go, the current one first.
  - `total` is the number of steps the guide started with.
  - `step` is derived: `.permission(first)`, or `.done` when nothing is pending.
  - `stepNumber` is derived as `total - pending.count + 1`.
- `Permissions`: an `@Observable` model that owns the cached status and the `guide?`. Every
  transition lives here:
  - `checkAtLaunch()`: missing permissions minus the remembered skips.
  - `startGuide(first:)`: every missing permission, skips included. A feature can put its
    permission first.
  - `require(_:)`: re-checks. If the permission is missing, it starts the guide on it and
    returns `false`.
  - `refresh()`: re-checks, drops granted steps from the guide, and forgets skips of
    permissions that are now granted.
  - `skip()`: only on a skippable step. It writes `LocalSettings.skippedPermissions`. If the
    skipped step was the guide's only one, the guide ends with no "all set" step.
  - `closeGuide()`: not a skip, so the next launch asks again.
- `LocalSettings.skippedPermissions` is kept in UserDefaults because TCC grants are per machine.
  Unknown raw values are ignored.
- `SettingsPane.permissions` is now visible.

### App
- `SystemPermissionChecker`:
  - reads status with `CGPreflightScreenCaptureAccess` and `AXIsProcessTrusted`
  - `register(_:)` calls `CGRequestScreenCaptureAccess` and `AXIsProcessTrustedWithOptions`
    with the prompt option, so Colorsip appears in System Settings' list
  - `openSettings(for:)` opens the `Privacy_ScreenCapture` / `Privacy_Accessibility` URL
- `PermissionsCoordinator`: the window side.
  - It watches `permissions.guide` with a re-arming `withObservationTracking`. It shows the
    window when a guide starts and closes it when the guide ends.
  - Closing the window by hand calls `closeGuide()`.
  - While the window is open, a 1 s timer calls `refresh()`. It also refreshes on
    `didBecomeActiveNotification`.
  - The window is `.floating`, so it stays visible above System Settings.
- `PermissionGuideView`: the step UI and the "You're all set" step. `Permission` gets `title`,
  `explanation` and `systemImage` there, and Settings reuses them.
- `PermissionsPane` in `SettingsTab.swift`: the status rows and "Start Guide Again". The button
  calls `AppModel.startPermissionsGuide`, which `AppDelegate` sets to go through the coordinator.
- `AppDelegate` runs `checkAtLaunch()`. The picker hook starts with
  `guard permissionsGuide.require(.screenRecording)`. cs-40b6c9 should do the same with
  `.accessibility` for Cmd+click paste.

## Non-obvious details
- **Polling must stay quiet.** `refresh()` runs every second, and the coordinator reacts to every
  change notification on `guide`. Reacting means raising the window and activating the app. With
  `@Observable`, assigning an equal `Set` doesn't notify, but mutating an optional in place
  (`guide?.pending.removeAll`) always does. So `refresh()` only writes `guide` when a pending
  step was actually granted. The test `refreshWithoutChangesDoesntNotifyObservers` guards this.
  It failed when the guard was removed.
- **Screen Recording may need a relaunch.** The running process might not see the grant. "Quit &
  Reopen" starts `/bin/sh` to wait until our PID exits and then `open` the bundle. A new instance
  started right away would compete with the old one for the status item and the Carbon hot keys.
- **Registering comes from the button, not from launch**, so the guide explains why before any
  system prompt appears.
- The explanation names the macOS 15 list entry ("Screen & System Audio Recording") so users find
  it in System Settings.
