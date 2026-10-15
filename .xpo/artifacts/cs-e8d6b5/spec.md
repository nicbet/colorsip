# Sound effects: slurp on pick, plopp on copy

## What
Short audio feedback for picks and copies, using the user-made sounds in `Audio/` (shipped under MIT):

| Event | Sound | File |
|---|---|---|
| Pick that keeps the picker open (Shift+click, multi mode click/Return) | "pick" | `pick-color.wav` (0.28 s) |
| Pick that closes the picker (single pick, Cmd+click paste, editor eyedropper) | "slurp" | `zeeoup.wav` (0.43 s) |
| Explicit copy of a swatch: click-to-copy, swatch menu Copy as…, editor Copy as… | "plopp" | `plopp.wav` (0.34 s) |

No sound for: Esc / finishing multi mode without a pick (`.close`), mode-menu clicks (`.none`), drag-out (not a clipboard copy). Picks also copy to the clipboard, but only play their pick sound — never plopp too.

A **"Play sound effects"** toggle in Settings ▸ General, on by default, stored in `settings.json` as `soundEffects` (lenient decoding: missing/invalid → `true`). The macOS "Play user interface sound effects" setting is not consulted.

## How
**ColorsipCore** (tested):
- `SoundEffect` enum: `.pick`, `.slurp`, `.plopp`, each with its resource name.
- `SoundEffect.forStep(_ step: PickerStep) -> SoundEffect?`: `.pick(close: true)` → `.slurp`, `.pick(close: false)` → `.pick`, otherwise `nil`.
- `SoundPlayer` protocol (`play(_ effect:)`), and `SoundEffects` (MainActor): wraps a player and the `SettingsStore`; `play(_:)` does nothing when `settings.soundEffects` is off.
- `AppSettings.soundEffects: Bool = true`.

**App target** (thin):
- `Colorsip/Sounds/*.wav` — copied from `Audio/` (the synchronized folder bundles them). `Audio/` itself is removed from the repo root (it's untracked there).
- `NSSoundPlayer: SoundPlayer` loads one `NSSound` per effect lazily from the bundle. Rapid repeats: `stop()` then `play()` on the same instance, so the latest event is always heard and sounds of one kind never pile up; different kinds may overlap. Volume as recorded.
- `PickerController.perform` plays `SoundEffect.forStep(step)` for every step (covers re-pick, paste and normal picks).
- `AppModel.copy` plays `.plopp`.
- `GeneralPane` gets the Toggle bound through `AppModel.soundEffectsEnabled`.
- `spec.md` §10 General lists the toggle; a short note in §4.5 / §3.1 on the sounds.

## Acceptance criteria
- [ ] Single pick, Cmd+click paste and eyedropper pick play slurp; Shift+click / multi picks play pick-color; Esc plays nothing.
- [ ] Swatch click and both Copy as… menus play plopp; drag-out and picks don't.
- [ ] Toggle off → no sounds; setting persists in `settings.json`, defaults to on, survives bad values.
- [ ] Rapid repeats restart the sound rather than queueing.
- [ ] Core tests cover the step→sound mapping, the mute gate and settings coding.

## Not automatable
Actual audio playback and bundling: verified by hand (build, pick/copy with the toggle on and off).
