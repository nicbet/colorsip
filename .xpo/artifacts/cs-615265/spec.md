# Color profiles / Smart Profiles

Refines `spec.md` §6 and §10 (Profiles pane).

## What
The picker converts each sample from extended Display P3 (§4.2) to a **target profile** chosen by
the app that owns the window under the pointer. Settings ▸ Profiles edits the app → profile table
and the fallback. The loupe label shows which profile it used.

## Why
Designers paste values into the app they picked from. A browser or Figma speaks sRGB; Xcode or
Sketch speak P3. Storing the pick in that app's space (§5.1) keeps the values they'd type there.

## Scope
**In:** target profile model and defaults, settings persistence, window hit-testing, conversion of
picks and the loupe label, profile badge, Profiles pane (add / edit / remove / restore defaults,
fallback).
**Out:** Smart Formats (V3), Adobe RGB, per-display behavior, a "Display native" option (removed
by `spec.md` §6; the issue checklist still mentions it and is out of date).

## Design

### Core (`ColorsipCore`, test-driven)
1. **`TargetProfile`**: `srgb`, `displayP3`, `genericRGB` (Codable raw values `srgb`,
   `display-p3`, `generic-rgb`). `colorSpace: ColorSpace`; `badge`: "sRGB", "P3", "Generic";
   `displayName`: "sRGB IEC61966-2.1", "Display P3", "Generic RGB".
2. **`SmartProfiles`** (in `AppSettings.profiles`):
   - `rules: [ProfileRule]` — `ProfileRule { bundleID, name, profile }`, ordered, unique by bundle ID
     (case-insensitive).
   - `fallback: TargetProfile` (default `.srgb`).
   - `profile(forBundleID: String?) -> TargetProfile` — matching rule, else fallback.
   - `static let defaultRules`: Safari, Chrome, Firefox, Arc, Edge, Brave, Figma → sRGB; Xcode,
     Sketch, Pixelmator Pro, Preview → Display P3.
   - Mutations: `setRule(bundleID:name:profile:)` (adds or updates), `removeRule(bundleID:)`,
     `restoreDefaults()` (rules only; fallback kept).
   - Stored in full in `settings.json` (`"profiles": { "rules": [...], "fallback": "srgb" }`), so a
     removed built-in stays removed. Missing key → defaults; unknown profiles or malformed rules are
     skipped; an unknown fallback → sRGB.
3. **`PickerWindow`** `{ frame (global, y up), bundleID? }` and
   `PickerGeometry.window(at:in:)`: the first window, front to back, whose frame contains the
   point.
4. **`PickerSession`** gains `windows: [PickerWindow]` and `profiles: SmartProfiles` (init
   parameters, defaulting to none / defaults).
   - `profile: TargetProfile` — for the window under `point`; no window → fallback.
   - `centerColor` is the sample **converted** to `profile.colorSpace` (unclamped: §5.1 stores
     values outside 0–1 losslessly; formatters gamut-map on output). Display P3 = no conversion.
   - Picks return the converted color; `PickerLabel` gains `profile` for the badge.
   - Moving to another window re-converts the current sample at once.

### App
- **Window list**: `PickerController.open()` snapshots `CGWindowListCopyWindowInfo(.optionOnScreenOnly
  + .excludeDesktopElements)` *before* showing the overlay; skips Colorsip's own windows and windows
  with alpha 0; flips bounds to AppKit coordinates; maps PID → bundle ID with
  `NSRunningApplication`. Windows can't move while the picker holds all input, so one snapshot per
  session is enough (and avoids a window-server call per mouse move).
- **Loupe label**: a small badge ("sRGB" / "P3" / "Generic") next to the value line.
- **Profiles pane** (`SettingsPane.profiles.hasContent = true`):
  - Fallback picker ("Other apps"): Display P3 (no conversion), sRGB, Generic RGB.
  - Rows: app icon, name and bundle ID, a profile picker, and a "−" button that removes the row.
  - "Add App" menu: running regular apps not yet listed, then "Choose…" (`NSOpenPanel` for
    `.app`). A new row starts on the fallback profile.
  - "Restore Defaults" button (disabled while the rows equal the defaults).
- The color editor's eyedropper gets the converted color too (it's a pick, §5.1).

## Acceptance criteria
- [ ] Pointer over a Safari window → label shows "sRGB" badge; the pick is stored with
      `colorSpace: srgb`.
- [ ] Pointer over Xcode → "P3", stored as `display-p3` with the sampled components unchanged.
- [ ] Pointer over an unlisted app, the desktop or a gap → fallback profile.
- [ ] The frontmost app doesn't matter; the window under the pointer does.
- [ ] Profiles pane: add, change and remove rows, change the fallback, restore defaults; changes
      persist in `settings.json` and apply to the next picker session.
- [ ] Out-of-sRGB P3 colors converted to sRGB keep components outside 0–1 (not clipped).

## Edge cases
- Overlapping windows → frontmost wins. Menu bar / Dock / floating panels count as windows of
  their owner (layer is not filtered), which matches "the app that owns the window under the
  cursor".
- A window whose app has no bundle ID → fallback.
- Duplicate bundle ID added again → updates the existing row.
- Settings saved by this version and read by an older one: the extra key is ignored.

## Testing
Core: `TargetProfile`, `SmartProfiles` (lookup, defaults, mutations, Codable leniency),
`PickerGeometry.window(at:in:)`, `PickerSession` profile/conversion/label, `SettingsPane.visible`.
By hand: window list snapshot, badge drawing, Profiles pane.
