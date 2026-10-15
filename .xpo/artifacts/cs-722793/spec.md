# Compact color editor sheet

Refines `spec.md` §5.4 (MVP, compact). Builds on the color model (cs-7375e5), the output formatters
(cs-86d22b) and the popover's library commands (cs-d6bd2c).

## What
A color editor for one swatch, opened from the popover: swatch → right-click → **Edit…**.

```
┌ Edit Color ─────────────────────── [⋯] ┐   … menu: Copy as ▸, Reset
│ ┌───────────────────────────┐  ┌──────┐ │
│ │  saturation / brightness  │  │before│ │   preview: old above new
│ │          field            │  │after │ │
│ └───────────────────────────┘  └──────┘ │
│                                  [💧]   │   eyedropper
│ [════════════ hue ═════════════]        │
│ [════════════ alpha ═══════════]        │
│ [HEX|RGB|HSB|HSL|OKLCH|P3]              │   model switcher
│  R [60] G [60] B [219]  A [100]  ⚠      │   numeric fields (per model)
│ Name                                    │
│ [Blue Genie                         ]   │
│ Description                             │
│ [Add a description                  ]   │
│                      [Cancel] [Done]    │
└─────────────────────────────────────────┘
```

## Why
Picked colors often need small corrections (a slightly lighter shade, an exact brand hex, a name).
Before this, a swatch could only be renamed or deleted.

## Behavior

### Opening and closing
- **Edit…** is in the swatch context menu after Copy as, before Rename…. It is hidden in Color
  History and in locked palettes (same rule as Rename and Delete).
- The editor **takes over the popover's content**, like a sheet (it slides in from the bottom), until
  Done or Cancel. A real SwiftUI `.sheet` inside an `NSPopover` is unreliable, so the editor replaces
  the content instead.
- It edits a **draft**; the library doesn't change until **Done**.
- **Done** (Return) applies color, name and description as **one undoable step, "Edit Color"**. If
  nothing changed, it just closes and records no undo step.
- **Cancel** (Esc) discards the draft. Closing the popover (click outside) also discards it.
- While the editor is open, the popover's library Undo/Redo keys are off, so Cmd+Z can't change
  the library under the draft (text fields keep their own undo).
- If the swatch disappears while the editor is open, the editor closes without changing anything.

### Working space (how an edit is stored)
`spec.md` §5.1: "edited colors use the editor's working space".
- The working space is an RGB space chosen when the editor opens: **sRGB** for colors stored in
  `srgb`, `hsl` or `hwb`; **Generic RGB** for `generic-rgb`; **Display P3** for everything else
  (`display-p3`, `oklab`, `oklch`).
- The 2D field and the hue slider are HSB in the working space.
- An edit that leaves the working space's gamut (for example P3 or OKLCH values typed into an sRGB
  color) **promotes the working space to Display P3**, so the edit isn't clipped. If it also leaves
  P3, it is stored unclamped in P3 (extended values are allowed, §5.1).
- Every color change stores the draft in the working space (an alpha-only change too). A color that
  is opened and saved without any color change keeps its original space and components exactly.

### Controls
- **2D field**: x = saturation 0–1, y = brightness 0–1 (top = 1). Click or drag; a ring marks the
  current value.
- **Hue slider**: 0–360°. **Alpha slider**: 0–100 %, over a checkerboard.
- The editor keeps its own HSB state, so hue and saturation are not lost when brightness or
  saturation reaches 0 (a gray has no hue). Typed or picked values reset that state from the color,
  except that a gray keeps the hue, and black keeps hue and saturation.
- **Preview**: the original color above the draft.
- **Model switcher** (segmented): HEX, RGB, HSB, HSL, OKLCH, P3. The choice is remembered between
  sessions (machine-local, `LocalSettings.editorModel`). Default HEX.
- **Numeric fields** per model, each with a short uppercase label (the HEX field is labeled "HEX").
  Alpha is an "A" field in every model, 0–100 with no unit shown, wide enough for "100".

| Model | Fields | Range / format | Space |
|---|---|---|---|
| HEX | HEX | `#rrggbb`; accepts 3, 4, 6 or 8 digits, with or without `#` (4/8 digits set alpha) | sRGB |
| RGB | R, G, B | 0–255, integers | sRGB |
| HSB | H, S, B | 0–360°, 0–100 %, 0–100 % (1 decimal) | working space |
| HSL | H, S, L | 0–360°, 0–100 %, 0–100 % (1 decimal) | sRGB |
| OKLCH | L, C, H | 0–100 % (1 decimal), 0–0.4 (3 decimals), 0–360° (1 decimal) | OKLCH |
| P3 | R, G, B | 0–1, 3 decimals | Display P3 |

- The sRGB models (HEX, RGB, HSL) show the **gamut-mapped** value when the color is outside sRGB,
  with a small warning icon ("Outside sRGB — shown mapped"). P3 shows the P3-mapped value.
- A field commits on Return or when it loses focus. Invalid input (not a number, bad hex) is
  rejected and the field shows the current value again. A trailing `%` or `°` and a decimal comma
  are accepted. Out-of-range numbers are clamped to the range in the table; hues wrap.
- Committing a field whose text didn't change does nothing, so tabbing through fields never changes
  the color (rounding would otherwise drift it).

### Name and description
- **Name** and **Description** labels are left-aligned, each above its field. The name field has
  the placeholder "Name"; the description field (1–3 lines) has "Add a description".
- An empty name on Done keeps the old name; an empty description clears it (same trimming rules as
  Rename and Edit Description).
- **Auto-name follows the color**: if the name is still the auto name of the color as opened
  (`friendlyName`) and the user hasn't typed in the name field, the name updates to the new color's
  friendly name as the color changes. Reset restores this.

### Eyedropper
- The eyedropper button closes the popover and opens the picker in **re-pick** mode: the first pick
  (any click, Return or Space, whatever the mode) closes the picker.
- The picked color replaces the draft's color (converted to the working space, promoted to P3 if
  needed). It does **not** go to Color History or the pick target and is not copied: it is an edit,
  not a pick.
- After the pick, or Esc, the popover reopens with the editor and the draft as it was (plus the
  picked color).
- Needs the Screen Recording permission like any pick; without it the permission guide opens and
  the draft is discarded.

### "…" menu
- **Copy as ▸** every output format, with the draft's value (same items as the swatch menu).
- **Reset**: back to the color, name and description as they were when the editor opened. Disabled
  when nothing changed.

### Duplicates
- Done with a color that another swatch in the same section already has (§7.2) is refused: the
  editor stays open and shows "“<name>” in this group already has this color." The message names the
  swatch because the strip (and its highlight) is hidden behind the editor. It clears when the color
  changes.

### Translucent swatches in the popover
- In the popover's swatch strips (palettes and Color History), a swatch whose alpha is below 1 is
  drawn over the same checkerboard as the editor, so translucent colors are recognizable. Opaque
  swatches are drawn as before.

## Design (code)
- **ColorsipCore**
  - `ColorEditor` (value type, `ColorEditor.swift`): original swatch, draft color, working space,
    HSB state, name, description, auto-name tracking. `setSaturation(_:brightness:)`, `setHue`,
    `setAlpha`, `setPicked`, `fields(_:)`, `alphaField`, `commit(_:field:of:)`, `commitAlpha`,
    `setName`, `reset()`, `isColorChanged`, `hasChanges`, `isOutsideSRGB`.
  - `EditorModel` enum (hex, rgb, hsb, hsl, oklch, displayP3) with display names and field labels.
  - `Library.editSwatch(_:in:color:name:description:at:)`: all three at once, or throws
    (`.locked`, `.notFound`, `.duplicate`) and changes nothing.
  - `LibraryController.editSwatch(…)` / `save(_ editor:in:)` → one "Edit Color" step;
    `SwatchEditResult` `.changed`, `.unchanged`, `.duplicate(existing:)`, `.failed`.
  - `SwatchMenuItem.edit`; `LocalSettings.editorModel`.
- **App**
  - `AppModel.colorEditor` (`ColorEditorSession`: draft, section, duplicate name), `openEditor`,
    `saveEditor`, `discardEditor`, `startRepick` / `endRepick`, `editorModel`.
  - `ColorEditorView`: thin views over `ColorEditor` (field, sliders, preview, fields, menus).
    `Checkerboard` is shared with the swatch strip.
  - `PopoverView` swaps its content for the editor; `PickerController.open(repick:)` hands the first
    pick to a completion; `StatusItemController.showPopover()` reopens the popover after it.

## Acceptance criteria
- [ ] Edit… appears in the swatch menu of unlocked palettes only; not in Color History or locked
      palettes.
- [ ] The editor shows the 2D field, hue and alpha sliders, preview, model switcher, numeric fields,
      name, description, eyedropper and "…" menu.
- [ ] Each model shows and accepts the fields in the table; alpha works in every model and "100"
      fits its field.
- [ ] Done applies color, name and description as one undo step "Edit Color"; Cmd+Z restores all
      three. Cancel/Esc changes nothing.
- [ ] Working-space rules hold, including promotion to P3 and the exact round trip of an unchanged
      color.
- [ ] Reset restores the opening state; Copy as copies the draft.
- [ ] Re-pick replaces the draft's color without touching Color History, the pick target or the
      clipboard, and the editor comes back.
- [ ] A duplicate in the section is refused with a message naming the existing swatch.
- [ ] Translucent swatches show a checkerboard behind them in the popover's strips.
- [ ] Logic is in ColorsipCore with tests; the app builds.

## Edge cases
- Gray / black: hue and saturation sliders keep their position.
- Hex input `abc`, `#abcd`, `3C3CDB`, `#3c3cdbcc`; invalid `#12`, `xyz`, `#gggggg`.
- Hue 360 → 0, −90 → 270; out-of-range values clamped.
- P3 color opened, HEX shows mapped value with warning; editing only the name keeps the P3 color
  exactly.
- OKLCH stored color opens in P3 working space; unchanged color stays OKLCH.
- Swatch deleted while the editor is open: the editor closes.

## Out of scope
- Multi-color editing and the main window inspector (V2).
- Undo inside the editor beyond text-field undo.

## Decisions (confirmed with the user)
1. **Draft + Done/Cancel**, one undo step — not live editing.
2. **Re-pick is an edit**, not a pick: no Color History, pick target or clipboard.
3. **Auto-name follows the color** while it's still the automatic name and untouched.
4. **Editor replaces the popover content** instead of a SwiftUI `.sheet` (made during
   implementation; the spec allowed this fallback).
5. **Review revisions**: the HEX field is labeled "HEX"; the alpha field drops its "%" and is wide
   enough for "100"; Name and Description labels are left-aligned above their fields, with
   placeholders.
6. **Checkerboard behind translucent swatches** in the popover's strips (user request during
   review; it goes with alpha editing, so it's part of this issue).
