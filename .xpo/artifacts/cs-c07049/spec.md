# cs-c07049 — Drag and drop of swatches

Refines `spec.md` §7.5 (drag and drop), §7.2 (refuse a duplicate and highlight the existing swatch),
§7.1 (locked palettes refuse drops) and §7.6 (undo).

## What
- Swatches can be dragged within the popover:
  - between palettes;
  - between the sections of a palette (the ungrouped section and its groups);
  - within a section, to reorder;
  - out of Color History.
- A plain drag **moves** the swatch and Option-drag **copies** it. A drag out of Color History or
  out of a locked palette always copies.
- **Drop targets:**
  - a palette's strip, where the pointer picks the section and the slot;
  - a palette's header (icon and name), which adds to the front of the ungrouped section;
  - the empty "Drop colors here" area, which adds to the ungrouped section.
- A drop that would duplicate a color in its section is refused, and the existing swatch briefly
  highlights. Locked palettes refuse drops.
- Dragging a swatch to another app gives the value as text in the active format, plus an `NSColor`.
- Every drop is one undoable step.

## Why
This is the last piece of palette management in the MVP popover. Picks land in one palette's
ungrouped section, so drag and drop is how users sort colors into groups and palettes. Dragging out
gets a value into an editor or a design tool without copy and paste.

## Scope
**In:** everything above.

**Out:**
- Drops from other apps (text or colors dragged into the popover). Such drops are ignored.
- Dragging several swatches at once.
- Auto-scrolling a strip, or the list, while dragging near an edge.
- Dropping into an empty group: empty groups aren't drawn in the strip.
- Group headers in the strip. "Group header" in `spec.md` §7.5 means the group's place in the
  strip (see Decisions); §7.5 is updated to say so.
- Drag and drop in the main window (V2).

## Design

### Core (`ColorsipCore`, test-driven)
1. **`SwatchDragSource`** (`SwatchDrag.swift`): what is being dragged.
   - `.history(Swatch)`: a Color History swatch. History isn't part of the library, so it carries
     the swatch itself.
   - `.palette(Swatch.ID, in: SectionID)`.
2. **`SwatchDrag.operation(for:onto:in:option:) -> SwatchDropOperation?`**
   - `SwatchDropOperation` is `.move` or `.copy`.
   - The arguments are the source, the destination palette's id, the library and whether Option
     is held.
   - Returns `nil` (refused) when the destination palette is locked or missing, or the source
     swatch no longer exists.
   - Returns `.copy` when the source is Color History, a locked palette, or Option is held.
     Otherwise it returns `.move`.
   - The drop delegate uses this for the cursor (move, copy or forbidden). The drop command uses
     it as well, so the two can't disagree.
3. **Drop position in a strip** (on `SwatchStripLayout`):
   - `dropSlot(at x: Double) -> StripSlot`, where `StripSlot` is `(group: SwatchGroup.ID?, index: Int)`.
     `x` is in content coordinates, so the app adds the scroll offset.
     - Each section owns the x range from the middle of the gap before it to the middle of the gap
       after it. The first section extends to −∞ and the last to +∞.
     - `index` is `round((x − section.x) / segmentWidth)`, clamped to `0…count`. That is the
       nearest boundary between swatches.
     - An empty layout gives `(nil, 0)`.
   - `insertionX(for: StripSlot) -> Double?`: where to draw the insertion line, at
     `section.swatchX(index)`. At the edge of a section next to another section (the start of a
     later one, or the end of an earlier one), the line sits in the middle of the gap. Returns
     `nil` for a section that isn't in the layout.
4. **`SwatchDrag.isUnchanged(_:onto:at:in:option:) -> Bool`**: whether a drop would be a move into
   the swatch's own place (slot `i` or `i + 1` of its own section). `dropSwatch` uses it for
   `.unchanged`, and the app uses it to hide the insertion line.
5. **`LibraryController.dropSwatch(_:onto:at:option:at:) -> SwatchDropResult`** (`SwatchDrag.swift`)
   - The arguments are the source, the destination `SectionID` and the `slot`. The slot is an index
     in the destination before anything is removed.
   - The results are `.moved(Swatch.ID)`, `.copied(Swatch.ID)`, `.unchanged`,
     `.duplicate(existing: Swatch.ID)` and `.refused`.
   - **Move** ("Move Swatch"):
     - Uses `Library.moveSwatch`, so the swatch keeps its id.
     - Within the same section, slot `i` or `i + 1` (the swatch's own place) returns `.unchanged`
       and records no undo step. Otherwise the slot is shifted down by one if it's after the
       swatch, since `moveSwatch` removes the swatch first.
   - **Copy** ("Copy Swatch"):
     - From a palette, uses `Library.copySwatch`.
     - From Color History, uses `insertSwatch` with the history swatch's color, name and
       description.
     - The copy gets a new id and new timestamps.
   - **Duplicate:** a `.duplicate` error from `Library` becomes `.duplicate(existing:)`, with
     nothing changed and no undo step. Moving a swatch within its own section never counts as a
     duplicate of itself.
   - **Refused:** when `operation` returns `nil`, or `Library` throws `.locked` or `.notFound`,
     the result is `.refused`, with nothing changed and no undo step.
6. **`SwatchDrag.payload(for:format:) -> String`**: the text a drag gives other apps,
   `format.string(for: color)`. The app also uses it to check a drop came from its own drag
   (see App).
7. **`SectionID.init(palette:group:)`** is public, so the app can build a section from an optional
   group id.

### App (thin, checked by hand)
- **Starting a drag:** each swatch cell in the strips (palettes and Color History) gets a
  `DragGesture` (minimum distance 4 pt, so a click still copies and right-click still opens the
  menu).
  - On its first change, it sets `AppModel.drag` to the `SwatchDragSource`. It then starts an
    AppKit drag session with `beginDraggingSession(with:event:source:)` on the content view of the
    current event's window (the popover), passing `NSApp.currentEvent` (the mouse-dragged event).
  - The pasteboard item holds the payload as `.string` and the `NSColor` as `.color`. The color is
    built from `displayP3Components` and written as a secure keyed archive, which is what `NSColor`
    itself writes. A scratch check confirmed the bytes match and that `NSColor(from:)` reads them
    back.
  - The drag image is a 24 pt rounded square in the swatch's color, centered on the pointer.
  - **Operations:** the source allows `[.move, .copy]` within the app and `[.copy]` outside it. So
    a drop into another app never removes the swatch.
  - When the session ends (`draggingSession(_:endedAt:operation:)`), `AppModel.drag` is cleared,
    whether the drop happened, was cancelled, or went to another app.
- **Why AppKit and not `.onDrag`:** the first version used SwiftUI's `.onDrag`. On macOS that
  source only allows copy. A drop target proposing move made AppKit fail the drop without calling
  `performDrop`, and proposing copy for every drop showed a + badge even on moves.
- **No custom UTType.** An undeclared custom type is what broke palette reordering (cs-d6bd2c).
  Also, SwiftUI hands a drop from this app an empty item provider. So the popover knows which
  swatch is dragged from `AppModel.drag`, kept in memory, and never reads the dropped item.
- **Drop targets** use `.onDrop(of: [.utf8PlainText], delegate:)`:
  - **Strip:** the pointer's x, plus the scroll offset, minus the inset, goes to `dropSlot`.
    While targeted, an accent-colored 2 pt line shows the slot across the strip's height. The line
    is hidden when the drop would be `.unchanged`.
  - **Palette header:** targets slot 0 of the ungrouped section. While targeted, the header gets a
    faint accent background.
  - **"Drop colors here" placeholder:** targets slot 0 of the ungrouped section. While targeted,
    its dashed border turns the accent color.
  - Color History isn't a drop target.
- **Drop delegate:**
  - `validateDrop` needs `AppModel.drag`. Without it (a drag from another app) the drop is refused.
  - `dropUpdated` reads Option from `NSEvent.modifierFlags` and returns the proposal from
    `SwatchDrag.operation`: `.move` (no badge), `.copy` (green +) or `.forbidden` (locked palette).
  - `performDrop` calls `dropSwatch` with `AppModel.drag` and clears it.
  - Closing the popover also clears `AppModel.drag`.
- **Duplicate highlight:**
  - On `.duplicate(existing:)`, `AppModel.highlightedSwatch` is set for about 1 s.
  - The strip draws a 2 pt ring on that swatch and fades it out. The ring is white or black,
    whichever reads on the color.
- **Drag to other apps** needs nothing more: the provider already has the text and the `NSColor`.
  A drag out never removes the swatch, even a plain one.
- **Undo:** drops go through `perform`, so the popover's Cmd+Z / Shift+Cmd+Z (cs-d6bd2c) already
  covers them.

## Acceptance criteria
- [ ] Dragging a swatch to another palette moves it there. With Option held it copies it, and the
      cursor shows a +.
- [ ] Dragging a swatch from one section to another in the same palette moves it. Option copies.
- [ ] Dragging within a section reorders. An insertion line shows the slot. Dropping in the
      swatch's own place changes nothing and records no undo step.
- [ ] Dragging out of Color History always copies. History doesn't change and isn't a drop target.
- [ ] Dragging out of a locked palette always copies. The palette doesn't change.
- [ ] Dropping onto a palette's header, or its "Drop colors here" area, adds to the front of the
      ungrouped section.
- [ ] Dropping onto a strip inserts at the slot under the pointer, in the section under the
      pointer. This also works after scrolling a long strip.
- [ ] A locked palette shows the forbidden cursor and refuses the drop.
- [ ] A drop that would duplicate a color in its section changes nothing. The existing swatch
      shows a ring for about a second.
- [ ] Dragging a swatch into TextEdit (or another text field) inserts its value in the active
      format. Dropping it on an `NSColor` target, such as a color well, gives the color.
- [ ] Each drop is one undo step ("Move Swatch" / "Copy Swatch"), and redo works. Changes are
      saved to `library.json`.
- [ ] Clicking a swatch still copies it, and palette reordering by the header still works.
- [ ] Core tests cover:
  - `SwatchDrag.operation`: history, locked source, Option, locked or missing destination,
    missing source;
  - `dropSlot` and `insertionX`: within a section, in the gaps, before the first, after the last,
    an empty layout;
  - `dropSwatch`: move between palettes, between sections and within a section (slot shifting);
    no-op slots; copy from a palette and from history; duplicates; locked destinations; missing
    ids; undo names; no undo step for refused or unchanged drops;
  - `isUnchanged`;
  - `payload`.

## Edge cases
- Moving the last swatch out of a palette leaves its "Drop colors here" area.
- Option-dragging a swatch within its own section is refused as a duplicate of itself, and it
  highlights.
- Moving a swatch to the pick target behaves like any other drop. Only picks follow the target.
- A swatch deleted (for example by undo) while it's dragged: the drop is `.refused` and nothing
  happens.
- The copy keeps the swatch's name and description. The move keeps the swatch as it is, id
  included.
- Dropping a swatch into another app activates that app, which closes the transient popover. This
  is expected.
- A drop between two groups lands in whichever section owns that half of the gap.

## Decisions
Confirmed by the user:
1. The drop position in the strip picks the section and the slot, and dropping on a palette's
   header adds to the front of the ungrouped section. There are no group headers, and empty groups
   can't be dropped on in the popover.
2. A drag out of a locked palette always copies, like Color History.
3. The drag is a system drag session, with the dragged swatch kept in memory rather than in a
   custom UTType.
4. Moves show no badge, and copies show + (review feedback). That needs an AppKit drag source
   started from a `DragGesture`, since SwiftUI's `.onDrag` only allows copy on macOS.

Agent decisions (flag if wrong):
5. ~~A drop's text is checked against the expected payload.~~ Dropped during review: SwiftUI hands
   a drop from this app an empty item provider, so the text can't be read. Instead,
   `AppModel.drag` is cleared when the drag session ends, so a stale drag can't be mistaken for a
   later drag from another app.
6. Copying from Color History is named "Copy Swatch" for undo, the same as copying from a palette.
7. The highlight is a ring on the swatch, not a flash of the whole strip, so it points at the one
   color.
