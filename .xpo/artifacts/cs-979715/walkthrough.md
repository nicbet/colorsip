# cs-979715 — Color History walkthrough

Color History is a read-only list of the last 16 picks. It's always the first row in the popover and is stored in `history.json` (`spec.md` §7.4, §11.1).

## The pieces

| File | Role |
|---|---|
| `Packages/ColorsipCore/Sources/ColorsipCore/ColorHistory.swift` | `ColorHistory` holds the rules and the JSON. `ColorHistoryController` loads and saves it. |
| `Packages/ColorsipCore/Sources/ColorsipCore/SwatchStripLayout.swift` | New `init(swatches:width:)` for a strip with one section |
| `Colorsip/AppModel.swift` | `history` and `recordPick(_:)` |
| `Colorsip/ColorsipApp.swift` | `onPick` records the pick and copies it. History load issues are logged. |
| `Colorsip/PaletteListView.swift` | `HistoryRow`, `StripPlaceholder` and `SwatchStrip`, which now takes a palette or plain swatches |

## How it works
- **`ColorHistory`** is a value type holding `swatches: [Swatch]`, newest first. Entries are ordinary `Swatch`es, so the strip, the tooltips ("name — value") and Copy as… work the same as for palettes.
  - `record(_:name:at:)` is the only way to change it. It removes any perceptually equal entry (ΔEOK < 0.002, §5.1), puts a new swatch at the front and trims to 16.
  - A re-pick replaces the old entry with the new pick's exact value and timestamp, so the newest value wins. The user confirmed this.
- **`init(swatches:)` normalizes its input.** It keeps the first of any duplicates and caps the list at 16. Decoding goes through it, so a hand-edited or merged file can't break the rules.
- **The JSON is lenient,** like `AppSettings`.
  - An entry that can't be decoded is skipped through a private `Lenient<T>` wrapper, so one bad entry doesn't lose the rest.
  - Only a `formatVersion` newer than 1 rejects the whole file, as `ColorsipFormatError.newerFormat`.
- **`ColorHistoryController`** follows `SettingsStore`.
  - It loads the file at init and saves atomically after each `record`. Save errors go to `lastError`.
  - If the file is corrupt or from a newer version, history works in memory for the session but the file is never written. The user's data stays safe.
- **Undo.** History lives outside `Library` and `UndoableLibrary`, so undo and redo can't touch it. §7.6 says the effect of a pick on history isn't undoable, and a test checks this.

## UI
- `PaletteListView` always shows the scroll view.
  - `HistoryRow` comes first, then the palettes. The "No palettes yet" hint now sits below history instead of replacing the whole list.
  - `HistoryRow` puts a clock symbol in the radio button's 16 pt slot so names line up. It has no radio button and no lock.
- `DropColorsTarget` became `StripPlaceholder(label:)`.
  - Empty history uses it with the label "Picked colors appear here".
  - It isn't a drop target: you can't drop colors into history.
- `SwatchStrip` builds its layout from a closure set by one of two initializers, one for a palette and one for plain swatches. Click to copy, the check mark, fades and Copy as… are shared.

## Scope notes
- Picks are named with `CSipColor.friendlyName`.
- Routing picks to the target palette, multi mode and undo of picks belong to cs-995046. This issue only adds the history call to the existing `onPick`.
- Dragging out of history, always as a copy, belongs to cs-c07049.

## Testing
- `ColorHistoryTests.swift` covers order, capacity, merging (including across color spaces), normalization, round-tripping, version rejection, skipped bad entries, and the controller's load, save, no-overwrite and save-error behavior. It also checks that undo leaves history alone.
- Test colors are OKLCH hues 5° apart. Steps of 1/64 in dark sRGB red fell below ΔEOK 0.002 and merged.
- The SwiftUI row and the picker wiring were checked by hand.
