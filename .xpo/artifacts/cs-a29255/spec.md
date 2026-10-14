# cs-a29255 — Palette list and swatch strips

Refines `spec.md` §3.1 (palette list, swatch interactions) and §7.3 (swatch strip).

## What
Fill the popover's empty middle area with a scrollable list of the library's palettes. Each row
shows a radio button, an optional icon, the name, a lock icon when the palette is locked, and a
swatch strip. Clicking a swatch copies its value in the active format. Right-clicking it offers
Copy as….

## Why
The library model and storage (cs-39dff3) exist, but the app doesn't load the library yet and
nothing shows it. This is the first surface that shows palettes. Color History (cs-979715),
management (cs-d6bd2c), drag and drop and the editor all build on this list.

## Scope
**In:**
- Loading the library in the app and saving it on change. Nothing does this yet, and the list needs it.
- Palette rows, strips, the empty-palette drop target (visual only), click to copy, Copy as….

**Out (later issues):**
- Color History row → cs-979715
- New palette, palette/group context menus, swatch Edit/Rename/Delete, reordering → cs-d6bd2c
- Making the drop target accept drops → cs-c07049
- Cmd+Z / Shift+Cmd+Z menu wiring → the first issue that adds user edits (cs-d6bd2c)

## Design

### Core (`ColorsipCore`, test-driven)
1. **`LibraryController`** (`@MainActor @Observable`, the same pattern as `SettingsStore`)
   - `init(store:)` loads the library and keeps its `issues` (as `loadIssues`).
   - `library` (read-only) and `perform(_ actionName:, _ change:)`. Each change goes through
     `UndoableLibrary` and is saved with `store.save(new, previous: old)`. `undo()`/`redo()` save too.
   - A save error goes to `lastError` and is cleared by the next successful save. The library is
     still saved when there are load issues: `LibraryStore` already protects files it couldn't read.
2. **`SwatchStripLayout`**: pure geometry for one palette's strip.
   - Input: the palette's sections and the strip width. Sections are the ungrouped section and then
     each group; empty sections are left out.
   - `segmentWidth = width / 16`. Segments in a section touch. Sections are separated by
     `groupGap` (4 pt).
   - Output: one frame per section (x, width) and one per swatch, plus `contentWidth`.
     `isScrollable` is true when `contentWidth > width`.
   - `fades(offset:)` returns `(leading: Bool, trailing: Bool)`: leading when `offset > 0`,
     trailing when `offset + width < contentWidth`, with a 0.5 pt tolerance.
   - `isEmpty` when the palette has no swatches, which shows the drop target.
3. **Copying**: a `Clipboard` protocol (`setString(_:)`; `Pasteboard` clashes with an ApplicationServices type) and
   `copyValue(of: CSipColor, as: OutputFormat, to: some Clipboard)`, which writes
   `format.string(for:)`. The app passes an `NSPasteboard` wrapper. Tests use a fake.
4. **`CSipColor.displayP3Components`**: the color gamut-mapped to Display P3 as (r, g, b, a), so
   the app can draw it as `Color(.displayP3, …)` without color math in the view.

### App (thin, checked by hand)
- `AppModel` owns `library: LibraryController` (created from the same `LibraryStore`).
- `PaletteListView`: a `ScrollView` + `LazyVStack` of `PaletteRow`s. With no palettes it shows a
  short hint: "No palettes yet. Click + to create one."
- `PaletteRow`:
  - Header: a leading slot, icon (emoji as text or SF Symbol), name.
  - Leading slot: unlocked palettes show the radio button for the pick target. Clicking it sets the
    target through `perform("Set Pick Target")`, which makes it undoable. Locked palettes can't be
    the target, so they show a lock icon in the same slot instead (no separate lock after the name).
  - Below the header is the strip, 20 pt tall.
- `SwatchStrip`:
  - A horizontal `ScrollView` (scrolls only when needed) with sections drawn as rounded rectangles
    (corner radius 4) clipped around their touching segments.
  - Fades are gradient masks on each edge, driven by `onScrollGeometryChange` and
    `SwatchStripLayout.fades`.
  - Each swatch: click copies (and briefly shows a check mark), `.help` shows its name and value,
    and its context menu has Copy as ▸ (every `OutputFormat`, showing the value next to each name).
- Empty palette: a dashed rounded rectangle labelled "Drop colors here", the same height as a
  strip.
- `AppDelegate` logs load issues with OSLog. Showing them in the UI is out of scope.

## Acceptance criteria
- [ ] Palettes on disk show in the popover in library order and scroll vertically.
- [ ] A row shows a leading radio button (unlocked) or lock icon (locked) in the same slot, then
      icon, name and strip.
- [ ] 16 swatches in one section fill the strip width exactly. Groups are separate rounded
      segments with a gap.
- [ ] Over 16 swatches (counting gaps), the strip scrolls horizontally. Each edge fades only when
      there's more content in that direction.
- [ ] An empty palette shows the dashed "Drop colors here" target.
- [ ] Clicking a swatch puts its value, in the format the dropdown shows, on the clipboard.
- [ ] Right-clicking a swatch → Copy as → any format copies that format.
- [ ] Clicking a radio button sets the pick target and saves it to `library.json`.
- [ ] Core tests cover `LibraryController` (load, save on perform, undo/redo save, errors),
      `SwatchStripLayout` and `copy`.

## Edge cases
- Groups that are all empty are left out of the strip. If the ungrouped section is also empty, the
  palette is empty and shows the drop target.
- Narrow widths and a width of 0 (before layout) don't divide by zero or produce negative sizes.
- Exactly 16 swatches in one section: not scrollable, no fades.
- 16 swatches split into two groups: content = width + gap, so the strip scrolls slightly. This is
  expected, since the segment width is fixed.

## Decisions (confirmed by the user)
1. The radio button is clickable in this issue (sets the pick target, undoable, saved).
2. Locked palettes show a lock icon where the radio button would be.
3. Click-to-copy shows a check mark on the swatch for about 1 s.
