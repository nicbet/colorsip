.DEFAULT_GOAL := help

XCODEBUILD ?= xcodebuild
SWIFT ?= swift

PROJECT := Colorsip.xcodeproj
SCHEME := Colorsip
CONFIGURATION ?= Release
CORE_PACKAGE_DIR := Packages/ColorsipCore

.PHONY: help build test

help:
	@printf '%s\n' \
		'Available targets:' \
		'  help   Show this help message' \
		'  build  Build the Colorsip app in Release configuration' \
		'  test   Run the ColorsipCore test suite'

build:
	$(XCODEBUILD) -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIGURATION) build

test:
	$(SWIFT) test --package-path $(CORE_PACKAGE_DIR)
