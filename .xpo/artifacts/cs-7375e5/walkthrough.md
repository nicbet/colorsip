# Walkthrough: color model, color spaces and conversions

## What was built
`ColorsipCore` now has the color model everything else depends on (`spec.md` §5.1):

- `CSipColor`: a color space, three `Double` components and alpha. They are stored exactly as given, with no clamping or rounding.
- `ColorSpace`: `srgb`, `display-p3`, `generic-rgb`, `oklab`, `oklch`, `hsl`, `hwb`. The raw values are the CSS Color 4 / DTCG names, so the storage work in cs-39dff3 can serialize them directly.
- Conversion between every pair of spaces, ΔEOK, perceptual equality, CSS Color 4 gamut mapping, an sRGB `hex` fallback, and an editor-only `HSB` type.

The type is called `CSipColor`, not `Color`, because the app imports both SwiftUI and ColorsipCore, and a bare `Color` would be ambiguous there.

## Files
| File | Contents |
|---|---|
| `CSipColor.swift` | `ColorSpace`, `HSB`, and `CSipColor`'s public API |
| `Conversion.swift` | The math: the XYZ hub, OKLab/OKLCH, HSL/HWB, the RGB spaces (`RGBSpace`), and `Vector3`/`Matrix3` |
| `GamutMapping.swift` | `gamutMapped(to:)`, the CSS Color 4 binary search |

## How conversion works
`Conversion.convert` routes every conversion through CIE XYZ with a D65 white point. There are two shortcuts:
- sRGB ↔ HSL/HWB, because HSL and HWB are defined on sRGB.
- OKLab ↔ OKLCH, because it is only a polar transform.

Every space we support uses D65, so no chromatic adaptation is needed anywhere.

**RGB spaces** (`RGBSpace`) are defined by their primaries and transfer function. The RGB → XYZ matrix is derived from the primaries and D65 (0.3127, 0.3290) in the standard way, and the inverse is computed. The OKLab matrices are the CSS Color 4 forward matrices, and their inverses are computed too. Because no inverse is hard-coded at limited precision, every round trip is exact to about 1e-15. The tests require 1e-9 for every pair of spaces.

**Transfer functions** extend to negative values by symmetry (`sign(x)·f(|x|)`), as in CSS Color 4. This keeps out-of-gamut values lossless: a Display P3 green becomes sRGB `(-0.51, 1.02, -0.31)` and converts back exactly.

**Generic RGB** is pure math matching Apple's "Generic RGB Profile" ICC file. The profile stores its primaries adapted to D50 in its `rXYZ`/`gXYZ`/`bXYZ` tags. Undoing its `chad` (Bradford) matrix gives primaries (0.630, 0.340), (0.295, 0.605), (0.155, 0.077), a D65 white point, and gamma 1.8. The profile encodes the gamma as 1.80078125, but the difference is negligible. We chose not to call CoreGraphics at runtime, for three reasons:
- ColorSync clamps ICC conversions to 0–1.
- It works through a D50 reference space.
- It would give this one space a different conversion path from the others.

Instead, `GenericRGBTests` uses CoreGraphics as a test oracle. The two agree to about 3e-5 (ColorSync computes in Float32), and the test tolerance is 1e-4.

**Hue** is shared by HSL, HWB and HSB (`Conversion.hue`). Achromatic colors store hue `0` rather than NaN, so components always serialize. For OKLCH, "achromatic" means chroma below 1e-7, because white converted from sRGB has chroma of about 1e-8 from rounding.

## Equality
- Swift `==` and hashing are exact (synthesized), because a hash can't use a tolerance.
- De-duplication uses `isPerceptuallyEqual`: ΔEOK < 0.002 **and** an alpha difference below 0.002. The user decided that the same color at a different alpha is a different swatch.

## Gamut mapping and hex
`gamutMapped(to:)` follows https://www.w3.org/TR/css-color-4/#binsearch:
- Colors with L ≥ 1 become white and colors with L ≤ 0 become black.
- In-gamut colors are only converted.
- Otherwise, a binary search reduces OKLCH chroma until clipping the result moves it by less than JND 0.02.

`ColorSpace.gamutSpace` says which RGB gamut bounds a space: HSL and HWB map to the sRGB gamut, and OKLab/OKLCH have no gamut.

`hex` gamut-maps to sRGB and rounds to 8 bits. It adds two alpha digits only when alpha doesn't round to `ff`, so alpha 0.999 doesn't produce `#rrggbbff`.

## HSB
HSB is not a `ColorSpace`, because DTCG has no HSB. `CSipColor(hsb:in:)` and `hsb(in:)` work in an RGB space (sRGB, P3 or Generic RGB), so the editor can show HSB for a P3 color without leaving P3. Passing a non-RGB space triggers a precondition failure.

## Tests
- `CSipColorTests.swift`: storage, published reference values (CSS Color 4 / colorjs.io), round trips between all pairs, out-of-range values, equality, gamut mapping, hex, HSB.
- `GenericRGBTests.swift`: comparison with ColorSync (macOS only, `#if canImport(CoreGraphics)`).
- `TestSupport.swift`: tolerance helpers that compare hues modulo 360.
