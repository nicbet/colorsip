# Output formatters

Refines `spec.md` §5.3. Logic lives in ColorsipCore.

## What
Turn a `CSipColor` into the string for each `OutputFormat`, ready to copy or paste.

## Why
Copying, "Copy as" and the loupe label (cs-40b6c9, cs-523d6a, cs-722793) all need these strings.

## API
```swift
extension OutputFormat {
    public func string(for color: CSipColor) -> String
}
extension CSipColor {
    public func formatted(as format: OutputFormat) -> String   // calls the method above
}
```

## Rules per format
Examples use sRGB `#3c3cdb` for the CSS and Android rows and the §5.1 Display P3 color
(0.2364, 0.2353, 0.8588) for the Display P3 and Apple rows.

| Format | Target space | Output (opaque / with alpha 0.8) |
|---|---|---|
| CSS Hex | sRGB, gamut-mapped | `#3c3cdb` / `#3c3cdbcc` (reuses `CSipColor.hex`) |
| CSS Hex (no #) | sRGB, gamut-mapped | `3c3cdb` / `3c3cdbcc` |
| CSS RGB | sRGB, gamut-mapped | `rgb(60 60 219)` / `rgb(60 60 219 / 80%)`, whole numbers (8-bit) |
| CSS HSL | sRGB, gamut-mapped | `hsl(240 68.83% 54.71%)` / `… / 80%)`, up to 2 decimals |
| CSS OKLCH | OKLCH, no mapping | `oklch(47.5% 0.233 273.1)` / `… / 80%)`. L is a percentage with up to 1 decimal, C has up to 3 decimals, h has up to 1 decimal |
| CSS Display P3 | P3, gamut-mapped to P3 | `color(display-p3 0.236 0.235 0.859)` / `… / 80%)`, up to 3 decimals |
| SwiftUI | see decision 1 | `Color(.displayP3, red: 0.236, green: 0.235, blue: 0.859, opacity: 1)` |
| NSColor | see decision 1 | `NSColor(displayP3Red: 0.236, green: 0.235, blue: 0.859, alpha: 1)` |
| UIColor | see decision 1 | `UIColor(displayP3Red: 0.236, green: 0.235, blue: 0.859, alpha: 1)` |
| Android | sRGB, gamut-mapped | `0xFF3C3CDB` / `0xCC3C3CDB` |
| Android (XML) | sRGB, gamut-mapped | `#FF3C3CDB` / `#CC3C3CDB` |

Shared rules:
- Decimal numbers drop trailing zeros (`1`, `0.5`, `0.236`), never print `-0`, and always use `.` as the decimal separator, whatever the locale.
- CSS alpha is a percentage with up to 1 decimal. It is left out when alpha rounds to 100%.
- Code formats (SwiftUI, NSColor, UIColor) always include alpha/opacity, with up to 3 decimals.
- Hue values are normalized to 0..<360; values that round to 360 are written as 0. Achromatic colors have hue 0.
- Hex is lowercase. Android is uppercase and always includes alpha (AARRGGBB).

## Decisions
1. **Apple code formats choose a space** (user-approved). If the color is stored in sRGB, HSL or HWB, the output uses sRGB, gamut-mapped to sRGB: `Color(.sRGB, red:…, opacity:…)`, `NSColor(srgbRed:…)`, `UIColor(red:…)`. Any other color (P3, Generic RGB, OKLab, OKLCH) uses Display P3, gamut-mapped to P3.
2. **Android has two forms** (user-approved). `android` ("Android", `0xFF3C3CDB`, for Kotlin/Java) and `androidXML` ("Android (XML)", `#FF3C3CDB`, right after it). The catalogue test is updated.
3. **Precision** (user-approved). Storage stays lossless (§5.1). Output strings only need to be precise enough that no difference is visible: about 8-bit precision. HSL gets 2 decimals at the user's request.

## Acceptance criteria
- [x] Every format produces the string in the table, for opaque and translucent colors.
- [x] A P3 color outside sRGB is gamut-mapped (CSS Color 4 OKLCH chroma reduction) for Hex, RGB, HSL and Android, and stays unmapped in OKLCH and Display P3.
- [x] A color outside P3 (for example, an extreme OKLCH color) is gamut-mapped to P3 for Display P3 and for the Apple code formats when they use P3.
- [x] Apple code formats use sRGB for sRGB/HSL/HWB colors and Display P3 for others.
- [x] Rounding edge cases: hue 359.996 is written as 0, alpha 0.9999 is written as opaque in CSS, no `-0`, `.` as decimal separator (`String(format:)` is locale-independent).
- [x] Unit tests for every format, in `OutputFormatTests.swift`.

## Out of scope
Parsing strings back into colors, user-defined templates (V3 Smart Formats), and the UI that copies the strings.
