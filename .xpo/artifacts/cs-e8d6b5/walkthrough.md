# Walkthrough: sound effects on pick and copy

## What was built
Picks and copies now play short sounds. The sounds are the user's own recordings and ship under MIT.

| Event | Effect | File |
|---|---|---|
| Pick that closes the picker (single pick, Cmd+click paste, the editor eyedropper) | `.slurp` | `zeeoup.wav` |
| Pick that keeps the picker open (Shift+click, multi mode) | `.pick` | `pick-color.wav` |
| Explicit copy (swatch click, swatch Copy as…, editor Copy as…) | `.plopp` | `plopp.wav` |

A "Play sound effects" toggle in Settings ▸ General turns them off. It is on by default.

## How the pieces fit
- **`ColorsipCore/SoundEffects.swift`** holds the decisions, so they can be unit-tested:
  - `SoundEffect` names each sound and its resource file.
  - `SoundEffect.forStep(_:)` maps a `PickerStep` to a sound. `.pick(close: true)` is a slurp and `.pick(close: false)` is a pick. `.close` and `.none` are silent.
  - `SoundEffects` wraps a `SoundPlayer` protocol and the `SettingsStore`. It drops every `play` while `soundEffects` is off.
- **`AppSettings.soundEffects`** is stored in `settings.json`. Like every other key, it is decoded leniently: a missing or invalid value means `true`.
- **App target**:
  - `NSSoundPlayer` loads one `NSSound` per effect on first use. On each play it calls `stop()` and then `play()`, so rapid repeats restart the sound instead of piling up. Different effects can still overlap.
  - The `.wav` files live in `Colorsip/Sounds/`. `Colorsip/` is a synchronized folder group, so Xcode bundles them without any pbxproj edit.
  - `AppModel` owns `sounds` and exposes `soundEffectsEnabled` for the Toggle.

## Hook points, and why there
- **`PickerController.perform(_:)`** is the one place every picker step passes through. Hooking it covers normal picks, Cmd+click paste and the eyedropper re-pick in one line. The step itself says whether the picker closes.
- **`AppModel.copy(_:as:)`** is used only by explicit UI copies. Picks write to the clipboard through `routePick`, which never calls `copy`, so a pick plays its pick sound and never a plopp as well.
- **Drag-out** builds its own pasteboard item. It isn't a clipboard copy, so it stays silent.

## Decisions
- The toggle is synced in `settings.json` rather than kept machine-local. It is a user preference like the default format.
- The macOS "Play user interface sound effects" setting is deliberately not consulted.
- Volume is as recorded.

## Verification
- Core tests cover the step→sound mapping, the mute gate and settings coding (`SoundEffectsTests`, `SettingsTests`).
- Actual playback was checked by hand by the user.
