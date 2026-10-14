## Overview

This change adds a root `Makefile` as a small, discoverable entry point for the workflows already documented by the repository. It does not replace Xcode or Swift Package Manager; each target delegates directly to the existing canonical command.

## Targets

- `make` / `make help` prints the available commands and their purpose.
- `make build` builds the `Colorsip` Xcode scheme in Release configuration.
- `make test` runs the `ColorsipCore` Swift package test suite.

All targets are declared phony so files named `help`, `build`, or `test` cannot suppress execution.

## Design Decisions

The Makefile keeps project, scheme, and package paths in named variables so the recipes remain readable. `XCODEBUILD`, `SWIFT`, and `CONFIGURATION` can be overridden by callers, which is useful for alternate toolchains, CI diagnostics, and non-Release local builds while preserving the documented defaults.

There is deliberately no duplicated build logic, dependency installation, clean target, or artifact management. Xcode and Swift Package Manager continue to own those concerns.

## Verification

- The default target produced concise help output.
- `make test` passed all 164 ColorsipCore tests.
- `make build` completed a Release build successfully.
- Substituting failing commands for `XCODEBUILD` and `SWIFT` verified that make returns a non-zero status when an underlying command fails.
- `git diff --check` reported no whitespace errors.