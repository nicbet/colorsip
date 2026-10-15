# Walkthrough: Compact color editor

## What was built
Right-click a swatch in the popover → **Edit…** opens a color editor. It has a saturation/brightness field, hue and alpha sliders, a before/after preview, and a model switcher with numeric fields (HEX, RGB, HSB, HSL, OKLCH, P3; alpha in all). It also has name and description fields, an eyedropper, and a "…" menu with Copy as and Reset. Done saves everything as one undo step, "Edit Color". In the popover strips, translucent swatches now show a checkerboard behind them.

## How the pieces fit

### ColorsipCore (all the rules, all tested)
- **`ColorEditor`** (`ColorEditor.swift`) is a value type that holds the *draft*. The UI never touches the library while editing; it only mutates this struct.
  - **Working space.** It is picked once, from the stored space: sRGB for srgb/hsl/hwb, Generic RGB for generic-rgb, P3 otherwise. `setColor` is the single choke point for every color change. It converts into the working space and **promotes to Display P3** when the new color leaves the gamut. That way typing a P3 or OKLCH value into an sRGB swatch isn't clipped.
  - **Exact round trip.** `color` starts as the original swatch color, untouched. Only a real change converts it, so saving a name-only edit keeps an OKLCH color in OKLCH, bit for bit.
  - **Separate HSB state.** `hsb` is kept apart from `color`. Without it, dragging brightness to 0 would make the hue and saturation undefined, and the ring and hue thumb would jump. Typed and picked colors refresh `hsb`, but a gray keeps the old hue, and black keeps hue and saturation.
  - **Fields.** `fields(_:)` renders each model with the same rounding helper as the output formats. HEX, RGB and HSL use the gamut-mapped sRGB value; `isOutsideSRGB` drives the warning icon.
  - **Commits.** `commit(_:field:of:)` parses, clamps or wraps, and applies. Committing text that equals what's shown is a no-op. This matters because tabbing through fields would otherwise re-apply rounded values and drift the color.
  - **Auto-name.** `nameFollowsColor` is true when the swatch's name equals its color's `friendlyName`, and `setName` clears it. Reset rebuilds the editor from the original swatch, which restores it.
- **`Library.editSwatch`** changes color, name and description in one pass, through the private `modifySwatch` helper. That helper was called `editSwatch` before and was renamed to free the name. The duplicate check runs before anything changes. It doesn't reuse `setSwatchColor` because that method stamps `modifiedAt` even when the color is unchanged, which would turn no-op saves into undo steps.
- **`LibraryController.editSwatch` / `save(_:in:)`** wrap that in one undoable step, trim the name and description (an empty name keeps the old one), and return `SwatchEditResult`: `.changed`, `.unchanged`, `.duplicate(existing:)` or `.failed`.
- `SwatchMenuItem.edit` (after Copy as; never shown in history or locked palettes) and `LocalSettings.editorModel` (the remembered model switcher choice).

### App (thin)
- **`AppModel`** holds a `ColorEditorSession`: the draft, the swatch's section, and the duplicate name after a refused save. It has `openEditor`, `saveEditor`, `discardEditor`, `startRepick` / `endRepick` and `closeEditorIfSwatchIsGone`.
- **`PopoverView`** swaps its whole content for `ColorEditorView` while a session exists (a slide-in, sheet-like transition). Library Undo/Redo keys belong to the normal content only, so they're off during editing. Closing the popover discards the draft, unless a re-pick is in progress.
- **`ColorEditorView`** draws the controls and forwards every gesture or commit to `ColorEditor` through one `update` helper. `NumericField` keeps local text, commits on Return or focus loss, and resyncs whenever the draft's value changes.
- **Eyedropper.** The button calls `model.startRepick()`, then `actions.repick`. That action is wrapped by `StatusItemController` to close the popover first. `AppDelegate` checks the Screen Recording permission, then calls `PickerController.open(repick:)`. In that mode the first pick goes to the completion instead of `onPick`, so there's no history, pick target or clipboard. Any close without a pick reports `nil`. The completion calls `endRepick` and `StatusItemController.showPopover()`.
- **`Checkerboard`** (in `ColorEditorView.swift`) is shared with `SwatchStrip`, which draws it behind cells with alpha < 1.

## Key decisions
1. **Draft + Done/Cancel**, one undo step, rather than live editing (user's choice).
2. **A re-pick is an edit, not a pick**: it doesn't go to Color History (user's choice).
3. **Auto-name follows the color** until the user types a name (user's choice).
4. **The editor replaces the popover content** instead of a SwiftUI `.sheet`, because sheets on an `NSPopover` window aren't reliable.
5. **A duplicate message names the existing swatch.** The usual strip highlight would be hidden behind the editor.
6. Review polish: the field is labeled "HEX"; the alpha field has a fixed width and no "%"; the Name and Description labels sit above their fields with placeholders; translucent swatches get a checkerboard.

## Non-obvious bits
- `#expect` can't wrap a mutating call, so `ColorEditorTests` routes `commit` results through `expectTrue` / `expectFalse` helpers.
- `PickerController.close()` always calls `finishRepick(nil)` in a `defer`. A re-pick completion is therefore called exactly once, whatever ends the session (Esc, a display change, a capture error).
- The hue slider stops at 359.999° so the thumb doesn't wrap back to 0 at the right end.

## Tests
`ColorEditorTests.swift` covers models, fields, working space, promotion, sliders, gray handling, hex/number parsing, no-op commits, auto-name and reset. `EditSwatchTests.swift` covers `Library.editSwatch`, the controller command and undo, trimming, no-op, duplicate and failed results, the menu and the `LocalSettings` round trip. 445 tests pass. The SwiftUI controls and the eyedropper round trip were checked by hand by the user.
