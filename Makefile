# ─── Config ───────────────────────────────────────────────────────────────────
SHELL         := /bin/bash
DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer
export DEVELOPER_DIR
SCHEME        = open-receipt
PROJECT       = open-receipt.xcodeproj
SIM_NAME      = $(or $(device),iPhone 17 Pro)
SIMULATOR     = platform=iOS Simulator,name=$(SIM_NAME),OS=latest
BUILD_DESTINATION = generic/platform=iOS Simulator
CONFIGURATION = $(if $(filter 1,$(release)),Release,Debug)
DEVICE_HUB     = $(DEVELOPER_DIR)/../Applications/DeviceHub.app
BUNDLE_ID     = com.collinmurch.open-receipt
BUILD_DIR     = .build
ARCHIVE_PATH  = $(BUILD_DIR)/archive/$(SCHEME).xcarchive
EXPORT_PATH   = $(BUILD_DIR)/export
EXPORT_OPTIONS = AppStoreExportOptions.plist
AUTO_EXPORT_OPTIONS = $(BUILD_DIR)/AppStoreExportOptions-auto.plist
AUTO_BUILD_NUMBER = $(filter auto,$(build_number))
RECEIPTLAB_DERIVED = $(BUILD_DIR)/derived-receiptlab
RECEIPTLAB    = $(RECEIPTLAB_DERIVED)/Build/Products/Release/ReceiptLab.app/Contents/MacOS/ReceiptLab
ASSETS        = Assets
ICON          = App/open-receipt.icon
ICTOOL        = $(DEVELOPER_DIR)/../Applications/Icon Composer.app/Contents/Executables/ictool
ICON_RENDITIONS = Default Dark ClearLight ClearDark TintedLight TintedDark
ICON_EXPORTS  = $(foreach rendition,$(ICON_RENDITIONS),$(ASSETS)/Icons/open-receipt-iOS-$(rendition)-1024@1x.png)
SCREENSHOT_SIMULATOR = platform=iOS Simulator,name=iPhone 17 Pro Max,OS=latest
SCREENSHOT_CAPTURES  = $(ASSETS)/ScreenshotData
SCREENSHOT_RECEIPT   = $(ASSETS)/Receipts/example-receipt.json
SCREENSHOT_OUTPUT    = $(ASSETS)/Previews
BASE_SPEC     = project.yml
LOCAL_SPEC    = project.local.yml
CURRENT_TEAM  := $(shell if [ -f "$(PROJECT)/project.pbxproj" ]; then rg -o 'DEVELOPMENT_TEAM = [A-Z0-9]+' "$(PROJECT)/project.pbxproj" | head -1 | awk '{print $$3}'; elif [ -f "$(LOCAL_SPEC)" ]; then awk '/DEVELOPMENT_TEAM:/ {print $$2; exit}' "$(LOCAL_SPEC)"; fi)
RESOLVED_TEAM := $(strip $(if $(TEAM_ID),$(TEAM_ID),$(CURRENT_TEAM)))
TEAM_ID       ?=
ASC_KEY_ID    ?=
ASC_ISSUER_ID ?=
ASC_KEY_PATH  ?=
ASC_AUTH_FLAGS = $(if $(strip $(ASC_KEY_PATH)),-authenticationKeyPath "$(ASC_KEY_PATH)" -authenticationKeyID "$(ASC_KEY_ID)" -authenticationKeyIssuerID "$(ASC_ISSUER_ID)",)

.DEFAULT_GOAL := help
.PHONY: configuration
configuration:
	@if [ "$(CONFIGURATION)" = "Debug" ]; then \
		echo "Configuration: Debug. Receipt parsing uses sample data. PCC is disabled."; \
	else \
		echo "Configuration: Release. Receipt parsing uses live PCC."; \
	fi

.PHONY: release-configuration
release-configuration:
	@echo "Configuration: Release. Receipt parsing uses live PCC."

.PHONY: help
help: ## Show available commands
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-22s\033[0m %s\n", $$1, $$2}'

# ─── Project ──────────────────────────────────────────────────────────────────
.PHONY: gen
gen: ## Generate the Xcode project
	@team='$(RESOLVED_TEAM)'; \
	if [ -n "$$team" ] && { [ ! -f "$(LOCAL_SPEC)" ] || [ -n "$(TEAM_ID)" ]; }; then \
		printf "targets:\n  open-receipt:\n    settings:\n      base:\n        DEVELOPMENT_TEAM: %s\n" "$$team" > "$(LOCAL_SPEC)"; \
	fi; \
	if [ -f "$(LOCAL_SPEC)" ]; then \
		INCLUDE_LOCAL_SPEC=1 xcodegen generate --spec "$(BASE_SPEC)"; \
	else \
		xcodegen generate --spec "$(BASE_SPEC)"; \
	fi

# ─── Receipt evaluation ───────────────────────────────────────────────────────
# Flags: of=<name|name/n|path> format=text|json|summary quiet=1 cached=1
#        reasoning=light|moderate|deep max_pixels=<N>
#        filter=<regex> head=<N> tail=<N>
.PHONY: receipts
receipts: receiptlab ## Evaluate receipt fixtures with Private Cloud Compute
	@set -o pipefail; \
	arg='$(of)'; \
	root="Fixtures/Receipts"; \
	mkdir -p "$$root"; \
	if [ -z "$$arg" ]; then \
		target="$$root"; \
	elif [ -e "$$arg" ]; then \
		target="$$arg"; \
	elif [ -e "$$root/$$arg" ]; then \
		target="$$root/$$arg"; \
	else \
		folder="$${arg%/*}"; sample="$${arg##*/}"; \
		if [ "$$arg" != "$$folder" ] && [ -d "$$root/$$folder/fixtures" ]; then \
			matches=("$$root/$$folder/fixtures/$$sample".*); \
			if [ -f "$${matches[0]}" ] && [ "$${#matches[@]}" -eq 1 ]; then \
				target="$${matches[0]}"; \
			elif [ "$${#matches[@]}" -gt 1 ]; then \
				echo "More than one fixture matches: $$arg" >&2; exit 64; \
			else echo "Not found: $$arg" >&2; exit 64; fi; \
		else \
			echo "Not found: $$arg" >&2; exit 64; \
		fi; \
	fi; \
	echo "ReceiptLab -> $$target"; \
	flags="--cache $(BUILD_DIR)/receiptlab-cache"; \
	$(if $(format),flags="$$flags --format $(format)";) \
	$(if $(quiet),flags="$$flags --quiet";) \
	$(if $(cached),flags="$$flags --cached";) \
	$(if $(reasoning),flags="$$flags --reasoning $(reasoning)";) \
	$(if $(max_pixels),flags="$$flags --max-pixels $(max_pixels)";) \
	"$(RECEIPTLAB)" run "$$target" $$flags 2>&1 \
		$(if $(filter),| grep --line-buffered -E '$(filter)') \
		$(if $(head),| head -n $(head)) \
		$(if $(tail),| tail -n $(tail)); \
	exit $${PIPESTATUS[0]}

.PHONY: receiptlab
receiptlab: gen
	@xcodebuild build \
		-project $(PROJECT) \
		-scheme ReceiptLab \
		-destination 'platform=macOS' \
		-configuration Release \
		-derivedDataPath $(RECEIPTLAB_DERIVED) \
		-allowProvisioningUpdates \
		-allowProvisioningDeviceRegistration \
		CODE_SIGN_STYLE=Automatic \
		$(if $(RESOLVED_TEAM),DEVELOPMENT_TEAM=$(RESOLVED_TEAM),) \
		-quiet

# ─── App Store assets ────────────────────────────────────────────────────
# Flags: cached=1 reuses the last capture and only composes. of=reading|split|requests|breakdown|share|library limits both steps.
.PHONY: icons
icons: $(ICON_EXPORTS) ## Export the app icon renditions to Assets/Icons

$(ASSETS)/Icons/open-receipt-iOS-%-1024@1x.png: $(ICON)/icon.json $(wildcard $(ICON)/Assets/*)
	@mkdir -p "$(@D)"
	@"$(ICTOOL)" "$(ICON)" --export-image --output-file "$@" \
		--platform iOS --rendition $* --width 1024 --height 1024 --scale 1 >/dev/null
	@echo "Wrote $@"

.PHONY: previews
previews: $(if $(cached),,gen) ## Capture and compose App Store screenshots. cached=1 only composes.
	@set -o pipefail; \
	if [ -z "$(cached)" ]; then \
		$(if $(of),,rm -rf "$(SCREENSHOT_CAPTURES)";) \
		mkdir -p "$(SCREENSHOT_CAPTURES)"; \
		TEST_RUNNER_SCREENSHOTS_OUTPUT="$(abspath $(SCREENSHOT_CAPTURES))" \
		TEST_RUNNER_SCREENSHOTS_RECEIPT="$(abspath $(SCREENSHOT_RECEIPT))" \
		xcodebuild test \
			-project $(PROJECT) \
			-scheme Screenshots \
			-destination '$(SCREENSHOT_SIMULATOR)' \
			-derivedDataPath $(BUILD_DIR)/derived \
			$(if $(of),-only-testing:ScreenshotCapture/ScreenshotCapture/test$$(echo "$(of)" | awk '{print toupper(substr($$0,1,1)) substr($$0,2)}')) \
			2>&1 | xcbeautify || exit $$?; \
	elif [ ! -d "$(SCREENSHOT_CAPTURES)/light" ]; then \
		echo "No capture in $(SCREENSHOT_CAPTURES). Run make previews first." >&2; exit 66; \
	fi; \
	swift build -c release --product ScreenshotComposer && \
	.build/release/ScreenshotComposer \
		--captures "$(SCREENSHOT_CAPTURES)" \
		--assets "$(ASSETS)" \
		--output "$(SCREENSHOT_OUTPUT)" \
		$(if $(of),--only "$(of)")

# ─── Build / Test ─────────────────────────────────────────────────────────────
.PHONY: build
build: configuration gen ## Build the app. Set release=1 to use live PCC parsing.
	xcodebuild build \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-destination '$(BUILD_DESTINATION)' \
		-configuration $(CONFIGURATION) \
		-derivedDataPath $(BUILD_DIR)/derived \
		ARCHS=arm64 \
		ONLY_ACTIVE_ARCH=YES \
		2>&1 | xcbeautify; exit $${PIPESTATUS[0]}

.PHONY: test
test: gen ## Run tests. fast=1 uses SPM only.
	@if [ -n "$(fast)" ]; then \
		swift test; \
	else \
		xcodebuild test \
			-project $(PROJECT) \
			-scheme $(SCHEME) \
			-destination '$(SIMULATOR)' \
			-derivedDataPath $(BUILD_DIR)/derived \
			2>&1 | xcbeautify; exit $${PIPESTATUS[0]}; \
	fi

# ─── Simulator ────────────────────────────────────────────────────────────────
.PHONY: run
run: build ## Build and run on simulator
	@open "$(DEVICE_HUB)"
	@xcrun simctl boot "$(SIM_NAME)" 2>/dev/null || true
	@xcrun simctl bootstatus "$(SIM_NAME)" -b
	xcrun simctl install "$(SIM_NAME)" \
		$(BUILD_DIR)/derived/Build/Products/$(CONFIGURATION)-iphonesimulator/$(SCHEME).app
	xcrun simctl launch --console "$(SIM_NAME)" $(BUNDLE_ID)

# ─── Device ───────────────────────────────────────────────────────────────────
.PHONY: build-device
build-device: configuration gen ## Build for iOS hardware. Set release=1 to use live PCC parsing.
	xcodebuild build \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-destination 'generic/platform=iOS' \
		-configuration $(CONFIGURATION) \
		-derivedDataPath $(BUILD_DIR)/derived \
		-allowProvisioningUpdates \
		-allowProvisioningDeviceRegistration \
		CODE_SIGN_STYLE=Automatic \
		$(if $(TEAM_ID),DEVELOPMENT_TEAM=$(TEAM_ID),) \
		2>&1 | xcbeautify; exit $${PIPESTATUS[0]}

.PHONY: check-device
check-device: gen ## Compile for iOS hardware without signing or installing
	xcodebuild build \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-destination 'generic/platform=iOS' \
		-configuration Debug \
		-derivedDataPath $(BUILD_DIR)/derived-device-check \
		ARCHS=arm64 \
		CODE_SIGNING_ALLOWED=NO \
		2>&1 | xcbeautify; exit $${PIPESTATUS[0]}

.PHONY: archive
archive: release-configuration gen ## Create a signed Release archive. Set build_number=N, or build_number=auto on upload.
	@if [ ! -x "$(DEVELOPER_DIR)/usr/bin/xcodebuild" ]; then \
		echo "No Xcode toolchain was found at $(DEVELOPER_DIR)." >&2; \
		echo "Install the current Xcode release or set DEVELOPER_DIR to it." >&2; \
		exit 69; \
	fi
	@if [ -z "$(RESOLVED_TEAM)" ]; then \
		echo "No Apple Developer team is configured. Use TEAM_ID=YOUR_TEAM_ID." >&2; \
		exit 64; \
	fi
	@if [ -n "$(ASC_KEY_ID)$(ASC_ISSUER_ID)$(ASC_KEY_PATH)" ] \
		&& { [ -z "$(ASC_KEY_ID)" ] || [ -z "$(ASC_ISSUER_ID)" ] || [ -z "$(ASC_KEY_PATH)" ]; }; then \
		echo "ASC_KEY_ID, ASC_ISSUER_ID, and ASC_KEY_PATH must be set together." >&2; \
		exit 64; \
	fi
	xcodebuild archive \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-configuration Release \
		-destination 'generic/platform=iOS' \
		-archivePath $(ARCHIVE_PATH) \
		-derivedDataPath $(BUILD_DIR)/derived \
		-allowProvisioningUpdates \
		CODE_SIGN_STYLE=Automatic \
		DEVELOPMENT_TEAM=$(RESOLVED_TEAM) \
		$(if $(AUTO_BUILD_NUMBER),,$(if $(build_number),CURRENT_PROJECT_VERSION=$(build_number),)) \
		$(ASC_AUTH_FLAGS) \
		2>&1 | xcbeautify; exit $${PIPESTATUS[0]}

.PHONY: upload
upload: archive ## Archive and upload to App Store Connect. build_number=auto picks the next number.
	$(if $(AUTO_BUILD_NUMBER),@cp $(EXPORT_OPTIONS) $(AUTO_EXPORT_OPTIONS) && plutil -replace manageAppVersionAndBuildNumber -bool YES $(AUTO_EXPORT_OPTIONS),)
	xcodebuild -exportArchive \
		-archivePath $(ARCHIVE_PATH) \
		-exportPath $(EXPORT_PATH) \
		-exportOptionsPlist $(if $(AUTO_BUILD_NUMBER),$(AUTO_EXPORT_OPTIONS),$(EXPORT_OPTIONS)) \
		-allowProvisioningUpdates \
		$(ASC_AUTH_FLAGS) \
		2>&1 | xcbeautify; exit $${PIPESTATUS[0]}

.PHONY: run-device
run-device: build-device ## Build and run on iOS hardware. Set release=1 to use live PCC parsing.
	@UDID=$$(xcrun devicectl list devices 2>/dev/null \
		| grep -oEi '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}|[0-9a-f]{8}-[0-9a-f]{16}' \
		| head -1); \
	APP=$$(find $(BUILD_DIR)/derived -name "$(SCHEME).app" -not -path "*iphonesimulator*" -type d 2>/dev/null | head -1); \
	xcrun devicectl device install app --device $$UDID $$APP && \
	xcrun devicectl device process launch --device $$UDID $(BUNDLE_ID)

# ─── Format / Lint / Clean ────────────────────────────────────────────────────
.PHONY: format
format: ## Format Swift source files
	swift-format format --recursive --in-place Sources/ Tools/ Tests/ ToolTests/ App/

.PHONY: lint
lint: ## Lint Swift source files
	swift-format lint --recursive Sources/ Tools/ Tests/ ToolTests/ App/

.PHONY: clean
clean: ## Remove build artifacts
	swift package clean
	rm -rf $(BUILD_DIR)
