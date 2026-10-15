# App icon implementation

## What changed

Colorsip now ships a complete macOS application icon asset set. The artwork comes from the user-supplied `~/Downloads/colorsip.png`: a glass eyedropper selecting blue from a layered color palette on a dark rounded-square tile.

The exterior white surround was removed and replaced with true transparency. The artwork itself was preserved. The resulting 1024×1024 master was color-tagged as sRGB and downsampled into the ten pixel renditions required by the macOS `AppIcon` asset catalog.

`Contents.json` now assigns a concrete filename to every 1x and 2x slot from 16pt through 512pt.

## How the pieces fit together

The asset catalog contains these logical sizes:

- 16pt: 16px and 32px
- 32pt: 32px and 64px
- 128pt: 128px and 256px
- 256pt: 256px and 512px
- 512pt: 512px and 1024px

Xcode compiles those source PNGs into `AppIcon.icns` and records `AppIcon` in the built application's `CFBundleIconFile` and `CFBundleIconName` keys. That compiled icon is what Finder, About, System Settings, and macOS permission surfaces consume.

The application remains an `LSUIElement` agent, so it does not gain a Dock presence from this change.

## Key decisions

### Preserve the supplied artwork

The source concept already communicates both halves of the product: the eyedropper represents picking and the colorful palette represents stored colors. Only the exterior background was removed; the composition, lighting, colors, materials, and internal white selection ring were retained.

### Use standard downsampling for small sizes

The 16px and 32px renditions were inspected at native resolution. The diagonal eyedropper and bright swatches remain recognizable, so a separate simplified redraw would have introduced unnecessary visual divergence.

### Keep the menu-bar glyph unchanged

The status item continues to use the monochrome template SF Symbol `eyedropper.halffull`. A detailed full-color application icon is inappropriate for the menu bar, where macOS expects a compact template image that adapts to system appearance.

### Keep transparency outside the existing silhouette

No second rounded-rectangle mask was applied. The original tile defines its own edge and shadow, while pixels beyond it are transparent.

## Verification

- Validated that all ten asset-catalog entries reference existing files with the expected dimensions.
- Validated alpha channels and sRGB PNG metadata for every rendition.
- Inspected the 16px, 32px, and 1024px source renditions.
- Built the Release application successfully with code signing disabled.
- Confirmed that the built application contains `AppIcon.icns`, and visually inspected a 256px extraction with clean transparent corners.
- Ran the complete ColorsipCore suite: 501 tests passed.
- Confirmed the status-item source was unchanged.

The user reviewed the result and approved it for merge.
