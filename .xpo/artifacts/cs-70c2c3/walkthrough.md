# Walkthrough: project scaffold

## What was built
The empty skeleton that every other MVP issue builds on (`spec.md` §1). It has no product features yet, only a buildable and testable structure with CI, docs and working rules.

## The pieces

### `Packages/ColorsipCore`: the UI-free core
A local Swift package (`swift-tools-version: 6.0`, `.macOS("15.8")`) with one library product. All testable logic goes here: the color model, conversions, formatters, naming, contrast math, storage and serialization. For now it only holds `ColorsipCore.version` and one Swift Testing smoke test, which proves the test setup works. Run it with `swift test` from the package directory.

Why a separate package and not a framework target in the app project? `swift test` runs in seconds without Xcode schemes, CI can run it directly, and SwiftPM keeps out anything that is not UI-free.

### `Colorsip.xcodeproj` and `Colorsip/`: the app
- **Written by hand, objectVersion 77.** The `Colorsip/` folder is a `PBXFileSystemSynchronizedRootGroup`: any file you drop in the folder joins the target. **You never need to edit `project.pbxproj` to add source files.** This needs Xcode 16 or later.
- **Local package link.** An `XCLocalSwiftPackageReference` points to `Packages/ColorsipCore`, and the target lists `ColorsipCore` as a package product dependency in its Frameworks phase.
- **No `Info.plist` file.** `GENERATE_INFOPLIST_FILE = YES`, and keys come from `INFOPLIST_KEY_*` build settings. The important one is `INFOPLIST_KEY_LSUIElement = YES`, which makes Colorsip an agent app with no Dock icon. Add new plist keys (for example usage descriptions) the same way. A real `Info.plist` in the synchronized folder would be copied as a resource and break the build.
- **Signing.** `CODE_SIGN_IDENTITY = "-"` ("Sign to Run Locally") with no team, so anyone can build. `Colorsip.entitlements` turns the sandbox off explicitly: the picker and event taps need it. Hardened runtime is enabled, but Xcode only applies it to Release builds.
- **Shared scheme.** `xcshareddata/xcschemes/Colorsip.xcscheme` is checked in so that `xcodebuild -scheme Colorsip` works on a fresh clone and in CI.
- **App shell.** `ColorsipApp` is a SwiftUI `App` whose only scene is an empty `Settings`, with an `NSApplicationDelegateAdaptor` for AppKit hooks. The status item and popover come in cs-5cda46 and attach to the `AppDelegate`.

### CI: `.github/workflows/ci.yml`
On every push and PR, on `macos-15` with the latest stable Xcode: run `swift test` in the Core package, then build the app in Release with `CODE_SIGNING_ALLOWED=NO`. CI does not need signing because it only proves the app compiles.

### Docs and rules
- `README.md`: requirements, how to build from Xcode or `xcodebuild`, the two permissions (Screen Recording, Accessibility) and why a rebuild can need them granted again (ad-hoc signatures change), and the project layout.
- `LICENSE`: MIT, © 2026 Nicolas Bettenburg.
- `CLAUDE.md` and `AGENTS.md` get a **Development practice** section with the TDD rule: tests from the spec first, see them fail, make them green, refactor. Logic belongs in `ColorsipCore` so it can be tested. When something can't be tested automatically, the completion comment must describe the manual check. The section is outside the `xpo:begin/end` markers on purpose, because xpo owns and regenerates that block.

## How it was verified
- `swift test`: 1 test passes.
- Debug build (ad-hoc signed) and Release build without signing (the CI command) both succeed on Xcode 26.3.
- The built bundle has the right bundle ID, `LSMinimumSystemVersion` 15.8, `LSUIElement`, and the sandbox off. When launched, LaunchServices reports `ApplicationType = UIElement`: no Dock icon and no window.
- CI had not run on GitHub at merge time. It runs on the first push.
