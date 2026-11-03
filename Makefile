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
	# Optional shadow module: an arm64e payload for Dock and its injector.
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

# Signed with Developer ID (hardened runtime, timestamp) and notarized. The
# notary profile is stored once with `xcrun notarytool store-credentials`.
#   make release VERSION=<x.y.z> SIGN_IDENTITY=<Developer ID Application identity> NOTARY_PROFILE=<name>
release:
	@test -n "$(VERSION)" -a -n "$(SIGN_IDENTITY)" -a -n "$(NOTARY_PROFILE)" || \
		{ echo "usage: make release VERSION=<x.y.z> SIGN_IDENTITY=<Developer ID Application identity> NOTARY_PROFILE=<name>"; exit 1; }
	@security find-identity -v -p codesigning | grep -F "$(SIGN_IDENTITY)" | grep -q "Developer ID Application" || \
		{ echo "SIGN_IDENTITY must be a Developer ID Application identity"; exit 1; }
	$(MAKE) dev SIGN_IDENTITY="$(SIGN_IDENTITY)" CODESIGN_FLAGS=--timestamp
	# Notarize only bin/swwm. The arm64e shadow binaries are not Gatekeeper-
	# launched (loaded into Dock / run by root launchd) and only work with SIP
	# partly disabled; putting them in the notary submission would risk failing
	# the whole thing and leaving swwm without a ticket.
	rm -f build/swwm-notarize.zip
	ditto -c -k --keepParent $(STAGE)/bin build/swwm-notarize.zip
	xcrun notarytool submit build/swwm-notarize.zip --keychain-profile "$(NOTARY_PROFILE)" --wait
	tar --uid 0 --gid 0 --uname root --gname wheel -czf build/swwm-$(VERSION).tar.gz -C $(STAGE) bin share
	shasum -a 256 build/swwm-$(VERSION).tar.gz

test:
	swift test

clean:
	rm -rf build .build
