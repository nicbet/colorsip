# Walkthrough: Output formatters

## What was built
`OutputFormat.string(for:)` turns a `CSipColor` into the text for each format in `spec.md` §5.3. `CSipColor.formatted(as:)` is a shortcut for it. Copy, "Copy as" and the loupe label will call this. A new case, `androidXML` ("Android (XML)"), sits after `android`.

All the code is in `Packages/ColorsipCore/Sources/ColorsipCore/OutputFormat.swift`. The tests are in `OutputFormatTests.swift`.

## How it works
Each format picks a target space and then prints numbers:

- **sRGB formats** (Hex, Hex without #, RGB, HSL, Android): `gamutMapped(to: .srgb)` (or `.hsl`, which maps within the sRGB gamut). Hex reuses `CSipColor.hex`. Android builds AARRGGBB from `CSipColor.byte`, which is now internal so both share the same 8-bit rounding.
- **OKLCH**: `converted(to: .oklch)`. OKLCH is unbounded, so it is never mapped.
- **Display P3**: `gamutMapped(to: .displayP3)`. P3 colors pass through unchanged, and only colors outside P3 are reduced.
- **SwiftUI / NSColor / UIColor** (`appleCode(for:)`): colors stored in sRGB, HSL or HWB use the sRGB initializers (`Color(.sRGB…)`, `NSColor(srgbRed:…)`, `UIColor(red:…)`), gamut-mapped to sRGB. All others use the Display P3 initializers, gamut-mapped to P3. A color from a hex code then reads like the hex, and wide-gamut colors stay intact.

## Number formatting
Every number goes through `OutputFormat.number(_:decimals:)`. It:

- rounds to at most `decimals` places;
- turns `-0` into `0` (`rounded` checks `r == 0`);
- prints with `String(format:)`, which is locale-independent, so the separator is always `.`;
- drops trailing zeros and a trailing dot.

Precision is set at about 8-bit precision: storage is lossless (§5.1), so output only has to be precise enough that no difference is visible. The user decided this in review:

| Value | Decimals |
|---|---|
| RGB | 0 (0–255) |
| HSL | 2 (the user's choice) |
| OKLCH | L% 1, C 3, h 1 |
| P3 and Apple formats | 3 |
| CSS alpha | 1 (as a percentage) |

`hue(_:decimals:)` normalizes a hue to 0..<360 before and after rounding, so 359.996 and -0.01 both print as `0`. `cssAlpha` leaves out the ` / x%` suffix when alpha rounds to 100%. The Apple formats always print alpha, because their initializers require it.

## Things to know
- Spec examples in `spec.md` §5.3 use the P3 color from §5.1, not `#3c3cdb`. For `#3c3cdb`, the outputs are `hsl(240 68.83% 54.71%)` and `oklch(47.5% 0.233 273.1)`.
- The tests read numbers back out of the output strings (the `numbers` helper) to check gamut bounds without restating the mapping algorithm.
