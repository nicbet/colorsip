# cs-40b6c9 — Picker overlay and loupe

Refines `spec.md` §4.1–4.3.

## What
Opening the picker (Hyper+P or the popover's eyedropper) covers every display with a transparent
overlay and replaces the pointer with a circular loupe. The loupe shows a magnified grid of the
physical pixels around the pointer with the center pixel outlined. A label under it shows the
center pixel's value in the active format and its friendly name. The mouse wheel resizes the loupe,
Option + wheel changes the grid size, arrow keys nudge by physical pixels, and Esc cancels.

## Why
The picker is the app's core feature. Pick routing and modes (cs-995046) and Smart Profiles
(cs-615265) build on this overlay, its sampling and its label.

## Scope
**In:** overlay windows, capture, loupe and label drawing, wheel / Option + wheel, arrow keys, Esc,
a minimal pick (click, Return or Space picks the center color, closes the picker and hands the
color to an `onPick` callback), and a manual test page of known swatches (`TestPages/picker-swatches.html`).

**Out:**
- Where picks go (history, palettes, clipboard), Shift+click, multi mode, Option mode menu →
  cs-995046. Until then `onPick` only copies the value in the active format, so the picker is usable.
- Converting to a per-app target profile and the profile badge → cs-615265. Samples arrive as
  extended Display P3; there is no "Display native" profile any more (`spec.md` §6).
- Cmd+click paste → cs-901e7e.

## Design

### Core (`ColorsipCore`, test-driven)
1. **`PickerDisplay`**: `id: UInt32`, `frame` (global points, AppKit coordinates: origin bottom-left
   of the primary display, y up), `scale` (pixels per point). Size in pixels = frame × scale.
2. **`PickerGeometry`** (pure functions over `[PickerDisplay]`):
   - `display(at point)`: the display whose frame contains the point (min-inclusive,
     max-exclusive); `nil` between displays.
   - `pixel(at point, on display) -> PixelPoint`: display-local pixel, origin top-left, y down
     (the capture's layout): `floor((x − minX) × scale)`, `floor((maxY − y) × scale)`, clamped into
     the display.
   - `point(of pixel, on display)`: the center of that pixel in global points.
   - `moved(point, dx, dy, on display)`: snaps to the current pixel, moves by `dx`/`dy` physical
     pixels (`dy` positive = down), clamps to the display, returns the new pixel's center. Arrow
     keys never cross to another display.
3. **`PixelGrid`**: for a center pixel, a grid size `n` (odd) and the display's pixel size, the
   `n × n` pixel coordinates around it. Cells outside the display are `nil` (drawn empty), so the
   center cell is always the pointer's pixel, even at screen edges.
4. **`PixelSampler`**: reads rows (`width`, `height`, `bytesPerRow`, bytes) in one of the capture
   formats and returns the grid's colors as `PixelSample?` (Double RGBA in the frame's color space)
   per cell:
   - `.rgbaHalf` (`kCVPixelFormatType_64RGBAHalf`, preferred), decoded without `Float16` so it also
     builds for x86_64;
   - `.argb2101010` (`l10r`, fallback): 32-bit little-endian words, A bits 30–31, R 20–29, G 10–19,
     B 0–9;
   - `.bgra8` (last resort).
5. **`CaptureColor`**: turns a sample in the frame's `CGColorSpace` into a `CSipColor` in
   **Display P3**, through ColorSync with an extended destination, so nothing is clipped.
   Round-trip guarantee (tested): every 8-bit sRGB color, converted to **linear** Display P3 and
   stored as half floats, comes back with the same CSS Hex. Gamma-encoded half floats don't (e.g.
   `#03d200` → `#04d200`): float precision is relative, which suits linear values near black.
6. **`LoupeScroll`**: turns scroll events into steps. Input: `deltaY`, `hasPreciseDeltas`,
   `isDirectionInvertedFromDevice`, `option`.
   - Physical direction is normalized: wheel up / two-finger swipe up = **+1 step**, for both
     natural and classic scrolling.
   - A mouse wheel notch (imprecise delta) is one step. Trackpad (precise) deltas accumulate; each
     20 pt of travel is one step. The accumulator resets when the direction changes.
   - A step changes `diameter` by ±20 pt (without Option) or `gridSize` by ±2 (with Option).
     Clamping is `LoupeSettings`'s.
7. **`LoupeLayout`**: from the pointer point, diameter, label size and the display's frame:
   the loupe frame is centered on the pointer (it may be clipped at screen edges, like the pointer
   it replaces). The label sits 8 pt below the loupe, centered; if it doesn't fit, it goes above.
   It is shifted horizontally to stay inside the display.
8. **`PickerSession`** (`@MainActor @Observable`): the state the overlay renders.
   - `init(displays:, loupe: LoupeSettings, start point)`.
   - `point`, `display`, `pixel`, `loupe` (in-session copy), `centerColor: CSipColor?`.
   - `pointerMoved(to:)`, `arrow(_ direction, shift:)` (1 or 10 pixels; returns the point to
     warp the real pointer to), `scroll(...)`, `sampled(grid:center:)`.
   - `label(format:)` → `(value: String, name: String)` for the center color, or `nil` before the
     first sample.
   - `finish(.pick | .cancel)` → `PickerOutcome?` (`.picked(CSipColor)` / `.cancelled`; `nil` for a
     pick before the first sample). The caller saves `session.loupe`.
   - Loupe size is saved to `settings.json` **once when the picker closes**, not on every wheel
     notch.

### App (thin, verified by hand)
- **`PickerController`** owns one session at a time; opening while open is ignored.
  - Remembers nothing about the frontmost app yet (cs-901e7e).
  - One borderless, transparent `NSPanel` per `NSScreen` at `.screenSaver` level, joining all
    spaces and full-screen apps, accepting mouse and key events. The app activates so the panel can
    be key. The system pointer is hidden while the picker is open and shown again on close.
  - Mouse moved/dragged → `pointerMoved`. Arrow keys → `arrow`, then `CGWarpMouseCursorPosition`
    so the real pointer follows. Scroll → `scroll`. Click / Return / Space → pick; Esc → cancel.
    Screen configuration changes while open cancel the picker.
- **`ScreenSampler`**: one `SCStream` for the display under the pointer, at native pixel size,
  `colorSpaceName` extended linear Display P3, pixel format half float (falling back to `l10r`,
  then BGRA, if the stream won't start; the fallback is logged; frames in another pixel format than
  requested are dropped), up to 60 fps, excluding Colorsip's own windows. The
  frame's color space comes from its attachments (fallback: Display P3), so linear or encoded
  float output both convert correctly. It switches streams when the pointer moves to another
  display. Each frame and each pointer move re-samples the grid from the latest frame.
- **Why not the display's native space:** a calibrated panel profile can clip sRGB colors (measured
  on a built-in display: sRGB blue → native red 0.0, giving `#1b00ff`; yellow → `#feff00`), and
  8-bit capture through a wider space is off by one for about half of all 8-bit sRGB colors. Other
  pickers (Digital Color Meter, for example) show the same errors.
- **`LoupeView`** (AppKit `NSView`, in the overlay of the pointer's display): the grid image
  scaled with nearest-neighbor, clipped to a circle, tagged with the display's color space so it
  looks like the screen. Thin grid lines, a two-tone (black/white) outline around the center
  pixel, and a ring around the loupe. The label is a rounded capsule with the value (monospaced)
  and the name.
- `AppDelegate`'s picker closure (already gated on Screen Recording) opens the picker. `onPick`
  copies the value in the active format (stand-in until cs-995046).

### Manual test page (`TestPages/picker-swatches.html`)
A static page, opened in Safari, for checking picked values against known ones:
- **sRGB swatches** (CSS hex): primaries, secondaries, grays (black, 50%, white) and a few
  mid-tones such as `#3c3cdb`. Each is labelled with its expected CSS Hex. Picking with "CSS Hex"
  should give the same value, ±1 per channel.
- **Display P3 swatches** (`color(display-p3 …)`), some inside sRGB and some outside it (e.g. P3
  red and green). Each is labelled with its expected "CSS Display P3" value; picking with that format
  should match within ±0.004 per channel on a P3 display. Out-of-sRGB swatches also list the expected
  gamut-mapped CSS Hex.
- **Pixel patterns**: a canvas drawn at `devicePixelRatio` with 1-physical-pixel stripes and a
  checkerboard, to check that the grid shows physical pixels and arrow keys step one pixel.
- A short note at the top on how to use it (which format to select, which tolerance to expect).
- README ▸ Development points to it.

## Edge cases
- Pointer between displays (gaps in the arrangement): the session keeps the last display and pixel.
- Grid at the edge of a display: off-screen cells are empty (transparent with grid lines).
- Mixed scale displays (1× + 2×): pixel math is per display; arrow keys move one physical pixel of
  the current display.
- The first frame isn't in yet: the loupe shows an empty grid and no label; click does nothing.
- Screen Recording revoked mid-session: the stream errors and the picker cancels.
- Full-screen apps and other Spaces: the panels join all Spaces.

## Acceptance criteria
- [x] Hyper+P and the toolbar eyedropper open the picker over every display.
- [x] The loupe follows the pointer across displays with different scale factors and profiles.
- [x] The grid shows the pixels around the pointer, with the center pixel outlined; it matches the
      screen (no feedback of the overlay itself).
- [x] Wheel changes the diameter 120–400 pt in 20 pt steps (default 200). Option + wheel changes
      the grid 5–31, odd only (default 11). Both are remembered after the picker closes.
- [x] Arrow keys move 1 physical pixel, Shift + arrow 10. Esc cancels.
- [x] The label shows the value in the active format and the friendly name.
- [x] Click, Return or Space picks the center color and closes the picker (value copied until
      cs-995046).
- [x] Picking the swatches on the test page reports exactly what the screen shows: Colorsip adds no
      error of its own (linear half-float capture). Where the display's profile can't hold a color,
      the app drawing it has already clipped or rounded it before capture. Measured on an LG
      32UN880-B with its EDID-derived profile: `#0000ff` → `#1a00ff`, `#ffff00` → `#feff00`,
      `#3c3cdb` → `#3c3bdc`; other pickers are off the same way. No picker can recover source values
      from pixels there.
- [x] Core logic (geometry, grid, sampling, color conversion, scroll steps, layout, session) is
      covered by Swift Testing tests.

## Not covered by automated tests
Overlay windows, ScreenCaptureKit streams, pointer hiding and warping, and drawing. Verified by hand
on a 2× built-in display plus a 1× external display, using the test page.
