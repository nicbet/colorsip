# Walkthrough: Picker modes and pick routing

## What was built
The picker (cs-40b6c9) used to have one hard-coded pick that closed it and went to history. It now
has modes and real routing (`spec.md` §4.3–4.5):
- **Single** (the default every session): click, Return or Space picks and closes.
- **Shift+click** picks and stays open, in either mode.
- **Multi**: every click picks. Return/Space picks if the loupe moved since the last pick, and
  finishes otherwise. Esc finishes.
- **Hold Option**: a Single/Multi menu appears beside the loupe; click an item to switch.
- A **MULTI** line in the loupe label shows whenever the next click keeps the picker open (multi
  mode, or Shift held).
- Every pick, as it's made, goes to Color History, to the front of the pick target's ungrouped
  section (one undoable "Pick Color" step), and onto the clipboard in the active format.

## How the pieces fit
**`PickerSession` (core)** owns every decision. Input methods return a `PickerStep`; the
controller only carries it out:
- `click(at:shift:)`, `confirm()` (Return/Space), `cancel()` (Esc).
- `PickerStep` is `.pick(color, close:)`, `.close` or `.none`. This replaced `finish(_:)` and the
  `PickerAction`/`PickerOutcome` enums.
- `movedSincePick` drives multi-mode Return. It starts true, so the first Return picks.
  `pointerMoved` sets it only when the point actually changes. A move into the gap between displays
  doesn't count, and neither does a warp that lands on the same point.
- `shiftChanged(isDown:)` feeds `PickerLabel.isMulti`.

**The mode menu.** The loupe is centered on the pointer, so a menu drawn beside it would move away
as the pointer approached it. So while Option is held:
- the loupe **freezes** and `pointerMoved` only updates `cursor`, which drives the hover highlight;
- the controller shows the system cursor;
- a click on an item sets the mode, and other clicks, arrows and Return do nothing;
- on release, `optionChanged(isDown: false)` returns the frozen point, and the controller warps
  the pointer back so the loupe is on the same pixel.

`PickerModeMenu` is pure layout in global coordinates: fixed 120×24 items, to the right of the
loupe (left if it would leave the display), clamped vertically. It is tested like `LoupeLayout`.

**Hyper+P includes Option.** If the user releases Ctrl/Cmd before Option, a `.flagsChanged` with
Option still down would open the menu. `PickerSession(optionHeld:)` ignores Option until it has
been released once.

**Routing.**
- `LibraryController.addPick` inserts at index 0 of the target's ungrouped section through
  `perform("Pick Color")`. It returns `nil` and records no step with no target, a locked target
  (locking already clears the target) or a duplicate in that section.
- `routePick(...)` is a free function: history, then palette, then clipboard. `AppModel.didPick`
  calls it. It isn't named `routePick` because member lookup would shadow the free function, and
  a type named `ColorsipCore` also shadows the module, so `ColorsipCore.routePick` doesn't work.

Because routing happens per pick, not at close, Esc and display changes never lose picks. Undo
removes picks one at a time and never touches history, which isn't part of the library.

**App layer.**
- `PickerController` adds `.flagsChanged` to its monitor and balances `NSCursor.hide/unhide`
  around the menu (`close()` skips unhide if the menu was open).
- `LoupeView` draws the menu and builds the label from a list of lines, so the MULTI line is just
  one more line.

## Decisions
- The mode resets to Single each session; it isn't stored in settings.
- Return in multi mode picks after a move and finishes otherwise, so multi picking works from the
  keyboard alone.
- Holding Shift for Shift+arrow also shows MULTI; the session can't tell it from an upcoming
  Shift+click.
- A duplicate pick isn't highlighted in the palette: the popover isn't visible while picking.

## Not automated
Event handling, cursor show/hide and warp, and menu/label drawing were checked by hand by the user.
