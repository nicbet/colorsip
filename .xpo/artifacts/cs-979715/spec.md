# cs-979715 — Color History

Refines `spec.md` §3.1 (palette list), §7.4 (Color History), §7.6 (undo) and §11.1 (`history.json`).

## What
A read-only **Color History** row, always first in the popover's palette list. It holds the last
16 picks, newest first. Picking a color that is already there moves it to the front. It is stored
in `history.json`.

## Why
Every pick should be recoverable, even when no palette is the pick target. Pick routing
(cs-995046) builds on this: every pick goes into history.

## Scope
**In:**
- Core model, rules and storage for history (`ColorHistory`, `ColorHistoryController`).
- The history row in the popover: a strip with click to copy and Copy as…, like a palette strip.
- Wiring the picker's current `onPick` so that a pick is recorded in history, as well as copied.
  Without this the feature can't be tried. Routing picks to the target palette, multi mode and
  undo of picks stay in cs-995046.

**Out:**
- Dragging out of history (always a copy) → cs-c07049, which already lists it.
- Sync (V3).

## Design

### Core (`ColorsipCore`, test-driven)
1. **`ColorHistory`** (value type, `Equatable`, `Sendable`, `Codable`)
   - `static let capacity = 16`
   - `swatches: [Swatch]` (read-only from outside), newest first. Entries are `Swatch`es, so the
     strip and the tooltip ("name — value") work the same as for palettes.
   - `mutating func record(_ color: CSipColor, name: String, at date: Date = .now)`
     - Removes any entry that is perceptually equal (ΔEOK < 0.002, §5.1), then inserts a new
       swatch with the new pick's exact color, name and timestamp at the front.
     - Trims to 16 by dropping the oldest entries.
   - No other mutating API: history can't be cleared, edited or reordered.
   - `init(swatches:)` normalizes its input: removes duplicates (keeps the first, newest one) and
     trims to 16. Decoding goes through it, so a hand-edited or merged file is cleaned up.
   - JSON:
     ```json
     { "formatVersion": 1, "swatches": [ { "id": "…", "color": { "colorSpace": "display-p3", "components": […], "alpha": 1, "hex": "#…" }, "name": "…", "createdAt": "…", "modifiedAt": "…" } ] }
     ```
     A `formatVersion` newer than 1 throws `ColorsipFormatError.newerFormat`. Entries that can't
     be decoded are skipped, so one bad entry doesn't lose the others (lenient, like
     `AppSettings`).
2. **`ColorHistoryController`** (`@MainActor @Observable`, the same pattern as `SettingsStore`)
   - `init(store:)` loads `history.json`. If the file is missing, history starts empty. If the file
     is corrupt or from a newer version, the app runs with an empty history for the session, sets
     `loadIssue`, and **never overwrites the file**.
   - `history`, `record(_:name:at:)`, which saves at once (atomic write). Save errors go to
     `lastError` and are cleared by the next successful save.
   - It isn't part of `UndoableLibrary`, so undo never touches history (§7.6).
3. **`SwatchStripLayout`** gets `init(swatches:width:)`, which is one ungrouped section, for
   history. The palette initializer shares the same code.

### App (thin, checked by hand)
- `AppModel` owns `history: ColorHistoryController` (from the same `LibraryStore`) and has
  `recordPick(_ color:)`, which records it with `color.friendlyName`.
- `onPick` copies the value **and** records it in history.
- `PaletteListView`: the history row comes first and is always shown, even with no palettes. The
  "No palettes yet. Click + to create one." hint moves below it.
- `HistoryRow`: a leading clock symbol (`clock.arrow.circlepath`, secondary) in the radio button
  slot, so the names line up. Then the name "Color History" and the strip. No radio button, no
  lock.
- `SwatchStrip` takes a `SwatchStripLayout` input (swatches or palette) instead of a `Palette`.
  Click to copy, the check mark and Copy as… are unchanged. The context menu has only Copy as…,
  which is already the case (Edit, Rename and Delete don't exist yet).
- Empty history: a dashed placeholder like the drop target, labelled "Picked colors appear here".
  It is not a drop target.

## Acceptance criteria
- [ ] Color History is always the first row, with no radio button and no lock. It shows even
      when there are no palettes.
- [ ] Picking adds the color to the front of history. After 17 distinct picks it holds the 16 newest.
- [ ] Re-picking a color already in history (ΔEOK < 0.002) moves it to the front without a
      duplicate, and the entry takes the new pick's value.
- [ ] History can't be edited, cleared or reordered: the only API is `record`, and the context
      menu only offers Copy as….
- [ ] Clicking a history swatch copies it in the active format. Copy as… works.
- [ ] History survives a relaunch through `history.json`, written atomically.
- [ ] A corrupt or newer `history.json` is never overwritten.
- [ ] Undo and redo of library changes don't affect history.
- [ ] Core tests cover `ColorHistory` (order, merging, capacity, normalization, coding, version)
      and `ColorHistoryController` (load, save, load issues, no overwrite).

## Edge cases
- Re-picking the color that is already at the front still saves (the timestamp and value change).
- A file with more than 16 entries or with duplicates is normalized on load. It is rewritten only
  on the next pick.
- Colors in different spaces that are perceptually equal (e.g. sRGB `#ff0000` and the same red in
  Display P3) count as the same color.

## Decisions (confirmed by the user)
1. A re-pick replaces the old entry with the new value (new id and timestamp), rather than only moving the old one.
2. Dragging out of history stays in cs-c07049.
3. This issue wires the existing `onPick` into history. cs-995046 does the rest of the routing.
4. Clock symbol in the leading slot; empty-state text "Picked colors appear here".
