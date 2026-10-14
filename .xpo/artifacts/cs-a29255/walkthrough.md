# cs-a29255 walkthrough: Palette list and swatch strips

## What was built
The popover's middle area now shows the library: a scrollable list of palette rows, each with a leading radio button or lock, an icon, the name and a swatch strip. Clicking a swatch copies its value in the active format. Right-click → Copy as lists every format. An empty palette shows a dashed "Drop colors here" target, drawn only; drops come in cs-c07049.

Before this, the app never loaded the library, so this issue also wires the library into the app.

## How the pieces fit

```
AppModel
 ├─ library: LibraryController ── UndoableLibrary ── Library
 │                              └─ LibraryStore (load at init, save after each change)
 ├─ copy(color, as:) ── copyValue(of:as:to:) ── SystemClipboard (NSPasteboard)
 └─ setPickTarget(id) ── library.perform("Set Pick Target")

PopoverView
 └─ PaletteListView ── PaletteRow ── SwatchStrip ── SwatchStripLayout (geometry)
                                  └─ DropColorsTarget (empty palette)
```

### Core (`ColorsipCore`, tested)
- **`LibraryController`** (`@MainActor @Observable`, the same shape as `SettingsStore`). It loads the library once at init and keeps `loadIssues`. Every change goes through `perform(name) { … }`, which delegates to `UndoableLibrary`, then saves only what changed (`store.save(new, previous: old)`). `undo()`/`redo()` save too.
  - A failed save sets `lastError`. Afterwards the disk may lag behind `previous`, so the next save passes `previous: nil` and writes everything; a successful save clears the error.
  - The library is still saved when there are load issues. `LibraryStore` already refuses to overwrite files it couldn't read.
- **`SwatchStripLayout`** holds all the strip geometry, so the view has no math to test by eye.
  - `segmentWidth = width / 16`. The width is fixed, so 16 swatches in one section fill the strip exactly.
  - Sections are the ungrouped section and then each group. Empty ones are left out, and sections are 4 pt apart (`groupGap`).
  - `isScrollable` and `fades(offset:)` use a 0.5 pt tolerance, so sub-point scroll positions and rubber-band overscroll don't flicker the fades.
  - Because the segment width is fixed, 16 swatches split across two groups overflow by exactly one gap and scroll slightly. This is expected.
  - A width of zero or less (before layout) gives zero-sized segments, never negative ones.
- **`Clipboard` + `copyValue(of:as:to:)`**: copying through a protocol, so it can be tested with a fake. It's named `Clipboard` because `Pasteboard` clashes with an ApplicationServices type in the app target.
- **`CSipColor.displayP3Components`**: the color gamut-mapped to Display P3, which the view turns into `Color(.displayP3, …)`. Wide-gamut colors draw correctly on P3 displays.

### App (thin, verified by hand)
- **`PaletteRow`**: the leading slot is the pick-target radio button, or a lock icon for locked palettes. Locked palettes can't be the target, and the product spec hides unavailable UI rather than disabling it, so the lock takes the radio's place (user decision). Clicking the selected radio does nothing; clearing the target belongs to cs-d6bd2c.
- **`SwatchStrip`**:
  - It uses a `GeometryReader` for the width, then a horizontal `ScrollView` that's disabled when the content fits.
  - Sections are `HStack`s clipped to a 4 pt rounded rectangle.
  - Fades are a gradient mask driven by `onScrollGeometryChange` and `layout.fades(offset:)`.
  - Clicking a swatch copies it and shows a check mark for about a second. The mark is black on light colors (OKLCH L > 0.65) and white otherwise.
- **`AppDelegate`** logs library load issues with OSLog. Showing them in the UI is out of scope.

## Decisions made during review
- The radio button is clickable in this issue; the change is undoable and saved to `library.json`.
- Locked palettes show the lock where the radio button would be.
- Click-to-copy shows a check mark for about a second.

## Not covered by automated tests
The SwiftUI views, scrolling, fades and the system pasteboard. The user tested them by hand against a seeded sample library: exactly 16 swatches, groups with an empty group, overflowing groups, 8 + 8 split, an empty palette, a locked wide-gamut palette, and a long name.

## Follow-ups found while testing
- cs-7940c0: ad-hoc signing makes permission grants stop applying after every rebuild.
- cs-925b95: "Quit & Reopen" in the permissions guide doesn't reopen.
- cs-f8f139: permissions onboarding as one checklist with at most one restart.
- Cmd+Z / Shift+Cmd+Z wiring in the popover arrives with the first user edits (cs-d6bd2c).
