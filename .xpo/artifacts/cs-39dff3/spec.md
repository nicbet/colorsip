# Library model, on-disk storage, `.colorsip` DTCG format and undo

Refines `spec.md` §5.2, §7.1, §7.2, §7.6, §11. All logic lives in ColorsipCore. No app UI in this issue.

## What
A value-type library model (palettes → ungrouped section + groups → swatches) with its rules applied by mutating operations, a store that reads and writes the library folder (`library.json`, `palettes/<uuid>.colorsip`) atomically, the `.colorsip` DTCG serialization with its JSON Schema, and a snapshot-based undo/redo stack.

## Why
Every MVP palette issue (cs-a29255, cs-979715, cs-d6bd2c, cs-c07049, cs-995046, cs-7f6ead) builds on this model and storage.

## API sketch
```swift
public struct Swatch: Identifiable, Hashable, Sendable, Codable     // id, color, name, description?, createdAt, modifiedAt
public struct SwatchGroup: Identifiable, Hashable, Sendable           // id, name, swatches
public enum PaletteIcon: Hashable, Sendable { case emoji(String), symbol(String) }
public struct Palette: Identifiable, Hashable, Sendable              // id, name, description?, icon?, isLocked,
                                                                     // createdAt, modifiedAt, ungrouped: [Swatch], groups: [SwatchGroup]
public struct Library: Hashable, Sendable {                          // palettes (ordered), pickTarget: Palette.ID?
    // Palettes: createPalette, rename, setDescription, setIcon, setLocked, duplicate, delete, movePalettes, setPickTarget
    // Groups:   addGroup, renameGroup, moveGroup, deleteGroup(_:keepSwatches:)
    // Swatches: insertSwatch(color:name:description:into:index:), renameSwatch, setSwatchDescription, setSwatchColor,
    //           deleteSwatch, moveSwatch(_:from:to:index:), copySwatch(_:from:to:index:)
    // All are `mutating … throws(LibraryError)` and take the time of the change (`at:`, default `.now`).
    // A failed call leaves the library unchanged.
}
public struct SectionID { palette; group: SwatchGroup.ID? }       // .ungrouped(p), .group(g, in: p)
public enum LibraryError: Error { case locked(Palette.ID), duplicate(existing: Swatch.ID), notFound }
public struct UndoableLibrary { library; perform(_ actionName:, _ change:) ; undo(); redo(); canUndo/canRedo; undo/redoActionName; replace(with:) }
public struct LibraryStore { init(folder:); static var defaultFolder; load() -> LibraryLoadResult; save(_:previous:) throws;
                             load(_:from: LibraryFile) / save(_:to: LibraryFile) for history.json and settings.json }
public enum ColorsipPaletteFormat { encode(_ palette:) -> Data; decode(_ data:) throws(ColorsipFormatError) -> Palette }
```
`CSipColor` becomes `Codable` in the §5.1 shape (`colorSpace`, `components`, `alpha`, `hex`). `hex` is written but ignored on read.

## Rules
- **Swatch uniqueness**: within one section (the ungrouped section counts as a section), no two swatches may be perceptually equal (`isPerceptuallyEqual`, §5.1). Inserting, moving or copying a duplicate throws `.duplicate(existing:)` so the UI can highlight the existing swatch. The same color may appear in different groups. Each occurrence is its own swatch with its own id.
- **Locked palettes** refuse every change to their content or metadata: add, edit, remove, reorder, rename, icon, description, groups, delete, and moving swatches out. The exceptions are `setLocked(false)`, `duplicate` and copying swatches out. Moving a locked palette's position in the palette list is allowed, because that is a library-level change.
- **Pick target**: at most one, and it must be an existing palette. A locked palette can never be the target (the UI shows a closed lock instead of the radio button): `setPickTarget` refuses a locked palette, and locking the current target clears the pick target. Deleting the target clears it too. Undo restores both together.
- **Timestamps**: inserting or editing a swatch sets its `modifiedAt`. Any change to a palette's content or metadata sets the palette's `modifiedAt`. Every operation takes the time of the change as a parameter (so tests control it). Dates are rounded to milliseconds, so they round-trip through ISO 8601 exactly.
- **Duplicating a palette** inserts an unlocked copy named "<name> copy" right after the original. The copy, its groups and its swatches get new ids and the current time.
- **Deleting a group** with `keepSwatches: true` appends its swatches to the end of the ungrouped section. Swatches that would duplicate an existing ungrouped swatch are dropped.

## Library folder (§11.1)
```
<folder>/library.json            { "formatVersion": 1, "paletteOrder": [uuid…], "pickTarget": uuid|null }
<folder>/palettes/<uuid>.colorsip
```
- `save(new, previous:)` writes only what changed: changed palettes, `library.json` when the order or pick target changed, and deletes the files of removed palettes. Every write uses `Data.write(options: .atomic)`.
- `load()` on a missing folder returns an empty library (the folder is created on first save).
- `history.json` and `settings.json`: this issue adds only generic `load/save<T: Codable>(_ file:)` helpers for them, with the same atomic writes. Their contents belong to cs-979715 and cs-7f6ead.
- `defaultFolder` is `~/Library/Application Support/Colorsip/Library/`.

## `.colorsip` format (§11.2)
```json
{
  "$description": "Palette description",
  "$extensions": { "app.colorsip": {
      "formatVersion": 1, "id": "…", "name": "Brand", "icon": { "emoji": "🎨" }, "locked": false,
      "createdAt": "2026-10-14T10:00:00.000Z", "modifiedAt": "…",
      "order": ["Blue", "Neutrals"] } },
  "Blue": {
    "$type": "color",
    "$value": { "colorSpace": "display-p3", "components": [0.2364, 0.2353, 0.8588], "alpha": 1, "hex": "#3c3cdb" },
    "$description": "optional",
    "$extensions": { "app.colorsip": { "id": "…", "name": "Blue", "createdAt": "…", "modifiedAt": "…" } }
  },
  "Neutrals": {
    "$extensions": { "app.colorsip": { "id": "…", "name": "Neutrals", "order": ["Gray"] } },
    "Gray": { "$type": "color", … }
  }
}
```
- Ungrouped swatches are top-level tokens. Each group is a top-level DTCG group. Tokens are told apart from groups by the presence of `$value`.
- **Token and group keys** come from the names: `{`, `}` and `.` are replaced by `_`, a leading `$` is dropped, an empty name becomes `Color`, and collisions within a level get ` 2`, ` 3`, …. The real name is kept in `$extensions` and wins on read.
- **Order** is stored as `order` (a list of keys) at the root and in each group, because JSON object order is not significant. The root `order` lists the ungrouped tokens first, then the groups.
- Output is deterministic (`.prettyPrinted, .sortedKeys, .withoutEscapingSlashes`), so sync diffs (V3) stay small.
- Schema: `schema/colorsip-palette.schema.json`, JSON Schema 2020-12, with `$defs` for color value, token and group. It requires the root `app.colorsip` metadata, including `formatVersion`.
- **`formatVersion` lives in the root `$extensions["app.colorsip"]`** (user decision), not at the top level, so every non-`$` key in the file is a valid DTCG token or group. `spec.md` §11.2 is updated to match.

## Undo (§7.6)
- `UndoableLibrary.perform("Rename Palette") { try $0.renamePalette(…) }` snapshots the library before the change. If the closure throws, nothing changes and nothing is recorded. A successful change clears the redo stack. The stack keeps 100 levels.
- Snapshot-based (the library is a value type with copy-on-write arrays), not `UndoManager`. It is plain, Sendable and testable. The UI issues bind Cmd+Z and Shift+Cmd+Z to it, because the popover's non-activating panel makes the responder-chain `UndoManager` unreliable.
- Color History isn't part of `Library`, so undoing a pick leaves history alone, as §7.6 requires.

## Edge cases
- HIGH: **A newer `formatVersion`** than supported, in `library.json` or a palette file, is refused: the palette isn't loaded, and its file is never overwritten or deleted. `load()` reports it in `LibraryLoadResult.issues`.
- HIGH: **A corrupt or unreadable palette file** is reported and skipped, and its file is left untouched. `save` never deletes files of palettes it didn't load.
- MEDIUM: A palette file that isn't listed in `paletteOrder` is appended at the end. An id in `paletteOrder` with no file is dropped. This helps V3 sync.
- MEDIUM: A `pickTarget` that points to a missing palette is cleared on load.
- LOW: Atomic writes leave no partial files. The file name's UUID must match the id inside the file; on a mismatch, the id inside the file wins.

## Acceptance criteria
- [x] Model and every operation are covered by tests, including uniqueness (insert/move/copy), lock refusal per operation, pick target rules, group deletion both ways, and timestamps.
- [x] Encoding a palette and decoding it gives an equal palette (round trip), including odd names (`.`, `{}`, `$`, duplicates, empty, emoji) and order.
- [x] Every encoded palette in the tests validates against `schema/colorsip-palette.schema.json`. Hand-written invalid files fail validation.
- [x] Store: load/save round trip in a temp folder, minimal writes, deletion of removed palettes, the edge cases above.
- [x] Undo/redo: perform, undo, redo, a failed change isn't recorded, redo is cleared by a new change, the 100-level limit.
- [x] `swift test` passes; the app still builds.

## Decisions
1. **Snapshot undo in Core, not `UndoManager`** (see Undo).
2. **Names as DTCG keys, with the real name and order in `$extensions`**, not UUID keys. Files stay readable and useful in DTCG tools.
3. **Schema validation without dependencies** (user decision). A small JSON Schema validator in the test target (`TestSupport/SchemaValidator.swift`) supports only the 2020-12 keywords the schema uses: `$ref`/`$defs`, `type`, `properties`, `required`, `additionalProperties`, `patternProperties`, `propertyNames`, `items`, `minItems`/`maxItems`, `enum`, `const`, `pattern`, `minimum`/`maximum`, `oneOf`/`anyOf`, and `not`. An unknown keyword in the schema fails the test, so the schema can't silently use something the validator ignores. The validator has its own tests. No SwiftPM, Python or Node dependency.
4. **No app wiring in this issue.** cs-a29255 loads the library into `AppModel` and shows it.
