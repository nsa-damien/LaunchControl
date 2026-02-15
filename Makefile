PROJECT ?= LaunchControl.xcodeproj
SCHEME ?= LaunchControl
CONFIG ?= Debug
DESTINATION ?= platform=macOS
DERIVED_DATA ?= tmp/DerivedData
BUILD_DIR ?= build
ARCHIVE_PATH ?= $(BUILD_DIR)/LaunchControl.xcarchive
ZIP_PATH ?= $(BUILD_DIR)/LaunchControl.zip
APP_PATH := $(DERIVED_DATA)/Build/Products/$(CONFIG)/LaunchControl.app
SIGNING_FLAGS ?= CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO

.PHONY: help build run build-run run-foreground test test-unit test-ui analyze clean archive package

help:
	@echo "LaunchControl Make targets:"
	@echo "  make build            Build the app (Debug by default)"
	@echo "  make run              Launch built app with open(1)"
	@echo "  make build-run        Build then launch app"
	@echo "  make run-foreground   Run app binary in current terminal"
	@echo "  make test             Run all tests"
	@echo "  make test-unit        Run unit tests only"
	@echo "  make test-ui          Run UI tests only"
	@echo "  make analyze          Run Xcode static analysis"
	@echo "  make archive          Create unsigned Release archive"
	@echo "  make package          Zip app from archive"
	@echo "  make clean            Clean build products and derived data"
	@echo ""
	@echo "Useful overrides:"
	@echo "  CONFIG=Release DERIVED_DATA=tmp/DerivedData"

build:
	xcodebuild -project "$(PROJECT)" \
		-scheme "$(SCHEME)" \
		-configuration "$(CONFIG)" \
		-destination "$(DESTINATION)" \
		-derivedDataPath "$(DERIVED_DATA)" \
		$(SIGNING_FLAGS) \
		build

run:
	@if [ ! -d "$(APP_PATH)" ]; then \
		echo "App not found at $(APP_PATH)"; \
		echo "Run 'make build' or 'make build-run' first."; \
		exit 1; \
	fi
	open "$(APP_PATH)"

build-run: build run

run-foreground:
	@if [ ! -x "$(APP_PATH)/Contents/MacOS/LaunchControl" ]; then \
		echo "App binary not found at $(APP_PATH)/Contents/MacOS/LaunchControl"; \
		echo "Run 'make build' first."; \
		exit 1; \
	fi
	"$(APP_PATH)/Contents/MacOS/LaunchControl"

test:
	xcodebuild -project "$(PROJECT)" \
		-scheme "$(SCHEME)" \
		-configuration "$(CONFIG)" \
		-destination "$(DESTINATION)" \
		-derivedDataPath "$(DERIVED_DATA)" \
		$(SIGNING_FLAGS) \
		test

test-unit:
	xcodebuild -project "$(PROJECT)" \
		-scheme "$(SCHEME)" \
		-configuration "$(CONFIG)" \
		-destination "$(DESTINATION)" \
		-derivedDataPath "$(DERIVED_DATA)" \
		-only-testing:LaunchControlTests \
		-skip-testing:LaunchControlUITests \
		$(SIGNING_FLAGS) \
		test

test-ui:
	xcodebuild -project "$(PROJECT)" \
		-scheme "$(SCHEME)" \
		-configuration "$(CONFIG)" \
		-destination "$(DESTINATION)" \
		-derivedDataPath "$(DERIVED_DATA)" \
		-only-testing:LaunchControlUITests \
		$(SIGNING_FLAGS) \
		test

analyze:
	xcodebuild -project "$(PROJECT)" \
		-scheme "$(SCHEME)" \
		-configuration "$(CONFIG)" \
		-destination "$(DESTINATION)" \
		-derivedDataPath "$(DERIVED_DATA)" \
		$(SIGNING_FLAGS) \
		analyze

archive:
	mkdir -p "$(BUILD_DIR)"
	xcodebuild -project "$(PROJECT)" \
		-scheme "$(SCHEME)" \
		-configuration Release \
		-destination "$(DESTINATION)" \
		-derivedDataPath "$(DERIVED_DATA)" \
		-archivePath "$(ARCHIVE_PATH)" \
		clean archive \
		CODE_SIGN_IDENTITY="-" \
		$(SIGNING_FLAGS)

package: archive
	mkdir -p "$(BUILD_DIR)"
	ditto -c -k --sequesterRsrc --keepParent \
		"$(ARCHIVE_PATH)/Products/Applications/LaunchControl.app" \
		"$(ZIP_PATH)"
	@echo "Created $(ZIP_PATH)"

clean:
	xcodebuild -project "$(PROJECT)" \
		-scheme "$(SCHEME)" \
		-configuration "$(CONFIG)" \
		-derivedDataPath "$(DERIVED_DATA)" \
		clean || true
	rm -rf "$(DERIVED_DATA)"
