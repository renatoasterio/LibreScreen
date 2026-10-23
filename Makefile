# LibreScreen — developer entry points.
#   make run        build Debug and launch the app
#   make test       unit tests
#   make release    Release build, ad-hoc signed, zipped into dist/
#   make install    Release build copied to /Applications
# Run `make help` for the full list.

SHELL := /bin/bash
.DEFAULT_GOAL := help

PROJECT      := LibreScreen.xcodeproj
SCHEME       := LibreScreen
CONFIG       ?= Debug
DESTINATION  := platform=macOS,arch=arm64
# Build products must stay outside the repository (see CLAUDE.md), so use a stable DerivedData path.
DERIVED_DATA ?= $(HOME)/Library/Developer/Xcode/DerivedData/LibreScreen-make
APP          := $(DERIVED_DATA)/Build/Products/$(CONFIG)/LibreScreen.app
BIN          := $(APP)/Contents/MacOS/LibreScreen
VERSION      ?= $(shell sed -n 's/.*MARKETING_VERSION: "\(.*\)"/\1/p' project.yml | head -1)
DIST         := dist
ZIP          := $(DIST)/LibreScreen-$(VERSION).zip

export PATH := /opt/homebrew/bin:$(PATH)

XCODEBUILD := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DESTINATION)' -derivedDataPath "$(DERIVED_DATA)" CODE_SIGN_IDENTITY=-

.PHONY: help tools generate build run stop test lint format audit smoke snapshot release install clean distclean

help: ## Show this help
	@awk 'BEGIN {FS = ":.*## "} /^[a-zA-Z_-]+:.*## / {printf "  \033[1m%-12s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@echo
	@echo "  Variables: CONFIG=$(CONFIG)  VERSION=$(VERSION)  DERIVED_DATA=$(DERIVED_DATA)"

tools: ## Install xcodegen, swiftlint and swiftformat with Homebrew
	brew install xcodegen swiftlint swiftformat

generate: ## Regenerate LibreScreen.xcodeproj from project.yml
	xcodegen generate

$(PROJECT)/project.pbxproj: project.yml
	xcodegen generate

build: $(PROJECT)/project.pbxproj ## Build the app (CONFIG=Debug by default)
	$(XCODEBUILD) -configuration $(CONFIG) build | $(if $(shell command -v xcbeautify),xcbeautify,cat)
	@echo "Built $(APP)"

run: build ## Build and launch the app
	@pkill -x LibreScreen 2>/dev/null || true
	open "$(APP)"

stop: ## Quit a running LibreScreen
	@pkill -x LibreScreen 2>/dev/null && echo "LibreScreen stopped" || echo "LibreScreen is not running"

test: $(PROJECT)/project.pbxproj ## Run the unit tests
	$(XCODEBUILD) test | $(if $(shell command -v xcbeautify),xcbeautify,grep -E "Test run with|✘|error:|passed|failed")

lint: ## SwiftFormat (lint mode) + SwiftLint strict
	swiftformat --lint .
	swiftlint lint --strict --config .swiftlint.yml

format: ## Apply SwiftFormat
	swiftformat .

audit: ## Full code audit (lint, format, static analyzer, safety scans)
	.claude/skills/code-audit/scripts/audit.sh

smoke: build ## Headless pipeline check: 6 s recording with a synthetic webcam, then screenshots (Debug only)
	caffeinate -d -u -i "$(BIN)" -autorecord 6 -with-fake-camera
	caffeinate -d -u -i "$(BIN)" -autoscreenshot

snapshot: build ## Render every screen to PNG in $(DERIVED_DATA)/snapshots (Debug only)
	@mkdir -p "$(DERIVED_DATA)/snapshots"
	caffeinate -d -u -i "$(BIN)" -snapshot "$(DERIVED_DATA)/snapshots"
	@echo "Snapshots in $(DERIVED_DATA)/snapshots"; open "$(DERIVED_DATA)/snapshots"

release: $(PROJECT)/project.pbxproj ## Release build, ad-hoc signed, zipped into dist/ with a SHA-256
	$(XCODEBUILD) -configuration Release MARKETING_VERSION="$(VERSION)" build | $(if $(shell command -v xcbeautify),xcbeautify,cat)
	@mkdir -p $(DIST)
	@rm -f "$(ZIP)"
	ditto -c -k --keepParent "$(DERIVED_DATA)/Build/Products/Release/LibreScreen.app" "$(ZIP)"
	shasum -a 256 "$(ZIP)" | tee "$(ZIP).sha256"
	@echo "Release archive: $(ZIP)"
	@echo "The app is ad-hoc signed: first launch needs right-click › Open."

install: ## Release build copied to /Applications (replaces an existing copy)
	$(MAKE) release
	@pkill -x LibreScreen 2>/dev/null || true
	rm -rf /Applications/LibreScreen.app
	ditto "$(DERIVED_DATA)/Build/Products/Release/LibreScreen.app" /Applications/LibreScreen.app
	@echo "Installed /Applications/LibreScreen.app"

clean: ## Remove build products and release archives
	rm -rf "$(DERIVED_DATA)" $(DIST)

distclean: clean ## Also remove the generated Xcode project
	rm -rf $(PROJECT)
