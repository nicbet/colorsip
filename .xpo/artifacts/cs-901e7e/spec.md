# Cmd+click paste into the active app

## What
Cmd+click in the picker picks the color, closes the picker, re-activates the app that was active
before the picker opened, and pastes the value there with a synthetic Cmd+V (`spec.md` §4.3, §4.5).
Without the Accessibility permission, the value is only copied and the permissions checklist opens
with the Accessibility row highlighted (§9).

## Why
Saves the switch-back-and-paste step, the most common thing done after a pick.

## Scope
**In:** Cmd+click in single and multi mode, remembering the paste target, routing + paste, the
permission fallback, a per-app format hook for Smart Formats.
**Out:** Smart Formats themselves (V3), Cmd+Return/Space (spec only lists Cmd+click), paste for the
color editor's eyedropper.

## Behavior
1. **Paste target.** Colorsip watches app activations (`NSWorkspace.didActivateApplicationNotification`)
   and remembers the last app that isn't Colorsip. When the picker opens, the target is the frontmost
   app if it isn't Colorsip (hotkey case), otherwise the remembered one (opened from the popover).
   It's taken once per session.
2. **Cmd+click** picks and closes in either mode, with or without Shift (Cmd wins). With the mode
   menu open it selects a mode as before. Return/Space/plain clicks are unchanged.
3. The pick is routed as usual (history, pick target, clipboard), except the clipboard value uses
   the format chosen for the target app.
4. Then, in order:
   - no target app → copy only, no prompt;
   - Accessibility missing → copy only; the checklist opens with Accessibility highlighted;
   - otherwise → the picker closes, the target is activated, and once it's frontmost (polled, up to
     ~1 s) Cmd+V is posted with `CGEvent` to the HID tap. If it never becomes frontmost, no paste
     (the value is still on the clipboard).
5. **Eyedropper (re-pick):** Cmd+click is a plain pick; nothing is pasted.

## Design
### Core (`ColorsipCore`, tested)
- `PickerStep.pick(CSipColor, close: Bool, paste: Bool = false)`.
- `PickerSession.click(at:shift:command:)` — `command` → `.pick(c, close: true, paste: true)`.
- `PasteTarget { pid: Int32, bundleID: String? }`.
- `PasteTargetTracker(ownBundleID:)`: `activated(_:)` remembers non-own apps;
  `target(frontmost:)` returns frontmost if it isn't own, else the remembered app.
- `routePastePick(color, into: target, accessibilityGranted:, formatForApp: (String?) -> OutputFormat, history:, library:, clipboard:, at:) -> PastePlan`
  with `PastePlan = .paste(PasteTarget) | .copyOnly | .needsAccessibility`. It routes with
  `formatForApp(target?.bundleID)`.
- **Smart Formats hook:** `formatForApp`. `AppModel.format(forApp:)` returns the active format for
  now; V3 replaces its body.

### App (thin, verified by hand)
- `PickerController` passes `.command` to `click`, records the target at `open()`, and calls
  `onPastePick(color, target)` for paste picks (after closing the overlay).
- `AppDelegate` owns the tracker (workspace observer), runs `routePastePick` via `AppModel`, and
  for `.needsAccessibility` calls `permissionsGuide.require(.accessibility)`.
- `SyntheticPaster`: activates the app (`NSApp.yieldActivation(to:)` + `activate()`), polls
  `frontmostApplication` every 20 ms up to 1 s, then posts Cmd+V key down/up.

## Acceptance criteria
- [ ] Cmd+click picks, closes (single and multi, with or without Shift), and pastes into the previous app.
- [ ] Opening from the hotkey pastes into the app that was frontmost; from the popover, into the app active before Colorsip.
- [ ] Without Accessibility: value copied, checklist opens with Accessibility highlighted, no paste.
- [ ] The pasted/copied value's format comes from `formatForApp(bundleID)`.
- [ ] Eyedropper Cmd+click doesn't paste.
- [ ] Core tests cover the session step, tracker and plan.

## Decisions (confirmed by the user)
1. **Key code:** Cmd+V is posted as virtual key 9 (`kVK_ANSI_V`). On layouts like Dvorak that key
   isn't "V"; the value is still on the clipboard. A follow-up can map through the layout if needed.
2. **Cmd+Shift+click** behaves like Cmd+click (closes and pastes).
3. **Target from popover** is the last non-Colorsip app activated; if none was seen since launch,
   it's copy-only.
