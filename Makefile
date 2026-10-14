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

.PHONY: help build test clean signing-cert reset-permissions

help:
	@printf '%s\n' \
		'Available targets:' \
		'  help               Show this help message' \
		'  build              Build the Colorsip app in Release configuration into $(BUILD_DIR)/' \
		'                     (VERBOSE=1 for full xcodebuild output)' \
		'  test               Run the ColorsipCore test suite' \
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

clean:
	rm -rf $(BUILD_DIR)

signing-cert:
	@sh scripts/create-signing-cert.sh

reset-permissions:
	tccutil reset ScreenCapture $(BUNDLE_ID)
	tccutil reset Accessibility $(BUNDLE_ID)
