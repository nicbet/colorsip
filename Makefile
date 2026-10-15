.DEFAULT_GOAL := help

XCODEBUILD ?= xcodebuild
SWIFT ?= swift

PROJECT := Colorsip.xcodeproj
SCHEME := Colorsip
CONFIGURATION ?= Release
BUNDLE_ID := com.nicolas-bettenburg.colorsip
VERBOSE ?= 0
CORE_PACKAGE_DIR := Packages/ColorsipCore
BUILD_DIR := Builds
DERIVED_DATA_DIR := $(BUILD_DIR)/DerivedData
SNAPSHOT_DIR := $(BUILD_DIR)/snapshots
SCREENSHOTS := popover picker editor settings
APP_PATH := $(DERIVED_DATA_DIR)/Build/Products/$(CONFIGURATION)/$(SCHEME).app
SIGNING_IDENTITY := Colorsip Local Signing
HAS_SIGNING_IDENTITY := $(shell security find-identity -v -p codesigning 2>/dev/null | grep -q '"$(SIGNING_IDENTITY)"' && echo 1)

ifeq ($(VERBOSE),1)
XCODEBUILD_FLAGS :=
else
XCODEBUILD_FLAGS := -quiet
endif

# Sign with the stable local identity when it exists, also in worktrees that lack
# Config/Signing.local.xcconfig. Otherwise Config/Signing.xcconfig signs ad hoc.
ifeq ($(HAS_SIGNING_IDENTITY),1)
SIGNING_FLAGS := COLORSIP_SIGNING_IDENTITY="$(SIGNING_IDENTITY)"
else
SIGNING_FLAGS :=
endif

.PHONY: help build test snapshot screenshots clean signing-cert reset-permissions

help:
	@printf '%s\n' \
		'Available targets:' \
		'  help               Show this help message' \
		'  build              Build the Colorsip app in Release configuration into $(BUILD_DIR)/' \
		'                     (VERBOSE=1 for full xcodebuild output)' \
		'  test               Run the ColorsipCore test suite' \
		'  snapshot           Render the popover, picker, editor and Settings to $(SNAPSHOT_DIR)/' \
		'  screenshots        Refresh the README screenshots in docs/ (needs cwebp: brew install webp)' \
		'  clean              Remove $(BUILD_DIR)/' \
		'  signing-cert       Create a local code-signing certificate so permissions survive rebuilds' \
		'  reset-permissions  Reset Screen Recording and Accessibility grants'

build:
	@echo 'Building $(SCHEME) ($(CONFIGURATION))...'
ifneq ($(HAS_SIGNING_IDENTITY),1)
	@echo 'Signing ad hoc: permissions reset on every rebuild. Run `make signing-cert` once to fix that.'
endif
	@$(XCODEBUILD) $(XCODEBUILD_FLAGS) -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIGURATION) -destination 'generic/platform=macOS' -derivedDataPath $(DERIVED_DATA_DIR) $(SIGNING_FLAGS) build
	@rm -rf $(BUILD_DIR)/$(SCHEME).app
	@ditto $(APP_PATH) $(BUILD_DIR)/$(SCHEME).app
	@echo 'Built $(BUILD_DIR)/$(SCHEME).app'

test:
	$(SWIFT) test --package-path $(CORE_PACKAGE_DIR)

# Rendered offscreen from a sample library: needs no permission and leaves your library alone.
snapshot: build
	@rm -rf $(SNAPSHOT_DIR)
	@$(BUILD_DIR)/$(SCHEME).app/Contents/MacOS/$(SCHEME) --snapshot $(SNAPSHOT_DIR)

screenshots: snapshot
	@for name in $(SCREENSHOTS); do for theme in light dark; do \
		cwebp -quiet -q 92 -m 6 -exact "$(SNAPSHOT_DIR)/$$name-$$theme.png" -o "docs/$$name-$$theme.webp"; \
	done; done
	@ls -l docs

clean:
	rm -rf $(BUILD_DIR)

signing-cert:
	@sh scripts/create-signing-cert.sh

reset-permissions:
	tccutil reset ScreenCapture $(BUNDLE_ID)
	tccutil reset Accessibility $(BUNDLE_ID)
