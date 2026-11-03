# Builds build/swwm.app. Signing needs a stable identity so the Accessibility
# permission survives rebuilds. Pick it by team or directly:
#   make app SIGN_TEAM=<team id>
#   make app SIGN_IDENTITY=<SHA-1 or name from `security find-identity -v -p codesigning`>
APP := build/swwm.app
SIGN_IDENTITY ?= $(if $(SIGN_TEAM),$(shell scripts/sign-identity $(SIGN_TEAM)))

.PHONY: app run test clean

app:
	@test -n "$(SIGN_IDENTITY)" || { echo "set SIGN_TEAM or SIGN_IDENTITY (no identity found)"; exit 1; }
	swift build -c release
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS
	cp .build/release/swwm $(APP)/Contents/MacOS/swwm
	cp Resources/Info.plist $(APP)/Contents/Info.plist
	codesign --force --sign "$(SIGN_IDENTITY)" $(APP)

run: app
	open $(APP)

test:
	swift test

clean:
	rm -rf build .build
