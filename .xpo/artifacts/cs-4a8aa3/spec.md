# cs-4a8aa3 — Instant hover label and pointing-hand cursor on swatches

Refines `spec.md` §3.1 (swatch interactions) and §7.3 (swatch strip).

## What
Hovering a swatch in any strip (palette rows and Color History) shows a small one-line label right away, such as `Dust Red (#3c72da)`. After a click copies, the label briefly reads `Copied`. Over a swatch, the cursor becomes the pointing hand, a hint that a click copies.

## Why
Today the name only shows in the system tooltip (`.help`), which waits about a second. The arrow cursor gives no hint that a swatch is clickable.

## Acceptance Criteria
- Over a swatch, a label appears with no delay. It's one line: `name (value)`, with the value in the active format. If the name is empty, it shows only the value.
- After a copy (click, or Copy as in the context menu), the label of the hovered swatch reads `Copied` for as long as the check mark shows (about a second), then goes back to `name (value)`. The label stays in place.
- The label sits centered above the hovered swatch. It flips below the swatch when there's no room above on the screen, and is clamped inside the screen's visible frame horizontally.
- Moving from swatch to swatch moves the label straight to the new swatch. It never disappears and reappears in between.
- These hide the label: leaving the strip, scrolling the strip or the palette list, starting a drag, the swatch disappearing (undo, color editor taking over), and closing the popover. The next pointer move over a swatch shows it again.
- The label never takes clicks, focus or drags (it ignores mouse events). Click-to-copy, the copied check mark, drag and drop, and the context menu work as before.
- The cursor is the pointing hand over swatches and the arrow everywhere else, and it never stays stuck as the hand.
- The `.help` tooltip is removed from swatches, since the label replaces it. The accessibility label is `name (value)`, and the swatch is marked as a button.

## Flow
1. **Core: `SwatchHoverLabel`** (`ColorsipCore/SwatchHover.swift`)
   - `init(swatch:format:copied:)` → `text`.
   - `text` is `Copied` when `copied` is set, otherwise `name (value)`, or only the value when the name is empty.
2. **Core: `SwatchHoverTracker`** (value type)
   - `enter(id)`, `exit(id)` → `hovered: Swatch.ID?`.
   - An `exit` for a swatch other than the current one is ignored. This handles SwiftUI sending B's enter before A's exit, so the label doesn't flicker.
   - `clear()` empties it.
3. **Core: `HoverLabelPlacement.frame(labelSize:anchor:visibleFrame:gap:)`** → `CGRect`
   - Places the label above the anchor if it fits, else below, then clamps it horizontally into the visible frame. This is pure geometry in screen coordinates (y grows upward).
4. **App: `SwatchHoverPanel`** (`Colorsip/SwatchHoverPanel.swift`)
   - A shared, borderless, non-activating `NSPanel` at `.popUpMenu` level, with `ignoresMouseEvents = true`, hosting a SwiftUI label on `.regularMaterial`.
   - `show(id, label:, anchor:)`, `exit(id)` and `hide()` wrap the tracker.
   - `update(id, label:)` changes the text of the hovered swatch's label and re-places it around the last anchor. It does nothing if `id` isn't hovered.
5. **App: `SwatchStrip.cell`**
   - `.onContinuousHover` calls `show` on every pointer move (no label while `model.drag != nil`) and `exit` on `.ended`.
   - The cell's screen frame comes from `NSEvent.mouseLocation` minus the pointer's local position, so no window lookup is needed.
   - `.onChange` of the copied state and the format calls `update`.
   - `.pointerStyle(.link)` sets the cursor (macOS 15+). `.onDisappear` exits.
6. **App:** `hide()` runs on strip scroll, palette list scroll, and `PopoverView.onDisappear`.

## Decisions
- **One line: `name (value)`,** as the user asked. It's more compact than two lines.
- **`Copied` replaces the text, and the check mark on the swatch stays.** The label confirms the copy near the pointer, and the check mark still works when the label isn't showing.
- **Floating panel, not a SwiftUI overlay.** An overlay would be clipped by the strip's scroll view, its fade mask and the palette list.
- **Panel, not `NSPopover`/`.popover`.** Popovers animate, draw an arrow, and close and reopen when they move. A plain panel moves instantly.
- **`.popUpMenu` level.** Menus share the level and open later, so a context menu covers the label.
- **`.pointerStyle(.link)`, not `NSCursor.push/pop`.** It's declarative and never leaves the cursor stuck.
- **Remove `.help`.** Showing a delayed tooltip as well as the instant label would duplicate it.
- **The swatch disappearing is handled by the cell's `.onDisappear`**, not by pruning the tracker against the library. This also covers the color editor replacing the list.

## Edge Cases
- MEDIUM: Hovering while a drag is in progress. No label is shown.
- LOW: Copy as from the context menu while the pointer is no longer over the swatch. No label is showing, so only the check mark confirms.
- LOW: Long names. The label is capped at 280 pt and truncates in the middle.
- LOW: The popover can't be detached (`popoverShouldDetach` → false), so there's no detach case.

## Assumptions
- Swatch names are never empty, because renames reject blank names. The label still renders with just the value if one is empty.
- The label follows system light/dark appearance through its material background.

## Testing
- Core (Swift Testing): label text per format, the empty name, `Copied`, the tracker's enter/exit ordering, and placement (above, flipped below, clamped left/right, offset screen).
- By hand: panel display, `Copied` feedback, the cursor, and that copy, drag and context menu still work. These are UI behaviors with no automated test.
