# swwm

A tiling window manager and bar for macOS, written in Swift. One app and one
config file, no scripts.

- Dwindle tiling (as in Hyprland): a new window splits the focused one; the
  split follows the shape of the area. Windows that cannot take their tile's
  size (fixed-size dialogs, settings windows) float where they open.
- Virtual workspaces assigned to displays. Inactive workspaces' windows are
  moved off-screen, so SIP can stay enabled.
- Focus never jumps to another display when a window closes, minimizes or
  its app hides.
- Built-in hotkeys and mouse actions.
- Built-in bar on every display: workspaces, focused app, clock, battery,
  volume, keyboard language. Fonts ship inside the app.
- One TOML config, applied on save.

## Requirements

- macOS 15 or later, Apple Silicon
- Accessibility permission

## Install

```sh
brew tap <owner>/<tap>
brew install swwm
brew services start swwm
```

Then allow swwm in System Settings → Privacy & Security → Accessibility;
swwm starts managing windows as soon as it is granted. `brew services` starts
it at login and restarts it if it crashes; `swwm quit` (or `ctrl-alt-q`) stops
it until the next login or `brew services restart swwm`.

For the bar to sit where the menu bar is, set System Settings → Control Center
→ "Automatically hide and show the menu bar" to Always (move the cursor to the
top edge to reach the macOS menu). Keep one native Space per display (remove
the others in Mission Control); swwm's workspaces replace them.

## CLI

The same `swwm` binary is the command line: with arguments it talks to the
running swwm over a socket in the user's temporary directory.

```sh
swwm workspace q            # any command from the bindings: focus left, move-to-workspace 2, …
swwm reload                 # re-read the config
swwm quit
swwm query windows          # JSON; also: workspaces, monitors
swwm query windows | jq -r '.[] | select(.focused) | .app'
swwm --version              # the release version; "dev" for a local build
```

Exit codes: `0` ok, `1` rejected (for example an unknown workspace, or swwm
already running when started without arguments), `2` swwm is not running,
`64` usage error.

## Config

`~/.config/swwm/swwm.toml` is created on first launch with the defaults and
comments. Saved changes apply at once; a broken config shows an error and the
previous config stays active.

- `[settings]`: gaps, padding, bar height, focus follows mouse, mouse follows
  focus, mouse modifier.
- `[[monitor]]`: workspaces per display, matched by the display's model name,
  `"built-in"`, or `"*"` for any other display. Workspaces of a disconnected
  display move to the remaining one and come back on reconnect.
- `[bindings]`: `"keys" = "command"`.
- `[[rule]]`: per-app workspace and floating, matched by regex on app name and
  window title.
- `[bar]`: colors (`0xAARRGGBB`) and fonts (`"Family:Style:Size"`).

## Default hotkeys

| Keys | Action |
|------|--------|
| `alt-h/j/k/l` | focus window left/down/up/right |
| `shift-alt-h/j/k/l` | swap with the neighbor |
| `ctrl-alt-h/j/k/l` | warp (move the window and re-split) |
| `alt-s` / `alt-g` | focus the display on the left / right |
| `shift-alt-s` / `shift-alt-g` | move the window to the display on the left / right |
| `alt-1..4`, `alt-q/w/e/r` | show workspace |
| `shift-alt-1..4`, `shift-alt-q/w/e/r` | move the window to a workspace |
| `cmd-tab` / `cmd-shift-tab` | next / previous workspace of the focused display |
| `shift-alt-t` | toggle floating |
| `shift-alt-m` | toggle zoom |
| `shift-alt-b` | balance |
| `shift-alt-y` / `shift-alt-x` | mirror along the y / x axis |
| `alt-return`, `alt-b`, `alt-t`, `alt-d`, `alt-n` | open Ghostty, Firefox, Telegram, Discord, Finder |
| `ctrl-alt-r` | reload the config |
| `ctrl-alt-q` | quit (all windows come back on screen) |

Mouse: hold `alt` and drag with the left button to move a window (drop it on
another window to swap), with the right button to resize. Dragging by the
title bar or resizing by an edge works too.

## Dock module

Optional. macOS has no public way to remove another app's window shadow or to
keep a window above the active app's windows, so this uses a small payload
loaded into Dock. With it, floating windows stay above tiled ones. It is off by
default and swwm works fully without it.

Requirements (the installer checks them): SIP filesystem protections and
debugging restrictions disabled, and the `-arm64e_preview_abi` boot-arg. Check
the current state with `csrutil status` and `nvram boot-args`.

To set them up (needs a reboot into recoveryOS; do it once):

1. Shut the Mac down. Hold the power button until "Loading startup options"
   appears, click **Options**, then **Continue** to enter recoveryOS.
2. From the menu bar open **Utilities → Terminal** and run:

   ```sh
   csrutil enable --without fs --without debug --without nvram
   nvram boot-args=-arm64e_preview_abi
   ```

   `csrutil` only takes effect from recoveryOS, and clearing the nvram
   protection (`--without nvram`) is what lets the boot-arg be set.
3. Reboot into macOS (**Apple menu → Restart**).
4. Confirm: `csrutil status` shows filesystem protections and debugging
   restrictions as `disabled`, and `nvram boot-args` contains
   `-arm64e_preview_abi`.

This weakens part of SIP, so only do it if you want the Dock module; swwm
works fully without it. To undo later, boot into recoveryOS and run
`csrutil enable`, then `sudo nvram -d boot-args` from macOS.

```sh
sudo swwm --install-dock-module     # installs a root launchd daemon; re-run after upgrading swwm
sudo swwm --uninstall-dock-module
```

The daemon loads the payload into Dock at boot and after every Dock restart,
logging to `/Library/Logs/swwm-dock.log`. Set the policy in the config:

```toml
[settings]
window-shadow = "float"   # only floating windows keep a shadow (default)
# window-shadow = "off"   # no window has a shadow
# window-shadow = "on"    # swwm never touches shadows
```

The Dock payload and its injector are derived from yabai's scripting addition
(MIT, Copyright (c) 2019 Åsmund Vikane; see `osax/LICENSE.yabai`); the arm64e
injection path is based on work by Jeremy Legendre.

## Development

Needs Xcode and a code-signing certificate (an Apple Development one is
enough). A stable signature keeps the Accessibility permission across rebuilds.

```sh
make dev SIGN_TEAM=<team id>    # build/swwm/bin/swwm + share/swwm/fonts, signed
make run SIGN_TEAM=<team id>    # start it through launchd (stop a brew service first)
make stop
make test
```

`SIGN_IDENTITY=<SHA-1 or name>` works instead of `SIGN_TEAM`. `make run`
starts swwm through launchd, so the Accessibility permission belongs to swwm
and not to the terminal.

A development build and the Homebrew build are signed by different
certificates, so macOS treats them as different programs with the same name:
after switching from one to the other, the Accessibility switch looks on but
does not apply. Remove swwm from the list with the − button and allow it
again (`tccutil` cannot reset it: swwm is a plain binary, not an app bundle).

## Release

A Developer ID Application certificate must be in the keychain.

```sh
make release VERSION=<x.y.z> SIGN_IDENTITY="<Developer ID Application identity>"
```

This signs `bin/swwm` and the Dock module binaries (hardened runtime,
timestamp), writes `build/swwm-<x.y.z>.tar.gz` and prints its SHA-256. Nothing
is notarized: Homebrew does not quarantine formula downloads, so Gatekeeper
never checks swwm. A tarball downloaded by a browser is quarantined; clear it
with `xattr -dr com.apple.quarantine` before running. Upload the tarball to a
GitHub release `v<x.y.z>`, then update `url` and `sha256` in the tap's
`Formula/swwm.rb` (template: `packaging/homebrew/swwm.rb`).

## License

MIT, see `LICENSE`. The bundled IBM Plex fonts are under the SIL Open Font
License (`Resources/Fonts/OFL.txt`).
