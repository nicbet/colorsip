# Picker modes and pick routing

## What
The picker gets its pick controls and modes (`spec.md` §4.3–4.4), and picks go where §4.5 says:
- **Single** (default): click, Return or Space picks and closes.
- **Shift+click** picks and keeps the picker open, in either mode.
- **Multi**: every click picks. Return or Space picks too, unless the pointer hasn't moved since the
  last pick: then it finishes. Esc finishes. Picks already made are kept.
- **Hold Option**: a small mode menu (Single, Multi) appears next to the loupe. Contrast stays
  hidden until V2 (cs-81d6ee). Every session starts in Single; the mode isn't remembered.
- Every pick, at the moment it is made:
  1. goes into Color History,
  2. is inserted at the **front** of the pick target's ungrouped section, unless there is no target
     or it is locked. This is one undoable step, "Pick Color". It doesn't touch history.
  3. has its value copied in the active format, so the last pick ends up on the clipboard.
- Picks are named with the color's friendly name (§5.5).
- **Multi indicator**: the loupe label shows a "Multi" badge whenever the next click keeps the picker
  open: in multi mode, or while Shift is held.

## Why
The overlay (cs-40b6c9) only had a minimal pick that went to history. This makes the picker the
way to fill palettes. Cmd+click paste (cs-901e7e), contrast mode (cs-81d6ee) and templates
(cs-e84626) build on it.

## Scope
**In:** modes, Shift+click, Return/Space/Esc rules, the Option mode menu, routing into history,
target palette and clipboard, undo.
**Out:** Cmd+click paste (cs-901e7e). Contrast mode (cs-81d6ee). Highlighting an existing swatch
on a duplicate pick: the popover isn't visible while picking.

## Design

### Core (`ColorsipCore`)
- `PickerMode`: `.single`, `.multi`. `PickerMode.menu` lists the modes the menu shows (no contrast).
- `PickerSession` gains `mode` (starts `.single`) and tracks whether the pointer moved since the
  last pick (`pointerMoved` and `arrow` set it; a pick clears it).
- `finish(_:)` is replaced by input methods that return what the controller should do:
  - `click(at:shift:) -> PickerStep`
  - `confirm() -> PickerStep` (Return, keypad Enter, Space)
  - `cancel() -> PickerStep` (Esc)
  - `PickerStep`: `.pick(CSipColor, close: Bool)`, `.close`, `.none` (nothing to do).
- Rules (menu closed):

| Input | Single | Multi |
|---|---|---|
| Click | pick, close | pick, stay |
| Shift+click | pick, stay | pick, stay |
| Return / Space | pick, close | moved since last pick (or no pick yet): pick, stay; else close |
| Esc | close | close |

  A pick before the first sample is `.none`. In multi mode, Return with earlier picks and no move
  closes even without a sample.
- **Mode menu**, `optionChanged(isDown:)`:
  - Option down opens the menu. The loupe **freezes** where it is, and the system cursor shows, so
    the pointer can reach the menu (otherwise the loupe, centered on the pointer, would carry the
    menu with it).
  - While it's open, pointer moves only move the cursor (and highlight the item under it), and don't
    count as a move. A click on an item selects that mode; a click elsewhere does nothing. Arrow
    keys and Return/Space do nothing. Esc closes the picker. Option + wheel still changes the grid.
  - Option up closes the menu and returns the frozen point, which the controller warps the pointer
    back to, so the loupe stays on the pixel it was on.
  - `PickerModeMenu` lays the menu out in global coordinates: fixed-size items, beside the loupe on
    the right (left when it doesn't fit on the display), vertically centered on it and kept on the
    display. `mode(at:)` hit-tests.
- `shiftChanged(isDown:)` tracks Shift. `PickerLabel.isMulti` is true in multi mode or while Shift
  is held; `LoupeView` draws it as a third line in the label, in the accent color.
- `LibraryController.addPick(_:name:at:) -> Swatch.ID?`: inserts into the target's ungrouped
  section at index 0 as "Pick Color". Returns `nil` (and records no step) with no target, a locked
  target or a duplicate in that section.
- `routePick(_:format:history:library:clipboard:at:)`: history → palette → copy.

### App
- `PickerController` maps events to the session's input methods and acts on `PickerStep`:
  `.pick` → `onPick(color)`, then closes if `close`; `.close` → closes. It also monitors
  `.flagsChanged` for Option, shows and hides the cursor, and warps back on release.
- `LoupeView` draws the menu with the current mode checked and the hovered item highlighted.
- `onPick` in `AppDelegate` calls `routePick` through `AppModel`.

## Edge cases
- A duplicate of a swatch already in the target's ungrouped section: not added; history and the
  clipboard still get it.
- Target locked or none: history and clipboard only.
- Picks in a multi session survive Esc and a display change (the session closes; picks already
  routed stay).
- Undo after a multi session undoes one pick at a time.
- Hyper+P includes Option. An Option still held when the picker opens doesn't open the menu until
  it has been released once (`PickerSession(optionHeld:)`).

## Acceptance criteria
- [ ] Single mode: click, Return or Space picks and closes
- [ ] Shift+click picks and keeps the picker open
- [ ] Multi mode: every click picks; Esc, or Return/Space without moving, finishes, keeping the picks
- [ ] The loupe label shows "Multi" in multi mode and while Shift is held
- [ ] Holding Option shows the mode menu (Single, Multi); clicking an item switches mode
- [ ] Every pick goes into Color History, and to the front of the target palette's ungrouped section unless it's locked
- [ ] The last pick's value is on the clipboard in the active format
- [ ] Picks are auto-named and undoable, and undo leaves history alone

## Testing
- Swift Testing in `ColorsipCore`: the input table, the moved flag, the menu (freeze, hit test,
  layout, warp-back point), `addPick` (front, locked, none, duplicate, undo, history untouched),
  routing and clipboard.
- By hand: event handling, cursor and drawing in the real overlay.
