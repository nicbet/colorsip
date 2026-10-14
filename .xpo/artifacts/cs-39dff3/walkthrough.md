# Walkthrough: library model, storage, `.colorsip` format and undo

All of this lives in ColorsipCore. The app doesn't use it yet: cs-a29255 loads the library into `AppModel`.

## The pieces

| File | Role |
|---|---|
| `Sources/ColorsipCore/Library.swift` | The model (`Swatch`, `SwatchGroup`, `PaletteIcon`, `Palette`, `SectionID`, `LibraryError`) and `Library`, which owns every rule |
| `Sources/ColorsipCore/UndoableLibrary.swift` | Undo and redo around `Library` |
| `Sources/ColorsipCore/ColorsipPaletteFormat.swift` | `.colorsip` DTCG encoding and decoding; `Codable` for `CSipColor` and `PaletteIcon`; the shared JSON encoder and decoder |
| `Sources/ColorsipCore/LibraryStore.swift` | The library folder: `library.json`, `palettes/<uuid>.colorsip`, `history.json`, `settings.json` |
| `schema/colorsip-palette.schema.json` | The published JSON Schema 2020-12 for `.colorsip` |
| `Tests/.../SchemaValidator.swift` | A dependency-free validator for the schema's keywords, used by the tests |

## How the model enforces the rules

`Library` is a value type whose `palettes` and `pickTarget` are `private(set)`. The only way to change them is through its `mutating … throws(LibraryError)` methods, so the rules can't be bypassed:

- **Locked palettes.** Almost every palette change goes through the private `editPalette(_:at:_:)`. It throws `.locked` first, works on a **copy** of the palette and stores the copy back only if the closure succeeds. That copy is what makes every failed call leave the library unchanged. It also sets `modifiedAt`. The exceptions are deliberate: `setLocked`, `duplicatePalette`, `movePalettes` (a palette's position isn't its content) and the source side of `copySwatch`.
- **Uniqueness.** `[Swatch].insertUnique` and `duplicate(of:excluding:)` use `CSipColor.isPerceptuallyEqual` (ΔEOK < 0.002) within one section. The ungrouped section counts as a section. The error carries the existing swatch's id so the UI can highlight it (§7.2).
- **Pick target.** `init` drops a target that is missing or locked. `setPickTarget` refuses locked palettes. `setLocked(true)` and `deletePalette` clear the target. The user decided that a locked palette can never be the target: the UI shows a lock instead of the radio button.
- **Sections** are addressed by `SectionID` (`.ungrouped(p)` or `.group(g, in: p)`), so one set of swatch methods serves both kinds.
- **Moving between palettes** edits a copy of the whole library (`var library = self … self = library`). If inserting into the destination fails, the removal from the source is discarded too.

Timestamps are passed in (`at:`, default `.now`) rather than read from a clock, so tests are deterministic. `Date.libraryTimestamp` rounds them to milliseconds, the precision of the files, so a palette compares equal after a save and reload. Rounding is used rather than truncation because parsing can land a hair below the stored value, and truncating that would drift by 1 ms.

## Undo

`UndoableLibrary.perform(name) { … }` runs the change on a draft. If the change throws, the draft is discarded. If it leaves the library equal, nothing is recorded. Otherwise the previous library is pushed as a snapshot and the redo stack is cleared. Snapshots are cheap because `Library` is made of copy-on-write arrays. `perform` is generic over the error type, so non-throwing changes don't need `try`. The stack keeps 100 levels; older ones are dropped.

Why not `UndoManager`: the popover is a non-activating panel, so the responder-chain undo manager is unreliable there, and a plain struct is `Sendable` and easy to test. The UI binds Cmd+Z and Shift+Cmd+Z to it. Color History lives outside `Library`, so undoing a pick leaves history alone, as §7.6 requires.

## The `.colorsip` format

A palette is a DTCG root group:
- Ungrouped swatches are top-level `$type: "color"` tokens. Groups are top-level DTCG groups, and a group contains only tokens (groups don't nest).
- **Keys** come from names (`KeyAllocator`): `{`, `}` and `.` become `_`, leading `$` are dropped, an empty name becomes `Color` or `Group`, and collisions get ` 2`, ` 3`, …. The real name is stored in `$extensions["app.colorsip"].name` and wins on read, so names round-trip exactly.
- **Order** is stored as `order` (a list of keys), because JSON object order isn't meaningful. The encoder uses `.sortedKeys`, so output is byte-for-byte deterministic, which keeps the V3 sync diffs small. On read, keys missing from `order` come after the listed ones, sorted.
- **`formatVersion`** is in the root `$extensions["app.colorsip"]` (user decision), so every non-`$` key in the file is a valid DTCG token or group. `decode` reads only the version first (`VersionProbe`) and throws `.newerFormat` before trying the full shape, which may have changed in a newer version.
- Colors use the §5.1 shape through `CSipColor: Codable`. `hex` is written but ignored on read, and a missing `alpha` means opaque.

The coding is done with `Codable` and a free-form `Key: CodingKey`, rather than a generic JSON tree, so it reuses the model's `Codable` conformances. Dates use ISO 8601 with milliseconds (`JSONEncoder.library` / `JSONDecoder.library`, which the store also uses).

## The store

- `load()` never throws. It returns a `LibraryLoadResult` with the library and a list of `issues`. Each palette file is decoded on its own. Corrupt files (`.unreadable`) and files from a newer Colorsip (`.newerFormat`) are skipped and reported. Because those palettes aren't in the library, `save` never writes or deletes their files. A `library.json` from a newer version is likewise reported and never overwritten (`indexIsNewer()`).
- Ordering: palettes come in `paletteOrder` order, ids without a file are dropped, and files missing from the order are appended oldest first. A pick target that is missing or locked is cleared by `Library.init`. Only `<uuid>.colorsip` files are loaded, so V3 conflict copies and stray files are ignored. If a file's name and the id inside it differ, the id inside wins; if two files hold the same id, the first in file-name order wins.
- `save(new, previous:)` diffs against `previous`. It writes changed palettes, deletes the files of removed palettes, and rewrites `library.json` only if the order or the pick target changed. Pass `previous: nil` to write everything. All writes use `.atomic`.
- `load(_:from:)` and `save(_:to:)` read and write `history.json` and `settings.json` for cs-979715 and cs-7f6ead.

## Schema validation without dependencies

The user asked to avoid a test-only package. `SchemaValidator` implements only the keywords the schema uses (`$ref`/`$defs`, `type`, `properties`, `patternProperties`, `additionalProperties`, `required`, `items`, `min/maxItems`, `enum`, `const`, `pattern`, `minimum`/`maximum`, `oneOf`/`anyOf`/`not`, `propertyNames`). Its constructor **throws on any other keyword**. If someone later adds, say, `format` or `unevaluatedProperties` to the schema, the tests fail instead of silently skipping that check. `SchemaValidatorTests` covers the validator itself.

## Tests

`LibraryTests` (rules per operation, including a table of every change a locked palette must refuse), `UndoableLibraryTests`, `PaletteFormatTests` (round trip with awkward names, DTCG shape, determinism, newer or invalid files, schema validation of valid and invalid documents), `LibraryStoreTests` (temp-folder round trip, minimal writes, the edge cases above) and `SchemaValidatorTests`. A mutation check during development confirmed the lock tests fail when the lock guard is removed.
