# Colorsip

Colorsip is a color-picker menubar app for macOS.
It is open source (MIT), distributed as source on GitHub, and built locally. There are no pre-built
binaries and no App Store version.

## 1. Platform

| Topic | Decision |
|---|---|
| OS | macOS 15.8 or later, macOS only (no iOS companion) |
| UI | SwiftUI, with AppKit where SwiftUI falls short (picker overlay, status item, popover, event taps) |
| Language | Swift 6 |
| Distribution | Source only. Not sandboxed, not on the App Store |
| License | MIT |
| App type | Agent app (`LSUIElement`): no Dock icon, even when the main window is open |
| Launch at login | Optional, off by default (`SMAppService`) |

### Project structure
- `ColorsipCore`: a Swift package with no UI. It holds the color model, conversions, formatters,
  naming, contrast math, the storage model and serialization. All of it is covered by unit tests
  (Swift Testing).
- `Colorsip`: the app target (menubar, picker, windows, settings).
- GitHub Actions CI builds the app and runs the Core tests on every push and PR.
- The README explains how to build from source and grant permissions.

## 2. Roadmap

| Release | Scope |
|---|---|
| **MVP** | Menubar app, palettes with named groups, Color History, picker (single and multi pick, precise movement, Cmd+click paste), color profiles / Smart Profiles, global shortcut, settings, permissions onboarding |
| **V2** | Main window app, import/export, contrast checker (including the picker's contrast mode), color vision simulation |
| **V3** | Smart Formats, templates, file-system sync |
| Later / not planned | Color Dock, custom format templates, import of third-party formats |

Each section below carries a release tag. UI that belongs to a later release is hidden until that
release ships. It is never shown disabled.

## 3. UI surfaces

### 3.1 Menubar popover — MVP
A status-bar icon opens a popover. The popover can't be detached into a window; the main window
(V2) serves that purpose.

From top to bottom:
1. **Toolbar**
   - Picker (eyedropper) — MVP
   - Contrast checker — V2
   - New palette (+) — MVP
   - Color vision simulation (color wheel), which opens the simulation mode menu — V2
2. **Format dropdown** (e.g. "CSS Hex"): the active output format for copy, paste and the loupe
   label. In V3, Smart Formats can override it per app.
3. **Palette list** (scrollable)
   - **Color History** is always first. It has no radio button and no lock.
   - Each palette row has a **radio button** (the target palette for new picks), an optional
     **icon**, the **name**, a **lock** icon when locked, and the **swatch strip**.
   - An empty palette shows a dashed "Drop colors here" target.
4. **Bottom bar**
   - Settings — MVP
   - Color vision mode menu — V2
   - Open main window — V2
   - Quit — MVP

Swatch interactions in the popover (MVP):
- **Click** a swatch: copies its value in the active format.
- Click-to-copy and Copy as… play a short "plopp" sound (Settings ▸ General can turn sounds off).
- **Right-click** a swatch: Copy as… (any format), Edit…, Rename, Delete. Edit, Rename and Delete
  are hidden in locked palettes and in Color History.
- **Right-click** a palette: Rename, Edit description, Set icon, Lock/Unlock, New group, Duplicate,
  Delete. A locked palette only offers Unlock (plus Export in V2).

### 3.2 Main window — V2
A three-pane window, opened from the popover's bottom bar or a user-assigned global shortcut.
- **Sidebar**: the same list as the popover (history plus palettes, with strips).
- **Content**: the selected palette's colors, organized by collapsible groups. Each row shows a
  swatch, its name and its value in the active format. There is a list/grid view toggle and a sort
  menu (manual, name, hue, lightness, date added). An empty palette shows an empty state ("This
  palette is empty — add colors by dragging and dropping them in this palette").
- **Inspector**
  - Palette selected: name, description, info (created, modified, color count) and a Lock toggle.
  - Color selected: the color editor (§5.4), description and info (created, modified).
  - Several colors selected: the editor in "Multiple Values" mode. Fields that differ show "Multi";
    editing one field applies it to every selected color.
  - Bottom actions: Export, Duplicate, Delete.
- **Toolbar**: New palette, view toggle, sort, picker, contrast checker, color vision, format
  dropdown.

## 4. Picker — MVP (contrast mode V2)

### 4.1 Invocation
- The default global shortcut is **Ctrl+Option+Cmd+P** (Hyper+P). Users can change it in
  Settings.
- Users can also assign optional global shortcuts to open the contrast checker (V2) and the main
  window (V2).
- The toolbar eyedropper also starts the picker.

### 4.2 Overlay and loupe
- A borderless, transparent overlay window covers every display. It follows the pointer across
  displays, including displays with different scale factors and color profiles.
- Pixels come from ScreenCaptureKit, composited in **extended linear Display P3, as half floats**,
  not in the display's native profile. A display's calibrated profile can clip colors (on some
  panels even sRGB blue and yellow), and 8 bits per channel can't round-trip 8-bit sRGB values
  through a wider space. Linear half floats keep both sRGB and P3 content exact.
- The **loupe** is a circle that shows a magnified pixel grid, with the center pixel outlined.
- Under the loupe, a **label** shows the value in the active format and the color's friendly name
  (§5.5).
- Loupe settings (starting defaults, to be tuned after we try them):

| Setting | Range | Default | Control |
|---|---|---|---|
| Loupe diameter | 120–400 pt, in steps of 20 | 200 pt | Mouse wheel |
| Grid size (pixels across) | 5–31, odd numbers only | 11 | Option + mouse wheel |

  Both are remembered between sessions.

### 4.3 Controls while the picker is active

| Input | Action |
|---|---|
| Click / Return / Space | Pick the color and close the picker (single mode) |
| Shift + click | Pick the color and keep the picker open |
| Cmd + click | Pick the color, close the picker, and paste the value into the active app (§4.5) |
| Arrow keys | Move 1 pixel (a physical pixel of the display) |
| Shift + arrow keys | Move 10 pixels |
| Hold Option | Show the mode popover menu next to the loupe |
| Esc | Cancel and close. In multi mode, colors already picked are kept |

### 4.4 Modes
The Option popover menu switches between modes:
- **Single** (default): the first pick closes the picker.
- **Multi**: every click picks a color. Esc or Return without moving finishes.
- **Contrast** (V2): pick the text color, then the background color. The contrast checker then
  opens with both.

### 4.5 Where picks go
- Every pick goes into **Color History**.
- A pick also goes into the palette selected with the radio button, unless that palette is
  locked. It is added to the **front** of the palette's ungrouped section, so the newest pick is
  always visible without scrolling.
- The value of the last pick is copied to the clipboard in the active format (Smart Formats in
  V3).
- **Cmd+click paste**: Colorsip remembers which app was active before the picker opened. It
  re-activates that app, puts the value on the clipboard and sends a synthetic Cmd+V (CGEvent).
  This needs the Accessibility permission. If the permission is missing, the value is only copied,
  and the user is pointed to the onboarding step (§9).
- **Sounds**: a pick that closes the picker (single pick, Cmd+click paste, the color editor's
  eyedropper) plays a "slurp"; a pick that keeps it open (Shift+click, multi mode) plays a
  shorter pick sound. Esc is silent. A repeated sound restarts instead of queueing. Settings ▸
  General can turn sounds off.

## 5. Colors

### 5.1 Color model (storage)
To keep colors lossless and compatible, each color is stored as **a color space, float
components and alpha**, following CSS Color 4 / the W3C Design Tokens (DTCG) color type:

```json
{ "colorSpace": "display-p3", "components": [0.2364, 0.2353, 0.8588], "alpha": 1.0, "hex": "#3c3cdb" }
```

- A color keeps the color space it was created in: picked colors use the resolved profile
  (§6); edited colors use the editor's working space.
- Components are 64-bit floats. Values outside the 0–1 range are allowed in extended spaces;
  nothing is rounded or clamped when stored.
- `hex` is an informative sRGB fallback (gamut-mapped). It is never read back as the source of
  truth.
- Supported spaces: `srgb`, `display-p3`, `oklch`, `oklab`, `hsl`, `hwb`, `generic-rgb` (Adobe RGB
  1998 is optional).
- **Equality** (for de-duplication) compares the colors converted to OKLab with a ΔEOK below 0.002.
  This tolerates rounding while keeping visibly different colors distinct.

### 5.2 Swatches
A swatch has an id (UUID), a color, a name (auto-named, editable), an optional description, and
created and modified timestamps.

### 5.3 Output formats — MVP
These formats are available in the format dropdown and in "Copy as":

| Format | Example |
|---|---|
| CSS Hex | `#3c3cdb` (`#3c3cdbcc` with alpha) |
| CSS Hex (no #) | `3c3cdb` |
| CSS RGB | `rgb(60 60 219)` / `rgb(60 60 219 / 80%)` |
| CSS HSL | `hsl(240 69% 55%)` |
| CSS OKLCH | `oklch(46.2% 0.226 271.5)` |
| CSS Display P3 | `color(display-p3 0.236 0.235 0.859)` |
| SwiftUI | `Color(.displayP3, red: 0.236, green: 0.235, blue: 0.859, opacity: 1)` |
| NSColor | `NSColor(displayP3Red: 0.236, green: 0.235, blue: 0.859, alpha: 1)` |
| UIColor | `UIColor(displayP3Red: 0.236, green: 0.235, blue: 0.859, alpha: 1)` |
| Android | `0xFF3C3CDB` / `#FF3C3CDB` |

Users can't define their own format templates for now. Formats that can't express a color's gamut
(for example Hex for a P3 color) are gamut-mapped to sRGB using the CSS Color 4 OKLCH chroma
reduction.

### 5.4 Color editor — MVP (compact), V2 (inspector)
- A 2D saturation/brightness field, a hue slider and an alpha slider.
- Numeric fields for **HEX, RGB, HSB, HSL, OKLCH and Display P3**. A model switcher chooses which
  set of fields is shown. Alpha is available in every model.
- An eyedropper button re-picks the color, and a "…" menu offers Copy as and Reset.
- In the MVP the editor opens as a sheet from the popover (swatch → Edit…). In V2 it is the main
  window's inspector, which also supports editing several colors at once.

### 5.5 Color names — MVP
- Names come from the bundled [meodai/color-name-list](https://github.com/meodai/color-name-list)
  (MIT, about 30k names).
- The name is the nearest entry by ΔEOK in OKLab. It is assigned automatically on pick and can be
  edited.

## 6. Color profiles and Smart Profiles — MVP
"Color profiles" and "Smart Profiles" are the same feature.

- The picker samples in extended Display P3 (§4.2) and **converts the value to a target profile**
  chosen for the app under the pointer: the app that owns the window under the cursor, not the
  frontmost app.
- **Smart Profiles** look up the target profile by app bundle ID. Built-in defaults, which users can
  edit:

| Apps | Profile |
|---|---|
| Safari, Chrome, Firefox, Arc, Edge, Brave, Figma | sRGB IEC61966-2.1 |
| Xcode, Sketch, Pixelmator Pro, Preview | Display P3 |
| Everything else | Fallback setting (default: sRGB) |

- In Settings, users can add, edit and remove app → profile rows. The fallback can be "Display
  P3" (no conversion), sRGB or Generic RGB. There is no "Display native" option: samples are
  never in the display's own profile (§4.2).
- The loupe label shows the profile it used (e.g. a small "sRGB" or "P3" badge).

## 7. Palettes — MVP

### 7.1 Palettes
- Each palette has a name, an optional description, an optional icon (**emoji or SF Symbol**), a
  locked flag, and created and modified timestamps.
- Palettes can be created, renamed, reordered (drag), duplicated and deleted.
- **Locked** palettes allow no changes: no adding, editing, removing, reordering or renaming, and
  they can't be the target of picks or drops. They can only be exported (V2) or unlocked.
- Exactly one palette, or none, is the **pick target** (radio button). New picks are added
  at the front of its ungrouped section, newest first.

### 7.2 Groups
- A palette contains an ordered list of **groups**. One level only: groups don't nest.
- Each palette has an implicit **ungrouped** section, which is shown first and has no header.
- Groups have a name and can be renamed, reordered and deleted. Deleting a group asks whether to
  also delete its swatches or move them to the ungrouped section.
- A color can appear in several groups. **Within one group, swatches must be unique** (by the
  equality rule in §5.1): a duplicate drop or pick into the same group is refused, and the existing
  swatch briefly highlights.

### 7.3 Swatch strip (preview)
- Swatches appear as equal-width segments. Each group is drawn as its own rounded segment, with a
  small gap between groups.
- With 16 colors or fewer, the segments spread out evenly to fill the strip's width.
- Over 16 colors, each segment is 1/16 of the width, so the strip **scrolls horizontally**. Its
  edges **fade** when there is more content in that direction.

### 7.4 Color History
- Holds the **last 16 picked colors**, newest first.
- **Duplicates are merged**: picking a color already in history moves it to the front.
- Read-only: it can't be cleared, edited or reordered. Users can copy from it and drag out of it.
- It syncs like everything else (V3).

### 7.5 Drag and drop
- Swatches can be dragged between palettes, between groups, within a group (to reorder), and from
  Color History. A plain drag between palettes **moves** the swatch; Option-drag **copies** it.
  Dragging out of Color History, or out of a locked palette, always copies.
- Users can drop onto a palette strip, where the pointer picks the group (or the ungrouped section)
  and the position in it; onto a palette's header, which adds to the front of the ungrouped
  section; or onto the empty "Drop colors here" area. Groups have no headers of their own in the
  strip, so empty groups can't be dropped on in the popover.
- A drop that would duplicate a color in its group is refused, and the existing swatch briefly
  highlights (§7.2). Locked palettes refuse drops.
- Dragging a swatch to other apps provides the value as text in the active format (plus an
  `NSColor` pasteboard type).

### 7.6 Undo and redo
All library changes can be undone (Cmd+Z / Shift+Cmd+Z) in the popover and the main window.
Picks can be undone too, except their effect on Color History.

## 8. Accessibility — V2

### 8.1 Contrast checker
- A small window with a text color and a background color, a live preview ("Aa" text in several
  sizes) and a score.
- The **algorithm** can be switched between **WCAG 2.x** (ratio, with AA/AAA pass/fail for normal
  and large text) and **APCA** (Lc value, with a pass/fail against a chosen target).
- Each side has sliders and color fields, and the score updates in real time.
- **Fix buttons on both sides**: the user chooses which color to adjust. The fix changes only that
  color's OKLCH lightness, by the smallest step that meets the target, and keeps hue and chroma
  (with gamut mapping if needed). The target is chosen next to the score (default: WCAG AA normal
  text / APCA Lc 60).
- The checker opens from the toolbar button, a global shortcut, a swatch's context menu ("Check
  contrast with…") in the main window, or the picker's contrast mode.

### 8.2 Color vision simulation
- Modes: Off, Protanopia, Deuteranopia, Tritanopia, Achromatopsia.
- The simulation only changes how **swatches are drawn** in the popover and the main window. Stored
  values and copied values stay the same.
- Algorithm: the Machado et al. (2009) matrices at full severity, applied in linear sRGB.
  Achromatopsia uses luminance only.
- It is opened from the color-wheel toolbar button and the bottom-bar menu. The current mode stays
  visible as long as the simulation is on.

## 9. Permissions and onboarding — MVP
- At launch, and whenever a feature needs a permission, Colorsip checks for:
  - **Screen Recording**: required by the picker.
  - **Accessibility**: only needed for Cmd+click paste.
- If any are missing, an onboarding window shows them **as one checklist**. Each row says what the
  permission is for, has a button that opens the right System Settings pane, and shows a ✓ as
  soon as the permission is granted, without restarting Colorsip. A feature that needs a
  permission opens the checklist with that row highlighted.
- Accessibility can be skipped. Settings shows the status of each permission and lets the user
  start the guide again.

## 10. Settings — MVP
- **General**: launch at login, default output format, play sound effects (on by default), quit.
- **Shortcuts**: the picker shortcut (MVP); contrast checker and main window shortcuts (V2).
- **Picker**: the default loupe diameter and grid size.
- **Profiles**: the Smart Profiles table and the fallback profile.
- **Permissions**: the status of each permission and a button to start the guide again.
- **Formats** (V3): the Smart Formats table.
- **Sync** (V3): the sync folder.

## 11. Storage and file format

### 11.1 Library on disk — MVP
The library is a **folder of plain files**, so that file-system sync (V3) works without
migration:

```
~/Library/Application Support/Colorsip/Library/
  library.json            # palette order, pick target, format version
  history.json            # Color History
  settings.json           # synced settings (shortcuts, formats, profiles, loupe defaults)
  palettes/<uuid>.colorsip
```

- Each palette is its own file, so a sync conflict affects only one palette.
- Files are written atomically. Machine-local state (window positions, the path of the sync
  folder, permission status) is stored in `UserDefaults`, not in the library.

### 11.2 Colorsip palette format (`.colorsip`) — MVP for storage, V2 as a document type
- UTF-8 JSON, compatible with the **W3C Design Tokens (DTCG)** format:
  - Groups become DTCG groups, and swatches become `$type: "color"` tokens.
  - Colorsip metadata (ids, icon, lock, timestamps, order, descriptions) sits under
    `$extensions["app.colorsip"]`.
- It has a `formatVersion` in `$extensions["app.colorsip"]` and is validated against a published **JSON Schema (2020-12)**
  stored at `schema/colorsip-palette.schema.json` in the repo.
- Exported UTI `app.colorsip.palette`, extension `.colorsip`. Double-clicking a file imports it (V2).

## 12. Import and export — V2

| Format | Export | Import |
|---|---|---|
| Colorsip (`.colorsip`) | ✅ | ✅ |
| Adobe Swatch Exchange (`.ase`) | ✅ | — |
| Apple Color List (`.clr`) | ✅ | — |
| JSON (`.json`, simple `{ name, groups: [{ name, colors: [{ name, hex, rgba, oklch }] }] }` for JS use) | ✅ | — |
| PDF | ✅ | — |

- **PDF layout**: one page per palette, with the palette name and description as the header. Each
  group is a section, and each swatch is a tile labeled with its name, HEX, RGB and OKLCH. The PDF
  is tagged with the Display P3 profile.
- Export opens from the palette context menu, the inspector and File ▸ Export. Import opens from
  File ▸ Import, drag and drop, or double-clicking a file. Importing never overwrites a palette: if
  the id is already in the library, the import becomes a copy.
- Groups map to ASE groups. CLR has no groups, so names are flattened to "Group / Name".

## 13. Smart Formats — V3
- In Settings, each app bundle ID can be assigned an output format.
- When Colorsip copies a value, it uses the format assigned to the app that was **frontmost at
  copy time**. When Colorsip itself is frontmost (popover or main window), that means the app that
  was active before Colorsip.
- Cmd+click paste uses the format of the app it pastes into.
- Apps without an assignment use the format dropdown's format.
- Optionally, Colorsip remembers the format: when the user changes the dropdown while app X was
  active, it offers to assign that format to X.

## 14. Templates — V3
- A **template** is a palette skeleton: groups with **named, empty slots** (e.g. "Primary / 500").
- Creating a palette from a template copies the skeleton. **Picking into a template** fills the
  next empty slot in order, and the loupe label shows the name of the slot being filled.
  Clicking a slot makes it the next one to fill.
- Built-in templates:
  - **Tailwind theme**: groups per color (primary, secondary, neutral, …), each with slots
    50–950. Every shade is **picked by hand**; nothing is generated.
  - **Web UI**: primary, secondary, accent, background, surface, text, muted text, border,
    success, warning, error, info.
  - **iOS / macOS / Android UI**: their system semantic color roles.
- Any palette with groups can be **saved as a template**. The template keeps the groups and swatch
  names and clears the colors.

## 15. File-system sync — V3
- Settings ▸ Sync lets the user choose a folder, typically inside Dropbox, OneDrive or Google
  Drive. The library (§11.1) moves into it.
- **Everything syncs**: palettes, Color History, library order and the settings in
  `settings.json`.
- On a fresh install, the user points Colorsip at an existing sync folder and everything comes back
  as it was.
- Colorsip watches the folder (FSEvents / `NSFilePresenter`) and reloads changed files live.
- Conflicts: each file is resolved on its own. The newer `modifiedAt` wins, and the losing version
  is kept as `palettes/<uuid>.conflict-<timestamp>.colorsip` and shown to the user. Conflicted copies
  created by the providers themselves are detected and handled the same way.
- No accounts, cloud APIs or iCloud.

## 16. Non-goals
- Mac App Store builds, sandboxing, pre-built or notarized binaries
- iOS/iPadOS apps
- iCloud or other cloud APIs, user accounts, real-time multi-user collaboration
- User-defined format templates (for now)
- Importing third-party formats (for now)
- Color Dock (may come later)

## 17. Open items
These need answers before or during the release they belong to; none of them block the MVP.
- The same color vision menu sits in two places (toolbar wheel and bottom bar). Keep both or just
  one? (V2)
- PDF layout details (paper size, light/dark background). (V2)
- The exact Tailwind color groups in the template, which could match the Tailwind v4 default
  palette. (V3)
- Fine-tuning the defaults: loupe ranges, the de-duplication ΔE threshold, the Smart Profile list.
  (MVP, after we try them)

## 18. Proposed backlog
These items are filed in xpo, with one top-level epic per release: **MVP** cs-71a6c7, **V2**
cs-db6fed, **V3** cs-05f589. Dependencies are `blocked_by` links in xpo; here they're shown as
"← #n". The issues on the board are the source of truth for status.

### MVP
| # | Issue | Label | Depends on |
|---|---|---|---|
| 1 | Project scaffold: Xcode app (LSUIElement), ColorsipCore package, CI, README, MIT license | task | — |
| 2 | Color model, color spaces and conversions (sRGB, P3, Generic RGB, OKLab/OKLCH, HSL, HSB; ΔEOK equality; gamut mapping) | feature | ← 1 |
| 3 | Output formatters (§5.3) | feature | ← 2 |
| 4 | Color naming with color-name-list | feature | ← 2 |
| 5 | Library model, on-disk storage, `.colorsip` DTCG format and JSON Schema, undo | feature | ← 2 |
| 6 | Menubar status item and popover shell (toolbar, format dropdown, bottom bar, launch at login) | feature | ← 1 |
| 7 | Palette list and swatch strips (groups, fade, horizontal scroll) | feature | ← 5, 6 |
| 8 | Color History | feature | ← 5, 7 |
| 9 | Palette and group management (CRUD, icon picker, description, lock, pick-target radio button) | feature | ← 7 |
| 10 | Drag and drop of swatches (move/copy, uniqueness within a group, drag to other apps) | feature | ← 9 |
| 11 | Compact color editor sheet (HEX, RGB, HSB, HSL, OKLCH, P3, alpha) | feature | ← 3, 9 |
| 12 | Settings window and global shortcuts | feature | ← 6 |
| 13 | Permissions onboarding (Screen Recording, Accessibility) | feature | ← 6 |
| 14 | Picker overlay and loupe (capture, multiple displays, diameter/grid, arrow keys, label) | feature | ← 3, 4, 12, 13 |
| 15 | Picker modes and pick routing (single/multi, Shift+click, Option menu, history/target palette, clipboard) | feature | ← 8, 9, 14 |
| 16 | Cmd+click paste into the active app | feature | ← 15 |
| 17 | Color profiles / Smart Profiles (app under the pointer → profile, settings table) | feature | ← 14, 12 |

### V2
| # | Issue | Label | Depends on |
|---|---|---|---|
| 18 | Main window: three panes, list/grid view, sort, inspector | feature | MVP |
| 19 | Inspector color editor with multi-selection editing | feature | ← 18, 11 |
| 20 | Import/export: Colorsip document type (UTI, double-click import) | feature | ← 5 |
| 21 | Export: ASE, CLR, JSON | feature | ← 20 |
| 22 | Export: PDF | feature | ← 20 |
| 23 | Contrast checker (WCAG 2.x and APCA, fix buttons, shortcut) | feature | ← 2, 12 |
| 24 | Picker contrast mode | feature | ← 23, 15 |
| 25 | Color vision simulation | feature | ← 7 |

### V3
| # | Issue | Label | Depends on |
|---|---|---|---|
| 26 | Smart Formats | feature | ← 3, 12 |
| 27 | Templates (built-in templates, pick into slots, save as template) | feature | ← 9, 15 |
| 28 | File-system sync (folder picker, live reload, conflicts, restore on fresh install) | feature | ← 5 |
