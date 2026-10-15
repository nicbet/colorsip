# Walkthrough: Update the README for the MVP

## What was built
1. **README rewrite** (`README.md`). It now describes what the MVP ships:
   - Features, with a picker controls table and an output formats table.
   - The color editor, shortcuts, build and permissions.
   - The library folder and the `.colorsip` DTCG format.
   - Known limitations, and the development tasks.
2. **Self-rendered screenshots**, following Cappucino's `--snapshot` pattern. The app renders its own UI from preset states, so the README images can be regenerated at any time and always match the code.

## How the pieces fit
- `Colorsip/Snapshot.swift`
  - `Snapshot.requestedDirectory` reads `--snapshot <dir>` from the command line.
  - `AppDelegate.applicationDidFinishLaunching` checks it first. If it's set, the app renders and quits without creating the status item, hotkeys or permission prompts.
  - `SampleLibrary` writes a fixed library to a temp folder with `LibraryStore`: Brand (with groups), Tailwind (three 11-shade groups, so the strip scrolls and fades), and a locked Sunset palette, plus 10 history entries.
  - It builds a fresh `AppModel` per shot over that library, with a throwaway `UserDefaults` suite and stub login item, hotkey, permission and sound services. The user's library and defaults are never touched, and both temp locations are removed at the end.
  - `capture(_:)` hosts a real view (`PopoverView`, `MainWindowView`) in an offscreen key window, lets SwiftUI settle, and caches the view, or the window frame for titled windows, into a 2× bitmap.
  - Scenes (`MenuBarScene`, `WindowScene`) put that bitmap on a wallpaper with a fake menu bar, with rounded corners and a shadow.
  - The picker shot renders `DesignScene` (tiles of design tokens) to an image and samples its 2× pixels around a point near a tile's rounded corner. It then draws the real `LoupeView` with those samples and a real `PickerLabel` (value, friendly name, sRGB badge). The loupe shows true pixels of the scene behind it.
- `Makefile`
  - `make snapshot` builds the app and writes PNGs to `Builds/snapshots/` (gitignored).
  - `make screenshots` converts the README set (`popover picker editor settings` × light/dark) to `docs/*.webp` with `cwebp -q 92`.
- The README embeds each shot in `<picture>`, so GitHub shows the dark version in dark mode.

## Key decisions
- **`activate(ignoringOtherApps:)`** in snapshot mode. When the app is launched from a terminal, the cooperative `activate()` is refused, and windows and segmented controls draw inactive (grey traffic lights, dimmed tabs).
- **Fixed Settings window size (560×480).** With `fittingSize`, the Profiles pane grew to list every app.
- **Moodboard (empty palette) left out of the sample.** It pushed the list past its 300 pt cap and left a half-visible row and a scroll bar.
- **Scoped `import struct ColorsipCore.KeyboardShortcut`.** The stubs have to name the type, and SwiftUI's `KeyboardShortcut` makes the bare name ambiguous. `ColorsipCore.KeyboardShortcut` doesn't compile, because the module also has an enum named `ColorsipCore`.
- **README scope.** It only describes MVP features. Import/export is V2, so the README documents the format and schema and says you can copy palette files meanwhile. The format table follows `OutputFormat` and `OutputFormatTests` (so it includes Android (XML)), not spec.md.
- **App icon** is left to cs-4618bb.

## Non-obvious things
- Snapshot rendering is UI drawing and has no automated tests. Check it by eye after `make screenshots`.
- App icons in the Profiles shot come from the rendering machine: apps that aren't installed show a placeholder.
- The known color-accuracy limitation (displays whose profile clips colors) comes from cs-40b6c9's investigation. Don't promise accuracy that pixel capture can't give.
