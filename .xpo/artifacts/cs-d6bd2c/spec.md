# cs-d6bd2c — Palette and group management in the popover

Refines `spec.md` §3.1 (toolbar +, palette and swatch context menus, list look), §7.1 (palettes),
§7.2 (groups), §7.3 (strip layout) and §7.6 (undo, Cmd+Z wiring deferred from cs-a29255).

## What
Users can manage palettes and groups from the popover:
- **+** creates a palette at the top of the list.
- Right-clicking a palette offers Rename, Edit Description, Set Icon, Lock/Unlock, New Group,
  Groups ▸, Duplicate and Delete.
- Right-clicking a swatch adds Rename and Delete.
- Palette rows can be reordered by dragging.
- The pick target can be chosen by clicking the radio button or the palette's name. The radio
  button can also clear it.
- Cmd+Z and Shift+Cmd+Z undo and redo in the popover.

The look also changes:
- The popover background is a light gray (#E5E7E9) in light mode.
- The whole list (Color History and every palette) sits in one rounded container: white with
  black text in light mode, black with white text in dark mode.
- There are no separator lines between the toolbar, the list and the bottom bar.
- The popover's height fits its content, so the bottom bar sits right below the container.
- Row labels are small (12 pt). Color History has no icon.
- Swatch strips are 32 pt tall. With 16 swatches or fewer they spread out to fill the width.
- Strip segments (the ungrouped section and each group):
  - are rounded with a 6 pt radius and sit 6 pt apart;
  - have a faint grey border and a subtle shadow, so white or black swatches stay visible
    against the container.

## Why
The library model (cs-39dff3) already supports every operation, but the popover can only show
palettes. Drag and drop (cs-c07049), the editor (cs-722793) and pick routing (cs-995046) need palettes
the user can create and manage.

The container gives colors a neutral, solid background to judge them against. One container reads
calmer than a card per row.

## Scope
**In:** everything in the issue checklist, plus:
- the undo/redo keys in the popover;
- the popover background, separators and height;
- the list container;
- the label and placeholder fonts;
- the strip height, spreading, rounding, gaps, border and shadow;
- clicking a name to select its palette.

**Out:**
- Swatch Edit… → cs-722793.
- Dragging swatches and dropping onto groups → cs-c07049.
- Export from a locked palette → V2.
- Main-window management → V2.
- Auto-scrolling the list while dragging a palette near its top or bottom edge.

## Design

### Core (`ColorsipCore`, test-driven)
1. **`LibraryController` commands** (`LibraryCommands.swift`). These are named, undoable operations,
   so the app only calls one method per menu item. Each goes through `perform` with the action name
   shown in parentheses.
   - `newPalette(at:) -> Palette.ID` ("New Palette")
     - Inserts a palette at the top of the list, named "New Palette", or "New Palette 2", 3, … if
       the name is taken.
   - `renamePalette(_:to:)` ("Rename Palette")
   - `setDescription(_:of:)` ("Edit Description")
   - `setIcon(_:of:)` ("Set Icon")
   - `setLocked(_:palette:)` ("Lock Palette" / "Unlock Palette")
   - `duplicatePalette(_:)` ("Duplicate Palette")
   - `deletePalette(_:)` ("Delete Palette")
   - `movePalette(_:before:)` ("Move Palette"): the target is another palette's id, or `nil` for
     the end.
   - `togglePickTarget(_:)` ("Set Pick Target"), used by the radio button: makes the palette the
     target, or clears the target if it already is.
   - `selectPickTarget(_:)` ("Set Pick Target"), used by clicking the name: makes the palette the
     target. If it already is, nothing changes and no undo step is recorded.
   - `newGroup(in:) -> SwatchGroup.ID` ("New Group")
     - Appends a group named "New Group", or "New Group 2", … if the name is taken in that palette.
   - `renameGroup(_:in:to:)` ("Rename Group")
   - `moveGroup(_:in:by:)` ("Move Group"): `by` is −1 for left or +1 for right. A move past either
     end does nothing.
   - `deleteGroup(_:in:keepSwatches:)` ("Delete Group")
   - `renameSwatch(_:in:to:)` ("Rename Swatch")
   - `deleteSwatch(_:in:)` ("Delete Swatch")
   - **Text input rules:**
     - Names are trimmed. An empty name is ignored, so the old name stays.
     - A description is trimmed, and an empty one becomes `nil`.
   - **Errors:**
     - A command on a locked palette, or on an id that no longer exists, leaves the library
       unchanged and records no undo step.
     - Commands return `Bool` or an optional id, and don't throw. The UI already hides what isn't
       allowed.
2. **`Library.movePalette(_:before:)`**: a convenience over `movePalettes(fromOffsets:toOffset:)`.
   Moving a palette before itself, into its current place, or before an unknown id changes nothing.
3. **`Library.uniqueName(_:among:)`** (internal helper): returns "Base", or "Base 2", "Base 3", …,
   whichever is the first not in the list. Names are compared case-insensitively.
4. **Edits that change nothing** don't stamp `modifiedAt`, on the palette or the swatch. So
   renaming to the same name leaves the library equal and records no undo step.
5. **Menus as data** (`LibraryMenus.swift`). The visibility rules can be tested without SwiftUI.
   - `PaletteMenuItem.items(for: Palette)`:
     - A locked palette gets `[.unlock]`.
     - An unlocked palette gets `[.rename, .editDescription, .setIcon, .lock, .newGroup, .groups,
       .duplicate, .delete]`. `.groups` is left out when the palette has no groups.
   - `GroupMenuItem.items(for: group, in: Palette)` gives `[.rename, .moveLeft, .moveRight, .delete]`.
     - `moveLeft` is left out for the first group and `moveRight` for the last.
     - A locked palette or a missing group has no items.
   - `SwatchMenuItem.items(in: group, of: Palette?)`:
     - Every swatch gets `[.copyAs]`.
     - A swatch in an unlocked palette also gets `.rename` and `.delete`, plus `.group` when it's in
       a group.
     - Color History passes `nil`, so its swatches only get `.copyAs`.
   - **Confirmation predicates:**
     - `Palette.deletionNeedsConfirmation`: true when the palette has any swatch.
     - `SwatchGroup.deletionNeedsChoice`: true when the group isn't empty.
6. **Icons** (`PaletteIconInput.swift`)
   - `PaletteIcon.emoji(from: String) -> PaletteIcon?`
     - Trims the input and accepts exactly one grapheme that is an emoji, such as 🎨, 👍🏽, 🇨🇦, 👩‍🎨
       or ❤️.
     - It rejects:
       - plain letters and digits;
       - characters that only have an emoji variant (`#`, `*`, `©`);
       - input with more than one grapheme;
       - empty input.
   - `PaletteIcon.curatedSymbols: [String]`: about 60 SF Symbol names suited to palettes, such as
     paintpalette, swatchpalette, star, heart, leaf and drop.
   - `PaletteIcon.symbols(matching query:)`: the curated symbols that contain the query,
     case-insensitively. An empty query returns all of them.
     The app also drops names that `NSImage(systemSymbolName:)` can't load, so an older OS doesn't
     show blank cells.
7. **Reorder geometry** (`ListReorder.swift`). These are pure functions, so the drop position can
   be tested without SwiftUI.
   - `ListReorder.insertionIndex(at y:, midpoints:) -> Int`: the slot (0…count) a row dropped at `y`
     goes into. It's the number of rows whose vertical midpoint is above `y`. The midpoints are in
     list order.
   - `ListReorder.isNoOp(moving:to:) -> Bool`: true when slot `to` is the dragged row's own slot or
     the one right after it, so the order wouldn't change. No insertion line is shown and nothing
     moves.
   - `ListReorder.move(_:to:in:) -> Move?`: the move to make. Its `before` is the id at the slot,
     or `nil` for the end, and becomes the argument to `movePalette`. It returns `nil` for a no-op
     or an unknown id.
8. **Strip layout** (`SwatchStripLayout`, which changes `spec.md` §7.3).
   - The gap between sections, `groupGap`, is 6 pt (was 4 pt).
   - With 16 swatches or fewer in total, segments spread out to fill the width exactly:
     `segmentWidth = (width − gaps) / count`, where `gaps` is `groupGap` × (sections − 1). The
     strip doesn't scroll.
   - With more than 16 swatches, segments stay at `width / 16` and the strip scrolls, as before.
   - The cutoff counts swatches, not points, so a strip never switches between the two modes as
     the width changes.
   - Color History uses the same layout, so it spreads too.
   - If the gaps alone are wider than the strip, the segment width is 0, never negative.

### App (thin, checked by hand)
- **Popover background:**
  - Light mode is #E5E7E9, so the white list container stands out. Dark mode keeps the system
    popover background.
  - The color fills the popover's frame view, arrow included. It's a dynamic `NSColor` in a
    view behind the hosting view; a SwiftUI background would leave the arrow in the system
    material.
- **No separators:**
  - The popover has no divider lines between the toolbar and the list, or between the list and the
    bottom bar.
  - The container is 10 pt from the format menu above and from the bottom bar below.
- **Popover height:**
  - The popover is 320 pt wide, and its height fits its content.
  - The list's scroll view is exactly as tall as its content, up to 300 pt, and scrolls beyond
    that. The content height is measured with `onGeometryChange`.
  - Adding or removing palettes resizes the popover.
- **List container:**
  - Color History and all palette rows sit in one rounded container (corner radius 12). It has
    10 pt of inner padding and a 10 pt horizontal margin to the popover edges.
  - The container is white in light mode and black in dark mode, and its text is black or white to
    match. The lock and palette symbols use the secondary style on top of that.
  - Rows inside have no backgrounds of their own and are 14 pt apart.
- **Color History row**: just the "Color History" label above its strip, with no icon. The label
  starts at the container's left edge.
- **Fonts:**
  - Row labels (the "Color History" title and palette names) are 12 pt.
  - Placeholder text ("Drop colors here", "Picked colors appear here") uses the body font.
  - The "No palettes yet" hint also uses the body font.
- **Strips:**
  - Swatches and the dashed placeholder are 32 pt tall.
  - Each strip segment (the ungrouped section and each group) is rounded with a 6 pt corner radius
    (was 4 pt). The dashed placeholder uses the same radius.
  - Each segment has a 1 pt border inside its edge. The border is the primary color at 12%
    opacity: faint grey on white, faint light grey on black.
  - Each segment also has a subtle shadow (black at 15% opacity, radius 1.5, y offset 0.5).
  - The strip's scroll content is inset 2 pt on every side so the shadow isn't clipped. Swatches
    stay 32 pt tall; the layout gets the width minus the inset.
- **+ (toolbar)** calls `newPalette`. The new palette appears at the top, right below Color History
  (which always stays first), and its Rename popover opens.
- **Palette context menu**: on the whole row, including the empty "Drop colors here" target. It's
  built from `PaletteMenuItem.items`.
  - Rename…, Edit Description… and Set Icon… open a small popover anchored to the row:
    - Rename and Edit Description show a text field with Cancel and Save. Return saves and Esc
      cancels.
    - Set Icon shows the icon picker.
  - Lock / Unlock act at once.
  - New Group… creates the group, then opens its Rename popover.
  - Groups ▸ has one submenu per group: Rename…, Move Left, Move Right and Delete….
  - Duplicate acts at once.
  - Delete asks first when `deletionNeedsConfirmation`: "Delete “Name”? This deletes its N
    colors." It offers Delete (destructive) and Cancel. Otherwise it deletes at once.
- **Group delete** in a non-empty group asks "Delete group “Name”?" with three choices: Delete
  Colors, Move Colors to Ungrouped, Cancel. An empty group is deleted at once.
- **Swatch context menu**: Copy as ▸, then Rename… and Delete as `SwatchMenuItem` allows.
  - A swatch in a group also shows that group's submenu ("Group “Name” ▸"). This item is hidden
    for locked palettes and Color History.
  - Swatch Rename… opens the same text popover, anchored to the row.
  - Swatch Delete acts at once.
- **Edit popover state**: `AppModel.edit: LibraryEdit?`. Each row shows the popover only while the
  edit belongs to its palette.
- **Icon picker** (popover):
  - An emoji field. It takes a single emoji, validated through `PaletteIcon.emoji(from:)`; a
    smiley button opens the system Character Viewer.
  - A search field over a grid of curated SF Symbols.
  - A "No Icon" button.
  - The current icon is highlighted. Choosing an icon applies it and closes the picker.
- **Radio button**: clicking it calls `togglePickTarget`, so clicking the current target clears it.
  Locked palettes keep showing the lock instead.
- **Clicking the name**: clicking the palette's header (icon and name) calls `selectPickTarget`, so
  the radio button becomes selected. For a locked palette nothing happens.
- **Reorder by dragging.** This replaces a first attempt that used a system drag session with an
  undeclared custom UTType, which didn't work in the popover.
  - It's handled entirely inside the list with a SwiftUI `DragGesture` on the palette header
    (minimum distance 4 pt, so a click still selects).
  - Rows report their frames in a named coordinate space on the list content. The pointer's y
    and the rows' midpoints go through `ListReorder`.
  - The list is lazy, so only rows on screen report frames. The slot is computed among those rows
    and mapped back to an index in the full list.
  - While dragging, the dragged row is dimmed (opacity 0.4). An accent-colored insertion line
    shows the slot, centered in the gap between rows.
  - Releasing calls `movePalette(_:before:)` as one undoable "Move Palette" step. A no-op slot does
    nothing.
  - Color History isn't draggable, and slot 0 is above the first palette, never above Color
    History.
  - The state lives in `PaletteReorder`: the dragged id, the pointer y and the row frames.
- **Undo/Redo**: the popover has hidden buttons with `.keyboardShortcut("z")` and
  `.keyboardShortcut("z", modifiers: [.command, .shift])`. They call `library.undo()` and `redo()`,
  and are disabled when there is nothing to undo or redo.
- **Popover closing**: the transient popover must stay open while a child popover or menu is up.
  This needs a check by hand.

## Acceptance criteria
- [ ] + creates "New Palette" (numbered if the name is taken) at the top, below Color History, and
      opens Rename. The new palette is saved.
- [ ] The popover background, arrow included, is #E5E7E9 in light mode.
- [ ] No separator lines between the toolbar, the list and the bottom bar.
- [ ] The popover's height fits its content. The bottom bar sits 10 pt below the container, and
      the list scrolls once it is taller than 300 pt.
- [ ] Color History and all palettes sit in one container with a corner radius of 12. It's white
      with black text in light mode and black with white text in dark mode.
- [ ] Color History shows its label without an icon.
- [ ] Row labels are 12 pt. Placeholder text uses the body font.
- [ ] Swatch strips and the empty placeholder are 32 pt tall.
- [ ] A strip with 16 swatches or fewer fills its width exactly, groups and gaps included. Over 16
      it scrolls.
- [ ] Strip segments have a 6 pt corner radius and sit 6 pt apart.
- [ ] Every strip segment has a faint grey border and a subtle shadow. A white swatch at the end
      of a strip is clearly visible against the white container.
- [ ] Unlocked palette context menu: Rename…, Edit Description…, Set Icon…, Lock, New Group…,
      Groups ▸ (only with groups), Duplicate, Delete.
- [ ] Locked palette context menu: only Unlock.
- [ ] Rename and description edits trim whitespace. An empty name is ignored, and an empty
      description is cleared.
- [ ] Icon picker sets an emoji or SF Symbol, or clears the icon. Invalid emoji input is refused.
- [ ] Dragging a palette's header up or down shows an insertion line. Releasing moves the palette
      there; it's undoable and saved to `library.json`.
- [ ] Groups can be created, renamed, moved left or right, and deleted.
- [ ] Deleting a non-empty group offers Delete Colors or Move to Ungrouped. Moved swatches that
      duplicate an ungrouped one are dropped, as `Library` does.
- [ ] Swatch context menu shows Rename… and Delete only in unlocked palettes, never in Color
      History.
- [ ] Clicking the selected radio button clears the pick target. Locking the target clears it too.
- [ ] Clicking an unlocked palette's name makes it the pick target. Clicking it again keeps it.
- [ ] Deleting a palette with swatches asks first. An empty palette is deleted at once.
- [ ] Cmd+Z and Shift+Cmd+Z in the popover undo and redo every change above.
- [ ] Core tests cover:
  - the commands: effects, action names, no-ops on locked or missing ids, input trimming;
  - unique names, `movePalette(_:before:)` and no-op edits;
  - menu items and the confirmation predicates;
  - emoji and symbol input;
  - `ListReorder`, strip spreading and the group gap.

## Edge cases
- Renaming to whitespace only keeps the old name and records no undo step.
- Renaming to the same name records no undo step.
- "New Palette 2" is used when "new palette" exists, since names are compared case-insensitively.
- Dropping a palette onto its own slot, or the slot right after it, changes nothing.
- Dragging above the first palette gives slot 0. Dragging below the last gives the end slot.
- Deleting the pick target clears the radio button.
- Duplicating a locked palette isn't offered in the popover (§3.1), although `Library` allows it.
- Emoji input: "🎨🎨" and "a" are refused, and " 🎨 " is accepted. A skin-tone or flag sequence is
  one grapheme and is accepted.
- An edit popover whose palette, group or swatch was deleted in the meantime (for example by
  undo) closes without changing anything.
- One swatch fills the whole strip.
- 16 swatches split across groups fit exactly and don't scroll. This replaces the old behavior,
  where 8 + 8 scrolled by one gap.
- A white swatch on the white container, or a black one on the black container, is outlined by
  the border.

## Decisions
Confirmed by the user:
1. Groups are managed through a Groups ▸ submenu in the palette menu and through the group's
   submenu in a swatch's menu. Groups are reordered with Move Left/Right, not by dragging.
2. Text edits use a small anchored popover with Cancel and Save.
3. Only deleting a non-empty palette asks first. Swatches and empty palettes are deleted at once;
   undo covers mistakes.
4. The icon picker has an emoji field (plus the Character Viewer), a searchable curated SF Symbol
   grid and No Icon.
5. Clicking the selected radio button clears the pick target (§7.1 "exactly one, or none").
6. New palettes go to the top of the list, below Color History, and don't become the pick target.
7. Group names don't have to be unique; only the default "New Group" is numbered.
8. Swatch strips are 32 pt tall (review feedback, was 20 pt).
9. One white or black container holds the whole list, following the system appearance (review
   feedback). A card per row was tried first and looked too busy.
10. Row labels are 12 pt; placeholder text uses the body font (review feedback).
11. Clicking a palette's name selects it as the pick target (review feedback).
12. The popover background is #E5E7E9 in light mode (review feedback).
13. Palettes are reordered by dragging their header (review feedback).
14. The container's corner radius is 12 pt, up from 8 (review feedback).
15. The popover has no separator lines, so it reads as one surface (review feedback).
16. Color History has no icon (review feedback).
17. No empty space between the container and the bottom bar (review feedback).
18. Strips with fewer than 16 swatches spread out evenly to fill the width (review feedback).
19. Strip segments get a faint grey border and a subtle shadow, so light swatches don't disappear
    into the container (review feedback).
20. Strip segments are rounder (6 pt, was 4 pt) and 6 pt apart (was 4 pt) (review feedback).

Agent decisions (flag if wrong):
21. Color History sits inside the container too, as the first row, since it's part of the list.
22. Clicking the name only selects; it never clears. Only the radio button clears the target, so a
    stray click on the name can't silently stop picks going to a palette.
23. Dark mode keeps the system popover background. Only a light-mode color was given.
24. Reordering uses an in-list `DragGesture` rather than a system drag session. Palettes never
    leave the popover, so pasteboard types and drop delegates aren't needed. Swatch drags to other
    apps (cs-c07049) will still use the system drag session.
25. The empty space is removed by sizing the popover to its content, rather than by keeping a fixed
    height and moving the bottom bar up, which would leave the space below it. The list grows up
    to 300 pt, which keeps the popover near its old 420 pt maximum.
26. Spreading also applies at exactly 16 swatches split across groups, so they fit without
    scrolling. It applies to Color History too.
27. The border and shadow go on each segment (ungrouped section and each group), not around the
    whole strip, so the groups still read as separate pieces.
