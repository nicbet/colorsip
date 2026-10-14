.DEFAULT_GOAL := help

XCODEBUILD ?= xcodebuild
SWIFT ?= swift

PROJECT := Colorsip.xcodeproj
SCHEME := Colorsip
CONFIGURATION ?= Release
VERBOSE ?= 0
CORE_PACKAGE_DIR := Packages/ColorsipCore
BUILD_DIR := Builds
DERIVED_DATA_DIR := $(BUILD_DIR)/DerivedData
APP_PATH := $(DERIVED_DATA_DIR)/Build/Products/$(CONFIGURATION)/$(SCHEME).app

ifeq ($(VERBOSE),1)
XCODEBUILD_FLAGS :=
else
XCODEBUILD_FLAGS := -quiet
endif

.PHONY: help build test clean

help:
	@printf '%s\n' \
		'Available targets:' \
		'  help   Show this help message' \
		'  build  Build the Colorsip app in Release configuration into $(BUILD_DIR)/' \
		'         (VERBOSE=1 for full xcodebuild output)' \
		'  test   Run the ColorsipCore test suite' \
		'  clean  Remove $(BUILD_DIR)/'

build:
	@echo 'Building $(SCHEME) ($(CONFIGURATION))...'
	@$(XCODEBUILD) $(XCODEBUILD_FLAGS) -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIGURATION) -destination 'generic/platform=macOS' -derivedDataPath $(DERIVED_DATA_DIR) build
	@rm -rf $(BUILD_DIR)/$(SCHEME).app
	@ditto $(APP_PATH) $(BUILD_DIR)/$(SCHEME).app
	@echo 'Built $(BUILD_DIR)/$(SCHEME).app'

test:
	$(SWIFT) test --package-path $(CORE_PACKAGE_DIR)

clean:
	rm -rf $(BUILD_DIR)
