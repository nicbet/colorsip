# Color naming with color-name-list

Refines `spec.md` §5.5. Logic lives in ColorsipCore.

## What
Give any `CSipColor` a friendly name: the nearest entry by ΔEOK in the bundled
meodai/color-name-list.

## Why
Swatches are auto-named on pick (§5.2), and the loupe label shows the name live under the pointer
(§4.2, cs-40b6c9). The loupe calls this on every pointer move, so lookup must be fast.

## Data
- Bundle the **full** `colornames.csv` from the `color-name-list` npm package, pinned to
  **v14.54.2** (31,935 entries, 669 KB). Updates are manual. Format: header `name,hex`, then
  `Name,#rrggbb`. No quoting, no commas in names, no duplicate hexes (checked).
- Location: `Packages/ColorsipCore/Sources/ColorsipCore/Resources/colornames.csv`, declared as a
  SwiftPM resource (`.copy`), loaded via `Bundle.module`.
- License: the upstream MIT `LICENSE` is copied next to it as `Resources/color-name-list-LICENSE`.
  The README gets a "Third-party" section crediting meodai/color-name-list (MIT, David Aerne) with
  the pinned version. No in-app credit for now.

## API
```swift
public struct ColorName: Sendable, Hashable {
    public let name: String
    public let color: CSipColor     // the entry's sRGB color
}

public final class ColorNames: Sendable {
    /// The bundled list, loaded and indexed on first use.
    public static let shared: ColorNames
    /// Builds an index from `name,#rrggbb` CSV text (header line optional).
    public init(csv: String)
    public var count: Int { get }
    /// The nearest entry by ΔEOK. Alpha is ignored. `nil` only if the list is empty.
    public func nearest(to color: CSipColor) -> ColorName?
}

extension CSipColor {
    /// Shortcut for `ColorNames.shared.nearest(to:)?.name`.
    public var friendlyName: String { get }
}
```

## Index
- On init, each entry's hex is parsed as sRGB and converted to OKLab once.
- The points go into a static, balanced **3-d k-d tree** in OKLab, built once by recursive median
  split cycling through L, a, b. It is stored implicitly in a flat array (median at the middle of
  each sub-range), so there are no node allocations.
- Nearest-neighbour search: descend to the query's side first, then visit the far side only when
  the squared distance to the split plane is ≤ the best squared distance so far. Distances are
  squared `Double`s (no sqrt).

## Rules and edge cases
- Exact list colors return their own name (e.g. `#c93f38` → "100 Mph").
- Ties: the entry that comes first in list order wins (deterministic). The search compares
  (distance, list index), and the far side is still visited when the plane distance equals the
  best, so ties can't be pruned away.
- Out-of-gamut and wide-gamut colors (P3, extended values) are named by their OKLab position; no
  gamut mapping first.
- Any input space works (it goes through OKLab).
- Malformed CSV lines are skipped, not fatal.
- `shared` is lazily initialized (Swift `static let`), thread-safe. Loading happens once; the app
  may warm it at launch.

## Out of scope
- Wiring into swatch creation and the loupe label (cs-40b6c9 and the picks/palette issues).
- Localized names, alternative lists (e.g. "bestof"), an update script, in-app credits.

## Acceptance criteria
- [ ] CSV and MIT license bundled as ColorsipCore resources; README credits the list.
- [ ] `ColorNames.shared.count` == 31,935.
- [ ] Exact hits: several list hexes return their names.
- [ ] The k-d tree agrees with a brute-force ΔEOK reference (using `CSipColor.deltaEOK`) on many
      random colors, including out-of-gamut ones.
- [ ] Works for P3, OKLCH, HSL inputs, and ignores alpha.
- [ ] Tie → first entry; empty list → `nil`; malformed lines skipped.
- [ ] Performance test: 10,000 lookups on the full list in < 1 s total in debug.
