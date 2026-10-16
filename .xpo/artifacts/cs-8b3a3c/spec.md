# Popover UI polish

## What
Visual polish for the menubar popover and the picker's loupe label, and an Option menu that switches the output format instead of the picker mode.

1. **Popover size:** fixed at 350 × 645 pt (now 320 wide, height follows content up to a 300 pt list).
2. **No scrollbars:** no visible scroll indicators in the popover.
3. **Palettes container:** still scrolls vertically, and its rounded corners (radius 12) always stay visible: content scrolls *inside* the rounded panel instead of the panel scrolling away with it.
4. **Locked palettes:** a locked palette's row sits on a rounded light grey background (`#F2F2F2`).
5. **Picker label redesign** (reference screenshot in the chat attachments):
   - **Pill 1** (white, fully rounded): a round swatch of the color · **friendly name** (black, semibold) · `•` · **value** in the active format (grey) · hint icons on the right.
   - **Pill 2** (smaller, dark translucent, below pill 1, centered): a profile icon (colorful gamut triangle) + the profile's display name (e.g. "Generic RGB").
   - **Hints:** small rounded icons instead of the "MULTI" text line:
     - **Multi:** Shift is held, so the next click keeps the picker open. This replaces "MULTI".
     - **Send:** Command is held, so a click picks and pastes into the previous app (`spec.md` §4.5). This is new: the label doesn't show this yet.
6. **Option menu switches the format** (added during review):
   - Holding Option shows a menu of every output format beside the loupe, the active one checked. Clicking an item makes it the app's active format: the same setting as the popover's format dropdown, so it stays after the picker closes. The label updates at once.
   - **Multi mode is removed.** Shift+click is the only way to keep the picker open. Click, Return and Space pick and close.
   - The menu otherwise behaves like the mode menu did: the loupe freezes and the cursor shows while Option is held, a click on an item doesn't pick, other clicks and keys except Esc do nothing, releasing Option puts the pointer back. An Option still held from Hyper+P is ignored until released.

## Why
The popover is cramped and its list container loses its rounded edges while scrolling. Locked palettes don't stand out. The loupe label has three stacked text lines that are hard to scan, and it says nothing about Cmd+click paste.

Sticky multi mode duplicates Shift+click. Switching the format mid-pick is more useful: today it means closing the picker and opening the popover.

## How

### Core (`ColorsipCore`, tested)
- `PickerLabel`: replace `isMulti: Bool` with `hints: [PickerHint]`, where `enum PickerHint { case multi, send }`, in display order (multi, then send).
- `PickerSession`:
  - Add `commandChanged(isDown:)` next to `shiftChanged`. The label adds `.multi` while Shift is held and `.send` while Command is held.
  - Remove `PickerMode`, `mode`, `setMode` and the "moved since the last pick" tracking. `click` closes unless Shift is held. `confirm` (Return/Space) always picks and closes.
  - The session owns the active format: `init(…, format:)`, `format` (read-only from outside), and `label()` uses it in place of `label(format:)`.
  - Rename the menu to the format menu: `PickerFormatMenu` with `Item.format`, `format(at:)`, `formatMenu` and `hoveredFormat`. Its items are `OutputFormat.allCases` in order, 160 × 24 pt each. A click on an item sets `format`.
- `PickerController`:
  - Reads Command at open and on `flagsChanged`, like Shift.
  - Starts the session with `model.outputFormat`. After a menu click, it copies `session.format` back to `model.outputFormat`, which saves it like the dropdown does.
- `LoupeLayout` is unchanged: it still takes one label size, which is now the bounding box of both pills.

### App (thin, checked by hand)
- **`PopoverView`:** `.frame(width: 350, height: 645)`. This applies to the color editor too, since it fills the same popover. The editor is pinned to the top instead of floating in the middle.
- **`PaletteListView`:**
  - Drop `maxListHeight` and the content-height sizing. The list fills the space between the format menu and the bottom bar.
  - Move the white/black rounded background and a `clipShape(RoundedRectangle(cornerRadius: 12))` *outside* the `ScrollView`, so the panel stays put and rows scroll inside it. Keep the inner padding as content insets.
  - Hide the indicators with `.scrollIndicators(.never)`, on the list and on the horizontal swatch strips. `.hidden` and `showsIndicators: false` still let a scroller show in some cases on macOS (one was seen under a scrollable strip in dark mode).
- **`PaletteRow`:** when `palette.isLocked`, add a `RoundedRectangle(cornerRadius: 8)` background with a little padding: `#F2F2F2` in light mode, `white.opacity(0.08)` in dark mode.
- **`LoupeView`:**
  - Redraw the label as the two pills above:
    - Pill 1: body-text size, like the rest of the UI: a 28 pt tall pill with a 13 pt semibold name and 13 pt value, an 18 pt swatch circle drawn in the capture color space, and hint icons as 16 pt rounded badges, white on black.
    - Pill 2: 12 pt text and a 14 pt gamut-triangle icon.
  - Drop the profile badge string from line 1. `TargetProfile.badge` goes unused; remove it if nothing else uses it.
  - Draw the format menu like the mode menu: format display names, the active one checked, the hovered one highlighted.
- **Product spec (`spec.md`):** update §4.3 (Option shows the format menu; Return/Space always close), §4.4 (no modes; Contrast stays V2 and needs a new entry point), and §4.5's sound note.

## Decisions
- **Hint icons:** SF Symbols in small rounded black badges with white icons: Multi = `square.stack.3d.up.fill`, Send = `paperplane.fill`.
- **Locked background in dark mode:** `white.opacity(0.08)`. Light mode uses `#F2F2F2`.
- **Pill 1:** always white with black text, in light and dark mode alike, since it floats over arbitrary screen content.
- **Profile icon:** the same drawn colorful gamut triangle for every profile.
- **Format menu scope:** done in this issue at the user's request.
- **Multi mode:** removed, since Shift+click covers it.
- **Format persistence:** global. The menu sets the app's active format, the same setting as the popover dropdown.

## Acceptance criteria
- [ ] The popover is 350 × 645 pt, with the list and with the color editor open.
- [ ] No scrollbar shows anywhere in the popover, even with many palettes. Trackpad/wheel scrolling of the palette list still works.
- [ ] While the list scrolls, the white (dark: black) container keeps all four rounded corners. Rows are clipped at the rounded edge.
- [ ] Locked palettes have a rounded `#F2F2F2` background (dark mode: white at 8% opacity). Unlocked ones don't.
- [ ] The loupe label shows pill 1 (swatch, name • value, hints) and pill 2 (profile icon + display name).
- [ ] The Multi hint shows while Shift is held. The Send hint shows while Command is held. Both can show together.
- [ ] The label still flips above the loupe near the bottom of the screen and stays on screen at the edges.
- [ ] Holding Option shows every output format with the active one checked. Clicking one changes the label's value at once and the popover dropdown afterwards, and doesn't pick.
- [ ] Click, Return and Space pick and close. Shift+click picks and stays open. Cmd+click picks, closes and pastes.
- [ ] Core tests cover: hints for Shift × Command; format menu layout, hit testing and selection; the session's format in the label; Return/Space always closing. Mode tests are removed or rewritten.
