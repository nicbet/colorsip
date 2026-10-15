# cs-4a8aa3 walkthrough: Instant hover label and pointing-hand cursor on swatches

## What was built
Hovering a swatch in any strip (palettes and Color History) instantly shows a one-line label above it, such as `Dust Red (#3c72da)`. The value is in the active output format. After a copy, the label reads `Copied` for as long as the swatch's check mark shows (about a second). Over a swatch, the cursor is the pointing hand. The swatches' old delayed `.help` tooltip is gone.

## Core (`ColorsipCore/SwatchHover.swift`, tested)
- **`SwatchHoverLabel(swatch:format:copied:)`** → `text`.
  - Normally `name (value)`, or only the value when the name is empty.
  - `Copied` while `copied` is set.
  - The same text is the swatch's accessibility label, minus the Copied state.
- **`SwatchHoverTracker`** remembers which swatch is hovered.
  - When the pointer moves across a strip, SwiftUI can deliver B's enter before A's exit. An `exit` only counts for the swatch that's currently hovered, so the label never blinks between swatches.
- **`HoverLabelPlacement.frame`** is pure geometry in AppKit screen coordinates (y up).
  - The label is centered above the anchor, flips below when it would cross the top of the visible frame, and is clamped horizontally.

## App
- **`SwatchHoverPanel`** (`Colorsip/SwatchHoverPanel.swift`): a single shared borderless, non-activating `NSPanel`.
  - Why a panel: a SwiftUI overlay would be clipped by the strip's scroll view, its fade mask and the palette list. An `NSPopover` animates, draws an arrow, and reopens when moved.
  - `ignoresMouseEvents = true`, so clicks, drags and right-clicks go to the swatch underneath.
  - It sits at the `.popUpMenu` level. A context menu opens later at the same level, so it covers the label.
  - `show(id, label:, anchor:)` moves and shows it. `update(id, label:)` changes the text in place (for Copied or a format change) and only acts if `id` is still hovered. `exit(id)` and `hide()` close it.
- **`SwatchStrip.cell`** (`PaletteListView.swift`):
  - `.onContinuousHover` calls `show` on each pointer move and `exit` on `.ended`. Nothing shows while a swatch drag is in progress.
  - The cell's screen frame comes from `NSEvent.mouseLocation` minus the pointer's local position in the cell. This avoids looking up the hosting window.
  - `.onChange(of: hoverLabel(swatch))` pushes Copied and format changes to the panel.
  - `.onDisappear` exits. This covers undo removing the swatch and the color editor replacing the list, so the tracker needs no pruning against the library.
  - `.pointerStyle(.link)` (macOS 15+) gives the pointing hand. It's declarative, so the cursor can't get stuck the way a missed `NSCursor.pop` would leave it.
- **Hiding:** scrolling the strip, scrolling the palette list, and `PopoverView.onDisappear` all call `hide()`. A label that stays where it was would point at the wrong swatch. The next pointer move shows it again.

## Decisions from review
- The user asked for one line (`name (value)`) instead of name and value on two lines.
- The user asked for the `Copied` feedback. It replaces the label text. The on-swatch check mark stays, because it confirms copies made from the context menu when no label is showing.

## Testing
- Core: label text (formats, empty name, Copied), tracker ordering, and placement (above, flipped, clamped left/right, offset screen).
- By hand (the user confirmed): the panel, the cursor, Copied, and that click, drag and context menu still work.
