# Walkthrough: picker no longer deactivates the frontmost app

Shipped on the cs-615265 branch, where it was found.

## Change
`PickerController.open()` no longer calls `NSApp.activate()`. It orders the overlay panels front and makes the one under the pointer key.

## Why this works
`PickerOverlayPanel` is created with `.nonactivatingPanel`. A non-activating panel can become key without activating its app, so key events go to Colorsip, and the local `NSEvent` monitor still sees them, while the app under the pointer keeps its active appearance. Clicks on the panel don't activate Colorsip either.

## Trade-off: the cursor
macOS ignores cursor changes from background apps, so `NSCursor.hide()` no longer hides the arrow. It stays visible over the loupe. The user tested this and accepted it. The `hide`/`unhide` calls stay because they keep the show/hide count balanced, and they still work when Colorsip is already active (for example the color editor's eyedropper).

## Don't
Don't use the private `SetsCursorInBackground` WindowServer property to hide the cursor. An attempt using `@_silgen_name` declarations of `_CGSDefaultConnection`/`CGSSetConnectionProperty` crashed WindowServer on its first run. The likely cause is that `@_silgen_name` uses the Swift calling convention, not the C one. Even a correct C declaration is unsupported private API.
