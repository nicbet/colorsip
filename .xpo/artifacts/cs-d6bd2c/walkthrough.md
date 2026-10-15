# cs-d6bd2c walkthrough: Palette and group management in the popover

## What was built
The popover can now manage the library, not just show it:
- **+** creates a palette at the top of the list.
- **Right-click a palette:** Rename, Edit Description, Set Icon, Lock/Unlock, New Group,
  Groups ▸, Duplicate and Delete.
- **Right-click a swatch:** Rename and Delete, plus its group's submenu.
- **Pick target:** the radio button toggles the target, and clicking a palette's name selects it.
- **Reordering:** dragging a palette's name reorders the palettes.
- **Undo:** Cmd+Z and Shift+Cmd+Z undo and redo every change.

Review also reworked how the popover looks:
- A light gray background (#E5E7E9 in light mode) and no separator lines.
- One white (or black) rounded container holding Color History and every palette.
- The popover's height fits its content.
- Swatch strips are 32 pt tall and spread out when they hold 16 swatches or fewer.
- Each strip segment has a faint border and a small shadow, so white swatches stay visible.

## How the pieces fit

```
PopoverView ── hidden Undo/Redo buttons → LibraryController.undo()/redo()
 └─ PaletteListView (sized to content, max 300 pt, then scrolls)
     ├─ HistoryRow
     ├─ PaletteRow ×n
     │    ├─ radio  → togglePickTarget        header tap → selectPickTarget
     │    ├─ header DragGesture → PaletteReorder → ListReorder → movePalette
     │    ├─ contextMenu ← PaletteMenuItem / GroupMenuItem
     │    ├─ SwatchStrip (SwatchStripLayout) → swatch menu ← SwatchMenuItem
     │    └─ .popover(item: AppModel.edit) → LibraryEditView
     └─ listContainer() (white/black panel)
StatusItemController ── PopoverBackgroundView (#E5E7E9 behind the frame view)
```

### Core (`ColorsipCore`, test-driven)
- **`LibraryCommands.swift`** adds one named, undoable command per menu action to
  `LibraryController`, such as `newPalette`, `renamePalette`, `togglePickTarget` and `moveGroup(by:)`.
  - The app makes one call per menu item, and the undo action names live in one place.
  - **No throwing.** A command that can't apply (a locked palette, or an id that's gone) returns
    `false` or `nil` and records no undo step. The UI already hides what isn't allowed, so a
    failure only happens in a race, such as an undo while a popover is open. Ignoring it is the
    right behavior there.
  - **Input rules:** names are trimmed and an empty name is ignored. A blank description becomes
    `nil`. New palettes and groups get numbered names ("New Palette 2"), compared
    case-insensitively by `Library.uniqueName`.
  - **Two pick-target commands.** The radio button toggles, which allows "none" (§7.1). Clicking
    the name only selects, so a stray click can't stop picks going to a palette.
- **`Library` changes**
  - `movePalette(_:before:)` is a convenience over `movePalettes(fromOffsets:toOffset:)`.
  - **Edits that change nothing no longer stamp `modifiedAt`.** Without this, renaming to the same
    name changed the timestamp, so `UndoableLibrary` recorded an undo step and the palette file
    was rewritten.
- **`LibraryMenus.swift`** describes the menus as data: `PaletteMenuItem`, `GroupMenuItem` and
  `SwatchMenuItem`, plus the predicates for when a delete asks first. The rules can be tested
  without SwiftUI:
  - A locked palette offers only Unlock.
  - Groups ▸ appears only when the palette has groups.
  - Move Left/Right are left out at the ends.
  - Color History and locked palettes only offer Copy as.
- **`PaletteIconInput.swift`**: `PaletteIcon.emoji(from:)` accepts exactly one emoji grapheme.
  - Skin tones, flags, ZWJ sequences and VS16 (❤️) count as one.
  - `#`, digits and `©` are refused. They have the Emoji property but aren't emoji on their own.
  - There's also a curated list of about 60 SF Symbols and a search over it.
- **`ListReorder.swift`**: the pure geometry of the drag.
  - The slot is the number of row midpoints above the pointer.
  - Dropping into the row's own slot, or the next one, does nothing.
- **`SwatchStripLayout`**
  - With 16 swatches or fewer, the segments share the width left after the gaps, so the strip
    fills exactly. Over 16, each segment is 1/16 of the width and the strip scrolls.
  - The cutoff counts swatches, not points, so a strip never flips between the two modes as the
    width changes.
  - `groupGap` is 6 pt.
  - `spec.md` §7.3 is updated to match.

### App (thin, checked by hand)
- **`AppModel.edit: LibraryEdit?`** is the single source of truth for the small edit popover.
  - Each `PaletteRow` binds `.popover(item:)` to it, but only while the edit belongs to its
    palette, so one popover shows at a time and it's anchored to the right row.
  - **+** and New Group… just set `edit` after creating the item, which opens Rename right away.
- **`LibraryEditView`** renders the edit:
  - text forms (Return saves, Esc cancels);
  - the delete confirmations (palette: Delete; group: Delete Colors / Move to Ungrouped);
  - the icon picker.
  If its target has disappeared, for example after an undo, it closes itself.
- **Drag to reorder** is an in-list `DragGesture` on the palette header, not a system drag.
  - The first version used `onDrag`/`DropDelegate` with an undeclared custom UTType, and it didn't
    work in the menubar popover.
  - Palettes never leave the popover, so a gesture is simpler and reliable.
  - Rows report their frames in a named coordinate space. `PaletteReorder` turns the pointer and
    the frames into a slot through `ListReorder`.
  - The list is lazy, so only rows on screen have frames. The slot is computed among those rows
    and mapped back to the full list.
  - A minimum distance of 4 pt keeps a plain click working as "select".
- **Undo/Redo** are invisible buttons with `.keyboardShortcut` in `PopoverView`, which is enough
  for the key equivalents while the popover is key.
- **Look:**
  - **List container:** `listContainer()` is one white or black rounded panel (radius 12).
    It reads the color scheme from the environment.
  - **Popover background:** `PopoverBackgroundView` is inserted behind the popover's frame view,
    so #E5E7E9 covers the arrow too. A SwiftUI background would leave the arrow in the system
    material. Dark mode keeps the system background.
  - **Popover height:** the list measures its content and sets its own height, up to 300 pt.
    The popover (`sizingOptions = .preferredContentSize`) shrinks to fit, which removed the empty
    space above the bottom bar.
  - **Strip segments:** each segment (the ungrouped section or a group) has a 1 pt
    `primary`-at-12% border and a soft shadow. The strip content is inset 2 pt so the scroll view
    doesn't clip the shadow.

## Decisions made during review
1. Each row got its own card at first; that looked busy, so one container holds the whole list.
2. New palettes go to the top, below Color History.
3. Clicking a palette's name selects it as the pick target.
4. The popover background is #E5E7E9, and the separator lines are gone.
5. Drag to reorder was rebuilt as an in-list gesture.
6. Color History lost its icon.
7. The popover's height fits its content.
8. Strips spread out to fill the width when they hold 16 swatches or fewer.
9. Strip segments got a border and a shadow, rounder corners (6 pt) and wider gaps (6 pt).

## Not covered by automated tests
The SwiftUI views were tested by hand in the running app:
- the menus, edit popovers and icon picker;
- dragging, the popover background and sizing;
- the undo keys.

## Follow-ups
- Picks don't go into the target palette yet. That's cs-995046, which this issue unblocks.
- The list doesn't auto-scroll while dragging a palette near its edge.
