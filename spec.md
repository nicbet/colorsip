# Colorsip

Colorsip is a color-picker menubar app.

## UI

There are two UI surfaces: a menubar app (menubar icon with a popover window), and a main window app

## Picker

To open the picker, use shortcut ctrl+option+cmd+p (Hyper+P)

The picker offers multiple easy customization options when active:
- shift + click to pick multiple colors without closing the picker
- mouseswheel adjusts diameter size of the loupe
- option + mousewheel adjusts grid size of the preview loupe
- command + click to pick a color and send the color code to the active app

The picker supports precise movement while active:
- arrow keys move the picker by 1px
- Shift + arrow keys move the picker by 10px

The picker supports shortcuts when holding down the option key when active:
- Pick single color mode
- pick multiple colors mode
- Contrast checker mode

## Editor

Editing colors is simple and enjoyable. Colorsip allows the user to create multiple named palettes
with a preview of up to 16 colors in the menubar app per palette. Palettes can be locked to prevent adding/changing/removing colors. A default palette called "Color History: is always shown at the top
and shows the 16 last picked colors chronologically.

## Palettes
Palettes can be named (with an optional description). 

### Groups
Within a palette, related colors can be grouped (named). 

### Sharing
Palettes can be exported (shared) in various formats:
- Colorsip palette
- Adobe Swatch Exchange (ASE)
- Apple Color List (CLR)
- JavaScript (JSON)
- Portable Document Format (PDF)

### Templates

Smart templates allow you to quickly define or pick colors into pre-arranged palettes with groups.
- Tailwind themes
- Web UI
- iOS/macOS/Android UI

You can turn any existing palette (with groups) into a template.


## Color Profiles

Automatically applies the correct color profile when picking from different environment for consistent and reliable results.

## Smart Formats
Smart Formats automatically apply the correct color format based on where you’re pasting. Assign specific formats to your favorite apps, and Colorsip will remember and apply them automatically when pasting.

## Smart Profiles
With Smart Profiles, Colorsip automatically adapts to the environment you’re working in by applying the correct color profile.

When picking a color on your screen, the result can vary depending on the color profile of the app or window you’re sampling from:
- Web browsers like Safari and Chrome often use sRGB IEC61966-2.1.
- Native macOS apps like Xcode and Sketch may use Display P3 or Generic RGB.

Without the correct profile, your picked colors may not match what you see in your designs. Smart Profiles solves this by ensuring:
- The correct color profile is applied automatically.
- Your colors are accurate and consistent across apps.
- You save time by letting Colorsip handle the technical details.

## Accessibility

A built-in contrast checker makes design more accessible and offers a one-button fix option. The Contrast Checker displays your text and background colors, alongside a contrast score. Adjust colors using the sliders or the color fields. The score updates in real time. It can be launched either:
- Click the Contrast Checker button in the toolbar to launch the tool.
- You can also open the Contrast Checker while working with palettes and colors in the main view.

A simulator allows us to toggle between modes like Protanopia, Deuteranopia, Tritanopia and Achromatopsia to preview palettes in real time for how colors appear to people with different types of color vision. You’ll find the simulation modes in the Color Blindness control in the bottom bar of the menu app and main window app. Pick one to see your palettes transform in real time

## Collaboration

Share and sync palettes, settings and more through iCloud, or alternatively Dropbox/OneDrive/Google Drive.
