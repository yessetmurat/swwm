//
//  DefaultConfig.swift
//  SwwmCore
//
//  Created by Yesset Murat on 03.11.2026.
//

extension Config {

    /// Written to ~/.config/swwm/swwm.toml on first launch.
    public static let defaultTOML = #"""
    # swwm config. Saved changes apply at once.

    [settings]
    gap = 8                    # between windows
    padding = 8                # between windows and display edges
    bar-height = 40            # reserved at the top of every display
    focus-follows-mouse = true # with autoraise
    mouse-follows-focus = true
    mouse-modifier = "alt"     # + left drag moves, + right drag resizes
    # Needs the optional shadow module (sudo swwm --install-shadows):
    # "float" - only floating windows keep a shadow, "off" - none, "on" - untouched.
    window-shadow = "float"

    # Workspaces per display. `match` is the display's model name as macOS
    # shows it, "built-in" for the laptop screen, or "*" for any other display.
    # Workspaces of a disconnected display move to the remaining one.
    [[monitor]]
    match = "built-in"
    workspaces = ["1", "2", "3", "4"]

    [[monitor]]
    match = "*"
    workspaces = ["q", "w", "e", "r"]

    [bindings]
    "alt-h" = "focus left"
    "alt-j" = "focus down"
    "alt-k" = "focus up"
    "alt-l" = "focus right"

    "shift-alt-h" = "swap left"
    "shift-alt-j" = "swap down"
    "shift-alt-k" = "swap up"
    "shift-alt-l" = "swap right"

    "ctrl-alt-h" = "warp left"
    "ctrl-alt-j" = "warp down"
    "ctrl-alt-k" = "warp up"
    "ctrl-alt-l" = "warp right"

    "alt-s" = "focus-monitor left"
    "alt-g" = "focus-monitor right"
    "shift-alt-s" = "move-to-monitor left"
    "shift-alt-g" = "move-to-monitor right"

    "alt-1" = "workspace 1"
    "alt-2" = "workspace 2"
    "alt-3" = "workspace 3"
    "alt-4" = "workspace 4"
    "alt-q" = "workspace q"
    "alt-w" = "workspace w"
    "alt-e" = "workspace e"
    "alt-r" = "workspace r"

    "shift-alt-1" = "move-to-workspace 1"
    "shift-alt-2" = "move-to-workspace 2"
    "shift-alt-3" = "move-to-workspace 3"
    "shift-alt-4" = "move-to-workspace 4"
    "shift-alt-q" = "move-to-workspace q"
    "shift-alt-w" = "move-to-workspace w"
    "shift-alt-e" = "move-to-workspace e"
    "shift-alt-r" = "move-to-workspace r"

    "cmd-tab" = "workspace-next"
    "cmd-shift-tab" = "workspace-prev"

    "shift-alt-t" = "toggle-float"
    "shift-alt-m" = "toggle-zoom"
    "shift-alt-b" = "balance"
    "shift-alt-y" = "mirror y"
    "shift-alt-x" = "mirror x"

    "alt-return" = "exec open -a Ghostty"
    "alt-b" = "exec open -a Firefox"
    "alt-t" = "exec open -a Telegram"
    "alt-d" = "exec open -a Discord"
    "alt-n" = "exec open -a Finder"

    "ctrl-alt-r" = "reload"
    "ctrl-alt-q" = "quit"

    # Bar on every display. Colors are 0xAARRGGBB; fonts "Family:Style:Size".
    [bar]
    background = "0x40000000"
    item-background = "0x33000000"
    foreground = "0xffffffff"
    workspace-font = "IBM Plex Mono:SemiBold:15"
    label-font = "IBM Plex Sans:SemiBold:14"

    # Rules for new windows: `app` and `title` are regular expressions.
    [[rule]]
    app = "^Ghostty$"
    workspace = "1"

    [[rule]]
    app = "^(Telegram|Discord)$"
    workspace = "2"

    # Windows that cannot take their tile's size float on their own; to float
    # anything else: [[rule]] app = "^App$" float = true
    """#
}
