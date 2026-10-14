# Colorsip

A color-picker menubar app for macOS. Pick colors from anywhere on screen, keep them in palettes
with named groups, and copy them in the format you need.

Colorsip is open source (MIT) and distributed as source only: there are no pre-built binaries and
no App Store version. You build it yourself.

The product spec is in [`spec.md`](spec.md).

## Requirements

- macOS 15.8 or later
- Xcode 26 or later

## Build from source

```sh
git clone https://github.com/nicbet/colorsip.git
cd colorsip
open Colorsip.xcodeproj
```

Select the **Colorsip** scheme and press **Run** (⌘R). The project uses "Sign to Run Locally", so
you don't need an Apple Developer account.

From the command line:

```sh
xcodebuild -project Colorsip.xcodeproj -scheme Colorsip -configuration Release build
```

To install, copy `Colorsip.app` from the build products into `/Applications`.

Colorsip is an agent app: it has no Dock icon. Look for it in the menubar.

## Grant permissions

Colorsip needs two macOS permissions. It asks for them the first time you use a feature that needs
them, and you can grant them later in **System Settings → Privacy & Security**.

| Permission | Needed for |
|---|---|
| **Screen & System Audio Recording** | Reading pixel colors under the picker |
| **Accessibility** | Global shortcuts and Cmd+click paste into the active app |

After you grant Screen Recording, quit and reopen Colorsip.

Because the app is signed locally, macOS ties these permissions to that build's signature. If a
rebuild stops working with a permission you already granted, remove Colorsip from the list in
System Settings and grant it again.

## Development

The project has two parts:

- `Packages/ColorsipCore`: a Swift package with no UI. It holds the color model, conversions,
  formatters, naming, contrast math, the storage model and serialization.
- `Colorsip`: the app target (menubar, picker, windows, settings).

Run the Core tests:

```sh
cd Packages/ColorsipCore
swift test
```

CI (GitHub Actions) runs the Core tests and builds the app on every push and pull request.

## License

MIT. See [`LICENSE`](LICENSE).
