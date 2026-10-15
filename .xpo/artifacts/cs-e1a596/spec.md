# Update the README for the MVP

## What
Rewrite `README.md` so it describes what the MVP ships, not just the scaffold, and add README screenshots rendered by the app itself, the way Cappucino and Nocchi do it.

## Why
The README dates from cs-70c2c3. A new user can't tell from it what Colorsip does or how to use the picker.

## README structure
1. **Intro**: one paragraph, a hero screenshot (`<picture>` with light/dark WebP), and the "source only, MIT" note.
2. **Features** (MVP only, no V2/V3 items): menubar popover; palettes with groups, icons, lock and pick target; Color History; picker and loupe; picker controls table (§4.3) and modes; Cmd+click paste; color profiles / Smart Profiles; output formats table (taken from `OutputFormat`, so Android XML is included); compact color editor; drag and drop; undo/redo; sound effects. More screenshots go next to the sections they illustrate.
3. **Shortcuts**: global picker shortcut ⌃⌥⌘P; how to change it in Settings ▸ Shortcuts.
4. **Requirements / Build from source / Grant permissions / Keep permissions across rebuilds**: kept, plus `make build` / `make test`.
5. **Your library and the `.colorsip` format**: the library folder layout (§11.1); `.colorsip` is DTCG JSON checked against `schema/colorsip-palette.schema.json`; import/export UI comes in V2.
6. **Known limitations**: colors are clipped on displays whose profile clips them, before Colorsip sees the pixels; macOS 15's recurring screen-capture prompt; Cmd+click paste needs Accessibility; main window, import/export, contrast checker and sync come in later releases.
7. **Development** (adds `make snapshot` / `make screenshots`), **License**, **Third-party**: kept.

## Screenshots (following Cappucino)
- `Colorsip --snapshot <dir>` (in `AppDelegate`, before any normal setup) renders preset states offscreen. It needs no Screen Recording permission and doesn't touch the user's library, settings or defaults: it uses a sample library in a temp folder, a throwaway `UserDefaults` suite and stub services.
- States, each in light and dark, drawn on a fake desktop (wallpaper plus menu bar):
  - `popover`: the popover under its status item, with sample palettes (groups, icons, a locked one) and Color History.
  - `picker`: the loupe and its label over a sample design, sampled from that design's pixels.
  - `editor`: the popover with the compact color editor open.
  - `settings`: the Settings window on the Profiles pane.
- `make snapshot` writes PNGs to `Builds/snapshots/`. `make screenshots` converts the README's set to `docs/<name>-<theme>.webp` with `cwebp` (`brew install webp`).
- The app icon is out of scope (cs-4618bb). The status item glyph is the current SF Symbol.

## Testing
Snapshot rendering is app-target UI drawing: it can't be covered by Swift Testing. To verify by hand: run `make screenshots`, look at every image, and check that the README renders on GitHub in light and dark mode. The sample data is fixed, so there's no logic to move into Core.

## Acceptance criteria
- Every item in the issue checklist is covered, except the app icon (cs-4618bb).
- Nothing in the README describes V2/V3 features as available.
- Shortcuts, formats and controls match the code.
- `make screenshots` regenerates every image in `docs/` used by the README.
