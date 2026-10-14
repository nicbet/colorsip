# Walkthrough: Picker overlay and loupe

## What was built
Hyper+P or the popover's eyedropper opens the picker (`spec.md` §4.1–4.3): a transparent overlay on
every screen and a circular loupe in place of the pointer. The loupe magnifies the pixels around
the pointer, outlines the center pixel, and has a label with the value in the active format and its
friendly name.
- The wheel resizes the loupe (120–400 pt). Option + wheel changes the grid (5–31, odd).
- Arrow keys move 1 pixel, Shift + arrow 10.
- Esc cancels. Click, Return or Space picks.
- The loupe size is saved once, when the picker closes.

Until cs-995046 routes picks, a pick only copies the value in the active format
(`AppDelegate`: `pickerController.onPick`).

## How the pieces fit

### Core (`ColorsipCore`, all unit-tested)
- `PickerGeometry.swift`
  - `PickerDisplay`: id, frame in global AppKit points, scale.
  - `PickerGeometry`: point ↔ pixel conversion. Pixels use a top-left origin, which matches the
    capture's layout. `moved` snaps to a pixel center and stops at the display edge, so arrow keys
    never jump displays.
  - `PixelGrid`: the n × n cells around the center. Cells off the display are `nil`, so the center
    cell is always the pointer's pixel, even at an edge.
  - `PixelSampler`: decodes the three capture formats (half float, `l10r`, BGRA) into `PixelSample`
    (Doubles). The half-float decoder is hand-written because `Float16` doesn't exist on x86_64
    macOS.
  - `CaptureColor`: ColorSync conversion from the frame's color space to *extended* Display P3, so
    nothing is clipped.
- `PickerSession.swift`
  - `LoupeScroll`: makes up = +1 step for natural and classic scrolling alike. A wheel notch is one
    step; trackpad travel accumulates 20 pt per step and resets when the direction changes.
  - `LoupeLayout`: the loupe is centered on the pointer. The label goes below it, flips above near
    the bottom edge, and is kept inside the display.
  - `PickerSession`: the observable state the overlay renders. Moving to another display clears the
    samples, because the old display's frame doesn't apply to the new one. `finish(.pick)` returns
    `nil` until there is a sample, so a click before the first frame does nothing.

### App (thin; verified by hand)
- `PickerController`
  - Opens one `PickerOverlayPanel` per screen at `.screenSaver` level. The panels join all Spaces
    and full-screen apps. `ignoresMouseEvents = false` is set explicitly, because otherwise clicks on
    a transparent window pass through to the app below.
  - Hides the cursor and routes input through a local event monitor, like `ShortcutRecorder` does.
  - Arrow keys warp the real pointer (`CGWarpMouseCursorPosition` +
    `CGAssociateMouseAndMouseCursorPosition`, which avoids the post-warp freeze).
  - Trackpad momentum scrolls are ignored. A screen configuration change cancels the picker.
- `ScreenSampler`
  - Runs one `SCStream` for the display under the pointer and switches streams on display change.
    A generation counter drops late frames and starts from the previous display.
  - Colorsip's own app is excluded from the filter, so the overlay never shows up in the loupe.
  - Idle frames (`SCFrameStatus` other than `.complete`) are skipped. Frames in a pixel format other
    than the one requested are dropped.
  - The format and color space of the first frame are logged (category `picker`).
- `LoupeView` draws the grid as a float `CGImage` in the frame's color space, with nearest-neighbor
  scaling, grid lines, a black and white center outline, a ring, and the label capsule.
- `TestPages/picker-swatches.html` (linked from the README): sRGB and P3 swatches labelled with
  values from Core's own formatters, plus 1-pixel patterns for checking the grid and arrow keys.

## Key decision: capture color space and precision
The first version sampled 8-bit BGRA in the display's native profile, as `spec.md` first said. On
the test page, `#ffff00` read as `#feff00`. Reproducing the chain off-screen showed two separate
problems:
1. **8-bit capture through a wider space is lossy.** Display P3 at 8 bits is off by one for about
   half of all 8-bit sRGB colors. Gamma-encoded half floats still fail near black (`#03d200` →
   `#04d200`). **Linear** half floats round-trip every 8-bit sRGB color, because float precision is
   relative, which suits the sRGB curve's steep part near black.
   `sRGBBytesRoundTripThroughLinearHalfFloatP3` checks this.
2. **The display's profile clips.** An external LG 32UN880-B uses macOS's EDID-derived profile,
   whose gamut doesn't contain sRGB blue or yellow. Apps draw their windows already matched to that
   profile, so the clipping happens before any capture.

So the stream now requests `extendedLinearDisplayP3` with `kCVPixelFormatType_64RGBAHalf`. It falls
back to `l10r`, then BGRA, and logs the fallback. This removed all error of our own: cyan went from
`#03ffff` to exact. On a display that clips, values stay as the screen shows them (measured:
`#0000ff` → `#1a00ff`, `#ffff00` → `#feff00`, `#3c3cdb` → `#3c3bdc`). Other pickers read the same
pixels the same way.

We decided **not** to reverse-search source values from the display profile:
- The remaining errors don't match ColorSync's math exactly; Safari or the GPU converts slightly
  differently.
- For clipped colors, several source values render to the same pixel, so the search would have to
  guess.

`spec.md` §4.2 and §6 were updated to match. §6 no longer has a "Display native" profile, since
samples are never in the display's profile. That matters for cs-615265.

## Things a future reader should know
- **Prompt on macOS 15+:** the "bypass the system private window picker" alert is macOS's, shown
  for any direct ScreenCaptureKit capture, and macOS repeats it periodically. There's no supported
  way around it for a locally built app; `NSColorSampler` avoids it, but the user chose to keep the
  custom loupe.
- **Scaled resolutions:** a "looks like 3360 × 1890" mode renders at 2× and is scaled down to the
  panel. The loupe and arrow keys work in rendered pixels, so 1-pixel patterns look crisp in the
  loupe even though they look gray on the panel.
- **Frame buffers:** `ScreenFrame` keeps the latest `CVPixelBuffer` alive, which takes one of the
  stream's three queue slots.
