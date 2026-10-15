# Design and add a proper app icon

## What

Replace the empty macOS `AppIcon` asset set with production-ready renditions derived from the user-supplied artwork at `~/Downloads/colorsip.png`.

The artwork depicts a glass eyedropper selecting blue from a layered color palette on a dark, rounded-square macOS-style tile. Preserve this concept and its visual character.

## Why

Colorsip currently has no proper application icon. The icon is needed for Finder, System Settings, the About panel, permission prompts, and other macOS surfaces even though Colorsip is an agent app without a Dock icon.

## Approach

1. Use the supplied 1254×1254 PNG as the source artwork.
2. Remove only the baked white exterior surrounding the dark rounded-square tile, producing genuine transparency outside the icon silhouette.
3. Preserve the dark tile, eyedropper, palette cards, colored swatches, lighting, and composition.
4. Normalize the master to a square 1024×1024 PNG with an embedded sRGB profile.
5. Generate every macOS AppIcon rendition required by the existing asset catalog:
   - 16×16 and 32×32
   - 32×32 and 64×64 Retina renditions
   - 128×128 and 256×256
   - 256×256 and 512×512 Retina renditions
   - 512×512 and 1024×1024
6. Inspect the 16px and 32px results at native size. If ordinary high-quality downsampling makes the icon illegible, create minimally simplified small-size renditions while preserving the same silhouette and subject.
7. Update `Contents.json` with the generated filenames.
8. Keep the status-item icon as the existing monochrome template SF Symbol `eyedropper.halffull`; do not reuse the full-color application icon in the menu bar.

## Constraints

- Do not redesign or AI-regenerate the supplied artwork.
- Do not add text, lettering, borders, badges, or new objects.
- Do not apply an additional rounded-rectangle mask over the existing tile.
- Transparency must exist only outside the intended icon silhouette; internal highlights and pale elements must remain intact.
- Generated asset files must live in `Colorsip/Assets.xcassets/AppIcon.appiconset`.

## Verification

- Confirm every asset-catalog slot references an existing PNG with the expected pixel dimensions.
- Confirm the PNGs contain transparency outside the tile and have an embedded sRGB profile.
- Build the application successfully.
- Inspect the icon at 16, 32, 128, 256, 512, and 1024 pixels.
- Verify the built app displays the icon in Finder and the About panel where practical.
- Confirm the menu-bar item remains a monochrome template image.

## Acceptance Criteria

- [ ] The supplied Colorsip artwork is used without a creative redesign.
- [ ] Exterior white pixels are replaced by clean transparency without damaging the tile edge.
- [ ] A color-managed 1024×1024 master and all required macOS renditions are present.
- [ ] `AppIcon.appiconset/Contents.json` references every rendition correctly.
- [ ] The icon remains recognizable at small sizes.
- [ ] The app builds with the completed asset catalog.
- [ ] Finder/About surfaces show the new icon where practical to verify.
- [ ] The menu-bar status-item glyph remains unchanged.
