# Walkthrough: Cmd+click paste into the active app

## What was built
Cmd+click in the picker now picks, closes the picker, re-activates the app that was active before
the picker opened, and pastes the value there with a synthetic Cmd+V (`spec.md` §4.3, §4.5). Without
the Accessibility permission the value is only copied and the permissions checklist opens with
Accessibility highlighted (§9).

## How the pieces fit
### Core (`ColorsipCore`, tested)
- **`PickerStep.pick(_:close:paste:)`**: `paste` defaults to `false`, so existing call sites and
  tests are unchanged.
- **`PickerSession.click(at:shift:command:)`**: Command wins over mode and Shift: it always returns
  `.pick(color, close: true, paste: true)`. With the mode menu open, clicks still only select modes.
- **`PasteTarget`** (pid + bundle ID) and **`PasteTargetTracker`**: remembers the last activated app
  that isn't Colorsip. `target(frontmost:)` returns the frontmost app unless it's Colorsip, otherwise
  the remembered one. This covers both entry points:
  - hotkey: Colorsip isn't activated, so the frontmost app is the target;
  - popover: Colorsip is active, so the app before it is the target.
- **`routePastePick(...) -> PastePlan`**: routes like `routePick` (history, pick target, clipboard),
  but copies in `formatForApp(target?.bundleID)`, then returns `.paste(target)`, `.copyOnly` (no
  target) or `.needsAccessibility`.

### App (thin, verified by hand)
- `AppDelegate` owns the tracker, fed by `NSWorkspace.didActivateApplicationNotification`. The
  picker closure computes the target **at open time** and passes it to
  `PickerController.open(pasteTarget:)`.
- `PickerController.perform` handles `paste: true` by closing the overlay **first** and then
  calling `onPastePick(color, target)`. The overlay must be gone before another app is activated.
  In eyedropper (re-pick) mode the `repick` case matches first, so Cmd+click is a plain pick.
- `AppModel.didPastePick` refreshes permissions and calls `routePastePick`. `AppDelegate` acts on the plan:
  `SyntheticPaster.paste(into:)`, or `permissionsGuide.require(.accessibility)`.
- `SyntheticPaster`: `NSApp.yieldActivation(to:)` + `activate()` (cooperative activation, needed
  when Colorsip is active from the popover), then it polls `frontmostApplication` every 20 ms for up
  to 1 s before it posts Cmd+V key down/up to `.cghidEventTap`. If the target never comes to the
  front, nothing is pasted, but the value is still on the clipboard.

## Key decisions
- **Smart Formats hook**: `AppModel.format(forApp:)` returns the active format today. V3 replaces its
  body; the core already passes the target's bundle ID through.
- **Key code 9 (`kVK_ANSI_V`)** (confirmed by the user). On non-QWERTY layouts such as Dvorak the
  shortcut differs. A follow-up can map the key through `UCKeyTranslate` if needed.
- **Cmd+Shift+click = Cmd+click** (confirmed by the user). Pasting while staying in the picker would
  mean switching focus back and forth.
- **No target** (no other app seen since launch) → copy only, without prompting for a permission.
- Cmd+Return/Space don't paste: the spec only defines Cmd+click.

## Non-obvious notes
- The Accessibility grant is tied to the code signature. An ad-hoc-signed rebuild can look granted
  without being able to post events; `make reset-permissions` fixes that.
- The app is not sandboxed, which posting CGEvents to other apps requires.
