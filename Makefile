APP_NAME := Codex Dock Notifier
BINARY_NAME := CodexDockNotifier
BUNDLE_ID := com.local.CodexDockNotifier
CONFIGURATION ?= debug
BUILD_DIR := .build/$(CONFIGURATION)
DIST_DIR := dist
APP_DIR := $(DIST_DIR)/$(APP_NAME).app
CONTENTS_DIR := $(APP_DIR)/Contents
MACOS_DIR := $(CONTENTS_DIR)/MacOS
RESOURCES_DIR := $(CONTENTS_DIR)/Resources

.PHONY: build run test clean install-login-item uninstall-login-item

build:
	swift build -c $(CONFIGURATION) --product $(BINARY_NAME)
	swift Scripts/make-app-icon.swift Resources/AppIcon.icns
	rm -rf "$(APP_DIR)"
	mkdir -p "$(MACOS_DIR)" "$(RESOURCES_DIR)"
	cp "$(BUILD_DIR)/$(BINARY_NAME)" "$(MACOS_DIR)/$(BINARY_NAME)"
	cp Resources/Info.plist "$(CONTENTS_DIR)/Info.plist"
	cp Resources/AppIcon.icns "$(RESOURCES_DIR)/AppIcon.icns"
	sleep 0.2
	xattr -cr "$(APP_DIR)" >/dev/null 2>&1 || true
	xattr -d com.apple.FinderInfo "$(APP_DIR)" >/dev/null 2>&1 || true
	xattr -d 'com.apple.fileprovider.fpfs#P' "$(APP_DIR)" >/dev/null 2>&1 || true
	xattr -d com.apple.FinderInfo "$(CONTENTS_DIR)" >/dev/null 2>&1 || true
	xattr -d 'com.apple.fileprovider.fpfs#P' "$(CONTENTS_DIR)" >/dev/null 2>&1 || true
	codesign --force --sign - --identifier $(BUNDLE_ID) --timestamp=none "$(APP_DIR)" >/dev/null 2>&1 || true
	@echo "Built $(APP_DIR)"

run: build
	open "$(APP_DIR)"

test:
	swift run CodexDockNotifierSmokeTest

clean:
	rm -rf .build "$(DIST_DIR)"

install-login-item: build
	Scripts/install-login-item.sh "$(APP_DIR)"

uninstall-login-item:
	Scripts/uninstall-login-item.sh
