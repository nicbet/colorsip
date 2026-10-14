# Project scaffold

## What
Create the empty but buildable project skeleton: the app target, the `ColorsipCore` package, CI, README and LICENSE. Also record the project's TDD rule in `CLAUDE.md` and `AGENTS.md`. No product features.

## Why
The product spec is `spec.md` at the repo root. This issue implements its §1 (Platform, Project structure). Every other MVP issue builds on this. It blocks cs-5cda46 and cs-7375e5.

## How

### Layout
```
Colorsip.xcodeproj/          app project (checked in), shared scheme "Colorsip"
Colorsip/                    app target sources (folder-synchronized group)
  ColorsipApp.swift          @main, NSApplicationDelegateAdaptor, no windows yet
  Colorsip.entitlements      sandbox off
  Assets.xcassets            empty AppIcon
Packages/ColorsipCore/       local Swift package, no UI imports
  Package.swift              swift-tools 6.0, platforms .macOS("15.8")
  Sources/ColorsipCore/
  Tests/ColorsipCoreTests/   Swift Testing (`import Testing`), one smoke test
.github/workflows/ci.yml
README.md
LICENSE
CLAUDE.md, AGENTS.md         add a "Development practice" section (TDD)
.gitignore                   Xcode/SwiftPM defaults
```

### Decisions
| Topic | Decision |
|---|---|
| Project generation | A plain checked-in `.xcodeproj`. No XcodeGen or Tuist |
| Project format | objectVersion 77 with a `PBXFileSystemSynchronizedRootGroup` for `Colorsip/`: files added to the folder join the target without pbxproj edits. Needs Xcode 16+ |
| Info.plist | Generated (`GENERATE_INFOPLIST_FILE`). Keys are set through `INFOPLIST_KEY_*` build settings, e.g. `LSUIElement = YES`. No `Info.plist` file, which would also clash with the synchronized group |
| Bundle ID | `com.nicolas-bettenburg.colorsip` |
| Deployment target | macOS 15.8, Swift 6 language mode, strict concurrency |
| Signing | Sign to Run Locally (ad-hoc, `CODE_SIGN_IDENTITY = -`, no team), so anyone can build without a developer account. Hardened runtime on (applied to Release builds) |
| App shell | `@main` SwiftUI `App` with an empty `Settings` scene and an AppDelegate. The status item comes in cs-5cda46 |
| CI | `macos-15` runner, latest stable Xcode via `maxim-lobanov/setup-xcode`. Steps: `swift test` in `Packages/ColorsipCore`, then a Release `xcodebuild build` with `CODE_SIGNING_ALLOWED=NO`. Runs on push and PR |
| LICENSE | MIT, © 2026 Nicolas Bettenburg |
| README | What it is, requirements, build from source (open in Xcode or `xcodebuild`), granting Screen Recording and Accessibility, license. Points to `spec.md` for the product spec |
| TDD rule | The same "Development practice" section in `CLAUDE.md` and `AGENTS.md`, outside the xpo-managed `xpo:begin/end` block so xpo updates don't overwrite it. Rule: write tests from the issue spec first, see them fail, then implement until they are green |

## Acceptance criteria
- [x] `swift test` passes in `Packages/ColorsipCore`
- [x] `xcodebuild -scheme Colorsip build` succeeds locally with no signing team
- [x] App launches with no Dock icon and no window
- [x] App target links `ColorsipCore`
- [x] CI workflow runs both steps on push and PR
- [x] README and MIT LICENSE are present
- [x] `CLAUDE.md` and `AGENTS.md` state the TDD rule
