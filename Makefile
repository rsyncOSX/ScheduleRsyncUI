# Apple Silicon only; requires Xcode 27 to build; runs on macOS 14 or later.
APP := ScheduleRsync
PROJECT := $(APP).xcodeproj
VERSION := $(shell sed -n 's/.*MARKETING_VERSION = \([^;]*\);.*/\1/p' "$(PROJECT)/project.pbxproj" | head -n 1)
BUILD_PATH ?= $(CURDIR)/build
DERIVED_DATA_PATH ?= $(BUILD_PATH)/DerivedData
ARCHIVE_PATH := $(BUILD_PATH)/arm64/$(APP).xcarchive
EXPORT_PATH := $(BUILD_PATH)/arm64
APP_PATH := $(EXPORT_PATH)/$(APP).app
ZIP_PATH := $(BUILD_PATH)/$(APP).$(VERSION).arm64.zip
DMG_PATH := $(CURDIR)/$(APP).$(VERSION).arm64.dmg

XCODEBUILD ?= xcodebuild
XCODEBUILD_FLAGS ?=
DESTINATION := platform=macOS,arch=arm64
ARCH_FLAGS := ARCHS=arm64 ONLY_ACTIVE_ARCH=NO EXCLUDED_ARCHS=x86_64
DEVELOPMENT_TEAM ?= 93M47F4H9T
# Reuse the existing developer's keychain credentials; override if needed.
NOTARY_PROFILE ?= RsyncUI
CREATE_DMG ?= ../create-dmg/create-dmg
DMG_BACKGROUND ?= $(CURDIR)/images/background.png
NOTARY_ID ?=

.DEFAULT_GOAL := build
# Keep clean, archive, export, notarization and packaging ordered with make -j.
.NOTPARALLEL:
.DELETE_ON_ERROR:

# Signed release: archive -> export -> notarize -> staple -> DMG.
build:
	$(MAKE) clean
	$(MAKE) archive
	$(MAKE) notarize
	$(MAKE) sign
	$(MAKE) prepare-dmg
	$(MAKE) open

# Local unsigned build; no export, signing credentials or notarization required.
debug: archive-debug open-debug

archive:
	$(XCODEBUILD) -project "$(PROJECT)" -scheme "$(APP)" \
		-destination '$(DESTINATION)' -configuration Release \
		-derivedDataPath "$(DERIVED_DATA_PATH)" \
		-archivePath "$(ARCHIVE_PATH)" \
		$(ARCH_FLAGS) DEVELOPMENT_TEAM="$(DEVELOPMENT_TEAM)" $(XCODEBUILD_FLAGS) archive
	$(XCODEBUILD) -exportArchive -exportOptionsPlist "exportOptions.plist" \
		-archivePath "$(ARCHIVE_PATH)" -exportPath "$(EXPORT_PATH)"
	xcrun lipo -verify_arch arm64 "$(APP_PATH)/Contents/MacOS/$(APP)"
	test "$$(xcrun lipo -archs "$(APP_PATH)/Contents/MacOS/$(APP)")" = arm64
	ditto -c -k --keepParent "$(APP_PATH)" "$(ZIP_PATH)"

archive-debug:
	$(XCODEBUILD) -project "$(PROJECT)" -scheme "$(APP)" \
		-destination '$(DESTINATION)' -configuration Debug \
		-derivedDataPath "$(DERIVED_DATA_PATH)" \
		$(ARCH_FLAGS) CODE_SIGNING_ALLOWED=NO $(XCODEBUILD_FLAGS) build
	mkdir -p "$(EXPORT_PATH)"
	rm -rf "$(APP_PATH)"
	ditto "$(DERIVED_DATA_PATH)/Build/Products/Debug/$(APP).app" "$(APP_PATH)"
	xcrun lipo -verify_arch arm64 "$(APP_PATH)/Contents/MacOS/$(APP)"
	test "$$(xcrun lipo -archs "$(APP_PATH)/Contents/MacOS/$(APP)")" = arm64
	@echo "Unsigned arm64 app: $(APP_PATH)"

test:
	$(XCODEBUILD) -project "$(PROJECT)" -scheme "$(APP)" \
		-destination '$(DESTINATION)' -configuration Debug \
		-derivedDataPath "$(DERIVED_DATA_PATH)" \
		$(ARCH_FLAGS) CODE_SIGNING_ALLOWED=NO $(XCODEBUILD_FLAGS) test

notarize:
	xcrun notarytool submit --keychain-profile "$(NOTARY_PROFILE)" --wait \
		--output-format plist "$(ZIP_PATH)" > "$(BUILD_PATH)/notarization.plist"
	@cat "$(BUILD_PATH)/notarization.plist"
	@test "$$(/usr/libexec/PlistBuddy -c 'Print :status' "$(BUILD_PATH)/notarization.plist")" = Accepted || { \
		echo 'Notarization was not accepted. Inspect the submission with make check NOTARY_ID=<id>.'; \
		exit 1; \
	}

# Historical target name: this staples and verifies the already-signed export.
sign:
	xcrun stapler staple "$(APP_PATH)"
	spctl -a -t exec -vvv "$(APP_PATH)"

prepare-dmg:
	@if [ -f "$(DMG_BACKGROUND)" ]; then \
		set -- --background "$(DMG_BACKGROUND)"; \
	else \
		set --; \
	fi; \
	"$(CREATE_DMG)" "$$@" \
		--volname "$(APP) ver $(VERSION) (Apple Silicon)" \
		--window-pos 200 120 --window-size 500 320 --icon-size 80 \
		--icon "$(APP).app" 125 175 --hide-extension "$(APP).app" \
		--app-drop-link 375 175 --no-internet-enable \
		--codesign "$(DEVELOPMENT_TEAM)" "$(DMG_PATH)" "$(APP_PATH)"

clean:
	@test -n "$(BUILD_PATH)" && test "$(BUILD_PATH)" != / && test "$(BUILD_PATH)" != "$(CURDIR)"
	rm -rf "$(BUILD_PATH)"
	rm -f "$(DMG_PATH)"

check:
	@test -n "$(NOTARY_ID)" || { echo 'Usage: make check NOTARY_ID=<submission-id>'; exit 1; }
	xcrun notarytool log "$(NOTARY_ID)" --keychain-profile "$(NOTARY_PROFILE)"

history:
	xcrun notarytool history --keychain-profile "$(NOTARY_PROFILE)"

open:
	open "$(CURDIR)"

open-debug:
	@echo "Debug build complete: $(APP_PATH)"
	open "$(EXPORT_PATH)"

# Compatibility aliases for the former Makefile-arm64 workflow.
archive-debug-arm64: archive-debug
notarize-arm64: notarize
sign-arm64: sign
prepare-dmg-arm64: prepare-dmg

.PHONY: build debug archive archive-debug test notarize sign prepare-dmg clean \
        check history open open-debug archive-debug-arm64 notarize-arm64 \
        sign-arm64 prepare-dmg-arm64
