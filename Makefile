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
	$(MAKE) icon
	@echo "Built $(APP_DIR) -- drag it into /Applications, or just double-click it."

# Builds AppIcon.icns from a pre-cropped 512x512 render of the default skin's
# face (Resources/AppIconFace.png, nearest-neighbor upscaled so it stays
# crisp/blocky) using macOS's own sips/iconutil -- no extra tooling required.
# Best-effort: skipped quietly if those tools (or the app bundle) aren't
# present, since the icon is cosmetic.
icon:
	@command -v sips >/dev/null 2>&1 && command -v iconutil >/dev/null 2>&1 && [ -d "$(APP_DIR)" ] || { echo "Skipping icon (sips/iconutil unavailable, or bundle missing)"; exit 0; }
	@rm -rf /tmp/boxbucko.iconset
	@mkdir -p /tmp/boxbucko.iconset
	@for size in 16 32 128 256 512; do \
		sips -z $$size $$size Resources/AppIconFace.png --out /tmp/boxbucko.iconset/icon_$${size}x$${size}.png >/dev/null; \
		double=$$((size * 2)); \
		sips -z $$double $$double Resources/AppIconFace.png --out /tmp/boxbucko.iconset/icon_$${size}x$${size}@2x.png >/dev/null; \
	done
	@iconutil -c icns /tmp/boxbucko.iconset -o "$(APP_DIR)/Contents/Resources/AppIcon.icns"
	@rm -rf /tmp/boxbucko.iconset

clean:
	rm -rf .build dist
