# Walkthrough: Color profiles / Smart Profiles

## What was built
The picker samples in extended linear Display P3 (cs-40b6c9). It now converts each sample to a **target profile** chosen by the app that owns the window under the pointer (not the frontmost app). The loupe label shows a badge for that profile. Settings ▸ Profiles edits the app → profile table and the fallback.

## Core pieces (`ColorsipCore`)
| Piece | File | Role |
|---|---|---|
| `TargetProfile` | `SmartProfiles.swift` | `srgb` / `display-p3` / `generic-rgb`. Maps to `ColorSpace` and has the loupe badge ("sRGB", "P3", "Generic") and the display name. |
| `ProfileRule`, `SmartProfiles` | `SmartProfiles.swift` | Ordered rows `{bundleID, name, profile}` plus `fallback` (default sRGB). `profile(forBundleID:)`, `setRule` (updates in place or appends), `removeRule`, `restoreDefaults` (keeps the fallback). |
| `AppSettings.profiles` | `Settings.swift` | Stored in `settings.json` under `"profiles"`. |
| `PickerWindow`, `PickerGeometry.window(at:in:)` | `PickerGeometry.swift` | Front-to-back hit test, max edges exclusive like `display(at:in:)`. |
| `PickerSession` | `PickerSession.swift` | Takes `windows` and `profiles`. Keeps the raw sample (`sampledCenter`). `profile` and `centerColor` are **computed**, so moving to another window converts the current sample again at once. `PickerLabel.profile` carries the badge. |

The Profiles pane's `hasContent` gate in `Release.swift` is gone: the pane now ships.

## Key decisions
- **Conversion is unclamped.** A P3 color outside sRGB keeps sRGB components below 0 or above 1. This follows the lossless storage rule (`spec.md` §5.1); formats like Hex gamut-map when they output. Display P3 means no conversion.
- **The table is stored in full** (not as overrides of the defaults like shortcuts), so a removed built-in stays removed. Restore Defaults brings the built-ins back. Decoding is lenient: missing `rules` → defaults, unreadable rows skipped, duplicates (case-insensitive) keep the first, unknown fallback → sRGB. A malformed array element is consumed with a `Skip` decodable, because a failed `decode` doesn't advance an unkeyed container.
- **Bundle IDs match case-insensitively**, as macOS treats them.
- **No "Display native" profile**: samples are never in the display's own profile (`spec.md` §6). The issue checklist was corrected.

## App layer
- `PickerController.otherAppsWindows()` takes a `CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements])` snapshot once per session. Windows can't move while the picker takes all input, and this avoids a window-server call per mouse move. It skips Colorsip's own PID and windows with alpha 0. It flips the top-left-origin bounds into AppKit coordinates using the primary screen. It caches PID → bundle ID through `NSRunningApplication`. The desktop is excluded, so it falls to the fallback.
- `LoupeView` adds the badge after the value on the label's first line.
- `ProfilesPane.swift`: a fallback picker ("Other apps"), and rows with an app icon, name, bundle ID, a profile picker and a remove button. An "Add App" menu lists running regular apps not yet in the table, then "Choose…" (`NSOpenPanel`). New rows start on the fallback. Restore Defaults is disabled while the rows equal the defaults.
- The color editor's eyedropper gets the converted color too, because it goes through the same session.

## Related
cs-48e6e4 (found while testing, shipped on this branch): the picker no longer activates Colorsip, so the app being picked from keeps its active appearance.

## Testing
Core tests cover the profile model and its JSON handling, the window hit test, session conversion, label and re-conversion, and pane visibility. The window snapshot, badge drawing and Profiles pane were verified by hand by the user.
