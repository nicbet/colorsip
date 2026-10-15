# Update the README for the MVP

## What
Rewrite `README.md` so it describes what the MVP ships, not just the scaffold. Docs only: no code changes.

## Why
The README dates from cs-70c2c3. A new user can't tell from it what Colorsip does or how to use the picker.

## Structure
1. **Intro**: one paragraph plus the "source only, MIT" note (kept).
2. **Features** (short bullets, MVP only — no V2/V3 items):
   - Menubar popover: format dropdown, palette list, click to copy, right-click menus, undo/redo
   - Palettes with named groups, icons, lock, pick-target radio button
   - Color History (last 16 picks, duplicates merged)
   - Picker + loupe: multi-display, loupe size (wheel) and grid size (Option+wheel), arrow keys, friendly names
   - Picker controls table (§4.3) and modes (single/multi via Option menu)
   - Cmd+click paste into the active app
   - Color profiles / Smart Profiles (app under the pointer → sRGB / Display P3 / Generic RGB)
   - Output formats table (§5.3)
   - Compact color editor
   - Drag and drop (between palettes/groups, Option = copy, to other apps)
   - Sound effects (can be turned off)
3. **Shortcuts**: global picker shortcut ⌃⌥⌘P, how to change it in Settings ▸ Shortcuts (click, press combination, Esc cancels, ⌫ clears, reset to default).
4. **Requirements / Build from source / Grant permissions / Keep permissions across rebuilds**: kept, with `make build` / `make test` mentioned.
5. **Your library and the `.colorsip` format**: library folder layout (§11.1), `.colorsip` is DTCG JSON validated by `schema/colorsip-palette.schema.json`. Import/export UI is V2, so the README says so instead of documenting a feature that doesn't exist.
6. **Known limitations**: color accuracy on displays whose profile clips colors (pixels are already clipped before capture; other pickers show the same); macOS 15's recurring screen-capture prompt; Cmd+click paste needs Accessibility; library sync, main window, import/export, contrast checker are later releases.
7. **Development**, **License**, **Third-party**: kept.

## Acceptance criteria
- Every item in the issue checklist is covered, except screenshots / app icon (see open question).
- Nothing in the README describes V2/V3 features as available.
- Shortcuts, formats and controls match the code (`ShortcutAction.defaultShortcut`, formatters, picker controls).
