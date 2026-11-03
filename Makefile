# swwm is a plain binary: bin/swwm plus share/swwm/fonts (Homebrew's layout).
# Signing needs a stable identity so the Accessibility permission survives
# rebuilds. Pick it by team or directly:
#   make dev SIGN_TEAM=<team id>
#   make dev SIGN_IDENTITY=<SHA-1 or name from `security find-identity -v -p codesigning`>
SIGN_IDENTITY ?= $(if $(SIGN_TEAM),$(shell scripts/sign-identity $(SIGN_TEAM)))
STAGE := build/swwm
CODESIGN_FLAGS ?=

.PHONY: dev run stop release test clean

dev:
	@test -n "$(SIGN_IDENTITY)" || { echo "set SIGN_TEAM or SIGN_IDENTITY (no identity found)"; exit 1; }
	swift build -c release
	rm -rf $(STAGE)
	mkdir -p $(STAGE)/bin $(STAGE)/share/swwm/fonts
	cp .build/release/swwm $(STAGE)/bin/swwm
	cp Resources/Fonts/* $(STAGE)/share/swwm/fonts/
	# Optional Dock module: an arm64e payload for Dock and its injector.
	mkdir -p $(STAGE)/share/swwm/osax
	xcrun clang osax/payload.m -shared -fPIC -O2 -Wall -Wextra -fvisibility=hidden -arch arm64e \
		-mmacosx-version-min=15.0 -F/System/Library/PrivateFrameworks -framework SkyLight -framework Foundation \
		-o $(STAGE)/share/swwm/osax/payload
	xcrun clang osax/loader.m -O2 -Wall -arch arm64e -mmacosx-version-min=15.0 \
		-framework Cocoa -framework SystemConfiguration -o $(STAGE)/share/swwm/osax/loader
	cp osax/LICENSE.yabai $(STAGE)/share/swwm/osax/
	# Debug-map entries hold the build machine's absolute paths; strip before signing.
	strip -S $(STAGE)/bin/swwm
	codesign --force --options runtime $(CODESIGN_FLAGS) --identifier dev.swwm.swwm --sign "$(SIGN_IDENTITY)" $(STAGE)/bin/swwm
	codesign --force --options runtime $(CODESIGN_FLAGS) --sign "$(SIGN_IDENTITY)" $(STAGE)/share/swwm/osax/payload $(STAGE)/share/swwm/osax/loader

# Started by launchd, swwm is its own responsible process: the Accessibility
# permission is asked for swwm, not for the terminal.
run: dev stop
	launchctl submit -l dev.swwm -- $(CURDIR)/$(STAGE)/bin/swwm

stop:
	-@launchctl remove dev.swwm 2>/dev/null
	@sleep 1

# Signed with Developer ID (hardened runtime, timestamp), not notarized:
# Homebrew does not quarantine formula downloads, so Gatekeeper never checks.
#   make release VERSION=<x.y.z> SIGN_IDENTITY=<Developer ID Application identity>
release:
	@test -n "$(VERSION)" -a -n "$(SIGN_IDENTITY)" || \
		{ echo "usage: make release VERSION=<x.y.z> SIGN_IDENTITY=<Developer ID Application identity>"; exit 1; }
	@security find-identity -v -p codesigning | grep -F "$(SIGN_IDENTITY)" | grep -q "Developer ID Application" || \
		{ echo "SIGN_IDENTITY must be a Developer ID Application identity"; exit 1; }
	# The version lives only in the tag: link a copy of Info.plist stamped with
	# it (the path carries the version, so a new version always relinks).
	mkdir -p build
	plutil -replace CFBundleShortVersionString -string "$(VERSION)" -o build/Info-$(VERSION).plist Resources/Info.plist
	SWWM_INFO_PLIST=build/Info-$(VERSION).plist $(MAKE) dev SIGN_IDENTITY="$(SIGN_IDENTITY)" CODESIGN_FLAGS=--timestamp
	test "$$($(STAGE)/bin/swwm --version)" = "$(VERSION)"
	tar --uid 0 --gid 0 --uname root --gname wheel -czf build/swwm-$(VERSION).tar.gz -C $(STAGE) bin share
	shasum -a 256 build/swwm-$(VERSION).tar.gz

test:
	swift test

clean:
	rm -rf build .build
