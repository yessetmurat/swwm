# swwm

A tiling window manager and bar for macOS, written in Swift. It replaces a
yabai + skhd + sketchybar setup with one app and one config file, and needs no
scripts.

- Dwindle tiling (as in Hyprland): a new window splits the focused one; the
  split follows the shape of the area.
- Virtual workspaces assigned to displays. Inactive workspaces' windows are
  moved off-screen, so SIP can stay enabled.
- Focus never jumps to another display when a window closes, minimizes or
  its app hides.
- Built-in hotkeys and mouse actions (no skhd).
- Built-in bar on every display: workspaces, focused app, clock, battery,
  volume, keyboard language. Fonts ship inside the app.
- One TOML config, applied on save.

## Requirements

- macOS 15 or later
- Accessibility permission
- An Apple Development certificate to sign the build (a stable signature
  keeps the Accessibility permission across rebuilds)

## Build and run

```sh
make app SIGN_TEAM=<team id>          # or SIGN_IDENTITY=<SHA-1 from `security find-identity -v -p codesigning`>
open build/swwm.app
```

On first launch, grant Accessibility in System Settings → Privacy & Security →
Accessibility; swwm starts managing windows as soon as it is granted. It adds
itself to the login items.

`make test` runs the unit tests.

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

## Moving from yabai, skhd and sketchybar

1. Stop and remove the old services:
   ```sh
   yabai --stop-service && yabai --uninstall-service
   skhd --stop-service && skhd --uninstall-service
   brew services stop sketchybar
   ```
   then `brew uninstall` them if you no longer need them.
2. System Settings → Control Center → "Automatically hide and show the menu
   bar": Always. The bar sits where the menu bar was; move the cursor to the
   top edge to reach the macOS menu.
3. Keep one native Space per display (remove the others in Mission Control);
   swwm's workspaces replace them.
4. SIP can be turned back on: swwm does not need the yabai scripting addition.
   A later optional module for removing window shadows will need it partly
   disabled.
