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

Colorsip needs two macOS permissions. At launch, and when you use a feature that needs one, a
guide walks you through the missing ones: it opens the right pane of **System Settings → Privacy &
Security** and moves on once you've turned Colorsip on. Accessibility is optional and can be
skipped. **Settings ▸ Permissions** shows what's granted and starts the guide again.

| Permission | Needed for |
|---|---|
| **Screen & System Audio Recording** | Reading pixel colors under the picker |
| **Accessibility** | Cmd+click paste into the active app |

The global picker shortcut, **⌃⌥⌘P** by default, needs no permission. You can change it in
Settings ▸ Shortcuts.

Colorsip lists the missing permissions in one window and ticks each one off as soon as you turn
it on in System Settings. No restart is needed.

### Keep permissions across rebuilds

By default the app is signed ad hoc, and macOS ties these permissions to that one build. After a
rebuild, Colorsip still shows as allowed in System Settings, but the permission no longer applies
and the guide comes back.

To fix that, create a local code-signing certificate once:

```sh
make signing-cert
```

This creates a self-signed certificate named "Colorsip Local Signing" in your login keychain,
trusts it for code signing only (macOS asks for your password), and writes the untracked
`Config/Signing.local.xcconfig` so Xcode signs with it too. `make build` uses it whenever it is in
your keychain. On the first signed build, macOS asks whether `codesign` may use the key: click
**Always Allow**.

Then clear the old grants and grant the permissions once more:

```sh
make reset-permissions
```

Without the certificate, run `make reset-permissions` (or remove Colorsip from the list in System
Settings) after a rebuild, then grant again.

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

The picker draws on screen and can't be fully tested automatically. To check it by hand, open
`TestPages/picker-swatches.html` in Safari. It has sRGB and Display P3 swatches labelled with
the values the picker should show, and 1-pixel patterns for checking the loupe grid and arrow keys.

## License

MIT. See [`LICENSE`](LICENSE).

## Third-party

- Color names come from [meodai/color-name-list](https://github.com/meodai/color-name-list)
  v14.54.2 by David Aerne, MIT licensed. The list and its license are bundled in
  `Packages/ColorsipCore/Sources/ColorsipCore/Resources/`. To update it, replace `colornames.csv`
  with the `dist/colornames.csv` of a newer `color-name-list` npm release, and update the version
  here, in `Package.swift`, and in the entry-count test.
