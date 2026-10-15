# Starter Palettes settings catalog

## What

Add an MVP Settings pane named **Palettes** whose content is titled **Starter Palettes**. The first catalog collection is Tailwind CSS v4: 22 individually installable hue palettes, each containing the 11 official shades from 50 through 950.

Installing a starter palette copies it into the user's ordinary library. Nothing is inserted automatically.

## Why

Reference palettes are useful, but preloading all 22 would crowd the menubar library and modify existing users' data without consent. A catalog in Settings makes the collection discoverable while keeping installation explicit and granular.

The Settings architecture already models release-gated panes in `ColorsipCore`, and the library already provides undoable, immediately persisted mutations. The feature should extend those established paths rather than create separate storage or a special read-only palette kind.

## Data source and attribution

- Pin the initial dataset to Tailwind CSS **v4.1.18** `packages/tailwindcss/theme.css`.
- This release matches the linked AIColors catalog: 22 classic families × 11 shades.
- Families, in display order: Slate, Gray, Zinc, Neutral, Stone, Red, Orange, Amber, Yellow, Lime, Green, Emerald, Teal, Cyan, Sky, Blue, Indigo, Violet, Purple, Fuchsia, Pink, Rose.
- Store the source OKLCH components exactly; do not derive the catalog from AIColors' displayed HEX values. Tailwind's achromatic `oklch(L 0 none)` entries map the undefined hue to numeric `0`, because `CSipColor` requires three numeric components and hue has no effect when chroma is zero.
- Bundle Tailwind CSS's MIT license and document the source version and URL near the data.
- Black and white are not separate starter palettes.
- Newer upstream-only families are out of scope for this versioned collection.

## Acceptance criteria

- [ ] Settings has an MVP-visible **Palettes** tab with the system image `square.stack.3d.up`.
- [ ] The pane presents a **Starter Palettes** catalog containing a Tailwind CSS v4.1.18 section.
- [ ] All 22 families appear in the specified order.
- [ ] Every row shows the palette name, an 11-swatch preview in 50→950 order, and Add/Added state.
- [ ] Installing family `<Family>` creates an unlocked palette named `Tailwind <Family>` with exactly 11 ungrouped swatches named `50`, `100`, …, `950`.
- [ ] Colors use the exact official OKLCH values with alpha 1.
- [ ] **Add** appends that palette to the user's library and changes the row to **Added**.
- [ ] **Add All** appends only missing catalog palettes, in catalog order, as one undoable operation.
- [ ] Existing palettes are detected by stable catalog palette UUID, not by mutable name or color content.
- [ ] Renaming or editing an installed starter does not make it appear missing.
- [ ] Deleting the installed starter makes it available to add again.
- [ ] A user-created palette with the same name does not block installation.
- [ ] Added palettes are ordinary unlocked palettes: editable, deletable, movable, and eligible as pick targets.
- [ ] No starter palette is installed automatically for new or existing users.
- [ ] Tailwind's MIT license is bundled with the app/package.
- [ ] The product spec documents the new Settings pane.
- [ ] Core tests and the Release app build pass.

## Flow

1. Extend `SettingsPane` in `Packages/ColorsipCore/Sources/ColorsipCore/Release.swift` with `.palettes`, released in MVP. Place it after Profiles and before Permissions. Extend release-gating tests.
2. Add a UI-free starter catalog in ColorsipCore (for example `StarterPalettes.swift`):
   - A collection model and palette entry model suitable for future collections.
   - Stable, explicitly assigned UUIDs for each catalog palette and its swatches.
   - A Tailwind v4.1.18 collection with the 22 families and exact OKLCH triples.
   - A factory that creates a normal `Palette` at the installation timestamp.
3. Add library operations:
   - Query whether a catalog palette UUID is present.
   - Add one starter only when its UUID is absent.
   - Add all missing starters in catalog order as one mutation.
   - Preserve normal library uniqueness, timestamps, undo, redo, and persistence behavior.
4. Expose the operations through `LibraryController`, using its existing `perform` path so each Add is one undo step and Add All is one undo step.
5. Extend `SettingsTab.swift`:
   - Tab title `Palettes`, symbol `square.stack.3d.up`.
   - A scrollable/form-based `StarterPalettesPane`.
   - Tailwind collection header and brief attribution.
   - One row per palette with a non-interactive 11-swatch preview and trailing Add/Added control.
   - Add All button disabled when nothing is missing.
6. Add Tailwind's MIT license as a ColorsipCore bundled resource and credit the pinned source.
7. Update `spec.md` §10 with the Palettes pane behavior.
8. Verify the catalog model, library operations, controller persistence/undo, release gating, and representative UI behavior; then run all Core tests and a Release build.

## Decisions

### Settings tab label: Palettes

Use the short tab label **Palettes**, with **Starter Palettes** as the pane heading. This fits the existing 560-point window and leaves the pane open to future curated collections.

### Explicit install, not automatic seeding

No library changes happen merely by launching or upgrading Colorsip. This prevents 22 reference rows from appearing without consent.

### Installed identity: stable UUID

The catalog owns a stable palette UUID for each entry. Presence is determined only by that UUID, so user edits and renames remain installed while a deletion reliably makes Add available again. Name or color matching would produce false positives and false negatives.

### Ordinary unlocked copies

A starter is copied into the regular library rather than represented as a new immutable model type. The user explicitly chose to install it, so it should support all normal palette workflows without special cases.

### Versioned source

Pin v4.1.18 instead of following Tailwind's latest file dynamically. Starter palette contents must be reproducible and must not change silently between Colorsip builds. A future Tailwind collection update can be a deliberate catalog revision.

### Core-owned catalog

Catalog definitions and add/missing logic live in ColorsipCore. SwiftUI only renders state and invokes controller operations, keeping the behavior testable under the project's TDD rules.

## Edge cases

### Medium risk

- **An existing palette has the starter's UUID but different content:** treat it as Added. Identity wins because the user may have intentionally edited it.
- **A palette has the same starter name but another UUID:** keep Add enabled. Names are user-editable and cannot establish identity.
- **Add All when some entries are installed:** append only missing entries, preserving catalog order among the newly appended palettes.
- **Save failure:** retain the current in-memory/error behavior of `LibraryController`; do not invent a second error channel for starter palettes.

### Low risk

- Rapid repeated Add actions are serialized on the main actor and the second attempt becomes a no-op.
- Re-adding after deletion recreates the stable catalog palette and swatch UUIDs with fresh installation timestamps.
- Preview swatches are display-only and do not copy, drag, or select.

## Testing

Follow TDD: write the tests below and confirm the relevant new assertions fail before implementing.

- Catalog count, collection metadata, family order, shade order, stable IDs, and representative exact OKLCH values.
- Every entry has 11 opaque OKLCH swatches and no groups.
- Add one, duplicate-add no-op, same-name/different-ID behavior, renamed/edited installed behavior, deletion/re-add.
- Add All with none/some/all installed; ordering and one-step undo/redo.
- Controller persistence after Add and Add All.
- `SettingsPane.visible(for: .mvp)` includes Palettes in the specified position.
- Build-time/resource check for the Tailwind license.
- Existing Core suite remains green and the Release app builds.

## Out of scope

- Automatic installation or migration.
- Removing palettes from Settings; deletion stays in the normal library UI.
- Updating already-installed palettes when a catalog definition changes.
- Search or filtering inside the starter catalog.
- Additional starter collections.
- Tailwind families added after v4.1.18.
- Import/export work from the V2 roadmap.

## Assumptions

- The linked AIColors page is a discovery/reference source; Tailwind's pinned official repository is the authoritative data source.
- Twenty-two rows fit comfortably in the existing Settings window when the pane scrolls.
- Stable catalog UUIDs do not require a `.colorsip` schema change because palette and swatch IDs already exist in the model.
- The existing library UI is sufficient for editing and deleting installed starters.

## Open questions

None. The user approved the Settings catalog, individual Add/Added state, Add All, ordinary editable palettes, stable identity, and a versioned Tailwind collection.
