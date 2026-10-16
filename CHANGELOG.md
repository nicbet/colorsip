# Changelog

All notable changes to Colorsip are listed here. Versions follow [Semantic Versioning](https://semver.org/).

## [1.0.0] - 2026-10-16

The first release. Colorsip is distributed as source only: build it with `make build` (see the
[README](README.md#build-from-source)).

### Added

- Menubar popover with palettes, Color History (the last 16 picks) and a format menu. Click a
  swatch to copy it; right-click for Copy as…, Edit…, Rename and Delete. Undo and redo for every
  change.
- Palettes with named groups, an emoji or SF Symbol icon, a description, duplicate and lock. The
  radio button picks the palette new picks go into.
- Starter Palettes: add the Tailwind CSS v4 palettes from Settings ▸ Palettes.
- Picker with a magnified loupe that follows the pointer across displays, friendly color names
  (from meodai/color-name-list), arrow-key nudging, resizable loupe and grid, and an Option menu
  for switching the output format. Global shortcut ⌃⌥⌘P, configurable in Settings ▸ Shortcuts.
- Picker modes: Shift+click keeps picking, Cmd+click pastes into the active app (needs
  Accessibility).
- Smart Profiles: picks are converted to the color profile of the app under the pointer (sRGB or
  Display P3), configurable in Settings ▸ Profiles.
- Output formats: CSS Hex, Hex (no #), RGB, HSL, OKLCH and Display P3; SwiftUI, NSColor, UIColor;
  Android and Android XML. Out-of-gamut colors are gamut-mapped the CSS Color 4 way.
- Compact color editor with HEX, RGB, HSB, HSL, OKLCH and Display P3 fields, alpha and an
  eyedropper.
- Drag and drop of swatches between palettes and groups, and out to other apps as text.
- Lossless color storage: colors keep their space and float components until copied.
- Library stored as plain files; each palette is a `.colorsip` file in the W3C Design Tokens
  (DTCG) format, with a JSON Schema in `schema/`.
- Permissions guide for Screen Recording and Accessibility, with no restart needed.
- Sound effects on pick and copy, which can be turned off in Settings ▸ General.
- App icon.

### Known limitations

- Some external displays clip colors in their color profile before any app can read them, so
  picks on those displays can be off (for example `#0000ff` reads as `#1a00ff`).
- macOS 15 and later ask again from time to time whether Colorsip may keep capturing the screen.
- Not yet included: the main window, import and export, the contrast checker, color vision
  simulation, per-app output formats, templates and folder sync.

[1.0.0]: https://github.com/nicbet/colorsip/releases/tag/v1.0.0
