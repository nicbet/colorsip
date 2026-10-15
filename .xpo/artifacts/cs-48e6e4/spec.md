# Opening the picker deactivates the frontmost app

## What
Opening the picker called `NSApp.activate()`, so the app being picked from became inactive and many apps redrew in their inactive look (grey selection, dimmed controls). The picker then sampled those colors.

## How
- Don't activate Colorsip. The overlay panels are `.nonactivatingPanel`, so `makeKey()` still makes them key: they get keyboard and mouse events through the local event monitor while the other app stays active.
- The cursor stays visible. `NSCursor.hide()` is still called, but macOS ignores it from a background app.

## Rejected
- Hiding the cursor in the background with the private WindowServer property `SetsCursorInBackground` (`CGSSetConnectionProperty`, declared with `@_silgen_name`). Its first run crashed WindowServer and killed every app, so it was removed. Don't retry it.

## Acceptance criteria
- [x] Invoking the picker with the shortcut leaves the frontmost app active.
- [x] Arrows, Esc, Return/Space, click, Shift+click, scroll and the Option menu still work.
