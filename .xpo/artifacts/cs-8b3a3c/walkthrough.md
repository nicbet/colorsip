# Walkthrough: Popover UI polish

## What was built
Three things, the last added during review:

1. **Popover layout:**
   - The popover is a fixed 350 × 645 pt, with no scrollbars.
   - The palette list's rounded panel keeps its corners while the rows scroll inside it.
   - Locked palettes sit on a rounded light grey background.
2. **Loupe label redesign:**
   - A white pill shows a swatch, "name • value" and hint badges.
   - A small dark pill below shows a gamut-triangle icon and the profile name.
3. **Option menu switches the output format.** Sticky multi mode is gone; Shift+click covers it.

## How the pieces fit

### Popover (`PopoverView`, `PaletteListView`)
- **Size:** `PopoverView` sets `.frame(width: 350, height: 645)` on the whole popover, so the color editor gets the same size. The editor is pinned to the top with `.frame(maxHeight: .infinity, alignment: .top)`, otherwise it floats in the middle.
- **Rounded corners:** before, `listContainer()` (white/black background, radius 12) was applied to the `LazyVStack` *inside* the `ScrollView`, so the whole panel scrolled away. Now:
  - The rows get plain `.padding(10)` inside the scroll view.
  - `listContainer()` wraps the `ScrollView` itself and adds a `clipShape`. The panel stays put and rows clip at its rounded edge.
  - `maxListHeight` and the content-height measuring are gone: the list just takes the space between the format menu and the bottom bar.
- **Scrollbars:** the list and the horizontal swatch strips both use `.scrollIndicators(.never)`. `showsIndicators: false` (which means `.hidden`) still let a horizontal scroller show under a scrollable strip in a dark-mode snapshot. `.never` doesn't.
- **Locked palettes:** the `LockedBackground` modifier pads the row by 6, draws the rounded background, then pads by −6 horizontally.
  - The background reaches into the list's side padding, so locked rows' contents line up with unlocked ones.
  - The color is `#F2F2F2` in light mode and white at 8% opacity in dark mode.

### Loupe label (`LoupeView.swift`, `LoupeLabel`)
- **Layout:** `LoupeLabel` is a private struct that measures and draws both pills. `size` is the bounding box of the two pills, and that's all `LoupeLayout` (Core) needs: its placement logic (below the loupe, flipped above near the bottom edge, kept on screen) is unchanged.
- **White pill:**
  - It is body-text sized: 28 pt tall, 13 pt name and value, 18 pt swatch, 16 pt hint badges.
  - It is always white with black text, because it floats over arbitrary screen content in either appearance.
  - The swatch is the center sample drawn in the capture's color space (`centerColor(_:)`), so it matches the loupe.
- **Hints:** black rounded badges with white SF Symbols: `square.stack.3d.up.fill` for Multi (Shift held), `paperplane.fill` for Send (Cmd held).
- **Profile icon:** the same rainbow-filled triangle for every profile, drawn by clipping an `NSGradient` to a triangle path.
- **Removed:** `TargetProfile.badge` ("sRGB"/"P3"/"Generic"), since the dark pill shows `displayName`.

### Hints and the format menu (Core, `PickerSession.swift`)
- **Hints:** `PickerLabel.hints: [PickerHint]` replaces `isMulti`. `PickerSession` tracks Shift and Command (`shiftChanged`, `commandChanged`), and `label()` lists `.multi` before `.send`. `PickerController` feeds both modifiers at open and on every `flagsChanged`.
- **Modes removed:** `PickerMode`, `setMode` and `movedSincePick` are gone.
  - `click` closes unless Shift is held. Cmd+click still picks, closes and pastes, even with Shift.
  - `confirm` (Return/Space) always picks and closes.
- **The session owns `format`:**
  - It is set at init from `model.outputFormat`, and `label()` formats with it.
  - `PickerFormatMenu` replaces `PickerModeMenu`, with the same placement rules and 160 × 24 items for `OutputFormat.allCases`.
  - A click on an item sets `session.format` and returns `.none`.
  - In `perform(.none)`, the controller copies the format to `model.outputFormat`, which saves it through Settings, so the choice is global and the popover dropdown follows.
- **Menu interaction is unchanged:** the loupe freezes, the cursor shows, other clicks and keys except Esc do nothing, releasing Option warps back, and an Option still held from Hyper+P is ignored until released.

## Key decisions
- Hint icons are SF Symbols; the white pill is always white; one gamut icon serves every profile; the dark-mode locked background is white at 8% (all chosen by the user).
- The format menu was folded into this issue at the user's request. Multi mode was removed and the format is global, also by the user's choice.
- The product `spec.md` is updated: §1 MVP line, §4.3 controls, §4.4 is now "Format menu", and the §4.5 sound note. **Knock-on:** the V2 contrast pick was going to be a mode in the Option menu, so it now needs its own entry point (noted in §4.4).
- The README features, picker text and controls table are updated, and the `docs/` screenshots are re-rendered with `make screenshots`.

## Testing
- **Core (Swift Testing, 503 pass):**
  - The hint tests cover Shift × Command.
  - The new `Picking` suite replaces the mode tests: Return always closes, Shift+click stays, Cmd+click pastes.
  - The `Picker format menu` suite covers layout, hit testing, hover, and selection without picking, plus the existing freeze, warp and Hyper+P behavior.
- **By hand / snapshots:**
  - Popover light and dark, editor, and label: checked with `make snapshot`.
  - Both hints and the format menu: checked in temporary snapshot renders, since reverted.
  - The user reviewed the running build.
