# cs-f8f139 — Permissions onboarding as one checklist, with live detection

## What
Replace the step-by-step permissions guide (cs-0fb394) with one checklist window that lists every
missing permission at once. Each row has its own live status and "Open System Settings" button.
Grants show up live, so the normal flow needs **no restart**.

## Why
Today the guide shows Screen Recording first and waits for it. `CGPreflightScreenCaptureAccess()`
caches its answer for the life of the process, so the grant is never seen and the guide is stuck
on step 1 until a restart. Accessibility then comes as a second round. Other onboarders see both
grants live; Colorsip must too.

## Live detection (`SystemPermissionChecker`)
- **Accessibility**: `AXIsProcessTrusted()`, which already updates live. Polled every second.
- **Screen Recording**: `CGPreflightScreenCaptureAccess()` **or** a live probe:
  `CGWindowListCopyWindowInfo(.optionOnScreenOnly)` contains a window owned by another process
  (not Colorsip, not the Dock) that has a `kCGWindowName`. The window server only exposes other
  apps' window titles with Screen Recording access, and checks this per call. The probe never shows
  a system prompt.
- To verify by hand: the picker can actually capture after a live-detected grant without a
  restart. If it can't, "Quit & Reopen" stays as the fallback below.

## Flow
1. At launch, `checkAtLaunch()` lists the missing permissions the user hasn't skipped before.
   "Start Guide Again" (Settings) and `require(_:)` list every missing permission, skipped ones
   included. If nothing is listed, no window opens.
2. The window shows one row per listed permission, in `Permission` order: icon, title,
   explanation, and on the right either a green ✓ "Granted", or "Open System Settings" (plus
   "Skip" for Accessibility). A skipped row shows "Skipped" and keeps its button.
3. The 1 s poll and `didBecomeActive` update each row as soon as macOS reports the grant.
4. "Quit & Reopen" is a fallback, at most one, at the bottom: shown only if Screen Recording is
   still unreported some time after the user opened its pane (exact trigger decided after the
   by-hand check in "Live detection"; may be dropped if the probe proves reliable).
5. When every listed permission is granted or skipped, the window shows "You're all set" with
   Done. If they were all skipped and none granted, the window closes (as now).
6. `require(p)` opens the same checklist with row `p` highlighted.

## Core changes (`Permissions.swift`, tested)
- `PermissionGuide` → `PermissionChecklist`: `items` (fixed when it starts), `highlighted`,
  `skipped` in this checklist.
- `Permissions`: `checklist` replaces `guide`; `status(of:)` (granted / skipped / missing);
  `skip(_:)`; `isComplete`. `checkAtLaunch`, `startGuide(highlighting:)`, `require`, `refresh`
  (still quiet when nothing changed), `closeGuide` keep their meaning.
- The screen-recording probe's decision logic (given a window list and our pid, is another app's
  window title visible?) lives in Core as a pure function and is unit-tested.

## App changes
- `SystemPermissionChecker` uses the probe for Screen Recording.
- `PermissionGuideView` → `PermissionChecklistView`; `PermissionsCoordinator` wires it.
- `spec.md` §9: one checklist with live status instead of "one at a time".

## Acceptance criteria
- With both missing, one window lists both rows.
- Turning on Screen Recording in System Settings flips its row to ✓ within ~1 s, no restart.
- Same for Accessibility.
- Accessibility Skip is remembered; the next launch doesn't list it.
- All granted/skipped → "You're all set"; all skipped with none granted → the window closes.
- `require(.screenRecording)` opens the checklist with that row highlighted.
- Core logic covered by Swift Testing tests.

## Not covered by automated tests
TCC itself, the window, and System Settings deep links. Verified by hand.

## Open questions
- If the probe sees the grant but the picker still can't capture until a restart, keep a "Quit &
  Reopen" fallback, or treat that as a separate bug?
