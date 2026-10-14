# cs-f8f139 — Permissions checklist with live detection

## What was built
The step-by-step permissions guide (cs-0fb394) is replaced by **one checklist window**. It lists
every missing permission at once. Each row shows its own status and has its own "Open System
Settings" button. Grants are detected **live**, so onboarding needs no restart.

## Why
The old guide showed Screen Recording first and waited for it. `CGPreflightScreenCaptureAccess()`
keeps its first answer for the life of the process. So the guide never saw the grant and stayed
stuck on step 1 until the user clicked "Quit & Reopen". Accessibility then came as a second round.
Other onboarders see grants live, so the fix was detection, not a smoother restart.

## How the pieces fit

### Core (`ColorsipCore`, unit-tested)
- `PermissionChecklist` (value type) replaces `PermissionGuide`.
  - `items`: the rows, fixed when the checklist starts, so granted rows stay visible with a ✓
    instead of disappearing.
  - `highlighted`: set by `require(_:)`.
  - `skipped`: rows skipped in this checklist.
- `Permissions`:
  - `checklist` replaces `guide`.
  - `status(of:)` returns `.granted`, `.skipped` or `.missing`. Granted wins over skipped.
  - `isComplete` is true when every row is granted or skipped.
  - `skip(_:)` takes the permission, because any row can be skipped in any order. If every row
    ends up skipped and none was granted, the checklist ends, as before.
  - `startGuide(highlighting:)` and `require` keep their meaning, but now highlight the row
    instead of reordering. Rows never jump around.
  - `refresh()` now only assigns the `granted` set. Statuses are derived, so the checklist never
    has to be mutated on poll. Polling stays quiet when nothing changed. The test
    `refreshWithoutChangesDoesntNotifyObservers` guards this.
- `ScreenRecordingProbe.isGranted(windows:ownPID:)` is a pure function over `WindowListEntry`
  values.

### App
- `SystemPermissionChecker` reports Screen Recording as
  `CGPreflightScreenCaptureAccess() || probe`. The probe reads
  `CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements])` and maps it to
  `WindowListEntry`. Accessibility still uses `AXIsProcessTrusted()`, which was already live.
- `PermissionGuideView` (the file name is kept) renders the rows, the tinted highlight and "You're
  all set".
- `PermissionsCoordinator` observes `checklist`. It keeps the 1 s poll while the window is open,
  plus refreshes on `didBecomeActive`. `relaunch()` and the "Quit & Reopen" button are removed.

## Non-obvious details
- **Why the probe works.** The window server checks Screen Recording on every window-list call. It
  only includes `kCGWindowName` for other apps' windows when Colorsip has the permission. The probe
  never shows a system prompt. While the user is granting, System Settings' own window is on
  screen, so there is always a titled window to see.
- **Probe filters.** It ignores our own windows (always titled), empty titles, and windows outside
  layer 0. The Dock, the menu bar and status items can expose names without the permission.
- The picker doesn't capture pixels yet (cs-40b6c9). That issue should confirm capture works right
  after a live-detected grant.

## Verified by hand
The user reset permissions, granted both in System Settings, and saw each row turn to ✓ live with
no restart.

## Follow-ups
- cs-925b95 (Quit & Reopen doesn't reopen): the button no longer exists, so that issue is likely
  obsolete.
