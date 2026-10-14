# cs-0fb394 — Permissions onboarding (Screen Recording, Accessibility)

## What
Check Colorsip's two macOS permissions at launch and when a feature needs one. If any are
missing, an onboarding window walks the user through them one at a time. Settings gets a
Permissions pane that shows each permission's status and a button that starts the guide again.

## Why
`spec.md` §9, §10, §4.5. The picker (cs-40b6c9) needs Screen Recording and Cmd+click paste needs
Accessibility. Without a guide, users have to find the right System Settings pane themselves.

## Acceptance criteria
- [ ] At launch, the guide opens if Screen Recording is missing, or if Accessibility is missing
      and the user hasn't skipped it before.
- [ ] Starting the picker (toolbar eyedropper or shortcut) without Screen Recording opens the
      guide on that step instead of the picker.
- [ ] `PermissionsCoordinator.require(_:)` gives cs-40b6c9 a hook for Cmd+click paste: it checks
      Accessibility and opens the guide on that step if it's missing (the value is still copied).
- [ ] The guide shows only the missing permissions, one step at a time, in a fixed order: Screen
      Recording, then Accessibility. A feature that requires a permission puts that step
      first. Each step shows what the permission is for, an "Open System Settings" button, and a
      "Waiting for permission…" indicator.
- [ ] "Open System Settings" registers Colorsip with the system first (so it appears in the
      list) and then opens the right pane (`Privacy_ScreenCapture` / `Privacy_Accessibility`).
- [ ] While the guide is open, the status is polled every second. When the current permission
      is granted, the guide moves on to the next step by itself.
- [ ] The Accessibility step has a "Skip" button; Screen Recording has none. Closing the window
      is allowed at any step, but it doesn't count as skipping.
- [ ] After the last step, a "You're all set" step with a Done button closes the window. (If
      every step was skipped, the window just closes.)
- [ ] The Screen Recording step offers "Quit & Reopen", because macOS may only report the grant
      after a relaunch (see Decisions). After the relaunch, the launch check moves on.
- [ ] Settings ▸ Permissions shows each permission with Granted / Not granted and its purpose,
      and a "Start Guide Again" button (shown while something is missing). That guide includes
      skipped steps. The status refreshes when the pane appears and when the app becomes active.
- [ ] Core tests cover the guide's state machine, launch logic, skip memory and pane gating.
- [ ] Manual check (TCC can't be tested automatically): a fresh grant in System Settings advances
      the guide; skipping Accessibility doesn't bring it back at the next launch.

## Flow
1. **Core `Permissions.swift`**
   - `enum Permission: String, CaseIterable, Sendable { case screenRecording, accessibility }`
     in guide order, with `isSkippable` (Accessibility only).
   - `@MainActor protocol PermissionChecker: AnyObject { func isGranted(_:) -> Bool }`. The app
     adapts `CGPreflightScreenCaptureAccess` and `AXIsProcessTrusted`. Tests use a fake.
   - `struct PermissionGuide: Equatable`: the walk. `pending` (ordered), `total`,
     `step: Step` (`.permission(P)` or `.done`), and `stepNumber` (1-based).
   - `@MainActor @Observable final class Permissions(checker:localSettings:)`:
     `isGranted(_:)`, `missing`, `guide: PermissionGuide?`, and these methods:
     - `refresh()` re-checks, drops granted steps from the guide, and forgets skips of
       permissions that are now granted.
     - `checkAtLaunch()` starts a guide for the missing permissions minus the remembered skips.
     - `startGuide(first:)` starts a guide for every missing permission, optionally putting one
       first. It returns `false` if nothing is missing.
     - `require(_:) -> Bool` returns `true` if granted. Otherwise it starts the guide with that
       permission first and returns `false`.
     - `skip()` works only on a skippable step. It remembers the skip and moves on. If nothing
       is left, the guide ends (`nil`).
     - `closeGuide()`.
   - `LocalSettings.skippedPermissions: Set<Permission>` in UserDefaults (it's machine-local).
   - `SettingsPane.permissions` gets content (`hasContent` true).
2. **App `SystemPermissionChecker.swift`**: the checker, plus `register(_:)`
   (`CGRequestScreenCaptureAccess()` / `AXIsProcessTrustedWithOptions(prompt: true)`) and
   `openSettings(for:)` (`x-apple.systempreferences:com.apple.preference.security?Privacy_…`).
3. **App `PermissionsCoordinator.swift`**: owns the guide window (`NSWindow` + SwiftUI, same as
   `MainWindowController`) and syncs it with `permissions.guide`. It runs a 1 s `Timer` while the
   window is open and treats closing the window as `closeGuide()`. It also refreshes on
   `NSApplication.didBecomeActiveNotification`.
4. **App `PermissionGuideView.swift`**: the step view (SF Symbol, title, explanation, buttons,
   "Step 1 of 2").
5. **App `SettingsTab.swift`**: `PermissionsPane`.
6. **`AppDelegate`**: `checkAtLaunch()` after launch. The picker hook returns early unless
   `require(.screenRecording)` passes.

## Decisions
- **Polling, not notifications.** macOS posts nothing when TCC changes. A 1 s timer runs only
  while the guide is open. Settings refreshes on appear and when the app becomes active.
- **Register before opening System Settings.** Calling `CGRequestScreenCaptureAccess` /
  `AXIsProcessTrustedWithOptions` adds Colorsip to the list, so the user only flips a switch. The
  system prompt they may show is acceptable. We trigger them from the button, not at launch, so
  the guide explains first.
- **Screen Recording may need a relaunch.** `CGPreflightScreenCaptureAccess` can keep returning
  `false` in the running process after the grant, and System Settings itself offers "Quit &
  Reopen". We poll anyway, in case it does update live, and show "Quit & Reopen" as a fallback.
  It relaunches through `NSWorkspace.openApplication` with a new instance, then terminates.
- **Skipping Accessibility is remembered** (UserDefaults), so the launch check doesn't nag.
  Closing the window isn't a skip. Starting the guide from Settings or from Cmd+click paste
  includes the step again.
- **The guide is its own window**, not a main-window tab, so it can open at launch on its own. It
  floats above System Settings (`.floating` level), so the user can see it while flipping
  switches.
- **The guide is a value type in Core.** `Permissions` owns it, so the whole state machine
  (launch, require, skip, advance) is unit-tested. The app only mirrors it in a window.

## Out of scope
- The picker and Cmd+click paste themselves (cs-40b6c9). This issue only provides the checks they
  call.

## Resolved questions (the user accepted the recommendations)
1. The guide window floats above System Settings.
2. The Screen Recording step has a "Quit & Reopen" fallback.
3. The Accessibility skip is remembered across launches.
