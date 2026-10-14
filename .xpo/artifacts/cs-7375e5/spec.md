# Color model, color spaces and conversions

Refines `spec.md` §5.1. Everything lives in `ColorsipCore`. It is pure Swift math (Foundation only, no CoreGraphics or AppKit at runtime) and is covered by Swift Testing.

## What
A lossless `CSipColor` value type and the math every other feature depends on: conversions between all supported spaces, perceptual equality (ΔEOK), and CSS Color 4 gamut mapping to sRGB with a hex fallback.

## Why
Picker, formatters (cs-86d22b), naming (cs-06fad2), and storage (cs-39dff3) all depend on this. Colors must keep their original space and full precision. Only output may be gamut-mapped.

## Public API

```swift
public enum ColorSpace: String, CaseIterable, Sendable, Codable {
    case srgb, displayP3 = "display-p3", genericRGB = "generic-rgb",
         oklab, oklch, hsl, hwb
}

public struct CSipColor: Sendable, Hashable {
    public var colorSpace: ColorSpace
    public var components: [Double]   // always 3, stored verbatim
    public var alpha: Double          // stored verbatim
    public init(_ space: ColorSpace, _ c0: Double, _ c1: Double, _ c2: Double, alpha: Double = 1)

    public func converted(to space: ColorSpace) -> CSipColor   // unclamped
    public func deltaEOK(_ other: CSipColor) -> Double
    public func isPerceptuallyEqual(to other: CSipColor, threshold: Double = 0.002) -> Bool
    public func gamutMapped(to space: ColorSpace = .srgb) -> CSipColor  // CSS Color 4 algorithm
    public func isInGamut(_ space: ColorSpace) -> Bool
    public var hex: String                                 // "#rrggbb" or "#rrggbbaa"

    // Editor-only HSB (not a storage space); `space` must be an RGB space
    public init(hsb: HSB, in space: ColorSpace = .srgb)
    public func hsb(in space: ColorSpace = .srgb) -> HSB
}
public struct HSB: Sendable, Hashable { hue: 0–360, saturation: 0–1, brightness: 0–1, alpha }
```

## Component conventions (DTCG / CSS Color 4)
| Space | Components |
|---|---|
| srgb, display-p3, generic-rgb | R, G, B in 0–1 (out of range allowed) |
| oklab | L 0–1, a, b (≈ ±0.4) |
| oklch | L 0–1, C ≥ 0, h 0–360 |
| hsl | h 0–360, s 0–100, l 0–100 (sRGB based) |
| hwb | h 0–360, w 0–100, b 0–100 (sRGB based) |

## How
- **Hub:** every space converts through CIE XYZ (D65). There are two shortcuts: sRGB ↔ HSL/HWB, and OKLab ↔ OKLCH.
  - RGB spaces: transfer function → linear → 3×3 matrix to XYZ.
  - OKLab/OKLCH use the CSS Color 4 forward matrices.
  - Inverse matrices are computed, not hard-coded, so round trips are exact to rounding error.
- **sRGB / Display P3:** the sRGB piecewise transfer function, extended symmetrically to negative values (`sign(x)·f(|x|)`). RGB → XYZ matrices are derived from the primaries and D65 (0.3127, 0.3290), the same way CSS Color 4 derives them.
- **Generic RGB:** pure math matching Apple's "Generic RGB Profile" (`/System/Library/ColorSync/Profiles/Generic RGB Profile.icc`):
  - Primaries: R (0.630, 0.340), G (0.295, 0.605), B (0.155, 0.077)
  - White point: D65
  - Transfer: a pure power curve with gamma 1.8, extended symmetrically to negative values
  - A test checks the results against `CGColor.converted` on macOS. They agree to about 3e-5.
- **Achromatic hue:** stored as `0`, not NaN, so components always serialize. This applies to HSL/HWB/HSB when max == min, and to OKLCH when chroma < 1e-7.
- **ΔEOK:** Euclidean distance in OKLab. Alpha is not part of the distance.
- **Perceptual equality:** `isPerceptuallyEqual` needs ΔEOK < threshold **and** `|Δalpha| < 0.002`. The same color at a different alpha is a different swatch.
- **HSB** is an editor helper type, not a stored `ColorSpace`, because DTCG has no HSB.
- **Gamut mapping:** the CSS Color 4 "binary search in OKLCH" algorithm (JND 0.02, ε 0.0001, clip + ΔEOK check). L ≥ 1 → white, L ≤ 0 → black. HSL/HWB map to the sRGB gamut. OKLab/OKLCH are only converted.
- **Hex:** gamut-map to sRGB, then `round(clamp(x)·255)`. It has 6 digits when alpha rounds to `ff`, otherwise 8 digits.
- **Swift `==` / `Hashable`** are exact/structural, because hashing can't use a tolerance. Use `isPerceptuallyEqual` to de-duplicate.

## Acceptance criteria
- [x] `CSipColor` stores space, 3 Float64 components and alpha exactly as given (no clamp, no rounding).
- [x] Round trips between every pair of spaces are within 1e-9 for in-gamut colors (hue compared modulo 360, skipped for achromatic colors).
- [x] Reference values (from CSS Color 4 / colorjs.io) match within 1e-4 for: sRGB ↔ P3, sRGB ↔ OKLab/OKLCH, sRGB ↔ HSL/HWB/HSB.
- [x] Out-of-range components survive conversion (for example, a P3 green converted to sRGB has negative components).
- [x] `isPerceptuallyEqual` is true below ΔEOK 0.002 and false above it, works across spaces, and is false when alpha differs.
- [x] Gamut mapping: in-gamut colors are unchanged. P3 / OKLCH colors outside sRGB map into sRGB with L and h preserved within tolerance. Very light and very dark colors map to white and black.
- [x] `hex` is correct with and without alpha, and for out-of-gamut input.
- [x] Generic RGB conversion matches CoreGraphics within 1e-4 (test only, macOS).

## Out of scope
- Codable / the JSON `{colorSpace, components, alpha, hex}` shape (cs-39dff3)
- Format strings (cs-86d22b)
- Adobe RGB (optional in §5.1, can be added later)

## Decisions
1. **Alpha in equality** (user): colors with different alpha are not equal.
2. **HSB** (user): an editor helper type, not a storage space.
3. **Generic RGB** (user): pure math, not CoreGraphics at runtime. CoreGraphics clamps ICC conversions to 0–1, uses a D50 reference space, and would give this one space a different conversion path. CoreGraphics is used only as a test oracle.
4. **Hex alpha** (agent): use 8 digits only when alpha doesn't round to `ff`. This avoids output like `#rrggbbff` for alpha 0.999.
5. **Type name** (user): `CSipColor`, not `Color`, so it does not clash with `SwiftUI.Color` in the app, which imports both modules.
