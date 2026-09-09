APP_NAME = BoxBucko
BUNDLE_ID = com.boxbucko.app
BUILD_DIR = .build/release
APP_DIR = dist/$(APP_NAME).app

.PHONY: build run bundle clean

build:
	swift build -c release

# Runs directly via SwiftPM (fastest inner loop). The app will still show up
# in the menu bar; it just won't have a "real" .app identity (no custom icon,
# Launch-at-Login won't work) until you `make bundle`.
run:
	swift run

# Packages a proper double-clickable BoxBucko.app with Info.plist (LSUIElement,
# so it never shows a Dock icon) and the bundled default-skin resource.
bundle: build
	rm -rf "$(APP_DIR)"
	mkdir -p "$(APP_DIR)/Contents/MacOS"
	mkdir -p "$(APP_DIR)/Contents/Resources"
	cp "$(BUILD_DIR)/$(APP_NAME)" "$(APP_DIR)/Contents/MacOS/$(APP_NAME)"
	cp Resources/Info.plist "$(APP_DIR)/Contents/Info.plist"
	@bundle_res="$(BUILD_DIR)/$(APP_NAME)_$(APP_NAME).bundle"; \
	if [ -d "$$bundle_res" ]; then \
		cp -R "$$bundle_res" "$(APP_DIR)/Contents/Resources/"; \
	fi
	@echo "Built $(APP_DIR) -- drag it into /Applications, or just double-click it."

clean:
	rm -rf .build dist
