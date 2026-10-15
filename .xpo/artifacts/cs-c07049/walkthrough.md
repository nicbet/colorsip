# cs-c07049 walkthrough: Drag and drop of swatches

## What was built
Swatches can be dragged in the popover (`spec.md` §7.5):
- **Where from:** between palettes, between the sections of a palette, within a section (to
  reorder), and out of Color History.
- **Move or copy:** a plain drag moves. Option-drag copies. Dragging out of Color History or out of
  a locked palette always copies.
- **Drop targets:**
  - a palette's strip, where the pointer picks the section and slot, shown by an insertion line;
  - a palette's header and the empty "Drop colors here" area, which add to the front of the
    ungrouped section.
- **Refusals:**
  - A duplicate in the destination section is refused, and the existing swatch gets a ring for
    about a second.
  - Locked palettes show the forbidden cursor.
- **Other apps:** dragging to another app gives the value as text in the active format, plus an
  `NSColor`. It never removes the swatch.
- **Undo:** every drop is one undo step ("Move Swatch" / "Copy Swatch").

## How the pieces fit

```
swatch cell ── DragGesture ─→ SwatchDragSession.begin ─→ NSView.beginDraggingSession
                                  │ sets AppModel.drag            (string + NSColor pasteboard item;
                                  │                                 move+copy in app, copy outside)
strip / header / placeholder ── .onDrop ─→ SwatchDropDelegate
     dropUpdated: SwatchDrag.operation → .move / .copy / .forbidden; StripSlot via layout.dropSlot
     performDrop: AppModel.dropDrag ─→ LibraryController.dropSwatch ─→ Library.move/copy/insertSwatch
                                        └ .duplicate(existing:) → AppModel.highlightedSwatch (ring)
session end (draggingSession(_:endedAt:)) / popover close ─→ AppModel.drag = nil
```

### Core (`SwatchDrag.swift`, test-driven)
- **`SwatchDragSource`** is what's dragged: `.palette(id, in: section)`, or `.history(Swatch)`.
  History isn't in the library, so a history drag carries the swatch itself.
- **`SwatchDrag.operation`** holds the move/copy/refuse rules in one place. The drop delegate uses
  it for the cursor and `dropSwatch` uses it for the action, so the two can't disagree.
- **`SwatchDrag.isUnchanged`** is true for a move into the swatch's own place: slot `i` or `i + 1`
  of its own section. That reuses `ListReorder.isNoOp` from palette reordering. `dropSwatch`
  returns `.unchanged` for it with no undo step, and the strip hides the insertion line.
- **`LibraryController.dropSwatch`** maps a drop onto `Library.moveSwatch`, `copySwatch` or
  `insertSwatch` (from history), as one `perform` step.
  - **Slots** count the destination's swatches before anything is removed, which is what the user
    sees. `moveSwatch` removes first, so within a section a later slot shifts down by one.
  - **Errors:** `Library`'s `.duplicate(existing:)` comes back as a result for the highlight.
    Locked and missing ids become `.refused`.
- **`SwatchStripLayout.dropSlot(at:)`** turns a pointer position into a slot.
  - Each section owns the strip up to the middle of the gaps around it, and the slot is the
    nearest boundary between its swatches.
  - **`insertionX(for:)`** draws the line on that boundary, or in the middle of the gap when the
    slot is at the edge next to another section.
- **`SectionID.init(palette:group:)`** is now public, so the app can build a section from an
  optional group id.

### App (`SwatchDragAndDrop.swift`, `PaletteListView`, `AppModel`, `PopoverView`)
- **Drag source.** A `DragGesture` (minimum distance 4 pt) on each cell notices the drag. It then
  calls `beginDraggingSession` on the popover's content view with `NSApp.currentEvent`.
  - `SwatchDragSession` is the `NSDraggingSource`. It allows `[.move, .copy]` within the app and
    `.copy` outside.
  - When the session ends, it clears `AppModel.drag`.
  - A static reference keeps the source alive for the length of the session.
  - The minimum distance keeps click-to-copy and the context menu working.
- **Pasteboard.** The item has the value as `.string`. It also has the `NSColor` as `.color`,
  written as the secure keyed archive `NSColor` itself writes; a scratch check confirmed the bytes
  match.
- **Drop targets** are `.onDrop(of: [.utf8PlainText])` with one delegate. The pointer goes through
  `dropSlot`, with the strip's scroll offset and inset applied. The header and placeholder always
  target slot 0 of the ungrouped section. Color History has no drop target.
- **Highlight.** `AppModel.highlightedSwatch` is set for about 1 s. The cell draws a white or black
  2 pt ring, whichever reads on the color.

## Decisions made during review
Getting drops working took three rounds, and each one explains a choice in the code:
1. **SwiftUI's `.onDrag` only allows copy on macOS.** The delegate proposed `.move` for plain
   drags. AppKit then failed the drop without calling `performDrop`, although the cursor and
   insertion line still showed.
2. **A drop from our own app gets an empty item provider** (`types=[]`, "Cannot load
   representation"). So the original idea of checking the dropped text against the expected value
   couldn't work. The drop relies on `AppModel.drag` alone, and the dropped item is never read.
3. **The + on every drop.** Proposing `.copy` everywhere made drops work but showed a + on moves.
   The user wanted no badge on moves, which needs a source that allows move. Hence the AppKit
   drag session started from a `DragGesture`, rather than `.onDrag`.
   - It also solves the problem of stale drag state: AppKit tells us when the session ends. An
     interim mouse-down monitor was removed.

Also decided with the user:
- Drop position in the strip stands in for "group header": groups have no headers, and empty groups
  can't be dropped on.
- Locked palettes copy on drag out.

## Not covered by automated tests
These were checked by hand in the running app:
- the drag session and the move/copy cursor;
- the insertion line;
- the header and placeholder targets;
- the duplicate ring;
- dragging into other apps.

## Follow-ups (out of scope)
- Auto-scrolling a strip or the list while dragging near an edge.
- Dragging several swatches at once.
- Drops from other apps.
- Dropping into empty groups.
