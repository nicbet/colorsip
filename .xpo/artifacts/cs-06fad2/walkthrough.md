# Walkthrough: Color naming with color-name-list

## What was built
`ColorsipCore` can now name any color (`spec.md` §5.5). The name is the nearest entry by ΔEOK
in the bundled meodai/color-name-list:

```swift
ColorNames.shared.nearest(to: color)   // ColorName? (name + sRGB color)
color.friendlyName                      // String
```

Swatch auto-naming and the loupe label (cs-40b6c9) will call this. The loupe calls it on every
pointer move, so lookups have to be fast.

Files:
- `Sources/ColorsipCore/ColorNames.swift`: `ColorName`, `ColorNames`, `CSipColor.friendlyName`.
- `Sources/ColorsipCore/Resources/colornames.csv` and `color-name-list-LICENSE`: the data and its
  MIT license, declared as `.copy` resources in `Package.swift`.
- `Tests/ColorsipCoreTests/ColorNamesTests.swift`.
- `Conversion.swift`: `Vector3` gained `lengthSquared` and an axis subscript (`v[0]` is x).
- `README.md`: a "Third-party" section with the credit and steps for updating the list.

## The data
The full `dist/colornames.csv` of the `color-name-list` npm package, pinned to **v14.54.2**
(31,935 entries, 669 KB). Updates are manual. The README lists the three places to touch: the
CSV, the version comment in `Package.swift` and the README, and the entry count in
`loadsTheFullList()`. (The user asked for "14.52.2", but that version doesn't exist on npm, so it
was read as a typo for 14.54.2.)

The format is plain: a `name,hex` header, then `Name,#rrggbb`. There's no quoting, and no hex
appears twice. The parser still copes with bad input: it splits at the **last** comma, requires a
non-empty name and exactly `#` + 6 hex digits, and skips any line that doesn't match (which also
skips the header). It checks `isHexDigit` explicitly, because `Int(_:radix:)` alone would accept
`#+12345`.

`ColorNames.shared` loads the file from `Bundle.module`. If the resource is missing it calls
`preconditionFailure`, because that's a build error, not a runtime condition. In the app, the file
ends up at `Colorsip.app/Contents/Resources/ColorsipCore_ColorsipCore.bundle/…`.

## The index: a static k-d tree in OKLab
ΔEOK is the Euclidean distance in OKLab, so finding the nearest name is a 3-d nearest-neighbour
search. The user chose a k-d tree over a linear scan.

- **Build** (once, in `init`): every entry is converted to OKLab (`points`, indexed by list
  position). `tree` starts as the list indices. `build` sorts each sub-range on the current axis,
  puts the median in the middle, and recurses on both halves, cycling through L, a, b. The tree is
  **implicit**: a node is the middle element of its range, its left subtree is the range before
  it, and its right subtree is the range after it. So it's one flat `[Int]` with no node objects.
- **Search**: visit the node and update the best match. Then descend into the side the query
  falls on, and visit the far side only if the squared distance to the split plane is ≤ the best
  squared distance. Everything works on squared distances, with no square roots.

### Ties
The spec says the first entry in list order wins. Two details make that hold with a tree:
1. The best-match update compares `(distance, list index)`, not just distance.
2. The prune test is `<=`, not `<`. Entries equal on the split axis can sit on either side of the
   median, so an equally close entry with a lower index could be on the far side. With `<`, it
   could be pruned away.

## Tests
- **The tree against brute force**: 300 random Display P3 colors with components in −0.1…1.1, so
  some are out of gamut, checked on the full list. Random lists of 1, 2, 3, 7 and 50 entries cover
  the edges of the tree. The brute-force reference uses `deltaEOK` over OKLab values it computes
  once itself. A first version converted every entry for every query and took 13.7 s; this one
  takes ~3.6 s in debug.
- Exact hits ("100 Mph", "Black", "White", …), the count (31,935), every input space, and alpha
  being ignored.
- Ties (three entries with the same hex → "First"), an empty list → `nil`, malformed lines and
  `\r\n` line endings.
- Speed: 10,000 lookups must take under 1 s. They actually take ~70 ms in debug, so ~7 µs each.

## Things to know
- **First use is slow in debug builds**: ~0.86 s to parse, convert and build the tree, once, on
  first use of `ColorNames.shared` (a lazy, thread-safe `static let`). Release builds haven't been
  timed. The loupe work (cs-40b6c9) should load the list off the main thread at launch, so the
  first pointer move doesn't stall.
- Wide-gamut colors are named by their actual OKLab position. They are not gamut-mapped to sRGB
  first, so a vivid P3 red gets the name of the nearest entry to that exact color.
- The README credit is the only one for now: there's no About-panel credit inside the app.
