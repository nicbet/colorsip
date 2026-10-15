# Starter Palettes settings catalog

## What was built

Colorsip now has an MVP-visible **Settings → Palettes** pane. Its first collection is the pinned Tailwind CSS v4.1.18 palette set: 22 classic color families, each with shades 50 through 950.

Each row shows a compact shade preview and either **Add** or **Added**. **Add All** installs every missing family in catalog order and becomes disabled when the full collection is present. A source link and MIT attribution are shown beneath the collection.

Nothing is installed automatically. The user chooses individual palettes or the whole collection.

## How the pieces fit together

### Bundled source data

ColorsipCore bundles Tailwind's official v4.1.18 `theme.css` and the upstream MIT license as Swift Package resources. `StarterPaletteCatalog` parses the pinned CSS into exact OKLCH values at startup. Keeping the upstream file intact makes the data auditable and avoids maintaining a second hand-transcribed table.

The catalog exposes collection, palette, and swatch value types. The models are generic enough for future collections: a starter palette carries its display name, installed library name, attribution, source collection, stable identity, and swatches.

### Stable identity and normal library behavior

Every starter palette and swatch has an explicit deterministic UUID. `Library.contains(starterPalette:)` checks only the palette UUID. This means:

- Renaming or editing an installed starter keeps it marked Added.
- A user-created palette with the same name does not block installation.
- Deleting the starter makes it available again.
- Reinstalling recreates the same catalog identity with fresh timestamps.

`StarterPalette.makePalette(at:)` creates a regular unlocked `Palette` with ungrouped swatches. There is no special persistent starter-palette type and no schema change, so installed palettes work with all existing edit, delete, move, and pick-target behavior.

### Persistence and undo

`Library.install` adds one missing starter, while `Library.installMissing` walks a collection in catalog order and adds only absent palettes.

`LibraryController` wraps these operations through its existing `perform` mechanism. A single Add is one persisted undo step, and Add All is also one persisted undo step regardless of how many palettes were missing. No-op adds do not create undo history or disk writes because `UndoableLibrary` already suppresses unchanged mutations.

### Settings integration

`SettingsPane.palettes` is released in MVP and ordered between Profiles and Permissions. `SettingsTab` renders the catalog as a grouped form so all 22 rows scroll within the existing window. Preview colors use the app's existing Display P3 SwiftUI conversion.

## Key decisions

- **Pinned Tailwind v4.1.18:** reproducible builds and palette values, with deliberate future upgrades instead of silently tracking upstream.
- **Official OKLCH source:** the bundled Tailwind CSS file is authoritative; AIColors was used only to identify the desired classic collection.
- **Explicit installation:** avoids crowding new and existing user libraries.
- **UUID presence, not content matching:** user customizations remain respected without creating duplicate catalog installs.
- **Ordinary unlocked palettes:** keeps the feature compatible with the existing library model and all editing workflows.
- **Numeric zero for undefined achromatic hue:** `CSipColor` requires three numeric components, and hue has no visual effect when chroma is zero.

## Verification

The new tests cover collection metadata and ordering, all shade names and color spaces, representative exact values, stable IDs, installation semantics, deletion and reinstallation, Add All ordering, persistence, undo/redo, and release gating.

- `make test`: 508 tests passed.
- `make build`: Release app built successfully.
